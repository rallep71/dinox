/*
 * DinoX MQTT Plugin
 *
 * Copyright (C) 2026 Ralf Peter <dinox@handwerker.jetzt>
 *
 * Two connection modes:
 *
 *   1. Per-Account MQTT  — each XMPP account can connect to its domain's
 *      MQTT broker (ejabberd mod_mqtt / Prosody mod_pubsub_mqtt).
 *      Enabled per account, uses XMPP credentials or explicit config.
 *
 *   2. Standalone MQTT   — a single connection to any MQTT broker,
 *      independent of XMPP accounts (Mosquitto, HiveMQ, HA, ...).
 *
 * Configuration:
 *
 *   Settings are stored in the DinoX database (settings table) and
 *   configurable via Preferences > MQTT.
 *
 *   Environment variable overrides (backward-compatible, for CI/Docker):
 *     DINOX_MQTT_HOST, DINOX_MQTT_PORT, DINOX_MQTT_TLS,
 *     DINOX_MQTT_USER, DINOX_MQTT_PASS, DINOX_MQTT_TOPICS,
 *     DINOX_MQTT_ACCOUNT
 *
 * Server Detection:
 *
 *   On XMPP connect, the plugin auto-detects ejabberd (mod_mqtt)
 *   or Prosody (mod_pubsub_mqtt) via XEP-0030 Service Discovery.
 *
 * Requires: libmosquitto-dev
 */

using Dino.Entities;
using Gee;
using Xmpp;

namespace Dino.Plugins.Mqtt {

public class Plugin : RootInterface, Object {

    public Dino.Application app;

    /* Per-account MQTT connections */
    private HashMap<string, MqttClient> account_clients =
        new HashMap<string, MqttClient>();  /* key = bare_jid string */

    /* Standalone MQTT connection (independent of accounts) */
    private MqttClient? standalone_client = null;

    /* Track connect-in-progress to prevent duplicate async calls */
    private HashSet<string> connecting_accounts = new HashSet<string>();
    private bool standalone_connecting = false;

    /* Mode flags */
    private bool mode_standalone = false;
    private bool mode_per_account = false;
    private bool mqtt_enabled = false;

    /* Config (from DB, with env-var override for backward compat) */
    private string? cfg_host = null;
    private int cfg_port = 1883;
    private bool cfg_tls = false;
    private string? cfg_user = null;
    private string? cfg_pass = null;
    private string[] cfg_topics = {};

    /* ── Phase 2: Bot-Conversation ─────────────────────────────────── */
    private MqttBotConversation? bot_conversation = null;
    private MqttCommandHandler? command_handler = null;

    /* ── Phase 3: Alerts & Notifications ────────────────────────────── */
    private MqttAlertManager? alert_manager = null;

    /* ── Phase 4: Bridge Manager ─────────────────────────────────── */
    private MqttBridgeManager? bridge_manager = null;

    /* ── DB keys (shared with MqttSettingsPage) ───────────────────── */

    internal const string KEY_ENABLED     = "mqtt_enabled";
    internal const string KEY_MODE        = "mqtt_mode";
    internal const string KEY_HOST        = "mqtt_host";
    internal const string KEY_PORT        = "mqtt_port";
    internal const string KEY_TLS         = "mqtt_tls";
    internal const string KEY_USER        = "mqtt_user";
    internal const string KEY_PASS        = "mqtt_pass";
    internal const string KEY_TOPICS      = "mqtt_topics";
    internal const string KEY_SERVER_TYPE = "mqtt_server_type";

    /* ── RootInterface ─────────────────────────────────────────────── */

