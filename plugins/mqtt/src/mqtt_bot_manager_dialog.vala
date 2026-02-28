/*
 * MqttBotManagerDialog — Per-account MQTT Bot management dialog.
 *
 * Opened from the Account Preferences Subpage ("MQTT Bot" section).
 * The dialog shows the full MQTT configuration for a specific account:
 *
 *   - Connection settings (enable, broker, auth)
 *   - Topic subscriptions
 *   - Publish presets + Freitext
 *   - Alert rules
 *   - Bridge rules
 *   - Status / DB stats
 *
 * The same dialog is used for per-account (ejabberd/Prosody) and
 * standalone MQTT.  Context is determined by the `account` parameter.
 *
 * Copyright (C) 2026 Ralf Peter <dinox@handwerker.jetzt>
 */

using Gtk;
using Gee;
using Dino.Entities;

namespace Dino.Plugins.Mqtt {

public class MqttBotManagerDialog : Adw.Dialog {

    private Plugin plugin;
    private Account account;
    private MqttConnectionConfig config;

    /* Navigation */
    private Adw.NavigationView nav_view;

    /* Connection page widgets */
    private Adw.SwitchRow enable_switch;
    private Adw.EntryRow broker_host_entry;
    private Adw.EntryRow broker_port_entry;
    private Adw.SwitchRow tls_switch;
    private Adw.SwitchRow xmpp_auth_switch;
    private Adw.EntryRow username_entry;
    private Adw.PasswordEntryRow password_entry;
    private Adw.ActionRow server_type_row;
    private Adw.ActionRow status_row;
    private Adw.PreferencesGroup tls_warning_group;

    /* Topics page widgets */
    private Adw.PreferencesGroup topics_group;
    private Entry topic_entry;
    private DropDown qos_dropdown;

    /* Alerts page widgets */
    private Adw.PreferencesGroup alerts_group;

    /* Bridges page widgets */
    private Adw.PreferencesGroup bridges_group;

    /* Publish page widgets */
    private Adw.PreferencesGroup presets_group;
    private Adw.SwitchRow freetext_enable_switch;
    private Adw.EntryRow freetext_pub_topic_entry;
    private Adw.EntryRow freetext_resp_topic_entry;

    /* Preset add widgets */
    private Adw.EntryRow preset_name_entry;
    private Adw.EntryRow preset_topic_entry;
    private Adw.EntryRow preset_payload_entry;

    public MqttBotManagerDialog(Plugin plugin, Account account) {
        this.plugin = plugin;
        this.account = account;
        this.config = plugin.get_account_config(account).copy();
        this.title = _("MQTT Bot — %s").printf(account.bare_jid.to_string());
        this.content_width = 520;
        this.content_height = 640;

        build_ui();
        populate_from_config();
    }

    /* ── UI Construction ──────────────────────────────────────────── */

    private void build_ui() {
        nav_view = new Adw.NavigationView();
        nav_view.vexpand = true;
        nav_view.hexpand = true;

        /* Root page: overview with sections that navigate to detail pages */
        var root_page = build_root_page();
        nav_view.add(root_page);

        this.set_child(nav_view);
    }

