/*
 * MqttCommandHandler — Process /mqtt chat commands in the bot conversation.
 *
 * When the user types a /mqtt command in the MQTT Bot conversation,
 * the message is intercepted before XMPP send (marked WONTSEND) and
 * processed here.  Responses are injected as incoming bot messages.
 *
 * Supported commands:
 *   /mqtt status       — Show connection & broker info
 *   /mqtt subscribe    — Subscribe to a topic
 *   /mqtt unsubscribe  — Unsubscribe from a topic
 *   /mqtt publish      — Publish a message to a topic
 *   /mqtt topics       — List active subscriptions
 *   /mqtt alert        — Set threshold alert
 *   /mqtt alerts       — List alert rules
 *   /mqtt rmalert      — Remove alert rule
 *   /mqtt priority     — Set per-topic notification priority
 *   /mqtt history      — Show topic history
 *   /mqtt pause        — Pause message display
 *   /mqtt resume       — Resume message display
 *   /mqtt help         — Show available commands
 *
 * Copyright (C) 2026 Ralf Peter <dinox@handwerker.jetzt>
 */

using Gee;
using Dino.Entities;

namespace Dino.Plugins.Mqtt {

public class MqttCommandHandler : Object {

    private Plugin plugin;
    private MqttBotConversation bot;

    public MqttCommandHandler(Plugin plugin, MqttBotConversation bot) {
        this.plugin = plugin;
        this.bot = bot;
    }

    /**
     * Process a /mqtt command string and inject the response.
     *
     * @param command_text  Full message text (starts with "/mqtt")
     * @param conversation  The bot conversation
     * @return true if the command was recognized and handled
     */
    public bool process(string command_text, Conversation conversation) {
        string trimmed = command_text.strip();

        /* Must start with /mqtt */
        if (!trimmed.has_prefix("/mqtt")) return false;

        /* Parse: /mqtt <subcommand> [args...] */
        string rest = trimmed.substring(5).strip();
        string[] parts = rest.split(" ", 4);

        string subcmd = (parts.length > 0) ? parts[0].down() : "help";
        string arg1 = (parts.length > 1) ? parts[1] : "";
        string arg2 = (parts.length > 2) ? parts[2] : "";
        string arg3 = (parts.length > 3) ? parts[3] : "";

        string response;

        switch (subcmd) {
            case "status":
                response = cmd_status();
                break;

            case "subscribe":
            case "sub":
                response = cmd_subscribe(arg1);
                break;

            case "unsubscribe":
            case "unsub":
                response = cmd_unsubscribe(arg1);
                break;

            case "publish":
            case "pub":
                response = cmd_publish(arg1, arg2);
                break;

            case "topics":
            case "list":
                response = cmd_topics();
                break;

            case "alert":
                response = cmd_alert(arg1, arg2, arg3);
                break;

            case "alerts":
                response = cmd_alerts();
                break;

            case "rmalert":
            case "delalert":
                response = cmd_rmalert(arg1);
                break;

            case "priority":
            case "prio":
                response = cmd_priority(arg1, arg2);
                break;

            case "history":
            case "hist":
                response = cmd_history(arg1, arg2);
                break;

            case "pause":
                response = cmd_pause();
                break;

            case "resume":
                response = cmd_resume();
                break;

            case "help":
            case "?":
                response = cmd_help();
                break;

            default:
                response = "Unknown command: /mqtt %s\n\nType /mqtt help for available commands.".printf(subcmd);
                break;
        }

        /* Inject response as incoming bot message */
        bot.inject_bot_message(conversation, response);
        return true;
    }

    /* ── Command Implementations ─────────────────────────────────── */

    private string cmd_status() {
        var sb = new StringBuilder();
        sb.append("MQTT Status\n");
        sb.append("───────────\n");

        /* Standalone client */
        MqttClient? standalone = plugin.get_standalone_client();
        if (standalone != null) {
            sb.append_printf("Standalone: %s\n",
                standalone.is_connected ? "Connected ✔" : "Disconnected ✘");
        }

        /* Per-account clients */
        var accounts = plugin.app.stream_interactor.get_accounts();
        foreach (var acct in accounts) {
            MqttClient? client = plugin.get_client_for_account(
                acct.bare_jid.to_string());
            if (client != null) {
                sb.append_printf("Account %s: %s\n",
                    acct.bare_jid.to_string(),
                    client.is_connected ? "Connected ✔" : "Disconnected ✘");
            }
        }

        if (standalone == null && plugin.get_standalone_client() == null) {
            sb.append("No active MQTT connections.\n");
            sb.append("Enable MQTT in Preferences > MQTT.");
        }

        return sb.str;
    }

