using Gee;
using Xmpp.Xep.Pubsub;

namespace Xmpp.Xep.VCard4 {

public const string NS_URI = "urn:ietf:params:xml:ns:vcard-4.0";

public class VCard4 : Object {
    public StanzaNode node;

    public VCard4(StanzaNode node) {
        this.node = node;
    }

    public VCard4.create() {
        this.node = new StanzaNode.build("vcard", NS_URI);
        this.node.add_self_xmlns();
    }

    // Helper to get/set simple text fields wrapped in <text>
    // e.g. <fn><text>Value</text></fn>
    private string? get_text_property(string name) {
        StanzaNode? prop = node.get_subnode(name, NS_URI);
        if (prop == null) return null;
        StanzaNode? text = prop.get_subnode("text", NS_URI);
        if (text == null) return null;
        return text.get_string_content();
    }

    private void set_text_property(string name, string? val) {
        // Remove existing
        StanzaNode? existing = node.get_subnode(name, NS_URI);
        if (existing != null) node.sub_nodes.remove(existing);

        if (val != null && val != "") {
            StanzaNode prop = new StanzaNode.build(name, NS_URI);
            StanzaNode text = new StanzaNode.build("text", NS_URI);
            text.put_node(new StanzaNode.text(val));
            prop.put_node(text);
            node.put_node(prop);
        }
    }

    public string? full_name {
        owned get { return get_text_property("fn"); }
        set { set_text_property("fn", value); }
    }

    public string? nickname {
        owned get { return get_text_property("nickname"); }
        set { set_text_property("nickname", value); }
    }

    public string? email {
        owned get { return get_text_property("email"); }
        set { set_text_property("email", value); }
    }

    public string? tel {
        owned get { return get_text_property("tel"); }
        set { set_text_property("tel", value); }
    }

    public string? url {
        owned get { return get_text_property("url"); }
        set { set_text_property("url", value); }
    }

    public string? role {
        owned get { return get_text_property("role"); }
        set { set_text_property("role", value); }
    }

    public string? title {
        owned get { return get_text_property("title"); }
        set { set_text_property("title", value); }
    }

    public string? org {
        owned get { return get_text_property("org"); }
        set { set_text_property("org", value); }
    }

    public string? note {
        owned get { return get_text_property("note"); }
        set { set_text_property("note", value); }
    }
}

public class Module : XmppStreamModule {
    public static ModuleIdentity<Module> IDENTITY = new ModuleIdentity<Module>(NS_URI, "0292_vcard4");

    public signal void received_vcard(XmppStream stream, Jid jid, VCard4 vcard);

    public override void attach(XmppStream stream) {
        stream.get_module(Pubsub.Module.IDENTITY).add_filtered_notification(stream, NS_URI, on_pubsub_item, null, null);
    }

    public override void detach(XmppStream stream) {
        stream.get_module(Pubsub.Module.IDENTITY).remove_filtered_notification(stream, NS_URI);
    }

    private void on_pubsub_item(XmppStream stream, Jid jid, string? id, StanzaNode? item) {
        if (item == null) return;
        
        StanzaNode? vcard_node = item.get_subnode("vcard", NS_URI);
        if (vcard_node != null) {
            received_vcard(stream, jid, new VCard4(vcard_node));
        }
    }

    public async void publish(XmppStream stream, VCard4 vcard) {
        yield stream.get_module(Pubsub.Module.IDENTITY).publish(stream, null, NS_URI, "current", vcard.node);
    }

    public async VCard4? request(XmppStream stream, Jid jid) {
        Gee.List<StanzaNode>? items = yield stream.get_module(Pubsub.Module.IDENTITY).request_all(stream, jid, NS_URI);
        if (items == null || items.size == 0) return null;

        // There should be only one item
        StanzaNode item = items[0];
        StanzaNode? vcard_node = item.get_subnode("vcard", NS_URI);
        if (vcard_node != null) {
            return new VCard4(vcard_node);
        }
        return null;
    }

    public override string get_ns() { return NS_URI; }
    public override string get_id() { return IDENTITY.id; }
}

}
