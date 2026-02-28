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

extern const string GETTEXT_PACKAGE;
extern const string LOCALE_INSTALL_DIR;

namespace Dino.Plugins.Mqtt {

public class Plugin : RootInterface, Object {

    public Dino.Application app;

    /* ── Per-account MQTT connections + configs ────────────────────── */
    private HashMap<string, MqttClient> account_clients =
        new HashMap<string, MqttClient>();  /* key = bare_jid string */
    private HashMap<int, MqttConnectionConfig> account_configs =
        new HashMap<int, MqttConnectionConfig>();  /* key = account.id */

    /* ── MQTT Database (mqtt.db) ────────────────────────────────────── */
    public MqttDatabase? mqtt_db = null;

    /* ── Standalone MQTT connection + config ───────────────────────── */
    private MqttClient? standalone_client = null;
    private MqttConnectionConfig standalone_config = new MqttConnectionConfig();

    /* Track connect-in-progress to prevent duplicate async calls */
    private HashSet<string> connecting_accounts = new HashSet<string>();
    private bool standalone_connecting = false;

    /* ── Discovery managers (per connection) ────────────────────────── */
    private HashMap<string, MqttDiscoveryManager> discovery_managers =
        new HashMap<string, MqttDiscoveryManager>();

    /* Auto-purge timer (every 6 hours) */
    private uint purge_timer_id = 0;
    private const uint PURGE_INTERVAL_SECS = 6 * 3600;  /* 6 hours */

    /* ── Backward-compat: legacy global flags (read-only after migration) ── */
    private bool mqtt_enabled = false;
    private bool mode_standalone = false;
    private bool mode_per_account = false;

    /* Legacy cfg_* fields — kept for backward compat during migration,
     * new code should use standalone_config / account_configs instead. */
    private string? cfg_host = null;
    private int cfg_port = 1883;
    private bool cfg_tls = false;
    private string? cfg_user = null;
    private string? cfg_pass = null;
    private string[] cfg_topics = {};

    /* ── Sub-systems ──────────────────────────────────────────────── */
    public MqttBotConversation? bot_conversation = null;
    private MqttCommandHandler? command_handler = null;
    public MqttAlertManager? alert_manager = null;
    public MqttBridgeManager? bridge_manager = null;

    /* ── Legacy DB keys (for migration + backward compat) ─────────── */
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

        /* Set up gettext for translatable UI strings */
        if (app.search_path_generator != null) {
            internationalize(GETTEXT_PACKAGE,
                ((!)app.search_path_generator).get_locale_path(GETTEXT_PACKAGE, LOCALE_INSTALL_DIR));
        } else {
            internationalize(GETTEXT_PACKAGE, LOCALE_INSTALL_DIR);
        }

        /* Open (or create) the MQTT database (encrypted with app.db_key) */
        try {
            string mqtt_db_path = Path.build_filename(
                Application.get_storage_dir(), "mqtt.db");
            mqtt_db = new MqttDatabase(mqtt_db_path, app.db_key);
            message("MQTT plugin: database opened at %s", mqtt_db_path);

            /* Run initial purge to clean up expired data from last session */
            int purged = mqtt_db.purge_expired();
            if (purged > 0) {
                message("MQTT plugin: startup purge removed %d expired rows", purged);
            }

            /* Schedule periodic purge every 6 hours */
            purge_timer_id = Timeout.add_seconds(PURGE_INTERVAL_SECS, () => {
                if (mqtt_db != null) {
                    int n = mqtt_db.purge_expired();
                    if (n > 0) {
                        message("MQTT plugin: periodic purge removed %d rows", n);
                    }
                }
                return Source.CONTINUE;
            });
        } catch (Error e) {
            warning("MQTT plugin: failed to open mqtt.db: %s", e.message);
        }

        /* Run one-time migration from old global keys → new per-account/standalone keys */
        migrate_legacy_settings();

        /* Load configuration: standalone from DB, per-account on demand */
        load_standalone_config();
        load_legacy_config();  /* backward compat: also populates old cfg_* fields */

        if (standalone_config.enabled) {
            message("MQTT plugin: standalone mode — broker %s:%d (tls=%s)",
                    standalone_config.broker_host, standalone_config.broker_port,
                    standalone_config.tls.to_string());
        }

        /* Check if any account has MQTT enabled (will connect in state_changed) */
        bool any_account_enabled = false;
        var accounts = app.stream_interactor.get_accounts();
        foreach (var acct in accounts) {
            var acfg = load_account_config(acct);
            if (acfg.enabled) {
                any_account_enabled = true;
                message("MQTT plugin: per-account mode enabled for %s",
                        acct.bare_jid.to_string());
            }
        }

        if (!standalone_config.enabled && !any_account_enabled) {
            message("MQTT plugin: registered (disabled — enable in Preferences > MQTT)");
        }

        /* Keep legacy flags in sync for code that still uses them */
        mqtt_enabled = standalone_config.enabled || any_account_enabled;
        mode_standalone = standalone_config.enabled;
        mode_per_account = any_account_enabled;

        /* Initialize bot conversation manager, command handler, and alert manager */
        bot_conversation = new MqttBotConversation(this);
        command_handler = new MqttCommandHandler(this, bot_conversation);
        alert_manager = new MqttAlertManager(this);
        bridge_manager = new MqttBridgeManager(this);

        /* Register settings page */
        app.configure_preferences.connect(on_preferences_configure);

        /* Register account MQTT Bot manager signal */
        app.open_account_mqtt_manager.connect(on_open_account_mqtt_manager);

        /* Listen for XMPP connection state changes */
        app.stream_interactor.connection_manager.connection_state_changed.connect(
            on_xmpp_connection_state_changed);

