using Gee;

namespace Xmpp.Xep.VCard {
private const string NS_URI = "vcard-temp";
private const string NS_URI_UPDATE = NS_URI + ":x:update";

public class VCardInfo : Object {
    public string? full_name { get; set; }
    public string? nickname { get; set; }
    public Gee.List<string> emails { get; set; default = new Gee.ArrayList<string>(); }
    public Gee.List<string> phones { get; set; default = new Gee.ArrayList<string>(); }
    public Gee.List<string> urls { get; set; default = new Gee.ArrayList<string>(); }
    public Gee.List<string> roles { get; set; default = new Gee.ArrayList<string>(); }
    public Gee.List<string> titles { get; set; default = new Gee.ArrayList<string>(); }
    public Gee.List<string> organizations { get; set; default = new Gee.ArrayList<string>(); }
    public string? description { get; set; }
    public string? birthday { get; set; }
    public string? adr_street { get; set; }
    public string? adr_locality { get; set; }
    public string? adr_pcode { get; set; }
    public string? adr_region { get; set; }
    public string? adr_country { get; set; }
    public Bytes? photo { get; set; }
    public string? photo_type { get; set; }

    public string? email { 
        owned get { return emails.size > 0 ? emails[0] : null; } 
        set { emails.clear(); if (value != null) emails.add(value); }
    }
    public string? phone { 
        owned get { return phones.size > 0 ? phones[0] : null; } 
        set { phones.clear(); if (value != null) phones.add(value); }
    }
    public string? url { 
        owned get { return urls.size > 0 ? urls[0] : null; } 
        set { urls.clear(); if (value != null) urls.add(value); }
    }
    public string? role { 
        owned get { return roles.size > 0 ? roles[0] : null; } 
        set { roles.clear(); if (value != null) roles.add(value); }
    }
    public string? title { 
        owned get { return titles.size > 0 ? titles[0] : null; } 
        set { titles.clear(); if (value != null) titles.add(value); }
    }
    public string? organization { 
        owned get { return organizations.size > 0 ? organizations[0] : null; } 
        set { organizations.clear(); if (value != null) organizations.add(value); }
    }

    public VCardInfo() {}