    private Adw.NavigationPage build_root_page() {
        var toolbar_view = new Adw.ToolbarView();

        var header = new Adw.HeaderBar();
        toolbar_view.add_top_bar(header);

        var page = new Adw.PreferencesPage();

        /* ── 1. Connection Group ──────────────────────────────── */
        var conn_group = new Adw.PreferencesGroup();
        conn_group.title = _("Connection");
        conn_group.description = _("MQTT broker connection for %s").printf(
            account.bare_jid.to_string());

        enable_switch = new Adw.SwitchRow();
        enable_switch.title = _("Enable MQTT");
        enable_switch.subtitle = _("Connect to the account's MQTT broker");
        conn_group.add(enable_switch);

        server_type_row = new Adw.ActionRow();
        server_type_row.title = _("Server Type");
        server_type_row.subtitle = _("unknown");
        conn_group.add(server_type_row);

        status_row = new Adw.ActionRow();
        status_row.title = _("Status");
        status_row.subtitle = _("Disconnected");
        conn_group.add(status_row);

        page.add(conn_group);

        /* ── 2. Broker Group ──────────────────────────────────── */
        var broker_group = new Adw.PreferencesGroup();
        broker_group.title = _("Broker");
        broker_group.description = _("Leave empty to auto-detect from XMPP server");

        broker_host_entry = new Adw.EntryRow();
        broker_host_entry.title = _("Hostname");
        broker_host_entry.changed.connect(() => { check_tls_warning(); });
        broker_group.add(broker_host_entry);

        broker_port_entry = new Adw.EntryRow();
        broker_port_entry.title = _("Port");
        broker_group.add(broker_port_entry);

        tls_switch = new Adw.SwitchRow();
        tls_switch.title = _("TLS Encryption");
        tls_switch.notify["active"].connect(() => { check_tls_warning(); });
        broker_group.add(tls_switch);

        page.add(broker_group);

        /* TLS Warning — visible when non-local host + TLS off */
        tls_warning_group = new Adw.PreferencesGroup();
        var tls_warn_row = new Adw.ActionRow();
        tls_warn_row.title = _("⚠ TLS Disabled");
        tls_warn_row.subtitle = _("Credentials and data are sent in plain text to a non-local host!");
        tls_warn_row.add_css_class("error");
        var warn_icon = new Image.from_icon_name("dialog-warning-symbolic");
        warn_icon.add_css_class("error");
        tls_warn_row.add_prefix(warn_icon);
        tls_warning_group.add(tls_warn_row);
        tls_warning_group.visible = false;
        page.add(tls_warning_group);

        /* ── 3. Authentication Group ──────────────────────────── */
        var auth_group = new Adw.PreferencesGroup();
        auth_group.title = _("Authentication");

        xmpp_auth_switch = new Adw.SwitchRow();
        xmpp_auth_switch.title = _("Use XMPP Credentials");
        xmpp_auth_switch.subtitle = _("Recommended for ejabberd (shares XMPP login)");
        xmpp_auth_switch.notify["active"].connect(() => {
            update_auth_visibility();
        });
        auth_group.add(xmpp_auth_switch);

        username_entry = new Adw.EntryRow();
        username_entry.title = _("MQTT Username");
        auth_group.add(username_entry);

        password_entry = new Adw.PasswordEntryRow();
        password_entry.title = _("MQTT Password");
        auth_group.add(password_entry);

        page.add(auth_group);

        /* ── 4. Section navigation rows ───────────────────────── */
        var sections_group = new Adw.PreferencesGroup();
        sections_group.title = _("Configuration");

        var topics_nav = new Adw.ActionRow();
        topics_nav.title = _("Topic Subscriptions");
        topics_nav.subtitle = _("Manage subscribed MQTT topics");
        topics_nav.activatable = true;
        topics_nav.add_suffix(new Image.from_icon_name("go-next-symbolic"));
        topics_nav.activated.connect(() => {
            nav_view.push(build_topics_page());
        });
        sections_group.add(topics_nav);

        var publish_nav = new Adw.ActionRow();
        publish_nav.title = _("Publish & Free Text");
        publish_nav.subtitle = _("Publish presets and free-text publishing");
        publish_nav.activatable = true;
        publish_nav.add_suffix(new Image.from_icon_name("go-next-symbolic"));
        publish_nav.activated.connect(() => {
            nav_view.push(build_publish_page());
        });
        sections_group.add(publish_nav);

        var alerts_nav = new Adw.ActionRow();
        alerts_nav.title = _("Alert Rules");
        alerts_nav.subtitle = _("Notification rules for MQTT messages");
        alerts_nav.activatable = true;
        alerts_nav.add_suffix(new Image.from_icon_name("go-next-symbolic"));
        alerts_nav.activated.connect(() => {
            nav_view.push(build_alerts_page());
        });
        sections_group.add(alerts_nav);

        var bridges_nav = new Adw.ActionRow();
        bridges_nav.title = _("Bridge Rules");
        bridges_nav.subtitle = _("Forward MQTT messages to XMPP contacts");
        bridges_nav.activatable = true;
        bridges_nav.add_suffix(new Image.from_icon_name("go-next-symbolic"));
        bridges_nav.activated.connect(() => {
            nav_view.push(build_bridges_page());
        });
        sections_group.add(bridges_nav);

        page.add(sections_group);

        /* ── 4b. HA Discovery ─────────────────────────────────── */
        var disc_group = new Adw.PreferencesGroup();
        disc_group.title = _("Home Assistant Discovery");
        disc_group.description = _("Auto-announce DinoX as a device in HA.");

        var disc_enable = new Adw.SwitchRow();
        disc_enable.title = _("Enable Discovery");
        disc_enable.subtitle = _("Publish device &amp; entity configs via MQTT");
        disc_enable.active = config.discovery_enabled;
        disc_enable.notify["active"].connect(() => {
            config.discovery_enabled = disc_enable.active;
        });
        disc_group.add(disc_enable);

        var disc_prefix_row = new Adw.EntryRow();
        disc_prefix_row.title = _("Discovery Prefix");
        disc_prefix_row.text = config.discovery_prefix != "" ? config.discovery_prefix : "homeassistant";
        disc_prefix_row.changed.connect(() => {
            string val = disc_prefix_row.text.strip();
            config.discovery_prefix = val != "" ? val : "homeassistant";
        });
        disc_group.add(disc_prefix_row);

        page.add(disc_group);

        /* ── 5. Save button ───────────────────────────────────── */
        var save_group = new Adw.PreferencesGroup();
        var save_btn = new Button.with_label(_("Save & Apply"));
        save_btn.add_css_class("suggested-action");
        save_btn.add_css_class("pill");
        save_btn.halign = Align.CENTER;
        save_btn.margin_top = 12;
        save_btn.clicked.connect(on_save_clicked);
        save_group.add(save_btn);

        page.add(save_group);

        toolbar_view.set_content(page);

        var nav_page = new Adw.NavigationPage.with_tag(toolbar_view, "root", _("MQTT Bot"));
        return nav_page;
    }