        /* Intercept outgoing messages to the MQTT bot (prevent XMPP send) */
        app.stream_interactor.get_module<MessageProcessor>(
            MessageProcessor.IDENTITY).pre_message_send.connect(
                on_pre_message_send);
    }

    public void shutdown() {
        /* Stop periodic purge timer */
        if (purge_timer_id != 0) {
            Source.remove(purge_timer_id);
            purge_timer_id = 0;
        }

        /* Remove bot conversations */
        if (bot_conversation != null) {
            bot_conversation.remove_all();
        }

        /* Publish offline for all discovery-enabled connections */
        foreach (var entry in discovery_managers.entries) {
            var dm = entry.value;
            var label = entry.key;
            MqttClient? cl = null;
            if (label == "standalone") {
                cl = standalone_client;
            } else {
                cl = account_clients.has_key(label) ? account_clients[label] : null;
            }
            if (cl != null && cl.is_connected) {
                string avail_topic = dm.get_availability_topic();
                cl.publish_string(avail_topic, dm.get_lwt_payload(), 1, true);
            }
        }
        discovery_managers.clear();

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
        if (mqtt_db != null) {
            mqtt_db.rekey(new_key);
        }
    }

    public void checkpoint_database() {
        if (mqtt_db != null) {
            try {
                mqtt_db.exec("PRAGMA wal_checkpoint(TRUNCATE)");
            } catch (Error e) {
                warning("MQTT plugin: checkpoint failed: %s", e.message);
            }
        }
    }

    /* ── Configuration: per-account ────────────────────────────────── */

    /**
     * Load MQTT config for a specific account from account_settings table.
     * Also caches in account_configs HashMap.
     */
    public MqttConnectionConfig load_account_config(Account account) {
        var db = app.db;
        var cfg = new MqttConnectionConfig();

        cfg.enabled        = db.account_settings.get_value(account.id, AccountKey.ENABLED) == "1";
        cfg.bot_enabled    = db.account_settings.get_value(account.id, AccountKey.BOT_ENABLED) != "0"; /* default true */
        cfg.broker_host    = db.account_settings.get_value(account.id, AccountKey.BROKER_HOST) ?? "";
        string? port_s     = db.account_settings.get_value(account.id, AccountKey.BROKER_PORT);
        cfg.broker_port    = port_s != null ? int.parse(port_s) : 1883;
        cfg.tls            = db.account_settings.get_value(account.id, AccountKey.TLS) == "1";
        cfg.use_xmpp_auth  = db.account_settings.get_value(account.id, AccountKey.USE_XMPP_AUTH) != "0"; /* default true */
        cfg.username       = db.account_settings.get_value(account.id, AccountKey.USERNAME) ?? "";
        cfg.password       = db.account_settings.get_value(account.id, AccountKey.PASSWORD) ?? "";
        cfg.topics         = db.account_settings.get_value(account.id, AccountKey.TOPICS) ?? "";
        cfg.server_type    = db.account_settings.get_value(account.id, AccountKey.SERVER_TYPE) ?? "unknown";
        cfg.bot_name       = db.account_settings.get_value(account.id, AccountKey.BOT_NAME) ?? "MQTT Bot";
        cfg.alerts_json    = db.account_settings.get_value(account.id, AccountKey.ALERTS) ?? "[]";
        cfg.bridges_json   = db.account_settings.get_value(account.id, AccountKey.BRIDGES) ?? "[]";
        cfg.topic_qos_json = db.account_settings.get_value(account.id, AccountKey.TOPIC_QOS) ?? "{}";
        cfg.topic_priorities_json = db.account_settings.get_value(account.id, AccountKey.TOPIC_PRIORITIES) ?? "{}";
        cfg.publish_presets_json  = db.account_settings.get_value(account.id, AccountKey.PUBLISH_PRESETS) ?? "[]";
        cfg.freetext_enabled       = db.account_settings.get_value(account.id, AccountKey.FREETEXT_ENABLED) == "1";
        cfg.freetext_publish_topic = db.account_settings.get_value(account.id, AccountKey.FREETEXT_PUBLISH_TOPIC) ?? "";
        cfg.freetext_response_topic = db.account_settings.get_value(account.id, AccountKey.FREETEXT_RESPONSE_TOPIC) ?? "";
        string? fqos_s = db.account_settings.get_value(account.id, AccountKey.FREETEXT_QOS);
        cfg.freetext_qos   = fqos_s != null ? int.parse(fqos_s) : 1;
        cfg.freetext_retain = db.account_settings.get_value(account.id, AccountKey.FREETEXT_RETAIN) == "1";
        cfg.discovery_enabled = db.account_settings.get_value(account.id, AccountKey.DISCOVERY_ENABLED) == "1";
        cfg.discovery_prefix = db.account_settings.get_value(account.id, AccountKey.DISCOVERY_PREFIX) ?? "homeassistant";
        if (cfg.discovery_prefix == "") cfg.discovery_prefix = "homeassistant";

        account_configs[account.id] = cfg;
        return cfg;
    }

