/*
 * MqttAlertManager — Threshold alerts, topic history, and notification
 *                     priority for MQTT messages.
 *
 * Alert rules are stored as JSON in the DinoX settings DB.
 * Topic history is kept in memory (last N values per topic).
 *
 * Priority levels:
 *   SILENT   — no badge, no notification (auto-mark-read)
 *   NORMAL   — standard badge + notification (default)
 *   ALERT    — badge + notification + [⚠] prefix
 *   CRITICAL — badge + notification + sound + [🔴] prefix
 *
 * Copyright (C) 2026 Ralf Peter <dinox@handwerker.jetzt>
 */

using Gee;
using Dino.Entities;

namespace Dino.Plugins.Mqtt {

/**
 * Notification priority for a topic or alert.
 */
public enum MqttPriority {
    SILENT,
    NORMAL,
    ALERT,
    CRITICAL;

    public string to_string_key() {
        switch (this) {
            case SILENT:   return "silent";
            case NORMAL:   return "normal";
            case ALERT:    return "alert";
            case CRITICAL: return "critical";
            default:       return "normal";
        }
    }

    public string to_label() {
        switch (this) {
            case SILENT:   return "Silent (no notification)";
            case NORMAL:   return "Normal (badge)";
            case ALERT:    return "Alert (badge + notification)";
            case CRITICAL: return "Critical (badge + notification + sound)";
            default:       return "Normal";
        }
    }

    public string to_icon() {
        switch (this) {
            case ALERT:    return "⚠";
            case CRITICAL: return "🔴";
            default:       return "";
        }
    }

    public static MqttPriority from_string(string s) {
        switch (s.down()) {
            case "silent":   return SILENT;
            case "alert":    return ALERT;
            case "critical": return CRITICAL;
            default:         return NORMAL;
        }
    }
}

/**
 * Comparison operator for threshold alerts.
 */
public enum AlertOperator {
    GT,    /* >  */
    LT,    /* <  */
    GTE,   /* >= */
    LTE,   /* <= */
    EQ,    /* == */
    NEQ,   /* != */
    CONTAINS;

    public string to_symbol() {
        switch (this) {
            case GT:       return ">";
            case LT:       return "<";
            case GTE:      return ">=";
            case LTE:      return "<=";
            case EQ:       return "==";
            case NEQ:      return "!=";
            case CONTAINS: return "contains";
            default:       return "?";
        }
    }

    public static AlertOperator? from_string(string s) {
        switch (s) {
            case ">":        return GT;
            case "<":        return LT;
            case ">=":       return GTE;
            case "<=":       return LTE;
            case "==":       return EQ;
            case "=":        return EQ;
            case "!=":       return NEQ;
            case "contains": return CONTAINS;
            default:         return null;
        }
    }
}

/**
 * A single alert rule.
 */
public class AlertRule : Object {
    public string id;            /* UUID */
    public string topic;         /* MQTT topic pattern (exact or wildcard) */
    public string? field;        /* JSON field name (null = whole payload) */
    public AlertOperator op;     /* Comparison operator */
    public string threshold;     /* Threshold value (numeric or string) */
    public MqttPriority priority; /* Priority when triggered */
    public bool enabled;
    public int64 last_triggered; /* Unix timestamp, 0 = never */
    public int64 cooldown_secs;  /* Min seconds between triggers (default 60) */

    public AlertRule() {
        id = Xmpp.random_uuid();
        enabled = true;
        priority = MqttPriority.ALERT;
        last_triggered = 0;
        cooldown_secs = 60;
    }

    /**
     * Check if the rule matches a topic.
     * Supports exact match and simple MQTT wildcard patterns.
     */
    public bool matches_topic(string incoming_topic) {
        if (topic == incoming_topic) return true;
        if (topic == "#") return true;

        /* Simple wildcard matching */
        string[] rule_parts = topic.split("/");
        string[] topic_parts = incoming_topic.split("/");

        int ri = 0;
        int ti = 0;
        while (ri < rule_parts.length && ti < topic_parts.length) {
            if (rule_parts[ri] == "#") return true; /* # matches rest */
            if (rule_parts[ri] == "+") {
                /* + matches single level */
                ri++;
                ti++;
                continue;
            }
            if (rule_parts[ri] != topic_parts[ti]) return false;
            ri++;
            ti++;
        }

        return ri == rule_parts.length && ti == topic_parts.length;
    }

