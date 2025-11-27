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
            } catch (InvalidJidError e) {
                warning("Could not create MUC server JID: %s", e.message);
            }
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

        // Deduplicate by JID - keep only first occurrence of each unique JID
        var seen_jids = new Gee.HashSet<string>();

        foreach (var item in all_items) {
            string jid_str = item.jid.to_string();

            // Skip if we've already seen this JID
            if (seen_jids.contains(jid_str)) {
                continue;
            }

            string name = item.name ?? item.jid.localpart ?? item.jid.to_string();
            if (filter == "" || name.down().contains(filter_lower) || jid_str.down().contains(filter_lower)) {
                // Determine which account to use for this item (first enabled)
                Account? account = null;
                foreach (var acc in stream_interactor.get_accounts()) { if (acc.enabled) { account = acc; break; } }

                // Create row and mark as joined if conversation exists
                if (account != null) {
                    room_list.append(new RoomRow(item, account, stream_interactor));
                } else {
                    room_list.append(new RoomRow(item, null, stream_interactor));
                }

                seen_jids.add(jid_str);
            }
        }
    }

    private void on_search_changed() {
        populate_list(search_entry.text);
    }

    private void on_row_selected(ListBoxRow? row) {
        var room_row = row as RoomRow;
        join_button.sensitive = row != null;
        
        // Change button label based on whether room is already joined
        if (room_row != null && room_row.joined) {
            join_button.label = _("Open");
        } else {
            join_button.label = _("Join");
        }
    }

    private void on_row_activated(ListBoxRow row) {
        on_join_clicked();
    }

    private void on_join_clicked() {
        var row = room_list.get_selected_row() as RoomRow;
        if (row != null) {
            if (row.joined) {
                // Room already joined - open the conversation
                open_room_conversation(row.item.jid);
            } else {
                // Room not joined - trigger join flow
                room_selected(row.item.jid);
            }
            close();
        }
    }
    
    private void open_room_conversation(Jid jid) {
        Conversation? conversation = stream_interactor.get_module(ConversationManager.IDENTITY).get_conversation(jid, account, Conversation.Type.GROUPCHAT);
        if (conversation != null) {
            Application app = GLib.Application.get_default() as Application;
            app.controller.select_conversation(conversation);
        }
    }

    private class RoomRow : ListBoxRow {
        public ServiceDiscovery.Item item { get; private set; }
        public bool joined { get; private set; }

        public RoomRow(ServiceDiscovery.Item item, Account? account, StreamInteractor stream_interactor) {
            this.item = item;
            this.joined = false;

            var box = new Box(Orientation.VERTICAL, 2);
            box.margin_top = 8;
            box.margin_bottom = 8;
            box.margin_start = 10;
            box.margin_end = 10;

            // Parse member count suffix like "name (2)"
            string display_name = item.name ?? item.jid.localpart;
            int member_count = -1;
            if (item.name != null) {
                string nm = item.name;
                if (nm.length > 0 && nm[nm.length - 1] == ')' && nm.contains(" (")) {
                    int pos = nm.last_index_of(" (");
                    if (pos >= 0) {
                        string num = nm.slice(pos + 2, nm.length - 1);
                        member_count = int.parse(num);
                        if (member_count == 0 && num != "0") {
                            member_count = -1;  // Parse failed
                        }
                        display_name = nm.slice(0, pos);
                    }
                }
            }

            var name_label = new Label(display_name);
            name_label.xalign = 0;
            name_label.add_css_class("heading");

            // Show member count (if parsed) or jid as dim subtitle
            Label subtitle;
            if (member_count >= 0) {
                subtitle = new Label(n("%i member", "%i members", member_count).printf(member_count));
            } else {
                subtitle = new Label(item.jid.to_string());
            }
            subtitle.xalign = 0;
            subtitle.add_css_class("dim-label");
            subtitle.ellipsize = Pango.EllipsizeMode.END;

            box.append(name_label);
            box.append(subtitle);

            // Mark if already joined (using MucManager.is_joined)
            if (account != null) {
                if (stream_interactor.get_module(MucManager.IDENTITY).is_joined(item.jid, account)) {
                    this.joined = true;
                    var joined_label = new Label(_("Joined"));
                    joined_label.add_css_class("success");
                    joined_label.xalign = 1;
                    box.append(joined_label);
                }
            }

            this.child = box;
        }
    }
}

}
