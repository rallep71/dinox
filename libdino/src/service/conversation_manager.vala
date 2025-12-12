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
using Dino.Entities;

namespace Dino {
public class ConversationManager : StreamInteractionModule, Object {
    public static ModuleIdentity<ConversationManager> IDENTITY = new ModuleIdentity<ConversationManager>("conversation_manager");
    public string id { get { return IDENTITY.id; } }

    public signal void conversation_activated(Conversation conversation);
    public signal void conversation_deactivated(Conversation conversation);
    public signal void conversation_cleared(Conversation conversation);

    private StreamInteractor stream_interactor;
    private Database db;

    private HashMap<Account, HashMap<Jid, Gee.List<Conversation>>> conversations = new HashMap<Account, HashMap<Jid, Gee.List<Conversation>>>(Account.hash_func, Account.equals_func);

    public static void start(StreamInteractor stream_interactor, Database db) {
        ConversationManager m = new ConversationManager(stream_interactor, db);
        stream_interactor.add_module(m);
    }

    private ConversationManager(StreamInteractor stream_interactor, Database db) {
        this.db = db;
        this.stream_interactor = stream_interactor;
        stream_interactor.add_module(this);
        stream_interactor.account_added.connect(on_account_added);
        stream_interactor.account_removed.connect(on_account_removed);
        stream_interactor.get_module(MessageProcessor.IDENTITY).received_pipeline.connect(new MessageListener(stream_interactor));
        stream_interactor.get_module(MessageProcessor.IDENTITY).message_sent.connect(handle_sent_message);
        stream_interactor.get_module(Calls.IDENTITY).call_incoming.connect(handle_new_call);
        stream_interactor.get_module(Calls.IDENTITY).call_outgoing.connect(handle_new_call);
    }

    public Conversation create_conversation(Jid jid, Account account, Conversation.Type? type = null) {
        assert(conversations.has_key(account));
        Jid store_jid = type == Conversation.Type.GROUPCHAT ? jid.bare_jid : jid;

        // Do we already have a conversation for this jid?
        if (conversations[account].has_key(store_jid)) {
            foreach (var conversation in conversations[account][store_jid]) {
                if (conversation.type_ == type) {
                    return conversation;
                }
            }
        }

        // Create a new converation
        Conversation conversation = new Conversation(jid, account, type);
        // Set encryption for conversation
        if (type == Conversation.Type.CHAT ||
                (type == Conversation.Type.GROUPCHAT && stream_interactor.get_module(MucManager.IDENTITY).is_private_room(account, jid))) {
            conversation.encryption = Application.get_default().settings.get_default_encryption(account);
        } else {
            conversation.encryption = Encryption.NONE;
        }

        add_conversation(conversation);
        conversation.persist(db);
        return conversation;
    }

    public Conversation? get_conversation_for_message(Entities.Message message) {
        if (conversations.has_key(message.account)) {
            if (message.type_ == Entities.Message.Type.CHAT) {
                return create_conversation(message.counterpart.bare_jid, message.account, Conversation.Type.CHAT);
            } else if (message.type_ == Entities.Message.Type.GROUPCHAT) {
                return create_conversation(message.counterpart.bare_jid, message.account, Conversation.Type.GROUPCHAT);
            } else if (message.type_ == Entities.Message.Type.GROUPCHAT_PM) {
                return create_conversation(message.counterpart, message.account, Conversation.Type.GROUPCHAT_PM);
            }
        }
        return null;
    }

    public Gee.List<Conversation> get_conversations(Jid jid, Account account) {
        Gee.List<Conversation> ret = new ArrayList<Conversation>(Conversation.equals_func);
        Conversation? bare_conversation = get_conversation(jid, account);
        if (bare_conversation != null) ret.add(bare_conversation);
        Conversation? full_conversation = get_conversation(jid.bare_jid, account);
        if (full_conversation != null) ret.add(full_conversation);
        return ret;
    }