    public void registered(Dino.Application app) {
        this.app = app;

        /* Load configuration: DB first, then env-var overrides */
        load_config();

        if (mqtt_enabled) {
            if (mode_standalone) {
                message("MQTT plugin: standalone mode — broker %s:%d (tls=%s)",
                        cfg_host, cfg_port, cfg_tls.to_string());
            } else if (mode_per_account) {
                message("MQTT plugin: per-account mode — will use each " +
                        "account's domain as MQTT broker");
            }
        } else {
            message("MQTT plugin: registered (disabled — enable in Preferences > MQTT)");
        }

        /* Initialize bot conversation manager, command handler, and alert manager */
        bot_conversation = new MqttBotConversation(this);
        command_handler = new MqttCommandHandler(this, bot_conversation);
        alert_manager = new MqttAlertManager(this);
        bridge_manager = new MqttBridgeManager(this);

        /* Register settings page */
        app.configure_preferences.connect(on_preferences_configure);

        /* Listen for XMPP connection state changes */
        app.stream_interactor.connection_manager.connection_state_changed.connect(
            on_xmpp_connection_state_changed);

        /* Intercept outgoing messages to the MQTT bot (prevent XMPP send) */
        app.stream_interactor.get_module<MessageProcessor>(
            MessageProcessor.IDENTITY).pre_message_send.connect(
                on_pre_message_send);
    }

    public void shutdown() {
        /* Remove bot conversations */
        if (bot_conversation != null) {
            bot_conversation.remove_all();
        }

        /* Disconnect standalone */
        if (standalone_client != null) {
            standalone_client.disconnect_sync();
            standalone_client = null;
        }

        /* Disconnect all per-account clients */
        foreach (var entry in account_clients.entries) {
            entry.value.disconnect_sync();
        }
        account_clients.clear();

        message("MQTT plugin: shutdown");
    }

    public void rekey_database(string new_key) throws Error {
        /* No database in this plugin — no-op */
    }

    public void checkpoint_database() {
        /* No database in this plugin — no-op */
    }

    /* ── Configuration ─────────────────────────────────────────────── */

    /**
     * Load config from DB settings, with environment variable overrides.
     * Env vars always win (for backward compat and CI/Docker).
     */
    private void load_config() {
        /* Read from DB first */
        mqtt_enabled = get_db_setting(KEY_ENABLED) == "1";

        string? db_mode = get_db_setting(KEY_MODE);
        cfg_host = get_db_setting(KEY_HOST);
        string? db_port = get_db_setting(KEY_PORT);
        if (db_port != null) cfg_port = int.parse(db_port);
        cfg_tls = get_db_setting(KEY_TLS) == "1";
        cfg_user = get_db_setting(KEY_USER);
        cfg_pass = get_db_setting(KEY_PASS);
        string? db_topics = get_db_setting(KEY_TOPICS);
        if (db_topics != null && db_topics != "") {
            cfg_topics = db_topics.split(",");
        }

        /* Determine mode from DB */
        if (db_mode == "per_account") {
            mode_per_account = true;
            mode_standalone = false;
        } else {
            mode_standalone = (cfg_host != null && cfg_host != "");
            mode_per_account = false;
        }

        /* Environment variable overrides (backward-compatible) */
        string? env_host = Environment.get_variable("DINOX_MQTT_HOST");
        if (env_host != null && env_host != "") {
            cfg_host = env_host;
            mode_standalone = true;
            mode_per_account = false;
            mqtt_enabled = true;  /* env var implies enabled */
            message("MQTT: env override — DINOX_MQTT_HOST=%s", env_host);
        }

        string? env_port = Environment.get_variable("DINOX_MQTT_PORT");
        if (env_port != null) cfg_port = int.parse(env_port);

        if (Environment.get_variable("DINOX_MQTT_TLS") == "1") cfg_tls = true;

        string? env_user = Environment.get_variable("DINOX_MQTT_USER");
        if (env_user != null) cfg_user = env_user;

        string? env_pass = Environment.get_variable("DINOX_MQTT_PASS");
        if (env_pass != null) cfg_pass = env_pass;

        string? env_topics = Environment.get_variable("DINOX_MQTT_TOPICS");
        if (env_topics != null) cfg_topics = env_topics.split(",");

        if (Environment.get_variable("DINOX_MQTT_ACCOUNT") == "1") {
            mode_per_account = true;
            mode_standalone = false;
            mqtt_enabled = true;
        }

        /* Standalone overrides per-account if both are set */
        if (mode_standalone && mode_per_account) {
            message("MQTT: Both standalone and per-account set — using standalone");
            mode_per_account = false;
        }
    }

