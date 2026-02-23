using Dino.Entities;
using Qlite;
using Gee;
using Omemo;
using Xmpp;
using Xmpp.Xep.Omemo;
using Xmpp.Xep.Sce;

namespace Dino.Plugins.Omemo {

    /**
     * OMEMO 2 decryptor (XEP-0384 v0.8+).
     *
     * Decryption flow:
     * 1. Find our <key> in <keys jid='our_jid'> group
     * 2. DR_decrypt(encrypted_key) -> mk(32) || auth_tag(16) = 48 bytes
     * 3. HKDF-SHA-256(mk, salt=32_zero_bytes, info="OMEMO Payload") -> 80 bytes:
     *    enc_key[32] | auth_key[32] | iv[16]
     * 4. Verify: HMAC-SHA-256(auth_key, ciphertext)[0:16] == auth_tag
     * 5. plaintext = AES-256-CBC-PKCS7-decrypt(enc_key, iv, ciphertext)
     * 6. Parse SCE envelope -> extract body text
     */
    public class Omemo2Decrypt : Xep.Omemo.Omemo2Decryptor {

        private Account account;
        private Store store;
        private Database db;
        private StreamInteractor stream_interactor;
        private TrustManager trust_manager;
        // Track devices where we already attempted session repair this runtime
        private Gee.HashSet<string> session_repair_attempted = new Gee.HashSet<string>();

        /* HKDF constants */
        private const int MK_SIZE = 32;
        private const string HKDF_INFO = "OMEMO Payload";
        private const int HKDF_OUTPUT_SIZE = 80;
        private const int HKDF_SALT_SIZE = 32;

        public override uint32 own_device_id { get { return store.local_registration_id; }}

        public Omemo2Decrypt(Account account, StreamInteractor stream_interactor, TrustManager trust_manager, Database db, Store store) {
            this.account = account;
            this.stream_interactor = stream_interactor;
            this.trust_manager = trust_manager;
            this.db = db;
            this.store = store;
        }

