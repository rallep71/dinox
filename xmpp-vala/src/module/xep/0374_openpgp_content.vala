using Gee;

namespace Xmpp.Xep.OpenPgpContent {
    
    // XEP-0374: OpenPGP for XMPP Instant Messaging
    // This defines the content elements for encrypted messages
    
    public const string NS_URI = "urn:xmpp:openpgp:0";
    public const string NS_URI_IM = "urn:xmpp:openpgp:im:0";  // Service Discovery feature for XEP-0374

    /**
     * Generate random padding for OpenPGP content elements (XEP-0374 §4).
     *
     * Returns a base64-encoded string of 16–64 random bytes sourced from
     * /dev/urandom (CSPRNG). The padding length is chosen uniformly using
     * rejection sampling to avoid modulo bias (Bug #16 fix: 256 % 49 ≠ 0).
     *
     * Shared by SigncryptElement, SignElement, and CryptElement.
     */
    internal static string generate_random_padding() {
        // Use CSPRNG for random padding (prevents traffic analysis)
        uint8[] bytes;
        try {
            var urandom = File.new_for_path("/dev/urandom");
            var stream = urandom.read();
            // Rejection sampling: discard values ≥ 245 (= 49*5) to get
            // a uniform distribution in [0, 48]. This avoids modulo bias
            // where values 0–10 would be ~20% more likely than 11–48.
            int length = 0;
            uint8[] len_buf = new uint8[1];
            do {
                stream.read(len_buf);
            } while (len_buf[0] >= 245);  // 49 * 5 = 245
            length = 16 + (int)(len_buf[0] % 49);  // uniform [16, 64]
            bytes = new uint8[length];
            stream.read(bytes);
            stream.close();
        } catch (Error e) {
            // Fallback for platforms without /dev/urandom
            int length = Random.int_range(16, 65);
            bytes = new uint8[length];
            for (int i = 0; i < length; i++) {
                bytes[i] = (uint8) Random.int_range(0, 256);
            }
        }
        return Base64.encode(bytes);
    }
    
    // The <signcrypt> element contains the signed and encrypted content
    public class SigncryptElement {
        public Jid? to { get; set; }
        public DateTime? time { get; set; }
        public string? rpad { get; set; }  // Random padding
        public StanzaNode? payload { get; set; }  // The actual content (typically <body>)
        
        public SigncryptElement() {
            this.time = new DateTime.now_utc();
            // Generate random padding (16-64 random bytes, base64 encoded)
            this.rpad = generate_random_padding();
        }
        
        public SigncryptElement.with_body(Jid recipient, string body_text) {
            this();
            this.to = recipient;
            
            // Create <body> payload
            this.payload = new StanzaNode.build("body", "jabber:client")
                .put_node(new StanzaNode.text(body_text));
        }
        
        public StanzaNode to_stanza_node() {
            var node = new StanzaNode.build("signcrypt", NS_URI)
                .add_self_xmlns();
            
            if (to != null) {
                node.put_node(new StanzaNode.build("to", NS_URI)
                    .put_attribute("jid", to.to_string()));
            }
            
            if (time != null) {
                node.put_node(new StanzaNode.build("time", NS_URI)
                    .put_attribute("stamp", time.format_iso8601()));
            }
            
            if (rpad != null) {
                node.put_node(new StanzaNode.build("rpad", NS_URI)
                    .put_node(new StanzaNode.text(rpad)));
            }
            
            if (payload != null) {
                node.put_node(new StanzaNode.build("payload", NS_URI)
                    .put_node(payload));
            }
            
            return node;
        }
        
        public static SigncryptElement? from_stanza_node(StanzaNode node) {
            if (node.name != "signcrypt" || node.ns_uri != NS_URI) {
                return null;
            }
            
            var element = new SigncryptElement();
            
            StanzaNode? to_node = node.get_subnode("to", NS_URI);
            if (to_node != null) {
                string? jid_str = to_node.get_attribute("jid");
                if (jid_str != null) {
                    try {
                        element.to = new Jid(jid_str);
                    } catch (Error e) {
                        warning("Invalid JID in signcrypt: %s", jid_str);
                    }
                }
            }
            
            StanzaNode? time_node = node.get_subnode("time", NS_URI);
            if (time_node != null) {
                string? stamp = time_node.get_attribute("stamp");
                if (stamp != null) {
                    element.time = new DateTime.from_iso8601(stamp, new TimeZone.utc());
                }
            }
            
            StanzaNode? rpad_node = node.get_subnode("rpad", NS_URI);
            if (rpad_node != null) {
                element.rpad = rpad_node.get_string_content();
            }
            
            StanzaNode? payload_node = node.get_subnode("payload", NS_URI);
            if (payload_node != null) {
                // Get first child of payload
                Gee.List<StanzaNode> children = payload_node.get_all_subnodes();
                if (children.size > 0) {
                    element.payload = children[0];
                }
            }
            
            return element;
        }
        
