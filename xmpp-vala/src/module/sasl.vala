namespace Xmpp.Sasl {
    private const string NS_URI = "urn:ietf:params:xml:ns:xmpp-sasl";

    public class Flag : XmppStreamFlag {
        public static FlagIdentity<Flag> IDENTITY = new FlagIdentity<Flag>(NS_URI, "sasl");
        public string mechanism;
        public string name;
        public string password;
        public string client_nonce;
        public uint8[] server_signature;
        public string gs2_header = "n,,";
        public uint8[]? channel_binding_data;
        public bool finished = false;

        public override string get_ns() { return NS_URI; }
        public override string get_id() { return IDENTITY.id; }
    }

    namespace Mechanism {
        public const string PLAIN = "PLAIN";
        public const string SCRAM_SHA_1 = "SCRAM-SHA-1";
        public const string SCRAM_SHA_1_PLUS = "SCRAM-SHA-1-PLUS";
        public const string SCRAM_SHA_256 = "SCRAM-SHA-256";
        public const string SCRAM_SHA_256_PLUS = "SCRAM-SHA-256-PLUS";
        public const string SCRAM_SHA_512 = "SCRAM-SHA-512";
        public const string SCRAM_SHA_512_PLUS = "SCRAM-SHA-512-PLUS";
    }

    public class Module : XmppStreamNegotiationModule {
        public static ModuleIdentity<Module> IDENTITY = new ModuleIdentity<Module>(NS_URI, "sasl");

        public string name { get; set; }
        public string password { get; set; }
        public bool require_channel_binding { get; set; default = false; }
        public bool use_full_name = false;

        public signal void received_auth_failure(XmppStream stream, StanzaNode node);

        public Module(string name, string password) {
            this.name = name;
            this.password = password;
        }

        public override void attach(XmppStream stream) {
            stream.received_features_node.connect(this.received_features_node);
            stream.received_nonza.connect(this.received_nonza);
        }

        public override void detach(XmppStream stream) {
            stream.received_features_node.disconnect(this.received_features_node);
            stream.received_nonza.disconnect(this.received_nonza);
        }

        private static size_t SHA1_SIZE = 20;

        private static uint8[] sha1(uint8[] data) {
            Checksum checksum = new Checksum(ChecksumType.SHA1);
            checksum.update(data, data.length);
            uint8[] res = new uint8[SHA1_SIZE];
            checksum.get_digest(res, ref SHA1_SIZE);
            return res;
        }

        private static uint8[] hmac_sha1(uint8[] key, uint8[] data) {
            Hmac hmac = new Hmac(ChecksumType.SHA1, key);
            hmac.update(data);
            uint8[] res = new uint8[SHA1_SIZE];
            hmac.get_digest(res, ref SHA1_SIZE);
            return res;
        }

        private static uint8[] pbkdf2_sha1(string password, uint8[] salt, uint iterations) {
            uint8[] res = new uint8[SHA1_SIZE];
            uint8[] last = new uint8[salt.length + 4];
            for(int i = 0; i < salt.length; i++) {
                last[i] = salt[i];
            }
            last[salt.length + 3] = 1;
            for(int i = 0; i < iterations; i++) {
                last = hmac_sha1((uint8[]) password.to_utf8(), last);
                xor_inplace(res, last);
            }
            return res;
        }

        private static size_t SHA256_SIZE = 32;

        private static uint8[] sha256(uint8[] data) {
            Checksum checksum = new Checksum(ChecksumType.SHA256);
            checksum.update(data, data.length);
            uint8[] res = new uint8[SHA256_SIZE];
            checksum.get_digest(res, ref SHA256_SIZE);
            return res;
        }

        private static uint8[] hmac_sha256(uint8[] key, uint8[] data) {
            Hmac hmac = new Hmac(ChecksumType.SHA256, key);
            hmac.update(data);
            uint8[] res = new uint8[SHA256_SIZE];
            hmac.get_digest(res, ref SHA256_SIZE);
            return res;
        }

        private static uint8[] pbkdf2_sha256(string password, uint8[] salt, uint iterations) {
            uint8[] res = new uint8[SHA256_SIZE];
            uint8[] last = new uint8[salt.length + 4];
            for(int i = 0; i < salt.length; i++) {
                last[i] = salt[i];
            }
            last[salt.length + 3] = 1;
            for(int i = 0; i < iterations; i++) {
                last = hmac_sha256((uint8[]) password.to_utf8(), last);
                xor_inplace(res, last);
            }
            return res;
        }

        private static size_t SHA512_SIZE = 64;

        private static uint8[] sha512(uint8[] data) {
            Checksum checksum = new Checksum(ChecksumType.SHA512);
            checksum.update(data, data.length);
            uint8[] res = new uint8[SHA512_SIZE];
            checksum.get_digest(res, ref SHA512_SIZE);
            return res;
        }

        private static uint8[] hmac_sha512(uint8[] key, uint8[] data) {
            Hmac hmac = new Hmac(ChecksumType.SHA512, key);
            hmac.update(data);
            uint8[] res = new uint8[SHA512_SIZE];
            hmac.get_digest(res, ref SHA512_SIZE);
            return res;
        }

        private static uint8[] pbkdf2_sha512(string password, uint8[] salt, uint iterations) {
            uint8[] res = new uint8[SHA512_SIZE];
            uint8[] last = new uint8[salt.length + 4];
            for(int i = 0; i < salt.length; i++) {
                last[i] = salt[i];
            }
            last[salt.length + 3] = 1;
            for(int i = 0; i < iterations; i++) {
                last = hmac_sha512((uint8[]) password.to_utf8(), last);
                xor_inplace(res, last);
            }
            return res;
        }

        // Dispatch helpers for multi-algorithm SCRAM
        private static uint8[] scram_hash(string mechanism, uint8[] data) {
            if (mechanism == Mechanism.SCRAM_SHA_512 || mechanism == Mechanism.SCRAM_SHA_512_PLUS) return sha512(data);
            if (mechanism == Mechanism.SCRAM_SHA_256 || mechanism == Mechanism.SCRAM_SHA_256_PLUS) return sha256(data);
            return sha1(data);
        }

        private static uint8[] scram_hmac(string mechanism, uint8[] key, uint8[] data) {
            if (mechanism == Mechanism.SCRAM_SHA_512 || mechanism == Mechanism.SCRAM_SHA_512_PLUS) return hmac_sha512(key, data);
            if (mechanism == Mechanism.SCRAM_SHA_256 || mechanism == Mechanism.SCRAM_SHA_256_PLUS) return hmac_sha256(key, data);
            return hmac_sha1(key, data);
        }

        private static uint8[] scram_pbkdf2(string mechanism, string password, uint8[] salt, uint iterations) {
            if (mechanism == Mechanism.SCRAM_SHA_512 || mechanism == Mechanism.SCRAM_SHA_512_PLUS) return pbkdf2_sha512(password, salt, iterations);
            if (mechanism == Mechanism.SCRAM_SHA_256 || mechanism == Mechanism.SCRAM_SHA_256_PLUS) return pbkdf2_sha256(password, salt, iterations);
            return pbkdf2_sha1(password, salt, iterations);
        }

        private static bool is_scram(string mechanism) {
            return mechanism == Mechanism.SCRAM_SHA_1 || mechanism == Mechanism.SCRAM_SHA_1_PLUS ||
                   mechanism == Mechanism.SCRAM_SHA_256 || mechanism == Mechanism.SCRAM_SHA_256_PLUS ||
                   mechanism == Mechanism.SCRAM_SHA_512 || mechanism == Mechanism.SCRAM_SHA_512_PLUS;
        }

        private static bool is_scram_plus(string mechanism) {
            return mechanism == Mechanism.SCRAM_SHA_1_PLUS ||
                   mechanism == Mechanism.SCRAM_SHA_256_PLUS ||
                   mechanism == Mechanism.SCRAM_SHA_512_PLUS;
        }

        private static void xor_inplace(uint8[] mix, uint8[] a2) {
            for(int i = 0; i < mix.length; i++) {
                mix[i] = mix[i] ^ a2[i];
            }
        }

        private static uint8[] xor(uint8[] a1, uint8[] a2) {
            uint8[] mix = new uint8[a1.length];
            for(int i = 0; i < a1.length; i++) {
                mix[i] = a1[i] ^ a2[i];
            }
            return mix;
        }

        private static string generate_csprng_nonce() {
            uint8[] nonce_bytes = new uint8[24];
            try {
                var urandom = File.new_for_path("/dev/urandom");
                var input_stream = urandom.read();
                size_t bytes_read;
                input_stream.read_all(nonce_bytes, out bytes_read);
                input_stream.close();
                if (bytes_read < 24) {
                    throw new IOError.FAILED("Short read from /dev/urandom");
                }
            } catch (Error e) {
                // Fallback for systems without /dev/urandom (Windows)
                for (int i = 0; i < nonce_bytes.length; i++) {
                    nonce_bytes[i] = (uint8) Random.int_range(0, 256);
                }
            }
            return Base64.encode(nonce_bytes);
        }

        public void received_nonza(XmppStream stream, StanzaNode node) {
            if (node.ns_uri == NS_URI) {
                if (node.name == "success") {
                    Flag flag = stream.get_flag(Flag.IDENTITY);
                    if (is_scram(flag.mechanism)) {
                        string confirm = (string) Base64.decode(node.get_string_content());
                        uint8[] server_signature = null;
                        foreach(string c in confirm.split(",")) {
                            string[] split = c.split("=", 2);
                            if (split.length != 2) continue;
                            switch(split[0]) {
                                case "v": server_signature = Base64.decode(split[1]); break;
                            }
                        }
                        if (server_signature == null) return;
                        if (server_signature.length != flag.server_signature.length) return;
                        uint8 result = 0;
                        for(int i = 0; i < server_signature.length; i++) {
                            result |= server_signature[i] ^ flag.server_signature[i];
                        }
                        if (result != 0) return;
                    }
                    stream.require_setup();
                    flag.password = null; // Remove password from memory
                    flag.finished = true;
                    debug("SASL: Authenticated via %s at %s", flag.mechanism, stream.remote_name.to_string());
                } else if (node.name == "failure") {
                    stream.remove_flag(stream.get_flag(Flag.IDENTITY));
                    received_auth_failure(stream, node);
                } else if (node.name == "challenge" && stream.has_flag(Flag.IDENTITY)) {
                    Flag flag = stream.get_flag(Flag.IDENTITY);
                    if (is_scram(flag.mechanism)) {
                        string challenge = (string) Base64.decode(node.get_string_content());
                        string? server_nonce = null;
                        uint8[] salt = null;
                        uint iterations = 0;
                        foreach(string c in challenge.split(",")) {
                            string[] split = c.split("=", 2);
                            if (split.length != 2) continue;
                            switch(split[0]) {
                                case "r": server_nonce = split[1]; break;
                                case "s": salt = Base64.decode(split[1]); break;
                                case "i": iterations = int.parse(split[1]); break;
                            }
                        }
                        if (server_nonce == null || salt == null || iterations == 0) return;
                        if (iterations < 4096) {
                            warning("SCRAM: Server iteration count too low (%u), rejecting", iterations);
                            return;
                        }
                        if (!server_nonce.has_prefix(flag.client_nonce)) return;
                        // Compute channel binding input: gs2-header + cbind-data
                        uint8[] gs2_bytes = (uint8[]) flag.gs2_header.to_utf8();
                        uint8[] cb_input;
                        if (flag.channel_binding_data != null) {
                            cb_input = new uint8[gs2_bytes.length + flag.channel_binding_data.length];
                            for (int i = 0; i < gs2_bytes.length; i++) cb_input[i] = gs2_bytes[i];
                            for (int i = 0; i < flag.channel_binding_data.length; i++) cb_input[gs2_bytes.length + i] = flag.channel_binding_data[i];
                        } else {
                            cb_input = gs2_bytes;
                        }
                        string c_value = Base64.encode((uchar[]) cb_input);
                        string client_final_message_bare = @"c=$c_value,r=$server_nonce";
                        uint8[] salted_password = scram_pbkdf2(flag.mechanism, flag.password, salt, iterations);
                        uint8[] client_key = scram_hmac(flag.mechanism, salted_password, (uint8[]) "Client Key".to_utf8());
                        uint8[] stored_key = scram_hash(flag.mechanism, client_key);
                        string auth_message = @"n=$(flag.name),r=$(flag.client_nonce),$challenge,$client_final_message_bare";
                        uint8[] client_signature = scram_hmac(flag.mechanism, stored_key, (uint8[]) auth_message.to_utf8());
                        uint8[] client_proof = xor(client_key, client_signature);
                        uint8[] server_key = scram_hmac(flag.mechanism, salted_password, (uint8[]) "Server Key".to_utf8());
                        flag.server_signature = scram_hmac(flag.mechanism, server_key, (uint8[]) auth_message.to_utf8());
                        string client_final_message = @"$client_final_message_bare,p=$(Base64.encode(client_proof))";
                        stream.write(new StanzaNode.build("response", NS_URI).add_self_xmlns()
                                .put_node(new StanzaNode.text(Base64.encode((uchar[]) (client_final_message).to_utf8()))));
                    }
                }
            }
        }

        public void received_features_node(XmppStream stream) {
            if (stream.has_flag(Flag.IDENTITY)) return;
            if (stream.is_setup_needed()) return;

            var mechanisms = stream.features.get_subnode("mechanisms", NS_URI);
            string[] supported_mechanisms = {};
            foreach (var mechanism in mechanisms.sub_nodes) {
                if (mechanism.name != "mechanism" || mechanism.ns_uri != NS_URI) continue;
                supported_mechanisms += mechanism.get_string_content();
            }
            if (!name.contains("@")) {
                name = "%s@%s".printf(name, stream.remote_name.to_string());
            }
            if (!use_full_name && name.contains("@")) {
                var split = name.split("@");
                if (split[1] == stream.remote_name.to_string()) {
                    name = split[0];
                } else {
                    use_full_name = true;
                }
            }
            string name = this.name;
            if (!use_full_name && name.contains("@")) {
                var split = name.split("@");
                if (split[1] == stream.remote_name.to_string()) {
                    name = split[0];
                }
            }
            // Try to get channel binding data for SCRAM-*-PLUS
            string? cb_type = null;
            uint8[]? cb_data = null;
#if GLIB_2_66
            if (stream is TlsXmppStream) {
                cb_data = ((TlsXmppStream) stream).get_channel_binding_data(out cb_type);
            }
#endif
            debug("SASL: Server offers: %s | Channel binding: %s (%s) | Downgrade protection: %s",
                string.joinv(", ", supported_mechanisms),
                cb_data != null ? "available" : "unavailable",
                cb_type ?? "none",
                require_channel_binding ? "ON" : "off");

            string? scram_mechanism = null;
            if (cb_data != null) {
                // Prefer -PLUS variants when channel binding is available
                if (Mechanism.SCRAM_SHA_512_PLUS in supported_mechanisms) {
                    scram_mechanism = Mechanism.SCRAM_SHA_512_PLUS;
                } else if (Mechanism.SCRAM_SHA_256_PLUS in supported_mechanisms) {
                    scram_mechanism = Mechanism.SCRAM_SHA_256_PLUS;
                } else if (Mechanism.SCRAM_SHA_1_PLUS in supported_mechanisms) {
                    scram_mechanism = Mechanism.SCRAM_SHA_1_PLUS;
                } else if (!require_channel_binding) {
                    // Fall back to non-PLUS only if downgrade protection is off
                    if (Mechanism.SCRAM_SHA_512 in supported_mechanisms) {
                        scram_mechanism = Mechanism.SCRAM_SHA_512;
                    } else if (Mechanism.SCRAM_SHA_256 in supported_mechanisms) {
                        scram_mechanism = Mechanism.SCRAM_SHA_256;
                    } else if (Mechanism.SCRAM_SHA_1 in supported_mechanisms) {
                        scram_mechanism = Mechanism.SCRAM_SHA_1;
                    }
                }
            } else if (!require_channel_binding) {
                // No channel binding data available; only proceed if not required
                if (Mechanism.SCRAM_SHA_512 in supported_mechanisms) {
                    scram_mechanism = Mechanism.SCRAM_SHA_512;
                } else if (Mechanism.SCRAM_SHA_256 in supported_mechanisms) {
                    scram_mechanism = Mechanism.SCRAM_SHA_256;
                } else if (Mechanism.SCRAM_SHA_1 in supported_mechanisms) {
                    scram_mechanism = Mechanism.SCRAM_SHA_1;
                }
            }
            if (scram_mechanism != null) {
                debug("SASL: Selected %s for %s", scram_mechanism, stream.remote_name.to_string());
                string normalized_password = password.normalize(-1, NormalizeMode.NFKC);
                string client_nonce = generate_csprng_nonce();
                // GS2 header: "p=<cb_type>,," for -PLUS, "n,," for non-PLUS
                string gs2_header = is_scram_plus(scram_mechanism) ? @"p=$cb_type,," : "n,,";
                string initial_message = @"n=$name,r=$client_nonce";
                stream.write(new StanzaNode.build("auth", NS_URI).add_self_xmlns()
                        .put_attribute("mechanism", scram_mechanism)
                        .put_node(new StanzaNode.text(Base64.encode((uchar[]) (gs2_header+initial_message).to_utf8()))));
                var flag = new Flag();
                flag.mechanism = scram_mechanism;
                flag.name = name;
                flag.password = normalized_password;
                flag.client_nonce = client_nonce;
                flag.gs2_header = gs2_header;
                if (is_scram_plus(scram_mechanism)) {
                    flag.channel_binding_data = cb_data;
                }
                stream.add_flag(flag);
            } else if (require_channel_binding) {
                warning("Channel binding required but no -PLUS mechanism available at %s (possible downgrade attack)", stream.remote_name.to_string());
                received_auth_failure(stream, new StanzaNode.build("failure", NS_URI));
                return;
            } else if (Mechanism.PLAIN in supported_mechanisms) {
                if (!(stream is TlsXmppStream)) {
                    warning("Refusing PLAIN authentication without TLS to %s", stream.remote_name.to_string());
                    return;
                }
                stream.write(new StanzaNode.build("auth", NS_URI).add_self_xmlns()
                                    .put_attribute("mechanism", Mechanism.PLAIN)
                                    .put_node(new StanzaNode.text(Base64.encode(get_plain_bytes(name, password)))));
                var flag = new Flag();
                flag.mechanism = Mechanism.PLAIN;
                flag.name = name;
                stream.add_flag(flag);
            } else {
                warning("No supported mechanism provided by server at %s", stream.remote_name.to_string());
                return;
            }
        }

        private static uchar[] get_plain_bytes(string name_s, string password_s) {
            var name = name_s.to_utf8();
            var password = password_s.to_utf8();
            uchar[] res = new uchar[name.length + password.length + 2];
            res[0] = 0;
            res[name.length + 1] = 0;
            for(int i = 0; i < name.length; i++) { res[i + 1] = (uchar) name[i]; }
            for(int i = 0; i < password.length; i++) { res[i + name.length + 2] = (uchar) password[i]; }
            return res;
        }

        public override bool mandatory_outstanding(XmppStream stream) {
            return !stream.has_flag(Flag.IDENTITY) || !stream.get_flag(Flag.IDENTITY).finished;
        }

        public override bool negotiation_active(XmppStream stream) {
            return stream.has_flag(Flag.IDENTITY) && !stream.get_flag(Flag.IDENTITY).finished;
        }

        public override string get_ns() { return NS_URI; }
        public override string get_id() { return IDENTITY.id; }
    }
}
