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
        string[] parts = rest.split(" ", 3);

        string subcmd = (parts.length > 0) ? parts[0].down() : "help";
        string arg1 = (parts.length > 1) ? parts[1] : "";
        string arg2 = (parts.length > 2) ? parts[2] : "";

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
               "/mqtt help                — This help text\n" +
               "\n" +
               "Topic wildcards:\n" +
               "  + = single level (home/+/temp)\n" +
               "  # = all below   (home/sensors/#)";
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