    private string cmd_subscribe(string topic) {
        if (topic == "") {
            return "Usage: /mqtt subscribe <topic>\n\nExamples:\n  /mqtt subscribe home/sensors/#\n  /mqtt subscribe home/+/temperature";
        }

        plugin.subscribe(topic);

        /* Also persist the topic to DB */
        string? existing = get_db_setting(Plugin.KEY_TOPICS);
        string new_topics;
        if (existing != null && existing != "") {
            /* Check for duplicates */
            string[] parts = existing.split(",");
            foreach (string p in parts) {
                if (p.strip() == topic) {
                    return "Already subscribed to: %s".printf(topic);
                }
            }
            new_topics = existing + "," + topic;
        } else {
            new_topics = topic;
        }
        set_db_setting(Plugin.KEY_TOPICS, new_topics);

        return "Subscribed to: %s ✔".printf(topic);
    }

    private string cmd_unsubscribe(string topic) {
        if (topic == "") {
            return "Usage: /mqtt unsubscribe <topic>";
        }

        /* Unsubscribe on all connections */
        MqttClient? standalone = plugin.get_standalone_client();
        if (standalone != null && standalone.is_connected) {
            standalone.unsubscribe(topic);
        }
        var accounts = plugin.app.stream_interactor.get_accounts();
        foreach (var acct in accounts) {
            MqttClient? client = plugin.get_client_for_account(
                acct.bare_jid.to_string());
            if (client != null && client.is_connected) {
                client.unsubscribe(topic);
            }
        }

        /* Remove from DB */
        string? existing = get_db_setting(Plugin.KEY_TOPICS);
        if (existing != null && existing != "") {
            string[] parts = existing.split(",");
            var remaining = new ArrayList<string>();
            bool found = false;
            foreach (string p in parts) {
                if (p.strip() == topic) {
                    found = true;
                } else {
                    remaining.add(p.strip());
                }
            }
            if (found) {
                set_db_setting(Plugin.KEY_TOPICS, string.joinv(",", remaining.to_array()));
                return "Unsubscribed from: %s ✔".printf(topic);
            }
        }

        return "Topic not found in subscriptions: %s".printf(topic);
    }

    private string cmd_publish(string topic, string payload) {
        if (topic == "") {
            return "Usage: /mqtt publish <topic> <payload>\n\nExample:\n  /mqtt publish home/light/set ON";
        }
        if (payload == "") {
            return "Usage: /mqtt publish <topic> <payload>\n\nPayload cannot be empty.";
        }

        plugin.publish(topic, payload);
        return "Published to %s:\n%s".printf(topic, payload);
    }

    private string cmd_topics() {
        string? topics_str = get_db_setting(Plugin.KEY_TOPICS);
        if (topics_str == null || topics_str.strip() == "") {
            return "No topic subscriptions configured.\n\nUse /mqtt subscribe <topic> to add one.";
        }

        string[] topics = topics_str.split(",");
        var sb = new StringBuilder();
        sb.append("Active Topic Subscriptions\n");
        sb.append("─────────────────────────\n");

        int i = 1;
        foreach (string t in topics) {
            string trimmed = t.strip();
            if (trimmed != "") {
                sb.append_printf("%d. %s\n", i++, trimmed);
            }
        }

        return sb.str;
    }

    private string cmd_help() {
        return "MQTT Bot Commands\n" +
               "─────────────────\n" +
               "/mqtt status              — Connection status\n" +
               "/mqtt subscribe <topic>   — Subscribe to a topic\n" +
               "/mqtt unsubscribe <topic> — Unsubscribe from a topic\n" +
               "/mqtt publish <t> <msg>   — Publish to a topic\n" +
               "/mqtt topics              — List subscriptions\n" +
               "/mqtt alert <topic> <op> <value>\n" +
               "                          — Set threshold alert\n" +
               "/mqtt alerts              — List alert rules\n" +
               "/mqtt rmalert <number>    — Remove alert rule\n" +
               "/mqtt priority <topic> <level>\n" +
               "                          — Set topic priority\n" +
               "/mqtt history [topic] [N] — Show topic history\n" +
               "/mqtt pause               — Pause messages\n" +
               "/mqtt resume              — Resume messages\n" +
               "/mqtt help                — This help text\n" +
               "\n" +
               "Topic wildcards:\n" +
               "  + = single level (home/+/temp)\n" +
               "  # = all below   (home/sensors/#)\n" +
               "\n" +
               "Alert examples:\n" +
               "  /mqtt alert home/temp > 30\n" +
               "  /mqtt alert home/door == OPEN\n" +
               "  /mqtt alert sensors/# contains error\n" +
               "\n" +
               "Priority levels: silent, normal, alert, critical";
    }

    /* ── Phase 3: New Command Implementations ────────────────────── */

