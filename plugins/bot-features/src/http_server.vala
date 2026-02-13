using Gee;

namespace Dino.Plugins.BotFeatures {

public class HttpServer : Object {

    private Soup.Server? server;
    private BotRegistry registry;
    private TokenManager token_manager;
    private MessageRouter message_router;
    private SessionPool session_pool;
    private AuthMiddleware auth;
    private RateLimiter rate_limiter;
    private bool running = false;

    public HttpServer(BotRegistry registry, TokenManager token_manager,
                      MessageRouter message_router, SessionPool session_pool) {
        this.registry = registry;
        this.token_manager = token_manager;
        this.message_router = message_router;
        this.session_pool = session_pool;
        this.rate_limiter = new RateLimiter(30, 1);
        this.auth = new AuthMiddleware(token_manager, rate_limiter);
    }

    public void start(uint16 port) throws Error {
        server = new Soup.Server(null);

        // Register all API routes
        server.add_handler("/bot/getMe", handle_get_me);
        server.add_handler("/bot/sendMessage", handle_send_message);
        server.add_handler("/bot/getUpdates", handle_get_updates);
        server.add_handler("/bot/setWebhook", handle_set_webhook);
        server.add_handler("/bot/deleteWebhook", handle_delete_webhook);
        server.add_handler("/bot/sendFile", handle_send_file);
        server.add_handler("/bot/setCommands", handle_set_commands);
        server.add_handler("/bot/getCommands", handle_get_commands);
        server.add_handler("/bot/joinRoom", handle_join_room);
        server.add_handler("/bot/leaveRoom", handle_leave_room);
        server.add_handler("/bot/sendReaction", handle_send_reaction);
        server.add_handler("/bot/getInfo", handle_get_info);
        server.add_handler("/bot/create", handle_create_bot);
        server.add_handler("/bot/list", handle_list_bots);
        server.add_handler("/bot/delete", handle_delete_bot);
        server.add_handler("/bot/account/status", handle_account_status);
        server.add_handler("/health", handle_health);

        // Listen on localhost only (security: no external access)
        server.listen_local(port, Soup.ServerListenOptions.IPV4_ONLY);
        running = true;
    }

    public void stop() {
        if (server != null && running) {
            server.disconnect();
            running = false;
        }
    }

    // --- POST /bot/create --- (no token needed, localhost only)
    private void handle_create_bot(Soup.Server srv, Soup.ServerMessage msg,
                                   string path, HashTable<string, string>? query) {
        if (msg.get_method() != "POST") {
            AuthMiddleware.send_error(msg, 405, "method_not_allowed", "Use POST");
            return;
        }

        var body = get_request_body(msg);
        if (body == null) {
            AuthMiddleware.send_error(msg, 400, "bad_request", "Invalid JSON body. Example: {\"name\":\"MeinBot\",\"account\":\"user@server.tld\"}");
            return;
        }

        string? name = json_get_string(body, "name");
        // Accept both "account" (UI) and "owner" (legacy) fields
        string? owner = json_get_string(body, "account");
        if (owner == null) owner = json_get_string(body, "owner");
        string? mode = json_get_string(body, "mode");
        if (mode == null) mode = "personal";

        if (name == null || name.strip().length == 0) {
            AuthMiddleware.send_error(msg, 400, "bad_request", "Missing required field: name");
            return;
        }
        if (owner == null || owner.strip().length == 0) {
            AuthMiddleware.send_error(msg, 400, "bad_request", "Missing required field: account (your JID)");
            return;
        }

        // Validate mode
        if (mode != "personal" && mode != "dedicated" && mode != "cloud") {
            AuthMiddleware.send_error(msg, 400, "bad_request", "Invalid mode. Must be: personal, dedicated, or cloud");
            return;
        }

        // Check bot limit per owner
        var existing = registry.get_bots_by_owner(owner);
        if (existing.size >= 20) {
            AuthMiddleware.send_error(msg, 429, "limit_reached", "Maximum 20 bots per owner");
            return;
        }

        int bot_id = registry.create_bot(name.strip(), owner.strip(), "", mode);
        string raw_token = token_manager.generate_token(bot_id);
        registry.log_action(bot_id, "created", "owner=%s mode=%s via=http".printf(owner, mode));

        string json = "{\"id\":%d,\"name\":\"%s\",\"token\":\"%s\",\"mode\":\"%s\",\"api_url\":\"http://localhost:7842/bot/\",\"hint\":\"Use token as Bearer in Authorization header\"}".printf(
            bot_id, escape_json(name.strip()), escape_json(raw_token), escape_json(mode));
        AuthMiddleware.send_success(msg, json);
    }

