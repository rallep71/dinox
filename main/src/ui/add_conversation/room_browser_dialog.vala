using Gee;
using Gtk;
using Dino.Entities;
using Xmpp;
using Xmpp.Xep;

namespace Dino.Ui {

[GtkTemplate (ui = "/im/github/rallep71/DinoX/add_conversation/room_browser_dialog.ui")]
public class RoomBrowserDialog : Gtk.Window {

    [GtkChild] private unowned Button cancel_button;
    [GtkChild] private unowned Button join_button;
    [GtkChild] private unowned SearchEntry search_entry;
    [GtkChild] private unowned ListBox room_list;
    [GtkChild] private unowned Spinner loading_spinner;
    [GtkChild] private unowned Label status_label;

    private StreamInteractor stream_interactor;
    private Account account;
    private Gee.List<ServiceDiscovery.Item> all_items = new Gee.ArrayList<ServiceDiscovery.Item>();
    
    public signal void room_selected(Jid room_jid);

    public RoomBrowserDialog(StreamInteractor stream_interactor, Account account) {
        this.stream_interactor = stream_interactor;
        this.account = account;

        cancel_button.clicked.connect(() => { close(); });
        join_button.clicked.connect(on_join_clicked);
        
        search_entry.search_changed.connect(on_search_changed);
        room_list.row_selected.connect(on_row_selected);
        room_list.row_activated.connect(on_row_activated);

        load_rooms.begin();
    }

    private async void load_rooms() {
        loading_spinner.visible = true;
        loading_spinner.start();
        status_label.visible = false;
        room_list.visible = false;

        Jid? muc_server = stream_interactor.get_module(MucManager.IDENTITY).default_muc_server.get(account);
        
        if (muc_server == null) {
            // Try to find it if not cached yet
            // This is a simplified check, ideally we would trigger a disco info on the server
            // But for now, let's assume if it's not in MucManager, we might need to guess or fail
            // Let's try to guess standard "conference.domain"
            try {
                muc_server = new Jid("conference." + account.domainpart);
            } catch (Error e) {}
        }

        if (muc_server == null) {
            show_error(_("Could not determine MUC server for this account."));
            return;
        }

        try {
            var stream = stream_interactor.get_stream(account);
            if (stream == null) {
                show_error(_("Account is offline."));
                return;
            }

            ServiceDiscovery.ItemsResult? result = yield stream.get_module(ServiceDiscovery.Module.IDENTITY).request_items(stream, muc_server);
            if (result != null) {
                all_items = result.items;
                populate_list("");
                room_list.visible = true;
            } else {
                show_error(_("No rooms found."));
            }
        } finally {
            loading_spinner.stop();
            loading_spinner.visible = false;
        }
    }

    private void show_error(string message) {
        status_label.label = message;
        status_label.visible = true;
        loading_spinner.stop();
        loading_spinner.visible = false;
    }

    private void populate_list(string filter) {
        // Clear list
        Gtk.Widget? child = room_list.get_first_child();
        while (child != null) {
            room_list.remove(child);
            child = room_list.get_first_child();
        }

        string filter_lower = filter.down();

        foreach (var item in all_items) {
            string name = item.name ?? item.jid.localpart ?? item.jid.to_string();
            if (filter == "" || name.down().contains(filter_lower) || item.jid.to_string().down().contains(filter_lower)) {
                room_list.append(new RoomRow(item));
            }
        }
    }

    private void on_search_changed() {
        populate_list(search_entry.text);
    }

    private void on_row_selected(ListBoxRow? row) {
        join_button.sensitive = row != null;
    }

    private void on_row_activated(ListBoxRow row) {
        on_join_clicked();
    }

    private void on_join_clicked() {
        var row = room_list.get_selected_row() as RoomRow;
        if (row != null) {
            room_selected(row.item.jid);
            close();
        }
    }

    private class RoomRow : ListBoxRow {
        public ServiceDiscovery.Item item { get; private set; }
        
        public RoomRow(ServiceDiscovery.Item item) {
            this.item = item;
            var box = new Box(Orientation.VERTICAL, 2);
            box.margin_top = 8;
            box.margin_bottom = 8;
            box.margin_start = 10;
            box.margin_end = 10;

            var name_label = new Label(item.name ?? item.jid.localpart);
            name_label.xalign = 0;
            name_label.add_css_class("heading");
            
            var jid_label = new Label(item.jid.to_string());
            jid_label.xalign = 0;
            jid_label.add_css_class("dim-label");
            jid_label.ellipsize = Pango.EllipsizeMode.END;

            box.append(name_label);
            box.append(jid_label);
            
            this.child = box;
        }
    }
}

}
