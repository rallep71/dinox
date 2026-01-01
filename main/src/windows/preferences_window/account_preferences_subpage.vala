using Dino.Entities;
using Xmpp;
using Xmpp.Xep;
using Gee;
using Gtk;
using Gdk;

[GtkTemplate (ui = "/im/github/rallep71/DinoX/preferences_window/account_preferences_subpage.ui")]
public class Dino.Ui.AccountPreferencesSubpage : Adw.NavigationPage {

    [GtkChild] public unowned Adw.HeaderBar headerbar;
    [GtkChild] public unowned AvatarPicture avatar;
    [GtkChild] public unowned Adw.ActionRow xmpp_address;
    [GtkChild] public unowned Adw.EntryRow local_alias;
    [GtkChild] public unowned Adw.ActionRow password_change;
    [GtkChild] public unowned Adw.ActionRow connection_status;
    [GtkChild] public unowned Button enter_password_button;
    [GtkChild] public unowned Button trust_certificate_button;
    [GtkChild] public unowned Box avatar_menu_box;
    [GtkChild] public unowned Button edit_avatar_button;
    [GtkChild] public unowned Button remove_avatar_button;
    [GtkChild] public unowned Widget button_container;
    [GtkChild] public unowned Button remove_account_button;
    [GtkChild] public unowned Button disable_account_button;
    [GtkChild] public unowned Adw.EntryRow custom_host_entry;
    [GtkChild] public unowned Adw.EntryRow custom_port_entry;

    [GtkChild] public unowned Adw.EntryRow vcard_fn;
    [GtkChild] public unowned Adw.EntryRow vcard_nickname;
    [GtkChild] public unowned Adw.EntryRow vcard_email;
    [GtkChild] public unowned Adw.EntryRow vcard_phone;
    [GtkChild] public unowned Adw.EntryRow vcard_title;
    [GtkChild] public unowned Adw.EntryRow vcard_role;
    [GtkChild] public unowned Adw.EntryRow vcard_org;
    [GtkChild] public unowned Adw.EntryRow vcard_url;
    [GtkChild] public unowned Adw.EntryRow vcard_desc;
    [GtkChild] public unowned Button save_vcard_button;

    public Account account { get { return model.selected_account.account; } }
    public ViewModel.PreferencesDialog model { get; set; }

    private Binding[] bindings = new Binding[0];
    private ulong alias_entry_changed = 0;
    private ulong custom_host_entry_changed = 0;
    private ulong custom_port_entry_changed = 0;

