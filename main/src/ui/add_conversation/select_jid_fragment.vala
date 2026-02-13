using Gee;
using Gtk;

using Dino.Entities;
using Xmpp;
using Xmpp.Xep;

namespace Dino.Ui {

[GtkTemplate (ui = "/im/github/rallep71/DinoX/add_conversation/select_jid_fragment.ui")]
public class SelectJidFragment : Gtk.Box {

    public signal void add_jid();
    public signal void remove_jid(ListRow row);
    public bool done {
        get { return list.get_selected_row() != null; }
        private set {}
    }

    public bool show_button_labels {
        get { return _show_button_labels; }
        set {
            _show_button_labels = value;
            update_button_labels_visibility();
        }
    }
    private bool _show_button_labels = false;
    
    public enum ButtonMode {
        CONTACT,
        GROUP
    }
    
    public ButtonMode button_mode {
        get { return _button_mode; }
        set {
            _button_mode = value;
            update_button_texts();
        }
    }
    private ButtonMode _button_mode = ButtonMode.CONTACT;
    
    public string placeholder_text {
        get { return entry.placeholder_text; }
        set { entry.placeholder_text = value; }
    }

    [GtkChild] private unowned Entry entry;
    [GtkChild] private unowned Box box;
    [GtkChild] private unowned Button add_button;
    [GtkChild] private unowned Button remove_button;
    [GtkChild] private unowned Label add_button_label;
    [GtkChild] private unowned Label remove_button_label;
    [GtkChild] private unowned Box account_selector_box;
    [GtkChild] private unowned DropDown account_dropdown;

    private StreamInteractor stream_interactor;
    private Gee.List<Account> accounts;
    private ArrayList<Widget> added_rows = new ArrayList<Widget>();

    private ListBox list;
    private string[]? filter_values;
    private Gee.List<ServiceDiscovery.Item> cached_public_rooms = new Gee.ArrayList<ServiceDiscovery.Item>();
    private bool discovery_started = false;
    private ArrayList<Account?> dropdown_accounts = new ArrayList<Account?>();

    public bool enable_muc_search {
        get { return _enable_muc_search; }
        set {
            _enable_muc_search = value;
            update_search_icon();
            if (value && !discovery_started) {
                discovery_started = true;
                fetch_public_rooms.begin();
            }
        }
    }
    private bool _enable_muc_search = false;
    
    public bool enable_contact_browse {
        get { return _enable_contact_browse; }
        set {
            _enable_contact_browse = value;
            update_search_icon();
        }
    }
    private bool _enable_contact_browse = false;
    
    public Account? filter_account { 
        get { return _filter_account; }
        set {
            _filter_account = value;
            list.invalidate_filter();
            
            // Sync dropdown if changed externally
            if (account_dropdown != null && dropdown_accounts.size > 0 && 
                ((_filter_account == null && dropdown_accounts[(int)account_dropdown.selected] != null) ||
                 (_filter_account != null && dropdown_accounts[(int)account_dropdown.selected] != _filter_account))) {
                 
                for (int i=0; i < dropdown_accounts.size; i++) {
                     if (dropdown_accounts[i] == _filter_account) {
                         // Cast simple int to avoid type issues if needed, though GObject usually accepts int
                         // but direct property set on Vala binding is uint
                         account_dropdown.selected = (uint) i;
                         break;
                     }
                }
            }
            
            // Re-run set_filter to update "added_rows" (e.g. Add Contact via...) which are not in the list model but added manually
            string current_text = entry.text;
            if (current_text != "") set_filter(current_text);
        }
    }
    private Account? _filter_account;
    public string text { get { return entry.text; } }

    public signal void browse_contacts_clicked();
    public signal void search_directory_clicked(string query);

    private async void fetch_public_rooms() {
        var seen_jids = new Gee.HashSet<string>();
        
        foreach (Account account in accounts) {
            if (!account.enabled) continue;
            try {
                Jid? muc_server = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).default_muc_server.get(account);
                if (muc_server == null) {
                    muc_server = new Jid("conference." + account.domainpart);
                }
                
                var stream = stream_interactor.get_stream(account);
                if (stream != null) {
                    var disco_module = stream.get_module<ServiceDiscovery.Module>(ServiceDiscovery.Module.IDENTITY);
                    var result = yield disco_module.request_items(stream, muc_server);
                    if (result != null) {
                        foreach (var item in result.items) {
                            string jid_str = item.jid.to_string();
                            // Only add if we haven't seen this JID before
                            if (!seen_jids.contains(jid_str)) {
                                cached_public_rooms.add(item);
                                seen_jids.add(jid_str);
                            }
                        }
                    }
                    // Refresh filter if user has typed something
                    if (entry.text != "") set_filter(entry.text);
                }
            } catch (Error e) {
                // Ignore discovery errors
            }
        }
    }

