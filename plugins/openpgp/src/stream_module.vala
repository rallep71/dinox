using Xmpp;

namespace Dino.Plugins.OpenPgp {
    private const string NS_URI = "jabber:x";
    private const string NS_URI_ENCRYPTED = NS_URI + ":encrypted";
    private const string NS_URI_SIGNED = NS_URI +  ":signed";

    public class Module : XmppStreamModule {
        public static Xmpp.ModuleIdentity<Module> IDENTITY = new Xmpp.ModuleIdentity<Module>(NS_URI, "0027_current_pgp_usage");

        public signal void received_jid_key_id(XmppStream stream, Jid jid, string key_id);

        private string? signed_status = null;
        private GPGHelper.Key? own_key = null;
        private ReceivedPipelineDecryptListener received_pipeline_decrypt_listener = new ReceivedPipelineDecryptListener();

        public Module(string? own_key_id = null) {
            set_private_key_id(own_key_id);
        }

        public void set_private_key_id(string? own_key_id) {
            if (own_key_id != null) {
                debug("OpenPGP XEP-0027: Setting private key ID: %s", own_key_id);
                try {
                    own_key = GPGHelper.get_private_key(own_key_id);
                    if (own_key == null) {
                        debug("OpenPGP XEP-0027: Can't get PGP private key %s - key returned null", own_key_id);
                    }
                } catch (Error e) {
                    debug("OpenPGP XEP-0027: Failed to get private key %s: %s", own_key_id, e.message);
                }
                if (own_key != null) {
                    debug("OpenPGP XEP-0027: Got private key, now trying to sign...");
                    signed_status = gpg_sign("", own_key);
                    if (signed_status != null) {
                        debug("OpenPGP XEP-0027: Presence signing ENABLED with key %s (fingerprint: %s)", own_key_id, own_key.fpr);
                        // Note: Keyserver upload is now user-controlled via Key Management dialog
                    } else {
                        debug("OpenPGP XEP-0027: Failed to create signed_status - signing disabled!");
                    }
                } else {
                    debug("OpenPGP XEP-0027: No private key available - presence signing DISABLED. Other clients won't see your key!");
                }
            } else {
                debug("OpenPGP XEP-0027: No key_id configured for this account");
            }
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
            
            // Create signcrypt content element
            var signcrypt = new Xmpp.Xep.OpenPgpContent.SigncryptElement.with_body(message.to, message.body);
            string signcrypt_xml = signcrypt.to_stanza_node().to_xml();
            
            // Sign and encrypt the signcrypt element
            string? encrypted;
            try {
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
            stream.get_module<Presence.Module>(Presence.Module.IDENTITY).received_presence.connect(on_received_presence);
            stream.get_module<Presence.Module>(Presence.Module.IDENTITY).pre_send_presence_stanza.connect(on_pre_send_presence_stanza);
            stream.get_module<MessageModule>(MessageModule.IDENTITY).received_pipeline.connect(received_pipeline_decrypt_listener);
            stream.add_flag(new Flag());
        }

        public override void detach(XmppStream stream) {
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
            
            // Store copies for the idle callback (avoid closure issues)
            string sig_copy = sig;
            string signed_data = presence.status == null ? "" : presence.status;
            Jid from_jid = presence.from;
            
            // Use Idle.add instead of Thread to avoid Windows GLib handler stack corruption
            // The GPG operations are already serialized via mutex, so this is safe
            Idle.add(() => {
                var verify_result = verify_signature(sig_copy, signed_data);
                
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
                    
                    if (verify_result.verified || verify_result.key_id != null) {
                        // Store the key ID even if not verified (user can import manually)
                        stream.get_flag(Flag.IDENTITY).set_key_id(from_jid, verify_result.key_id);
                        string key_id_copy = verify_result.key_id;
                        Idle.add(() => {
                            received_jid_key_id(stream, from_jid, key_id_copy);
                            return false;
                        });
                        if (verify_result.verified) {
                            debug("OpenPGP XEP-0027: VERIFIED key %s from %s", verify_result.key_id, from_jid.to_string());
                        } else {
                            debug("OpenPGP XEP-0027: Stored UNVERIFIED key %s from %s (key not in keyring)", 
                                    verify_result.key_id, from_jid.to_string());
                        }
                    }
                } else {
                    debug("OpenPGP XEP-0027: Could not extract key ID from signature of %s", from_jid.to_string());
                }
                return false;  // Don't repeat
            });
        }
        
