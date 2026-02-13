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
            registry = new BotRegistry(db_path);
        } catch (Error e) {
            warning("Botmother: Failed to open bot registry: %s", e.message);
            return;
        }

        token_manager = new TokenManager(registry);
        session_pool = new SessionPool(app);
        webhook_dispatcher = new WebhookDispatcher();
        message_router = new MessageRouter(app, registry, session_pool, webhook_dispatcher);
        http_server = new HttpServer(registry, token_manager, message_router, session_pool);
        botfather = new BotfatherHandler(app, registry, token_manager);
        message_router.set_botfather(botfather);

        // Start HTTP API on configured port
        uint16 port = (uint16) registry.get_setting_int("api_port", 7842);
        try {
            http_server.start(port);
            enabled = true;
            message("Botmother: HTTP API running on localhost:%u", port);
        } catch (Error e) {
            warning("Botmother: Failed to start HTTP server: %s", e.message);
        }

        // Ensure "Botmother" self-chat exists and is pinned for enabled accounts
        ensure_botmother_conversations();

        // When a bot is deleted, check if account has 0 bots left -> unpin
        registry.bot_deleted.connect(on_bot_deleted);

        // When per-account toggle changes -> pin or unpin
        registry.account_toggled.connect(on_account_toggled);

        // Watch for setting changes
        app.settings.notify["bot-features-enabled"].connect(on_setting_changed);
    }

    // Check whether Botmother is enabled for a specific account.
    // Default is true (enabled) when no explicit setting exists.
    private bool is_account_enabled(string jid_str) {
        if (registry == null) return false;
        string key = "botmother_account_enabled:" + jid_str;
        string? val = registry.get_setting(key);
        return (val == null || val == "true");
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

                // Only pin if per-account enabled AND has bots
                var bots = registry.get_bots_by_owner(jid_str);
                if (bots.size == 0 || !is_account_enabled(jid_str)) {
                    message("Botmother: Skipping self-chat for %s (bots=%d, enabled=%s)",
                        jid_str, bots.size, is_account_enabled(jid_str).to_string());
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

    // Called when a bot is deleted -- if the owner has no bots left, unpin self-chat
    private void on_bot_deleted(string owner_jid, int bot_id) {
        if (registry == null) return;
        var remaining = registry.get_bots_by_owner(owner_jid);
        if (remaining.size == 0) {
            message("Botmother: Last bot deleted for %s, unpinning self-chat", owner_jid);
            unpin_botmother_conversation(owner_jid);
        }
    }

    // Called when per-account Botmother is toggled on/off via the API
    private void on_account_toggled(string account_jid, bool account_enabled) {
        if (account_enabled) {
            // Re-pin if the account has bots
            if (registry == null) return;
            var bots = registry.get_bots_by_owner(account_jid);
            if (bots.size > 0) {
                pin_botmother_conversation(account_jid);
            }
        } else {
            // Unpin
            unpin_botmother_conversation(account_jid);
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

    public void shutdown() {
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
        enabled = false;
    }
}

}
