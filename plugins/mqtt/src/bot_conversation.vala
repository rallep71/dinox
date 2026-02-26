/*
 * MqttBotConversation — Virtual bot contact for MQTT data in the chat view.
 *
 * Creates a pseudo-conversation with "MQTT Bot" that appears in the
 * regular conversation list.  Incoming MQTT messages are injected as
 * chat messages from the bot, and the user can type /mqtt commands.
 *
 * Copyright (C) 2026 Ralf Peter <dinox@handwerker.jetzt>
 */

using Gee;
using Xmpp;
using Dino.Entities;

namespace Dino.Plugins.Mqtt {

/**
 * Manages the lifecycle of the MQTT Bot conversation(s).
 *
 * In standalone mode, a single bot conversation is created using the
 * first available XMPP account.  In per-account mode, each account
 * gets its own bot conversation.
 */
public class MqttBotConversation : Object {

    /* Synthetic JID domain — will never collide with real XMPP */
    public const string BOT_DOMAIN = "mqtt.local";
    public const string BOT_LOCALPART = "mqtt-bot";
    public const string BOT_JID_STR = BOT_LOCALPART + "@" + BOT_DOMAIN;

    /* Back-references */
    private Plugin plugin;
    private Dino.Application app;

    /* Conversation per account bare_jid (or "standalone") */
    private HashMap<string, Conversation> bot_conversations =
        new HashMap<string, Conversation>();

    /* The Jid object (created once) */
    private Jid? mqtt_bot_jid = null;

    /* ── Construction ────────────────────────────────────────────── */

    public MqttBotConversation(Plugin plugin) {
        this.plugin = plugin;
        this.app = plugin.app;

        try {
            mqtt_bot_jid = new Jid(BOT_JID_STR);
        } catch (InvalidJidError e) {
            warning("MQTT Bot: Cannot create bot JID: %s", e.message);
        }
    }

    /* ── Public API ──────────────────────────────────────────────── */

    /**
     * Get or create the bot conversation for the given account.
     * The conversation is activated (made visible in the sidebar)
     * and pinned so it doesn't disappear.
     */
    public Conversation? ensure_conversation(Account account) {
        if (mqtt_bot_jid == null) return null;

        string key = account.bare_jid.to_string();
        if (bot_conversations.has_key(key)) {
            return bot_conversations[key];
        }

        var cm = app.stream_interactor.get_module<ConversationManager>(
            ConversationManager.IDENTITY);

        Conversation conv = cm.create_conversation(
            mqtt_bot_jid, account, Conversation.Type.CHAT);
        conv.encryption = Encryption.NONE;

        cm.start_conversation(conv);

        /* Pin so the bot stays at the top */
        conv.pinned = 1;
        conv.notify_property("pinned");

        bot_conversations[key] = conv;

        message("MQTT Bot: Conversation created for %s (conv.id=%d)", key, conv.id);
        return conv;
    }

    /**
     * Ensure the standalone bot (using first available account).
     */
    public Conversation? ensure_standalone_conversation() {
        var accounts = app.stream_interactor.get_accounts();
        if (accounts.size == 0) {
            warning("MQTT Bot: No XMPP accounts — cannot create bot conversation");
            return null;
        }

        /* Use first connected account, or first account if none connected */
        Account? target = null;
        foreach (var acct in accounts) {
            var state = app.stream_interactor.connection_manager
                .get_state(acct);
            if (state == ConnectionManager.ConnectionState.CONNECTED) {
                target = acct;
                break;
            }
        }
        if (target == null) target = accounts.first();

        return ensure_conversation(target);
    }

    /**
     * Remove (deactivate) the bot conversation for a specific account.
     * The conversation is closed but history is preserved.
     */
    public void remove_conversation(string key) {
        if (!bot_conversations.has_key(key)) return;

        Conversation conv = bot_conversations[key];
        var cm = app.stream_interactor.get_module<ConversationManager>(
            ConversationManager.IDENTITY);
        cm.close_conversation(conv);
        bot_conversations.unset(key);

        message("MQTT Bot: Conversation removed for %s", key);
    }

    /**
     * Remove all bot conversations (e.g. when MQTT is fully disabled).
     */
    public void remove_all() {
        var keys = new ArrayList<string>();
        keys.add_all(bot_conversations.keys);
        foreach (string key in keys) {
            remove_conversation(key);
        }
    }

