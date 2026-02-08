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

            stream_interactor.get_module<MessageProcessor>(MessageProcessor.IDENTITY).received_pipeline.connect(this);
            
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
                bool muc_supports_moderation = stream_interactor.get_module<EntityInfo>(EntityInfo.IDENTITY)
                        .has_feature_cached(conversation.account, conversation.counterpart, Xmpp.Xep.MessageModeration.NS_URI);
                bool we_are_moderator = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).get_own_role(conversation) == Xmpp.Xep.Muc.Role.MODERATOR;
                return is_own_message || (muc_supports_moderation && we_are_moderator);
            } else {
                return is_own_message;
            }
        }

        private class RetractionTask {
            public XmppStream stream;
            public MessageStanza stanza;
        }

        private Gee.Queue<RetractionTask> retraction_queue = new LinkedList<RetractionTask>();
        private uint retraction_timer_id = 0;

        public void enqueue_retraction(XmppStream stream, MessageStanza stanza) {
            retraction_queue.offer(new RetractionTask() { stream = stream, stanza = stanza });
            if (retraction_timer_id == 0) {
                retraction_timer_id = Timeout.add(200, process_retraction_queue);
            }
        }

        private bool process_retraction_queue() {
            if (retraction_queue.is_empty) {
                retraction_timer_id = 0;
                return false;
            }

            var task = retraction_queue.poll();
            task.stream.get_module<MessageModule>(MessageModule.IDENTITY).send_message.begin(task.stream, task.stanza);

            return true;
        }

        public void delete_globally(Conversation conversation, ContentItem content_item) {
            var stream = stream_interactor.get_stream(conversation.account);
            if (stream == null) return;

            string? message_id_to_delete = stream_interactor.get_module<ContentItemStore>(ContentItemStore.IDENTITY).get_message_id_for_content_item(conversation, content_item);
            if (message_id_to_delete == null || message_id_to_delete.strip().length == 0) {
                debug("Can't delete globally: missing message reference id (content_item=%i), falling back to local delete", content_item.id);
                // Fall back to local deletion (still satisfies user intent to remove from the UI).
                delete_locally(conversation, content_item, conversation.account.bare_jid);
                return;
            }

            bool perform_retraction = false;
            
            if (conversation.type_ == Conversation.Type.CHAT) {
                perform_retraction = true;
                delete_locally(conversation, content_item, conversation.account.bare_jid);
            } else if (conversation.type_.is_muc_semantic()) {
                bool is_own_message = false;
                if (content_item is MessageItem) {
                    is_own_message = ((MessageItem) content_item).message.direction == Message.DIRECTION_SENT;
                } else if (content_item is FileItem) {
                    is_own_message = ((FileItem) content_item).file_transfer.direction == FileTransfer.DIRECTION_SENT;
                }

                if (is_own_message) {
                    perform_retraction = true;
                } else {
                    Xmpp.Xep.MessageModeration.moderate.begin(stream, conversation.counterpart, (!)message_id_to_delete);
                }
                // Message will be deleted locally when the MUC server sends out a moderation/retraction message
            }
            
            if (perform_retraction) {
                // Send retraction as a proper message (encrypted if needed) with Fallback/Hint
                Entities.Message retraction_msg = new Entities.Message("This message was retracted.");
                retraction_msg.account = conversation.account;
                retraction_msg.counterpart = conversation.counterpart;
                retraction_msg.direction = Entities.Message.DIRECTION_SENT;
                retraction_msg.encryption = conversation.encryption;
                retraction_msg.stanza_id = Xmpp.random_uuid();
                retraction_msg.type_ = Util.get_message_type_for_conversation(conversation);

                if (conversation.type_ == Conversation.Type.GROUPCHAT) {
                    retraction_msg.ourpart = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).get_own_jid(conversation.counterpart, conversation.account) ?? conversation.account.bare_jid;
                } else {
                    retraction_msg.ourpart = conversation.account.full_jid;
                }
                
                // Use a dedicated handler method instead of lambda to avoid Vala compiler crashes
                ulong signal_id = 0;
                var message_processor = stream_interactor.get_module<MessageProcessor>(MessageProcessor.IDENTITY);
                signal_id = message_processor.build_message_stanza.connect((msg, stanza, conv) => {
                    if (msg == retraction_msg) {
                        // 1. Retract
                        Xep.MessageRetraction.set_retract_id(stanza, message_id_to_delete);

                        // 2. Fallback
                        var locations = new ArrayList<Xep.FallbackIndication.FallbackLocation>();
                        // "This message was retracted." is 27 chars
                        locations.add(new Xep.FallbackIndication.FallbackLocation.partial_body(0, 27)); 
                        var fallback = new Xep.FallbackIndication.Fallback(Xep.MessageRetraction.NS_URI, locations);
                        Xep.FallbackIndication.set_fallback(stanza, fallback);

                        // 3. Store Hint
                        Xep.MessageProcessingHints.set_message_hint(stanza, Xep.MessageProcessingHints.HINT_STORE);

                        // Disconnect self immediately
                        GLib.SignalHandler.disconnect(message_processor, signal_id);
                    }
                });

                message_processor.send_xmpp_message(retraction_msg, conversation);
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
            Message? message = stream_interactor.get_module<ContentItemStore>(ContentItemStore.IDENTITY).get_message_for_content_item(conversation, content_item);
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

            ContentItem? content_item = stream_interactor.get_module<ContentItemStore>(ContentItemStore.IDENTITY).get_content_item_for_referencing_id(conversation, delete_message_id);
            
            // Debugging Retraction Issues:
            if (content_item == null) {
                // If standard lookup failed, maybe the ID was stored as the other ID type?
                // Sometimes clients send the stanza-id as 'id', but we stored it as 'server_id' or vice versa,
                // especially in mixed environments (MAM/Carbons).
                // Let's manually try to find it by poking MessageStorage directly for BOTH fields.
                
                var msg_storage = stream_interactor.get_module<MessageStorage>(MessageStorage.IDENTITY);
                Message? found_msg = msg_storage.get_message_by_stanza_id(delete_message_id, conversation);
                if (found_msg == null) {
                    found_msg = msg_storage.get_message_by_server_id(delete_message_id, conversation);
                }
                
                if (found_msg != null) {
                    // We found the message, but ContentItemStore lookup failed. Map it back to ContentItem.
                    // This is a workaround for database lookup inconsistencies.
                     var ci_row = stream_interactor.get_module<ContentItemStore>(ContentItemStore.IDENTITY).get_content_item_row_for_message(conversation, found_msg);
                     if (ci_row != null) {
                         try {
                            content_item = stream_interactor.get_module<ContentItemStore>(ContentItemStore.IDENTITY).get_item_from_row(ci_row, conversation);
                         } catch (GLib.Error e) {}
                     }
                }
            }

            if (content_item != null) {
                bool allowed = is_removal_allowed(conversation, content_item, stanza.from);
                debug("Deletion request: %s wants to remove message %s content item id %i. Allowed: %b",
                        message.from.to_string(), delete_message_id, content_item.id, allowed);
                
                if (allowed) {
                    delete_locally(conversation, content_item, stanza.from);
                    return true;
                }
            } else {
                debug("Deletion request: %s wants to remove message %s but it was not found.", 
                        message.from.to_string(), delete_message_id);
                // Even if we didn't find the message, we should consume the retraction stanza to prevent
                // the fallback "This message was retracted" text from appearing as a new message.
                // The user clearly intended to retract something, showing the fallback is confusing/wrong
                // if we can't link it.
                return true;
            }

            return false;
        }

        private bool is_removal_allowed(Conversation conversation, ContentItem content_item, Jid removed_by) {
            if (conversation.type_ == Conversation.Type.CHAT) {
                // In 1:1 chats, allow retraction if the sender matches (ignoring resource)
                return removed_by.equals_bare(content_item.jid);
            } else if (conversation.type_.is_muc_semantic()) {
                // Case 1: Moderator/Server Removal (XEP-0425) - From Room JID
                if (removed_by.equals(conversation.counterpart)) {
                    return stream_interactor.get_module<EntityInfo>(EntityInfo.IDENTITY)
                        .has_feature_cached(conversation.account, conversation.counterpart, Xmpp.Xep.MessageModeration.NS_URI);
                }
                
                // Case 2: Self-Retraction (XEP-0424) - From Sender's Occupant JID
                // Verify the retraction sender matches the original message sender
                if (removed_by.equals(content_item.jid)) {
                    return true;
                }
            }

            return false;
        }

        // Timer callback for auto-deleting expired messages
        private bool check_expired_messages() {
            var now = new DateTime.now_utc();
            var content_item_store = stream_interactor.get_module<ContentItemStore>(ContentItemStore.IDENTITY);
            
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
