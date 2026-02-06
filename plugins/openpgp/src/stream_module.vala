using Xmpp;

namespace Dino.Plugins.OpenPgp {
    private const string NS_URI = "jabber:x";
    private const string NS_URI_ENCRYPTED = NS_URI + ":encrypted";
    private const string NS_URI_SIGNED = NS_URI +  ":signed";

    public class Module : XmppStreamModule {
        public static Xmpp.ModuleIdentity<Module> IDENTITY = new Xmpp.ModuleIdentity<Module>(NS_URI, "0027_current_pgp_usage");

        public signal void received_jid_key_id(XmppStream stream, Jid jid, string key_id);
        
        // Signal emitted when key setup is complete - allows triggering presence resend
        public signal void key_setup_complete();

        private string? signed_status = null;
        private GPGHelper.Key? own_key = null;
        private ReceivedPipelineDecryptListener received_pipeline_decrypt_listener = new ReceivedPipelineDecryptListener();
        
        // Flag to prevent use-after-free in thread callbacks
        private bool module_disposed = false;
        
        // Reference to attached stream for presence resend
        private weak XmppStream? attached_stream = null;
        
        // Store key_id for deferred initialization (safer on Windows)
        private string? pending_key_id = null;
        private bool key_setup_done = false;

        public Module(string? own_key_id = null) {
            // DON'T do key setup in constructor - just store the ID
            // The actual setup happens in attach() when the stream is ready
            // This avoids thread race conditions on Windows
            this.pending_key_id = own_key_id;
            debug("OpenPGP XEP-0027: Module created with key_id: %s (setup deferred)", own_key_id ?? "none");
        }

        public void set_private_key_id(string? own_key_id) {
            // Just update the pending key ID - actual setup is done in do_key_setup()
            this.pending_key_id = own_key_id;
            this.key_setup_done = false;
            
            if (own_key_id == null || own_key_id.length == 0) {
                own_key = null;
                signed_status = null;
                debug("OpenPGP XEP-0027: Key cleared");
            } else if (attached_stream != null) {
                // If already attached, do setup now
                do_key_setup();
            }
        }
        
        // Perform key setup in background thread - non-blocking
        private void do_key_setup() {
            if (key_setup_done || pending_key_id == null || pending_key_id.length == 0) {
                return;
            }
            
            // Mark as done immediately to prevent duplicate calls
            key_setup_done = true;
            
            debug("OpenPGP XEP-0027: Starting async key setup for: %s", pending_key_id);
            
            // Copy values for thread safety
            string key_id_copy = pending_key_id;
            
            // Run GPG operations in background thread to avoid blocking UI
            new Thread<void*>("openpgp-key-setup", () => {
                GPGHelper.Key? key = null;
                string? sig = null;
                
                try {
                    key = GPGHelper.get_private_key(key_id_copy);
                    if (key == null) {
                        debug("OpenPGP XEP-0027: Can't get PGP private key %s - key returned null", key_id_copy);
                        return null;
                    }
                    
                    debug("OpenPGP XEP-0027: Got private key, now trying to sign...");
                    sig = gpg_sign("", key);
                } catch (Error e) {
                    debug("OpenPGP XEP-0027: Failed to get private key %s: %s", key_id_copy, e.message);
                    return null;
                }
                
                // Callback to main thread with results
                Idle.add(() => {
                    if (module_disposed) return false;
                    
                    if (sig != null && key != null) {
                        this.own_key = key;
                        this.signed_status = sig;
                        debug("OpenPGP XEP-0027: Presence signing ENABLED with key %s", key_id_copy);
                        
                        // Send presence with signature
                        if (attached_stream != null) {
                            debug("OpenPGP XEP-0027: Sending signed presence...");
                            var presence_module = attached_stream.get_module<Presence.Module>(Presence.Module.IDENTITY);
                            if (presence_module != null) {
                                var presence = new Presence.Stanza();
                                presence.type_ = Presence.Stanza.TYPE_AVAILABLE;
                                presence_module.send_presence(attached_stream, presence);
                                debug("OpenPGP XEP-0027: Signed presence sent!");
                            }
                        }
                        
                        key_setup_complete();
                    } else {
                        debug("OpenPGP XEP-0027: Failed to create signed_status - signing disabled!");
                    }
                    return false;
                });
                
                return null;
            });
        }
        