    /**
     * Check if a conversation belongs to the MQTT bot.
     */
    public bool is_bot_conversation(Conversation conversation) {
        if (mqtt_bot_jid == null) return false;
        return conversation.counterpart.equals_bare(mqtt_bot_jid);
    }

    /**
     * Get the bot JID.
     */
    public Jid? get_bot_jid() {
        return mqtt_bot_jid;
    }

    /**
     * Get the bot conversation for a key (account JID or "standalone").
     */
    public Conversation? get_conversation(string key) {
        return bot_conversations.has_key(key) ? bot_conversations[key] : null;
    }

    /**
     * Get any active bot conversation (first found).
     */
    public Conversation? get_any_conversation() {
        if (bot_conversations.size == 0) return null;
        foreach (var entry in bot_conversations.entries) {
            return entry.value;
        }
        return null;
    }

    /* ── Message Injection ───────────────────────────────────────── */

    /**
     * Inject an incoming MQTT message into the bot conversation.
     * This creates a Message object that appears as a received chat
     * message from the bot, with the topic as a header line.
     *
     * @param conversation  The bot conversation
     * @param topic         MQTT topic name
     * @param payload       MQTT payload (UTF-8 text)
     * @param priority      Notification priority for this message
     */
    public void inject_mqtt_message(Conversation conversation,
                                     string topic, string payload,
                                     MqttPriority priority = MqttPriority.NORMAL) {
        /* Format: topic on first line, payload on second */
        string body = format_mqtt_message(topic, payload, priority);

        if (priority == MqttPriority.SILENT) {
            inject_silent_message(conversation, body);
        } else {
            inject_bot_message(conversation, body);
        }
    }

    /**
     * Inject a plain text response from the bot (for command replies).
     */
    public void inject_bot_message(Conversation conversation, string body) {
        var storage = app.stream_interactor.get_module<MessageStorage>(
            MessageStorage.IDENTITY);
        var cis = app.stream_interactor.get_module<ContentItemStore>(
            ContentItemStore.IDENTITY);
        var mp = app.stream_interactor.get_module<MessageProcessor>(
            MessageProcessor.IDENTITY);

        Message msg = new Message(body);
        msg.account = conversation.account;
        msg.counterpart = mqtt_bot_jid;
        msg.ourpart = conversation.account.bare_jid;
        msg.direction = Message.DIRECTION_RECEIVED;
        msg.type_ = Message.Type.CHAT;
        msg.stanza_id = Xmpp.random_uuid();

        /* Remove milliseconds — matches Dino convention */
        DateTime now = new DateTime.from_unix_utc(
            new DateTime.now_utc().to_unix());
        msg.time = now;
        msg.local_time = now;
        msg.marked = Message.Marked.NONE;
        msg.encryption = Encryption.NONE;

        /* Persist to DB */
        storage.add_message(msg, conversation);

        /* Create content_item row (makes it appear in timeline) */
        cis.insert_message(msg, conversation);

        /* Fire message_received → triggers announce_message in
         * ContentItemStore (UI update) and ConversationManager
         * (activates conversation, updates last_active). */
        mp.message_received(msg, conversation);
    }

    /**
     * Inject a silent message (no badge, no notification).
     * Message is persisted and visible in timeline but marked as read.
     */
    public void inject_silent_message(Conversation conversation, string body) {
        var storage = app.stream_interactor.get_module<MessageStorage>(
            MessageStorage.IDENTITY);
        var cis = app.stream_interactor.get_module<ContentItemStore>(
            ContentItemStore.IDENTITY);

        Message msg = new Message(body);
        msg.account = conversation.account;
        msg.counterpart = mqtt_bot_jid;
        msg.ourpart = conversation.account.bare_jid;
        msg.direction = Message.DIRECTION_RECEIVED;
        msg.type_ = Message.Type.CHAT;
        msg.stanza_id = Xmpp.random_uuid();

        DateTime now = new DateTime.from_unix_utc(
            new DateTime.now_utc().to_unix());
        msg.time = now;
        msg.local_time = now;
        msg.marked = Message.Marked.READ;
        msg.encryption = Encryption.NONE;

        storage.add_message(msg, conversation);
        cis.insert_message(msg, conversation);

        /* Advance read pointer so no badge/notification appears */
        var latest = cis.get_latest(conversation);
        if (latest != null) {
            conversation.read_up_to_item = latest.id;
        }

        /* Do NOT call mp.message_received() — this suppresses the
         * notification pipeline. The message is still visible when
         * the user opens the conversation. */
    }

