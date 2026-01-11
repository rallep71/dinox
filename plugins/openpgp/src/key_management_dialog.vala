/*
 * Copyright (C) 2025 Ralf Peter <dinox@handwerker.jetzt>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

using Gtk;
using Adw;

namespace Dino.Plugins.OpenPgp {

/**
 * Simple key info structure parsed from GPG output
 */
public class GpgKeyInfo {
    public string fingerprint;
    public string uid;
    public string email;
    public int64 created_timestamp;
    public string expires;
    
    public GpgKeyInfo(string fpr, string uid_str, int64 created = 0) {
        this.fingerprint = fpr;
        this.uid = uid_str;
        this.created_timestamp = created;
        
        // Extract email from uid (format: "Name <email>")
        if (uid_str.contains("<") && uid_str.contains(">")) {
            int start = uid_str.index_of("<") + 1;
            int end = uid_str.index_of(">");
            this.email = uid_str.substring(start, end - start);
        } else {
            this.email = "";
        }
    }
}

/**
 * Dialog for managing OpenPGP keys - generate, import, export, delete.
 * Uses GPG command line for reliability.
 */
public class KeyManagementDialog : Object {

    private Adw.Dialog dialog;
    private Gtk.Window parent_window;
    private Adw.PreferencesGroup keys_group;
    private Gee.List<GpgKeyInfo> current_keys;

    public signal void keys_changed();

    public KeyManagementDialog(Gtk.Window parent) {
        this.parent_window = parent;
        this.current_keys = new Gee.ArrayList<GpgKeyInfo>();
    }

    public void present() {
        dialog = new Adw.Dialog();
        dialog.title = _("OpenPGP Key Management");
        dialog.content_width = 500;
        dialog.content_height = 600;

        var toolbar_view = new Adw.ToolbarView();
        
        var header = new Adw.HeaderBar();
        toolbar_view.add_top_bar(header);

        var content_page = new Adw.PreferencesPage();
        
        // Actions group
        var actions_group = new Adw.PreferencesGroup();
        actions_group.title = _("Actions");
        
        // Generate Key button - use activatable_widget for proper click handling
        var generate_row = new Adw.ActionRow();
        generate_row.title = _("Generate New Key");
        generate_row.subtitle = _("Create a new OpenPGP key pair");
        var gen_icon = new Gtk.Image.from_icon_name("list-add-symbolic");
        generate_row.add_suffix(gen_icon);
        var gen_btn = new Gtk.Button();
        gen_btn.add_css_class("flat");
        gen_btn.child = new Gtk.Image.from_icon_name("go-next-symbolic");
        gen_btn.valign = Gtk.Align.CENTER;
        gen_btn.clicked.connect(() => {
            debug("Generate clicked!");
            show_generate_dialog();
        });
        generate_row.add_suffix(gen_btn);
        generate_row.activatable_widget = gen_btn;
        actions_group.add(generate_row);
        
        // Import Key button
        var import_row = new Adw.ActionRow();
        import_row.title = _("Import Key");
        import_row.subtitle = _("Import a key from file (.asc, .gpg)");
        var imp_icon = new Gtk.Image.from_icon_name("document-open-symbolic");
        import_row.add_suffix(imp_icon);
        var imp_btn = new Gtk.Button();
        imp_btn.add_css_class("flat");
        imp_btn.child = new Gtk.Image.from_icon_name("go-next-symbolic");
        imp_btn.valign = Gtk.Align.CENTER;
        imp_btn.clicked.connect(() => {
            debug("Import clicked!");
            show_import_dialog();
        });
        import_row.add_suffix(imp_btn);
        import_row.activatable_widget = imp_btn;
        actions_group.add(import_row);
        
        content_page.add(actions_group);
        
        // Keys list group
        keys_group = new Adw.PreferencesGroup();
        keys_group.title = _("Your Keys");
        keys_group.description = _("Private keys available for signing and decryption");
        content_page.add(keys_group);
        
        toolbar_view.content = content_page;
        dialog.child = toolbar_view;
        
        // Load keys
        load_keys.begin();
        
        dialog.present(parent_window);
    }

