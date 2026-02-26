/*
 * MqttClient — libmosquitto wrapper with GLib Main Loop integration.
 *
 * Instead of mosquitto_loop_start() (which spawns a thread), we integrate
 * the mosquitto socket into GLib's main loop via IOChannel + Timeout.
 * This keeps everything on the GTK main thread — no locking needed.
 *
 * Flow:
 *   1. mosquitto_connect() runs in a GLib.Thread (blocks for TCP handshake)
 *   2. On success: IOChannel watch on the socket fd for IN/ERR/HUP
 *   3. loop_read()  — processes incoming MQTT packets, fires callbacks
 *   4. loop_write() — flushes outgoing data (triggered when want_write())
 *   5. loop_misc()  — keepalive + housekeeping, every 1 second via Timeout
 *   6. On disconnect: teardown sources, schedule reconnect after 5 seconds
 *
 * Requires: libmosquitto-dev (apt install libmosquitto-dev)
 */

using GLib;

namespace Dino.Plugins.Mqtt {

public class MqttClient : Object {

    public bool is_connected { get; private set; default = false; }

    /** Emitted on incoming message (topic + raw payload bytes). */
    public signal void on_message(string topic, uint8[] payload);

    /** Emitted when MQTT connection state changes. */
    public signal void on_connection_changed(bool connected);

    /* ── Private state ───────────────────────────────────────────── */

    private Mosquitto.Client? mosq = null;
    private GLib.IOChannel? io_channel = null;
    private uint io_watch_id = 0;
    private uint write_watch_id = 0;
    private uint misc_timer_id = 0;
    private uint reconnect_timer_id = 0;

    /* Stored for reconnection */
    private string broker_host = "";
    private int broker_port = 1883;
    private bool broker_use_tls = false;
    private string? broker_username = null;
    private string? broker_password = null;
    private bool initial_connect_done = false;

    /* Topics to re-subscribe after reconnect */
    private Gee.HashMap<string, int> subscribed_topics =
        new Gee.HashMap<string, int>();

    /* Instance registry for C callback dispatch.
     * mosquitto_new() stores a userdata pointer that is passed to every
     * callback.  We pass the instance_id, then look up the MqttClient. */
    private static uint _next_instance_id = 1;
    private static Gee.HashMap<uint, unowned MqttClient>? _instances = null;
    private uint _instance_id = 0;

    private static bool _lib_initialized = false;

    /* ── Construction / Destruction ──────────────────────────────── */

    public MqttClient() {
        if (!_lib_initialized) {
            Mosquitto.lib_init();
            _lib_initialized = true;
        }
        if (_instances == null) {
            _instances = new Gee.HashMap<uint, unowned MqttClient>();
        }
        _instance_id = _next_instance_id++;
        _instances[_instance_id] = this;
    }

    ~MqttClient() {
        disconnect_sync();
        if (_instances != null) {
            _instances.unset(_instance_id);
        }
    }

    /* ── Connect ─────────────────────────────────────────────────── */