    public SelectJidFragment(StreamInteractor stream_interactor, ListBox list, Gee.List<Account> accounts) {
        this.stream_interactor = stream_interactor;
        this.list = list;
        this.accounts = accounts;

        // Hide search icon by default
        entry.secondary_icon_name = null;

        list.activate_on_single_click = false;
        list.vexpand = true;
        box.append(list);

        list.set_sort_func(sort);
        list.set_filter_func(filter);
        list.set_header_func(header);
        list.row_selected.connect(check_buttons_active);
        list.row_selected.connect(update_button_label);
        list.row_selected.connect(() => { done = true; }); // just for notifying
        entry.changed.connect(() => { set_filter(entry.text); });
        entry.icon_press.connect(on_icon_press);
        
        add_button.clicked.connect(() => { add_jid(); });
        remove_button.clicked.connect(() => {
            var list_row = list.get_selected_row();
            if (list_row == null) return;
            remove_jid(list_row.child as ListRow);
        });
        
        setup_account_selector();
    }
    
    private void setup_account_selector() {
        if (accounts.size <= 1) {
            account_selector_box.visible = false;
            return;
        }

        var model = new StringList(null);
        model.append(_("All Accounts"));
        dropdown_accounts.add(null);

        bool has_active = false;
        foreach (var account in accounts) {
            if (account.enabled) {
                model.append(account.display_name);
                dropdown_accounts.add(account);
                has_active = true;
            }
        }
        
        if (!has_active) {
             account_selector_box.visible = false;
             return;
        }

        account_dropdown.model = model;
        account_dropdown.notify["selected"].connect(() => {
            int idx = (int) account_dropdown.selected;
            if (idx >= 0 && idx < dropdown_accounts.size) {
                this.filter_account = dropdown_accounts[idx];
            }
        });
        
        account_selector_box.visible = true;
    }

    private void update_search_icon() {
        if (enable_muc_search) {
            entry.secondary_icon_name = "system-search-symbolic";
            entry.secondary_icon_tooltip_text = _("Browse Rooms");
        } else {
            // Disable the confusing "Browse Contacts" icon since we now have inline search
            entry.secondary_icon_name = null;
            entry.secondary_icon_tooltip_text = null;
        }
    }
    
    private void on_icon_press(EntryIconPosition pos) {
        if (pos == EntryIconPosition.SECONDARY) {
            if (enable_muc_search) {
                open_room_browser();
            } else if (enable_contact_browse) {
                browse_contacts_clicked();
            }
        }
    }

    private void open_room_browser() {
        Account? account = null;
        if (filter_account != null && filter_account.enabled) {
            account = filter_account;
        } else {
            foreach(var acc in accounts) {
                if (acc.enabled) {
                    account = acc;
                    break;
                }
            }
        }
        
        if (account != null) {
            var dialog = new RoomBrowserDialog(stream_interactor, account);
            var root = this.get_root() as Gtk.Window;
            
            dialog.room_selected.connect((jid) => {
                entry.text = jid.to_string();
            });
            dialog.present(root);
        }
    }
    
    private void update_button_labels_visibility() {
        add_button_label.visible = _show_button_labels;
        remove_button_label.visible = _show_button_labels;
    }
    
    private void update_button_texts() {
        if (_button_mode == ButtonMode.CONTACT) {
            add_button_label.label = _("Add Contact");
            remove_button_label.label = _("Delete Contact");
        } else {
            add_button_label.label = _("Add Group");
            remove_button_label.label = _("Leave Group");
        }
    }
    
    private void update_button_label() {
        if (!_show_button_labels) return;
        
        // For GROUP mode, always show "Leave Group"
        if (_button_mode != ButtonMode.GROUP) return;
        
        remove_button_label.label = _("Leave Group");
    }

    public void set_filter(string str) {
        if (entry.text != str) entry.text = str;

        foreach (Widget row in added_rows) list.remove(row);
        added_rows.clear();

        filter_values = str == "" ? null : str.split(" ");
        list.invalidate_filter();

        // 1. Try to parse as JID (Direct entry)
        try {
            Jid parsed_jid = new Jid(str);
            if (parsed_jid != null && parsed_jid.localpart != null) {
                foreach (Account account in accounts) {
                    if (filter_account != null && account != filter_account) continue;
                    var list_row = new Gtk.ListBoxRow();
                    list_row.set_child(new AddListRow(stream_interactor, parsed_jid, account));
                    list.append(list_row);
                    added_rows.add(list_row);
                }
            }
        } catch (InvalidJidError ignored) {
            // Ignore
        }

        // 2. If MUC search enabled, search in cached public rooms
        if (enable_muc_search && str != "") {
            // Search in discovered rooms
            foreach (var item in cached_public_rooms) {
                if ((item.name != null && item.name.down().contains(str.down())) || 
                    item.jid.to_string().down().contains(str.down())) {
                    
                    // Find account for this item (simplified: use first enabled account or filter_account)
                    Account? account = null;
                    if (filter_account != null && filter_account.enabled) {
                        account = filter_account;
                    } else {
                        foreach(var acc in accounts) { if (acc.enabled) { account = acc; break; } }
                    }
                    
                    if (account != null) {
                        // Skip rooms where we are already joined
                        if (stream_interactor.get_module<MucManager>(MucManager.IDENTITY).is_joined(item.jid, account)) continue;

                        var list_row = new Gtk.ListBoxRow();
                        list_row.set_child(new AddListRow(stream_interactor, item.jid, account, item.name));
                        list.append(list_row);
                        added_rows.add(list_row);
                    }
                }
            }
        }
        // 3. Add "Search Directory" option if not empty
        if (str != "" && !enable_muc_search) {
            var list_row = new Gtk.ListBoxRow();
            var search_row = new SearchDirectoryRow(str);
            list_row.set_child(search_row);
            list.append(list_row);
            added_rows.add(list_row);
        }
    }