        // LEGACY synchronous version - NOT USED, kept for reference
        private void do_key_setup_sync_UNUSED() {
            string? key_id_copy = pending_key_id;
            if (key_id_copy == null || key_id_copy.length == 0) return;
            
            try {
                var key = GPGHelper.get_private_key(key_id_copy);
                if (key == null) {
                    debug("OpenPGP XEP-0027: Can't get PGP private key %s - key returned null", key_id_copy);
                    return;
                }
                
                string? sig = gpg_sign("", key);
                
                if (sig != null) {
                    this.own_key = key;
                    this.signed_status = sig;
                    debug("OpenPGP XEP-0027: Presence signing ENABLED with key %s", pending_key_id);
                    
                    // Send presence with signature
                    if (attached_stream != null) {
                        debug("OpenPGP XEP-0027: Sending signed presence...");
                        var presence_module = attached_stream.get_module<Presence.Module>(Presence.Module.IDENTITY);
                        if (presence_module != null) {
                            var presence = new Presence.Stanza();
                            presence.type_ = Presence.Stanza.TYPE_AVAILABLE;
                            presence_module.send_presence(attached_stream, presence);
                            debug("OpenPGP XEP-0027: Signed presence sent!");
                        }
                    }
                    
                    key_setup_complete();
                } else {
                    debug("OpenPGP XEP-0027: Failed to create signed_status - signing disabled!");
                }
            } catch (Error e) {
                debug("OpenPGP XEP-0027: Failed to get private key %s: %s", pending_key_id, e.message);
            }
            
            key_setup_done = true;
        }

        // XEP-0027 encryption (legacy format)
        public bool encrypt(MessageStanza message, GPGHelper.Key[] keys) {
            string? enc_body = gpg_encrypt(message.body, keys);
            if (enc_body != null) {
                message.stanza.put_node(new StanzaNode.build("x", NS_URI_ENCRYPTED).add_self_xmlns().put_node(new StanzaNode.text(enc_body)));
                message.body = "[This message is OpenPGP encrypted (see XEP-0027)]";
                Xep.ExplicitEncryption.add_encryption_tag_to_message(message, NS_URI_ENCRYPTED);
                return true;
            }
            return false;
        }
        
        // XEP-0374 encryption (modern format with signcrypt)
        public bool encrypt_0374(MessageStanza message, GPGHelper.Key[] keys) {
            if (message.to == null || message.body == null) return false;
            
            // Sign and encrypt the signcrypt element
            string? encrypted;
            try {
                // Create signcrypt content element
                var signcrypt = new Xmpp.Xep.OpenPgpContent.SigncryptElement.with_body(message.to, message.body);
                string signcrypt_xml = signcrypt.to_stanza_node().to_xml();
                
                // For XEP-0374 we need to sign AND encrypt
                // The signcrypt element itself should be encrypted to all recipients
                encrypted = GPGHelper.sign_and_encrypt(signcrypt_xml, keys, own_key);
            } catch (Error e) {
                debug("OpenPGP XEP-0374: Sign+Encrypt failed: %s", e.message);
                return false;
            }
            
            if (encrypted == null) return false;
            
            // Base64 encode the raw OpenPGP message (not ASCII armor)
            // For simplicity, we'll use the armored version without headers
            string base64_data = extract_pgp_data(encrypted);
            
            // Create <openpgp> element
            var openpgp_node = new StanzaNode.build("openpgp", "urn:xmpp:openpgp:0")
                .add_self_xmlns()
                .put_node(new StanzaNode.text(base64_data));
            
            message.stanza.put_node(openpgp_node);
            
            // Add EME (Explicit Message Encryption) hint
            message.stanza.put_node(new StanzaNode.build("encryption", "urn:xmpp:eme:0")
                .add_self_xmlns()
                .put_attribute("namespace", "urn:xmpp:openpgp:0")
                .put_attribute("name", "OpenPGP for XMPP"));
            
            // Add fallback body
            message.body = "[This message is encrypted with OpenPGP for XMPP (XEP-0373/0374)]";
            
            // Add store hint
            message.stanza.put_node(new StanzaNode.build("store", "urn:xmpp:hints").add_self_xmlns());
            
            debug("OpenPGP XEP-0374: Message encrypted with signcrypt format");
            return true;
        }
        
