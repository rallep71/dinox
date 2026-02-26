/*
 * MqttTopicManagerDialog — Visual topic manager for the MQTT Bot.
 *
 * An Adw.Dialog that allows the user to manage MQTT topic subscriptions,
 * QoS levels, priorities, and bridge rules without typing chat commands.
 *
 * Opened via the /mqtt manager command or from the MQTT settings page.
 *
 * Copyright (C) 2026 Ralf Peter <dinox@handwerker.jetzt>
 */

using Gtk;
using Gee;
using Dino.Entities;

namespace Dino.Plugins.Mqtt {

public class MqttTopicManagerDialog : Adw.Dialog {

    private Plugin plugin;

    /* Widgets */
    private Adw.PreferencesPage main_page;
    private Adw.PreferencesGroup topics_group;
    private Adw.PreferencesGroup bridges_group;
    private Adw.PreferencesGroup alerts_group;

    /* Topic entry */
    private Entry topic_entry;
    private DropDown qos_dropdown;

    /* Bridge entry */
    private Entry bridge_topic_entry;
    private Entry bridge_jid_entry;

    public MqttTopicManagerDialog(Plugin plugin) {
        this.plugin = plugin;
        this.title = "MQTT Topic Manager";
        this.content_width = 480;
        this.content_height = 600;

        build_ui();
        populate();
    }

    private void build_ui() {
        var toolbar_view = new Adw.ToolbarView();

        /* Header bar */
        var header = new Adw.HeaderBar();
        toolbar_view.add_top_bar(header);

        /* Main preferences page inside a scrolled window */
        main_page = new Adw.PreferencesPage();

        /* ── Topic Subscriptions Group ─────────────────────────── */
        topics_group = new Adw.PreferencesGroup();
        topics_group.title = "Topic Subscriptions";
        topics_group.description = "Active MQTT topic subscriptions with QoS level";

        /* Add-topic row */
        var add_topic_box = new Box(Orientation.HORIZONTAL, 6);
        add_topic_box.margin_top = 6;
        add_topic_box.margin_bottom = 6;

        topic_entry = new Entry();
        topic_entry.placeholder_text = "home/sensors/#";
        topic_entry.hexpand = true;
        add_topic_box.append(topic_entry);

        /* QoS dropdown */
        string[] qos_labels = { "QoS 0", "QoS 1", "QoS 2" };
        qos_dropdown = new DropDown.from_strings(qos_labels);
        qos_dropdown.selected = 0;
        add_topic_box.append(qos_dropdown);

        var add_btn = new Button.with_label("Subscribe");
        add_btn.add_css_class("suggested-action");
        add_btn.clicked.connect(on_subscribe_clicked);
        add_topic_box.append(add_btn);

        topics_group.add(add_topic_box);
        main_page.add(topics_group);

        /* ── Bridge Rules Group ────────────────────────────────── */
        bridges_group = new Adw.PreferencesGroup();
        bridges_group.title = "MQTT → XMPP Bridge";
        bridges_group.description = "Forward MQTT messages to XMPP contacts";

        var add_bridge_box = new Box(Orientation.HORIZONTAL, 6);
        add_bridge_box.margin_top = 6;
        add_bridge_box.margin_bottom = 6;

        bridge_topic_entry = new Entry();
        bridge_topic_entry.placeholder_text = "home/alerts/#";
        bridge_topic_entry.hexpand = true;
        add_bridge_box.append(bridge_topic_entry);

        bridge_jid_entry = new Entry();
        bridge_jid_entry.placeholder_text = "user@example.com";
        bridge_jid_entry.hexpand = true;
        add_bridge_box.append(bridge_jid_entry);

        var add_bridge_btn = new Button.with_label("Bridge");
        add_bridge_btn.add_css_class("suggested-action");
        add_bridge_btn.clicked.connect(on_bridge_clicked);
        add_bridge_box.append(add_bridge_btn);

        bridges_group.add(add_bridge_box);
        main_page.add(bridges_group);

        /* ── Alerts Group ──────────────────────────────────────── */
        alerts_group = new Adw.PreferencesGroup();
        alerts_group.title = "Alert Rules";
        alerts_group.description = "Threshold alerts for MQTT topics";
        main_page.add(alerts_group);

        toolbar_view.content = main_page;
        this.child = toolbar_view;
    }

    private void populate() {
        /* Clear existing dynamic rows */
        populate_topics();
        populate_bridges();
        populate_alerts();
    }

    /* ── Topic Display ───────────────────────────────────────────── */

    private void populate_topics() {
        string? topics_str = get_db_setting(Plugin.KEY_TOPICS);
        if (topics_str == null || topics_str.strip() == "") return;

        string[] topics = topics_str.split(",");

        MqttAlertManager? am = plugin.get_alert_manager();

        foreach (string t in topics) {
            string topic = t.strip();
            if (topic == "") continue;

            int qos = (am != null) ? am.get_topic_qos(topic) : 0;
            MqttPriority prio = (am != null) ?
                am.get_topic_priority(topic) : MqttPriority.NORMAL;

            var row = new Adw.ActionRow();
            row.title = topic;
            row.subtitle = "QoS %d · %s".printf(qos, prio.to_string_key());

            /* Unsubscribe button */
            var unsub_btn = new Button.from_icon_name("list-remove-symbolic");
            unsub_btn.valign = Align.CENTER;
            unsub_btn.add_css_class("flat");
            unsub_btn.tooltip_text = "Unsubscribe";
            string topic_copy = topic;
            unsub_btn.clicked.connect(() => {
                remove_topic(topic_copy);
            });
            row.add_suffix(unsub_btn);

            topics_group.add(row);
        }
    }

