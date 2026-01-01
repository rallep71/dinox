using Gee;
using Xmpp.Xep.Pubsub;

namespace Xmpp.Xep.VCard4 {

public const string NS_URI = "urn:ietf:params:xml:ns:vcard-4.0";
public const string NODE_URI_LEGACY = "urn:xmpp:vcard4";

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
        
        // Try direct content first (some clients might do this)
        var val = prop.get_string_content();
        if (val != null && val != "") return val;

        StanzaNode? text = prop.get_subnode("text", NS_URI);
        if (text == null) return null;
        return text.get_string_content();
    }

    private Gee.List<string> get_text_properties(string name) {
        var list = new Gee.ArrayList<string>();
        foreach (var prop in node.get_subnodes(name, NS_URI)) {
            // Try direct content first
            var val = prop.get_string_content();
            if (val != null && val != "") {
                list.add(val);
                continue;
            }

            var text = prop.get_subnode("text", NS_URI);
            if (text != null) {
                val = text.get_string_content();
                if (val != null) list.add(val);
            }
        }
        return list;
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

    // Helper for URI properties (e.g. <url><uri>http://...</uri></url>)
    private string? get_uri_property(string name) {
        StanzaNode? prop = node.get_subnode(name, NS_URI);
        if (prop == null) return null;
        StanzaNode? uri = prop.get_subnode("uri", NS_URI);
        if (uri == null) return null;
        return uri.get_string_content();
    }

    private Gee.List<string> get_uri_properties(string name) {
        var list = new Gee.ArrayList<string>();
        foreach (var prop in node.get_subnodes(name, NS_URI)) {
            var uri = prop.get_subnode("uri", NS_URI);
            if (uri != null) {
                var val = uri.get_string_content();
                if (val != null) list.add(val);
            }
        }
        return list;
    }

    private void set_uri_property(string name, string? val) {
        StanzaNode? existing = node.get_subnode(name, NS_URI);
        if (existing != null) node.sub_nodes.remove(existing);

        if (val != null && val != "") {
            StanzaNode prop = new StanzaNode.build(name, NS_URI);
            StanzaNode uri = new StanzaNode.build("uri", NS_URI);
            uri.put_node(new StanzaNode.text(val));
            prop.put_node(uri);
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
    public Gee.List<string> emails { owned get { return get_text_properties("email"); } }

    public string? tel {
        owned get { return get_text_property("tel"); }
        set { set_text_property("tel", value); }
    }
    public Gee.List<string> tels { owned get { return get_text_properties("tel"); } }

    public string? url {
        owned get { return get_uri_property("url"); }
        set { set_uri_property("url", value); }
    }
    public Gee.List<string> urls { owned get { return get_uri_properties("url"); } }

    public string? role {
        owned get { return get_text_property("role"); }
        set { set_text_property("role", value); }
    }
    public Gee.List<string> roles { owned get { return get_text_properties("role"); } }

    public string? title {
        owned get { return get_text_property("title"); }
        set { set_text_property("title", value); }
    }
    public Gee.List<string> titles { owned get { return get_text_properties("title"); } }

    public string? org {
        owned get { return get_text_property("org"); }
        set { set_text_property("org", value); }
    }
    public Gee.List<string> orgs { owned get { return get_text_properties("org"); } }

    public string? bday {
        owned get { 
            var val = get_text_property("bday"); 
            if (val != null) return val;
            
            // Check for <date> or <date-time>
            StanzaNode? prop = node.get_subnode("bday", NS_URI);
            if (prop != null) {
                StanzaNode? date = prop.get_subnode("date", NS_URI);
                if (date != null) return date.get_string_content();
                
                StanzaNode? datetime = prop.get_subnode("date-time", NS_URI);
                if (datetime != null) return datetime.get_string_content();
            }
            return null;
        }
        set { 
            // Remove existing
            StanzaNode? existing = node.get_subnode("bday", NS_URI);
            if (existing != null) node.sub_nodes.remove(existing);

            if (value != null && value != "") {
                StanzaNode prop = new StanzaNode.build("bday", NS_URI);
                // Assume date for now, as it's most common for birthdays
                StanzaNode date = new StanzaNode.build("date", NS_URI);
                date.put_node(new StanzaNode.text(value));
                prop.put_node(date);
                node.put_node(prop);
            }
        }
    }

    public string? tz {
        owned get { return get_text_property("tz"); }
        set { set_text_property("tz", value); }
    }

    public string? impp {
        owned get { return get_uri_property("impp"); }
        set { set_uri_property("impp", value); }
    }
    public Gee.List<string> impps { owned get { return get_uri_properties("impp"); } }

    public string? note {
        owned get { return get_text_property("note"); }
        set { set_text_property("note", value); }
    }

    // Gender field
    private string? get_gender_property() {
        StanzaNode? gender = node.get_subnode("gender", NS_URI);
        if (gender == null) return null;
        
        // Try <sex> child
        StanzaNode? sex = gender.get_subnode("sex", NS_URI);
        if (sex != null) {
            var val = sex.get_string_content();
            if (val != null && val != "") return val;
        }
        
        // Fallback: maybe direct content?
        return gender.get_string_content();
    }

    private void set_gender_property(string? val) {
        StanzaNode? existing = node.get_subnode("gender", NS_URI);
        if (existing != null) node.sub_nodes.remove(existing);

        if (val != null && val != "") {
            StanzaNode gender = new StanzaNode.build("gender", NS_URI);
            StanzaNode sex = new StanzaNode.build("sex", NS_URI);
            sex.put_node(new StanzaNode.text(val));
            gender.put_node(sex);
            node.put_node(gender);
        }
    }

    public string? gender {
        owned get { return get_gender_property(); }
        set { set_gender_property(value); }
    }

    // Address fields
    private string? get_adr_property(string name) {
        // Iterate all ADR nodes to find one with the requested property
        foreach (var adr in node.get_subnodes("adr", NS_URI)) {
            StanzaNode? prop = adr.get_subnode(name, NS_URI);
            if (prop != null) {
                // Try direct content first (correct for vCard4 XML)
                var val = prop.get_string_content();
                if (val != null && val != "") return val;
                
                // Fallback: check for <text> child (incorrect but maybe some clients do it?)
                StanzaNode? text = prop.get_subnode("text", NS_URI);
                if (text != null) {
                    val = text.get_string_content();
                    if (val != null && val != "") return val;
                }
            }
        }
        return null;
    }

    private void set_adr_property(string name, string? val) {
        StanzaNode? adr = node.get_subnode("adr", NS_URI);
        if (adr == null) {
            if (val == null || val == "") return;
            adr = new StanzaNode.build("adr", NS_URI);
            
            // Add parameters: <parameters /> (empty, like "test" user)
            StanzaNode params = new StanzaNode.build("parameters", NS_URI);
            adr.put_node(params);
            
            node.put_node(adr);
        }
        
        StanzaNode? existing = adr.get_subnode(name, NS_URI);
        if (existing != null) adr.sub_nodes.remove(existing);

        if (val != null && val != "") {
            StanzaNode prop = new StanzaNode.build(name, NS_URI);
            // Direct text content, no <text> wrapper, to match "test" user format
            prop.put_node(new StanzaNode.text(val));
            adr.put_node(prop);
        }
    }

    public string? adr_street {
        owned get { return get_adr_property("street"); }
        set { set_adr_property("street", value); }
    }
    public string? adr_locality {
        owned get { return get_adr_property("locality"); }
        set { set_adr_property("locality", value); }
    }
    public string? adr_pcode {
        owned get { return get_adr_property("code"); }
        set { set_adr_property("code", value); }
    }
    public string? adr_pobox {
        owned get { return get_adr_property("pobox"); }
        set { set_adr_property("pobox", value); }
    }
    public string? adr_region {
        owned get { return get_adr_property("region"); }
        set { set_adr_property("region", value); }
    }
    public string? adr_country {
        owned get { return get_adr_property("country"); }
        set { set_adr_property("country", value); }
    }
}

public class Module : XmppStreamModule {
    public static ModuleIdentity<Module> IDENTITY = new ModuleIdentity<Module>(NS_URI, "0292_vcard4");

    public signal void received_vcard(XmppStream stream, Jid jid, VCard4 vcard);

    public override void attach(XmppStream stream) {
        stream.get_module(Pubsub.Module.IDENTITY).add_filtered_notification(stream, NS_URI, on_pubsub_item, null, null);
        stream.get_module(Pubsub.Module.IDENTITY).add_filtered_notification(stream, NODE_URI_LEGACY, on_pubsub_item, null, null);
    }

    public override void detach(XmppStream stream) {
        stream.get_module(Pubsub.Module.IDENTITY).remove_filtered_notification(stream, NS_URI);
        stream.get_module(Pubsub.Module.IDENTITY).remove_filtered_notification(stream, NODE_URI_LEGACY);
    }

    private void on_pubsub_item(XmppStream stream, Jid jid, string? id, StanzaNode? item) {
        if (item == null) return;
        
        StanzaNode? vcard_node = item.get_subnode("vcard", NS_URI);
        if (vcard_node == null) vcard_node = item.get_subnode("vcard", NODE_URI_LEGACY);
        
        if (vcard_node != null) {
            received_vcard(stream, jid, new VCard4(vcard_node));
        }
    }

    public async bool publish(XmppStream stream, VCard4 vcard, Pubsub.PublishOptions? options = null) {
        var pubsub = stream.get_module(Pubsub.Module.IDENTITY);
        if (pubsub == null) {
            warning("VCard4: Pubsub module not found");
            return false;
        }

        print("VCard4: Publishing to standard node %s\n", NS_URI);
        bool res1 = yield pubsub.publish(stream, null, NS_URI, "current", vcard.node, options);
        print("VCard4: Standard publish result: %s\n", res1.to_string());
        
        print("VCard4: Publishing to legacy node %s\n", NODE_URI_LEGACY);
        // Also publish to legacy node for compatibility
        bool res2 = yield pubsub.publish(stream, null, NODE_URI_LEGACY, "current", vcard.node, options);
        print("VCard4: Legacy publish result: %s\n", res2.to_string());
        
        return res1 || res2;
    }

    public async VCard4? request(XmppStream stream, Jid jid) {
        var vcard = yield request_node(stream, jid, NS_URI);
        if (vcard != null) return vcard;
        
        return yield request_node(stream, jid, NODE_URI_LEGACY);
    }

    private async VCard4? request_node(XmppStream stream, Jid jid, string node) {
        Gee.List<StanzaNode>? items = yield stream.get_module(Pubsub.Module.IDENTITY).request_all(stream, jid, node);
        if (items == null || items.size == 0) return null;

        // There should be only one item
        StanzaNode item = items[0];
        StanzaNode? vcard_node = item.get_subnode("vcard", NS_URI);
        if (vcard_node == null) vcard_node = item.get_subnode("vcard", NODE_URI_LEGACY);
        
        if (vcard_node != null) {
            return new VCard4(vcard_node);
        }
        return null;
    }

    public override string get_ns() { return NS_URI; }
    public override string get_id() { return IDENTITY.id; }
}

}
