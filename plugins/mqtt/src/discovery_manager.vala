/*
 * MqttDiscoveryManager — Home Assistant MQTT Discovery for DinoX.
 *
 * Implements the HA MQTT Discovery protocol (Device Discovery format)
 * so that DinoX appears as a device in Home Assistant (or compatible
 * software) with entities for connection status, subscriptions, bridges,
 * alerts, and overall status.
 *
 * Discovery is opt-in (disabled by default) and can be toggled per
 * connection via Settings or /mqtt discovery on|off.
 *
 * Uses the **device discovery** format (single config message with
 * all components) as recommended by HA for multi-entity devices:
 *
 *   <prefix>/device/<node_id>/config        → JSON device config (retained)
 *   dinox/<node_id>/availability             → "online"/"offline" (retained, LWT)
 *   dinox/<node_id>/<entity>/state           → current value (retained)
 *
 * Default prefix: "homeassistant"
 *
 * HA status topic: <prefix>/status — DinoX subscribes to this and
 * re-publishes discovery + state when HA sends "online" (birth message).
 *
 * Reference: https://www.home-assistant.io/integrations/mqtt/#mqtt-discovery
 *
 * Copyright (C) 2026 Ralf Peter <dinox@handwerker.jetzt>
 */

using Gee;
using Json;

namespace Dino.Plugins.Mqtt {

/**
 * Manages MQTT Discovery announcements for a single DinoX connection.
 */
public class MqttDiscoveryManager : GLib.Object {

    /** The MQTT client to publish on. */
    private MqttClient client;

    /** Connection label ("standalone" or account JID). */
    private string connection_label;

    /** Discovery topic prefix (default: "homeassistant"). */
    private string prefix;

    /** Sanitized node ID derived from connection_label. */
    private string node_id;

    /** Whether discovery configs have been published. */
    private bool published = false;

    /** Reference to the plugin for querying state. */
    private weak Plugin plugin;

    /** Whether we are subscribed to the HA status topic. */
    private bool subscribed_to_ha_status = false;

    /* ── Entity IDs ────────────────────────────────────────────────── */

    private const string ENTITY_CONNECTIVITY  = "connectivity";
    private const string ENTITY_SUBSCRIPTIONS = "subscriptions";
    private const string ENTITY_BRIDGES       = "bridges";
    private const string ENTITY_ALERTS        = "alerts";
    private const string ENTITY_STATUS        = "status";

    /* ── Command entity IDs ────────────────────────────────────────── */

    private const string ENTITY_ALERTS_PAUSE  = "alerts_pause";
    private const string ENTITY_RECONNECT     = "reconnect";
    private const string ENTITY_REFRESH       = "refresh";

    /* ── Software info ─────────────────────────────────────────────── */

    private const string ORIGIN_NAME = "DinoX";
    private const string ORIGIN_SW   = "1.1.4.2";
    private const string ORIGIN_URL  = "https://github.com/rallep71/dinox";

    /* ── Construction ──────────────────────────────────────────────── */

    public MqttDiscoveryManager(Plugin plugin, MqttClient client,
                                 string connection_label, string prefix) {
        this.plugin = plugin;
        this.client = client;
        this.connection_label = connection_label;
        this.prefix = (prefix != "") ? prefix : "homeassistant";
        this.node_id = sanitize_id(connection_label);
    }

    /* ── Public API ────────────────────────────────────────────────── */

    /**
     * Get the availability topic for LWT / birth.
     */
    public string get_availability_topic() {
        return "dinox/%s/availability".printf(node_id);
    }

    /**
     * Get the birth payload ("online").
     */
    public string get_birth_payload() {
        return "online";
    }

    /**
     * Get the LWT payload ("offline").
     */
    public string get_lwt_payload() {
        return "offline";
    }

    /**
     * Get the HA status topic that HA publishes to on start.
     * Devices should subscribe to this and re-publish discovery on "online".
     */
    public string get_ha_status_topic() {
        return "%s/status".printf(prefix);
    }

    /**
     * Get the command topic for an entity.
     */
    public string command_topic(string entity_id) {
        return "dinox/%s/%s/set".printf(node_id, entity_id);
    }

    /**
     * Check if a topic is one of our command topics.
     */
    public bool is_command_topic(string topic) {
        return topic == command_topic(ENTITY_ALERTS_PAUSE)
            || topic == command_topic(ENTITY_RECONNECT)
            || topic == command_topic(ENTITY_REFRESH);
    }