    /**
     * Reload config from DB (called after settings page changes).
     */
    public void reload_config() {
        load_config();
        message("MQTT: Config reloaded — enabled=%s mode=%s host=%s port=%d",
                mqtt_enabled.to_string(),
                mode_standalone ? "standalone" : (mode_per_account ? "per_account" : "none"),
                cfg_host ?? "(none)", cfg_port);
    }

    private string? get_db_setting(string key) {
        var row_opt = app.db.settings.select({app.db.settings.value})
            .with(app.db.settings.key, "=", key)
            .single()
            .row();
        if (row_opt.is_present()) return row_opt[app.db.settings.value];
        return null;
    }

    /* ── Preferences UI ────────────────────────────────────────────── */

    private void on_preferences_configure(Object object) {
        Adw.PreferencesDialog? dialog = object as Adw.PreferencesDialog;
        if (dialog != null) {
            var page = new MqttSettingsPage(this);
            dialog.add(page);

            /* Match the main dialog breakpoint: hide title at narrow width */
            var bp = new Adw.Breakpoint(
                new Adw.BreakpointCondition.length(
                    Adw.BreakpointConditionLengthType.MAX_WIDTH, 600,
                    Adw.LengthUnit.PX));
            bp.apply.connect(() => { page.title = ""; });
            bp.unapply.connect(() => { page.title = "MQTT"; });
            dialog.add_breakpoint(bp);
        }
    }

    /* ── XMPP ↔ MQTT lifecycle ─────────────────────────────────────── */

    private void on_xmpp_connection_state_changed(Account account,
                                                  ConnectionManager.ConnectionState state) {
        string jid = account.bare_jid.to_string();

        if (state == ConnectionManager.ConnectionState.CONNECTED) {
            /* Only connect MQTT if enabled */
            if (!mqtt_enabled) return;

            /* Run server detection in background (non-blocking) */
            run_server_detection.begin(account);

            if (mode_standalone) {
                /* Standalone: connect once (first account triggers it) */
                if (standalone_client == null && !standalone_connecting) {
                    standalone_connecting = true;
                    start_standalone.begin((obj, res) => {
                        start_standalone.end(res);
                        standalone_connecting = false;
                    });
                }
            } else if (mode_per_account) {
                /* Per-account: connect MQTT for this specific account */
                if (!account_clients.has_key(jid) &&
                    !connecting_accounts.contains(jid)) {
                    connecting_accounts.add(jid);
                    start_per_account.begin(account, (obj, res) => {
                        start_per_account.end(res);
                        connecting_accounts.remove(jid);
                    });
                }
            }
        } else if (state == ConnectionManager.ConnectionState.DISCONNECTED) {
            if (mode_per_account) {
                /* Per-account: disconnect MQTT when XMPP goes offline */
                if (account_clients.has_key(jid)) {
                    message("MQTT: Account %s offline — disconnecting MQTT", jid);
                    account_clients[jid].disconnect_sync();
                    account_clients.unset(jid);
                }
            }
            /* Standalone mode: keep MQTT connected regardless */
        }
    }

    /* ── Server detection (async, background) ─────────────────────── */