    /* ── Topics Page ──────────────────────────────────────────────── */

    private Adw.NavigationPage build_topics_page() {
        var toolbar_view = new Adw.ToolbarView();
        var header = new Adw.HeaderBar();
        toolbar_view.add_top_bar(header);

        var page = new Adw.PreferencesPage();

        /* Add-topic row */
        var add_group = new Adw.PreferencesGroup();
        add_group.title = _("Subscribe to Topic");

        var add_box = new Box(Orientation.HORIZONTAL, 6);
        add_box.margin_top = 6;
        add_box.margin_bottom = 6;

        topic_entry = new Entry();
        topic_entry.placeholder_text = "home/sensors/#";
        topic_entry.hexpand = true;
        add_box.append(topic_entry);

        string[] qos_labels = { "QoS 0", "QoS 1", "QoS 2" };
        qos_dropdown = new DropDown.from_strings(qos_labels);
        qos_dropdown.selected = 0;
        add_box.append(qos_dropdown);

        var add_btn = new Button.with_label(_("Subscribe"));
        add_btn.add_css_class("suggested-action");
        add_btn.clicked.connect(on_add_topic);
        add_box.append(add_btn);

        add_group.add(add_box);
        page.add(add_group);

        /* Active subscriptions list */
        topics_group = new Adw.PreferencesGroup();
        topics_group.title = _("Active Subscriptions");
        page.add(topics_group);

        populate_topics_list();

        toolbar_view.set_content(page);
        var nav_page = new Adw.NavigationPage.with_tag(toolbar_view, "topics", _("Topics"));
        return nav_page;
    }

