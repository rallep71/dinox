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

    /* ── Retained message dedup cache ─────────────────────────────── */
    /* Key: "label\ttopic", Value: payload hash.
     * Prevents re-injecting the same retained message on every reconnect. */
    private HashMap<string, string> retained_cache =
        new HashMap<string, string>();

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

    /* ── Signal handler IDs (for proper cleanup) ──────────────────── */
    private ulong sig_pre_message_send = 0;
    private ulong sig_connection_state_changed = 0;
    private ulong sig_configure_preferences = 0;
    private ulong sig_open_mqtt_manager = 0;

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
                debug("MQTT plugin: startup purge removed %d expired rows", purged);
            }

            /* Schedule periodic purge every 6 hours */
            purge_timer_id = Timeout.add_seconds(PURGE_INTERVAL_SECS, () => {
                if (mqtt_db != null) {
                    int n = mqtt_db.purge_expired();
                    if (n > 0) {
                        debug("MQTT plugin: periodic purge removed %d rows", n);
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
        sig_configure_preferences = app.configure_preferences.connect(on_preferences_configure);

        /* Register account MQTT Bot manager signal */
        sig_open_mqtt_manager = app.open_account_mqtt_manager.connect(on_open_account_mqtt_manager);

        /* Listen for XMPP connection state changes (per-account MQTT lifecycle) */
        sig_connection_state_changed = app.stream_interactor.connection_manager.connection_state_changed.connect(
            on_xmpp_connection_state_changed);

        /* Intercept outgoing messages to the MQTT bot (prevent XMPP send) */
        sig_pre_message_send = app.stream_interactor.get_module<MessageProcessor>(
            MessageProcessor.IDENTITY).pre_message_send.connect(
                on_pre_message_send);

        /* ── Standalone auto-connect ──────────────────────────────
         * Standalone MQTT is independent of XMPP accounts.
         * Connect immediately at startup if enabled. */
        if (standalone_config.enabled && standalone_config.broker_host != "") {
            debug("[STANDALONE] Auto-connecting to %s:%d (independent of XMPP)",
                    standalone_config.broker_host, standalone_config.broker_port);
            standalone_connecting = true;
            start_standalone.begin((obj, res) => {
                start_standalone.end(res);
                standalone_connecting = false;
                /* Note: connection_changed is already emitted by the
                 * on_connection_changed handler wired in create_client().
                 * No explicit emit needed here. */
            });
        }
    }

    public void shutdown() {
        /* Disconnect signal handlers to prevent interference with
         * other plugins (video calls, file transfers) after disable.
         * Without this, handlers on pre_message_send and
         * connection_state_changed remain active permanently. */
        disconnect_signal_handlers();

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

    /**
     * Disconnect all signal handlers from core DinoX components.
     * This ensures the MQTT plugin doesn't interfere with other
     * subsystems (RTP video calls, file transfers, etc.) after being
     * disabled at runtime. Without this, leaked handlers can:
     * - Block the main loop on every outgoing message
     * - Trigger bridge flushes and server detection on XMPP reconnect
     * - Hold stale build_message_stanza handlers that scan every message
     */
    private void disconnect_signal_handlers() {
        if (sig_pre_message_send != 0) {
            var mp = app.stream_interactor.get_module<MessageProcessor>(
                MessageProcessor.IDENTITY);
            if (mp != null) mp.disconnect(sig_pre_message_send);
            sig_pre_message_send = 0;
        }
        if (sig_connection_state_changed != 0) {
            app.stream_interactor.connection_manager.disconnect(sig_connection_state_changed);
            sig_connection_state_changed = 0;
        }
        if (sig_configure_preferences != 0) {
            app.disconnect(sig_configure_preferences);
            sig_configure_preferences = 0;
        }
        if (sig_open_mqtt_manager != 0) {
            app.disconnect(sig_open_mqtt_manager);
            sig_open_mqtt_manager = 0;
        }
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
        int raw_port       = port_s != null ? int.parse(port_s) : 1883;
        cfg.broker_port    = (raw_port > 0 && raw_port <= 65535) ? raw_port : 1883;
        cfg.tls            = db.account_settings.get_value(account.id, AccountKey.TLS) == "1";
        cfg.use_xmpp_auth  = db.account_settings.get_value(account.id, AccountKey.USE_XMPP_AUTH) != "0"; /* default true */
        cfg.username       = db.account_settings.get_value(account.id, AccountKey.USERNAME) ?? "";
        cfg.password       = db.account_settings.get_value(account.id, AccountKey.PASSWORD) ?? "";
        cfg.topics         = db.account_settings.get_value(account.id, AccountKey.TOPICS) ?? "";
        cfg.server_type    = db.account_settings.get_value(account.id, AccountKey.SERVER_TYPE) ?? "unknown";
        cfg.bot_name       = db.account_settings.get_value(account.id, AccountKey.BOT_NAME) ?? "MQTT Bot";
        /* alerts_json and bridges_json are NOT loaded here — those are
         * managed exclusively by AlertManager / BridgeManager via mqtt.db. */
        cfg.topic_qos_json = db.account_settings.get_value(account.id, AccountKey.TOPIC_QOS) ?? "{}";
        cfg.topic_priorities_json = db.account_settings.get_value(account.id, AccountKey.TOPIC_PRIORITIES) ?? "{}";
        cfg.topic_aliases_json    = db.account_settings.get_value(account.id, AccountKey.TOPIC_ALIASES) ?? "{}";
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
        /* NOTE: alerts_json and bridges_json are NOT saved here.
         * AlertManager and BridgeManager own their data in mqtt.db. */
        upsert_account(t, account.id, AccountKey.TOPIC_QOS,         cfg.topic_qos_json);
        upsert_account(t, account.id, AccountKey.TOPIC_PRIORITIES,  cfg.topic_priorities_json);
        upsert_account(t, account.id, AccountKey.TOPIC_ALIASES,     cfg.topic_aliases_json);
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
        int raw_port    = port_s != null ? int.parse(port_s) : 1883;
        cfg.broker_port = (raw_port > 0 && raw_port <= 65535) ? raw_port : 1883;
        cfg.tls         = get_db_setting(StandaloneKey.TLS) == "1";
        cfg.username    = get_db_setting(StandaloneKey.USERNAME) ?? "";
        cfg.password    = get_db_setting(StandaloneKey.PASSWORD) ?? "";
        cfg.topics      = get_db_setting(StandaloneKey.TOPICS) ?? "";
        cfg.bot_enabled = get_db_setting(StandaloneKey.BOT_ENABLED) != "0";
        cfg.bot_name    = get_db_setting(StandaloneKey.BOT_NAME) ?? "MQTT Bot";
        /* alerts_json and bridges_json are NOT loaded here — those are
         * managed exclusively by AlertManager / BridgeManager via mqtt.db. */
        cfg.topic_qos_json = get_db_setting(StandaloneKey.TOPIC_QOS) ?? "{}";
        cfg.topic_priorities_json = get_db_setting(StandaloneKey.TOPIC_PRIORITIES) ?? "{}";
        cfg.topic_aliases_json    = get_db_setting(StandaloneKey.TOPIC_ALIASES) ?? "{}";
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
            debug("MQTT: env override — DINOX_MQTT_HOST=%s", env_host);
        }
        string? env_port = Environment.get_variable("DINOX_MQTT_PORT");
        if (env_port != null) {
            int p = int.parse(env_port);
            if (p > 0 && p <= 65535) cfg.broker_port = p;
        }
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
        /* NOTE: alerts_json and bridges_json are NOT saved here.
         * AlertManager and BridgeManager persist their own data to
         * mqtt.db tables (mqtt_alert_rules, mqtt_bridge_rules).
         * The StandaloneKey.ALERTS / BRIDGES keys in the settings table
         * are legacy dead fields — writing "[]" here would be misleading
         * and risk data loss if anyone later reads from these keys. */
        save_db_setting(StandaloneKey.TOPIC_QOS, standalone_config.topic_qos_json);
        save_db_setting(StandaloneKey.TOPIC_PRIORITIES, standalone_config.topic_priorities_json);
        save_db_setting(StandaloneKey.TOPIC_ALIASES, standalone_config.topic_aliases_json);
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
        debug("[MQTT] Config reloaded — standalone.enabled=%s per_account=%s",
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

        /* Reload from DB */
        reload_config();

        debug("[STANDALONE] apply_settings: enabled=%s client=%s | [ACCOUNTS] per_account=%s",
                standalone_config.enabled.to_string(),
                (standalone_client != null).to_string(),
                mode_per_account.to_string());

        /* ── Standalone handling (independent of per-account) ────── */
        if (standalone_config.enabled) {
            bool conn_changed = old_sa.connection_differs(standalone_config) || !old_sa.enabled;

            if (standalone_client != null && standalone_client.is_connected
                && !conn_changed) {
                /* Same connection params — just re-sync topics */
                debug("[STANDALONE] No connection change — syncing topics only");
                sync_topics_to_client_cfg(standalone_client, standalone_config, "standalone");
                /* HA Discovery: live enable/disable without reconnect */
                sync_discovery("standalone", standalone_client, standalone_config);
                /* NOTE: Do NOT return here! Per-account handling follows below
                 * and must not be skipped just because standalone didn't change. */
            } else {
                /* Need (re)connect */
                debug("[STANDALONE] Connection change detected → (re)connecting");
                if (standalone_client != null) {
                    standalone_client.disconnect_sync();
                    standalone_client = null;
                }

                if (standalone_config.broker_host != "" && !standalone_connecting) {
                    standalone_connecting = true;
                    start_standalone.begin((obj, res) => {
                        start_standalone.end(res);
                        standalone_connecting = false;
                        /* Note: connection_changed is already emitted by the
                         * on_connection_changed handler wired in create_client().
                         * No explicit emit needed here. */
                    });
                }
            }
        } else {
            /* Standalone disabled → disconnect if running */
            if (standalone_client != null) {
                debug("[STANDALONE] Disabled → disconnecting");
                /* Clean up discovery retained messages before disconnect —
                 * clean disconnect does NOT trigger LWT. */
                cleanup_discovery_before_disconnect("standalone", standalone_client);
                standalone_client.disconnect_sync();
                standalone_client = null;
                /* Note: disconnect_sync() already fires connection_changed
                 * via the on_connection_changed handler in create_client.
                 * No explicit signal emit needed here (BUG-6 fix). */
            }
            /* Remove the standalone bot conversation specifically.
             * The old code only removed bots when ALL MQTT was disabled
             * (!mqtt_enabled), but when per-account MQTT is still active
             * the standalone bot stayed visible after standalone was
             * toggled off. */
            if (bot_conversation != null) {
                bot_conversation.remove_conversation(
                    MqttBotConversation.STANDALONE_KEY);
            }
        }

        /* ── Per-account handling (independent of standalone) ────── */
        var accounts = app.stream_interactor.get_accounts();
        foreach (var acct in accounts) {
            var acfg = get_account_config(acct);
            string jid = acct.bare_jid.to_string();
            var state = app.stream_interactor.connection_manager.get_state(acct);

            if (acfg.enabled && state == ConnectionManager.ConnectionState.CONNECTED) {
                if (!account_clients.has_key(jid) &&
                    !connecting_accounts.contains(jid)) {
                    debug("[ACCT:%s] Enabled + XMPP online → connecting MQTT", jid);
                    connecting_accounts.add(jid);
                    start_per_account.begin(acct, (obj, res) => {
                        start_per_account.end(res);
                        connecting_accounts.remove(jid);
                    });
                } else if (account_clients.has_key(jid)) {
                    /* Already connected — re-sync topics */
                    sync_topics_to_client_cfg(account_clients[jid], acfg, jid);
                    /* HA Discovery: live enable/disable without reconnect */
                    sync_discovery(jid, account_clients[jid], acfg);
                }
            } else if (!acfg.enabled && account_clients.has_key(jid)) {
                /* Disabled → disconnect */
                debug("[ACCT:%s] Disabled → disconnecting MQTT", jid);
                /* Clean up discovery retained messages before disconnect */
                cleanup_discovery_before_disconnect(jid, account_clients[jid]);
                account_clients[jid].disconnect_sync();
                account_clients.unset(jid);
                /* Remove per-account bot conversation */
                if (bot_conversation != null) {
                    bot_conversation.remove_conversation(jid);
                }
                /* Note: disconnect_sync() already fires connection_changed
                 * via the on_connection_changed handler (BUG-6 fix). */
            }
        }

        /* Clean up bot conversations for modes that have no active connections.
         * Each mode manages its own bot conversation independently.
         * Only remove_all() if BOTH standalone and per-account are disabled. */
        if (!standalone_config.enabled && !mode_per_account) {
            debug("[MQTT] All modes disabled → removing all bot conversations");
            if (bot_conversation != null) {
                bot_conversation.remove_all();
            }
        }
    }

    /**
     * Ensure discovery state matches config for a live connection.
     * Creates DiscoveryManager + publishes configs if discovery is now enabled,
     * or removes retained messages + destroys manager if now disabled.
     *
     * Does NOT set LWT (requires pre-connect); LWT takes effect on next reconnect.
     * Safe to call repeatedly — only acts on state transitions.
     */
    private void sync_discovery(string label, MqttClient client, MqttConnectionConfig cfg) {
        bool is_xmpp_mode = cfg.use_xmpp_auth || cfg.broker_host.strip() == "";
        if (cfg.discovery_enabled && !is_xmpp_mode) {
            if (!discovery_managers.has_key(label)) {
                var dm = new MqttDiscoveryManager(this, client, label, cfg.discovery_prefix);
                discovery_managers[label] = dm;
                dm.publish_birth();
                dm.publish_discovery_config();
                dm.publish_all_states();
                dm.subscribe_ha_status();
                debug("[%s] HA Discovery started (live)", label);
            }
        } else {
            if (discovery_managers.has_key(label)) {
                discovery_managers[label].remove_discovery_configs();
                discovery_managers.unset(label);
                debug("[%s] HA Discovery stopped (live)", label);
            }
        }
    }

    /**
     * Publish offline availability and remove discovery configs for a label.
     * Must be called BEFORE disconnect_sync() — clean disconnect does NOT
     * trigger the LWT, so retained "online" would persist on the broker.
     */
    private void cleanup_discovery_before_disconnect(string label, MqttClient? client) {
        if (discovery_managers.has_key(label) && client != null && client.is_connected) {
            var dm = discovery_managers[label];
            client.publish_string(dm.get_availability_topic(), dm.get_lwt_payload(), 1, true);
            dm.remove_discovery_configs();
            discovery_managers.unset(label);
            debug("[%s] HA Discovery cleaned up before disconnect", label);
        }
    }

    /**
     * Sync topics from config to a client — subscribe new, unsubscribe removed.
     * Works even when the client is temporarily disconnected: subscribe()
     * and unsubscribe() always update the subscribed_topics map, which is
     * replayed on reconnect by handle_connect().  Without this, a topic
     * deletion saved while the connection is briefly down would be lost.
     */
    private void sync_topics_to_client_cfg(MqttClient client, MqttConnectionConfig cfg, string label) {
        /* Build set of wanted topics from the config's topic string */
        var wanted = new Gee.HashSet<string>();
        foreach (string t in cfg.get_topic_list()) {
            string trimmed = t.strip();
            if (trimmed != "") wanted.add(trimmed);
        }

        /* Preserve freetext response topic — subscribed separately by create_client */
        if (cfg.freetext_enabled) {
            string frt = cfg.freetext_response_topic.strip();
            if (frt != "") wanted.add(frt);
        }

        /* Preserve HA Discovery system topics (status + command topics) */
        foreach (var entry in discovery_managers.entries) {
            wanted.add_all(entry.value.get_system_topics());
        }

        /* Preserve bridge rule topics — ensure forwarding survives reconnect.
         * BUG-FIX: Bridge rules were never auto-subscribed, so messages
         * on bridge-only topics were silently lost after reconnect.
         * Only include rules belonging to THIS client (scoped by label). */
        if (bridge_manager != null) {
            foreach (var rule in bridge_manager.get_rules_for_client(label)) {
                if (rule.enabled && rule.topic.strip() != "") {
                    wanted.add(rule.topic.strip());
                }
            }
        }

        /* Unsubscribe topics that are no longer wanted.
         * Collect first, then unsubscribe — avoids modifying the set during iteration. */
        var current = client.get_subscribed_topics();
        var to_remove = new Gee.ArrayList<string>();
        foreach (string t in current) {
            if (!wanted.contains(t)) {
                to_remove.add(t);
            }
        }
        foreach (string t in to_remove) {
            client.unsubscribe(t);
            debug("MQTT: Unsubscribed removed topic '%s'", t);
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

    /**
     * Immediately subscribe a bridge topic on the correct MQTT client.
     * Called from dialog when a new bridge rule is added, so that
     * forwarding works immediately without requiring Save & Apply.
     *
     * @param topic        The MQTT topic to subscribe
     * @param client_label "standalone" or account bare JID
     */
    public void subscribe_bridge_topic(string topic, string client_label) {
        string t = topic.strip();
        if (t == "") return;

        if (client_label == "standalone") {
            if (standalone_client != null && standalone_client.is_connected) {
                standalone_client.subscribe(t, 0);
            }
        } else {
            if (account_clients.has_key(client_label)) {
                var client = account_clients[client_label];
                if (client.is_connected) {
                    client.subscribe(t, 0);
                }
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
                    bool is_secret = (old_key == KEY_PASS || old_key == KEY_USER);
                    debug("MQTT: Migrated %s → %s = '%s'", old_key, new_key,
                            is_secret ? "***" : val);
                }
            }
        }

        /* Handle mode migration: if old mode was "per_account", the user had
         * per-account enabled → we don't need to set standalone flags for that.
         * Just mark migration done; per-account configs will be empty and
         * the user can configure them in the new UI. */
        string? old_mode = get_db_setting(KEY_MODE);
        if (old_mode == "per_account") {
            debug("MQTT: Old mode was 'per_account' — no standalone migration needed");
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
     * Check if the standalone MQTT client is currently connected.
     */
    public bool is_standalone_connected() {
        return standalone_client != null && standalone_client.is_connected;
    }

    /**
     * Force a full disconnect → reconnect cycle for a per-account client.
     * Used by the Reconnect button in the dialog.
     */
    public void force_reconnect_account(Account account) {
        string jid = account.bare_jid.to_string();
        var acfg = get_account_config(account);

        if (!acfg.enabled) {
            debug("[ACCT:%s] Reconnect ignored — MQTT disabled", jid);
            return;
        }

        /* Tear down existing client */
        if (account_clients.has_key(jid)) {
            debug("[ACCT:%s] Reconnect → disconnecting…", jid);
            account_clients[jid].disconnect_sync();
            account_clients.unset(jid);
        }

        /* Reset connecting flag — a previous start_per_account may not have
         * completed its async callback yet. */
        connecting_accounts.remove(jid);

        /* Re-connect */
        var state = app.stream_interactor.connection_manager.get_state(account);
        if (state == ConnectionManager.ConnectionState.CONNECTED) {
            debug("[ACCT:%s] Reconnect → connecting…", jid);
            connecting_accounts.add(jid);
            start_per_account.begin(account, (obj, res) => {
                start_per_account.end(res);
                connecting_accounts.remove(jid);
            });
        } else {
            debug("[ACCT:%s] Reconnect → XMPP not connected, will auto-connect later", jid);
        }
    }

    /**
     * Force a full disconnect → reconnect cycle for the standalone client.
     * Used by the Reconnect button in the dialog.
     */
    public void force_reconnect_standalone() {
        if (!standalone_config.enabled) {
            debug("[STANDALONE] Reconnect ignored — disabled");
            return;
        }

        /* Tear down existing client */
        if (standalone_client != null) {
            debug("[STANDALONE] Reconnect → disconnecting…");
            standalone_client.disconnect_sync();
            standalone_client = null;
        }

        /* Reset connecting flag — a previous start_standalone may not have
         * completed its async callback yet (the Idle.add for standalone_connecting=false
         * runs in a later main loop iteration).  Without this reset,
         * the reconnect is silently skipped. */
        standalone_connecting = false;

        /* Re-connect */
        if (standalone_config.broker_host != "") {
            debug("[STANDALONE] Reconnect → connecting to %s:%d…",
                    standalone_config.broker_host, standalone_config.broker_port);
            standalone_connecting = true;
            start_standalone.begin((obj, res) => {
                start_standalone.end(res);
                standalone_connecting = false;
            });
        } else {
            debug("[STANDALONE] Reconnect failed — no broker host configured");
            connection_changed("standalone", false);
        }
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
                /* Clean up discovery retained messages before disconnect */
                cleanup_discovery_before_disconnect(acct_jid, account_clients[acct_jid]);
                account_clients[acct_jid].disconnect_sync();
                account_clients.unset(acct_jid);
                debug("[ACCT:%s] Disabled → disconnected", acct_jid);
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
                if (account_clients.has_key(jid)) {
                    /* Already connected — re-sync topics (subscribe new, unsubscribe removed) */
                    sync_topics_to_client_cfg(account_clients[jid], cfg, jid);

                    /* HA Discovery: live start/stop without requiring reconnect */
                    sync_discovery(jid, account_clients[jid], cfg);

                    /* Notify UI — no connect/disconnect happened so no signal would fire,
                     * but the dialog needs to update status from "Connecting…" to "Connected". */
                    connection_changed(jid, account_clients[jid].is_connected);
                } else if (!connecting_accounts.contains(jid)) {
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
        /* Early exit: if MQTT is entirely disabled, don't interfere
         * with XMPP connection handling at all. */
        if (!mqtt_enabled) return;

        string jid = account.bare_jid.to_string();

        if (state == ConnectionManager.ConnectionState.CONNECTED) {
            /* Run server detection in background (non-blocking) */
            run_server_detection.begin(account);

            /* Flush pending bridge messages — MQTT may have queued messages
             * while waiting for an XMPP account to come online. */
            if (bridge_manager != null) {
                bridge_manager.flush_pending();
            }

            /* NOTE: Standalone MQTT auto-connects at startup in registered(),
             * completely independent of XMPP accounts. No standalone logic here. */

            /* Per-account: connect MQTT for this specific account if enabled */
            var acfg = get_account_config(account);
            if (acfg.enabled) {
                if (!account_clients.has_key(jid) &&
                    !connecting_accounts.contains(jid)) {
                    debug("[ACCT:%s] XMPP online → starting per-account MQTT", jid);
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
                debug("[ACCT:%s] XMPP offline → disconnecting per-account MQTT", jid);
                /* Publish offline availability before clean disconnect —
                 * LWT only fires on unclean disconnect (TCP timeout). */
                if (discovery_managers.has_key(jid)) {
                    var dm = discovery_managers[jid];
                    var cl = account_clients[jid];
                    if (cl.is_connected) {
                        cl.publish_string(dm.get_availability_topic(), dm.get_lwt_payload(), 1, true);
                    }
                    /* Don't remove configs — XMPP will reconnect and re-publish */
                }
                account_clients[jid].disconnect_sync();
                account_clients.unset(jid);
                /* Note: disconnect_sync() already fires connection_changed
                 * via the on_connection_changed handler in create_client(). */
            }
            /* NOTE: Standalone MQTT is NOT affected by XMPP disconnect */
        }
    }

    /* ── Server detection (async, background) ─────────────────────── */

    private async void run_server_detection(Account account) {
        /* Only run detection if no type is set yet */
        string? existing = get_db_setting(KEY_SERVER_TYPE);
        if (existing != null && existing != "" && existing != "unknown") {
            /* Global detection already ran — propagate result to
             * per-account config if it still shows "unknown". */
            var acfg_prop = get_account_config(account);
            if (acfg_prop.server_type == "unknown" || acfg_prop.server_type == "") {
                acfg_prop.server_type = existing;
                save_account_config(account, acfg_prop);
                debug("MQTT: Propagated server_type '%s' to account %s",
                        existing, account.bare_jid.to_string());
            }
            return;
        }

        debug("MQTT: Running server type detection for %s…",
                account.bare_jid.to_string());

        DetectionResult result = yield ServerDetector.detect(
            app.stream_interactor, account);

        /* Re-check after yield: account may have been removed or
         * disconnected while detection was running (Coding Guidelines §9). */
        var post_state = app.stream_interactor.connection_manager.get_state(account);
        if (post_state != ConnectionManager.ConnectionState.CONNECTED) {
            debug("MQTT: Server detection finished but account %s no longer connected — discarding",
                    account.bare_jid.to_string());
            return;
        }

        if (result.server_type != ServerType.UNKNOWN) {
            app.db.settings.upsert()
                .value(app.db.settings.key, KEY_SERVER_TYPE, true)
                .value(app.db.settings.value, result.server_type.to_string_key())
                .perform();
            debug("MQTT: Server type saved: %s", result.server_type.to_label());

            /* Also save detection result in the per-account config */
            var acfg = get_account_config(account);
            acfg.server_type = result.server_type.to_string_key();

            /* Auto-configure port/TLS for ejabberd if still at defaults.
             * Only touch use_xmpp_auth when the user hasn't explicitly
             * chosen Custom Broker mode (broker_host == "" means
             * no custom broker was configured yet). */
            if (result.server_type == ServerType.EJABBERD) {
                if (acfg.broker_port == 1883 && !acfg.tls) {
                    acfg.broker_port = 8883;
                    acfg.tls = true;
                    if (acfg.broker_host == "") {
                        acfg.use_xmpp_auth = true;
                    }
                    debug("MQTT: Auto-configured port=8883 tls=true for ejabberd");
                }
            }

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
        debug("[STANDALONE] Connecting to %s:%d (tls=%s)…",
                cfg.broker_host, cfg.broker_port, cfg.tls.to_string());

        /* Register BEFORE connect_async — the CONNACK handler fires
         * on_connection_changed during connect_async (before it returns),
         * and is_standalone_connected() needs standalone_client set for
         * the dialog status display to work. */
        var client = create_client("standalone", cfg);
        standalone_client = client;

        bool ok = yield client.connect_async(
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
            client.disconnect_sync();
            /* Only null out if nobody replaced us during the yield */
            if (standalone_client == client) {
                standalone_client = null;
            }
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

        debug("[ACCT:%s] Connecting to %s:%d (tls=%s, xmpp_auth=%s)…",
                jid, host, port, tls.to_string(), acfg.use_xmpp_auth.to_string());

        var client = create_client(jid, acfg);

        /* Register client BEFORE connect_async — the CONNACK handler fires
         * on_connection_changed during connect_async (before it returns),
         * and is_account_connected() needs the client in account_clients
         * for the dialog status display to work. */
        account_clients[jid] = client;

        bool ok = yield client.connect_async(host, port, tls, user, pass);

        if (!ok) {
            warning("MQTT: Per-account connect failed for %s (host=%s port=%d)",
                    jid, host, port);
            /* Record failed connection event */
            if (mqtt_db != null) {
                mqtt_db.record_connection_event(jid, "error", host, port,
                    "Connect failed (host=%s port=%d)".printf(host, port));
            }
            client.disconnect_sync();
            /* Only remove from map if nobody replaced us during the yield */
            if (account_clients.has_key(jid) && account_clients[jid] == client) {
                account_clients.unset(jid);
            }
        }
    }

    /* ── Client factory ────────────────────────────────────────────── */

    private MqttClient create_client(string label, MqttConnectionConfig cfg) {
        var client = new MqttClient();

        /* Capture topic list from config at creation time */
        string[] topics_snapshot = cfg.get_topic_list();
        string cfg_host = cfg.broker_host;
        int cfg_port = cfg.broker_port;

        /* HA Discovery: set up LWT and DiscoveryManager if enabled.
         * Discovery requires a real MQTT broker (retained messages, LWT,
         * free topic hierarchies).  ejabberd/Prosody XMPP-MQTT do not
         * support these features — skip Discovery for XMPP mode. */
        MqttDiscoveryManager? disc_mgr = null;
        bool is_xmpp_mode = cfg.use_xmpp_auth || cfg.broker_host.strip() == "";
        if (cfg.discovery_enabled && !is_xmpp_mode) {
            disc_mgr = new MqttDiscoveryManager(this, client, label, cfg.discovery_prefix);
            /* Set LWT before connect — broker publishes "offline" on unclean disconnect */
            client.set_will(disc_mgr.get_availability_topic(), disc_mgr.get_lwt_payload());
            discovery_managers[label] = disc_mgr;
        } else if (cfg.discovery_enabled && is_xmpp_mode) {
            debug("MQTT [%s]: HA Discovery skipped — XMPP server MQTT does not support retained messages/LWT", label);
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

        /* BUG-FIX: Auto-subscribe bridge rule topics so that MQTT→XMPP
         * forwarding works even if the bridge topic isn't in the user's
         * explicit topic list.  Without this, bridge rules on topics not
         * in the config are silently inactive.
         * Only subscribe rules belonging to THIS client (scoped by label). */
        if (bridge_manager != null) {
            foreach (var rule in bridge_manager.get_rules_for_client(label)) {
                if (rule.enabled && rule.topic.strip() != "") {
                    client.subscribe(rule.topic.strip(), 0);
                }
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
                string prefix = (label == "standalone") ? "[STANDALONE]" : "[ACCT:%s]".printf(label);
                debug("%s Connected — %d topics pre-subscribed",
                        prefix, topics_snapshot.length);

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
            /* BUG-7 fix: validate UTF-8 — payload may contain arbitrary bytes */
            string payload_str = ((string) payload).make_valid();
            debug("MQTT on_message: label='%s' topic='%s' payload='%.120s' qos=%d retained=%s",
                  label, topic, payload_str, qos, retained ? "true" : "false");
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

            /* Skip bridge evaluation for self-published freetext messages.
             * When the user types e.g. "e5" in the bot chat it is published
             * to freetext_publish_topic. If the bridge rule uses a wildcard
             * that matches that topic, the broker echoes the user's own
             * command back and the bridge would forward it — which is wrong.
             * Only the *response* on a different topic should be bridged. */
            bool is_own_freetext = false;
            {
                MqttConnectionConfig? msg_cfg = null;
                if (label == "standalone") {
                    msg_cfg = standalone_config;
                } else {
                    var accounts = app.stream_interactor.get_accounts();
                    foreach (var acct in accounts) {
                        if (acct.bare_jid.to_string() == label) {
                            msg_cfg = get_account_config(acct);
                            break;
                        }
                    }
                }
                if (msg_cfg != null && msg_cfg.freetext_enabled
                        && msg_cfg.freetext_publish_topic.strip() != ""
                        && topic == msg_cfg.freetext_publish_topic.strip()) {
                    is_own_freetext = true;
                    debug("MQTT Bridge: skipping bridge for self-published freetext topic '%s'", topic);
                }
            }

            /* Phase 4: Evaluate bridge rules (MQTT → XMPP forwarding).
             * If a bridge rule matched, the message goes to the configured
             * MUC/chat — do NOT also show it in the bot conversation. */
            bool bridged = false;
            bool is_html = is_html_payload(payload_str);
            string? stream_url = extract_stream_url(payload_str);
            string? binary_ext = detect_binary_type(payload);
            if (bridge_manager != null && !is_own_freetext) {
                /* Check for binary payload (images etc.) — save to temp
                 * file and pass as local path instead of garbled text. */
                if (binary_ext != null) {
                    /* Reject oversized binary payloads (10 MB limit) */
                    if (payload.length > 10 * 1024 * 1024) {
                        debug("MQTT Bridge: Binary %s too large (%d bytes) — skipping",
                              binary_ext, payload.length);
                    } else {
                        /* Offload file write to a background thread to avoid
                         * blocking the main loop — large payloads (up to 10 MB)
                         * would otherwise stall RTP/Jingle video calls and
                         * ICE negotiation. */
                        uint8[] payload_copy = payload;
                        string ext_copy = binary_ext;
                        string label_copy = label;
                        string topic_copy = topic;
                        new Thread<void*>("mqtt-binary-save", () => {
                            string? temp_path = save_binary_payload(payload_copy, ext_copy);
                            Idle.add(() => {
                                if (temp_path != null && bridge_manager != null) {
                                    debug("MQTT Bridge: Binary %s detected (%d bytes), saved to %s",
                                          ext_copy, payload_copy.length, temp_path);
                                    bool b = bridge_manager.evaluate_binary(label_copy, topic_copy, temp_path);
                                    if (!b) {
                                        GLib.FileUtils.unlink(temp_path);
                                    } else {
                                        string tp = temp_path;
                                        Timeout.add_seconds(120, () => {
                                            GLib.FileUtils.unlink(tp);
                                            return false;
                                        });
                                    }
                                } else if (temp_path == null) {
                                    warning("MQTT Bridge: Binary %s detected but failed to save temp file",
                                            ext_copy);
                                }
                                return false;
                            });
                            return null;
                        });
                        bridged = true;  /* assume bridged — actual result on main loop */
                    }
                } else if (stream_url != null) {
                    /* M3U/PLS playlist — forward the extracted stream URL */
                    debug("MQTT Bridge: Stream URL extracted from playlist on '%s': %s",
                          topic, stream_url);
                    bridged = bridge_manager.evaluate(label, topic, stream_url);
                } else if (is_html) {
                    /* HTML pages (e.g. from Node-RED http-request with ret=txt)
                     * contain thousands of broken URL fragments that crash
                     * URL preview widgets or produce garbage in XMPP chats.
                     * Don't forward HTML verbatim — just log it. */
                    debug("MQTT Bridge: HTML payload detected (%d bytes) on topic '%s' — skipping bridge",
                          payload_str.length, topic);
                } else {
                    bridged = bridge_manager.evaluate(label, topic, payload_str);
                }
            }

            /* Phase 3: Evaluate alert rules and determine priority */
            MqttPriority priority = MqttPriority.NORMAL;
            if (alert_manager != null) {
                var result = alert_manager.evaluate(topic, payload_str);
                priority = result.priority;

                /* Log triggered alerts */
                if (result.triggered_rules.size > 0) {
                    debug("MQTT [%s]: Alert triggered on %s (%d rules, priority=%s)",
                            label, topic, result.triggered_rules.size,
                            priority.to_string_key());
                }
            }

            /* Retained message dedup: skip if the same retained message
             * was already seen.  Retained messages are re-delivered by
             * the broker on every reconnect — without this check they
             * flood both the DB and the chat with duplicates.
             * Non-retained messages always pass through. */
            if (retained) {
                string dedup_key = label + "\t" + topic;
                string payload_hash = Checksum.compute_for_string(ChecksumType.SHA256, payload_str);
                if (retained_cache.has_key(dedup_key) &&
                    retained_cache[dedup_key] == payload_hash) {
                    return;
                }
                retained_cache[dedup_key] = payload_hash;
            }

            /* If paused, record to DB but don't display as chat bubble */
            if (alert_manager != null && alert_manager.paused
                    && priority < MqttPriority.ALERT) {
                if (mqtt_db != null) {
                    mqtt_db.record_message(label, topic, payload_str,
                                           qos, retained,
                                           priority.to_string_key());
                }
                return;
            }

            /* Record message to DB */
            if (mqtt_db != null) {
                mqtt_db.record_message(label, topic, payload_str,
                                       qos, retained,
                                       priority.to_string_key());
            }

            /* Inject into bot conversation with priority.
             * Always show in bot — even if also forwarded by a bridge rule,
             * so the user sees the full MQTT traffic in the bot chat.
             * For binary payloads, show a description instead of garbled text.
             * For HTML payloads, show a summary instead of the raw HTML. */
            if (bot_conversation != null) {
                Conversation? conv = bot_conversation.get_conversation(label);
                if (conv == null) conv = bot_conversation.get_any_conversation();
                if (conv != null) {
                    if (binary_ext != null) {
                        string info = "📎 [%s] %s (%d bytes)".printf(
                            topic, binary_ext.up(), payload.length);
                        if (bridged) {
                            info += " → bridge forwarded";
                        }
                        bot_conversation.inject_mqtt_message(
                            conv, topic, info, priority);
                    } else if (stream_url != null) {
                        string info = "📻 [%s] Stream: %s".printf(topic, stream_url);
                        if (bridged) {
                            info += " → bridge forwarded";
                        }
                        bot_conversation.inject_mqtt_message(
                            conv, topic, info, priority);
                    } else if (is_html) {
                        string info = "🌐 [%s] HTML (%d bytes)".printf(
                            topic, payload_str.length);
                        bot_conversation.inject_mqtt_message(
                            conv, topic, info, priority);
                    } else {
                        /* Truncate very large text payloads to prevent UI hangs */
                        string display_str = payload_str;
                        if (display_str.length > 4096) {
                            display_str = display_str.substring(0, 4096) + "\n… (%d bytes truncated)".printf(payload_str.length - 4096);
                        }
                        bot_conversation.inject_mqtt_message(
                            conv, topic, display_str, priority);
                    }
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
                        "Account Settings → MQTT Bot → Publish &amp; Free Text."));
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

        /* Clamp port to valid range before any use (Audit Finding 3) */
        int safe_port = port.clamp(1, 65535);

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
            tmp_cfg.broker_port = safe_port;
            tmp_cfg.tls = use_tls;
            tmp_cfg.topics = standalone_config.topics;
            standalone_client = create_client("standalone", tmp_cfg);
        }

        return yield standalone_client.connect_async(
            broker_host, safe_port, use_tls, username, password);
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

    /**
     * Remove a discovery manager entry from the internal HashMap.
     * Used by command_handler after calling remove_discovery_configs().
     */
    public void remove_discovery_manager(string label) {
        discovery_managers.unset(label);
    }

    /**
     * Clear the retained-message dedup cache for a connection label.
     * Called by /mqtt clear so that retained messages re-appear if the
     * user explicitly reconnects after clearing history.
     */
    public void clear_retained_cache(string label) {
        var to_remove = new Gee.ArrayList<string>();
        string prefix = label + "\t";
        foreach (string key in retained_cache.keys) {
            if (key.has_prefix(prefix)) {
                to_remove.add(key);
            }
        }
        foreach (string key in to_remove) {
            retained_cache.unset(key);
        }
    }

    /* ── App-DB settings helpers (shared by AlertManager, BridgeManager) ── */

    public string? get_app_db_setting(string key) {
        var row_opt = app.db.settings.select(
                {app.db.settings.value})
            .with(app.db.settings.key, "=", key)
            .single()
            .row();
        if (row_opt.is_present())
            return row_opt[app.db.settings.value];
        return null;
    }

    public void set_app_db_setting(string key, string val) {
        app.db.settings.upsert()
            .value(app.db.settings.key, key, true)
            .value(app.db.settings.value, val)
            .perform();
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

    /* ── Binary payload detection ────────────────────────────────── */

    /**
     * Detect binary file type from magic bytes in MQTT payload.
     * Returns file extension (e.g. "png", "jpg") or null if not binary.
     */
    private static string? detect_binary_type(uint8[] data) {
        if (data.length < 12) return null;

        /* ── Images ── */
        /* PNG: \x89PNG\r\n\x1A\n */
        if (data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47) return "png";
        /* JPEG: \xFF\xD8\xFF */
        if (data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF) return "jpg";
        /* GIF: GIF87a or GIF89a */
        if (data[0] == 0x47 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x38) return "gif";
        /* WebP: RIFF....WEBP */
        if (data[0] == 0x52 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x46
            && data[8] == 0x57 && data[9] == 0x45 && data[10] == 0x42 && data[11] == 0x50) return "webp";
        /* BMP: BM + valid file-size field (bytes 2-5, little-endian, must match data length)
         * and reserved bytes 6-9 must be zero. Prevents false positive on text like "BMS voltage". */
        if (data[0] == 0x42 && data[1] == 0x4D
            && data[6] == 0x00 && data[7] == 0x00 && data[8] == 0x00 && data[9] == 0x00) {
            uint32 bmp_size = data[2] | (data[3] << 8) | (data[4] << 16) | (data[5] << 24);
            if (bmp_size >= 54 && bmp_size == data.length) return "bmp";
        }

        /* ── Audio ── */
        /* MP3: ID3 tag or MPEG sync word with valid version/layer bits.
         * Sync: 11 bits set (0xFF + 3 MSBs of byte 1), then version != 01, layer != 00 */
        if (data[0] == 0x49 && data[1] == 0x44 && data[2] == 0x33) return "mp3";
        if (data[0] == 0xFF && (data[1] & 0xE0) == 0xE0) {
            uint8 version = (data[1] >> 3) & 0x03;  /* 00=2.5, 01=reserved, 10=2, 11=1 */
            uint8 layer   = (data[1] >> 1) & 0x03;  /* 00=reserved, 01=III, 10=II, 11=I */
            if (version != 0x01 && layer != 0x00) return "mp3";
        }
        /* OGG: OggS */
        if (data[0] == 0x4F && data[1] == 0x67 && data[2] == 0x67 && data[3] == 0x53) return "ogg";
        /* FLAC: fLaC */
        if (data[0] == 0x66 && data[1] == 0x4C && data[2] == 0x61 && data[3] == 0x43) return "flac";
        /* WAV: RIFF....WAVE */
        if (data[0] == 0x52 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x46
            && data[8] == 0x57 && data[9] == 0x41 && data[10] == 0x56 && data[11] == 0x45) return "wav";

        /* ── Video ── */
        /* MP4/M4A/M4V: ....ftyp (offset 4) */
        if (data[4] == 0x66 && data[5] == 0x74 && data[6] == 0x79 && data[7] == 0x70) return "mp4";
        /* MKV/WebM: \x1A\x45\xDF\xA3 (EBML header) */
        if (data[0] == 0x1A && data[1] == 0x45 && data[2] == 0xDF && data[3] == 0xA3) return "mkv";
        /* AVI: RIFF....AVI  */
        if (data[0] == 0x52 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x46
            && data[8] == 0x41 && data[9] == 0x56 && data[10] == 0x49 && data[11] == 0x20) return "avi";

        /* ── Documents ── */
        /* PDF: %PDF */
        if (data[0] == 0x25 && data[1] == 0x50 && data[2] == 0x44 && data[3] == 0x46) return "pdf";
        /* ZIP (also DOCX/XLSX/etc.): PK\x03\x04 */
        if (data[0] == 0x50 && data[1] == 0x4B && data[2] == 0x03 && data[3] == 0x04) return "zip";

        return null;
    }

    /**
     * Save binary MQTT payload to a temp file.
     * Returns the temp file path, or null on error.
     */
    private static string? save_binary_payload(uint8[] data, string extension) {
        string temp_dir = GLib.Environment.get_tmp_dir();
        string filename = "dinox-mqtt-%s.%s".printf(
            GLib.Random.next_int().to_string("%08x"), extension);
        string path = GLib.Path.build_filename(temp_dir, filename);
        try {
            GLib.FileUtils.set_data(path, data);
            return path;
        } catch (GLib.FileError e) {
            warning("MQTT: Failed to save binary payload: %s", e.message);
            return null;
        }
    }

    /**
     * Detect if a text payload looks like an HTML page.
     * Checks for common HTML markers in the first 512 bytes.
     */
    private static bool is_html_payload(string text) {
        if (text.length < 15) return false;
        string head = text.substring(0, int.min(512, text.length)).down();
        return head.contains("<!doctype html") || head.contains("<html")
            || head.contains("<head>") || head.contains("<head ")
            || head.contains("<meta ");
    }

    /**
     * Detect M3U/PLS playlist content and extract the first stream URL.
     * Returns the stream URL or null if not a playlist.
     */
    private static string? extract_stream_url(string text) {
        if (text.length < 10) return null;
        /* Strip Unicode replacement chars (U+FFFD) that make_valid() inserts
         * for binary garbage at the end of HTTP responses from Node-RED. */
        string cleaned = text.replace("\xef\xbf\xbd", "");
        string trimmed = cleaned.strip();
        string lower = trimmed.down();

        /* M3U: starts with #EXTM3U or first non-comment line is a URL */
        if (lower.has_prefix("#extm3u") || lower.has_prefix("#extinf")) {
            int line_count = 0;
            foreach (string line in trimmed.split("\n")) {
                if (++line_count > 100) break;
                string l = line.strip().replace("\xef\xbf\xbd", "");
                if (l.has_prefix("http://") || l.has_prefix("https://")) {
                    try {
                        GLib.Uri.parse(l, GLib.UriFlags.NONE);
                        return l;
                    } catch { return null; }
                }
            }
            return null;
        }

        /* PLS: starts with [playlist] */
        if (lower.has_prefix("[playlist]")) {
            int line_count = 0;
            foreach (string line in trimmed.split("\n")) {
                if (++line_count > 100) break;
                string l = line.strip();
                /* File1=http://... */
                if (l.down().has_prefix("file") && l.contains("=")) {
                    string val = l.substring(l.index_of("=") + 1).strip().replace("\xef\xbf\xbd", "");
                    if (val.has_prefix("http://") || val.has_prefix("https://")) {
                        try {
                            GLib.Uri.parse(val, GLib.UriFlags.NONE);
                            return val;
                        } catch { return null; }
                    }
                }
            }
            return null;
        }

        /* Direct URL to a stream/playlist file (.m3u, .m3u8, .pls, .xspf)
         * e.g. https://frontend.streamonkey.net/antthue-90er/mp3-stream.m3u */
        if ((lower.has_prefix("http://") || lower.has_prefix("https://"))
            && !trimmed.contains("\n")) {
            /* Check for stream-related file extensions or path patterns */
            string path_lower = lower;
            /* Strip query string for extension check */
            int qpos = path_lower.index_of("?");
            if (qpos > 0) path_lower = path_lower.substring(0, qpos);
            if (path_lower.has_suffix(".m3u") || path_lower.has_suffix(".m3u8")
                || path_lower.has_suffix(".pls") || path_lower.has_suffix(".xspf")) {
                try {
                    GLib.Uri.parse(trimmed, GLib.UriFlags.NONE);
                    return trimmed;
                } catch { return null; }
            }
        }

        return null;
    }
}

}
