namespace Xmpp.Xep.MessageRetraction {

    public const string NS_URI = "urn:xmpp:message-retract:1";
    public const string NS_URI_0 = "urn:xmpp:message-retract:0";
    public const string NS_FASTEN = "urn:xmpp:fasten:0";

    public static string? get_retract_id(MessageStanza message) {
        // Fastening (XEP-0422) support
        StanzaNode? apply_to = message.stanza.get_subnode("apply-to", NS_FASTEN);
        if (apply_to != null) {
            bool has_retract_v1 = apply_to.get_subnode("retract", NS_URI) != null;
            bool has_retract_v0 = apply_to.get_subnode("retract", NS_URI_0) != null;
            
            if (has_retract_v1 || has_retract_v0) {
                string? id = apply_to.get_attribute("id");
                if (id != null) return id;
                
                // Fallback: If ID is missing on apply-to, check the internal retract element
                // (Some clients might put it there incorrectly, but we should handle it)
                if (has_retract_v1) {
                    return apply_to.get_subnode("retract", NS_URI).get_attribute("id");
                }
                if (has_retract_v0) {
                    return apply_to.get_subnode("retract", NS_URI_0).get_attribute("id");
                }
            }
        }

        // Legacy / Direct child support
        // We check explicit namespaces to avoid ambiguity
        StanzaNode? direct_retract_v1 = message.stanza.get_subnode("retract", NS_URI);
        if (direct_retract_v1 != null) {
            return direct_retract_v1.get_attribute("id");
        }

        StanzaNode? direct_retract_v0 = message.stanza.get_subnode("retract", NS_URI_0);
        if (direct_retract_v0 != null) {
            return direct_retract_v0.get_attribute("id");
        }

        return null;
    }

    public static void set_retract_id(MessageStanza message, string message_id) {
        if (message_id == null) return;
        
        // 1. Standard: XEP-0422 Fastening with Retract V1 (Current Standard)
        // Expected by modern clients (Conversations, Gajim, etc.)
        StanzaNode apply_to = new StanzaNode.build("apply-to", NS_FASTEN);
        apply_to.add_self_xmlns();
        apply_to.put_attribute("id", message_id);
        
        StanzaNode retract_v1 = new StanzaNode.build("retract", NS_URI);
        retract_v1.add_self_xmlns();
        apply_to.put_node(retract_v1);
        
        message.stanza.put_node(apply_to);

        // 2. Legacy Fallback: Direct Child with Retract V1 (Legacy style)
        // Monal seems to require the V1 namespace ('urn:xmpp:message-retract:1') as a direct child.
        // Even though V0 is technically the 'legacy' draft, mostly implemented clients use V1 in the legacy position.
        StanzaNode retract_legacy = new StanzaNode.build("retract", NS_URI);
        retract_legacy.add_self_xmlns();
        retract_legacy.put_attribute("id", message_id);
        
        message.stanza.put_node(retract_legacy);
    }

    public class Module : XmppStreamModule {
        public static ModuleIdentity<Module> IDENTITY = new ModuleIdentity<Module>(NS_URI, "0424_message_retraction");

        public override void attach(XmppStream stream) {
            stream.get_module<ServiceDiscovery.Module>(ServiceDiscovery.Module.IDENTITY).add_feature(stream, NS_URI);
        }

        public override void detach(XmppStream stream) {
            stream.get_module<ServiceDiscovery.Module>(ServiceDiscovery.Module.IDENTITY).remove_feature(stream, NS_URI);
        }

        public override string get_ns() { return NS_URI; }

        public override string get_id() { return IDENTITY.id; }
    }
}
