using Gee;
using Xmpp;
using Xmpp.Xep;

namespace Dino.Plugins.BotFeatures {

/**
 * OMEMO encryption manager for dedicated bot streams.
 *
 * Uses the OMEMO plugin's Context/Store/StreamModule infrastructure directly.
 * Each bot gets its own Signal Protocol identity with in-memory key stores.
 * Identity key + registration_id are persisted in bot_registry.db settings.
 * All device identities are auto-trusted (no manual key verification).
 */
public class BotOmemoManager : Object {

    private const string OMEMO_NS = "eu.siacs.conversations.axolotl";
    private const uint AES_KEY_SIZE = 16;
    private const uint AES_IV_SIZE = 12;
    private const uint AES_TAG_SIZE = 16;
    private const int NUM_PRE_KEYS = 100;

    private BotRegistry registry;

    // Per-bot state
    private HashMap<int, global::Omemo.Store> stores = new HashMap<int, global::Omemo.Store>();
    private HashMap<int, Dino.Plugins.Omemo.StreamModule> stream_modules = new HashMap<int, Dino.Plugins.Omemo.StreamModule>();

    public BotOmemoManager(BotRegistry registry) {
        this.registry = registry;
    }

    // ---------------------------------------------------------------
    // Initialization
    // ---------------------------------------------------------------

    /**
     * Create an OMEMO Store for a bot, generating or loading its identity.
     * Must be called before the bot stream connects.
     */
    public bool init_bot(int bot_id) {
        if (stores.has_key(bot_id)) return true;

        if (!Dino.Plugins.Omemo.Plugin.ensure_context()) {
            warning("BotOmemo: OMEMO context init failed");
            return false;
        }
        global::Omemo.Context ctx = Dino.Plugins.Omemo.Plugin.get_context();
        global::Omemo.Store store = ctx.create_store();

        // Try loading persisted identity
        string? pub_b64 = registry.get_setting("omemo_ik_pub:%d".printf(bot_id));
        string? priv_b64 = registry.get_setting("omemo_ik_priv:%d".printf(bot_id));
        string? reg_str = registry.get_setting("omemo_reg_id:%d".printf(bot_id));

        if (pub_b64 != null && pub_b64.length > 0
            && priv_b64 != null && priv_b64.length > 0
            && reg_str != null && reg_str.length > 0) {
            // Existing identity
            store.identity_key_store.identity_key_public =
                new Bytes(Base64.decode(pub_b64));
            store.identity_key_store.identity_key_private =
                new Bytes(Base64.decode(priv_b64));
            store.identity_key_store.local_registration_id =
                (uint32) int64.parse(reg_str);
            message("BotOmemo: Loaded identity for bot %d (device_id=%u)",
                bot_id, store.local_registration_id);
        } else {
            // Generate fresh identity
            try {
                global::Omemo.ECKeyPair kp = ctx.generate_key_pair();
                store.identity_key_store.identity_key_public =
                    new Bytes(kp.public.serialize());
                store.identity_key_store.identity_key_private =
                    new Bytes(kp.private.serialize());

                // Registration id 1-16380
                uint8[] rb = new uint8[4];
                ctx.randomize(rb);
                uint32 reg_id = (((uint32) rb[0] << 8) | (uint32) rb[1]) % 16380 + 1;
                store.identity_key_store.local_registration_id = reg_id;

                // Persist
                registry.set_setting("omemo_ik_pub:%d".printf(bot_id),
                    Base64.encode(store.identity_key_store.identity_key_public.get_data()));
                registry.set_setting("omemo_ik_priv:%d".printf(bot_id),
                    Base64.encode(store.identity_key_store.identity_key_private.get_data()));
                registry.set_setting("omemo_reg_id:%d".printf(bot_id),
                    reg_id.to_string());
                message("BotOmemo: Generated identity for bot %d (device_id=%u)",
                    bot_id, reg_id);
            } catch (Error e) {
                warning("BotOmemo: Key generation failed for bot %d: %s",
                    bot_id, e.message);
                return false;
            }
        }

        // ---- Signed pre-key and pre-keys (persistent across restarts) ----
        if (!load_persisted_prekeys(bot_id, ctx, store)) {
            if (!generate_and_persist_prekeys(bot_id, ctx, store)) {
                return false;
            }
        }

        // Load persisted Signal sessions (ratchet state survives restart)
        load_persisted_sessions(bot_id, store);

        // Auto-persist session changes during runtime (ratchet advances)
        store.session_store.session_stored.connect((session) => {
            persist_session(bot_id, session);
        });

        stores[bot_id] = store;
        message("BotOmemo: Bot %d initialised (%d pre-keys)", bot_id, NUM_PRE_KEYS);
        return true;
    }

