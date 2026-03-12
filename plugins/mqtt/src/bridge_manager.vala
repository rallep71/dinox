/*
 * MqttBridgeManager — Forward MQTT messages to real XMPP contacts.
 *
 * Bridge rules map MQTT topics to XMPP JIDs.  When a message arrives
 * on a bridged topic, it is automatically sent as a chat message to
 * the configured XMPP contact.
 *
 * Commands (handled by MqttCommandHandler):
 *   /mqtt bridge <topic> <jid>  — Create a bridge rule
 *   /mqtt bridges               — List bridge rules
 *   /mqtt rmbridge <number>     — Remove a bridge rule
 *
 * Copyright (C) 2026 Ralf Peter <dinox@handwerker.jetzt>
 */

using Gee;
using Xmpp;
using Dino.Entities;

namespace Dino.Plugins.Mqtt {

/**
 * A single bridge rule: MQTT topic → XMPP JID.
 */
public class BridgeRule : Object {
    public string id;
    public string topic;        /* MQTT topic pattern (exact or wildcard) */
    public string target_jid;   /* Bare JID of the XMPP recipient */
    public bool enabled;
    public string? format;      /* Optional format: "full" (default), "payload", "short" */
    public string? alias;       /* Human-readable display name for the topic */
    public string client_label; /* Which MQTT client owns this rule: "standalone" or account bare JID */
    public string? send_account; /* Bare JID of the XMPP account to send from (mandatory for delivery) */

    public BridgeRule() {
        id = Xmpp.random_uuid();
        enabled = true;
        format = "full";
        alias = null;
        client_label = "standalone";
        send_account = null;
    }

    /**
     * Check if this rule matches an MQTT topic.
     */
    public bool matches_topic(string incoming_topic) {
        return MqttUtils.topic_matches(topic, incoming_topic);
    }

    /**
     * Format the bridged message body.
     * Uses the alias (if set) instead of the raw topic path.
     */
    public string format_message(string topic_name, string payload) {
        string display = (alias != null && alias.strip() != "") ? alias : topic_name;
        return MqttUtils.format_bridge_message(format ?? "full", display, payload);
    }

    /**
     * Serialize to JSON.
     */
    public Json.Object to_json() {
        var obj = new Json.Object();
        obj.set_string_member("id", id);
        obj.set_string_member("topic", topic);
        obj.set_string_member("target_jid", target_jid);
        obj.set_boolean_member("enabled", enabled);
        if (format != null) obj.set_string_member("format", format);
        if (alias != null) obj.set_string_member("alias", alias);
        obj.set_string_member("client_label", client_label);
        if (send_account != null) obj.set_string_member("send_account", send_account);
        return obj;
    }

    /**
     * Deserialize from JSON.
     */
    public static BridgeRule? from_json(Json.Object obj) {
        var rule = new BridgeRule();

        if (!obj.has_member("topic") || !obj.has_member("target_jid"))
            return null;

        if (obj.has_member("id"))
            rule.id = obj.get_string_member("id");
        rule.topic = obj.get_string_member("topic");
        rule.target_jid = obj.get_string_member("target_jid");

        if (obj.has_member("enabled"))
            rule.enabled = obj.get_boolean_member("enabled");
        if (obj.has_member("format"))
            rule.format = obj.get_string_member("format");
        if (obj.has_member("alias"))
            rule.alias = obj.get_string_member("alias");
        if (obj.has_member("client_label"))
            rule.client_label = obj.get_string_member("client_label");
        if (obj.has_member("send_account"))
            rule.send_account = obj.get_string_member("send_account");

        return rule;
    }
}


/**
 * Manages bridge rules and forwards MQTT messages to XMPP contacts.
 */
public class MqttBridgeManager : Object {

    /* DB key for bridge rules JSON */
    internal const string KEY_BRIDGES = "mqtt_bridges";

    /* Back-references */
    private Plugin plugin;

    /* Bridge rules (loaded from DB) */
    private ArrayList<BridgeRule> rules = new ArrayList<BridgeRule>();

