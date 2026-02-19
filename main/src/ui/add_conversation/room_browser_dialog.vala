using Gee;
using Gtk;
using Dino.Entities;
using Xmpp;
using Xmpp.Xep;

namespace Dino.Ui {

[GtkTemplate (ui = "/im/github/rallep71/DinoX/add_conversation/room_browser_dialog.ui")]
public class RoomBrowserDialog : Adw.Dialog {

    [GtkChild] private unowned Button cancel_button;
    [GtkChild] private unowned Button join_button;
    [GtkChild] private unowned SearchEntry search_entry;
    [GtkChild] private unowned ListBox room_list;
    [GtkChild] private unowned Spinner loading_spinner;
    [GtkChild] private unowned Label status_label;
    [GtkChild] private unowned Switch public_search_switch;

    private StreamInteractor stream_interactor;
    private Account account;
    private Gee.List<ServiceDiscovery.Item> all_items = new Gee.ArrayList<ServiceDiscovery.Item>();
    private Gee.List<PublicRoom> public_results = new Gee.ArrayList<PublicRoom>();
    private Soup.Session http = new Soup.Session();
    private uint search_timeout_id = 0;
    
    // search.jabber.network API endpoint
    private const string PUBLIC_SEARCH_API = "https://search.jabber.network/api/1.0/search";
    
    public signal void room_selected(Jid room_jid);

    // Data class for public search results
    private class PublicRoom {
        public string address;
        public string name;
        public string description;
        public int nusers;
        public string language;
        public bool is_open;
        
        public PublicRoom(string address, string name, string description, int nusers, string language, bool is_open) {
            this.address = address;
            this.name = name;
            this.description = description;
            this.nusers = nusers;
            this.language = language;
            this.is_open = is_open;
        }
    }

    public RoomBrowserDialog(StreamInteractor stream_interactor, Account account) {
        this.stream_interactor = stream_interactor;
        this.account = account;

        cancel_button.clicked.connect(() => { close(); });
        join_button.clicked.connect(on_join_clicked);
        
        search_entry.search_changed.connect(on_search_changed);
        room_list.row_selected.connect(on_row_selected);
        room_list.row_activated.connect(on_row_activated);
        
        public_search_switch.notify["active"].connect(on_search_mode_changed);

        load_rooms.begin();
    }

    private void on_search_mode_changed() {
        if (public_search_switch.active) {
            // Public search mode - trigger search if there's text
            string query = search_entry.text.strip();
            if (query.length >= 2) {
                search_public_rooms.begin(query);
            } else {
                clear_list();
                show_info(_("Enter at least 2 characters to search public rooms."));
            }
        } else {
            // Local mode - show local rooms filtered
            status_label.visible = false;
            populate_list(search_entry.text);
        }
    }

    private async void load_rooms() {
        loading_spinner.visible = true;
        loading_spinner.start();
        status_label.visible = false;
        room_list.visible = false;

        Jid? muc_server = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).default_muc_server.get(account);
        
        if (muc_server == null) {
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

            ServiceDiscovery.ItemsResult? result = yield stream.get_module<ServiceDiscovery.Module>(ServiceDiscovery.Module.IDENTITY).request_items(stream, muc_server);
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
        status_label.add_css_class("error");
        status_label.remove_css_class("dim-label");
        status_label.visible = true;
        loading_spinner.stop();
        loading_spinner.visible = false;
    }
    
    // Safely get a string from JSON, returning "" for missing or null values
    private static string safe_get_string(Json.Object obj, string member) {
        if (!obj.has_member(member)) return "";
        var node = obj.get_member(member);
        if (node.is_null()) return "";
        return node.get_string() ?? "";
    }
    
    private void show_info(string message) {
        status_label.label = message;
        status_label.remove_css_class("error");
        status_label.add_css_class("dim-label");
        status_label.visible = true;
    }

    private void clear_list() {
        Gtk.ListBoxRow? row;
        while ((row = room_list.get_row_at_index(0)) != null) {
            room_list.remove(row);
        }
    }

    private void populate_list(string filter) {
        clear_list();

        string filter_lower = filter.down();
        var seen_jids = new Gee.HashSet<string>();

        foreach (var item in all_items) {
            string jid_str = item.jid.to_string();

            if (seen_jids.contains(jid_str)) {
                continue;
            }

            string name = item.name ?? item.jid.localpart ?? item.jid.to_string();
            if (filter == "" || name.down().contains(filter_lower) || jid_str.down().contains(filter_lower)) {
                Account? acc = null;
                foreach (var a in stream_interactor.get_accounts()) { if (a.enabled) { acc = a; break; } }

                if (acc != null) {
                    room_list.append(new RoomRow(item, acc, stream_interactor));
                } else {
                    room_list.append(new RoomRow(item, null, stream_interactor));
                }

                seen_jids.add(jid_str);
            }
        }
    }
    
