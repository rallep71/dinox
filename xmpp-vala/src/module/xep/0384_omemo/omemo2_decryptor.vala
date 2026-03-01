using Gee;
using Xmpp.Xep;
using Xmpp;

namespace Xmpp.Xep.Omemo {

    /**
     * OMEMO 2 decryptor — parses <encrypted xmlns='urn:xmpp:omemo:2'> stanzas.
     *
     * Key differences from legacy:
     * - Keys grouped by JID: <keys jid='alice@example.com'><key rid='...'/>
     * - No <iv> in XML (IV derived via HKDF from message key)
     * - Attribute 'kex' instead of 'prekey'
     * - Payload = AES-256-CBC(SCE) || HMAC-SHA-256[16]
     */
    public abstract class Omemo2Decryptor : XmppStreamModule {

        public static Xmpp.ModuleIdentity<Omemo2Decryptor> IDENTITY = new Xmpp.ModuleIdentity<Omemo2Decryptor>(NS_URI_V2, "0384_omemo2_decryptor");

        public abstract uint32 own_device_id { get; }

        /**
         * Decrypt the OMEMO 2 payload (AES-256-CBC + HMAC-SHA-256) then
         * parse SCE envelope to extract the message body.
         * @param ciphertext The full payload (ciphertext || HMAC[16])
         * @param message_key The 32-byte decrypted message key
         * @return The decrypted plaintext body
         */
        public abstract async string decrypt(uint8[] ciphertext, uint8[] message_key) throws GLib.Error;

        /**
         * Decrypt the per-device key using the Double Ratchet session.
         * @param data The parsed OMEMO 2 message data
         * @param from_jid The sender's JID
         * @return The decrypted 32-byte message key
         */
        public abstract uint8[] decrypt_key(Omemo2ParsedData data, Jid from_jid) throws GLib.Error;

        /**
         * Parse an <encrypted xmlns='urn:xmpp:omemo:2'> node.
         */
        public Omemo2ParsedData? parse_node(StanzaNode encrypted_node, Jid our_jid) {
            Omemo2ParsedData ret = new Omemo2ParsedData();

            StanzaNode? header_node = encrypted_node.get_subnode("header", NS_URI_V2);
            if (header_node == null) {
                warning("OMEMO 2: Can't parse: No header node");
                return null;
            }

            ret.sid = header_node.get_attribute_int("sid", -1);
            if (ret.sid == -1) {
                warning("OMEMO 2: Can't parse: No sid");
                return null;
            }

            /* Parse payload (contains ciphertext || hmac[16]) */
            string? payload_str = encrypted_node.get_deep_string_content("payload");
            if (payload_str != null) {
                ret.ciphertext = Base64.decode(payload_str);
            }

            /* Parse <keys jid='...'> groups — find our JID's keys */
            string our_bare_jid = our_jid.bare_jid.to_string();
            foreach (StanzaNode keys_node in header_node.get_subnodes("keys", NS_URI_V2)) {
                string? jid_attr = keys_node.get_attribute("jid");
                if (jid_attr == null) continue;

                /* Check if this keys group is for our JID */
                if (jid_attr == our_bare_jid) {
                    foreach (StanzaNode key_node in keys_node.get_subnodes("key", NS_URI_V2)) {
                        uint rid = key_node.get_attribute_uint("rid", 0);
                        if (rid == 0) continue;

                        debug("OMEMO 2: Is ours? rid=%u =? own=%u", rid, own_device_id);
                        if (rid == own_device_id) {
                            string? key_content = key_node.get_string_content();
                            if (key_content == null) continue;
                            uint8[] encrypted_key = Base64.decode(key_content);
                            bool is_kex = key_node.get_attribute_bool("kex", false);
                            ret.our_potential_encrypted_keys[new Bytes.take(encrypted_key)] = is_kex;
                        }
                    }
                }
            }

            return ret;
        }

        public override void attach(XmppStream stream) { }
        public override void detach(XmppStream stream) { }
        public override string get_ns() { return NS_URI_V2; }
        public override string get_id() { return IDENTITY.id; }
    }

    /**
     * Parsed OMEMO 2 message data.
     */
    public class Omemo2ParsedData {
        public int sid;
        public uint8[]? ciphertext;  /* payload = AES-CBC ciphertext || HMAC[16] */

        /** Map: encrypted_key_bytes → is_kex (pre-key exchange) */
        public HashMap<Bytes, bool> our_potential_encrypted_keys = new HashMap<Bytes, bool>();
    }
}
