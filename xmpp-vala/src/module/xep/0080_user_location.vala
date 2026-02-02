using Gee;

namespace Xmpp.Xep.UserLocation {

public const string NS_URI = "http://jabber.org/protocol/geoloc";

public class UserLocation : Object {
    public StanzaNode node;

    public UserLocation(StanzaNode node) {
        this.node = node;
    }

    public UserLocation.create() {
        this.node = new StanzaNode.build("geoloc", NS_URI);
        this.node.add_self_xmlns();
    }

    public double lat {
        get {
            string? val = node.get_subnode("lat")?.get_string_content();
            if (val != null) return double.parse(val);
            return 0.0;
        }
        set {
            set_field("lat", "%.6f".printf(value).replace(",", "."));
        }
    }

    public double lon {
        get {
            string? val = node.get_subnode("lon")?.get_string_content();
            if (val != null) return double.parse(val);
            return 0.0;
        }
        set {
            set_field("lon", "%.6f".printf(value).replace(",", "."));
        }
    }
    
    public double accuracy {
        get {
            string? val = node.get_subnode("accuracy")?.get_string_content();
            if (val != null) return double.parse(val);
            return 0.0;
        }
        set {
            set_field("accuracy", "%.6f".printf(value).replace(",", "."));
        }
    }
    
    public string? text {
        get { return node.get_subnode("text")?.get_string_content(); }
        set { set_field("text", value); }
    }

    public string? uri {
        get { return node.get_subnode("uri")?.get_string_content(); }
        set { set_field("uri", value); }
    }

    public DateTime? timestamp {
        owned get {
            string? val = node.get_subnode("timestamp")?.get_string_content();
            if (val != null) return Xmpp.Xep.DateTimeProfiles.parse_string(val);
            return null;
        }
        set {
            set_field("timestamp", value != null ? Xmpp.Xep.DateTimeProfiles.to_datetime(value) : null);
        }
    }

    // Helper to set simple text fields
    private void set_field(string name, string? val) {
        StanzaNode? sub = node.get_subnode(name);
        if (val == null) {
            if (sub != null) node.sub_nodes.remove(sub);
        } else {
            if (sub == null) {
                sub = new StanzaNode.build(name, NS_URI);
                node.put_node(sub);
            }
            sub.sub_nodes.clear();
            sub.put_node(new StanzaNode.text(val));
        }
    }
    
    public static UserLocation? from_message(MessageStanza message) {
        StanzaNode? node = message.stanza.get_subnode("geoloc", NS_URI);
        if (node != null) return new UserLocation(node);
        return null;
    }
}

}