    // --- GET /bot/list --- (no token needed, localhost only)
    private void handle_list_bots(Soup.Server srv, Soup.ServerMessage msg,
                                  string path, HashTable<string, string>? query) {
        // Optional filter by account
        string? account_filter = null;
        if (query != null && query.contains("account")) {
            account_filter = query.get("account");
        }

        var bots = registry.get_all_bots();
        var sb = new StringBuilder("{\"bots\":[");
        bool first = true;
        foreach (BotInfo bot in bots) {
            // Filter by account if specified
            if (account_filter != null && bot.owner_jid != account_filter) continue;
            if (!first) sb.append(",");
            sb.append(bot_to_json(bot));
            first = false;
        }
        sb.append("]}");
        msg.set_status(200, null);
        msg.set_response("application/json", Soup.MemoryUse.COPY, sb.str.data);
    }

    // --- POST or DELETE /bot/delete --- (no token needed, localhost only)
    private void handle_delete_bot(Soup.Server srv, Soup.ServerMessage msg,
                                   string path, HashTable<string, string>? query) {
        string method = msg.get_method();
        int bot_id = -1;

        if (method == "DELETE" && query != null && query.contains("id")) {
            // DELETE /bot/delete?id=123
            bot_id = int.parse(query.get("id"));
        } else if (method == "POST") {
            // POST /bot/delete with JSON body {"id":123}
            var body = get_request_body(msg);
            if (body == null || !body.has_member("id")) {
                AuthMiddleware.send_error(msg, 400, "bad_request", "Missing required field: id");
                return;
            }
            bot_id = (int) body.get_int_member("id");
        } else {
            AuthMiddleware.send_error(msg, 405, "method_not_allowed", "Use POST or DELETE");
            return;
        }

        if (bot_id <= 0) {
            AuthMiddleware.send_error(msg, 400, "bad_request", "Invalid bot id");
            return;
        }

        BotInfo? bot = registry.get_bot_by_id(bot_id);
        if (bot == null) {
            AuthMiddleware.send_error(msg, 404, "not_found", "Botmother not found");
            return;
        }
        registry.delete_bot(bot_id);
        registry.log_action(bot_id, "deleted", "via=http");
        AuthMiddleware.send_success(msg, "{\"deleted\":true,\"id\":%d}".printf(bot_id));
    }

