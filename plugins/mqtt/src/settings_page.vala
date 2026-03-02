/*
 * MqttStandaloneSettingsPage — Adw.PreferencesPage for standalone MQTT config.
 *
 * Provides:
 *   - Enable/disable toggle
 *   - Mode selection (standalone / per-account / auto)
 *   - Broker host, port, TLS
 *   - Username / password
 *   - Server type display (auto-detected or manual)
 *   - Topic list management
 *
 * Per-account MQTT configuration is handled by MqttBotManagerDialog.
 * This page only manages the standalone connection.
 *
 * Registered via configure_preferences signal in Plugin.registered().
 *
 * Copyright (C) 2026 Ralf Peter <dinox@handwerker.jetzt>
 */

using Gtk;
using Adw;
using GLib;
using Gee;
using Dino.Entities;

namespace Dino.Plugins.Mqtt {

public class MqttStandaloneSettingsPage : Adw.PreferencesPage {

    /* References */
    private Plugin plugin;
    private Dino.Database db;

    /* Widgets */
    private Switch enable_switch;
    private Adw.EntryRow host_row;
    private Adw.SpinRow port_row;
    private Switch tls_switch;
    private Adw.EntryRow user_row;
    private Adw.PasswordEntryRow pass_row;
    private Label status_label;
    private Gtk.Button save_button;
    private Switch disc_switch;
    private Adw.EntryRow disc_prefix_row;
    private Adw.PreferencesGroup discovery_group;

    /* Prevent saving during programmatic updates */
    private bool loading = true;

    /* TLS warning */
    private Adw.PreferencesGroup tls_warning_group;

    /* Status refresh timer */
    private uint status_timer_id = 0;
    private uint status_oneshot_id = 0;
    private ulong connection_signal_id = 0;

    /* ── DB keys — now use StandaloneKey.* for standalone config ──── */

    /* The mode row is kept for UX but doesn't affect backend anymore.
     * Backend uses standalone_config + per-account configs independently. */


    /* ── Constructor ──────────────────────────────────────────────── */

    public MqttStandaloneSettingsPage(Plugin plugin) {
        this.plugin = plugin;
        this.db = plugin.app.db;
        this.title = _("MQTT (Standalone)");
        this.icon_name = "network-transmit-symbolic";
        this.name = "mqtt";

        build_ui();
        load_settings();
        loading = false;
    }

    /* ── UI construction ──────────────────────────────────────────── */