    /**
     * Save per-account MQTT config to account_settings table.
     */
    public void save_account_config(Account account, MqttConnectionConfig cfg) {
        var db = app.db;
        var t = db.account_settings;

        upsert_account(t, account.id, AccountKey.ENABLED,           cfg.enabled ? "1" : "0");
        upsert_account(t, account.id, AccountKey.BOT_ENABLED,       cfg.bot_enabled ? "1" : "0");
        upsert_account(t, account.id, AccountKey.BROKER_HOST,       cfg.broker_host);
        upsert_account(t, account.id, AccountKey.BROKER_PORT,       cfg.broker_port.to_string());
        upsert_account(t, account.id, AccountKey.TLS,               cfg.tls ? "1" : "0");
        upsert_account(t, account.id, AccountKey.USE_XMPP_AUTH,     cfg.use_xmpp_auth ? "1" : "0");
        upsert_account(t, account.id, AccountKey.USERNAME,          cfg.username);
        upsert_account(t, account.id, AccountKey.PASSWORD,          cfg.password);
        upsert_account(t, account.id, AccountKey.TOPICS,            cfg.topics);
        upsert_account(t, account.id, AccountKey.SERVER_TYPE,       cfg.server_type);
        upsert_account(t, account.id, AccountKey.BOT_NAME,          cfg.bot_name);
        upsert_account(t, account.id, AccountKey.ALERTS,            cfg.alerts_json);
        upsert_account(t, account.id, AccountKey.BRIDGES,           cfg.bridges_json);
        upsert_account(t, account.id, AccountKey.TOPIC_QOS,         cfg.topic_qos_json);
        upsert_account(t, account.id, AccountKey.TOPIC_PRIORITIES,  cfg.topic_priorities_json);
        upsert_account(t, account.id, AccountKey.PUBLISH_PRESETS,   cfg.publish_presets_json);
        upsert_account(t, account.id, AccountKey.FREETEXT_ENABLED,       cfg.freetext_enabled ? "1" : "0");
        upsert_account(t, account.id, AccountKey.FREETEXT_PUBLISH_TOPIC, cfg.freetext_publish_topic);
        upsert_account(t, account.id, AccountKey.FREETEXT_RESPONSE_TOPIC, cfg.freetext_response_topic);
        upsert_account(t, account.id, AccountKey.FREETEXT_QOS,           cfg.freetext_qos.to_string());
        upsert_account(t, account.id, AccountKey.FREETEXT_RETAIN,        cfg.freetext_retain ? "1" : "0");
        upsert_account(t, account.id, AccountKey.DISCOVERY_ENABLED,       cfg.discovery_enabled ? "1" : "0");
        upsert_account(t, account.id, AccountKey.DISCOVERY_PREFIX,        cfg.discovery_prefix);

        account_configs[account.id] = cfg;
    }

    private void upsert_account(Database.AccountSettingsTable t, int acct_id,
                                string key_name, string val) {
        t.upsert()
            .value(t.key, key_name, true)
            .value(t.account_id, acct_id, true)
            .value(t.value, val)
            .perform();
    }

    /**
     * Get cached account config, or load from DB.
     */
    public MqttConnectionConfig get_account_config(Account account) {
        if (account_configs.has_key(account.id)) {
            return account_configs[account.id];
        }
        return load_account_config(account);
    }

    /* ── Configuration: standalone ─────────────────────────────────── */

    /**
     * Load standalone config from global settings table (mqtt_sa_* keys).
     */
    public void load_standalone_config() {
        var cfg = standalone_config;
        cfg.enabled     = get_db_setting(StandaloneKey.ENABLED) == "1";
        cfg.broker_host = get_db_setting(StandaloneKey.BROKER_HOST) ?? "";
        string? port_s  = get_db_setting(StandaloneKey.BROKER_PORT);
        cfg.broker_port = port_s != null ? int.parse(port_s) : 1883;
        cfg.tls         = get_db_setting(StandaloneKey.TLS) == "1";
        cfg.username    = get_db_setting(StandaloneKey.USERNAME) ?? "";
        cfg.password    = get_db_setting(StandaloneKey.PASSWORD) ?? "";
        cfg.topics      = get_db_setting(StandaloneKey.TOPICS) ?? "";
        cfg.bot_enabled = get_db_setting(StandaloneKey.BOT_ENABLED) != "0";
        cfg.bot_name    = get_db_setting(StandaloneKey.BOT_NAME) ?? "MQTT Bot";
        cfg.alerts_json = get_db_setting(StandaloneKey.ALERTS) ?? "[]";
        cfg.bridges_json = get_db_setting(StandaloneKey.BRIDGES) ?? "[]";
        cfg.topic_qos_json = get_db_setting(StandaloneKey.TOPIC_QOS) ?? "{}";
        cfg.topic_priorities_json = get_db_setting(StandaloneKey.TOPIC_PRIORITIES) ?? "{}";
        cfg.publish_presets_json = get_db_setting(StandaloneKey.PUBLISH_PRESETS) ?? "[]";
        cfg.freetext_enabled       = get_db_setting(StandaloneKey.FREETEXT_ENABLED) == "1";
        cfg.freetext_publish_topic = get_db_setting(StandaloneKey.FREETEXT_PUBLISH_TOPIC) ?? "";
        cfg.freetext_response_topic = get_db_setting(StandaloneKey.FREETEXT_RESPONSE_TOPIC) ?? "";
        string? fqos_s = get_db_setting(StandaloneKey.FREETEXT_QOS);
        cfg.freetext_qos    = fqos_s != null ? int.parse(fqos_s) : 1;
        cfg.freetext_retain = get_db_setting(StandaloneKey.FREETEXT_RETAIN) == "1";
        cfg.discovery_enabled = get_db_setting(StandaloneKey.DISCOVERY_ENABLED) == "1";
        cfg.discovery_prefix = get_db_setting(StandaloneKey.DISCOVERY_PREFIX) ?? "homeassistant";
        if (cfg.discovery_prefix == "") cfg.discovery_prefix = "homeassistant";

        /* Also apply env-var overrides for standalone (backward compat, CI/Docker) */
        string? env_host = Environment.get_variable("DINOX_MQTT_HOST");
        if (env_host != null && env_host != "") {
            cfg.broker_host = env_host;
            cfg.enabled = true;
            message("MQTT: env override — DINOX_MQTT_HOST=%s", env_host);
        }
        string? env_port = Environment.get_variable("DINOX_MQTT_PORT");
        if (env_port != null) cfg.broker_port = int.parse(env_port);
        if (Environment.get_variable("DINOX_MQTT_TLS") == "1") cfg.tls = true;
        string? env_user = Environment.get_variable("DINOX_MQTT_USER");
        if (env_user != null) cfg.username = env_user;
        string? env_pass = Environment.get_variable("DINOX_MQTT_PASS");
        if (env_pass != null) cfg.password = env_pass;
        string? env_topics = Environment.get_variable("DINOX_MQTT_TOPICS");
        if (env_topics != null) cfg.topics = env_topics;
    }