        /**
         * Try to decrypt an OMEMO 2 encrypted message.
         */
        public async bool decrypt_message(Entities.Message message, Xmpp.MessageStanza stanza, Conversation conversation) {
            StanzaNode? encrypted_node = stanza.stanza.get_subnode("encrypted", NS_URI_V2);
            if (encrypted_node == null || MessageFlag.get_flag(stanza) != null || stanza.from == null) return false;

            if (!Plugin.ensure_context()) return false;
            int identity_id = db.identity.get_id(conversation.account.id);

            MessageFlag flag = new MessageFlag();
            stanza.add_flag(flag);

            Jid our_jid = account.bare_jid;
            Omemo2ParsedData? data = parse_node(encrypted_node, our_jid);
            if (data == null) return false;

            foreach (Bytes encr_key in data.our_potential_encrypted_keys.keys) {
                bool is_kex = data.our_potential_encrypted_keys[encr_key];
                uint8[] encrypted_key = encr_key.get_data();

                Gee.List<Jid> possible_jids = get_potential_message_jids(message, encrypted_key, is_kex, data, identity_id);
                if (possible_jids.size == 0) {
                    debug("OMEMO 2: Received message from unknown entity with device id %d", data.sid);
                }

                foreach (Jid possible_jid in possible_jids) {
                    try {
                        /* Decrypt per-device key -> mk || auth_tag */
                        uint8[] mk_and_tag = decrypt_key_raw(encrypted_key, is_kex, data.sid, possible_jid);

                        if (data.ciphertext != null) {
                            Xep.Sce.Envelope envelope = yield decrypt_envelope(data.ciphertext, mk_and_tag);

                            /* Extract body if present */
                            string? body = envelope.get_body();
                            if (body != null) {
                                message.body = body;
                            }

                            /* Inject all SCE content nodes into stanza for downstream handlers
                             * (e.g. FileProvider for file-sharing, OOB, SFS elements) */
                            foreach (StanzaNode content_node in envelope.content_nodes) {
                                debug("OMEMO 2: SCE content node: <%s xmlns='%s'> xml=%s",
                                      content_node.name,
                                      content_node.ns_uri ?? "(null)",
                                      content_node.to_xml());
                                if (content_node.name != "body") {
                                    stanza.stanza.put_node(content_node);
                                }
                                /* Store BOB (Bits of Binary) data from SCE envelope so that
                                 * thumbnail cid: URIs can be resolved later.  The normal
                                 * BOB pipeline listener ran before OMEMO decryption and
                                 * couldn't see these nodes. */
                                if (content_node.name == "data" && content_node.ns_uri == Xmpp.Xep.BitsOfBinary.NS_URI) {
                                    string? cid = content_node.get_attribute("cid");
                                    string? base64 = content_node.get_string_content();
                                    if (cid != null && base64 != null) {
                                        if (Xmpp.Xep.BitsOfBinary.known_bobs == null) {
                                            Xmpp.Xep.BitsOfBinary.known_bobs = new Gee.HashMap<string, GLib.Bytes>();
                                        }
                                        Xmpp.Xep.BitsOfBinary.known_bobs[cid] = new GLib.Bytes.take(GLib.Base64.decode(base64));
                                        debug("OMEMO 2: Stored BOB data for cid=%s (%d bytes)", cid, (int)Xmpp.Xep.BitsOfBinary.known_bobs[cid].length);
                                    }
                                }
                            }
                        }

                        if (conversation.type_ == Conversation.Type.GROUPCHAT && message.real_jid == null) {
                            message.real_jid = possible_jid;
                        }

                        message.encryption = Encryption.OMEMO;
                        trust_manager.message_device_id_map[message] = data.sid;

                        // Update last_active for this device (actual message, not just PubSub presence)
                        if (identity_id >= 0) {
                            db.identity_meta.update_last_active(identity_id, possible_jid.bare_jid.to_string(), data.sid);
                        }

                        return true;
                    } catch (Error e) {
                        debug("OMEMO 2: Decrypting message from %s/%d failed: %s", possible_jid.to_string(), data.sid, e.message);

                        string repair_key = "%s/%d".printf(possible_jid.bare_jid.to_string(), data.sid);
                        if ((e.message.contains("SG_ERR_NO_SESSION") || e.message.contains("SG_ERR_INVALID_MESSAGE"))
                            && !session_repair_attempted.contains(repair_key)) {
                            session_repair_attempted.add(repair_key);
                            debug("OMEMO 2: Broken/missing session for %s/%d — deleting and fetching bundle (one-time repair)", possible_jid.to_string(), data.sid);
                            try {
                                Address addr = new Address(possible_jid.bare_jid.to_string(), data.sid);
                                if (store.contains_session(addr)) {
                                    store.delete_session(addr);
                                    debug("OMEMO 2: Deleted broken session for %s/%d", possible_jid.to_string(), data.sid);
                                }
                                addr.device_id = 0;
                            } catch (Error del_err) {
                                warning("OMEMO 2: Error deleting session: %s", del_err.message);
                            }
                            XmppStream? stream = stream_interactor.get_stream(account);
                            if (stream != null) {
                                StreamModule2? module = stream.get_module<StreamModule2>(StreamModule2.IDENTITY);
                                if (module != null) {
                                    module.fetch_bundle(stream, possible_jid, data.sid, false);
                                }
                            }
                        } else if (e.message.contains("SG_ERR_NO_SESSION") || e.message.contains("SG_ERR_INVALID_MESSAGE")) {
                            debug("OMEMO 2: Session repair already attempted for %s/%d — ignoring old message", possible_jid.to_string(), data.sid);
                        }
                    }
                }
            }

            if (data.ciphertext != null &&
                data.our_potential_encrypted_keys.size == 0 &&
                store.local_registration_id != data.sid
            ) {
                bool should_mark_undecryptable = true;
                if (conversation.history_cleared_at != null && message.time != null) {
                    if (message.time.compare(conversation.history_cleared_at) < 0) {
                        should_mark_undecryptable = false;
                    }
                }

                if (should_mark_undecryptable) {
                    db.identity_meta.update_last_message_undecryptable(identity_id, data.sid, message.time);
                    trust_manager.bad_message_state_updated(conversation.account, message.from, data.sid);
                }
            }

            debug("OMEMO 2: Received encrypted message that could not be decrypted.");
            return false;
        }

