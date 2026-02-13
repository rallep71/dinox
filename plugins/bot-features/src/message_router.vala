using Gee;
using Xmpp;
using Dino.Entities;

namespace Dino.Plugins.BotFeatures {

public class MessageRouter : Object {

    private Dino.Application app;
    private BotRegistry registry;
    private SessionPool session_pool;
    private WebhookDispatcher webhook_dispatcher;
    private HashMap<int, ulong> message_handlers = new HashMap<int, ulong>();
    private uint cleanup_timer_id = 0;

    public MessageRouter(Dino.Application app, BotRegistry registry,
                         SessionPool session_pool, WebhookDispatcher webhook_dispatcher) {
        this.app = app;
        this.registry = registry;
        this.session_pool = session_pool;
        this.webhook_dispatcher = webhook_dispatcher;

        // Listen for incoming messages on all accounts
        app.stream_interactor.get_module<MessageProcessor>(MessageProcessor.IDENTITY)
            .received_pipeline.connect(new ReceivedMessageListener(this));

        // Periodic cleanup of old updates
        cleanup_timer_id = GLib.Timeout.add_seconds(3600, () => {
            registry.cleanup_old_updates();
            return GLib.Source.CONTINUE;
        });
    }

    public void shutdown() {
        if (cleanup_timer_id != 0) {
            GLib.Source.remove(cleanup_timer_id);
            cleanup_timer_id = 0;
        }
    }

    // --- Outbound: Bot -> XMPP ---

    public string? send_message(BotInfo bot, string to_jid_str, string text, string msg_type = "chat") {
        XmppStream? stream = session_pool.get_stream(bot);
        if (stream == null) {
            warning("BotRouter: No stream available for bot %d", bot.id);
            return null;
        }

        try {
            Jid to_jid = new Jid(to_jid_str);
            string message_id = Xmpp.random_uuid();

            Xmpp.MessageStanza message = new Xmpp.MessageStanza(message_id);
            message.to = to_jid;
            message.type_ = msg_type == "groupchat" ? Xmpp.MessageStanza.TYPE_GROUPCHAT : Xmpp.MessageStanza.TYPE_CHAT;
            message.body = text;

            stream.get_module<Xmpp.MessageModule>(Xmpp.MessageModule.IDENTITY).send_message.begin(stream, message);

            registry.update_bot_last_active(bot.id);
            registry.log_action(bot.id, "send_message", "to=%s".printf(to_jid_str));
            return message_id;
        } catch (Error e) {
            warning("BotRouter: Failed to send message: %s", e.message);
            return null;
        }
    }

    public string? send_file(BotInfo bot, string to_jid_str, string file_url, string? caption = null) {
        XmppStream? stream = session_pool.get_stream(bot);
        if (stream == null) return null;

        try {
            Jid to_jid = new Jid(to_jid_str);
            string message_id = Xmpp.random_uuid();

            Xmpp.MessageStanza message = new Xmpp.MessageStanza(message_id);
            message.to = to_jid;
            message.type_ = Xmpp.MessageStanza.TYPE_CHAT;

            // Include URL as body (XMPP clients will auto-detect as file)
            if (caption != null && caption.length > 0) {
                message.body = "%s\n%s".printf(caption, file_url);
            } else {
                message.body = file_url;
            }

            // Add OOB data (XEP-0066)
            StanzaNode x_node = new StanzaNode.build("x", "jabber:x:oob")
                .add_self_xmlns();
            StanzaNode url_node = new StanzaNode.build("url", "jabber:x:oob");
            url_node.put_node(new StanzaNode.text(file_url));
            x_node.put_node(url_node);
            if (caption != null) {
                StanzaNode desc_node = new StanzaNode.build("desc", "jabber:x:oob");
                desc_node.put_node(new StanzaNode.text(caption));
                x_node.put_node(desc_node);
            }
            message.stanza.put_node(x_node);

            stream.get_module<Xmpp.MessageModule>(Xmpp.MessageModule.IDENTITY).send_message.begin(stream, message);

            registry.log_action(bot.id, "send_file", "to=%s url=%s".printf(to_jid_str, file_url));
            return message_id;
        } catch (Error e) {
            warning("BotRouter: Failed to send file: %s", e.message);
            return null;
        }
    }