        // Extract PGP data from ASCII armor (remove headers/footers, base64 encode if needed)
        private static string extract_pgp_data(string armored) {
            int start = armored.index_of("\n\n");
            if (start < 0) start = armored.index_of("\r\n\r\n");
            if (start < 0) return Base64.encode(armored.data);
            
            start += 2;
            int end = armored.index_of("-----END PGP MESSAGE-----");
            if (end < 0) end = armored.length;
            
            // The data between headers is already base64, just return it
            return armored.substring(start, end - start).strip();
        }

        public override void attach(XmppStream stream) {
            // Store reference to stream for presence resend after key setup
            attached_stream = stream;
            
            stream.get_module<Presence.Module>(Presence.Module.IDENTITY).received_presence.connect(on_received_presence);
            stream.get_module<Presence.Module>(Presence.Module.IDENTITY).pre_send_presence_stanza.connect(on_pre_send_presence_stanza);
            stream.get_module<MessageModule>(MessageModule.IDENTITY).received_pipeline.connect(received_pipeline_decrypt_listener);
            stream.add_flag(new Flag());
            
            // Perform deferred key setup now that stream is attached
            // Use Idle.add to not block the attach() call
            Idle.add(() => {
                if (!module_disposed) {
                    do_key_setup();
                }
                return false;
            });
        }

        public override void detach(XmppStream stream) {
            // Mark as disposed FIRST to prevent any pending callbacks from running
            module_disposed = true;
            attached_stream = null;
            
            stream.get_module<Presence.Module>(Presence.Module.IDENTITY).received_presence.disconnect(on_received_presence);
            stream.get_module<Presence.Module>(Presence.Module.IDENTITY).pre_send_presence_stanza.disconnect(on_pre_send_presence_stanza);
            stream.get_module<MessageModule>(MessageModule.IDENTITY).received_pipeline.disconnect(received_pipeline_decrypt_listener);
        }

        public static void require(XmppStream stream) {
            if (stream.get_module<Module>(IDENTITY) == null) stream.add_module(new Module());
        }

        public override string get_ns() { return NS_URI; }
        public override string get_id() { return IDENTITY.id; }

