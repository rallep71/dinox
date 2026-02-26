/*
 * DinoX MQTT Plugin
 *
 * Copyright (C) 2026 Ralf Peter <dinox@handwerker.jetzt>
 *
 * Connects to an MQTT broker (typically the same ejabberd instance)
 * and provides publish/subscribe functionality for IoT, bot events,
 * and lightweight notifications.
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
    private bool enabled = false;

    /* ── RootInterface ─────────────────────────────────────────────── */

    public void registered(Dino.Application app) {
        this.app = app;
        message("MQTT plugin registered (not yet enabled)");

        // TODO: Read settings, auto-connect if mqtt_enabled == true
        // TODO: Listen for XMPP connection state to sync MQTT lifecycle
    }

    public void shutdown() {
        if (client != null) {
            client.disconnect_async.begin();
            client = null;
        }
        enabled = false;
        message("MQTT plugin shutdown");
    }

    public void rekey_database(string new_key) throws Error {
        // No database in this plugin — no-op
    }

    public void checkpoint_database() {
        // No database in this plugin — no-op
    }

    /* ── Public API ────────────────────────────────────────────────── */

    /**
     * Connect to MQTT broker.
     * If host is null, uses the same host as the first XMPP account.
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
            // Derive from first XMPP account
            var accounts = app.stream_interactor.get_accounts();
            if (accounts.size > 0) {
                broker_host = accounts.first().domainpart;
            } else {
                warning("MQTT: No host specified and no XMPP accounts available");
                return false;
            }
        }

        client = new MqttClient();
        bool ok = yield client.connect_async(broker_host, port, use_tls,
                                               username, password);
        if (ok) {
            enabled = true;
            message("MQTT: Connected to %s:%d", broker_host, port);
        } else {
            warning("MQTT: Connection failed to %s:%d", broker_host, port);
            client = null;
        }
        return ok;
    }

    /**
     * Subscribe to an MQTT topic.
     * Callback receives (topic, payload) for each message.
     */
    public void subscribe(string topic, int qos = 0) {
        if (client == null || !client.is_connected) {
            warning("MQTT: Cannot subscribe, not connected");
            return;
        }
        client.subscribe(topic, qos);
    }

    /**
     * Publish a message to an MQTT topic.
     */
    public void publish(string topic, string payload, int qos = 0,
                         bool retain = false) {
        if (client == null || !client.is_connected) {
            warning("MQTT: Cannot publish, not connected");
            return;
        }
        client.publish(topic, payload, qos, retain);
    }

    /* ── Signals ───────────────────────────────────────────────────── */

    /** Emitted when a message is received on a subscribed topic. */
    public signal void message_received(string topic, string payload);

    /** Emitted when the MQTT connection state changes. */
    public signal void connection_changed(bool connected);
}

}
