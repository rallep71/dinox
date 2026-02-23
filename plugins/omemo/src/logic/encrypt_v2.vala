using Gee;
using Omemo;
using Dino.Entities;
using Xmpp;
using Xmpp.Xep.Omemo;
using Xmpp.Xep.Sce;

namespace Dino.Plugins.Omemo {

    /**
     * OMEMO 2 encryptor (XEP-0384 v0.8+).
     *
     * Encryption flow:
     * 1. Build SCE envelope with body text + from JID + random padding
     * 2. Generate random 32-byte message key (mk)
     * 3. HKDF-SHA-256(mk, salt=32_zero_bytes, info="OMEMO Payload") -> 80 bytes:
     *    enc_key[32] | auth_key[32] | iv[16]
     * 4. ciphertext = AES-256-CBC-PKCS7(enc_key, iv, SCE_plaintext)
     * 5. auth_tag = HMAC-SHA-256(auth_key, ciphertext)[0:16]
     * 6. payload = ciphertext (in <payload>)
     * 7. Per device: DR_encrypt(mk || auth_tag) = 48 bytes -> <key rid='...'> 
     */
    public class Omemo2Encrypt : Xep.Omemo.Omemo2Encryptor {

        private Account account;
        private Store store;
        private TrustManager trust_manager;

        /* HKDF constants */
        private const int MK_SIZE = 32;
        private const string HKDF_INFO = "OMEMO Payload";
        private const int HKDF_OUTPUT_SIZE = 80;  /* 32 + 32 + 16 */
        private const int HKDF_SALT_SIZE = 32;    /* 32 zero bytes */

        public override uint32 own_device_id { get { return store.local_registration_id; }}

        public Omemo2Encrypt(Account account, TrustManager trust_manager, Store store) {
            this.account = account;
            this.trust_manager = trust_manager;
            this.store = store;
        }

        public override Omemo2EncryptionData encrypt_plaintext(string plaintext) throws GLib.Error {
            return encrypt_plaintext_with_extras(plaintext, null);
        }

        /**
         * Encrypt the full message and add to the MessageStanza.
         * For OMEMO 2, this wraps the body AND any SFS/OOB/fallback elements
         * inside the SCE envelope so they are encrypted end-to-end.
         */
        public EncryptState encrypt(MessageStanza message, Jid self_jid, Gee.List<Jid> recipients, XmppStream stream) {
            EncryptState status = new EncryptState();
            if (!Plugin.ensure_context()) return status;
            if (message.to == null) return status;

            try {
                /* Collect extra nodes from the stanza that should go inside the SCE envelope */
                var extra_nodes = new Gee.ArrayList<StanzaNode>();
                var nodes_to_remove = new Gee.ArrayList<StanzaNode>();
                // Namespaces of content that belongs inside the SCE envelope
                string[] sce_ns = {
                    "urn:xmpp:sfs:0",            // XEP-0447 Stateless File Sharing
                    "jabber:x:oob",               // XEP-0066 Out of Band Data
                    "urn:xmpp:fallback:0",         // XEP-0428 Fallback Indication
                    "urn:xmpp:receipts",           // XEP-0184 Message Delivery Receipts
                    "urn:xmpp:chat-markers:0",     // XEP-0333 Chat Markers
                    "urn:xmpp:bob"                 // XEP-0231 Bits of Binary (thumbnails)
                };
                foreach (StanzaNode child in message.stanza.get_all_subnodes()) {
                    foreach (string ns in sce_ns) {
                        if (child.ns_uri == ns) {
                            extra_nodes.add(child);
                            nodes_to_remove.add(child);
                            break;
                        }
                    }
                }

                /* Determine SCE body text.
                 * If the message contains SFS nodes, omit the body entirely
                 * (the URL would otherwise appear as text below the file in
                 * clients like Kaidan). */
                bool has_sfs = false;
                foreach (StanzaNode en in extra_nodes) {
                    if (en.ns_uri == "urn:xmpp:sfs:0") { has_sfs = true; break; }
                }
                string? body_text = has_sfs ? null : message.body;
                if (body_text != null && body_text.has_prefix("aesgcm://")) {
                    string stripped = "https://" + body_text.substring("aesgcm://".length);
                    int frag = stripped.index_of("#");
                    if (frag >= 0) stripped = stripped.substring(0, frag);
                    body_text = stripped;
                }

                Omemo2EncryptionData enc_data = encrypt_plaintext_with_extras(body_text, extra_nodes);

                debug("OMEMO 2 encrypt: body='%s' extra_nodes=%d", 
                      body_text != null && body_text.length > 80 ? body_text.substring(0, 80) + "..." : body_text ?? "(null)",
                      extra_nodes.size);
                foreach (StanzaNode en in extra_nodes) {
                    debug("OMEMO 2 encrypt: extra node <%s xmlns='%s'>", en.name, en.ns_uri ?? "(null)");
                }

                status = encrypt_key_to_recipients(enc_data, self_jid, recipients, stream);

                /* Remove the collected nodes from the cleartext stanza */
                foreach (StanzaNode node in nodes_to_remove) {
                    message.stanza.sub_nodes.remove(node);
                }

                message.stanza.put_node(enc_data.get_encrypted_node());
                Xep.ExplicitEncryption.add_encryption_tag_to_message(message, NS_URI_V2, "OMEMO");
                message.body = "[This message is OMEMO encrypted]";
                status.encrypted = true;
            } catch (Error e) {
                warning("OMEMO 2: Error while encrypting message: %s", e.message);
                message.body = "[OMEMO encryption failed]";
                status.encrypted = false;
            }
            return status;
        }

