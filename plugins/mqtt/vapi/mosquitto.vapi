/*
 * Vala VAPI binding for libmosquitto (Eclipse Mosquitto MQTT client library)
 *
 * Based on mosquitto.h from libmosquitto-dev
 * Install: apt install libmosquitto-dev
 * pkg-config: libmosquitto
 *
 * Reference: https://mosquitto.org/api/files/mosquitto-h.html
 *
 * TODO: This is a minimal binding covering connect/subscribe/publish/disconnect.
 *       Add more functions as needed (will, TLS options, v5 properties, etc.)
 */

[CCode (cheader_filename = "mosquitto.h")]
namespace Mosquitto {

    [CCode (cname = "mosquitto_lib_init")]
    public static int lib_init();

    [CCode (cname = "mosquitto_lib_cleanup")]
    public static int lib_cleanup();

    [Compact]
    [CCode (cname = "struct mosquitto", free_function = "mosquitto_destroy")]
    public class Client {

        [CCode (cname = "mosquitto_new")]
        public Client(string? id, bool clean_session, void* userdata);

        [CCode (cname = "mosquitto_connect")]
        public int connect(string host, int port = 1883, int keepalive = 60);

        [CCode (cname = "mosquitto_disconnect")]
        public int disconnect();

        [CCode (cname = "mosquitto_subscribe")]
        public int subscribe(int* mid, string sub, int qos);

        [CCode (cname = "mosquitto_unsubscribe")]
        public int unsubscribe(int* mid, string sub);

        [CCode (cname = "mosquitto_publish")]
        public int publish(int* mid, string topic,
                           int payloadlen, [CCode (array_length = false)] uint8[] payload,
                           int qos, bool retain);

        [CCode (cname = "mosquitto_socket")]
        public int socket();

        [CCode (cname = "mosquitto_loop_read")]
        public int loop_read(int max_packets = 1);

        [CCode (cname = "mosquitto_loop_write")]
        public int loop_write(int max_packets = 1);

        [CCode (cname = "mosquitto_loop_misc")]
        public int loop_misc();

        [CCode (cname = "mosquitto_loop")]
        public int loop(int timeout = -1, int max_packets = 1);

        [CCode (cname = "mosquitto_loop_start")]
        public int loop_start();

        [CCode (cname = "mosquitto_loop_stop")]
        public int loop_stop(bool force = false);

        [CCode (cname = "mosquitto_username_pw_set")]
        public int username_pw_set(string? username, string? password);

        [CCode (cname = "mosquitto_tls_set")]
        public int tls_set(string? cafile, string? capath,
                           string? certfile, string? keyfile,
                           void* pw_callback = null);

        [CCode (cname = "mosquitto_tls_insecure_set")]
        public int tls_insecure_set(bool value);

        [CCode (cname = "mosquitto_want_write")]
        public bool want_write();

        /* ── Callback setters ─────────────────────────────────── */

        [CCode (cname = "mosquitto_connect_callback_set")]
        public void connect_callback_set(ConnectCallback cb);

        [CCode (cname = "mosquitto_disconnect_callback_set")]
        public void disconnect_callback_set(DisconnectCallback cb);

        [CCode (cname = "mosquitto_message_callback_set")]
        public void message_callback_set(MessageCallback cb);

        [CCode (cname = "mosquitto_subscribe_callback_set")]
        public void subscribe_callback_set(SubscribeCallback cb);
    }

    /* ── Callback delegates ────────────────────────────────────── */

    [CCode (cname = "mosquitto_connect_callback", has_target = false)]
    public delegate void ConnectCallback(Client mosq, void* userdata, int rc);

    [CCode (cname = "mosquitto_disconnect_callback", has_target = false)]
    public delegate void DisconnectCallback(Client mosq, void* userdata, int rc);

    [CCode (cname = "mosquitto_message_callback", has_target = false)]
    public delegate void MessageCallback(Client mosq, void* userdata, Message msg);

    [CCode (cname = "mosquitto_subscribe_callback", has_target = false)]
    public delegate void SubscribeCallback(Client mosq, void* userdata, int mid,
                                            int qos_count,
                                            [CCode (array_length = false)] int[] granted_qos);

    /* ── Message struct ────────────────────────────────────────── */

    [CCode (cname = "struct mosquitto_message", destroy_function = "mosquitto_message_free")]
    public struct Message {
        public int mid;
        public string topic;
        [CCode (array_length_cname = "payloadlen")]
        public uint8[] payload;
        public int payloadlen;
        public int qos;
        public bool retain;
    }

    /* ── Error codes ───────────────────────────────────────────── */

    [CCode (cname = "int", cprefix = "MOSQ_ERR_")]
    public enum Error {
        SUCCESS,
        NOMEM,
        PROTOCOL,
        INVAL,
        NO_CONN,
        CONN_REFUSED,
        NOT_FOUND,
        CONN_LOST,
        TLS,
        PAYLOAD_SIZE,
        NOT_SUPPORTED,
        AUTH,
        ACL_DENIED,
        UNKNOWN,
        ERRNO,
        EAI
    }
}
