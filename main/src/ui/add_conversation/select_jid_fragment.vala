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

    [GtkChild] private unowned Entry entry;
    [GtkChild] private unowned Box box;
    [GtkChild] private unowned Button add_button;
    [GtkChild] private unowned Button remove_button;

    private StreamInteractor stream_interactor;
    private Gee.List<Account> accounts;
    private ArrayList<Widget> added_rows = new ArrayList<Widget>();

    private ListBox list;
    private string[]? filter_values;
    private Gee.List<ServiceDiscovery.Item> cached_public_rooms = new Gee.ArrayList<ServiceDiscovery.Item>();
    private bool discovery_started = false;

    public bool enable_muc_search {
        get { return _enable_muc_search; }
        set {
            _enable_muc_search = value;
            entry.secondary_icon_name = value ? "system-search-symbolic" : null;
            entry.secondary_icon_tooltip_text = value ? _("Browse Rooms") : null;
            if (value && !discovery_started) {
                discovery_started = true;
                fetch_public_rooms.begin();
            }
        }
    }
    private bool _enable_muc_search = false;

    private async void fetch_public_rooms() {
        foreach (Account account in accounts) {
            if (!account.enabled) continue;
            try {
                Jid? muc_server = stream_interactor.get_module(MucManager.IDENTITY).default_muc_server.get(account);
                if (muc_server == null) {
                    muc_server = new Jid("conference." + account.domainpart);
                }
                
                var stream = stream_interactor.get_stream(account);
                if (stream != null) {
                    var disco_module = stream.get_module(ServiceDiscovery.Module.IDENTITY);
                    var result = yield disco_module.request_items(stream, muc_server);
                    if (result != null) {
                        foreach (var item in result.items) {
                            cached_public_rooms.add(item);
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
        list.row_selected.connect(() => { done = true; }); // just for notifying
        entry.changed.connect(() => { set_filter(entry.text); });
        entry.icon_press.connect(on_icon_press);
        add_button.clicked.connect(() => { add_jid(); });
        remove_button.clicked.connect(() => {
            var list_row = list.get_selected_row();
            if (list_row == null) return;
            remove_jid(list_row.child as ListRow);
        });
    }

    private void on_icon_press(EntryIconPosition pos) {
        if (pos == EntryIconPosition.SECONDARY && enable_muc_search) {
            open_room_browser();
        }
    }

    private void open_room_browser() {
        Account? account = null;
        foreach(var acc in accounts) {
            if (acc.enabled) {
                account = acc;
                break;
            }
        }
        
        if (account != null) {
            var dialog = new RoomBrowserDialog(stream_interactor, account);
            var root = this.get_root() as Gtk.Window;
            if (root != null) dialog.transient_for = root;
            
            dialog.room_selected.connect((jid) => {
                entry.text = jid.to_string();
            });
            dialog.present();
        }
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
                    
                    // Find account for this item (simplified: use first enabled account)
                    // Ideally we should track which account discovered which item, but for now this is fine
                    Account? account = null;
                    foreach(var acc in accounts) { if (acc.enabled) { account = acc; break; } }
                    
                    if (account != null) {
                        var list_row = new Gtk.ListBoxRow();
                        list_row.set_child(new AddListRow(stream_interactor, item.jid, account, item.name));
                        list.append(list_row);
                        added_rows.add(list_row);
                    }
                }
            }
        }
    }

    private void check_buttons_active() {
        ListBoxRow? row = list.get_selected_row();
        bool active = row != null && !row.get_type().is_a(typeof(AddListRow));
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
        }
    }

    private int sort(ListBoxRow row1, ListBoxRow row2) {
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
}

}
