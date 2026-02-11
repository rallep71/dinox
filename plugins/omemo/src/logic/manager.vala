using Dino.Entities;
using Omemo;
using Qlite;
using Xmpp;
using Gee;

namespace Dino.Plugins.Omemo {

public class Manager : StreamInteractionModule, Object {
    public static ModuleIdentity<Manager> IDENTITY = new ModuleIdentity<Manager>("omemo_manager");
    public string id { get { return IDENTITY.id; } }

    private StreamInteractor stream_interactor;
    private Database db;
    private TrustManager trust_manager;
    private HashMap<Account, OmemoEncryptor> encryptors;
    private HashMap<Account, Omemo2Encrypt> encryptors_v2;
    private Map<Entities.Message, MessageState> message_states = new HashMap<Entities.Message, MessageState>(Entities.Message.hash_func, Entities.Message.equals_func);
    /* Track JIDs that have announced OMEMO 2 devices */
    private HashSet<string> v2_jids = new HashSet<string>();

    private class MessageState {
        public Entities.Message msg { get; private set; }
        public Xep.Omemo.EncryptState last_try { get; private set; }
        public int waiting_other_sessions { get; set; }
        public int waiting_own_sessions { get; set; }
        public bool waiting_own_devicelist { get; set; }
        public int waiting_other_devicelists { get; set; }
        public bool force_next_attempt { get; set; }
        public bool will_send_now { get; private set; }
        public bool active_send_attempt { get; set; }

        public MessageState(Entities.Message msg, Xep.Omemo.EncryptState last_try) {
            update_from_encrypt_status(msg, last_try);
        }

        public void update_from_encrypt_status(Entities.Message msg, Xep.Omemo.EncryptState new_try) {
            this.msg = msg;
            this.last_try = new_try;
            this.waiting_other_sessions = new_try.other_unknown;
            this.waiting_own_sessions = new_try.own_unknown;
            this.waiting_own_devicelist = !new_try.own_list;
            this.waiting_other_devicelists = new_try.other_waiting_lists;
            this.active_send_attempt = false;
            will_send_now = false;
            if (new_try.other_failure > 0 || (new_try.other_lost == new_try.other_devices && new_try.other_devices > 0)) {
                msg.marked = Entities.Message.Marked.WONTSEND;
            } else if (new_try.other_unknown > 0 || new_try.own_unknown > 0 || new_try.other_waiting_lists > 0 || !new_try.own_list || new_try.own_devices == 0) {
                msg.marked = Entities.Message.Marked.UNSENT;
            } else if (!new_try.encrypted) {
                msg.marked = Entities.Message.Marked.WONTSEND;
            } else {
                will_send_now = true;
            }
        }

        public bool should_retry_now() {
            return !waiting_own_devicelist && waiting_other_devicelists <= 0 && waiting_other_sessions <= 0 && waiting_own_sessions <= 0 && !active_send_attempt;
        }

        public string to_string() {
            return @"MessageState (msg=$(msg.stanza_id), send=$will_send_now, $last_try)";
        }
    }

    private Manager(StreamInteractor stream_interactor, Database db, TrustManager trust_manager, HashMap<Account, OmemoEncryptor> encryptors, HashMap<Account, Omemo2Encrypt> encryptors_v2) {
        this.stream_interactor = stream_interactor;
        this.db = db;
        this.trust_manager = trust_manager;
        this.encryptors = encryptors;
        this.encryptors_v2 = encryptors_v2;

        stream_interactor.account_added.connect(on_account_added);
        stream_interactor.account_removed.connect(on_account_removed);
        stream_interactor.stream_negotiated.connect(on_stream_negotiated);
        stream_interactor.get_module<MessageProcessor>(MessageProcessor.IDENTITY).pre_message_send.connect(on_pre_message_send);
        stream_interactor.get_module<RosterManager>(RosterManager.IDENTITY).mutual_subscription.connect(on_mutual_subscription);
        stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY).conversation_cleared.connect(on_conversation_cleared);

        // When the user removes an own device via TrustManager, republish the device list
        trust_manager.own_device_removed.connect((account) => {
            XmppStream? stream = stream_interactor.get_stream(account);
            if (stream != null) {
                republish_device_list(account, stream);
                republish_device_list_v2(account, stream);
            }
        });
    }

    private void on_conversation_cleared(Conversation conversation) {
        // When conversation history is cleared, also clear OMEMO data for this contact
        clear_contact_data(conversation.account, conversation.counterpart);
    }