    private void build_ui() {
        /* ── Group 1: Connection ──────────────────────────────────── */
        var conn_group = new Adw.PreferencesGroup();
        conn_group.title = _("Standalone MQTT Connection");
        conn_group.description = _("Global MQTT broker — independent of your XMPP accounts.\n" +
            "For account-specific MQTT, use Account Settings → MQTT Bot.");
        this.add(conn_group);

        /* Enable switch */
        var enable_row = new Adw.ActionRow();
        enable_row.title = _("Enable Standalone MQTT");
        enable_row.subtitle = _("Connect to an external MQTT broker (Mosquitto, Home Assistant, HiveMQ…)");

        enable_switch = new Switch();
        enable_switch.valign = Align.CENTER;
        /* Toggle only updates the visual state and marks dirty.
         * Actual save + apply happens via "Save & Apply" button,
         * matching the per-account MQTT UX. */
        enable_switch.notify["active"].connect(() => {
            if (loading) return;
            message("[STANDALONE] UI toggle → %s (not yet applied)",
                    enable_switch.active ? "ON" : "OFF");
            update_sensitivity();
            mark_dirty();
        });
        enable_row.add_suffix(enable_switch);
        conn_group.add(enable_row);

        /* ── Group 2: Broker ──────────────────────────────────────── */
        var broker_group = new Adw.PreferencesGroup();
        broker_group.title = _("Broker");
        this.add(broker_group);

        /* Host */
        host_row = new Adw.EntryRow();
        host_row.title = _("Host");
        host_row.changed.connect(() => {
            if (!loading) mark_dirty();
            check_tls_warning();
        });
        broker_group.add(host_row);

        /* Port */
        var port_adj = new Adjustment(1883, 1, 65535, 1, 100, 0);
        port_row = new Adw.SpinRow(port_adj, 1, 0);
        port_row.title = _("Port");
        port_row.notify["value"].connect(() => {
            if (!loading) mark_dirty();
        });
        broker_group.add(port_row);

        /* TLS */
        var tls_row = new Adw.ActionRow();
        tls_row.title = _("TLS Encryption");
        tls_row.subtitle = _("Enable for port 8883 or secure connections");

        tls_switch = new Switch();
        tls_switch.valign = Align.CENTER;
        tls_switch.notify["active"].connect(() => {
            if (!loading) mark_dirty();
            check_tls_warning();
        });
        tls_row.add_suffix(tls_switch);
        broker_group.add(tls_row);

        /* TLS Warning group — shown when host is non-local and TLS is off */
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
        this.add(tls_warning_group);

        /* ── Group 3: Authentication ──────────────────────────────── */
        var auth_group = new Adw.PreferencesGroup();
        auth_group.title = _("Authentication");
        auth_group.description = _("Leave empty if the broker requires no authentication.");
        this.add(auth_group);

        user_row = new Adw.EntryRow();
        user_row.title = _("Username");
        user_row.changed.connect(() => {
            if (!loading) mark_dirty();
        });
        auth_group.add(user_row);

        pass_row = new Adw.PasswordEntryRow();
        pass_row.title = _("Password");
        pass_row.changed.connect(() => {
            if (!loading) mark_dirty();
        });
        auth_group.add(pass_row);

        /* ── Group 4: Bot Manager ─────────────────────────────────── */
        var manager_group = new Adw.PreferencesGroup();
        manager_group.title = _("MQTT Bot Manager");
        manager_group.description = _("Publish presets, alerts, bridges, free-text and more");
        this.add(manager_group);

        var manager_row = new Adw.ActionRow();
        manager_row.title = _("Open Bot Manager");
        manager_row.subtitle = _("Configure publish presets, alert rules, bridge rules, free-text publishing");
        manager_row.activatable = true;
        manager_row.add_suffix(new Image.from_icon_name("go-next-symbolic"));
        manager_row.activated.connect(() => {
            var dialog = new MqttBotManagerDialog.standalone(plugin);
            /* Find the top-level window to present the dialog on */
            var win = this.get_root() as Gtk.Window;
            if (win != null) {
                dialog.present(win);
            }
        });
        manager_group.add(manager_row);

        /* Show Bot in Chat — re-open closed bot conversation */
        var show_bot_row = new Adw.ActionRow();
        show_bot_row.title = _("Show Bot in Chat");
        show_bot_row.subtitle = _("Re-open the MQTT Bot conversation if you closed it");
        show_bot_row.activatable = true;
        show_bot_row.add_suffix(new Image.from_icon_name("chat-message-new-symbolic"));
        show_bot_row.activated.connect(() => {
            if (plugin.bot_conversation != null) {
                var conv = plugin.bot_conversation.reopen_standalone_conversation();
                if (conv != null) {
                    message("MQTT Settings: Standalone bot conversation re-opened");
                }
            }
        });
        manager_group.add(show_bot_row);

        /* ── Group 7: Status ──────────────────────────────────────── */
        var status_group = new Adw.PreferencesGroup();
        status_group.title = _("Status");
        this.add(status_group);

        var status_row = new Adw.ActionRow();
        status_row.title = _("Connection Status");
        status_label = new Label(_("Not connected"));
        status_label.add_css_class("dim-label");
        status_label.valign = Align.CENTER;
        status_row.add_suffix(status_label);
        status_group.add(status_row);

        /* Update status periodically and on connection changes */
        update_status();
        status_timer_id = Timeout.add_seconds(3, () => {
            update_status();
            return true;  /* keep timer */
        });
        connection_signal_id = plugin.connection_changed.connect((source, connected) => {
            update_status();
        });

        /* ── HA Discovery ─────────────────────────────────────────── */
        discovery_group = new Adw.PreferencesGroup();
        discovery_group.title = _("Home Assistant Discovery");
        discovery_group.description = _("Announce DinoX as a device in Home Assistant via MQTT Discovery.\n" +
            "Requires a broker with retained message support (not XMPP-MQTT).");
        this.add(discovery_group);

        var disc_row = new Adw.ActionRow();
        disc_row.title = _("Enable Discovery");
        disc_row.subtitle = _("Publish device and entity configs to the broker");
        disc_switch = new Switch();
        disc_switch.valign = Align.CENTER;
        disc_switch.notify["active"].connect(() => {
            if (!loading) mark_dirty();
        });
        disc_row.add_suffix(disc_switch);
        discovery_group.add(disc_row);

        disc_prefix_row = new Adw.EntryRow();
        disc_prefix_row.title = _("Discovery Prefix");
        disc_prefix_row.changed.connect(() => {
            if (!loading) mark_dirty();
        });
        discovery_group.add(disc_prefix_row);

        /* ── Save & Apply (bottom of page) ────────────────────────── */
        var save_group = new Adw.PreferencesGroup();
        save_button = new Gtk.Button.with_label(_("Save & Apply"));
        save_button.add_css_class("suggested-action");
        save_button.add_css_class("pill");
        save_button.halign = Align.CENTER;
        save_button.margin_top = 12;
        save_button.sensitive = false;
        save_button.clicked.connect(on_save_clicked);
        save_group.add(save_button);
        this.add(save_group);
    }

    ~MqttStandaloneSettingsPage() {
        if (status_oneshot_id != 0) {
            Source.remove(status_oneshot_id);
            status_oneshot_id = 0;
        }
        if (status_timer_id != 0) {
            Source.remove(status_timer_id);
            status_timer_id = 0;
        }
        if (connection_signal_id != 0) {
            plugin.disconnect(connection_signal_id);
            connection_signal_id = 0;
        }
    }

