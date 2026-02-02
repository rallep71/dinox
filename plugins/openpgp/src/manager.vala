using Gee;
using Xmpp;

using Xmpp;
using Dino.Entities;

namespace Dino.Plugins.OpenPgp {

public class Manager : StreamInteractionModule, Object {
    public static ModuleIdentity<Manager> IDENTITY = new ModuleIdentity<Manager>("pgp_manager");
    public string id { get { return IDENTITY.id; } }

    public const string MESSAGE_ENCRYPTED = "pgp";
    
    // XEP-0374 namespace for Service Discovery
    private const string NS_OPENPGP_IM = "urn:xmpp:openpgp:im:0";

    private StreamInteractor stream_interactor;
    private Database db;
    private HashMap<Jid, string> pgp_key_ids = new HashMap<Jid, string>(Jid.hash_bare_func, Jid.equals_bare_func);
    private ReceivedMessageListener received_message_listener = new ReceivedMessageListener();
    
    // XEP-0373 key manager reference - set by plugin after initialization
    public Xep0373KeyManager? xep0373_manager { get; set; default = null; }

    public static void start(StreamInteractor stream_interactor, Database db) {
        Manager m = new Manager(stream_interactor, db);
        stream_interactor.add_module(m);
    }

    private Manager(StreamInteractor stream_interactor, Database db) {
        this.stream_interactor = stream_interactor;
        this.db = db;

        stream_interactor.account_added.connect(on_account_added);
        stream_interactor.get_module<MessageProcessor>(MessageProcessor.IDENTITY).received_pipeline.connect(received_message_listener);
        stream_interactor.get_module<MessageProcessor>(MessageProcessor.IDENTITY).pre_message_send.connect(check_encypt);
    }
    
    /**
     * Check if a contact supports XEP-0374 via Dino's EntityInfo cache
     * Uses synchronous lookup - safe and fast
     */
    private bool check_xep0374_support(Account account, Jid jid) {
        // Use Dino's built-in EntityInfo cache (populated via XEP-0115 Entity Capabilities)
        var entity_info = stream_interactor.get_module<EntityInfo>(EntityInfo.IDENTITY);
        if (entity_info == null) {
            debug("OpenPGP: EntityInfo module not available, cannot check XEP-0374 support");
            return false;
        }
        
        // Try cached lookup first (synchronous, crash-safe)
        bool has_feature = entity_info.has_feature_cached(account, jid.bare_jid, NS_OPENPGP_IM);
        if (has_feature) {
            debug("OpenPGP: %s supports XEP-0374 (cached)", jid.to_string());
            return true;
        }
        
        // Also check offline DB cache for known contacts
        has_feature = entity_info.has_feature_offline(account, jid.bare_jid, NS_OPENPGP_IM);
        if (has_feature) {
            debug("OpenPGP: %s supports XEP-0374 (offline DB)", jid.to_string());
            return true;
        }
        
        debug("OpenPGP: %s does NOT support XEP-0374 - using XEP-0027 fallback", jid.to_string());
        return false;
    }

    public GPGHelper.Key[] get_key_fprs(Conversation conversation) throws Error {
        Gee.List<string> keys = new Gee.ArrayList<string>();
        
        string? account_key = db.get_account_key(conversation.account);
        if (account_key != null) {
            keys.add(account_key);
            debug("OpenPGP get_key_fprs: Added account key %s", account_key);
        } else {
            debug("OpenPGP get_key_fprs: No account key configured!");
        }
        
        if (conversation.type_ == Conversation.Type.GROUPCHAT) {
            Gee.List<Jid> muc_jids = new Gee.ArrayList<Jid>();
            Gee.List<Jid>? occupants = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).get_occupants(conversation.counterpart, conversation.account);
            if (occupants != null) muc_jids.add_all(occupants);
            Gee.List<Jid>? offline_members = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).get_offline_members(conversation.counterpart, conversation.account);
            if (occupants != null) muc_jids.add_all(offline_members);

            foreach (Jid jid in muc_jids) {
                string? key_id = stream_interactor.get_module<Manager>(Manager.IDENTITY).get_key_id(conversation.account, jid);
                if (key_id != null && GPGHelper.get_keylist(key_id).size > 0 && !keys.contains(key_id)) {
                    keys.add(key_id);
                }
            }
        } else {
            string? key_id = get_key_id(conversation.account, conversation.counterpart);
            if (key_id != null) {
                keys.add(key_id);
                debug("OpenPGP get_key_fprs: Added contact key %s for %s", key_id, conversation.counterpart.to_string());
            } else {
                debug("OpenPGP get_key_fprs: No contact key for %s!", conversation.counterpart.to_string());
            }
        }
        
        debug("OpenPGP get_key_fprs: Total %d key IDs to encrypt to", keys.size);
        