    /**
     * Connect to an MQTT broker.
     *
     * The TCP handshake runs in a background thread so the GTK main loop
     * is not blocked. After TCP succeeds, GLib sources are installed and
     * the CONNACK callback sets is_connected = true.
     *
     * Returns true if TCP connect + CONNACK succeeded within the timeout.
     */
    public async bool connect_async(string host, int port = 1883,
                                    bool use_tls = false,
                                    string? username = null,
                                    string? password = null) {
        if (is_connected) {
            message("MQTT: Already connected to %s:%d", broker_host, broker_port);
            return true;
        }

        /* Store for reconnect */
        broker_host = host;
        broker_port = port;
        broker_use_tls = use_tls;
        broker_username = username;
        broker_password = password;

        /* Create mosquitto client — pass instance_id as userdata for
         * C callback dispatch (supports multiple MqttClient instances) */
        string client_id = "dinox-%u-%lld".printf(_instance_id,
                                                   GLib.get_real_time() / 1000);
        mosq = new Mosquitto.Client(client_id, true,
                                     (void*)(ulong)_instance_id);

        if (mosq == null) {
            warning("MQTT: mosquitto_new() failed");
            return false;
        }

        /* Credentials */
        if (username != null && username != "") {
            mosq.username_pw_set(username, password);
        }

        /* TLS — try common CA certificate locations */
        if (use_tls) {
            string? cafile = null;
            string? capath = null;

            if (FileUtils.test("/etc/ssl/certs/ca-certificates.crt", FileTest.EXISTS)) {
                cafile = "/etc/ssl/certs/ca-certificates.crt";
            } else if (FileUtils.test("/etc/ssl/certs/ca-bundle.crt", FileTest.EXISTS)) {
                cafile = "/etc/ssl/certs/ca-bundle.crt";
            } else if (FileUtils.test("/etc/ssl/certs", FileTest.IS_DIR)) {
                capath = "/etc/ssl/certs";
            }

            int tls_rc = mosq.tls_set(cafile, capath, null, null);
            if (tls_rc != Mosquitto.Error.SUCCESS) {
                warning("MQTT: tls_set failed (rc=%d)", tls_rc);
            }
        }

        /* Install C callbacks (dispatch via static _active pointer) */
        mosq.connect_callback_set(on_connect_cb);
        mosq.disconnect_callback_set(on_disconnect_cb);
        mosq.message_callback_set(on_message_cb);

        /* ---------- TCP connect in background thread ---------- */
        int tcp_rc = Mosquitto.Error.UNKNOWN;
        /* capture async resume callback */
        SourceFunc resume = connect_async.callback;

        new Thread<void*>("mqtt-connect", () => {
            tcp_rc = mosq.connect(host, port, 60);
            Idle.add((owned) resume);
            return null;
        });
        yield;   /* resume when thread finishes */

        if (tcp_rc != Mosquitto.Error.SUCCESS) {
            warning("MQTT: TCP connect to %s:%d failed (rc=%d: %s)",
                    host, port, tcp_rc, rc_to_string(tcp_rc));
            mosq = null;
            return false;
        }

        initial_connect_done = true;

        /* TCP connected — install GLib main loop sources */
        setup_glib_sources();

        message("MQTT: TCP connected to %s:%d, waiting for CONNACK…", host, port);

        /* Wait for CONNACK (on_connect_cb stores result and resumes us) */
        int connack_rc = -1;
        connack_resume = connect_async.callback;

        /* Timeout: give broker 10 s to respond */
        uint timeout_id = Timeout.add_seconds(10, () => {
            connack_rc = -1;    /* timeout */
            if (connack_resume != null) {
                Idle.add((owned) connack_resume);
                connack_resume = null;
            }
            return false;
        });

        yield;   /* resume on CONNACK or timeout */

        /* If CONNACK arrived, connack_rc was written by handle_connect */
        connack_rc = connack_result;
        Source.remove(timeout_id);
        connack_resume = null;

        if (connack_rc != 0) {
            warning("MQTT: CONNACK refused (rc=%d: %s)",
                    connack_rc, connack_rc_to_string(connack_rc));
            teardown_glib_sources();
            mosq.disconnect();
            mosq = null;
            initial_connect_done = false;
            return false;
        }

        message("MQTT: Connected to %s:%d ✔", host, port);
        return true;
    }

    /* Used to resume connect_async from the CONNACK callback */
    private SourceFunc? connack_resume = null;
    private int connack_result = -1;

    /* ── GLib Main Loop Integration ──────────────────────────────── */

    private void setup_glib_sources() {
        int fd = mosq.socket();
        if (fd < 0) {
            warning("MQTT: mosquitto_socket() returned %d", fd);
            return;
        }

        io_channel = new IOChannel.unix_new(fd);
        try {
            io_channel.set_encoding(null);
        } catch (IOChannelError e) {
            warning("MQTT: set_encoding failed: %s", e.message);
        }
        io_channel.set_buffered(false);

        /* Persistent read watch */
        io_watch_id = io_channel.add_watch(
            IOCondition.IN | IOCondition.ERR | IOCondition.HUP,
            on_io_readable);

        /* Periodic housekeeping (keepalive, ping, retry) */
        misc_timer_id = Timeout.add_seconds(1, on_misc_timer);
    }

    private void teardown_glib_sources() {
        if (io_watch_id  != 0) { Source.remove(io_watch_id);  io_watch_id  = 0; }
        if (write_watch_id != 0) { Source.remove(write_watch_id); write_watch_id = 0; }
        if (misc_timer_id != 0) { Source.remove(misc_timer_id); misc_timer_id = 0; }
        if (reconnect_timer_id != 0) { Source.remove(reconnect_timer_id); reconnect_timer_id = 0; }
        io_channel = null;
    }

    /* ── IO callbacks ────────────────────────────────────────────── */