        /**
         * Build and encrypt an SCE envelope with body text and extra content nodes.
         */
        public Omemo2EncryptionData encrypt_plaintext_with_extras(string? plaintext, Gee.List<StanzaNode>? extra_content_nodes = null) throws GLib.Error {
            /* 1. Build SCE envelope with body + extra nodes */
            Xep.Sce.Envelope envelope = Xep.Sce.build_message_envelope(plaintext, account.bare_jid);

            if (extra_content_nodes != null) {
                foreach (StanzaNode node in extra_content_nodes) {
                    envelope.add_content_node(node);
                }
            }

            uint8[] sce_bytes = envelope.to_xml();

            /* 2. Generate message key */
            uint8[] mk = new uint8[MK_SIZE];
            Plugin.get_context().randomize(mk);

            /* 3-6. Crypto pipeline */
            uint8[] ciphertext;
            uint8[] mk_with_tag;
            omemo2_encrypt_payload(mk, sce_bytes, out ciphertext, out mk_with_tag);

            var ret = new Omemo2EncryptionData(own_device_id);
            ret.ciphertext = ciphertext;
            ret.message_key = mk_with_tag;

            // Zeroize sensitive key material
            Memory.set(mk, 0, MK_SIZE);

            return ret;
        }

        /**
         * Pure crypto pipeline: HKDF → AES-256-CBC → HMAC-SHA-256.
         *
         * Deterministic given (mk, plaintext). No I/O, no RNG,
         * no Account/Store/Plugin dependencies.
         *
         * @param mk           32-byte message key (caller-generated)
         * @param plaintext     SCE envelope bytes to encrypt
         * @param ciphertext    [out] AES-256-CBC-PKCS7 ciphertext
         * @param mk_with_tag  [out] mk || truncated_hmac (48 bytes)
         */
        internal static void omemo2_encrypt_payload(uint8[] mk, uint8[] plaintext,
                out uint8[] ciphertext, out uint8[] mk_with_tag) throws GLib.Error {

            /* HKDF-SHA-256(mk, salt=32_zeros, info="OMEMO Payload") → 80 bytes */
            uint8[] salt = new uint8[HKDF_SALT_SIZE];
            Memory.set(salt, 0, HKDF_SALT_SIZE);
            uint8[] hkdf_output = new uint8[HKDF_OUTPUT_SIZE];

            int rc = omemo2_hkdf_sha256(hkdf_output, HKDF_OUTPUT_SIZE,
                mk, salt, HKDF_INFO.data);
            if (rc != 0) throw new GLib.Error(Quark.from_string("omemo2"), 1, "HKDF failed");

            uint8[] enc_key = hkdf_output[0:32];
            uint8[] auth_key = hkdf_output[32:64];
            uint8[] iv = hkdf_output[64:80];

            /* AES-256-CBC-PKCS7 encrypt */
            size_t ciphertext_len;
            rc = omemo2_aes_256_cbc_pkcs7_encrypt(out ciphertext, out ciphertext_len,
                enc_key, iv, plaintext);
            if (rc != 0) throw new GLib.Error(Quark.from_string("omemo2"), 2, "AES-256-CBC encrypt failed");
            ciphertext.length = (int)ciphertext_len;

            /* HMAC-SHA-256 auth tag (truncated to 16 bytes) */
            uint8[] auth_tag = new uint8[16];
            rc = omemo2_hmac_sha256(auth_tag, 16, auth_key, ciphertext);
            if (rc != 0) throw new GLib.Error(Quark.from_string("omemo2"), 3, "HMAC-SHA-256 failed");

            /* Build mk || auth_tag = 48 bytes */
            mk_with_tag = new uint8[MK_SIZE + 16];
            Memory.copy(mk_with_tag, mk, MK_SIZE);
            Memory.copy((uint8*)mk_with_tag + MK_SIZE, auth_tag, 16);

            // Zeroize intermediates
            Memory.set(hkdf_output, 0, HKDF_OUTPUT_SIZE);
            Memory.set(enc_key, 0, 32);
            Memory.set(auth_key, 0, 32);
        }