    /* ── Publish Page ─────────────────────────────────────────────── */

    private Adw.NavigationPage build_publish_page() {
        var toolbar_view = new Adw.ToolbarView();
        var header = new Adw.HeaderBar();
        toolbar_view.add_top_bar(header);

        var page = new Adw.PreferencesPage();

        /* Freitext-Publish configuration */
        var freetext_group = new Adw.PreferencesGroup();
        freetext_group.title = _("Free-Text Publish (Node-RED)");
        freetext_group.description = _("Type free text in the bot chat to publish directly to a topic");

        freetext_enable_switch = new Adw.SwitchRow();
        freetext_enable_switch.title = _("Enable Free-Text Publish");
        freetext_enable_switch.active = config.freetext_enabled;
        freetext_group.add(freetext_enable_switch);

        freetext_pub_topic_entry = new Adw.EntryRow();
        freetext_pub_topic_entry.title = _("Publish Topic");
        freetext_pub_topic_entry.text = config.freetext_publish_topic;
        freetext_group.add(freetext_pub_topic_entry);

        freetext_resp_topic_entry = new Adw.EntryRow();
        freetext_resp_topic_entry.title = _("Response Topic");
        freetext_resp_topic_entry.text = config.freetext_response_topic;
        freetext_group.add(freetext_resp_topic_entry);

        page.add(freetext_group);

        /* Publish Presets */
        presets_group = new Adw.PreferencesGroup();
        presets_group.title = _("Publish Presets");
        presets_group.description = _("Quick-publish actions for the MQTT bot");
        page.add(presets_group);

        populate_presets_list();

        /* Add-Preset form */
        var add_preset_group = new Adw.PreferencesGroup();
        add_preset_group.title = _("Add Preset");

        preset_name_entry = new Adw.EntryRow();
        preset_name_entry.title = _("Name");
        add_preset_group.add(preset_name_entry);

        preset_topic_entry = new Adw.EntryRow();
        preset_topic_entry.title = _("Topic");
        add_preset_group.add(preset_topic_entry);

        preset_payload_entry = new Adw.EntryRow();
        preset_payload_entry.title = _("Payload");
        add_preset_group.add(preset_payload_entry);

        var add_preset_btn = new Button.with_label(_("Add Preset"));
        add_preset_btn.add_css_class("suggested-action");
        add_preset_btn.halign = Align.END;
        add_preset_btn.margin_top = 8;
        add_preset_btn.clicked.connect(() => { on_add_preset(); });
        add_preset_group.add(add_preset_btn);

        page.add(add_preset_group);

        toolbar_view.set_content(page);
        var nav_page = new Adw.NavigationPage.with_tag(toolbar_view, "publish", _("Publish & Free Text"));
        return nav_page;
    }

    /* ── Alerts Page ──────────────────────────────────────────────── */

    private Adw.NavigationPage build_alerts_page() {
        var toolbar_view = new Adw.ToolbarView();
        var header = new Adw.HeaderBar();
        toolbar_view.add_top_bar(header);

        var page = new Adw.PreferencesPage();

        alerts_group = new Adw.PreferencesGroup();
        alerts_group.title = _("Alert Rules");
        alerts_group.description = _("Rules that trigger notifications when MQTT messages match patterns");
        page.add(alerts_group);

        populate_alerts_list();

        /* Add alert button */
        var add_group = new Adw.PreferencesGroup();
        var info_row = new Adw.ActionRow();
        info_row.title = _("Add via Chat Command");
        info_row.subtitle = _("Use /mqtt alert <topic_pattern> <keyword> [priority] in the bot chat");
        add_group.add(info_row);
        page.add(add_group);

        toolbar_view.set_content(page);
        var nav_page = new Adw.NavigationPage.with_tag(toolbar_view, "alerts", _("Alert Rules"));
        return nav_page;
    }

    /* ── Bridges Page ─────────────────────────────────────────────── */

