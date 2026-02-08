/**
 * XEP-0373: OpenPGP for XMPP
 * 
 * This module handles the PubSub-based key distribution for OpenPGP.
 * It publishes and retrieves public keys via PEP (Personal Eventing Protocol).
 * 
 * Nodes:
 * - urn:xmpp:openpgp:0:public-keys - List of public key metadata
 * - urn:xmpp:openpgp:0:public-keys:[fingerprint] - Individual public key data
 * 
 * This complements XEP-0027 (legacy presence signing) with modern PubSub-based
 * key discovery, enabling interoperability with clients like Conversations.
 */

using Gee;

namespace Xmpp.Xep.OpenPgp {

    public const string NS_URI = "urn:xmpp:openpgp:0";
    public const string NS_URI_PUBKEYS = NS_URI + ":public-keys";

    /**
     * Metadata about a published public key
     */
    public class PublicKeyMeta {
        public string fingerprint { get; set; }
        public DateTime? date { get; set; }
        
        public PublicKeyMeta(string fingerprint, DateTime? date = null) {
            this.fingerprint = fingerprint;
            this.date = date;
        }
    }

    /**
     * A full public key with its armored data
     */
    public class PublicKeyData {
        public string fingerprint { get; set; }
        public string armored_key { get; set; }
        public DateTime? date { get; set; }
        
        public PublicKeyData(string fingerprint, string armored_key, DateTime? date = null) {
            this.fingerprint = fingerprint;
            this.armored_key = armored_key;
            this.date = date;
        }
    }

    public class Module : XmppStreamModule {
        public static ModuleIdentity<Module> IDENTITY = new ModuleIdentity<Module>(NS_URI, "0373_openpgp");

        /**
         * Signal emitted when we receive updated key metadata from a contact
         */
        public signal void public_keys_received(XmppStream stream, Jid jid, Gee.List<PublicKeyMeta> keys);

        public override void attach(XmppStream stream) {
            // Subscribe to notifications about public key updates
            stream.get_module<Pubsub.Module>(Pubsub.Module.IDENTITY).add_filtered_notification(
                stream, 
                NS_URI_PUBKEYS,
                on_pubkeys_item_received,
                null,
                null
            );
        }

        public override void detach(XmppStream stream) {
            stream.get_module<Pubsub.Module>(Pubsub.Module.IDENTITY).remove_filtered_notification(stream, NS_URI_PUBKEYS);
        }

        public override string get_ns() { return NS_URI; }
        public override string get_id() { return IDENTITY.id; }

