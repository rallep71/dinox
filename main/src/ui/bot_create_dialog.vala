/*
 * Copyright (C) 2025 Ralf Peter <dinox@handwerker.jetzt>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

using Gtk;

namespace Dino.Ui {

[GtkTemplate (ui = "/im/github/rallep71/DinoX/bot_create_dialog.ui")]
public class BotCreateDialog : Adw.Dialog {

    [GtkChild] private unowned Gtk.Stack content_stack;
    [GtkChild] private unowned Gtk.Button cancel_button;
    [GtkChild] private unowned Gtk.Button create_button;
    [GtkChild] private unowned Adw.EntryRow name_entry;
    [GtkChild] private unowned Adw.ComboRow mode_combo;
    [GtkChild] private unowned Adw.EntryRow webhook_entry;
    [GtkChild] private unowned Gtk.Label token_label;
    [GtkChild] private unowned Gtk.Button copy_token_button;
    [GtkChild] private unowned Gtk.Label mode_description;

    public signal void bot_created();

    private Soup.Session http;
    private uint16 api_port = 7842;
    private string? created_token = null;

    // Mode values sent to API
    private const string[] MODE_KEYS = { "personal", "dedicated", "cloud" };
    private const string[] MODE_LABELS = {
        "Personal Bot",
        "Dedicated Bot Account",
        "DinoX Bot Server"
    };
    private const string[] MODE_DESCRIPTIONS = {
        "Botmother uses your XMPP account to send and receive messages via the local API on port 7842.",
        "Creates a dedicated XMPP account for the bot on your server. Requires server admin access.",
        "Hosted on bots.dinox.im. The bot runs on our server. (Coming soon)"
    };

    public string account_jid { get; set; default = ""; }

    construct {
        http = new Soup.Session();

        // Setup mode combo with 3 modes
        var mode_model = new Gtk.StringList(null);
        for (int i = 0; i < MODE_LABELS.length; i++) {
            mode_model.append(MODE_LABELS[i]);
        }
        mode_combo.model = mode_model;
        mode_combo.selected = 0;

        // Update description when mode changes
        mode_combo.notify["selected"].connect(() => {
            uint sel = mode_combo.selected;
            if (sel < MODE_DESCRIPTIONS.length) {
                mode_description.label = MODE_DESCRIPTIONS[sel];
            }
        });

        // Enable create button when name is not empty
        name_entry.changed.connect(() => {
            create_button.sensitive = name_entry.text.strip() != "";
        });

        cancel_button.clicked.connect(() => {
            if (created_token != null) {
                bot_created();
            }
            close();
        });

        create_button.clicked.connect(() => {
            do_create.begin();
        });

        copy_token_button.clicked.connect(() => {
            if (created_token != null) {
                var clipboard = copy_token_button.get_clipboard();
                clipboard.set_text(created_token);
                copy_token_button.label = "Copied!";
                GLib.Timeout.add(2000, () => {
                    copy_token_button.label = "Copy Token";
                    return false;
                });
            }
        });
    }

    private async void do_create() {
        string name = name_entry.text.strip();
        if (name == "") return;

        // Get selected mode
        uint sel = mode_combo.selected;
        string mode = (sel < MODE_KEYS.length) ? MODE_KEYS[sel] : "personal";

        content_stack.visible_child_name = "creating";
        create_button.sensitive = false;

        try {
            // Build JSON body
            var builder = new Json.Builder();
            builder.begin_object();
            builder.set_member_name("name");
            builder.add_string_value(name);
            builder.set_member_name("mode");
            builder.add_string_value(mode);
            if (account_jid != "") {
                builder.set_member_name("account");
                builder.add_string_value(account_jid);
            }
            string webhook = webhook_entry.text.strip();
            if (webhook != "") {
                builder.set_member_name("webhook_url");
                builder.add_string_value(webhook);
            }
            builder.end_object();

            var gen = new Json.Generator();
            gen.root = builder.get_root();
            string body = gen.to_data(null);

            var msg = new Soup.Message("POST", "http://127.0.0.1:%u/bot/create".printf(api_port));
            msg.set_request_body_from_bytes("application/json", new GLib.Bytes(body.data));
            Bytes response = yield http.send_and_read_async(msg, GLib.Priority.DEFAULT, null);

            if (msg.status_code == 200) {
                var parser = new Json.Parser();
                parser.load_from_data((string) response.get_data());
                var root = parser.get_root().get_object();

                // Response wrapped by send_success: {"ok":true,"result":{...}}
                Json.Object result_obj = root;
                if (root.has_member("result")) {
                    var result_node = root.get_member("result");
                    if (result_node.get_node_type() == Json.NodeType.OBJECT) {
                        result_obj = result_node.get_object();
                    }
                }

                if (result_obj.has_member("token")) {
                    created_token = result_obj.get_string_member("token");
                    token_label.label = created_token;
                } else {
                    token_label.label = "(token not returned)";
                }

                cancel_button.label = "Done";
                create_button.visible = false;
                content_stack.visible_child_name = "success";
            } else {
                warning("Botmother: API returned %u", msg.status_code);
                content_stack.visible_child_name = "form";
                create_button.sensitive = true;
            }
        } catch (Error e) {
            warning("Botmother: Create error: %s", e.message);
            content_stack.visible_child_name = "form";
            create_button.sensitive = true;
        }
    }
}

}