    /* Rate limiting: track last send time per rule to avoid flooding.
     * int64? is required because Vala generics need boxed (nullable) types. */
    private HashMap<string, int64?> last_send_times =
        new HashMap<string, int64?>();
    private const int64 MIN_SEND_INTERVAL_MS = 200; /* 200ms — fast enough for request/response flows */

    /* Pending messages queued when no XMPP account is connected.
     * Drained automatically when an account connects (flush_pending). */
    private struct PendingMsg {
        public string source;
        public string target_jid;
        public string body;
    }
    private ArrayList<PendingMsg?> pending_messages = new ArrayList<PendingMsg?>();
    private const int MAX_PENDING = 50;  /* prevent unbounded growth */

    /* ── Construction ────────────────────────────────────────────── */

    public MqttBridgeManager(Plugin plugin) {
        this.plugin = plugin;
        load_rules();
    }

    /* ── Rule Management ─────────────────────────────────────────── */

    public void add_rule(BridgeRule rule) {
        rules.add(rule);
        save_rules();
    }

    public bool remove_rule_by_index(int index) {
        if (index < 1 || index > rules.size) return false;
        rules.remove_at(index - 1);
        save_rules();
        return true;
    }

    /**
     * Remove a bridge rule by its UUID.
     */
    public bool remove_rule(string id) {
        BridgeRule? target = null;
        foreach (var rule in rules) {
            if (rule.id == id) {
                target = rule;
                break;
            }
        }
        if (target != null) {
            rules.remove(target);
            save_rules();
            return true;
        }
        return false;
    }

    public ArrayList<BridgeRule> get_rules() {
        return rules;
    }

    /**
     * Get bridge rules filtered by client label.
     * Returns only rules belonging to the specified MQTT client.
     */
    public ArrayList<BridgeRule> get_rules_for_client(string client_label) {
        var filtered = new ArrayList<BridgeRule>();
        foreach (var rule in rules) {
            if (rule.client_label == client_label) {
                filtered.add(rule);
            }
        }
        return filtered;
    }

    /**
     * Update an existing bridge rule by its UUID.
     * Returns true if the rule was found and updated.
     */
    public bool update_rule(string id, string topic, string target_jid,
                             string? format, string? alias, string? send_account) {
        foreach (var rule in rules) {
            if (rule.id == id) {
                rule.topic = topic;
                rule.target_jid = target_jid;
                rule.format = format ?? "full";
                rule.alias = alias;
                rule.send_account = send_account;
                /* client_label is NOT changed on edit — the rule stays
                 * bound to the same MQTT client it was created for. */
                save_rules();
                return true;
            }
        }
        return false;
    }

    /**
     * Get a bridge rule by its UUID.
     */
    public BridgeRule? get_rule(string id) {
        foreach (var rule in rules) {
            if (rule.id == id) return rule;
        }
        return null;
    }

    /* ── Message Forwarding ──────────────────────────────────────── */

    /**
     * Check an incoming MQTT message against all bridge rules.
     * If a match is found, send it as an XMPP message to the target JID.
     *
     * @param source  The MQTT connection label (account JID or "standalone")
     * @param topic   The MQTT topic
     * @param payload The MQTT payload (UTF-8)
     */
    /**
     * Evaluate bridge rules for an incoming MQTT message.
     * @return true if at least one rule matched and forwarded the message.
     */
    public bool evaluate(string source, string topic, string payload) {
        bool forwarded = false;
        debug("MQTT Bridge: evaluate() called — source='%s', topic='%s', rules=%d",
              source, topic, rules.size);
        foreach (var rule in rules) {
            if (!rule.enabled) {
                debug("MQTT Bridge:   rule '%s' skipped (disabled)", rule.topic);
                continue;
            }
            /* Only evaluate rules belonging to the MQTT client that
             * received this message — prevents cross-broker duplicates. */
            if (rule.client_label != source) {
                debug("MQTT Bridge:   rule '%s' skipped (client_label='%s' != source='%s')",
                      rule.topic, rule.client_label, source);
                continue;
            }
            if (!rule.matches_topic(topic)) {
                debug("MQTT Bridge:   rule '%s' skipped (topic mismatch: rule='%s' vs incoming='%s')",
                      rule.topic, rule.topic, topic);
                continue;
            }

            /* Skip rules without a configured send account */
            if (rule.send_account == null || rule.send_account.strip() == "") {
                warning("MQTT Bridge: Rule '%s' has no send_account, skipping", rule.topic);
                continue;
            }

            /* Rate limiting (millisecond granularity) */
            int64 now_ms = GLib.get_real_time() / 1000; /* microseconds → milliseconds */
            if (last_send_times.has_key(rule.id)) {
                if (now_ms - last_send_times[rule.id] < MIN_SEND_INTERVAL_MS) {
                    debug("MQTT Bridge:   rule '%s' skipped (rate limited)", rule.topic);
                    continue;
                }
            }
            last_send_times[rule.id] = now_ms;

            /* Format and send */
            string body = rule.format_message(topic, payload);
            debug("MQTT Bridge:   rule '%s' MATCHED — sending to JID='%s' via account='%s'",
                  rule.topic, rule.target_jid, rule.send_account);
            send_xmpp_message(rule.send_account, rule.target_jid, body);
            forwarded = true;
        }
        return forwarded;
    }