    private void check_buttons_active() {
        ListBoxRow? row = list.get_selected_row();
        bool active = row != null && row.child != null && !(row.child is AddListRow) && !(row.child is SearchDirectoryRow);
        remove_button.sensitive = active;

        foreach (Widget w in added_rows) {
            var lb_row = w as ListBoxRow;
            if (lb_row != null) {
                var add_row = lb_row.child as AddListRow;
                if (add_row != null) add_row.set_selected(false);
            }
        }

        if (row != null) {
            var add_row = row.child as AddListRow;
            if (add_row != null) add_row.set_selected(true);
            
            var search_row = row.child as SearchDirectoryRow;
            if (search_row != null) {
                search_directory_clicked(search_row.query);
            }
        }
    }

    private int sort(ListBoxRow row1, ListBoxRow row2) {
        // SearchDirectoryRow always at the bottom
        if (row1.child is SearchDirectoryRow) return 1;
        if (row2.child is SearchDirectoryRow) return -1;

        AddListRow al1 = (row1.child as AddListRow);
        AddListRow al2 = (row2.child as AddListRow);
        if (al1 != null && al2 == null) {
            return -1;
        } else if (al2 != null && al1 == null) {
            return 1;
        }

        ListRow? c1 = (row1.child as ListRow);
        ListRow? c2 = (row2.child as ListRow);
        if (c1 != null && c2 != null) {
            return c1.name_label.label.collate(c2.name_label.label);
        }

        return 0;
    }

    private bool filter(ListBoxRow r) {
        ListRow? row = (r.child as ListRow);
        if (row == null) return true;

        if (filter_account != null && row.account != null && row.account != filter_account) return false;

        if (filter_values != null) {
            foreach (string filter in filter_values) {
                if (!(row.name_label.label.down().contains(filter.down()) ||
                        row.jid.to_string().down().contains(filter.down()))) {
                    return false;
                }
            }
        }
        return true;
    }

    private void header(ListBoxRow row, ListBoxRow? before_row) {
        if (row.get_header() == null && before_row != null) {
            row.set_header(new Separator(Orientation.HORIZONTAL));
        }
    }

    private class AddListRow : ListRow {

        public AddListRow(StreamInteractor stream_interactor, Jid jid, Account account, string? name = null) {
            this.account = account;
            this.jid = jid;

            name_label.label = name != null ? "%s (%s)".printf(name, jid.to_string()) : jid.to_string();
            if (stream_interactor.get_accounts().size > 1) {
                via_label.label = account.bare_jid.to_string();
            } else {
                via_label.visible = false;
            }
            picture.model = new ViewModel.CompatAvatarPictureModel(stream_interactor).add("+");
        }

        public void set_selected(bool selected) {
            var model = picture.model;
            if (model != null && model.tiles.get_n_items() > 0) {
                var tile = model.tiles.get_item(0) as ViewModel.AvatarPictureTileModel;
                if (tile != null) {
                    if (selected) {
                        tile.background_color = Gdk.RGBA() { red = 0.18f, green = 0.76f, blue = 0.49f, alpha = 1.0f };
                    } else {
                        tile.background_color = Gdk.RGBA() { red = 0.5f, green = 0.5f, blue = 0.5f, alpha = 1.0f };
                    }
                }
            }
            picture.queue_draw();
        }
    }

    private class SearchDirectoryRow : Box {
        public string query { get; private set; }
        
        public SearchDirectoryRow(string query) {
            this.query = query;
            this.orientation = Orientation.HORIZONTAL;
            this.spacing = 10;
            this.margin_top = 10;
            this.margin_bottom = 10;
            this.margin_start = 10;
            this.margin_end = 10;
            
            var icon = new Image.from_icon_name("system-search-symbolic");
            this.append(icon);
            
            var label = new Label(_("Search directory for '%s'").printf(query));
            label.ellipsize = Pango.EllipsizeMode.END;
            label.xalign = 0;
            this.append(label);
        }
    }
}

}
