using Gee;

namespace Dino.Plugins.BotFeatures {

/**
 * Telegram Bridge for dedicated bots.
 * Bridges messages between an XMPP bot and a Telegram bot.
 *
 * Settings per bot (in bot_registry):
 *   bot_{id}_tg_enabled    = "true" / "false"
 *   bot_{id}_tg_token      = Telegram Bot API token
 *   bot_{id}_tg_chat_id    = Default Telegram chat ID to bridge to
 *   bot_{id}_tg_mode       = "bridge" (bidirectional) / "forward" (XMPP->TG only)
 */
public class TelegramBridge : Object {

    private BotRegistry registry;
    private Soup.Session http;

    // Per-bot polling state
    private HashMap<int, int64?> poll_offsets;
    private HashMap<int, uint> poll_timers;
    private HashMap<int, string> bot_default_xmpp_jid;

    // Signal: Telegram message received, needs to be sent to XMPP
    public signal void telegram_message_received(int bot_id, string from_name, string text);

    private const int POLL_INTERVAL_MS = 3000;

    public TelegramBridge(BotRegistry registry) {
        this.registry = registry;
        this.http = new Soup.Session();
        this.http.timeout = 35; // Long polling + buffer
        this.poll_offsets = new HashMap<int, int64?>();
        this.poll_timers = new HashMap<int, uint>();
        this.bot_default_xmpp_jid = new HashMap<int, string>();
    }

    // Check if Telegram bridge is enabled for a bot
    public bool is_enabled(int bot_id) {
        string? val = registry.get_setting("bot_%d_tg_enabled".printf(bot_id));
        return val == "true";
    }

    // Configure Telegram bridge
    public void configure(int bot_id, string tg_token, string tg_chat_id, string mode) {
        string prefix = "bot_%d_tg".printf(bot_id);
        registry.set_setting(prefix + "_enabled", "true");
        registry.set_setting(prefix + "_token", tg_token);
        registry.set_setting(prefix + "_chat_id", tg_chat_id);
        registry.set_setting(prefix + "_mode", mode);
        message("Telegram: Configured for bot %d: chat_id=%s mode=%s", bot_id, tg_chat_id, mode);
    }

    // Disable Telegram bridge
    public void disable(int bot_id) {
        registry.set_setting("bot_%d_tg_enabled".printf(bot_id), "false");
        stop_polling(bot_id);
        message("Telegram: Disabled for bot %d", bot_id);
    }

    // Start polling for a bot
    public void start_polling(int bot_id, string default_xmpp_jid) {
        if (poll_timers.has_key(bot_id)) return; // Already polling

        bot_default_xmpp_jid[bot_id] = default_xmpp_jid;
        poll_offsets[bot_id] = 0;

        // Initial poll
        poll_telegram.begin(bot_id);

        // Set up recurring poll
        uint timer_id = Timeout.add(POLL_INTERVAL_MS, () => {
            poll_telegram.begin(bot_id);
            return true; // Continue
        });
        poll_timers[bot_id] = timer_id;
        message("Telegram: Started polling for bot %d", bot_id);
    }

    // Stop polling for a bot
    public void stop_polling(int bot_id) {
        if (poll_timers.has_key(bot_id)) {
            Source.remove(poll_timers[bot_id]);
            poll_timers.unset(bot_id);
        }
        poll_offsets.unset(bot_id);
        bot_default_xmpp_jid.unset(bot_id);
        message("Telegram: Stopped polling for bot %d", bot_id);
    }

    // Forward an XMPP message to Telegram
    public async bool forward_to_telegram(int bot_id, string from_jid, string text) {
        string prefix = "bot_%d_tg".printf(bot_id);
        string? token = registry.get_setting(prefix + "_token");
        string? chat_id = registry.get_setting(prefix + "_chat_id");

        if (token == null || chat_id == null) {
            warning("Telegram: Not configured for bot %d", bot_id);
            return false;
        }

        string tg_text = "[XMPP] %s:\n%s".printf(from_jid, text);
        return yield send_telegram_message(token, chat_id, tg_text);
    }

    // Get status
    public string get_status(int bot_id) {
        string prefix = "bot_%d_tg".printf(bot_id);
        bool enabled = is_enabled(bot_id);
        if (!enabled) {
            return "Telegram: deaktiviert";
        }
        string chat_id = registry.get_setting(prefix + "_chat_id") ?? "?";
        string mode = registry.get_setting(prefix + "_mode") ?? "bridge";
        bool polling = poll_timers.has_key(bot_id);
        return "Telegram: aktiv\nChat-ID: %s\nModus: %s\nPolling: %s".printf(
            chat_id, mode, polling ? "laeuft" : "gestoppt");
    }