    /**
     * Create the StreamModule for a bot.  The caller must add the returned
     * module (and a fresh Pubsub.Module) to the bot stream's module list
     * BEFORE connecting.
     */
    public Dino.Plugins.Omemo.StreamModule? create_stream_module(int bot_id) {
        var store = stores[bot_id];
        if (store == null) return null;

        var module = new Dino.Plugins.Omemo.StreamModule(store);
        stream_modules[bot_id] = module;
        return module;
    }

    /**
     * Wire up signal handlers on the stream.  Call this AFTER the
     * XmppStream object exists but BEFORE loop() starts processing.
     */
    public void wire_signals(int bot_id, XmppStream stream) {
        var module = stream_modules[bot_id];
        if (module == null) return;

        // Auto-start sessions when bundles arrive
        module.bundle_fetched.connect((jid, device_id, bundle) => {
            bool ok = module.start_session(stream, jid, device_id, bundle);
            message("BotOmemo: Bot %d session for %s/%d %s",
                bot_id, jid.to_string(), device_id,
                ok ? "started" : "skipped (existing)");
        });

        module.device_list_loaded.connect((jid, devices) => {
            message("BotOmemo: Bot %d device list for %s (%d devices)",
                bot_id, jid.to_string(), devices.size);
        });
    }

    // ---------------------------------------------------------------
    // Encryption
    // ---------------------------------------------------------------

