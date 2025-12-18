using Gee;
using Xmpp;

namespace Xmpp.Xep.Stickers {

    public const string NS_URI = "urn:xmpp:stickers:0";

    public class StickerReference : Object {
        public string pack_id { get; set; }
        public string? jid { get; set; }
        public string? node { get; set; }
    }

    public static StickerReference? get_sticker(MessageStanza message) {
        StanzaNode? sticker_node = message.stanza.get_subnode("sticker", NS_URI);
        if (sticker_node == null) return null;

        string? pack = sticker_node.get_attribute("pack");
        if (pack == null || pack == "") return null;

        var sticker = new StickerReference();
        sticker.pack_id = pack;
        sticker.jid = sticker_node.get_attribute("jid");
        sticker.node = sticker_node.get_attribute("node");
        return sticker;
    }

    public static void set_sticker(MessageStanza message, StickerReference sticker) {
        var sticker_node = new StanzaNode.build("sticker", NS_URI).add_self_xmlns();
        sticker_node.put_attribute("pack", sticker.pack_id);
        if (sticker.jid != null) sticker_node.put_attribute("jid", sticker.jid);
        if (sticker.node != null) sticker_node.put_attribute("node", sticker.node);
        message.stanza.put_node(sticker_node);
    }
}
