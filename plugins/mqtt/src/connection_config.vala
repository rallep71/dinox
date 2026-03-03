/*
 * MqttConnectionConfig — Per-connection configuration for MQTT.
 *
 * Each MQTT connection (per-account or standalone) has its own
 * MqttConnectionConfig instance.  This replaces the old global
 * cfg_* fields in Plugin.
 *
 * Per-account configs are stored in the `account_settings` table.
 * Standalone config is stored in the global `settings` table
 * (with `mqtt_sa_` prefix).
 *
 * Copyright (C) 2026 Ralf Peter <dinox@handwerker.jetzt>
 */

using Gee;

namespace Dino.Plugins.Mqtt {

/**
 * Holds all configuration for a single MQTT connection.
 *
 * Used for both per-account and standalone connections.
 * Changes to this object do NOT auto-persist — call
 * Plugin.save_account_config() or Plugin.save_standalone_config()
 * after modifying.
 */
public class MqttConnectionConfig : Object {

    /* ── Basic connection ─────────────────────────────────────────── */

    /** Whether this connection is enabled. */
    public bool enabled { get; set; default = false; }

    /** Broker hostname or IP (empty = use account domain for per-account). */
    public string broker_host { get; set; default = ""; }

    /** Broker port (1–65535, clamped on set). */
    private int _broker_port = 1883;
    public int broker_port {
        get { return _broker_port; }
        set { _broker_port = value.clamp(1, 65535); }
    }

    /** Use TLS encryption. */
    public bool tls { get; set; default = false; }

    /* ── Authentication ───────────────────────────────────────────── */

    /** Use XMPP credentials for MQTT auth (ejabberd). Per-account only. */
    public bool use_xmpp_auth { get; set; default = false; }

    /** MQTT username (ignored when use_xmpp_auth is true). */
    public string username { get; set; default = ""; }

    /** MQTT password (ignored when use_xmpp_auth is true). */
    public string password { get; set; default = ""; }

    /* ── Topics ───────────────────────────────────────────────────── */

    /** Comma-separated list of subscribed topics. */
    public string topics { get; set; default = ""; }

    /** JSON map: topic → QoS level (0/1/2). */
    public string topic_qos_json { get; set; default = "{}"; }

    /** JSON map: topic → priority label. */
    public string topic_priorities_json { get; set; default = "{}"; }

    /** JSON map: topic → user-defined alias (display name). */
    public string topic_aliases_json { get; set; default = "{}"; }

    /* ── Bot ──────────────────────────────────────────────────────── */

    /** Whether to show a bot conversation for this connection. */
    public bool bot_enabled { get; set; default = true; }

    /** Display name for the bot conversation. */
    public string bot_name { get; set; default = "MQTT Bot"; }

    /* ── Server detection ─────────────────────────────────────────── */

    /** Detected server type: "ejabberd", "prosody", "unknown". */
    public string server_type { get; set; default = "unknown"; }

    /* ── Freitext-Publish (Node-RED integration) ──────────────────── */

    /** Allow free-form text in bot chat → publish to topic. */
    public bool freetext_enabled { get; set; default = false; }

    /** Topic for free-form text publish. */
    public string freetext_publish_topic { get; set; default = ""; }

    /** Topic for responses (auto-subscribed). */
    public string freetext_response_topic { get; set; default = ""; }

    /** QoS for free-form publishes (clamped 0–2). */
    private int _freetext_qos = 1;
    public int freetext_qos {
        get { return _freetext_qos; }
        set { _freetext_qos = value.clamp(0, 2); }
    }

    /** Retain flag for free-form publishes. */
    public bool freetext_retain { get; set; default = false; }

    /* ── Home Assistant Discovery ────────────────────────────── */

    /** Enable MQTT Discovery (Home Assistant auto-discovery). */
    public bool discovery_enabled { get; set; default = false; }

    /** Discovery topic prefix (default: homeassistant).
     *  Sanitized on set: MQTT wildcard chars (#, +) and control
     *  chars removed to prevent invalid topic construction.
     *  (Audit Finding 7) */
    private string _discovery_prefix = "homeassistant";
    public string discovery_prefix {
        get { return _discovery_prefix; }
        set {
            string v = value.strip();
            /* Remove MQTT wildcard and control characters */
            v = v.replace("#", "").replace("+", "")
                 .replace("\0", "").replace(" ", "");
            _discovery_prefix = (v != "") ? v : "homeassistant";
        }
    }

    /* ── Alerts / Bridges / Presets (JSON-serialised) ─────────────── */

    /** JSON array of AlertRule objects. */
    public string alerts_json { get; set; default = "[]"; }

    /** JSON array of BridgeRule objects. */
    public string bridges_json { get; set; default = "[]"; }

    /** JSON array of PublishPreset objects. */
    public string publish_presets_json { get; set; default = "[]"; }

    /* ── Helpers ──────────────────────────────────────────────────── */

    /**
     * Split topics string into a trimmed, non-empty array.
     */
    public string[] get_topic_list() {
        if (topics.strip() == "") return {};
        string[] result = {};
        foreach (string t in topics.split(",")) {
            string trimmed = t.strip();
            if (trimmed != "") result += trimmed;
        }
        return result;
    }