    /**
     * Encrypt body and send it from the bot stream to to_jid.
     * Fetches device list + bundles if sessions are missing (async).
     * Returns true if the message was encrypted and sent.
     */
    public async bool encrypt_and_send(int bot_id, XmppStream stream,
                                        Jid to_jid, string body) {
        var store = stores[bot_id];
        var module = stream_modules[bot_id];
        if (store == null || module == null) return false;

        if (!Dino.Plugins.Omemo.Plugin.ensure_context()) return false;
        var ctx = Dino.Plugins.Omemo.Plugin.get_context();

        try {
            // 1 — Recipient device list
            ArrayList<int32> devices =
                yield module.request_user_devicelist(stream, to_jid);
            if (devices.size == 0) {
                warning("BotOmemo: No devices for %s — cannot encrypt",
                    to_jid.to_string());
                return false;
            }

            // 2 — Ensure Signal sessions exist
            yield ensure_sessions(bot_id, stream, to_jid, devices);

            // 3 — AES-GCM encrypt the plaintext
            uint8[] key = new uint8[AES_KEY_SIZE];
            ctx.randomize(key);
            uint8[] iv = new uint8[AES_IV_SIZE];
            ctx.randomize(iv);

            uint8[] aes_out = global::Omemo.aes_encrypt(global::Omemo.Cipher.AES_GCM_NOPADDING,
                                          key, iv, body.data);
            // aes_out = ciphertext || 16-byte GCM tag
            uint8[] ciphertext = aes_out[0 : aes_out.length - AES_TAG_SIZE];
            uint8[] tag = aes_out[aes_out.length - AES_TAG_SIZE : aes_out.length];

            // keytag = key || tag  (32 bytes)
            uint8[] keytag = new uint8[AES_KEY_SIZE + AES_TAG_SIZE];
            Memory.copy(keytag, key, AES_KEY_SIZE);
            Memory.copy((uint8*) keytag + AES_KEY_SIZE, tag, AES_TAG_SIZE);

            // Build OMEMO EncryptionData
            var enc = new Xep.Omemo.EncryptionData(store.local_registration_id);
            enc.ciphertext = ciphertext;
            enc.keytag = keytag;
            enc.iv = iv;

            // 4 — Encrypt keytag for each recipient device
            int ok = 0;
            foreach (int32 did in devices) {
                global::Omemo.Address addr = new global::Omemo.Address(to_jid.bare_jid.to_string(), did);
                try {
                    if (store.contains_session(addr)) {
                        global::Omemo.SessionCipher cipher = store.create_session_cipher(addr);
                        global::Omemo.CiphertextMessage ek = cipher.encrypt(keytag);
                        enc.add_device_key(did, ek.serialized,
                            ek.type == global::Omemo.CiphertextType.PREKEY);
                        ok++;
                    }
                } catch (Error e) {
                    warning("BotOmemo: encrypt_key %s/%d: %s",
                        to_jid.to_string(), did, e.message);
                }
                addr.device_id = 0; // prevent premature free
            }

            if (ok == 0) {
                warning("BotOmemo: No sessions for any device of %s",
                    to_jid.to_string());
                return false;
            }

            // 5 — Build and send message stanza
            var msg = new Xmpp.MessageStanza();
            msg.to = to_jid;
            msg.type_ = Xmpp.MessageStanza.TYPE_CHAT;
            msg.body = "[This message is OMEMO encrypted]";
            msg.stanza.put_node(enc.get_encrypted_node());
            Xep.ExplicitEncryption.add_encryption_tag_to_message(
                msg, OMEMO_NS, "OMEMO");

            stream.get_module<Xmpp.MessageModule>(Xmpp.MessageModule.IDENTITY)
                .send_message.begin(stream, msg);

            message("BotOmemo: Bot %d sent OMEMO to %s (%d/%d devices)",
                bot_id, to_jid.to_string(), ok, devices.size);
            return true;
        } catch (Error e) {
            warning("BotOmemo: encrypt_and_send bot %d: %s",
                bot_id, e.message);
            return false;
        }
    }

    /** Block until Signal sessions exist for all devices (max 5 s). */
    private async void ensure_sessions(int bot_id, XmppStream stream,
                                        Jid jid, ArrayList<int32> devices) {
        var store = stores[bot_id];
        var module = stream_modules[bot_id];
        if (store == null || module == null) return;

        bool any_missing = false;
        foreach (int32 did in devices) {
            global::Omemo.Address addr = new global::Omemo.Address(jid.bare_jid.to_string(), did);
            try {
                if (!store.contains_session(addr)) {
                    module.fetch_bundle(stream, jid, did, false);
                    any_missing = true;
                }
            } catch (Error e) {
                any_missing = true;
            }
            addr.device_id = 0;
        }
        if (!any_missing) return;

        // Poll for sessions — up to 50 * 100 ms = 5 seconds
        for (int i = 0; i < 50; i++) {
            Timeout.add(100, ensure_sessions.callback);
            yield;

            bool all_ok = true;
            foreach (int32 did in devices) {
                global::Omemo.Address addr = new global::Omemo.Address(jid.bare_jid.to_string(), did);
                try {
                    if (!store.contains_session(addr)) all_ok = false;
                } catch (Error e) { all_ok = false; }
                addr.device_id = 0;
            }
            if (all_ok) break;
        }
    }

    // ---------------------------------------------------------------
    // Decryption
    // ---------------------------------------------------------------

