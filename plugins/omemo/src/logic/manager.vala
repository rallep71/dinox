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
    /* Track JIDs that have announced OMEMO 1 (legacy) devices */
    private HashSet<string> v1_jids = new HashSet<string>();

    /* ── Bundle-Retry ──────────────────────────────────────────────
     * Wenn ein OMEMO-2-Bundle leer/kaputt vom Server kommt (z.B.
     * Kaidan publiziert <ik/> ohne Inhalt), wird das Gerät hier
     * eingetragen.  Alle BUNDLE_RETRY_INTERVAL_SEC Sekunden fragt
     * DinoX das Bundle erneut ab.  Nach BUNDLE_RETRY_MAX_ATTEMPTS
     * erfolglosen Versuchen wird das Gerät nicht mehr probiert.
     * Sobald ein gültiges Bundle eintrifft, wird der Eintrag
     * entfernt und die Session normal aufgebaut.
     * ─────────────────────────────────────────────────────────── */
    private const int BUNDLE_RETRY_INTERVAL_SEC = 10 * 60;   // 10 Minuten
    private const int BUNDLE_RETRY_MAX_ATTEMPTS = 5;

    private class BundleRetryEntry {
        public Account account;
        public Jid jid;
        public int32 device_id;
        public int attempts;
        public BundleRetryEntry(Account account, Jid jid, int32 device_id) {
            this.account = account;
            this.jid = jid;
            this.device_id = device_id;
            this.attempts = 0;
        }
        public string key() {
            return @"$(account.id):$(jid.bare_jid):$device_id";
        }
    }

    /* Map: "account_id:bare_jid:device_id" → BundleRetryEntry */
    private HashMap<string, BundleRetryEntry> bundle_retry_queue
        = new HashMap<string, BundleRetryEntry>();
    private uint bundle_retry_timer_id = 0;



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
            } else if (new_try.other_waiting_lists > 0 || !new_try.own_list || new_try.own_devices == 0) {
                // Still waiting for device lists — must block
                msg.marked = Entities.Message.Marked.UNSENT;
            } else if (new_try.other_unknown > 0 && new_try.other_success < 1) {
                // No counterpart device succeeded at all — block until bundle arrives
                msg.marked = Entities.Message.Marked.UNSENT;
            } else if (new_try.own_unknown > 0 && new_try.own_success < 1) {
                // No own device succeeded — block until own session established
                msg.marked = Entities.Message.Marked.UNSENT;
            } else if (!new_try.encrypted) {
                msg.marked = Entities.Message.Marked.WONTSEND;
            } else {
                // Send: at least 1 counterpart device OK, at least 1 own device OK.
                // Stale devices without sessions are skipped gracefully.
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
        stream_interactor.get_module<MucManager>(MucManager.IDENTITY).conference_removed.connect(on_conference_removed);

        // Proactively fetch OMEMO keys when a new member joins a private MUC
        // Without this, keys are only fetched on first message send → visible delay
        stream_interactor.get_module<MucManager>(MucManager.IDENTITY).private_room_occupant_updated.connect((account, room, occupant) => {
            on_private_room_occupant_updated.begin(account, room, occupant);
        });

        // When the user removes an own device via TrustManager, republish the device list
        trust_manager.own_device_removed.connect((account) => {
            XmppStream? stream = stream_interactor.get_stream(account);
            if (stream != null) {
                republish_device_list(account, stream);
                republish_device_list_v2(account, stream);
            }
        });
    }

    private async void on_private_room_occupant_updated(Account account, Jid room, Jid occupant) {
        // A new member joined or real JID was revealed in a private MUC.
        // Proactively fetch their OMEMO device list + bundles so encryption
        // is ready when the user sends a message (no delay).
        Jid? real_jid = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).get_real_jid(occupant, account);
        if (real_jid == null || real_jid.equals(account.bare_jid)) return;

        Jid bare = real_jid.bare_jid;
        if (trust_manager.is_known_address(account, bare)) return;

        XmppStream? stream = stream_interactor.get_stream(account);
        if (stream == null) return;

        debug("OMEMO: Proactively fetching keys for new MUC member %s in %s", bare.to_string(), room.bare_jid.to_string());
        StreamModule? module = stream.get_module<StreamModule>(StreamModule.IDENTITY);
        if (module != null) {
            yield module.request_user_devicelist(stream, bare);
        }
        StreamModule2? module2 = stream.get_module<StreamModule2>(StreamModule2.IDENTITY);
        if (module2 != null) {
            yield module2.request_user_devicelist(stream, bare);
        }
    }

    private void on_conversation_cleared(Conversation conversation) {
        /* When conversation history is cleared, only clear Signal sessions
         * (ratchet state).  Preserve identity_meta (known devices + keys)
         * and trust (user trust decisions).
         *
         * Rationale: Deleting the message history is NOT the same as
         * resetting the cryptographic relationship.  Wiping identity_meta
         * causes is_known_address() to return false, which triggers a
         * complex device-list-re-fetch → bundle-fetch → session-setup
         * retry dance that often fails (empty PEP result, timing issues,
         * contact offline) and leaves messages stuck in WONTSEND with
         * "contact doesn't support OMEMO".
         *
         * By keeping identity_meta, the next send attempt sees existing
         * devices, detects NO_SESSION, fetches bundles, builds sessions
         * and sends — the normal, well-tested code path. */
        int identity_id = db.identity.get_id(conversation.account.id);
        if (identity_id < 0) return;

        string address_name = conversation.counterpart.bare_jid.to_string();

        // Only clear Signal sessions — new ones will be established on next send
        db.session.delete()
                .with(db.session.identity_id, "=", identity_id)
                .with(db.session.address_name, "=", address_name)
                .perform();

        debug("OMEMO: Cleared sessions for %s (chat history deleted, device knowledge preserved)", address_name);

        // Proactively re-fetch bundles to rebuild sessions before user tries to send
        XmppStream? stream = stream_interactor.get_stream(conversation.account);
        if (stream != null) {
            StreamModule? module = ((!)stream).get_module<StreamModule>(StreamModule.IDENTITY);
            if (module != null) {
                module.fetch_bundles((!)stream, conversation.counterpart.bare_jid,
                    trust_manager.get_trusted_devices(conversation.account, conversation.counterpart.bare_jid));
            }
            StreamModule2? module2 = ((!)stream).get_module<StreamModule2>(StreamModule2.IDENTITY);
            if (module2 != null) {
                module2.fetch_bundles((!)stream, conversation.counterpart.bare_jid,
                    trust_manager.get_trusted_devices(conversation.account, conversation.counterpart.bare_jid));
            }
        }
    }

    private void on_conference_removed(Account account, Jid room_jid) {
        // When a MUC is destroyed/left, clean OMEMO data stored under the room JID.
        // Member keys (stored under real JIDs) are intentionally preserved.
        int identity_id = db.identity.get_id(account.id);
        if (identity_id < 0) return;

        string room_address = room_jid.bare_jid.to_string();

        db.identity_meta.delete()
                .with(db.identity_meta.identity_id, "=", identity_id)
                .with(db.identity_meta.address_name, "=", room_address)
                .perform();

        db.session.delete()
                .with(db.session.identity_id, "=", identity_id)
                .with(db.session.address_name, "=", room_address)
                .perform();

        db.trust.delete()
                .with(db.trust.identity_id, "=", identity_id)
                .with(db.trust.address_name, "=", room_address)
                .perform();

        debug("OMEMO: Cleaned data for removed MUC %s", room_address);
    }

    /**
     * Fully wipe all OMEMO data for a contact (identity_meta, sessions, trust).
     * Used for account removal and MUC cleanup.  NOT used for chat-clear
     * (see on_conversation_cleared which preserves device knowledge).
     */
    internal void clear_contact_data(Account account, Xmpp.Jid jid) {
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
        if(occupant_jids == null || occupant_jids.size == 0) {
            // Affiliations may not be loaded yet after (re)join — warn but continue
            // Encryptor will encrypt to self devices only in this case
            if (stream_interactor.get_module<MucManager>(MucManager.IDENTITY).is_groupchat(jid, account)) {
                warning("OMEMO: No offline members for MUC %s — affiliations may not be loaded yet", jid.to_string());
            }
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
                // Empty recipients is OK in MUC (solo room) — encryptor will encrypt to self-devices
            } else {
                recipients = new ArrayList<Jid>(Jid.equals_bare_func);
                recipients.add(message_stanza.to);
            }

            //Attempt to encrypt the message
            /* Use v2 encryptor ONLY if ALL recipients have v2 devices AND none
             * have v1-only devices. This ensures compatibility in MUCs where
             * some members may only support OMEMO v1 (Monal, Conversations).
             * A single v1-only member forces the entire message to use v1 format. */
            bool use_v2 = true;
            if (recipients.size == 0) {
                use_v2 = false;
            }
            foreach (Jid recipient in recipients) {
                string bare = recipient.bare_jid.to_string();
                if (!v2_jids.contains(bare) || v1_jids.contains(bare)) {
                    // This recipient has v1 devices or no v2 devices → must use v1
                    use_v2 = false;
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
                    lock (message_states) {
                        message_states.unset(message);
                    }
                } else {
                    debug("delaying message %s", state.to_string());

                    // Fetch bundles via both legacy and v2 modules
                    StreamModule2? module2_delay = ((!)stream).get_module<StreamModule2>(StreamModule2.IDENTITY);

                    if (state.waiting_own_sessions > 0) {
                        module.fetch_bundles((!)stream, conversation.account.bare_jid, trust_manager.get_trusted_devices(conversation.account, conversation.account.bare_jid));
                        if (use_v2 && module2_delay != null) {
                            module2_delay.fetch_bundles((!)stream, conversation.account.bare_jid, trust_manager.get_trusted_devices(conversation.account, conversation.account.bare_jid));
                        }
                    }
                    if (state.waiting_other_sessions > 0 && message.counterpart != null) {
                        foreach(Jid jid in get_occupants(((!)message.counterpart).bare_jid, conversation.account)) {
                            module.fetch_bundles((!)stream, jid, trust_manager.get_trusted_devices(conversation.account, jid));
                            if (use_v2 && module2_delay != null) {
                                module2_delay.fetch_bundles((!)stream, jid, trust_manager.get_trusted_devices(conversation.account, jid));
                            }
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
                // Clean stale devices, then republish clean device list
                cleanup_stale_own_devices(account, stream);
            });
        }
        /* Bundle-Retry-Timer starten (einmalig, läuft für alle Accounts) */
        start_bundle_retry_timer();

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

    /* ── Bundle-Retry-Timer ────────────────────────────────────────
     * Startet einen GLib.Timeout, der alle BUNDLE_RETRY_INTERVAL_SEC
     * Sekunden die Retry-Queue abarbeitet.  Wird nur einmal gestartet
     * und läuft, solange die Queue Einträge hat.
     * ───────────────────────────────────────────────────────────── */
    private void start_bundle_retry_timer() {
        if (bundle_retry_timer_id != 0) return;  // läuft bereits
        bundle_retry_timer_id = Timeout.add_seconds(BUNDLE_RETRY_INTERVAL_SEC, () => {
            process_bundle_retry_queue();
            if (bundle_retry_queue.size == 0) {
                debug("OMEMO 2: Bundle retry queue empty – timer stopped");
                bundle_retry_timer_id = 0;
                return false;  // Timer beenden
            }
            return true;  // weiter laufen lassen
        });
        debug("OMEMO 2: Bundle retry timer started (%d sec interval)", BUNDLE_RETRY_INTERVAL_SEC);
    }

    /* Alle Einträge in der Retry-Queue durchgehen und Bundle erneut
     * vom Server abfragen.  Einträge mit zu vielen Versuchen werden
     * entfernt und das Gerät ignoriert. */
    private void process_bundle_retry_queue() {
        if (bundle_retry_queue.size == 0) return;

        var to_remove = new ArrayList<string>();

        foreach (var entry in bundle_retry_queue.entries) {
            BundleRetryEntry r = entry.value;
            r.attempts++;

            if (r.attempts > BUNDLE_RETRY_MAX_ATTEMPTS) {
                debug("OMEMO 2: Giving up on bundle for %s/%d after %d attempts",
                      r.jid.to_string(), r.device_id, BUNDLE_RETRY_MAX_ATTEMPTS);
                to_remove.add(entry.key);
                continue;
            }

            XmppStream? stream = stream_interactor.get_stream(r.account);
            if (stream == null) continue;

            StreamModule2? module2 = stream.get_module<StreamModule2>(StreamModule2.IDENTITY);
            if (module2 == null) continue;

            debug("OMEMO 2: Retry bundle fetch for %s/%d (attempt %d/%d)",
                  r.jid.to_string(), r.device_id, r.attempts, BUNDLE_RETRY_MAX_ATTEMPTS);
            module2.fetch_bundle(stream, r.jid, r.device_id, false);
        }

        foreach (string key in to_remove) {
            bundle_retry_queue.unset(key);
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
            var device_node = new StanzaNode.build("device", Xep.Omemo.NS_URI)
                .put_attribute("id", device_id.to_string());
            // Add label for own device
            if (device_id == current_device_id && module.own_device_label != null && module.own_device_label.length > 0) {
                device_node.put_attribute("label", module.own_device_label);
            }
            list_node.put_node(device_node);
        }

        // Publish to trigger PEP notification to all subscribers
        // NODE_DEVICELIST = "eu.siacs.conversations.axolotl.devicelist"
        // Use fixed item_id "current" to REPLACE existing item (not create a new one)
        stream.get_module<Xep.Pubsub.Module>(Xep.Pubsub.Module.IDENTITY).publish.begin(stream, account.bare_jid, 
            Xep.Omemo.NS_URI + ".devicelist", "current", list_node);
        
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
            var device_node = new StanzaNode.build("device", Xep.Omemo.NS_URI_V2)
                .put_attribute("id", device_id.to_string());
            // Add label for own device
            if (device_id == current_device_id && module2.own_device_label != null && module2.own_device_label.length > 0) {
                device_node.put_attribute("label", module2.own_device_label);
            }
            devices_node.put_node(device_node);
        }

        // Use fixed item_id "current" to REPLACE existing item (not create a new one)
        stream.get_module<Xep.Pubsub.Module>(Xep.Pubsub.Module.IDENTITY).publish.begin(stream, account.bare_jid,
            Xep.Omemo.NODE_DEVICELIST_V2, "current", devices_node);

        debug("Republished OMEMO 2 device list for %s with %d devices", account.bare_jid.to_string(), devices.size);
    }

    /**
     * Entfernt veraltete eigene Geräte aus der Device-List (v1+v2) und der lokalen DB.
     * Wird nach dem Laden der Device-List beim Connect aufgerufen.
     *
     * Ablauf:
     * 1. Alle eigenen Geräte in identity_meta, die NICHT das aktuelle Gerät sind,
     *    werden als now_active=false markiert.
     * 2. Die bereinigte Device-List wird auf dem Server veröffentlicht (v1 + v2).
     * 3. Veraltete v1-Bundle-Nodes werden vom PubSub gelöscht.
     * 4. Veraltete v2-Bundle-Items werden vom PubSub zurückgezogen.
     */
    private string[] device_list_to_strings(ArrayList<int32> devices) {
        string[] result = new string[devices.size];
        for (int i = 0; i < devices.size; i++) {
            result[i] = devices[i].to_string();
        }
        return result;
    }

    private void cleanup_stale_own_devices(Account account, XmppStream stream) {
        int identity_id = db.identity.get_id(account.id);
        if (identity_id < 0) return;

        StreamModule? module = stream.get_module<StreamModule>(StreamModule.IDENTITY);
        if (module == null) return;
        int32 own_device_id = (int32) module.store.local_registration_id;
        if (own_device_id == 0) return;

        string own_jid = account.bare_jid.to_string();

        // Only remove TRUE phantom devices: those without an identity key.
        // Devices WITH an identity key are legitimate other clients (e.g. Monal,
        // Conversations) using the same JID — they must NOT be removed.
        debug("OMEMO cleanup: own_device_id=%d, checking active devices for %s", own_device_id, own_jid);
        var stale_devices = new ArrayList<int32>();
        int kept_count = 0;
        foreach (Row row in db.identity_meta.with_address(identity_id, own_jid)
                .with(db.identity_meta.device_id, "!=", own_device_id)
                .with(db.identity_meta.now_active, "=", true)) {
            int32 dev_id = row[db.identity_meta.device_id];
            string? pub_key = row[db.identity_meta.identity_key_public_base64];
            if (pub_key == null || pub_key.length == 0) {
                // Phantom device: appeared in device list but never had a bundle fetched
                debug("OMEMO cleanup: device %d → PHANTOM (no identity key) → will remove", dev_id);
                stale_devices.add(dev_id);
            } else {
                debug("OMEMO cleanup: device %d → KEPT (has identity key)", dev_id);
                kept_count++;
            }
        }

        if (stale_devices.size == 0) {
            // No phantom devices, just republish (ensures our device is in the list)
            debug("OMEMO cleanup: no phantoms found, %d other devices kept, republishing", kept_count);
            republish_device_list_with_retry(account, stream, 5);
            return;
        }

        debug("OMEMO: Cleaning %d stale phantom devices for %s (no identity key)", stale_devices.size, own_jid);

        // Deactivate only phantom devices (no identity key)
        foreach (int32 stale_id in stale_devices) {
            db.identity_meta.update()
                .with(db.identity_meta.identity_id, "=", identity_id)
                .with(db.identity_meta.address_name, "=", own_jid)
                .with(db.identity_meta.device_id, "=", stale_id)
                .set(db.identity_meta.now_active, false)
                .perform();
        }

        // Bereinigte Device-List veröffentlichen (enthält nur noch unser Gerät)
        republish_device_list(account, stream);

        // Delete then republish v2 devicelist node to clear accumulated old items
        // (v2 node may have max_items=max, causing stale device lists to persist)
        var pubsub = stream.get_module<Xep.Pubsub.Module>(Xep.Pubsub.Module.IDENTITY);
        if (pubsub != null) {
            debug("OMEMO: Deleting v2 devicelist node to clear stale items");
            pubsub.delete_node(stream, account.bare_jid, Xep.Omemo.NODE_DEVICELIST_V2);
        }
        republish_device_list_v2(account, stream);

        // Veraltete v1-Bundle-Nodes löschen
        if (pubsub != null) {
            foreach (int32 stale_id in stale_devices) {
                string v1_bundle_node = NODE_BUNDLES + ":" + stale_id.to_string();
                debug("OMEMO: Deleting stale v1 bundle node %s", v1_bundle_node);
                pubsub.delete_node(stream, account.bare_jid, v1_bundle_node);

                // v2-Bundle-Item zurückziehen
                debug("OMEMO: Retracting stale v2 bundle item %d", stale_id);
                pubsub.retract_item.begin(stream, account.bare_jid, NODE_BUNDLES_V2, stale_id.to_string());
            }
        }

        debug("OMEMO: Stale phantom device cleanup done for %s — removed %d devices", own_jid, stale_devices.size);
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
        // Filter out non-user JIDs (PubSub services, MUC room JIDs, server components)
        string bare_str = jid.bare_jid.to_string();
        if (!bare_str.contains("@") || stream_interactor.get_module<MucManager>(MucManager.IDENTITY).is_groupchat(jid.bare_jid, account)) {
            debug("OMEMO: Ignoring device list from non-user JID %s", bare_str);
            return;
        }
        debug("received device list for %s from %s", account.bare_jid.to_string(), jid.to_string());

        /* Track JIDs with v1 (legacy) device list */
        if (device_list.size > 0) {
            v1_jids.add(jid.bare_jid.to_string());
            debug("OMEMO 1: Marked %s as v1-capable (%d devices)", jid.bare_jid.to_string(), device_list.size);
        }

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

        /* Multi-Device-sicher: Device-Listen vom Server werden
         * unveraendert uebernommen. Echte Geraete (Handy, Tablet)
         * behalten ihre Device-IDs. Stale Devices blockieren das
         * Senden nicht (Toleranz-Fix in update_from_encrypt_status:
         * own_unknown > 0 blockiert nur wenn own_success < 1).
         * cleanup_stale_own_devices() raeumt nur wirklich tote
         * Geraete auf (kein Identity Key = nie ein Bundle gesehen). */
        if (jid.equals_bare(account.bare_jid)) {
            debug("OMEMO device_list_loaded: OWN JID %s — server sent %d devices: %s",
                  jid.to_string(), device_list.size,
                  string.joinv(", ", device_list_to_strings(device_list)));
        }
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

        /* Also fetch v2 bundles for known devices without a session,
         * but ONLY for v2-only JIDs.  For JIDs with v1 devices we use the
         * v1 encryptor, and a v4 session in the shared store would produce
         * messages with a broken version byte (SG_ERR_LEGACY_MESSAGE). */
        string dl_bare = jid.bare_jid.to_string();
        if (module2 != null && !v1_jids.contains(dl_bare)) {
            int v2_inc = 0;
            foreach (int32 device_id in device_list) {
                Address address = new Address(dl_bare, device_id);
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
                debug("v2 session-less bundles %i/%i for %s", v2_inc, device_list.size, dl_bare);
            }
        }

        //Create an entry for the jid in the account table if one does not exist already
        if (db.trust.select().with(db.trust.identity_id, "=", identity_id).with(db.trust.address_name, "=", jid.bare_jid.to_string()).count() == 0) {
            db.trust.insert().value(db.trust.identity_id, identity_id).value(db.trust.address_name, jid.bare_jid.to_string()).value(db.trust.blind_trust, true).perform();
        }

        //Get all messages that needed the devicelist and determine if we can now send them
        HashSet<Entities.Message> send_now = new HashSet<Entities.Message>();
        lock (message_states) {
            foreach (var entry in message_states.entries) {
                Entities.Message msg = entry.key;
                if (!msg.account.equals(account)) continue;
                MessageState state = entry.value;
                if (state == null) continue;
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

        // Filter out non-user JIDs (PubSub services, MUC room JIDs, server components)
        string bare_str = jid.bare_jid.to_string();
        if (!bare_str.contains("@") || stream_interactor.get_module<MucManager>(MucManager.IDENTITY).is_groupchat(jid.bare_jid, account)) {
            debug("OMEMO 2: Ignoring v2 device list from non-user JID %s", bare_str);
            return;
        }

        debug("OMEMO 2: received v2 device list for %s (%d devices)", jid.to_string(), device_list.size);

        XmppStream? stream = stream_interactor.get_stream(account);
        if (stream == null) return;

        int identity_id = db.identity.get_id(account.id);
        if (identity_id < 0) return;

        /* Multi-Device-sicher: v2-Device-Listen unveraendert uebernehmen. */

        // Additively add v2 devices (don't deactivate existing v1 devices)
        db.identity_meta.insert_device_list_additive(identity_id, jid.bare_jid.to_string(), device_list);

        // Create trust entry if needed
        if (db.trust.select().with(db.trust.identity_id, "=", identity_id).with(db.trust.address_name, "=", jid.bare_jid.to_string()).count() == 0) {
            db.trust.insert().value(db.trust.identity_id, identity_id).value(db.trust.address_name, jid.bare_jid.to_string()).value(db.trust.blind_trust, true).perform();
        }

        // Clean phantom devices from v2 device list for own JID.
        // The v1 cleanup runs before v2 list processing, so phantoms
        // re-created by insert_device_list_additive need a second pass.
        if (jid.equals_bare(account.bare_jid)) {
            debug("OMEMO 2: own v2 device list loaded — running phantom cleanup");
            cleanup_stale_own_devices(account, stream);
        }

        // Fetch v2 bundles only for ACTIVE devices without a session,
        // and ONLY for v2-only JIDs.  For JIDs with v1 devices we use
        // the v1 encryptor, and a v4 session in the shared store would
        // conflict (SG_ERR_LEGACY_MESSAGE).  Mirrors the guard in
        // on_device_list_loaded() and on_bundle_v2_fetched().
        string dl_v2_bare = jid.bare_jid.to_string();
        StreamModule2? module2 = stream.get_module<StreamModule2>(StreamModule2.IDENTITY);
        if (module2 != null && !v1_jids.contains(dl_v2_bare)) {
            foreach (Row row in db.identity_meta.with_address(identity_id, jid.bare_jid.to_string())
                    .with(db.identity_meta.now_active, "=", true)) {
                int32 device_id = row[db.identity_meta.device_id];
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

        /* Always call start_session — not just when a message is pending.
         * start_session() checks contains_session() internally and is a
         * no-op when a valid v3 session already exists.  But if a stale
         * v4 session is present (race: v2 bundle arrived before v1 device
         * list), start_session() replaces it with a proper v3 session.
         * Without this, the v4 session survives until the user sends a
         * message, at which point the v1 encryptor has to delete + retry,
         * causing unnecessary warnings and a round-trip delay. */
        {
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
            /* Bundle ist leer/kaputt – für periodischen Retry vormerken.
             * Typisch für Kaidan u.a., die manchmal <ik/> ohne Inhalt
             * publizieren.  Beim nächsten Retry-Zyklus wird das Bundle
             * erneut abgefragt; repariert der Kontakt sein Bundle
             * zwischenzeitlich, klappt der Session-Aufbau automatisch. */
            var entry = new BundleRetryEntry(account, jid, device_id);
            string key = entry.key();
            if (!bundle_retry_queue.has_key(key)) {
                bundle_retry_queue[key] = entry;
                debug("OMEMO 2: Bundle for %s/%d has no identity key – queued for retry",
                      jid.to_string(), device_id);
            } else {
                debug("OMEMO 2: Bundle for %s/%d still broken (attempt %d)",
                      jid.to_string(), device_id,
                      bundle_retry_queue[key].attempts);
            }

            /* Gerät auch im v2-Modul als ignored markieren, damit der
             * Encryptor es als 'lost' statt 'unknown' zählt.  Sonst
             * blockiert ein einzelnes kaputtes Gerät ALLE Nachrichten
             * an den Kontakt, obwohl andere Geräte erreichbar sind. */
            XmppStream? ign_stream = stream_interactor.get_stream(account);
            if (ign_stream != null) {
                StreamModule2? m2 = ign_stream.get_module<StreamModule2>(StreamModule2.IDENTITY);
                if (m2 != null) {
                    m2.ignore_device(jid, device_id);
                    debug("OMEMO 2: Ignoring device %s/%d (broken bundle)",
                          jid.to_string(), device_id);
                }
            }
            continue_message_sending(account, jid);
            return;
        }

        /* Gültiges Bundle erhalten → aus Retry-Queue entfernen, falls vorhanden */
        string ok_key = @"$(account.id):$(jid.bare_jid):$device_id";
        if (bundle_retry_queue.has_key(ok_key)) {
            debug("OMEMO 2: Bundle for %s/%d now valid – removed from retry queue",
                  jid.to_string(), device_id);
            bundle_retry_queue.unset(ok_key);
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

        /* Start v2 session ONLY for v2-only JIDs (no v1 devices).
         * If the JID has v1 devices we use the v1 encryptor, and a v4 session
         * in the shared store would produce messages with a broken version
         * byte that v1 decryptors reject as SG_ERR_LEGACY_MESSAGE. */
        string v2_bare = jid.bare_jid.to_string();
        if (!v1_jids.contains(v2_bare)) {
            XmppStream? stream = stream_interactor.get_stream(account);
            if (stream != null) {
                StreamModule2? module2 = ((!)stream).get_module<StreamModule2>(StreamModule2.IDENTITY);
                if (module2 != null) {
                    debug("OMEMO 2: Starting session with %s/%d from bundle (v2-only JID)", jid.to_string(), device_id);
                    module2.start_session(stream, jid, device_id, bundle);
                }
            }
        } else {
            debug("OMEMO 2: Skipping v2 session for %s/%d (JID has v1 devices, would conflict with v1 encryptor)", jid.to_string(), device_id);
        }
        continue_message_sending(account, jid);
    }

    private void continue_message_sending(Account account, Jid jid) {
        //Get all messages waiting and determine if they can now be sent
        HashSet<Entities.Message> send_now = new HashSet<Entities.Message>();
        lock (message_states) {
            foreach (var entry in message_states.entries) {
                Entities.Message msg = entry.key;
                if (!msg.account.equals(account)) continue;
                MessageState state = entry.value;
                if (state == null) continue;

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
            // Load own device label from DB and set it on both modules
            load_own_device_label(account, module);

            module.request_user_devicelist.begin((!)stream, account.bare_jid);
            /* Also request OMEMO 2 device list */
            StreamModule2? module2 = stream_interactor.module_manager.get_module<StreamModule2>(account, StreamModule2.IDENTITY);
            if (module2 != null) {
                load_own_device_label_v2(account, module2);
                module2.request_user_devicelist.begin((!)stream, account.bare_jid);
            }
        }
    }

    private void load_own_device_label(Account account, StreamModule module) {
        int identity_id = db.identity.get_id(account.id);
        if (identity_id < 0) return;
        int32 device_id = (int32) module.store.local_registration_id;
        Row? meta = db.identity_meta.get_device(identity_id, account.bare_jid.to_string(), device_id);
        if (meta != null) {
            module.own_device_label = meta[db.identity_meta.device_label];
        }
    }

    private void load_own_device_label_v2(Account account, StreamModule2 module2) {
        int identity_id = db.identity.get_id(account.id);
        if (identity_id < 0) return;
        int32 device_id = (int32) module2.store.local_registration_id;
        Row? meta = db.identity_meta.get_device(identity_id, account.bare_jid.to_string(), device_id);
        if (meta != null) {
            module2.own_device_label = meta[db.identity_meta.device_label];
        }
    }

    /** Set own device label, store in DB, and republish device lists (v1 + v2) */
    public void set_own_device_label(Account account, string label) {
        int identity_id = db.identity.get_id(account.id);
        if (identity_id < 0) return;

        StreamModule? module = stream_interactor.module_manager.get_module<StreamModule>(account, StreamModule.IDENTITY);
        if (module == null) return;
        int32 device_id = (int32) module.store.local_registration_id;

        // Store in DB
        db.identity_meta.update_device_label(identity_id, account.bare_jid.to_string(), device_id, label);
        debug("Stored own device label '%s' for %s/%d", label, account.bare_jid.to_string(), device_id);

        // Set on modules
        module.own_device_label = label;
        StreamModule2? module2 = stream_interactor.module_manager.get_module<StreamModule2>(account, StreamModule2.IDENTITY);
        if (module2 != null) {
            module2.own_device_label = label;
        }

        // Republish device lists with label
        XmppStream? stream = stream_interactor.get_stream(account);
        if (stream != null) {
            republish_device_list(account, stream);
            republish_device_list_v2(account, stream);
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
            // Try up to 8 times (4 seconds) to get device list.
            // Bot accounts may still be publishing their device list via PubSub
            // when we first check, causing a false "does not support OMEMO".
            for (int attempt = 0; attempt < 8; attempt++) {
                // Check DB first (PEP notification may have arrived)
                if (trust_manager.is_known_address(account, jid)) return true;

                var device_list = yield stream_interactor.module_manager.get_module<StreamModule>(account, StreamModule.IDENTITY).request_user_devicelist(stream, jid);
                /* Also try OMEMO 2 device list */
                StreamModule2? module2 = stream_interactor.module_manager.get_module<StreamModule2>(account, StreamModule2.IDENTITY);
                if (module2 != null) {
                    var device_list_v2 = yield module2.request_user_devicelist(stream, jid);
                    if (device_list_v2.size > 0 && device_list.size == 0) {
                        return true;
                    }
                }
                if (device_list.size > 0) return true;

                // No devices yet — wait 500ms and retry
                if (attempt < 7) {
                    debug("OMEMO: No devices for %s yet (attempt %d/8), retrying...", jid.to_string(), attempt + 1);
                    Timeout.add(500, ensure_get_keys_for_jid.callback);
                    yield;
                }
            }
            debug("OMEMO: No devices found for %s after retries", jid.to_string());
            return false;
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
