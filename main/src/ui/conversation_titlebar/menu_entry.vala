using Gtk;

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

        Menu menu_model = new Menu();
        menu_model.append(_("Conversation Details"), "conversation.details");
        menu_model.append(_("Delete Conversation History"), "conversation.clear");
        menu_model.append(_("Close Conversation"), "app.close-current-conversation");
        Gtk.PopoverMenu popover_menu = new Gtk.PopoverMenu.from_model(menu_model);
        button.popover = popover_menu;

        SimpleActionGroup action_group = new SimpleActionGroup();
        SimpleAction details_action = new SimpleAction("details", null);
        details_action.activate.connect((parameter) => {
            var variant = new Variant.tuple(new Variant[] {new Variant.int32(conversation.id), new Variant.string("about")});
            GLib.Application.get_default().activate_action("open-conversation-details", variant);
        });
        action_group.add_action(details_action);
        
        SimpleAction clear_action = new SimpleAction("clear", null);
        clear_action.activate.connect((parameter) => {
            if (conversation == null) return;
            
            // Show confirmation dialog (GTK 4.10+ AlertDialog)
            Gtk.AlertDialog dialog = new Gtk.AlertDialog(
                _("Delete all message history for this conversation?")
            );
            dialog.detail = _("This action cannot be undone.");
            dialog.modal = true;
            dialog.buttons = new string[] { _("Cancel"), _("Delete") };
            dialog.cancel_button = 0;
            dialog.default_button = 0;
            
            dialog.choose.begin(button.get_root() as Gtk.Window, null, (obj, res) => {
                try {
                    int response = dialog.choose.end(res);
                    if (response == 1) { // Delete button
                        stream_interactor.get_module(ConversationManager.IDENTITY).clear_conversation_history(conversation);
                    }
                } catch (Error e) {
                    // Dialog was cancelled or closed
                }
            });
        });
        action_group.add_action(clear_action);
        
        button.insert_action_group("conversation", action_group);
    }

    public new void set_conversation(Conversation conversation) {
        button.sensitive = true;
        this.conversation = conversation;
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
