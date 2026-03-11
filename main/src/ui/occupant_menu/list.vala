using Gee;
using Gtk;

using Dino.Entities;
using Xmpp;

namespace Dino.Ui.OccupantMenu {

[GtkTemplate (ui = "/im/github/rallep71/DinoX/occupant_list.ui")]
public class List : Box {

    public signal void conversation_selected(Conversation? conversation);
    private StreamInteractor stream_interactor;

    [GtkChild] public unowned ListBox list_box;
    [GtkChild] private unowned SearchEntry search_entry;

    private Conversation conversation;
    private string[]? filter_values;
    private HashMap<Jid, Widget> rows = new HashMap<Jid, Widget>(Jid.hash_func, Jid.equals_func);
    public HashMap<Widget, ListRow> row_wrappers = new HashMap<Widget, ListRow>();

    // Pre-computed affiliation counts for O(1) header generation
    private HashMap<Xmpp.Xep.Muc.Affiliation, int> affiliation_counts = new HashMap<Xmpp.Xep.Muc.Affiliation, int>();

    // Debounce timer for batching occupant presence updates (avoids O(n²) sort thrashing)
    private uint occupant_update_timeout = 0;
    private bool pending_invalidate = false;

    // Batched initialization state
    private uint batch_init_source = 0;
    private bool initializing = false;

    // Signal handler IDs for cleanup
    private ulong show_received_handler = 0;
    private ulong offline_presence_handler = 0;

    public List(StreamInteractor stream_interactor, Conversation conversation) {
        this.stream_interactor = stream_interactor;
        search_entry.search_changed.connect(refilter);

        show_received_handler = stream_interactor.get_module<PresenceManager>(PresenceManager.IDENTITY).show_received.connect(on_show_received);
        offline_presence_handler = stream_interactor.get_module<PresenceManager>(PresenceManager.IDENTITY).received_offline_presence.connect(on_received_offline_presence);

        initialize_for_conversation(conversation);
    }

    public void cleanup() {
        if (batch_init_source != 0) {
            Source.remove(batch_init_source);
            batch_init_source = 0;
        }
        if (occupant_update_timeout != 0) {
            Source.remove(occupant_update_timeout);
            occupant_update_timeout = 0;
        }
        initializing = false;
        var pm = stream_interactor.get_module<PresenceManager>(PresenceManager.IDENTITY);
        if (show_received_handler != 0) {
            pm.disconnect(show_received_handler);
            show_received_handler = 0;
        }
        if (offline_presence_handler != 0) {
            pm.disconnect(offline_presence_handler);
            offline_presence_handler = 0;
        }
        rows.clear();
        row_wrappers.clear();
        affiliation_counts.clear();
    }

    public override void dispose() {
        cleanup();
        base.dispose();
    }

    public void initialize_for_conversation(Conversation conversation) {
        this.conversation = conversation;
        Gee.List<Jid>? occupants = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).get_occupants(conversation.counterpart, conversation.account);
        if (occupants == null || occupants.size == 0) {
            list_box.set_sort_func(sort);
            list_box.set_header_func(header);
            list_box.set_filter_func(filter);
            return;
        }