        /**
         * Decrypt per-device key using Double Ratchet.
         */
        private uint8[] decrypt_key_raw(uint8[] encrypted_key, bool is_kex, int sid, Jid from_jid) throws GLib.Error {
            Address address = new Address(from_jid.bare_jid.to_string(), sid);
            uint8[] decrypted;

            if (is_kex) {
                int identity_id = db.identity.get_id(account.id);
                /* Use OMEMO 2 deserialization: registration_id from header sid */
                PreKeyOmemoMessage msg = Plugin.get_context().deserialize_omemo_pre_key_message(encrypted_key, (uint32)sid);
                string identity_key = Base64.encode(msg.identity_key.serialize());

                bool ok = update_db_for_prekey(identity_id, identity_key, from_jid, sid);
                if (!ok) throw new GLib.Error(-1, 0, "Failed updating db for prekey");

                debug("OMEMO 2: Starting new session for decryption with %s/%d", from_jid.to_string(), sid);
                SessionCipher cipher = store.create_session_cipher(address);
                cipher.version = 4; // OMEMO 2 requires protocol version 4
                decrypted = cipher.decrypt_pre_key_message(msg);
            } else {
                debug("OMEMO 2: Continuing session for decryption with %s/%d", from_jid.to_string(), sid);
                OmemoMessage msg = Plugin.get_context().deserialize_omemo_message(encrypted_key);
                SessionCipher cipher = store.create_session_cipher(address);
                cipher.version = 4; // OMEMO 2 requires protocol version 4
                decrypted = cipher.decrypt_message(msg);
            }

            address.device_id = 0;
            return decrypted;
        }

        /**
         * Decrypt the OMEMO 2 payload using the message key.
         */
        public override async string decrypt(uint8[] ciphertext, uint8[] message_key) throws GLib.Error {
            Xep.Sce.Envelope envelope = yield decrypt_envelope(ciphertext, message_key);
            string? body = envelope.get_body();
            return body ?? "";
        }

        /**
         * Decrypt payload: verify HMAC, AES-256-CBC decrypt, parse SCE.
         * Returns the full SCE envelope for processing all content nodes.
         */
        private async Xep.Sce.Envelope decrypt_envelope(uint8[] ciphertext, uint8[] mk_and_tag) throws GLib.Error {
            uint8[] plaintext = omemo2_decrypt_payload(ciphertext, mk_and_tag);

            /* Parse SCE envelope */
            Xep.Sce.Envelope? envelope = yield Xep.Sce.Envelope.from_xml(plaintext);
            if (envelope == null) {
                throw new GLib.Error(Quark.from_string("omemo2"), 15, "Failed to parse SCE envelope");
            }

            debug("OMEMO 2: SCE envelope decoded, %d content nodes, body=%s",
                  envelope.content_nodes.size, envelope.get_body() != null ? "yes" : "no");

            return envelope;
        }