    private void populate_public_results() {
        clear_list();
        status_label.visible = false;
        
        if (public_results.size == 0) {
            show_info(_("No public rooms found for this search."));
            return;
        }
        
        var seen_jids = new Gee.HashSet<string>();
        
        foreach (var room in public_results) {
            if (seen_jids.contains(room.address)) continue;
            seen_jids.add(room.address);
            
            try {
                var jid = new Jid(room.address);
                room_list.append(new PublicRoomRow(room, jid, account, stream_interactor));
            } catch (InvalidJidError e) {
                // Skip invalid JIDs
            }
        }
        
        room_list.visible = true;
    }
    
    private async void search_public_rooms(string query) {
        loading_spinner.visible = true;
        loading_spinner.start();
        status_label.visible = false;
        clear_list();
        room_list.visible = false;
        
        try {
            // API requires GET with JSON body and Content-Type: application/json
            var msg = new Soup.Message("GET", PUBLIC_SEARCH_API);
            
            // Build JSON payload: {"keywords": "query"}
            var builder = new Json.Builder();
            builder.begin_object();
            builder.set_member_name("keywords");
            builder.add_string_value(query);
            builder.end_object();
            
            var gen = new Json.Generator();
            gen.root = builder.get_root();
            string json_body = gen.to_data(null);
            
            msg.set_request_body_from_bytes("application/json", new Bytes(json_body.data));
            
            Bytes response = yield http.send_and_read_async(msg, Priority.DEFAULT, null);
            
            if (msg.status_code != 200) {
                show_error(_("Search failed (HTTP %u).").printf(msg.status_code));
                return;
            }
            
            string body = (string) response.get_data();
            var parser = new Json.Parser();
            parser.load_from_data(body, -1);
            
            var root = parser.get_root();
            if (root == null || root.get_node_type() != Json.NodeType.OBJECT) {
                show_error(_("Invalid response from search service."));
                return;
            }
            
            var root_obj = root.get_object();
            public_results.clear();
            
            // Response format: { "result": { "items": [...] } }
            Json.Array? items = null;
            if (root_obj.has_member("result")) {
                var result_obj = root_obj.get_object_member("result");
                if (result_obj != null && result_obj.has_member("items")) {
                    items = result_obj.get_array_member("items");
                }
            }
            // Fallback: items directly at root level
            if (items == null && root_obj.has_member("items")) {
                items = root_obj.get_array_member("items");
            }
            
            if (items != null) {
                for (uint i = 0; i < items.get_length(); i++) {
                    var item_obj = items.get_object_element(i);
                    
                    string address = safe_get_string(item_obj, "address");
                    string name = safe_get_string(item_obj, "name");
                    string description = safe_get_string(item_obj, "description");
                    int nusers = item_obj.has_member("nusers") && !item_obj.get_null_member("nusers") ? (int) item_obj.get_int_member("nusers") : -1;
                    string language = safe_get_string(item_obj, "language");
                    bool is_open = item_obj.has_member("is_open") && !item_obj.get_null_member("is_open") ? item_obj.get_boolean_member("is_open") : true;
                    
                    if (address != "") {
                        public_results.add(new PublicRoom(address, name, description, nusers, language, is_open));
                    }
                }
            }
            
            populate_public_results();
            
        } catch (Error e) {
            show_error(_("Search error: %s").printf(e.message));
        } finally {
            loading_spinner.stop();
            loading_spinner.visible = false;
        }
    }

    private void on_search_changed() {
        if (public_search_switch.active) {
            // Debounce: wait 400ms after last keystroke before querying
            if (search_timeout_id != 0) {
                Source.remove(search_timeout_id);
                search_timeout_id = 0;
            }
            
            string query = search_entry.text.strip();
            if (query.length < 2) {
                clear_list();
                show_info(_("Enter at least 2 characters to search public rooms."));
                return;
            }
            
            search_timeout_id = Timeout.add(400, () => {
                search_timeout_id = 0;
                search_public_rooms.begin(search_entry.text.strip());
                return false;
            });
        } else {
            populate_list(search_entry.text);
        }
    }