    private Adw.NavigationPage build_bridges_page() {
        var toolbar_view = new Adw.ToolbarView();
        var header = new Adw.HeaderBar();
        toolbar_view.add_top_bar(header);

        var page = new Adw.PreferencesPage();

        bridges_group = new Adw.PreferencesGroup();
        bridges_group.title = _("Bridge Rules");
        bridges_group.description = _("Forward MQTT messages to XMPP contacts or MUCs");
        page.add(bridges_group);

        populate_bridges_list();

        /* Info */
        var info_group = new Adw.PreferencesGroup();
        var info_row = new Adw.ActionRow();
        info_row.title = _("Add via Chat Command");
        info_row.subtitle = _("Use /mqtt bridge <topic_pattern> <xmpp_jid> in the bot chat");
        info_group.add(info_row);
        page.add(info_group);

        toolbar_view.set_content(page);
        var nav_page = new Adw.NavigationPage.with_tag(toolbar_view, "bridges", _("Bridge Rules"));
        return nav_page;
    }

    /* ── Populate widgets from config ─────────────────────────────── */

    private void populate_from_config() {
        enable_switch.active = config.enabled;
        broker_host_entry.text = config.broker_host;
        broker_port_entry.text = config.broker_port.to_string();
        tls_switch.active = config.tls;
        xmpp_auth_switch.active = config.use_xmpp_auth;
        username_entry.text = config.username;
        password_entry.text = config.password;
        server_type_row.subtitle = format_server_type(config.server_type);

        update_auth_visibility();
        update_status_display();
        check_tls_warning();
    }

    private void update_auth_visibility() {
        bool manual = !xmpp_auth_switch.active;
        username_entry.sensitive = manual;
        password_entry.sensitive = manual;
        if (!manual) {
            username_entry.text = "";
            password_entry.text = "";
        }
    }

    private void update_status_display() {
        /* Check if there's an active client for this account */
        string key = account.bare_jid.to_string();
        bool connected = plugin.is_account_connected(key);
        if (connected) {
            status_row.subtitle = _("Connected");
            status_row.remove_css_class("error");
            status_row.add_css_class("success");
        } else if (config.enabled) {
            status_row.subtitle = _("Disconnected (retrying\u2026)");
            status_row.add_css_class("error");
            status_row.remove_css_class("success");
        } else {
            status_row.subtitle = _("Disabled");
            status_row.remove_css_class("error");
            status_row.remove_css_class("success");
        }
    }

    private string format_server_type(string type) {
        switch (type) {
            case "ejabberd": return _("ejabberd (mod_mqtt)");
            case "prosody":  return _("Prosody (mod_pubsub_mqtt) \u2014 read-only");
            default:         return _("Unknown / Not detected");
        }
    }

    /* ── Topic list ───────────────────────────────────────────────── */

    private void populate_topics_list() {
        /* Clear existing children */
        Widget? child = topics_group.get_first_child();
        while (child != null) {
            Widget? next = child.get_next_sibling();
            /* Only remove AdwActionRow children (keep group header) */
            if (child is Adw.ActionRow) {
                topics_group.remove(child);
            }
            child = next;
        }

        string[] topic_list = config.get_topic_list();
        if (topic_list.length == 0) {
            var empty_row = new Adw.ActionRow();
            empty_row.title = _("No topics subscribed");
            empty_row.subtitle = _("Add a topic above");
            topics_group.add(empty_row);
            return;
        }

        /* Parse QoS map */
        HashMap<string, int> qos_map = parse_qos_map(config.topic_qos_json);

        foreach (string topic in topic_list) {
            int qos = qos_map.has_key(topic) ? qos_map[topic] : 0;

            var row = new Adw.ActionRow();
            row.title = topic;
            row.subtitle = "QoS %d".printf(qos);

            var remove_btn = new Button.from_icon_name("user-trash-symbolic");
            remove_btn.valign = Align.CENTER;
            remove_btn.add_css_class("flat");
            remove_btn.add_css_class("destructive-action");
            string t = topic; /* capture for closure */
            remove_btn.clicked.connect(() => {
                remove_topic(t);
            });
            row.add_suffix(remove_btn);

            topics_group.add(row);
        }
    }