    /**
     * Subscribe to the HA status topic and all command topics.
     * When HA (re)starts, it sends "online" to <prefix>/status.
     * We re-publish our discovery configs + states in response.
     * Must be called after the MQTT connection is established.
     */
    public void subscribe_ha_status() {
        if (subscribed_to_ha_status) return;

        string ha_topic = get_ha_status_topic();
        client.subscribe(ha_topic, 1);
        message("MQTT Discovery: Subscribed to HA status topic: %s", ha_topic);

        /* Subscribe to command topics */
        client.subscribe(command_topic(ENTITY_ALERTS_PAUSE), 1);
        client.subscribe(command_topic(ENTITY_RECONNECT), 1);
        client.subscribe(command_topic(ENTITY_REFRESH), 1);
        message("MQTT Discovery: Subscribed to command topics for node=%s", node_id);

        subscribed_to_ha_status = true;
    }

    /**
     * Handle a message received on the HA status topic.
     * Called from the plugin's message handler.
     * If HA sends "online", re-publish discovery configs + states.
     */
    public void handle_ha_status_message(string payload) {
        if (payload.strip() == "online") {
            message("MQTT Discovery: HA birth detected — re-publishing discovery for node=%s", node_id);
            /* Re-publish: force re-send even if already published */
            published = false;
            publish_discovery_config();
            publish_all_states();
        }
    }

    /**
     * Handle a command message received on a command topic.
     * Returns true if the topic was handled.
     */
    public bool handle_command_message(string topic, string payload) {
        if (topic == command_topic(ENTITY_ALERTS_PAUSE)) {
            return handle_alerts_pause_command(payload);
        }
        if (topic == command_topic(ENTITY_RECONNECT)) {
            return handle_reconnect_command(payload);
        }
        if (topic == command_topic(ENTITY_REFRESH)) {
            return handle_refresh_command(payload);
        }
        return false;
    }

    /**
     * Handle alerts pause switch command (ON/OFF).
     */
    private bool handle_alerts_pause_command(string payload) {
        string cmd = payload.strip().up();
        MqttAlertManager? am = plugin.get_alert_manager();
        if (am == null) return false;

        if (cmd == "ON") {
            am.paused = true;
            message("MQTT Discovery: Alerts paused via HA command");
        } else if (cmd == "OFF") {
            am.paused = false;
            message("MQTT Discovery: Alerts resumed via HA command");
        } else {
            return false;
        }
        /* Publish confirmed state back */
        publish_state(ENTITY_ALERTS_PAUSE, am.paused ? "ON" : "OFF");
        return true;
    }

    /**
     * Handle reconnect button command (PRESS).
     */
    private bool handle_reconnect_command(string payload) {
        string cmd = payload.strip().up();
        if (cmd != "PRESS") return false;

        message("MQTT Discovery: Reconnect triggered via HA command for node=%s", node_id);
        /* Schedule reconnect on main loop to avoid re-entrant issues */
        Idle.add(() => {
            plugin.reload_config();
            return false;  /* run once */
        });
        return true;
    }

    /**
     * Handle refresh discovery button command (PRESS).
     */
    private bool handle_refresh_command(string payload) {
        string cmd = payload.strip().up();
        if (cmd != "PRESS") return false;

        message("MQTT Discovery: Refresh triggered via HA command for node=%s", node_id);
        published = false;
        publish_discovery_config();
        publish_all_states();
        return true;
    }

