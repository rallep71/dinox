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
    [GtkChild] public unowned Adw.ComboRow proxy_type_row;
    [GtkChild] public unowned Adw.EntryRow proxy_host_entry;
    [GtkChild] public unowned Adw.EntryRow proxy_port_entry;
    [GtkChild] public unowned Adw.SwitchRow require_channel_binding_switch;

    [GtkChild] public unowned Adw.EntryRow vcard_fn;
    [GtkChild] public unowned Adw.EntryRow vcard_nickname;
    [GtkChild] public unowned Adw.ComboRow vcard_gender;
    [GtkChild] public unowned Adw.EntryRow vcard_bday;
    [GtkChild] public unowned Adw.EntryRow vcard_adr_street;
    [GtkChild] public unowned Adw.EntryRow vcard_adr_pcode;
    [GtkChild] public unowned Adw.EntryRow vcard_adr_city;
    [GtkChild] public unowned Adw.EntryRow vcard_adr_region;
    [GtkChild] public unowned Adw.EntryRow vcard_adr_country;
    [GtkChild] public unowned Adw.EntryRow vcard_email;
    [GtkChild] public unowned Adw.EntryRow vcard_impp;
    [GtkChild] public unowned Adw.SwitchRow vcard_public_access;
    [GtkChild] public unowned Adw.SwitchRow vcard_share_with_contacts;
    [GtkChild] public unowned Adw.EntryRow vcard_phone;
    [GtkChild] public unowned Adw.EntryRow vcard_title;
    [GtkChild] public unowned Adw.EntryRow vcard_role;
    [GtkChild] public unowned Adw.EntryRow vcard_org;
    [GtkChild] public unowned Adw.EntryRow vcard_tz;
    [GtkChild] public unowned Adw.EntryRow vcard_url;
    [GtkChild] public unowned Adw.EntryRow vcard_desc;
    [GtkChild] public unowned Button save_vcard_button;

    // Server Certificate section
    [GtkChild] public unowned Adw.PreferencesGroup cert_group;
    [GtkChild] public unowned Adw.ActionRow cert_status_row;
    [GtkChild] public unowned Adw.ActionRow cert_issuer_row;
    [GtkChild] public unowned Adw.ActionRow cert_validity_row;
    [GtkChild] public unowned Adw.ActionRow cert_fingerprint_row;
    [GtkChild] public unowned Button unpin_certificate_button;
    [GtkChild] public unowned Adw.ActionRow manage_botmothers_row;
    [GtkChild] public unowned Adw.ActionRow manage_mqtt_bot_row;

    public Account account { get { return model.selected_account.account; } }
    public ViewModel.PreferencesDialog model { get; set; }

    private Binding[] bindings = new Binding[0];
    private ulong alias_entry_changed = 0;
    private ulong custom_host_entry_changed = 0;
    private ulong custom_port_entry_changed = 0;
    private ulong proxy_type_row_changed = 0;
    private ulong proxy_host_entry_changed = 0;
    private ulong proxy_port_entry_changed = 0;
    private ulong require_cb_changed = 0;

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
        manage_botmothers_row.activatable_widget = new Label("");
        manage_botmothers_row.activated.connect(() => {
            var dialog = new BotManagerDialog();
            dialog.account_jid = account.bare_jid.to_string();
            dialog.present((Gtk.Window)this.get_root());
        });
        manage_mqtt_bot_row.activatable_widget = new Label("");
        manage_mqtt_bot_row.activated.connect(() => {
            var win = (Gtk.Window) this.get_root();
            var app = (Dino.Application) win.get_application();
            app.open_account_mqtt_manager(account, win);
        });
        password_change.activatable_widget = new Label("");
        password_change.activated.connect(() => {
            var dialog = new ChangePasswordDialog(model.get_change_password_dialog_model());
            dialog.present((Gtk.Window)this.get_root());
        });
        enter_password_button.clicked.connect(() => {
            var dialog = new Adw.AlertDialog("Enter password for %s".printf(account.bare_jid.to_string()), null);
            var password = new PasswordEntry() { show_peek_icon=true };
            dialog.response.connect((response) => {
                if (response == "connect") {
                    account.password = password.text;
                    model.reconnect_account(account);
                }
            });
            dialog.default_response = "connect";
            dialog.extra_child = password;
            dialog.add_response("cancel", _("Cancel"));
            dialog.add_response("connect", _("Connect"));

            dialog.present((Gtk.Window)this.get_root());
        });
        
        trust_certificate_button.clicked.connect(() => {
            show_certificate_dialog();
        });

        unpin_certificate_button.clicked.connect(() => {
            var dialog = new Adw.AlertDialog(
                _("Remove pinned certificate for %s?").printf(account.domainpart),
                _("The server will need to present a valid CA-signed certificate, or you will be asked to trust it again.")
            );
            dialog.add_response("cancel", _("Cancel"));
            dialog.add_response("remove", _("Remove"));
            dialog.set_response_appearance("remove", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.response.connect((response) => {
                if (response == "remove") {
                    model.stream_interactor.connection_manager.unpin_certificate(account.domainpart);
                    model.reconnect_account(account);
                    update_certificate_info();
                }
            });
            dialog.present((Window)this.get_root());
        });

        save_vcard_button.clicked.connect(() => {
            save_vcard.begin();
        });

        vcard_public_access.notify["active"].connect(() => {
            vcard_share_with_contacts.sensitive = !vcard_public_access.active;
            if (vcard_public_access.active) {
                vcard_share_with_contacts.active = true;
            }
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

                // Populate and bind proxy fields
                if (proxy_type_row_changed != 0) proxy_type_row.disconnect(proxy_type_row_changed);
                if (proxy_host_entry_changed != 0) proxy_host_entry.disconnect(proxy_host_entry_changed);
                if (proxy_port_entry_changed != 0) proxy_port_entry.disconnect(proxy_port_entry_changed);

                int type_index = 0;
                if (account.proxy_type == "socks5") type_index = 1;
                proxy_type_row.selected = type_index;

                proxy_host_entry.text = account.proxy_host ?? "";
                proxy_port_entry.text = account.proxy_port > 0 ? account.proxy_port.to_string() : "";
                
                update_proxy_visibility();

                proxy_type_row_changed = proxy_type_row.notify["selected"].connect(() => {
                    if (proxy_type_row.selected == 0) account.proxy_type = "none";
                    else if (proxy_type_row.selected == 1) account.proxy_type = "socks5";
                    
                    update_proxy_visibility();
                    check_proxy_availability.begin();
                    
                    if (account.enabled) {
                        model.reconnect_account(account);
                    }
                });

                proxy_host_entry_changed = proxy_host_entry.changed.connect(() => {
                    account.proxy_host = proxy_host_entry.text.length > 0 ? proxy_host_entry.text : null;
                    check_proxy_availability.begin();
                });

                proxy_port_entry_changed = proxy_port_entry.changed.connect(() => {
                    int port = int.parse(proxy_port_entry.text);
                    account.proxy_port = (port > 0 && port <= 65535) ? port : 0;
                    check_proxy_availability.begin();
                });

                // Channel binding downgrade protection
                if (require_cb_changed != 0) require_channel_binding_switch.disconnect(require_cb_changed);
                require_channel_binding_switch.active = account.require_channel_binding;
                require_cb_changed = require_channel_binding_switch.notify["active"].connect(() => {
                    account.require_channel_binding = require_channel_binding_switch.active;
                });

                load_vcard.begin();
                check_proxy_availability.begin();

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
                    update_certificate_info();
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
                avatar_model.notify["image-bytes"].connect(() => {
                    remove_avatar_button.visible = avatar_model.image_bytes != null;
                });
                remove_avatar_button.visible = avatar_model.image_bytes != null;

                model.selected_account.notify["connection-error"].connect(() => {
                    update_connection_error_ui();
                    update_certificate_info();
                });
                update_connection_error_ui();
                update_certificate_info();
            });
        });
    }

    private void update_proxy_visibility() {
        bool show_settings = proxy_type_row.selected == 1; // SOCKS5
        proxy_host_entry.visible = show_settings;
        proxy_port_entry.visible = show_settings;
    }

    private async void check_proxy_availability() {
        if (proxy_type_row.selected == 0) { // None
            proxy_type_row.subtitle = "";
            proxy_type_row.remove_css_class("error");
            proxy_type_row.remove_css_class("success");
            return;
        }

        string host;
        int port;

        // SOCKS5 (index 1)
        host = account.proxy_host ?? "";
        port = account.proxy_port;

        if (host == "" || port <= 0) {
            proxy_type_row.subtitle = "";
            return;
        }

        proxy_type_row.subtitle = _("Checking status...");
        
        try {
            SocketClient client = new SocketClient();
            client.timeout = 2; // 2 seconds timeout
            yield client.connect_to_host_async(host, (uint16)port);
            
            proxy_type_row.subtitle = _("Service is running and reachable");
            proxy_type_row.add_css_class("success");
            proxy_type_row.remove_css_class("error");
        } catch (Error e) {
            proxy_type_row.subtitle = _("Proxy unreachable");
            proxy_type_row.add_css_class("error");
            proxy_type_row.remove_css_class("success");
        }
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

    private void update_certificate_info() {
        string domain = account.domainpart;
        var cm = model.stream_interactor.connection_manager;
        
        // Try to get the live certificate from active connection
        TlsCertificate? live_cert = cm.get_peer_certificate(account);
        bool is_pinned = cm.is_certificate_pinned(domain);
        CertificateInfo? pinned_info = cm.get_pinned_certificate_info(domain);

        if (live_cert != null) {
            // Connected — show the live certificate
            string fingerprint = CertificateManager.get_certificate_fingerprint(live_cert);
            string? issuer = CertificateManager.get_certificate_issuer(live_cert);
            DateTime? not_before = CertificateManager.get_certificate_not_before(live_cert);
            DateTime? not_after = CertificateManager.get_certificate_not_after(live_cert);

            cert_group.visible = true;

            if (is_pinned) {
                cert_status_row.subtitle = _("Pinned (self-signed / manually trusted)");
                cert_status_row.add_css_class("warning");
            } else {
                cert_status_row.subtitle = _("Valid (CA-signed)");
                cert_status_row.remove_css_class("warning");
            }

            if (issuer != null) {
                cert_issuer_row.subtitle = issuer;
                cert_issuer_row.visible = true;
            } else {
                cert_issuer_row.visible = false;
            }

            if (not_before != null || not_after != null) {
                string validity = "";
                if (not_before != null) validity += _("From:") + " " + not_before.format("%Y-%m-%d");
                if (not_after != null) {
                    if (validity.length > 0) validity += "  —  ";
                    validity += _("Until:") + " " + not_after.format("%Y-%m-%d");
                    if (not_after.compare(new DateTime.now_utc()) < 0) {
                        validity += " (" + _("expired") + ")";
                    }
                }
                cert_validity_row.subtitle = validity;
                cert_validity_row.visible = true;
            } else {
                cert_validity_row.visible = false;
            }

            cert_fingerprint_row.subtitle = fingerprint;
            cert_fingerprint_row.visible = true;
            unpin_certificate_button.visible = is_pinned;

        } else if (pinned_info != null) {
            // Not connected but have a pinned cert — show the stored info
            cert_group.visible = true;
            cert_status_row.subtitle = _("Pinned (not connected)");
            cert_status_row.add_css_class("warning");

            if (pinned_info.issuer != null) {
                cert_issuer_row.subtitle = pinned_info.issuer;
                cert_issuer_row.visible = true;
            } else {
                cert_issuer_row.visible = false;
            }

            cert_validity_row.subtitle = pinned_info.get_validity_string();
            cert_validity_row.visible = true;

            cert_fingerprint_row.subtitle = pinned_info.fingerprint_sha256;
            cert_fingerprint_row.visible = true;
            unpin_certificate_button.visible = true;
        } else {
            // Not connected and no pinned cert
            if (cm.get_state(account) == ConnectionManager.ConnectionState.DISCONNECTED) {
                cert_group.visible = false;
            } else {
                cert_group.visible = true;
                cert_status_row.subtitle = _("Connecting…");
                cert_issuer_row.visible = false;
                cert_validity_row.visible = false;
                cert_fingerprint_row.visible = false;
                unpin_certificate_button.visible = false;
            }
        }
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
                _("You won't be able to access your conversation history anymore.")
        );

        // Checkbox: also delete from server
        var server_check = new Gtk.CheckButton.with_label(_("Also delete account from server"));
        server_check.margin_start = 12;
        server_check.margin_end = 12;
        server_check.margin_top = 6;
        dialog.set_extra_child(server_check);

        dialog.add_response("cancel", _("Cancel"));
        dialog.add_response("remove", _("Remove"));
        dialog.set_response_appearance("remove", Adw.ResponseAppearance.DESTRUCTIVE);
        dialog.response.connect((response) => {
            if (response == "remove") {
                model.remove_account(account, server_check.active);

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
        vcard_gender.selected = 0; // Unknown
        vcard_bday.text = "";
        vcard_adr_street.text = "";
        vcard_adr_pcode.text = "";
        vcard_adr_city.text = "";
        vcard_adr_region.text = "";
        vcard_adr_country.text = "";
        vcard_email.text = "";
        vcard_impp.text = "";
        vcard_phone.text = "";
        vcard_title.text = "";
        vcard_role.text = "";
        vcard_org.text = "";
        vcard_tz.text = "";
        vcard_url.text = "";
        vcard_desc.text = "";
        vcard_public_access.active = false;
        vcard_share_with_contacts.active = false;
        save_vcard_button.sensitive = false;

        var stream = model.stream_interactor.get_stream(account);
        if (stream == null) return;

        // Try VCard4 (XEP-0292) first
        var vcard4_module = stream.get_module<Xmpp.Xep.VCard4.Module>(Xmpp.Xep.VCard4.Module.IDENTITY);
        if (vcard4_module != null) {
            var vcard4 = yield vcard4_module.request(stream, account.bare_jid);
            if (vcard4 != null) {
                vcard_fn.text = vcard4.full_name ?? "";
                vcard_nickname.text = vcard4.nickname ?? "";
                
                if (vcard4.gender == "M") vcard_gender.selected = 1;
                else if (vcard4.gender == "F") vcard_gender.selected = 2;
                else if (vcard4.gender == "O") vcard_gender.selected = 3;
                else if (vcard4.gender == "N") vcard_gender.selected = 4;
                else vcard_gender.selected = 0;

                vcard_bday.text = vcard4.bday ?? "";
                vcard_email.text = vcard4.email ?? "";
                vcard_phone.text = vcard4.tel ?? "";
                vcard_title.text = vcard4.title ?? "";
                vcard_role.text = vcard4.role ?? "";
                vcard_org.text = vcard4.org ?? "";
                vcard_tz.text = vcard4.tz ?? "";
                vcard_url.text = vcard4.url ?? "";
                vcard_desc.text = vcard4.note ?? "";
                
                if (vcard4.impp != null) {
                    vcard_impp.text = vcard4.impp;
                }
                
                if (vcard4.adr_street != null) vcard_adr_street.text = vcard4.adr_street;
                if (vcard4.adr_locality != null) vcard_adr_city.text = vcard4.adr_locality;
                if (vcard4.adr_region != null) vcard_adr_region.text = vcard4.adr_region;
                if (vcard4.adr_pcode != null) vcard_adr_pcode.text = vcard4.adr_pcode;
                if (vcard4.adr_country != null) vcard_adr_country.text = vcard4.adr_country;
                
                // Check access model
                var pubsub_module = stream.get_module<Xmpp.Xep.Pubsub.Module>(Xmpp.Xep.Pubsub.Module.IDENTITY);
                if (pubsub_module != null) {
                    var config = yield pubsub_module.request_node_config(stream, null, "urn:ietf:params:xml:ns:vcard-4.0");
                    if (config != null) {
                        foreach (var field in config.fields) {
                            if (field.var == "pubsub#access_model") {
                                string val = field.get_value_string();
                                vcard_public_access.active = (val == "open");
                                
                                if (val == "open") {
                                    vcard_share_with_contacts.active = true;
                                    vcard_share_with_contacts.sensitive = false;
                                } else {
                                    vcard_share_with_contacts.sensitive = true;
                                    vcard_share_with_contacts.active = (val == "presence");
                                }
                                break;
                            }
                        }
                    }
                }

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
            
            // VCard-temp address handling
            if (vcard.adr_street != null) vcard_adr_street.text = vcard.adr_street;
            if (vcard.adr_locality != null) vcard_adr_city.text = vcard.adr_locality;
            if (vcard.adr_region != null) vcard_adr_region.text = vcard.adr_region;
            if (vcard.adr_pcode != null) vcard_adr_pcode.text = vcard.adr_pcode;
            if (vcard.adr_country != null) vcard_adr_country.text = vcard.adr_country;
        }
        save_vcard_button.sensitive = true;
    }

    private async void save_vcard() {
        save_vcard_button.sensitive = false;
        var stream = model.stream_interactor.get_stream(account);
        if (stream == null) {
            return;
        }

        // 1. Save VCard-temp (XEP-0054)
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
        
        if (vcard_adr_street.text != "") vcard.adr_street = vcard_adr_street.text;
        if (vcard_adr_city.text != "") vcard.adr_locality = vcard_adr_city.text;
        if (vcard_adr_region.text != "") vcard.adr_region = vcard_adr_region.text;
        if (vcard_adr_pcode.text != "") vcard.adr_pcode = vcard_adr_pcode.text;
        if (vcard_adr_country.text != "") vcard.adr_country = vcard_adr_country.text;
        
        try {
            var current_vcard = yield Xmpp.Xep.VCard.fetch_vcard(stream);
            if (current_vcard != null) {
                vcard.photo = current_vcard.photo;
                vcard.photo_type = current_vcard.photo_type;
            }
            
            yield Xmpp.Xep.VCard.publish_vcard(stream, vcard);
        } catch (Error e) {
            warning("Failed to save vCard: %s", e.message);
            var dialog = new Adw.AlertDialog("Failed to save profile", e.message);
            dialog.add_response("ok", _("OK"));
            dialog.present((Window)this.get_root());
        }

        // 2. Save VCard4 (XEP-0292)
        var vcard4_module = stream.get_module<Xmpp.Xep.VCard4.Module>(Xmpp.Xep.VCard4.Module.IDENTITY);
        if (vcard4_module != null) {
            var vcard4 = new Xmpp.Xep.VCard4.VCard4.create();
            vcard4.full_name = vcard_fn.text;
            vcard4.nickname = vcard_nickname.text;
            
            switch (vcard_gender.selected) {
                case 1: vcard4.gender = "M"; break;
                case 2: vcard4.gender = "F"; break;
                case 3: vcard4.gender = "O"; break;
                case 4: vcard4.gender = "N"; break;
                case 5: vcard4.gender = "U"; break;
                default: vcard4.gender = null; break;
            }

            vcard4.bday = vcard_bday.text;
            vcard4.email = vcard_email.text;
            vcard4.tel = vcard_phone.text;
            vcard4.title = vcard_title.text;
            vcard4.role = vcard_role.text;
            vcard4.org = vcard_org.text;
            vcard4.tz = vcard_tz.text;
            vcard4.url = vcard_url.text;
            vcard4.note = vcard_desc.text;
            
            if (vcard_impp.text != "") {
                vcard4.impp = vcard_impp.text;
            }
            
            if (vcard_adr_street.text != "" || vcard_adr_city.text != "" || vcard_adr_region.text != "" || vcard_adr_pcode.text != "" || vcard_adr_country.text != "") {
                vcard4.adr_street = vcard_adr_street.text;
                vcard4.adr_locality = vcard_adr_city.text;
                vcard4.adr_region = vcard_adr_region.text;
                vcard4.adr_pcode = vcard_adr_pcode.text;
                vcard4.adr_country = vcard_adr_country.text;
            }
            
            // Add a timeout to re-enable the button in case publish hangs
            uint timeout_id = Timeout.add_seconds(10, () => {
                if (!save_vcard_button.sensitive) {
                    save_vcard_button.sensitive = true;
                }
                return false;
            });

            // Configure Access Model
            var pubsub_options = new Xmpp.Xep.Pubsub.PublishOptions();
            if (vcard_public_access.active) {
                pubsub_options.set_access_model(Xmpp.Xep.Pubsub.ACCESS_MODEL_OPEN);
            } else if (vcard_share_with_contacts.active) {
                pubsub_options.set_access_model(Xmpp.Xep.Pubsub.ACCESS_MODEL_PRESENCE);
            } else {
                pubsub_options.set_access_model(Xmpp.Xep.Pubsub.ACCESS_MODEL_WHITELIST);
            }

            bool success = yield vcard4_module.publish(stream, vcard4, pubsub_options);
            Source.remove(timeout_id);
            
            if (success) {
                yield load_vcard();
            } else {
                warning("VCard4 save failed");
                // Re-enable button so user can try again
                save_vcard_button.sensitive = true;
            }
        } else {
            warning("VCard4 module not found");
        }

        // 3. Publish PEP Nickname (XEP-0172) for compatibility (e.g. Gajim)
        var pubsub_module = stream.get_module<Xmpp.Xep.Pubsub.Module>(Xmpp.Xep.Pubsub.Module.IDENTITY);
        if (pubsub_module != null && vcard_nickname.text != "") {
            var nick_node = new StanzaNode.build("nick", "http://jabber.org/protocol/nick");
            nick_node.put_node(new StanzaNode.text(vcard_nickname.text));
            
            bool res = yield pubsub_module.publish(stream, null, "http://jabber.org/protocol/nick", "current", nick_node);
            if (!res) {
                warning("Failed to publish PEP Nickname");
            }
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
        return _("Unknown Status");
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
            if (alt_minimum_baseline < minimum_baseline && alt_minimum_baseline != -1) minimum_baseline = alt_minimum_baseline;
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
