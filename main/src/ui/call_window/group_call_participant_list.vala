using Gtk;
using Gee;
using Xmpp;
using Dino.Entities;

namespace Dino.Ui {

    public class GroupCallParticipantList : Box {
        
        private ListBox participants_list = new ListBox();
        private Label title_label = new Label(_("Participants")) { halign=Align.START };
        private HashMap<Jid, GroupCallParticipantRow> participant_rows = new HashMap<Jid, GroupCallParticipantRow>(Jid.hash_func, Jid.equals_func);
        
        construct {
            orientation = Orientation.VERTICAL;
            spacing = 10;
            margin_top = margin_bottom = margin_start = margin_end = 10;
            width_request = 250;
            
            // Title
            title_label.add_css_class("heading");
            title_label.margin_bottom = 5;
            append(title_label);
            
            // Scrollable list
            var scrolled = new ScrolledWindow() {
                vexpand = true,
                hscrollbar_policy = PolicyType.NEVER,
                vscrollbar_policy = PolicyType.AUTOMATIC
            };
            
            participants_list.add_css_class("boxed-list");
            participants_list.selection_mode = SelectionMode.NONE;
            scrolled.set_child(participants_list);
            append(scrolled);
            
            add_css_class("group-call-participants");
        }
        
        public void add_participant(Jid jid, string? display_name = null) {
            if (participant_rows.has_key(jid)) {
                return; // Already exists
            }
            
            var row = new GroupCallParticipantRow(jid, display_name);
            participant_rows[jid] = row;
            participants_list.append(row);
            
            update_title();
        }
        
        public void remove_participant(Jid jid) {
            if (!participant_rows.has_key(jid)) {
                return;
            }
            
            var row = participant_rows[jid];
            participants_list.remove(row);
            participant_rows.unset(jid);
            
            update_title();
        }
        
        public void set_participant_connection_status(Jid jid, bool connected) {
            if (!participant_rows.has_key(jid)) {
                return;
            }
            
            participant_rows[jid].set_connection_status(connected);
        }
        
        private void update_title() {
            int count = participant_rows.size;
            title_label.label = _("Participants") + " (" + count.to_string() + ")";
        }
    }
    
    private class GroupCallParticipantRow : Box {
        
        private Image status_icon = new Image() { pixel_size = 16 };
        private Label name_label = new Label("") { ellipsize = Pango.EllipsizeMode.END, xalign = 0 };
        private Jid jid;
        
        public GroupCallParticipantRow(Jid jid, string? display_name = null) {
            this.jid = jid;
            
            orientation = Orientation.HORIZONTAL;
            spacing = 10;
            margin_top = margin_bottom = 6;
            margin_start = margin_end = 10;
            
            status_icon.icon_name = "network-idle-symbolic";
            status_icon.add_css_class("dim-label");
            append(status_icon);
            
            name_label.label = display_name ?? jid.to_string();
            name_label.hexpand = true;
            append(name_label);
        }
        
        public void set_connection_status(bool connected) {
            if (connected) {
                status_icon.icon_name = "emblem-ok-symbolic";
                status_icon.remove_css_class("dim-label");
                status_icon.add_css_class("success");
            } else {
                status_icon.icon_name = "network-idle-symbolic";
                status_icon.remove_css_class("success");
                status_icon.add_css_class("dim-label");
            }
        }
    }
}
