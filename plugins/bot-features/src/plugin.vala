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

        // Initialize core components
        string db_path = GLib.Path.build_filename(
            GLib.Environment.get_user_data_dir(), "dinox", "bot_registry.db"
        );
        try {
            registry = new BotRegistry(db_path);
        } catch (Error e) {
            warning("BotFeatures: Failed to open bot registry: %s", e.message);
            return;
        }

        token_manager = new TokenManager(registry);
        session_pool = new SessionPool(app);
        webhook_dispatcher = new WebhookDispatcher();
        message_router = new MessageRouter(app, registry, session_pool, webhook_dispatcher);
        http_server = new HttpServer(registry, token_manager, message_router, session_pool);
        botfather = new BotfatherHandler(app, registry, token_manager);

        // Start HTTP API on configured port
        uint16 port = (uint16) registry.get_setting_int("api_port", 7842);
        try {
            http_server.start(port);
            enabled = true;
            message("BotFeatures: HTTP API running on localhost:%u", port);
        } catch (Error e) {
            warning("BotFeatures: Failed to start HTTP server: %s", e.message);
        }
    }

    public void shutdown() {
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
