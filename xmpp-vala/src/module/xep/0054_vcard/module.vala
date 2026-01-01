namespace Xmpp.Xep.VCard {
private const string NS_URI = "vcard-temp";
private const string NS_URI_UPDATE = NS_URI + ":x:update";

public class VCardInfo : Object {
    public string? full_name { get; set; }
    public string? nickname { get; set; }
    public string? email { get; set; }
    public string? phone { get; set; }
    public string? url { get; set; }
    public string? role { get; set; }
    public string? title { get; set; }
    public string? organization { get; set; }
    public string? description { get; set; }
    public Bytes? photo { get; set; }
    public string? photo_type { get; set; }

    public VCardInfo() {}

    public static VCardInfo from_node(StanzaNode node) {
        var vcard = new VCardInfo();
        vcard.full_name = node.get_subnode("FN")?.get_string_content();
        vcard.nickname = node.get_subnode("NICKNAME")?.get_string_content();
        // Simplified EMAIL structure: EMAIL -> USERID
        var email_node = node.get_subnode("EMAIL");
        if (email_node != null) {
            vcard.email = email_node.get_subnode("USERID")?.get_string_content();
        }
        // Simplified TEL structure: TEL -> NUMBER
        var tel_node = node.get_subnode("TEL");
        if (tel_node != null) {
            vcard.phone = tel_node.get_subnode("NUMBER")?.get_string_content();
        }
        vcard.url = node.get_subnode("URL")?.get_string_content();
        vcard.role = node.get_subnode("ROLE")?.get_string_content();
        vcard.title = node.get_subnode("TITLE")?.get_string_content();
        vcard.description = node.get_subnode("DESC")?.get_string_content();
        
        var org = node.get_subnode("ORG");
        if (org != null) {
            vcard.organization = org.get_subnode("ORGNAME")?.get_string_content();
        }

        var photo = node.get_subnode("PHOTO");
        if (photo != null) {
            vcard.photo_type = photo.get_subnode("TYPE")?.get_string_content();
            string? binval = photo.get_subnode("BINVAL")?.get_string_content();
            if (binval != null) {
                // Remove whitespace from base64 string
                string clean_binval = "";
                foreach (string line in binval.split("\n")) {
                    clean_binval += line.strip();
                }
                vcard.photo = new Bytes.take(Base64.decode(clean_binval));
            }
        }
        return vcard;
    }

    private void add_text_node(StanzaNode parent, string name, string content) {
        var child = new StanzaNode.build(name, NS_URI);
        child.put_node(new StanzaNode.text(content));
        parent.put_node(child);
    }

    public StanzaNode to_node() {
        var node = new StanzaNode.build("vCard", NS_URI);
        if (full_name != null) add_text_node(node, "FN", full_name);
        if (nickname != null) add_text_node(node, "NICKNAME", nickname);
        if (email != null) {
            var email_node = new StanzaNode.build("EMAIL", NS_URI);
            email_node.put_node(new StanzaNode.build("INTERNET", NS_URI));
            email_node.put_node(new StanzaNode.build("PREF", NS_URI));
            add_text_node(email_node, "USERID", email);
            node.put_node(email_node);
        }
        if (phone != null) {
            var tel_node = new StanzaNode.build("TEL", NS_URI);
            tel_node.put_node(new StanzaNode.build("VOICE", NS_URI));
            add_text_node(tel_node, "NUMBER", phone);
            node.put_node(tel_node);
        }
        if (url != null) add_text_node(node, "URL", url);
        if (role != null) add_text_node(node, "ROLE", role);
        if (title != null) add_text_node(node, "TITLE", title);
        if (description != null) add_text_node(node, "DESC", description);
        
        if (organization != null) {
            var org = new StanzaNode.build("ORG", NS_URI);
            add_text_node(org, "ORGNAME", organization);
            node.put_node(org);
        }

        if (photo != null) {
            var photo_node = new StanzaNode.build("PHOTO", NS_URI);
            if (photo_type != null) add_text_node(photo_node, "TYPE", photo_type);
            add_text_node(photo_node, "BINVAL", Base64.encode(photo.get_data()));
            node.put_node(photo_node);
        }
        return node;
    }
}

public async VCardInfo? fetch_vcard(XmppStream stream, Jid? jid = null) {
    Iq.Stanza iq = new Iq.Stanza.get(new StanzaNode.build("vCard", NS_URI).add_self_xmlns());
    if (jid != null) iq.to = jid;
    
    Iq.Stanza iq_res;
    try {
        iq_res = yield stream.get_module(Iq.Module.IDENTITY).send_iq_async(stream, iq);
    } catch (GLib.Error e) {
        warning("Failed to fetch vCard: %s", e.message);
        return null;
    }

    if (iq_res.is_error()) return null;
    var vcard_node = iq_res.stanza.get_subnode("vCard", NS_URI);
    if (vcard_node == null) return null;
    
    return VCardInfo.from_node(vcard_node);
}

public async void publish_vcard(XmppStream stream, VCardInfo vcard) throws Error {
    Iq.Stanza iq = new Iq.Stanza.set(vcard.to_node().add_self_xmlns());
    yield stream.get_module(Iq.Module.IDENTITY).send_iq_async(stream, iq);
}

public async Bytes? fetch_image(XmppStream stream, Jid jid, string hash) {
    Iq.Stanza iq = new Iq.Stanza.get(new StanzaNode.build("vCard", NS_URI).add_self_xmlns()) { to=jid };
    Iq.Stanza iq_res;
    try {
        iq_res = yield stream.get_module(Iq.Module.IDENTITY).send_iq_async(stream, iq);
    } catch (GLib.Error e) {
        warning("Failed to fetch vCard image: %s", e.message);
        return null;
    }

    if (iq_res.is_error()) return null;
    string? res = iq_res.stanza.get_deep_string_content(@"$NS_URI:vCard", "PHOTO", "BINVAL");
    if (res == null) return null;
    Bytes content = new Bytes.take(Base64.decode(res));
    string sha1 = Checksum.compute_for_bytes(ChecksumType.SHA1, content);
    if (sha1 != hash) return null;

    return content;
}

public class Module : XmppStreamModule {
    public static ModuleIdentity<Module> IDENTITY = new ModuleIdentity<Module>(NS_URI, "0153_vcard_based_avatars");

    public signal void received_avatar_hash(XmppStream stream, Jid jid, string hash);

    public override void attach(XmppStream stream) {
        stream.get_module(Presence.Module.IDENTITY).received_presence.connect(on_received_presence);
    }

    public override void detach(XmppStream stream) {
        stream.get_module(Presence.Module.IDENTITY).received_presence.disconnect(on_received_presence);
    }

    public override string get_ns() { return NS_URI; }
    public override string get_id() { return IDENTITY.id; }

    private void on_received_presence(XmppStream stream, Presence.Stanza presence) {
        if (presence.type_ != Presence.Stanza.TYPE_AVAILABLE) {
            return;
        }
        StanzaNode? update_node = presence.stanza.get_subnode("x", NS_URI_UPDATE);
        if (update_node == null) return;
        StanzaNode? photo_node = update_node.get_subnode("photo", NS_URI_UPDATE);
        if (photo_node == null) return;
        string? sha1 = photo_node.get_string_content();
        if (sha1 == null) return;
        received_avatar_hash(stream, presence.from, sha1);
    }
}
}