    private async void run_server_detection(Account account) {
        /* Only run detection if no type is set yet */
        string? existing = get_db_setting(KEY_SERVER_TYPE);
        if (existing != null && existing != "" && existing != "unknown") {
            return;
        }

        message("MQTT: Running server type detection for %s…",
                account.bare_jid.to_string());

        DetectionResult result = yield ServerDetector.detect(
            app.stream_interactor, account);

        if (result.server_type != ServerType.UNKNOWN) {
            app.db.settings.upsert()
                .value(app.db.settings.key, KEY_SERVER_TYPE, true)
                .value(app.db.settings.value, result.server_type.to_string_key())
                .perform();
            message("MQTT: Server type saved: %s", result.server_type.to_label());

            /* Inject server-specific hints into bot conversation */
            if (bot_conversation != null) {
                Conversation? conv = bot_conversation.get_any_conversation();
                if (conv != null) {
                    if (result.server_type == ServerType.EJABBERD) {
                        /* ejabberd: shared XMPP/MQTT auth hint */
                        bot_conversation.inject_silent_message(conv,
                            "ℹ Server: ejabberd (mod_mqtt detected)\n\n" +
                            "ejabberd shares XMPP and MQTT authentication.\n" +
                            "You can use your XMPP credentials to connect\n" +
                            "to the MQTT broker on the same domain.\n\n" +
                            "Per-account mode uses these credentials automatically.");
                    } else if (result.server_type == ServerType.PROSODY) {
                        /* Prosody: security warning (no MQTT auth) */
                        bot_conversation.inject_bot_message(conv,
                            "⚠ Server: Prosody (mod_pubsub_mqtt detected)\n\n" +
                            "Prosody's MQTT bridge does NOT support authentication.\n" +
                            "Any client on the network can subscribe to topics.\n\n" +
                            "Recommendations:\n" +
                            "• Restrict MQTT port via firewall\n" +
                            "• Use TLS for encryption\n" +
                            "• Do not publish sensitive data\n\n" +
                            "Topic format: <HOST>/<TYPE>/<NODE>");
                    }
                }
            }
        }
    }

    /* ── Standalone connect ────────────────────────────────────────── */

    private async void start_standalone() {
        message("MQTT: Connecting standalone to %s:%d…", cfg_host, cfg_port);

        standalone_client = create_client("standalone");

        bool ok = yield standalone_client.connect_async(
            cfg_host, cfg_port, cfg_tls, cfg_user, cfg_pass);

        if (!ok) {
            warning("MQTT: Standalone connect failed (host=%s port=%d)",
                    cfg_host, cfg_port);
            standalone_client = null;
        }
    }

    /* ── Per-account connect ───────────────────────────────────────── */

    private async void start_per_account(Account account) {
        string jid = account.bare_jid.to_string();
        string host = account.domainpart;

        /* For ejabberd, XMPP credentials can be reused as MQTT login */
        string? user = account.bare_jid.to_string();
        string? pass = account.password;

        message("MQTT: Connecting per-account for %s → %s:%d…",
                jid, host, cfg_port);

        var client = create_client(jid);

        bool ok = yield client.connect_async(
            host, cfg_port, cfg_tls, user, pass);

        if (ok) {
            account_clients[jid] = client;
        } else {
            warning("MQTT: Per-account connect failed for %s (host=%s port=%d)",
                    jid, host, cfg_port);
            client.disconnect_sync();
        }
    }

    /* ── Client factory ────────────────────────────────────────────── */