    private bool on_io_readable(IOChannel source, IOCondition cond) {
        if (mosq == null) return false;

        if ((cond & IOCondition.ERR) != 0 || (cond & IOCondition.HUP) != 0) {
            warning("MQTT: Socket error/hangup");
            handle_disconnect_event(Mosquitto.Error.CONN_LOST);
            return false;    /* remove this watch */
        }

        int rc = mosq.loop_read(1);
        if (rc != Mosquitto.Error.SUCCESS) {
            warning("MQTT: loop_read failed (rc=%d: %s)", rc, rc_to_string(rc));
            handle_disconnect_event(rc);
            return false;
        }

        /* Flush outgoing data if the library buffered a response */
        schedule_write_if_needed();

        return true;    /* keep watching */
    }

    private bool on_io_writable(IOChannel source, IOCondition cond) {
        if (mosq == null) return false;

        int rc = mosq.loop_write(1);
        if (rc != Mosquitto.Error.SUCCESS) {
            warning("MQTT: loop_write failed (rc=%d)", rc);
        }

        write_watch_id = 0;
        return false;    /* one-shot: remove write watch */
    }

    private bool on_misc_timer() {
        if (mosq == null) return false;

        int rc = mosq.loop_misc();
        if (rc != Mosquitto.Error.SUCCESS) {
            if (rc == Mosquitto.Error.NO_CONN || rc == Mosquitto.Error.CONN_LOST) {
                handle_disconnect_event(rc);
                return false;
            }
        }

        schedule_write_if_needed();
        return true;    /* keep timer */
    }

    private void schedule_write_if_needed() {
        if (mosq != null && mosq.want_write() &&
            write_watch_id == 0 && io_channel != null) {
            write_watch_id = io_channel.add_watch(
                IOCondition.OUT, on_io_writable);
        }
    }

    /* ── Mosquitto C callbacks (static → dispatch via instance registry) ── */

    private static unowned MqttClient? lookup(void* userdata) {
        uint id = (uint)(ulong)userdata;
        if (_instances != null && _instances.has_key(id)) {
            return _instances[id];
        }
        return null;
    }

    private static void on_connect_cb(Mosquitto.Client mosq,
                                      void* userdata, int rc) {
        unowned MqttClient? self = lookup(userdata);
        if (self != null) self.handle_connect(rc);
    }

    private static void on_disconnect_cb(Mosquitto.Client mosq,
                                         void* userdata, int rc) {
        unowned MqttClient? self = lookup(userdata);
        if (self != null) self.handle_disconnect_event(rc);
    }

    private static void on_message_cb(Mosquitto.Client mosq,
                                      void* userdata, Mosquitto.Message* msg) {
        unowned MqttClient? self = lookup(userdata);
        if (self != null) self.handle_message(msg);
    }

    /* ── Instance event handlers ─────────────────────────────────── */

    private void handle_connect(int rc) {
        connack_result = rc;

        if (rc == 0) {
            is_connected = true;
            on_connection_changed(true);
            message("MQTT: CONNACK success");

            /* Re-subscribe topics (after reconnect) */
            foreach (var entry in subscribed_topics.entries) {
                mosq.subscribe(null, entry.key, entry.value);
                message("MQTT: Re-subscribed to '%s' (qos=%d)", entry.key, entry.value);
            }
        } else {
            warning("MQTT: CONNACK refused (rc=%d: %s)",
                    rc, connack_rc_to_string(rc));
            is_connected = false;
            on_connection_changed(false);
        }

        /* Resume connect_async if it's waiting */
        if (connack_resume != null) {
            Idle.add((owned) connack_resume);
            connack_resume = null;
        }
    }

    private void handle_disconnect_event(int rc) {
        bool was_connected = is_connected;
        is_connected = false;

        teardown_glib_sources();

        if (was_connected) {
            on_connection_changed(false);
            warning("MQTT: Connection lost (rc=%d: %s), reconnecting in 5 s…",
                    rc, rc_to_string(rc));
            schedule_reconnect();
        }
    }

    private void handle_message(Mosquitto.Message* msg) {
        /* Copy topic and payload — they're only valid during this callback */
        string topic = msg->topic;

        uint8[] payload = new uint8[msg->payloadlen];
        if (msg->payloadlen > 0 && msg->payload != null) {
            GLib.Memory.move(payload, msg->payload, msg->payloadlen);
        }

        on_message(topic, payload);
    }

    /* ── Reconnection ────────────────────────────────────────────── */

    private void schedule_reconnect() {
        if (reconnect_timer_id != 0) return;
        if (!initial_connect_done) return;    /* first connect never succeeded */

        reconnect_timer_id = Timeout.add_seconds(5, () => {
            reconnect_timer_id = 0;
            attempt_reconnect.begin();
            return false;
        });
    }

