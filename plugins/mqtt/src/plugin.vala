/*
 * DinoX MQTT Plugin
 *
 * Copyright (C) 2026 Ralf Peter <dinox@handwerker.jetzt>
 *
 * Connects to any MQTT broker (standalone Mosquitto, HiveMQ, EMQX, …
 * or optionally the same ejabberd/Prosody XMPP server) and provides
 * publish/subscribe functionality for IoT dashboards, bot events,
 * and lightweight notifications.
 *
 * Configuration (Phase 1 — environment variables, until Settings UI):
 *   DINOX_MQTT_HOST   — broker hostname/IP (required for auto-connect)
 *   DINOX_MQTT_PORT   — broker port (default: 1883, or 8883 with TLS)
 *   DINOX_MQTT_TLS    — "1" to enable TLS
 *   DINOX_MQTT_USER   — username (optional)
 *   DINOX_MQTT_PASS   — password (optional)
 *   DINOX_MQTT_TOPICS — comma-separated topic filters to subscribe
 *                       e.g. "home/sensors/#,dinox/bots/#"
 *
 * Requires: libmosquitto-dev
 */

using Dino.Entities;
using Gee;
using Xmpp;

namespace Dino.Plugins.Mqtt {

public class Plugin : RootInterface, Object {

    public Dino.Application app;
    private MqttClient? client = null;
    private bool mqtt_auto_connect = false;

    /* Env-based config (Phase 1) */
    private string? cfg_host = null;
    private int cfg_port = 1883;
    private bool cfg_tls = false;
    private string? cfg_user = null;
    private string? cfg_pass = null;
    private string[] cfg_topics = {};

    /* ── RootInterface ─────────────────────────────────────────────── */

    public void registered(Dino.Application app) {
        this.app = app;

        /* Read config from environment */
        cfg_host = Environment.get_variable("DINOX_MQTT_HOST");
        string? port_s = Environment.get_variable("DINOX_MQTT_PORT");
        if (port_s != null) cfg_port = int.parse(port_s);
        cfg_tls = Environment.get_variable("DINOX_MQTT_TLS") == "1";
        cfg_user = Environment.get_variable("DINOX_MQTT_USER");
        cfg_pass = Environment.get_variable("DINOX_MQTT_PASS");
        string? topics_s = Environment.get_variable("DINOX_MQTT_TOPICS");
        if (topics_s != null) {
            cfg_topics = topics_s.split(",");
        }

        mqtt_auto_connect = (cfg_host != null && cfg_host != "");

        if (mqtt_auto_connect) {
            message("MQTT plugin: auto-connect configured for %s:%d (tls=%s)",
                    cfg_host, cfg_port, cfg_tls.to_string());
        } else {
            message("MQTT plugin: registered (no DINOX_MQTT_HOST set — " +
                    "use mqtt_connect() or set env vars to connect)");
        }

        /* Listen for XMPP connection state changes to sync MQTT lifecycle */
        app.stream_interactor.connection_manager.connection_state_changed.connect(
            on_xmpp_connection_state_changed);
    }

    public void shutdown() {
        if (client != null) {
            client.disconnect_sync();
            client = null;
        }
        message("MQTT plugin: shutdown");
    }

    public void rekey_database(string new_key) throws Error {
        /* No database in this plugin — no-op */
    }

    public void checkpoint_database() {
        /* No database in this plugin — no-op */
    }

    /* ── XMPP ↔ MQTT lifecycle ─────────────────────────────────────── */

    private void on_xmpp_connection_state_changed(Account account,
                                                  ConnectionManager.ConnectionState state) {
        if (state == ConnectionManager.ConnectionState.CONNECTED) {
            /* First XMPP account online → connect MQTT (if configured) */
            if (mqtt_auto_connect && client == null) {
                start_mqtt.begin();
            }
        }
        /* Note: we do NOT disconnect MQTT when XMPP goes offline —
         * MQTT is independent and should stay connected to the broker. */
    }

    private async void start_mqtt() {
        /* Derive host from XMPP account if not explicitly set */
        string host = cfg_host;
        if (host == null || host == "") {
            var accounts = app.stream_interactor.get_accounts();
            if (accounts.size > 0) {
                host = accounts.first().domainpart;
                message("MQTT: No host configured, using XMPP domain '%s'", host);
            } else {
                warning("MQTT: No host and no XMPP accounts — cannot connect");
                return;
            }
        }

        client = new MqttClient();

        /* Wire up signals */
        client.on_connection_changed.connect((connected) => {
            connection_changed(connected);
            if (connected) {
                message("MQTT: Connection established — subscribing to %d topics",
                        cfg_topics.length);
                foreach (string topic in cfg_topics) {
                    string t = topic.strip();
                    if (t != "") {
                        client.subscribe(t);
                    }
                }
            }
        });

        client.on_message.connect((topic, payload) => {
            string payload_str = (string) payload;
            message_received(topic, payload_str);
        });

        bool ok = yield client.connect_async(host, cfg_port, cfg_tls,
                                              cfg_user, cfg_pass);
        if (!ok) {
            warning("MQTT: Auto-connect failed (host=%s port=%d)", host, cfg_port);
            client = null;
        }
    }

    /* ── Public API ────────────────────────────────────────────────── */

    /**
     * Connect to an MQTT broker programmatically.
     * If host is null, the domain of the first XMPP account is used.
     */
    public async bool mqtt_connect(string? host = null, int port = 1883,
                                   bool use_tls = false,
                                   string? username = null,
                                   string? password = null) {
        if (client != null && client.is_connected) {
            warning("MQTT: Already connected");
            return true;
        }

        string broker_host = host;
        if (broker_host == null || broker_host == "") {
            var accounts = app.stream_interactor.get_accounts();
            if (accounts.size > 0) {
                broker_host = accounts.first().domainpart;
            } else {
                warning("MQTT: No host specified and no XMPP accounts available");
                return false;
            }
        }

        if (client == null) {
            client = new MqttClient();
            client.on_connection_changed.connect((connected) => {
                connection_changed(connected);
            });
            client.on_message.connect((topic, payload) => {
                string payload_str = (string) payload;
                message_received(topic, payload_str);
            });
        }

        return yield client.connect_async(broker_host, port, use_tls,
                                           username, password);
    }

    /**
     * Subscribe to an MQTT topic.
     */
    public void subscribe(string topic, int qos = 0) {
        if (client == null || !client.is_connected) {
            warning("MQTT: Cannot subscribe, not connected");
            return;
        }
        client.subscribe(topic, qos);
    }

    /**
     * Publish a UTF-8 string to an MQTT topic.
     */
    public void publish(string topic, string payload, int qos = 0,
                        bool retain = false) {
        if (client == null || !client.is_connected) {
            warning("MQTT: Cannot publish, not connected");
            return;
        }
        client.publish_string(topic, payload, qos, retain);
    }

    /**
     * Disconnect from the MQTT broker.
     */
    public async void mqtt_disconnect() {
        if (client != null) {
            yield client.disconnect_async();
            client = null;
        }
    }

    /* ── Signals ───────────────────────────────────────────────────── */

    /** Emitted when a message is received on a subscribed topic. */
    public signal void message_received(string topic, string payload);

    /** Emitted when the MQTT connection state changes. */
    public signal void connection_changed(bool connected);
}

}
