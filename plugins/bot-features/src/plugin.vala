using Dino.Entities;
using Gee;
using Xmpp;

namespace Dino.Plugins.BotFeatures {

public class Plugin : RootInterface, Object {

    public Dino.Application app;
    private BotRegistry? registry;
    private TokenManager? token_manager;
    private HttpServer? http_server;
    private SessionPool? session_pool;
    private MessageRouter? message_router;
    private WebhookDispatcher? webhook_dispatcher;
    private BotfatherHandler? botfather;
    private bool enabled = false;
    private uint api_restart_timeout_id = 0;

    public void registered(Dino.Application app) {
        this.app = app;

        // Check if bot features are enabled in settings
        if (!app.settings.bot_features_enabled) {
            message("Botmother: Disabled in settings, skipping initialization");
            // Watch for setting changes to enable later
            app.settings.notify["bot-features-enabled"].connect(on_setting_changed);
            return;
        }

        initialize();
    }

    private void on_setting_changed() {
        if (app.settings.bot_features_enabled && !enabled) {
            initialize();
        } else if (!app.settings.bot_features_enabled && enabled) {
            shutdown();
        }
    }

    private void initialize() {
        // Initialize core components
        string db_path = GLib.Path.build_filename(
            GLib.Environment.get_user_data_dir(), "dinox", "bot_registry.db"
        );
        try {
            registry = new BotRegistry(db_path, app.db_key);
        } catch (Error e) {
            warning("Botmother: Failed to open bot registry: %s", e.message);
            return;
        }

        token_manager = new TokenManager(registry);
        session_pool = new SessionPool(app);
        session_pool.set_registry(registry);

        // OMEMO manager for bot streams
        var bot_omemo = new BotOmemoManager(registry);
        session_pool.set_bot_omemo(bot_omemo);

        webhook_dispatcher = new WebhookDispatcher();
        message_router = new MessageRouter(app, registry, session_pool, webhook_dispatcher);
        http_server = new HttpServer(registry, token_manager, message_router, session_pool);
        var ejabberd_api = new EjabberdApi(registry);
        botfather = new BotfatherHandler(app, registry, token_manager, ejabberd_api);
        message_router.set_botfather(botfather);
        message_router.set_ejabberd_api(ejabberd_api);

        // Start HTTP API on configured port and mode
        var app_settings = app.settings;
        uint16 port = (uint16) app_settings.api_port;
        string mode = app_settings.api_mode;
        string tls_cert = app_settings.api_tls_cert;
        string tls_key = app_settings.api_tls_key;
        try {
            http_server.start(port, mode, tls_cert, tls_key);
            enabled = true;
            if (mode == "network") {
                message("Botmother: HTTPS API running on 0.0.0.0:%u (TLS)", port);
            } else {
                message("Botmother: HTTP API running on localhost:%u", port);
            }
        } catch (Error e) {
            // If network mode fails (cert error etc.), fall back to localhost
            if (mode == "network") {
                warning("Botmother: Network mode failed (%s), falling back to localhost", e.message);
                try {
                    http_server.start(port, "local", "", "");
                    enabled = true;
                    message("Botmother: HTTP API running on localhost:%u (fallback)", port);
                } catch (Error e2) {
                    warning("Botmother: Failed to start HTTP server: %s", e2.message);
                }
            } else {
                warning("Botmother: Failed to start HTTP server: %s", e.message);
            }
        }

        // Ensure "Botmother" self-chat exists and is pinned for enabled accounts
        ensure_botmother_conversations();

        // Suppress subscription notifications for all known dedicated bot JIDs
        suppress_bot_subscriptions();

        // Clean up orphaned conversations after accounts are loaded (2s delay)
        GLib.Timeout.add(2000, () => {
            cleanup_orphaned_bot_conversations();
            return false;
        });

        // Fix encryption + subscriptions for existing dedicated bot conversations
        // Run after accounts and conversations are loaded
        // BUG-10 fix: Single timer instead of duplicate 1s + 2.5s
        GLib.Timeout.add(2500, () => {
            fix_dedicated_bot_conversations();
            return false;
        });

        // Connect dedicated bots after a short delay (so main accounts connect first)
        GLib.Timeout.add(5000, () => {
            session_pool.connect_all_dedicated();
            return false;
        });

        // When a dedicated bot is ready, set roster name and disable OMEMO
        session_pool.dedicated_bot_ready.connect(on_dedicated_bot_ready);

        // Auto-approve subscription requests from dedicated bot JIDs
        var presence_mgr = app.stream_interactor.get_module<PresenceManager>(PresenceManager.IDENTITY);
        presence_mgr.received_subscription_request.connect(on_subscription_request);

        // When a bot is deleted, check if account has 0 bots left -> unpin
        registry.bot_deleted.connect(on_bot_deleted);

        // When per-account toggle changes -> pin or unpin, close/open bot chats
        registry.account_toggled.connect(on_account_toggled);

        // When a bot is activated/deactivated -> show/hide its conversation
        registry.bot_status_changed.connect(on_bot_status_changed);

        // Watch for setting changes
        app.settings.notify["bot-features-enabled"].connect(on_setting_changed);

        // Watch API server settings and auto-restart on change
        app.settings.notify["api-mode"].connect(on_api_setting_changed);
        app.settings.notify["api-port"].connect(on_api_setting_changed);
        app.settings.notify["api-tls-cert"].connect(on_api_setting_changed);
        app.settings.notify["api-tls-key"].connect(on_api_setting_changed);
    }

