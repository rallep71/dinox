using Dino.Entities;
using Gtk;

namespace Dino.Ui {
    public Plugins.MessageAction get_reaction_action(ContentItem content_item, Conversation conversation, StreamInteractor stream_interactor) {
        Plugins.MessageAction action = new Plugins.MessageAction();
        action.name = "reaction";
        action.icon_name = "dino-emoticon-add-symbolic";
        action.tooltip = _("Add reaction");

        action.callback = (variant) => {
            string emoji = variant.get_string();
            stream_interactor.get_module(Reactions.IDENTITY).add_reaction(conversation, content_item, emoji);
        };

        // Disable the button if reaction aren't possible.
        bool supports_reactions = stream_interactor.get_module(Reactions.IDENTITY).conversation_supports_reactions(conversation);
        string? message_id = stream_interactor.get_module(ContentItemStore.IDENTITY).get_message_id_for_content_item(conversation, content_item);

        if (!supports_reactions) {
            action.tooltip = _("This conversation does not support reactions.");
            action.sensitive = false;
        } else if (message_id == null) {
            action.tooltip = "This message does not support reactions.";
            action.sensitive = false;
        }
        return action;
    }

    public Plugins.MessageAction get_reply_action(ContentItem content_item, Conversation conversation, StreamInteractor stream_interactor) {
        Plugins.MessageAction action = new Plugins.MessageAction();
        action.name = "reply";
        action.icon_name = "mail-reply-sender-symbolic";
        action.tooltip = _("Reply");
        action.callback = () => {
            GLib.Application.get_default().activate_action("quote", new GLib.Variant.tuple(new GLib.Variant[] { new GLib.Variant.int32(conversation.id), new GLib.Variant.int32(content_item.id) }));
        };

        // Disable the button if replies aren't possible.
        string? message_id = stream_interactor.get_module(ContentItemStore.IDENTITY).get_message_id_for_content_item(conversation, content_item);
        if (message_id == null) {
            action.sensitive = false;
            if (conversation.type_.is_muc_semantic()) {
                action.tooltip = _("This conversation does not support replies.");
            } else {
                action.tooltip = "This message does not support replies.";
            }
        }
        return action;
    }

    public Plugins.MessageAction? get_delete_action(ContentItem content_item, Conversation conversation, StreamInteractor stream_interactor) {
        bool is_deletable = stream_interactor.get_module(MessageDeletion.IDENTITY).is_deletable(conversation, content_item);
        if (!is_deletable) return null;

        bool can_delete_for_everyone = stream_interactor.get_module(MessageDeletion.IDENTITY).can_delete_for_everyone(conversation, content_item);

        Plugins.MessageAction action = new Plugins.MessageAction();
        action.name = "delete";
        action.icon_name = "user-trash-symbolic";
        
        if (can_delete_for_everyone) {
            action.tooltip = _("Delete...");
        } else {
            action.tooltip = _("Delete locally");
        }

        action.callback = () => {
            // If we can delete for everyone (own message), offer choice
            if (can_delete_for_everyone) {
                var app = (Dino.Ui.Application) GLib.Application.get_default();
                var window = app.window;

                Gtk.AlertDialog dialog = new Gtk.AlertDialog(
                    _("Delete message")
                );
                dialog.detail = _("Do you want to delete this message just for yourself or for everyone?");
                dialog.modal = true;
                dialog.buttons = new string[] { _("Cancel"), _("Delete locally"), _("Delete for everyone") };
                dialog.cancel_button = 0;
                dialog.default_button = 0; // Default to Cancel for safety
                
                dialog.choose.begin(window, null, (obj, res) => {
                    try {
                        int response = dialog.choose.end(res);
                        if (response == 1) { // Delete locally
                            stream_interactor.get_module(MessageDeletion.IDENTITY).delete_locally(conversation, content_item, conversation.account.bare_jid);
                        } else if (response == 2) { // Delete for everyone
                            stream_interactor.get_module(MessageDeletion.IDENTITY).delete_globally(conversation, content_item);
                        }
                    } catch (Error e) {
                        // Cancelled
                    }
                });
            } else {
                stream_interactor.get_module(MessageDeletion.IDENTITY).delete_locally(conversation, content_item, conversation.account.bare_jid);
            }
        };
        return action;
    }
}