        public string? get_body_text() {
            if (payload == null) return null;
            if (payload.name == "body") {
                return payload.get_string_content();
            }
            return null;
        }
    }
    
    // The <sign> element for signed-only content (not encrypted)
    public class SignElement {
        public Jid? to { get; set; }
        public DateTime? time { get; set; }
        public string? rpad { get; set; }
        public StanzaNode? payload { get; set; }
        
        public SignElement() {
            this.time = new DateTime.now_utc();
            this.rpad = generate_random_padding();
        }
        
        public StanzaNode to_stanza_node() {
            var node = new StanzaNode.build("sign", NS_URI)
                .add_self_xmlns();
            
            if (to != null) {
                node.put_node(new StanzaNode.build("to", NS_URI)
                    .put_attribute("jid", to.to_string()));
            }
            
            if (time != null) {
                node.put_node(new StanzaNode.build("time", NS_URI)
                    .put_attribute("stamp", time.format_iso8601()));
            }
            
            if (rpad != null) {
                node.put_node(new StanzaNode.build("rpad", NS_URI)
                    .put_node(new StanzaNode.text(rpad)));
            }
            
            if (payload != null) {
                node.put_node(new StanzaNode.build("payload", NS_URI)
                    .put_node(payload));
            }
            
            return node;
        }
        
        public static SignElement? from_stanza_node(StanzaNode node) {
            if (node.name != "sign" || node.ns_uri != NS_URI) {
                return null;
            }
            
            var element = new SignElement();
            
            StanzaNode? to_node = node.get_subnode("to", NS_URI);
            if (to_node != null) {
                string? jid_str = to_node.get_attribute("jid");
                if (jid_str != null) {
                    try {
                        element.to = new Jid(jid_str);
                    } catch (Error e) {
                        warning("Invalid JID in sign: %s", jid_str);
                    }
                }
            }
            
            StanzaNode? time_node = node.get_subnode("time", NS_URI);
            if (time_node != null) {
                string? stamp = time_node.get_attribute("stamp");
                if (stamp != null) {
                    element.time = new DateTime.from_iso8601(stamp, new TimeZone.utc());
                }
            }
            
            StanzaNode? rpad_node = node.get_subnode("rpad", NS_URI);
            if (rpad_node != null) {
                element.rpad = rpad_node.get_string_content();
            }
            
            StanzaNode? payload_node = node.get_subnode("payload", NS_URI);
            if (payload_node != null) {
                Gee.List<StanzaNode> children = payload_node.get_all_subnodes();
                if (children.size > 0) {
                    element.payload = children[0];
                }
            }
            
            return element;
        }
    }
    
    // The <crypt> element for encrypted-only content (not signed)
    public class CryptElement {
        public Jid? to { get; set; }
        public DateTime? time { get; set; }
        public string? rpad { get; set; }
        public StanzaNode? payload { get; set; }
        
        public CryptElement() {
            this.time = new DateTime.now_utc();
            this.rpad = generate_random_padding();
        }
        
        public StanzaNode to_stanza_node() {
            var node = new StanzaNode.build("crypt", NS_URI)
                .add_self_xmlns();
            
            if (to != null) {
                node.put_node(new StanzaNode.build("to", NS_URI)
                    .put_attribute("jid", to.to_string()));
            }
            
            if (time != null) {
                node.put_node(new StanzaNode.build("time", NS_URI)
                    .put_attribute("stamp", time.format_iso8601()));
            }
            
            if (rpad != null) {
                node.put_node(new StanzaNode.build("rpad", NS_URI)
                    .put_node(new StanzaNode.text(rpad)));
            }
            
            if (payload != null) {
                node.put_node(new StanzaNode.build("payload", NS_URI)
                    .put_node(payload));
            }
            
            return node;
        }
        