        /**
         * Publish our public key to PEP
         * 
         * This publishes to two nodes:
         * 1. urn:xmpp:openpgp:0:public-keys - metadata list with fingerprint and date
         * 2. urn:xmpp:openpgp:0:public-keys:[fingerprint] - the actual key data
         */
        public async bool publish_key(XmppStream stream, string fingerprint, string armored_public_key) {
            var pubsub = stream.get_module<Pubsub.Module>(Pubsub.Module.IDENTITY);
            
            // Normalize fingerprint (uppercase, no spaces)
            string fp = fingerprint.up().replace(" ", "");
            
            debug("XEP-0373: publish_key called with fingerprint: %s", fp);
            
            // First, publish the actual key data to its own node
            string key_node = NS_URI_PUBKEYS + ":" + fp;
            
            debug("XEP-0373: Publishing to node: %s", key_node);
            
            // Build the pubkey element with base64-encoded key
            // XEP-0373 specifies: <pubkey><data>[BASE64 KEY]</data></pubkey>
            // Note: The armored_public_key is already ASCII, we base64 encode it for transport
            StanzaNode pubkey_node = new StanzaNode.build("pubkey", NS_URI)
                .add_self_xmlns()
                .put_node(new StanzaNode.build("data", NS_URI)
                    .put_node(new StanzaNode.text(Base64.encode(armored_public_key.data))));
            
            // Publish options for the key node - open access so contacts can retrieve it
            var key_publish_options = new Pubsub.PublishOptions();
            key_publish_options.settings["pubsub#access_model"] = Pubsub.ACCESS_MODEL_OPEN;
            key_publish_options.settings["pubsub#persist_items"] = "true";
            key_publish_options.settings["pubsub#max_items"] = "1";
            
            bool key_published = yield pubsub.publish(stream, null, key_node, fp, pubkey_node, key_publish_options);
            debug("XEP-0373: Key data publish result: %s", key_published ? "SUCCESS" : "FAILED");
            if (!key_published) {
                debug("XEP-0373: Failed to publish public key data to %s", key_node);
                return false;
            }
            
            // Now publish/update the metadata list
            // First retrieve existing list, then update it
            DateTime now = new DateTime.now_utc();
            string date_str = now.format_iso8601();
            
            debug("XEP-0373: Publishing metadata with date: %s", date_str);
            
            // Build pubkeys-list element
            // <public-keys-list><pubkey-metadata v4-fingerprint="..." date="..."/></public-keys-list>
            StanzaNode pubkeys_list = new StanzaNode.build("public-keys-list", NS_URI)
                .add_self_xmlns()
                .put_node(new StanzaNode.build("pubkey-metadata", NS_URI)
                    .put_attribute("v4-fingerprint", fp)
                    .put_attribute("date", date_str));
            
            // Publish options for the metadata node
            var meta_publish_options = new Pubsub.PublishOptions();
            meta_publish_options.settings["pubsub#access_model"] = Pubsub.ACCESS_MODEL_OPEN;
            meta_publish_options.settings["pubsub#persist_items"] = "true";
            meta_publish_options.settings["pubsub#max_items"] = "1";
            
            // Use a fixed item-id for the metadata (some servers require this)
            bool meta_published = yield pubsub.publish(stream, null, NS_URI_PUBKEYS, "current", pubkeys_list, meta_publish_options);
            debug("XEP-0373: Metadata publish result: %s", meta_published ? "SUCCESS" : "FAILED");
            if (!meta_published) {
                debug("XEP-0373: Failed to publish public key metadata to %s", NS_URI_PUBKEYS);
                return false;
            }
            
            debug("XEP-0373: Successfully published public key %s", fp);
            
            // Self-test: Try to retrieve our own key to verify it was published correctly
            Jid? own_jid = stream.get_flag(Bind.Flag.IDENTITY)?.my_jid;
            if (own_jid != null) {
                debug("XEP-0373: Self-test - retrieving our own published key from %s", own_jid.bare_jid.to_string());
                var self_keys = yield fetch_public_keys_list(stream, own_jid.bare_jid);
                if (self_keys != null && self_keys.size > 0) {
                    debug("XEP-0373: Self-test SUCCESS - found %d key(s) for ourselves", self_keys.size);
                } else {
                    debug("XEP-0373: Self-test FAILED - could not retrieve our own keys!");
                }
            }
            return true;
        }

        /**
         * Unpublish (retract) a public key from PEP.
         * This removes the key data node and updates the metadata list
         * to no longer include this fingerprint.
         *
         * @param stream The XMPP stream
         * @param fingerprint The fingerprint to retract (uppercase, no spaces)
         * @return true if successful
         */
        public async bool unpublish_key(XmppStream stream, string fingerprint) {
            var pubsub = stream.get_module<Pubsub.Module>(Pubsub.Module.IDENTITY);
            
            string fp = fingerprint.up().replace(" ", "");
            string key_node = NS_URI_PUBKEYS + ":" + fp;
            
            debug("XEP-0373: Unpublishing key %s – deleting node %s", fp, key_node);
            
            // 1. Delete the key data node entirely
            pubsub.delete_node(stream, null, key_node);
            
            // 2. Publish an empty metadata list so contacts know the key is gone
            StanzaNode empty_list = new StanzaNode.build("public-keys-list", NS_URI)
                .add_self_xmlns();
            
            var meta_publish_options = new Pubsub.PublishOptions();
            meta_publish_options.settings["pubsub#access_model"] = Pubsub.ACCESS_MODEL_OPEN;
            meta_publish_options.settings["pubsub#persist_items"] = "true";
            meta_publish_options.settings["pubsub#max_items"] = "1";
            
            bool meta_ok = yield pubsub.publish(stream, null, NS_URI_PUBKEYS, "current", empty_list, meta_publish_options);
            debug("XEP-0373: Metadata cleared: %s", meta_ok ? "SUCCESS" : "FAILED");
            
            return meta_ok;
        }