    /**
     * /mqtt alert <topic> <op> <threshold>
     * /mqtt alert <topic>.<field> <op> <threshold>
     */
    private string cmd_alert(string topic_or_field, string op_str,
                              string threshold) {
        if (topic_or_field == "" || op_str == "" || threshold == "") {
            return "Usage: /mqtt alert <topic> <op> <value>\n\n" +
                   "Operators: > < >= <= == != contains\n\n" +
                   "Examples:\n" +
                   "  /mqtt alert home/temp > 30\n" +
                   "  /mqtt alert home/sensors/# contains error\n" +
                   "  /mqtt alert home/data.temperature > 25\n" +
                   "    (checks JSON field 'temperature')";
        }

        AlertOperator? op = AlertOperator.from_string(op_str);
        if (op == null) {
            return "Unknown operator: %s\n\nValid operators: > < >= <= == != contains".printf(op_str);
        }

        /* Check if topic contains a field reference: topic.field */
        string topic = topic_or_field;
        string? field = null;

        /* Split on last dot that's not part of the topic hierarchy.
         * MQTT topics use / as separator, so a dot likely indicates
         * a field reference: "home/sensors/data.temperature" */
        int dot_pos = topic_or_field.last_index_of(".");
        int slash_pos = topic_or_field.last_index_of("/");
        if (dot_pos > slash_pos && dot_pos > 0) {
            topic = topic_or_field.substring(0, dot_pos);
            field = topic_or_field.substring(dot_pos + 1);
        }

        var rule = new AlertRule();
        rule.topic = topic;
        rule.field = field;
        rule.op = op;
        rule.threshold = threshold;
        rule.priority = MqttPriority.ALERT;

        MqttAlertManager? am = plugin.get_alert_manager();
        if (am == null) {
            return "Alert manager not available.";
        }

        am.add_rule(rule);

        var sb = new StringBuilder();
        sb.append("Alert rule created ✔\n\n");
        sb.append("Topic: %s\n".printf(topic));
        if (field != null) {
            sb.append("Field: %s\n".printf(field));
        }
        sb.append("Condition: %s %s\n".printf(op.to_symbol(), threshold));
        sb.append("Priority: %s\n".printf(rule.priority.to_label()));
        sb.append("Cooldown: %llds".printf(rule.cooldown_secs));

        return sb.str;
    }

    /**
     * /mqtt alerts — List all alert rules.
     */
    private string cmd_alerts() {
        MqttAlertManager? am = plugin.get_alert_manager();
        if (am == null) return "Alert manager not available.";

        var rules = am.get_rules();
        if (rules.size == 0) {
            return "No alert rules defined.\n\n" +
                   "Use /mqtt alert <topic> <op> <value> to create one.";
        }

        var sb = new StringBuilder();
        sb.append("Alert Rules\n");
        sb.append("───────────\n");

        int i = 1;
        foreach (var rule in rules) {
            string status = rule.enabled ? "✔" : "✘";
            string field_str = (rule.field != null && rule.field != "")
                ? ".%s".printf(rule.field) : "";
            sb.append("%d. [%s] %s%s %s %s  (%s)\n".printf(
                i++, status, rule.topic, field_str,
                rule.op.to_symbol(), rule.threshold,
                rule.priority.to_string_key()));
        }

        sb.append("\nUse /mqtt rmalert <number> to remove a rule.");
        return sb.str;
    }

    /**
     * /mqtt rmalert <number> — Remove alert rule by index.
     */
    private string cmd_rmalert(string index_str) {
        if (index_str == "") {
            return "Usage: /mqtt rmalert <number>\n\n" +
                   "Use /mqtt alerts to see rule numbers.";
        }

        int index = int.parse(index_str);
        if (index <= 0) {
            return "Invalid number: %s".printf(index_str);
        }

        MqttAlertManager? am = plugin.get_alert_manager();
        if (am == null) return "Alert manager not available.";

        if (am.remove_rule_by_index(index)) {
            return "Alert rule #%d removed ✔".printf(index);
        } else {
            return "Alert rule #%d not found.\n\nUse /mqtt alerts to see rule numbers.".printf(index);
        }
    }