    /**
     * Send a chat message to an XMPP contact.
     * If no XMPP account is connected, queues the message for later delivery.
     */
    private void send_xmpp_message(string source, string target_jid_str,
                                    string body) {
        try {
            Jid target_jid = new Jid(target_jid_str);

            /* Find the right account to send from */
            Account? account = find_account(source);
            if (account == null) {
                /* Queue for later delivery instead of silently dropping */
                if (pending_messages.size < MAX_PENDING) {
                    PendingMsg pm = PendingMsg();
                    pm.source = source;
                    pm.target_jid = target_jid_str;
                    pm.body = body;
                    pending_messages.add(pm);
                    debug("MQTT Bridge: Queued message for %s (no XMPP account connected, %d pending)",
                            target_jid_str, pending_messages.size);
                } else {
                    warning("MQTT Bridge: Pending queue full (%d), dropping message for %s",
                            MAX_PENDING, target_jid_str);
                }
                return;
            }

            deliver_message(account, target_jid, body, source);

        } catch (InvalidJidError e) {
            warning("MQTT Bridge: Invalid JID '%s': %s",
                    target_jid_str, e.message);
        }
    }

    /**
     * Actually deliver a bridge message via XMPP.
     */
    private void deliver_message(Account account, Jid target_jid,
                                  string body, string source) {
        /* Determine conversation type: MUC (groupchat) or regular chat.
         * If the target JID is a known MUC, send as GROUPCHAT so the
         * message goes to the room.  Otherwise send as a 1:1 CHAT. */
        var muc_manager = plugin.app.stream_interactor.get_module<MucManager>(
            MucManager.IDENTITY);
        Conversation.Type conv_type = Conversation.Type.CHAT;
        if (muc_manager != null && muc_manager.is_groupchat(target_jid, account)) {
            conv_type = Conversation.Type.GROUPCHAT;
        }

        /* Get the conversation (or create one).
         * Respect existing encryption: if the conversation already uses
         * OMEMO, keep it — bridge messages should honour the user's
         * per-conversation encryption choice.  Only force NONE when
         * there is no prior conversation (fresh create). */
        var cm = plugin.app.stream_interactor.get_module<ConversationManager>(
            ConversationManager.IDENTITY);
        Conversation conv = cm.create_conversation(
            target_jid, account, conv_type);

        debug("MQTT Bridge: deliver_message — conv encryption=%d for %s (type=%d)",
              conv.encryption, target_jid.to_string(), conv_type);

        /* Send via MessageProcessor — create + send on main loop */
        var mp = plugin.app.stream_interactor.get_module<MessageProcessor>(
            MessageProcessor.IDENTITY);
        var cis = plugin.app.stream_interactor.get_module<ContentItemStore>(
            ContentItemStore.IDENTITY);

        string body_copy = body;
        Conversation conv_ref = conv;
        Idle.add(() => {
            Message out_msg = mp.create_out_message(body_copy, conv_ref);
            cis.insert_message(out_msg, conv_ref);
            mp.send_xmpp_message(out_msg, conv_ref);
            mp.message_sent(out_msg, conv_ref);
            return false;
        });

        debug("MQTT Bridge: Forwarded [%s] → %s (%d chars)",
                source, target_jid.to_string(), body.length);
    }