    public Conversation? get_conversation(Jid jid, Account account, Conversation.Type? type = null) {
        if (conversations.has_key(account)) {
            if (conversations[account].has_key(jid)) {
                foreach (var conversation in conversations[account][jid]) {
                    if (type == null || conversation.type_ == type) {
                        return conversation;
                    }
                }
            }
        }
        return null;
    }

    public Conversation? approx_conversation_for_stanza(Jid from, Jid to, Account account, string msg_ty) {
        if (msg_ty == Xmpp.MessageStanza.TYPE_GROUPCHAT) {
            return get_conversation(from.bare_jid, account, Conversation.Type.GROUPCHAT);
        }

        Jid counterpart = from.equals_bare(account.bare_jid) ? to : from;

        if (msg_ty == Xmpp.MessageStanza.TYPE_CHAT && counterpart.is_full() &&
                get_conversation(counterpart.bare_jid, account, Conversation.Type.GROUPCHAT) != null) {
            var pm = get_conversation(counterpart, account, Conversation.Type.GROUPCHAT_PM);
            if (pm != null) return pm;
        }

        return get_conversation(counterpart.bare_jid, account, Conversation.Type.CHAT);
    }

    public Conversation? get_conversation_by_id(int id) {
        foreach (HashMap<Jid, Gee.List<Conversation>> hm in conversations.values) {
            foreach (Gee.List<Conversation> hm2 in hm.values) {
                foreach (Conversation conversation in hm2) {
                    if (conversation.id == id) {
                        return conversation;
                    }
                }
            }
        }
        return null;
    }

    public Gee.List<Conversation> get_active_conversations(Account? account = null) {
        Gee.List<Conversation> ret = new ArrayList<Conversation>(Conversation.equals_func);
        foreach (Account account_ in conversations.keys) {
            if (account != null && !account_.equals(account)) continue;
            foreach (Gee.List<Conversation> list in conversations[account_].values) {
                foreach (var conversation in list) {
                    if(conversation.active) ret.add(conversation);
                }
            }
        }
        return ret;
    }

    public void start_conversation(Conversation conversation) {
        if (conversation.last_active == null) {
            conversation.last_active = new DateTime.now_utc();
            if (conversation.active) conversation_activated(conversation);
        }
        if (!conversation.active) {
            conversation.active = true;
            conversation_activated(conversation);
        }
    }

    public void close_conversation(Conversation conversation) {
        if (!conversation.active) return;

        conversation.active = false;
        conversation_deactivated(conversation);
    }

    private void on_account_added(Account account) {
        conversations[account] = new HashMap<Jid, ArrayList<Conversation>>(Jid.hash_func, Jid.equals_func);
        foreach (Conversation conversation in db.get_conversations(account)) {
            add_conversation(conversation);
        }
    }

    private void on_account_removed(Account account) {
        foreach (Gee.List<Conversation> list in conversations[account].values) {
            foreach (var conversation in list) {
                if(conversation.active) conversation_deactivated(conversation);
            }
        }
        conversations.unset(account);
    }

    private class MessageListener : Dino.MessageListener {

        public string[] after_actions_const = new string[]{ "DEDUPLICATE", "FILTER_EMPTY" };
        public override string action_group { get { return "MANAGER"; } }
        public override string[] after_actions { get { return after_actions_const; } }

        private StreamInteractor stream_interactor;

        public MessageListener(StreamInteractor stream_interactor) {
            this.stream_interactor = stream_interactor;
        }

        public override async bool run(Entities.Message message, Xmpp.MessageStanza stanza, Conversation conversation) {
            conversation.last_active = message.time;

            if (stanza != null) {
                bool is_mam_message = Xmpp.MessageArchiveManagement.MessageFlag.get_flag(stanza) != null;
                bool is_recent = message.time.compare(new DateTime.now_utc().add_days(-3)) > 0;
                if (is_mam_message && !is_recent) return false;
            }
            stream_interactor.get_module(ConversationManager.IDENTITY).start_conversation(conversation);
            return false;
        }
    }

    private void handle_sent_message(Entities.Message message, Conversation conversation) {
        conversation.last_active = message.time;

        bool is_recent = message.time.compare(new DateTime.now_utc().add_hours(-24)) > 0;
        if (is_recent) {
            start_conversation(conversation);
        }
    }

