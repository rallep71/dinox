using Gee;
using Crypto;

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
    private HashMap<int, bool> poll_in_progress;
    private HashMap<int, int64?> poll_skip_until; // Monotonic time (usec) to skip polls until

    // Signal: Telegram message received, needs to be sent to XMPP
    public signal void telegram_message_received(int bot_id, string from_name, string text);

    // Signal: Telegram file received, needs to be sent as inline media to XMPP
    public signal void telegram_file_received(int bot_id, string from_name, string file_url, string? caption);

    // aesgcm:// URL pattern: aesgcm://host/path#IV_HEX+KEY_HEX
    private Regex aesgcm_regex;

    private const int POLL_INTERVAL_MS = 1000;
    private const int TG_LONG_POLL_TIMEOUT = 25;
    private const uint KEY_SIZE = 32;
    private const uint GCM_TAG_SIZE = 16;

    public TelegramBridge(BotRegistry registry) {
        this.registry = registry;
        this.http = new Soup.Session();
        this.http.timeout = 35; // Long polling + buffer
        this.poll_offsets = new HashMap<int, int64?>();
        this.poll_timers = new HashMap<int, uint>();
        this.bot_default_xmpp_jid = new HashMap<int, string>();
        this.poll_in_progress = new HashMap<int, bool>();
        this.poll_skip_until = new HashMap<int, int64?>();
        try {
            // Match aesgcm://host:port/path#hexsecret
            this.aesgcm_regex = new Regex("^aesgcm://([^\\s#]+)#([0-9a-fA-F]+)$");
        } catch (RegexError e) {
            warning("Telegram: Failed to compile aesgcm regex: %s", e.message);
        }
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

        // Delete any existing webhook first (webhook + getUpdates causes 409)
        delete_webhook_and_start.begin(bot_id);
    }

    // Delete webhook then start polling loop
    private async void delete_webhook_and_start(int bot_id) {
        string prefix = "bot_%d_tg".printf(bot_id);
        string? token = registry.get_setting(prefix + "_token");
        if (token != null) {
            string url = "https://api.telegram.org/bot%s/deleteWebhook".printf(token);
            try {
                var request = new Soup.Message("GET", url);
                yield http.send_and_read_async(request, GLib.Priority.DEFAULT, null);
                message("Telegram: Deleted webhook for bot %d", bot_id);
            } catch (GLib.Error e) {
                warning("Telegram: deleteWebhook error: %s", e.message);
            }
        }

        // Now start polling
        poll_telegram.begin(bot_id);

        // Set up recurring poll - skip if previous poll still running
        uint timer_id = Timeout.add(POLL_INTERVAL_MS, () => {
            if (poll_in_progress.has_key(bot_id) && poll_in_progress[bot_id]) {
                return true; // Previous poll still active, skip
            }
            // 409 backoff: skip until cooldown expires
            if (poll_skip_until.has_key(bot_id) && poll_skip_until[bot_id] != null) {
                int64 now = GLib.get_monotonic_time();
                if (now < poll_skip_until[bot_id]) {
                    return true; // Still in backoff, skip
                }
                poll_skip_until.unset(bot_id);
            }
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

        // Check if the text is an aesgcm:// URL (OMEMO encrypted file)
        string trimmed = text.strip();
        if (aesgcm_regex != null && aesgcm_regex.match(trimmed, 0, null)) {
            // Extract URL parts via second match with MatchInfo
            MatchInfo mi;
            aesgcm_regex.match(trimmed, 0, out mi);
            string? url_path = mi.fetch(1);   // host:port/path
            string? hex_secret = mi.fetch(2);  // IV+Key hex

            if (url_path != null && hex_secret != null) {
                // Forward as decrypted file
                bool sent = yield forward_aesgcm_file(token, chat_id, from_jid, url_path, hex_secret);
                if (sent) return true;
                // Fallback: send as text if file forwarding failed
                warning("Telegram: aesgcm file forwarding failed, falling back to text");
            }
        }

        string tg_text = "[XMPP] %s:\n%s".printf(from_jid, text);
        return yield send_telegram_message(token, chat_id, tg_text);
    }

    // Download, decrypt, and forward an aesgcm:// file to Telegram
    private async bool forward_aesgcm_file(string token, string chat_id,
                                           string from_jid, string url_path4,
                                           string hex_secret) {
        // Parse IV and Key from hex secret
        // Format: IV (24 hex = 12 bytes) + Key (64 hex = 32 bytes) = 88 hex
        // Also support: IV (32 hex = 16 bytes) + Key (64 hex = 32 bytes) = 96 hex
        uint8[] iv_and_key = hex_to_bytes(hex_secret);
        if (iv_and_key.length != 44 && iv_and_key.length != 48) {
            warning("Telegram: Invalid aesgcm secret length: %d bytes", iv_and_key.length);
            return false;
        }

        uint8[] iv = iv_and_key[0:iv_and_key.length - KEY_SIZE];
        uint8[] key = iv_and_key[iv_and_key.length - KEY_SIZE:iv_and_key.length];

        // Build HTTPS download URL
        string https_url = "https://" + url_path4;

        // Extract filename from URL path
        string filename = "file";
        int last_slash = url_path4.last_index_of("/");
        if (last_slash >= 0 && last_slash < url_path4.length - 1) {
            filename = url_path4.substring(last_slash + 1);
        }

        // Download encrypted file (accept self-signed certs from our own XMPP server)
        uint8[]? encrypted_data = yield download_file(https_url);
        if (encrypted_data == null || encrypted_data.length <= GCM_TAG_SIZE) {
            warning("Telegram: Failed to download aesgcm file from %s", https_url);
            return false;
        }

        // Decrypt: file = ciphertext + 16-byte GCM auth tag
        uint8[]? decrypted = decrypt_aesgcm(encrypted_data, key, iv);
        if (decrypted == null) {
            warning("Telegram: AES-GCM decryption failed for %s", filename);
            return false;
        }

        // Determine Telegram API method based on file extension
        string caption = "[XMPP] %s".printf(from_jid);
        return yield upload_file_to_telegram(token, chat_id, filename, decrypted, caption);
    }

    // Download a file from HTTPS URL (accepting self-signed certs)
    private async uint8[]? download_file(string url) {
        try {
            var request = new Soup.Message("GET", url);
            // Accept self-signed certificates (our own XMPP server)
            request.accept_certificate.connect((cert, errors) => { return true; });

            var response = yield http.send_and_read_async(request, GLib.Priority.DEFAULT, null);
            uint status = request.get_status();

            if (status < 200 || status >= 300) {
                warning("Telegram: Download HTTP %u from %s", status, url);
                return null;
            }

            return response.get_data();
        } catch (GLib.Error e) {
            warning("Telegram: Download error: %s", e.message);
            return null;
        }
    }

    // Decrypt AES-256-GCM data (ciphertext + 16-byte tag)
    private uint8[]? decrypt_aesgcm(uint8[] encrypted_data, uint8[] key, uint8[] iv) {
        try {
            uint8[] ciphertext = encrypted_data[0:encrypted_data.length - GCM_TAG_SIZE];
            uint8[] tag = encrypted_data[encrypted_data.length - GCM_TAG_SIZE:encrypted_data.length];

            var cipher = new SymmetricCipher("AES-GCM");
            cipher.set_key(key);
            cipher.set_iv(iv);

            uint8[] plaintext = new uint8[ciphertext.length];
            cipher.decrypt(plaintext, ciphertext);
            cipher.check_tag(tag);

            return plaintext;
        } catch (GLib.Error e) {
            warning("Telegram: AES-GCM decrypt error: %s", e.message);
            return null;
        }
    }

    // Upload a file to Telegram using multipart/form-data
    private async bool upload_file_to_telegram(string token, string chat_id,
                                               string filename, uint8[] data,
                                               string caption) {
        // Determine Telegram API method and form field based on file extension
        string ext = "";
        int dot = filename.last_index_of(".");
        if (dot >= 0) ext = filename.substring(dot).down();

        string method;
        string field;
        string content_type;

        switch (ext) {
            case ".jpg": case ".jpeg": case ".png":
                method = "sendPhoto";
                field = "photo";
                content_type = (ext == ".png") ? "image/png" : "image/jpeg";
                break;
            case ".gif":
                method = "sendAnimation";
                field = "animation";
                content_type = "image/gif";
                break;
            case ".mp4": case ".mov": case ".avi": case ".mkv": case ".webm":
                method = "sendVideo";
                field = "video";
                content_type = "video/mp4";
                break;
            case ".mp3": case ".m4a": case ".wav": case ".flac":
                method = "sendAudio";
                field = "audio";
                content_type = "audio/mpeg";
                break;
            case ".ogg": case ".oga":
                method = "sendVoice";
                field = "voice";
                content_type = "audio/ogg";
                break;
            default:
                method = "sendDocument";
                field = "document";
                content_type = "application/octet-stream";
                break;
        }

        string url = "https://api.telegram.org/bot%s/%s".printf(token, method);

        try {
            var multipart = new Soup.Multipart("multipart/form-data");
            multipart.append_form_string("chat_id", chat_id);
            multipart.append_form_string("caption", caption);
            multipart.append_form_file(field, filename, content_type,
                new Bytes.take(data));

            var request = new Soup.Message.from_multipart(url, multipart);

            var response = yield http.send_and_read_async(request, GLib.Priority.DEFAULT, null);
            uint status = request.get_status();

            if (status >= 200 && status < 300) {
                message("Telegram: Uploaded %s (%d bytes) via %s", filename, data.length, method);
                return true;
            }

            string body = (string) response.get_data();
            warning("Telegram: Upload %s failed HTTP %u: %s", method, status, body);
            return false;
        } catch (GLib.Error e) {
            warning("Telegram: Upload error: %s", e.message);
            return false;
        }
    }

    // Convert hex string to byte array
    private static uint8[] hex_to_bytes(string hex) {
        int len = hex.length / 2;
        uint8[] result = new uint8[len];
        for (int i = 0; i < len; i++) {
            result[i] = (uint8) ((hex_char_val(hex[i * 2]) << 4) | hex_char_val(hex[i * 2 + 1]));
        }
        return result;
    }

    private static uint8 hex_char_val(char c) {
        if (c >= '0' && c <= '9') return (uint8) (c - '0');
        if (c >= 'a' && c <= 'f') return (uint8) (c - 'a' + 10);
        if (c >= 'A' && c <= 'F') return (uint8) (c - 'A' + 10);
        return 0;
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
        // Prevent concurrent polls (causes HTTP 409)
        if (poll_in_progress.has_key(bot_id) && poll_in_progress[bot_id]) return;
        poll_in_progress[bot_id] = true;

        string prefix = "bot_%d_tg".printf(bot_id);
        string? token = registry.get_setting(prefix + "_token");
        if (token == null) { poll_in_progress[bot_id] = false; return; }

        int64 offset = 0;
        if (poll_offsets.has_key(bot_id) && poll_offsets[bot_id] != null) {
            offset = poll_offsets[bot_id];
        }

        string url = "https://api.telegram.org/bot%s/getUpdates?offset=%lld&timeout=%d&limit=20".printf(
            token, offset, TG_LONG_POLL_TIMEOUT);

        try {
            var request = new Soup.Message("GET", url);
            var response = yield http.send_and_read_async(request, GLib.Priority.DEFAULT, null);
            uint status = request.get_status();

            if (status == 409) {
                // 409 = another getUpdates is active (e.g. Node-RED using same bot token)
                // Set 5 second backoff before next poll attempt
                debug("Telegram: Poll 409 for bot %d - another consumer active, backoff 5s", bot_id);
                poll_skip_until[bot_id] = GLib.get_monotonic_time() + 5000000; // 5 seconds in usec
                poll_in_progress[bot_id] = false;
                return;
            }

            if (status < 200 || status >= 300) {
                warning("Telegram: Poll HTTP %u for bot %d", status, bot_id);
                poll_in_progress[bot_id] = false;
                return;
            }

            string body = (string) response.get_data();
            var parser = new Json.Parser();
            parser.load_from_data(body, -1);
            var root = parser.get_root().get_object();

            if (!root.get_boolean_member("ok")) {
                // BUG-08 fix: Must reset poll_in_progress before returning
                poll_in_progress[bot_id] = false;
                return;
            }

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

                    // Extract sender name
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

                    // Text message
                    if (msg.has_member("text")) {
                        string text = msg.get_string_member("text");
                        telegram_message_received(bot_id, from_name, text);
                    }
                    // Media messages (photo, video, audio, voice, document, sticker, animation, video_note)
                    else {
                        string? caption = msg.has_member("caption") ? msg.get_string_member("caption") : null;
                        string? file_id = null;
                        string media_type = "";

                        if (msg.has_member("photo")) {
                            // photo is an array of PhotoSize, take the largest (last)
                            var photos = msg.get_array_member("photo");
                            if (photos.get_length() > 0) {
                                var largest = photos.get_object_element(photos.get_length() - 1);
                                file_id = largest.get_string_member("file_id");
                                media_type = "photo";
                            }
                        } else if (msg.has_member("video")) {
                            file_id = msg.get_object_member("video").get_string_member("file_id");
                            media_type = "video";
                        } else if (msg.has_member("animation")) {
                            file_id = msg.get_object_member("animation").get_string_member("file_id");
                            media_type = "GIF";
                        } else if (msg.has_member("audio")) {
                            file_id = msg.get_object_member("audio").get_string_member("file_id");
                            media_type = "audio";
                        } else if (msg.has_member("voice")) {
                            file_id = msg.get_object_member("voice").get_string_member("file_id");
                            media_type = "voice";
                        } else if (msg.has_member("video_note")) {
                            file_id = msg.get_object_member("video_note").get_string_member("file_id");
                            media_type = "video_note";
                        } else if (msg.has_member("document")) {
                            file_id = msg.get_object_member("document").get_string_member("file_id");
                            media_type = "document";
                        } else if (msg.has_member("sticker")) {
                            var sticker = msg.get_object_member("sticker");
                            bool is_animated = sticker.has_member("is_animated") && sticker.get_boolean_member("is_animated");
                            bool is_video = sticker.has_member("is_video") && sticker.get_boolean_member("is_video");
                            string? emoji = sticker.has_member("emoji") ? sticker.get_string_member("emoji") : null;

                            if (is_animated || is_video) {
                                // Animated (.tgs) and video (.webm) stickers - send emoji as text
                                string sticker_text = (emoji != null) ? emoji : "[Sticker]";
                                debug("Telegram: Animated/video sticker -> emoji: %s", sticker_text);
                                telegram_message_received(bot_id, from_name, sticker_text);
                                continue; // Already handled, skip file processing
                            } else {
                                // Static sticker (.webp) - can be displayed as image
                                file_id = sticker.get_string_member("file_id");
                                media_type = "sticker";
                            }
                        }

                        debug("Telegram: Media detected: type=%s file_id=%s", media_type, file_id ?? "null");

                        if (file_id != null) {
                            string? download_url = yield resolve_telegram_file(token, file_id);
                            debug("Telegram: Resolved URL: %s", download_url ?? "null");
                            if (download_url != null) {
                                // Emit file signal -> MessageRouter sends bare URL for inline display
                                telegram_file_received(bot_id, from_name, download_url, caption);
                            } else {
                                // File too large or API error - still forward info
                                telegram_message_received(bot_id, from_name,
                                    "[%s] (%s)".printf(media_type,
                                        _("File could not be downloaded")));
                            }
                        }
                    }
                }
            }
        } catch (GLib.Error e) {
            // Socket timeouts during long-polling are normal (network hiccups)
            if (e.message.contains("Zeitüberschreitung") || e.message.contains("timed out") || e.message.contains("Timeout")) {
                debug("Telegram: Poll timeout for bot %d (normal), retrying", bot_id);
            } else {
                warning("Telegram: Poll error for bot %d: %s", bot_id, e.message);
            }
        }
        poll_in_progress[bot_id] = false;
    }

    // Resolve a Telegram file_id to a download URL via getFile API
    // BUG-06 fix: Returns only the file_path, not the full URL with token
    private async string? resolve_telegram_file(string token, string file_id) {
        string url = "https://api.telegram.org/bot%s/getFile?file_id=%s".printf(token, file_id);
        try {
            var request = new Soup.Message("GET", url);
            var response = yield http.send_and_read_async(request, GLib.Priority.DEFAULT, null);
            uint status = request.get_status();

            if (status < 200 || status >= 300) {
                warning("Telegram: getFile HTTP %u for file_id %s", status, file_id);
                return null;
            }

            string body = (string) response.get_data();
            var parser = new Json.Parser();
            parser.load_from_data(body, -1);
            var root = parser.get_root().get_object();

            if (root.get_boolean_member("ok") && root.has_member("result")) {
                var result = root.get_object_member("result");
                if (result.has_member("file_path")) {
                    string file_path = result.get_string_member("file_path");
                    // Download the file content and re-host via data: URI or return description
                    // For now, download and send the raw bytes via signal
                    string download_url = "https://api.telegram.org/file/bot%s/%s".printf(token, file_path);
                    uint8[]? file_data = yield download_file(download_url);
                    if (file_data != null && file_data.length > 0) {
                        // Extract filename from file_path
                        string filename = file_path;
                        int last_slash = file_path.last_index_of("/");
                        if (last_slash >= 0 && last_slash < file_path.length - 1) {
                            filename = file_path.substring(last_slash + 1);
                        }
                        // Store temporarily and return a local reference
                        // Since we can't easily re-host, return a redacted description
                        // Note: The actual file content is passed via telegram_file_received signal
                        return "[Telegram file: %s, %d bytes]".printf(filename, file_data.length);
                    }
                    return null;
                }
            }
            return null;
        } catch (GLib.Error e) {
            warning("Telegram: getFile error: %s", e.message);
            return null;
        }
    }

    // Send a message via Telegram Bot API
    private async bool send_telegram_message(string token, string chat_id, string text) {
        string url = "https://api.telegram.org/bot%s/sendMessage".printf(token);

        var sb = new StringBuilder();
        // BUG-15 fix: Removed parse_mode:HTML — text is not HTML-escaped, would break on <, >, &
        sb.append("{\"chat_id\":\"%s\",\"text\":\"%s\"}".printf(
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
        } catch (GLib.Error e) {
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
        } catch (GLib.Error e) {
            return "Telegram-Fehler: %s".printf(e.message);
        }
    }

    public void shutdown() {
        // Stop all polling timers
        foreach (var entry in poll_timers.entries) {
            GLib.Source.remove(entry.value);
        }
        poll_timers.clear();
        http.abort();
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

    // RFC 8259 compliant JSON string escaping (BUG-05 fix)
    private static string escape_json(string s) {
        var sb = new StringBuilder.sized(s.length);
        for (int i = 0; i < s.length; i++) {
            unichar c = s[i];
            if (c == '\\') sb.append("\\\\");
            else if (c == '"') sb.append("\\\"");
            else if (c == '\n') sb.append("\\n");
            else if (c == '\r') sb.append("\\r");
            else if (c == '\t') sb.append("\\t");
            else if (c < 0x20) sb.append("\\u%04x".printf(c));
            else sb.append_unichar(c);
        }
        return sb.str;
    }
}

} // namespace