    private void clear_contact_data(Account account, Xmpp.Jid jid) {
        int identity_id = db.identity.get_id(account.id);
        if (identity_id < 0) return;

        string address_name = jid.bare_jid.to_string();

        // Delete all OMEMO data for this contact
        db.identity_meta.delete()
                .with(db.identity_meta.identity_id, "=", identity_id)
                .with(db.identity_meta.address_name, "=", address_name)
                .perform();

        db.session.delete()
                .with(db.session.identity_id, "=", identity_id)
                .with(db.session.address_name, "=", address_name)
                .perform();

        db.trust.delete()
                .with(db.trust.identity_id, "=", identity_id)
                .with(db.trust.address_name, "=", address_name)
                .perform();

        // Note: content_item_meta is tied to message_id, already deleted when messages are deleted
    }

    public void clear_device_list(Account account) {
        XmppStream? stream = stream_interactor.get_stream(account);
        if (stream == null) return;

        stream.get_module<StreamModule>(StreamModule.IDENTITY).clear_device_list(stream);
    }

    private Gee.List<Jid> get_occupants(Jid jid, Account account){
        Gee.List<Jid> occupants = new ArrayList<Jid>(Jid.equals_bare_func);
        if(!stream_interactor.get_module<MucManager>(MucManager.IDENTITY).is_groupchat(jid, account)){
            occupants.add(jid);
        }
        Gee.List<Jid>? occupant_jids = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).get_offline_members(jid, account);
        if(occupant_jids == null) {
            return occupants;
        }
        foreach (Jid occupant in occupant_jids) {
            if(!occupant.equals(account.bare_jid)){
                occupants.add(occupant.bare_jid);
            }
        }
        return occupants;
    }

    private void on_pre_message_send(Entities.Message message, Xmpp.MessageStanza message_stanza, Conversation conversation) {
        if (message.encryption == Encryption.OMEMO) {
            if (message.type_ == Message.Type.GROUPCHAT_PM) {
                message.marked = Message.Marked.WONTSEND;
                return;
            }
            XmppStream? stream = stream_interactor.get_stream(conversation.account);
            if (stream == null) {
                message.marked = Entities.Message.Marked.UNSENT;
                return;
            }
            StreamModule? module_ = ((!)stream).get_module<StreamModule>(StreamModule.IDENTITY);
            if (module_ == null) {
                message.marked = Entities.Message.Marked.UNSENT;
                return;
            }
            StreamModule module = (!)module_;

            //Get a list of everyone for whom the message should be encrypted
            Gee.List<Jid> recipients;
            if (message_stanza.type_ == MessageStanza.TYPE_GROUPCHAT) {
                recipients = get_occupants((!)message.to.bare_jid, conversation.account);
                if (recipients.size == 0) {
                    message.marked = Entities.Message.Marked.WONTSEND;
                    return;
                }
            } else {
                recipients = new ArrayList<Jid>(Jid.equals_bare_func);
                recipients.add(message_stanza.to);
            }

            //Attempt to encrypt the message
            /* Check if any recipient has OMEMO 2 devices -- if so, use v2 encryptor */
            bool use_v2 = false;
            foreach (Jid recipient in recipients) {
                if (v2_jids.contains(recipient.bare_jid.to_string())) {
                    use_v2 = true;
                    break;
                }
            }

            Xep.Omemo.EncryptState enc_state;
            if (use_v2 && encryptors_v2.has_key(conversation.account)) {
                debug("OMEMO 2: Using v2 encryptor for message (recipient has v2 devices)");
                enc_state = encryptors_v2[conversation.account].encrypt(message_stanza, conversation.account.bare_jid, recipients, stream);
            } else {
                enc_state = encryptors[conversation.account].encrypt(message_stanza, conversation.account.bare_jid, recipients, stream);
            }
            MessageState state;
            lock (message_states) {
                if (message_states.has_key(message)) {
                    state = message_states.get(message);
                    state.update_from_encrypt_status(message, enc_state);
                    if (state.will_send_now) {
                        debug("sending message delayed: %s", state.to_string());
                    }
                } else {
                    state = new MessageState(message, enc_state);
                    message_states[message] = state;
                }
                if (state.will_send_now) {
                    message_states.unset(message);
                }
            }

            //Encryption failed - need to fetch more information
            if (!state.will_send_now) {
                if (message.marked == Entities.Message.Marked.WONTSEND) {
                    debug("retracting message %s", state.to_string());
                    message_states.unset(message);
                } else {
                    debug("delaying message %s", state.to_string());

                    if (state.waiting_own_sessions > 0) {
                        module.fetch_bundles((!)stream, conversation.account.bare_jid, trust_manager.get_trusted_devices(conversation.account, conversation.account.bare_jid));
                    }
                    if (state.waiting_other_sessions > 0 && message.counterpart != null) {
                        foreach(Jid jid in get_occupants(((!)message.counterpart).bare_jid, conversation.account)) {
                            module.fetch_bundles((!)stream, jid, trust_manager.get_trusted_devices(conversation.account, jid));
                        }
                    }
                    if (state.waiting_other_devicelists > 0 && message.counterpart != null) {
                        foreach(Jid jid in get_occupants(((!)message.counterpart).bare_jid, conversation.account)) {
                            module.request_user_devicelist.begin((!)stream, jid);
                        }
                    }
                }
            }
        }
    }

    private void on_mutual_subscription(Account account, Jid jid) {
        XmppStream? stream = stream_interactor.get_stream(account);
        if(stream == null) return;

        stream_interactor.module_manager.get_module<StreamModule>(account, StreamModule.IDENTITY).request_user_devicelist.begin((!)stream, jid);
        StreamModule2? module2 = stream_interactor.module_manager.get_module<StreamModule2>(account, StreamModule2.IDENTITY);
        if (module2 != null) {
            module2.request_user_devicelist.begin((!)stream, jid);
        }
    }

    private void on_stream_negotiated(Account account, XmppStream stream) {
        StreamModule module = stream_interactor.module_manager.get_module<StreamModule>(account, StreamModule.IDENTITY);
        if (module != null) {
            // Request our device list - this will automatically trigger republish if needed
            module.request_user_devicelist.begin(stream, account.bare_jid, (obj, res) => {
                module.request_user_devicelist.end(res);
                // Force republish of device list to notify all subscribers
                republish_device_list_with_retry(account, stream, 5);
            });
        }
        /* Also request OMEMO 2 device list */
        StreamModule2? module2 = stream_interactor.module_manager.get_module<StreamModule2>(account, StreamModule2.IDENTITY);
        if (module2 != null) {
            module2.request_user_devicelist.begin(stream, account.bare_jid);

            /* Request v2 device lists for all active conversation partners.
             * PEP auto-notifications may not arrive for all contacts,
             * so we actively fetch their v2 device lists too. */
            Gee.List<Conversation> conversations = stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY).get_active_conversations(account);
            foreach (Conversation conv in conversations) {
                if (conv.counterpart != null && !conv.counterpart.equals_bare(account.bare_jid)) {
                    module2.request_user_devicelist.begin(stream, conv.counterpart.bare_jid);
                }
            }
        }
    }

    // Republish device list with retry mechanism for race condition after new account creation
    // After Panic Wipe + new login, initialize_store (async key generation) may not be finished
    // when on_stream_negotiated fires. This retry ensures we eventually publish the device list.
    private void republish_device_list_with_retry(Account account, XmppStream stream, int retries_left) {
        int identity_id = db.identity.get_id(account.id);
        if (identity_id < 0) {
            if (retries_left > 0) {
                // Identity not yet created (initialize_store still running), retry after delay
                debug("OMEMO: Identity not yet available for %s, retrying in 500ms (%d retries left)", 
                      account.bare_jid.to_string(), retries_left);
                Timeout.add(500, () => {
                    // Verify stream is still valid
                    if (stream_interactor.get_stream(account) == stream) {
                        republish_device_list_with_retry(account, stream, retries_left - 1);
                    }
                    return false; // Don't repeat
                });
            } else {
                warning("OMEMO: Identity still not available after retries for %s", account.bare_jid.to_string());
            }
            return;
        }
        
        // Identity exists, proceed with republish
        republish_device_list(account, stream);
    }

    private void republish_device_list(Account account, XmppStream stream) {
        int identity_id = db.identity.get_id(account.id);
        if (identity_id < 0) return;

        StreamModule? module = stream.get_module<StreamModule>(StreamModule.IDENTITY);
        if (module == null) return;
        int32 current_device_id = (int32) module.store.local_registration_id;

        // Build device list with all known active devices
        ArrayList<int32> devices = new ArrayList<int32>();
        foreach (Row row in db.identity_meta.with_address(identity_id, account.bare_jid.to_string())
                .with(db.identity_meta.now_active, "=", true)) {
            devices.add(row[db.identity_meta.device_id]);
        }

        // Ensure current device is in the list
        if (!devices.contains(current_device_id)) {
             devices.add(current_device_id);
        }

        // Create device list stanza node
        StanzaNode list_node = new StanzaNode.build("list", Xep.Omemo.NS_URI).add_self_xmlns();
        foreach (int32 device_id in devices) {
            list_node.put_node(new StanzaNode.build("device", Xep.Omemo.NS_URI)
                .put_attribute("id", device_id.to_string()));
        }

        // Publish to trigger PEP notification to all subscribers
        // NODE_DEVICELIST = "eu.siacs.conversations.axolotl.devicelist"
        stream.get_module<Xep.Pubsub.Module>(Xep.Pubsub.Module.IDENTITY).publish.begin(stream, account.bare_jid, 
            Xep.Omemo.NS_URI + ".devicelist", null, list_node);
        
        debug("Republished device list for %s with %d devices", account.bare_jid.to_string(), devices.size);
    }

    /**
     * Republish OMEMO 2 device list to PubSub based on current DB state.
     * Same logic as republish_device_list() but for the urn:xmpp:omemo:2:devices node.
     */
    private void republish_device_list_v2(Account account, XmppStream stream) {
        int identity_id = db.identity.get_id(account.id);
        if (identity_id < 0) return;

        StreamModule2? module2 = stream.get_module<StreamModule2>(StreamModule2.IDENTITY);
        if (module2 == null) return;
        int32 current_device_id = (int32) module2.store.local_registration_id;

        // Build device list from DB (same source as v1 -- they share device IDs)
        ArrayList<int32> devices = new ArrayList<int32>();
        foreach (Row row in db.identity_meta.with_address(identity_id, account.bare_jid.to_string())
                .with(db.identity_meta.now_active, "=", true)) {
            devices.add(row[db.identity_meta.device_id]);
        }

        // Ensure current device is in the list
        if (!devices.contains(current_device_id)) {
            devices.add(current_device_id);
        }

        // Create OMEMO 2 device list stanza: <devices xmlns='urn:xmpp:omemo:2'><device id='...'/></devices>
        StanzaNode devices_node = new StanzaNode.build("devices", Xep.Omemo.NS_URI_V2).add_self_xmlns();
        foreach (int32 device_id in devices) {
            devices_node.put_node(new StanzaNode.build("device", Xep.Omemo.NS_URI_V2)
                .put_attribute("id", device_id.to_string()));
        }

        stream.get_module<Xep.Pubsub.Module>(Xep.Pubsub.Module.IDENTITY).publish.begin(stream, account.bare_jid,
            Xep.Omemo.NODE_DEVICELIST_V2, null, devices_node);

        debug("Republished OMEMO 2 device list for %s with %d devices", account.bare_jid.to_string(), devices.size);
    }

    private void on_account_added(Account account) {
        StreamModule module = stream_interactor.module_manager.get_module<StreamModule>(account, StreamModule.IDENTITY);
        if (module != null) {
            module.device_list_loaded.connect((jid, devices) => on_device_list_loaded(account, jid, devices));
            module.bundle_fetched.connect((jid, device_id, bundle) => on_bundle_fetched(account, jid, device_id, bundle));
            module.bundle_fetch_failed.connect((jid) => continue_message_sending(account, jid));
            module.device_label_received.connect((jid, device_id, label) => {
                int identity_id = db.identity.get_id(account.id);
                if (identity_id >= 0) {
                    db.identity_meta.update_device_label(identity_id, jid.bare_jid.to_string(), device_id, label);
                    debug("OMEMO 1: Stored device label '%s' for %s/%d", label, jid.to_string(), device_id);
                }
            });
        }
        /* OMEMO 2 stream module */
        StreamModule2? module2 = stream_interactor.module_manager.get_module<StreamModule2>(account, StreamModule2.IDENTITY);
        if (module2 != null) {
            module2.device_list_loaded.connect((jid, devices) => {
                /* Track JIDs that announce OMEMO 2 devices */
                if (devices.size > 0) {
                    v2_jids.add(jid.bare_jid.to_string());
                    /* Also register for ESFS file transfer detection */
                    Dino.Entities.FileTransfer.register_esfs_jid(jid.bare_jid.to_string());
                    debug("OMEMO 2: Marked %s as v2-capable (%d devices)", jid.bare_jid.to_string(), devices.size);
                }
                /* Handle v2 device list separately -- must be ADDITIVE.
                 * DO NOT call on_device_list_loaded() here! That function
                 * uses insert_device_list() which destructively deactivates
                 * ALL existing devices before reactivating listed ones.
                 * An empty v2 list (contact doesn't support OMEMO 2) would
                 * wipe all v1 devices. Even a non-empty v2 list would
                 * deactivate v1-only devices. */
                on_device_list_loaded_v2(account, jid, devices);
            });
            module2.bundle_fetched.connect((jid, device_id, bundle) => on_bundle_v2_fetched(account, jid, device_id, bundle));
            module2.bundle_fetch_failed.connect((jid) => continue_message_sending(account, jid));
            module2.device_label_received.connect((jid, device_id, label) => {
                int identity_id = db.identity.get_id(account.id);
                if (identity_id >= 0) {
                    db.identity_meta.update_device_label(identity_id, jid.bare_jid.to_string(), device_id, label);
                    debug("OMEMO 2: Stored device label '%s' for %s/%d", label, jid.to_string(), device_id);
                }
            });
        }
        initialize_store.begin(account);
    }

    private void on_account_removed(Account account) {
        // Clean up all OMEMO data for this account from omemo.db
        int identity_id = db.identity.get_id(account.id);
        if (identity_id < 0) return;

        // Delete child tables first (reference identity_id)
        db.content_item_meta.delete().with(db.content_item_meta.identity_id, "=", identity_id).perform();
        db.trust.delete().with(db.trust.identity_id, "=", identity_id).perform();
        db.identity_meta.delete().with(db.identity_meta.identity_id, "=", identity_id).perform();
        db.session.delete().with(db.session.identity_id, "=", identity_id).perform();
        db.pre_key.delete().with(db.pre_key.identity_id, "=", identity_id).perform();
        db.signed_pre_key.delete().with(db.signed_pre_key.identity_id, "=", identity_id).perform();

        // Delete the identity row itself (own keypair)
        db.identity.delete().with(db.identity.account_id, "=", account.id).perform();

        // Remove from in-memory caches
        encryptors.unset(account);
        encryptors_v2.unset(account);
    }

    private void on_device_list_loaded(Account account, Jid jid, ArrayList<int32> device_list) {
        debug("received device list for %s from %s", account.bare_jid.to_string(), jid.to_string());

        XmppStream? stream = stream_interactor.get_stream(account);
        if (stream == null) {
            return;
        }
        StreamModule? module = ((!)stream).get_module<StreamModule>(StreamModule.IDENTITY);
        if (module == null) {
            return;
        }

        int identity_id = db.identity.get_id(account.id);
        if (identity_id < 0) return;

        //Update meta database
        db.identity_meta.insert_device_list(identity_id, jid.bare_jid.to_string(), device_list);

        //Fetch the bundle for each new device (try both legacy and OMEMO 2)
        StreamModule2? module2 = ((!)stream).get_module<StreamModule2>(StreamModule2.IDENTITY);
        int inc = 0;
        foreach (Row row in db.identity_meta.get_unknown_devices(identity_id, jid.bare_jid.to_string())) {
            try {
                Jid device_jid = new Jid(row[db.identity_meta.address_name]);
                int device_id = row[db.identity_meta.device_id];
                module.fetch_bundle(stream, device_jid, device_id, false);
                if (module2 != null) {
                    module2.fetch_bundle(stream, device_jid, device_id, false);
                }
                inc++;
            } catch (InvalidJidError e) {
                warning("Ignoring device with invalid Jid: %s", e.message);
            }
        }
        if (inc > 0) {
            debug("new bundles %i/%i for %s (legacy + v2)", inc, device_list.size, jid.to_string());
        }

        /* Also fetch v2 bundles for known devices without a session.
         * This covers OMEMO 2-only devices (e.g. Kaidan) that were already
         * inserted into the DB but whose legacy bundle fetch failed. */
        if (module2 != null) {
            int v2_inc = 0;
            foreach (int32 device_id in device_list) {
                Address address = new Address(jid.bare_jid.to_string(), device_id);
                try {
                    if (!module.store.contains_session(address)) {
                        module2.fetch_bundle(stream, jid, device_id, false);
                        v2_inc++;
                    }
                } catch (Error e) {
                    // ignore
                }
                address.device_id = 0;
            }
            if (v2_inc > 0) {
                debug("v2 session-less bundles %i/%i for %s", v2_inc, device_list.size, jid.to_string());
            }
        }

        //Create an entry for the jid in the account table if one does not exist already
        if (db.trust.select().with(db.trust.identity_id, "=", identity_id).with(db.trust.address_name, "=", jid.bare_jid.to_string()).count() == 0) {
            db.trust.insert().value(db.trust.identity_id, identity_id).value(db.trust.address_name, jid.bare_jid.to_string()).value(db.trust.blind_trust, true).perform();
        }

        //Get all messages that needed the devicelist and determine if we can now send them
        HashSet<Entities.Message> send_now = new HashSet<Entities.Message>();
        lock (message_states) {
            foreach (Entities.Message msg in message_states.keys) {
                if (!msg.account.equals(account)) continue;
                MessageState state = message_states[msg];
                if (account.bare_jid.equals(jid)) {
                    state.waiting_own_devicelist = false;
                } else if (msg.counterpart != null) {
                    Gee.List<Jid> occupants = get_occupants(msg.counterpart.bare_jid, account);
                    if (occupants.contains(jid)) {
                        state.waiting_other_devicelists--;
                    }
                }
                if (state.should_retry_now()) {
                    send_now.add(msg);
                    state.active_send_attempt = true;
                }
            }
        }
        foreach (Entities.Message msg in send_now) {
            if (msg.counterpart == null) continue;
            Entities.Conversation? conv = stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY).get_conversation(((!)msg.counterpart), account);
            if (conv == null) continue;
            stream_interactor.get_module<MessageProcessor>(MessageProcessor.IDENTITY).send_xmpp_message(msg, (!)conv, true);
        }

    }

    /**
     * Handle OMEMO 2 device list results -- ADDITIVE processing.
     * Unlike the v1 handler, this does NOT deactivate existing devices.
     * Empty v2 lists are ignored (contact doesn't support OMEMO 2).
     */
    private void on_device_list_loaded_v2(Account account, Jid jid, ArrayList<int32> device_list) {
        if (device_list.size == 0) {
            // Contact has no OMEMO 2 devices -- nothing to do.
            // Crucially, we do NOT deactivate their v1 devices.
            return;
        }

        debug("OMEMO 2: received v2 device list for %s (%d devices)", jid.to_string(), device_list.size);

        XmppStream? stream = stream_interactor.get_stream(account);
        if (stream == null) return;

        int identity_id = db.identity.get_id(account.id);
        if (identity_id < 0) return;

        // Additively add v2 devices (don't deactivate existing v1 devices)
        db.identity_meta.insert_device_list_additive(identity_id, jid.bare_jid.to_string(), device_list);

        // Create trust entry if needed
        if (db.trust.select().with(db.trust.identity_id, "=", identity_id).with(db.trust.address_name, "=", jid.bare_jid.to_string()).count() == 0) {
            db.trust.insert().value(db.trust.identity_id, identity_id).value(db.trust.address_name, jid.bare_jid.to_string()).value(db.trust.blind_trust, true).perform();
        }

        // Fetch v2 bundles for devices without a session
        StreamModule2? module2 = stream.get_module<StreamModule2>(StreamModule2.IDENTITY);
        if (module2 != null) {
            foreach (int32 device_id in device_list) {
                Address address = new Address(jid.bare_jid.to_string(), device_id);
                try {
                    if (!module2.store.contains_session(address)) {
                        module2.fetch_bundle(stream, jid, device_id, false);
                    }
                } catch (Error e) {
                    // ignore
                }
                address.device_id = 0;
            }
        }

        // Continue any waiting messages
        continue_message_sending(account, jid);
    }

    private void on_bundle_fetched(Account account, Jid jid, int32 device_id, Bundle bundle) {
        int identity_id = db.identity.get_id(account.id);
        if (identity_id < 0) return;

        bool blind_trust = db.trust.get_blind_trust(identity_id, jid.bare_jid.to_string(), true);

        //If we don't blindly trust new devices and we haven't seen this key before then don't trust it
        bool untrust = !(blind_trust || db.identity_meta.with_address(identity_id, jid.bare_jid.to_string())
                .with(db.identity_meta.device_id, "=", device_id)
                .with(db.identity_meta.identity_key_public_base64, "=", Base64.encode(bundle.identity_key.serialize()))
                .single().row().is_present());

        //Get trust information from the database if the device id is known
        Row device = db.identity_meta.get_device(identity_id, jid.bare_jid.to_string(), device_id);
        TrustLevel trusted = TrustLevel.UNKNOWN;
        if (device != null) {
            trusted = (TrustLevel) device[db.identity_meta.trust_level];
        }

        if(untrust) {
            trusted = TrustLevel.UNKNOWN;
        } else if (blind_trust && trusted == TrustLevel.UNKNOWN) {
            trusted = TrustLevel.TRUSTED;
        }

        //Update the database with the appropriate trust information
        db.identity_meta.insert_device_bundle(identity_id, jid.bare_jid.to_string(), device_id, bundle, trusted);

        if (should_start_session(account, jid)) {
            XmppStream? stream = stream_interactor.get_stream(account);
            if (stream != null) {
                StreamModule? module = ((!)stream).get_module<StreamModule>(StreamModule.IDENTITY);
                if (module != null) {
                    module.start_session(stream, jid, device_id, bundle);
                }
            }
        }
        continue_message_sending(account, jid);
    }

    /**
     * Handle OMEMO 2 bundle fetch results.
     * Uses the same session setup via libomemo-c Signal protocol.
     */
    private void on_bundle_v2_fetched(Account account, Jid jid, int32 device_id, Bundle2 bundle) {
        int identity_id = db.identity.get_id(account.id);
        if (identity_id < 0) return;

        ECPublicKey? identity_key = bundle.identity_key;
        if (identity_key == null) {
            debug("OMEMO 2: Bundle for %s/%d has no identity key", jid.to_string(), device_id);
            return;
        }

        bool blind_trust = db.trust.get_blind_trust(identity_id, jid.bare_jid.to_string(), true);

        bool untrust = !(blind_trust || db.identity_meta.with_address(identity_id, jid.bare_jid.to_string())
                .with(db.identity_meta.device_id, "=", device_id)
                .with(db.identity_meta.identity_key_public_base64, "=", Base64.encode(identity_key.serialize()))
                .single().row().is_present());

        Row device = db.identity_meta.get_device(identity_id, jid.bare_jid.to_string(), device_id);
        TrustLevel trusted = TrustLevel.UNKNOWN;
        if (device != null) {
            trusted = (TrustLevel) device[db.identity_meta.trust_level];
        }

        if (untrust) {
            trusted = TrustLevel.UNKNOWN;
        } else if (blind_trust && trusted == TrustLevel.UNKNOWN) {
            trusted = TrustLevel.TRUSTED;
        }

        /* Store identity key in database using insert_device_session */
        string identity_key_b64 = Base64.encode(identity_key.serialize());
        db.identity_meta.insert_device_session(identity_id, jid.bare_jid.to_string(), device_id, identity_key_b64, trusted);

        /* Always start session for OMEMO 2 bundles -- these may come from
         * OMEMO 2-only devices (e.g. Kaidan) that have no legacy bundle.
         * Without a proactive session, the legacy encryptor marks them as
         * 'lost' and messages are retracted as WONTSEND. */
        XmppStream? stream = stream_interactor.get_stream(account);
        if (stream != null) {
            StreamModule2? module2 = ((!)stream).get_module<StreamModule2>(StreamModule2.IDENTITY);
            if (module2 != null) {
                debug("OMEMO 2: Starting session with %s/%d from bundle", jid.to_string(), device_id);
                module2.start_session(stream, jid, device_id, bundle);
            }
        }
        continue_message_sending(account, jid);
    }

    private bool should_start_session(Account account, Jid jid) {
        lock (message_states) {
            foreach (Entities.Message msg in message_states.keys) {
                if (!msg.account.equals(account)) continue;
                if (account.bare_jid.equals(jid)) {
                    return true;
                }
                if (msg.counterpart != null) {
                    Gee.List<Jid> occupants = get_occupants(msg.counterpart.bare_jid, account);
                    if (msg.counterpart.equals_bare(jid) || occupants.contains(jid)) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    private void continue_message_sending(Account account, Jid jid) {
        //Get all messages waiting and determine if they can now be sent
        HashSet<Entities.Message> send_now = new HashSet<Entities.Message>();
        lock (message_states) {
            foreach (Entities.Message msg in message_states.keys) {
                if (!msg.account.equals(account)) continue;
                MessageState state = message_states[msg];

                if (account.bare_jid.equals(jid)) {
                    state.waiting_own_sessions--;
                } else if (msg.counterpart != null) {
                    Gee.List<Jid> occupants = get_occupants(msg.counterpart.bare_jid, account);
                    if (msg.counterpart.equals_bare(jid) || occupants.contains(jid)) {
                        state.waiting_other_sessions--;
                    }
                }
                if (state.should_retry_now()){
                    send_now.add(msg);
                    state.active_send_attempt = true;
                }
            }
        }
        foreach (Entities.Message msg in send_now) {
            if (msg.counterpart == null) continue;
            Entities.Conversation? conv = stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY).get_conversation((!)msg.counterpart, account);
            if (conv == null) continue;
            stream_interactor.get_module<MessageProcessor>(MessageProcessor.IDENTITY).send_xmpp_message(msg, (!)conv, true);
        }
    }

    private async void initialize_store(Account account) {
        // If the account is not yet persisted, wait for that and then continue - without identity.account_id the entry isn't worth much.
        if (account.id == -1) {
            account.notify["id"].connect(() => initialize_store.callback());
            yield;
        }
        StreamModule? module = stream_interactor.module_manager.get_module<StreamModule>(account, StreamModule.IDENTITY);
        if (module == null) return;
        Store store = module.store;
        Qlite.Row? row = db.identity.row_with(db.identity.account_id, account.id).inner;
        int identity_id = -1;
        bool publish_identity = false;

        if (row == null) {
            // OMEMO not yet initialized, starting with empty base
            publish_identity = true;
            try {
                store.identity_key_store.local_registration_id = Random.int_range(1, int32.MAX);

                ECKeyPair key_pair = Plugin.get_context().generate_key_pair();
                store.identity_key_store.identity_key_private = new Bytes(key_pair.private.serialize());
                store.identity_key_store.identity_key_public = new Bytes(key_pair.public.serialize());

                identity_id = (int) db.identity.upsert()
                        .value(db.identity.account_id, account.id, true)
                        .value(db.identity.device_id, (int) store.local_registration_id)
                        .value(db.identity.identity_key_private_base64, Base64.encode(store.identity_key_store.identity_key_private.get_data()))
                        .value(db.identity.identity_key_public_base64, Base64.encode(store.identity_key_store.identity_key_public.get_data()))
                        .perform();
            } catch (Error e) {
                // Ignore error
            }
        } else {
            store.identity_key_store.local_registration_id = ((!)row)[db.identity.device_id];
            store.identity_key_store.identity_key_private = new Bytes(Base64.decode(((!)row)[db.identity.identity_key_private_base64]));
            store.identity_key_store.identity_key_public = new Bytes(Base64.decode(((!)row)[db.identity.identity_key_public_base64]));
            identity_id = ((!)row)[db.identity.id];
        }

        if (identity_id >= 0) {
            store.signed_pre_key_store = new BackedSignedPreKeyStore(db, identity_id);
            store.pre_key_store = new BackedPreKeyStore(db, identity_id);
            store.session_store = new BackedSessionStore(db, identity_id);
        } else {
            warning("store for %s is not persisted!", account.bare_jid.to_string());
        }

        // Generated new device ID, ensure this gets added to the devicelist
        XmppStream? stream = stream_interactor.get_stream(account);
        if (stream != null) {
            module.request_user_devicelist.begin((!)stream, account.bare_jid);
            /* Also request OMEMO 2 device list */
            StreamModule2? module2 = stream_interactor.module_manager.get_module<StreamModule2>(account, StreamModule2.IDENTITY);
            if (module2 != null) {
                module2.request_user_devicelist.begin((!)stream, account.bare_jid);
            }
        }
    }

    public async bool ensure_get_keys_for_conversation(Conversation conversation) {
        if (stream_interactor.get_module<MucManager>(MucManager.IDENTITY).is_private_room(conversation.account, conversation.counterpart)) {
            foreach (Jid offline_member in stream_interactor.get_module<MucManager>(MucManager.IDENTITY).get_offline_members(conversation.counterpart, conversation.account)) {
                bool ok = yield ensure_get_keys_for_jid(conversation.account, offline_member);
                if (!ok) {
                    return false;
                }
            }
            return true;
        }

        return yield ensure_get_keys_for_jid(conversation.account, conversation.counterpart.bare_jid);
    }

    public async bool ensure_get_keys_for_jid(Account account, Jid jid) {
        if (trust_manager.is_known_address(account, jid)) return true;
        
        // Wait for stream to become available (up to 10 seconds)
        // On first start, the XMPP connection may still be establishing
        // when the chat window opens and checks OMEMO availability.
        XmppStream? stream = stream_interactor.get_stream(account);
        if (stream == null) {
            debug("OMEMO: Stream not ready for %s, waiting...", jid.to_string());
            for (int i = 0; i < 20; i++) {
                Timeout.add(500, () => {
                    ensure_get_keys_for_jid.callback();
                    return false;
                });
                yield;
                stream = stream_interactor.get_stream(account);
                if (stream != null) {
                    debug("OMEMO: Stream became available for %s after %d ms", jid.to_string(), (i + 1) * 500);
                    break;
                }
            }
        }
        
        if (stream != null) {
            var device_list = yield stream_interactor.module_manager.get_module<StreamModule>(account, StreamModule.IDENTITY).request_user_devicelist(stream, jid);
            /* Also try OMEMO 2 device list */
            StreamModule2? module2 = stream_interactor.module_manager.get_module<StreamModule2>(account, StreamModule2.IDENTITY);
            if (module2 != null) {
                var device_list_v2 = yield module2.request_user_devicelist(stream, jid);
                if (device_list_v2.size > 0 && device_list.size == 0) {
                    return true;
                }
            }
            return device_list.size > 0;
        }
        debug("OMEMO: Cannot verify keys for %s - no stream available after waiting", jid.to_string());
        return false;
    }

    public static void start(StreamInteractor stream_interactor, Database db, TrustManager trust_manager, HashMap<Account, OmemoEncryptor> encryptors, HashMap<Account, Omemo2Encrypt> encryptors_v2 = new HashMap<Account, Omemo2Encrypt>(Account.hash_func, Account.equals_func)) {
        Manager m = new Manager(stream_interactor, db, trust_manager, encryptors, encryptors_v2);
        stream_interactor.add_module(m);
    }
}

}