    /**
     * Publish the device discovery config message (retained).
     * Uses the HA "device discovery" format: a single message at
     *   <prefix>/device/<node_id>/config
     * containing all components under the "cmps" key.
     *
     * Called once after successful MQTT connect and on HA birth.
     */
    public void publish_discovery_config() {
        if (published) return;

        var builder = new Json.Builder();
        builder.begin_object();

        /* ── device (dev) — mandatory ──────────────────────────────── */
        builder.set_member_name("dev");
        builder.begin_object();
        builder.set_member_name("ids");
        builder.begin_array();
        builder.add_string_value("dinox_%s".printf(node_id));
        builder.end_array();
        string device_name;
        if (connection_label == "standalone") {
            device_name = "DinoX MQTT (Standalone)";
        } else {
            device_name = "DinoX MQTT (%s)".printf(connection_label);
        }
        builder.set_member_name("name");
        builder.add_string_value(device_name);
        builder.set_member_name("mf");
        builder.add_string_value("DinoX");
        builder.set_member_name("mdl");
        builder.add_string_value("MQTT Plugin");
        builder.set_member_name("sw");
        builder.add_string_value(ORIGIN_SW);
        builder.end_object();

        /* ── origin (o) — mandatory for device discovery ───────────── */
        builder.set_member_name("o");
        builder.begin_object();
        builder.set_member_name("name");
        builder.add_string_value(ORIGIN_NAME);
        builder.set_member_name("sw");
        builder.add_string_value(ORIGIN_SW);
        builder.set_member_name("url");
        builder.add_string_value(ORIGIN_URL);
        builder.end_object();

        /* ── availability (shared for all components) ──────────────── */
        builder.set_member_name("avty");
        builder.begin_array();
        builder.begin_object();
        builder.set_member_name("t");
        builder.add_string_value(get_availability_topic());
        builder.set_member_name("pl_avail");
        builder.add_string_value("online");
        builder.set_member_name("pl_not_avail");
        builder.add_string_value("offline");
        builder.end_object();
        builder.end_array();

        /* ── components (cmps) — all entities ──────────────────────── */
        builder.set_member_name("cmps");
        builder.begin_object();

        /* 1. Connectivity (binary_sensor) */
        builder.set_member_name(ENTITY_CONNECTIVITY);
        builder.begin_object();
        builder.set_member_name("p");
        builder.add_string_value("binary_sensor");
        builder.set_member_name("device_class");
        builder.add_string_value("connectivity");
        builder.set_member_name("stat_t");
        builder.add_string_value(state_topic(ENTITY_CONNECTIVITY));
        builder.set_member_name("pl_on");
        builder.add_string_value("ON");
        builder.set_member_name("pl_off");
        builder.add_string_value("OFF");
        builder.set_member_name("ic");
        builder.add_string_value("mdi:chat-processing");
        builder.set_member_name("uniq_id");
        builder.add_string_value(unique_id(ENTITY_CONNECTIVITY));
        builder.end_object();

        /* 2. Subscriptions (sensor) */
        add_sensor_component(builder, ENTITY_SUBSCRIPTIONS,
            _("Subscriptions"), "mdi:playlist-check");

        /* 3. Bridges (sensor) */
        add_sensor_component(builder, ENTITY_BRIDGES,
            _("Bridge Rules"), "mdi:bridge");

        /* 4. Alerts (sensor) */
        add_sensor_component(builder, ENTITY_ALERTS,
            _("Alert Rules"), "mdi:bell-alert");

        /* 5. Status (sensor) */
        add_sensor_component(builder, ENTITY_STATUS,
            _("Status"), "mdi:information-outline");

        /* 6. Alerts Pause (switch) — controllable from HA */
        builder.set_member_name(ENTITY_ALERTS_PAUSE);
        builder.begin_object();
        builder.set_member_name("p");
        builder.add_string_value("switch");
        builder.set_member_name("name");
        builder.add_string_value(_("Alerts Pause"));
        builder.set_member_name("stat_t");
        builder.add_string_value(state_topic(ENTITY_ALERTS_PAUSE));
        builder.set_member_name("cmd_t");
        builder.add_string_value(command_topic(ENTITY_ALERTS_PAUSE));
        builder.set_member_name("ic");
        builder.add_string_value("mdi:bell-sleep");
        builder.set_member_name("uniq_id");
        builder.add_string_value(unique_id(ENTITY_ALERTS_PAUSE));
        builder.end_object();

        /* 7. Reconnect (button) — controllable from HA */
        builder.set_member_name(ENTITY_RECONNECT);
        builder.begin_object();
        builder.set_member_name("p");
        builder.add_string_value("button");
        builder.set_member_name("name");
        builder.add_string_value(_("Reconnect"));
        builder.set_member_name("cmd_t");
        builder.add_string_value(command_topic(ENTITY_RECONNECT));
        builder.set_member_name("ic");
        builder.add_string_value("mdi:connection");
        builder.set_member_name("uniq_id");
        builder.add_string_value(unique_id(ENTITY_RECONNECT));
        builder.end_object();

        /* 8. Refresh Discovery (button) — controllable from HA */
        builder.set_member_name(ENTITY_REFRESH);
        builder.begin_object();
        builder.set_member_name("p");
        builder.add_string_value("button");
        builder.set_member_name("name");
        builder.add_string_value(_("Refresh Discovery"));
        builder.set_member_name("cmd_t");
        builder.add_string_value(command_topic(ENTITY_REFRESH));
        builder.set_member_name("ic");
        builder.add_string_value("mdi:refresh");
        builder.set_member_name("uniq_id");
        builder.add_string_value(unique_id(ENTITY_REFRESH));
        builder.end_object();

        builder.end_object();  /* end cmps */

        builder.end_object();  /* end root */

        /* Publish to device discovery topic */
        string config_topic = "%s/device/%s/config".printf(prefix, node_id);
        publish_retained(config_topic, generate_json(builder));

        published = true;
        message("MQTT Discovery: Published device config to %s", config_topic);
    }