    // --- GET/POST /bot/account/status ---
    // GET: returns {"account":"jid","enabled":true/false}
    // POST: {"account":"jid","enabled":true/false} -> sets the per-account toggle
    private void handle_account_status(Soup.Server srv, Soup.ServerMessage msg,
                                       string path, HashTable<string, string>? query) {
        string method = msg.get_method();

        if (method == "GET") {
            string? account = query != null ? query.lookup("account") : null;
            if (account == null || account.strip().length == 0) {
                AuthMiddleware.send_error(msg, 400, "bad_request", "Missing ?account= parameter");
                return;
            }
            string key = "botmother_account_enabled:" + account.strip();
            string? val = registry.get_setting(key);
            bool is_enabled = (val == null || val == "true"); // default: enabled
            string json = "{\"account\":\"%s\",\"enabled\":%s}".printf(
                account.strip(), is_enabled ? "true" : "false");
            AuthMiddleware.send_success(msg, json);
            return;
        }

        if (method == "POST") {
            var body = get_request_body(msg);
            if (body == null) {
                AuthMiddleware.send_error(msg, 400, "bad_request", "Invalid JSON body");
                return;
            }
            string? account = json_get_string(body, "account");
            if (account == null || account.strip().length == 0) {
                AuthMiddleware.send_error(msg, 400, "bad_request", "Missing 'account' field");
                return;
            }
            bool new_enabled = true;
            if (body.has_member("enabled")) {
                new_enabled = body.get_boolean_member("enabled");
            }
            string key = "botmother_account_enabled:" + account.strip();
            registry.set_setting(key, new_enabled ? "true" : "false");

            // Emit signal so the plugin can react (pin/unpin)
            registry.account_toggled(account.strip(), new_enabled);

            string json = "{\"account\":\"%s\",\"enabled\":%s}".printf(
                account.strip(), new_enabled ? "true" : "false");
            AuthMiddleware.send_success(msg, json);
            return;
        }

        AuthMiddleware.send_error(msg, 405, "method_not_allowed", "Use GET or POST");
    }

    // --- GET /health ---
    private void handle_health(Soup.Server srv, Soup.ServerMessage msg,
                               string path, HashTable<string, string>? query) {
        string json = "{\"status\":\"ok\",\"version\":\"1.0.0\",\"active_bots\":%d}".printf(
            registry.get_all_active_bots().size);
        msg.set_status(200, null);
        msg.set_response("application/json", Soup.MemoryUse.COPY, json.data);
    }

    // --- GET /bot/getMe ---
    private void handle_get_me(Soup.Server srv, Soup.ServerMessage msg,
                               string path, HashTable<string, string>? query) {
        BotInfo? bot = auth.authenticate(msg);
        if (bot == null) return;

        string json = bot_to_json(bot);
        AuthMiddleware.send_success(msg, json);
    }

    // --- POST /bot/sendMessage ---
    private void handle_send_message(Soup.Server srv, Soup.ServerMessage msg,
                                     string path, HashTable<string, string>? query) {
        BotInfo? bot = auth.authenticate(msg);
        if (bot == null) return;

        if (msg.get_method() != "POST") {
            AuthMiddleware.send_error(msg, 405, "method_not_allowed", "Use POST");
            return;
        }

        var body = get_request_body(msg);
        if (body == null) {
            AuthMiddleware.send_error(msg, 400, "bad_request", "Invalid JSON body");
            return;
        }

        string? to_jid = json_get_string(body, "to");
        string? text = json_get_string(body, "text");
        string? msg_type = json_get_string(body, "type");

        if (to_jid == null || text == null) {
            AuthMiddleware.send_error(msg, 400, "bad_request", "Missing required fields: to, text");
            return;
        }

        if (msg_type == null) msg_type = "chat";

        // Send via message router
        string? message_id = message_router.send_message(bot, to_jid, text, msg_type);
        if (message_id != null) {
            AuthMiddleware.send_success(msg, "{\"message_id\":\"%s\"}".printf(message_id));
        } else {
            AuthMiddleware.send_error(msg, 500, "send_failed", "Failed to send message");
        }
    }

    // --- GET /bot/getUpdates ---
    private void handle_get_updates(Soup.Server srv, Soup.ServerMessage msg,
                                    string path, HashTable<string, string>? query) {
        BotInfo? bot = auth.authenticate(msg);
        if (bot == null) return;

        int offset = 0;
        int limit = 100;

        if (query != null) {
            string? off_str = query.lookup("offset");
            string? lim_str = query.lookup("limit");
            if (off_str != null) offset = int.parse(off_str);
            if (lim_str != null) limit = int.parse(lim_str).clamp(1, 100);
        }

        var updates = registry.get_updates(bot.id, offset, limit);

        // If offset > 0, confirm and delete old updates
        if (offset > 0) {
            registry.delete_updates_up_to(bot.id, offset - 1);
        }

        var sb = new StringBuilder("[");
        bool first = true;
        foreach (UpdateInfo update in updates) {
            if (!first) sb.append(",");
            sb.append("{\"update_id\":%d,\"type\":\"%s\",\"data\":%s}".printf(
                update.id, update.update_type, update.payload));
            first = false;
        }
        sb.append("]");

        AuthMiddleware.send_success(msg, sb.str);
    }