        /**
         * Pure crypto pipeline for decryption: HKDF → HMAC verify → AES-256-CBC decrypt.
         *
         * Inverse of Omemo2Encrypt.omemo2_encrypt_payload().
         * Deterministic given (ciphertext, mk_and_tag). No I/O, no async.
         *
         * @param ciphertext    AES-256-CBC ciphertext
         * @param mk_and_tag   mk || truncated_hmac (48 bytes)
         * @return              decrypted plaintext bytes
         */
        internal static uint8[] omemo2_decrypt_payload(uint8[] ciphertext, uint8[] mk_and_tag) throws GLib.Error {
            if (mk_and_tag.length < MK_SIZE + 16) {
                throw new GLib.Error(Quark.from_string("omemo2"), 10, "Decrypted key too short (got %d, need %d)", mk_and_tag.length, MK_SIZE + 16);
            }

            uint8[] mk = mk_and_tag[0:MK_SIZE];
            uint8[] received_tag = mk_and_tag[MK_SIZE:MK_SIZE + 16];

            /* HKDF to derive enc_key, auth_key, iv */
            uint8[] salt = new uint8[HKDF_SALT_SIZE];
            Memory.set(salt, 0, HKDF_SALT_SIZE);
            uint8[] hkdf_output = new uint8[HKDF_OUTPUT_SIZE];

            int rc = omemo2_hkdf_sha256(hkdf_output, HKDF_OUTPUT_SIZE,
                mk, salt, HKDF_INFO.data);
            if (rc != 0) throw new GLib.Error(Quark.from_string("omemo2"), 11, "HKDF failed");

            uint8[] enc_key = hkdf_output[0:32];
            uint8[] auth_key = hkdf_output[32:64];
            uint8[] iv = hkdf_output[64:80];

            /* Verify HMAC */
            uint8[] computed_tag = new uint8[16];
            rc = omemo2_hmac_sha256(computed_tag, 16, auth_key, ciphertext);
            if (rc != 0) throw new GLib.Error(Quark.from_string("omemo2"), 12, "HMAC computation failed");

            if (!constant_time_compare(computed_tag, received_tag)) {
                throw new GLib.Error(Quark.from_string("omemo2"), 13, "HMAC verification failed");
            }

            /* AES-256-CBC decrypt */
            uint8[] plaintext;
            size_t plaintext_len;
            rc = omemo2_aes_256_cbc_pkcs7_decrypt(out plaintext, out plaintext_len,
                enc_key, iv, ciphertext);
            if (rc != 0) throw new GLib.Error(Quark.from_string("omemo2"), 14, "AES-256-CBC decrypt failed");
            plaintext.length = (int)plaintext_len;

            return plaintext;
        }

        /**
         * Constant-time comparison to prevent timing attacks.
         */
        internal static bool constant_time_compare(uint8[] a, uint8[] b) {
            if (a.length != b.length) return false;
            uint8 result = 0;
            for (int i = 0; i < a.length; i++) {
                result |= a[i] ^ b[i];
            }
            return result == 0;
        }

        public override uint8[] decrypt_key(Omemo2ParsedData data, Jid from_jid) throws GLib.Error {
            /* Find the first working key */
            foreach (Bytes encr_key in data.our_potential_encrypted_keys.keys) {
                bool is_kex = data.our_potential_encrypted_keys[encr_key];
                try {
                    return decrypt_key_raw(encr_key.get_data(), is_kex, data.sid, from_jid);
                } catch (Error e) {
                    debug("OMEMO 2: Key decryption attempt failed: %s", e.message);
                }
            }
            throw new GLib.Error(-1, 0, "No valid key found for decryption");
        }

        private Gee.List<Jid> get_potential_message_jids(Entities.Message message, uint8[] encrypted_key, bool is_kex, Omemo2ParsedData data, int identity_id) {
            Gee.List<Jid> possible_jids = new ArrayList<Jid>();
            if (message.type_ == Message.Type.CHAT) {
                possible_jids.add(message.from.bare_jid);
            } else {
                if (message.real_jid != null) {
                    possible_jids.add(message.real_jid.bare_jid);
                } else if (is_kex) {
                    try {
                        PreKeyOmemoMessage msg = Plugin.get_context().deserialize_omemo_pre_key_message(encrypted_key, (uint32)data.sid);
                        string identity_key = Base64.encode(msg.identity_key.serialize());
                        foreach (Row row in db.identity_meta.get_with_device_id(identity_id, data.sid).with(db.identity_meta.identity_key_public_base64, "=", identity_key)) {
                            try {
                                possible_jids.add(new Jid(row[db.identity_meta.address_name]));
                            } catch (InvalidJidError e) {
                                warning("Ignoring invalid jid from database: %s", e.message);
                            }
                        }
                    } catch (Error e) {
                        warning("OMEMO 2: Failed to deserialize pre-key message: %s", e.message);
                    }
                } else {
                    foreach (Row row in db.identity_meta.get_with_device_id(identity_id, data.sid)) {
                        try {
                            possible_jids.add(new Jid(row[db.identity_meta.address_name]));
                        } catch (InvalidJidError e) {
                            warning("Ignoring invalid jid from database: %s", e.message);
                        }
                    }
                }
            }
            return possible_jids;
        }