        /**
         * Retrieve the list of public key metadata from a contact
         */
        public async Gee.List<PublicKeyMeta>? fetch_public_keys_list(XmppStream stream, Jid jid) {
            var pubsub = stream.get_module<Pubsub.Module>(Pubsub.Module.IDENTITY);
            
            debug("XEP-0373: Fetching public keys list from %s, node: %s", jid.to_string(), NS_URI_PUBKEYS);
            var items = yield pubsub.request_all(stream, jid, NS_URI_PUBKEYS);
            
            if (items == null) {
                debug("XEP-0373: PubSub request_all returned null for %s", jid.to_string());
                return null;
            }
            
            if (items.size == 0) {
                debug("XEP-0373: PubSub returned empty items list for %s", jid.to_string());
                return null;
            }
            
            debug("XEP-0373: Got %d item(s) from PubSub for %s", items.size, jid.to_string());
            
            var result = new ArrayList<PublicKeyMeta>();
            
            foreach (var item in items) {
                debug("XEP-0373: Processing item: %s", item.to_string());
                
                // Try to find the public-keys-list element
                StanzaNode? pubkeys_list = item.get_subnode("public-keys-list", NS_URI);
                if (pubkeys_list == null) {
                    // Maybe the content is directly in the item
                    pubkeys_list = item.get_subnode("public-keys-list");
                }
                if (pubkeys_list == null) {
                    // Maybe the item IS the public-keys-list
                    if (item.name == "public-keys-list") {
                        pubkeys_list = item;
                    }
                }
                if (pubkeys_list == null) {
                    debug("XEP-0373: Item has no public-keys-list element");
                    continue;
                }
                
                // Find pubkey-metadata elements
                var meta_nodes = pubkeys_list.get_subnodes("pubkey-metadata", NS_URI);
                if (meta_nodes.size == 0) {
                    meta_nodes = pubkeys_list.get_subnodes("pubkey-metadata");
                }
                
                debug("XEP-0373: Found %d pubkey-metadata node(s)", meta_nodes.size);
                
                foreach (var meta_node in meta_nodes) {
                    string? fp = meta_node.get_attribute("v4-fingerprint");
                    string? date_str = meta_node.get_attribute("date");
                    
                    if (fp != null) {
                        DateTime? date = null;
                        if (date_str != null) {
                            date = new DateTime.from_iso8601(date_str, new TimeZone.utc());
                        }
                        result.add(new PublicKeyMeta(fp.up(), date));
                    }
                }
            }
            
            debug("XEP-0373: Found %d public key(s) for %s", result.size, jid.to_string());
            return result;
        }

        /**
         * Retrieve a specific public key from a contact
         */
        public async PublicKeyData? fetch_public_key(XmppStream stream, Jid jid, string fingerprint) {
            var pubsub = stream.get_module<Pubsub.Module>(Pubsub.Module.IDENTITY);
            
            string fp = fingerprint.up().replace(" ", "");
            string key_node = NS_URI_PUBKEYS + ":" + fp;
            
            var key_stanza = yield pubsub.request_item(stream, jid, key_node, fp);
            if (key_stanza == null) {
                debug("XEP-0373: Could not fetch public key %s from %s", fp, jid.to_string());
                return null;
            }
            
            StanzaNode? data_node = key_stanza.get_subnode("data", NS_URI);
            if (data_node == null) {
                data_node = key_stanza.get_subnode("data"); // Try without namespace
            }
            
            if (data_node == null) {
                debug("XEP-0373: Key node has no data element");
                return null;
            }
            
            string? base64_key = data_node.get_string_content();
            if (base64_key == null) {
                debug("XEP-0373: Key data is empty");
                return null;
            }
            
            debug("XEP-0373: fetch_public_key - base64_key length: %d, first 100 chars: %.100s", 
                    base64_key.length, base64_key);
            
            // Decode base64 - the result should be ASCII-armored key
            uint8[] key_bytes = Base64.decode(base64_key);
            string armored_key = (string) key_bytes;
            
            debug("XEP-0373: fetch_public_key - decoded key length: %d, first 100 chars: %.100s", 
                    armored_key.length, armored_key);
            
            debug("XEP-0373: Successfully fetched public key %s from %s", fp, jid.to_string());
            return new PublicKeyData(fp, armored_key);
        }

        /**
         * Handle incoming PubSub notifications about public key updates
         */
        private void on_pubkeys_item_received(XmppStream stream, Jid jid, string id, StanzaNode? node) {
            if (node == null) return;
            debug("XEP-0373: Received public key update from %s", jid.to_string());
            
            var result = new ArrayList<PublicKeyMeta>();
            
            StanzaNode? pubkeys_list = node.get_subnode("public-keys-list", NS_URI);
            if (pubkeys_list == null) {
                pubkeys_list = node; // Maybe node is the list itself
            }
            
            foreach (var meta_node in pubkeys_list.get_subnodes("pubkey-metadata", NS_URI)) {
                string? fp = meta_node.get_attribute("v4-fingerprint");
                string? date_str = meta_node.get_attribute("date");
                
                if (fp != null) {
                    DateTime? date = null;
                    if (date_str != null) {
                        date = new DateTime.from_iso8601(date_str, new TimeZone.utc());
                    }
                    result.add(new PublicKeyMeta(fp.up(), date));
                }
            }
            
            if (result.size > 0) {
                public_keys_received(stream, jid, result);
            }
        }
    }
}