    /* ── Message Formatting ──────────────────────────────────────── */

    /**
     * Format an MQTT message for display in the chat bubble.
     * Topic is shown as a bracketed header, payload below.
     * Alert/Critical messages get a priority icon prefix.
     */
    private string format_mqtt_message(string topic, string payload,
                                        MqttPriority priority = MqttPriority.NORMAL) {
        string trimmed = payload.strip();
        string icon = priority.to_icon();
        string prefix = (icon != "") ? "%s ".printf(icon) : "";

        /* Format topic — Prosody uses HOST/TYPE/NODE format */
        string display_topic = format_topic_display(topic);

        /* Try to detect JSON and pretty-print key values */
        if (trimmed.has_prefix("{") && trimmed.has_suffix("}")) {
            string? pretty = try_format_json(trimmed);
            if (pretty != null) {
                return "%s[%s]\n%s".printf(prefix, display_topic, pretty);
            }
        }

        /* Plain text */
        if (trimmed.length > 0) {
            return "%s[%s]\n%s".printf(prefix, display_topic, trimmed);
        }
        return "%s[%s] (empty)".printf(prefix, display_topic);
    }

    /**
     * Format a topic for human-readable display.
     *
     * Prosody mod_pubsub_mqtt bridges use the format:
     *   HOST/TYPE/NODE → e.g. "example.com/pubsub/home/sensors/temp"
     *
     * This method detects the Prosody format and shows a cleaner version:
     *   "example.com/pubsub/home/sensors/temp" → "home/sensors/temp (PubSub)"
     *
     * Standard MQTT topics pass through unchanged.
     */
    private string format_topic_display(string topic) {
        /* Detect Prosody format: starts with a hostname followed by /pubsub/ */
        if (topic.contains("/pubsub/")) {
            int pubsub_idx = topic.index_of("/pubsub/");
            if (pubsub_idx > 0) {
                string host = topic.substring(0, pubsub_idx);
                string node = topic.substring(pubsub_idx + 8);  /* skip /pubsub/ */
                /* Verify host looks like a domain (contains a dot) */
                if (host.contains(".") && node.length > 0) {
                    return "%s (PubSub@%s)".printf(node, host);
                }
            }
        }
        return topic;
    }

    /**
     * Simple JSON key-value formatter.
     * For {"temp": 22.1, "unit": "°C"} → "temp: 22.1\nunit: °C"
     * Returns null if parsing fails.
     */
    private string? try_format_json(string json_str) {
        try {
            var parser = new Json.Parser();
            parser.load_from_data(json_str, -1);
            var root = parser.get_root();
            if (root == null || root.get_node_type() != Json.NodeType.OBJECT) {
                return null;
            }

            var obj = root.get_object();
            var sb = new StringBuilder();
            bool first = true;

            foreach (string member in obj.get_members()) {
                if (!first) sb.append("\n");
                first = false;

                var node = obj.get_member(member);
                if (node.get_node_type() == Json.NodeType.VALUE) {
                    var val_type = node.get_value_type();
                    if (val_type == typeof(string)) {
                        sb.append("%s: %s".printf(member, node.get_string()));
                    } else if (val_type == typeof(int64)) {
                        sb.append("%s: %s".printf(member,
                                   node.get_int().to_string()));
                    } else if (val_type == typeof(double)) {
                        sb.append("%s: %.2f".printf(member, node.get_double()));
                    } else if (val_type == typeof(bool)) {
                        sb.append("%s: %s".printf(member,
                                   node.get_boolean() ? "true" : "false"));
                    } else {
                        sb.append("%s: %s".printf(member, json_str));
                    }
                } else {
                    /* Nested object/array: show raw */
                    var gen = new Json.Generator();
                    gen.set_root(node);
                    sb.append("%s: %s".printf(member, gen.to_data(null)));
                }
            }

            return sb.str;
        } catch (GLib.Error e) {
            return null;
        }
    }
}

}
