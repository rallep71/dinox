/*
 * Copyright (C) 2025 Ralf Peter <dinox@handwerker.jetzt>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

using Gee;

using Xmpp;
using Xmpp.Xep;
using Dino.Entities;
using Qlite;

namespace Dino {

    public class MessageDeletion : StreamInteractionModule, MessageListener {
        public static ModuleIdentity<MessageDeletion> IDENTITY = new ModuleIdentity<MessageDeletion>("message_deletion");
        public string id { get { return IDENTITY.id; } }

        public signal void item_deleted(ContentItem content_item);

        private StreamInteractor stream_interactor;
        private Database db;

        public static void start(StreamInteractor stream_interactor, Database db) {
            MessageDeletion m = new MessageDeletion(stream_interactor, db);
            stream_interactor.add_module(m);
        }

        public MessageDeletion(StreamInteractor stream_interactor, Database db) {
            this.stream_interactor = stream_interactor;
            this.db = db;

            stream_interactor.get_module(MessageProcessor.IDENTITY).received_pipeline.connect(this);
            
            // Start timer for auto-deleting expired messages (every 5 minutes)
            Timeout.add_seconds(60 * 5, check_expired_messages);
        }

        public bool is_deletable(Conversation conversation, ContentItem content_item) {
            if (content_item is MessageItem) {
                return ((MessageItem) content_item).message.body != "";
            } else if (content_item is FileItem) {
                return true;
            }
            return false;
        }

        public bool can_delete_for_everyone(Conversation conversation, ContentItem content_item) {
            bool is_own_message = false;
            if (content_item is MessageItem) {
                is_own_message = ((MessageItem) content_item).message.direction == Message.DIRECTION_SENT;
            } else if (content_item is FileItem) {
                is_own_message = ((FileItem) content_item).file_transfer.direction == FileTransfer.DIRECTION_SENT;
                if (((FileItem) content_item).file_transfer.info == null) return false;
            }

            if (conversation.type_.is_muc_semantic()) {
                bool muc_supports_moderation = stream_interactor.get_module(EntityInfo.IDENTITY)
                        .has_feature_cached(conversation.account, conversation.counterpart, Xmpp.Xep.MessageModeration.NS_URI);
                bool we_are_moderator = stream_interactor.get_module(MucManager.IDENTITY).get_own_role(conversation) == Xmpp.Xep.Muc.Role.MODERATOR;
                return is_own_message || (muc_supports_moderation && we_are_moderator);
            } else {
                return is_own_message;
            }
        }

        public void delete_globally(Conversation conversation, ContentItem content_item) {
            var stream = stream_interactor.get_stream(conversation.account);
            if (stream == null) return;

            string message_id_to_delete = stream_interactor.get_module(ContentItemStore.IDENTITY).get_message_id_for_content_item(conversation, content_item);

            if (conversation.type_ == Conversation.Type.CHAT) {
                MessageStanza stanza = new MessageStanza() { to = conversation.counterpart };
                Xmpp.Xep.MessageRetraction.set_retract_id(stanza, message_id_to_delete);
                stream.get_module(MessageModule.IDENTITY).send_message.begin(stream, stanza);
                delete_locally(conversation, content_item, conversation.account.bare_jid);
            } else if (conversation.type_.is_muc_semantic()) {
                bool is_own_message = false;
                if (content_item is MessageItem) {
                    is_own_message = ((MessageItem) content_item).message.direction == Message.DIRECTION_SENT;
                } else if (content_item is FileItem) {
                    is_own_message = ((FileItem) content_item).file_transfer.direction == FileTransfer.DIRECTION_SENT;
                }

                if (is_own_message) {
                    MessageStanza stanza = new MessageStanza() { to = conversation.counterpart };
                    stanza.type_ = MessageStanza.TYPE_GROUPCHAT;
                    Xmpp.Xep.MessageRetraction.set_retract_id(stanza, message_id_to_delete);
                    stream.get_module(MessageModule.IDENTITY).send_message.begin(stream, stanza);
                } else {
                    Xmpp.Xep.MessageModeration.moderate.begin(stream, conversation.counterpart, message_id_to_delete);
                }
                // Message will be deleted locally when the MUC server sends out a moderation/retraction message
            }
        }

        public void delete_locally(Conversation conversation, ContentItem content_item, Jid removed_by) {
            // If it's a file transfer, remove the file
            if (content_item.type_ == FileItem.TYPE) {
                FileItem file_item = (FileItem) content_item;
                if (file_item.file_transfer.path != null) {
                    FileUtils.remove(file_item.file_transfer.path);
                }
            }

            // Mark the (underlying) message as removed and clear the body
            Message? message = stream_interactor.get_module(ContentItemStore.IDENTITY).get_message_for_content_item(conversation, content_item);
            if (message != null) {
                message.body = "";
            }

            // Hide the content item from the view
            db.content_item.update()
                .with(db.content_item.id, "=", content_item.id)
                .set(db.content_item.hide, true)
                .perform();

            item_deleted(content_item);
        }

        public string[] after_actions_const = new string[]{ };
        public override string action_group { get { return "DELETE"; } }
        public override string[] after_actions { get { return after_actions_const; } }

        public override async bool run(Entities.Message message, Xmpp.MessageStanza stanza, Conversation conversation) {
            string? delete_message_id = Xep.MessageRetraction.get_retract_id(stanza);
            if (delete_message_id == null) return false;

            ContentItem? content_item = stream_interactor.get_module(ContentItemStore.IDENTITY).get_content_item_for_referencing_id(conversation, delete_message_id);
            if (content_item != null) {
                debug("Deletion request: %s wants to remove message %s content item id %i. Allowed: %b",
                        message.from.to_string(), delete_message_id, content_item.id,
                        is_removal_allowed(conversation, content_item, stanza.from));
                delete_locally(conversation, content_item, stanza.from);
            }

            return false;
        }

        private bool is_removal_allowed(Conversation conversation, ContentItem content_item, Jid removed_by) {
            if (conversation.type_ == Conversation.Type.CHAT) {
                return removed_by.equals_bare(content_item.jid);
            } else if (conversation.type_.is_muc_semantic()) {
                // Only accept MUC message removals if the MUC server announced support.
                // MUC moderations should always come from the MUC bare JID.
                bool muc_supports_moderation = stream_interactor.get_module(EntityInfo.IDENTITY)
                        .has_feature_cached(conversation.account, conversation.counterpart, Xmpp.Xep.MessageModeration.NS_URI);
                return muc_supports_moderation && removed_by.equals(conversation.counterpart);
            }

            return false;
        }

        // Timer callback for auto-deleting expired messages
        private bool check_expired_messages() {
            var now = new DateTime.now_utc();
            var content_item_store = stream_interactor.get_module(ContentItemStore.IDENTITY);
            
            foreach (Account account in stream_interactor.get_accounts()) {
                foreach (Conversation conversation in db.get_conversations(account)) {
                    if (conversation.message_expiry_seconds > 0) {
                        delete_expired_messages(conversation, now, content_item_store);
                    }
                }
            }
            return true;  // Keep timer running
        }

        private void delete_expired_messages(Conversation conversation, DateTime now, ContentItemStore content_item_store) {
            var cutoff_time = now.add_seconds(-conversation.message_expiry_seconds);
            var items = content_item_store.get_items_older_than(conversation, cutoff_time);
            
            if (items.size > 0) {
                debug("Auto-deleting %d expired messages for %s (older than %s)", 
                      items.size, conversation.counterpart.to_string(), cutoff_time.to_string());
            }
            
            foreach (ContentItem item in items) {
                // Check if it's our own message
                bool is_own = false;
                if (item is MessageItem) {
                    is_own = ((MessageItem) item).message.direction == Message.DIRECTION_SENT;
                } else if (item is FileItem) {
                    is_own = ((FileItem) item).file_transfer.direction == FileTransfer.DIRECTION_SENT;
                }
                
                if (is_own && can_delete_for_everyone(conversation, item)) {
                    // Own message: Delete globally (server + local)
                    delete_globally(conversation, item);
                } else {
                    // Received message: Delete locally only
                    delete_locally(conversation, item, conversation.account.bare_jid);
                }
            }
        }
    }

}