    // --- POST /bot/setWebhook ---
    private void handle_set_webhook(Soup.Server srv, Soup.ServerMessage msg,
                                    string path, HashTable<string, string>? query) {
        BotInfo? bot = auth.authenticate(msg);
        if (bot == null) return;

        if (msg.get_method() != "POST") {
            AuthMiddleware.send_error(msg, 405, "method_not_allowed", "Use POST");
            return;
        }

        var body = get_request_body(msg);
        if (body == null) {
            AuthMiddleware.send_error(msg, 400, "bad_request", "Invalid JSON body");
            return;
        }

        string? url = json_get_string(body, "url");
        if (url == null || !url.has_prefix("http")) {
            AuthMiddleware.send_error(msg, 400, "bad_request", "Missing or invalid 'url' field");
            return;
        }

        string secret = TokenManager.generate_webhook_secret();
        registry.set_webhook(bot.id, url, secret, true);
        registry.log_action(bot.id, "webhook_set", url);

        AuthMiddleware.send_success(msg, "{\"webhook_url\":\"%s\",\"secret\":\"%s\"}".printf(url, secret));
    }

    // --- POST /bot/deleteWebhook ---
    private void handle_delete_webhook(Soup.Server srv, Soup.ServerMessage msg,
                                       string path, HashTable<string, string>? query) {
        BotInfo? bot = auth.authenticate(msg);
        if (bot == null) return;

        registry.set_webhook(bot.id, null, null, false);
        registry.log_action(bot.id, "webhook_deleted");
        AuthMiddleware.send_success(msg, "true");
    }

    // --- POST /bot/sendFile ---
    private void handle_send_file(Soup.Server srv, Soup.ServerMessage msg,
                                  string path, HashTable<string, string>? query) {
        BotInfo? bot = auth.authenticate(msg);
        if (bot == null) return;

        if (msg.get_method() != "POST") {
            AuthMiddleware.send_error(msg, 405, "method_not_allowed", "Use POST");
            return;
        }

        var body = get_request_body(msg);
        if (body == null) {
            AuthMiddleware.send_error(msg, 400, "bad_request", "Invalid JSON body");
            return;
        }

        string? to_jid = json_get_string(body, "to");
        string? file_url = json_get_string(body, "url");
        string? caption = json_get_string(body, "caption");

        if (to_jid == null || file_url == null) {
            AuthMiddleware.send_error(msg, 400, "bad_request", "Missing required fields: to, url");
            return;
        }

        // Send file URL as an out-of-band message (XEP-0066 style)
        string? message_id = message_router.send_file(bot, to_jid, file_url, caption);
        if (message_id != null) {
            AuthMiddleware.send_success(msg, "{\"message_id\":\"%s\"}".printf(message_id));
        } else {
            AuthMiddleware.send_error(msg, 500, "send_failed", "Failed to send file");
        }
    }

    // --- POST /bot/setCommands ---
    private void handle_set_commands(Soup.Server srv, Soup.ServerMessage msg,
                                     string path, HashTable<string, string>? query) {
        BotInfo? bot = auth.authenticate(msg);
        if (bot == null) return;

        if (msg.get_method() != "POST") {
            AuthMiddleware.send_error(msg, 405, "method_not_allowed", "Use POST");
            return;
        }

        var body = get_request_body(msg);
        if (body == null) {
            AuthMiddleware.send_error(msg, 400, "bad_request", "Invalid JSON body");
            return;
        }

        // Parse commands array from JSON
        var commands = parse_commands_array(body);
        if (commands == null) {
            AuthMiddleware.send_error(msg, 400, "bad_request", "Missing or invalid 'commands' array");
            return;
        }

        registry.set_bot_commands(bot.id, commands);
        AuthMiddleware.send_success(msg, "true");
    }

