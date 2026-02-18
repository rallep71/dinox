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
    [GtkChild] private unowned Adw.EntryRow ejabberd_url_entry;
    [GtkChild] private unowned Adw.EntryRow ejabberd_host_entry;
    [GtkChild] private unowned Adw.EntryRow ejabberd_admin_entry;
    [GtkChild] private unowned Adw.PasswordEntryRow ejabberd_password_entry;
    [GtkChild] private unowned Gtk.Button ejabberd_test_button;
    [GtkChild] private unowned Gtk.Button ejabberd_save_button;
    [GtkChild] private unowned Adw.ActionRow ejabberd_actions_row;

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

        // Auto-refresh when dialog gets focus — BUT NOT when clicking inside the dialog
        // Only refresh when the entire dialog regains focus from outside
        this.map.connect(() => {
            if (account_jid != "") {
                load_bots.begin();
            }
        });

        // ejabberd settings buttons
        ejabberd_save_button.clicked.connect(() => {
            save_ejabberd_settings.begin();
        });
        ejabberd_test_button.clicked.connect(() => {
            test_ejabberd_connection.begin();
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
        yield load_ejabberd_settings();
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
                // Still show "list" page so toggle + ejabberd settings remain visible
                api_status_label.label = "Botmother API: http://127.0.0.1:%u".printf(api_port);
                main_stack.visible_child_name = "list";
                return;
            }

            for (uint i = 0; i < bots.get_length(); i++) {
                var bot = bots.get_object_element(i);
                int64 bot_id = bot.get_int_member("id");
                string name = bot.get_string_member("name");
                string mode = bot.has_member("mode") ? bot.get_string_member("mode") : "personal";
                string status = bot.has_member("status") ? bot.get_string_member("status") : "active";
                string? token = bot.has_member("token") ? bot.get_string_member("token") : null;
                string? bot_jid = bot.has_member("jid") ? bot.get_string_member("jid") : null;
                string status_icon = (status == "active") ? "\xf0\x9f\x9f\xa2" : "\xf0\x9f\x94\xb4";

                // Bot info row
                var row = new Adw.ActionRow();
                row.title = "%s %s".printf(status_icon, name);
                if (bot_jid != null && bot_jid != "") {
                    row.subtitle = "ID: %lld \u00b7 %s \u00b7 %s \u00b7 %s".printf(bot_id, mode, status, bot_jid);
                } else {
                    row.subtitle = "ID: %lld \u00b7 %s \u00b7 %s".printf(bot_id, mode, status);
                }
                row.activatable = false;
                row.selectable = false;

                // Activate/deactivate toggle button as suffix
                bool is_active = (status == "active");
                var toggle_btn = new Gtk.Button.from_icon_name(
                    is_active ? "media-playback-pause-symbolic" : "media-playback-start-symbolic");
                toggle_btn.valign = Gtk.Align.CENTER;
                toggle_btn.tooltip_text = is_active ? _("Deactivate") : _("Activate");
                toggle_btn.add_css_class("flat");
                if (!is_active) toggle_btn.add_css_class("success");
                int64 toggle_id = bot_id;
                bool toggle_active = is_active;
                toggle_btn.clicked.connect(() => {
                    toggle_bot_status.begin(toggle_id, !toggle_active);
                });
                row.add_suffix(toggle_btn);

                // Delete button as suffix
                var delete_btn = new Gtk.Button.from_icon_name("user-trash-symbolic");
                delete_btn.valign = Gtk.Align.CENTER;
                delete_btn.tooltip_text = _("Delete Botmother");
                delete_btn.add_css_class("flat");
                delete_btn.add_css_class("error");
                int64 del_id = bot_id;
                string del_name = name;
                delete_btn.clicked.connect(() => {
                    confirm_delete.begin(del_id, del_name);
                });
                row.add_suffix(delete_btn);
                bot_list.append(row);

                // Token row with copy, regenerate and revoke buttons
                if (token != null && token != "") {
                    string token_copy = token;
                    int64 token_bot_id = bot_id;

                    var token_row = new Adw.ActionRow();
                    token_row.title = token;
                    token_row.add_css_class("monospace");
                    token_row.activatable = false;
                    token_row.selectable = false;

                    // Copy button
                    var copy_btn = new Gtk.Button.from_icon_name("edit-copy-symbolic");
                    copy_btn.valign = Gtk.Align.CENTER;
                    copy_btn.tooltip_text = _("Copy token");
                    copy_btn.add_css_class("flat");
                    copy_btn.clicked.connect(() => {
                        copy_to_clipboard(token_copy);
                        copy_btn.icon_name = "emblem-ok-symbolic";
                        copy_btn.tooltip_text = _("Copied!");
                        Timeout.add(1500, () => {
                            copy_btn.icon_name = "edit-copy-symbolic";
                            copy_btn.tooltip_text = _("Copy token");
                            return false;
                        });
                    });
                    token_row.add_suffix(copy_btn);

                    // Regenerate token button
                    var regen_btn = new Gtk.Button.from_icon_name("view-refresh-symbolic");
                    regen_btn.valign = Gtk.Align.CENTER;
                    regen_btn.tooltip_text = _("Regenerate token");
                    regen_btn.add_css_class("flat");
                    regen_btn.add_css_class("warning");
                    regen_btn.clicked.connect(() => {
                        regenerate_token.begin(token_bot_id);
                    });
                    token_row.add_suffix(regen_btn);

                    // Revoke token button
                    var revoke_btn = new Gtk.Button.from_icon_name("action-unavailable-symbolic");
                    revoke_btn.valign = Gtk.Align.CENTER;
                    revoke_btn.tooltip_text = _("Revoke token");
                    revoke_btn.add_css_class("flat");
                    revoke_btn.add_css_class("error");
                    revoke_btn.clicked.connect(() => {
                        confirm_revoke.begin(token_bot_id, name);
                    });
                    token_row.add_suffix(revoke_btn);

                    bot_list.append(token_row);
                } else {
                    // No token - show generate button
                    int64 gen_bot_id = bot_id;
                    var gen_row = new Adw.ActionRow();
                    gen_row.title = _("No token");
                    gen_row.add_css_class("dim-label");
                    gen_row.activatable = false;
                    gen_row.selectable = false;

                    var gen_btn = new Gtk.Button.from_icon_name("list-add-symbolic");
                    gen_btn.valign = Gtk.Align.CENTER;
                    gen_btn.tooltip_text = _("Generate token");
                    gen_btn.add_css_class("flat");
                    gen_btn.add_css_class("suggested-action");
                    gen_btn.clicked.connect(() => {
                        regenerate_token.begin(gen_bot_id);
                    });
                    gen_row.add_suffix(gen_btn);
                    bot_list.append(gen_row);
                }
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

    private async void regenerate_token(int64 bot_id) {
        try {
            string json_body = "{\"id\":%lld}".printf(bot_id);
            var msg = new Soup.Message("POST", "http://127.0.0.1:%u/bot/token".printf(api_port));
            msg.set_request_body_from_bytes("application/json", new Bytes(json_body.data));
            Bytes response = yield http.send_and_read_async(msg, GLib.Priority.DEFAULT, null);

            if (msg.status_code == 200) {
                // Parse the new token and copy it to clipboard
                var parser = new Json.Parser();
                parser.load_from_data((string) response.get_data());
                var root = parser.get_root().get_object();
                if (root.has_member("result") && root.get_member("result").get_node_type() == Json.NodeType.OBJECT) {
                    var result = root.get_object_member("result");
                    if (result.has_member("token")) {
                        copy_to_clipboard(result.get_string_member("token"));
                    }
                }
                yield load_bots();
            } else {
                warning("BotManager: Token regeneration failed with status %u", msg.status_code);
            }
        } catch (Error e) {
            warning("BotManager: Token regeneration error: %s", e.message);
        }
    }

    private async void confirm_revoke(int64 bot_id, string bot_name) {
        var alert = new Adw.AlertDialog(
            _("Revoke Token?"),
            _("Revoke the API token for \"%s\"? The bot will be disabled and all API access will stop.").printf(bot_name)
        );
        alert.add_response("cancel", _("Cancel"));
        alert.add_response("revoke", _("Revoke"));
        alert.set_response_appearance("revoke", Adw.ResponseAppearance.DESTRUCTIVE);
        alert.default_response = "cancel";

        string response = yield alert.choose(this, null);
        if (response == "revoke") {
            yield revoke_token(bot_id);
        }
    }

    private async void revoke_token(int64 bot_id) {
        try {
            string json_body = "{\"id\":%lld}".printf(bot_id);
            var msg = new Soup.Message("POST", "http://127.0.0.1:%u/bot/revoke".printf(api_port));
            msg.set_request_body_from_bytes("application/json", new Bytes(json_body.data));
            yield http.send_and_read_async(msg, GLib.Priority.DEFAULT, null);

            if (msg.status_code == 200) {
                yield load_bots();
            } else {
                warning("BotManager: Token revoke failed with status %u", msg.status_code);
            }
        } catch (Error e) {
            warning("BotManager: Token revoke error: %s", e.message);
        }
    }

    private async void toggle_bot_status(int64 bot_id, bool new_active) {
        try {
            string json_body = "{\"id\":%lld,\"active\":%s}".printf(bot_id, new_active ? "true" : "false");
            var msg = new Soup.Message("POST", "http://127.0.0.1:%u/bot/activate".printf(api_port));
            msg.set_request_body_from_bytes("application/json", new Bytes(json_body.data));
            yield http.send_and_read_async(msg, GLib.Priority.DEFAULT, null);

            if (msg.status_code == 200) {
                yield load_bots();
            } else {
                warning("BotManager: Activate/deactivate failed with status %u", msg.status_code);
            }
        } catch (Error e) {
            warning("BotManager: Activate/deactivate error: %s", e.message);
        }
    }

    private void show_error(string detail) {
        warning("BotManager: %s", detail);
        main_stack.visible_child_name = "error";
    }

    // --- ejabberd settings ---

    private async void load_ejabberd_settings() {
        try {
            var msg = new Soup.Message("GET", "http://127.0.0.1:%u/bot/ejabberd/settings".printf(api_port));
            Bytes response = yield http.send_and_read_async(msg, GLib.Priority.DEFAULT, null);
            if (msg.status_code == 200) {
                var parser = new Json.Parser();
                parser.load_from_data((string) response.get_data());
                var root = parser.get_root().get_object();
                Json.Object data = root;
                if (root.has_member("result") && root.get_member("result").get_node_type() == Json.NodeType.OBJECT) {
                    data = root.get_object_member("result");
                }
                if (data.has_member("api_url")) ejabberd_url_entry.text = data.get_string_member("api_url");
                if (data.has_member("host")) ejabberd_host_entry.text = data.get_string_member("host");
                if (data.has_member("admin_jid")) ejabberd_admin_entry.text = data.get_string_member("admin_jid");
                // Password is masked on the server side, don't populate it unless empty
                if (data.has_member("admin_password")) {
                    string pw = data.get_string_member("admin_password");
                    if (pw != "********") {
                        ejabberd_password_entry.text = pw;
                    }
                }
                if (data.has_member("configured") && data.get_boolean_member("configured")) {
                    ejabberd_actions_row.subtitle = _("Configured");
                } else {
                    ejabberd_actions_row.subtitle = _("Not configured");
                }
            }
        } catch (Error e) {
            warning("BotManager: Failed to load ejabberd settings: %s", e.message);
        }
    }

    private async void save_ejabberd_settings() {
        try {
            var builder = new Json.Builder();
            builder.begin_object();
            builder.set_member_name("api_url");
            builder.add_string_value(ejabberd_url_entry.text.strip());
            builder.set_member_name("host");
            builder.add_string_value(ejabberd_host_entry.text.strip());
            builder.set_member_name("admin_jid");
            builder.add_string_value(ejabberd_admin_entry.text.strip());
            string pw = ejabberd_password_entry.text.strip();
            if (pw != "") {
                builder.set_member_name("admin_password");
                builder.add_string_value(pw);
            }
            builder.end_object();

            var gen = new Json.Generator();
            gen.root = builder.get_root();
            string body = gen.to_data(null);

            var msg = new Soup.Message("POST", "http://127.0.0.1:%u/bot/ejabberd/settings".printf(api_port));
            msg.set_request_body_from_bytes("application/json", new Bytes(body.data));
            yield http.send_and_read_async(msg, GLib.Priority.DEFAULT, null);

            if (msg.status_code == 200) {
                ejabberd_actions_row.subtitle = _("Saved");
                Timeout.add(2000, () => {
                    load_ejabberd_settings.begin();
                    return false;
                });
            } else {
                ejabberd_actions_row.subtitle = _("Save failed");
            }
        } catch (Error e) {
            warning("BotManager: Failed to save ejabberd settings: %s", e.message);
            ejabberd_actions_row.subtitle = _("Error: %s").printf(e.message);
        }
    }

    private async void test_ejabberd_connection() {
        ejabberd_actions_row.subtitle = _("Testing...");
        ejabberd_test_button.sensitive = false;
        try {
            var msg = new Soup.Message("POST", "http://127.0.0.1:%u/bot/ejabberd/test".printf(api_port));
            msg.set_request_body_from_bytes("application/json", new Bytes("{}".data));
            Bytes response = yield http.send_and_read_async(msg, GLib.Priority.DEFAULT, null);

            if (msg.status_code == 200) {
                var parser = new Json.Parser();
                parser.load_from_data((string) response.get_data());
                var root = parser.get_root().get_object();
                Json.Object data = root;
                if (root.has_member("result") && root.get_member("result").get_node_type() == Json.NodeType.OBJECT) {
                    data = root.get_object_member("result");
                }
                string resp = data.has_member("response") ? data.get_string_member("response") : "ok";
                ejabberd_actions_row.subtitle = _("Connected: %s").printf(resp);
            } else {
                var parser = new Json.Parser();
                parser.load_from_data((string) response.get_data());
                var root = parser.get_root().get_object();
                string err = root.has_member("description") ? root.get_string_member("description") : "Connection failed";
                ejabberd_actions_row.subtitle = _("Failed: %s").printf(err);
            }
        } catch (Error e) {
            ejabberd_actions_row.subtitle = _("Error: %s").printf(e.message);
        }
        ejabberd_test_button.sensitive = true;
    }

    // Reliable clipboard copy that works from Adw.Dialog on X11
    private void copy_to_clipboard(string text) {
        try {
            // Write token to temp file, then use xclip to read it
            string tmp_path = Path.build_filename(Environment.get_tmp_dir(), "dinox_clip_%d".printf(Posix.getpid()));
            FileUtils.set_contents(tmp_path, text);
            string[] argv = { "/bin/sh", "-c", "xclip -selection clipboard < " + tmp_path + " && rm -f " + tmp_path };
            Process.spawn_async(null, argv, null, SpawnFlags.SEARCH_PATH, null, null);
        } catch (Error e) {
            warning("Clipboard copy failed: %s", e.message);
        }
    }
}

}