    /**
     * Try to OMEMO-decrypt a message stanza received by a bot.
     * Returns the plaintext, or null if it cannot be decrypted or
     * the stanza does not carry OMEMO encryption.
     */
    public string? decrypt_message(int bot_id, Xmpp.MessageStanza stanza) {
        var store = stores[bot_id];
        if (store == null) return null;

        StanzaNode? encrypted_node =
            stanza.stanza.get_subnode("encrypted", OMEMO_NS);
        if (encrypted_node == null) return null;

        if (!Dino.Plugins.Omemo.Plugin.ensure_context()) return null;
        var ctx = Dino.Plugins.Omemo.Plugin.get_context();

        // --- Parse header ---
        StanzaNode? header = encrypted_node.get_subnode("header");
        if (header == null) return null;

        int sid = header.get_attribute_int("sid", -1);
        if (sid == -1) return null;

        string? iv_str = header.get_deep_string_content("iv");
        if (iv_str == null) return null;
        uint8[] iv = Base64.decode(iv_str);

        string? payload_str =
            encrypted_node.get_deep_string_content("payload");
        uint8[]? ciphertext = null;
        if (payload_str != null) ciphertext = Base64.decode(payload_str);

        // --- Find our device's key ---
        uint32 own_did = store.local_registration_id;
        foreach (StanzaNode key_node in header.get_subnodes("key")) {
            if (key_node.get_attribute_int("rid") != (int) own_did) continue;

            string? key_b64 = key_node.get_string_content();
            if (key_b64 == null) continue;

            uint8[] encrypted_key = Base64.decode(key_b64);
            bool is_prekey = key_node.get_attribute_bool("prekey");

            Jid? from_jid = stanza.from;
            if (from_jid == null) continue;

            try {
                global::Omemo.Address addr = new global::Omemo.Address(
                    from_jid.bare_jid.to_string(), sid);
                uint8[] key;

                if (is_prekey) {
                    global::Omemo.PreKeyOmemoMessage msg =
                        ctx.deserialize_signal_pre_key_message(encrypted_key);
                    global::Omemo.SessionCipher cipher = store.create_session_cipher(addr);
                    key = cipher.decrypt_pre_key_message(msg);
                } else {
                    global::Omemo.OmemoMessage msg =
                        ctx.deserialize_signal_message(encrypted_key);
                    global::Omemo.SessionCipher cipher = store.create_session_cipher(addr);
                    key = cipher.decrypt_message(msg);
                }
                addr.device_id = 0;

                // Handle extended keytag format (key.length > 16)
                if (key.length >= 32 && ciphertext != null) {
                    int auth_len = key.length - 16;
                    uint8[] combined = new uint8[ciphertext.length + auth_len];
                    Memory.copy(combined, ciphertext, ciphertext.length);
                    Memory.copy((uint8*) combined + ciphertext.length,
                        (uint8*) key + 16, auth_len);
                    ciphertext = combined;
                    uint8[] short_key = new uint8[16];
                    Memory.copy(short_key, key, 16);
                    key = short_key;
                }

                if (ciphertext != null) {
                    uint8[] pt = global::Omemo.aes_decrypt(
                        global::Omemo.Cipher.AES_GCM_NOPADDING, key, iv, ciphertext);
                    // Null-terminate for Vala string
                    uint8[] result = new uint8[pt.length + 1];
                    Memory.copy(result, pt, pt.length);
                    string plaintext = (string) result;

                    message("BotOmemo: Bot %d decrypted from %s/%d",
                        bot_id, from_jid.to_string(), sid);
                    return plaintext;
                }
            } catch (Error e) {
                warning("BotOmemo: Decrypt failed bot %d from %s/%d: %s",
                    bot_id, from_jid.to_string(), sid, e.message);
            }
        }

        warning("BotOmemo: Could not decrypt for bot %d (own_did=%u)",
            bot_id, own_did);
        return null;
    }

    // ---------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------

