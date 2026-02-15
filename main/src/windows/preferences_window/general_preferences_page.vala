/*
 * Copyright (C) 2025 Ralf Peter <dinox@handwerker.jetzt>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

using Gtk;

public class Dino.Ui.ViewModel.GeneralPreferencesPage : Object {
    public bool send_typing { get; set; }
    public bool send_marker { get; set; }
    public bool notifications { get; set; }
    public bool keep_background { get; set; }
    public bool convert_emojis { get; set; }
    public string color_scheme { get; set; }

    public bool stickers_enabled { get; set; }
    public bool sticker_animations_enabled { get; set; }
    public bool location_sharing_enabled { get; set; }
    public bool bot_features_enabled { get; set; }
    public string api_mode { get; set; default = "local"; }
    public int api_port { get; set; default = 7842; }
    public string api_tls_cert { get; set; default = ""; }
    public string api_tls_key { get; set; default = ""; }
}

[GtkTemplate (ui = "/im/github/rallep71/DinoX/preferences_window/general_preferences_page.ui")]
public class Dino.Ui.GeneralPreferencesPage : Adw.PreferencesPage {
    [GtkChild] private unowned Adw.SwitchRow typing_row;
    [GtkChild] private unowned Adw.SwitchRow marker_row;
    [GtkChild] private unowned Adw.SwitchRow notification_row;
    [GtkChild] private unowned Adw.SwitchRow keep_background_row;
    [GtkChild] private unowned Adw.SwitchRow emoji_row;
    [GtkChild] private unowned Adw.SwitchRow stickers_enabled_row;
    [GtkChild] private unowned Adw.SwitchRow sticker_animations_row;
    [GtkChild] private unowned Adw.SwitchRow location_sharing_row;
    [GtkChild] private unowned Adw.SwitchRow bot_features_row;
    [GtkChild] private unowned Adw.ComboRow api_mode_row;
    [GtkChild] private unowned Adw.SpinRow api_port_row;
    [GtkChild] private unowned Adw.EntryRow api_tls_cert_row;
    [GtkChild] private unowned Adw.EntryRow api_tls_key_row;
    [GtkChild] private unowned Adw.ActionRow api_cert_renew_row;
    [GtkChild] private unowned Adw.ActionRow api_cert_delete_row;
    [GtkChild] private unowned Adw.ComboRow color_scheme_row;
    [GtkChild] private unowned Adw.ActionRow backup_row;
    [GtkChild] private unowned Adw.ActionRow restore_backup_row;
    [GtkChild] private unowned Adw.ActionRow data_location_row;
    [GtkChild] private unowned Adw.ActionRow change_db_password_row;
    [GtkChild] private unowned Adw.ActionRow clear_cache_row;
    [GtkChild] private unowned Adw.ActionRow reset_database_row;
    [GtkChild] private unowned Adw.ActionRow factory_reset_row;

    public ViewModel.GeneralPreferencesPage model { get; set; default = new ViewModel.GeneralPreferencesPage(); }
    private Binding[] model_bindings = new Binding[0];
    
    public signal void backup_requested();
    public signal void restore_backup_requested();
    public signal void show_data_location();
    public signal void change_db_password_requested();
    public signal void clear_cache_requested();
    public signal void reset_database_requested();
    public signal void factory_reset_requested();


    construct {
        this.notify["model"].connect(on_model_changed);
        
        // Setup color scheme options
        var scheme_model = new Gtk.StringList(null);
        scheme_model.append("Default (Follow System)");
        scheme_model.append("Light");
        scheme_model.append("Dark");
        color_scheme_row.model = scheme_model;

        // Setup API mode options
        var mode_model = new Gtk.StringList(null);
        mode_model.append(_( "Local (localhost)"));
        mode_model.append(_( "Network (0.0.0.0 + TLS)"));
        api_mode_row.model = mode_model;

        // Initially hide network-only settings
        update_api_visibility();

        // Connect cert management rows
        api_cert_renew_row.activated.connect(on_cert_renew_clicked);
        api_cert_delete_row.activated.connect(on_cert_delete_clicked);
        
        // Connect backup and data location rows
        backup_row.activated.connect(() => backup_requested());
        restore_backup_row.activated.connect(() => restore_backup_requested());
        data_location_row.activated.connect(() => show_data_location());

        change_db_password_row.activated.connect(() => change_db_password_requested());
        
        // Connect database maintenance rows
        clear_cache_row.activated.connect(() => clear_cache_requested());
        reset_database_row.activated.connect(() => reset_database_requested());
        factory_reset_row.activated.connect(() => factory_reset_requested());
    }

    private void on_model_changed() {
        foreach (Binding binding in model_bindings) {
            binding.unbind();
        }
        if (model != null) {
            model_bindings = new Binding[] {
                model.bind_property("send-typing", typing_row, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL),
                model.bind_property("send-marker", marker_row, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL),
                model.bind_property("notifications", notification_row, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL),
                model.bind_property("keep-background", keep_background_row, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL),
                model.bind_property("convert-emojis", emoji_row, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL),
                model.bind_property("stickers-enabled", stickers_enabled_row, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL),
                model.bind_property("sticker-animations-enabled", sticker_animations_row, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL),
                model.bind_property("location-sharing-enabled", location_sharing_row, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL),
                model.bind_property("bot-features-enabled", bot_features_row, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL)
            };

            // Bind API mode with custom conversion
            model.notify["api-mode"].connect(on_model_api_mode_changed);
            api_mode_row.notify["selected"].connect(on_ui_api_mode_changed);
            on_model_api_mode_changed();

            // Bind API port
            model.notify["api-port"].connect(() => {
                api_port_row.value = model.api_port;
            });
            api_port_row.notify["value"].connect(() => {
                model.api_port = (int) api_port_row.value;
            });
            api_port_row.value = model.api_port;

            // Bind TLS cert/key paths
            model.notify["api-tls-cert"].connect(() => {
                if (api_tls_cert_row.text != model.api_tls_cert) {
                    api_tls_cert_row.text = model.api_tls_cert;
                }
            });
            api_tls_cert_row.notify["text"].connect(() => {
                if (model.api_tls_cert != api_tls_cert_row.text) {
                    model.api_tls_cert = api_tls_cert_row.text;
                }
            });
            api_tls_cert_row.text = model.api_tls_cert ?? "";

            model.notify["api-tls-key"].connect(() => {
                if (api_tls_key_row.text != model.api_tls_key) {
                    api_tls_key_row.text = model.api_tls_key;
                }
            });
            api_tls_key_row.notify["text"].connect(() => {
                if (model.api_tls_key != api_tls_key_row.text) {
                    model.api_tls_key = api_tls_key_row.text;
                }
            });
            api_tls_key_row.text = model.api_tls_key ?? "";

            // Show/hide API settings based on bot_features_enabled
            bot_features_row.notify["active"].connect(update_api_visibility);
            update_api_visibility();
            
            // Bind color scheme with custom conversion
            model.notify["color-scheme"].connect(on_model_color_scheme_changed);
            color_scheme_row.notify["selected"].connect(on_ui_color_scheme_changed);
            on_model_color_scheme_changed();
        } else {
            model_bindings = new Binding[0];
        }
    }

    private void on_model_color_scheme_changed() {
        switch (model.color_scheme) {
            case "light":
                color_scheme_row.selected = 1;
                break;
            case "dark":
                color_scheme_row.selected = 2;
                break;
            default:
                color_scheme_row.selected = 0;
                break;
        }
    }

    private void on_ui_color_scheme_changed() {
        switch (color_scheme_row.selected) {
            case 1:
                model.color_scheme = "light";
                break;
            case 2:
                model.color_scheme = "dark";
                break;
            default:
                model.color_scheme = "default";
                break;
        }
    }

    private void on_model_api_mode_changed() {
        if (model.api_mode == "network") {
            api_mode_row.selected = 1;
        } else {
            api_mode_row.selected = 0;
        }
        update_api_visibility();
    }

    private void on_ui_api_mode_changed() {
        if (api_mode_row.selected == 1) {
            model.api_mode = "network";
        } else {
            model.api_mode = "local";
        }
        update_api_visibility();
    }

    private void update_api_visibility() {
        bool bot_enabled = bot_features_row.active;
        bool network_mode = (api_mode_row.selected == 1);

        api_mode_row.visible = bot_enabled;
        api_port_row.visible = bot_enabled;
        api_tls_cert_row.visible = bot_enabled && network_mode;
        api_tls_key_row.visible = bot_enabled && network_mode;

        // Cert management buttons: only in network mode with empty (auto) cert paths
        bool auto_cert = (api_tls_cert_row.text == null || api_tls_cert_row.text == "") &&
                         (api_tls_key_row.text == null || api_tls_key_row.text == "");
        string cert_dir = Path.build_filename(Environment.get_user_data_dir(), "dinox", "api-tls");
        string cert_path = Path.build_filename(cert_dir, "server.crt");
        bool cert_exists = FileUtils.test(cert_path, FileTest.EXISTS);

        api_cert_renew_row.visible = bot_enabled && network_mode && auto_cert && cert_exists;
        api_cert_delete_row.visible = bot_enabled && network_mode && auto_cert && cert_exists;

        // Update subtitle for TLS rows
        if (network_mode) {
            string cert_hint = (api_tls_cert_row.text == null || api_tls_cert_row.text == "")
                ? _( "Empty = auto-generated self-signed") : "";
            string key_hint = (api_tls_key_row.text == null || api_tls_key_row.text == "")
                ? _( "Empty = auto-generated self-signed") : "";
            // Placeholder text to hint auto-generation
            api_tls_cert_row.set_tooltip_text(cert_hint);
            api_tls_key_row.set_tooltip_text(key_hint);
        }
    }

    private void on_cert_renew_clicked() {
        string cert_dir = Path.build_filename(Environment.get_user_data_dir(), "dinox", "api-tls");
        string cert_path = Path.build_filename(cert_dir, "server.crt");
        string key_path = Path.build_filename(cert_dir, "server.key");

        // Delete existing cert files
        if (FileUtils.test(cert_path, FileTest.EXISTS)) {
            FileUtils.remove(cert_path);
        }
        if (FileUtils.test(key_path, FileTest.EXISTS)) {
            FileUtils.remove(key_path);
        }

        // Update subtitle to show status
        api_cert_renew_row.subtitle = _( "Certificate deleted. Server will restart with new certificate.");
        update_api_visibility();

        // Trigger API server restart by toggling a setting
        model.api_tls_cert = " ";
        model.api_tls_cert = "";
    }

    private void on_cert_delete_clicked() {
        string cert_dir = Path.build_filename(Environment.get_user_data_dir(), "dinox", "api-tls");
        string cert_path = Path.build_filename(cert_dir, "server.crt");
        string key_path = Path.build_filename(cert_dir, "server.key");

        if (FileUtils.test(cert_path, FileTest.EXISTS)) {
            FileUtils.remove(cert_path);
        }
        if (FileUtils.test(key_path, FileTest.EXISTS)) {
            FileUtils.remove(key_path);
        }

        api_cert_delete_row.subtitle = _( "Certificate and key deleted.");
        update_api_visibility();

        // Trigger API server restart
        model.api_tls_cert = " ";
        model.api_tls_cert = "";
    }
}
