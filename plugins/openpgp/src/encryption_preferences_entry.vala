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
        // private Gee.List<GPG.Key>? cached_keys = null;
        private Gee.List<GpgKeyInfo>? cached_keys = null;

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
            
            // Add loading placeholder immediately
            var loading_row = new Adw.ActionRow();
            loading_row.title = _("Loading keys...");
            loading_row.add_prefix(new Gtk.Spinner() { spinning = true });
            list_box.append(loading_row);
            
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
                    if (key.fingerprint == current_key_id) {
                        // Escape markup in UID to prevent GTK warnings about invalid XML
                        string escaped_uid = GLib.Markup.escape_text(key.uid);
                        // Adw.ActionRow.subtitle treats text as Pango markup.
                        // We MUST escape it to avoid "Failed to set text ... from markup" errors when UID contains <email>.
                        select_row.subtitle = escaped_uid;
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
            // var key_names = get_key_names_from_gpg();
            
            foreach (var key in cached_keys) {
                // Get name from our map, or use fingerprint as fallback
                string name = key.uid;
                if (name == null || name == "") {
                    name = key.fingerprint.substring(key.fingerprint.length - 16);
                }
                
                // Create radio with name and short fingerprint
                string short_fpr = key.fingerprint.substring(key.fingerprint.length - 16);
                

                string safe_name = GLib.Markup.escape_text(name);
                var name_label = new Gtk.Label(null);
                
                // Debugging markup error
                // warning("Setting markup for key: '%s' -> '%s'", name, safe_name);
                
                name_label.set_markup(safe_name);
                name_label.xalign = 0;
                name_label.add_css_class("heading");

                var radio = new Gtk.CheckButton();
                var label_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
                
                var fpr_label = new Gtk.Label(format_fpr_short(short_fpr));
                fpr_label.xalign = 0;
                fpr_label.add_css_class("dim-label");
                fpr_label.add_css_class("monospace");
                label_box.append(name_label);
                label_box.append(fpr_label);
                radio.child = label_box;
                
                radio.set_group(first_radio);
                radio.set_data<string>("key_fpr", key.fingerprint);
                if (key.fingerprint == current_key_id) radio.active = true;
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
                    
                    // First check if the key requires a passphrase
                    bool requires_passphrase = GPGHelper.key_requires_passphrase(new_key_fpr);
                    
                    if (!requires_passphrase) {
                        // Key has no passphrase, save directly
                        debug("OpenPGP: Key %s has no passphrase, saving directly", new_key_fpr);
                        save_key_selection(new_key_fpr);
                        dialog.force_close();
                        return;
                    }
                    
                    // Key requires passphrase - verify it
                    string passphrase = pw_entry.text;
                    if (passphrase.length == 0) {
                        error_label.label = _("Passphrase required");
                        error_label.visible = true;
                        return;
                    }
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
                    string openpgp_gnupg_home = Environment.get_variable("GNUPGHOME");
                    if (openpgp_gnupg_home == null) openpgp_gnupg_home = Path.build_filename(Application.get_storage_dir(), "openpgp", "gnupg");
                    
                    string gpg_bin = Environment.find_program_in_path("gpg");
                    if (gpg_bin == null) gpg_bin = "gpg";

                    // Use Subprocess to avoid shell injection
                    // Note: Passphrase is still visible in process list, but RCE is prevented.
                    string[] argv = {
                        gpg_bin, "--homedir", openpgp_gnupg_home, 
                        "--batch", "--yes", "--pinentry-mode", "loopback", 
                        "--passphrase", passphrase, 
                        "-u", key_fpr, 
                        "--sign", "--armor", "-o", "nul" // Windows needs 'nul', Linux '/dev/null'. Since we are debugging Windows, force nul.
                    };
#if !WINDOWS
                    argv[argv.length - 1] = "/dev/null";
#endif

                    Subprocess proc = new Subprocess.newv(argv, SubprocessFlags.STDIN_PIPE);
                    proc.communicate_utf8("test", null, null, null);
                    
                    success = proc.get_successful();
                } catch (Error e) { debug(e.message); }
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
            
            // Also republish via XEP-0373 for modern clients (Monocles, Conversations)
            if (plugin.xep0373_manager != null) {
                plugin.xep0373_manager.republish_key(current_account);
            }
            
            // IMPORTANT: Resend presence so other clients (XEP-0027) see our signed presence
            // This is necessary because the presence was already sent before the key was configured
            if (current_account != null) {
                var presence_manager = plugin.app.stream_interactor.get_module<Dino.PresenceManager>(Dino.PresenceManager.IDENTITY);
                if (presence_manager != null) {
                    presence_manager.resend_presence(current_account);
                    debug("OpenPGP: Resent presence after key selection for %s", current_account.bare_jid.to_string());
                }
            }
            
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
                key_dialog = new KeyManagementDialog(parent_window, plugin.db, plugin.xep0373_manager, current_account);
                keys_changed_handler_id = key_dialog.keys_changed.connect(() => { on_keys_changed(); });
                key_dialog.present();
            }
        }

        private static async Gee.List<GpgKeyInfo> get_pgp_keys() {
            var keys = new Gee.ArrayList<GpgKeyInfo>();
            
            // Call GPG CLI directly to avoid GPGME crashes in preferences UI
            try {
                string openpgp_gnupg_home = Environment.get_variable("GNUPGHOME");
                if (openpgp_gnupg_home == null) openpgp_gnupg_home = Path.build_filename(Application.get_storage_dir(), "openpgp", "gnupg");

                string gpg_bin = Environment.find_program_in_path("gpg");
                if (gpg_bin == null) {
                    if (FileUtils.test("/usr/bin/gpg.exe", FileTest.EXISTS)) gpg_bin = "/usr/bin/gpg.exe";
                    else if (FileUtils.test("C:/msys64/usr/bin/gpg.exe", FileTest.EXISTS)) gpg_bin = "C:/msys64/usr/bin/gpg.exe";
                    else if (FileUtils.test("C:/msys64/mingw64/bin/gpg.exe", FileTest.EXISTS)) gpg_bin = "C:/msys64/mingw64/bin/gpg.exe";
                    else gpg_bin = "gpg";
                }

                string[] argv = { gpg_bin, "--homedir", openpgp_gnupg_home, "--list-secret-keys", "--with-colons" };
                
                // Use Subprocess for async execution to not block UI
                var proc = new Subprocess.newv(argv, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
                string? stdout_str = null;
                string? stderr_str = null;

                yield proc.communicate_utf8_async(null, null, out stdout_str, out stderr_str);

                if (proc.get_exit_status() == 0 && stdout_str != null) {
                    string? current_fpr = null;
                    int64 current_created = 0;
                    bool in_main_key = false;
                    
                    foreach (var line in stdout_str.split("\n")) {
                        var parts = line.split(":");
                        if (parts.length < 2) continue;
                        
                        if (parts[0] == "sec") {
                            in_main_key = true;
                            current_fpr = null;
                            current_created = 0;
                            if (parts.length > 5 && parts[5].length > 0) current_created = int64.parse(parts[5]);
                        } else if (parts[0] == "ssb") {
                            in_main_key = false;
                        } else if (parts[0] == "fpr" && in_main_key && current_fpr == null) {
                            if (parts.length > 9 && parts[9].length > 0) current_fpr = parts[9];
                        } else if (parts[0] == "uid" && current_fpr != null) {
                            if (parts.length > 9) {
                                string uid = parts[9];
                                if (uid.length > 0) {
                                    keys.add(new GpgKeyInfo(current_fpr, uid, current_created));
                                    current_fpr = null;
                                }
                            }
                        }
                    }
                }
            } catch (Error e) {
                debug("Error listing GPG keys: %s", e.message);
            }
            
            return keys;
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