    private void on_row_selected(ListBoxRow? row) {
        join_button.sensitive = row != null;
        
        if (row is RoomRow) {
            var room_row = (RoomRow) row;
            join_button.label = room_row.joined ? _("Open") : _("Join");
        } else if (row is PublicRoomRow) {
            var pub_row = (PublicRoomRow) row;
            join_button.label = pub_row.joined ? _("Open") : _("Join");
        }
    }

    private void on_row_activated(ListBoxRow row) {
        on_join_clicked();
    }

    private void on_join_clicked() {
        Jid? jid = null;
        bool joined = false;
        
        var selected = room_list.get_selected_row();
        if (selected is RoomRow) {
            var row = (RoomRow) selected;
            jid = row.item.jid;
            joined = row.joined;
        } else if (selected is PublicRoomRow) {
            var row = (PublicRoomRow) selected;
            jid = row.jid;
            joined = row.joined;
        }
        
        if (jid != null) {
            if (joined) {
                open_room_conversation(jid);
            } else {
                room_selected(jid);
            }
            close();
        }
    }
    
    private void open_room_conversation(Jid jid) {
        Conversation? conversation = stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY).get_conversation(jid, account, Conversation.Type.GROUPCHAT);
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
                            member_count = -1;
                        }
                        display_name = nm.slice(0, pos);
                    }
                }
            }

            var name_label = new Label(display_name);
            name_label.xalign = 0;
            name_label.add_css_class("heading");
            name_label.ellipsize = Pango.EllipsizeMode.END;
            name_label.max_width_chars = 30;

            Label subtitle;
            if (member_count >= 0) {
                subtitle = new Label(n("%i member", "%i members", member_count).printf(member_count));
            } else {
                subtitle = new Label(item.jid.to_string());
            }
            subtitle.xalign = 0;
            subtitle.add_css_class("dim-label");
            subtitle.ellipsize = Pango.EllipsizeMode.END;
            subtitle.max_width_chars = 40;

            box.append(name_label);
            box.append(subtitle);

            if (account != null) {
                if (stream_interactor.get_module<MucManager>(MucManager.IDENTITY).is_joined(item.jid, account)) {
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
    
    private class PublicRoomRow : ListBoxRow {
        public Jid jid { get; private set; }
        public bool joined { get; private set; }
        
        public PublicRoomRow(PublicRoom room, Jid jid, Account account, StreamInteractor stream_interactor) {
            this.jid = jid;
            this.joined = false;
            
            var box = new Box(Orientation.VERTICAL, 2);
            box.margin_top = 8;
            box.margin_bottom = 8;
            box.margin_start = 10;
            box.margin_end = 10;
            
            string display_name = (room.name != null && room.name != "") ? room.name : jid.localpart ?? jid.to_string();
            
            var name_label = new Label(display_name);
            name_label.xalign = 0;
            name_label.add_css_class("heading");
            name_label.ellipsize = Pango.EllipsizeMode.END;
            name_label.max_width_chars = 40;
            box.append(name_label);
            
            // JID line
            var jid_label = new Label(jid.to_string());
            jid_label.xalign = 0;
            jid_label.add_css_class("dim-label");
            jid_label.ellipsize = Pango.EllipsizeMode.END;
            jid_label.max_width_chars = 50;
            box.append(jid_label);
            
            // Details line: member count + language
            var details = new StringBuilder();
            if (room.nusers >= 0) {
                details.append(n("%i member", "%i members", room.nusers).printf(room.nusers));
            }
            if (room.language != null && room.language != "") {
                if (details.len > 0) details.append("  ·  ");
                details.append(room.language.up());
            }
            if (!room.is_open) {
                if (details.len > 0) details.append("  ·  ");
                details.append(_("Closed"));
            }
            
            if (details.len > 0) {
                var details_label = new Label(details.str);
                details_label.xalign = 0;
                details_label.add_css_class("dim-label");
                details_label.add_css_class("caption");
                box.append(details_label);
            }
            
            // Description (truncated)
            if (room.description != null && room.description != "" && room.description != room.name) {
                string desc = room.description;
                if (desc.length > 100) desc = desc.substring(0, 100) + "…";
                var desc_label = new Label(desc);
                desc_label.xalign = 0;
                desc_label.add_css_class("dim-label");
                desc_label.wrap = true;
                desc_label.max_width_chars = 50;
                box.append(desc_label);
            }
            
            // Mark if already joined
            if (stream_interactor.get_module<MucManager>(MucManager.IDENTITY).is_joined(jid, account)) {
                this.joined = true;
                var joined_label = new Label(_("Joined"));
                joined_label.add_css_class("success");
                joined_label.xalign = 1;
                box.append(joined_label);
            }
            
            this.child = box;
        }
    }
}

}
