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
 * Each MQTT connection (per-account or standalone) gets its own
 * bot conversation with a UNIQUE bare JID:
 *
 *   Per-account: mqtt-<escaped_bare_jid>@mqtt.local
 *                e.g. mqtt-user_at_example.org@mqtt.local
 *   Standalone:  mqtt-standalone@mqtt.local
 *
 * ConversationManager strips resources for CHAT-type conversations,
 * so every bot MUST have a different bare JID (localpart) to prevent
 * ConversationManager from collapsing them into the same conversation.
 *
 * Domain check (counterpart.domainpart == "mqtt.local") matches
 * all bot conversations for command interception.
 */
public class MqttBotConversation : Object {

    /* Synthetic JID domain — will never collide with real XMPP */
    public const string BOT_DOMAIN = "mqtt.local";
    public const string BOT_LOCALPART_PREFIX = "mqtt-";

    /* Standalone uses a DIFFERENT bare JID so its Conversation never
     * collides with per-account bot conversations in ConversationManager.
     * Without this, ConversationManager strips the resource for CHAT-type
     * conversations and both resolve to mqtt-bot@mqtt.local on the same
     * account → same Conversation object → enable/disable cross-wiring
     * and mixed-up messages (BUG-CRITICAL). */
    public const string STANDALONE_LOCALPART = "mqtt-standalone";
    public const string STANDALONE_JID_STR = STANDALONE_LOCALPART + "@" + BOT_DOMAIN;

    public const string STANDALONE_KEY = "standalone";

    /* Back-references */
    private Plugin plugin;
    private Dino.Application app;

    /* Conversation per connection_key (account bare_jid or "standalone") */
    private HashMap<string, Conversation> bot_conversations =
        new HashMap<string, Conversation>();

    /* JID per connection_key (each has a unique bare JID) */
    private HashMap<string, Jid> bot_jids =
        new HashMap<string, Jid>();

    /* Standalone bare JID (constant) */
    private Jid? mqtt_standalone_bare_jid = null;

    /* ── Construction ────────────────────────────────────────────── */

    public MqttBotConversation(Plugin plugin) {
        this.plugin = plugin;
        this.app = plugin.app;

        try {
            mqtt_standalone_bare_jid = new Jid(STANDALONE_JID_STR);
        } catch (InvalidJidError e) {
            warning("MQTT Bot: Cannot create standalone JID: %s", e.message);
        }
    }

    /* ── Helpers ──────────────────────────────────────────────────── */

    /**
     * Activate a bot conversation and pin it to the sidebar.
     * Central helper — avoids 4x duplication of the start+pin+notify
     * pattern (REVIEW_CHECKLIST §10.3).
     *
     * Returns false only if ConversationManager is unavailable.
     */
    private bool activate_and_pin(Conversation conv) {
        var cm = app.stream_interactor.get_module<ConversationManager>(
            ConversationManager.IDENTITY);
        if (cm == null) {
            warning("MQTT Bot: ConversationManager unavailable — cannot activate conversation");
            return false;
        }
        cm.start_conversation(conv);
        conv.pinned = 1;
        conv.notify_property("pinned");
        return true;
    }

    /* ── Display name ────────────────────────────────────────────── */

    /**
     * Compute the sidebar display name for a bot conversation.
     * Uses bot_name from MqttConnectionConfig, appends context:
     *   Standalone → "MQTT Bot (Standalone)"
     *   Per-account → "MQTT Bot (user@example.org)"
     */
    private string compute_display_name(string key, Account account) {
        string base_name = "MQTT Bot";

        if (key == STANDALONE_KEY) {
            var sa_config = plugin.get_standalone_config();
            if (sa_config.bot_name != null && sa_config.bot_name.strip() != "") {
                base_name = sa_config.bot_name;
            }
            return "%s (Standalone)".printf(base_name);
        } else {
            var acct_config = plugin.get_account_config(account);
            if (acct_config.bot_name != null && acct_config.bot_name.strip() != "") {
                base_name = acct_config.bot_name;
            }
            return "%s (%s)".printf(base_name, key);
        }
    }

    /* ── JID factory ─────────────────────────────────────────────── */

    /**
     * Escape an account bare JID for use as a JID localpart.
     * Replaces '@' with '_at_' since '@' is not allowed in localparts.
     *   user@example.org → user_at_example.org
     */
    private static string escape_for_localpart(string bare_jid) {
        return bare_jid.replace("@", "_at_");
    }

