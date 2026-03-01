/*
 * ejabberd REST API client for dedicated bot account management.
 * Handles registration, deletion, and password changes via admin API.
 */

namespace Dino.Plugins.BotFeatures {

public class EjabberdApi : Object {

    private Soup.Session http;
    private BotRegistry registry;

    // Settings keys
    public const string KEY_API_URL = "ejabberd_api_url";
    public const string KEY_ADMIN_JID = "ejabberd_admin_jid";
    public const string KEY_ADMIN_PASSWORD = "ejabberd_admin_password";
    public const string KEY_HOST = "ejabberd_host";

    public EjabberdApi(BotRegistry registry) {
        this.registry = registry;
        this.http = new Soup.Session();
    }

    public void shutdown() {
        http.abort();
    }

    // Check if ejabberd API is configured
    public bool is_configured() {
        string? url = registry.get_setting(KEY_API_URL);
        string? admin_jid = registry.get_setting(KEY_ADMIN_JID);
        string? admin_pw = registry.get_setting(KEY_ADMIN_PASSWORD);
        string? host = registry.get_setting(KEY_HOST);
        return (url != null && url.strip() != "" &&
                admin_jid != null && admin_jid.strip() != "" &&
                admin_pw != null && admin_pw.strip() != "" &&
                host != null && host.strip() != "");
    }

    // Get the XMPP host domain
    public string get_host() {
        return registry.get_setting(KEY_HOST) ?? "localhost";
    }

    // Test connectivity to ejabberd API (using saved config)
    public async ApiResult test_connection() {
        if (!is_configured()) {
            return ApiResult() { success = false, error_message = "ejabberd API not configured" };
        }
        return yield api_call("status", "{}");
    }

    // Test connectivity with explicit credentials (for test-before-save)
    public async ApiResult test_connection_with_params(string api_url, string host, string admin_jid, string admin_password) {
        if (api_url.strip() == "" || admin_jid.strip() == "" || admin_password.strip() == "" || host.strip() == "") {
            return ApiResult() { success = false, error_message = "Missing required fields" };
        }
        return yield api_call_direct(api_url.strip(), admin_jid.strip(), admin_password.strip(), "status", "{}");
    }

    // Register a new XMPP account on the server
    public async ApiResult register_account(string username, string password) {
        if (!is_configured()) {
            return ApiResult() { success = false, error_message = "ejabberd API not configured" };
        }
        string host = get_host();
        string body = "{\"user\":\"%s\",\"host\":\"%s\",\"password\":\"%s\"}".printf(
            escape_json(username), escape_json(host), escape_json(password));
        return yield api_call("register", body);
    }

    // Delete an XMPP account from the server
    public async ApiResult unregister_account(string username) {
        if (!is_configured()) {
            return ApiResult() { success = false, error_message = "ejabberd API not configured" };
        }
        string host = get_host();
        string body = "{\"user\":\"%s\",\"host\":\"%s\"}".printf(
            escape_json(username), escape_json(host));
        return yield api_call("unregister", body);
    }

    // Change password for an existing account
    public async ApiResult change_password(string username, string new_password) {
        if (!is_configured()) {
            return ApiResult() { success = false, error_message = "ejabberd API not configured" };
        }
        string host = get_host();
        string body = "{\"user\":\"%s\",\"host\":\"%s\",\"newpass\":\"%s\"}".printf(
            escape_json(username), escape_json(host), escape_json(new_password));
        return yield api_call("change_password", body);
    }

    // Check if an account exists on the server
    public async ApiResult check_account(string username) {
        if (!is_configured()) {
            return ApiResult() { success = false, error_message = "ejabberd API not configured" };
        }
        string host = get_host();
        string body = "{\"user\":\"%s\",\"host\":\"%s\"}".printf(
            escape_json(username), escape_json(host));
        return yield api_call("check_account", body);
    }