    private void on_add_topic() {
        string new_topic = topic_entry.text.strip();
        if (new_topic == "") return;

        /* Add to comma-separated list */
        string[] current = config.get_topic_list();
        /* Check for duplicates */
        foreach (string t in current) {
            if (t == new_topic) {
                topic_entry.text = "";
                return;
            }
        }

        if (config.topics.strip() == "") {
            config.topics = new_topic;
        } else {
            config.topics = config.topics + ", " + new_topic;
        }

        /* Update QoS */
        int qos = (int) qos_dropdown.selected;
        HashMap<string, int> qos_map = parse_qos_map(config.topic_qos_json);
        qos_map[new_topic] = qos;
        config.topic_qos_json = build_qos_json(qos_map);

        topic_entry.text = "";
        populate_topics_list();
    }

    private void remove_topic(string topic) {
        string[] current = config.get_topic_list();
        string[] kept = {};
        foreach (string t in current) {
            if (t != topic) kept += t;
        }
        config.topics = string.joinv(", ", kept);

        /* Remove from QoS map */
        HashMap<string, int> qos_map = parse_qos_map(config.topic_qos_json);
        qos_map.unset(topic);
        config.topic_qos_json = build_qos_json(qos_map);

        populate_topics_list();
    }

    /* ── Alerts list ──────────────────────────────────────────────── */

    private void populate_alerts_list() {
        Widget? child = alerts_group.get_first_child();
        while (child != null) {
            Widget? next = child.get_next_sibling();
            if (child is Adw.ActionRow) {
                alerts_group.remove(child);
            }
            child = next;
        }

        /* Read alert rules from alert_manager */
        if (plugin.alert_manager == null) return;

        var rules = plugin.alert_manager.get_rules();

        if (rules.size == 0) {
            var empty_row = new Adw.ActionRow();
            empty_row.title = _("No alert rules configured");
            empty_row.subtitle = _("Use /mqtt alert in the bot chat to add rules");
            alerts_group.add(empty_row);
            return;
        }

        foreach (var rule in rules) {
            var row = new Adw.ActionRow();
            row.title = "%s — \"%s\"".printf(
                rule.topic, rule.threshold);
            row.subtitle = "Priority: %s | Op: %s".printf(
                rule.priority.to_string_key(), rule.op.to_symbol());

            var remove_btn = new Button.from_icon_name("user-trash-symbolic");
            remove_btn.valign = Align.CENTER;
            remove_btn.add_css_class("flat");
            remove_btn.add_css_class("destructive-action");
            string rid = rule.id;
            remove_btn.clicked.connect(() => {
                if (plugin.alert_manager != null) {
                    plugin.alert_manager.remove_rule(rid);
                    populate_alerts_list();
                }
            });
            row.add_suffix(remove_btn);

            alerts_group.add(row);
        }
    }

    /* ── Bridges list ─────────────────────────────────────────────── */

    private void populate_bridges_list() {
        Widget? child = bridges_group.get_first_child();
        while (child != null) {
            Widget? next = child.get_next_sibling();
            if (child is Adw.ActionRow) {
                bridges_group.remove(child);
            }
            child = next;
        }

        if (plugin.bridge_manager == null) return;

        var rules = plugin.bridge_manager.get_rules();

        if (rules.size == 0) {
            var empty_row = new Adw.ActionRow();
            empty_row.title = _("No bridge rules configured");
            empty_row.subtitle = _("Use /mqtt bridge in the bot chat to add rules");
            bridges_group.add(empty_row);
            return;
        }

        foreach (var rule in rules) {
            var row = new Adw.ActionRow();
            row.title = "%s → %s".printf(rule.topic, rule.target_jid);
            row.subtitle = "Format: %s".printf(rule.format ?? "full");

            var remove_btn = new Button.from_icon_name("user-trash-symbolic");
            remove_btn.valign = Align.CENTER;
            remove_btn.add_css_class("flat");
            remove_btn.add_css_class("destructive-action");
            string rid = rule.id;
            remove_btn.clicked.connect(() => {
                if (plugin.bridge_manager != null) {
                    plugin.bridge_manager.remove_rule(rid);
                    populate_bridges_list();
                }
            });
            row.add_suffix(remove_btn);

            bridges_group.add(row);
        }
    }

