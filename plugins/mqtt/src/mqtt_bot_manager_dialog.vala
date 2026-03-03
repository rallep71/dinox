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
    private Account? account;
    private MqttConnectionConfig config;
    private bool is_standalone;

    /**
     * Return the MQTT client label for the context this dialog manages.
     * "standalone" for the general broker, or the account bare JID.
     */
    private string get_client_label() {
        if (is_standalone) return "standalone";
        return account.bare_jid.to_string();
    }

    /* Signal handler ID for live status updates */
    private ulong connection_changed_handler_id = 0;

    /* Tracked Idle.add source for deferred sensitivity update (§9) */
    private uint sensitivity_idle_id = 0;

    /* Per-account mode groups (for show/hide by mode selector) */
    private Adw.ComboRow mode_selector;
    private Adw.PreferencesGroup xmpp_server_group;   /* Server Type (XMPP mode) */
    private Adw.PreferencesGroup broker_group;         /* Hostname/Port/TLS (Custom mode) */
    private Adw.PreferencesGroup auth_group;           /* Auth fields */
    private Adw.PreferencesGroup disc_group;           /* HA Discovery (hidden in XMPP mode) */

    /* Navigation */
    private Adw.NavigationView nav_view;
    private Adw.ToastOverlay toast_overlay;

    /* Connection page widgets */
    private Adw.SwitchRow enable_switch;
    private Adw.EntryRow broker_host_entry;
    private Adw.EntryRow broker_port_entry;
    private Adw.SwitchRow tls_switch;
    private Adw.SwitchRow xmpp_auth_switch;
    private Adw.EntryRow xmpp_port_entry;
    private Adw.SwitchRow xmpp_tls_switch;
    private Adw.EntryRow username_entry;
    private Adw.PasswordEntryRow password_entry;
    private Adw.ActionRow server_type_row;
    private Adw.ActionRow status_row;
    private Adw.PreferencesGroup tls_warning_group;

    /* Topics page widgets */
    private Adw.PreferencesGroup topics_group;
    private Gee.ArrayList<Gtk.Widget> topic_rows = new Gee.ArrayList<Gtk.Widget>();
    private Entry topic_entry;
    private Entry topic_alias_entry;
    private DropDown qos_dropdown;
    private Button topic_add_btn;
    private string? editing_topic = null;  /* topic being edited, or null */

    /* Alerts page widgets */
    private Adw.PreferencesGroup alerts_group;
    private Gee.ArrayList<Gtk.Widget> alert_rows = new Gee.ArrayList<Gtk.Widget>();
    private Adw.EntryRow alert_topic_entry;
    private Adw.EntryRow alert_threshold_entry;
    private Adw.EntryRow alert_field_entry;
    private DropDown alert_op_dropdown;
    private DropDown alert_priority_dropdown;

    /* Bridges page widgets */
    private Adw.PreferencesGroup bridges_group;
    private Gee.ArrayList<Gtk.Widget> bridge_rows = new Gee.ArrayList<Gtk.Widget>();
    private Adw.EntryRow bridge_topic_entry;
    private Adw.EntryRow bridge_jid_entry;
    private Adw.EntryRow bridge_alias_entry;
    private DropDown bridge_format_dropdown;
    private DropDown bridge_account_dropdown;
    private Gtk.StringList bridge_account_model;
    private Button bridge_add_btn;

    /* Publish page widgets */
    private Adw.PreferencesGroup presets_group;
    private Gee.ArrayList<Gtk.Widget> preset_rows = new Gee.ArrayList<Gtk.Widget>();
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
        this.is_standalone = false;
        this.config = plugin.get_account_config(account).copy();
        this.title = _("MQTT Bot — %s").printf(account.bare_jid.to_string());
        this.content_width = 520;
        this.content_height = 640;

        build_ui();
        populate_from_config();
        connect_live_signals();
    }

    /**
     * Standalone constructor — manages the standalone MQTT connection.
     */
    public MqttBotManagerDialog.standalone(Plugin plugin) {
        this.plugin = plugin;
        this.account = null;
        this.is_standalone = true;
        this.config = plugin.get_standalone_config().copy();
        this.title = _("MQTT Bot — Standalone");
        this.content_width = 520;
        this.content_height = 640;

        build_ui();
        populate_from_config();
        connect_live_signals();
    }

    ~MqttBotManagerDialog() {
        /* Safety net: ensure signal handler is cleaned up even if
         * the dialog is destroyed without the closed signal firing
         * (e.g. app quit while dialog is open). */
        if (connection_changed_handler_id != 0) {
            plugin.disconnect(connection_changed_handler_id);
            connection_changed_handler_id = 0;
        }
        /* Cancel pending Idle.add for sensitivity update (§9) */
        if (sensitivity_idle_id != 0) {
            Source.remove(sensitivity_idle_id);
            sensitivity_idle_id = 0;
        }
    }

    /* ── Live signal subscription ─────────────────────────────────── */

    private void connect_live_signals() {
        /* Subscribe to connection_changed so status updates in real-time */
        connection_changed_handler_id = plugin.connection_changed.connect(
            (source, connected) => {
                /* Only react to our own connection label */
                if (source != get_client_label()) return;
                update_status_display();
                /* Connection established → refresh server type (detection
                 * may have completed in the background). */
                if (connected) {
                    refresh_server_type();
                }
            });

        /* Disconnect handler when dialog is closed */
        this.closed.connect(() => {
            /* Clear focus entirely via the root window.  grab_focus()
             * on nav_view re-delegates focus to a child entry, causing
             * "Broken accounting of active state" and "did not receive
             * a focus-out event" GTK warnings.  set_focus(null) clears
             * focus completely before widgets are destroyed. */
            var root = this.get_root() as Gtk.Root;
            if (root != null) root.set_focus(null);

            if (connection_changed_handler_id != 0) {
                plugin.disconnect(connection_changed_handler_id);
                connection_changed_handler_id = 0;
            }
        });
    }

    /**
     * Re-read server_type from the persisted config and update the row.
     */
    private void refresh_server_type() {
        if (server_type_row == null) return;
        /* Re-read from DB to get the latest detection result */
        MqttConnectionConfig fresh;
        if (is_standalone) {
            fresh = plugin.get_standalone_config();
        } else {
            fresh = plugin.get_account_config(account);
        }
        config.server_type = fresh.server_type;
        server_type_row.subtitle = format_server_type(config.server_type);
    }

    /* ── UI Construction ──────────────────────────────────────────── */

    private void build_ui() {
        nav_view = new Adw.NavigationView();
        nav_view.vexpand = true;
        nav_view.hexpand = true;

        /* Root page: overview with sections that navigate to detail pages */
        var root_page = build_root_page();
        nav_view.add(root_page);

        toast_overlay = new Adw.ToastOverlay();
        toast_overlay.child = nav_view;
        this.set_child(toast_overlay);
    }

    private Adw.NavigationPage build_root_page() {
        var toolbar_view = new Adw.ToolbarView();

        var header = new Adw.HeaderBar();
        toolbar_view.add_top_bar(header);

        var page = new Adw.PreferencesPage();

        if (!is_standalone) {
            /* ── 1. Connection Group (per-account only) ───────────── */
            var conn_group = new Adw.PreferencesGroup();
            conn_group.title = _("Connection");
            conn_group.description = _("MQTT connection for %s").printf(
                account.bare_jid.to_string());

            enable_switch = new Adw.SwitchRow();
            enable_switch.title = _("Enable MQTT");
            enable_switch.subtitle = _("Activate the MQTT client for this account");
            /* Immediate visual feedback when toggling — update widget
             * sensitivity so the user sees the change right away,
             * not only after pressing Save & Apply.
             *
             * Deferred to Idle.add() so the sensitivity change doesn't
             * block the Switch animation frame — setting .sensitive on
             * 5+ widget groups triggers CSS restyling + relayout which
             * causes visible stutter if done synchronously in
             * notify["active"]. */
            enable_switch.notify["active"].connect(() => {
                if (sensitivity_idle_id != 0) {
                    Source.remove(sensitivity_idle_id);
                    sensitivity_idle_id = 0;
                }
                sensitivity_idle_id = Idle.add(() => {
                    sensitivity_idle_id = 0;
                    update_connection_sensitivity();
                    return Source.REMOVE;
                });
            });
            conn_group.add(enable_switch);

            /* Mode selector: XMPP Server vs Custom Broker */
            mode_selector = new Adw.ComboRow();
            mode_selector.title = _("Connection Mode");
            mode_selector.subtitle = _("How this account connects to MQTT");
            var mode_model = new Gtk.StringList(null);
            mode_model.append(_("XMPP Server (ejabberd / Prosody)"));
            mode_model.append(_("Custom Broker (any MQTT server)"));
            mode_selector.model = mode_model;
            mode_selector.notify["selected"].connect(() => {
                update_mode_visibility();
            });
            conn_group.add(mode_selector);

            status_row = new Adw.ActionRow();
            status_row.title = _("Status");
            status_row.subtitle = _("Disconnected");
            conn_group.add(status_row);

            page.add(conn_group);

            /* ── 2a. XMPP Server Group (visible in XMPP mode) ────── */
            xmpp_server_group = new Adw.PreferencesGroup();
            xmpp_server_group.title = _("XMPP Server MQTT");
            xmpp_server_group.description = _("Uses your XMPP server's built-in MQTT.\nNote: ejabberd/Prosody MQTT is still in testing.");

            server_type_row = new Adw.ActionRow();
            server_type_row.title = _("Detected Server");
            server_type_row.subtitle = _("unknown");
            xmpp_server_group.add(server_type_row);

            var xmpp_hint = new Adw.ActionRow();
            xmpp_hint.title = _("Broker");
            xmpp_hint.subtitle = _("Auto-detected from account domain (%s)").printf(
                account.bare_jid.domain_jid.to_string());
            xmpp_server_group.add(xmpp_hint);

            xmpp_auth_switch = new Adw.SwitchRow();
            xmpp_auth_switch.title = _("Use XMPP Credentials");
            xmpp_auth_switch.subtitle = _("Share your XMPP login with ejabberd's MQTT (recommended)");
            xmpp_server_group.add(xmpp_auth_switch);

            xmpp_port_entry = new Adw.EntryRow();
            xmpp_port_entry.title = _("MQTT Port");
            xmpp_port_entry.text = "8883";
            xmpp_port_entry.input_purpose = Gtk.InputPurpose.DIGITS;
            xmpp_server_group.add(xmpp_port_entry);

            xmpp_tls_switch = new Adw.SwitchRow();
            xmpp_tls_switch.title = _("TLS Encryption");
            xmpp_tls_switch.subtitle = _("ejabberd mod_mqtt usually runs on port 8883 with TLS");
            xmpp_tls_switch.active = true;
            xmpp_server_group.add(xmpp_tls_switch);

            page.add(xmpp_server_group);

            /* ── 2b. Custom Broker Group (visible in Custom mode) ─── */
            broker_group = new Adw.PreferencesGroup();
            broker_group.title = _("Custom Broker");
            broker_group.description = _("Connect to any MQTT broker with own credentials.");

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
            tls_warn_row.title = _("TLS Disabled");
            tls_warn_row.subtitle = _("Credentials and data are sent in plain text to a non-local host!");
            tls_warn_row.add_css_class("error");
            var warn_icon = new Image.from_icon_name("dialog-warning-symbolic");
            warn_icon.add_css_class("error");
            tls_warn_row.add_prefix(warn_icon);
            tls_warning_group.add(tls_warn_row);
            tls_warning_group.visible = false;
            page.add(tls_warning_group);

            /* ── 3. Authentication (Custom mode only) ─────────────── */
            auth_group = new Adw.PreferencesGroup();
            auth_group.title = _("Authentication");
            auth_group.description = _("Credentials for the custom MQTT broker.");

            username_entry = new Adw.EntryRow();
            username_entry.title = _("MQTT Username");
            auth_group.add(username_entry);

            password_entry = new Adw.PasswordEntryRow();
            password_entry.title = _("MQTT Password");
            auth_group.add(password_entry);

            page.add(auth_group);

            /* ── Show Bot button (per-account) ────────────────────── */
            var bot_btn_group = new Adw.PreferencesGroup();
            var show_bot_btn = new Button.with_label(_("Show Bot in Chat"));
            show_bot_btn.add_css_class("flat");
            show_bot_btn.add_css_class("pill");
            show_bot_btn.halign = Align.CENTER;
            show_bot_btn.tooltip_text = _("Re-open the MQTT Bot conversation in the sidebar");
            show_bot_btn.clicked.connect(() => {
                if (plugin.bot_conversation != null && account != null) {
                    var conv = plugin.bot_conversation.reopen_conversation(account);
                    if (conv != null) {
                        message("MQTT Bot Manager: Bot conversation re-opened for %s",
                                account.bare_jid.to_string());
                    }
                }
            });
            bot_btn_group.add(show_bot_btn);

            /* Reconnect button (per-account) */
            var reconnect_btn_pa = new Button.with_label(_("Reconnect"));
            reconnect_btn_pa.add_css_class("flat");
            reconnect_btn_pa.add_css_class("pill");
            reconnect_btn_pa.halign = Align.CENTER;
            reconnect_btn_pa.tooltip_text = _("Disconnect and reconnect to the MQTT broker");
            reconnect_btn_pa.clicked.connect(() => {
                if (account != null) {
                    status_row.subtitle = _("Reconnecting\u2026");
                    status_row.remove_css_class("success");
                    status_row.remove_css_class("error");
                    plugin.force_reconnect_account(account);
                }
            });
            bot_btn_group.add(reconnect_btn_pa);

            page.add(bot_btn_group);
        } else {
            /* ── Standalone: just show status ─────────────────────── */
            var status_group = new Adw.PreferencesGroup();
            status_group.title = _("Standalone MQTT");
            status_group.description = _("Connection settings are managed in Preferences → MQTT (Standalone).");

            status_row = new Adw.ActionRow();
            status_row.title = _("Status");
            status_row.subtitle = _("Disconnected");
            status_group.add(status_row);

            /* Show Bot button (standalone) */
            var show_bot_btn_sa = new Button.with_label(_("Show Bot in Chat"));
            show_bot_btn_sa.add_css_class("flat");
            show_bot_btn_sa.add_css_class("pill");
            show_bot_btn_sa.halign = Align.CENTER;
            show_bot_btn_sa.tooltip_text = _("Re-open the MQTT Bot conversation in the sidebar");
            show_bot_btn_sa.clicked.connect(() => {
                if (plugin.bot_conversation != null) {
                    var conv = plugin.bot_conversation.reopen_standalone_conversation();
                    if (conv != null) {
                        message("MQTT Bot Manager: Standalone bot conversation re-opened");
                    }
                }
            });
            status_group.add(show_bot_btn_sa);

            /* Reconnect button (standalone) */
            var reconnect_btn_sa = new Button.with_label(_("Reconnect"));
            reconnect_btn_sa.add_css_class("flat");
            reconnect_btn_sa.add_css_class("pill");
            reconnect_btn_sa.halign = Align.CENTER;
            reconnect_btn_sa.tooltip_text = _("Disconnect and reconnect to the MQTT broker");
            reconnect_btn_sa.clicked.connect(() => {
                var sa_cfg = plugin.get_standalone_config();
                if (!sa_cfg.enabled) {
                    status_row.subtitle = _("Disabled — enable in Preferences first");
                    status_row.add_css_class("error");
                    status_row.remove_css_class("success");
                    return;
                }
                if (sa_cfg.broker_host.strip() == "") {
                    status_row.subtitle = _("No broker configured — set in Preferences");
                    status_row.add_css_class("error");
                    status_row.remove_css_class("success");
                    return;
                }
                status_row.subtitle = _("Reconnecting…");
                status_row.remove_css_class("success");
                status_row.remove_css_class("error");
                plugin.force_reconnect_standalone();
            });
            status_group.add(reconnect_btn_sa);

            page.add(status_group);
        }

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
        publish_nav.title = _("Publish &amp; Free Text");
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

        /* ── 4a. Pause/Resume toggle ──────────────────────────── */
        var runtime_group = new Adw.PreferencesGroup();
        runtime_group.title = _("Runtime");

        var pause_switch = new Adw.SwitchRow();
        pause_switch.title = _("Pause Messages");
        MqttAlertManager? am = plugin.get_alert_manager();
        bool initially_paused = (am != null) ? am.paused : false;
        pause_switch.subtitle = initially_paused
            ? _("Paused — messages are recorded but not shown")
            : _("Incoming MQTT messages are recorded but not shown in chat");
        pause_switch.active = initially_paused;
        pause_switch.notify["active"].connect(() => {
            MqttAlertManager? alert_mgr = plugin.get_alert_manager();
            if (alert_mgr != null) {
                alert_mgr.paused = pause_switch.active;
            }
            if (pause_switch.active) {
                pause_switch.subtitle = _("Paused — messages are recorded but not shown");
                toast_overlay.add_toast(new Adw.Toast(_("Messages paused")));
            } else {
                pause_switch.subtitle = _("Incoming MQTT messages are recorded but not shown in chat");
                toast_overlay.add_toast(new Adw.Toast(_("Messages resumed")));
            }
        });
        runtime_group.add(pause_switch);
        page.add(runtime_group);

        /* ── 4b. HA Discovery (per-account only — standalone has it on Settings Page) ── */
        if (!is_standalone) {
            disc_group = new Adw.PreferencesGroup();
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
        }

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

        topic_add_btn = new Button.with_label(_("Subscribe"));
        topic_add_btn.add_css_class("suggested-action");
        topic_add_btn.clicked.connect(on_add_topic);
        add_box.append(topic_add_btn);

        add_group.add(add_box);

        /* Alias entry row */
        var alias_box = new Box(Orientation.HORIZONTAL, 6);
        alias_box.margin_bottom = 6;

        topic_alias_entry = new Entry();
        topic_alias_entry.placeholder_text = _("Alias (optional, e.g. 🌡 Living Room)");
        topic_alias_entry.hexpand = true;
        topic_alias_entry.max_length = MqttConnectionConfig.MAX_ALIAS_LENGTH;
        alias_box.append(topic_alias_entry);

        add_group.add(alias_box);

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
        var nav_page = new Adw.NavigationPage.with_tag(toolbar_view, "publish", _("Publish &amp; Free Text"));
        return nav_page;
    }

    /* ── Alerts Page ──────────────────────────────────────────────── */

    private Adw.NavigationPage build_alerts_page() {
        var toolbar_view = new Adw.ToolbarView();
        var header = new Adw.HeaderBar();
        toolbar_view.add_top_bar(header);

        var page = new Adw.PreferencesPage();

        /* ── Add Alert form ──────────────────────────────────────── */
        var add_group = new Adw.PreferencesGroup();
        add_group.title = _("New Alert Rule");
        add_group.description = _("Trigger a notification when an MQTT message matches");

        alert_topic_entry = new Adw.EntryRow();
        alert_topic_entry.title = _("Topic pattern");
        alert_topic_entry.text = "";
        add_group.add(alert_topic_entry);

        alert_field_entry = new Adw.EntryRow();
        alert_field_entry.title = _("JSON field (optional)");
        alert_field_entry.text = "";
        add_group.add(alert_field_entry);

        /* Operator dropdown */
        string[] op_labels = { "contains", "==", "!=", ">", ">=", "<", "<=" };
        alert_op_dropdown = new DropDown.from_strings(op_labels);
        alert_op_dropdown.selected = 0;
        var op_row = new Adw.ActionRow();
        op_row.title = _("Operator");
        op_row.add_suffix(alert_op_dropdown);
        alert_op_dropdown.valign = Align.CENTER;
        add_group.add(op_row);

        alert_threshold_entry = new Adw.EntryRow();
        alert_threshold_entry.title = _("Threshold / keyword");
        alert_threshold_entry.text = "";
        add_group.add(alert_threshold_entry);

        /* Priority dropdown — must match MqttPriority enum values */
        string[] prio_labels = { "silent", "normal", "alert", "critical" };
        alert_priority_dropdown = new DropDown.from_strings(prio_labels);
        alert_priority_dropdown.selected = 2; /* default: alert */
        var prio_row = new Adw.ActionRow();
        prio_row.title = _("Priority");
        prio_row.add_suffix(alert_priority_dropdown);
        alert_priority_dropdown.valign = Align.CENTER;
        add_group.add(prio_row);

        var add_btn = new Button.with_label(_("Add Alert"));
        add_btn.add_css_class("suggested-action");
        add_btn.halign = Align.END;
        add_btn.margin_top = 8;
        add_btn.clicked.connect(on_add_alert);
        add_group.add(add_btn);

        page.add(add_group);

        /* ── Existing rules list ───────────────────────────────── */
        alerts_group = new Adw.PreferencesGroup();
        alerts_group.title = _("Alert Rules");
        alerts_group.description = _("Rules that trigger notifications when MQTT messages match patterns");
        page.add(alerts_group);

        populate_alerts_list();

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

        /* ── Add Bridge form ─────────────────────────────────────── */
        var add_group = new Adw.PreferencesGroup();
        add_group.title = _("New Bridge Rule");
        add_group.description = _("Forward MQTT messages to an XMPP contact or MUC");

        bridge_topic_entry = new Adw.EntryRow();
        bridge_topic_entry.title = _("Topic pattern");
        bridge_topic_entry.text = "";
        add_group.add(bridge_topic_entry);

        bridge_jid_entry = new Adw.EntryRow();
        bridge_jid_entry.title = _("XMPP JID");
        bridge_jid_entry.text = "";
        add_group.add(bridge_jid_entry);

        bridge_alias_entry = new Adw.EntryRow();
        bridge_alias_entry.title = _("Alias (optional)");
        bridge_alias_entry.text = "";
        add_group.add(bridge_alias_entry);

        /* Format dropdown: full, payload, short */
        var format_model = new Gtk.StringList(null);
        format_model.append("full");
        format_model.append("payload");
        format_model.append("short");
        bridge_format_dropdown = new DropDown(format_model, null);
        bridge_format_dropdown.selected = 0;
        var format_row = new Adw.ActionRow();
        format_row.title = _("Format");
        format_row.add_suffix(bridge_format_dropdown);
        add_group.add(format_row);

        /* Send-account dropdown (mandatory): which XMPP account sends */
        bridge_account_model = new Gtk.StringList(null);
        var accounts = plugin.app.stream_interactor.get_accounts();
        foreach (var acct in accounts) {
            bridge_account_model.append(acct.bare_jid.to_string());
        }
        bridge_account_dropdown = new DropDown(bridge_account_model, null);
        /* Pre-select: for per-account dialog, pick this account */
        if (!is_standalone && account != null) {
            for (uint i = 0; i < bridge_account_model.get_n_items(); i++) {
                if (bridge_account_model.get_string(i) == account.bare_jid.to_string()) {
                    bridge_account_dropdown.selected = i;
                    break;
                }
            }
        }
        var account_row = new Adw.ActionRow();
        account_row.title = _("Send as account");
        account_row.add_suffix(bridge_account_dropdown);
        add_group.add(account_row);

        bridge_add_btn = new Button.with_label(_("Add Bridge"));
        bridge_add_btn.add_css_class("suggested-action");
        bridge_add_btn.halign = Align.END;
        bridge_add_btn.margin_top = 8;
        bridge_add_btn.clicked.connect(on_add_bridge);
        add_group.add(bridge_add_btn);

        page.add(add_group);

        /* ── Existing rules list ───────────────────────────────── */
        bridges_group = new Adw.PreferencesGroup();
        bridges_group.title = _("Bridge Rules");
        bridges_group.description = _("Forward MQTT messages to XMPP contacts or MUCs");
        page.add(bridges_group);

        populate_bridges_list();

        toolbar_view.set_content(page);
        var nav_page = new Adw.NavigationPage.with_tag(toolbar_view, "bridges", _("Bridge Rules"));
        return nav_page;
    }

    /* ── Populate widgets from config ─────────────────────────────── */

    private void populate_from_config() {
        if (enable_switch != null) {
            enable_switch.active = config.enabled;
        }

        /* Mode selector: Use the persisted use_xmpp_auth flag as the
         * canonical indicator of which mode the user chose last time.
         * Do NOT infer from credential data — that causes the dialog
         * to flip to XMPP mode when the user hasn't entered
         * credentials yet but explicitly chose Custom mode. */
        if (mode_selector != null) {
            mode_selector.selected = config.use_xmpp_auth ? 0 : 1;
        }

        if (broker_host_entry != null) {
            broker_host_entry.text = config.broker_host;
        }
        if (broker_port_entry != null) {
            broker_port_entry.text = config.broker_port.to_string();
        }
        if (tls_switch != null) {
            tls_switch.active = config.tls;
        }
        if (xmpp_auth_switch != null) {
            xmpp_auth_switch.active = config.use_xmpp_auth;
        }
        if (xmpp_port_entry != null) {
            /* Show 8883 as default for XMPP mode if port is still 1883 */
            int port_val = config.broker_port;
            if (config.use_xmpp_auth && port_val == 1883) port_val = 8883;
            xmpp_port_entry.text = port_val.to_string();
        }
        if (xmpp_tls_switch != null) {
            /* Default to TLS on for XMPP mode if port is still 1883 (first time) */
            bool tls_val = config.tls;
            if (config.use_xmpp_auth && config.broker_port == 1883 && !config.tls) tls_val = true;
            xmpp_tls_switch.active = tls_val;
        }
        if (username_entry != null) {
            username_entry.text = config.username;
        }
        if (password_entry != null) {
            password_entry.text = config.password;
        }
        if (server_type_row != null) {
            server_type_row.subtitle = format_server_type(config.server_type);
        }

        update_mode_visibility();
        update_connection_sensitivity();
        update_status_display();
        check_tls_warning();
    }

    private void update_mode_visibility() {
        if (mode_selector == null) return;
        bool is_xmpp = (mode_selector.selected == 0);

        /* XMPP mode: show server info, hide broker/auth fields */
        if (xmpp_server_group != null) xmpp_server_group.visible = is_xmpp;
        if (broker_group != null) broker_group.visible = !is_xmpp;
        if (auth_group != null) auth_group.visible = !is_xmpp;
        if (tls_warning_group != null && is_xmpp) tls_warning_group.visible = false;

        /* HA Discovery requires a real MQTT broker (Mosquitto, EMQX etc.).
         * ejabberd/Prosody XMPP-MQTT do not support retained messages,
         * LWT, or free topic hierarchies — Discovery cannot work. */
        if (disc_group != null) disc_group.visible = !is_xmpp;

        /* XMPP mode: sync the xmpp_auth_switch */
        if (xmpp_auth_switch != null) {
            xmpp_auth_switch.active = is_xmpp;
        }

        /* Custom mode: re-check TLS warning */
        if (!is_xmpp) {
            check_tls_warning();
        }
    }

    private void update_status_display() {
        /* Check if there's an active client for this connection */
        bool connected;
        if (is_standalone) {
            connected = plugin.is_standalone_connected();
        } else {
            string key = account.bare_jid.to_string();
            connected = plugin.is_account_connected(key);
        }
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

    /**
     * Update widget sensitivity based on enable_switch state.
     * Dims all configuration when MQTT is disabled so the user
     * gets immediate visual feedback when toggling.
     */
    private void update_connection_sensitivity() {
        if (enable_switch == null) return;
        bool enabled = enable_switch.active;

        if (mode_selector != null) mode_selector.sensitive = enabled;
        if (xmpp_server_group != null) xmpp_server_group.sensitive = enabled;
        if (broker_group != null) broker_group.sensitive = enabled;
        if (auth_group != null) auth_group.sensitive = enabled;
        if (disc_group != null) disc_group.sensitive = enabled;
    }

    private string format_server_type(string type) {
        switch (type) {
            case "ejabberd": return _("ejabberd (mod_mqtt)");
            case "prosody":  return _("Prosody (mod_pubsub_mqtt) \u2014 read-only");
            default:         return _("Unknown / Not detected");
        }
    }

    /* ── Topic list ───────────────────────────────────────────────── */

    /** Priority labels for the per-topic dropdown. Index = MqttPriority ordinal. */
    private const string[] PRIORITY_LABELS = { "Silent", "Normal", "Alert", "Critical" };

    private void populate_topics_list() {
        /* Clear tracked rows — get_first_child() doesn't work on
         * Adw.PreferencesGroup because rows live inside an internal
         * GtkListBox, not as direct children.  Use explicit tracking.
         * Guard: skip remove for orphaned widgets from a rebuilt page. */
        foreach (var w in topic_rows) {
            if (w.get_parent() != null) {
                topics_group.remove(w);
            }
        }
        topic_rows.clear();

        string[] topic_list = config.get_topic_list();
        if (topic_list.length == 0) {
            var empty_row = new Adw.ActionRow();
            empty_row.title = _("No topics subscribed");
            empty_row.subtitle = _("Add a topic above");
            topics_group.add(empty_row);
            topic_rows.add(empty_row);
            return;
        }

        /* Parse QoS, priority and alias maps */
        HashMap<string, int> qos_map = parse_qos_map(config.topic_qos_json);
        HashMap<string, string> prio_map = parse_priority_map(config.topic_priorities_json);
        HashMap<string, string> aliases = config.get_aliases_map();

        foreach (string topic in topic_list) {
            int qos = qos_map.has_key(topic) ? qos_map[topic] : 0;
            string prio_str = prio_map.has_key(topic) ? prio_map[topic] : "normal";
            MqttPriority prio = MqttPriority.from_string(prio_str);
            string? alias = aliases.has_key(topic) ? aliases[topic] : null;

            var row = new Adw.ActionRow();
            if (alias != null && alias != "") {
                row.title = alias;
                row.subtitle = topic;
            } else {
                row.title = topic;
            }

            /* Suffix box: QoS dropdown + Priority dropdown + edit + delete */
            var suffix_box = new Box(Orientation.HORIZONTAL, 4);
            suffix_box.valign = Align.CENTER;

            /* QoS dropdown */
            string[] qos_labels = { "QoS 0", "QoS 1", "QoS 2" };
            var qos_dd = new DropDown.from_strings(qos_labels);
            qos_dd.selected = qos;
            qos_dd.tooltip_text = _("Quality of Service level");
            string t_qos = topic; /* capture for closure */
            qos_dd.notify["selected"].connect(() => {
                var qm = parse_qos_map(config.topic_qos_json);
                qm[t_qos] = (int) qos_dd.selected;
                config.topic_qos_json = build_qos_json(qm);
            });
            suffix_box.append(qos_dd);

            /* Priority dropdown */
            var prio_dd = new DropDown.from_strings(PRIORITY_LABELS);
            prio_dd.selected = (uint) prio;
            prio_dd.tooltip_text = _("Notification priority");
            string t_prio = topic;
            prio_dd.notify["selected"].connect(() => {
                var pm = parse_priority_map(config.topic_priorities_json);
                MqttPriority new_prio = (MqttPriority) prio_dd.selected;
                if (new_prio == MqttPriority.NORMAL) {
                    pm.unset(t_prio);
                } else {
                    pm[t_prio] = new_prio.to_string_key();
                }
                config.topic_priorities_json = build_priority_json(pm);
            });
            suffix_box.append(prio_dd);

            /* Edit button — loads values into the form above (like bridges) */
            var edit_btn = new Button.from_icon_name("document-edit-symbolic");
            edit_btn.valign = Align.CENTER;
            edit_btn.add_css_class("flat");
            edit_btn.tooltip_text = _("Edit subscription");
            string t_edit = topic;
            edit_btn.clicked.connect(() => {
                start_editing_topic(t_edit);
            });
            suffix_box.append(edit_btn);

            /* Delete button */
            var remove_btn = new Button.from_icon_name("user-trash-symbolic");
            remove_btn.valign = Align.CENTER;
            remove_btn.add_css_class("flat");
            remove_btn.add_css_class("destructive-action");
            string t = topic; /* capture for closure */
            remove_btn.clicked.connect(() => {
                remove_topic(t);
            });
            suffix_box.append(remove_btn);

            row.add_suffix(suffix_box);

            topics_group.add(row);
            topic_rows.add(row);
        }
    }

    /**
     * Load a subscription's values into the form for editing (like bridges).
     */
    private void start_editing_topic(string topic) {
        editing_topic = topic;

        topic_entry.text = topic;

        /* Restore QoS */
        HashMap<string, int> qm = parse_qos_map(config.topic_qos_json);
        qos_dropdown.selected = qm.has_key(topic) ? qm[topic] : 0;

        /* Restore alias */
        HashMap<string, string> aliases = config.get_aliases_map();
        topic_alias_entry.text = aliases.has_key(topic) ? aliases[topic] : "";

        /* Visual cue: change button label */
        topic_add_btn.label = _("Save");
        topic_entry.grab_focus();
    }

    private void on_add_topic() {
        string new_topic = topic_entry.text.strip();
        if (new_topic == "") return;

        string alias_text = topic_alias_entry.text.strip();
        int qos = (int) qos_dropdown.selected;

        if (editing_topic != null) {
            /* ── Update existing subscription ── */
            string old_topic = editing_topic;
            editing_topic = null;

            if (new_topic != old_topic) {
                /* Topic path changed → swap in topic list */
                string[] current = config.get_topic_list();
                string[] updated = {};
                foreach (string t in current) {
                    updated += (t == old_topic) ? new_topic : t;
                }
                config.topics = string.joinv(", ", updated);

                /* Migrate QoS */
                HashMap<string, int> qm = parse_qos_map(config.topic_qos_json);
                qm.unset(old_topic);
                qm[new_topic] = qos;
                config.topic_qos_json = build_qos_json(qm);

                /* Migrate priority */
                HashMap<string, string> pm = parse_priority_map(config.topic_priorities_json);
                if (pm.has_key(old_topic)) {
                    string pv = pm[old_topic];
                    pm.unset(old_topic);
                    pm[new_topic] = pv;
                    config.topic_priorities_json = build_priority_json(pm);
                }

                /* Migrate alias */
                config.remove_alias(old_topic);
            } else {
                /* Same topic — just update QoS */
                HashMap<string, int> qm = parse_qos_map(config.topic_qos_json);
                qm[new_topic] = qos;
                config.topic_qos_json = build_qos_json(qm);
            }

            /* Update alias */
            if (alias_text != "") {
                config.set_alias(new_topic, alias_text);
            } else {
                config.remove_alias(new_topic);
            }
        } else {
            /* ── Add new subscription ── */
            string[] current = config.get_topic_list();
            foreach (string t in current) {
                if (t == new_topic) {
                    topic_entry.text = "";
                    topic_alias_entry.text = "";
                    return;
                }
            }

            if (config.topics.strip() == "") {
                config.topics = new_topic;
            } else {
                config.topics = config.topics + ", " + new_topic;
            }

            HashMap<string, int> qos_map = parse_qos_map(config.topic_qos_json);
            qos_map[new_topic] = qos;
            config.topic_qos_json = build_qos_json(qos_map);

            if (alias_text != "") {
                config.set_alias(new_topic, alias_text);
            }
        }

        /* Clear form and reset button */
        topic_entry.text = "";
        topic_alias_entry.text = "";
        qos_dropdown.selected = 0;
        topic_add_btn.label = _("Subscribe");
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

        /* Remove alias if set */
        config.remove_alias(topic);

        populate_topics_list();
    }

    /* ── Add Alert handler ────────────────────────────────────────── */

    private void on_add_alert() {
        string topic = alert_topic_entry.text.strip();
        string threshold = alert_threshold_entry.text.strip();
        if (topic == "" || threshold == "") return;

        /* Map dropdown index to operator string */
        string[] op_values = { "contains", "==", "!=", ">", ">=", "<", "<=" };
        int op_idx = (int) alert_op_dropdown.selected;
        string op_str = op_values[op_idx];
        AlertOperator? op = AlertOperator.from_string(op_str);
        if (op == null) op = AlertOperator.CONTAINS;

        /* Map priority dropdown — must match MqttPriority enum values */
        string[] prio_values = { "silent", "normal", "alert", "critical" };
        int prio_idx = (int) alert_priority_dropdown.selected;
        MqttPriority prio = MqttPriority.from_string(prio_values[prio_idx]);

        var rule = new AlertRule();
        rule.topic = topic;
        rule.field = alert_field_entry.text.strip();
        if (rule.field == "") rule.field = null;
        rule.op = op;
        rule.threshold = threshold;
        rule.priority = prio;

        if (plugin.alert_manager != null) {
            plugin.alert_manager.add_rule(rule);
        }

        /* Clear form */
        alert_topic_entry.text = "";
        alert_field_entry.text = "";
        alert_threshold_entry.text = "";
        alert_op_dropdown.selected = 0;
        alert_priority_dropdown.selected = 2;  /* reset to "alert" */

        populate_alerts_list();
    }

    /* ── Add Bridge handler ───────────────────────────────────────── */

    private void on_add_bridge() {
        string topic = bridge_topic_entry.text.strip();
        string jid = bridge_jid_entry.text.strip();
        if (topic == "" || jid == "") return;

        /* send_account is mandatory */
        uint acct_idx = bridge_account_dropdown.selected;
        if (acct_idx == Gtk.INVALID_LIST_POSITION || acct_idx >= bridge_account_model.get_n_items()) return;
        string send_acct = bridge_account_model.get_string(acct_idx);
        if (send_acct == null || send_acct.strip() == "") return;

        string alias_text = bridge_alias_entry.text.strip();
        string? alias_val = (alias_text != "") ? alias_text : null;

        /* Map dropdown index to format string */
        string[] formats = { "full", "payload", "short" };
        uint sel = bridge_format_dropdown.selected;
        string format = (sel < formats.length) ? formats[sel] : "full";

        if (plugin.bridge_manager != null) {
            if (editing_bridge_id != null) {
                /* Update existing rule */
                plugin.bridge_manager.update_rule(
                    editing_bridge_id, topic, jid, format, alias_val, send_acct);
                editing_bridge_id = null;
                bridge_add_btn.label = _("Add Bridge");
            } else {
                /* Create new rule */
                var rule = new BridgeRule();
                rule.topic = topic;
                rule.target_jid = jid;
                rule.alias = alias_val;
                rule.format = format;
                rule.client_label = get_client_label();
                rule.send_account = send_acct;
                plugin.bridge_manager.add_rule(rule);
            }
        }

        /* Immediately subscribe the new bridge topic on the correct
         * MQTT client so that forwarding works without Save & Apply. */
        plugin.subscribe_bridge_topic(topic, get_client_label());

        /* Clear form */
        bridge_topic_entry.text = "";
        bridge_jid_entry.text = "";
        bridge_alias_entry.text = "";
        bridge_format_dropdown.selected = 0;

        populate_bridges_list();
    }

    /* ── Alerts list ──────────────────────────────────────────────── */

    private void populate_alerts_list() {
        /* Use tracked rows for clean removal (get_first_child doesn't
         * work on Adw.PreferencesGroup internal container).
         * Guard: only remove if the widget is still a child of the
         * current group — after back-navigation the group is rebuilt
         * and the old widgets are orphaned. */
        foreach (var w in alert_rows) {
            if (w.get_parent() != null) {
                alerts_group.remove(w);
            }
        }
        alert_rows.clear();

        /* Read alert rules from alert_manager */
        if (plugin.alert_manager == null) return;

        var rules = plugin.alert_manager.get_rules();

        if (rules.size == 0) {
            var empty_row = new Adw.ActionRow();
            empty_row.title = _("No alert rules configured");
            empty_row.subtitle = _("Add a rule above");
            alerts_group.add(empty_row);
            alert_rows.add(empty_row);
            return;
        }

        foreach (var rule in rules) {
            var row = new Adw.ActionRow();
            string? alias = config.resolve_alias(rule.topic);
            string display_topic = (alias != null) ? alias : rule.topic;
            row.title = "%s — \"%s\"".printf(
                display_topic, rule.threshold);
            string subtitle = "Priority: %s | Op: %s".printf(
                rule.priority.to_string_key(), rule.op.to_symbol());
            if (alias != null) {
                subtitle += " | %s".printf(rule.topic);
            }
            row.subtitle = subtitle;

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
            alert_rows.add(row);
        }
    }

    /* ── Bridges list ─────────────────────────────────────────────── */

    /* ID of the rule currently being edited, or null */
    private string? editing_bridge_id = null;

    private void populate_bridges_list() {
        /* Guard: skip remove for orphaned widgets from a rebuilt page */
        foreach (var w in bridge_rows) {
            if (w.get_parent() != null) {
                bridges_group.remove(w);
            }
        }
        bridge_rows.clear();

        if (plugin.bridge_manager == null) return;

        /* Only show rules that belong to this dialog's MQTT client */
        var rules = plugin.bridge_manager.get_rules_for_client(get_client_label());

        if (rules.size == 0) {
            var empty_row = new Adw.ActionRow();
            empty_row.title = _("No bridge rules configured");
            empty_row.subtitle = _("Add a rule above");
            bridges_group.add(empty_row);
            bridge_rows.add(empty_row);
            return;
        }

        foreach (var rule in rules) {
            var row = new Adw.ActionRow();

            /* Prefer rule-level alias, fall back to global config alias */
            string? alias = rule.alias;
            if (alias == null) alias = config.resolve_alias(rule.topic);
            string display_topic = (alias != null) ? alias : rule.topic;

            row.title = "%s → %s".printf(display_topic, rule.target_jid);
            string subtitle = "Format: %s".printf(rule.format ?? "full");
            if (alias != null) {
                subtitle += " | %s".printf(rule.topic);
            }
            if (rule.send_account != null && rule.send_account.strip() != "") {
                subtitle += " | via %s".printf(rule.send_account);
            }
            row.subtitle = subtitle;

            /* ── Edit button ── */
            var edit_btn = new Button.from_icon_name("document-edit-symbolic");
            edit_btn.valign = Align.CENTER;
            edit_btn.add_css_class("flat");
            edit_btn.tooltip_text = _("Edit");
            string eid = rule.id;
            edit_btn.clicked.connect(() => {
                start_editing_bridge(eid);
            });
            row.add_suffix(edit_btn);

            /* ── Delete button ── */
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
            bridge_rows.add(row);
        }
    }

    /** Load a bridge rule's values into the form for editing. */
    private void start_editing_bridge(string rule_id) {
        if (plugin.bridge_manager == null) return;
        BridgeRule? rule = plugin.bridge_manager.get_rule(rule_id);
        if (rule == null) return;

        editing_bridge_id = rule_id;
        bridge_topic_entry.text = rule.topic;
        bridge_jid_entry.text = rule.target_jid;
        bridge_alias_entry.text = rule.alias ?? "";

        /* Select the correct format in the dropdown */
        string[] formats = { "full", "payload", "short" };
        uint idx = 0;
        for (uint i = 0; i < formats.length; i++) {
            if (formats[i] == (rule.format ?? "full")) { idx = i; break; }
        }
        bridge_format_dropdown.selected = idx;

        /* Select the correct account in the dropdown */
        if (rule.send_account != null) {
            for (uint i = 0; i < bridge_account_model.get_n_items(); i++) {
                if (bridge_account_model.get_string(i) == rule.send_account) {
                    bridge_account_dropdown.selected = i;
                    break;
                }
            }
        }

        /* Switch button label to "Save" */
        bridge_add_btn.label = _("Save");

        /* Visual cue: scroll to top / focus topic entry */
        bridge_topic_entry.grab_focus();
    }

    /* ── Presets list ─────────────────────────────────────────────── */

    private void populate_presets_list() {
        /* Clear tracked rows — get_first_child() doesn't work on
         * Adw.PreferencesGroup because rows live inside an internal
         * GtkListBox, not as direct children.  Use explicit tracking.
         * Guard: skip remove for orphaned widgets from a rebuilt page. */
        foreach (var w in preset_rows) {
            if (w.get_parent() != null) {
                presets_group.remove(w);
            }
        }
        preset_rows.clear();

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
                preset_rows.add(row);
            }
        } catch (Error e) {
            warning("MQTT Bot Manager: Failed to parse presets JSON: %s", e.message);
            add_empty_presets_row();
        }
    }

    private void add_empty_presets_row() {
        var row = new Adw.ActionRow();
        row.title = _("No publish presets");
        row.subtitle = _("Use the form below to add a preset");
        presets_group.add(row);
        preset_rows.add(row);
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
            warning("MqttBotManagerDialog.on_add_preset: JSON parse failed: %s", e.message);
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
        /* Clear focus from any entry row to ensure changed signals
         * fire and focus is released properly before saving.  Using
         * set_focus(null) on the root avoids the GTK "Broken accounting
         * of active state" / "did not receive a focus-out event"
         * warnings that grab_focus() on a container can cause. */
        var root = this.get_root() as Gtk.Root;
        if (root != null) root.set_focus(null);

        /* Read values from widgets back to config (connection widgets only for per-account) */
        if (!is_standalone) {
            config.enabled = enable_switch.active;

            bool is_xmpp = (mode_selector != null && mode_selector.selected == 0);
            if (is_xmpp) {
                /* XMPP mode: auto-detect broker, use XMPP credentials.
                 * Keep any previously entered custom credentials intact
                 * so they are still there if the user switches back to
                 * Custom mode later.  Only set use_xmpp_auth = true so
                 * the connection logic knows to use XMPP creds. */
                config.use_xmpp_auth = true;
                /* Save port + TLS from XMPP mode fields */
                if (xmpp_port_entry != null) {
                    string xp_text = xmpp_port_entry.text.strip();
                    int xp_raw = xp_text != "" ? int.parse(xp_text) : 8883;
                    if (xp_raw < 1 || xp_raw > 65535) {
                        debug("MQTT: Invalid XMPP-mode port '%s', using 8883", xp_text);
                        xp_raw = 8883;
                    }
                    config.broker_port = xp_raw;
                }
                if (xmpp_tls_switch != null) {
                    config.tls = xmpp_tls_switch.active;
                }
                /* HA Discovery cannot work with XMPP-MQTT (no retain/LWT) */
                config.discovery_enabled = false;
            } else {
                /* Custom broker mode */
                config.broker_host = broker_host_entry.text.strip();
                string port_text = broker_port_entry.text.strip();
                int raw_port = port_text != "" ? int.parse(port_text) : 1883;
                config.broker_port = (raw_port > 0 && raw_port <= 65535) ? raw_port : 1883;
                config.tls = tls_switch.active;
                config.use_xmpp_auth = false;
                config.username = username_entry.text.strip();
                config.password = password_entry.text;
            }
        }

        /* Freitext settings (if publish page was visited) */
        if (freetext_enable_switch != null) {
            config.freetext_enabled = freetext_enable_switch.active;
            config.freetext_publish_topic = freetext_pub_topic_entry.text.strip();
            config.freetext_response_topic = freetext_resp_topic_entry.text.strip();
        }

        /* Discovery fields are already synced from widget callbacks */

        /* Preserve server_type from DB — don't overwrite detection
         * result with the potentially stale value from the dialog copy. */
        if (!is_standalone) {
            var fresh_st = plugin.get_account_config(account);
            if (fresh_st.server_type != "unknown" && fresh_st.server_type != "") {
                config.server_type = fresh_st.server_type;
            }
        }

        /* Persist to DB and apply */
        if (is_standalone) {
            /* Copy only bot/feature fields — connection settings are managed by settings_page */
            var sa = plugin.get_standalone_config();
            sa.topics = config.topics;
            sa.bot_enabled = config.bot_enabled;
            sa.bot_name = config.bot_name;
            sa.freetext_enabled = config.freetext_enabled;
            sa.freetext_publish_topic = config.freetext_publish_topic;
            sa.freetext_response_topic = config.freetext_response_topic;
            sa.freetext_qos = config.freetext_qos;
            sa.freetext_retain = config.freetext_retain;
            /* Discovery for standalone is managed by Settings Page — don't overwrite here */
            sa.publish_presets_json = config.publish_presets_json;
            sa.topic_qos_json = config.topic_qos_json;
            sa.topic_priorities_json = config.topic_priorities_json;
            sa.topic_aliases_json = config.topic_aliases_json;
            /* NOTE: alerts_json and bridges_json are NOT copied here.
             * AlertManager and BridgeManager own their data and persist
             * directly to mqtt.db.  The config.alerts_json / bridges_json
             * fields are legacy dead fields that were never synchronized
             * with the managers — copying them would overwrite good data
             * with stale "[]". */
            plugin.save_standalone_config();
            plugin.apply_settings();
            message("MQTT Bot Manager: Saved standalone config (enabled=%s)",
                    config.enabled.to_string());
        } else {
            plugin.save_account_config(account, config);
            plugin.apply_account_config_change(account, config);
            message("MQTT Bot Manager: Saved config for %s (enabled=%s)",
                    account.bare_jid.to_string(), config.enabled.to_string());
        }

        /* Immediate UI feedback after save */
        if (config.enabled) {
            status_row.subtitle = _("Connecting…");
            status_row.remove_css_class("error");
            status_row.remove_css_class("success");
        } else {
            status_row.subtitle = _("Disabled");
            status_row.remove_css_class("error");
            status_row.remove_css_class("success");
        }

        /* Refresh server type from persisted config (may have been
         * updated by auto-detection running in background) */
        refresh_server_type();

        /* Don't auto-close — user closes manually via X button */
    }

    /* ── TLS / Prosody warnings ─────────────────────────────────── */

    /**
     * Show/hide TLS warning when host is non-local and TLS is off.
     */
    private void check_tls_warning() {
        if (broker_host_entry == null || tls_switch == null || tls_warning_group == null) return;
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

    private HashMap<string, string> parse_priority_map(string json) {
        var map = new HashMap<string, string>();
        if (json == null || json.strip() == "" || json == "{}") return map;
        try {
            var parser = new Json.Parser();
            parser.load_from_data(json, -1);
            var root = parser.get_root();
            if (root != null && root.get_node_type() == Json.NodeType.OBJECT) {
                var obj = root.get_object();
                foreach (string member in obj.get_members()) {
                    string? val = obj.get_string_member(member);
                    if (val != null) map[member] = val;
                }
            }
        } catch (Error e) {
            warning("MqttBotManagerDialog: parse priority JSON: %s", e.message);
        }
        return map;
    }

    private string build_priority_json(HashMap<string, string> map) {
        var builder = new Json.Builder();
        builder.begin_object();
        foreach (var entry in map.entries) {
            builder.set_member_name(entry.key);
            builder.add_string_value(entry.value);
        }
        builder.end_object();
        var gen = new Json.Generator();
        gen.set_root(builder.get_root());
        return gen.to_data(null);
    }
}

}
