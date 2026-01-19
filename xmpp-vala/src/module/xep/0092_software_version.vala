using Gee;
using Xmpp;

namespace Xmpp.Xep.SoftwareVersion {
    private const string NS_URI = "jabber:iq:version";

    public class Module : XmppStreamModule, Iq.Handler {
        public static ModuleIdentity<Module> IDENTITY = new ModuleIdentity<Module>(NS_URI, "0092_software_version");
        
        public string client_name { get; private set; }
        public string client_version { get; private set; }
        public string client_os { get; private set; }

        public Module(string name, string version, string os) {
            this.client_name = name;
            this.client_version = version;
            this.client_os = os;
        }

        public override void attach(XmppStream stream) {
            stream.get_module<Iq.Module>(Iq.Module.IDENTITY).register_for_namespace(NS_URI, this);
            stream.get_module<ServiceDiscovery.Module>(ServiceDiscovery.Module.IDENTITY).add_feature(stream, NS_URI);
        }

        public override void detach(XmppStream stream) {
            stream.get_module<Iq.Module>(Iq.Module.IDENTITY).unregister_from_namespace(NS_URI, this);
            stream.get_module<ServiceDiscovery.Module>(ServiceDiscovery.Module.IDENTITY).remove_feature(stream, NS_URI);
        }

        public async void on_iq_get(XmppStream stream, Iq.Stanza iq) {
            StanzaNode query_node = new StanzaNode.build("query", NS_URI).add_self_xmlns();
            query_node.put_node(new StanzaNode.build("name", NS_URI).put_node(new StanzaNode.text(client_name)));
            query_node.put_node(new StanzaNode.build("version", NS_URI).put_node(new StanzaNode.text(client_version)));
            if (client_os != null) {
                query_node.put_node(new StanzaNode.build("os", NS_URI).put_node(new StanzaNode.text(client_os)));
            }
            
            stream.get_module<Iq.Module>(Iq.Module.IDENTITY).send_iq(stream, new Iq.Stanza.result(iq, query_node));
        }

        public async void on_iq_set(XmppStream stream, Iq.Stanza iq) {
             stream.get_module<Iq.Module>(Iq.Module.IDENTITY).send_iq(stream, new Iq.Stanza.error(iq, new ErrorStanza.build(ErrorStanza.TYPE_CANCEL, ErrorStanza.CONDITION_NOT_ALLOWED, null, null)));
        }

        public override string get_ns() { return NS_URI; }
        public override string get_id() { return IDENTITY.id; }
    }
}
