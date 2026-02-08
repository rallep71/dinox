/*
 * Copyright (C) 2025 Ralf Peter <dinox@handwerker.jetzt>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

using Gee;
using Gtk;
using Pango;

using Dino.Entities;
using Xmpp;

namespace Dino.Ui.ManageAccounts {

[GtkTemplate (ui = "/im/github/rallep71/DinoX/preferences_window/add_account_dialog.ui")]
public class AddAccountDialog : Adw.Dialog {

    public signal void added(Account account);

    enum Page {
        SIGN_IN,
        SIGN_IN_TLS_ERROR,
        CREATE_ACCOUNT_SELECT_SERVER,
        CREATE_ACCOUNT_REGISTER_FORM,
        SUCCESS
    }

    [GtkChild] private unowned Stack stack;

    [GtkChild] private unowned Revealer notification_revealer;
    [GtkChild] private unowned Label notification_label;

    // Sign in - JID
    [GtkChild] private unowned Box sign_in_box;
    [GtkChild] private unowned Label sign_in_error_label;
    [GtkChild] private unowned Adw.EntryRow jid_entry;
    [GtkChild] private unowned Adw.PreferencesGroup password_group;
    [GtkChild] private unowned Adw.PasswordEntryRow password_entry;
    [GtkChild] private unowned Adw.EntryRow custom_host_entry;
    [GtkChild] private unowned Adw.EntryRow custom_port_entry;
    [GtkChild] private unowned Button sign_in_continue_button;
    [GtkChild] private unowned Spinner sign_in_continue_spinner;
    [GtkChild] private unowned Button sign_in_serverlist_button;

    // Sign in - TLS error
    [GtkChild] private unowned Box sign_in_tls_box;
    [GtkChild] private unowned Label sign_in_tls_label;
    [GtkChild] private unowned Button sign_in_tls_back_button;
    [GtkChild] private unowned Button sign_in_tls_trust_button;

    // Select Server
    [GtkChild] private unowned Box create_account_box;
    [GtkChild] private unowned Button login_button;
    [GtkChild] private unowned Spinner select_server_continue_spinner;
    [GtkChild] private unowned Button select_server_continue;
    [GtkChild] private unowned Label register_form_continue_label;
    [GtkChild] private unowned ListBox server_list_box;
    [GtkChild] private unowned Entry server_entry;

    // Register Form
    [GtkChild] private unowned Button back_button;
    [GtkChild] private unowned Box register_box;
    [GtkChild] private unowned Box form_box;
    [GtkChild] private unowned Spinner register_form_continue_spinner;
    [GtkChild] private unowned Button register_form_continue;

    // Success
    [GtkChild] private unowned Box success_box;
    [GtkChild] private unowned Label success_description;
    [GtkChild] private unowned Button success_continue_button;

    private static string[] server_list = new string[]{
        "5222.de",
        "jabber.fr",
        "movim.eu",
        "yax.im"
    };

    private StreamInteractor stream_interactor;
    private Database db;
    private HashMap<ListBoxRow, string> list_box_jids = new HashMap<ListBoxRow, string>();
    private Jid? server_jid = null;
    private Jid? login_jid = null;
    private Xep.InBandRegistration.Form? form = null;
    private TlsCertificate? pending_tls_certificate = null;
    private TlsCertificateFlags pending_tls_flags;

    public AddAccountDialog(StreamInteractor stream_interactor, Database db, bool start_registration = false) {
        this.stream_interactor = stream_interactor;
        this.db = db;
        this.title = _("Add Account");

        // Sign in - Jid
        jid_entry.changed.connect(on_jid_entry_changed);
        sign_in_continue_button.clicked.connect(on_sign_in_continue_button_clicked);
        sign_in_serverlist_button.clicked.connect(show_select_server);

        // Sign in - TLS error
        sign_in_tls_back_button.clicked.connect(() => show_sign_in() );
        sign_in_tls_trust_button.clicked.connect(() => on_tls_trust_button_clicked.begin() );

        // Select Server
        server_entry.changed.connect(() => {
            try {
                Jid jid = new Jid(server_entry.text);
                select_server_continue.sensitive = jid != null && jid.localpart == null && jid.resourcepart == null;
            } catch (InvalidJidError e) {
                select_server_continue.sensitive = false;
            }
        });
        select_server_continue.clicked.connect(on_select_server_continue);
        login_button.clicked.connect(() => show_sign_in() );

        foreach (string server in server_list) {
            ListBoxRow list_box_row = new ListBoxRow();
            list_box_row.set_child(new Label(server) { xalign=0, margin_start=7, margin_end=7 });
            list_box_jids[list_box_row] = server;
            server_list_box.append(list_box_row);
        }

        // Register Form
        register_form_continue.clicked.connect(on_register_form_continue_clicked);
        back_button.clicked.connect(() => {
            show_select_server();
            back_button.visible = false;
        });

        // Success
        success_continue_button.clicked.connect(() => close());

        if (start_registration) {
            show_select_server();
        } else {
            show_sign_in();
        }
    }

    private void show_sign_in(bool keep_jid = false) {
        switch_stack_page(Page.SIGN_IN);

        this.title = _("Sign in");

        set_default_widget(sign_in_continue_button);
        sign_in_error_label.visible = false;
        sign_in_continue_spinner.visible = false;
        if (!keep_jid) {
            jid_entry.text = "";
            jid_entry.grab_focus();
        }
        password_entry.text = "";
        password_group.visible = false;
        custom_host_entry.text = "";
        custom_port_entry.text = "";
        sign_in_serverlist_button.visible = true;
    }

    private void show_tls_error(string domain, TlsCertificateFlags error_flags, TlsCertificate? cert = null) {
        switch_stack_page(Page.SIGN_IN_TLS_ERROR);

        // Store certificate for potential pinning
        pending_tls_certificate = cert;
        pending_tls_flags = error_flags;
        sign_in_tls_trust_button.visible = (cert != null);

        string error_desc = _("The server could not prove that it is %s.").printf("<b>" + domain + "</b>");
        if (TlsCertificateFlags.UNKNOWN_CA in error_flags) {
            error_desc += " " + _("Its security certificate is not trusted by your operating system.");
        } else if (TlsCertificateFlags.BAD_IDENTITY in error_flags) {
            error_desc += " " + _("Its security certificate is issued to another domain.");
        } else if (TlsCertificateFlags.NOT_ACTIVATED in error_flags) {
            error_desc += " " + _("Its security certificate will only become valid in the future.");
        } else if (TlsCertificateFlags.EXPIRED in error_flags) {
            error_desc += " " + _("Its security certificate is expired.");
        }
        sign_in_tls_label.label = error_desc;
    }

    private async void on_tls_trust_button_clicked() {
        if (pending_tls_certificate == null || login_jid == null) return;

        // Pin the certificate
        stream_interactor.connection_manager.pin_certificate(
            login_jid.domainpart, pending_tls_certificate, pending_tls_flags);

        // Clear pending state
        pending_tls_certificate = null;

        // Go back and retry with the now-pinned certificate
        show_sign_in(true);

        // Auto-retry the sign-in
        yield on_sign_in_continue_button_clicked();
    }

    private void show_select_server() {
        switch_stack_page(Page.CREATE_ACCOUNT_SELECT_SERVER);

        this.title = _("Create account");
        server_entry.text = "";
        server_entry.grab_focus();
        set_default_widget(select_server_continue);

        server_list_box.row_activated.disconnect(on_server_list_row_activated);
        server_list_box.unselect_all();
        server_list_box.row_activated.connect(on_server_list_row_activated);
    }

    private void show_register_form() {
        switch_stack_page(Page.CREATE_ACCOUNT_REGISTER_FORM);

        set_default_widget(register_form_continue);
    }

    private void show_success(Account account) {
        switch_stack_page(Page.SUCCESS);

        success_description.label = _("You can now use the account %s.").printf("<b>" + Markup.escape_text(account.bare_jid.to_string()) + "</b>");

        set_default_widget(success_continue_button);
    }

    private void on_jid_entry_changed() {
        try {
            login_jid = new Jid(jid_entry.text);
            if (login_jid.localpart != null && login_jid.resourcepart == null) {
                sign_in_continue_button.sensitive = true;
            } else {
                sign_in_continue_button.sensitive = false;
            }
        } catch (InvalidJidError e) {
            sign_in_continue_button.sensitive = false;
        }
    }

    private async void on_sign_in_continue_button_clicked() {
        try {
            login_jid = new Jid(jid_entry.text);
            sign_in_tls_label.label = "";
            sign_in_error_label.visible = false;
            sign_in_continue_button.sensitive = false;
            sign_in_continue_spinner.visible = true;

            ulong jid_entry_changed_handler_id = -1;
            jid_entry_changed_handler_id = jid_entry.changed.connect(() => {
                jid_entry.disconnect(jid_entry_changed_handler_id);
                show_sign_in(true);
                return;
            });

            if (password_group.visible) {
                // JID + Psw fields were visible: Try to log in
                string password = password_entry.text;
                Account account = new Account(login_jid, password);
                
                // Set custom host/port if provided
                if (custom_host_entry.text.length > 0) {
                    account.custom_host = custom_host_entry.text;
                }
                if (custom_port_entry.text.length > 0) {
                    int port = int.parse(custom_port_entry.text);
                    if (port > 0 && port <= 65535) {
                        account.custom_port = port;
                    }
                }

                ConnectionManager.ConnectionError.Source? error = yield stream_interactor.get_module<Register>(Register.IDENTITY).add_check_account(account);
                sign_in_continue_spinner.visible = false;
                sign_in_continue_button.sensitive = true;

                if (error != null) {
                    sign_in_error_label.visible = true;
                    switch (error) {
                        case ConnectionManager.ConnectionError.Source.SASL:
                            sign_in_error_label.label = _("Wrong username or password");
                            break;
                        default:
                            sign_in_error_label.label = _("Something went wrong");
                            break;
                    }
                } else {
                    add_activate_account(account);
                    show_success(account);
                }
            } else {
                // Only JID field was visible: Check if server exists (skip if custom host set)
                bool has_custom_host = custom_host_entry.text.length > 0;
                
                if (!has_custom_host) {
                    Register register_module = stream_interactor.get_module<Register>(Register.IDENTITY);
                    Register.ServerAvailabilityReturn server_status = yield register_module.check_server_availability(login_jid);
                    sign_in_continue_spinner.visible = false;
                    sign_in_continue_button.sensitive = true;
                    if (!server_status.available) {
                        if (server_status.error_flags != null) {
                            show_tls_error(login_jid.domainpart, server_status.error_flags, server_status.tls_certificate);
                        } else {
                            sign_in_error_label.visible = true;
                            sign_in_error_label.label = _("Could not connect to %s").printf(login_jid.domainpart);
                        }
                        return;
                    }
                }
                
                // Show password field (server OK or custom host set)
                sign_in_continue_spinner.visible = false;
                sign_in_continue_button.sensitive = true;
                password_group.visible = true;
                password_entry.grab_focus();
                sign_in_serverlist_button.visible = false;
            }
        } catch (InvalidJidError e) {
            warning("Invalid address from interface allowed login: %s", e.message);
            sign_in_error_label.visible = true;
            sign_in_error_label.label = _("Invalid address");
        }
    }

    private void on_select_server_continue() {
        try {
            server_jid = new Jid(server_entry.text);
            request_show_register_form.begin(server_jid);
        } catch (InvalidJidError e) {
            warning("Invalid address from interface allowed server: %s", e.message);
            display_notification(_("Invalid address"));
        }
    }

    private void on_server_list_row_activated(ListBox box, ListBoxRow row) {
        try {
            server_jid = new Jid(list_box_jids[row]);
            request_show_register_form.begin(server_jid);
        } catch (InvalidJidError e) {
            warning("Invalid address from selected server: %s", e.message);
            display_notification(_("Invalid address"));
        }
    }

    private async void request_show_register_form(Jid server_jid) {
        select_server_continue_spinner.visible = true;
        Register.RegistrationFormReturn form_return = yield Register.get_registration_form(server_jid);
        if (select_server_continue_spinner == null) {
            return;
        }
        select_server_continue_spinner.visible = false;
        if (form_return.form != null) {
            form = form_return.form;
            set_register_form(server_jid, form);
            show_register_form();
        } else if (form_return.error_flags != null) {
            show_tls_error(server_jid.domainpart, form_return.error_flags);
        } else {
            display_notification(_("No response from server"));
        }
    }

    private void set_register_form(Jid server, Xep.InBandRegistration.Form form) {
        Widget widget = form_box.get_first_child();
        while (widget != null) {
            form_box.remove(widget);
            widget = form_box.get_first_child();
        }

        this.title = _("Register on %s").printf(server.to_string());

        if (form.oob != null) {
            form_box.append(new Label(_("The server requires to sign up through a website")));
            form_box.append(new Label(@"<a href=\"$(form.oob)\">$(form.oob)</a>") { use_markup=true });
            register_form_continue_label.label = _("Open website");
            register_form_continue.visible = true;
            register_form_continue.grab_focus();
        } else if (form.fields.size > 0) {
            if (form.instructions != null && form.instructions != "") {
                string markup_instructions = Util.parse_add_markup(Util.unbreak_space_around_non_spacing_mark(form.instructions), null, true, false);
                form_box.append(new Label(markup_instructions) { use_markup=true, xalign=0, margin_top=7,
                    wrap=true, wrap_mode=Pango.WrapMode.WORD_CHAR });
            }
            var form_preference_group = Util.rows_to_preference_group(Util.get_data_form_view_model(form), "");
            form_box.append(form_preference_group);
            register_form_continue.visible = true;
            register_form_continue_label.label = _("Register");
        } else {
            form_box.append(new Label(_("Check %s for information on how to sign up").printf(@"<a href=\"http://$(server)\">$(server)</a>")) { use_markup=true });
            register_form_continue.visible = false;
        }
    }

    private async void on_register_form_continue_clicked() {
        notification_revealer.set_reveal_child(false);
        // Button is opening a registration website
        if (form.oob != null) {
            try {
                AppInfo.launch_default_for_uri(form.oob, null);
            } catch (Error e) {
                warning("AddAccountDialog: Failed to launch registration URI %s: %s", form.oob, e.message);
            }
            show_sign_in();
            return;
        }

        register_form_continue_spinner.visible = true;
        string? error = yield Register.submit_form(server_jid, form);
        if (register_form_continue_spinner == null) {
            return;
        }
        register_form_continue_spinner.visible = false;
        if (error == null) {
            string? username = null, password = null;
            foreach (Xep.DataForms.DataForm.Field field in form.fields) {
                switch (field.var) {
                    case "username": username = field.get_value_string(); break;
                    case "password": password = field.get_value_string(); break;
                }
            }
            try {
                Account account = new Account(new Jid.components(username, server_jid.domainpart, null), password);
                add_activate_account(account);
                show_success(account);
            } catch (InvalidJidError e) {
                warning("Invalid address from components of registration: %s", e.message);
                display_notification(_("Invalid address"));
            }
        } else {
            display_notification(error);
        }
    }

    private void display_notification(string text) {
        notification_label.label = text;
        notification_revealer.set_reveal_child(true);
        Timeout.add_seconds(5, () => {
            notification_revealer.set_reveal_child(false);
            return false;
        });
    }

    private void add_activate_account(Account account) {
        account.enabled = true;
        account.persist(db);
        stream_interactor.connect_account(account);
        added(account);
    }

    private void switch_stack_page(Page page) {
        sign_in_box.visible = page == SIGN_IN;
        sign_in_tls_box.visible = page == SIGN_IN_TLS_ERROR;
        create_account_box.visible = page == CREATE_ACCOUNT_SELECT_SERVER;
        register_box.visible = page == CREATE_ACCOUNT_REGISTER_FORM;
        success_box.visible = page == SUCCESS;

        stack.visible_child_name = get_visible_stack_child_name(page);

        back_button.visible = page == CREATE_ACCOUNT_REGISTER_FORM;
    }

    private string get_visible_stack_child_name(Page page) {
        switch (page) {
            case SIGN_IN: return "login_jid";
            case SIGN_IN_TLS_ERROR: return "tls_error";
            case CREATE_ACCOUNT_SELECT_SERVER: return "server";
            case CREATE_ACCOUNT_REGISTER_FORM: return "form";
            case SUCCESS: return "success";
        }
        warning("Unknown Page: %d", page);
        return "login_jid";
    }
}

}