    // --- GET /bot/getCommands ---
    private void handle_get_commands(Soup.Server srv, Soup.ServerMessage msg,
                                     string path, HashTable<string, string>? query) {
        BotInfo? bot = auth.authenticate(msg);
        if (bot == null) return;

        var commands = registry.get_bot_commands(bot.id);
        var sb = new StringBuilder("[");
        bool first = true;
        foreach (CommandInfo cmd in commands) {
            if (!first) sb.append(",");
            sb.append("{\"command\":\"%s\",\"description\":\"%s\"}".printf(
                escape_json(cmd.command),
                escape_json(cmd.description ?? "")
            ));
            first = false;
        }
        sb.append("]");
        AuthMiddleware.send_success(msg, sb.str);
    }

    // --- POST /bot/joinRoom ---
    private void handle_join_room(Soup.Server srv, Soup.ServerMessage msg,
                                  string path, HashTable<string, string>? query) {
        BotInfo? bot = auth.authenticate(msg);
        if (bot == null) return;

        if (msg.get_method() != "POST") {
            AuthMiddleware.send_error(msg, 405, "method_not_allowed", "Use POST");
            return;
        }

        var body = get_request_body(msg);
        if (body == null) {
            AuthMiddleware.send_error(msg, 400, "bad_request", "Invalid JSON body");
            return;
        }

        string? room_jid = json_get_string(body, "room");
        string? nick = json_get_string(body, "nick");
        if (room_jid == null) {
            AuthMiddleware.send_error(msg, 400, "bad_request", "Missing required field: room");
            return;
        }

        bool result = message_router.join_room(bot, room_jid, nick);
        if (result) {
            AuthMiddleware.send_success(msg, "true");
        } else {
            AuthMiddleware.send_error(msg, 500, "join_failed", "Failed to join room");
        }
    }

    // --- POST /bot/leaveRoom ---
    private void handle_leave_room(Soup.Server srv, Soup.ServerMessage msg,
                                   string path, HashTable<string, string>? query) {
        BotInfo? bot = auth.authenticate(msg);
        if (bot == null) return;

        if (msg.get_method() != "POST") {
            AuthMiddleware.send_error(msg, 405, "method_not_allowed", "Use POST");
            return;
        }

        var body = get_request_body(msg);
        if (body == null) {
            AuthMiddleware.send_error(msg, 400, "bad_request", "Invalid JSON body");
            return;
        }

        string? room_jid = json_get_string(body, "room");
        if (room_jid == null) {
            AuthMiddleware.send_error(msg, 400, "bad_request", "Missing required field: room");
            return;
        }

        bool result = message_router.leave_room(bot, room_jid);
        if (result) {
            AuthMiddleware.send_success(msg, "true");
        } else {
            AuthMiddleware.send_error(msg, 500, "leave_failed", "Failed to leave room");
        }
    }

    // --- POST /bot/sendReaction ---
    private void handle_send_reaction(Soup.Server srv, Soup.ServerMessage msg,
                                      string path, HashTable<string, string>? query) {
        BotInfo? bot = auth.authenticate(msg);
        if (bot == null) return;

        if (msg.get_method() != "POST") {
            AuthMiddleware.send_error(msg, 405, "method_not_allowed", "Use POST");
            return;
        }

        var body = get_request_body(msg);
        if (body == null) {
            AuthMiddleware.send_error(msg, 400, "bad_request", "Invalid JSON body");
            return;
        }

        string? to_jid = json_get_string(body, "to");
        string? message_id = json_get_string(body, "message_id");
        string? reaction = json_get_string(body, "reaction");

        if (to_jid == null || message_id == null || reaction == null) {
            AuthMiddleware.send_error(msg, 400, "bad_request", "Missing required fields: to, message_id, reaction");
            return;
        }

        bool result = message_router.send_reaction(bot, to_jid, message_id, reaction);
        if (result) {
            AuthMiddleware.send_success(msg, "true");
        } else {
            AuthMiddleware.send_error(msg, 500, "reaction_failed", "Failed to send reaction");
        }
    }