    construct {
        title = "Account";
        headerbar.show_title = false;
        button_container.layout_manager = new NaturalDirectionBoxLayout((BoxLayout)button_container.layout_manager);
        edit_avatar_button.clicked.connect(() => {
            show_select_avatar();
        });
        remove_avatar_button.clicked.connect(() => {
            model.remove_avatar(account);
        });
        disable_account_button.clicked.connect(() => {
            model.enable_disable_account(account);
        });
        remove_account_button.clicked.connect(() => {
            show_remove_account_dialog();
        });
        password_change.activatable_widget = new Label("");
        password_change.activated.connect(() => {
            var dialog = new ChangePasswordDialog(model.get_change_password_dialog_model());
            dialog.present((Gtk.Window)this.get_root());
        });
        enter_password_button.clicked.connect(() => {
            var dialog = new Adw.MessageDialog((Window)this.get_root(), "Enter password for %s".printf(account.bare_jid.to_string()), null);
            var password = new PasswordEntry() { show_peek_icon=true };
            dialog.response.connect((response) => {
                if (response == "connect") {
                    account.password = password.text;
                    model.reconnect_account(account);
                }
            });
            dialog.set_default_response("connect");
            dialog.set_extra_child(password);
            dialog.add_response("cancel", _("Cancel"));
            dialog.add_response("connect", _("Connect"));

            dialog.present();
        });
        
        trust_certificate_button.clicked.connect(() => {
            show_certificate_dialog();
        });

        save_vcard_button.clicked.connect(() => {
            save_vcard.begin();
        });

        this.notify["model"].connect(() => {
            model.notify["selected-account"].connect(() => {
                foreach (var binding in bindings) {
                    binding.unbind();
                }

                avatar.model = model.selected_account.avatar_model;
                xmpp_address.subtitle = account.bare_jid.to_string();

                if (alias_entry_changed != 0) local_alias.disconnect(alias_entry_changed);
                local_alias.text = account.alias ?? "";
                alias_entry_changed = local_alias.changed.connect(() => {
                    account.alias = local_alias.text;
                });

                // Populate and bind custom host/port fields
                if (custom_host_entry_changed != 0) custom_host_entry.disconnect(custom_host_entry_changed);
                if (custom_port_entry_changed != 0) custom_port_entry.disconnect(custom_port_entry_changed);
                
                custom_host_entry.text = account.custom_host ?? "";
                custom_port_entry.text = account.custom_port > 0 ? account.custom_port.to_string() : "";
                
                custom_host_entry_changed = custom_host_entry.changed.connect(() => {
                    account.custom_host = custom_host_entry.text.length > 0 ? custom_host_entry.text : null;
                });
                
                custom_port_entry_changed = custom_port_entry.changed.connect(() => {
                    int port = int.parse(custom_port_entry.text);
                    account.custom_port = (port > 0 && port <= 65535) ? port : 0;
                });

                load_vcard.begin();

                bindings += account.bind_property("enabled", disable_account_button, "label", BindingFlags.SYNC_CREATE, (binding, from, ref to) => {
                    bool enabled_bool = (bool) from;
                    to = enabled_bool ? _("Disable account") : _("Enable account");
                    return true;
                });
                bindings += account.bind_property("enabled", avatar_menu_box, "visible", BindingFlags.SYNC_CREATE);
                bindings += account.bind_property("enabled", password_change, "visible", BindingFlags.SYNC_CREATE);
                bindings += account.bind_property("enabled", connection_status, "visible", BindingFlags.SYNC_CREATE);
                bindings += model.selected_account.bind_property("connection-state", connection_status, "subtitle", BindingFlags.SYNC_CREATE, (binding, from, ref to) => {
                    to = get_status_label();
                    return true;
                });
                bindings += model.selected_account.bind_property("connection-error", connection_status, "subtitle", BindingFlags.SYNC_CREATE, (binding, from, ref to) => {
                    to = get_status_label();
                    return true;
                });
                bindings += model.selected_account.bind_property("connection-error", enter_password_button, "visible", BindingFlags.SYNC_CREATE, (binding, from, ref to) => {
                    var error = (ConnectionManager.ConnectionError) from;
                    to = error != null && error.source == ConnectionManager.ConnectionError.Source.SASL;
                    return true;
                });

                // Only show avatar removal button if an avatar is set
                var avatar_model = model.selected_account.avatar_model.tiles.get_item(0) as ViewModel.AvatarPictureTileModel;
                avatar_model.notify["image-file"].connect(() => {
                    remove_avatar_button.visible = avatar_model.image_file != null;
                });
                remove_avatar_button.visible = avatar_model.image_file != null;

                model.selected_account.notify["connection-error"].connect(() => {
                    update_connection_error_ui();
                });
                update_connection_error_ui();
            });
        });
    }

    private void update_connection_error_ui() {
        var error = model.selected_account.connection_error;
        if (error != null) {
            connection_status.add_css_class("error");
            // Show trust certificate button for TLS errors with certificate info
            if (error.source == ConnectionManager.ConnectionError.Source.TLS && 
                error.tls_certificate != null) {
                trust_certificate_button.visible = true;
            } else {
                trust_certificate_button.visible = false;
            }
        } else {
            connection_status.remove_css_class("error");
            trust_certificate_button.visible = false;
        }
    }

    private void show_certificate_dialog() {
        var error = model.selected_account.connection_error;
        if (error == null || error.tls_certificate == null) return;

        var dialog = new CertificateWarningDialog(
            account,
            error.tls_certificate,
            error.tls_flags,
            error.tls_domain ?? account.domainpart,
            model.stream_interactor
        );
        dialog.present((Window)this.get_root());
    }

    private void show_select_avatar() {
        var chooser = new Gtk.FileDialog();
        chooser.title = _("Select avatar");
        chooser.accept_label = _("Select");

        var filters = new GLib.ListStore(typeof(Gtk.FileFilter));

        var image_filter = new Gtk.FileFilter();
        foreach (PixbufFormat pixbuf_format in Pixbuf.get_formats()) {
            foreach (string mime_type in pixbuf_format.get_mime_types()) {
                image_filter.add_mime_type(mime_type);
            }
        }
        image_filter.name = _("Images");
        filters.append(image_filter);

        var all_filter = new Gtk.FileFilter();
        all_filter.name = _("All files");
        all_filter.add_pattern("*");
        filters.append(all_filter);

        chooser.filters = filters;
        chooser.default_filter = image_filter;

        chooser.open.begin((Window)this.get_root(), null, (obj, res) => {
            try {
                File file = chooser.open.end(res);
                model.set_avatar_file(account, file);
            } catch (Error e) {
            }
        });
    }