        private bool update_db_for_prekey(int identity_id, string identity_key, Jid from_jid, int sid) {
            Row? device = db.identity_meta.get_device(identity_id, from_jid.to_string(), sid);
            if (device != null && device[db.identity_meta.identity_key_public_base64] != null) {
                if (device[db.identity_meta.identity_key_public_base64] != identity_key) {
                    warning("OMEMO 2: Identity key changed for device %d of %s. Accepting new key (may be key format migration or reinstall).", sid, from_jid.to_string());
                    // Delete old session -- it's no longer valid with the new identity key
                    try {
                        Address addr = new Address(from_jid.bare_jid.to_string(), sid);
                        store.delete_session(addr);
                        addr.device_id = 0;
                    } catch (Error e) {
                        warning("OMEMO 2: Failed to delete old session for %s/%d: %s", from_jid.to_string(), sid, e.message);
                    }
                    // Update the stored identity key and reset trust to UNKNOWN
                    db.identity_meta.insert_device_session(identity_id, from_jid.to_string(), sid, identity_key, TrustLevel.UNKNOWN);
                }
            } else {
                debug("OMEMO 2: Learn new device from incoming message from %s/%d", from_jid.to_string(), sid);
                bool blind_trust = db.trust.get_blind_trust(identity_id, from_jid.to_string(), true);
                if (db.identity_meta.insert_device_session(identity_id, from_jid.to_string(), sid, identity_key, blind_trust ? TrustLevel.TRUSTED : TrustLevel.UNKNOWN) < 0) {
                    critical("OMEMO 2: Failed learning a device.");
                    return false;
                }
            }

            XmppStream? stream = stream_interactor.get_stream(account);
            if (stream != null) {
                var module = stream.get_module<StreamModule2>(StreamModule2.IDENTITY);
                if (module != null) {
                    module.request_user_devicelist.begin(stream, from_jid);
                }
            }

            return true;
        }
    }

    /**
     * Classification of what action to take when processing a pre-key message
     * with respect to identity key storage.
     *
     * Security note: KEY_CHANGED currently proceeds silently (Bug #19).
     * A compliant implementation should halt and require user confirmation
     * (CWE-295: Improper Certificate Validation / CWE-322).
     */
    internal enum PreKeyUpdateAction {
        /** Device is new — insert with blind-trust or UNKNOWN. */
        INSERT_NEW,
        /** Identity key matches — no database write needed. */
        NO_CHANGE,
        /** Identity key CHANGED — old session invalid, trust reset to UNKNOWN.
         *  Currently accepted silently (Bug #19). */
        KEY_CHANGED,
    }

    /**
     * Pure decision function: classify what action update_db_for_prekey should take.
     *
     * Extracted from Omemo2Decrypt.update_db_for_prekey() and
     * OmemoDecryptor.update_db_for_prekey() for testability.
     *
     * @param existing_identity_key  The identity key currently stored in DB (null if none)
     * @param incoming_identity_key  The identity key from the incoming pre-key message
     * @param device_exists          Whether a device record exists in the DB
     * @return The action to take
     */
    internal static PreKeyUpdateAction classify_prekey_update(
        string? existing_identity_key,
        string incoming_identity_key,
        bool device_exists
    ) {
        if (!device_exists || existing_identity_key == null) {
            return PreKeyUpdateAction.INSERT_NEW;
        }
        if (existing_identity_key != incoming_identity_key) {
            return PreKeyUpdateAction.KEY_CHANGED;
        }
        return PreKeyUpdateAction.NO_CHANGE;
    }

    /**
     * Stage at which a decryption failure occurred, relative to ratchet state.
     *
     * PRE_RATCHET errors are safe to retry — the Double Ratchet has not advanced.
     * POST_RATCHET errors mean the ratchet key was consumed and the message
     * can never be retried (CWE-755: inconsistent state on partial failure).
     */
    internal enum DecryptFailureStage {
        /** Failure before ratchet advance: deserialization, no session, lookup. */
        PRE_RATCHET,
        /** Failure after ratchet advance: HMAC, AES, SCE parse. */
        POST_RATCHET,
        /** Unknown error — assume post-ratchet for safety. */
        UNKNOWN_ASSUME_POST,
    }

