/*
 * Vala VAPI binding for libmosquitto (Eclipse Mosquitto MQTT client library)
 *
 * Based on mosquitto.h from libmosquitto-dev
 * Install: apt install libmosquitto-dev
 * pkg-config: libmosquitto
 *
 * Reference: https://mosquitto.org/api/files/mosquitto-h.html
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

        [CCode (cname = "mosquitto_reconnect")]
        public int reconnect();

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

        /* loop_misc has no parameters besides the client pointer */
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
    /* has_target = false: plain C function pointers, userdata via mosquitto_new() */

    [CCode (cname = "mosquitto_on_connect_cb", has_target = false)]
    public delegate void ConnectCallback(Client mosq, void* userdata, int rc);

    [CCode (cname = "mosquitto_on_disconnect_cb", has_target = false)]
    public delegate void DisconnectCallback(Client mosq, void* userdata, int rc);

    [CCode (cname = "mosquitto_on_message_cb", has_target = false)]
    public delegate void MessageCallback(Client mosq, void* userdata, Message* msg);

    [CCode (cname = "mosquitto_on_subscribe_cb", has_target = false)]
    public delegate void SubscribeCallback(Client mosq, void* userdata, int mid,
                                            int qos_count,
                                            [CCode (array_length = false)] int[] granted_qos);

    /* ── Message struct ────────────────────────────────────────── */
    /* No destroy_function — mosquitto manages message lifetime in callbacks.
     * Use void* for payload and unowned string for topic to avoid
     * Vala ownership issues with the C struct we don't own. */

    [CCode (cname = "struct mosquitto_message")]
    public struct Message {
        public int mid;
        public unowned string topic;
        public void* payload;
        public int payloadlen;
        public int qos;
        public bool retain;
    }

    /* ── Error codes (enum mosq_err_t from mosquitto.h) ────────── */

    [CCode (cname = "int", cprefix = "MOSQ_ERR_")]
    public enum Error {
        CONN_PENDING  = -1,
        SUCCESS       =  0,
        NOMEM         =  1,
        PROTOCOL      =  2,
        INVAL         =  3,
        NO_CONN       =  4,
        CONN_REFUSED  =  5,
        NOT_FOUND     =  6,
        CONN_LOST     =  7,
        TLS           =  8,
        PAYLOAD_SIZE  =  9,
        NOT_SUPPORTED = 10,
        AUTH          = 11,
        ACL_DENIED    = 12,
        UNKNOWN       = 13,
        ERRNO         = 14,
        EAI           = 15,
        PROXY         = 16
    }
}