    public bool send_reaction(BotInfo bot, string to_jid_str, string message_id, string reaction) {
        XmppStream? stream = session_pool.get_stream(bot);
        if (stream == null) return false;

        try {
            Jid to_jid = new Jid(to_jid_str);
            var reactions = new Gee.ArrayList<string>();
            reactions.add(reaction);

            stream.get_module<Xmpp.Xep.Reactions.Module>(Xmpp.Xep.Reactions.Module.IDENTITY)
                .send_reaction.begin(stream, to_jid, Xmpp.MessageStanza.TYPE_CHAT, message_id, reactions);

            registry.log_action(bot.id, "send_reaction", "to=%s".printf(to_jid_str));
            return true;
        } catch (Error e) {
            warning("BotRouter: Failed to send reaction: %s", e.message);
            return false;
        }
    }

    public bool join_room(BotInfo bot, string room_jid_str, string? nick = null) {
        Account? account = session_pool.get_account_for_bot(bot);
        if (account == null) return false;

        try {
            Jid room_jid = new Jid(room_jid_str);
            string nickname = nick ?? (bot.name ?? "bot");

            app.stream_interactor.get_module<MucManager>(MucManager.IDENTITY)
                .join(account, room_jid, nickname, null);

            registry.log_action(bot.id, "join_room", room_jid_str);
            return true;
        } catch (Error e) {
            warning("BotRouter: Failed to join room: %s", e.message);
            return false;
        }
    }

    public bool leave_room(BotInfo bot, string room_jid_str) {
        Account? account = session_pool.get_account_for_bot(bot);
        if (account == null) return false;

        try {
            Jid room_jid = new Jid(room_jid_str);
            app.stream_interactor.get_module<MucManager>(MucManager.IDENTITY)
                .part(account, room_jid);

            registry.log_action(bot.id, "leave_room", room_jid_str);
            return true;
        } catch (Error e) {
            warning("BotRouter: Failed to leave room: %s", e.message);
            return false;
        }
    }

    // --- Inbound: XMPP -> Bot Update Queue / Webhook ---

    public void on_message_received(Entities.Message message, Conversation conversation) {
        // Route to all active bots owned by this account
        Account account = conversation.account;
        var bots = registry.get_all_active_bots();

        foreach (BotInfo bot in bots) {
            // Check if this bot is bound to this account
            Account? bot_account = session_pool.get_account_for_bot(bot);
            if (bot_account == null || !bot_account.equals(account)) continue;

            // Create update payload
            string payload = message_to_json(message, conversation);

            // Enqueue for long-poll (getUpdates)
            registry.enqueue_update(bot.id, "message", payload);

            // Dispatch webhook if configured
            if (bot.webhook_enabled && bot.webhook_url != null && bot.webhook_secret != null) {
                string full_payload = "{\"update_type\":\"message\",\"data\":%s}".printf(payload);
                webhook_dispatcher.dispatch(bot.webhook_url, bot.webhook_secret, full_payload);
            }
        }
    }

    private string message_to_json(Entities.Message message, Conversation conversation) {
        var sb = new StringBuilder();
        sb.append("{");
        sb.append("\"from\":\"%s\"".printf(escape_json(message.from.to_string())));
        sb.append(",\"to\":\"%s\"".printf(escape_json(message.to.to_string())));
        sb.append(",\"body\":\"%s\"".printf(escape_json(message.body ?? "")));
        sb.append(",\"type\":\"%s\"".printf(conversation.type_ == Conversation.Type.GROUPCHAT ? "groupchat" : "chat"));
        sb.append(",\"stanza_id\":\"%s\"".printf(escape_json(message.stanza_id ?? "")));
        sb.append(",\"timestamp\":%ld".printf((long) (message.time ?? new DateTime.now_utc()).to_unix()));
        sb.append("}");
        return sb.str;
    }

    private static string escape_json(string s) {
        return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r");
    }

    // Listener for the message pipeline
    private class ReceivedMessageListener : MessageListener {
        public string[] after_actions_const = {};
        public override string action_group { get { return "BOT_FEATURES"; } }
        public override string[] after_actions { get { return after_actions_const; } }

        private MessageRouter router;

        public ReceivedMessageListener(MessageRouter router) {
            this.router = router;
        }

        public override async bool run(Entities.Message message, Xmpp.MessageStanza stanza, Conversation conversation) {
            router.on_message_received(message, conversation);
            return false; // Don't consume the message
        }
    }
}

}