    private MqttClient create_client(string label) {
        var client = new MqttClient();

        client.on_connection_changed.connect((connected) => {
            connection_changed(label, connected);
            if (connected) {
                message("MQTT [%s]: Connected — subscribing to %d topics",
                        label, cfg_topics.length);
                foreach (string topic in cfg_topics) {
                    string t = topic.strip();
                    if (t != "") {
                        /* Use per-topic QoS if configured */
                        int qos = 0;
                        if (alert_manager != null) {
                            qos = alert_manager.get_topic_qos(t);
                        }
                        client.subscribe(t, qos);
                    }
                }

                /* Phase 2: Create/activate bot conversation */
                if (bot_conversation != null) {
                    if (label == "standalone") {
                        var conv = bot_conversation.ensure_standalone_conversation();
                        if (conv != null) {
                            /* Register under "standalone" key */
                            bot_conversation.inject_bot_message(conv,
                                "MQTT Bot connected ✔\n\n" +
                                "Type /mqtt help for available commands.\n" +
                                "Subscribed MQTT messages will appear here.");
                        }
                    } else {
                        /* Per-account: label is the account JID */
                        var accounts = app.stream_interactor.get_accounts();
                        foreach (var acct in accounts) {
                            if (acct.bare_jid.to_string() == label) {
                                var conv = bot_conversation.ensure_conversation(acct);
                                if (conv != null) {
                                    bot_conversation.inject_bot_message(conv,
                                        "MQTT Bot connected for %s ✔\n\n".printf(label) +
                                        "Type /mqtt help for available commands.");
                                }
                                break;
                            }
                        }
                    }
                }
            }
        });

        client.on_message.connect((topic, payload) => {
            string payload_str = (string) payload;
            message_received(label, topic, payload_str);

            /* Phase 4: Evaluate bridge rules (MQTT → XMPP forwarding) */
            if (bridge_manager != null) {
                bridge_manager.evaluate(label, topic, payload_str);
            }

            /* Phase 3: Evaluate alert rules and determine priority */
            MqttPriority priority = MqttPriority.NORMAL;
            if (alert_manager != null) {
                var result = alert_manager.evaluate(topic, payload_str);
                priority = result.priority;

                /* If paused, still record history (done in evaluate)
                 * but don't display as chat bubble */
                if (alert_manager.paused && priority < MqttPriority.ALERT) {
                    return;
                }

                /* Log triggered alerts */
                if (result.triggered_rules.size > 0) {
                    message("MQTT [%s]: Alert triggered on %s (%d rules, priority=%s)",
                            label, topic, result.triggered_rules.size,
                            priority.to_string_key());
                }
            }

            /* Inject into bot conversation with priority */
            if (bot_conversation != null) {
                Conversation? conv = bot_conversation.get_conversation(label);
                if (conv == null) conv = bot_conversation.get_any_conversation();
                if (conv != null) {
                    bot_conversation.inject_mqtt_message(
                        conv, topic, payload_str, priority);
                }
            }
        });

        /* Phase 4: MQTT 5.0 User Properties display */
        client.on_message_properties.connect((topic, properties) => {
            if (bot_conversation != null && properties.size > 0) {
                Conversation? conv = bot_conversation.get_conversation(label);
                if (conv == null) conv = bot_conversation.get_any_conversation();
                if (conv != null) {
                    var sb = new StringBuilder();
                    sb.append("📋 Properties [%s]\n".printf(topic));
                    foreach (var entry in properties.entries) {
                        sb.append("  %s: %s\n".printf(entry.key, entry.value));
                    }
                    bot_conversation.inject_silent_message(conv, sb.str);
                }
            }
        });

        return client;
    }

    /* ── Phase 2: Command interception ─────────────────────────────── */

    /**
     * Intercept outgoing messages to the MQTT Bot.
     * If the message is a /mqtt command, handle it locally and
     * prevent it from being sent over XMPP.
     */
    private void on_pre_message_send(Entities.Message message,
                                     Xmpp.MessageStanza stanza,
                                     Conversation conversation) {
        if (bot_conversation == null) return;
        if (!bot_conversation.is_bot_conversation(conversation)) return;

        /* ALL messages to the bot are local — never send over XMPP */
        message.marked = Entities.Message.Marked.WONTSEND;

        string body = message.body ?? "";

        if (body.has_prefix("/mqtt")) {
            /* Process /mqtt command */
            Idle.add(() => {
                /* Mark as SENT so it looks like a normal sent message */
                message.marked = Entities.Message.Marked.SENT;
                command_handler.process(body, conversation);
                return false;
            });
        } else if (body.strip() != "") {
            /* Non-command text to the bot → show help hint */
            Idle.add(() => {
                message.marked = Entities.Message.Marked.SENT;
                bot_conversation.inject_bot_message(conversation,
                    "I only understand /mqtt commands.\n\n" +
                    "Type /mqtt help for available commands.");
                return false;
            });
        }
    }