    /**
     * Save standalone config to global settings table.
     */
    public void save_standalone_config() {
        save_db_setting(StandaloneKey.ENABLED,  standalone_config.enabled ? "1" : "0");
        save_db_setting(StandaloneKey.BROKER_HOST, standalone_config.broker_host);
        save_db_setting(StandaloneKey.BROKER_PORT, standalone_config.broker_port.to_string());
        save_db_setting(StandaloneKey.TLS,      standalone_config.tls ? "1" : "0");
        save_db_setting(StandaloneKey.USERNAME,  standalone_config.username);
        save_db_setting(StandaloneKey.PASSWORD,  standalone_config.password);
        save_db_setting(StandaloneKey.TOPICS,    standalone_config.topics);
        save_db_setting(StandaloneKey.BOT_ENABLED, standalone_config.bot_enabled ? "1" : "0");
        save_db_setting(StandaloneKey.BOT_NAME,  standalone_config.bot_name);
        save_db_setting(StandaloneKey.ALERTS,    standalone_config.alerts_json);
        save_db_setting(StandaloneKey.BRIDGES,   standalone_config.bridges_json);
        save_db_setting(StandaloneKey.TOPIC_QOS, standalone_config.topic_qos_json);
        save_db_setting(StandaloneKey.TOPIC_PRIORITIES, standalone_config.topic_priorities_json);
        save_db_setting(StandaloneKey.PUBLISH_PRESETS, standalone_config.publish_presets_json);
        save_db_setting(StandaloneKey.FREETEXT_ENABLED, standalone_config.freetext_enabled ? "1" : "0");
        save_db_setting(StandaloneKey.FREETEXT_PUBLISH_TOPIC, standalone_config.freetext_publish_topic);
        save_db_setting(StandaloneKey.FREETEXT_RESPONSE_TOPIC, standalone_config.freetext_response_topic);
        save_db_setting(StandaloneKey.FREETEXT_QOS, standalone_config.freetext_qos.to_string());
        save_db_setting(StandaloneKey.FREETEXT_RETAIN, standalone_config.freetext_retain ? "1" : "0");
        save_db_setting(StandaloneKey.DISCOVERY_ENABLED, standalone_config.discovery_enabled ? "1" : "0");
        save_db_setting(StandaloneKey.DISCOVERY_PREFIX, standalone_config.discovery_prefix);
    }

    /**
     * Get the standalone config (reference — changes are reflected).
     */
    public MqttConnectionConfig get_standalone_config() {
        return standalone_config;
    }

    /* ── Legacy config loader (backward compat) ───────────────────── */

    /**
     * Load old-style global config into legacy cfg_* fields.
     * This keeps existing code (command_handler, etc.) working
     * until they are migrated to use MqttConnectionConfig.
     */
    private void load_legacy_config() {
        /* Populate from standalone config */
        cfg_host = standalone_config.broker_host;
        cfg_port = standalone_config.broker_port;
        cfg_tls = standalone_config.tls;
        cfg_user = standalone_config.username;
        cfg_pass = standalone_config.password;
        cfg_topics = standalone_config.get_topic_list();
        mqtt_enabled = standalone_config.enabled;
        mode_standalone = standalone_config.enabled;

        /* Check if any account has MQTT enabled */
        var accounts = app.stream_interactor.get_accounts();
        foreach (var acct in accounts) {
            var acfg = get_account_config(acct);
            if (acfg.enabled) {
                mqtt_enabled = true;
                mode_per_account = true;
                break;
            }
        }
    }

    /**
     * Reload config from DB (called after settings page changes).
     * Backward-compatible wrapper.
     */
    public void reload_config() {
        load_standalone_config();
        load_legacy_config();
        message("MQTT: Config reloaded — standalone=%s per_account=%s",
                standalone_config.enabled.to_string(),
                mode_per_account.to_string());
    }

    /**
     * Apply settings changes immediately (called from settings page).
     *
     * Compares the new DB config with the running state and
     * connects, disconnects, or reconnects as needed.
     */
    public void apply_settings() {
        /* Snapshot old state */
        var old_sa = standalone_config.copy();
        bool was_enabled = mqtt_enabled;

        /* Reload from DB */
        reload_config();

        /* ── Standalone handling ─────────────────────────────────── */
        if (standalone_config.enabled) {
            bool conn_changed = old_sa.connection_differs(standalone_config) || !was_enabled;

            if (standalone_client != null && standalone_client.is_connected
                && !conn_changed) {
                /* Same connection params — just re-sync topics */
                sync_topics_to_client_cfg(standalone_client, standalone_config);
                return;
            }

            /* Need (re)connect */
            if (standalone_client != null) {
                standalone_client.disconnect_sync();
                standalone_client = null;
            }

            if (standalone_config.broker_host != "" && !standalone_connecting) {
                standalone_connecting = true;
                start_standalone.begin((obj, res) => {
                    start_standalone.end(res);
                    standalone_connecting = false;
                    connection_changed("standalone",
                        standalone_client != null && standalone_client.is_connected);
                });
            }
        } else {
            /* Standalone disabled → disconnect if running */
            if (standalone_client != null) {
                standalone_client.disconnect_sync();
                standalone_client = null;
                connection_changed("standalone", false);
            }
        }

        /* ── Per-account handling ────────────────────────────────── */
        var accounts = app.stream_interactor.get_accounts();
        foreach (var acct in accounts) {
            var acfg = get_account_config(acct);
            string jid = acct.bare_jid.to_string();
            var state = app.stream_interactor.connection_manager.get_state(acct);

            if (acfg.enabled && state == ConnectionManager.ConnectionState.CONNECTED) {
                if (!account_clients.has_key(jid) &&
                    !connecting_accounts.contains(jid)) {
                    connecting_accounts.add(jid);
                    start_per_account.begin(acct, (obj, res) => {
                        start_per_account.end(res);
                        connecting_accounts.remove(jid);
                    });
                } else if (account_clients.has_key(jid)) {
                    /* Already connected — re-sync topics */
                    sync_topics_to_client_cfg(account_clients[jid], acfg);
                }
            } else if (!acfg.enabled && account_clients.has_key(jid)) {
                /* Disabled → disconnect */
                account_clients[jid].disconnect_sync();
                account_clients.unset(jid);
                connection_changed(jid, false);
            }
        }

        /* If nothing is enabled, clean up bot conversations */
        if (!mqtt_enabled) {
            if (bot_conversation != null) {
                bot_conversation.remove_all();
            }
        }
    }

