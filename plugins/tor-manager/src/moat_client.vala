using GLib;
using Soup;

namespace Dino.Plugins.TorManager {

    public class BridgeClient : GLib.Object {
        private Session session;

        private const string BRIDGES_URL = "https://bridges.torproject.org/bridges";

        public BridgeClient() {
            session = new Session();
            session.user_agent = "Dino/0.4 (TorBridgeFetcher)";
            session.timeout = 30;
        }

        // Fetch bridges from HTTPS distributor (no CAPTCHA required)
        public async string[] fetch_bridges(string transport) throws Error {
            var msg = new Message("GET",
                BRIDGES_URL + "?transport=" + Uri.escape_string(transport));

            Bytes response_body = yield session.send_and_read_async(msg, Priority.DEFAULT, null);

            if (msg.status_code != 200) {
                throw new Error(Quark.from_string("BridgeClient"), (int)msg.status_code,
                    "HTTP Error: %u %s".printf(msg.status_code, msg.reason_phrase));
            }

            string html = (string)response_body.get_data();

            // Parse bridge lines from <div id="bridgelines">...<br/>...</div>
            int marker = html.index_of("id=\"bridgelines\"");
            if (marker < 0) {
                throw new Error(Quark.from_string("BridgeClient"), 3,
                    _("No bridge lines found in response. The server may be temporarily unavailable."));
            }

            int content_start = html.index_of(">", marker);
            if (content_start < 0) {
                throw new Error(Quark.from_string("BridgeClient"), 3,
                    _("Malformed response from bridge distributor"));
            }
            content_start++;

            int content_end = html.index_of("</div>", content_start);
            if (content_end < 0) {
                throw new Error(Quark.from_string("BridgeClient"), 3,
                    _("Malformed response from bridge distributor"));
            }

            string content = html.substring(content_start, content_end - content_start);

            // Decode HTML entities (server encodes + as &#43; in cert= values)
            content = decode_html_entities(content);

            // Normalize <br> variants and split
            content = content.replace("<br>", "<br/>");
            content = content.replace("<br />", "<br/>");
            string[] parts = content.split("<br/>");
            string[] results = {};

            foreach (string part in parts) {
                string line = part.strip();
                if (line.length > 0) {
                    results += line;
                }
            }

            return results;
        }

        private string decode_html_entities(string input) {
            string result = input;
            result = result.replace("&amp;", "&");
            result = result.replace("&lt;", "<");
            result = result.replace("&gt;", ">");
            result = result.replace("&quot;", "\"");
            result = result.replace("&#43;", "+");
            result = result.replace("&#61;", "=");
            result = result.replace("&#47;", "/");
            return result;
        }
    }
}