    /**
     * Reverse the localpart escaping to recover the account bare JID.
     *   user_at_example.org → user@example.org
     */
    private static string unescape_from_localpart(string escaped) {
        return escaped.replace("_at_", "@");
    }

    /**
     * Create or retrieve the bot JID for a given connection key.
     *
     * Every bot gets a UNIQUE bare JID so ConversationManager
     * (which strips resources for CHAT-type conversations) never
     * collapses different bots into the same conversation:
     *
     *   Per-account: mqtt-<escaped_bare_jid>@mqtt.local
     *                e.g. mqtt-user_at_example.org@mqtt.local
     *   Standalone:  mqtt-standalone@mqtt.local
     */
    private Jid? make_bot_jid(string connection_key) {
        if (bot_jids.has_key(connection_key)) {
            return bot_jids[connection_key];
        }

        try {
            Jid jid;
            if (connection_key == STANDALONE_KEY) {
                /* Standalone: use dedicated bare JID */
                if (mqtt_standalone_bare_jid == null) return null;
                jid = mqtt_standalone_bare_jid;
            } else {
                /* Per-account: unique bare JID per account */
                string escaped = escape_for_localpart(connection_key);
                jid = new Jid(BOT_LOCALPART_PREFIX + escaped + "@" + BOT_DOMAIN);
            }
            bot_jids[connection_key] = jid;
            return jid;
        } catch (InvalidJidError e) {
            warning("MQTT Bot: Cannot create JID for '%s': %s",
                    connection_key, e.message);
            return null;
        }
    }

    /* ── Public API ──────────────────────────────────────────────── */

    /**
     * Get or create the bot conversation for the given account.
     *
     * Uses a unique bare JID per account:
     *   mqtt-<escaped_bare_jid>@mqtt.local
     * The conversation is activated (made visible in the sidebar)
     * and pinned so it doesn't disappear.
     *
     * The bot display name is read from the account's MqttConnectionConfig.
     */
    public Conversation? ensure_conversation(Account account) {
        string key = account.bare_jid.to_string();
        return ensure_conversation_for_key(key, account);
    }

    /**
     * Ensure the standalone bot (using first available account).
     * JID: mqtt-standalone@mqtt.local (different bare JID from per-account).
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

        return ensure_conversation_for_key(STANDALONE_KEY, target);
    }

    /**
     * Internal: create/get conversation for a connection key.
     *
     * Every bot has a unique bare JID:
     *   standalone  → mqtt-standalone@mqtt.local
     *   per-account → mqtt-<escaped_bare_jid>@mqtt.local
     * So ConversationManager bare-JID lookup always finds the right one.
     */
    private Conversation? ensure_conversation_for_key(string key, Account account) {
        if (bot_conversations.has_key(key)) {
            Conversation cached = bot_conversations[key];
            /* Refresh display name (may have changed in settings) */
            cached.nickname = compute_display_name(key, account);
            /* BUG-FIX: If the user manually closed the bot from the sidebar,
             * the conversation is still in our HashMap but inactive.
             * Reactivate it so it appears in the sidebar again. */
            if (!cached.active) {
                if (!activate_and_pin(cached)) return null;
                message("MQTT Bot: Reactivated closed conversation for '%s'", key);
            }
            return cached;
        }

        Jid? jid = make_bot_jid(key);
        if (jid == null) return null;

        var cm = app.stream_interactor.get_module<ConversationManager>(
            ConversationManager.IDENTITY);
        if (cm == null) {
            warning("MQTT Bot: ConversationManager unavailable");
            return null;
        }

        /* Try bare JID first — matches DB-loaded conversations after restart */
        Conversation? existing = cm.get_conversation(
            jid.bare_jid, account, Conversation.Type.CHAT);
        if (existing != null) {
            bot_conversations[key] = existing;
            existing.nickname = compute_display_name(key, account);
            activate_and_pin(existing);
            message("MQTT Bot: Reusing DB-loaded conversation for '%s' (conv.id=%d, name='%s')",
                    key, existing.id, existing.nickname);
            return existing;
        }

        /* No existing conversation — create new (first-time setup only) */
        Conversation conv = cm.create_conversation(
            jid, account, Conversation.Type.CHAT);
        conv.encryption = Encryption.NONE;
        conv.nickname = compute_display_name(key, account);

        activate_and_pin(conv);

        bot_conversations[key] = conv;

        /* Sanity check: ensure the ID is valid (not from a stale rowid) */
        if (conv.id <= 0) {
            warning("MQTT Bot: Conversation persist returned invalid id=%d for '%s' — DB conflict?",
                    conv.id, key);
        }

        message("MQTT Bot: Conversation created for '%s' (JID=%s, conv.id=%d)",
                key, jid.to_string(), conv.id);
        return conv;
    }