        internal EncryptState encrypt_key_to_recipients(Omemo2EncryptionData enc_data, Jid self_jid, Gee.List<Jid> recipients, XmppStream stream) throws Error {
            EncryptState status = new EncryptState();

            if (!trust_manager.is_known_address(account, self_jid)) return status;
            status.own_list = true;
            status.own_devices = trust_manager.get_trusted_devices(account, self_jid).size;
            status.other_waiting_lists = 0;
            status.other_devices = 0;
            foreach (Jid recipient in recipients) {
                if (!trust_manager.is_known_address(account, recipient)) {
                    status.other_waiting_lists++;
                }
                if (status.other_waiting_lists > 0) return status;
                status.other_devices += trust_manager.get_trusted_devices(account, recipient).size;
            }
            // Allow sending with no other devices (e.g. solo MUC — encrypt to self only)
            if (status.own_devices == 0) return status;
            if (recipients.size > 0 && status.other_devices == 0) return status;

            foreach (Jid recipient in recipients) {
                EncryptionResult enc_res = encrypt_key_to_recipient(stream, enc_data, recipient);
                status.add_result(enc_res, false);
            }

            EncryptionResult enc_res = encrypt_key_to_recipient(stream, enc_data, self_jid);
            status.add_result(enc_res, true);

            return status;
        }

        public override EncryptionResult encrypt_key_to_recipient(XmppStream stream, Omemo2EncryptionData enc_data, Jid recipient) throws GLib.Error {
            var result = new EncryptionResult();
            /* Use both legacy and v2 stream modules for device tracking */
            StreamModule2? module = stream.get_module<StreamModule2>(StreamModule2.IDENTITY);
            if (module == null) {
                warning("OMEMO 2: StreamModule2 not available");
                return result;
            }

            foreach (int32 device_id in trust_manager.get_trusted_devices(account, recipient)) {
                if (module.is_ignored_device(recipient, device_id)) {
                    result.lost++;
                    continue;
                }
                try {
                    encrypt_key(enc_data, recipient, device_id);
                    result.success++;
                } catch (Error e) {
                    if (e.code == ErrorCode.UNKNOWN) result.unknown++;
                    else result.failure++;
                }
            }
            return result;
        }

        public override void encrypt_key(Omemo2EncryptionData encryption_data, Jid jid, int32 device_id) throws GLib.Error {
            Address address = new Address(jid.bare_jid.to_string(), device_id);
            SessionCipher cipher = store.create_session_cipher(address);
            cipher.version = 4; // OMEMO 2 requires protocol version 4
            CiphertextMessage device_key = cipher.encrypt(encryption_data.message_key);
            address.device_id = 0;
            debug("OMEMO 2: Created encrypted key for %s/%d", jid.bare_jid.to_string(), device_id);

            encryption_data.add_device_key(jid, device_id, device_key.serialized, device_key.type == CiphertextType.PREKEY);
        }
    }
}
