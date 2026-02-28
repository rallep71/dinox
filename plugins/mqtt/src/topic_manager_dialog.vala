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
    private string? connection_key;  /* null = standalone, else account bare JID */

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

    public MqttTopicManagerDialog(Plugin plugin, string? connection_key = null) {
        this.plugin = plugin;
        this.connection_key = connection_key;
        this.title = connection_key != null
            ? _("MQTT Topics \u2014 %s").printf(connection_key)
            : _("MQTT Topic Manager");
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
        topics_group.title = _("Topic Subscriptions");
        topics_group.description = _("Active MQTT topic subscriptions with QoS level");

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

        var add_btn = new Button.with_label(_("Subscribe"));
        add_btn.add_css_class("suggested-action");
        add_btn.clicked.connect(on_subscribe_clicked);
        add_topic_box.append(add_btn);

        topics_group.add(add_topic_box);
        main_page.add(topics_group);

        /* ── Bridge Rules Group ────────────────────────────────── */
        bridges_group = new Adw.PreferencesGroup();
        bridges_group.title = _("MQTT → XMPP Bridge");
        bridges_group.description = _("Forward MQTT messages to XMPP contacts");

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

        var add_bridge_btn = new Button.with_label(_("Bridge"));
        add_bridge_btn.add_css_class("suggested-action");
        add_bridge_btn.clicked.connect(on_bridge_clicked);
        add_bridge_box.append(add_bridge_btn);

        bridges_group.add(add_bridge_box);
        main_page.add(bridges_group);

        /* ── Alerts Group ──────────────────────────────────────── */
        alerts_group = new Adw.PreferencesGroup();
        alerts_group.title = _("Alert Rules");
        alerts_group.description = _("Threshold alerts for MQTT topics");
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

    /**
     * Get topics string for the current connection context.
     */
    private string? get_topics_string() {
        if (connection_key != null) {
            /* Per-account: look up account by bare JID */
            var accounts = plugin.app.stream_interactor.get_accounts();
            foreach (var acc in accounts) {
                if (acc.bare_jid.to_string() == connection_key) {
                    var cfg = plugin.get_account_config(acc);
                    return cfg.topics;
                }
            }
            return null;
        }
        /* Standalone: read from standalone config */
        return plugin.get_standalone_config().topics;
    }

    /**
     * Save topics string for the current connection context.
     */
    private void save_topics_string(string topics) {
        if (connection_key != null) {
            var accounts = plugin.app.stream_interactor.get_accounts();
            foreach (var acc in accounts) {
                if (acc.bare_jid.to_string() == connection_key) {
                    var cfg = plugin.get_account_config(acc);
                    cfg.topics = topics;
                    plugin.save_account_config(acc, cfg);
                    return;
                }
            }
        } else {
            /* Standalone: save to standalone config */
            var sa_cfg = plugin.get_standalone_config();
            sa_cfg.topics = topics;
            plugin.save_standalone_config();
        }
    }

    private void populate_topics() {
        string? topics_str = get_topics_string();
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
            unsub_btn.tooltip_text = _("Unsubscribe");
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
            row.subtitle = rule.enabled ? _("Active") : _("Disabled");

            var remove_btn = new Button.from_icon_name("list-remove-symbolic");
            remove_btn.valign = Align.CENTER;
            remove_btn.add_css_class("flat");
            remove_btn.tooltip_text = _("Remove bridge");
            int rule_idx = idx;
            remove_btn.clicked.connect(() => {
                if (bm.remove_rule_by_index(rule_idx)) {
                    bridges_group.remove(row);  /* remove from UI */
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
                rule.enabled ? _("Active") : _("Disabled"),
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
            remove_btn.tooltip_text = _("Remove alert");
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
        plugin.subscribe(topic, qos, connection_key);

        /* Persist */
        string? existing = get_topics_string();
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
        save_topics_string(new_topics);

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
        /* Unsubscribe on the relevant connection */
        plugin.unsubscribe(topic, connection_key);

        /* Remove from persistent topic list */
        string? existing = get_topics_string();
        if (existing != null && existing != "") {
            string[] parts = existing.split(",");
            var remaining = new ArrayList<string>();
            foreach (string p in parts) {
                if (p.strip() != topic) {
                    remaining.add(p.strip());
                }
            }
            save_topics_string(string.joinv(",", remaining.to_array()));
        }

        /* Rebuild topic list UI instead of closing the dialog */
        rebuild_topics_ui();
    }

    /**
     * Clear and re-populate the topics group.
     */
    private void rebuild_topics_ui() {
        /* Remove all dynamic rows (keep the first child = add-topic box) */
        Widget? child = topics_group.get_first_child();
        var to_remove = new ArrayList<Widget>();
        bool first = true;
        while (child != null) {
            if (!first) {
                to_remove.add(child);
            }
            first = false;
            child = child.get_next_sibling();
        }
        foreach (var w in to_remove) {
            topics_group.remove(w);
        }
        populate_topics();
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