    /**
     * Publish the birth message ("online") on the availability topic.
     * Called after successful connect.
     */
    public void publish_birth() {
        publish_retained(get_availability_topic(), get_birth_payload());
    }

    /**
     * Publish current state for all entities.
     * Called after connect and whenever state changes.
     */
    public void publish_all_states() {
        publish_state(ENTITY_CONNECTIVITY, "ON");
        update_subscriptions_state();
        update_bridges_state();
        update_alerts_state();
        update_status_state();
        update_alerts_pause_state();
    }

    /**
     * Update the alerts pause switch state.
     */
    public void update_alerts_pause_state() {
        MqttAlertManager? am = plugin.get_alert_manager();
        string state = (am != null && am.paused) ? "ON" : "OFF";
        publish_state(ENTITY_ALERTS_PAUSE, state);
    }

    /**
     * Update the subscriptions count state.
     */
    public void update_subscriptions_state() {
        int count = 0;
        var cfg = get_config();
        if (cfg != null) {
            count = cfg.get_topic_list().length;
        }
        publish_state(ENTITY_SUBSCRIPTIONS, count.to_string());
    }

    /**
     * Update the bridge rules count state.
     */
    public void update_bridges_state() {
        int count = 0;
        MqttBridgeManager? bm = plugin.get_bridge_manager();
        if (bm != null) {
            count = bm.get_rules().size;
        }
        publish_state(ENTITY_BRIDGES, count.to_string());
    }

    /**
     * Update the alert rules count state.
     */
    public void update_alerts_state() {
        int count = 0;
        MqttAlertManager? am = plugin.get_alert_manager();
        if (am != null) {
            count = am.get_rules().size;
        }
        publish_state(ENTITY_ALERTS, count.to_string());
    }

    /**
     * Update the status text state.
     */
    public void update_status_state() {
        var cfg = get_config();
        string status_text;
        if (cfg != null) {
            string broker = cfg.broker_host != "" ? cfg.broker_host : _("auto");
            status_text = "%s:%d (%s)".printf(broker, cfg.broker_port,
                client.is_connected ? _("connected") : _("disconnected"));
        } else {
            status_text = _("unconfigured");
        }
        publish_state(ENTITY_STATUS, status_text);
    }

    /**
     * Remove all discovery configs (publish empty retained to device topic).
     * Called when discovery is disabled.
     */
    public void remove_discovery_configs() {
        /* Device discovery: single empty payload removes the entire device */
        string config_topic = "%s/device/%s/config".printf(prefix, node_id);
        publish_retained(config_topic, "");

        /* Also clear state topics and availability */
        publish_retained(get_availability_topic(), "");
        publish_retained(state_topic(ENTITY_CONNECTIVITY), "");
        publish_retained(state_topic(ENTITY_SUBSCRIPTIONS), "");
        publish_retained(state_topic(ENTITY_BRIDGES), "");
        publish_retained(state_topic(ENTITY_ALERTS), "");
        publish_retained(state_topic(ENTITY_STATUS), "");
        /* BUG-16 fix: also clear ENTITY_ALERTS_PAUSE state topic */
        publish_retained(state_topic(ENTITY_ALERTS_PAUSE), "");

        /* BUG-14 fix: unsubscribe from command topics + HA status topic */
        if (subscribed_to_ha_status) {
            client.unsubscribe(get_ha_status_topic());
            client.unsubscribe(command_topic(ENTITY_ALERTS_PAUSE));
            client.unsubscribe(command_topic(ENTITY_RECONNECT));
            client.unsubscribe(command_topic(ENTITY_REFRESH));
            subscribed_to_ha_status = false;
        }

        published = false;
        message("MQTT Discovery: Removed device config for node=%s", node_id);
    }