        private void on_received_presence(XmppStream stream, Presence.Stanza presence) {
            StanzaNode x_node = presence.stanza.get_subnode("x", NS_URI_SIGNED);
            if (x_node == null) {
                return;
            }
            string? sig = x_node.get_string_content();
            if (sig == null) {
                return;
            }
            debug("OpenPGP XEP-0027: Got signed presence from %s, signature length: %d", presence.from.to_string(), sig.length);
            
            // Store copies for thread safety
            string sig_copy = sig;
            string signed_data = presence.status == null ? "" : presence.status;
            Jid from_jid = presence.from;
            
            // Run GPG verification in background thread to avoid blocking UI
            new Thread<void*>("openpgp-verify-presence", () => {
                GPGHelper.SignatureVerifyResult verify_result;
                try {
                    verify_result = verify_signature(sig_copy, signed_data);
                } catch (Error e) {
                    debug("OpenPGP: Error in verify_signature: %s", e.message);
                    return null;
                }
                
                if (verify_result.key_id != null) {
                    if (verify_result.key_missing) {
                        // Key is not in our keyring - try to fetch from keyserver
                        debug("OpenPGP XEP-0027: Key %s from %s not in keyring, trying keyserver...", 
                                verify_result.key_id, from_jid.to_string());
                        try {
                            bool imported = GPGHelper.download_key_from_keyserver(verify_result.key_id);
                            if (imported) {
                                debug("OpenPGP XEP-0027: Successfully imported key %s from keyserver!", verify_result.key_id);
                                // Now verify again
                                verify_result = verify_signature(sig_copy, signed_data);
                            } else {
                                debug("OpenPGP XEP-0027: Key %s not found on keyserver", verify_result.key_id);
                            }
                        } catch (Error e) {
                            debug("OpenPGP XEP-0027: Keyserver lookup failed: %s", e.message);
                        }
                    }
                    
                    // Copy final result for main thread callback
                    string? final_key_id = verify_result.key_id;
                    bool final_verified = verify_result.verified;
                    
                    // Callback to main thread to update UI/flags
                    Idle.add(() => {
                        if (module_disposed) return false;
                        
                        if (final_key_id != null) {
                            // Store the key ID even if not verified (user can import manually)
                            stream.get_flag(Flag.IDENTITY).set_key_id(from_jid, final_key_id);
                            received_jid_key_id(stream, from_jid, final_key_id);
                            
                            if (final_verified) {
                                debug("OpenPGP XEP-0027: VERIFIED key %s from %s", final_key_id, from_jid.to_string());
                            } else {
                                debug("OpenPGP XEP-0027: Stored UNVERIFIED key %s from %s (key not in keyring)", 
                                        final_key_id, from_jid.to_string());
                            }
                        }
                        return false;
                    });
                } else {
                    debug("OpenPGP XEP-0027: Could not extract key ID from signature of %s", from_jid.to_string());
                }
                
                return null;
            });
        }
        
        // Wrapper for GPGHelper.verify_signature
        private static GPGHelper.SignatureVerifyResult verify_signature(string sig, string signed_text) {
            // Validate signature before passing to GPG - avoid radix64 errors
            // Check for base64url characters that will cause GPG to fail
            if (sig.contains("-") || sig.contains("_")) {
                debug("OpenPGP XEP-0027: Signature contains base64url characters, skipping");
                return new GPGHelper.SignatureVerifyResult();
            }
            
            // XEP-0027 uses detached PGP SIGNATURE format, not PGP MESSAGE
            string armor = "-----BEGIN PGP SIGNATURE-----\n\n" + sig + "\n-----END PGP SIGNATURE-----";
            debug("OpenPGP XEP-0027: verify_signature armor:\n%s", armor);
            try {
                return GPGHelper.verify_signature(armor, signed_text);
            } catch (Error e) {
                debug("OpenPGP: Failed to verify signature: %s", e.message);
                return new GPGHelper.SignatureVerifyResult();
            }
        }

        private void on_pre_send_presence_stanza(XmppStream stream, Presence.Stanza presence) {
            if (presence.type_ == Presence.Stanza.TYPE_AVAILABLE && signed_status != null) {
                presence.stanza.put_node(new StanzaNode.build("x", NS_URI_SIGNED).add_self_xmlns().put_node(new StanzaNode.text(signed_status)));
                debug("OpenPGP XEP-0027: Sending signed presence with key signature (length: %d)", signed_status.length);
            } else if (presence.type_ == Presence.Stanza.TYPE_AVAILABLE && signed_status == null) {
                debug("OpenPGP XEP-0027: NOT sending signed presence - signed_status is NULL!");
            }
        }

