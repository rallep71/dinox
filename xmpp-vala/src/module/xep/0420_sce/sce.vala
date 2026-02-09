using Xmpp;

namespace Xmpp.Xep.Sce {

    public const string NS_URI = "urn:xmpp:sce:1";

    /**
     * Build an SCE envelope wrapping the given content nodes.
     *
     * XEP-0420: Stanza Content Encryption
     * <envelope xmlns='urn:xmpp:sce:1'>
     *   <content>...</content>
     *   <rpad>RANDOM</rpad>
     *   <from jid='...'/>
     *   <time stamp='...'/>
     * </envelope>
     */
    public class Envelope {
        public Gee.List<StanzaNode> content_nodes = new Gee.ArrayList<StanzaNode>();
        public string? from_jid;
        public string? to_jid;
        public DateTime? timestamp;

        public Envelope() {}

        public void add_content_node(StanzaNode node) {
            content_nodes.add(node);
        }

        /**
         * Serialize to XML bytes (UTF-8).
         */
        public uint8[] to_xml() throws IOError {
            StanzaNode envelope = new StanzaNode.build("envelope", NS_URI).add_self_xmlns();

            /* <content> with payload children */
            StanzaNode content = new StanzaNode.build("content", NS_URI);
            foreach (StanzaNode child in content_nodes) {
                content.put_node(child);
            }
            envelope.put_node(content);

            /* <rpad> random padding (XEP-0420 §4.1) */
            envelope.put_node(new StanzaNode.build("rpad", NS_URI)
                .put_node(new StanzaNode.text(generate_rpad())));

            /* Affix elements */
            if (from_jid != null) {
                envelope.put_node(new StanzaNode.build("from", NS_URI)
                    .put_attribute("jid", from_jid));
            }
            if (to_jid != null) {
                envelope.put_node(new StanzaNode.build("to", NS_URI)
                    .put_attribute("jid", to_jid));
            }
            if (timestamp != null) {
                envelope.put_node(new StanzaNode.build("time", NS_URI)
                    .put_attribute("stamp", timestamp.format_iso8601()));
            }

            string xml = envelope.to_xml();
            return xml.data;
        }

        /**
         * Parse an SCE envelope from XML bytes (async due to StanzaReader).
         */
        public static async Envelope? from_xml(uint8[] xml_bytes) {
            string xml_str = (string) xml_bytes;

            /* Parse the <envelope> using StanzaReader from buffer */
            StanzaNode? envelope_node = null;
            try {
                var reader = new StanzaReader.for_string(xml_str);
                envelope_node = yield reader.read_stanza_node();
            } catch (IOError e) {
                warning("SCE: Failed to parse envelope XML: %s", e.message);
                return null;
            }

            if (envelope_node == null) return null;
            if (envelope_node.name != "envelope") {
                warning("SCE: Root element is not <envelope>");
                return null;
            }

            Envelope env = new Envelope();

            /* Parse <content> children */
            StanzaNode? content_node = envelope_node.get_subnode("content", NS_URI);
            if (content_node != null) {
                foreach (StanzaNode child in content_node.get_all_subnodes()) {
                    env.content_nodes.add(child);
                }
            }

            /* Parse affix elements */
            StanzaNode? from_node = envelope_node.get_subnode("from", NS_URI);
            if (from_node != null) {
                env.from_jid = from_node.get_attribute("jid");
            }

            StanzaNode? to_node = envelope_node.get_subnode("to", NS_URI);
            if (to_node != null) {
                env.to_jid = to_node.get_attribute("jid");
            }

            StanzaNode? time_node = envelope_node.get_subnode("time", NS_URI);
            if (time_node != null) {
                string? stamp = time_node.get_attribute("stamp");
                if (stamp != null) {
                    env.timestamp = new DateTime.from_iso8601(stamp, new TimeZone.utc());
                }
            }

            return env;
        }

        /**
         * Get the <body> text from content nodes, if present.
         */
        public string? get_body() {
            foreach (StanzaNode node in content_nodes) {
                if (node.name == "body") {
                    return node.get_string_content();
                }
            }
            return null;
        }

        /**
         * Generate random padding string (1-200 random printable chars).
         */
        private static string generate_rpad() {
            int len = 1 + (int)(GLib.Random.next_int() % 200);
            var sb = new GLib.StringBuilder.sized(len);
            for (int i = 0; i < len; i++) {
                /* Printable ASCII 0x20-0x7E */
                char c = (char)(0x20 + (GLib.Random.next_int() % 95));
                sb.append_c(c);
            }
            return sb.str;
        }
    }

    /**
     * Convenience: Build an SCE envelope for a simple text message.
     */
    public Envelope build_message_envelope(string body_text, Jid from_jid, Jid? to_jid = null) {
        Envelope env = new Envelope();

        StanzaNode body_node = new StanzaNode.build("body", "jabber:client")
            .add_self_xmlns()
            .put_node(new StanzaNode.text(body_text));
        env.add_content_node(body_node);

        env.from_jid = from_jid.to_string();
        if (to_jid != null) {
            env.to_jid = to_jid.to_string();
        }
        env.timestamp = new DateTime.now_utc();

        return env;
    }
}
