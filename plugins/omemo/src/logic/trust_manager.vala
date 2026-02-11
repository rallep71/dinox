using Dino.Entities;
using Gee;
using Xmpp;
using Omemo;
using Qlite;

namespace Dino.Plugins.Omemo {

public class TrustManager {

    public signal void bad_message_state_updated(Account account, Jid jid, int device_id);
    /** Emitted after an own device is removed from the local DB, so the
     *  device list on PubSub can be republished without that device. */
    public signal void own_device_removed(Account account);

    private StreamInteractor stream_interactor;
    private Database db;
    private TagMessageListener tag_message_listener;

    public HashMap<Message, int> message_device_id_map = new HashMap<Message, int>(Message.hash_func, Message.equals_func);

    public TrustManager(StreamInteractor stream_interactor, Database db) {
        this.stream_interactor = stream_interactor;
        this.db = db;

        tag_message_listener = new TagMessageListener(stream_interactor, this, db, message_device_id_map);
        stream_interactor.get_module<MessageProcessor>(MessageProcessor.IDENTITY).received_pipeline.connect(tag_message_listener);
    }

    public void set_blind_trust(Account account, Jid jid, bool blind_trust) {
        int identity_id = db.identity.get_id(account.id);
        if (identity_id < 0) return;
        db.trust.update()
            .with(db.trust.identity_id, "=", identity_id)
            .with(db.trust.address_name, "=", jid.bare_jid.to_string())
            .set(db.trust.blind_trust, blind_trust).perform();
    }

    /**
     * Remove a device entirely: delete session + identity_meta entry.
     * If this is one of the user's own devices, also emit own_device_removed()
     * so the PubSub device list gets republished without it.
     */
    public void delete_device(Account account, Jid jid, int device_id) {
        int identity_id = db.identity.get_id(account.id);
        if (identity_id < 0) return;

        // Delete the signal session
        Dino.Application? app = Application.get_default() as Dino.Application;
        if (app != null) {
            Store? store = app.stream_interactor.module_manager.get_module<StreamModule>(account, StreamModule.IDENTITY).store;
            if (store != null) {
                try {
                    Address addr = new Address(jid.bare_jid.to_string(), device_id);
                    if (store.contains_session(addr)) {
                        store.delete_session(addr);
                        debug("Deleted session for %s/%d", jid.to_string(), device_id);
                    }
                    addr.device_id = 0;
                } catch (Error e) {
                    warning("Error deleting session for %s/%d: %s", jid.to_string(), device_id, e.message);
                }
            }
        }

        // Delete identity_meta row
        db.identity_meta.delete()
            .with(db.identity_meta.identity_id, "=", identity_id)
            .with(db.identity_meta.address_name, "=", jid.bare_jid.to_string())
            .with(db.identity_meta.device_id, "=", device_id)
            .perform();

        debug("Removed device %s/%d from database", jid.to_string(), device_id);

        // If this was an own device, signal so Manager republishes the PubSub device list
        if (jid.equals_bare(account.bare_jid)) {
            own_device_removed(account);
        }
    }

    public void set_device_trust(Account account, Jid jid, int device_id, TrustLevel trust_level) {
        int identity_id = db.identity.get_id(account.id);
        db.identity_meta.update()
            .with(db.identity_meta.identity_id, "=", identity_id)
            .with(db.identity_meta.address_name, "=", jid.bare_jid.to_string())
            .with(db.identity_meta.device_id, "=", device_id)
            .set(db.identity_meta.trust_level, trust_level).perform();

        // Hide messages from untrusted or unknown devices
        string selection = null;
        string[] selection_args = {};
        var app_db = Application.get_default().db;
        foreach (Row row in db.content_item_meta.with_device(identity_id, jid.bare_jid.to_string(), device_id).with(db.content_item_meta.trusted_when_received, "=", false)) {
            if (selection == null) {
                selection = @"$(app_db.content_item.id) = ?";
            } else {
                selection += @" OR $(app_db.content_item.id) = ?";
            }
            selection_args += row[db.content_item_meta.content_item_id].to_string();
        }
        if (selection != null) {
            app_db.content_item.update()
                .set(app_db.content_item.hide, trust_level == TrustLevel.UNTRUSTED || trust_level == TrustLevel.UNKNOWN)
                .where(selection, selection_args)
                .perform();
        }

        if (trust_level == TrustLevel.TRUSTED) {
            db.identity_meta.update_last_message_untrusted(identity_id, device_id, null);
            bad_message_state_updated(account, jid, device_id);
        }
    }

