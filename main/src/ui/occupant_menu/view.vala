using Gee;
using Gtk;

using Dino.Entities;
using Xmpp;

namespace Dino.Ui.OccupantMenu {
public class View : Popover {

    private StreamInteractor stream_interactor;
    private Conversation conversation;

    private Stack stack = new Stack() { vhomogeneous=false };
    private Box list_box = new Box(Orientation.VERTICAL, 1);
    private List? list = null;
    private ListBox invite_list = new ListBox();
    private Box? jid_menu = null;

    private Jid? selected_jid;

    public View(StreamInteractor stream_interactor, Conversation conversation) {
        this.stream_interactor = stream_interactor;
        this.conversation = conversation;

        this.show.connect(initialize_list);

        invite_list.append(new ListRow.label("+", _("Invite")).get_widget());
        invite_list.can_focus = false;
        list_box.append(invite_list);
        invite_list.row_activated.connect(on_invite_clicked);

        stack.add_named(list_box, "list");
        set_child(stack);
        stack.visible_child_name = "list";

        hide.connect(reset);
    }

    public void reset() {
        stack.transition_type = StackTransitionType.NONE;
        stack.visible_child_name = "list";
        if (list != null) list.list_box.unselect_all();
        invite_list.unselect_all();
    }

    private void initialize_list() {
        printerr("DEBUG: initialize_list called\n");
        if (list == null) {
            list = new List(stream_interactor, conversation);
            list_box.prepend(list);

            list.list_box.row_activated.connect((row) => {
                ListRow row_wrapper = list.row_wrappers[row.get_child()];
                show_menu(row_wrapper.jid, row_wrapper.name_label.label);
            });
        }
    }

    private void show_list() {
        if (list != null) list.list_box.unselect_all();
        stack.transition_type = StackTransitionType.SLIDE_RIGHT;
        stack.visible_child_name = "list";
    }