    /* ── Alias helpers ────────────────────────────────────────────── */

    /** Lazily-built alias cache for O(1) lookup. Rebuilt on mutation. */
    private HashMap<string, string>? _alias_cache = null;
    /** Tracks the JSON that was used to build the cache. */
    private string? _alias_cache_json = null;

    /**
     * Parse topic_aliases_json into a HashMap.
     * Cached after first call; invalidated by set_alias/remove_alias
     * or when topic_aliases_json changes externally.
     */
    public HashMap<string, string> get_aliases_map() {
        /* Invalidate cache if the JSON was changed externally */
        if (_alias_cache != null && _alias_cache_json != topic_aliases_json) {
            _alias_cache = null;
        }
        if (_alias_cache != null) return _alias_cache;
        _alias_cache = new HashMap<string, string>();
        _alias_cache_json = topic_aliases_json;
        if (topic_aliases_json == null || topic_aliases_json.strip() == ""
            || topic_aliases_json == "{}") {
            return _alias_cache;
        }
        try {
            var parser = new Json.Parser();
            parser.load_from_data(topic_aliases_json, -1);
            var root = parser.get_root();
            if (root != null && root.get_node_type() == Json.NodeType.OBJECT) {
                root.get_object().foreach_member((obj, key, node) => {
                    string? val = node.get_string();
                    if (val != null && val.strip() != "") {
                        _alias_cache[key] = val.strip();
                    }
                });
            }
        } catch (Error e) {
            warning("MQTT: Failed to parse topic_aliases_json: %s", e.message);
        }
        return _alias_cache;
    }

    /**
     * Resolve a topic to its alias, with wildcard prefix matching.
     *
     * 1. Exact match: topic in aliases → alias
     * 2. Wildcard prefix: "a/b/#" alias + topic "a/b/c/d" → "alias / c/d"
     * 3. No match → null (caller falls back to raw topic display)
     */
    public string? resolve_alias(string topic) {
        var aliases = get_aliases_map();
        if (aliases.size == 0) return null;

        /* 1. Exact match */
        if (aliases.has_key(topic)) return aliases[topic];

        /* 2. Wildcard prefix match (longest prefix wins) */
        string? best_alias = null;
        int best_prefix_len = -1;
        foreach (var entry in aliases.entries) {
            string pattern = entry.key;
            if (!pattern.has_suffix("/#")) continue;
            string prefix = pattern.substring(0, pattern.length - 2); /* strip /# */
            if (topic.has_prefix(prefix + "/") && (int)prefix.length > best_prefix_len) {
                string rest = topic.substring(prefix.length + 1);
                best_alias = "%s / %s".printf(entry.value, rest);
                best_prefix_len = (int)prefix.length;
            }
        }
        return best_alias;
    }

    /**
     * Set or update an alias for a topic.
     * Alias is clamped to MAX_ALIAS_LENGTH characters.
     */
    public const int MAX_ALIAS_LENGTH = 50;

    public void set_alias(string topic, string alias) {
        string safe = alias.strip();
        if (safe.length > MAX_ALIAS_LENGTH) {
            safe = safe.substring(0, MAX_ALIAS_LENGTH);
        }
        var map = get_aliases_map();
        map[topic] = safe;
        _rebuild_aliases_json();
    }

    /**
     * Remove an alias for a topic. Returns true if it existed.
     */
    public bool remove_alias(string topic) {
        var map = get_aliases_map();
        if (!map.has_key(topic)) return false;
        map.unset(topic);
        _rebuild_aliases_json();
        return true;
    }

    /**
     * Rebuild topic_aliases_json from the in-memory cache.
     */
    private void _rebuild_aliases_json() {
        var map = get_aliases_map();
        var builder = new Json.Builder();
        builder.begin_object();
        foreach (var entry in map.entries) {
            builder.set_member_name(entry.key);
            builder.add_string_value(entry.value);
        }
        builder.end_object();
        var gen = new Json.Generator();
        gen.set_root(builder.get_root());
        topic_aliases_json = gen.to_data(null);
    }

    /**
     * Deep-copy this config.
     */
    public MqttConnectionConfig copy() {
        var c = new MqttConnectionConfig();
        c.enabled = this.enabled;
        c.broker_host = this.broker_host;
        c.broker_port = this.broker_port;
        c.tls = this.tls;
        c.use_xmpp_auth = this.use_xmpp_auth;
        c.username = this.username;
        c.password = this.password;
        c.topics = this.topics;
        c.topic_qos_json = this.topic_qos_json;
        c.topic_priorities_json = this.topic_priorities_json;
        c.topic_aliases_json = this.topic_aliases_json;
        c.bot_enabled = this.bot_enabled;
        c.bot_name = this.bot_name;
        c.server_type = this.server_type;
        c.freetext_enabled = this.freetext_enabled;
        c.freetext_publish_topic = this.freetext_publish_topic;
        c.freetext_response_topic = this.freetext_response_topic;
        c.freetext_qos = this.freetext_qos;
        c.freetext_retain = this.freetext_retain;
        c.alerts_json = this.alerts_json;
        c.bridges_json = this.bridges_json;
        c.publish_presets_json = this.publish_presets_json;
        c.discovery_enabled = this.discovery_enabled;
        c.discovery_prefix = this.discovery_prefix;
        return c;
    }

