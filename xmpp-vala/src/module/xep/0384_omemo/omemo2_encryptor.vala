using Gee;
using Xmpp.Xep;
using Xmpp;

namespace Xmpp.Xep.Omemo {

    /**
     * OMEMO 2 (XEP-0384 v0.8+) namespace and PEP nodes.
     */
    public const string NS_URI_V2 = "urn:xmpp:omemo:2";
    public const string NODE_DEVICELIST_V2 = NS_URI_V2 + ":devices";
    public const string NODE_BUNDLES_V2 = NS_URI_V2 + ":bundles";

    /**
     * OMEMO 2 encryptor — builds <encrypted xmlns='urn:xmpp:omemo:2'> stanzas.
     *
     * Key difference from legacy: keys are grouped by JID:
     * <encrypted xmlns='urn:xmpp:omemo:2'>
     *   <header sid='12345'>
     *     <keys jid='alice@example.com'>
     *       <key rid='31415' kex='true'>base64</key>
     *     </keys>
     *     <keys jid='bob@example.com'>
     *       <key rid='27182'>base64</key>
     *     </keys>
     *   </header>
     *   <payload>base64</payload>
     * </encrypted>
     */
    public abstract class Omemo2Encryptor : XmppStreamModule {

        public static Xmpp.ModuleIdentity<Omemo2Encryptor> IDENTITY = new Xmpp.ModuleIdentity<Omemo2Encryptor>(NS_URI_V2, "0384_omemo2_encryptor");

        public abstract uint32 own_device_id { get; }

        /**
         * Encrypt plaintext into SCE envelope, then into OMEMO 2 payload.
         * Returns Omemo2EncryptionData with ciphertext, IV, and empty key lists.
         */
        public abstract Omemo2EncryptionData encrypt_plaintext(string plaintext) throws GLib.Error;

        /**
         * Encrypt the message key to a specific device of a given JID.
         */
        public abstract void encrypt_key(Omemo2EncryptionData encryption_data, Jid jid, int32 device_id) throws GLib.Error;

        /**
         * Encrypt the message key to all known devices of a recipient.
         */
        public abstract EncryptionResult encrypt_key_to_recipient(XmppStream stream, Omemo2EncryptionData enc_data, Jid recipient) throws GLib.Error;

        public override void attach(XmppStream stream) { }
        public override void detach(XmppStream stream) { }
        public override string get_ns() { return NS_URI_V2; }
        public override string get_id() { return IDENTITY.id; }
    }

    /**
     * OMEMO 2 encryption data — holds per-message crypto material and
     * builds the <encrypted> XML node with JID-grouped keys.
     */
    public class Omemo2EncryptionData {
        public uint32 own_device_id;
        public uint8[] ciphertext;  /* AES-256-CBC encrypted SCE envelope + HMAC */
        public uint8[] message_key; /* 32-byte random key (encrypted per device) */
        public uint8[] iv;          /* Derived from HKDF, not transmitted separately */

        /** Map: JID string → list of <key> nodes for that JID */
        public HashMap<string, ArrayList<StanzaNode>> keys_by_jid = new HashMap<string, ArrayList<StanzaNode>>();

        public Omemo2EncryptionData(uint32 own_device_id) {
            this.own_device_id = own_device_id;
        }

        /**
         * Add an encrypted key for a specific device of a JID.
         * @param jid The bare JID of the recipient
         * @param device_id The device rid
         * @param device_key The encrypted key||hmac (48 bytes encrypted via Double Ratchet)
         * @param kex Whether this used a pre-key (key exchange)
         */
        public void add_device_key(Jid jid, int device_id, uint8[] device_key, bool kex) {
            string jid_str = jid.bare_jid.to_string();
            if (!keys_by_jid.has_key(jid_str)) {
                keys_by_jid[jid_str] = new ArrayList<StanzaNode>();
            }

            StanzaNode key_node = new StanzaNode.build("key", NS_URI_V2)
                    .put_attribute("rid", device_id.to_string())
                    .put_node(new StanzaNode.text(Base64.encode(device_key)));
            if (kex) {
                key_node.put_attribute("kex", "true");
            }
            keys_by_jid[jid_str].add(key_node);
        }

        /**
         * Build the <encrypted xmlns='urn:xmpp:omemo:2'> stanza node.
         */
        public StanzaNode get_encrypted_node() {
            StanzaNode encrypted_node = new StanzaNode.build("encrypted", NS_URI_V2).add_self_xmlns();

            /* <header sid='...'> */
            StanzaNode header_node = new StanzaNode.build("header", NS_URI_V2)
                    .put_attribute("sid", own_device_id.to_string());
            encrypted_node.put_node(header_node);

            /* <keys jid='...'> grouped */
            foreach (var entry in keys_by_jid.entries) {
                StanzaNode keys_node = new StanzaNode.build("keys", NS_URI_V2)
                        .put_attribute("jid", entry.key);
                foreach (StanzaNode key_node in entry.value) {
                    keys_node.put_node(key_node);
                }
                header_node.put_node(keys_node);
            }

            /* <payload> */
            if (ciphertext != null && ciphertext.length > 0) {
                StanzaNode payload_node = new StanzaNode.build("payload", NS_URI_V2)
                        .put_node(new StanzaNode.text(Base64.encode(ciphertext)));
                encrypted_node.put_node(payload_node);
            }

            return encrypted_node;
        }
    }
}