    private void show_remove_account_dialog() {
        Adw.AlertDialog dialog = new Adw.AlertDialog (
                _("Remove account %s?".printf(account.bare_jid.to_string())),
                "You won't be able to access your conversation history anymore."
        );
        // TODO remove history!
        dialog.add_response("cancel", "Cancel");
        dialog.add_response("remove", "Remove");
        dialog.set_response_appearance("remove", Adw.ResponseAppearance.DESTRUCTIVE);
        dialog.response.connect((response) => {
            if (response == "remove") {
                model.remove_account(account);

                // Close the account subpage. Get the parent-times-x PreferencesDialog, to call pop_subpage() on it.
                Widget parent = this.parent;
                for (int i = 0; parent != null && i < 20; i++) {
                    if (parent.get_type() == typeof(Dino.Ui.PreferencesDialog)) {
                        ((Dino.Ui.PreferencesDialog) parent).pop_subpage();
                    }
                    parent = parent.parent;
                }
            }
            dialog.close();
        });
        dialog.present((Window)this.get_root());
    }

    private async void load_vcard() {
        vcard_fn.text = "";
        vcard_nickname.text = "";
        vcard_email.text = "";
        vcard_phone.text = "";
        vcard_title.text = "";
        vcard_role.text = "";
        vcard_org.text = "";
        vcard_url.text = "";
        vcard_desc.text = "";
        save_vcard_button.sensitive = false;

        var stream = model.stream_interactor.get_stream(account);
        if (stream == null) return;

        // Try VCard4 (XEP-0292) first
        var vcard4_module = stream.get_module(Xmpp.Xep.VCard4.Module.IDENTITY);
        if (vcard4_module != null) {
            var vcard4 = yield vcard4_module.request(stream, account.bare_jid);
            if (vcard4 != null) {
                vcard_fn.text = vcard4.full_name ?? "";
                vcard_nickname.text = vcard4.nickname ?? "";
                vcard_email.text = vcard4.email ?? "";
                vcard_phone.text = vcard4.tel ?? "";
                vcard_title.text = vcard4.title ?? "";
                vcard_role.text = vcard4.role ?? "";
                vcard_org.text = vcard4.org ?? "";
                vcard_url.text = vcard4.url ?? "";
                vcard_desc.text = vcard4.note ?? "";
                save_vcard_button.sensitive = true;
                return;
            }
        }

        // Fallback to VCard-temp (XEP-0054)
        var vcard = yield Xmpp.Xep.VCard.fetch_vcard(stream);
        if (vcard != null) {
            vcard_fn.text = vcard.full_name ?? "";
            vcard_nickname.text = vcard.nickname ?? "";
            vcard_email.text = vcard.email ?? "";
            vcard_phone.text = vcard.phone ?? "";
            vcard_title.text = vcard.title ?? "";
            vcard_role.text = vcard.role ?? "";
            vcard_org.text = vcard.organization ?? "";
            vcard_url.text = vcard.url ?? "";
            vcard_desc.text = vcard.description ?? "";
        }
        save_vcard_button.sensitive = true;
    }

    private async void save_vcard() {
        save_vcard_button.sensitive = false;
        var stream = model.stream_interactor.get_stream(account);
        if (stream == null) return;

        // Save VCard4 (XEP-0292)
        var vcard4_module = stream.get_module(Xmpp.Xep.VCard4.Module.IDENTITY);
        if (vcard4_module != null) {
            var vcard4 = new Xmpp.Xep.VCard4.VCard4.create();
            vcard4.full_name = vcard_fn.text;
            vcard4.nickname = vcard_nickname.text;
            vcard4.email = vcard_email.text;
            vcard4.tel = vcard_phone.text;
            vcard4.title = vcard_title.text;
            vcard4.role = vcard_role.text;
            vcard4.org = vcard_org.text;
            vcard4.url = vcard_url.text;
            vcard4.note = vcard_desc.text;
            
            yield vcard4_module.publish(stream, vcard4);
        }

        // Save VCard-temp (XEP-0054)
        var vcard = new Xmpp.Xep.VCard.VCardInfo();
        vcard.full_name = vcard_fn.text;
        vcard.nickname = vcard_nickname.text;
        vcard.email = vcard_email.text;
        vcard.phone = vcard_phone.text;
        vcard.title = vcard_title.text;
        vcard.role = vcard_role.text;
        vcard.organization = vcard_org.text;
        vcard.url = vcard_url.text;
        vcard.description = vcard_desc.text;
        
        try {
            var current_vcard = yield Xmpp.Xep.VCard.fetch_vcard(stream);
            if (current_vcard != null) {
                vcard.photo = current_vcard.photo;
                vcard.photo_type = current_vcard.photo_type;
            }
            
            yield Xmpp.Xep.VCard.publish_vcard(stream, vcard);
        } catch (Error e) {
            warning("Failed to save vCard: %s", e.message);
            var dialog = new Adw.MessageDialog((Window)this.get_root(), "Failed to save profile", e.message);
            dialog.add_response("ok", _("OK"));
            dialog.present();
        }
        save_vcard_button.sensitive = true;
    }