    /**
     * Publish the bot's OMEMO bundle via PubSub so other clients can
     * build sessions to us.  Called after stream negotiation.
     */
    public async void publish_bundle(int bot_id, XmppStream stream) {
        var store = stores[bot_id];
        if (store == null) return;

        uint32 device_id = store.local_registration_id;
        if (device_id == 0) return;

        try {
            // Get signed pre-key (id=1, generated in init_bot)
            global::Omemo.SignedPreKeyRecord spk = store.load_signed_pre_key(1);
            global::Omemo.ECKeyPair spk_kp = spk.key_pair;

            // Build bundle stanza
            var bundle_node = new StanzaNode.build("bundle", OMEMO_NS)
                .add_self_xmlns()
                .put_node(new StanzaNode.build("signedPreKeyPublic", OMEMO_NS)
                    .put_attribute("signedPreKeyId", "1")
                    .put_node(new StanzaNode.text(Base64.encode(spk_kp.public.serialize()))))
                .put_node(new StanzaNode.build("signedPreKeySignature", OMEMO_NS)
                    .put_node(new StanzaNode.text(Base64.encode(spk.signature))))
                .put_node(new StanzaNode.build("identityKey", OMEMO_NS)
                    .put_node(new StanzaNode.text(Base64.encode(
                        store.identity_key_store.identity_key_public.get_data()))));

            // Add pre-keys
            var prekeys_node = new StanzaNode.build("prekeys", OMEMO_NS);
            for (int i = 1; i <= NUM_PRE_KEYS; i++) {
                try {
                    global::Omemo.PreKeyRecord pk = store.load_pre_key((uint32) i);
                    prekeys_node.put_node(new StanzaNode.build("preKeyPublic", OMEMO_NS)
                        .put_attribute("preKeyId", i.to_string())
                        .put_node(new StanzaNode.text(
                            Base64.encode(pk.key_pair.public.serialize()))));
                } catch (Error e) {
                    // skip missing pre-keys
                }
            }
            bundle_node.put_node(prekeys_node);

            string node_id = "%s.bundles:%u".printf(OMEMO_NS, device_id);
            yield stream.get_module<Xep.Pubsub.Module>(Xep.Pubsub.Module.IDENTITY)
                .publish(stream, null, node_id, "1", bundle_node);
            message("BotOmemo: Bot %d bundle published (node=%s)", bot_id, node_id);

            // Make bundle node public (fire-and-forget, not on critical path)
            make_bundle_node_public.begin(stream, node_id);
        } catch (Error e) {
            warning("BotOmemo: Bundle publish failed for bot %d: %s", bot_id, e.message);
        }
    }

    /** Make a PubSub bundle node publicly accessible (background task). */
    private async void make_bundle_node_public(XmppStream stream, string node_id) {
        try {
            Xep.DataForms.DataForm? form = yield stream.get_module<Xep.Pubsub.Module>(Xep.Pubsub.Module.IDENTITY)
                .request_node_config(stream, null, node_id);
            if (form == null) return;
            foreach (Xep.DataForms.DataForm.Field field in form.fields) {
                if (field.var == "pubsub#access_model" &&
                    field.get_value_string() != Xep.Pubsub.ACCESS_MODEL_OPEN) {
                    field.set_value_string(Xep.Pubsub.ACCESS_MODEL_OPEN);
                    yield stream.get_module<Xep.Pubsub.Module>(Xep.Pubsub.Module.IDENTITY)
                        .submit_node_config(stream, null, form, node_id);
                    message("BotOmemo: Made bundle node %s public", node_id);
                    break;
                }
            }
        } catch (Error e) {
            warning("BotOmemo: Could not make bundle node %s public: %s", node_id, e.message);
        }
    }

    /** Check whether a stanza carries OMEMO encryption. */
    public bool is_omemo_encrypted(Xmpp.MessageStanza stanza) {
        return stanza.stanza.get_subnode("encrypted", OMEMO_NS) != null;
    }

    /** Whether OMEMO state exists for a bot. */
    public bool is_initialized(int bot_id) {
        return stores.has_key(bot_id);
    }

    /** The OMEMO device id for a bot (0 if not initialised). */
    public uint32 get_device_id(int bot_id) {
        var store = stores[bot_id];
        return store != null ? store.local_registration_id : 0;
    }

