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

    /** Broker port. */
    public int broker_port { get; set; default = 1883; }

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

    /** QoS for free-form publishes. */
    public int freetext_qos { get; set; default = 1; }

    /** Retain flag for free-form publishes. */
    public bool freetext_retain { get; set; default = false; }

    /* ── Home Assistant Discovery ────────────────────────────── */

    /** Enable MQTT Discovery (Home Assistant auto-discovery). */
    public bool discovery_enabled { get; set; default = false; }

    /** Discovery topic prefix (default: homeassistant). */
    public string discovery_prefix { get; set; default = "homeassistant"; }

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