    // Generate a random password for bot accounts
    public static string generate_bot_password() {
        string chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%&*";
        var sb = new GLib.StringBuilder();
        for (int i = 0; i < 24; i++) {
            int idx = (int) GLib.Random.int_range(0, (int32) chars.length);
            sb.append_c(chars[idx]);
        }
        return sb.str;
    }

    // Delete MAM (Message Archive) messages on the server
    // WARNING: This is a GLOBAL operation - deletes ALL users' MAM archives!
    // ejabberd has no per-user MAM delete via REST API.
    public async ApiResult delete_mam_messages() {
        if (!is_configured()) {
            return ApiResult() { success = false, error_message = "ejabberd API not configured" };
        }
        // delete_old_mam_messages with type=all and days=0 deletes ALL archived messages
        string body = "{\"type\":\"all\",\"days\":0}";
        return yield api_call("delete_old_mam_messages", body);
    }

    // Generate a bot username from the bot name
    public static string generate_bot_username(string bot_name) {
        // Convert to lowercase, replace spaces/special chars with underscore
        string clean = bot_name.down().strip();
        var sb = new GLib.StringBuilder();
        sb.append("bot_");
        int name_chars = 0;
        for (int i = 0; i < clean.length && name_chars < 50; i++) {
            char c = clean[i];
            if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) {
                sb.append_c(c);
                name_chars++;
            } else if (c == ' ' || c == '-' || c == '_') {
                sb.append_c('_');
                name_chars++;
            }
        }
        // Append random suffix to avoid collisions
        sb.append("_%04x".printf((uint) GLib.Random.int_range(0, 0xFFFF)));
        return sb.str;
    }

    // Internal: make an API call to ejabberd using saved settings
    private async ApiResult api_call(string endpoint, string json_body) {
        string? api_url = registry.get_setting(KEY_API_URL);
        string? admin_jid = registry.get_setting(KEY_ADMIN_JID);
        string? admin_pw = registry.get_setting(KEY_ADMIN_PASSWORD);

        if (api_url == null || admin_jid == null || admin_pw == null) {
            return ApiResult() { success = false, error_message = "Missing API configuration" };
        }

        return yield api_call_direct(api_url, admin_jid, admin_pw, endpoint, json_body);
    }

    // Internal: make an API call with explicit credentials
    private async ApiResult api_call_direct(string api_url, string admin_jid, string admin_pw, string endpoint, string json_body) {
        // Ensure URL ends without trailing slash
        string base_url = api_url.strip();
        if (base_url.has_suffix("/")) {
            base_url = base_url.substring(0, base_url.length - 1);
        }

        string url = "%s/%s".printf(base_url, endpoint);

        try {
            var msg = new Soup.Message("POST", url);
            msg.set_request_body_from_bytes("application/json", new GLib.Bytes(json_body.data));

            // Accept self-signed certificates
            msg.accept_certificate.connect((cert, errors) => {
                return true;
            });

            // Set Basic Auth header
            string credentials = "%s:%s".printf(admin_jid.strip(), admin_pw.strip());
            string encoded = GLib.Base64.encode(credentials.data);
            msg.get_request_headers().append("Authorization", "Basic %s".printf(encoded));

            Bytes response = yield http.send_and_read_async(msg, GLib.Priority.DEFAULT, null);
            string response_text = (string) response.get_data();

            if (msg.status_code >= 200 && msg.status_code < 300) {
                return ApiResult() { success = true, response_body = response_text };
            } else {
                return ApiResult() {
                    success = false,
                    status_code = msg.status_code,
                    error_message = "HTTP %u: %s".printf(msg.status_code, response_text),
                    response_body = response_text
                };
            }
        } catch (Error e) {
            return ApiResult() { success = false, error_message = e.message };
        }
    }

    // Delegate to shared BotUtils (clone removal)
    private static string escape_json(string s) {
        return BotUtils.escape_json(s);
    }
}

// Result of an ejabberd API call
public struct ApiResult {
    public bool success;
    public uint status_code;
    public string? error_message;
    public string? response_body;
}

}