    // Check whether Botmother is enabled for a specific account.
    // Default is true (enabled) when no explicit setting exists.
    private bool is_account_enabled(string jid_str) {
        if (registry == null) return false;
        string key = "botmother_account_enabled:" + jid_str;
        string? val = registry.get_setting(key);
        return (val == null || val == "true");
    }

    // Auto-approve incoming subscription requests from known dedicated bot JIDs
    private void on_subscription_request(Jid jid, Account account) {
        if (registry == null) return;
        if (!is_dedicated_bot_jid(jid.bare_jid.to_string())) return;

        message("Botmother: Auto-approving subscription request from bot %s", jid.to_string());
        var pm = app.stream_interactor.get_module<PresenceManager>(PresenceManager.IDENTITY);
        pm.approve_subscription(account, jid);
        pm.request_subscription(account, jid);
    }

    // Check if a JID belongs to a known dedicated bot
    private bool is_dedicated_bot_jid(string jid_str) {
        if (registry == null) return false;
        var all_bots = registry.get_all_bots();
        foreach (BotInfo bot in all_bots) {
            if (bot.mode == "dedicated" && bot.jid != null && bot.jid == jid_str) {
                return true;
            }
        }
        return false;
    }

    // Called when a dedicated bot's XMPP stream is fully ready
    private void on_dedicated_bot_ready(int bot_id, BotInfo bot) {
        if (bot.jid == null || bot.name == null) return;

        try {
            Xmpp.Jid bot_jid = new Xmpp.Jid(bot.jid);

            // Suppress subscription notification for this bot JID
            var presence_mgr = app.stream_interactor.get_module<PresenceManager>(PresenceManager.IDENTITY);
            presence_mgr.suppress_subscription_notification(bot_jid);

            // Find the owner account for this bot
            Xmpp.Jid? owner_jid = null;
            if (bot.owner_jid != null) {
                try {
                    owner_jid = new Xmpp.Jid(bot.owner_jid);
                } catch (Error e) {
                    warning("Botmother: Invalid owner JID for bot %d: %s", bot_id, bot.owner_jid);
                }
            }

            // Find the matching owner account - bot conversations only appear for the owner
            var accounts = app.stream_interactor.get_accounts();
            Account? target_account = null;
            foreach (Account account in accounts) {
                if (owner_jid != null && account.bare_jid.equals(owner_jid)) {
                    target_account = account;
                    break;
                }
            }
            if (target_account == null) {
                message("Botmother: Owner account '%s' not active in DinoX for bot %d - conversation will appear when owner logs in",
                    bot.owner_jid ?? "(null)", bot_id);
                return;
            }

            // Set roster handle: show bot name instead of raw JID
            var roster_mgr = app.stream_interactor.get_module<RosterManager>(RosterManager.IDENTITY);
            var existing_item = roster_mgr.get_roster_item(target_account, bot_jid);
            if (existing_item != null) {
                roster_mgr.set_jid_handle(target_account, bot_jid, bot.name);
            } else {
                roster_mgr.add_jid(target_account, bot_jid, bot.name);
            }
            message("Botmother: Set roster name '%s' for bot JID %s (account %s)",
                bot.name, bot.jid, target_account.bare_jid.to_string());

            // Create/get conversation with bot JID and set encryption to OMEMO
            var cm = app.stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY);
            Conversation conversation = cm.create_conversation(bot_jid, target_account, Conversation.Type.CHAT);
            // Set encryption BEFORE start_conversation so it takes effect immediately
            conversation.encryption = Entities.Encryption.OMEMO;
            message("Botmother: Set encryption=OMEMO for bot conversation %s", bot.jid);
            // Now activate it in the sidebar
            cm.start_conversation(conversation);

            // Approve any pending subscription FROM the bot + send our subscription TO the bot
            presence_mgr.approve_subscription(target_account, bot_jid);
            presence_mgr.request_subscription(target_account, bot_jid);
            message("Botmother: Approved + requested subscription for bot %s", bot.jid);
        } catch (Error e) {
            warning("Botmother: Error setting up bot conversation for %d: %s", bot_id, e.message);
        }