    /**
     * Classify a decryption error to determine if the Double Ratchet has advanced.
     *
     * In the OMEMO 2 decrypt path (decrypt_key_raw → decrypt_envelope), failures
     * can occur at different stages:
     *
     * PRE-RATCHET (safe to retry):
     * - Deserialization failure (bad protobuf)
     * - SG_ERR_NO_SESSION (no session in store)
     * - SG_ERR_INVALID_MESSAGE (message format rejected before decrypt)
     * - SG_ERR_LEGACY_MESSAGE (v3/v4 version mismatch)
     * - DB update failure (update_db_for_prekey returns false)
     *
     * POST-RATCHET (ratchet consumed, cannot retry):
     * - HMAC verification failed (ratchet decrypted key, but payload HMAC bad)
     * - AES-256-CBC decrypt failed (key derived, CBC failed)
     * - SCE envelope parse failed (plaintext obtained, XML parse failed)
     * - Decrypted key too short (ratchet decrypted, but result wrong size)
     *
     * @param error_message  The GLib.Error.message string
     * @return The failure stage classification
     */
    internal static DecryptFailureStage classify_decrypt_failure_stage(string error_message) {
        /* Pre-ratchet: Signal Protocol errors occur before chain key consumption */
        if (error_message.contains("SG_ERR_NO_SESSION")) return DecryptFailureStage.PRE_RATCHET;
        if (error_message.contains("SG_ERR_INVALID_MESSAGE")) return DecryptFailureStage.PRE_RATCHET;
        if (error_message.contains("SG_ERR_LEGACY_MESSAGE")) return DecryptFailureStage.PRE_RATCHET;
        if (error_message.contains("deserialize")) return DecryptFailureStage.PRE_RATCHET;
        if (error_message.contains("Failed updating db for prekey")) return DecryptFailureStage.PRE_RATCHET;

        /* Post-ratchet: these occur after cipher.decrypt returned successfully */
        if (error_message.contains("HMAC verification failed")) return DecryptFailureStage.POST_RATCHET;
        if (error_message.contains("AES-256-CBC decrypt failed")) return DecryptFailureStage.POST_RATCHET;
        if (error_message.contains("Failed to parse SCE envelope")) return DecryptFailureStage.POST_RATCHET;
        if (error_message.contains("Decrypted key too short")) return DecryptFailureStage.POST_RATCHET;
        if (error_message.contains("HKDF failed")) return DecryptFailureStage.POST_RATCHET;
        if (error_message.contains("HMAC computation failed")) return DecryptFailureStage.POST_RATCHET;

        /* Unknown — conservative: assume ratchet may have advanced */
        return DecryptFailureStage.UNKNOWN_ASSUME_POST;
    }

    /**
     * Message listener for OMEMO 2 decryption.
     */
    public class Omemo2DecryptMessageListener : MessageListener {
        public string[] after_actions_const = new string[]{ };
        public override string action_group { get { return "DECRYPT"; } }
        public override string[] after_actions { get { return after_actions_const; } }

        private HashMap<Account, Omemo2Decrypt> decryptors;

        public Omemo2DecryptMessageListener(HashMap<Account, Omemo2Decrypt> decryptors) {
            this.decryptors = decryptors;
        }

        public override async bool run(Entities.Message message, Xmpp.MessageStanza stanza, Conversation conversation) {
            bool had_encrypted_node = stanza.stanza.get_subnode("encrypted", "urn:xmpp:omemo:2") != null;
            bool decrypted = false;
            if (decryptors.has_key(message.account)) {
                decrypted = yield decryptors[message.account].decrypt_message(message, stanza, conversation);
            }

            // If the stanza had an OMEMO v2 <encrypted> element but decryption failed,
            // clear the body so the OMEMO fallback text doesn't get stored as plaintext.
            if (had_encrypted_node && !decrypted && message.encryption != Encryption.OMEMO) {
                message.body = null;
            }
            return false;
        }
    }
}