    /**
     * Flush pending bridge messages.
     * Called when an XMPP account connects (from Plugin connection_state_changed).
     */
    public void flush_pending() {
        if (pending_messages.size == 0) return;

        int delivered = 0;
        var still_pending = new ArrayList<PendingMsg?>();

        foreach (var pm in pending_messages) {
            try {
                Account? acct = find_account(pm.source);
                if (acct != null) {
                    Jid jid = new Jid(pm.target_jid);
                    deliver_message(acct, jid, pm.body, pm.source);
                    delivered++;
                } else {
                    still_pending.add(pm);
                }
            } catch (InvalidJidError e) {
                warning("MQTT Bridge: flush_pending: Invalid JID '%s': %s",
                        pm.target_jid, e.message);
            }
        }

        pending_messages.clear();
        pending_messages.add_all(still_pending);

        if (delivered > 0) {
            debug("MQTT Bridge: Flushed %d pending messages (%d still pending)",
                    delivered, still_pending.size);
        }
    }

    /**
     * Find the Account for a given bare JID.
     */
    private Account? find_account(string bare_jid) {
        var accounts = plugin.app.stream_interactor.get_accounts();

        foreach (var acct in accounts) {
            if (acct.bare_jid.to_string() == bare_jid) {
                var state = plugin.app.stream_interactor.connection_manager
                    .get_state(acct);
                if (state == ConnectionManager.ConnectionState.CONNECTED) {
                    return acct;
                }
                /* Account exists but not connected */
                return null;
            }
        }

        return null;
    }

    /* ── Persistence ─────────────────────────────────────────────── */

    private void load_rules() {
        /* Phase 1c: Try loading from mqtt.db first */
        if (plugin.mqtt_db != null) {
            var iter = plugin.mqtt_db.bridge_rules.select()
                .order_by(plugin.mqtt_db.bridge_rules.created_at, "ASC")
                .iterator();
            while (iter.next()) {
                var row = iter.get();
                var rule = new BridgeRule();
                rule.id = plugin.mqtt_db.bridge_rules.id[row];
                rule.topic = plugin.mqtt_db.bridge_rules.topic[row];
                rule.target_jid = plugin.mqtt_db.bridge_rules.target_jid[row];
                rule.format = plugin.mqtt_db.bridge_rules.format[row];
                rule.enabled = plugin.mqtt_db.bridge_rules.enabled[row];
                rule.alias = plugin.mqtt_db.bridge_rules.alias[row];
                rule.client_label = plugin.mqtt_db.bridge_rules.client_label[row];
                rule.send_account = plugin.mqtt_db.bridge_rules.send_account[row];
                rules.add(rule);
            }

            if (rules.size > 0) {
                /* Auto-fill send_account for legacy rules that still
                 * have it unset after the DB migration (e.g. standalone
                 * rules where client_label == "standalone"). */
                bool needs_save = false;
                string? first_acct = null;
                var accounts = plugin.app.stream_interactor.get_accounts();
                foreach (var acct in accounts) {
                    var st = plugin.app.stream_interactor.connection_manager
                        .get_state(acct);
                    if (st == ConnectionManager.ConnectionState.CONNECTED) {
                        first_acct = acct.bare_jid.to_string();
                        break;
                    }
                }
                /* Fallback: first account even if not connected */
                if (first_acct == null && accounts.size > 0) {
                    first_acct = accounts.first().bare_jid.to_string();
                }

                foreach (var r in rules) {
                    if (r.send_account == null || r.send_account.strip() == "") {
                        if (r.client_label != "standalone") {
                            r.send_account = r.client_label;
                            needs_save = true;
                        } else if (first_acct != null) {
                            r.send_account = first_acct;
                            needs_save = true;
                        }
                    }
                }
                if (needs_save) {
                    debug("MQTT BridgeManager: Auto-filled send_account for legacy rules");
                    save_rules();
                }

                debug("MQTT BridgeManager: Loaded %d bridge rules from mqtt.db", rules.size);
                return;
            }
        }

        /* Fallback: load from JSON in settings (legacy) */
        string? json_str = get_db_setting(KEY_BRIDGES);
        if (json_str == null || json_str.strip() == "") return;

        try {
            var parser = new Json.Parser();
            parser.load_from_data(json_str, -1);
            var root = parser.get_root();
            if (root == null || root.get_node_type() != Json.NodeType.ARRAY)
                return;

            var array = root.get_array();
            for (uint i = 0; i < array.get_length(); i++) {
                var node = array.get_element(i);
                if (node.get_node_type() != Json.NodeType.OBJECT) continue;
                BridgeRule? rule = BridgeRule.from_json(node.get_object());
                if (rule != null) {
                    rules.add(rule);
                }
            }

            debug("MQTT BridgeManager: Loaded %d bridge rules from JSON (legacy)", rules.size);

            /* One-time migration: write rules to mqtt.db */
            if (rules.size > 0 && plugin.mqtt_db != null) {
                save_rules();
                debug("MQTT BridgeManager: Migrated %d rules from JSON → mqtt.db", rules.size);
            }
        } catch (GLib.Error e) {
            warning("MQTT BridgeManager: Failed to load rules: %s", e.message);
        }
    }