    /**
     * Evaluate the rule against a payload value.
     * Returns true if the alert condition is met.
     */
    public bool evaluate(string value) {
        /* Check cooldown */
        if (last_triggered > 0 && cooldown_secs > 0) {
            int64 now = new DateTime.now_utc().to_unix();
            if (now - last_triggered < cooldown_secs) {
                return false;
            }
        }

        switch (op) {
            case AlertOperator.CONTAINS:
                return value.down().contains(threshold.down());

            case AlertOperator.EQ:
                /* Try numeric first, then string */
                double? val_num = try_parse_double(value);
                double? thr_num = try_parse_double(threshold);
                if (val_num != null && thr_num != null) {
                    return Math.fabs(val_num - thr_num) < 0.001;
                }
                return value.strip() == threshold.strip();

            case AlertOperator.NEQ:
                double? val_n = try_parse_double(value);
                double? thr_n = try_parse_double(threshold);
                if (val_n != null && thr_n != null) {
                    return Math.fabs(val_n - thr_n) >= 0.001;
                }
                return value.strip() != threshold.strip();

            default:
                /* Numeric comparisons */
                double? val_d = try_parse_double(value);
                double? thr_d = try_parse_double(threshold);
                if (val_d == null || thr_d == null) return false;

                switch (op) {
                    case AlertOperator.GT:  return val_d > thr_d;
                    case AlertOperator.LT:  return val_d < thr_d;
                    case AlertOperator.GTE: return val_d >= thr_d;
                    case AlertOperator.LTE: return val_d <= thr_d;
                    default: return false;
                }
        }
    }

    /**
     * Serialize to JSON object.
     */
    public Json.Object to_json() {
        var obj = new Json.Object();
        obj.set_string_member("id", id);
        obj.set_string_member("topic", topic);
        if (field != null) obj.set_string_member("field", field);
        obj.set_string_member("op", op.to_symbol());
        obj.set_string_member("threshold", threshold);
        obj.set_string_member("priority", priority.to_string_key());
        obj.set_boolean_member("enabled", enabled);
        obj.set_int_member("cooldown", cooldown_secs);
        return obj;
    }

    /**
     * Deserialize from JSON object.
     */
    public static AlertRule? from_json(Json.Object obj) {
        var rule = new AlertRule();

        if (!obj.has_member("topic") || !obj.has_member("op") ||
            !obj.has_member("threshold")) return null;

        if (obj.has_member("id"))
            rule.id = obj.get_string_member("id");
        rule.topic = obj.get_string_member("topic");
        if (obj.has_member("field"))
            rule.field = obj.get_string_member("field");

        AlertOperator? parsed_op = AlertOperator.from_string(
            obj.get_string_member("op"));
        if (parsed_op == null) return null;
        rule.op = parsed_op;

        rule.threshold = obj.get_string_member("threshold");

        if (obj.has_member("priority"))
            rule.priority = MqttPriority.from_string(
                obj.get_string_member("priority"));
        if (obj.has_member("enabled"))
            rule.enabled = obj.get_boolean_member("enabled");
        if (obj.has_member("cooldown"))
            rule.cooldown_secs = obj.get_int_member("cooldown");

        return rule;
    }

    private static double? try_parse_double(string s) {
        string trimmed = s.strip();
        if (trimmed == "") return null;
        double val;
        if (double.try_parse(trimmed, out val)) {
            return val;
        }
        return null;
    }
}

/**
 * A single history entry for a topic.
 */
public class TopicHistoryEntry {
    public string topic;
    public string payload;
    public DateTime timestamp;
    public MqttPriority triggered_priority;

    public TopicHistoryEntry(string topic, string payload) {
        this.topic = topic;
        this.payload = payload;
        this.timestamp = new DateTime.now_utc();
        this.triggered_priority = MqttPriority.NORMAL;
    }
}

/**
 * Result of evaluating alert rules against an incoming message.
 */
public class AlertEvalResult {
    public MqttPriority priority;
    public ArrayList<AlertRule> triggered_rules;
    public string? topic_priority;  /* per-topic fixed priority */

    public AlertEvalResult() {
        priority = MqttPriority.NORMAL;
        triggered_rules = new ArrayList<AlertRule>();
        topic_priority = null;
    }
}


/**
 * Manages alert rules, topic history, and per-topic priority settings.
 */
public class MqttAlertManager : Object {

    /* DB key for alert rules JSON */
    internal const string KEY_ALERTS = "mqtt_alerts";

    /* DB key for per-topic priority JSON */
    internal const string KEY_TOPIC_PRIORITIES = "mqtt_topic_priorities";

    /* Max history entries per topic */
    private const int MAX_HISTORY_PER_TOPIC = 50;

    /* Back-references */
    private Plugin plugin;

    /* Alert rules (loaded from DB) */
    private ArrayList<AlertRule> rules = new ArrayList<AlertRule>();

    /* Per-topic priority settings (topic → priority) */
    private HashMap<string, MqttPriority> topic_priorities =
        new HashMap<string, MqttPriority>();