    private string get_status_label() {
        string? error_label = get_connection_error_description();
        if (error_label != null) return error_label;

        ConnectionManager.ConnectionState state = model.selected_account.connection_state;
        switch (state) {
            case ConnectionManager.ConnectionState.CONNECTING:
                return _("Connecting…");
            case ConnectionManager.ConnectionState.CONNECTED:
                return _("Connected");
            case ConnectionManager.ConnectionState.DISCONNECTED:
                return _("Disconnected");
        }
        assert_not_reached();
    }

    private string? get_connection_error_description() {
        ConnectionManager.ConnectionError? error = model.selected_account.connection_error;
        if (error == null) return null;

        switch (error.source) {
            case ConnectionManager.ConnectionError.Source.SASL:
                return _("Wrong password");
            case ConnectionManager.ConnectionError.Source.TLS:
                return _("Invalid TLS certificate");
            case ConnectionManager.ConnectionError.Source.CONNECTION:
            case ConnectionManager.ConnectionError.Source.STREAM_ERROR:
                // Fall through to default error handling
                break;
        }
        if (error.identifier != null) {
            return _("Error") + ": " + error.identifier;
        } else {
            return _("Error");
        }
    }
}

public class Dino.Ui.NaturalDirectionBoxLayout : LayoutManager {
    private BoxLayout original;
    private BoxLayout alternative;

    public NaturalDirectionBoxLayout(BoxLayout original) {
        this.original = original;
        if (original.orientation == Orientation.HORIZONTAL) {
            this.alternative = new BoxLayout(Orientation.VERTICAL);
            this.alternative.spacing = this.original.spacing / 2;
        }
    }

    public override SizeRequestMode get_request_mode(Widget widget) {
        return original.orientation == Orientation.HORIZONTAL ? SizeRequestMode.HEIGHT_FOR_WIDTH : SizeRequestMode.WIDTH_FOR_HEIGHT;
    }

    public override void allocate(Widget widget, int width, int height, int baseline) {
        int blind_minimum, blind_natural, blind_minimum_baseline, blind_natural_baseline;
        original.measure(widget, original.orientation, -1, out blind_minimum, out blind_natural, out blind_minimum_baseline, out blind_natural_baseline);
        int for_size = (original.orientation == Orientation.HORIZONTAL ? width : height);
        if (for_size >= blind_minimum) {
            original.allocate(widget, width, height, baseline);
        } else {
            alternative.allocate(widget, width, height, baseline);
        }
    }

    public override void measure(Widget widget, Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
        if (for_size == -1) {
            original.measure(widget, orientation, -1, out minimum, out natural, out minimum_baseline, out natural_baseline);
            int alt_minimum, alt_natural, alt_minimum_baseline, alt_natural_baseline;
            alternative.measure(widget, orientation, -1, out alt_minimum, out alt_natural, out alt_minimum_baseline, out alt_natural_baseline);
            if (alt_minimum < minimum && alt_minimum != -1) minimum = alt_minimum;
            if (alt_minimum_baseline < minimum_baseline && alt_minimum_baseline != -1) minimum = alt_minimum_baseline;
        } else {
            Orientation other_orientation = orientation == Orientation.HORIZONTAL ? Orientation.VERTICAL : Orientation.HORIZONTAL;
            int blind_minimum, blind_natural, blind_minimum_baseline, blind_natural_baseline;
            original.measure(widget, other_orientation, -1, out blind_minimum, out blind_natural, out blind_minimum_baseline, out blind_natural_baseline);
            if (for_size >= blind_minimum) {
                original.measure(widget, orientation, for_size, out minimum, out natural, out minimum_baseline, out natural_baseline);
            } else {
                alternative.measure(widget, orientation, for_size, out minimum, out natural, out minimum_baseline, out natural_baseline);
            }
        }
    }
}