    /* ── Presets list ─────────────────────────────────────────────── */

    private void populate_presets_list() {
        /* Clear existing rows */
        Widget? child = presets_group.get_first_child();
        while (child != null) {
            Widget? next = child.get_next_sibling();
            if (child is Adw.ActionRow) {
                presets_group.remove(child);
            }
            child = next;
        }

        /* Parse publish presets from config JSON */
        try {
            var parser = new Json.Parser();
            parser.load_from_data(config.publish_presets_json, -1);
            var root = parser.get_root();
            if (root == null || root.get_node_type() != Json.NodeType.ARRAY) {
                add_empty_presets_row();
                return;
            }
            var arr = root.get_array();
            if (arr.get_length() == 0) {
                add_empty_presets_row();
                return;
            }
            for (uint i = 0; i < arr.get_length(); i++) {
                var obj = arr.get_object_element(i);
                string name = obj.has_member("name") ? obj.get_string_member("name") : "Unnamed";
                string topic = obj.has_member("topic") ? obj.get_string_member("topic") : "";
                string payload = obj.has_member("payload") ? obj.get_string_member("payload") : "";

                var row = new Adw.ActionRow();
                row.title = name;
                row.subtitle = "%s → %s".printf(topic,
                    payload.length > 40 ? payload.substring(0, 40) + "…" : payload);

                /* Delete button */
                uint idx = i;
                var del_btn = new Button.from_icon_name("user-trash-symbolic");
                del_btn.valign = Align.CENTER;
                del_btn.add_css_class("flat");
                del_btn.add_css_class("destructive-action");
                del_btn.tooltip_text = _("Remove this preset");
                del_btn.clicked.connect(() => { on_remove_preset(idx); });
                row.add_suffix(del_btn);

                presets_group.add(row);
            }
        } catch (Error e) {
            add_empty_presets_row();
        }
    }

    private void add_empty_presets_row() {
        var row = new Adw.ActionRow();
        row.title = _("No publish presets");
        row.subtitle = _("Use the form below to add a preset");
        presets_group.add(row);
    }

    /**
     * Add a new preset from the entry fields.
     */
    private void on_add_preset() {
        string name = preset_name_entry.text.strip();
        string topic = preset_topic_entry.text.strip();
        string payload = preset_payload_entry.text.strip();

        if (name == "" || topic == "") {
            /* Need at least name and topic */
            return;
        }

        /* Parse existing JSON, append new entry */
        var arr = new Json.Array();
        try {
            var parser = new Json.Parser();
            parser.load_from_data(config.publish_presets_json, -1);
            var root = parser.get_root();
            if (root != null && root.get_node_type() == Json.NodeType.ARRAY) {
                arr = root.get_array();
            }
        } catch (Error e) {
            /* Start fresh */
        }

        var obj = new Json.Object();
        obj.set_string_member("id", GLib.Uuid.string_random());
        obj.set_string_member("name", name);
        obj.set_string_member("topic", topic);
        obj.set_string_member("payload", payload);
        obj.set_int_member("qos", 0);
        obj.set_boolean_member("retain", false);
        obj.set_int_member("use_count", 0);

        var node = new Json.Node(Json.NodeType.OBJECT);
        node.set_object(obj);
        arr.add_element(node);

        /* Serialize back */
        config.publish_presets_json = serialize_json_array(arr);

        /* Clear entry fields */
        preset_name_entry.text = "";
        preset_topic_entry.text = "";
        preset_payload_entry.text = "";

        /* Refresh list */
        populate_presets_list();
    }

