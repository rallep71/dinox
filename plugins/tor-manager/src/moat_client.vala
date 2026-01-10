using GLib;
using Soup;
using Json;

namespace Dino.Plugins.TorManager {

    public class MoatClient : GLib.Object {
        private Session session;
        // Official Tor Project Moat Endpoint
        private const string MOAT_URL = "https://bridges.torproject.org/moat/fetch";
        
        public MoatClient() {
            session = new Session();
            session.user_agent = "Dino/0.4 (TorBridgeFetcher)";
            session.timeout = 15; // 15 seconds timeout
        }

        // Returns: base64 encoded image string (jpeg) and the challenge ID
        public async MoatChallenge fetch_challenge() throws Error {
            var msg = new Message("POST", MOAT_URL);
            
            // Build JSON Body: { "data": [ { "version": "0.1.0", "type": "client-transports", "supported_transports": ["obfs4"] } ] }
            var builder = new Json.Builder();
            builder.begin_object();
            builder.set_member_name("data");
            builder.begin_array();
            builder.begin_object();
            builder.set_member_name("version");
            builder.add_string_value("0.1.0");
            builder.set_member_name("type");
            builder.add_string_value("client-transports");
            builder.set_member_name("supported_transports");
            builder.begin_array();
            builder.add_string_value("obfs4");
            builder.end_array();
            builder.end_object();
            builder.end_array();
            builder.end_object();
            
            var generator = new Json.Generator();
            generator.set_root(builder.get_root());
            string body_data = generator.to_data(null);
            
            msg.set_request_body_from_bytes("application/vnd.api+json", new Bytes(body_data.data));
            
            // Send
            Bytes response_body = yield session.send_and_read_async(msg, Priority.DEFAULT, null);
            
            if (msg.status_code != 200) {
                throw new Error(Quark.from_string("MoatClient"), (int)msg.status_code, "HTTP Error: %u %s".printf(msg.status_code, msg.reason_phrase));
            }

            // Parse Response
            var parser = new Json.Parser();
            parser.load_from_data((string)response_body.get_data());
            
            var root = parser.get_root().get_object();
            var data_array = root.get_array_member("data");
            if (data_array.get_length() == 0) throw new Error(Quark.from_string("MoatClient"), 1, "Empty response from Moat");
            
            var data_item = data_array.get_object_element(0);
            string challenge = data_item.get_string_member("challenge");
            string image = data_item.get_string_member("image");
            
            return new MoatChallenge(challenge, image);
        }
        
        // Returns: List of bridge lines
        public async string[] check_solution(string challenge, string solution) throws Error {
            var msg = new Message("POST", "https://bridges.torproject.org/moat/check");
            
            // Body: { "data": [ { "id": "2", "type": "moat-challenge", "version": "0.1.0", "transport": "obfs4", "challenge": "...", "solution": "..." } ] }
            var builder = new Json.Builder();
            builder.begin_object();
            builder.set_member_name("data");
            builder.begin_array();
            builder.begin_object();
            builder.set_member_name("id");
            builder.add_string_value("2"); // Arbitrary ID
            builder.set_member_name("type");
            builder.add_string_value("moat-challenge");
            builder.set_member_name("version");
            builder.add_string_value("0.1.0");
            builder.set_member_name("transport");
            builder.add_string_value("obfs4");
            builder.set_member_name("challenge");
            builder.add_string_value(challenge);
            builder.set_member_name("solution");
            builder.add_string_value(solution);
            builder.end_object();
            builder.end_array();
            builder.end_object();
             
            var generator = new Json.Generator();
            generator.set_root(builder.get_root());
            string body_data = generator.to_data(null);
            
            msg.set_request_body_from_bytes("application/vnd.api+json", new Bytes(body_data.data));

            Bytes response_body = yield session.send_and_read_async(msg, Priority.DEFAULT, null);
            
            if (msg.status_code != 200) {
                 throw new Error(Quark.from_string("MoatClient"), (int)msg.status_code, "HTTP Error: %u %s".printf(msg.status_code, msg.reason_phrase));
            }
            
            // Parse Response: Looking for "bridges" array
            var parser = new Json.Parser();
            parser.load_from_data((string)response_body.get_data());
            var root = parser.get_root().get_object();
            var data_array = root.get_array_member("data");
             if (data_array.get_length() == 0) throw new Error(Quark.from_string("MoatClient"), 1, "Empty response from Moat Check");
             
            var data_item = data_array.get_object_element(0);
            
            // Check for errors
            if (data_item.has_member("error")) {
                 throw new Error(Quark.from_string("MoatClient"), 2, "Moat API Error: %s".printf(data_item.get_string_member("error")));
            }
            
            var bridges_node = data_item.get_member("bridges");
            if (bridges_node == null || bridges_node.get_node_type() != Json.NodeType.ARRAY) {
                 // Sometimes responses are tricky, but let's assume success path first
                 return {};
            }
            
            var bridges_array = bridges_node.get_array();
            string[] results = {};
            bridges_array.foreach_element((array, index, node) => {
                results += node.get_string();
            });
            
            return results;
        }
    }
    
    public class MoatChallenge {
        public string challenge; // The crypto challenge string
        public string image;     // Base64 encoded jpeg
        
        public MoatChallenge(string c, string i) {
            this.challenge = c;
            this.image = i;
        }
    }
}