    /**
     * Sync topics from config to an active client — subscribe new, unsubscribe removed.
     */
    private void sync_topics_to_client_cfg(MqttClient client, MqttConnectionConfig cfg) {
        if (!client.is_connected) return;

        /* Build set of wanted topics from the config's topic string */
        var wanted = new Gee.HashSet<string>();
        foreach (string t in cfg.get_topic_list()) {
            string trimmed = t.strip();
            if (trimmed != "") wanted.add(trimmed);
        }

        /* Unsubscribe topics that are no longer wanted */
        var current = client.get_subscribed_topics();
        foreach (string t in current) {
            if (!wanted.contains(t)) {
                client.unsubscribe(t);
                message("MQTT: Unsubscribed removed topic '%s'", t);
            }
        }

        /* Subscribe new topics */
        foreach (string t in wanted) {
            if (!current.contains(t)) {
                int qos = 0;
                if (alert_manager != null) {
                    qos = alert_manager.get_topic_qos(t);
                }
                client.subscribe(t, qos);
            }
        }
    }

    private string? get_db_setting(string key) {
        var row_opt = app.db.settings.select({app.db.settings.value})
            .with(app.db.settings.key, "=", key)
            .single()
            .row();
        if (row_opt.is_present()) return row_opt[app.db.settings.value];
        return null;
    }

    private void save_db_setting(string key, string val) {
        app.db.settings.upsert()
            .value(app.db.settings.key, key, true)
            .value(app.db.settings.value, val)
            .perform();
    }

    /* ── Migration: old global keys → new standalone keys ──────────── */

    /**
     * One-time migration from old mqtt_* keys to new mqtt_sa_* keys.
     * Runs only once; a sentinel key (MigrationKey.MIGRATED) prevents re-run.
     */
    private void migrate_legacy_settings() {
        string? done = get_db_setting(MigrationKey.MIGRATED);
        if (done == "1") return;

        message("MQTT: Running one-time settings migration…");

        /* Map old → new keys */
        string[,] map = {
            { KEY_ENABLED,     StandaloneKey.ENABLED },
            { KEY_HOST,        StandaloneKey.BROKER_HOST },
            { KEY_PORT,        StandaloneKey.BROKER_PORT },
            { KEY_TLS,         StandaloneKey.TLS },
            { KEY_USER,        StandaloneKey.USERNAME },
            { KEY_PASS,        StandaloneKey.PASSWORD },
            { KEY_TOPICS,      StandaloneKey.TOPICS },
            { KEY_SERVER_TYPE, StandaloneKey.SERVER_TYPE }
        };

        for (int i = 0; i < map.length[0]; i++) {
            string old_key = map[i, 0];
            string new_key = map[i, 1];
            string? val = get_db_setting(old_key);
            if (val != null && val != "") {
                /* Only write if new key not already set */
                string? existing = get_db_setting(new_key);
                if (existing == null || existing == "") {
                    save_db_setting(new_key, val);
                    message("MQTT: Migrated %s → %s = '%s'", old_key, new_key, val);
                }
            }
        }

        /* Handle mode migration: if old mode was "per_account", the user had
         * per-account enabled → we don't need to set standalone flags for that.
         * Just mark migration done; per-account configs will be empty and
         * the user can configure them in the new UI. */
        string? old_mode = get_db_setting(KEY_MODE);
        if (old_mode == "per_account") {
            message("MQTT: Old mode was 'per_account' — no standalone migration needed");
            /* Don't enable standalone; user was in per-account mode */
            save_db_setting(StandaloneKey.ENABLED, "0");
        }

        save_db_setting(MigrationKey.MIGRATED, "1");
        message("MQTT: Migration complete");
    }

    /* ── Preferences UI ────────────────────────────────────────────── */