    // --- GET /bot/getInfo ---
    private void handle_get_info(Soup.Server srv, Soup.ServerMessage msg,
                                 string path, HashTable<string, string>? query) {
        BotInfo? bot = auth.authenticate(msg);
        if (bot == null) return;

        var commands = registry.get_bot_commands(bot.id);
        var sb = new StringBuilder();
        sb.append("{");
        sb.append("\"bot\":%s,".printf(bot_to_json(bot)));
        sb.append("\"commands\":[");
        bool first = true;
        foreach (CommandInfo cmd in commands) {
            if (!first) sb.append(",");
            sb.append("{\"command\":\"%s\",\"description\":\"%s\"}".printf(
                escape_json(cmd.command),
                escape_json(cmd.description ?? "")
            ));
            first = false;
        }
        sb.append("],\"active_sessions\":%d".printf(0));
        sb.append("}");

        AuthMiddleware.send_success(msg, sb.str);
    }

    // --- JSON Helpers ---

    private string bot_to_json(BotInfo bot) {
        var sb = new StringBuilder();
        sb.append("{\"id\":%d".printf(bot.id));
        sb.append(",\"name\":\"%s\"".printf(escape_json(bot.name ?? "")));
        sb.append(",\"jid\":\"%s\"".printf(escape_json(bot.jid ?? "")));
        sb.append(",\"mode\":\"%s\"".printf(escape_json(bot.mode ?? "personal")));
        sb.append(",\"status\":\"%s\"".printf(escape_json(bot.status ?? "active")));
        sb.append(",\"description\":\"%s\"".printf(escape_json(bot.description ?? "")));
        sb.append(",\"created_at\":%ld".printf(bot.created_at));
        if (bot.token_raw != null && bot.token_raw.strip().length > 0) {
            sb.append(",\"token\":\"%s\"".printf(escape_json(bot.token_raw)));
        }
        sb.append("}");
        return sb.str;
    }

    // Simple JSON parser - extract string value by key from JSON body
    private Json.Object? get_request_body(Soup.ServerMessage msg) {
        var body = msg.get_request_body();
        if (body == null) return null;
        Bytes? bytes = body.flatten();
        if (bytes == null || bytes.get_size() == 0) return null;

        try {
            var parser = new Json.Parser();
            unowned uint8[] raw = bytes.get_data();
            parser.load_from_data((string) raw, (ssize_t) raw.length);
            var root = parser.get_root();
            if (root == null || root.get_node_type() != Json.NodeType.OBJECT) return null;
            return root.get_object();
        } catch (Error e) {
            return null;
        }
    }

    private string? json_get_string(Json.Object obj, string key) {
        if (!obj.has_member(key)) return null;
        var node = obj.get_member(key);
        if (node.get_node_type() != Json.NodeType.VALUE) return null;
        return node.get_string();
    }

    private Gee.List<CommandInfo>? parse_commands_array(Json.Object obj) {
        if (!obj.has_member("commands")) return null;
        var node = obj.get_member("commands");
        if (node.get_node_type() != Json.NodeType.ARRAY) return null;

        var arr = node.get_array();
        var commands = new ArrayList<CommandInfo>();
        for (uint i = 0; i < arr.get_length(); i++) {
            var elem = arr.get_element(i);
            if (elem.get_node_type() != Json.NodeType.OBJECT) continue;
            var cmd_obj = elem.get_object();
            string? command = json_get_string(cmd_obj, "command");
            string? description = json_get_string(cmd_obj, "description");
            if (command != null) {
                commands.add(new CommandInfo(command, description));
            }
        }
        return commands;
    }

    private static string escape_json(string s) {
        return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t");
    }
}

}