        private static string? gpg_encrypt(string plain, GPGHelper.Key[] keys) {
            string encr;
            try {
                encr = GPGHelper.encrypt_armor(plain, keys, 0);
            } catch (Error e) {
                debug("OpenPGP: Encryption failed: %s", e.message);
                return null;
            }
            
            // Extract base64 content between headers
            // Format: -----BEGIN PGP MESSAGE-----\n\n[base64]\n-----END PGP MESSAGE-----
            // Note: Windows GPG may use \r\n, so normalize first
            string normalized = encr.replace("\r\n", "\n");
            
            int begin_marker = normalized.index_of("-----BEGIN PGP MESSAGE-----");
            if (begin_marker == -1) {
                debug("OpenPGP: No PGP MESSAGE header found");
                return null;
            }
            
            // Find the empty line after headers
            int content_start = normalized.index_of("\n\n", begin_marker);
            if (content_start == -1) {
                debug("OpenPGP: No empty line after header");
                return null;
            }
            content_start += 2; // Skip \n\n
            
            int end_marker = normalized.index_of("-----END PGP MESSAGE-----");
            if (end_marker == -1) {
                debug("OpenPGP: No END PGP MESSAGE footer found");
                return null;
            }
            
            // Extract only the base64 part
            string base64_content = normalized.substring(content_start, end_marker - content_start);
            base64_content = base64_content.strip();
            
            debug("OpenPGP gpg_encrypt: Extracted (length %d)", base64_content.length);
            return base64_content;
        }

        private static string? gpg_sign(string str, GPGHelper.Key key) {
            string signed;
            try {
                signed = GPGHelper.sign(str, 1, key);  // 1 = DETACH mode
            } catch (Error e) {
                debug("OpenPGP: Signing failed: %s", e.message);
                return null;
            }
            
            // Debug: log full GPG output
            debug("OpenPGP gpg_sign: Full GPG output:\n%s", signed);
            
            // For detached signature, extract just the base64 part
            // GPG output format:
            // -----BEGIN PGP SIGNATURE-----
            // 
            // iQIzBAABCAAdFiEE...   (base64 data, may have newlines every 64 chars)
            // =XXXX                  (checksum)
            // -----END PGP SIGNATURE-----
            
            int begin_marker = signed.index_of("-----BEGIN PGP SIGNATURE-----");
            if (begin_marker == -1) {
                debug("OpenPGP: No PGP SIGNATURE header found in signed output");
                return null;
            }
            
            // Find the empty line after any headers (Hash: SHA256, etc.)
            int content_start = signed.index_of("\n\n", begin_marker);
            if (content_start == -1) {
                // Try with just one newline
                content_start = signed.index_of("\n", begin_marker + 30);
            }
            content_start += 2; // Skip the \n\n
            
            int end_marker = signed.index_of("-----END PGP SIGNATURE-----");
            if (end_marker == -1) {
                debug("OpenPGP: No END PGP SIGNATURE footer found");
                return null;
            }
            
            // Extract the base64 content (includes checksum line like =XXXX)
            string base64_content = signed.substring(content_start, end_marker - content_start);
            
            // Remove newlines to get pure base64
            base64_content = base64_content.replace("\r\n", "\n").replace("\r", "");
            
            // Strip trailing newline
            base64_content = base64_content.strip();
            
            debug("OpenPGP gpg_sign: Extracted signature (length %d):\n%s", base64_content.length, base64_content);
            
            return base64_content;
        }
    }

    public class MessageFlag : Xmpp.MessageFlag {
        public const string id = "pgp";

        public bool decrypted = false;

        public static MessageFlag? get_flag(MessageStanza message) {
            return (MessageFlag) message.get_flag(NS_URI, id);
        }

        public override string get_ns() { return NS_URI; }
        public override string get_id() { return id; }
    }

public class ReceivedPipelineDecryptListener : StanzaListener<MessageStanza> {

    private string[] after_actions_const = {"MODIFY_BODY"};

    public override string action_group { get { return "ENCRYPT_BODY"; } }
    public override string[] after_actions { get { return after_actions_const; } }