    /* ── Save & Apply ─────────────────────────────────────────────── */

    /** Mark connection settings as modified — enables the Save button. */
    private void mark_dirty() {
        if (save_button != null) save_button.sensitive = true;
    }

    /**
     * Save all connection fields to DB and apply.
     * Matches the per-account "Save & Apply" UX pattern.
     */
    private void on_save_clicked() {
        /* Grab focus away from entry rows to prevent GTK
         * "did not receive a focus-out event" warnings. */
        save_button.grab_focus();

        save_setting(StandaloneKey.ENABLED, enable_switch.active ? "1" : "0");
        save_setting(StandaloneKey.BROKER_HOST, host_row.text);
        save_setting(StandaloneKey.BROKER_PORT, ((int) port_row.value).to_string());
        save_setting(StandaloneKey.TLS, tls_switch.active ? "1" : "0");
        save_setting(StandaloneKey.USERNAME, user_row.text);
        save_setting(StandaloneKey.PASSWORD, pass_row.text);
        save_setting(StandaloneKey.DISCOVERY_ENABLED, disc_switch.active ? "1" : "0");
        string prefix_val = disc_prefix_row.text.strip();
        save_setting(StandaloneKey.DISCOVERY_PREFIX,
                     prefix_val != "" ? prefix_val : "homeassistant");

        message("[STANDALONE] Save & Apply — reloading config");
        plugin.reload_config();
        plugin.apply_settings();

        save_button.sensitive = false;

        /* Refresh status after a short delay */
        if (status_oneshot_id != 0) {
            Source.remove(status_oneshot_id);
            status_oneshot_id = 0;
        }
        status_oneshot_id = Timeout.add(500, () => {
            status_oneshot_id = 0;
            update_status();
            return false;
        });
    }

    /* ── Settings persistence ─────────────────────────────────────── */

    private void load_settings() {
        loading = true;

        enable_switch.active = get_setting(StandaloneKey.ENABLED) == "1";

        host_row.text = get_setting(StandaloneKey.BROKER_HOST) ?? "";
        string? port_s = get_setting(StandaloneKey.BROKER_PORT);
        port_row.value = port_s != null ? double.parse(port_s) : 1883;
        tls_switch.active = get_setting(StandaloneKey.TLS) == "1";
        user_row.text = get_setting(StandaloneKey.USERNAME) ?? "";
        pass_row.text = get_setting(StandaloneKey.PASSWORD) ?? "";

        disc_switch.active = get_setting(StandaloneKey.DISCOVERY_ENABLED) == "1";
        disc_prefix_row.text = get_setting(StandaloneKey.DISCOVERY_PREFIX) ?? "homeassistant";

        update_sensitivity();
        check_tls_warning();
        loading = false;
    }

    private string? get_setting(string key) {
        var row_opt = db.settings.select({db.settings.value})
            .with(db.settings.key, "=", key)
            .single()
            .row();
        if (row_opt.is_present()) return row_opt[db.settings.value];
        return null;
    }

    private void save_setting(string key, string val) {
        db.settings.upsert()
            .value(db.settings.key, key, true)
            .value(db.settings.value, val)
            .perform();
    }

    /* ── Sensitivity logic ────────────────────────────────────────── */

    private void update_sensitivity() {
        bool enabled = enable_switch.active;
        host_row.sensitive = enabled;
        port_row.sensitive = enabled;
        tls_switch.sensitive = enabled;
        user_row.sensitive = enabled;
        pass_row.sensitive = enabled;
        if (discovery_group != null) discovery_group.sensitive = enabled;
    }

    /* ── Status display ───────────────────────────────────────────── */

    /**
     * Show/hide TLS warning when host is non-local and TLS is off.
     */
    private void check_tls_warning() {
        string host = host_row.text.strip();
        bool tls = tls_switch.active;
        tls_warning_group.visible = (host != "" && !tls && !MqttUtils.is_local_host(host));
    }

    private void update_status() {
        /* Show standalone-specific status only — this is the standalone
         * settings page.  The old code also checked per-account clients,
         * which caused the status to stay "Connected (N accounts)" after
         * standalone was disabled if per-account MQTT was still active.
         * The user then thinks standalone didn't disconnect. */
        var standalone = plugin.get_standalone_client();
        if (standalone != null && standalone.is_connected) {
            status_label.label = _("Connected");
            status_label.remove_css_class("dim-label");
            status_label.add_css_class("success");
        } else if (enable_switch.active) {
            status_label.label = _("Connecting…");
            status_label.remove_css_class("success");
            status_label.add_css_class("dim-label");
        } else {
            status_label.label = _("Disabled");
            status_label.remove_css_class("success");
            status_label.add_css_class("dim-label");
        }
    }
}

}