    public void show_menu(Jid jid, string name_) {
        printerr("DEBUG: Entering show_menu for %s\n", jid != null ? jid.to_string() : "null");
        selected_jid = jid;
        stack.transition_type = StackTransitionType.SLIDE_LEFT;

        string name = Markup.escape_text(name_);
        Jid? real_jid = stream_interactor.get_module(MucManager.IDENTITY).get_real_jid(jid, conversation.account);
        if (real_jid != null) name += "\n<span font=\'8\'>%s</span>".printf(Markup.escape_text(real_jid.bare_jid.to_string()));

        Box header_box = new Box(Orientation.HORIZONTAL, 5);
        // Only show back button if we have a list to go back to
        if (list != null) {
            header_box.append(new Image.from_icon_name("pan-start-symbolic"));
        }
        header_box.append(new Label(name) { xalign=0, use_markup=true, hexpand=true });
        Button header_button = new Button() { has_frame=false };
        header_button.child = header_box;

        Box outer_box = new Box(Orientation.VERTICAL, 0); // Reduced spacing to 0
        outer_box.append(header_button);
        if (list != null) {
            header_button.clicked.connect(show_list);
        }

        outer_box.append(create_menu_button(_("Start private conversation"), private_conversation_button_clicked));

        Jid? own_jid = stream_interactor.get_module(MucManager.IDENTITY).get_own_jid(conversation.counterpart, conversation.account);
        Xmpp.Xep.Muc.Role? role = null;
        if (own_jid != null) {
            role = stream_interactor.get_module(MucManager.IDENTITY).get_role(own_jid, conversation.account);
        }

        Xmpp.Xep.Muc.Affiliation? my_affiliation = Xmpp.Xep.Muc.Affiliation.NONE;
        if (own_jid != null) {
            my_affiliation = stream_interactor.get_module(MucManager.IDENTITY).get_affiliation(conversation.counterpart, own_jid, conversation.account);
        }
        // Fallback: Check affiliation of the account JID if MUC JID affiliation is unknown
        if (my_affiliation == Xmpp.Xep.Muc.Affiliation.NONE || my_affiliation == null) {
             printerr("DEBUG: Fallback to account bare JID: %s\n", conversation.account.bare_jid.to_string());
             my_affiliation = stream_interactor.get_module(MucManager.IDENTITY).get_affiliation(conversation.counterpart, conversation.account.bare_jid, conversation.account);
        }
        // Fallback: If we are Owner/Admin, we are effectively a Moderator
        if (role == null && (my_affiliation == Xmpp.Xep.Muc.Affiliation.OWNER || my_affiliation == Xmpp.Xep.Muc.Affiliation.ADMIN)) {
            role = Xmpp.Xep.Muc.Role.MODERATOR;
        }

        bool is_self = (own_jid != null && jid.equals(own_jid));
        Xmpp.Xep.Muc.Affiliation? target_affiliation = stream_interactor.get_module(MucManager.IDENTITY).get_affiliation(conversation.counterpart, jid, conversation.account);
        
        bool allowed_by_hierarchy = true;
        if (my_affiliation == Xmpp.Xep.Muc.Affiliation.ADMIN) {
            if (target_affiliation == Xmpp.Xep.Muc.Affiliation.OWNER || target_affiliation == Xmpp.Xep.Muc.Affiliation.ADMIN) {
                allowed_by_hierarchy = false;
            }
        }

        // Blocking (XEP-0191)
        if (!is_self && stream_interactor.get_module(BlockingManager.IDENTITY).is_supported(conversation.account)) {
            bool is_blocked = stream_interactor.get_module(BlockingManager.IDENTITY).is_blocked(conversation.account, selected_jid);
            if (is_blocked) {
                outer_box.append(create_menu_button(_("Unblock Contact"), unblock_button_clicked));
            } else {
                outer_box.append(create_menu_button(_("Block Contact"), block_button_clicked));
            }
        }

        if (!is_self && allowed_by_hierarchy && role ==  Xmpp.Xep.Muc.Role.MODERATOR && stream_interactor.get_module(MucManager.IDENTITY).kick_possible(conversation.account, jid)) {
            outer_box.append(new Separator(Orientation.HORIZONTAL));
            outer_box.append(create_section_label(_("Moderation")));
            
            outer_box.append(create_menu_button(_("Kick"), kick_button_clicked));
        }
        
        if (!is_self && allowed_by_hierarchy && (my_affiliation == Xmpp.Xep.Muc.Affiliation.OWNER || my_affiliation == Xmpp.Xep.Muc.Affiliation.ADMIN)) {
            outer_box.append(create_menu_button(_("Ban (Permanent)"), ban_button_clicked));
            outer_box.append(create_menu_button(_("Ban (10 min)"), () => ban_timed_button_clicked(10)));
            outer_box.append(create_menu_button(_("Ban (15 min)"), () => ban_timed_button_clicked(15)));
            outer_box.append(create_menu_button(_("Ban (30 min)"), () => ban_timed_button_clicked(30)));

            // Affiliation Management
            outer_box.append(new Separator(Orientation.HORIZONTAL));
            outer_box.append(create_section_label(_("Administration")));

            if (my_affiliation == Xmpp.Xep.Muc.Affiliation.OWNER) {
                if (target_affiliation != Xmpp.Xep.Muc.Affiliation.ADMIN) {
                    outer_box.append(create_menu_button(_("Make Admin"), () => set_affiliation_button_clicked("admin")));
                } else {
                    outer_box.append(create_menu_button(_("Revoke Admin"), () => set_affiliation_button_clicked("member")));
                }

                if (target_affiliation != Xmpp.Xep.Muc.Affiliation.OWNER) {
                    outer_box.append(create_menu_button(_("Make Owner"), () => set_affiliation_button_clicked("owner")));
                }
            }

            if (target_affiliation != Xmpp.Xep.Muc.Affiliation.MEMBER) {
                outer_box.append(create_menu_button(_("Make Member"), () => set_affiliation_button_clicked("member")));
            } else {
                outer_box.append(create_menu_button(_("Revoke Membership"), () => set_affiliation_button_clicked("none")));
            }
        }

        bool is_moderated = stream_interactor.get_module(MucManager.IDENTITY).is_moderated_room(conversation.account, conversation.counterpart);
        Xmpp.Xep.Muc.Role? target_role = stream_interactor.get_module(MucManager.IDENTITY).get_role(selected_jid, conversation.account);
        printerr("DEBUG: Is Moderated: %s, Target Role: %s\n", is_moderated.to_string(), target_role != null ? target_role.to_string() : "null");

        if (role == Xmpp.Xep.Muc.Role.MODERATOR) {
            if (target_role ==  Xmpp.Xep.Muc.Role.VISITOR) {
                outer_box.append(create_menu_button(_("Unmute"), () => voice_button_clicked("participant")));
            } 
            else if (target_role ==  Xmpp.Xep.Muc.Role.PARTICIPANT || target_role == null){
                // If role is null, we assume they are a participant (standard user) or we just try anyway.
                outer_box.append(create_menu_button(_("Mute"), () => voice_button_clicked("visitor")));
            }
        }

        if (jid_menu != null) stack.remove(jid_menu);
        stack.add_named(outer_box, "menu");
        stack.visible_child_name = "menu";
        jid_menu = outer_box;
    }

    private Button create_menu_button(string label_text, owned clicked_cb callback) {
        Button button = new Button();
        button.has_frame = false;
        Label label = new Label(label_text);
        label.xalign = 0;
        label.hexpand = true;
        button.child = label;
        button.clicked.connect(() => callback());
        return button;
    }

    private Label create_section_label(string text) {
        var label = new Label(text);
        label.xalign = 0;
        label.margin_start = 5;
        label.margin_top = 5;
        label.margin_bottom = 5;
        label.use_markup = true;
        var attr_list = new Pango.AttrList();
        attr_list.insert(Pango.attr_weight_new(Pango.Weight.BOLD));
        label.attributes = attr_list;
        return label;
    }

