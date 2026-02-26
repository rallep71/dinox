/*
 * Copyright (C) 2025 Ralf Peter <dinox@handwerker.jetzt>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

using Gtk;
using Gee;

using Dino.Entities;

namespace Dino.Ui {

class MenuEntry : Plugins.ConversationTitlebarEntry, Object {
    public string id { get { return "menu"; } }
    public double order { get { return 0; } }

    StreamInteractor stream_interactor;
    private Conversation? conversation;

    MenuButton button = new MenuButton() { icon_name="view-more-symbolic" };

    public MenuEntry(StreamInteractor stream_interactor) {
        this.stream_interactor = stream_interactor;

        SimpleActionGroup action_group = new SimpleActionGroup();
        SimpleAction details_action = new SimpleAction("details", null);
        details_action.activate.connect((parameter) => {
            var variant = new Variant.tuple(new Variant[] {new Variant.int32(conversation.id), new Variant.string("about")});
            GLib.Application.get_default().activate_action("open-conversation-details", variant);
        });
        action_group.add_action(details_action);

        SimpleAction invite_action = new SimpleAction("invite", null);
        invite_action.activate.connect(on_invite_action);
        action_group.add_action(invite_action);
        
        SimpleAction clear_action = new SimpleAction("clear", null);
        clear_action.activate.connect((parameter) => {
            if (conversation == null) return;
            
            var dialog = new Adw.AlertDialog(
                _("Delete all message history?"),
                _("This will permanently delete all messages in this conversation. This action cannot be undone.")
            );

            Gtk.CheckButton? global_check = null;
            if (conversation.type_ == Conversation.Type.CHAT) {
                global_check = new Gtk.CheckButton.with_label(_("Also delete for chat partner"));
                global_check.halign = Gtk.Align.CENTER;
                dialog.set_extra_child(global_check);
            }

            dialog.add_response("cancel", _("Cancel"));
            dialog.add_response("delete", _("Delete"));
            dialog.set_response_appearance("delete", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.set_default_response("cancel");
            dialog.set_close_response("cancel");
            
            dialog.response.connect((response) => {
                if (response == "delete") {
                    bool global = global_check != null && global_check.active;
                    stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY).clear_conversation_history(conversation, global);
                }
            });
            
            dialog.present(button.get_root() as Gtk.Window);
        });
        action_group.add_action(clear_action);
        
        button.insert_action_group("conversation", action_group);
    }

    public new void set_conversation(Conversation conversation) {
        button.sensitive = true;
        this.conversation = conversation;
        update_menu();
    }

    private void update_menu() {
        Menu menu_model = new Menu();
        menu_model.append(_("Conversation Details"), "conversation.details");
        // Invite is available via the occupant menu (user icon)
        // if (conversation.type_ == Conversation.Type.GROUPCHAT) {
        //    menu_model.append(_("Invite Contact"), "conversation.invite");
        // }
        menu_model.append(_("Delete Conversation History"), "conversation.clear");
        if (conversation.type_ == Conversation.Type.GROUPCHAT) {
            menu_model.append(_("Leave Conversation"), "app.close-current-conversation");
        } else {
            menu_model.append(_("Close Conversation"), "app.close-current-conversation");
        }
        
        Gtk.PopoverMenu popover_menu = new Gtk.PopoverMenu.from_model(menu_model);
        button.popover = popover_menu;
    }

    private void on_invite_action(Variant? parameter) {
        if (conversation == null || conversation.type_ != Conversation.Type.GROUPCHAT) return;

        var accounts = new ArrayList<Account>();
        accounts.add(conversation.account);

        SelectContactDialog dialog = new SelectContactDialog(stream_interactor, accounts);
        dialog.title = _("Invite Contact");
        dialog.ok_button.label = _("Invite");
        
        var root = button.get_root() as Gtk.Window;

        dialog.selected.connect((account, jid) => {
            stream_interactor.get_module<MucManager>(MucManager.IDENTITY).invite(conversation.account, conversation.counterpart, jid);
            dialog.close();
        });
        
        dialog.present(root);
    }

    public new void unset_conversation() {
        button.sensitive = false;
    }



    public Object? get_widget(Plugins.WidgetType type) {
        if (type != Plugins.WidgetType.GTK4) return null;
        return button;
    }
}
}
