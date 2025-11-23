using Dino.Entities;
using Gtk;
using Xmpp;

namespace Dino.Ui {
    public Plugins.MessageAction? get_kick_action(ContentItem content_item, Conversation conversation, StreamInteractor stream_interactor) {
        if (conversation.type_ != Conversation.Type.GROUPCHAT) return null;

        // Don't kick yourself
        bool is_own_message = false;
        if (content_item is MessageItem) {
            is_own_message = ((MessageItem) content_item).message.direction == Message.DIRECTION_SENT;
        } else if (content_item is FileItem) {
            is_own_message = ((FileItem) content_item).file_transfer.direction == FileTransfer.DIRECTION_SENT;
        }
        if (is_own_message) return null;

        Jid? occupant_jid = content_item.jid;
        if (occupant_jid == null) return null;

        // Check permissions
        if (!stream_interactor.get_module(MucManager.IDENTITY).kick_possible(conversation.account, occupant_jid)) return null;

        Plugins.MessageAction action = new Plugins.MessageAction();
        action.name = "kick";
        action.icon_name = "system-log-out-symbolic";
        action.tooltip = _("Kick user");

        action.callback = () => {
            stream_interactor.get_module(MucManager.IDENTITY).kick(conversation.account, conversation.counterpart, occupant_jid.resourcepart);
        };

        return action;
    }

    public Plugins.MessageAction? get_ban_action(ContentItem content_item, Conversation conversation, StreamInteractor stream_interactor) {
        if (conversation.type_ != Conversation.Type.GROUPCHAT) return null;

        // Don't ban yourself
        bool is_own_message = false;
        if (content_item is MessageItem) {
            is_own_message = ((MessageItem) content_item).message.direction == Message.DIRECTION_SENT;
        } else if (content_item is FileItem) {
            is_own_message = ((FileItem) content_item).file_transfer.direction == FileTransfer.DIRECTION_SENT;
        }
        if (is_own_message) return null;

        Jid? occupant_jid = content_item.jid;
        if (occupant_jid == null) return null;

        // Check permissions (Owner or Admin)
        Jid? own_jid = stream_interactor.get_module(MucManager.IDENTITY).get_own_jid(conversation.counterpart, conversation.account);
        Xmpp.Xep.Muc.Affiliation? my_affiliation = stream_interactor.get_module(MucManager.IDENTITY).get_affiliation(conversation.counterpart, own_jid, conversation.account);

        if (my_affiliation != Xmpp.Xep.Muc.Affiliation.OWNER && my_affiliation != Xmpp.Xep.Muc.Affiliation.ADMIN) return null;

        Plugins.MessageAction action = new Plugins.MessageAction();
        action.name = "ban";
        action.icon_name = "dialog-error-symbolic";
        action.tooltip = _("Ban user");

        action.callback = () => {
             stream_interactor.get_module(MucManager.IDENTITY).ban(conversation.account, conversation.counterpart, occupant_jid);
        };

        return action;
    }

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

        // Check if it is own message to distinguish between Retraction and Moderation
        bool is_own_message = false;
        if (content_item is MessageItem) {
            is_own_message = ((MessageItem) content_item).message.direction == Message.DIRECTION_SENT;
        } else if (content_item is FileItem) {
            is_own_message = ((FileItem) content_item).file_transfer.direction == FileTransfer.DIRECTION_SENT;
        }

        bool is_moderation = can_delete_for_everyone && !is_own_message;

        Plugins.MessageAction action = new Plugins.MessageAction();
        action.name = "delete";
        action.icon_name = "user-trash-symbolic";
        
        if (is_moderation) {
            action.tooltip = _("Moderate message...");
        } else if (can_delete_for_everyone) {
            action.tooltip = _("Delete...");
        } else {
            action.tooltip = _("Delete locally");
        }

        action.callback = () => {
            // If we can delete for everyone (own message or moderation), offer choice
            if (can_delete_for_everyone) {
                var app = (Dino.Ui.Application) GLib.Application.get_default();
                var window = app.window;

                Gtk.AlertDialog dialog = new Gtk.AlertDialog(
                    is_moderation ? _("Moderate message") : _("Delete message")
                );

                if (is_moderation) {
                    dialog.detail = _("Do you want to remove this message from the channel?");
                    dialog.buttons = new string[] { _("Cancel"), _("Remove") };
                } else {
                    dialog.detail = _("Do you want to delete this message just for yourself or for everyone?");
                    dialog.buttons = new string[] { _("Cancel"), _("Delete locally"), _("Delete for everyone") };
                }

                dialog.modal = true;
                dialog.cancel_button = 0;
                dialog.default_button = 0; // Default to Cancel for safety
                
                dialog.choose.begin(window, null, (obj, res) => {
                    try {
                        int response = dialog.choose.end(res);
                        if (is_moderation) {
                            if (response == 1) { // Remove (Globally)
                                stream_interactor.get_module(MessageDeletion.IDENTITY).delete_globally(conversation, content_item);
                            }
                        } else {
                            if (response == 1) { // Delete locally
                                stream_interactor.get_module(MessageDeletion.IDENTITY).delete_locally(conversation, content_item, conversation.account.bare_jid);
                            } else if (response == 2) { // Delete for everyone
                                stream_interactor.get_module(MessageDeletion.IDENTITY).delete_globally(conversation, content_item);
                            }
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
