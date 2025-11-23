using Gee;
using Gtk;
using Dino.Entities;
using Xmpp;

namespace Dino.Ui {

public class MucAdminDialog : Gtk.Window {

    private StreamInteractor stream_interactor;
    private Account account;
    private Jid muc_jid;

    private ListBox list_box;
    private DropDown affiliation_dropdown;
    private string[] affiliation_ids = { "owner", "admin", "member", "outcast" };
    private Button add_button;
    private Button remove_button;

    private string current_affiliation = "member";
    private ArrayList<ListBoxRow> rows = new ArrayList<ListBoxRow>();

    public MucAdminDialog(StreamInteractor stream_interactor, Account account, Jid muc_jid) {
        this.stream_interactor = stream_interactor;
        this.account = account;
        this.muc_jid = muc_jid;

        this.title = _("Room Administration");
        this.modal = true;
        this.default_width = 400;
        this.default_height = 500;

        setup_ui();
        load_list.begin();
    }

    private void setup_ui() {
        Box main_box = new Box(Orientation.VERTICAL, 0);
        this.set_child(main_box);

        // Header / Toolbar
        Box header_box = new Box(Orientation.HORIZONTAL, 6);
        header_box.margin_top = 6;
        header_box.margin_bottom = 6;
        header_box.margin_start = 6;
        header_box.margin_end = 6;

        string[] items = { _("Owners"), _("Admins"), _("Members"), _("Banned") };
        var model = new StringList(items);

        affiliation_dropdown = new DropDown(model, null);
        affiliation_dropdown.selected = 2;
        affiliation_dropdown.notify["selected"].connect(() => {
            current_affiliation = affiliation_ids[affiliation_dropdown.selected];
            load_list.begin();
        });
        header_box.append(affiliation_dropdown);

        main_box.append(header_box);

        // List
        ScrolledWindow scrolled = new ScrolledWindow();
        scrolled.vexpand = true;
        list_box = new ListBox();
        list_box.selection_mode = SelectionMode.SINGLE;
        list_box.row_selected.connect(update_buttons);
        scrolled.set_child(list_box);
        main_box.append(scrolled);

        // Bottom Action Bar
        Box action_box = new Box(Orientation.HORIZONTAL, 6);
        action_box.margin_top = 6;
        action_box.margin_bottom = 6;
        action_box.margin_start = 6;
        action_box.margin_end = 6;

        add_button = new Button.with_label(_("Add..."));
        add_button.hexpand = true;
        add_button.clicked.connect(on_add_clicked);
        action_box.append(add_button);

        remove_button = new Button.with_label(_("Remove"));
        remove_button.sensitive = false;
        remove_button.clicked.connect(on_remove);
        action_box.append(remove_button);

        main_box.append(action_box);
    }

    private async void load_list() {
        // Clear list
        ListBoxRow? row;
        while ((row = list_box.get_row_at_index(0)) != null) {
            list_box.remove(row);
        }
        rows.clear();
        remove_button.sensitive = false;

        var jids = yield stream_interactor.get_module(MucManager.IDENTITY).get_affiliations(account, muc_jid, current_affiliation);
        if (jids != null) {
            foreach (Jid jid in jids) {
                var label = new Label(jid.to_string());
                label.xalign = 0;
                label.margin_start = 10;
                label.margin_end = 10;
                label.margin_top = 10;
                label.margin_bottom = 10;
                
                var list_row = new ListBoxRow();
                list_row.set_child(label);
                list_row.set_data("jid", jid);
                
                list_box.append(list_row);
                rows.add(list_row);
            }
        }
    }

    private void update_buttons() {
        remove_button.sensitive = list_box.get_selected_row() != null;
    }

    private void on_add_clicked() {
        var accounts = new ArrayList<Account>();
        accounts.add(account);

        SelectContactDialog dialog = new SelectContactDialog(stream_interactor, accounts);
        dialog.title = _("Add Member");
        dialog.ok_button.label = _("Add");
        
        dialog.transient_for = this;

        dialog.selected.connect((account, jid) => {
            stream_interactor.get_module(MucManager.IDENTITY).set_affiliation(account, muc_jid, jid, current_affiliation);
            dialog.close();
            // Reload list after a short delay to allow server to process
            Timeout.add(500, () => { load_list.begin(); return false; });
        });
        
        dialog.present();
    }

    private void on_remove() {
        var row = list_box.get_selected_row();
        if (row == null) return;

        Jid? jid = row.get_data<Jid>("jid");
        if (jid != null) {
            stream_interactor.get_module(MucManager.IDENTITY).set_affiliation(account, muc_jid, jid, "none");
            // Reload list after a short delay
            Timeout.add(500, () => { load_list.begin(); return false; });
        }
    }
}

}