    /** Remove OMEMO state for a deleted bot. */
    public void cleanup_bot(int bot_id) {
        stores.unset(bot_id);
        stream_modules.unset(bot_id);
        // Delete persisted keys from DB
        registry.delete_setting("omemo_ik_pub:%d".printf(bot_id));
        registry.delete_setting("omemo_ik_priv:%d".printf(bot_id));
        registry.delete_setting("omemo_reg_id:%d".printf(bot_id));
        registry.delete_setting("omemo_spk:%d".printf(bot_id));
        registry.delete_setting("omemo_pks:%d".printf(bot_id));
        registry.delete_setting("omemo_sessions:%d".printf(bot_id));
        message("BotOmemo: Cleaned up bot %d", bot_id);
    }

    // ---------------------------------------------------------------
    // Pre-key and session persistence
    // ---------------------------------------------------------------

    /**
     * Try loading persisted pre-keys + signed pre-key from the DB.
     * Returns true if successfully loaded, false if not found.
     */
    private bool load_persisted_prekeys(int bot_id,
                                         global::Omemo.Context ctx,
                                         global::Omemo.Store store) {
        string? spk_b64 = registry.get_setting(
            "omemo_spk:%d".printf(bot_id));
        if (spk_b64 == null || spk_b64.length == 0) return false;

        string? pks_json = registry.get_setting(
            "omemo_pks:%d".printf(bot_id));
        if (pks_json == null || pks_json.length == 0) return false;

        try {
            // Restore signed pre-key from raw serialized bytes
            store.signed_pre_key_store.store_signed_pre_key(1,
                Base64.decode(spk_b64));

            // Restore pre-keys from JSON
            var parser = new Json.Parser();
            parser.load_from_data(pks_json);
            var arr = parser.get_root().get_array();
            for (uint i = 0; i < arr.get_length(); i++) {
                var obj = arr.get_object_element(i);
                uint32 pk_id = (uint32) obj.get_int_member("i");
                string pk_data = obj.get_string_member("d");
                store.pre_key_store.store_pre_key(pk_id,
                    Base64.decode(pk_data));
            }
            message("BotOmemo: Loaded %u persisted pre-keys + signed pre-key " +
                "for bot %d", arr.get_length(), bot_id);
            return true;
        } catch (Error e) {
            warning("BotOmemo: Failed loading persisted pre-keys for bot %d: %s",
                bot_id, e.message);
            return false;
        }
    }

    /**
     * Generate fresh pre-keys + signed pre-key and persist to DB.
     * Returns true on success.
     */
    private bool generate_and_persist_prekeys(int bot_id,
                                               global::Omemo.Context ctx,
                                               global::Omemo.Store store) {
        try {
            // Generate and store signed pre-key
            global::Omemo.SignedPreKeyRecord spk = ctx.generate_signed_pre_key(
                store.identity_key_pair, 1);
            store.store_signed_pre_key(spk);

            // Persist signed pre-key raw bytes
            uint8[]? spk_data = store.signed_pre_key_store.load_signed_pre_key(1);
            if (spk_data != null) {
                registry.set_setting("omemo_spk:%d".printf(bot_id),
                    Base64.encode(spk_data));
            }

            // Generate and store pre-keys
            Gee.Set<global::Omemo.PreKeyRecord> pks =
                ctx.generate_pre_keys(1, NUM_PRE_KEYS);
            foreach (global::Omemo.PreKeyRecord pk in pks) {
                store.store_pre_key(pk);
            }

            // Persist pre-keys as JSON array
            var builder = new Json.Builder();
            builder.begin_array();
            for (uint32 i = 1; i <= NUM_PRE_KEYS; i++) {
                uint8[]? pk_data = store.pre_key_store.load_pre_key(i);
                if (pk_data != null) {
                    builder.begin_object();
                    builder.set_member_name("i");
                    builder.add_int_value((int64) i);
                    builder.set_member_name("d");
                    builder.add_string_value(Base64.encode(pk_data));
                    builder.end_object();
                }
            }
            builder.end_array();
            var gen = new Json.Generator();
            gen.root = builder.get_root();
            registry.set_setting("omemo_pks:%d".printf(bot_id),
                gen.to_data(null));

            message("BotOmemo: Generated and persisted %d pre-keys for bot %d",
                NUM_PRE_KEYS, bot_id);
            return true;
        } catch (Error e) {
            warning("BotOmemo: Pre-key generation failed for bot %d: %s",
                bot_id, e.message);
            return false;
        }
    }

