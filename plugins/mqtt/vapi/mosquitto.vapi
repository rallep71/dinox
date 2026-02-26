/*
 * Vala VAPI binding for libmosquitto (Eclipse Mosquitto MQTT client library)
 *
 * Based on mosquitto.h from libmosquitto-dev
 * Install: apt install libmosquitto-dev
 * pkg-config: libmosquitto
 *
 * Reference: https://mosquitto.org/api/files/mosquitto-h.html
 */

[CCode (cheader_filename = "mosquitto.h,mqtt_protocol.h")]
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

        [CCode (cname = "mosquitto_message_v5_callback_set")]
        public void message_v5_callback_set(MessageV5Callback cb);

        [CCode (cname = "mosquitto_int_option")]
        public int int_option(Option option, int value);
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

    /* ── Options (enum mosq_opt_t from mosquitto.h) ────────────── */

    [CCode (cname = "int", cprefix = "MOSQ_OPT_")]
    public enum Option {
        PROTOCOL_VERSION = 1,
        TCP_NODELAY      = 2,
        RECEIVE_MAXIMUM  = 3,
        SEND_MAXIMUM     = 4
    }

    /* ── MQTT Protocol Versions ────────────────────────────────── */

    [CCode (cname = "MQTT_PROTOCOL_V31")]
    public const int PROTOCOL_V31;

    [CCode (cname = "MQTT_PROTOCOL_V311")]
    public const int PROTOCOL_V311;

    [CCode (cname = "MQTT_PROTOCOL_V5")]
    public const int PROTOCOL_V5;

    /* ── MQTT 5.0 Property Identifiers ─────────────────────────── */

    [CCode (cname = "int", cprefix = "MQTT_PROP_")]
    public enum PropertyId {
        PAYLOAD_FORMAT_INDICATOR    =  1,
        MESSAGE_EXPIRY_INTERVAL     =  2,
        CONTENT_TYPE                =  3,
        RESPONSE_TOPIC              =  8,
        CORRELATION_DATA            =  9,
        SUBSCRIPTION_IDENTIFIER     = 11,
        SESSION_EXPIRY_INTERVAL     = 17,
        ASSIGNED_CLIENT_IDENTIFIER  = 18,
        SERVER_KEEP_ALIVE           = 19,
        AUTHENTICATION_METHOD       = 21,
        AUTHENTICATION_DATA         = 22,
        REQUEST_PROBLEM_INFORMATION = 23,
        WILL_DELAY_INTERVAL         = 24,
        REQUEST_RESPONSE_INFORMATION = 25,
        RESPONSE_INFORMATION        = 26,
        SERVER_REFERENCE            = 28,
        REASON_STRING               = 31,
        RECEIVE_MAXIMUM             = 33,
        TOPIC_ALIAS_MAXIMUM         = 34,
        TOPIC_ALIAS                 = 35,
        MAXIMUM_QOS                 = 36,
        RETAIN_AVAILABLE            = 37,
        USER_PROPERTY               = 38,
        MAXIMUM_PACKET_SIZE         = 39,
        WILDCARD_SUB_AVAILABLE      = 40,
        SUBSCRIPTION_ID_AVAILABLE   = 41,
        SHARED_SUB_AVAILABLE        = 42
    }

    /* ── MQTT 5.0 Property list (opaque pointer) ───────────────── */

    [Compact]
    [CCode (cname = "mosquitto_property", free_function = "")]
    public class Property {
        /* Read a string pair from the property list.
         * Returns a pointer to the next match, or null.
         * Caller must free name and value with GLib.free(). */
        [CCode (cname = "mosquitto_property_read_string_pair")]
        public static unowned Property? read_string_pair(
            Property? proplist, int identifier,
            out string? name, out string? value, bool skip_first);

        /* Read a string from the property list. */
        [CCode (cname = "mosquitto_property_read_string")]
        public static unowned Property? read_string(
            Property? proplist, int identifier,
            out string? value, bool skip_first);
    }

    /* ── MQTT 5.0 Message callback with properties ─────────────── */

    [CCode (cname = "mosquitto_on_message_v5_cb", has_target = false)]
    public delegate void MessageV5Callback(Client mosq, void* userdata,
                                            Message* msg, Property? props);
}
