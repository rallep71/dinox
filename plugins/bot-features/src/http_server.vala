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
    private EjabberdApi ejabberd_api;
    private bool running = false;
    private string current_mode = "local";
    private uint16 current_port = 7842;

    public HttpServer(BotRegistry registry, TokenManager token_manager,
                      MessageRouter message_router, SessionPool session_pool) {
        this.registry = registry;
        this.token_manager = token_manager;
        this.message_router = message_router;
        this.session_pool = session_pool;
        this.rate_limiter = new RateLimiter(30, 1);
        this.auth = new AuthMiddleware(token_manager, rate_limiter);
        this.ejabberd_api = new EjabberdApi(registry);
    }

    public void start(uint16 port, string mode = "local", string tls_cert_path = "", string tls_key_path = "") throws Error {
        server = new Soup.Server("server-header", "DinoX-BotAPI/1.0", null);
        current_mode = mode;
        current_port = port;

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
        server.add_handler("/bot/activate", handle_activate_bot);
        server.add_handler("/bot/token", handle_regenerate_token);
        server.add_handler("/bot/revoke", handle_revoke_token);
        server.add_handler("/bot/account/status", handle_account_status);
        server.add_handler("/bot/ejabberd/settings", handle_ejabberd_settings);
        server.add_handler("/bot/ejabberd/test", handle_ejabberd_test);
        server.add_handler("/bot/telegram/setup", handle_telegram_setup);
        server.add_handler("/bot/telegram/status", handle_telegram_status);
        server.add_handler("/bot/telegram/enable", handle_telegram_enable);
        server.add_handler("/bot/telegram/send", handle_telegram_send);
        server.add_handler("/bot/telegram/test", handle_telegram_test);
        server.add_handler("/bot/ai/setup", handle_ai_setup);
        server.add_handler("/bot/ai/status", handle_ai_status);
        server.add_handler("/bot/ai/enable", handle_ai_enable);
        server.add_handler("/bot/ai/ask", handle_ai_ask);
        server.add_handler("/health", handle_health);

        if (mode == "network") {
            // Network mode: TLS required, listen on all interfaces
            string cert_path = tls_cert_path;
            string key_path = tls_key_path;

            // Auto-generate self-signed certificate if no paths provided
            if (cert_path == "" || key_path == "") {
                string cert_dir = Path.build_filename(Environment.get_user_data_dir(), "dinox", "api-tls");
                cert_path = Path.build_filename(cert_dir, "server.crt");
                key_path = Path.build_filename(cert_dir, "server.key");

                // Generate if missing or expired
                if (CertGen.check_cert_valid(cert_path) == 0) {
                    message("Botmother: Generating self-signed TLS certificate...");
                    int ret = CertGen.generate_self_signed_cert(cert_path, key_path, "DinoX API Server");
                    if (ret < 0) {
                        throw new IOError.FAILED("Failed to generate TLS certificate (error %d). Falling back to localhost.", ret);
                    }
                    message("Botmother: Self-signed certificate created at %s", cert_path);
                }
            }

            // Load TLS certificate
            var tls_cert = new TlsCertificate.from_files(cert_path, key_path);
            server.set_tls_certificate(tls_cert);

            // Listen on all interfaces with HTTPS
            server.listen(new InetSocketAddress(new InetAddress.any(SocketFamily.IPV4), port), Soup.ServerListenOptions.HTTPS);
            running = true;
            message("Botmother: HTTPS API running on 0.0.0.0:%u (TLS)", port);
        } else {
            // Local mode (default): HTTP on localhost only
            server.listen_local(port, Soup.ServerListenOptions.IPV4_ONLY);
            running = true;
        }
    }

    public string get_mode() {
        return current_mode;
    }

    public uint16 get_port() {
        return current_port;
    }

    public bool is_running() {
        return running;
    }

    public void stop() {
        if (server != null && running) {
            server.disconnect();
            running = false;
            server = null;
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
        string? avatar_data = json_get_string(body, "avatar");
        string? avatar_type = json_get_string(body, "avatar_type");

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

        // Dedicated mode requires ejabberd API to be configured
        if (mode == "dedicated" && !ejabberd_api.is_configured()) {
            AuthMiddleware.send_error(msg, 400, "not_configured",
                "Dedicated bot mode requires ejabberd API settings. Configure them in Botmother settings.");
            return;
        }

        // Check bot limit per owner
        var existing = registry.get_bots_by_owner(owner);
        if (existing.size >= 20) {
            AuthMiddleware.send_error(msg, 429, "limit_reached", "Maximum 20 bots per owner");
            return;
        }

        if (mode == "dedicated") {
            // Async: register XMPP account via ejabberd
            msg.pause();
            do_create_dedicated_bot.begin(msg, name.strip(), owner.strip(), mode, avatar_data, avatar_type);
        } else {
            int bot_id = registry.create_bot(name.strip(), owner.strip(), "", mode);
            string raw_token = token_manager.generate_token(bot_id);
            // Store avatar if provided
            if (avatar_data != null && avatar_data.length > 0) {
                registry.set_setting("bot_avatar:%d".printf(bot_id), avatar_data);
                registry.set_setting("bot_avatar_type:%d".printf(bot_id), avatar_type ?? "image/png");
            }
            registry.log_action(bot_id, "created", "owner=%s mode=%s via=http".printf(owner, mode));

            string json = "{\"id\":%d,\"name\":\"%s\",\"token\":\"%s\",\"mode\":\"%s\",\"api_url\":\"http://localhost:7842/bot/\",\"hint\":\"Use token as Bearer in Authorization header\"}".printf(
                bot_id, escape_json(name.strip()), escape_json(raw_token), escape_json(mode));
            AuthMiddleware.send_success(msg, json);
        }
    }

    // Async handler for creating a dedicated bot with ejabberd account registration
    private async void do_create_dedicated_bot(Soup.ServerMessage msg, string name, string owner, string mode,
                                                string? avatar_data, string? avatar_type) {
        string username = EjabberdApi.generate_bot_username(name);
        string password = EjabberdApi.generate_bot_password();
        string host = ejabberd_api.get_host();
        string bot_jid = "%s@%s".printf(username, host);

        // Register the account on ejabberd
        var result = yield ejabberd_api.register_account(username, password);
        if (!result.success) {
            AuthMiddleware.send_error(msg, 502, "registration_failed",
                "Failed to register XMPP account: %s".printf(result.error_message ?? "Unknown error"));
            msg.unpause();
            return;
        }

        // Create bot in local DB
        int bot_id = registry.create_bot(name, owner, "", mode, bot_jid);
        registry.update_bot_password(bot_id, password);
        string raw_token = token_manager.generate_token(bot_id);
        // Store avatar if provided
        if (avatar_data != null && avatar_data.length > 0) {
            registry.set_setting("bot_avatar:%d".printf(bot_id), avatar_data);
            registry.set_setting("bot_avatar_type:%d".printf(bot_id), avatar_type ?? "image/png");
        }
        registry.log_action(bot_id, "created", "owner=%s mode=%s jid=%s via=http".printf(owner, mode, bot_jid));

        string json = "{\"id\":%d,\"name\":\"%s\",\"token\":\"%s\",\"mode\":\"%s\",\"jid\":\"%s\",\"api_url\":\"http://localhost:7842/bot/\",\"hint\":\"Use token as Bearer in Authorization header\"}".printf(
            bot_id, escape_json(name), escape_json(raw_token), escape_json(mode), escape_json(bot_jid));
        AuthMiddleware.send_success(msg, json);
        msg.unpause();

        // Connect the new dedicated bot immediately
        BotInfo? new_bot = registry.get_bot_by_id(bot_id);
        if (new_bot != null) {
            session_pool.connect_dedicated.begin(new_bot);
        }
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

        // For dedicated bots, also unregister the XMPP account on the server
        if (bot.mode == "dedicated" && bot.jid != null && bot.jid.contains("@")) {
            string username = bot.jid.split("@")[0];
            msg.pause();
            do_delete_dedicated_bot.begin(msg, bot_id, username);
        } else {
            registry.delete_bot(bot_id);
            registry.log_action(bot_id, "deleted", "via=http");
            AuthMiddleware.send_success(msg, "{\"deleted\":true,\"id\":%d}".printf(bot_id));
        }
    }

    // Async handler for deleting a dedicated bot with ejabberd account removal
    private async void do_delete_dedicated_bot(Soup.ServerMessage msg, int bot_id, string username) {
        // Try to unregister from ejabberd, but delete locally regardless
        var result = yield ejabberd_api.unregister_account(username);
        if (!result.success) {
            warning("Botmother: Failed to unregister %s from ejabberd: %s", username, result.error_message ?? "?");
        }
        registry.delete_bot(bot_id);
        registry.log_action(bot_id, "deleted", "dedicated_account_removed=%s via=http".printf(
            result.success ? "true" : "false"));
        AuthMiddleware.send_success(msg, "{\"deleted\":true,\"id\":%d,\"account_removed\":%s}".printf(
            bot_id, result.success ? "true" : "false"));
        msg.unpause();
    }

    // --- POST /bot/activate --- (no token needed, localhost only)
    // Sets bot status to "active" or "disabled"
    private void handle_activate_bot(Soup.Server srv, Soup.ServerMessage msg,
                                     string path, HashTable<string, string>? query) {
        if (msg.get_method() != "POST") {
            AuthMiddleware.send_error(msg, 405, "method_not_allowed", "Use POST");
            return;
        }

        var body = get_request_body(msg);
        if (body == null) {
            AuthMiddleware.send_error(msg, 400, "bad_request", "Invalid JSON body. Example: {\"id\":1,\"active\":true}");
            return;
        }

        if (!body.has_member("id")) {
            AuthMiddleware.send_error(msg, 400, "bad_request", "Missing required field: id");
            return;
        }
        int bot_id = (int) body.get_int_member("id");

        if (!body.has_member("active")) {
            AuthMiddleware.send_error(msg, 400, "bad_request", "Missing required field: active (true/false)");
            return;
        }
        bool new_active = body.get_boolean_member("active");

        BotInfo? bot = registry.get_bot_by_id(bot_id);
        if (bot == null) {
            AuthMiddleware.send_error(msg, 404, "not_found", "Bot not found");
            return;
        }

        string new_status = new_active ? "active" : "disabled";
        registry.update_bot_status(bot_id, new_status);
        registry.log_action(bot_id, new_active ? "activated" : "deactivated", "via=http");

        // Notify plugin to show/hide bot conversation
        registry.bot_status_changed(bot_id, new_status);

        string json = "{\"id\":%d,\"status\":\"%s\"}".printf(bot_id, new_status);
        AuthMiddleware.send_success(msg, json);
    }

    // --- POST /bot/token --- (no token needed, localhost only)
    // Regenerates the token for a bot and returns the new token
    private void handle_regenerate_token(Soup.Server srv, Soup.ServerMessage msg,
                                         string path, HashTable<string, string>? query) {
        if (msg.get_method() != "POST") {
            AuthMiddleware.send_error(msg, 405, "method_not_allowed", "Use POST");
            return;
        }

        var body = get_request_body(msg);
        if (body == null || !body.has_member("id")) {
            AuthMiddleware.send_error(msg, 400, "bad_request", "Missing required field: id");
            return;
        }
        int bot_id = (int) body.get_int_member("id");

        BotInfo? bot = registry.get_bot_by_id(bot_id);
        if (bot == null) {
            AuthMiddleware.send_error(msg, 404, "not_found", "Bot not found");
            return;
        }

        string raw_token = token_manager.regenerate_token(bot_id);
        registry.log_action(bot_id, "token_regenerated", "via=http");

        string json = "{\"id\":%d,\"token\":\"%s\"}".printf(bot_id, escape_json(raw_token));
        AuthMiddleware.send_success(msg, json);
    }

    // --- POST /bot/revoke --- (no token needed, localhost only)
    // Revokes the token for a bot (disables the bot)
    private void handle_revoke_token(Soup.Server srv, Soup.ServerMessage msg,
                                     string path, HashTable<string, string>? query) {
        if (msg.get_method() != "POST") {
            AuthMiddleware.send_error(msg, 405, "method_not_allowed", "Use POST");
            return;
        }

        var body = get_request_body(msg);
        if (body == null || !body.has_member("id")) {
            AuthMiddleware.send_error(msg, 400, "bad_request", "Missing required field: id");
            return;
        }
        int bot_id = (int) body.get_int_member("id");

        BotInfo? bot = registry.get_bot_by_id(bot_id);
        if (bot == null) {
            AuthMiddleware.send_error(msg, 404, "not_found", "Bot not found");
            return;
        }

        token_manager.revoke_token(bot_id);
        registry.update_bot_status(bot_id, "disabled");
        registry.log_action(bot_id, "token_revoked", "via=http");

        string json = "{\"id\":%d,\"revoked\":true,\"status\":\"disabled\"}".printf(bot_id);
        AuthMiddleware.send_success(msg, json);
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

    // --- GET/POST /bot/ejabberd/settings ---
    // GET: returns current ejabberd API settings (password masked)
    // POST: saves ejabberd API settings
    private void handle_ejabberd_settings(Soup.Server srv, Soup.ServerMessage msg,
                                          string path, HashTable<string, string>? query) {
        string method = msg.get_method();

        if (method == "GET") {
            string? url = registry.get_setting(EjabberdApi.KEY_API_URL);
            string? admin_jid = registry.get_setting(EjabberdApi.KEY_ADMIN_JID);
            string? admin_pw = registry.get_setting(EjabberdApi.KEY_ADMIN_PASSWORD);
            string? host = registry.get_setting(EjabberdApi.KEY_HOST);
            bool configured = ejabberd_api.is_configured();

            // Mask password
            string pw_display = (admin_pw != null && admin_pw.strip() != "") ? "********" : "";

            string json = "{\"api_url\":\"%s\",\"admin_jid\":\"%s\",\"admin_password\":\"%s\",\"host\":\"%s\",\"configured\":%s}".printf(
                escape_json(url ?? ""),
                escape_json(admin_jid ?? ""),
                escape_json(pw_display),
                escape_json(host ?? ""),
                configured ? "true" : "false");
            AuthMiddleware.send_success(msg, json);
            return;
        }

        if (method == "POST") {
            var body = get_request_body(msg);
            if (body == null) {
                AuthMiddleware.send_error(msg, 400, "bad_request", "Invalid JSON body");
                return;
            }

            string? url = json_get_string(body, "api_url");
            string? admin_jid = json_get_string(body, "admin_jid");
            string? admin_pw = json_get_string(body, "admin_password");
            string? host = json_get_string(body, "host");

            if (url != null) registry.set_setting(EjabberdApi.KEY_API_URL, url.strip());
            if (admin_jid != null) registry.set_setting(EjabberdApi.KEY_ADMIN_JID, admin_jid.strip());
            // Only update password if not masked
            if (admin_pw != null && admin_pw != "********") {
                registry.set_setting(EjabberdApi.KEY_ADMIN_PASSWORD, admin_pw.strip());
            }
            if (host != null) registry.set_setting(EjabberdApi.KEY_HOST, host.strip());

            registry.log_action(0, "ejabberd_settings_updated", "via=http");
            AuthMiddleware.send_success(msg, "{\"saved\":true,\"configured\":%s}".printf(
                ejabberd_api.is_configured() ? "true" : "false"));
            return;
        }

        AuthMiddleware.send_error(msg, 405, "method_not_allowed", "Use GET or POST");
    }

    // --- POST /bot/ejabberd/test ---
    // Tests connectivity to ejabberd API
    private void handle_ejabberd_test(Soup.Server srv, Soup.ServerMessage msg,
                                      string path, HashTable<string, string>? query) {
        if (msg.get_method() != "POST") {
            AuthMiddleware.send_error(msg, 405, "method_not_allowed", "Use POST");
            return;
        }

        do_ejabberd_test.begin(msg);
        msg.pause();
    }

    private async void do_ejabberd_test(Soup.ServerMessage msg) {
        var result = yield ejabberd_api.test_connection();
        if (result.success) {
            string json = "{\"connected\":true,\"response\":\"%s\"}".printf(
                escape_json(result.response_body ?? "ok"));
            AuthMiddleware.send_success(msg, json);
        } else {
            AuthMiddleware.send_error(msg, 502, "connection_failed", result.error_message ?? "Unknown error");
        }
        msg.unpause();
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

    // ════════════════════════════════════════════════════════════
    // Telegram API Endpoints
    // ════════════════════════════════════════════════════════════

    // --- POST /bot/telegram/setup --- Configure Telegram bridge
    private void handle_telegram_setup(Soup.Server srv, Soup.ServerMessage msg,
                                       string path, HashTable<string, string>? query) {
        BotInfo? bot = auth.authenticate(msg);
        if (bot == null) return;

        if (msg.get_method() != "POST") {
            AuthMiddleware.send_error(msg, 405, "method_not_allowed", "Use POST");
            return;
        }

        var body = get_request_body(msg);
        if (body == null) {
            AuthMiddleware.send_error(msg, 400, "bad_request",
                "Invalid JSON body. Example: {\"token\":\"123:ABC\",\"chat_id\":\"987654321\",\"mode\":\"bridge\"}");
            return;
        }

        string? tg_token = json_get_string(body, "token");
        string? chat_id = json_get_string(body, "chat_id");
        string? mode = json_get_string(body, "mode");
        if (mode == null) mode = "bridge";

        if (tg_token == null || chat_id == null) {
            AuthMiddleware.send_error(msg, 400, "bad_request", "Missing required fields: token, chat_id");
            return;
        }

        if (mode != "bridge" && mode != "forward") {
            AuthMiddleware.send_error(msg, 400, "bad_request", "Invalid mode. Must be: bridge or forward");
            return;
        }

        message_router.telegram.configure(bot.id, tg_token, chat_id, mode);
        message_router.telegram.start_polling(bot.id, bot.owner_jid ?? "");
        registry.log_action(bot.id, "telegram_setup", "chat_id=%s mode=%s via=http".printf(chat_id, mode));

        string json = "{\"configured\":true,\"chat_id\":\"%s\",\"mode\":\"%s\"}".printf(
            escape_json(chat_id), escape_json(mode));
        AuthMiddleware.send_success(msg, json);
    }

    // --- GET /bot/telegram/status --- Get Telegram bridge status
    private void handle_telegram_status(Soup.Server srv, Soup.ServerMessage msg,
                                        string path, HashTable<string, string>? query) {
        BotInfo? bot = auth.authenticate(msg);
        if (bot == null) return;

        bool enabled = message_router.telegram.is_enabled(bot.id);
        string? chat_id = registry.get_setting("bot_%d_tg_chat_id".printf(bot.id));
        string? mode = registry.get_setting("bot_%d_tg_mode".printf(bot.id));
        bool configured = registry.get_setting("bot_%d_tg_token".printf(bot.id)) != null;

        string json = "{\"enabled\":%s,\"configured\":%s,\"chat_id\":\"%s\",\"mode\":\"%s\"}".printf(
            enabled ? "true" : "false",
            configured ? "true" : "false",
            escape_json(chat_id ?? ""),
            escape_json(mode ?? "bridge"));
        AuthMiddleware.send_success(msg, json);
    }

    // --- POST /bot/telegram/enable --- Enable or disable Telegram bridge
    private void handle_telegram_enable(Soup.Server srv, Soup.ServerMessage msg,
                                        string path, HashTable<string, string>? query) {
        BotInfo? bot = auth.authenticate(msg);
        if (bot == null) return;

        if (msg.get_method() != "POST") {
            AuthMiddleware.send_error(msg, 405, "method_not_allowed", "Use POST");
            return;
        }

        var body = get_request_body(msg);
        if (body == null || !body.has_member("enabled")) {
            AuthMiddleware.send_error(msg, 400, "bad_request", "Missing required field: enabled (true/false)");
            return;
        }

        bool new_enabled = body.get_boolean_member("enabled");

        if (new_enabled) {
            string? token = registry.get_setting("bot_%d_tg_token".printf(bot.id));
            if (token == null) {
                AuthMiddleware.send_error(msg, 400, "not_configured",
                    "Telegram not configured. Use /bot/telegram/setup first.");
                return;
            }
            registry.set_setting("bot_%d_tg_enabled".printf(bot.id), "true");
            message_router.telegram.start_polling(bot.id, bot.owner_jid ?? "");
        } else {
            message_router.telegram.disable(bot.id);
        }

        registry.log_action(bot.id, new_enabled ? "telegram_enabled" : "telegram_disabled", "via=http");
        string json = "{\"enabled\":%s}".printf(new_enabled ? "true" : "false");
        AuthMiddleware.send_success(msg, json);
    }

    // --- POST /bot/telegram/send --- Send a message to Telegram
    private void handle_telegram_send(Soup.Server srv, Soup.ServerMessage msg,
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

        string? text = json_get_string(body, "text");
        if (text == null) {
            AuthMiddleware.send_error(msg, 400, "bad_request", "Missing required field: text");
            return;
        }

        if (!message_router.telegram.is_enabled(bot.id)) {
            AuthMiddleware.send_error(msg, 400, "not_enabled", "Telegram bridge is not enabled for this bot");
            return;
        }

        msg.pause();
        do_telegram_send.begin(msg, bot, text);
    }

    private async void do_telegram_send(Soup.ServerMessage msg, BotInfo bot, string text) {
        bool ok = yield message_router.telegram.forward_to_telegram(bot.id, "API", text);
        if (ok) {
            AuthMiddleware.send_success(msg, "{\"sent\":true}");
        } else {
            AuthMiddleware.send_error(msg, 500, "send_failed", "Failed to send message to Telegram");
        }
        msg.unpause();
    }

    // --- POST /bot/telegram/test --- Test Telegram connection
    private void handle_telegram_test(Soup.Server srv, Soup.ServerMessage msg,
                                      string path, HashTable<string, string>? query) {
        BotInfo? bot = auth.authenticate(msg);
        if (bot == null) return;

        if (msg.get_method() != "POST") {
            AuthMiddleware.send_error(msg, 405, "method_not_allowed", "Use POST");
            return;
        }

        msg.pause();
        do_telegram_test.begin(msg, bot);
    }

    private async void do_telegram_test(Soup.ServerMessage msg, BotInfo bot) {
        string? result = yield message_router.telegram.test_connection(bot.id);
        if (result != null && result.contains("verbunden")) {
            AuthMiddleware.send_success(msg, "{\"connected\":true,\"info\":\"%s\"}".printf(
                escape_json(result)));
        } else {
            AuthMiddleware.send_error(msg, 502, "connection_failed", result ?? "Unknown error");
        }
        msg.unpause();
    }

    // ════════════════════════════════════════════════════════════
    // AI API Endpoints
    // ════════════════════════════════════════════════════════════

    // --- POST /bot/ai/setup --- Configure AI provider
    private void handle_ai_setup(Soup.Server srv, Soup.ServerMessage msg,
                                 string path, HashTable<string, string>? query) {
        BotInfo? bot = auth.authenticate(msg);
        if (bot == null) return;

        if (msg.get_method() != "POST") {
            AuthMiddleware.send_error(msg, 405, "method_not_allowed", "Use POST");
            return;
        }

        var body = get_request_body(msg);
        if (body == null) {
            AuthMiddleware.send_error(msg, 400, "bad_request",
                "Invalid JSON body. Example: {\"provider\":\"openai\",\"api_key\":\"sk-...\",\"model\":\"gpt-4o\"}");
            return;
        }

        string? provider = json_get_string(body, "provider");
        string? api_key = json_get_string(body, "api_key");
        string? model = json_get_string(body, "model");

        if (provider == null || model == null) {
            AuthMiddleware.send_error(msg, 400, "bad_request", "Missing required fields: provider, model");
            return;
        }
        if (api_key == null) api_key = "-";

        message_router.ai.configure_preset(bot.id, provider, api_key, model);
        registry.log_action(bot.id, "ai_setup", "provider=%s model=%s via=http".printf(provider, model));

        AuthMiddleware.send_success(msg, "{\"configured\":true,\"provider\":\"%s\",\"model\":\"%s\"}".printf(
            escape_json(provider), escape_json(model)));
    }

    // --- GET /bot/ai/status --- Get AI config status
    private void handle_ai_status(Soup.Server srv, Soup.ServerMessage msg,
                                  string path, HashTable<string, string>? query) {
        BotInfo? bot = auth.authenticate(msg);
        if (bot == null) return;

        bool enabled = message_router.ai.is_enabled(bot.id);
        string? ai_type = registry.get_setting("bot_%d_ai_type".printf(bot.id));
        string? model = registry.get_setting("bot_%d_ai_model".printf(bot.id));
        string? endpoint = registry.get_setting("bot_%d_ai_endpoint".printf(bot.id));
        bool configured = endpoint != null;

        string json = "{\"enabled\":%s,\"configured\":%s,\"type\":\"%s\",\"model\":\"%s\",\"endpoint\":\"%s\"}".printf(
            enabled ? "true" : "false",
            configured ? "true" : "false",
            escape_json(ai_type ?? ""),
            escape_json(model ?? ""),
            escape_json(endpoint ?? ""));
        AuthMiddleware.send_success(msg, json);
    }

    // --- POST /bot/ai/enable --- Enable or disable AI
    private void handle_ai_enable(Soup.Server srv, Soup.ServerMessage msg,
                                  string path, HashTable<string, string>? query) {
        BotInfo? bot = auth.authenticate(msg);
        if (bot == null) return;

        if (msg.get_method() != "POST") {
            AuthMiddleware.send_error(msg, 405, "method_not_allowed", "Use POST");
            return;
        }

        var body = get_request_body(msg);
        if (body == null || !body.has_member("enabled")) {
            AuthMiddleware.send_error(msg, 400, "bad_request", "Missing required field: enabled (true/false)");
            return;
        }

        bool new_enabled = body.get_boolean_member("enabled");

        if (new_enabled) {
            string? endpoint = registry.get_setting("bot_%d_ai_endpoint".printf(bot.id));
            if (endpoint == null) {
                AuthMiddleware.send_error(msg, 400, "not_configured",
                    "AI not configured. Use /bot/ai/setup first.");
                return;
            }
            registry.set_setting("bot_%d_ai_enabled".printf(bot.id), "true");
        } else {
            message_router.ai.disable(bot.id);
        }

        registry.log_action(bot.id, new_enabled ? "ai_enabled" : "ai_disabled", "via=http");
        string json = "{\"enabled\":%s}".printf(new_enabled ? "true" : "false");
        AuthMiddleware.send_success(msg, json);
    }

    // --- POST /bot/ai/ask --- Send a question to the AI
    private void handle_ai_ask(Soup.Server srv, Soup.ServerMessage msg,
                               string path, HashTable<string, string>? query) {
        BotInfo? bot = auth.authenticate(msg);
        if (bot == null) return;

        if (msg.get_method() != "POST") {
            AuthMiddleware.send_error(msg, 405, "method_not_allowed", "Use POST");
            return;
        }

        var body = get_request_body(msg);
        if (body == null) {
            AuthMiddleware.send_error(msg, 400, "bad_request",
                "Invalid JSON body. Example: {\"message\":\"Hello, how are you?\"}");
            return;
        }

        string? question = json_get_string(body, "message");
        if (question == null) question = json_get_string(body, "text");
        if (question == null) {
            AuthMiddleware.send_error(msg, 400, "bad_request", "Missing required field: message");
            return;
        }

        if (!message_router.ai.is_enabled(bot.id)) {
            AuthMiddleware.send_error(msg, 400, "not_enabled", "AI is not enabled for this bot");
            return;
        }

        string from = "api-client";
        if (query != null && query.contains("from")) {
            from = query.get("from");
        }

        msg.pause();
        do_ai_ask.begin(msg, bot, from, question);
    }

    private async void do_ai_ask(Soup.ServerMessage msg, BotInfo bot, string from, string question) {
        string? answer = yield message_router.ai.ask(bot.id, from, question);
        if (answer != null) {
            AuthMiddleware.send_success(msg, "{\"response\":\"%s\"}".printf(escape_json(answer)));
        } else {
            AuthMiddleware.send_error(msg, 500, "ai_error", "AI returned no response");
        }
        msg.unpause();
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
