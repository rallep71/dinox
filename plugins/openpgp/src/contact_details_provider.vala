using Gtk;

using Dino.Entities;

namespace Dino.Plugins.OpenPgp {

public class ContactDetailsProvider : Plugins.ContactDetailsProvider, Object {
    public string id { get { return "pgp_info"; } }
    public string tab { get { return "encryption"; } }

    private StreamInteractor stream_interactor;

    public ContactDetailsProvider(StreamInteractor stream_interactor) {
        this.stream_interactor = stream_interactor;
    }

    public void populate(Conversation conversation, Plugins.ContactDetails contact_details, WidgetType type) { }

    public Object? get_widget(Conversation conversation) {
        if (conversation == null) return null;
        
        var preferences_group = new Adw.PreferencesGroup() { title="OpenPGP" };

        if (conversation.type_ != Conversation.Type.CHAT) return null;

        string? key_id = stream_interactor.get_module<Manager>(Manager.IDENTITY).get_key_id(conversation.account, conversation.counterpart);
        if (key_id == null) {
            // No key known yet - show option to fetch from keyserver
            var fetch_row = new Adw.ActionRow() {
                title = _("No OpenPGP key"),
                subtitle = _("Click to search keyserver for this contact's key")
            };
            var fetch_btn = new Gtk.Button.from_icon_name("sync-synchronizing-symbolic");
            fetch_btn.valign = Gtk.Align.CENTER;
            fetch_btn.add_css_class("flat");
            fetch_btn.tooltip_text = _("Search keyserver");
            fetch_btn.clicked.connect(() => {
                fetch_key_combined.begin(conversation, fetch_row);
            });
            fetch_row.add_suffix(fetch_btn);
            fetch_row.activatable_widget = fetch_btn;
            preferences_group.add(fetch_row);
            return preferences_group;
        }

        // Create initial UI with "loading" state to avoid blocking
        var view = new Adw.ActionRow() {
            title = _("Fingerprint"),
            subtitle = _("Loading key info..."),
            subtitle_selectable = true
        };
        
        var action_btn = new Gtk.Button.from_icon_name("sync-synchronizing-symbolic");
        action_btn.valign = Gtk.Align.CENTER;
        action_btn.add_css_class("flat");
        action_btn.tooltip_text = _("Loading...");
        action_btn.sensitive = false;
        view.add_suffix(action_btn);
        
        preferences_group.add(view);
        
        // Check keylist in background thread to avoid blocking UI
        string key_id_copy = key_id;
        new Thread<void*>("openpgp-contact-details", () => {
            Gee.List<GPGHelper.Key>? keys = null;
            try {
                keys = GPGHelper.get_keylist(key_id_copy);
            } catch (Error e) {
                debug("ContactDetailsProvider: Failed to get keylist for %s: %s", key_id_copy, e.message);
            }
            
            // Update UI on main thread
            bool key_in_keychain = keys != null && keys.size > 0;
            string? fpr = key_in_keychain ? keys[0].fpr : null;
            
            Idle.add(() => {
                string str;
                if (key_in_keychain && fpr != null) {
                    str = markup_id(fpr, true);
                } else {
                    str = _("Key not in keychain") + "\n" + markup_id(key_id_copy, false);
                }
                view.subtitle = str;
                
                // Update button state
                if (key_in_keychain) {
                    action_btn.icon_name = "emblem-ok-symbolic";
                    action_btn.tooltip_text = _("Key verified");
                    action_btn.sensitive = false;
                } else {
                    action_btn.icon_name = "sync-synchronizing-symbolic";
                    action_btn.tooltip_text = _("Fetch from keyserver");
                    action_btn.sensitive = true;
                    action_btn.clicked.connect(() => {
                        fetch_key_from_keyserver.begin(key_id_copy, view);
                    });
                }
                return false;
            });
            
            return null;
        });

        return preferences_group;
    }
    