    public bool is_known_address(Account account, Jid jid) {
        int identity_id = db.identity.get_id(account.id);
        if (identity_id < 0) return false;
        return db.identity_meta.with_address(identity_id, jid.bare_jid.to_string())
                .with(db.identity_meta.now_active, "=", true).count() > 0;
    }

    public Gee.List<int32> get_trusted_devices(Account account, Jid jid) {
        Gee.List<int32> devices = new ArrayList<int32>();
        int identity_id = db.identity.get_id(account.id);
        if (identity_id < 0) return devices;
        foreach (Row device in db.identity_meta.get_trusted_devices(identity_id, jid.bare_jid.to_string())) {
            if(device[db.identity_meta.trust_level] != TrustLevel.UNKNOWN || device[db.identity_meta.identity_key_public_base64] == null)
                devices.add(device[db.identity_meta.device_id]);
        }
        return devices;
    }

    private class TagMessageListener : MessageListener {
        public string[] after_actions_const = new string[]{ "STORE" };
        public override string action_group { get { return "DECRYPT_TAG"; } }
        public override string[] after_actions { get { return after_actions_const; } }

        private StreamInteractor stream_interactor;
        private TrustManager trust_manager;
        private Database db;
        private HashMap<Message, int> message_device_id_map;

        public TagMessageListener(StreamInteractor stream_interactor, TrustManager trust_manager, Database db, HashMap<Message, int> message_device_id_map) {
            this.stream_interactor = stream_interactor;
            this.trust_manager = trust_manager;
            this.db = db;
            this.message_device_id_map = message_device_id_map;
        }

        public override async bool run(Entities.Message message, Xmpp.MessageStanza stanza, Conversation conversation) {
            int device_id = 0;
            if (message_device_id_map.has_key(message)) {
                device_id = message_device_id_map[message];
                message_device_id_map.unset(message);
            }

            // TODO: Handling of files

            ContentItem? content_item = stream_interactor.get_module<ContentItemStore>(ContentItemStore.IDENTITY).get_item_by_foreign(conversation, 1, message.id);

            if (content_item != null && device_id != 0) {
                Jid jid = content_item.jid;
                if (conversation.type_ == Conversation.Type.GROUPCHAT) {
                    jid = message.real_jid;
                }

                int identity_id = db.identity.get_id(conversation.account.id);
                TrustLevel trust_level = (TrustLevel) db.identity_meta.get_device(identity_id, jid.bare_jid.to_string(), device_id)[db.identity_meta.trust_level];
                if (trust_level == TrustLevel.UNTRUSTED || trust_level == TrustLevel.UNKNOWN) {
                    stream_interactor.get_module<ContentItemStore>(ContentItemStore.IDENTITY).set_item_hide(content_item, true);
                    
                    // Don't mark messages as untrusted if they are older than conversation history clear
                    bool should_mark_untrusted = true;
                    if (conversation.history_cleared_at != null && message.time != null) {
                        if (message.time.compare(conversation.history_cleared_at) < 0) {
                            should_mark_untrusted = false;
                        }
                    }
                    
                    if (should_mark_untrusted) {
                        db.identity_meta.update_last_message_untrusted(identity_id, device_id, message.time);
                        trust_manager.bad_message_state_updated(conversation.account, jid, device_id);
                    }
                }

                db.content_item_meta.insert()
                    .value(db.content_item_meta.content_item_id, content_item.id)
                    .value(db.content_item_meta.identity_id, identity_id)
                    .value(db.content_item_meta.address_name, jid.bare_jid.to_string())
                    .value(db.content_item_meta.device_id, device_id)
                    .value(db.content_item_meta.trusted_when_received, trust_level != TrustLevel.UNTRUSTED)
                    .perform();
            }
            return false;
        }
    }
}

}