    /**
     * Remove a preset by index.
     */
    private void on_remove_preset(uint index) {
        try {
            var parser = new Json.Parser();
            parser.load_from_data(config.publish_presets_json, -1);
            var root = parser.get_root();
            if (root == null || root.get_node_type() != Json.NodeType.ARRAY) return;

            var arr = root.get_array();
            if (index >= arr.get_length()) return;

            arr.remove_element(index);
            config.publish_presets_json = serialize_json_array(arr);
            populate_presets_list();
        } catch (Error e) {
            warning("MqttBotManagerDialog: remove preset: %s", e.message);
        }
    }

    /**
     * Serialize a Json.Array to a compact JSON string.
     */
    private string serialize_json_array(Json.Array arr) {
        var root_node = new Json.Node(Json.NodeType.ARRAY);
        root_node.set_array(arr);
        var gen = new Json.Generator();
        gen.set_root(root_node);
        return gen.to_data(null);
    }

    /* ── Save ─────────────────────────────────────────────────────── */

    private void on_save_clicked() {
        /* Read values from widgets back to config */
        config.enabled = enable_switch.active;
        config.broker_host = broker_host_entry.text.strip();
        string port_text = broker_port_entry.text.strip();
        config.broker_port = port_text != "" ? int.parse(port_text) : 1883;
        config.tls = tls_switch.active;
        config.use_xmpp_auth = xmpp_auth_switch.active;
        if (!config.use_xmpp_auth) {
            config.username = username_entry.text.strip();
            config.password = password_entry.text;
        } else {
            config.username = "";
            config.password = "";
        }

        /* Freitext settings (if publish page was visited) */
        if (freetext_enable_switch != null) {
            config.freetext_enabled = freetext_enable_switch.active;
            config.freetext_publish_topic = freetext_pub_topic_entry.text.strip();
            config.freetext_response_topic = freetext_resp_topic_entry.text.strip();
        }

        /* Discovery fields are already synced from widget callbacks */

        /* Persist to DB */
        plugin.save_account_config(account, config);

        /* Notify plugin to apply changes (connect/reconnect/disconnect) */
        plugin.apply_account_config_change(account, config);

        message("MQTT Bot Manager: Saved config for %s (enabled=%s)",
                account.bare_jid.to_string(), config.enabled.to_string());

        /* Close dialog */
        this.close();
    }

    /* ── TLS / Prosody warnings ─────────────────────────────────── */

    /**
     * Show/hide TLS warning when host is non-local and TLS is off.
     */
    private void check_tls_warning() {
        string host = broker_host_entry.text.strip();
        bool tls = tls_switch.active;
        tls_warning_group.visible = (host != "" && !tls && !MqttUtils.is_local_host(host));
    }

    /* ── JSON helpers ─────────────────────────────────────────────── */

    private HashMap<string, int> parse_qos_map(string json) {
        var map = new HashMap<string, int>();
        try {
            var parser = new Json.Parser();
            parser.load_from_data(json, -1);
            var root = parser.get_root();
            if (root != null && root.get_node_type() == Json.NodeType.OBJECT) {
                var obj = root.get_object();
                foreach (string member in obj.get_members()) {
                    map[member] = (int) obj.get_int_member(member);
                }
            }
        } catch (Error e) {
            warning("MqttBotManagerDialog: parse QoS JSON: %s", e.message);
        }
        return map;
    }

    private string build_qos_json(HashMap<string, int> map) {
        var builder = new Json.Builder();
        builder.begin_object();
        foreach (var entry in map.entries) {
            builder.set_member_name(entry.key);
            builder.add_int_value(entry.value);
        }
        builder.end_object();
        var gen = new Json.Generator();
        gen.set_root(builder.get_root());
        return gen.to_data(null);
    }
}

}