        // Start Telegram polling if configured for this bot
        if (message_router != null && message_router.telegram.is_enabled(bot_id)) {
            string owner = bot.owner_jid ?? "";
            message_router.telegram.start_polling(bot_id, owner);
            message("Botmother: Started Telegram polling for bot %d", bot_id);
        }
    }

    // Fix encryption and subscription for ALL known dedicated bot conversations at startup
    // This prevents OMEMO errors and subscription bars when opening a bot chat
    private void fix_dedicated_bot_conversations() {
        if (registry == null) return;
        var cm = app.stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY);
        var presence_mgr = app.stream_interactor.get_module<PresenceManager>(PresenceManager.IDENTITY);
        var all_bots = registry.get_all_bots();

        foreach (BotInfo bot in all_bots) {
            if (bot.mode != "dedicated" || bot.jid == null) continue;

            try {
                Xmpp.Jid bot_jid = new Xmpp.Jid(bot.jid);

                // Find the owner account; fall back to first available if owner not found
                Xmpp.Jid? owner_jid = null;
                if (bot.owner_jid != null) {
                    try {
                        owner_jid = new Xmpp.Jid(bot.owner_jid);
                    } catch (Error e) { /* ignore */ }
                }

                // Only create/fix conversation if owner account is active
                var accounts = app.stream_interactor.get_accounts();
                Account? target_account = null;
                foreach (Account account in accounts) {
                    if (owner_jid != null && account.bare_jid.equals(owner_jid)) {
                        target_account = account;
                        break;
                    }
                }
                if (target_account == null) continue;

                // Check if conversation exists and fix encryption
                Conversation? conv = cm.get_conversation(bot_jid, target_account, Conversation.Type.CHAT);
                if (conv != null && conv.encryption != Entities.Encryption.OMEMO) {
                    conv.encryption = Entities.Encryption.OMEMO;
                    message("Botmother: Fixed encryption=OMEMO for bot conversation %s", bot.jid);
                }

                // Auto-approve any pending subscription from the bot
                if (presence_mgr.exists_subscription_request(target_account, bot_jid)) {
                    message("Botmother: Auto-approving pending subscription from bot %s at startup", bot.jid);
                    presence_mgr.approve_subscription(target_account, bot_jid);
                    presence_mgr.request_subscription(target_account, bot_jid);
                }

                // Also set roster name if available (preserve subscription state)
                if (bot.name != null) {
                    var roster_mgr = app.stream_interactor.get_module<RosterManager>(RosterManager.IDENTITY);
                    var item = roster_mgr.get_roster_item(target_account, bot_jid);
                    if (item == null) {
                        roster_mgr.add_jid(target_account, bot_jid, bot.name);
                        message("Botmother: Set roster name '%s' for bot %s at startup", bot.name, bot.jid);
                    } else if (item.name == null || item.name == "") {
                        roster_mgr.set_jid_handle(target_account, bot_jid, bot.name);
                        message("Botmother: Updated roster name '%s' for bot %s at startup", bot.name, bot.jid);
                    }
                }
            } catch (Error e) {
                warning("Botmother: Error fixing bot conversation for %d: %s", bot.id, e.message);
            }
        }
    }

    // Create and pin a self-chat conversation for accounts that:
    //   1. Have at least one bot registered AND
    //   2. Have per-account Botmother enabled (default = true)
    private void ensure_botmother_conversations() {
        var cm = app.stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY);

        // Wait a moment for accounts to be loaded
        GLib.Timeout.add(2000, () => {
            foreach (Account account in app.stream_interactor.get_accounts()) {
                string jid_str = account.bare_jid.to_string();

                // Only pin if per-account enabled AND has active personal bots
                // Dedicated bots have their own JID/conversation, no self-chat needed
                var bots = registry.get_bots_by_owner(jid_str);
                int active_personal_count = 0;
                foreach (BotInfo b in bots) {
                    if (b.status == "active" && b.mode == "personal") {
                        active_personal_count++;
                    }
                }
                if (active_personal_count == 0 || !is_account_enabled(jid_str)) {
                    message("Botmother: Skipping self-chat for %s (active_personal=%d, enabled=%s)",
                        jid_str, active_personal_count, is_account_enabled(jid_str).to_string());
                    // If self-chat was previously pinned, unpin it
                    unpin_botmother_conversation(jid_str);
                    continue;
                }

                Xmpp.Jid self_jid = account.bare_jid;
                Conversation conversation = cm.create_conversation(self_jid, account, Conversation.Type.CHAT);
                cm.start_conversation(conversation);

                // Pin it if not already pinned (pinned > 0 means pinned)
                if (conversation.pinned == 0) {
                    conversation.pinned = 1;
                    conversation.notify_property("pinned");
                }

                message("Botmother: Self-chat for %s ready (pinned, %d bot(s))", jid_str, bots.size);
            }
            return false; // Don't repeat
        });
    }

    // Called when a bot is deleted -- close bot conversation + unpin self-chat if no bots left
    private void on_bot_deleted(string owner_jid, int bot_id, string? bot_jid, string? bot_mode) {
        if (registry == null) return;

        // For dedicated bots: close the conversation with the bot JID
        if (bot_mode == "dedicated" && bot_jid != null) {
            try {
                Xmpp.Jid jid = new Xmpp.Jid(bot_jid);
                var cm = app.stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY);
                var roster_mgr = app.stream_interactor.get_module<RosterManager>(RosterManager.IDENTITY);
                foreach (Account account in app.stream_interactor.get_accounts()) {
                    // Close the conversation
                    Conversation? conv = cm.get_conversation(jid, account, Conversation.Type.CHAT);
                    if (conv != null) {
                        if (conv.pinned > 0) {
                            conv.pinned = 0;
                            conv.notify_property("pinned");
                        }
                        cm.close_conversation(conv);
                        message("Botmother: Closed bot conversation %s for %s", bot_jid, owner_jid);
                    }
                    // Remove from roster
                    roster_mgr.remove_jid(account, jid);
                }
            } catch (Error e) {
                warning("Botmother: Error closing bot conversation %s: %s", bot_jid, e.message);
            }

            // Clean up OMEMO state (in-memory + persisted keys)
            uint32 device_id = 0;
            if (session_pool != null && session_pool.bot_omemo != null) {
                device_id = session_pool.bot_omemo.get_device_id(bot_id);
                session_pool.bot_omemo.cleanup_bot(bot_id);
            }

            // Delete PubSub nodes (device list, bundle, avatar) then disconnect
            if (session_pool != null) {
                session_pool.cleanup_pubsub_and_disconnect(bot_id, device_id);
            }

            // Clean up bot settings (avatar etc.)
            registry.delete_setting("bot_avatar:%d".printf(bot_id));
            registry.delete_setting("bot_avatar_type:%d".printf(bot_id));

            // Clean up AI and Telegram integration settings
            if (message_router != null) {
                message_router.ai.cleanup(bot_id);
                message_router.telegram.cleanup(bot_id);
            }

            // Store deleted JID for cleanup on next startup (in case close didn't persist)
            string deleted_list = registry.get_setting("deleted_bot_jids") ?? "";
            if (deleted_list.length > 0) {
                deleted_list += "," + bot_jid;
            } else {
                deleted_list = bot_jid;
            }
            registry.set_setting("deleted_bot_jids", deleted_list);
        }

        // If no personal bots left for this owner, unpin self-chat
        var remaining = registry.get_bots_by_owner(owner_jid);
        int remaining_personal = 0;
        foreach (BotInfo rb in remaining) {
            if (rb.status == "active" && rb.mode == "personal") remaining_personal++;
        }
        if (remaining_personal == 0) {
            message("Botmother: No personal bots left for %s, unpinning self-chat", owner_jid);
            unpin_botmother_conversation(owner_jid);
        }
    }

    // Suppress subscription notifications for all known dedicated bot JIDs
    private void suppress_bot_subscriptions() {
        if (registry == null) return;
        var presence_mgr = app.stream_interactor.get_module<PresenceManager>(PresenceManager.IDENTITY);
        var all_bots = registry.get_all_bots();
        foreach (BotInfo bot in all_bots) {
            if (bot.mode == "dedicated" && bot.jid != null) {
                try {
                    Xmpp.Jid bot_jid = new Xmpp.Jid(bot.jid);
                    presence_mgr.suppress_subscription_notification(bot_jid);
                    message("Botmother: Suppressed subscription notification for bot %s", bot.jid);
                } catch (Error e) {
                    // ignore
                }
            }
        }
    }

    // Clean up conversations and roster entries for previously deleted bots
    private void cleanup_orphaned_bot_conversations() {
        if (registry == null) return;
        string? deleted_list = registry.get_setting("deleted_bot_jids");
        if (deleted_list == null || deleted_list.strip() == "") return;

        var cm = app.stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY);
        var roster_mgr = app.stream_interactor.get_module<RosterManager>(RosterManager.IDENTITY);
        string[] jids = deleted_list.split(",");
        foreach (string jid_str in jids) {
            string trimmed = jid_str.strip();
            if (trimmed == "") continue;
            try {
                Xmpp.Jid jid = new Xmpp.Jid(trimmed);
                foreach (Account account in app.stream_interactor.get_accounts()) {
                    // Close conversation
                    Conversation? conv = cm.get_conversation(jid, account, Conversation.Type.CHAT);
                    if (conv != null) {
                        if (conv.active) {
                            conv.pinned = 0;
                            conv.notify_property("pinned");
                            cm.close_conversation(conv);
                            message("Botmother: Cleaned up orphaned bot conversation %s", trimmed);
                        }
                    }
                    // Remove from roster / contact list
                    roster_mgr.remove_jid(account, jid);
                    message("Botmother: Removed orphaned bot %s from roster", trimmed);
                }
            } catch (Error e) {
                // ignore
            }
        }
        // Clear the list after cleanup
        registry.set_setting("deleted_bot_jids", "");
    }

    // Called when per-account Botmother is toggled on/off via the API
    private void on_account_toggled(string account_jid, bool account_enabled) {
        if (registry == null) return;
        var cm = app.stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY);

        if (account_enabled) {
            // Re-pin only if the account has active personal bots
            var bots = registry.get_bots_by_owner(account_jid);
            int personal_count = 0;
            foreach (BotInfo b in bots) {
                if (b.status == "active" && b.mode == "personal") personal_count++;
            }
            if (personal_count > 0) {
                pin_botmother_conversation(account_jid);
            } else {
                unpin_botmother_conversation(account_jid);
            }

            // Re-show active dedicated bot conversations
            foreach (BotInfo b in bots) {
                if (b.mode == "dedicated" && b.jid != null && b.status == "active") {
                    try {
                        Xmpp.Jid bot_jid = new Xmpp.Jid(b.jid);
                        foreach (Account account in app.stream_interactor.get_accounts()) {
                            if (account.bare_jid.to_string() != account_jid) continue;
                            Conversation c = cm.create_conversation(bot_jid, account, Conversation.Type.CHAT);
                            c.encryption = Entities.Encryption.NONE;
                            cm.start_conversation(c);
                        }
                    } catch (Error e) { /* ignore */ }
                }
            }

            // Reconnect dedicated bot streams
            if (session_pool != null) {
                foreach (BotInfo b in bots) {
                    if (b.mode == "dedicated" && b.status == "active") {
                        session_pool.connect_dedicated.begin(b);
                    }
                }
            }
        } else {
            // Unpin self-chat
            unpin_botmother_conversation(account_jid);

            // Close all dedicated bot conversations for this account
            var bots = registry.get_bots_by_owner(account_jid);
            foreach (BotInfo b in bots) {
                if (b.mode == "dedicated" && b.jid != null) {
                    try {
                        Xmpp.Jid bot_jid = new Xmpp.Jid(b.jid);
                        foreach (Account account in app.stream_interactor.get_accounts()) {
                            if (account.bare_jid.to_string() != account_jid) continue;
                            Conversation? c = cm.get_conversation(bot_jid, account, Conversation.Type.CHAT);
                            if (c != null) {
                                cm.close_conversation(c);
                                message("Botmother: Closed bot chat %s (account disabled)", b.jid);
                            }
                        }
                    } catch (Error e) { /* ignore */ }
                }
            }

            // Disconnect dedicated bot streams for this account
            if (session_pool != null) {
                foreach (BotInfo b in bots) {
                    if (b.mode == "dedicated") {
                        session_pool.disconnect_dedicated(b.id);
                    }
                }
            }
        }
    }

    // Called when a bot's status changes (active/disabled)
    private void on_bot_status_changed(int bot_id, string new_status) {
        if (registry == null) return;
        BotInfo? bot = registry.get_bot_by_id(bot_id);
        if (bot == null || bot.mode != "dedicated" || bot.jid == null) return;

        var cm = app.stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY);

        if (new_status == "active") {
            // Re-open conversation and reconnect stream
            try {
                Xmpp.Jid bot_jid = new Xmpp.Jid(bot.jid);
                foreach (Account account in app.stream_interactor.get_accounts()) {
                    Conversation c = cm.create_conversation(bot_jid, account, Conversation.Type.CHAT);
                    // BUG-11 fix: Set OMEMO immediately (on_dedicated_bot_ready will confirm it)
                    c.encryption = Entities.Encryption.OMEMO;
                    cm.start_conversation(c);
                }
            } catch (Error e) { /* ignore */ }
            if (session_pool != null) {
                session_pool.connect_dedicated.begin(bot);
            }
            message("Botmother: Bot %d activated, conversation reopened", bot_id);
        } else {
            // Close conversation and disconnect stream
            try {
                Xmpp.Jid bot_jid = new Xmpp.Jid(bot.jid);
                foreach (Account account in app.stream_interactor.get_accounts()) {
                    Conversation? c = cm.get_conversation(bot_jid, account, Conversation.Type.CHAT);
                    if (c != null) {
                        cm.close_conversation(c);
                    }
                }
            } catch (Error e) { /* ignore */ }
            if (session_pool != null) {
                session_pool.disconnect_dedicated(bot_id);
            }
            message("Botmother: Bot %d deactivated, conversation closed", bot_id);
        }
    }

    // Pin the self-chat for a single account JID
    private void pin_botmother_conversation(string jid_str) {
        var cm = app.stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY);
        foreach (Account account in app.stream_interactor.get_accounts()) {
            if (account.bare_jid.to_string() != jid_str) continue;
            Xmpp.Jid self_jid = account.bare_jid;
            Conversation conversation = cm.create_conversation(self_jid, account, Conversation.Type.CHAT);
            cm.start_conversation(conversation);
            if (conversation.pinned == 0) {
                conversation.pinned = 1;
                conversation.notify_property("pinned");
                message("Botmother: Pinned self-chat for %s", jid_str);
            }
        }
    }

    // Unpin and close the self-chat for a single account JID
    private void unpin_botmother_conversation(string jid_str) {
        var cm = app.stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY);
        foreach (Account account in app.stream_interactor.get_accounts()) {
            if (account.bare_jid.to_string() != jid_str) continue;
            Xmpp.Jid self_jid = account.bare_jid;
            Conversation? conversation = cm.get_conversation(self_jid, account, Conversation.Type.CHAT);
            if (conversation != null) {
                if (conversation.pinned > 0) {
                    conversation.pinned = 0;
                    conversation.notify_property("pinned");
                }
                cm.close_conversation(conversation);
                message("Botmother: Closed self-chat for %s", jid_str);
            }
        }
    }

    // Unpin and close self-chats for ALL accounts (used when Botmother is globally disabled)
    private void unpin_all_botmother_conversations() {
        var cm = app.stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY);
        foreach (Account account in app.stream_interactor.get_accounts()) {
            Xmpp.Jid self_jid = account.bare_jid;
            Conversation? conversation = cm.get_conversation(self_jid, account, Conversation.Type.CHAT);
            if (conversation != null) {
                if (conversation.pinned > 0) {
                    conversation.pinned = 0;
                    conversation.notify_property("pinned");
                }
                cm.close_conversation(conversation);
                message("Botmother: Closed self-chat for %s (global shutdown)", account.bare_jid.to_string());
            }
        }
    }

    // Debounced restart of the HTTP API server when settings change
    private void on_api_setting_changed() {
        if (!enabled || http_server == null) return;
        // Debounce: wait 500ms so multiple rapid changes (mode+port) combine
        if (api_restart_timeout_id != 0) {
            GLib.Source.remove(api_restart_timeout_id);
        }
        api_restart_timeout_id = GLib.Timeout.add(500, () => {
            api_restart_timeout_id = 0;
            restart_http_server();
            return false;
        });
    }

    private void restart_http_server() {
        if (http_server == null) return;

        http_server.stop();

        var s = app.settings;
        uint16 port = (uint16) s.api_port;
        string mode = s.api_mode;
        string tls_cert = s.api_tls_cert;
        string tls_key = s.api_tls_key;

        try {
            http_server.start(port, mode, tls_cert, tls_key);
            if (mode == "network") {
                message("Botmother: API restarted - HTTPS on 0.0.0.0:%u (TLS)", port);
            } else {
                message("Botmother: API restarted - HTTP on localhost:%u", port);
            }
        } catch (Error e) {
            if (mode == "network") {
                warning("Botmother: Network mode failed (%s), falling back to localhost", e.message);
                try {
                    http_server.start(port, "local", "", "");
                    message("Botmother: API restarted - HTTP on localhost:%u (fallback)", port);
                } catch (Error e2) {
                    warning("Botmother: Failed to restart HTTP server: %s", e2.message);
                }
            } else {
                warning("Botmother: Failed to restart HTTP server: %s", e.message);
            }
        }
    }

    public void shutdown() {
        // Cancel pending API restart
        if (api_restart_timeout_id != 0) {
            GLib.Source.remove(api_restart_timeout_id);
            api_restart_timeout_id = 0;
        }

        // Unpin all Botmother self-chats when globally disabled
        unpin_all_botmother_conversations();

        if (http_server != null) {
            http_server.stop();
        }
        if (session_pool != null) {
            session_pool.disconnect_all();
        }
        if (message_router != null) {
            message_router.shutdown();
        }
        if (webhook_dispatcher != null) {
            webhook_dispatcher.shutdown();
        }
        enabled = false;
    }

    public void rekey_database(string new_key) throws Error {
        if (registry != null) {
            registry.rekey(new_key);
        }
    }

    public void checkpoint_database() {
        if (registry != null) {
            try {
                registry.exec("PRAGMA wal_checkpoint(TRUNCATE)");
            } catch (Error e) {
                warning("BotFeatures: WAL checkpoint failed: %s", e.message);
            }
        }
    }
}

}