    public override async bool run(XmppStream stream, MessageStanza message) {
        debug("OpenPGP ReceivedPipeline: Processing message from %s, body=%s", 
              message.from != null ? message.from.to_string() : "null",
              message.body != null ? "(has body)" : "(no body)");
        
        // Check if we have any secret keys before attempting decryption
        // Without secret keys, decryption will always fail
        if (!GPGHelper.has_secret_keys()) {
            debug("OpenPGP ReceivedPipeline: No secret keys available, skipping decryption");
            return false;
        }
        
        // Try XEP-0374 format first (<openpgp> element)
        string? openpgp_data = get_openpgp_content(message);
        if (openpgp_data != null) {
            debug("OpenPGP ReceivedPipeline: Found XEP-0374 encrypted content, length=%d", openpgp_data.length);
            MessageFlag flag = new MessageFlag();
            message.add_flag(flag);
            string? decrypted = yield gpg_decrypt_0374(openpgp_data);
            if (decrypted != null) {
                flag.decrypted = true;
                message.body = decrypted;
                debug("OpenPGP ReceivedPipeline: Decrypted XEP-0374 message: %s", decrypted);
            } else {
                debug("OpenPGP ReceivedPipeline: XEP-0374 decryption returned null!");
            }
            return false;
        }
        
        // Fall back to XEP-0027 format (<x xmlns='jabber:x:encrypted'>)
        string? encrypted = get_cyphertext(message);
        if (encrypted != null) {
            debug("OpenPGP ReceivedPipeline: Found XEP-0027 encrypted content, length=%d", encrypted.length);
            MessageFlag flag = new MessageFlag();
            message.add_flag(flag);
            string? decrypted = yield gpg_decrypt(encrypted);
            if (decrypted != null) {
                flag.decrypted = true;
                message.body = decrypted;
                debug("OpenPGP ReceivedPipeline: Decrypted XEP-0027 message: %s", decrypted);
            } else {
                debug("OpenPGP ReceivedPipeline: XEP-0027 decryption returned null!");
            }
        } else {
            debug("OpenPGP ReceivedPipeline: No encrypted content found in message");
        }
        return false;
    }

