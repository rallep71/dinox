/*
 * Copyright (C) 2025 Ralf Peter <dinox@handwerker.jetzt>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

using Gtk;
using Gee;

namespace Dino.Ui {

[GtkTemplate (ui = "/im/github/rallep71/DinoX/bot_manager_dialog.ui")]
public class BotManagerDialog : Adw.Dialog {

    [GtkChild] private unowned Gtk.Stack main_stack;
    [GtkChild] private unowned Gtk.ListBox bot_list;
    [GtkChild] private unowned Gtk.Button create_button;
    [GtkChild] private unowned Gtk.Label api_status_label;
    [GtkChild] private unowned Adw.SwitchRow account_enabled_switch;

    private Soup.Session http;
    private uint16 api_port = 7842;
    private bool toggle_loading = false; // suppress signal during load

    public string account_jid { get; set; default = ""; }

    construct {
        http = new Soup.Session();

        create_button.clicked.connect(on_create_clicked);

        // Toggle per-account Botmother enabled/disabled
        account_enabled_switch.notify["active"].connect(() => {
            if (!toggle_loading && account_jid != "") {
                set_account_enabled.begin(account_enabled_switch.active);
            }
        });

        // Load when mapped (account_jid may be set after construct)
        this.notify["account-jid"].connect(() => {
            if (account_jid != "") {
                this.title = "Botmother \u2014 %s".printf(account_jid);
                main_stack.visible_child_name = "loading";
                load_account_status.begin();
            }
        });

        // Auto-refresh when dialog gets focus
        this.notify["focus-widget"].connect(() => {
            if (account_jid != "" && this.focus_widget != null) {
                load_bots.begin();
            }
        });

        main_stack.visible_child_name = "loading";
        // Initial load deferred until account_jid is set
    }

    // Load the per-account enabled status from the API, then load bots
    private async void load_account_status() {
        toggle_loading = true;
        try {
            string url = "http://127.0.0.1:%u/bot/account/status?account=%s".printf(
                api_port, GLib.Uri.escape_string(account_jid, null, false));
            var msg = new Soup.Message("GET", url);
            Bytes response = yield http.send_and_read_async(msg, GLib.Priority.DEFAULT, null);
            if (msg.status_code == 200) {
                var parser = new Json.Parser();
                parser.load_from_data((string) response.get_data());
                var root = parser.get_root().get_object();
                if (root.has_member("result") && root.get_member("result").get_node_type() == Json.NodeType.OBJECT) {
                    var result = root.get_object_member("result");
                    if (result.has_member("enabled")) {
                        account_enabled_switch.active = result.get_boolean_member("enabled");
                    }
                } else if (root.has_member("enabled")) {
                    account_enabled_switch.active = root.get_boolean_member("enabled");
                }
            }
        } catch (Error e) {
            warning("BotManager: Failed to load account status: %s", e.message);
        }
        toggle_loading = false;
        yield load_bots();
    }

    // Toggle per-account enabled via POST to API
    private async void set_account_enabled(bool new_enabled) {
        try {
            string json_body = "{\"account\":\"%s\",\"enabled\":%s}".printf(
                account_jid, new_enabled ? "true" : "false");
            string url = "http://127.0.0.1:%u/bot/account/status".printf(api_port);
            var msg = new Soup.Message("POST", url);
            msg.set_request_body_from_bytes("application/json", new Bytes(json_body.data));
            yield http.send_and_read_async(msg, GLib.Priority.DEFAULT, null);

            if (msg.status_code != 200) {
                warning("BotManager: Toggle failed with status %u", msg.status_code);
            }
        } catch (Error e) {
            warning("BotManager: Toggle error: %s", e.message);
        }
    }

    private async void load_bots() {
        try {
            string url = "http://127.0.0.1:%u/bot/list".printf(api_port);
            if (account_jid != "") {
                url += "?account=%s".printf(GLib.Uri.escape_string(account_jid, null, false));
            }
            var msg = new Soup.Message("GET", url);
            Bytes response = yield http.send_and_read_async(msg, GLib.Priority.DEFAULT, null);

            if (msg.status_code != 200) {
                show_error("API returned status %u".printf(msg.status_code));
                return;
            }

            var parser = new Json.Parser();
            parser.load_from_data((string) response.get_data());
            var root = parser.get_root().get_object();

            if (!root.has_member("bots")) {
                show_error("Invalid response from API");
                return;
            }

            var bots = root.get_array_member("bots");

            // Clear existing rows
            Gtk.Widget? child = bot_list.get_first_child();
            while (child != null) {
                Gtk.Widget? next = child.get_next_sibling();
                bot_list.remove(child);
                child = next;
            }

            if (bots.get_length() == 0) {
                main_stack.visible_child_name = "empty";
                return;
            }

            for (uint i = 0; i < bots.get_length(); i++) {
                var bot = bots.get_object_element(i);
                int64 bot_id = bot.get_int_member("id");
                string name = bot.get_string_member("name");
                string mode = bot.has_member("mode") ? bot.get_string_member("mode") : "personal";
                string status = bot.has_member("status") ? bot.get_string_member("status") : "active";
                string? token = bot.has_member("token") ? bot.get_string_member("token") : null;
                string status_icon = (status == "active") ? "\xf0\x9f\x9f\xa2" : "\xf0\x9f\x94\xb4";

                var row = new Adw.ActionRow();
                row.title = "%s %s".printf(status_icon, name);
                row.subtitle = "ID: %lld · %s · %s".printf(bot_id, mode, status);

                // Copy token button
                if (token != null && token != "") {
                    var copy_btn = new Gtk.Button();
                    copy_btn.icon_name = "edit-copy-symbolic";
                    copy_btn.valign = Gtk.Align.CENTER;
                    copy_btn.tooltip_text = "Copy API Token";
                    copy_btn.add_css_class("flat");
                    string token_copy = token;
                    copy_btn.clicked.connect(() => {
                        var clipboard = copy_btn.get_clipboard();
                        clipboard.set_text(token_copy);
                    });
                    row.add_suffix(copy_btn);
                }

                // Delete button
                var delete_btn = new Gtk.Button();
                delete_btn.icon_name = "user-trash-symbolic";
                delete_btn.valign = Gtk.Align.CENTER;
                delete_btn.tooltip_text = "Delete Botmother";
                delete_btn.add_css_class("flat");
                delete_btn.add_css_class("error");
                int64 del_id = bot_id;
                string del_name = name;
                delete_btn.clicked.connect(() => {
                    confirm_delete.begin(del_id, del_name);
                });
                row.add_suffix(delete_btn);

                bot_list.append(row);
            }

            api_status_label.label = "Botmother API: http://127.0.0.1:%u".printf(api_port);
            main_stack.visible_child_name = "list";

        } catch (Error e) {
            show_error(e.message);
        }
    }

    private void on_create_clicked() {
        var dialog = new BotCreateDialog();
        dialog.account_jid = this.account_jid;
        dialog.bot_created.connect(() => {
            load_bots.begin();
        });
        dialog.present(this);
    }

    private async void confirm_delete(int64 bot_id, string bot_name) {
        var alert = new Adw.AlertDialog(
            "Delete Botmother?",
            "Are you sure you want to delete \"%s\"? This cannot be undone.".printf(bot_name)
        );
        alert.add_response("cancel", "Cancel");
        alert.add_response("delete", "Delete");
        alert.set_response_appearance("delete", Adw.ResponseAppearance.DESTRUCTIVE);
        alert.default_response = "cancel";

        string response = yield alert.choose(this, null);
        if (response == "delete") {
            yield delete_bot(bot_id);
        }
    }

    private async void delete_bot(int64 bot_id) {
        try {
            var msg = new Soup.Message("DELETE", "http://127.0.0.1:%u/bot/delete?id=%lld".printf(api_port, bot_id));
            yield http.send_and_read_async(msg, GLib.Priority.DEFAULT, null);

            if (msg.status_code == 200) {
                main_stack.visible_child_name = "loading";
                yield load_bots();
            } else {
                warning("BotManager: Delete failed with status %u", msg.status_code);
            }
        } catch (Error e) {
            warning("BotManager: Delete error: %s", e.message);
        }
    }

    private void show_error(string detail) {
        warning("BotManager: %s", detail);
        main_stack.visible_child_name = "error";
    }
}

}