    private async void load_keys() {
        current_keys.clear();
        
        // Use GPG command to get keys with proper info
        try {
            string[] argv = { "gpg", "--list-secret-keys", "--with-colons" };
            
            var proc = new Subprocess.newv(argv, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
            string? stdout_str = null;
            string? stderr_str = null;
            
            yield proc.communicate_utf8_async(null, null, out stdout_str, out stderr_str);
            
            if (proc.get_exit_status() == 0 && stdout_str != null) {
                parse_gpg_output(stdout_str);
            }
        } catch (Error e) {
            warning("Error listing GPG keys: %s", e.message);
        }
        
        // Display keys
        if (current_keys.size == 0) {
            var empty_row = new Adw.ActionRow();
            empty_row.title = _("No private keys found");
            empty_row.subtitle = _("Generate or import a key to get started");
            empty_row.add_prefix(new Gtk.Image.from_icon_name("dialog-information-symbolic"));
            keys_group.add(empty_row);
        } else {
            foreach (var key in current_keys) {
                add_key_row(key);
            }
        }
    }
    
    private void parse_gpg_output(string output) {
        string? current_fpr = null;
        int64 current_created = 0;
        bool in_main_key = false;  // Track if we're processing a main key (sec), not subkey (ssb)
        
        foreach (var line in output.split("\n")) {
            var parts = line.split(":");
            if (parts.length < 2) continue;
            
            if (parts[0] == "sec") {
                // Secret key line - start of a new main key
                in_main_key = true;
                current_fpr = null;
                current_created = 0;
                if (parts.length > 5 && parts[5].length > 0) {
                    current_created = int64.parse(parts[5]);
                }
            } else if (parts[0] == "ssb") {
                // Subkey line - ignore subkeys, they belong to the main key
                in_main_key = false;
            } else if (parts[0] == "fpr" && in_main_key && current_fpr == null) {
                // First fingerprint after sec is the main key fingerprint
                if (parts.length > 9 && parts[9].length > 0) {
                    current_fpr = parts[9];
                }
            } else if (parts[0] == "uid" && current_fpr != null) {
                // UID is in field index 9
                if (parts.length > 9) {
                    string uid = parts[9];
                    if (uid.length > 0) {
                        current_keys.add(new GpgKeyInfo(current_fpr, uid, current_created));
                        current_fpr = null; // Only take first UID per key
                    }
                }
            }
        }
        
        // Sort by creation timestamp, newest first
        current_keys.sort((a, b) => {
            if (b.created_timestamp > a.created_timestamp) return 1;
            if (b.created_timestamp < a.created_timestamp) return -1;
            return 0;
        });
    }

    private void add_key_row(GpgKeyInfo key) {
        var row = new Adw.ExpanderRow();
        
        // Don't escape - use_markup = false handles it
        row.title = key.uid;
        row.subtitle = key.fingerprint.substring(key.fingerprint.length - 16);
        row.use_markup = false;
        
        var icon = new Gtk.Image.from_icon_name("channel-secure-symbolic");
        row.add_prefix(icon);
        
        // Fingerprint row
        var fp_row = new Adw.ActionRow();
        fp_row.title = _("Fingerprint");
        var fp_label = new Gtk.Label(format_fingerprint(key.fingerprint));
        fp_label.add_css_class("monospace");
        fp_label.add_css_class("dim-label");
        fp_label.selectable = true;
        fp_label.wrap = true;
        fp_label.xalign = 1;
        fp_row.add_suffix(fp_label);
        row.add_row(fp_row);
        
        // Export button row
        var export_row = new Adw.ActionRow();
        export_row.title = _("Export Public Key");
        export_row.activatable = true;
        export_row.add_suffix(new Gtk.Image.from_icon_name("document-save-symbolic"));
        export_row.activated.connect(() => export_key(key));
        row.add_row(export_row);
        
        // Delete button row
        var delete_row = new Adw.ActionRow();
        delete_row.title = _("Delete Key");
        delete_row.add_css_class("error");
        delete_row.activatable = true;
        delete_row.add_suffix(new Gtk.Image.from_icon_name("user-trash-symbolic"));
        delete_row.activated.connect(() => confirm_delete_key(key));
        row.add_row(delete_row);
        
        keys_group.add(row);
    }

    private string format_fingerprint(string fpr) {
        var sb = new StringBuilder();
        for (int i = 0; i < fpr.length; i++) {
            sb.append_c(fpr[i]);
            if ((i + 1) % 4 == 0 && i < fpr.length - 1) {
                sb.append(" ");
            }
        }
        return sb.str;
    }

    private void show_generate_dialog() {
        var gen_dialog = new Adw.AlertDialog(
            _("Generate New OpenPGP Key"),
            _("Enter your details to create a new key pair.")
        );
        
        var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
        box.margin_start = 24;
        box.margin_end = 24;
        
        // Name
        var name_label = new Gtk.Label(_("Name"));
        name_label.xalign = 0;
        box.append(name_label);
        
        var name_entry = new Gtk.Entry();
        name_entry.placeholder_text = _("Your Name");
        box.append(name_entry);
        
        // Email
        var email_label = new Gtk.Label(_("Email"));
        email_label.xalign = 0;
        email_label.margin_top = 8;
        box.append(email_label);
        
        var email_entry = new Gtk.Entry();
        email_entry.placeholder_text = _("you@example.com");
        box.append(email_entry);
        
        // Passphrase
        var pass_label = new Gtk.Label(_("Passphrase (optional)"));
        pass_label.xalign = 0;
        pass_label.margin_top = 8;
        box.append(pass_label);
        
        var pass_entry = new Gtk.PasswordEntry();
        pass_entry.show_peek_icon = true;
        box.append(pass_entry);
        
        var info_label = new Gtk.Label(_("4096-bit RSA key, valid for 2 years."));
        info_label.add_css_class("dim-label");
        info_label.margin_top = 12;
        box.append(info_label);
        
        gen_dialog.extra_child = box;
        
        gen_dialog.add_response("cancel", _("Cancel"));
        gen_dialog.add_response("generate", _("Generate"));
        gen_dialog.set_response_appearance("generate", Adw.ResponseAppearance.SUGGESTED);
        gen_dialog.default_response = "generate";
        gen_dialog.close_response = "cancel";
        
        gen_dialog.response.connect((response) => {
            if (response == "generate") {
                string name = name_entry.text.strip();
                string email = email_entry.text.strip();
                string passphrase = pass_entry.text;
                
                if (name.length < 2) {
                    show_message(_("Error"), _("Name must be at least 2 characters"));
                    return;
                }
                if (!email.contains("@")) {
                    show_message(_("Error"), _("Please enter a valid email address"));
                    return;
                }
                
                generate_key(name, email, passphrase);
            }
        });
        
        gen_dialog.present(dialog);
    }

    private Adw.AlertDialog? progress_dialog;

    private void generate_key(string name, string email, string passphrase) {
        // Show progress dialog with spinner
        progress_dialog = new Adw.AlertDialog(
            _("Generating Key..."),
            _("Please wait while your key is being generated. This may take a moment.")
        );
        
        var spinner = new Gtk.Spinner();
        spinner.spinning = true;
        spinner.set_size_request(48, 48);
        spinner.halign = Gtk.Align.CENTER;
        spinner.margin_top = 12;
        spinner.margin_bottom = 12;
        progress_dialog.extra_child = spinner;
        
        // No close button - user must wait
        progress_dialog.present(dialog);
        
        // Prepare batch file
        try {
            var batch = new StringBuilder();
            batch.append("Key-Type: RSA\n");
            batch.append("Key-Length: 4096\n");
            batch.append("Subkey-Type: RSA\n");
            batch.append("Subkey-Length: 4096\n");
            batch.append(@"Name-Real: $name\n");
            batch.append(@"Name-Email: $email\n");
            batch.append("Expire-Date: 2y\n");
            if (passphrase.length > 0) {
                batch.append(@"Passphrase: $passphrase\n");
            } else {
                batch.append("%no-protection\n");
            }
            batch.append("%commit\n");
            
            string batch_path = Path.build_filename(Environment.get_tmp_dir(), "dinox-gpg-batch");
            FileUtils.set_contents(batch_path, batch.str);
            
            // Run GPG async
            string[] argv = { "gpg", "--batch", "--gen-key", batch_path };
            var subprocess = new Subprocess.newv(argv, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
            
            subprocess.wait_async.begin(null, (obj, res) => {
                try {
                    subprocess.wait_async.end(res);
                    FileUtils.remove(batch_path);
                    
                    // Close progress dialog
                    if (progress_dialog != null) {
                        progress_dialog.force_close();
                        progress_dialog = null;
                    }
                    
                    if (subprocess.get_successful()) {
                        keys_changed();
                        dialog.force_close();
                        show_message(_("Success"), _("Key generated successfully!"));
                    } else {
                        show_message(_("Error"), _("Failed to generate key."));
                    }
                } catch (Error e) {
                    if (progress_dialog != null) {
                        progress_dialog.force_close();
                        progress_dialog = null;
                    }
                    show_message(_("Error"), e.message);
                }
            });
        } catch (Error e) {
            if (progress_dialog != null) {
                progress_dialog.force_close();
                progress_dialog = null;
            }
            show_message(_("Error"), e.message);
        }
    }

    private void show_import_dialog() {
        var file_dialog = new Gtk.FileDialog();
        file_dialog.title = _("Import OpenPGP Key");
        
        var filters = new GLib.ListStore(typeof(Gtk.FileFilter));
        
        var key_filter = new Gtk.FileFilter();
        key_filter.name = _("OpenPGP Keys (*.asc, *.gpg)");
        key_filter.add_pattern("*.asc");
        key_filter.add_pattern("*.gpg");
        key_filter.add_pattern("*.pgp");
        filters.append(key_filter);
        
        var all_filter = new Gtk.FileFilter();
        all_filter.name = _("All Files");
        all_filter.add_pattern("*");
        filters.append(all_filter);
        
        file_dialog.filters = filters;
        file_dialog.default_filter = key_filter;
        
        file_dialog.open.begin(parent_window, null, (obj, res) => {
            try {
                var file = file_dialog.open.end(res);
                if (file != null) {
                    import_key_from_file.begin(file.get_path());
                }
            } catch (Error e) {
                // User cancelled
            }
        });
    }

    private async void import_key_from_file(string path) {
        try {
            string[] argv = { "gpg", "--import", path };
            
            var proc = new Subprocess.newv(argv, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
            string? stdout_str = null;
            string? stderr_str = null;
            
            yield proc.communicate_utf8_async(null, null, out stdout_str, out stderr_str);
            
            if (proc.get_exit_status() == 0) {
                keys_changed();
                dialog.force_close();
                show_message(_("Success"), _("Key imported! Re-open Key Management to see it."));
            } else {
                show_message(_("Error"), _("Import failed: ") + (stderr_str ?? ""));
            }
        } catch (Error e) {
            show_message(_("Error"), e.message);
        }
    }

    private void export_key(GpgKeyInfo key) {
        var file_dialog = new Gtk.FileDialog();
        file_dialog.title = _("Export Public Key");
        file_dialog.initial_name = key.email.replace("@", "_") + "_public.asc";
        
        file_dialog.save.begin(parent_window, null, (obj, res) => {
            try {
                var file = file_dialog.save.end(res);
                if (file != null) {
                    export_key_to_file.begin(key, file.get_path());
                }
            } catch (Error e) {
                // User cancelled
            }
        });
    }

    private async void export_key_to_file(GpgKeyInfo key, string path) {
        try {
            string[] argv = { "gpg", "--armor", "--export", key.fingerprint };
            
            var proc = new Subprocess.newv(argv, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
            string? stdout_str = null;
            string? stderr_str = null;
            
            yield proc.communicate_utf8_async(null, null, out stdout_str, out stderr_str);
            
            if (proc.get_exit_status() == 0 && stdout_str != null && stdout_str.length > 0) {
                try {
                    // Use File.replace_contents_async correctly
                    File f = File.new_for_path(path);
                    yield f.replace_contents_async(stdout_str.data, null, false, FileCreateFlags.NONE, null, null);
                    show_message(_("Success"), _("Key exported to: ") + path);
                } catch (Error e) {
                    show_message(_("Error"), e.message);
                }
            } else {
                show_message(_("Error"), _("Export failed."));
            }
        } catch (Error e) {
            show_message(_("Error"), e.message);
        }
    }

    private void confirm_delete_key(GpgKeyInfo key) {
        var confirm = new Adw.AlertDialog(_("Delete Key?"), 
            _("Delete this key?\n\n%s\n\nThis cannot be undone!").printf(key.uid));
        
        confirm.add_response("cancel", _("Cancel"));
        confirm.add_response("delete", _("Delete"));
        confirm.set_response_appearance("delete", Adw.ResponseAppearance.DESTRUCTIVE);
        confirm.default_response = "cancel";
        confirm.close_response = "cancel";
        
        confirm.response.connect((response) => {
            if (response == "delete") {
                delete_key.begin(key);
            }
        });
        
        confirm.present(dialog);
    }

    private async void delete_key(GpgKeyInfo key) {
        try {
            string[] argv = { "gpg", "--batch", "--yes", "--delete-secret-and-public-key", key.fingerprint };
            
            var proc = new Subprocess.newv(argv, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
            string? stdout_str = null;
            string? stderr_str = null;

            yield proc.communicate_utf8_async(null, null, out stdout_str, out stderr_str);
            
            if (proc.get_exit_status() == 0) {
                keys_changed();
                dialog.force_close();
                show_message(_("Success"), _("Key deleted."));
            } else {
                show_message(_("Error"), _("Delete failed: ") + (stderr_str ?? ""));
            }
        } catch (Error e) {
            show_message(_("Error"), e.message);
        }
    }

    private void show_message(string title, string message) {
        var msg = new Adw.AlertDialog(title, message);
        msg.add_response("ok", _("OK"));
        msg.default_response = "ok";
        msg.close_response = "ok";
        msg.present(parent_window);
    }
}

}