    /**
     * Check if broker connection parameters differ from another config.
     * Used to decide if a reconnect is needed.
     */
    public bool connection_differs(MqttConnectionConfig other) {
        return (this.broker_host != other.broker_host ||
                this.broker_port != other.broker_port ||
                this.tls != other.tls ||
                this.use_xmpp_auth != other.use_xmpp_auth ||
                this.username != other.username ||
                this.password != other.password);
    }

    public string to_debug_string() {
        return "MqttConnectionConfig(enabled=%s host=%s port=%d tls=%s topics=%s)".printf(
            enabled.to_string(), broker_host, broker_port,
            tls.to_string(), topics);
    }
}

/* ── DB key constants ─────────────────────────────────────────────── */

/**
 * Keys for per-account settings (stored in `account_settings` table).
 */
namespace AccountKey {
    public const string ENABLED           = "mqtt_enabled";
    public const string BOT_ENABLED       = "mqtt_bot_enabled";
    public const string BROKER_HOST       = "mqtt_broker_host";
    public const string BROKER_PORT       = "mqtt_broker_port";
    public const string TLS               = "mqtt_tls";
    public const string USE_XMPP_AUTH     = "mqtt_use_xmpp_auth";
    public const string USERNAME          = "mqtt_username";
    public const string PASSWORD          = "mqtt_password";
    public const string TOPICS            = "mqtt_topics";
    public const string SERVER_TYPE       = "mqtt_server_type";
    public const string BOT_NAME          = "mqtt_bot_name";
    public const string ALERTS            = "mqtt_alerts";
    public const string BRIDGES           = "mqtt_bridges";
    public const string TOPIC_QOS         = "mqtt_topic_qos";
    public const string TOPIC_PRIORITIES  = "mqtt_topic_priorities";
    public const string TOPIC_ALIASES      = "mqtt_topic_aliases";
    public const string PUBLISH_PRESETS   = "mqtt_publish_presets";
    public const string FREETEXT_ENABLED       = "mqtt_freetext_enabled";
    public const string FREETEXT_PUBLISH_TOPIC = "mqtt_freetext_publish_topic";
    public const string FREETEXT_RESPONSE_TOPIC = "mqtt_freetext_response_topic";
    public const string FREETEXT_QOS           = "mqtt_freetext_qos";
    public const string FREETEXT_RETAIN        = "mqtt_freetext_retain";
    public const string DISCOVERY_ENABLED       = "mqtt_discovery_enabled";
    public const string DISCOVERY_PREFIX        = "mqtt_discovery_prefix";
    public const string HINT_SHOWN        = "mqtt_hint_shown";
}

/**
 * Keys for standalone settings (stored in global `settings` table).
 * Prefixed with `mqtt_sa_` to distinguish from old global keys.
 */
namespace StandaloneKey {
    public const string ENABLED           = "mqtt_sa_enabled";
    public const string BROKER_HOST       = "mqtt_sa_host";
    public const string BROKER_PORT       = "mqtt_sa_port";
    public const string TLS               = "mqtt_sa_tls";
    public const string USERNAME          = "mqtt_sa_username";
    public const string PASSWORD          = "mqtt_sa_password";
    public const string TOPICS            = "mqtt_sa_topics";
    public const string BOT_ENABLED       = "mqtt_sa_bot_enabled";
    public const string BOT_NAME          = "mqtt_sa_bot_name";
    public const string ALERTS            = "mqtt_sa_alerts";
    public const string BRIDGES           = "mqtt_sa_bridges";
    public const string TOPIC_QOS         = "mqtt_sa_topic_qos";
    public const string TOPIC_PRIORITIES  = "mqtt_sa_topic_priorities";
    public const string TOPIC_ALIASES      = "mqtt_sa_topic_aliases";
    public const string PUBLISH_PRESETS   = "mqtt_sa_publish_presets";
    public const string SERVER_TYPE       = "mqtt_sa_server_type";
    public const string FREETEXT_ENABLED       = "mqtt_sa_freetext_enabled";
    public const string FREETEXT_PUBLISH_TOPIC = "mqtt_sa_freetext_publish_topic";
    public const string FREETEXT_RESPONSE_TOPIC = "mqtt_sa_freetext_response_topic";
    public const string FREETEXT_QOS           = "mqtt_sa_freetext_qos";
    public const string FREETEXT_RETAIN        = "mqtt_sa_freetext_retain";
    public const string DISCOVERY_ENABLED       = "mqtt_sa_discovery_enabled";
    public const string DISCOVERY_PREFIX        = "mqtt_sa_discovery_prefix";
}

/**
 * Migration key — set once after old→new migration completes.
 */
namespace MigrationKey {
    public const string MIGRATED = "mqtt_migrated";
}

}