        // Wrapper for GPGHelper.verify_signature
        private static GPGHelper.SignatureVerifyResult verify_signature(string sig, string signed_text) {
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
        // Try XEP-0374 format first (<openpgp> element)
        string? openpgp_data = get_openpgp_content(message);
        if (openpgp_data != null) {
            MessageFlag flag = new MessageFlag();
            message.add_flag(flag);
            string? decrypted = yield gpg_decrypt_0374(openpgp_data);
            if (decrypted != null) {
                flag.decrypted = true;
                message.body = decrypted;
                debug("OpenPGP: Decrypted XEP-0374 message");
            }
            return false;
        }
        
        // Fall back to XEP-0027 format (<x xmlns='jabber:x:encrypted'>)
        string? encrypted = get_cyphertext(message);
        if (encrypted != null) {
            MessageFlag flag = new MessageFlag();
            message.add_flag(flag);
            string? decrypted = yield gpg_decrypt(encrypted);
            if (decrypted != null) {
                flag.decrypted = true;
                message.body = decrypted;
                debug("OpenPGP: Decrypted XEP-0027 message");
            }
        }
        return false;
    }

    // Decrypt XEP-0374 format
    private static async string? gpg_decrypt_0374(string base64_data) {
        SourceFunc callback = gpg_decrypt_0374.callback;
        string? res = null;
        new Thread<void*> (null, () => {
            // The data is base64-encoded OpenPGP message
            // We need to wrap it in ASCII armor for GPG
            // But first check if it's already armored
            string armor;
            string clean_data = base64_data.strip();
            
            if (clean_data.has_prefix("-----BEGIN PGP")) {
                // Already armored, use as-is
                armor = clean_data;
            } else {
                // Wrap in armor
                armor = "-----BEGIN PGP MESSAGE-----\n\n" + clean_data + "\n-----END PGP MESSAGE-----";
            }
            
            try {
                string decrypted_xml = GPGHelper.decrypt(armor);
                // Parse the decrypted XML to extract the body
                // The decrypted content should be a <signcrypt> element
                res = extract_body_from_signcrypt(decrypted_xml);
            } catch (Error e) {
                debug("OpenPGP XEP-0374: Decryption failed: %s", e.message);
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
            // Check if already armored
            string armor;
            string clean_data = enc.strip();
            
            if (clean_data.has_prefix("-----BEGIN PGP")) {
                // Already armored, use as-is
                armor = clean_data;
            } else {
                // Wrap in armor
                armor = "-----BEGIN PGP MESSAGE-----\n\n" + clean_data + "\n-----END PGP MESSAGE-----";
            }
            
            try {
                res = GPGHelper.decrypt(armor);
            } catch (Error e) {
                debug("OpenPGP XEP-0027: Decryption failed: %s", e.message);
                res = null;
            }
            Idle.add((owned) callback);
            return null;
        });
        yield;
        return res;
    }

    private string? get_cyphertext(MessageStanza message) {
        StanzaNode? x_node = message.stanza.get_subnode("x", NS_URI_ENCRYPTED);
        return x_node == null ? null : x_node.get_string_content();
    }
    
    private string? get_openpgp_content(MessageStanza message) {
        StanzaNode? openpgp_node = message.stanza.get_subnode("openpgp", "urn:xmpp:openpgp:0");
        return openpgp_node == null ? null : openpgp_node.get_string_content();
    }
}

}
