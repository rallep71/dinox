using Gee;
using Gtk;

using Dino.Entities;
using Xmpp;

namespace Dino.Ui {

[GtkTemplate (ui = "/im/github/rallep71/DinoX/add_conversation/add_contact_dialog.ui")]
protected class AddContactDialog : Adw.Dialog {

    public Account? account {
        get { return account_combobox.active_account; }
        set { account_combobox.active_account = value; }
    }

    public string jid {
        get { return jid_entry.text; }
        set { jid_entry.text = value; }
    }

    [GtkChild] private unowned AccountComboBox account_combobox;
    [GtkChild] private unowned Button ok_button;
    [GtkChild] private unowned Button cancel_button;
    [GtkChild] private unowned Entry jid_entry;
    [GtkChild] private unowned Entry alias_entry;
    [GtkChild] private unowned Box content_area; // Need to add this ID to the UI file or find the box programmatically

    private StreamInteractor stream_interactor;

    public AddContactDialog(StreamInteractor stream_interactor) {
        this.stream_interactor = stream_interactor;
        account_combobox.initialize(stream_interactor);

        cancel_button.clicked.connect(() => { close(); });
        ok_button.clicked.connect(on_ok_button_clicked);
        jid_entry.changed.connect(on_jid_entry_changed);
        
        // Add Search Button
        var search_btn = new Button.with_label(_("Search Directory"));
        search_btn.margin_top = 0;
        search_btn.margin_bottom = 20;
        search_btn.halign = Align.CENTER;
        search_btn.add_css_class("pill");
        search_btn.clicked.connect(() => {
            var search_dialog = new UserSearchDialog(stream_interactor, account);
            search_dialog.contact_selected.connect((jid) => {
                this.jid = jid.to_string();
            });
            search_dialog.present(this);
        });
        
        content_area.append(search_btn);
    }

    private void on_ok_button_clicked() {
        string? alias = alias_entry.text == "" ? null : alias_entry.text;
        try {
            Jid jid = new Jid(jid_entry.text);
            stream_interactor.get_module<RosterManager>(RosterManager.IDENTITY).add_jid(account, jid, alias);
            stream_interactor.get_module<PresenceManager>(PresenceManager.IDENTITY).request_subscription(account, jid);
            
            // Clear fields for next use
            jid_entry.text = "";
            alias_entry.text = "";
            
            close();
        } catch (InvalidJidError e) {
            warning("Tried to add contact with invalid Jid: %s", e.message);
        }
    }

    private void on_jid_entry_changed() {
        try {
            Jid parsed_jid = new Jid(jid_entry.text);
            // Disable button if: invalid JID, has resource, already in roster, or is own JID
            ok_button.sensitive = parsed_jid != null && 
                    parsed_jid.resourcepart == null &&
                    stream_interactor.get_module<RosterManager>(RosterManager.IDENTITY).get_roster_item(account, parsed_jid) == null &&
                    !account.bare_jid.equals_bare(parsed_jid);
        } catch (InvalidJidError e) {
            ok_button.sensitive = false;
        }
    }
}

}