    // Poll Telegram for new messages
    private async void poll_telegram(int bot_id) {
        string prefix = "bot_%d_tg".printf(bot_id);
        string? token = registry.get_setting(prefix + "_token");
        if (token == null) return;

        int64 offset = 0;
        if (poll_offsets.has_key(bot_id) && poll_offsets[bot_id] != null) {
            offset = poll_offsets[bot_id];
        }

        string url = "https://api.telegram.org/bot%s/getUpdates?offset=%lld&timeout=1&limit=20".printf(
            token, offset);

        try {
            var request = new Soup.Message("GET", url);
            var response = yield http.send_and_read_async(request, GLib.Priority.DEFAULT, null);
            uint status = request.get_status();

            if (status < 200 || status >= 300) {
                warning("Telegram: Poll HTTP %u for bot %d", status, bot_id);
                return;
            }

            string body = (string) response.get_data();
            var parser = new Json.Parser();
            parser.load_from_data(body, -1);
            var root = parser.get_root().get_object();

            if (!root.get_boolean_member("ok")) return;

            var result = root.get_array_member("result");
            for (uint i = 0; i < result.get_length(); i++) {
                var update = result.get_object_element(i);
                int64 update_id = update.get_int_member("update_id");

                // Update offset
                if (update_id >= offset) {
                    poll_offsets[bot_id] = update_id + 1;
                }

                // Extract message
                if (update.has_member("message")) {
                    var msg = update.get_object_member("message");
                    if (msg.has_member("text")) {
                        string text = msg.get_string_member("text");
                        string from_name = "Telegram";

                        if (msg.has_member("from")) {
                            var from = msg.get_object_member("from");
                            string? first = null;
                            string? last = null;
                            if (from.has_member("first_name"))
                                first = from.get_string_member("first_name");
                            if (from.has_member("last_name"))
                                last = from.get_string_member("last_name");
                            if (first != null) {
                                from_name = first;
                                if (last != null) from_name += " " + last;
                            }
                        }

                        // Emit signal for message router to forward to XMPP
                        telegram_message_received(bot_id, from_name, text);
                    }
                }
            }
        } catch (Error e) {
            warning("Telegram: Poll error for bot %d: %s", bot_id, e.message);
        }
    }

    // Send a message via Telegram Bot API
    private async bool send_telegram_message(string token, string chat_id, string text) {
        string url = "https://api.telegram.org/bot%s/sendMessage".printf(token);

        var sb = new StringBuilder();
        sb.append("{\"chat_id\":\"%s\",\"text\":\"%s\",\"parse_mode\":\"HTML\"}".printf(
            escape_json(chat_id), escape_json(text)));

        try {
            var request = new Soup.Message("POST", url);
            request.set_request_body_from_bytes("application/json",
                new Bytes.take(sb.str.data));

            var response = yield http.send_and_read_async(request, GLib.Priority.DEFAULT, null);
            uint status = request.get_status();

            if (status >= 200 && status < 300) {
                return true;
            }
            string body = (string) response.get_data();
            warning("Telegram: Send failed HTTP %u: %s", status, body);
            return false;
        } catch (Error e) {
            warning("Telegram: Send error: %s", e.message);
            return false;
        }
    }

    // Test the connection (get bot info from Telegram)
    public async string? test_connection(int bot_id) {
        string prefix = "bot_%d_tg".printf(bot_id);
        string? token = registry.get_setting(prefix + "_token");
        if (token == null) return "Telegram nicht konfiguriert.";

        string url = "https://api.telegram.org/bot%s/getMe".printf(token);
        try {
            var request = new Soup.Message("GET", url);
            var response = yield http.send_and_read_async(request, GLib.Priority.DEFAULT, null);
            uint status = request.get_status();

            if (status < 200 || status >= 300) {
                return "Telegram HTTP-Fehler %u".printf(status);
            }

            string body = (string) response.get_data();
            var parser = new Json.Parser();
            parser.load_from_data(body, -1);
            var root = parser.get_root().get_object();

            if (root.get_boolean_member("ok") && root.has_member("result")) {
                var result = root.get_object_member("result");
                string name = result.has_member("first_name") ? result.get_string_member("first_name") : "?";
                string username = result.has_member("username") ? result.get_string_member("username") : "?";
                return "Telegram verbunden!\nBot: %s (@%s)".printf(name, username);
            }
            return "Telegram: Unerwartete Antwort";
        } catch (Error e) {
            return "Telegram-Fehler: %s".printf(e.message);
        }
    }

    // Cleanup all settings for a bot
    public void cleanup(int bot_id) {
        stop_polling(bot_id);
        string prefix = "bot_%d_tg".printf(bot_id);
        registry.delete_setting(prefix + "_enabled");
        registry.delete_setting(prefix + "_token");
        registry.delete_setting(prefix + "_chat_id");
        registry.delete_setting(prefix + "_mode");
    }

    private static string escape_json(string s) {
        return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r");
    }
}

} // namespace