    /**
     * Load persisted Signal sessions from DB into the store.
     */
    private void load_persisted_sessions(int bot_id,
                                          global::Omemo.Store store) {
        try {
            string? json_str = registry.get_setting(
                "omemo_sessions:%d".printf(bot_id));
            if (json_str == null || json_str.length == 0) return;

            var parser = new Json.Parser();
            parser.load_from_data(json_str);
            var arr = parser.get_root().get_array();
            int count = 0;
            for (uint i = 0; i < arr.get_length(); i++) {
                var obj = arr.get_object_element(i);
                string name = obj.get_string_member("n");
                int did = (int) obj.get_int_member("d");
                string record_b64 = obj.get_string_member("r");
                global::Omemo.Address addr =
                    new global::Omemo.Address(name, did);
                store.session_store.store_session(addr,
                    Base64.decode(record_b64));
                addr.device_id = 0; // prevent premature free
                count++;
            }
            message("BotOmemo: Loaded %d persisted sessions for bot %d",
                count, bot_id);
        } catch (Error e) {
            warning("BotOmemo: Failed loading persisted sessions for bot %d: %s",
                bot_id, e.message);
        }
    }

    /**
     * Persist a single session update to DB.
     * Called from the session_stored signal whenever ratchet state changes.
     */
    private void persist_session(int bot_id,
                                  global::Omemo.SessionStore.Session session) {
        try {
            string key = "omemo_sessions:%d".printf(bot_id);
            string? json_str = registry.get_setting(key);

            var builder = new Json.Builder();
            builder.begin_array();
            bool found = false;

            if (json_str != null && json_str.length > 0) {
                var parser = new Json.Parser();
                parser.load_from_data(json_str);
                var arr = parser.get_root().get_array();
                for (uint i = 0; i < arr.get_length(); i++) {
                    var obj = arr.get_object_element(i);
                    string n = obj.get_string_member("n");
                    int d = (int) obj.get_int_member("d");
                    if (n == session.name && d == session.device_id) {
                        // Replace with updated record
                        builder.begin_object();
                        builder.set_member_name("n");
                        builder.add_string_value(session.name);
                        builder.set_member_name("d");
                        builder.add_int_value(session.device_id);
                        builder.set_member_name("r");
                        builder.add_string_value(
                            Base64.encode(session.record));
                        builder.end_object();
                        found = true;
                    } else {
                        // Keep existing session
                        builder.begin_object();
                        builder.set_member_name("n");
                        builder.add_string_value(n);
                        builder.set_member_name("d");
                        builder.add_int_value(d);
                        builder.set_member_name("r");
                        builder.add_string_value(
                            obj.get_string_member("r"));
                        builder.end_object();
                    }
                }
            }

            if (!found) {
                builder.begin_object();
                builder.set_member_name("n");
                builder.add_string_value(session.name);
                builder.set_member_name("d");
                builder.add_int_value(session.device_id);
                builder.set_member_name("r");
                builder.add_string_value(Base64.encode(session.record));
                builder.end_object();
            }

            builder.end_array();
            var gen = new Json.Generator();
            gen.root = builder.get_root();
            registry.set_setting(key, gen.to_data(null));
        } catch (Error e) {
            warning("BotOmemo: Failed to persist session for bot %d: %s",
                bot_id, e.message);
        }
    }
}

}
