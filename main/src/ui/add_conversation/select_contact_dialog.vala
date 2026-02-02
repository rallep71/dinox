using Gee;
using Gdk;
using Gtk;

using Dino.Entities;
using Xmpp;

namespace Dino.Ui {

public class SelectContactDialog : Adw.Dialog {

    public signal void selected(Account account, Jid jid);

    public Button ok_button;

    private RosterList roster_list;
    private ListBox roster_list_box;
    private SelectJidFragment select_jid_fragment;
    private StreamInteractor stream_interactor;
    private Gee.List<Account> accounts;
    private Adw.HeaderBar header_bar;

    public SelectContactDialog(StreamInteractor stream_interactor, Gee.List<Account> accounts) {
        this.content_width = 460;
        this.content_height = 550;

        this.stream_interactor = stream_interactor;
        this.accounts = accounts;

        var toolbar_view = new Adw.ToolbarView();
        this.child = toolbar_view;

        setup_headerbar(toolbar_view);
        setup_view(toolbar_view);
    }

    public void set_filter(string str) {
        select_jid_fragment.set_filter(str);
    }

    private void setup_headerbar(Adw.ToolbarView toolbar_view) {
        Button cancel_button = new Button();
        cancel_button.set_label(_("Cancel"));
        cancel_button.visible = true;

        ok_button = new Button();
        ok_button.add_css_class("suggested-action");
        ok_button.sensitive = false;
        ok_button.visible = true;

        header_bar = new Adw.HeaderBar();
        header_bar.pack_start(cancel_button);
        header_bar.pack_end(ok_button);

        /* Account Selector is now handled internally by SelectJidFragment in the content area
        if (accounts.size > 1) {
            ...
        }
        */
        
        var window_title = new Adw.WindowTitle("", "");
        this.bind_property("title", window_title, "title", BindingFlags.SYNC_CREATE);
        header_bar.title_widget = window_title;
        
        toolbar_view.add_top_bar(header_bar);

        cancel_button.clicked.connect(() => { close(); });
        ok_button.clicked.connect(() => {
            ListRow? selected_row = roster_list_box.get_selected_row() != null ? roster_list_box.get_selected_row().get_child() as ListRow : null;
            if (selected_row != null) selected(selected_row.account, selected_row.jid);
            close();
        });
    }

    private void setup_view(Adw.ToolbarView toolbar_view) {
        roster_list = new RosterList(stream_interactor, accounts);
        roster_list_box = roster_list.get_list_box();
        roster_list_box.row_activated.connect(() => { ok_button.clicked(); });
        select_jid_fragment = new SelectJidFragment(stream_interactor, roster_list_box, accounts);
        select_jid_fragment.button_mode = SelectJidFragment.ButtonMode.CONTACT;
        select_jid_fragment.show_button_labels = true;
        select_jid_fragment.placeholder_text = _("Search or enter contact address...");
        select_jid_fragment.enable_contact_browse = true;
        select_jid_fragment.browse_contacts_clicked.connect(open_contact_browser);
        select_jid_fragment.add_jid.connect((row) => {
            AddContactDialog add_contact_dialog = new AddContactDialog(stream_interactor);
            add_contact_dialog.present(this);
        });
        select_jid_fragment.remove_jid.connect((row) => {
            ListRow list_row = roster_list_box.get_selected_row().child as ListRow;
            stream_interactor.get_module<RosterManager>(RosterManager.IDENTITY).remove_jid(list_row.account, list_row.jid);
        });
        select_jid_fragment.notify["done"].connect(() => {
            ok_button.sensitive = select_jid_fragment.done;
        });
        select_jid_fragment.search_directory_clicked.connect((query) => {
            // Use filter account or first enabled
            Account? account = select_jid_fragment.filter_account;
            if (account == null || !account.enabled) {
                foreach(var acc in accounts) { if (acc.enabled) { account = acc; break; } }
            }
            
            if (account != null) {
                var dialog = new UserSearchDialog(stream_interactor, account, query);
                dialog.contact_selected.connect((jid) => {
                    selected(account, jid);
                    close();
                });
                dialog.present(this);
            }
        });
        toolbar_view.content = select_jid_fragment;
    }
    
    private void open_contact_browser() {
        var dialog = new ContactBrowserDialog(stream_interactor, accounts);
        dialog.contact_selected.connect((account, jid) => {
            // Trigger selection as if user typed the JID
            selected(account, jid);
            close();
        });
        dialog.present(this);
    }
}

public class AddChatDialog : SelectContactDialog {

    public signal void added(Conversation conversation);

    public AddChatDialog(StreamInteractor stream_interactor, Gee.List<Account> accounts) {
        base(stream_interactor, accounts);
        title = _("Start Conversation");
        ok_button.label = _("Start");
        selected.connect((account, jid) => {
            Conversation conversation = stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY).create_conversation(jid, account, Conversation.Type.CHAT);
            stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY).start_conversation(conversation);
            added(conversation);
        });
    }
}

}
