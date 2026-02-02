using Gee;
using Xmpp;
using Dino.Entities;

// Alias for XEP-0373 types to avoid conflict with Dino.Plugins.OpenPgp.Module
// The XMPP module is at Xmpp.Xep.OpenPgp.Module

namespace Dino.Plugins.OpenPgp {
    
    // XEP-0373 Key Publishing Manager
    // Publishes and retrieves OpenPGP keys via PubSub/PEP
    // Compatible with Conversations, Monocles, and other modern XMPP clients
    
    public class Xep0373KeyManager : Object {
        
        private StreamInteractor stream_interactor;
        private Database db;
        
        public signal void key_received(Account account, Jid jid, string fingerprint, string key_data);
        
        public Xep0373KeyManager(StreamInteractor stream_interactor, Database db) {
            this.stream_interactor = stream_interactor;
            this.db = db;
            
            stream_interactor.stream_negotiated.connect(on_stream_negotiated);
        }
        
        private void on_stream_negotiated(Account account, XmppStream stream) {
            debug("XEP-0373: Stream negotiated for %s, publishing key...", account.bare_jid.to_string());
            // When stream is established, publish our key via XEP-0373 if we have one
            publish_own_key_async.begin(account, stream);
            
            // Connect to the XEP-0373 module signals
            Xmpp.Xep.OpenPgp.Module? module = stream.get_module(Xmpp.Xep.OpenPgp.Module.IDENTITY);
            if (module != null) {
                module.public_keys_received.connect((stream_, jid, keys) => {
                    on_public_keys_received(account, stream_, jid, keys);
                });
                debug("XEP-0373: Connected to module signals");
            } else {
                debug("XEP-0373: Module NOT found on stream!");
            }
        }
        
        private async void publish_own_key_async(Account account, XmppStream stream) {
            string? key_id = db.get_account_key(account);
            if (key_id == null) {
                debug("XEP-0373: No key configured for account %s", account.bare_jid.to_string());
                return;
            }
            
            debug("XEP-0373: Publishing key %s for account %s", key_id, account.bare_jid.to_string());
            
            try {
                // Get the full key data for publishing
                GPGHelper.Key? key = GPGHelper.get_private_key(key_id);
                if (key == null) {
                    debug("XEP-0373: Could not get key %s for publishing", key_id);
                    return;
                }
                
                debug("XEP-0373: Got private key, fingerprint: %s", key.fpr);
                
                // Export the public key in ASCII armor format
                string? armored_key = GPGHelper.export_public_key(key_id);
                if (armored_key == null) {
                    debug("XEP-0373: Could not export public key %s", key_id);
                    return;
                }
                
                debug("XEP-0373: Exported public key, length: %d bytes", armored_key.length);
                
                // Get the fingerprint
                string fingerprint = key.fpr;
                
                // Get the XEP-0373 module
                Xmpp.Xep.OpenPgp.Module? module = stream.get_module(Xmpp.Xep.OpenPgp.Module.IDENTITY);
                if (module == null) {
                    debug("XEP-0373: Module not loaded on stream");
                    return;
                }
                
                // Publish the key
                yield module.publish_key(stream, fingerprint, armored_key);
                
                debug("XEP-0373: Successfully published key %s for %s", fingerprint, account.bare_jid.to_string());
                
            } catch (Error e) {
                debug("XEP-0373: Failed to publish key: %s", e.message);
            }
        }
        
        private void on_public_keys_received(Account account, XmppStream stream, Jid jid, Gee.List<Xmpp.Xep.OpenPgp.PublicKeyMeta> keys) {
            // Fetch and import each key
            foreach (var key_meta in keys) {
                fetch_and_import_key.begin(account, stream, jid, key_meta.fingerprint);
            }
        }
        
        private async void fetch_and_import_key(Account account, XmppStream stream, Jid jid, string fingerprint) {
            try {
                Xmpp.Xep.OpenPgp.Module? module = stream.get_module(Xmpp.Xep.OpenPgp.Module.IDENTITY);
                if (module == null) return;
                
                Xmpp.Xep.OpenPgp.PublicKeyData? key_data = yield module.fetch_public_key(stream, jid, fingerprint);
                if (key_data == null) {
                    debug("XEP-0373: No key data for %s from %s", fingerprint, jid.to_string());
                    return;
                }
                
                // Import the key into our keyring
                debug("XEP-0373: About to import key, first 200 chars: %.200s", key_data.armored_key);
                GPGHelper.import_key(key_data.armored_key);
                
                debug("XEP-0373: Imported key %s from %s", fingerprint, jid.to_string());
                
                // Notify listeners
                key_received(account, jid, fingerprint, key_data.armored_key);
                
            } catch (Error e) {
                debug("XEP-0373: Failed to fetch/import key %s from %s: %s", 
                        fingerprint, jid.to_string(), e.message);
            }
        }
        
        // Manually request keys from a contact
        public async void request_keys(Account account, Jid jid) {
            XmppStream? stream = stream_interactor.get_stream(account);
            if (stream == null) {
                debug("XEP-0373: Cannot request keys - no stream for %s", account.bare_jid.to_string());
                return;
            }
            
            Xmpp.Xep.OpenPgp.Module? module = stream.get_module(Xmpp.Xep.OpenPgp.Module.IDENTITY);
            if (module == null) {
                debug("XEP-0373: Cannot request keys - XEP-0373 module not loaded");
                return;
            }
            
            try {
                debug("XEP-0373: Requesting keys from %s via PubSub node %s", jid.to_string(), "urn:xmpp:openpgp:0:public-keys");
                Gee.List<Xmpp.Xep.OpenPgp.PublicKeyMeta>? keys = yield module.fetch_public_keys_list(stream, jid);
                
                if (keys == null || keys.size == 0) {
                    debug("XEP-0373: No keys found for %s (contact may not have published any)", jid.to_string());
                    return;
                }
                
                debug("XEP-0373: Found %d key(s) for %s", keys.size, jid.to_string());
                
                foreach (var key_meta in keys) {
                    yield fetch_and_import_key(account, stream, jid, key_meta.fingerprint);
                }
            } catch (Error e) {
                debug("XEP-0373: Failed to request keys from %s: %s", jid.to_string(), e.message);
            }
        }
        
        // Public method to republish our key (called when user changes key in settings)
        public void republish_key(Account account) {
            XmppStream? stream = stream_interactor.get_stream(account);
            if (stream == null) {
                debug("XEP-0373: Cannot republish key - no stream for %s", account.bare_jid.to_string());
                return;
            }
            
            debug("XEP-0373: Republishing key for account %s", account.bare_jid.to_string());
            publish_own_key_async.begin(account, stream);
        }
    }
}