    private async void attempt_reconnect() {
        if (mosq == null || is_connected) return;

        message("MQTT: Reconnecting to %s:%d…", broker_host, broker_port);

        int rc = Mosquitto.Error.UNKNOWN;
        SourceFunc resume = attempt_reconnect.callback;

        new Thread<void*>("mqtt-reconnect", () => {
            rc = mosq.reconnect();
            Idle.add((owned) resume);
            return null;
        });
        yield;

        if (rc == Mosquitto.Error.SUCCESS) {
            setup_glib_sources();
            message("MQTT: Reconnect TCP OK, waiting for CONNACK…");
            /* handle_connect will fire from on_connect_cb via loop_read */
        } else {
            warning("MQTT: Reconnect failed (rc=%d), retrying…", rc);
            schedule_reconnect();
        }
    }

    /* ── Public API ──────────────────────────────────────────────── */

    /**
     * Subscribe to an MQTT topic filter.
     * Supports wildcards: + (single level), # (multi level).
     */
    public void subscribe(string topic, int qos = 0) {
        subscribed_topics[topic] = qos;  /* remember for reconnect */

        if (mosq == null || !is_connected) return;

        int rc = mosq.subscribe(null, topic, qos);
        if (rc != Mosquitto.Error.SUCCESS) {
            warning("MQTT: subscribe('%s') failed (rc=%d)", topic, rc);
        } else {
            message("MQTT: Subscribed to '%s' (qos=%d)", topic, qos);
        }

        schedule_write_if_needed();
    }

    /**
     * Unsubscribe from an MQTT topic filter.
     */
    public void unsubscribe(string topic) {
        subscribed_topics.unset(topic);

        if (mosq == null || !is_connected) return;
        mosq.unsubscribe(null, topic);
        schedule_write_if_needed();
    }

    /**
     * Publish raw bytes to an MQTT topic.
     */
    public void publish(string topic, uint8[] payload,
                        int qos = 0, bool retain = false) {
        if (mosq == null || !is_connected) return;

        int rc = mosq.publish(null, topic, payload.length, payload, qos, retain);
        if (rc != Mosquitto.Error.SUCCESS) {
            warning("MQTT: publish('%s') failed (rc=%d)", topic, rc);
        }

        schedule_write_if_needed();
    }

    /**
     * Publish a UTF-8 string to an MQTT topic (convenience wrapper).
     */
    public void publish_string(string topic, string payload,
                               int qos = 0, bool retain = false) {
        publish(topic, payload.data, qos, retain);
    }

    /**
     * Disconnect gracefully (async-safe).
     */
    public async void disconnect_async() {
        disconnect_sync();
    }

    /**
     * Disconnect immediately (safe to call from any context).
     */
    public void disconnect_sync() {
        if (mosq == null) return;

        teardown_glib_sources();

        bool was_connected = is_connected;
        is_connected = false;
        initial_connect_done = false;

        mosq.disconnect();
        mosq = null;

        if (was_connected) {
            on_connection_changed(false);
        }

        message("MQTT: Disconnected");
    }

    /* ── Helpers ──────────────────────────────────────────────────── */

    /** Human-readable MOSQ_ERR_* code. */
    private static string rc_to_string(int rc) {
        switch (rc) {
            case Mosquitto.Error.SUCCESS:       return "SUCCESS";
            case Mosquitto.Error.NOMEM:         return "NOMEM";
            case Mosquitto.Error.PROTOCOL:      return "PROTOCOL";
            case Mosquitto.Error.INVAL:         return "INVAL";
            case Mosquitto.Error.NO_CONN:       return "NO_CONN";
            case Mosquitto.Error.CONN_REFUSED:  return "CONN_REFUSED";
            case Mosquitto.Error.NOT_FOUND:     return "NOT_FOUND";
            case Mosquitto.Error.CONN_LOST:     return "CONN_LOST";
            case Mosquitto.Error.TLS:           return "TLS";
            case Mosquitto.Error.AUTH:          return "AUTH";
            case Mosquitto.Error.ERRNO:         return "ERRNO";
            case Mosquitto.Error.EAI:           return "EAI (DNS)";
            default:                            return "UNKNOWN(%d)".printf(rc);
        }
    }

    /** Human-readable CONNACK return code. */
    private static string connack_rc_to_string(int rc) {
        switch (rc) {
            case 0: return "Accepted";
            case 1: return "Refused: wrong protocol version";
            case 2: return "Refused: identifier rejected";
            case 3: return "Refused: server unavailable";
            case 4: return "Refused: bad username/password";
            case 5: return "Refused: not authorized";
            default: return "Unknown CONNACK rc=%d".printf(rc);
        }
    }
}

}
