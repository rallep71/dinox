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
    public string topic;       /* MQTT topic pattern (exact or wildcard) */
    public string target_jid;  /* Bare JID of the XMPP recipient */
    public bool enabled;
    public string? format;     /* Optional format: "full" (default), "payload", "short" */

    public BridgeRule() {
        id = Xmpp.random_uuid();
        enabled = true;
        format = "full";
    }

    /**
     * Check if this rule matches an MQTT topic.
     */
    public bool matches_topic(string incoming_topic) {
        return MqttUtils.topic_matches(topic, incoming_topic);
    }

    /**
     * Format the bridged message body.
     */
    public string format_message(string topic_name, string payload) {
        return MqttUtils.format_bridge_message(format ?? "full", topic_name, payload);
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

    /* Rate limiting: track last send time per rule to avoid flooding */
    private HashMap<string, int64?> last_send_times =
        new HashMap<string, int64?>();
    private const int64 MIN_SEND_INTERVAL_SECS = 2;

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

    /* ── Message Forwarding ──────────────────────────────────────── */

    /**
     * Check an incoming MQTT message against all bridge rules.
     * If a match is found, send it as an XMPP message to the target JID.
     *
     * @param source  The MQTT connection label (account JID or "standalone")
     * @param topic   The MQTT topic
     * @param payload The MQTT payload (UTF-8)
     */
    public void evaluate(string source, string topic, string payload) {
        foreach (var rule in rules) {
            if (!rule.enabled) continue;
            if (!rule.matches_topic(topic)) continue;

            /* Rate limiting */
            int64 now = new DateTime.now_utc().to_unix();
            if (last_send_times.has_key(rule.id)) {
                if (now - last_send_times[rule.id] < MIN_SEND_INTERVAL_SECS) {
                    continue;
                }
            }
            last_send_times[rule.id] = now;

            /* Format and send */
            string body = rule.format_message(topic, payload);
            send_xmpp_message(source, rule.target_jid, body);
        }
    }

    /**
     * Send a chat message to an XMPP contact.
     */
    private void send_xmpp_message(string source, string target_jid_str,
                                    string body) {
        try {
            Jid target_jid = new Jid(target_jid_str);

            /* Find the right account to send from */
            Account? account = find_account(source);
            if (account == null) {
                warning("MQTT Bridge: No account to send from (%s)", source);
                return;
            }

            /* Get the conversation (or create one) */
            var cm = plugin.app.stream_interactor.get_module<ConversationManager>(
                ConversationManager.IDENTITY);
            Conversation conv = cm.create_conversation(
                target_jid, account, Conversation.Type.CHAT);
            conv.encryption = Encryption.NONE;

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

            message("MQTT Bridge: Forwarded [%s] → %s (%d chars)",
                    source, target_jid_str, body.length);

        } catch (InvalidJidError e) {
            warning("MQTT Bridge: Invalid JID '%s': %s",
                    target_jid_str, e.message);
        }
    }

    /**
     * Find the Account for a given source label.
     */
    private Account? find_account(string source) {
        var accounts = plugin.app.stream_interactor.get_accounts();

        if (source == "standalone") {
            /* Use first connected account */
            foreach (var acct in accounts) {
                var state = plugin.app.stream_interactor.connection_manager
                    .get_state(acct);
                if (state == ConnectionManager.ConnectionState.CONNECTED) {
                    return acct;
                }
            }
            return accounts.size > 0 ? accounts.first() : null;
        }

        /* Per-account: source is the bare JID */
        foreach (var acct in accounts) {
            if (acct.bare_jid.to_string() == source) {
                return acct;
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
                rules.add(rule);
            }

            if (rules.size > 0) {
                message("MQTT BridgeManager: Loaded %d bridge rules from mqtt.db", rules.size);
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

            message("MQTT BridgeManager: Loaded %d bridge rules from JSON (legacy)", rules.size);

            /* One-time migration: write rules to mqtt.db */
            if (rules.size > 0 && plugin.mqtt_db != null) {
                save_rules();
                message("MQTT BridgeManager: Migrated %d rules from JSON → mqtt.db", rules.size);
            }
        } catch (GLib.Error e) {
            warning("MQTT BridgeManager: Failed to load rules: %s", e.message);
        }
    }

    private void save_rules() {
        /* Phase 1c: Save to mqtt.db */
        if (plugin.mqtt_db != null) {
            /* Wrap DELETE ALL + INSERT ALL in a transaction for atomicity */
            try { plugin.mqtt_db.exec("BEGIN TRANSACTION"); } catch (Error e) {
                warning("MQTT BridgeManager: BEGIN TRANSACTION failed: %s", e.message);
            }

            /* Delete all existing rules and re-insert */
            plugin.mqtt_db.bridge_rules.delete().perform();

            long now = (long) new DateTime.now_utc().to_unix();
            foreach (var rule in rules) {
                plugin.mqtt_db.bridge_rules.insert()
                    .value(plugin.mqtt_db.bridge_rules.id, rule.id)
                    .value(plugin.mqtt_db.bridge_rules.topic, rule.topic)
                    .value(plugin.mqtt_db.bridge_rules.target_jid, rule.target_jid)
                    .value(plugin.mqtt_db.bridge_rules.format, rule.format ?? "full")
                    .value(plugin.mqtt_db.bridge_rules.enabled, rule.enabled)
                    .value(plugin.mqtt_db.bridge_rules.created_at, now)
                    .perform();
            }

            try { plugin.mqtt_db.exec("COMMIT"); } catch (Error e) {
                warning("MQTT BridgeManager: COMMIT failed: %s", e.message);
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

    /* ── DB helpers ──────────────────────────────────────────────── */

    private string? get_db_setting(string key) {
        var row_opt = plugin.app.db.settings.select(
                {plugin.app.db.settings.value})
            .with(plugin.app.db.settings.key, "=", key)
            .single()
            .row();
        if (row_opt.is_present())
            return row_opt[plugin.app.db.settings.value];
        return null;
    }

    private void set_db_setting(string key, string val) {
        plugin.app.db.settings.upsert()
            .value(plugin.app.db.settings.key, key, true)
            .value(plugin.app.db.settings.value, val)
            .perform();
    }
}

}