    /* Topic history (topic → list of entries, most recent last) */
    private HashMap<string, ArrayList<TopicHistoryEntry>> history =
        new HashMap<string, ArrayList<TopicHistoryEntry>>();

    /* Pause state: when true, messages are still recorded in history
     * but not displayed as chat bubbles */
    private bool _paused = false;
    public bool paused {
        get { return _paused; }
        set { _paused = value; }
    }

    /* ── Construction ────────────────────────────────────────────── */

    public MqttAlertManager(Plugin plugin) {
        this.plugin = plugin;
        load_rules();
        load_topic_priorities();
    }

    /* ── Alert Rule Management ───────────────────────────────────── */

    /**
     * Add a new alert rule.
     */
    public void add_rule(AlertRule rule) {
        rules.add(rule);
        save_rules();
    }

    /**
     * Remove an alert rule by ID.
     */
    public bool remove_rule(string id) {
        AlertRule? target = null;
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

    /**
     * Remove an alert rule by index (1-based).
     */
    public bool remove_rule_by_index(int index) {
        if (index < 1 || index > rules.size) return false;
        rules.remove_at(index - 1);
        save_rules();
        return true;
    }

    /**
     * Get all alert rules.
     */
    public ArrayList<AlertRule> get_rules() {
        return rules;
    }

    /**
     * Toggle an alert rule's enabled state by index (1-based).
     */
    public bool toggle_rule(int index) {
        if (index < 1 || index > rules.size) return false;
        rules[index - 1].enabled = !rules[index - 1].enabled;
        save_rules();
        return true;
    }

    /* ── Per-Topic Priority ──────────────────────────────────────── */

    /**
     * Set the notification priority for a specific topic.
     */
    public void set_topic_priority(string topic, MqttPriority priority) {
        if (priority == MqttPriority.NORMAL) {
            /* NORMAL is default — remove the override */
            topic_priorities.unset(topic);
        } else {
            topic_priorities[topic] = priority;
        }
        save_topic_priorities();
    }

    /**
     * Get the notification priority for a topic (default: NORMAL).
     */
    public MqttPriority get_topic_priority(string topic) {
        if (topic_priorities.has_key(topic)) {
            return topic_priorities[topic];
        }

        /* Check wildcard patterns in topic_priorities */
        foreach (var entry in topic_priorities.entries) {
            if (topic_matches_pattern(topic, entry.key)) {
                return entry.value;
            }
        }

        return MqttPriority.NORMAL;
    }

    /**
     * Get all per-topic priority overrides.
     */
    public HashMap<string, MqttPriority> get_all_topic_priorities() {
        return topic_priorities;
    }

    /* ── Topic History ───────────────────────────────────────────── */

    /**
     * Record a value in the topic history.
     */
    public void record_history(string topic, string payload,
                                MqttPriority priority) {
        if (!history.has_key(topic)) {
            history[topic] = new ArrayList<TopicHistoryEntry>();
        }

        var entry = new TopicHistoryEntry(topic, payload);
        entry.triggered_priority = priority;
        history[topic].add(entry);

        /* Trim to max size */
        while (history[topic].size > MAX_HISTORY_PER_TOPIC) {
            history[topic].remove_at(0);
        }
    }

    /**
     * Get history for a topic (most recent last).
     */
    public ArrayList<TopicHistoryEntry>? get_history(string topic) {
        if (history.has_key(topic)) {
            return history[topic];
        }

        /* Try wildcard match */
        var result = new ArrayList<TopicHistoryEntry>();
        foreach (var entry in history.entries) {
            if (topic_matches_pattern(entry.key, topic)) {
                result.add_all(entry.value);
            }
        }

        if (result.size > 0) {
            /* Sort by timestamp */
            result.sort((a, b) => {
                return a.timestamp.compare(b.timestamp);
            });
            return result;
        }

        return null;
    }

    /**
     * Get a list of all topics that have history entries.
     */
    public ArrayList<string> get_history_topics() {
        var topics = new ArrayList<string>();
        topics.add_all(history.keys);
        topics.sort();
        return topics;
    }

    /* ── Alert Evaluation ────────────────────────────────────────── */

    /**
     * Evaluate an incoming MQTT message against all alert rules
     * and per-topic priority settings.
     *
     * Returns the effective priority and list of triggered rules.
     */
    public AlertEvalResult evaluate(string topic, string payload) {
        var result = new AlertEvalResult();

        /* 1. Check per-topic priority */
        MqttPriority topic_prio = get_topic_priority(topic);
        result.priority = topic_prio;

        /* 2. Evaluate alert rules (can escalate priority) */
        foreach (var rule in rules) {
            if (!rule.enabled) continue;
            if (!rule.matches_topic(topic)) continue;

            /* Extract value to test */
            string test_value;
            if (rule.field != null && rule.field != "") {
                test_value = extract_json_field(payload, rule.field);
            } else {
                test_value = payload.strip();
            }

            if (rule.evaluate(test_value)) {
                result.triggered_rules.add(rule);

                /* Alert rule priority can escalate but not de-escalate */
                if (rule.priority > result.priority) {
                    result.priority = rule.priority;
                }

                /* Update trigger timestamp */
                rule.last_triggered = new DateTime.now_utc().to_unix();
            }
        }

        /* Save rules if any were triggered (to persist last_triggered) */
        if (result.triggered_rules.size > 0) {
            save_rules();
        }

        /* Record in history */
        record_history(topic, payload, result.priority);

        return result;
    }

    /* ── JSON Field Extraction ───────────────────────────────────── */

    /**
     * Extract a field value from a JSON payload.
     * Returns the string representation of the value.
     */
    private string extract_json_field(string payload, string field) {
        try {
            var parser = new Json.Parser();
            parser.load_from_data(payload, -1);
            var root = parser.get_root();
            if (root == null || root.get_node_type() != Json.NodeType.OBJECT) {
                return payload.strip();
            }

            var obj = root.get_object();
            if (!obj.has_member(field)) return "";

            var node = obj.get_member(field);
            if (node.get_node_type() == Json.NodeType.VALUE) {
                var val_type = node.get_value_type();
                if (val_type == typeof(string)) {
                    return node.get_string();
                } else if (val_type == typeof(int64)) {
                    return node.get_int().to_string();
                } else if (val_type == typeof(double)) {
                    return "%.6f".printf(node.get_double());
                } else if (val_type == typeof(bool)) {
                    return node.get_boolean() ? "true" : "false";
                }
            }

            /* Nested: return raw JSON */
            var gen = new Json.Generator();
            gen.set_root(node);
            return gen.to_data(null);
        } catch (GLib.Error e) {
            return payload.strip();
        }
    }

    /* ── MQTT Wildcard Matching ──────────────────────────────────── */

    private bool topic_matches_pattern(string topic, string pattern) {
        if (pattern == topic) return true;
        if (pattern == "#") return true;

        string[] pat_parts = pattern.split("/");
        string[] top_parts = topic.split("/");

        int pi = 0;
        int ti = 0;
        while (pi < pat_parts.length && ti < top_parts.length) {
            if (pat_parts[pi] == "#") return true;
            if (pat_parts[pi] == "+") {
                pi++;
                ti++;
                continue;
            }
            if (pat_parts[pi] != top_parts[ti]) return false;
            pi++;
            ti++;
        }

        return pi == pat_parts.length && ti == top_parts.length;
    }

    /* ── Persistence ─────────────────────────────────────────────── */

    private void load_rules() {
        string? json_str = get_db_setting(KEY_ALERTS);
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
                AlertRule? rule = AlertRule.from_json(node.get_object());
                if (rule != null) {
                    rules.add(rule);
                }
            }

            message("MQTT AlertManager: Loaded %d alert rules", rules.size);
        } catch (GLib.Error e) {
            warning("MQTT AlertManager: Failed to load rules: %s", e.message);
        }
    }

