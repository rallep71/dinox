using Gee;

namespace Xmpp.Xep.Search {

public const string NS_URI = "jabber:iq:search";

public class Module : XmppStreamModule {
    public static ModuleIdentity<Module> IDENTITY = new ModuleIdentity<Module>(NS_URI, "0055_search_module");

    public override void attach(XmppStream stream) {
    }

    public override void detach(XmppStream stream) {
    }

    public override string get_ns() {
        return IDENTITY.ns;
    }

    public override string get_id() {
        return IDENTITY.id;
    }

    public async DataForms.DataForm? get_fields(XmppStream stream, Jid jid) throws Error {
        StanzaNode query = new StanzaNode.build("query", NS_URI);
        Iq.Stanza iq = new Iq.Stanza.get(query);
        iq.to = jid;

        print("DEBUG: Sending search fields request to %s\n", jid.to_string());
        Iq.Stanza? result_iq = yield stream.get_module<Iq.Module>(Iq.Module.IDENTITY).send_iq_async(stream, iq);
        if (result_iq == null) {
            print("DEBUG: Search fields request returned null\n");
            return null;
        }
        if (result_iq.type_ == Xmpp.Stanza.TYPE_ERROR) {
            print("DEBUG: Search fields request returned error: %s\n", result_iq.stanza.to_string());
            return null;
        }
        print("DEBUG: Search fields response: %s\n", result_iq.stanza.to_string());

        StanzaNode? result_query = result_iq.stanza.get_subnode("query", NS_URI);
        if (result_query == null) return null;

        StanzaNode? x = result_query.get_subnode("x", DataForms.NS_URI);
        if (x != null) {
            return new DataForms.DataForm.from_node(x);
        }
        
        return null;
    }

    public async Gee.List<Item>? search(XmppStream stream, Jid jid, DataForms.DataForm form, bool legacy_only = false) throws Error {
        StanzaNode query = new StanzaNode.build("query", NS_URI);
        
        // Add legacy fields if present in the form
        foreach (var field in form.fields) {
            if (field.var == "nick" || field.var == "first" || field.var == "last" || field.var == "email") {
                var values = field.get_values();
                if (values.size > 0) {
                    var node = new StanzaNode.build(field.var, NS_URI);
                    node.put_node(new StanzaNode.text(values[0]));
                    query.put_node(node);
                }
            }
        }

        if (!legacy_only) {
            query.put_node(form.stanza_node);
        }
        
        Iq.Stanza iq = new Iq.Stanza.set(query);
        iq.to = jid;

        print("DEBUG: Sending search request to %s: %s\n", jid.to_string(), iq.stanza.to_string());
        Iq.Stanza? result_iq = yield stream.get_module<Iq.Module>(Iq.Module.IDENTITY).send_iq_async(stream, iq);
        if (result_iq == null) {
            print("DEBUG: Search request returned null\n");
            return null;
        }
        if (result_iq.type_ == Xmpp.Stanza.TYPE_ERROR) {
            print("DEBUG: Search request returned error: %s\n", result_iq.stanza.to_string());
            return null;
        }
        print("DEBUG: Search response: %s\n", result_iq.stanza.to_string());

        StanzaNode? result_query = result_iq.stanza.get_subnode("query", NS_URI);
        if (result_query == null) return null;

        StanzaNode? x = result_query.get_subnode("x", DataForms.NS_URI);
        if (x != null) {
            // x:data result
            var result_form = new DataForms.DataForm.from_node(x);
            var items = new ArrayList<Item>();
            
            foreach (var item_fields in result_form.items) {
                var item = new Item();
                foreach (var field in item_fields) {
                    var values = field.get_values();
                    if (field.var == "jid") {
                        try {
                            if (values.size > 0)
                                item.jid = new Jid(values[0]);
                        } catch (Error e) {}
                    } else {
                        if (values.size > 0) {
                            item.fields[field.var] = values[0];
                        }
                    }
                }
                if (item.jid != null) {
                    items.add(item);
                }
            }
            return items;
        }

        // Fallback: Try to parse legacy search results (direct children of query)
        var legacy_items = new ArrayList<Item>();
        foreach (var child in result_query.sub_nodes) {
            if (child.name == "item") {
                var jid_str = child.get_attribute("jid");
                if (jid_str != null) {
                    var item = new Item();
                    try {
                        item.jid = new Jid(jid_str);
                    } catch (Error e) { continue; }
                    
                    foreach (var field_node in child.sub_nodes) {
                        var content = field_node.get_string_content();
                        if (content != null) {
                            item.fields[field_node.name] = content;
                        }
                    }
                    legacy_items.add(item);
                }
            }
        }
        
        if (legacy_items.size > 0) {
            print("DEBUG: Found %d legacy search items\n", legacy_items.size);
            return legacy_items;
        }
        
        return null;
    }
}

public class Item {
    public Jid jid;
    public HashMap<string, string> fields = new HashMap<string, string>();
}

}