    public void save_rules() {
        /* Phase 1c: Save to mqtt.db */
        if (plugin.mqtt_db != null) {
            /* Wrap DELETE ALL + INSERT ALL in a transaction for atomicity.
             * On any error, ROLLBACK to preserve existing data (BUG-2 fix). */
            try {
                plugin.mqtt_db.exec("BEGIN TRANSACTION");

                /* Delete all existing rules and re-insert */
                plugin.mqtt_db.bridge_rules.delete().perform();

                long now = (long) MqttUtils.now_unix();
                foreach (var rule in rules) {
                    plugin.mqtt_db.bridge_rules.insert()
                        .value(plugin.mqtt_db.bridge_rules.id, rule.id)
                        .value(plugin.mqtt_db.bridge_rules.topic, rule.topic)
                        .value(plugin.mqtt_db.bridge_rules.target_jid, rule.target_jid)
                        .value(plugin.mqtt_db.bridge_rules.format, rule.format ?? "full")
                        .value(plugin.mqtt_db.bridge_rules.enabled, rule.enabled)
                        .value(plugin.mqtt_db.bridge_rules.alias, rule.alias)
                        .value(plugin.mqtt_db.bridge_rules.client_label, rule.client_label)
                        .value(plugin.mqtt_db.bridge_rules.send_account, rule.send_account)
                        .value(plugin.mqtt_db.bridge_rules.created_at, now)
                        .perform();
                }

                plugin.mqtt_db.exec("COMMIT");
            } catch (Error e) {
                warning("MQTT BridgeManager: save_rules failed, rolling back: %s", e.message);
                try { plugin.mqtt_db.exec("ROLLBACK"); } catch (Error e2) {
                    warning("MQTT BridgeManager: ROLLBACK also failed: %s", e2.message);
                }
            }
            return;
        }

        /* Fallback: save as JSON in settings (legacy) */
        var array = new Json.Array();
        foreach (var rule in rules) {
            var node = new Json.Node(Json.NodeType.OBJECT);
            node.set_object(rule.to_json());
            array.add_element(node);
        }

        var root = new Json.Node(Json.NodeType.ARRAY);
        root.set_array(array);

        var gen = new Json.Generator();
        gen.set_root(root);
        string json_str = gen.to_data(null);

        set_db_setting(KEY_BRIDGES, json_str);
    }

    /* ── DB helpers (delegated to Plugin) ─────────────────────────── */

    private string? get_db_setting(string key) {
        return plugin.get_app_db_setting(key);
    }

    private void set_db_setting(string key, string val) {
        plugin.set_app_db_setting(key, val);
    }
}

}