    public static VCardInfo from_node(StanzaNode node) {
        var vcard = new VCardInfo();
        // Debug: Print the entire vCard node structure
        print("Parsing vCard node: %s\n", node.to_string());

        vcard.full_name = node.get_subnode("FN")?.get_string_content();
        vcard.nickname = node.get_subnode("NICKNAME")?.get_string_content();
        vcard.birthday = node.get_subnode("BDAY")?.get_string_content();

        foreach (var email_node in node.get_subnodes("EMAIL")) {
            var userid = email_node.get_subnode("USERID")?.get_string_content();
            if (userid != null) vcard.emails.add(userid);
        }

        foreach (var tel_node in node.get_subnodes("TEL")) {
            var number = tel_node.get_subnode("NUMBER")?.get_string_content();
            if (number != null) vcard.phones.add(number);
        }
        
        foreach (var url_node in node.get_subnodes("URL")) {
            var url = url_node.get_string_content();
            if (url != null) vcard.urls.add(url);
        }

        foreach (var role_node in node.get_subnodes("ROLE")) {
            var role = role_node.get_string_content();
            if (role != null) vcard.roles.add(role);
        }

        foreach (var title_node in node.get_subnodes("TITLE")) {
            var title = title_node.get_string_content();
            if (title != null) vcard.titles.add(title);
        }

        foreach (var org_node in node.get_subnodes("ORG")) {
            var org_name = org_node.get_subnode("ORGNAME")?.get_string_content();
            if (org_name != null) vcard.organizations.add(org_name);
            
            foreach (var org_unit in org_node.get_subnodes("ORGUNIT")) {
                var unit = org_unit.get_string_content();
                if (unit != null) vcard.organizations.add(unit);
            }
        }

        // Address - iterate all ADR nodes to find one with data
        foreach (var adr_node in node.get_subnodes("ADR")) {
            var street = adr_node.get_subnode("STREET")?.get_string_content();
            var locality = adr_node.get_subnode("LOCALITY")?.get_string_content();
            var region = adr_node.get_subnode("REGION")?.get_string_content();
            var pcode = adr_node.get_subnode("PCODE")?.get_string_content();
            var country = adr_node.get_subnode("CTRY")?.get_string_content();
            
            // If we found a new address part, update our vcard
            // This is a simple merge strategy: last non-null wins, or first non-null wins?
            // Let's prefer the first one that has data, but fill in gaps from others.
            if (vcard.adr_street == null) vcard.adr_street = street;
            if (vcard.adr_locality == null) vcard.adr_locality = locality;
            if (vcard.adr_region == null) vcard.adr_region = region;
            if (vcard.adr_pcode == null) vcard.adr_pcode = pcode;
            if (vcard.adr_country == null) vcard.adr_country = country;
        }

        vcard.description = node.get_subnode("DESC")?.get_string_content();
        if (vcard.description == null) {
            vcard.description = node.get_subnode("NOTE")?.get_string_content();
        }

        var jabberid = node.get_subnode("JABBERID")?.get_string_content();
        if (jabberid != null) {
            // We don't have a field for this in VCardInfo yet, let's add it or put it in emails/impp?
            // For now, let's add it to emails if it looks like an email, or just ignore it if we don't have a place.
            // Actually, let's add a property for it.
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
        if (birthday != null) add_text_node(node, "BDAY", birthday);
        
        foreach (var email in emails) {
            var email_node = new StanzaNode.build("EMAIL", NS_URI);
            email_node.put_node(new StanzaNode.build("INTERNET", NS_URI));
            email_node.put_node(new StanzaNode.build("PREF", NS_URI));
            add_text_node(email_node, "USERID", email);
            node.put_node(email_node);
        }

        foreach (var phone in phones) {
            var tel_node = new StanzaNode.build("TEL", NS_URI);
            tel_node.put_node(new StanzaNode.build("VOICE", NS_URI));
            add_text_node(tel_node, "NUMBER", phone);
            node.put_node(tel_node);
        }

        if (adr_street != null || adr_locality != null || adr_region != null || adr_pcode != null || adr_country != null) {
            var adr_node = new StanzaNode.build("ADR", NS_URI);
            adr_node.put_node(new StanzaNode.build("HOME", NS_URI));
            if (adr_street != null) add_text_node(adr_node, "STREET", adr_street);
            if (adr_locality != null) add_text_node(adr_node, "LOCALITY", adr_locality);
            if (adr_region != null) add_text_node(adr_node, "REGION", adr_region);
            if (adr_pcode != null) add_text_node(adr_node, "PCODE", adr_pcode);
            if (adr_country != null) add_text_node(adr_node, "CTRY", adr_country);

            node.put_node(adr_node);

            // Add LABEL for compatibility
            var sb = new StringBuilder();
            if (adr_street != null) sb.append(adr_street).append("\n");
            if (adr_pcode != null) sb.append(adr_pcode).append(" ");
            if (adr_locality != null) sb.append(adr_locality).append("\n");
            if (adr_region != null) sb.append(adr_region).append("\n");
            if (adr_country != null) sb.append(adr_country);
            string label_str = sb.str.strip();
            if (label_str != "") {
                var label_node = new StanzaNode.build("LABEL", NS_URI);
                label_node.put_node(new StanzaNode.build("HOME", NS_URI));
                foreach (string line in label_str.split("\n")) {
                    if (line.strip() != "") {
                        label_node.put_node(new StanzaNode.build("LINE", NS_URI).put_node(new StanzaNode.text(line)));
                    }
                }
                node.put_node(label_node);
            }
        }

        foreach (var url in urls) add_text_node(node, "URL", url);
        foreach (var role in roles) add_text_node(node, "ROLE", role);
        foreach (var title in titles) add_text_node(node, "TITLE", title);
        
        if (description != null) add_text_node(node, "DESC", description);
        
        foreach (var org in organizations) {
            var org_node = new StanzaNode.build("ORG", NS_URI);
            add_text_node(org_node, "ORGNAME", org);
            node.put_node(org_node);
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
        iq_res = yield stream.get_module<Iq.Module>(Iq.Module.IDENTITY).send_iq_async(stream, iq);
    } catch (GLib.Error e) {
        warning("Failed to fetch vCard: %s", e.message);
        return null;
    }

    if (iq_res.is_error()) return null;
    
    // Debug: Print full IQ response
    print("vCard IQ response: %s\n", iq_res.stanza.to_string());

    var vcard_node = iq_res.stanza.get_subnode("vCard", NS_URI);
    if (vcard_node == null) return null;
    
    return VCardInfo.from_node(vcard_node);
}

public async void publish_vcard(XmppStream stream, VCardInfo vcard, Jid? to = null) throws Error {
    Iq.Stanza iq = new Iq.Stanza.set(vcard.to_node().add_self_xmlns());
    if (to != null) iq.to = to;
    yield stream.get_module<Iq.Module>(Iq.Module.IDENTITY).send_iq_async(stream, iq);
}

public async Bytes? fetch_image(XmppStream stream, Jid jid, string hash) {
    Iq.Stanza iq = new Iq.Stanza.get(new StanzaNode.build("vCard", NS_URI).add_self_xmlns()) { to=jid };
    Iq.Stanza iq_res;
    try {
        iq_res = yield stream.get_module<Iq.Module>(Iq.Module.IDENTITY).send_iq_async(stream, iq);
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
        stream.get_module<Presence.Module>(Presence.Module.IDENTITY).received_presence.connect(on_received_presence);
    }

    public override void detach(XmppStream stream) {
        stream.get_module<Presence.Module>(Presence.Module.IDENTITY).received_presence.disconnect(on_received_presence);
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