    private void save_rules() {
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

        set_db_setting(KEY_ALERTS, json_str);
    }

    private void load_topic_priorities() {
        string? json_str = get_db_setting(KEY_TOPIC_PRIORITIES);
        if (json_str == null || json_str.strip() == "") return;

        try {
            var parser = new Json.Parser();
            parser.load_from_data(json_str, -1);
            var root = parser.get_root();
            if (root == null || root.get_node_type() != Json.NodeType.OBJECT)
                return;

            var obj = root.get_object();
            foreach (string member in obj.get_members()) {
                string prio_str = obj.get_string_member(member);
                topic_priorities[member] = MqttPriority.from_string(prio_str);
            }

            message("MQTT AlertManager: Loaded %d topic priorities",
                    topic_priorities.size);
        } catch (GLib.Error e) {
            warning("MQTT AlertManager: Failed to load priorities: %s",
                    e.message);
        }
    }

    private void save_topic_priorities() {
        var obj = new Json.Object();
        foreach (var entry in topic_priorities.entries) {
            obj.set_string_member(entry.key, entry.value.to_string_key());
        }

        var root = new Json.Node(Json.NodeType.OBJECT);
        root.set_object(obj);

        var gen = new Json.Generator();
        gen.set_root(root);
        string json_str = gen.to_data(null);

        set_db_setting(KEY_TOPIC_PRIORITIES, json_str);
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