        // Build array, filtering out null keys
        var valid_keys = new Gee.ArrayList<GPGHelper.Key>();
        for (int i = 0; i < keys.size; i++) {
            try {
                GPGHelper.Key? key = GPGHelper.get_public_key(keys[i]);
                if (key != null) {
                    valid_keys.add(key);
                    debug("OpenPGP get_key_fprs: Got public key %s", key.fpr);
                } else {
                    debug("OpenPGP get_key_fprs: Key %s returned null!", keys[i]);
                }
            } catch (Error e) {
                debug("OpenPGP: Failed to get public key for %s: %s", keys[i], e.message);
            }
        }
        
        debug("OpenPGP get_key_fprs: Returning %d valid keys", valid_keys.size);
        return valid_keys.to_array();
    }

    private void check_encypt(Entities.Message message, Xmpp.MessageStanza message_stanza, Conversation conversation) {
        debug("OpenPGP check_encypt: message.encryption=%d, PGP=%d, to=%s", 
              (int)message.encryption, (int)Encryption.PGP, conversation.counterpart.to_string());
        try {
            if (message.encryption == Encryption.PGP) {
                debug("OpenPGP check_encypt: Encryption IS PGP, getting keys...");
                GPGHelper.Key[] keys = get_key_fprs(conversation);
                XmppStream? stream = stream_interactor.get_stream(conversation.account);
                if (stream != null) {
                    bool encrypted = false;
                    
                    // Check if contact supports XEP-0374 via Service Discovery cache
                    // If we don't know yet, default to XEP-0027 (more compatible)
                    // The async disco query will populate the cache for next time
                    bool supports_0374 = check_xep0374_support(conversation.account, conversation.counterpart);
                    
                    if (supports_0374) {
                        // Use XEP-0374 format (signcrypt) - modern, more secure
                        encrypted = stream.get_module<Module>(Module.IDENTITY).encrypt_0374(message_stanza, keys);
                        if (encrypted) {
                            debug("OpenPGP: Message encrypted with XEP-0374 format (signcrypt) to %s", conversation.counterpart.to_string());
                        }
                    }
                    
                    if (!encrypted) {
                        // Fall back to XEP-0027 format (legacy) - widely supported
                        encrypted = stream.get_module<Module>(Module.IDENTITY).encrypt(message_stanza, keys);
                        if (encrypted) {
                            debug("OpenPGP: Message encrypted with XEP-0027 format (legacy) to %s", conversation.counterpart.to_string());
                        }
                    }
                    
                    if (!encrypted) message.marked = Entities.Message.Marked.WONTSEND;
                }
            }
        } catch (Error e) {
            debug("OpenPGP: Encryption failed: %s", e.message);
            message.marked = Entities.Message.Marked.WONTSEND;
        }
    }

    public string? get_key_id(Account account, Jid jid) {
        Jid search_jid = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).is_groupchat_occupant(jid, account) ? jid : jid.bare_jid;
        string? key_id = db.get_contact_key(search_jid);
        
        // If no key found locally, try to fetch via XEP-0373 (PubSub)
        // This enables interoperability with Conversations, Monocles, etc.
        if (key_id == null && xep0373_manager != null) {
            debug("OpenPGP: No local key for %s, requesting via XEP-0373", search_jid.to_string());
            xep0373_manager.request_keys.begin(account, search_jid);
            // Note: This is async, so the key won't be immediately available.
            // The user may need to retry or the next message will use the fetched key.
        }
        
        return key_id;
    }

    private void on_account_added(Account account) {
        stream_interactor.module_manager.get_module<Module>(account, Module.IDENTITY).received_jid_key_id.connect((stream, jid, key_id) => {
            on_jid_key_received(account, jid, key_id);
        });
    }

    private void on_jid_key_received(Account account, Jid jid, string key_id) {
        lock (pgp_key_ids) {
            if (!pgp_key_ids.has_key(jid) || pgp_key_ids[jid] != key_id) {
                Jid set_jid = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).is_groupchat_occupant(jid, account) ? jid : jid.bare_jid;
                db.set_contact_key(set_jid, key_id);
            }
            pgp_key_ids[jid] = key_id;
        }
    }

    private class ReceivedMessageListener : MessageListener {

        public string[] after_actions_const = new string[]{ };
        public override string action_group { get { return "DECRYPT"; } }
        public override string[] after_actions { get { return after_actions_const; } }

        public override async bool run(Entities.Message message, Xmpp.MessageStanza stanza, Conversation conversation) {
            if (MessageFlag.get_flag(stanza) != null && MessageFlag.get_flag(stanza).decrypted) {
                message.encryption = Encryption.PGP;
            }
            return false;
        }
    }
}

}
