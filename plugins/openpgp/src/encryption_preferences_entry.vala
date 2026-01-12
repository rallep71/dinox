using Adw;
using Dino.Entities;
using Gtk;

namespace Dino.Plugins.OpenPgp {

    public class PgpPreferencesEntry : Plugins.EncryptionPreferencesEntry {

        private Plugin plugin;
        private Account? current_account;
        private Gtk.ListBox? list_box;
        private KeyManagementDialog? key_dialog;
        private ulong keys_changed_handler_id = 0;
        private Gee.List<GPG.Key>? cached_keys = null;

        public PgpPreferencesEntry(Plugin plugin) {
            this.plugin = plugin;
        }

        public override Object? get_widget(Account account, WidgetType type) {
            if (type != WidgetType.GTK4) return null;
            current_account = account;
            var group = new Adw.PreferencesGroup() { title="OpenPGP" };
            list_box = new Gtk.ListBox();
            list_box.selection_mode = Gtk.SelectionMode.NONE;
            list_box.add_css_class("boxed-list");
            group.add(list_box);
            build_ui.begin();
            return group;
        }

        public override string id { get { return "pgp_preferences_encryption"; }}

        private void clear_list() {
            if (list_box == null) return;
            Gtk.Widget? child = list_box.get_first_child();
            while (child != null) {
                Gtk.Widget? next = child.get_next_sibling();
                list_box.remove(child);
                child = next;
            }
        }

        private async void build_ui() {
            if (list_box == null || current_account == null) return;
            clear_list();
            cached_keys = yield get_pgp_keys();

            if (cached_keys == null) {
                list_box.append(new Adw.ActionRow() { title=_("Announce key"), subtitle=_("Error in GnuPG") });
                add_manage_button();
                return;
            }
            
            if (cached_keys.size == 0) {
                list_box.append(new Adw.ActionRow() { title=_("Announce key"), subtitle=_("No keys available. Generate or import one!") });
                add_manage_button();
                return;
            }

            var select_row = new Adw.ActionRow();
            select_row.title = _("Announce key");
            select_row.activatable = true;
            select_row.add_suffix(new Gtk.Image.from_icon_name("go-next-symbolic"));
            
            string current_key_id = plugin.db.get_account_key(current_account);
            if (current_key_id == null || current_key_id == "") {
                select_row.subtitle = _("Disabled");
            } else {
                foreach (var key in cached_keys) {
                    if (key.fpr == current_key_id && key.uids.length > 0) {
                        select_row.subtitle = key.uids[0].uid;
                        break;
                    }
                }
                if (select_row.subtitle == null) {
                    select_row.subtitle = current_key_id.substring(current_key_id.length - 16);
                }
            }
            
            select_row.activated.connect(() => { show_key_selection_dialog(); });
            list_box.append(select_row);
            add_manage_button();
        }

        private void show_key_selection_dialog() {
            if (list_box == null || cached_keys == null) return;
            
            Gtk.Window? parent_window = null;
            var widget = list_box as Gtk.Widget;
            while (widget != null && !(widget is Gtk.Window)) {
                widget = widget.get_parent();
            }
            if (widget is Gtk.Window) parent_window = (Gtk.Window)widget;
            if (parent_window == null) return;

            var dialog = new Adw.AlertDialog(_("Select OpenPGP Key"), _("Choose a key to announce to your contacts."));
            dialog.add_response("cancel", _("Cancel"));
            dialog.add_response("ok", _("OK"));
            dialog.default_response = "ok";
            dialog.close_response = "cancel";
            
            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
            box.margin_start = 12;
            box.margin_end = 12;
            
            Gtk.CheckButton? first_radio = null;
            string current_key_id = plugin.db.get_account_key(current_account);
            
            var disabled_radio = new Gtk.CheckButton.with_label(_("Disabled"));
            if (current_key_id == null || current_key_id == "") disabled_radio.active = true;
            first_radio = disabled_radio;
            box.append(disabled_radio);
            
            // Get key names from GPG CLI since GPGME doesn't always return UIDs
            var key_names = get_key_names_from_gpg();
            
            foreach (var key in cached_keys) {
                // Get name from our map, or use fingerprint as fallback
                string name = key_names.get(key.fpr);
                if (name == null || name == "") {
                    name = key.fpr.substring(key.fpr.length - 16);
                }
                
                // Create radio with name and short fingerprint
                string short_fpr = key.fpr.substring(key.fpr.length - 16);
                
                var radio = new Gtk.CheckButton();
                var label_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
                var name_label = new Gtk.Label(name);
                name_label.xalign = 0;
                name_label.add_css_class("heading");
                var fpr_label = new Gtk.Label(format_fpr_short(short_fpr));
                fpr_label.xalign = 0;
                fpr_label.add_css_class("dim-label");
                fpr_label.add_css_class("monospace");
                label_box.append(name_label);
                label_box.append(fpr_label);
                radio.child = label_box;
                
                radio.set_group(first_radio);
                radio.set_data<string>("key_fpr", key.fpr);
                if (key.fpr == current_key_id) radio.active = true;
                radio.margin_top = 8;
                box.append(radio);
            }
            
            var pw_label = new Gtk.Label(_("Enter GPG passphrase to confirm:"));
            pw_label.xalign = 0;
            pw_label.margin_top = 16;
            box.append(pw_label);
            
            var pw_entry = new Gtk.PasswordEntry();
            pw_entry.show_peek_icon = true;
            pw_entry.placeholder_text = _("Passphrase");
            box.append(pw_entry);
            
            var error_label = new Gtk.Label("");
            error_label.add_css_class("error");
            error_label.visible = false;
            box.append(error_label);
            
            dialog.extra_child = box;
            
            dialog.response.connect((response) => {
                if (response == "ok") {
                    string? new_key_fpr = null;
                    var child = box.get_first_child();
                    while (child != null) {
                        if (child is Gtk.CheckButton) {
                            var cb = (Gtk.CheckButton)child;
                            if (cb.active) {
                                new_key_fpr = cb.get_data<string>("key_fpr");
                                break;
                            }
                        }
                        child = child.get_next_sibling();
                    }
                    
                    if (new_key_fpr == null) {
                        save_key_selection("");
                        return;
                    }
                    
                    string passphrase = pw_entry.text;
                    verify_passphrase_and_save.begin(new_key_fpr, passphrase, error_label, dialog);
                }
            });
            
            dialog.present(parent_window);
        }
        