    private async void fetch_key_from_keyserver(string key_id_or_email, Adw.ActionRow row) {
        row.subtitle = _("Searching keyserver...");
        
        bool success = false;
        string error_msg = "";
        
        // Run GPG keyserver fetch in background thread
        SourceFunc callback = fetch_key_from_keyserver.callback;
        new Thread<void*>(null, () => {
            try {
                string gpg_bin = Environment.find_program_in_path("gpg");
                if (gpg_bin == null) gpg_bin = "gpg";
                
                string openpgp_gnupg_home = Path.build_filename(Application.get_storage_dir(), "openpgp", "gnupg");
                
                // Try to receive key from keyserver using --recv-keys
                // This works with fingerprints, key IDs, and emails (keys.openpgp.org supports email lookup via WKD)
                string[] argv = { gpg_bin, "--homedir", openpgp_gnupg_home, "--batch", "--yes", 
                                  "--keyserver", "hkps://keys.openpgp.org", 
                                  "--keyserver-options", "import-minimal",
                                  "--recv-keys", key_id_or_email };
                
                var proc = new Subprocess.newv(argv, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
                string? stdout_str = null;
                string? stderr_str = null;
                proc.communicate_utf8(null, null, out stdout_str, out stderr_str);
                
                if (proc.get_exit_status() == 0) {
                    success = true;
                } else {
                    // If keys.openpgp.org failed, try Ubuntu keyserver as fallback
                    string[] argv2 = { gpg_bin, "--homedir", openpgp_gnupg_home, "--batch", "--yes", 
                                       "--keyserver", "hkps://keyserver.ubuntu.com", 
                                       "--recv-keys", key_id_or_email };
                    var proc2 = new Subprocess.newv(argv2, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
                    proc2.communicate_utf8(null, null, out stdout_str, out stderr_str);
                    success = proc2.get_exit_status() == 0;
                    if (!success) {
                        error_msg = stderr_str ?? _("Key not found on keyserver");
                    }
                }
            } catch (Error e) {
                error_msg = e.message;
            }
            Idle.add((owned)callback);
            return null;
        });
        yield;
        
        if (success) {
            row.subtitle = _("Key imported from keyserver!");
            // Invalidate cache so next time the key is shown
            GPGHelper.invalidate_secret_keys_cache();
        } else {
            row.subtitle = _("Failed: ") + error_msg;
        }
    }
    
    // Combined fetch: try fingerprint first, then JID, then ask for email
    private async void fetch_key_combined(Conversation conversation, Adw.ActionRow row) {
        string jid = conversation.counterpart.bare_jid.to_string();
        bool found = false;
        string error_msg = "";
        
        // Step 1: Check if we have a key_id/fingerprint from presence signature
        string? known_key_id = stream_interactor.get_module<Manager>(Manager.IDENTITY).get_key_id(conversation.account, conversation.counterpart);
        
        if (known_key_id != null) {
            row.subtitle = _("Searching keyserver with fingerprint: ") + known_key_id.substring(0, int.min(16, known_key_id.length)) + "...";
            debug("ContactDetails: Trying fingerprint %s", known_key_id);
            
            SourceFunc callback1 = fetch_key_combined.callback;
            new Thread<void*>(null, () => {
                try {
                    found = GPGHelper.download_key_from_keyserver(known_key_id);
                    debug("ContactDetails: Fingerprint search result: %s", found ? "FOUND" : "NOT FOUND");
                } catch (Error e) {
                    error_msg = e.message;
                    debug("ContactDetails: Fingerprint search error: %s", e.message);
                }
                Idle.add((owned)callback1);
                return null;
            });
            yield;
            
            if (found) {
                row.title = _("OpenPGP Key Found!");
                row.subtitle = _("Key imported with fingerprint. Reopen dialog to see details.");
                GPGHelper.invalidate_secret_keys_cache();
                return;
            } else {
                // Show more helpful error message
                if (error_msg.length == 0) {
                    error_msg = _("Key not found or has no verified email on keyserver.\nAsk the contact to verify their email on keys.openpgp.org\nor send you their public key file directly.");
                }
                row.subtitle = _("Failed: ") + error_msg;
                // Continue to try other methods
            }
        }
        
        // Step 2: Try keyserver with JID
        row.subtitle = _("Searching keyserver with JID...");
        
        // Step 1: Try keyserver with JID
        SourceFunc callback = fetch_key_combined.callback;
        new Thread<void*>(null, () => {
            try {
                found = GPGHelper.download_key_from_keyserver(jid);
            } catch (Error e) {
                error_msg = e.message;
            }
            Idle.add((owned)callback);
            return null;
        });
        yield;
        
        if (found) {
            row.title = _("OpenPGP Key Found!");
            row.subtitle = _("Key imported. Reopen dialog to see details.");
            GPGHelper.invalidate_secret_keys_cache();
            return;
        }
        
        // Step 2: JID not found - show email input dialog directly
        yield show_email_input_dialog(conversation, row);
    }
    
    private async void show_email_input_dialog(Conversation conversation, Adw.ActionRow row) {
        row.subtitle = _("Not found with JID. Enter email address:");
        // Find parent window
        Gtk.Window? parent_window = null;
        var widget = row as Gtk.Widget;
        while (widget != null && !(widget is Gtk.Window)) {
            widget = widget.get_parent();
        }
        if (widget is Gtk.Window) parent_window = (Gtk.Window)widget;
        
        var dialog = new Adw.AlertDialog(
            _("Enter Email Address"),
            _("The key was not found using the JID.\n\nEnter the email address that is in the contact's OpenPGP key:")
        );
        dialog.add_response("cancel", _("Cancel"));
        dialog.add_response("search", _("Search"));
        dialog.default_response = "search";
        dialog.close_response = "cancel";
        
        var entry = new Gtk.Entry();
        entry.placeholder_text = "user@example.com";
        entry.margin_start = 12;
        entry.margin_end = 12;
        dialog.extra_child = entry;
        
        dialog.response.connect((response) => {
            if (response == "search") {
                string email = entry.text.strip();
                if (email.length > 0) {
                    fetch_key_by_email.begin(email, row);
                }
            }
        });
        
        dialog.present(parent_window);
    }
    
    private async void fetch_key_by_email(string email, Adw.ActionRow row) {
        row.subtitle = _("Searching keyserver for: ") + email + "...";
        
        bool found = false;
        string error_msg = "";
        
        SourceFunc callback = fetch_key_by_email.callback;
        new Thread<void*>(null, () => {
            try {
                found = GPGHelper.download_key_from_keyserver(email);
            } catch (Error e) {
                error_msg = e.message;
            }
            Idle.add((owned)callback);
            return null;
        });
        yield;
        
        if (found) {
            row.title = _("OpenPGP Key Found!");
            row.subtitle = _("Key imported from: ") + email;
            GPGHelper.invalidate_secret_keys_cache();
        } else {
            row.subtitle = _("Not found: ") + email + ". " + error_msg;
        }
    }
}

}