    private delegate void clicked_cb();

    private void private_conversation_button_clicked() {
        if (selected_jid == null) return;
        hide();

        Conversation conversation = stream_interactor.get_module(ConversationManager.IDENTITY).create_conversation(selected_jid, conversation.account, Conversation.Type.GROUPCHAT_PM);
        stream_interactor.get_module(ConversationManager.IDENTITY).start_conversation(conversation);

        Application app = GLib.Application.get_default() as Application;
        app.controller.select_conversation(conversation);
    }

    private void kick_button_clicked() {
        if (selected_jid == null) return;
        hide();

        stream_interactor.get_module(MucManager.IDENTITY).kick(conversation.account, conversation.counterpart, selected_jid.resourcepart, _("Kicked by moderator"));
    }

    private void ban_button_clicked() {
        if (selected_jid == null) return;
        hide();

        stream_interactor.get_module(MucManager.IDENTITY).ban(conversation.account, conversation.counterpart, selected_jid);
    }

    private void block_button_clicked() {
        if (selected_jid == null) return;
        hide();
        stream_interactor.get_module(BlockingManager.IDENTITY).block(conversation.account, selected_jid);
    }

    private void unblock_button_clicked() {
        if (selected_jid == null) return;
        hide();
        stream_interactor.get_module(BlockingManager.IDENTITY).unblock(conversation.account, selected_jid);
    }

    private void set_affiliation_button_clicked(string affiliation) {
        if (selected_jid == null) return;
        hide();
        
        Jid? real_jid = stream_interactor.get_module(MucManager.IDENTITY).get_real_jid(selected_jid, conversation.account);
        if (real_jid != null) {
            stream_interactor.get_module(MucManager.IDENTITY).set_affiliation(conversation.account, conversation.counterpart, real_jid, affiliation);
        } else {
            stream_interactor.get_module(MucManager.IDENTITY).change_affiliation(conversation.account, conversation.counterpart, selected_jid.resourcepart, affiliation);
        }
    }

    private void voice_button_clicked(string role) {
        if (selected_jid == null) return;
        hide();

        stream_interactor.get_module(MucManager.IDENTITY).change_role(conversation.account, conversation.counterpart, selected_jid.resourcepart, role);
    }

    private void on_invite_clicked() {
        hide();
        Gee.List<Account> acc_list = new ArrayList<Account>(Account.equals_func);
        acc_list.add(conversation.account);
        SelectContactDialog add_chat_dialog = new SelectContactDialog(stream_interactor, acc_list);
        add_chat_dialog.set_transient_for((Window) get_root());
        add_chat_dialog.title = _("Invite to Conference");
        add_chat_dialog.ok_button.label = _("Invite");
        add_chat_dialog.selected.connect((account, jid) => {
            stream_interactor.get_module(MucManager.IDENTITY).invite(conversation.account, conversation.counterpart, jid);
        });
        add_chat_dialog.present();
    }

    private void ban_timed_button_clicked(int minutes) {
        if (selected_jid == null) return;
        
        Jid target = selected_jid;
        Account account = conversation.account;
        Jid room = conversation.counterpart;

        printerr("DEBUG: ban_timed_button_clicked for %s, %d minutes\n", target.to_string(), minutes);

        // Get current affiliation to restore later
        Xmpp.Xep.Muc.Affiliation? current_aff = stream_interactor.get_module(MucManager.IDENTITY).get_affiliation(room, target, account);
        string restore_aff = "none";
        if (current_aff == Xmpp.Xep.Muc.Affiliation.MEMBER) restore_aff = "member";
        else if (current_aff == Xmpp.Xep.Muc.Affiliation.ADMIN) restore_aff = "admin";
        else if (current_aff == Xmpp.Xep.Muc.Affiliation.OWNER) restore_aff = "owner";

        // Send a message to the room notifying about the ban
        string msg = "/me banned %s for %d minutes.".printf(target.resourcepart, minutes);
        Dino.send_message(conversation, msg, 0, null, new Gee.ArrayList<Xmpp.Xep.MessageMarkup.Span>());

        GLib.Timeout.add(500, () => {
            printerr("DEBUG: Executing timed ban for %s\n", target.to_string());
            stream_interactor.get_module(MucManager.IDENTITY).ban(account, room, target, "Banned for %d minutes".printf(minutes));
            return false;
        });

        GLib.Timeout.add_seconds((uint)(minutes * 60), () => {
            printerr("DEBUG: Restoring affiliation for %s to %s\n", target.to_string(), restore_aff);
            Jid? real_jid = stream_interactor.get_module(MucManager.IDENTITY).get_real_jid(target, account);
            if (real_jid != null) {
                stream_interactor.get_module(MucManager.IDENTITY).set_affiliation(account, room, real_jid, restore_aff);
            } else {
                stream_interactor.get_module(MucManager.IDENTITY).change_affiliation(account, room, target.resourcepart, restore_aff);
            }
            return false;
        });
        
        hide();
    }
}

}