    private void on_preferences_configure(Object object) {
        Adw.PreferencesDialog? dialog = object as Adw.PreferencesDialog;
        if (dialog != null) {
            var page = new MqttStandaloneSettingsPage(this);
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

    /**
     * Handle the account MQTT manager signal — present the dialog.
     * Called from the Account Preferences Subpage when the user
     * clicks "Manage MQTT Bot".
     */
    private void on_open_account_mqtt_manager(Dino.Entities.Account account, Object window) {
        var dialog = new MqttBotManagerDialog(this, account);
        dialog.present((Gtk.Window) window);
    }

    /**
     * Check if a per-account MQTT client is currently connected.
     */
    public bool is_account_connected(string account_jid) {
        if (account_clients.has_key(account_jid)) {
            return account_clients[account_jid].is_connected;
        }
        return false;
    }

    /**
     * Apply a config change from the UI — connect/disconnect/reconnect as needed.
     * Called by MqttBotManagerDialog after saving config.
     */
    public void apply_account_config_change(Account account, MqttConnectionConfig cfg) {
        string acct_jid = account.bare_jid.to_string();

        if (!cfg.enabled) {
            /* Disabled — disconnect if connected */
            if (account_clients.has_key(acct_jid)) {
                account_clients[acct_jid].disconnect_sync();
                account_clients.unset(acct_jid);
                message("MQTT: Disabled per-account for %s (disconnected)", acct_jid);
            }
            /* Remove bot conversation */
            if (bot_conversation != null) {
                bot_conversation.remove_conversation(acct_jid);
            }
        } else {
            /* Enabled — trigger connection via XMPP state handler */
            var state = app.stream_interactor.connection_manager.get_state(account);
            if (state == ConnectionManager.ConnectionState.CONNECTED) {
                /* Already online — connect MQTT now */
                string jid = account.bare_jid.to_string();
                if (!account_clients.has_key(jid) &&
                    !connecting_accounts.contains(jid)) {
                    connecting_accounts.add(jid);
                    start_per_account.begin(account, (obj, res) => {
                        start_per_account.end(res);
                        connecting_accounts.remove(jid);
                    });
                }
            }
            /* Else: will auto-connect when XMPP comes online */
        }

        /* Update legacy flags */
        bool any_enabled = false;
        foreach (var entry in account_configs.entries) {
            if (entry.value.enabled) { any_enabled = true; break; }
        }
        mode_per_account = any_enabled;
        mqtt_enabled = standalone_config.enabled || any_enabled;
    }

    /* ── XMPP ↔ MQTT lifecycle ─────────────────────────────────────── */

    private void on_xmpp_connection_state_changed(Account account,
                                                  ConnectionManager.ConnectionState state) {
        string jid = account.bare_jid.to_string();

        if (state == ConnectionManager.ConnectionState.CONNECTED) {
            /* Run server detection in background (non-blocking) */
            run_server_detection.begin(account);

            /* Standalone: connect once (first XMPP account triggers it) */
            if (standalone_config.enabled) {
                if (standalone_client == null && !standalone_connecting) {
                    standalone_connecting = true;
                    start_standalone.begin((obj, res) => {
                        start_standalone.end(res);
                        standalone_connecting = false;
                    });
                }
            }

            /* Per-account: connect MQTT for this specific account if enabled */
            var acfg = get_account_config(account);
            if (acfg.enabled) {
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
            /* Per-account: disconnect MQTT when XMPP goes offline */
            if (account_clients.has_key(jid)) {
                message("MQTT: Account %s offline — disconnecting MQTT", jid);
                account_clients[jid].disconnect_sync();
                account_clients.unset(jid);
                connection_changed(jid, false);
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

            /* Also save detection result in the per-account config */
            var acfg = get_account_config(account);
            acfg.server_type = result.server_type.to_string_key();
            save_account_config(account, acfg);

            /* Inject server-specific hints into bot conversation */
            if (bot_conversation != null) {
                Conversation? conv = bot_conversation.get_any_conversation();
                if (conv != null) {
                    if (result.server_type == ServerType.EJABBERD) {
                        /* ejabberd: shared XMPP/MQTT auth hint */
                        bot_conversation.inject_silent_message(conv,
                            _("ℹ Server: ejabberd (mod_mqtt detected)\n\n" +
                            "ejabberd shares XMPP and MQTT authentication.\n" +
                            "You can use your XMPP credentials to connect\n" +
                            "to the MQTT broker on the same domain.\n\n" +
                            "Per-account mode uses these credentials automatically."));
                    } else if (result.server_type == ServerType.PROSODY) {
                        /* Prosody: security warning (no MQTT auth) */
                        bot_conversation.inject_bot_message(conv,
                            _("⚠ Server: Prosody (mod_pubsub_mqtt detected)\n\n" +
                            "Prosody's MQTT bridge does NOT support authentication.\n" +
                            "Any client on the network can subscribe to topics.\n\n" +
                            "Recommendations:\n" +
                            "• Restrict MQTT port via firewall\n" +
                            "• Use TLS for encryption\n" +
                            "• Do not publish sensitive data\n\n" +
                            "Topic format: <HOST>/<TYPE>/<NODE>"));
                    }

                    /* Opt-in hint: MQTT support found but not enabled */
                    if (!acfg.enabled) {
                        string server_label = result.server_type == ServerType.EJABBERD
                            ? "ejabberd" : "Prosody";
                        bot_conversation.inject_bot_message(conv,
                            _("💡 Your XMPP server (%s) supports MQTT!\n\n").printf(server_label) +
                            _("MQTT is not yet enabled for %s.\n").printf(account.bare_jid.to_string()) +
                            _("To enable it, go to:\n" +
                            "  Account Settings → MQTT Bot → Enable MQTT\n\n" +
                            "Or type: /mqtt help"));
                    }
                }
            }
        }
    }

    /* ── Standalone connect ────────────────────────────────────────── */

    private async void start_standalone() {
        var cfg = standalone_config;
        message("MQTT: Connecting standalone to %s:%d…", cfg.broker_host, cfg.broker_port);

        standalone_client = create_client("standalone", cfg);

        bool ok = yield standalone_client.connect_async(
            cfg.broker_host, cfg.broker_port, cfg.tls, cfg.username, cfg.password);

        if (!ok) {
            warning("MQTT: Standalone connect failed (host=%s port=%d)",
                    cfg.broker_host, cfg.broker_port);
            /* Record failed connection event */
            if (mqtt_db != null) {
                mqtt_db.record_connection_event("standalone", "error",
                    cfg.broker_host, cfg.broker_port,
                    "Connect failed (host=%s port=%d)".printf(
                        cfg.broker_host, cfg.broker_port));
            }
            standalone_client = null;
        }
    }

    /* ── Per-account connect ───────────────────────────────────────── */

    private async void start_per_account(Account account) {
        string jid = account.bare_jid.to_string();
        var acfg = get_account_config(account);

        /* Determine broker host and credentials */
        string host;
        string? user;
        string? pass;
        int port = acfg.broker_port;
        bool tls = acfg.tls;

        if (acfg.use_xmpp_auth || (acfg.broker_host == "")) {
            /* Use XMPP domain as broker, XMPP credentials for auth */
            host = account.domainpart;
            user = account.bare_jid.to_string();
            pass = account.password;
        } else {
            /* Explicit broker config */
            host = acfg.broker_host;
            user = acfg.username;
            pass = acfg.password;
        }

        message("MQTT: Connecting per-account for %s → %s:%d…", jid, host, port);

        var client = create_client(jid, acfg);

        bool ok = yield client.connect_async(host, port, tls, user, pass);

        if (ok) {
            account_clients[jid] = client;
        } else {
            warning("MQTT: Per-account connect failed for %s (host=%s port=%d)",
                    jid, host, port);
            /* Record failed connection event */
            if (mqtt_db != null) {
                mqtt_db.record_connection_event(jid, "error", host, port,
                    "Connect failed (host=%s port=%d)".printf(host, port));
            }
            client.disconnect_sync();
        }
    }

    /* ── Client factory ────────────────────────────────────────────── */

    private MqttClient create_client(string label, MqttConnectionConfig cfg) {
        var client = new MqttClient();

        /* Capture topic list from config at creation time */
        string[] topics_snapshot = cfg.get_topic_list();
        string cfg_host = cfg.broker_host;
        int cfg_port = cfg.broker_port;

        /* HA Discovery: set up LWT and DiscoveryManager if enabled */
        MqttDiscoveryManager? disc_mgr = null;
        if (cfg.discovery_enabled) {
            disc_mgr = new MqttDiscoveryManager(this, client, label, cfg.discovery_prefix);
            /* Set LWT before connect — broker publishes "offline" on unclean disconnect */
            client.set_will(disc_mgr.get_availability_topic(), disc_mgr.get_lwt_payload());
            discovery_managers[label] = disc_mgr;
        }

        /* Fix #6: Subscribe topics BEFORE connect — handle_connect() will
         * re-subscribe from subscribed_topics on every (re)connect.
         * This avoids double-subscribe on reconnect. */
        foreach (string topic in topics_snapshot) {
            string t = topic.strip();
            if (t != "") {
                int qos = 0;
                if (alert_manager != null) {
                    qos = alert_manager.get_topic_qos(t);
                }
                client.subscribe(t, qos);  /* pre-populates subscribed_topics map */
            }
        }
        /* Fix #3: Also subscribe freetext_response_topic if enabled */
        if (cfg.freetext_enabled) {
            string frt = cfg.freetext_response_topic.strip();
            if (frt != "") {
                client.subscribe(frt, 0);
            }
        }

        client.on_connection_changed.connect((connected) => {
            connection_changed(label, connected);

            /* Record connection event to DB */
            if (mqtt_db != null) {
                mqtt_db.record_connection_event(
                    label, connected ? "connected" : "disconnected",
                    cfg_host, cfg_port);
            }

            if (connected) {
                message("MQTT [%s]: Connected — %d topics pre-subscribed",
                        label, topics_snapshot.length);

                /* HA Discovery: publish birth + configs + states */
                var dm = discovery_managers.has_key(label) ?
                    discovery_managers[label] : null;
                if (dm != null) {
                    dm.publish_birth();
                    dm.publish_discovery_config();
                    dm.publish_all_states();
                    dm.subscribe_ha_status();
                }

                /* Phase 2: Create/activate bot conversation */
                if (bot_conversation != null) {
                    if (label == "standalone") {
                        var conv = bot_conversation.ensure_standalone_conversation();
                        if (conv != null) {
                            /* Register under "standalone" key */
                            bot_conversation.inject_bot_message(conv,
                                _("MQTT Bot connected ✔\n\n" +
                                "Type /mqtt help for available commands.\n" +
                                "Subscribed MQTT messages will appear here."));
                        }
                    } else {
                        /* Per-account: label is the account JID */
                        var accounts = app.stream_interactor.get_accounts();
                        foreach (var acct in accounts) {
                            if (acct.bare_jid.to_string() == label) {
                                var conv = bot_conversation.ensure_conversation(acct);
                                if (conv != null) {
                                    bot_conversation.inject_bot_message(conv,
                                        _("MQTT Bot connected for %s ✔\n\n").printf(label) +
                                        _("Type /mqtt help for available commands."));
                                }
                                break;
                            }
                        }
                    }
                }
            }
        });

        client.on_message.connect((topic, payload, qos, retained) => {
            string payload_str = (string) payload;
            message_received(label, topic, payload_str);

            /* HA Discovery: route HA status messages and command topics */
            var dm_msg = discovery_managers.has_key(label) ?
                discovery_managers[label] : null;
            if (dm_msg != null && topic == dm_msg.get_ha_status_topic()) {
                dm_msg.handle_ha_status_message(payload_str);
                return;
            }
            if (dm_msg != null && dm_msg.is_command_topic(topic)) {
                dm_msg.handle_command_message(topic, payload_str);
                return;
            }

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
                    /* Still record to DB even when paused */
                    if (mqtt_db != null) {
                        mqtt_db.record_message(label, topic, payload_str,
                                               qos, retained,
                                               priority.to_string_key());
                    }
                    return;
                }

                /* Log triggered alerts */
                if (result.triggered_rules.size > 0) {
                    message("MQTT [%s]: Alert triggered on %s (%d rules, priority=%s)",
                            label, topic, result.triggered_rules.size,
                            priority.to_string_key());
                }
            }

            /* Record message to DB */
            if (mqtt_db != null) {
                mqtt_db.record_message(label, topic, payload_str,
                                       qos, retained,
                                       priority.to_string_key());
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
     *
     * Supports freetext-publish: if the connection has freetext_enabled,
     * non-command messages are published to the configured topic.
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
            /* Non-command text: check freetext-publish mode */
            string? conn_key = bot_conversation.get_connection_key(conversation);
            MqttConnectionConfig? cfg = null;

            if (conn_key != null) {
                if (conn_key == MqttBotConversation.STANDALONE_KEY) {
                    cfg = standalone_config;
                } else {
                    var accounts = app.stream_interactor.get_accounts();
                    foreach (var acct in accounts) {
                        if (acct.bare_jid.to_string() == conn_key) {
                            cfg = get_account_config(acct);
                            break;
                        }
                    }
                }
            }

            if (cfg != null && cfg.freetext_enabled && cfg.freetext_publish_topic.strip() != "") {
                /* Freetext-publish: send to configured topic */
                string freetext_topic = cfg.freetext_publish_topic.strip();
                string? acct_jid = (conn_key != MqttBotConversation.STANDALONE_KEY) ? conn_key : null;
                int qos = cfg.freetext_qos;
                bool retain = cfg.freetext_retain;

                Idle.add(() => {
                    message.marked = Entities.Message.Marked.SENT;
                    publish(freetext_topic, body.strip(), qos, retain, acct_jid);

                    /* Record freetext exchange to DB */
                    if (mqtt_db != null) {
                        string cid = conn_key ?? "standalone";
                        mqtt_db.record_freetext(cid, "outgoing",
                            freetext_topic, body.strip(), qos, retain);
                    }

                    bot_conversation.inject_silent_message(conversation,
                        _("→ Published to: %s").printf(freetext_topic));
                    return false;
                });
            } else {
                Idle.add(() => {
                    message.marked = Entities.Message.Marked.SENT;
                    bot_conversation.inject_bot_message(conversation,
                        _("I only understand /mqtt commands.\n\n" +
                        "Type /mqtt help for available commands.\n" +
                        "To enable free-text publishing, configure it in\n" +
                        "Account Settings → MQTT Bot → Publish & Free Text."));
                    return false;
                });
            }
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
            /* Build a temporary config for this programmatic connect */
            var tmp_cfg = new MqttConnectionConfig();
            tmp_cfg.broker_host = broker_host;
            tmp_cfg.broker_port = port;
            tmp_cfg.tls = use_tls;
            tmp_cfg.topics = standalone_config.topics;
            standalone_client = create_client("standalone", tmp_cfg);
        }

        return yield standalone_client.connect_async(
            broker_host, port, use_tls, username, password);
    }

    /**
     * Subscribe to an MQTT topic.
     * If connection_key is null, subscribes on all active connections.
     * If connection_key is "standalone", subscribes only on standalone.
     * Otherwise subscribes on the specified account connection.
     */
    public void subscribe(string topic, int qos = 0, string? connection_key = null) {
        bool any = false;

        if (connection_key == null || connection_key == "standalone"
                || connection_key == MqttBotConversation.STANDALONE_KEY) {
            if (standalone_client != null && standalone_client.is_connected) {
                standalone_client.subscribe(topic, qos);
                any = true;
            }
        }

        if (connection_key == null) {
            foreach (var entry in account_clients.entries) {
                if (entry.value.is_connected) {
                    entry.value.subscribe(topic, qos);
                    any = true;
                }
            }
        } else if (connection_key != "standalone"
                && connection_key != MqttBotConversation.STANDALONE_KEY) {
            var client = account_clients.has_key(connection_key)
                ? account_clients[connection_key] : null;
            if (client != null && client.is_connected) {
                client.subscribe(topic, qos);
                any = true;
            }
        }

        if (!any) {
            warning("MQTT: Cannot subscribe — no active connections");
        }
    }

    /**
     * Unsubscribe from an MQTT topic.
     * If connection_key is null, unsubscribes on all connections.
     * Otherwise targets the specified connection.
     */
    public void unsubscribe(string topic, string? connection_key = null) {
        if (connection_key == null || connection_key == "standalone"
                || connection_key == MqttBotConversation.STANDALONE_KEY) {
            if (standalone_client != null && standalone_client.is_connected) {
                standalone_client.unsubscribe(topic);
            }
        }

        if (connection_key == null) {
            foreach (var entry in account_clients.entries) {
                if (entry.value.is_connected) {
                    entry.value.unsubscribe(topic);
                }
            }
        } else if (connection_key != "standalone"
                && connection_key != MqttBotConversation.STANDALONE_KEY) {
            var client = account_clients.has_key(connection_key)
                ? account_clients[connection_key] : null;
            if (client != null && client.is_connected) {
                client.unsubscribe(topic);
            }
        }

        /* Reload cfg_topics from DB so reconnect uses the updated list */
        reload_config();
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

        /* Record outgoing publish to DB */
        if (mqtt_db != null) {
            string conn_id = account_jid ?? "standalone";
            mqtt_db.record_publish(conn_id, topic, payload, qos, retain, "manual");
        }
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

    /**
     * Get the discovery manager for a given connection label (or null).
     */
    public MqttDiscoveryManager? get_discovery_manager(string label) {
        return discovery_managers.has_key(label) ? discovery_managers[label] : null;
    }

    /**
     * Get all discovery managers keyed by connection label.
     */
    public HashMap<string, MqttDiscoveryManager> get_discovery_managers() {
        return discovery_managers;
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
