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
     * 3. HKDF-SHA-256(mk, salt=32_zero_bytes, info="OMEMO Payload") → 80 bytes:
     *    enc_key[32] | auth_key[32] | iv[16]
     * 4. ciphertext = AES-256-CBC-PKCS7(enc_key, iv, SCE_plaintext)
     * 5. auth_tag = HMAC-SHA-256(auth_key, ciphertext)[0:16]
     * 6. payload = ciphertext (in <payload>)
     * 7. Per device: DR_encrypt(mk || auth_tag) = 48 bytes → <key rid='...'> 
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
            /* 1. Build SCE envelope */
            Xep.Sce.Envelope envelope = Xep.Sce.build_message_envelope(plaintext, account.bare_jid);
            uint8[] sce_bytes = envelope.to_xml();

            /* 2. Generate message key */
            uint8[] mk = new uint8[MK_SIZE];
            Plugin.get_context().randomize(mk);

            /* 3. HKDF to derive enc_key, auth_key, iv */
            uint8[] salt = new uint8[HKDF_SALT_SIZE];
            Memory.set(salt, 0, HKDF_SALT_SIZE);
            uint8[] hkdf_output = new uint8[HKDF_OUTPUT_SIZE];

            int rc = omemo2_hkdf_sha256(hkdf_output, HKDF_OUTPUT_SIZE,
                mk, salt, HKDF_INFO.data);
            if (rc != 0) throw new GLib.Error(Quark.from_string("omemo2"), 1, "HKDF failed");

            uint8[] enc_key = hkdf_output[0:32];
            uint8[] auth_key = hkdf_output[32:64];
            uint8[] iv = hkdf_output[64:80];

            /* 4. AES-256-CBC-PKCS7 encrypt */
            uint8[] ciphertext;
            size_t ciphertext_len;
            rc = omemo2_aes_256_cbc_pkcs7_encrypt(out ciphertext, out ciphertext_len,
                enc_key, iv, sce_bytes);
            if (rc != 0) throw new GLib.Error(Quark.from_string("omemo2"), 2, "AES-256-CBC encrypt failed");
            ciphertext.length = (int)ciphertext_len;

            /* 5. HMAC-SHA-256 auth tag (truncated to 16 bytes) */
            uint8[] auth_tag = new uint8[16];
            rc = omemo2_hmac_sha256(auth_tag, 16, auth_key, ciphertext);
            if (rc != 0) throw new GLib.Error(Quark.from_string("omemo2"), 3, "HMAC-SHA-256 failed");

            /* 6. Build mk || auth_tag = 48 bytes (encrypted per device) */
            uint8[] mk_with_tag = new uint8[MK_SIZE + 16];
            Memory.copy(mk_with_tag, mk, MK_SIZE);
            Memory.copy((uint8*)mk_with_tag + MK_SIZE, auth_tag, 16);

            var ret = new Omemo2EncryptionData(own_device_id);
            ret.ciphertext = ciphertext;
            ret.message_key = mk_with_tag;  /* 48 bytes: mk || auth_tag */
            return ret;
        }

        /**
         * Encrypt the full message and add to the MessageStanza.
         */
        public EncryptState encrypt(MessageStanza message, Jid self_jid, Gee.List<Jid> recipients, XmppStream stream) {
            EncryptState status = new EncryptState();
            if (!Plugin.ensure_context()) return status;
            if (message.to == null) return status;

            try {
                Omemo2EncryptionData enc_data = encrypt_plaintext(message.body);
                status = encrypt_key_to_recipients(enc_data, self_jid, recipients, stream);

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
            if (status.own_devices == 0 || status.other_devices == 0) return status;

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
            CiphertextMessage device_key = cipher.encrypt(encryption_data.message_key);
            address.device_id = 0;
            debug("OMEMO 2: Created encrypted key for %s/%d", jid.bare_jid.to_string(), device_id);

            encryption_data.add_device_key(jid, device_id, device_key.serialized, device_key.type == CiphertextType.PREKEY);
        }
    }
}
