using Gee;
using Gtk;

using Dino.Entities;
using Xmpp;

namespace Dino.Ui {

[GtkTemplate (ui = "/im/github/rallep71/DinoX/add_conversation/add_groupchat_dialog.ui")]
protected class AddGroupchatDialog : Gtk.Window {

    [GtkChild] private unowned Stack accounts_stack;
    [GtkChild] private unowned AccountComboBox account_combobox;
    [GtkChild] private unowned Button ok_button;
    [GtkChild] private unowned Button cancel_button;
    [GtkChild] private unowned Entry jid_entry;
    [GtkChild] private unowned Entry alias_entry;
    [GtkChild] private unowned Entry nick_entry;
    [GtkChild] private unowned CheckButton private_room_checkbutton;

    private StreamInteractor stream_interactor;
    private bool alias_entry_changed = false;

    public AddGroupchatDialog(StreamInteractor stream_interactor) {
        this.stream_interactor = stream_interactor;
        ok_button.label = _("Add");
        ok_button.add_css_class("suggested-action"); // TODO why doesn't it work in XML
        accounts_stack.set_visible_child_name("combobox");
        account_combobox.initialize(stream_interactor);

        cancel_button.clicked.connect(() => { close(); });
        ok_button.clicked.connect(on_ok_button_clicked);

        jid_entry.changed.connect(on_jid_key_release);
        nick_entry.changed.connect(check_ok);
    }

    private void on_jid_key_release() {
        check_ok();
        if (!alias_entry_changed) {
            try {
                Jid parsed_jid = new Jid(get_effective_jid());
                alias_entry.text = parsed_jid != null && parsed_jid.localpart != null ? parsed_jid.localpart : jid_entry.text;
            } catch (InvalidJidError e) {
                alias_entry.text = jid_entry.text;
            }
        }
    }

    private string get_effective_jid() {
        string text = jid_entry.text;
        if (text.contains("@")) {
            return text;
        }
        var account = account_combobox.active_account;
        if (account != null) {
            return "%s@conference.%s".printf(text, account.domainpart);
        }
        return text;
    }

    private void check_ok() {
        try {
            Jid parsed_jid = new Jid(get_effective_jid());
            ok_button.sensitive = parsed_jid != null && parsed_jid.localpart != null && parsed_jid.resourcepart == null;
        } catch (InvalidJidError e) {
            ok_button.sensitive = false;
        }
    }

    private void on_ok_button_clicked() {
        try {
            Conference conference = new Conference();
            conference.jid = new Jid(get_effective_jid());
            conference.nick = nick_entry.text != "" ? nick_entry.text : null;
            conference.name = alias_entry.text;
            stream_interactor.get_module(MucManager.IDENTITY).add_bookmark(account_combobox.active_account, conference);
            
            // If "Create as private room" is checked, configure the room after joining
            if (private_room_checkbutton.active) {
                configure_private_room(account_combobox.active_account, conference.jid);
            }
            
            close();
        } catch (InvalidJidError e) {
            warning("Ignoring invalid conference Jid: %s", e.message);
        }
    }
    
    private void configure_private_room(Account account, Jid room_jid) {
        // Wait a bit for the room to be joined, then configure it
        Timeout.add_seconds(2, () => {
            configure_room_async.begin(account, room_jid);
            return Source.REMOVE;
        });
    }
    
    private async void configure_room_async(Account account, Jid room_jid) {
        Xep.DataForms.DataForm? data_form = yield stream_interactor.get_module(MucManager.IDENTITY).get_config_form(account, room_jid);
        if (data_form == null) return;
        
        // Configure as private room (members-only + non-anonymous + persistent)
        foreach (Xep.DataForms.DataForm.Field field in data_form.fields) {
            switch (field.var) {
                case "muc#roomconfig_membersonly":
                    if (field.type_ == Xep.DataForms.DataForm.Type.BOOLEAN) {
                        ((Xep.DataForms.DataForm.BooleanField) field).value = true;
                    }
                    break;
                case "muc#roomconfig_whois":
                    if (field.type_ == Xep.DataForms.DataForm.Type.LIST_SINGLE) {
                        ((Xep.DataForms.DataForm.ListSingleField) field).value = "anyone";
                    }
                    break;
                case "muc#roomconfig_persistentroom":
                    if (field.type_ == Xep.DataForms.DataForm.Type.BOOLEAN) {
                        ((Xep.DataForms.DataForm.BooleanField) field).value = true;
                    }
                    break;
            }
        }
        yield stream_interactor.get_module(MucManager.IDENTITY).set_config_form(account, room_jid, data_form);
    }
}

}