    private void handle_new_call(Call call, CallState state, Conversation conversation) {
        conversation.last_active = call.time;
        start_conversation(conversation);
    }

    public void clear_conversation_history(Conversation conversation) {
        // Delete all content items globally (server + local) in batches
        var content_item_store = stream_interactor.get_module(ContentItemStore.IDENTITY);
        var message_deletion = stream_interactor.get_module(MessageDeletion.IDENTITY);
        
        // Get items in batches and delete them from server using XEP-0425 Message Retraction
        int batch_size = 100;
        while (true) {
            var items = content_item_store.get_n_latest(conversation, batch_size);
            if (items.size == 0) break;
            
            foreach (ContentItem item in items) {
                if (message_deletion.is_deletable(conversation, item)) {
                    // Send XEP-0425 retraction to server
                    message_deletion.delete_globally(conversation, item);
                }
                // Always delete locally to prevent infinite loop
                // For MUC, delete_globally doesn't delete locally (waits for server confirmation)
                // but we need to proceed regardless
                message_deletion.delete_locally(conversation, item, conversation.account.bare_jid);
            }
            
            if (items.size < batch_size) break;
        }
        
        // Clear message storage caches
        stream_interactor.get_module(MessageStorage.IDENTITY).clear_conversation_cache(conversation);
        
        // Delete all remaining local data from database
        db.message.delete()
            .with(db.message.account_id, "=", conversation.account.id)
            .with(db.message.counterpart_id, "=", db.get_jid_id(conversation.counterpart))
            .with(db.message.type_, "=", Util.get_message_type_for_conversation(conversation))
            .perform();
                
        db.content_item.delete()
            .with(db.content_item.conversation_id, "=", conversation.id)
            .perform();
        
        // NOTE: Message deletion from server depends on XEP-0425 support:
        // - If the server supports XEP-0425 AND applies it to MAM archives: Messages stay deleted
        // - If the server doesn't support it or ignores it for MAM: Messages will reappear on next sync
        // 
        // This is a limitation of XMPP - there's no standard way to delete from MAM archives.
        // XEP-0313 (Message Archive Management) has no delete operation.
        //
        // To check if your server supports XEP-0425 for MAM:
        // 1. Check https://compliance.conversations.im/
        // 2. Or check ejabberd config for mod_message_retract
        
        // CRITICAL: Delete ALL MAM catchup for this account's bare JID
        // This forces a complete re-sync from scratch, but messages will be deduplicated
        // This is the ONLY way to prevent deleted messages from reappearing via MAM
        db.mam_catchup.delete()
            .with(db.mam_catchup.account_id, "=", conversation.account.id)
            .with(db.mam_catchup.server_jid, "=", conversation.account.bare_jid.to_string())
            .perform();
        
        // Mark this conversation as "cleared" with current timestamp
        // This will filter out old messages during MAM re-sync (both in-memory and after restart)
        var clear_timestamp = new DateTime.now_utc();
        conversation.history_cleared_at = clear_timestamp;
        
        // Persist the clear timestamp to database
        db.conversation.update()
            .with(db.conversation.id, "=", conversation.id)
            .set(db.conversation.history_cleared_at, (long) conversation.history_cleared_at.to_unix())
            .perform();
        
        // Clear OMEMO bad message warnings through signal
        // The BadMessagesPopulator will receive this and clear warnings
        // NOTE: OMEMO plugin will also catch this signal via conversation_cleared
        // to delete identity_meta, sessions, and trust data for this contact
        conversation_cleared(conversation);

    }

    private void add_conversation(Conversation conversation) {
        if (!conversations[conversation.account].has_key(conversation.counterpart)) {
            conversations[conversation.account][conversation.counterpart] = new ArrayList<Conversation>(Conversation.equals_func);
        }

        conversations[conversation.account][conversation.counterpart].add(conversation);

        if (conversation.active) {
            conversation_activated(conversation);
        }
    }
}

}