    // Decrypt XEP-0374 format
    private static async string? gpg_decrypt_0374(string base64_data) {
        SourceFunc callback = gpg_decrypt_0374.callback;
        string? res = null;
        new Thread<void*> (null, () => {
            try {
                string clean_data = base64_data.strip();
                
                debug("OpenPGP gpg_decrypt_0374: Input length=%d, first 100 chars: %s", 
                      clean_data.length, 
                      clean_data.length > 100 ? clean_data.substring(0, 100) : clean_data);
                
                string? decrypted_xml = null;
                
                if (clean_data.has_prefix("-----BEGIN PGP")) {
                    debug("OpenPGP gpg_decrypt_0374: Data is already armored");
                    try {
                        decrypted_xml = GPGHelper.decrypt(clean_data);
                    } catch (Error e) {
                        debug("OpenPGP gpg_decrypt_0374: Armored decryption failed: %s", e.message);
                    }
                } else {
                    // Remove whitespace from base64
                    clean_data = clean_data.replace("\n", "").replace("\r", "").replace(" ", "").replace("\t", "");
                    
                    // Add padding if needed
                    int padding_needed = (4 - (clean_data.length % 4)) % 4;
                    for (int i = 0; i < padding_needed; i++) {
                        clean_data += "=";
                    }
                    
                    debug("OpenPGP gpg_decrypt_0374: Base64 after cleanup, length=%d", clean_data.length);
                    
                    // Decode base64 to binary
                    uint8[] binary_data;
                    try {
                        binary_data = Base64.decode(clean_data);
                        debug("OpenPGP gpg_decrypt_0374: Decoded to %d binary bytes", binary_data.length);
                    } catch (Error e) {
                        debug("OpenPGP gpg_decrypt_0374: Base64 decode failed: %s", e.message);
                        res = null;
                        Idle.add((owned) callback);
                        return null;
                    }
                    
                    // Decrypt binary data
                    try {
                        var decrypted = GPGHelper.decrypt_data(binary_data);
                        // Convert uint8[] to string safely
                        decrypted_xml = (string) decrypted.data;
                        if (decrypted.data.length > 0 && decrypted.data[decrypted.data.length - 1] != 0) {
                            var sb = new StringBuilder();
                            foreach (uint8 b in decrypted.data) {
                                if (b != 0) sb.append_c((char) b);
                            }
                            decrypted_xml = sb.str;
                        }
                        debug("OpenPGP gpg_decrypt_0374: Binary decryption successful");
                    } catch (Error e) {
                        debug("OpenPGP gpg_decrypt_0374: Binary decryption failed: %s", e.message);
                        
                        // Fallback: try ASCII armor
                        var wrapped = new StringBuilder();
                        for (int i = 0; i < clean_data.length; i += 64) {
                            int end = int.min(i + 64, clean_data.length);
                            wrapped.append(clean_data.substring(i, end - i));
                            wrapped.append("\n");
                        }
                        
                        string armor = "-----BEGIN PGP MESSAGE-----\n\n" + wrapped.str + "-----END PGP MESSAGE-----";
                        try {
                            decrypted_xml = GPGHelper.decrypt(armor);
                            debug("OpenPGP gpg_decrypt_0374: ASCII armor fallback successful");
                        } catch (Error e2) {
                            debug("OpenPGP gpg_decrypt_0374: ASCII armor fallback also failed: %s", e2.message);
                        }
                    }
                }
                
                if (decrypted_xml != null) {
                    debug("OpenPGP gpg_decrypt_0374: Decrypted XML: %s", 
                          decrypted_xml.length > 200 ? decrypted_xml.substring(0, 200) + "..." : decrypted_xml);
                    res = extract_body_from_signcrypt(decrypted_xml);
                    if (res != null) {
                        debug("OpenPGP gpg_decrypt_0374: Extracted body: %s", res);
                    } else {
                        // If no <body> tag, return the whole decrypted content
                        debug("OpenPGP gpg_decrypt_0374: No body tag found, using full content");
                        res = decrypted_xml;
                    }
                }
            } catch (Error e) {
                debug("OpenPGP XEP-0374: Thread error: %s", e.message);
                res = null;
            }
            Idle.add((owned) callback);
            return null;
        });
        yield;
        return res;
    }
    
    // Extract body text from signcrypt XML
    private static string? extract_body_from_signcrypt(string xml) {
        // Simple extraction - look for <body>...</body>
        int body_start = xml.index_of("<body");
        if (body_start < 0) return null;
        
        int content_start = xml.index_of(">", body_start);
        if (content_start < 0) return null;
        content_start++;
        
        int body_end = xml.index_of("</body>", content_start);
        if (body_end < 0) return null;
        
        return xml.substring(content_start, body_end - content_start);
    }