    /* ── Public API ────────────────────────────────────────────────── */

    /**
     * Connect to an MQTT broker programmatically (standalone mode).
     * If host is null, the domain of the first XMPP account is used.
     */
    public async bool mqtt_connect(string? host = null, int port = 1883,
                                   bool use_tls = false,
                                   string? username = null,
                                   string? password = null) {
        if (standalone_client != null && standalone_client.is_connected) {
            warning("MQTT: Standalone already connected");
            return true;
        }

        string broker_host = host ?? "";
        if (broker_host == "") {
            var accounts = app.stream_interactor.get_accounts();
            if (accounts.size > 0) {
                broker_host = accounts.first().domainpart;
            } else {
                warning("MQTT: No host specified and no XMPP accounts available");
                return false;
            }
        }

        if (standalone_client == null) {
            standalone_client = create_client("standalone");
        }

        return yield standalone_client.connect_async(
            broker_host, port, use_tls, username, password);
    }

    /**
     * Subscribe to an MQTT topic on all active connections.
     */
    public void subscribe(string topic, int qos = 0) {
        bool any = false;

        if (standalone_client != null && standalone_client.is_connected) {
            standalone_client.subscribe(topic, qos);
            any = true;
        }

        foreach (var entry in account_clients.entries) {
            if (entry.value.is_connected) {
                entry.value.subscribe(topic, qos);
                any = true;
            }
        }

        if (!any) {
            warning("MQTT: Cannot subscribe — no active connections");
        }
    }

    /**
     * Publish a UTF-8 string to an MQTT topic.
     * If account_jid is null, publishes on the standalone connection.
     * If account_jid is given, publishes on that account's connection.
     */
    public void publish(string topic, string payload, int qos = 0,
                        bool retain = false, string? account_jid = null) {
        MqttClient? target = null;

        if (account_jid != null && account_clients.has_key(account_jid)) {
            target = account_clients[account_jid];
        } else if (standalone_client != null) {
            target = standalone_client;
        }

        if (target == null || !target.is_connected) {
            warning("MQTT: Cannot publish — no active connection%s",
                    account_jid != null ? " for " + account_jid : "");
            return;
        }

        target.publish_string(topic, payload, qos, retain);
    }

    /**
     * Disconnect all MQTT connections.
     */
    public async void mqtt_disconnect() {
        if (standalone_client != null) {
            yield standalone_client.disconnect_async();
            standalone_client = null;
        }
        foreach (var entry in account_clients.entries) {
            entry.value.disconnect_sync();
        }
        account_clients.clear();
    }

    /**
     * Get the MqttClient for a specific account (or null).
     */
    public MqttClient? get_client_for_account(string bare_jid) {
        return account_clients.has_key(bare_jid) ? account_clients[bare_jid] : null;
    }

    /**
     * Get the standalone MqttClient (or null).
     */
    public MqttClient? get_standalone_client() {
        return standalone_client;
    }

    /**
     * Get the alert manager (or null).
     */
    public MqttAlertManager? get_alert_manager() {
        return alert_manager;
    }

    /**
     * Get the bridge manager (or null).
     */
    public MqttBridgeManager? get_bridge_manager() {
        return bridge_manager;
    }

    /* ── Signals ───────────────────────────────────────────────────── */

    /**
     * Emitted when a message is received on a subscribed topic.
     * source = account JID (per-account) or "standalone".
     */
    public signal void message_received(string source, string topic,
                                         string payload);

    /**
     * Emitted when an MQTT connection state changes.
     * source = account JID (per-account) or "standalone".
     */
    public signal void connection_changed(string source, bool connected);
}

}