        public static CryptElement? from_stanza_node(StanzaNode node) {
            if (node.name != "crypt" || node.ns_uri != NS_URI) {
                return null;
            }
            
            var element = new CryptElement();
            
            StanzaNode? to_node = node.get_subnode("to", NS_URI);
            if (to_node != null) {
                string? jid_str = to_node.get_attribute("jid");
                if (jid_str != null) {
                    try {
                        element.to = new Jid(jid_str);
                    } catch (Error e) {
                        warning("Invalid JID in crypt: %s", jid_str);
                    }
                }
            }
            
            StanzaNode? time_node = node.get_subnode("time", NS_URI);
            if (time_node != null) {
                string? stamp = time_node.get_attribute("stamp");
                if (stamp != null) {
                    element.time = new DateTime.from_iso8601(stamp, new TimeZone.utc());
                }
            }
            
            StanzaNode? rpad_node = node.get_subnode("rpad", NS_URI);
            if (rpad_node != null) {
                element.rpad = rpad_node.get_string_content();
            }
            
            StanzaNode? payload_node = node.get_subnode("payload", NS_URI);
            if (payload_node != null) {
                Gee.List<StanzaNode> children = payload_node.get_all_subnodes();
                if (children.size > 0) {
                    element.payload = children[0];
                }
            }
            
            return element;
        }
    }
    
    // The <openpgp> wrapper element used in XMPP stanzas
    public class OpenpgpElement {
        // The base64-encoded OpenPGP message
        public string openpgp_data { get; set; }
        
        public OpenpgpElement(string data) {
            this.openpgp_data = data;
        }
        
        public StanzaNode to_stanza_node() {
            return new StanzaNode.build("openpgp", NS_URI)
                .add_self_xmlns()
                .put_node(new StanzaNode.text(openpgp_data));
        }
        
        public static OpenpgpElement? from_stanza_node(StanzaNode node) {
            if (node.name != "openpgp" || node.ns_uri != NS_URI) {
                return null;
            }
            
            string? data = node.get_string_content();
            if (data == null) return null;
            
            return new OpenpgpElement(data);
        }
    }
    
    // Module for XEP-0374 message handling
    public class Module : XmppStreamModule {
        public static ModuleIdentity<Module> IDENTITY = new ModuleIdentity<Module>(NS_URI, "0374_openpgp_content");
        
        // Signal when an encrypted message is received
        public signal void encrypted_message_received(XmppStream stream, MessageStanza message, OpenpgpElement element);
        
        public override void attach(XmppStream stream) {
            // Add Service Discovery feature for XEP-0374 (OpenPGP for XMPP IM)
            stream.get_module<ServiceDiscovery.Module>(ServiceDiscovery.Module.IDENTITY).add_feature(stream, NS_URI_IM);
            
            stream.get_module<MessageModule>(MessageModule.IDENTITY).received_message.connect(on_received_message);
        }
        
        public override void detach(XmppStream stream) {
            stream.get_module<MessageModule>(MessageModule.IDENTITY).received_message.disconnect(on_received_message);
        }
        
        private void on_received_message(XmppStream stream, MessageStanza message) {
            StanzaNode? openpgp_node = message.stanza.get_subnode("openpgp", NS_URI);
            if (openpgp_node == null) return;
            
            OpenpgpElement? element = OpenpgpElement.from_stanza_node(openpgp_node);
            if (element == null) return;
            
            encrypted_message_received(stream, message, element);
        }
        
        // Create an encrypted message stanza
        public MessageStanza create_encrypted_message(Jid to, string openpgp_data, string message_type = MessageStanza.TYPE_CHAT) {
            MessageStanza message = new MessageStanza();
            message.to = to;
            message.type_ = message_type;
            
            // Add <openpgp> element
            var openpgp = new OpenpgpElement(openpgp_data);
            message.stanza.put_node(openpgp.to_stanza_node());
            
            // Add EME (Explicit Message Encryption) hint
            message.stanza.put_node(new StanzaNode.build("encryption", "urn:xmpp:eme:0")
                .add_self_xmlns()
                .put_attribute("namespace", NS_URI)
                .put_attribute("name", "OpenPGP for XMPP"));
            
            // Add fallback body for clients that don't support XEP-0374
            message.stanza.put_node(new StanzaNode.build("body", "jabber:client")
                .put_node(new StanzaNode.text("[This message is encrypted with OpenPGP for XMPP (XEP-0373/0374)]")));
            
            // Add store hint
            message.stanza.put_node(new StanzaNode.build("store", "urn:xmpp:hints")
                .add_self_xmlns());
            
            return message;
        }
        
        public override string get_ns() {
            return NS_URI;
        }
        
        public override string get_id() {
            return IDENTITY.id;
        }
    }
}