        // Pre-sort occupants so widgets are appended in correct order
        // This is much faster than sorting 200 GtkWidgets via set_sort_func
        var sorted = new ArrayList<Jid>(Jid.equals_func);
        sorted.add_all(occupants);
        sorted.sort((a, b) => {
            var aff_a = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).get_affiliation(conversation.counterpart, a, conversation.account) ?? Xmpp.Xep.Muc.Affiliation.NONE;
            var aff_b = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).get_affiliation(conversation.counterpart, b, conversation.account) ?? Xmpp.Xep.Muc.Affiliation.NONE;
            int ra = get_affiliation_ranking(aff_a);
            int rb = get_affiliation_ranking(aff_b);
            if (ra != rb) return ra - rb;
            string na = Util.get_participant_display_name(stream_interactor, conversation, a);
            string nb = Util.get_participant_display_name(stream_interactor, conversation, b);
            return na.collate(nb);
        });

        // Use Timeout.add (NOT Idle.add!) with small batches.
        // Idle.add runs all pending callbacks in one frame — no UI responsiveness.
        // Timeout.add forces a real main loop iteration between batches.
        int index = 0;
        int batch_size = 10;
        initializing = true;
        batch_init_source = Timeout.add(1, () => {
            int end = int.min(index + batch_size, sorted.size);
            for (int i = index; i < end; i++) {
                add_occupant(sorted[i]);
            }
            index = end;
            if (index >= sorted.size) {
                batch_init_source = 0;
                initializing = false;
                // Rows already in correct order; set_sort_func for future updates only
                list_box.set_sort_func(sort);
                list_box.set_header_func(header);
                list_box.set_filter_func(filter);
                return Source.REMOVE;
            }
            return Source.CONTINUE;
        });
    }

    private void refilter() {
        string[]? values = null;
        string str = search_entry.get_text ();
        if (str != "") values = str.split(" ");
        if (filter_values == values) return;
        filter_values = values;
        list_box.invalidate_filter();
    }

    public void add_occupant(Jid jid) {
        var row_wrapper = new ListRow(stream_interactor, conversation, jid);
        var widget = row_wrapper.get_widget();

        var aff = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).get_affiliation(conversation.counterpart, jid, conversation.account) ?? Xmpp.Xep.Muc.Affiliation.NONE;
        row_wrapper.affiliation = aff;
        affiliation_counts[aff] = (affiliation_counts.has_key(aff) ? affiliation_counts[aff] : 0) + 1;

        row_wrappers[widget] = row_wrapper;
        rows[jid] = widget;
        list_box.append(widget);
    }

    public void remove_occupant(Jid jid) {
        if (!rows.has_key(jid)) return;
        var widget = rows[jid];
        var row_wrapper = row_wrappers[widget];

        if (affiliation_counts.has_key(row_wrapper.affiliation) && affiliation_counts[row_wrapper.affiliation] > 0) {
            affiliation_counts[row_wrapper.affiliation] = affiliation_counts[row_wrapper.affiliation] - 1;
        }

        rows.unset(jid);
        row_wrappers.unset(widget);
        if (widget.get_parent() == list_box) {
            list_box.remove(widget);
        }
    }

    private void on_received_offline_presence(Jid jid, Account account) {
        if (initializing) return;
        if (conversation != null && conversation.counterpart.equals_bare(jid) && jid.is_full()) {
            if (rows.has_key(jid)) {
                remove_occupant(jid);
            }
            schedule_invalidate();
        }
    }

    private void on_show_received(Jid jid, Account account) {
        if (initializing) return;
        if (conversation != null && conversation.counterpart.equals_bare(jid) && jid.is_full()) {
            if (!rows.has_key(jid)) {
                add_occupant(jid);
            }
            schedule_invalidate();
        }
    }

    private void schedule_invalidate() {
        pending_invalidate = true;
        if (occupant_update_timeout == 0) {
            occupant_update_timeout = Timeout.add(150, () => {
                occupant_update_timeout = 0;
                if (pending_invalidate) {
                    pending_invalidate = false;
                    list_box.invalidate_sort();
                    list_box.invalidate_headers();
                    list_box.invalidate_filter();
                }
                return Source.REMOVE;
            });
        }
    }

    private void header(ListBoxRow row, ListBoxRow? before_row) {
        ListRow? row_wrapper1 = row_wrappers[row.get_child()];
        if (row_wrapper1 == null) return;
        Xmpp.Xep.Muc.Affiliation a1 = row_wrapper1.affiliation;

        if (before_row != null) {
            ListRow? row_wrapper2 = row_wrappers[before_row.get_child()];
            if (row_wrapper2 == null) return;
            Xmpp.Xep.Muc.Affiliation a2 = row_wrapper2.affiliation;
            if (a1 != a2) {
                row.set_header(generate_header_widget(a1, false));
            } else if (row.get_header() != null){
                row.set_header(null);
            }
        } else {
            row.set_header(generate_header_widget(a1, true));
        }
    }

    private Widget generate_header_widget(Xmpp.Xep.Muc.Affiliation affiliation, bool top) {
        string aff_str;
        switch (affiliation) {
            case Xmpp.Xep.Muc.Affiliation.OWNER:
                aff_str = _("Owner"); break;
            case Xmpp.Xep.Muc.Affiliation.ADMIN:
                aff_str = _("Admin"); break;
            case Xmpp.Xep.Muc.Affiliation.MEMBER:
                aff_str = _("Member"); break;
            default:
                aff_str = _("User"); break;
        }

        int count = affiliation_counts.has_key(affiliation) ? affiliation_counts[affiliation] : 0;

        Label title_label = new Label("") { margin_start=10, xalign=0 };
        title_label.set_markup(@"<b>$(Markup.escape_text(aff_str))</b>");

        Label count_label = new Label(@"$count") { xalign=0, margin_end=7, hexpand=true };
        count_label.add_css_class("dim-label");

        Grid grid = new Grid() { margin_top=top?5:15, column_spacing=5, hexpand=true };
        grid.attach(title_label, 0, 0, 1, 1);
        grid.attach(count_label, 1, 0, 1, 1);
        grid.attach(new Separator(Orientation.HORIZONTAL) { hexpand=true, vexpand=true }, 0, 1, 2, 1);
        return grid;
    }

    private bool filter(ListBoxRow r) {
        ListRow? row_wrapper = row_wrappers[r.get_child()];
        if (row_wrapper == null) return false;
        string name_lower = row_wrapper.name_label.label.down();
        foreach (string filter in filter_values) {
            if (!name_lower.contains(filter.down())) return false;
        }
        return true;
    }

    private int sort(ListBoxRow row1, ListBoxRow row2) {
        ListRow? row_wrapper1 = row_wrappers[row1.get_child()];
        ListRow? row_wrapper2 = row_wrappers[row2.get_child()];
        if (row_wrapper1 == null || row_wrapper2 == null) return 0;

        int affiliation1 = get_affiliation_ranking(row_wrapper1.affiliation);
        int affiliation2 = get_affiliation_ranking(row_wrapper2.affiliation);

        if (affiliation1 < affiliation2) return -1;
        else if (affiliation1 > affiliation2) return 1;
        else return row_wrapper1.name_label.label.collate(row_wrapper2.name_label.label);
    }

    private int get_affiliation_ranking(Xmpp.Xep.Muc.Affiliation affiliation) {
        switch (affiliation) {
            case Xmpp.Xep.Muc.Affiliation.OWNER:
                return 1;
            case Xmpp.Xep.Muc.Affiliation.ADMIN:
                return 2;
            case Xmpp.Xep.Muc.Affiliation.MEMBER:
                return 3;
            default:
                return 4;
        }
    }
}

}