    /**
     * Get a summary of the current discovery state.
     */
    public string get_status_summary() {
        var sb = new StringBuilder();
        sb.append(_("MQTT Discovery Status\n"));
        sb.append("─────────────────────\n");
        sb.append(_("Format: Device Discovery (HA 2024.x+)\n"));
        sb.append(_("Enabled: %s\n").printf(published ? _("Yes") : _("No")));
        sb.append(_("Prefix: %s\n").printf(prefix));
        sb.append(_("Node ID: %s\n").printf(node_id));
        sb.append(_("Config topic: %s/device/%s/config\n").printf(prefix, node_id));
        sb.append(_("Availability: %s\n").printf(get_availability_topic()));
        sb.append(_("HA status topic: %s\n").printf(get_ha_status_topic()));
        sb.append("\n");
        sb.append(_("Announced Entities:\n"));
        sb.append("  • %s (binary_sensor, device_class=connectivity)\n".printf(ENTITY_CONNECTIVITY));
        sb.append("  • %s (sensor)\n".printf(ENTITY_SUBSCRIPTIONS));
        sb.append("  • %s (sensor)\n".printf(ENTITY_BRIDGES));
        sb.append("  • %s (sensor)\n".printf(ENTITY_ALERTS));
        sb.append("  • %s (sensor)\n".printf(ENTITY_STATUS));
        sb.append("  • %s (switch, cmd_t)\n".printf(ENTITY_ALERTS_PAUSE));
        sb.append("  • %s (button, cmd_t)\n".printf(ENTITY_RECONNECT));
        sb.append("  • %s (button, cmd_t)\n".printf(ENTITY_REFRESH));
        sb.append("\n");
        sb.append(_("Origin: %s %s\n").printf(ORIGIN_NAME, ORIGIN_SW));
        return sb.str;
    }

    /* ── Private helpers ──────────────────────────────────────────── */

    /**
     * Get the active config for this connection.
     */
    private MqttConnectionConfig? get_config() {
        if (connection_label == "standalone") {
            return plugin.get_standalone_config();
        }
        var accounts = plugin.app.stream_interactor.get_accounts();
        foreach (var acct in accounts) {
            if (acct.bare_jid.to_string() == connection_label) {
                return plugin.get_account_config(acct);
            }
        }
        return null;
    }

    /**
     * Add a sensor component to the cmps object builder.
     */
    private void add_sensor_component(Json.Builder builder, string entity_id,
                                       string name, string icon) {
        builder.set_member_name(entity_id);
        builder.begin_object();
        builder.set_member_name("p");
        builder.add_string_value("sensor");
        builder.set_member_name("name");
        builder.add_string_value(name);
        builder.set_member_name("stat_t");
        builder.add_string_value(state_topic(entity_id));
        builder.set_member_name("ic");
        builder.add_string_value(icon);
        builder.set_member_name("uniq_id");
        builder.add_string_value(unique_id(entity_id));
        builder.end_object();
    }

    /**
     * Get full unique_id for an entity.
     */
    private string unique_id(string entity_id) {
        return "dinox_%s_%s".printf(node_id, entity_id);
    }

    /**
     * Get the state topic for an entity.
     */
    private string state_topic(string entity_id) {
        return "dinox/%s/%s/state".printf(node_id, entity_id);
    }

    /**
     * Publish a state value (retained).
     */
    private void publish_state(string entity_id, string value) {
        publish_retained(state_topic(entity_id), value);
    }

    /**
     * Publish a retained message via the MQTT client.
     */
    private void publish_retained(string topic, string payload) {
        if (client != null && client.is_connected) {
            client.publish_string(topic, payload, 1, true);
        }
    }

    /**
     * Generate JSON string from a builder.
     */
    private string generate_json(Json.Builder builder) {
        var gen = new Json.Generator();
        gen.set_root(builder.get_root());
        gen.set_pretty(false);
        return gen.to_data(null);
    }

    /**
     * Sanitize a connection label to be a valid HA node/object ID.
     * Allowed characters: [a-zA-Z0-9_-] per HA spec.
     * Other characters are replaced with underscores.
     */
    private static string sanitize_id(string label) {
        var sb = new StringBuilder();
        for (int i = 0; i < label.length; i++) {
            char c = label[i];
            if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                (c >= '0' && c <= '9') || c == '_' || c == '-') {
                sb.append_c(c);
            } else {
                sb.append_c('_');
            }
        }
        return sb.str.down();
    }
}

}
