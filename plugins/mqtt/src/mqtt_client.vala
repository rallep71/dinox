/*
 * MqttClient — Wrapper around libmosquitto for GLib Main Loop integration.
 *
 * Instead of using mosquitto_loop_start() (which spawns a thread),
 * we integrate the mosquitto socket into GLib's main loop using GSource.
 * This avoids threading issues with GTK4.
 *
 * Requires: libmosquitto-dev (apt install libmosquitto-dev)
 */

using GLib;

namespace Dino.Plugins.Mqtt {

public class MqttClient : Object {

    public bool is_connected { get; private set; default = false; }

    /** Emitted on incoming message. */
    public signal void on_message(string topic, uint8[] payload);

    /** Emitted when connection state changes. */
    public signal void on_connection_changed(bool connected);

    // TODO: Replace these stubs with actual libmosquitto calls
    // once the mosquitto.vapi binding is written.

    // private Mosquitto.Client? mosq = null;
    // private uint io_source_id = 0;
    // private uint misc_timer_id = 0;

    public MqttClient() {
        // Mosquitto.lib_init();  // call once globally
    }

    ~MqttClient() {
        disconnect_sync();
        // Mosquitto.lib_cleanup();
    }

    /**
     * Connect to the MQTT broker asynchronously.
     *
     * Returns true if the connection succeeds.
     */
    public async bool connect_async(string host, int port = 1883,
                                      bool use_tls = false,
                                      string? username = null,
                                      string? password = null) {

        // ── Stub implementation ──────────────────────────────────
        // Real implementation will:
        // 1. mosq = new Mosquitto.Client(client_id, clean_session, userdata)
        // 2. mosq.username_pw_set(username, password)
        // 3. if (use_tls) mosq.tls_set(...)
        // 4. mosq.connect_callback_set(on_connect_cb)
        // 5. mosq.message_callback_set(on_message_cb)
        // 6. mosq.disconnect_callback_set(on_disconnect_cb)
        // 7. int rc = mosq.connect(host, port, keepalive: 60)
        // 8. Setup GLib.IOChannel on mosq.socket() for read/write events
        // 9. Setup GLib.Timeout for mosquitto_loop_misc() every 1s

        message("MQTT stub: connect_async(%s, %d, tls=%s, user=%s)",
                host, port, use_tls.to_string(),
                username ?? "(xmpp-credentials)");

        // Simulate async delay
        Idle.add(connect_async.callback);
        yield;

        // Stub: always fails until real implementation
        warning("MQTT: libmosquitto bindings not yet implemented");
        return false;
    }

    /**
     * Subscribe to an MQTT topic filter.
     * topic can include wildcards: + (single level), # (multi level)
     */
    public void subscribe(string topic, int qos = 0) {
        if (!is_connected) return;
        // mosq.subscribe(null, topic, qos);
        message("MQTT stub: subscribe('%s', qos=%d)", topic, qos);
    }

    /**
     * Unsubscribe from an MQTT topic filter.
     */
    public void unsubscribe(string topic) {
        if (!is_connected) return;
        // mosq.unsubscribe(null, topic);
        message("MQTT stub: unsubscribe('%s')", topic);
    }

    /**
     * Publish a message to an MQTT topic.
     */
    public void publish(string topic, string payload, int qos = 0,
                         bool retain = false) {
        if (!is_connected) return;
        // mosq.publish(null, topic, payload.data, qos, retain);
        message("MQTT stub: publish('%s', '%s', qos=%d, retain=%s)",
                topic, payload, qos, retain.to_string());
    }

    /**
     * Disconnect from the MQTT broker (async-safe).
     */
    public async void disconnect_async() {
        disconnect_sync();
        Idle.add(disconnect_async.callback);
        yield;
    }

    private void disconnect_sync() {
        if (!is_connected) return;

        // // Remove GLib sources
        // if (io_source_id != 0) { GLib.Source.remove(io_source_id); io_source_id = 0; }
        // if (misc_timer_id != 0) { GLib.Source.remove(misc_timer_id); misc_timer_id = 0; }
        //
        // mosq.disconnect();
        // mosq.destroy();
        // mosq = null;

        is_connected = false;
        on_connection_changed(false);
        message("MQTT stub: disconnected");
    }

    /* ── GLib Main Loop Integration (to be implemented) ──────── */

    // The idea:
    // 1. After mosquitto_connect(), get the socket fd via mosquitto_socket()
    // 2. Create a GLib.IOChannel on that fd
    // 3. Add GLib.io_add_watch() for IN/OUT/ERR conditions
    // 4. In the callback:
    //    - On G_IO_IN: call mosquitto_loop_read()
    //    - On G_IO_OUT: call mosquitto_loop_write()
    //    - On G_IO_ERR: handle reconnection
    // 5. Add GLib.Timeout.add_seconds(1, () => mosquitto_loop_misc())
    //    for keepalive and housekeeping
    //
    // This avoids mosquitto_loop_start() which creates a background thread.
}

}