    /**
     * Re-open (re-activate) the bot conversation for a specific account.
     * If the user closed the bot in the sidebar, this brings it back.
     */
    public Conversation? reopen_conversation(Account account) {
        string key = account.bare_jid.to_string();
        return reopen_for_key(key, account);
    }

    /**
     * Re-open the standalone bot conversation.
     */
    public Conversation? reopen_standalone_conversation() {
        var accounts = app.stream_interactor.get_accounts();
        if (accounts.size == 0) return null;

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
        return reopen_for_key(STANDALONE_KEY, target);
    }

    /**
     * Internal: re-activate a bot conversation (or create if missing).
     * Checks whether the conversation is already active + pinned first
     * to avoid redundant work and misleading log messages.
     */
    private Conversation? reopen_for_key(string key, Account account) {
        if (bot_conversations.has_key(key)) {
            Conversation conv = bot_conversations[key];
            /* Refresh display name (may have changed in settings) */
            conv.nickname = compute_display_name(key, account);
            if (conv.active) {
                message("MQTT Bot: Conversation for '%s' already open — nothing to do", key);
                return conv;
            }
            activate_and_pin(conv);
            message("MQTT Bot: Conversation re-opened for '%s'", key);
            return conv;
        }

        /* Not in HashMap — create fresh */
        return ensure_conversation_for_key(key, account);
    }