    private static async string? gpg_decrypt(string enc) {
        SourceFunc callback = gpg_decrypt.callback;
        string? res = null;
        new Thread<void*> (null, () => {
            try {
                string clean_data = enc.strip();
                
                debug("OpenPGP gpg_decrypt: Input length=%d, first 100 chars: %s", 
                      clean_data.length, 
                      clean_data.length > 100 ? clean_data.substring(0, 100) : clean_data);
                
                // Check if it's already armored
                if (clean_data.has_prefix("-----BEGIN PGP")) {
                    debug("OpenPGP gpg_decrypt: Data is already armored, decrypting directly");
                    try {
                        res = GPGHelper.decrypt(clean_data);
                        debug("OpenPGP gpg_decrypt: Armored decryption successful");
                    } catch (Error e) {
                        debug("OpenPGP gpg_decrypt: Armored decryption failed: %s", e.message);
                    }
                } else {
                    // XEP-0027 sends base64-encoded PGP message
                    // Decode base64 and pass binary data to GPG
                    
                    // Remove any whitespace/newlines from the base64
                    clean_data = clean_data.replace("\n", "").replace("\r", "").replace(" ", "").replace("\t", "");
                    
                    debug("OpenPGP gpg_decrypt: Base64 after cleanup, length=%d", clean_data.length);
                    
                    // Add padding if needed
                    int padding_needed = (4 - (clean_data.length % 4)) % 4;
                    for (int i = 0; i < padding_needed; i++) {
                        clean_data += "=";
                    }
                    
                    // Decode base64 to binary
                    uint8[] binary_data;
                    try {
                        binary_data = Base64.decode(clean_data);
                        debug("OpenPGP gpg_decrypt: Decoded to %d binary bytes", binary_data.length);
                    } catch (Error e) {
                        debug("OpenPGP gpg_decrypt: Base64 decode failed: %s", e.message);
                        res = null;
                        Idle.add((owned) callback);
                        return null;
                    }
                    
                    // Write binary data to temp file and decrypt
                    try {
                        var decrypted = GPGHelper.decrypt_data(binary_data);
                        // Convert uint8[] to string safely
                        res = (string) decrypted.data;
                        // Ensure null termination for string
                        if (decrypted.data.length > 0 && decrypted.data[decrypted.data.length - 1] != 0) {
                            // Data is not null-terminated, create proper string
                            var sb = new StringBuilder();
                            foreach (uint8 b in decrypted.data) {
                                if (b != 0) sb.append_c((char) b);
                            }
                            res = sb.str;
                        }
                        debug("OpenPGP gpg_decrypt: Binary decryption successful, result: %s", 
                              res != null ? res : "null");
                    } catch (Error e) {
                        debug("OpenPGP gpg_decrypt: Binary decryption failed: %s", e.message);
                        
                        // Fallback: try as ASCII armor
                        debug("OpenPGP gpg_decrypt: Trying ASCII armor fallback...");
                        var wrapped = new StringBuilder();
                        for (int i = 0; i < clean_data.length; i += 64) {
                            int end = int.min(i + 64, clean_data.length);
                            wrapped.append(clean_data.substring(i, end - i));
                            wrapped.append("\n");
                        }
                        
                        string armor = "-----BEGIN PGP MESSAGE-----\n\n" + wrapped.str + "-----END PGP MESSAGE-----";
                        try {
                            res = GPGHelper.decrypt(armor);
                            debug("OpenPGP gpg_decrypt: ASCII armor fallback successful");
                        } catch (Error e2) {
                            debug("OpenPGP gpg_decrypt: ASCII armor fallback also failed: %s", e2.message);
                            res = null;
                        }
                    }
                }
            } catch (Error e) {
                debug("OpenPGP XEP-0027: Thread error: %s", e.message);
                res = null;
            }
            Idle.add((owned) callback);
            return null;
        });
        yield;
        return res;
    }

    private string? get_cyphertext(MessageStanza message) {
        // Debug: dump stanza to see what we're looking for
        debug("OpenPGP get_cyphertext: Looking for <x xmlns='jabber:x:encrypted'>");
        debug("OpenPGP get_cyphertext: Stanza: %s", message.stanza.to_string());
        StanzaNode? x_node = message.stanza.get_subnode("x", NS_URI_ENCRYPTED);
        if (x_node != null) {
            string? content = x_node.get_string_content();
            debug("OpenPGP get_cyphertext: Found encrypted content, length=%d", content != null ? content.length : 0);
            return content;
        }
        debug("OpenPGP get_cyphertext: No <x> node found with namespace %s", NS_URI_ENCRYPTED);
        return null;
    }
    
    private string? get_openpgp_content(MessageStanza message) {
        debug("OpenPGP get_openpgp_content: Looking for <openpgp xmlns='urn:xmpp:openpgp:0'>");
        StanzaNode? openpgp_node = message.stanza.get_subnode("openpgp", "urn:xmpp:openpgp:0");
        if (openpgp_node != null) {
            string? content = openpgp_node.get_string_content();
            debug("OpenPGP get_openpgp_content: Found openpgp content, length=%d", content != null ? content.length : 0);
            return content;
        }
        debug("OpenPGP get_openpgp_content: No <openpgp> node found");
        return null;
    }
}

}
