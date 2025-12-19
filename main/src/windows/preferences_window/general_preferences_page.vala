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
                model.bind_property("sticker-animations-enabled", sticker_animations_row, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL)
            };
            
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
}