        private async void verify_passphrase_and_save(string key_fpr, string passphrase, Gtk.Label error_label, Adw.AlertDialog dialog) {
            bool success = false;
            SourceFunc callback = verify_passphrase_and_save.callback;
            
            new Thread<void*>(null, () => {
                try {
                    // Use Subprocess to avoid shell injection
                    // Note: Passphrase is still visible in process list, but RCE is prevented.
                    string[] argv = {
                        "gpg", "--batch", "--yes", "--pinentry-mode", "loopback", 
                        "--passphrase", passphrase, 
                        "-u", key_fpr, 
                        "--sign", "--armor", "-o", "/dev/null"
                    };

                    Subprocess proc = new Subprocess.newv(argv, SubprocessFlags.STDIN_PIPE);
                    proc.communicate_utf8("test", null, null, null);
                    
                    success = proc.get_successful();
                } catch (Error e) { warning(e.message); }
                Idle.add((owned)callback);
                return null;
            });
            yield;
            
            if (success) {
                save_key_selection(key_fpr);
                dialog.force_close();
            } else {
                error_label.label = _("Wrong passphrase");
                error_label.visible = true;
            }
        }
        
        private void save_key_selection(string key_fpr) {
            if (plugin.modules.has_key(current_account)) plugin.modules[current_account].set_private_key_id(key_fpr);
            plugin.db.set_account_key(current_account, key_fpr);
            build_ui.begin();
        }

        private void add_manage_button() {
            var manage_row = new Adw.ActionRow();
            manage_row.title = _("Manage Keys");
            manage_row.subtitle = _("Generate, import, export, or delete keys");
            manage_row.activatable = true;
            manage_row.add_suffix(new Gtk.Image.from_icon_name("go-next-symbolic"));
            manage_row.activated.connect(() => { open_key_dialog(); });
            list_box.append(manage_row);
        }

        private void on_keys_changed() { build_ui.begin(); }

        private void open_key_dialog() {
            if (list_box == null) return;
            Gtk.Window? parent_window = null;
            var widget = list_box as Gtk.Widget;
            while (widget != null && !(widget is Gtk.Window)) widget = widget.get_parent();
            if (widget is Gtk.Window) parent_window = (Gtk.Window)widget;
            if (parent_window != null) {
                if (key_dialog != null && keys_changed_handler_id > 0) { key_dialog.disconnect(keys_changed_handler_id); keys_changed_handler_id = 0; }
                key_dialog = new KeyManagementDialog(parent_window);
                keys_changed_handler_id = key_dialog.keys_changed.connect(() => { on_keys_changed(); });
                key_dialog.present();
            }
        }

        private static async Gee.List<GPG.Key> get_pgp_keys() {
            Gee.List<GPG.Key> keys = null;
            SourceFunc callback = get_pgp_keys.callback;
            new Thread<void*> (null, () => {
                try { keys = GPGHelper.get_keylist(null, true); } catch (Error e) { warning(e.message); }
                Idle.add((owned)callback);
                return null;
            });
            yield;
            return keys;
        }
        
        private Gee.HashMap<string, string> get_key_names_from_gpg() {
            var map = new Gee.HashMap<string, string>();
            try {
                string stdout_str, stderr_str;
                int exit_status;
                Process.spawn_command_line_sync("gpg --list-secret-keys --with-colons",
                    out stdout_str, out stderr_str, out exit_status);
                
                if (exit_status == 0) {
                    string? current_fpr = null;
                    bool expect_fpr = false;
                    
                    foreach (string line in stdout_str.split("\n")) {
                        if (line.has_prefix("sec:")) {
                            expect_fpr = true;
                            current_fpr = null;
                        } else if (line.has_prefix("ssb:") || line.has_prefix("sub:")) {
                            expect_fpr = false;
                        } else if (line.has_prefix("fpr:") && expect_fpr && current_fpr == null) {
                            var parts = line.split(":");
                            if (parts.length > 9) {
                                current_fpr = parts[9];
                            }
                        } else if (line.has_prefix("uid:") && current_fpr != null) {
                            var parts = line.split(":");
                            if (parts.length > 9 && parts[9].length > 0) {
                                map.set(current_fpr, parts[9]);
                                current_fpr = null; // Only take first UID
                            }
                        }
                    }
                }
            } catch (Error e) {
                warning("Error getting key names: %s", e.message);
            }
            return map;
        }
        
        private string format_fpr_short(string fpr) {
            var sb = new StringBuilder();
            for (int i = 0; i < fpr.length; i++) {
                sb.append_c(fpr[i]);
                if ((i + 1) % 4 == 0 && i < fpr.length - 1) {
                    sb.append(" ");
                }
            }
            return sb.str;
        }
    }
}