    private void populate_bridges() {
        MqttBridgeManager? bm = plugin.get_bridge_manager();
        if (bm == null) return;

        var rules = bm.get_rules();
        int idx = 1;
        foreach (var rule in rules) {
            var row = new Adw.ActionRow();
            row.title = "%s → %s".printf(rule.topic, rule.target_jid);
            row.subtitle = rule.enabled ? "Active" : "Disabled";

            var remove_btn = new Button.from_icon_name("list-remove-symbolic");
            remove_btn.valign = Align.CENTER;
            remove_btn.add_css_class("flat");
            remove_btn.tooltip_text = "Remove bridge";
            int rule_idx = idx;
            remove_btn.clicked.connect(() => {
                if (bm.remove_rule_by_index(rule_idx)) {
                    topics_group.remove(row);  /* remove from UI */
                }
            });
            row.add_suffix(remove_btn);

            bridges_group.add(row);
            idx++;
        }
    }

    private void populate_alerts() {
        MqttAlertManager? am = plugin.get_alert_manager();
        if (am == null) return;

        var rules = am.get_rules();
        int idx = 1;
        foreach (var rule in rules) {
            string field_str = (rule.field != null && rule.field != "")
                ? ".%s".printf(rule.field) : "";

            var row = new Adw.ActionRow();
            row.title = "%s%s %s %s".printf(
                rule.topic, field_str,
                rule.op.to_symbol(), rule.threshold);
            row.subtitle = "%s · %s".printf(
                rule.enabled ? "Active" : "Disabled",
                rule.priority.to_string_key());

            var toggle = new Switch();
            toggle.valign = Align.CENTER;
            toggle.active = rule.enabled;
            int rule_idx = idx;
            toggle.notify["active"].connect(() => {
                am.toggle_rule(rule_idx);
            });
            row.add_suffix(toggle);

            var remove_btn = new Button.from_icon_name("list-remove-symbolic");
            remove_btn.valign = Align.CENTER;
            remove_btn.add_css_class("flat");
            remove_btn.tooltip_text = "Remove alert";
            remove_btn.clicked.connect(() => {
                if (am.remove_rule_by_index(rule_idx)) {
                    alerts_group.remove(row);
                }
            });
            row.add_suffix(remove_btn);

            alerts_group.add(row);
            idx++;
        }
    }

    /* ── Button Handlers ─────────────────────────────────────────── */

    private void on_subscribe_clicked() {
        string topic = topic_entry.text.strip();
        if (topic == "") return;

        int qos = (int) qos_dropdown.selected;

        /* Subscribe */
        plugin.subscribe(topic, qos);

        /* Persist */
        string? existing = get_db_setting(Plugin.KEY_TOPICS);
        string new_topics;
        if (existing != null && existing != "") {
            /* Check duplicate */
            foreach (string p in existing.split(",")) {
                if (p.strip() == topic) return;  /* already subscribed */
            }
            new_topics = existing + "," + topic;
        } else {
            new_topics = topic;
        }
        set_db_setting(Plugin.KEY_TOPICS, new_topics);

        /* Set QoS if not default */
        if (qos > 0) {
            MqttAlertManager? am = plugin.get_alert_manager();
            if (am != null) am.set_topic_qos(topic, qos);
        }

        /* Add row to UI */
        var row = new Adw.ActionRow();
        row.title = topic;
        row.subtitle = "QoS %d · normal".printf(qos);

        var unsub_btn = new Button.from_icon_name("list-remove-symbolic");
        unsub_btn.valign = Align.CENTER;
        unsub_btn.add_css_class("flat");
        string topic_copy = topic;
        unsub_btn.clicked.connect(() => { remove_topic(topic_copy); });
        row.add_suffix(unsub_btn);

        topics_group.add(row);

        /* Clear entry */
        topic_entry.text = "";
    }

    private void on_bridge_clicked() {
        string topic = bridge_topic_entry.text.strip();
        string jid = bridge_jid_entry.text.strip();
        if (topic == "" || jid == "") return;

        MqttBridgeManager? bm = plugin.get_bridge_manager();
        if (bm == null) return;

        var rule = new BridgeRule();
        rule.topic = topic;
        rule.target_jid = jid;
        bm.add_rule(rule);

        /* Add row */
        var row = new Adw.ActionRow();
        row.title = "%s → %s".printf(topic, jid);
        row.subtitle = "Active";
        bridges_group.add(row);

        bridge_topic_entry.text = "";
        bridge_jid_entry.text = "";
    }

    private void remove_topic(string topic) {
        /* Unsubscribe */
        MqttClient? standalone = plugin.get_standalone_client();
        if (standalone != null && standalone.is_connected) {
            standalone.unsubscribe(topic);
        }

        /* Remove from DB */
        string? existing = get_db_setting(Plugin.KEY_TOPICS);
        if (existing != null && existing != "") {
            string[] parts = existing.split(",");
            var remaining = new ArrayList<string>();
            foreach (string p in parts) {
                if (p.strip() != topic) {
                    remaining.add(p.strip());
                }
            }
            set_db_setting(Plugin.KEY_TOPICS, string.joinv(",", remaining.to_array()));
        }

        /* Refresh display */
        this.close();
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
