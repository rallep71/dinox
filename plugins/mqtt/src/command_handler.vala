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
     * Determine the connection key for a bot conversation.
     * Returns the account JID for per-account bots, "standalone" for standalone.
     * Falls back to "standalone" if unknown.
     */
    private string get_connection_key(Conversation conversation) {
        string? key = bot.get_connection_key(conversation);
        return key ?? MqttBotConversation.STANDALONE_KEY;
    }

    /**
     * Get the MqttClient for the conversation's connection.
     */
    private MqttClient? get_client_for_conversation(Conversation conversation) {
        string key = get_connection_key(conversation);
        if (key == MqttBotConversation.STANDALONE_KEY) {
            return plugin.get_standalone_client();
        }
        return plugin.get_client_for_account(key);
    }

    /**
     * Get the MqttConnectionConfig for the conversation's connection.
     */
    private MqttConnectionConfig? get_config_for_conversation(Conversation conversation) {
        string key = get_connection_key(conversation);
        if (key == MqttBotConversation.STANDALONE_KEY) {
            return plugin.get_standalone_config();
        }
        /* Find account by JID */
        var accounts = plugin.app.stream_interactor.get_accounts();
        foreach (var acct in accounts) {
            if (acct.bare_jid.to_string() == key) {
                return plugin.get_account_config(acct);
            }
        }
        return null;
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
                response = cmd_subscribe(arg1, conversation);
                break;

            case "unsubscribe":
            case "unsub":
                response = cmd_unsubscribe(arg1, conversation);
                break;

            case "publish":
            case "pub":
                response = cmd_publish(arg1, arg2);
                break;

            case "topics":
            case "list":
                response = cmd_topics(conversation);
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

            case "qos":
                response = cmd_qos(arg1, arg2);
                break;

            case "chart":
            case "sparkline":
                response = cmd_chart(arg1, arg2);
                break;

            case "bridge":
                response = cmd_bridge(arg1, arg2);
                break;

            case "bridges":
                response = cmd_bridges();
                break;

            case "rmbridge":
            case "delbridge":
                response = cmd_rmbridge(arg1);
                break;

            case "manager":
            case "manage":
                response = cmd_manager(conversation);
                break;

            case "dbstats":
            case "db":
                response = cmd_dbstats();
                break;

            case "purge":
                response = cmd_purge();
                break;

            case "preset":
                response = cmd_preset(arg1, arg2, arg3, conversation);
                break;

            case "presets":
                response = cmd_presets(conversation);
                break;

            case "config":
                response = cmd_config(conversation);
                break;

            case "discovery":
                response = cmd_discovery(arg1, conversation);
                break;

            case "reconnect":
                response = cmd_reconnect(conversation);
                break;

            case "help":
            case "?":
                response = cmd_help();
                break;

            default:
                response = _("Unknown command: /mqtt %s\n\nType /mqtt help for available commands.").printf(subcmd);
                break;
        }

        /* Inject response as incoming bot message */
        bot.inject_bot_message(conversation, response);
        return true;
    }

    /* ── Command Implementations ─────────────────────────────────── */

    private string cmd_status() {
        var sb = new StringBuilder();
        sb.append(_("MQTT Status\n"));
        sb.append("───────────\n");

        /* Standalone client */
        MqttClient? standalone = plugin.get_standalone_client();
        if (standalone != null) {
            sb.append_printf(_("Standalone: %s\n"),
                standalone.is_connected ? _("Connected ✔") : _("Disconnected ✘"));
        }

        /* Per-account clients */
        var accounts = plugin.app.stream_interactor.get_accounts();
        foreach (var acct in accounts) {
            MqttClient? client = plugin.get_client_for_account(
                acct.bare_jid.to_string());
            if (client != null) {
                sb.append_printf(_("Account %s: %s\n"),
                    acct.bare_jid.to_string(),
                    client.is_connected ? _("Connected ✔") : _("Disconnected ✘"));
            }
        }

        if (standalone == null && accounts.size == 0) {
            sb.append(_("No active MQTT connections.\n"));
            sb.append(_("Enable MQTT in Preferences > Account > MQTT Bot."));
        }

        return sb.str;
    }

    private string cmd_subscribe(string topic, Conversation conversation) {
        if (topic == "") {
            return _("Usage: /mqtt subscribe <topic>\n\nExamples:\n  /mqtt subscribe home/sensors/#\n  /mqtt subscribe home/+/temperature");
        }

        /* Persist to the correct connection config (standalone or per-account) */
        var cfg = get_config_for_conversation(conversation);
        if (cfg == null) return _("No config available for this connection.");

        string existing = cfg.topics ?? "";
        if (existing.strip() != "") {
            /* Check for duplicates */
            string[] parts = existing.split(",");
            foreach (string p in parts) {
                if (p.strip() == topic) {
                    return _("Already subscribed to: %s").printf(topic);
                }
            }
            cfg.topics = existing + "," + topic;
        } else {
            cfg.topics = topic;
        }
        save_config_for_conversation(conversation, cfg);

        /* Subscribe on the correct client */
        string key = get_connection_key(conversation);
        plugin.subscribe(topic, 0, key);

        /* Reload config so cfg_topics stays in sync */
        plugin.reload_config();

        return _("Subscribed to: %s ✔").printf(topic);
    }

    private string cmd_unsubscribe(string topic, Conversation conversation) {
        if (topic == "") {
            return _("Usage: /mqtt unsubscribe <topic>");
        }

        /* Persist removal to the correct connection config */
        var cfg = get_config_for_conversation(conversation);
        if (cfg == null) return _("No config available for this connection.");

        string existing = cfg.topics ?? "";
        if (existing.strip() != "") {
            string[] parts = existing.split(",");
            var remaining = new ArrayList<string>();
            bool found = false;
            foreach (string p in parts) {
                if (p.strip() == topic) {
                    found = true;
                } else if (p.strip() != "") {
                    remaining.add(p.strip());
                }
            }
            if (found) {
                cfg.topics = string.joinv(",", remaining.to_array());
                save_config_for_conversation(conversation, cfg);

                /* Unsubscribe on the correct client */
                string key = get_connection_key(conversation);
                plugin.unsubscribe(topic, key);

                /* Reload config so cfg_topics stays in sync */
                plugin.reload_config();
                return _("Unsubscribed from: %s ✔").printf(topic);
            }
        }

        return _("Topic not found in subscriptions: %s").printf(topic);
    }

    private string cmd_publish(string topic, string payload) {
        if (topic == "") {
            return _("Usage: /mqtt publish <topic> <payload>\n\nExample:\n  /mqtt publish home/light/set ON");
        }
        if (payload == "") {
            return _("Usage: /mqtt publish <topic> <payload>\n\nPayload cannot be empty.");
        }

        /* Publish on all active connections (same as before) */
        plugin.publish(topic, payload);
        return _("Published to %s:\n%s").printf(topic, payload);
    }

    private string cmd_topics(Conversation conversation) {
        var cfg = get_config_for_conversation(conversation);
        string? topics_str = (cfg != null) ? cfg.topics : null;
        if (topics_str == null || topics_str.strip() == "") {
            return _("No topic subscriptions configured.\n\nUse /mqtt subscribe <topic> to add one.");
        }

        string[] topics = topics_str.split(",");
        var sb = new StringBuilder();
        sb.append(_("Active Topic Subscriptions\n"));
        sb.append("─────────────────────────\n");

        MqttAlertManager? am = plugin.get_alert_manager();

        int i = 1;
        foreach (string t in topics) {
            string trimmed = t.strip();
            if (trimmed != "") {
                int qos = (am != null) ? am.get_topic_qos(trimmed) : 0;
                MqttPriority prio = (am != null) ?
                    am.get_topic_priority(trimmed) : MqttPriority.NORMAL;
                string extras = "QoS %d".printf(qos);
                if (prio != MqttPriority.NORMAL) {
                    extras += ", %s".printf(prio.to_string_key());
                }
                sb.append_printf("%d. %s  [%s]\n", i++, trimmed, extras);
            }
        }

        return sb.str;
    }

    private string cmd_help() {
        return _("MQTT Bot Commands\n" +
               "─────────────────\n" +
               "/mqtt status              — Connection status\n" +
               "/mqtt subscribe <topic>   — Subscribe to a topic\n" +
               "/mqtt unsubscribe <topic> — Unsubscribe from a topic\n" +
               "/mqtt publish <t> <msg>   — Publish to a topic\n" +
               "/mqtt topics              — List subscriptions\n" +
               "/mqtt qos <topic> <0|1|2> — Set topic QoS level\n" +
               "/mqtt chart <topic> [N]   — Sparkline chart\n" +
               "/mqtt bridge <topic> <jid>— Forward to XMPP contact\n" +
               "/mqtt bridges             — List bridge rules\n" +
               "/mqtt rmbridge <number>   — Remove bridge rule\n" +
               "/mqtt preset add <name> <topic> <payload>\n" +
               "                          — Add publish preset\n" +
               "/mqtt preset remove <N>   — Remove preset by number\n" +
               "/mqtt preset <name>       — Execute preset\n" +
               "/mqtt presets             — List all presets\n" +
               "/mqtt config              — Show connection config\n" +
               "/mqtt reconnect           — Force reconnect\n" +
               "/mqtt manager             — Open Topic Manager\n" +
               "/mqtt alert <topic> <op> <value>\n" +
               "                          — Set threshold alert\n" +
               "/mqtt alerts              — List alert rules\n" +
               "/mqtt rmalert <number>    — Remove alert rule\n" +
               "/mqtt priority <topic> <level>\n" +
               "                          — Set topic priority\n" +
               "/mqtt history [topic] [N] — Show topic history\n" +
               "/mqtt dbstats             — Database statistics\n" +
               "/mqtt purge               — Manual data cleanup\n" +
               "/mqtt pause               — Pause messages\n" +
               "/mqtt resume              — Resume messages\n" +
               "/mqtt discovery [on|off]  — HA Discovery status/toggle\n" +
               "/mqtt help                — This help text\n" +
               "\n" +
               "Topic wildcards:\n" +
               "  + = single level (home/+/temp)\n" +
               "  # = all below   (home/sensors/#)\n" +
               "\n" +
               "Alert examples:\n" +
               "  /mqtt alert home/temp > 30\n" +
               "  /mqtt alert home/door == OPEN\n" +
               "\n" +
               "Bridge example:\n" +
               "  /mqtt bridge home/alerts/# user@example.com\n" +
               "\n" +
               "Preset example:\n" +
               "  /mqtt preset add LichtAN home/light/set ON\n" +
               "  /mqtt preset LichtAN\n" +
               "\n" +
               "QoS levels: 0 (fire&forget), 1 (ack), 2 (exactly once)\n" +
               "Priority levels: silent, normal, alert, critical\n" +
               "\n" +
               "HA Discovery:\n" +
               "  /mqtt discovery         — Show discovery status\n" +
               "  /mqtt discovery on      — Enable & publish\n" +
               "  /mqtt discovery off     — Disable & remove");
    }

    /* ── Phase 3: New Command Implementations ────────────────────── */

    /**
     * /mqtt alert <topic> <op> <threshold>
     * /mqtt alert <topic>.<field> <op> <threshold>
     */
    private string cmd_alert(string topic_or_field, string op_str,
                              string threshold) {
        if (topic_or_field == "" || op_str == "" || threshold == "") {
            return _("Usage: /mqtt alert <topic> <op> <value>\n\n" +
                   "Operators: > < >= <= == != contains\n\n" +
                   "Examples:\n" +
                   "  /mqtt alert home/temp > 30\n" +
                   "  /mqtt alert home/sensors/# contains error\n" +
                   "  /mqtt alert home/data.temperature > 25\n" +
                   "    (checks JSON field 'temperature')");
        }

        AlertOperator? op = AlertOperator.from_string(op_str);
        if (op == null) {
            return _("Unknown operator: %s\n\nValid operators: > < >= <= == != contains").printf(op_str);
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
            return _("Alert manager not available.");
        }

        am.add_rule(rule);

        var sb = new StringBuilder();
        sb.append(_("Alert rule created ✔\n\n"));
        sb.append(_("Topic: %s\n").printf(topic));
        if (field != null) {
            sb.append(_("Field: %s\n").printf(field));
        }
        sb.append(_("Condition: %s %s\n").printf(op.to_symbol(), threshold));
        sb.append(_("Priority: %s\n").printf(rule.priority.to_label()));
        sb.append(_("Cooldown: %llds").printf(rule.cooldown_secs));

        return sb.str;
    }

    /**
     * /mqtt alerts — List all alert rules.
     */
    private string cmd_alerts() {
        MqttAlertManager? am = plugin.get_alert_manager();
        if (am == null) return _("Alert manager not available.");

        var rules = am.get_rules();
        if (rules.size == 0) {
            return _("No alert rules defined.\n\n" +
                   "Use /mqtt alert <topic> <op> <value> to create one.");
        }

        var sb = new StringBuilder();
        sb.append(_("Alert Rules\n"));
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

        sb.append(_("\nUse /mqtt rmalert <number> to remove a rule."));
        return sb.str;
    }

    /**
     * /mqtt rmalert <number> — Remove alert rule by index.
     */
    private string cmd_rmalert(string index_str) {
        if (index_str == "") {
            return _("Usage: /mqtt rmalert <number>\n\n" +
                   "Use /mqtt alerts to see rule numbers.");
        }

        int index = int.parse(index_str);
        if (index <= 0) {
            return _("Invalid number: %s").printf(index_str);
        }

        MqttAlertManager? am = plugin.get_alert_manager();
        if (am == null) return _("Alert manager not available.");

        if (am.remove_rule_by_index(index)) {
            return _("Alert rule #%d removed ✔").printf(index);
        } else {
            return _("Alert rule #%d not found.\n\nUse /mqtt alerts to see rule numbers.").printf(index);
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
            if (am == null) return _("Alert manager not available.");

            var prios = am.get_all_topic_priorities();
            if (prios.size == 0) {
                return _("No per-topic priority overrides set.\n" +
                       "All topics use default priority: normal\n\n" +
                       "Usage: /mqtt priority <topic> <level>\n" +
                       "Levels: silent, normal, alert, critical");
            }

            var sb = new StringBuilder();
            sb.append(_("Topic Priority Overrides\n"));
            sb.append("───────────────────────\n");
            foreach (var entry in prios.entries) {
                sb.append("%s → %s\n".printf(entry.key,
                    entry.value.to_label()));
            }
            sb.append(_("\nUse /mqtt priority <topic> normal to remove override."));
            return sb.str;
        }

        if (level_str == "") {
            return _("Usage: /mqtt priority <topic> <level>\n\n" +
                   "Levels: silent, normal, alert, critical\n\n" +
                   "Examples:\n" +
                   "  /mqtt priority home/sensors/heartbeat silent\n" +
                   "  /mqtt priority home/alerts/# critical");
        }

        MqttPriority prio = MqttPriority.from_string(level_str);
        MqttAlertManager? am = plugin.get_alert_manager();
        if (am == null) return _("Alert manager not available.");

        am.set_topic_priority(topic, prio);

        if (prio == MqttPriority.NORMAL) {
            return _("Topic '%s' reset to default priority (normal) ✔").printf(topic);
        }
        return _("Topic '%s' priority set to %s ✔").printf(topic, prio.to_label());
    }

    /**
     * /mqtt history [topic] [N]
     */
    private string cmd_history(string topic, string count_str) {
        MqttAlertManager? am = plugin.get_alert_manager();
        if (am == null) return _("Alert manager not available.");
        if (plugin.mqtt_db != null) {
            return cmd_history_from_db(topic, count_str);
        }

        /* Fallback: RAM-only history from alert_manager */
        if (topic == "") {
            /* List topics with history */
            var topics = am.get_history_topics();
            if (topics.size == 0) {
                return _("No topic history available yet.\n" +
                       "History is recorded when MQTT messages arrive.");
            }

            var sb = new StringBuilder();
            sb.append(_("Topics with History\n"));
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
            return _("No history for topic: %s").printf(topic);
        }

        var sb = new StringBuilder();
        sb.append(_("History: %s\n").printf(topic));
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
     * DB-backed /mqtt history implementation (Phase 1c).
     */
    private string cmd_history_from_db(string topic, string count_str) {
        var db = plugin.mqtt_db;

        if (topic == "") {
            /* List topics with stats from DB */
            var stats = db.get_all_topic_stats_all();
            if (stats.size == 0) {
                return _("No topic history available yet.\n" +
                       "History is recorded when MQTT messages arrive.");
            }

            var sb = new StringBuilder();
            sb.append(_("Topics with History\n"));
            sb.append("───────────────────\n");
            int i = 1;
            foreach (var row in stats) {
                string t = db.topic_stats.topic[row];
                long count = db.topic_stats.message_count[row];
                string? last_val = db.topic_stats.last_payload[row];
                string last_preview = "";
                if (last_val != null && last_val.strip() != "") {
                    last_preview = last_val.strip();
                    if (last_preview.length > 30) {
                        last_preview = last_preview.substring(0, 27) + "...";
                    }
                    last_preview = " → " + last_preview;
                }
                sb.append("%d. %s (%ld msgs%s)\n".printf(i++, t, count, last_preview));
            }
            sb.append(_("\nUse /mqtt history <topic> [N] to see values."));
            return sb.str;
        }

        int max_entries = 10;
        if (count_str != "") {
            int parsed = int.parse(count_str);
            if (parsed > 0) max_entries = parsed;
        }

        var rows = db.get_topic_history_all(topic, max_entries);
        if (rows.size == 0) {
            return _("No history for topic: %s").printf(topic);
        }

        var sb = new StringBuilder();
        sb.append(_("History: %s (DB)\n").printf(topic));
        sb.append("────────");
        for (int j = 0; j < topic.length && j < 40; j++) sb.append("─");
        sb.append("\n");

        /* Rows are newest first from DB — reverse for chronological display */
        for (int i = rows.size - 1; i >= 0; i--) {
            var row = rows[i];
            long ts = db.messages.timestamp[row];
            var dt = new DateTime.from_unix_utc(ts).to_local();
            string time_str = dt.format("%H:%M:%S");
            string prio_str = db.messages.priority[row];
            MqttPriority prio = MqttPriority.from_string(prio_str);
            string prio_icon = prio.to_icon();
            string prio_prefix = (prio_icon != "") ? prio_icon + " " : "";
            string? payload_raw = db.messages.payload[row];
            string payload_display = (payload_raw != null) ? payload_raw.strip() : "";
            if (payload_display.length > 60) {
                payload_display = payload_display.substring(0, 57) + "...";
            }
            sb.append("[%s] %s%s\n".printf(time_str, prio_prefix, payload_display));
        }

        /* Check if there are more entries in DB */
        var all_stats = db.get_all_topic_stats_all();
        foreach (var srow in all_stats) {
            if (db.topic_stats.topic[srow] == topic) {
                long total = db.topic_stats.message_count[srow];
                if (total > max_entries) {
                    sb.append("\n(%ld total — use /mqtt history %s %ld to see all)".printf(
                        total, topic, total));
                }
                break;
            }
        }

        return sb.str;
    }

    /**
     * /mqtt pause — Pause message display (history still recorded).
     */
    private string cmd_pause() {
        MqttAlertManager? am = plugin.get_alert_manager();
        if (am == null) return _("Alert manager not available.");

        if (am.paused) {
            return _("Messages are already paused.\n" +
                   "Use /mqtt resume to resume.");
        }

        am.paused = true;
        return _("MQTT messages paused ⏸\n\n" +
               "Messages are still recorded in history.\n" +
               "Use /mqtt resume to resume display.");
    }

    /**
     * /mqtt resume — Resume message display.
     */
    private string cmd_resume() {
        MqttAlertManager? am = plugin.get_alert_manager();
        if (am == null) return _("Alert manager not available.");

        if (!am.paused) {
            return _("Messages are not paused.");
        }

        am.paused = false;
        return _("MQTT messages resumed ▶\n\n" +
               "Incoming messages will appear as chat bubbles again.");
    }

    /**
     * /mqtt qos [topic] [0|1|2]
     * Without args: show all QoS settings.
     * With args: set QoS for a topic.
     */
    private string cmd_qos(string topic, string level_str) {
        MqttAlertManager? am = plugin.get_alert_manager();
        if (am == null) return _("Alert manager not available.");

        if (topic == "") {
            /* Show current QoS settings */
            var qos_map = am.get_all_topic_qos();
            if (qos_map.size == 0) {
                return _("No per-topic QoS overrides set.\n" +
                       "All topics use default QoS: 0 (at most once)\n\n" +
                       "Usage: /mqtt qos <topic> <0|1|2>\n\n" +
                       "QoS levels:\n" +
                       "  0 = At most once (fire & forget)\n" +
                       "  1 = At least once (acknowledged)\n" +
                       "  2 = Exactly once (guaranteed)");
            }

            var sb = new StringBuilder();
            sb.append(_("Topic QoS Settings\n"));
            sb.append("──────────────────\n");
            foreach (var entry in qos_map.entries) {
                sb.append("%s → QoS %d (%s)\n".printf(
                    entry.key, entry.value, qos_label(entry.value)));
            }
            sb.append(_("\nUse /mqtt qos <topic> 0 to reset to default."));
            return sb.str;
        }

        if (level_str == "") {
            /* Show QoS for specific topic */
            int current = am.get_topic_qos(topic);
            return _("Topic '%s' QoS: %d (%s)\n\n").printf(
                       topic, current, qos_label(current)) +
                   _("Usage: /mqtt qos <topic> <0|1|2>");
        }

        int qos = int.parse(level_str);
        if (qos < 0 || qos > 2) {
            return _("Invalid QoS level: %s\n\nValid values: 0, 1, 2").printf(level_str);
        }

        am.set_topic_qos(topic, qos);

        /* Re-subscribe with new QoS on active connections */
        plugin.subscribe(topic, qos);

        if (qos == 0) {
            return _("Topic '%s' QoS reset to default (0 — at most once) ✔").printf(topic);
        }
        return _("Topic '%s' QoS set to %d (%s) ✔\n\n").printf(
                   topic, qos, qos_label(qos)) +
               _("Active subscriptions have been updated.");
    }

    private string qos_label(int qos) {
        switch (qos) {
            case 0: return _("at most once");
            case 1: return _("at least once");
            case 2: return _("exactly once");
            default: return _("unknown");
        }
    }

    /**
     * /mqtt chart [topic] [N]
     * Generate a sparkline chart from topic history.
     */
    private string cmd_chart(string topic, string count_str) {
        MqttAlertManager? am = plugin.get_alert_manager();
        if (am == null) return _("Alert manager not available.");

        if (topic == "") {
            /* Show topics with numeric history */
            var topics = am.get_history_topics();
            if (topics.size == 0) {
                return _("No topic history available.\n" +
                       "History is recorded when MQTT messages arrive.\n\n" +
                       "Usage: /mqtt chart <topic> [N]");
            }

            var sb = new StringBuilder();
            sb.append(_("Topics with History Data\n"));
            sb.append("───────────────────────\n");
            int i = 1;
            foreach (string t in topics) {
                var entries = am.get_history(t);
                int count = (entries != null) ? entries.size : 0;
                sb.append("%d. %s (%d values)\n".printf(i++, t, count));
            }
            sb.append(_("\nUse /mqtt chart <topic> [N] to generate a chart."));
            return sb.str;
        }

        int max_points = 20;
        if (count_str != "") {
            int parsed = int.parse(count_str);
            if (parsed > 0 && parsed <= 50) max_points = parsed;
        }

        string? chart = am.generate_sparkline(topic, max_points);
        if (chart == null) {
            return _("Cannot generate chart for '%s'.\n\n").printf(topic) +
                   _("Possible reasons:\n" +
                   "• No history data for this topic\n" +
                   "• Payload is not numeric (need numbers or JSON with numeric fields)\n" +
                   "• Less than 2 data points available");
        }

        return chart;
    }

    /* ── Phase 4: Bridge Commands ────────────────────────────────── */

    /**
     * /mqtt bridge <topic> <jid>  — Create MQTT→XMPP bridge.
     */
    private string cmd_bridge(string topic, string jid_str) {
        if (topic == "" || jid_str == "") {
            return _("Usage: /mqtt bridge <topic> <jid>\n\n" +
                   "Forward MQTT messages to an XMPP contact.\n\n" +
                   "Examples:\n" +
                   "  /mqtt bridge home/alerts/# user@example.com\n" +
                   "  /mqtt bridge sensors/fire admin@company.org");
        }

        /* Validate JID */
        try {
            new Xmpp.Jid(jid_str);
        } catch (Xmpp.InvalidJidError e) {
            return _("Invalid JID: %s\n\n%s").printf(jid_str, e.message);
        }

        MqttBridgeManager? bm = plugin.get_bridge_manager();
        if (bm == null) return _("Bridge manager not available.");

        var rule = new BridgeRule();
        rule.topic = topic;
        rule.target_jid = jid_str;
        bm.add_rule(rule);

        return _("Bridge rule created ✔\n\n" +
               "Topic: %s\n").printf(topic) +
               _("Target: %s\n\n").printf(jid_str) +
               _("MQTT messages matching this topic will be forwarded\n" +
               "as XMPP chat messages to the target contact.");
    }

    /**
     * /mqtt bridges — List all bridge rules.
     */
    private string cmd_bridges() {
        MqttBridgeManager? bm = plugin.get_bridge_manager();
        if (bm == null) return _("Bridge manager not available.");

        var rules = bm.get_rules();
        if (rules.size == 0) {
            return _("No bridge rules defined.\n\n" +
                   "Use /mqtt bridge <topic> <jid> to create one.");
        }

        var sb = new StringBuilder();
        sb.append(_("MQTT → XMPP Bridge Rules\n"));
        sb.append("────────────────────────\n");

        int i = 1;
        foreach (var rule in rules) {
            string status = rule.enabled ? "✔" : "✘";
            sb.append("%d. [%s] %s → %s\n".printf(
                i++, status, rule.topic, rule.target_jid));
        }

        sb.append(_("\nUse /mqtt rmbridge <number> to remove a rule."));
        return sb.str;
    }

    /**
     * /mqtt rmbridge <number> — Remove bridge rule by index.
     */
    private string cmd_rmbridge(string index_str) {
        if (index_str == "") {
            return _("Usage: /mqtt rmbridge <number>\n\n" +
                   "Use /mqtt bridges to see rule numbers.");
        }

        int index = int.parse(index_str);
        if (index <= 0) {
            return _("Invalid number: %s").printf(index_str);
        }

        MqttBridgeManager? bm = plugin.get_bridge_manager();
        if (bm == null) return _("Bridge manager not available.");

        if (bm.remove_rule_by_index(index)) {
            return _("Bridge rule #%d removed ✔").printf(index);
        } else {
            return _("Bridge rule #%d not found.\n\nUse /mqtt bridges to see rule numbers.").printf(index);
        }
    }

    /**
     * /mqtt manager — Open visual topic manager dialog.
     */
    private string cmd_manager(Conversation conversation) {
        string? conn_key = get_connection_key(conversation);
        Idle.add(() => {
            var dialog = new MqttTopicManagerDialog(plugin, conn_key);
            var gtk_app = plugin.app as Gtk.Application;
            if (gtk_app != null && gtk_app.active_window != null) {
                dialog.present(gtk_app.active_window);
            }
            return false;
        });

        return _("Opening Topic Manager…");
    }

    /* ── Database maintenance commands ───────────────────────────── */

    /**
     * /mqtt dbstats — Show database size and row counts.
     */
    private string cmd_dbstats() {
        if (plugin.mqtt_db == null) {
            return _("MQTT database not available.");
        }
        return plugin.mqtt_db.get_stats_summary();
    }

    /**
     * /mqtt purge — Manually trigger data retention purge.
     */
    private string cmd_purge() {
        if (plugin.mqtt_db == null) {
            return _("MQTT database not available.");
        }
        int deleted = plugin.mqtt_db.purge_expired();
        if (deleted == 0) {
            return _("No expired data found. All data is within retention limits:\n" +
                   "• Messages: %d days\n").printf(
                       (int)(MqttDatabase.RETENTION_MESSAGES_SECS / 86400)) +
                   _("• Freetext: %d days\n").printf(
                       (int)(MqttDatabase.RETENTION_FREETEXT_SECS / 86400)) +
                   _("• Connection Log: %d days\n").printf(
                       (int)(MqttDatabase.RETENTION_CONNLOG_SECS / 86400)) +
                   _("• Publish History: %d days").printf(
                       (int)(MqttDatabase.RETENTION_PUBLISH_HIST_SECS / 86400));
        }
        return _("Purge complete: %d expired rows deleted ✔").printf(deleted);
    }

    /* ── Phase 2: Preset, Config, Reconnect Commands ────────────── */

    /**
     * /mqtt preset add <name> <topic> <payload>
     * /mqtt preset remove <number>
     * /mqtt preset <name>  — execute a named preset
     */
    private string cmd_preset(string subcmd, string arg2, string arg3,
                               Conversation conversation) {
        if (subcmd == "" || subcmd == "list") {
            return cmd_presets(conversation);
        }

        if (subcmd == "add") {
            return cmd_preset_add(arg2, arg3, conversation);
        }

        if (subcmd == "remove" || subcmd == "rm" || subcmd == "del") {
            return cmd_preset_remove(arg2, conversation);
        }

        /* Otherwise: treat subcmd as preset name to execute */
        return cmd_preset_exec(subcmd, conversation);
    }

    /**
     * /mqtt presets — List all publish presets for this connection.
     */
    private string cmd_presets(Conversation conversation) {
        var cfg = get_config_for_conversation(conversation);
        if (cfg == null) return _("No config available for this connection.");

        ArrayList<PresetEntry> presets = parse_presets_json(cfg.publish_presets_json);

        if (presets.size == 0) {
            return _("No publish presets defined.\n\n" +
                   "Use /mqtt preset add <name> <topic> <payload> to create one.\n\n" +
                   "Example:\n" +
                   "  /mqtt preset add LichtAN home/light/set ON");
        }

        var sb = new StringBuilder();
        sb.append(_("Publish Presets\n"));
        sb.append("───────────────\n");
        int i = 1;
        foreach (var p in presets) {
            sb.append("%d. %s → %s : %s\n".printf(i++, p.name, p.topic, p.payload));
        }
        sb.append(_("\nUse /mqtt preset <name> to publish."));
        sb.append(_("\nUse /mqtt preset remove <number> to delete."));
        return sb.str;
    }

    /**
     * Add a new preset.
     */
    private string cmd_preset_add(string topic, string payload,
                                    Conversation conversation) {
        /* arg2 = topic (required), arg3 = payload (required).
         * But the command is: /mqtt preset add <name> <topic> <payload>
         * Due to split limits, we need to reparse. The caller used
         * split(" ", 4), so arg1="add", arg2=<name>, arg3="<topic> <payload>" */
        string name = topic;  /* arg2 is actually the name */
        if (name == "" || payload == "") {
            return _("Usage: /mqtt preset add <name> <topic> <payload>\n\n" +
                   "Example:\n" +
                   "  /mqtt preset add LichtAN home/light/set ON\n" +
                   "  /mqtt preset add TempRead home/sensor/get read");
        }

        /* payload contains "topic payload" — split on first space */
        string[] parts = payload.split(" ", 2);
        string preset_topic = parts[0];
        string preset_payload = (parts.length > 1) ? parts[1] : "";

        if (preset_topic == "" || preset_payload == "") {
            return _("Usage: /mqtt preset add <name> <topic> <payload>");
        }

        var cfg = get_config_for_conversation(conversation);
        if (cfg == null) return _("No config available for this connection.");

        /* Parse existing presets */
        ArrayList<PresetEntry> presets = parse_presets_json(cfg.publish_presets_json);

        /* Check for duplicate name */
        foreach (var p in presets) {
            if (p.name.down() == name.down()) {
                return _("Preset '%s' already exists. Remove it first with /mqtt preset remove <N>.").printf(name);
            }
        }

        /* Add new preset */
        var entry = new PresetEntry();
        entry.id = Xmpp.random_uuid();
        entry.name = name;
        entry.topic = preset_topic;
        entry.payload = preset_payload;
        presets.add(entry);

        /* Serialize and save */
        cfg.publish_presets_json = build_presets_json(presets);
        save_config_for_conversation(conversation, cfg);

        return _("Preset '%s' created ✔\n\nTopic: %s\nPayload: %s\n\nUse /mqtt preset %s to publish.").printf(
            name, preset_topic, preset_payload, name);
    }

    /**
     * Remove a preset by number.
     */
    private string cmd_preset_remove(string index_str, Conversation conversation) {
        if (index_str == "") {
            return _("Usage: /mqtt preset remove <number>\n\nUse /mqtt presets to see numbers.");
        }

        int index = int.parse(index_str);
        if (index <= 0) {
            return _("Invalid number: %s").printf(index_str);
        }

        var cfg = get_config_for_conversation(conversation);
        if (cfg == null) return _("No config available for this connection.");

        ArrayList<PresetEntry> presets = parse_presets_json(cfg.publish_presets_json);
        if (index > presets.size) {
            return _("Preset #%d not found. Use /mqtt presets to see numbers.").printf(index);
        }

        string removed_name = presets[index - 1].name;
        presets.remove_at(index - 1);

        cfg.publish_presets_json = build_presets_json(presets);
        save_config_for_conversation(conversation, cfg);

        return _("Preset '%s' (#%d) removed ✔").printf(removed_name, index);
    }

    /**
     * Execute a preset by name.
     */
    private string cmd_preset_exec(string name, Conversation conversation) {
        var cfg = get_config_for_conversation(conversation);
        if (cfg == null) return _("No config available for this connection.");

        ArrayList<PresetEntry> presets = parse_presets_json(cfg.publish_presets_json);

        PresetEntry? match = null;
        foreach (var p in presets) {
            if (p.name.down() == name.down()) {
                match = p;
                break;
            }
        }

        if (match == null) {
            return _("Preset '%s' not found.\n\nUse /mqtt presets to list available presets.").printf(name);
        }

        /* Publish on correct connection */
        string key = get_connection_key(conversation);
        string? acct_jid = (key != MqttBotConversation.STANDALONE_KEY) ? key : null;
        plugin.publish(match.topic, match.payload, match.qos, match.retain, acct_jid);

        /* Track usage */
        match.use_count++;
        cfg.publish_presets_json = build_presets_json(presets);
        save_config_for_conversation(conversation, cfg);

        return _("Published: %s → %s : %s ✔").printf(match.name, match.topic, match.payload);
    }

    /**
     * /mqtt config — Show current connection configuration.
     */
    private string cmd_config(Conversation conversation) {
        string key = get_connection_key(conversation);
        var cfg = get_config_for_conversation(conversation);
        if (cfg == null) return _("No config available for this connection.");

        var client = get_client_for_conversation(conversation);

        var sb = new StringBuilder();
        sb.append(_("MQTT Connection Config\n"));
        sb.append("──────────────────────\n");
        sb.append(_("Connection: %s\n").printf(key));
        sb.append(_("Enabled: %s\n").printf(cfg.enabled ? _("Yes") : _("No")));
        sb.append(_("Broker: %s:%d\n").printf(
            cfg.broker_host != "" ? cfg.broker_host : _("(auto-detect)"),
            cfg.broker_port));
        sb.append(_("TLS: %s\n").printf(cfg.tls ? _("Yes") : _("No")));
        sb.append(_("Server Type: %s\n").printf(cfg.server_type));

        if (cfg.use_xmpp_auth) {
            sb.append(_("Auth: XMPP Credentials (shared)\n"));
        } else if (cfg.username != "") {
            sb.append(_("Auth: %s (manual)\n").printf(cfg.username));
        } else {
            sb.append(_("Auth: None\n"));
        }

        string[] topics = cfg.get_topic_list();
        sb.append(_("Topics: %d subscribed\n").printf(topics.length));

        if (client != null) {
            sb.append(_("Status: %s\n").printf(
                client.is_connected ? _("Connected ✔") : _("Disconnected ✘")));
        } else {
            sb.append(_("Status: No client\n"));
        }

        if (cfg.freetext_enabled) {
            sb.append(_("\nFree Text Publish: Enabled\n"));
            sb.append(_("  Publish Topic: %s\n").printf(cfg.freetext_publish_topic));
            if (cfg.freetext_response_topic != "") {
                sb.append(_("  Response Topic: %s\n").printf(cfg.freetext_response_topic));
            }
        }

        return sb.str;
    }

    /**
     * /mqtt reconnect — Force disconnect + reconnect of this connection.
     */
    private string cmd_reconnect(Conversation conversation) {
        string key = get_connection_key(conversation);
        var cfg = get_config_for_conversation(conversation);
        if (cfg == null) return _("No config available for this connection.");

        if (!cfg.enabled) {
            return _("Connection '%s' is disabled. Enable it first.").printf(key);
        }

        /* Find account and trigger reconnect via apply */
        if (key == MqttBotConversation.STANDALONE_KEY) {
            /* Disconnect and reconnect standalone */
            plugin.apply_settings();
            return _("Reconnecting standalone connection…\n\nCheck /mqtt status in a few seconds.");
        }

        /* Per-account: find account and trigger reconnect */
        var accounts = plugin.app.stream_interactor.get_accounts();
        foreach (var acct in accounts) {
            if (acct.bare_jid.to_string() == key) {
                plugin.apply_account_config_change(acct, cfg);
                return _("Reconnecting %s…\n\nCheck /mqtt status in a few seconds.").printf(key);
            }
        }

        return _("Account '%s' not found.").printf(key);
    }

    /**
     * /mqtt discovery [on|off] — Show/toggle Home Assistant MQTT Discovery.
     */
    private string cmd_discovery(string action, Conversation conversation) {
        string key = get_connection_key(conversation);
        var cfg = get_config_for_conversation(conversation);
        if (cfg == null) return _("No config available for this connection.");

        var dm = plugin.get_discovery_manager(key);

        if (action == "") {
            /* Show status */
            if (!cfg.discovery_enabled) {
                return _("HA Discovery is disabled for '%s'.\n\nUse /mqtt discovery on to enable.").printf(key);
            }
            if (dm != null) {
                return dm.get_status_summary();
            }
            return _("HA Discovery is enabled (prefix: %s) but not yet connected.").printf(
                cfg.discovery_prefix);
        }

        string a = action.down().strip();

        if (a == "on" || a == "enable" || a == "1") {
            if (cfg.discovery_enabled && dm != null) {
                /* Already enabled — re-publish */
                dm.publish_discovery_config();
                dm.publish_all_states();
                return _("HA Discovery already enabled — re-published configs.");
            }
            cfg.discovery_enabled = true;
            if (cfg.discovery_prefix == "") {
                cfg.discovery_prefix = "homeassistant";
            }
            save_config_for_conversation(conversation, cfg);

            /* Reconnect needed so LWT can be set before connect */
            plugin.reload_config();
            return _("HA Discovery enabled (prefix: %s).\n\n" +
                     "Reconnecting to set LWT… check /mqtt status in a few seconds.").printf(
                cfg.discovery_prefix);
        }

        if (a == "off" || a == "disable" || a == "0") {
            if (!cfg.discovery_enabled) {
                return _("HA Discovery is already disabled.");
            }
            /* Remove discovery configs before disabling */
            if (dm != null) {
                dm.remove_discovery_configs();
            }
            cfg.discovery_enabled = false;
            save_config_for_conversation(conversation, cfg);
            return _("HA Discovery disabled — configs removed from broker.\n\n" +
                     "Home Assistant will remove the device after its availability timeout.");
        }

        if (a == "prefix") {
            return _("Current prefix: %s\n\nTo change, edit the Discovery Prefix in Settings.").printf(
                cfg.discovery_prefix != "" ? cfg.discovery_prefix : "homeassistant");
        }

        if (a == "refresh" || a == "update") {
            if (!cfg.discovery_enabled || dm == null) {
                return _("HA Discovery is not active. Enable it first with /mqtt discovery on");
            }
            dm.publish_all_states();
            return _("Published updated state for all entities.");
        }

        return _("Usage: /mqtt discovery [on|off|refresh]\n\n" +
                 "  on      — Enable HA Discovery & publish configs\n" +
                 "  off     — Disable & remove from broker\n" +
                 "  refresh — Re-publish state values");
    }

    /**
     * Save config back to the correct store (account or standalone).
     */
    private void save_config_for_conversation(Conversation conversation,
                                                MqttConnectionConfig cfg) {
        string key = get_connection_key(conversation);
        if (key == MqttBotConversation.STANDALONE_KEY) {
            plugin.save_standalone_config();
        } else {
            var accounts = plugin.app.stream_interactor.get_accounts();
            foreach (var acct in accounts) {
                if (acct.bare_jid.to_string() == key) {
                    plugin.save_account_config(acct, cfg);
                    break;
                }
            }
        }
    }

    /* ── Preset JSON helpers ─────────────────────────────────────── */

    private class PresetEntry {
        public string id = "";
        public string name = "";
        public string topic = "";
        public string payload = "";
        public int qos = 0;
        public bool retain = false;
        public int use_count = 0;
    }

    private ArrayList<PresetEntry> parse_presets_json(string json) {
        var list = new ArrayList<PresetEntry>();
        try {
            var parser = new Json.Parser();
            parser.load_from_data(json, -1);
            var root = parser.get_root();
            if (root == null || root.get_node_type() != Json.NodeType.ARRAY) return list;
            var arr = root.get_array();
            for (uint i = 0; i < arr.get_length(); i++) {
                var obj = arr.get_object_element(i);
                var e = new PresetEntry();
                e.id = obj.has_member("id") ? obj.get_string_member("id") : Xmpp.random_uuid();
                e.name = obj.has_member("name") ? obj.get_string_member("name") : "";
                e.topic = obj.has_member("topic") ? obj.get_string_member("topic") : "";
                e.payload = obj.has_member("payload") ? obj.get_string_member("payload") : "";
                e.qos = obj.has_member("qos") ? (int) obj.get_int_member("qos") : 0;
                e.retain = obj.has_member("retain") ? obj.get_boolean_member("retain") : false;
                e.use_count = obj.has_member("use_count") ? (int) obj.get_int_member("use_count") : 0;
                if (e.name != "") list.add(e);
            }
        } catch (Error e) {
            warning("MqttCommandHandler: parse presets JSON: %s", e.message);
        }
        return list;
    }

    private string build_presets_json(ArrayList<PresetEntry> presets) {
        var builder = new Json.Builder();
        builder.begin_array();
        foreach (var p in presets) {
            builder.begin_object();
            builder.set_member_name("id"); builder.add_string_value(p.id);
            builder.set_member_name("name"); builder.add_string_value(p.name);
            builder.set_member_name("topic"); builder.add_string_value(p.topic);
            builder.set_member_name("payload"); builder.add_string_value(p.payload);
            builder.set_member_name("qos"); builder.add_int_value(p.qos);
            builder.set_member_name("retain"); builder.add_boolean_value(p.retain);
            builder.set_member_name("use_count"); builder.add_int_value(p.use_count);
            builder.end_object();
        }
        builder.end_array();
        var gen = new Json.Generator();
        gen.set_root(builder.get_root());
        return gen.to_data(null);
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