    /**
     * Remove (deactivate) the bot conversation for a specific account.
     * The conversation is closed but history is preserved.
     */
    public void remove_conversation(string key) {
        if (!bot_conversations.has_key(key)) return;

        Conversation conv = bot_conversations[key];

        /* Unpin BEFORE closing — otherwise pinned conversations
         * can remain visible in the sidebar even after deactivation. */
        conv.pinned = 0;
        conv.notify_property("pinned");

        var cm = app.stream_interactor.get_module<ConversationManager>(
            ConversationManager.IDENTITY);
        if (cm == null) {
            warning("MQTT Bot: ConversationManager not available, cannot close conversation");
        } else {
            cm.close_conversation(conv);
        }
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
     * Matches all bot JIDs (per-account and standalone) by checking
     * the domain (mqtt.local).
     */
    public bool is_bot_conversation(Conversation conversation) {
        return conversation.counterpart.domainpart == BOT_DOMAIN;
    }

    /**
     * Get the bot JID for a specific connection key.
     */
    public Jid? get_bot_jid_for_key(string key) {
        return bot_jids.has_key(key) ? bot_jids[key] : make_bot_jid(key);
    }

    /**
     * Determine which connection key a bot conversation belongs to.
     *
     * For standalone: localpart is "mqtt-standalone" → return STANDALONE_KEY
     * For per-account: localpart encodes the account bare JID
     *   mqtt-user_at_example.org@mqtt.local → "user@example.org"
     *
     * Returns null if the conversation is not a bot conversation.
     */
    public string? get_connection_key(Conversation conversation) {
        if (!is_bot_conversation(conversation)) return null;

        string? localpart = conversation.counterpart.localpart;
        if (localpart == null) return null;

        /* Standalone: identified by localpart */
        if (localpart == STANDALONE_LOCALPART) {
            return STANDALONE_KEY;
        }

        /* Per-account: localpart = "mqtt-" + escaped bare JID */
        if (localpart.has_prefix(BOT_LOCALPART_PREFIX)) {
            string escaped = localpart.substring(BOT_LOCALPART_PREFIX.length);
            return unescape_from_localpart(escaped);
        }

        /* Fallback for old conversations with legacy localpart:
         * check which key maps to this conversation */
        foreach (var entry in bot_conversations.entries) {
            if (entry.value.id == conversation.id) {
                return entry.key;
            }
        }

        return null;
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
        /* Resolve topic alias from the connection's config */
        string display_topic = resolve_topic_alias(conversation, topic);

        /* Format: topic on first line, payload on second */
        string body = format_mqtt_message(display_topic, payload, priority);

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
        /* Safety: refuse to inject into a conversation with invalid ID.
         * This guards against the persist() / last_insert_rowid() bug
         * where the conversation could end up with the wrong ID. */
        if (conversation.id <= 0) {
            warning("MQTT BotConversation: inject_bot_message — conversation has invalid id=%d, refusing to inject",
                    conversation.id);
            return;
        }
        if (!is_bot_conversation(conversation)) {
            warning("MQTT BotConversation: inject_bot_message — conversation id=%d is NOT a bot conversation (counterpart=%s), refusing to inject",
                    conversation.id, conversation.counterpart.to_string());
            return;
        }

        var storage = app.stream_interactor.get_module<MessageStorage>(
            MessageStorage.IDENTITY);
        var cis = app.stream_interactor.get_module<ContentItemStore>(
            ContentItemStore.IDENTITY);
        var mp = app.stream_interactor.get_module<MessageProcessor>(
            MessageProcessor.IDENTITY);

        /* BUG-8 fix: bail out if any required module is unavailable */
        if (storage == null || cis == null || mp == null) {
            warning("MQTT BotConversation: inject_bot_message — required module(s) unavailable");
            return;
        }

        /* Use the conversation's counterpart JID (includes resource) */
        Jid bot_jid = conversation.counterpart;

        Message msg = new Message(body);
        msg.account = conversation.account;
        msg.counterpart = bot_jid;
        msg.ourpart = conversation.account.bare_jid;
        msg.direction = Message.DIRECTION_RECEIVED;
        msg.type_ = Message.Type.CHAT;
        msg.stanza_id = Xmpp.random_uuid();

        /* Remove milliseconds — matches Dino convention */
        DateTime now = new DateTime.from_unix_utc(MqttUtils.now_unix());
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
        /* Same safety guards as inject_bot_message() */
        if (conversation.id <= 0) {
            warning("MQTT BotConversation: inject_silent_message — conversation has invalid id=%d",
                    conversation.id);
            return;
        }
        if (!is_bot_conversation(conversation)) {
            warning("MQTT BotConversation: inject_silent_message — conversation id=%d is NOT a bot conversation",
                    conversation.id);
            return;
        }

        var storage = app.stream_interactor.get_module<MessageStorage>(
            MessageStorage.IDENTITY);
        var cis = app.stream_interactor.get_module<ContentItemStore>(
            ContentItemStore.IDENTITY);

        /* BUG-8 fix: bail out if any required module is unavailable */
        if (storage == null || cis == null) {
            warning("MQTT BotConversation: inject_silent_message — required module(s) unavailable");
            return;
        }

        /* Use the conversation's counterpart JID (includes resource) */
        Jid bot_jid = conversation.counterpart;

        Message msg = new Message(body);
        msg.account = conversation.account;
        msg.counterpart = bot_jid;
        msg.ourpart = conversation.account.bare_jid;
        msg.direction = Message.DIRECTION_RECEIVED;
        msg.type_ = Message.Type.CHAT;
        msg.stanza_id = Xmpp.random_uuid();

        DateTime now = new DateTime.from_unix_utc(MqttUtils.now_unix());
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
     *
     * @param display_topic  Resolved alias or formatted topic name
     */
    private string format_mqtt_message(string display_topic,
                                        string payload,
                                        MqttPriority priority = MqttPriority.NORMAL) {
        string trimmed = payload.strip();
        string icon = priority.to_icon();
        string prefix = (icon != "") ? "%s ".printf(icon) : "";

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
        return "%s[%s] %s".printf(prefix, display_topic, _("(empty)"));
    }

    /**
     * Resolve a topic to its display name using the connection's alias map.
     * Falls back to format_topic_display() if no alias is set.
     */
    private string resolve_topic_alias(Conversation conversation, string topic) {
        string? key = get_connection_key(conversation);
        if (key != null) {
            MqttConnectionConfig? cfg = null;
            if (key == STANDALONE_KEY) {
                cfg = plugin.get_standalone_config();
            } else {
                var accounts = plugin.app.stream_interactor.get_accounts();
                foreach (var acct in accounts) {
                    if (acct.bare_jid.to_string() == key) {
                        cfg = plugin.get_account_config(acct);
                        break;
                    }
                }
            }
            if (cfg != null) {
                string? alias = cfg.resolve_alias(topic);
                if (alias != null) return alias;
            }
        }
        return format_topic_display(topic);
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
        return MqttUtils.format_topic_display(topic);
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