    /**
     * /mqtt priority <topic> <level>
     * Levels: silent, normal, alert, critical
     */
    private string cmd_priority(string topic, string level_str) {
        if (topic == "") {
            /* Show current priorities */
            MqttAlertManager? am = plugin.get_alert_manager();
            if (am == null) return "Alert manager not available.";

            var prios = am.get_all_topic_priorities();
            if (prios.size == 0) {
                return "No per-topic priority overrides set.\n" +
                       "All topics use default priority: normal\n\n" +
                       "Usage: /mqtt priority <topic> <level>\n" +
                       "Levels: silent, normal, alert, critical";
            }

            var sb = new StringBuilder();
            sb.append("Topic Priority Overrides\n");
            sb.append("───────────────────────\n");
            foreach (var entry in prios.entries) {
                sb.append("%s → %s\n".printf(entry.key,
                    entry.value.to_label()));
            }
            sb.append("\nUse /mqtt priority <topic> normal to remove override.");
            return sb.str;
        }

        if (level_str == "") {
            return "Usage: /mqtt priority <topic> <level>\n\n" +
                   "Levels: silent, normal, alert, critical\n\n" +
                   "Examples:\n" +
                   "  /mqtt priority home/sensors/heartbeat silent\n" +
                   "  /mqtt priority home/alerts/# critical";
        }

        MqttPriority prio = MqttPriority.from_string(level_str);
        MqttAlertManager? am = plugin.get_alert_manager();
        if (am == null) return "Alert manager not available.";

        am.set_topic_priority(topic, prio);

        if (prio == MqttPriority.NORMAL) {
            return "Topic '%s' reset to default priority (normal) ✔".printf(topic);
        }
        return "Topic '%s' priority set to %s ✔".printf(topic, prio.to_label());
    }

    /**
     * /mqtt history [topic] [N]
     */
    private string cmd_history(string topic, string count_str) {
        MqttAlertManager? am = plugin.get_alert_manager();
        if (am == null) return "Alert manager not available.";

        if (topic == "") {
            /* List topics with history */
            var topics = am.get_history_topics();
            if (topics.size == 0) {
                return "No topic history available yet.\n" +
                       "History is recorded when MQTT messages arrive.";
            }

            var sb = new StringBuilder();
            sb.append("Topics with History\n");
            sb.append("───────────────────\n");
            int i = 1;
            foreach (string t in topics) {
                var entries = am.get_history(t);
                int count = (entries != null) ? entries.size : 0;
                sb.append("%d. %s (%d entries)\n".printf(i++, t, count));
            }
            sb.append("\nUse /mqtt history <topic> [N] to see values.");
            return sb.str;
        }

        int max_entries = 10;
        if (count_str != "") {
            int parsed = int.parse(count_str);
            if (parsed > 0) max_entries = parsed;
        }

        var entries = am.get_history(topic);
        if (entries == null || entries.size == 0) {
            return "No history for topic: %s".printf(topic);
        }

        var sb = new StringBuilder();
        sb.append("History: %s\n".printf(topic));
        sb.append("────────");
        for (int j = 0; j < topic.length && j < 40; j++) sb.append("─");
        sb.append("\n");

        /* Show last N entries */
        int start = (entries.size > max_entries) ?
            entries.size - max_entries : 0;
        for (int i = start; i < entries.size; i++) {
            var entry = entries[i];
            string time_str = entry.timestamp.format("%H:%M:%S");
            string prio_icon = entry.triggered_priority.to_icon();
            string prio_prefix = (prio_icon != "") ? prio_icon + " " : "";
            /* Truncate long payloads */
            string payload_display = entry.payload.strip();
            if (payload_display.length > 60) {
                payload_display = payload_display.substring(0, 57) + "...";
            }
            sb.append("[%s] %s%s\n".printf(time_str, prio_prefix,
                payload_display));
        }

        if (entries.size > max_entries) {
            sb.append("\n(%d more entries — use /mqtt history %s %d to see all)".printf(
                entries.size - max_entries, topic, entries.size));
        }

        return sb.str;
    }

    /**
     * /mqtt pause — Pause message display (history still recorded).
     */
    private string cmd_pause() {
        MqttAlertManager? am = plugin.get_alert_manager();
        if (am == null) return "Alert manager not available.";

        if (am.paused) {
            return "Messages are already paused.\n" +
                   "Use /mqtt resume to resume.";
        }

        am.paused = true;
        return "MQTT messages paused ⏸\n\n" +
               "Messages are still recorded in history.\n" +
               "Use /mqtt resume to resume display.";
    }

    /**
     * /mqtt resume — Resume message display.
     */
    private string cmd_resume() {
        MqttAlertManager? am = plugin.get_alert_manager();
        if (am == null) return "Alert manager not available.";

        if (!am.paused) {
            return "Messages are not paused.";
        }

        am.paused = false;
        return "MQTT messages resumed ▶\n\n" +
               "Incoming messages will appear as chat bubbles again.";
    }

    /* ── DB helpers ──────────────────────────────────────────────── */

    private string? get_db_setting(string key) {
        var row_opt = plugin.app.db.settings.select({plugin.app.db.settings.value})
            .with(plugin.app.db.settings.key, "=", key)
            .single()
            .row();
        if (row_opt.is_present()) return row_opt[plugin.app.db.settings.value];
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
