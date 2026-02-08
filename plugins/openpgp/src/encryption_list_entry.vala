using Gee;
using Gtk;

using Dino.Entities;
using Xmpp;

namespace Dino.Plugins.OpenPgp {

private class EncryptionListEntry : Plugins.EncryptionListEntry, Object {

    private StreamInteractor stream_interactor;
    private Database db;
    private Xep0373KeyManager? xep0373_manager = null;

    public EncryptionListEntry(StreamInteractor stream_interactor, Database db) {
        this.stream_interactor = stream_interactor;
        this.db = db;
    }
    
    // Allow plugin to set XEP-0373 manager reference
    public void set_xep0373_manager(Xep0373KeyManager? manager) {
        this.xep0373_manager = manager;
    }

    public Entities.Encryption encryption { get {
        return Encryption.PGP;
    }}

    public string name { get {
        return "OpenPGP";
    }}

    public Object? get_encryption_icon(Entities.Conversation conversation, ContentItem content_item) {
        if (conversation == null) return null;
        return null;
    }

    public string? get_encryption_icon_name(Entities.Conversation conversation, ContentItem content_item) {
        if (conversation == null) return null;
        return null;
    }

    public void encryption_activated(Entities.Conversation conversation, Plugins.SetInputFieldStatus input_status_callback) {
        // Null check to prevent assertion failures
        if (conversation == null) {
            input_status_callback(new Plugins.InputFieldStatus("No conversation selected.", Plugins.InputFieldStatus.MessageType.ERROR, Plugins.InputFieldStatus.InputState.NO_SEND));
            return;
        }
        
        // Run key checks in background to avoid blocking UI
        string? account_key = db.get_account_key(conversation.account);
        
        if (account_key == null || account_key.length == 0) {
            input_status_callback(new Plugins.InputFieldStatus("You didn't configure OpenPGP for this account. You can do that in the Accounts Dialog.", Plugins.InputFieldStatus.MessageType.ERROR, Plugins.InputFieldStatus.InputState.NO_SEND));
            return;
        }
        
        // Re-publish our key to ensure the contact can get it
        if (xep0373_manager != null) {
            debug("OpenPGP: Re-publishing own key for encryption activation");
            xep0373_manager.republish_key(conversation.account);
        }

        if (conversation.type_ == Conversation.Type.CHAT) {
            // First check if we already have the contact's key locally
            string? key_id = db.get_contact_key(conversation.counterpart.bare_jid);
            
            if (key_id != null) {
                // Verify key in background thread and cache it
                string key_id_copy = key_id;
                new Thread<void*>("openpgp-check-key", () => {
                    GPGHelper.Key? key = null;
                    try {
                        key = GPGHelper.get_public_key(key_id_copy);
                    } catch (Error e) {
                        debug("OpenPGP: Key check failed: %s", e.message);
                    }
                    
                    Idle.add(() => {
                        // Cache the key (or null if invalid) for future use
                        var manager = stream_interactor.get_module<Manager>(Manager.IDENTITY);
                        if (manager != null) {
                            manager.cache_key(key_id_copy, key);
                        }
                        
                        if (key != null) {
                            debug("OpenPGP: Contact key found locally: %s", key_id_copy);
                            // Clear any error status
                            input_status_callback(new Plugins.InputFieldStatus("", Plugins.InputFieldStatus.MessageType.NONE, Plugins.InputFieldStatus.InputState.NORMAL));
                        } else {
                            input_status_callback(new Plugins.InputFieldStatus("This contact's OpenPGP key is not in your keyring.", Plugins.InputFieldStatus.MessageType.ERROR, Plugins.InputFieldStatus.InputState.NO_SEND));
                        }
                        return false;
                    });
                    return null;
                });
                return;
            }
            
            // No key locally - try to fetch via XEP-0373
            if (xep0373_manager != null) {
                debug("OpenPGP: No local key for %s, fetching via XEP-0373...", conversation.counterpart.to_string());
                input_status_callback(new Plugins.InputFieldStatus("Fetching contact's OpenPGP key via PubSub...", Plugins.InputFieldStatus.MessageType.INFO, Plugins.InputFieldStatus.InputState.NO_SEND));
                
                // Async fetch keys and update status when done
                fetch_key_and_update_status.begin(conversation, input_status_callback);
            } else {
                input_status_callback(new Plugins.InputFieldStatus("This contact does not support %s encryption.".printf("OpenPGP"), Plugins.InputFieldStatus.MessageType.ERROR, Plugins.InputFieldStatus.InputState.NO_SEND));
            }
        } else if (conversation.type_ == Conversation.Type.GROUPCHAT) {
            // Run MUC key checks in background thread
            Gee.List<Jid> muc_jids = new Gee.ArrayList<Jid>();
            Gee.List<Jid>? occupants = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).get_occupants(conversation.counterpart, conversation.account);
            if (occupants != null) muc_jids.add_all(occupants);
            Gee.List<Jid>? offline_members = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).get_offline_members(conversation.counterpart, conversation.account);
            if (offline_members != null) muc_jids.add_all(offline_members);

            // Preload account key for MUC
            string? muc_account_key = db.get_account_key(conversation.account);
            if (muc_account_key != null) {
                var manager = stream_interactor.get_module<Manager>(Manager.IDENTITY);
                if (manager != null) {
                    manager.preload_key_async(muc_account_key);
                }
            }

            // Check MUC member keys in background
            check_muc_keys_async.begin(conversation.account, muc_jids, input_status_callback);
        }
    }
    
    // Async check MUC member keys
    private async void check_muc_keys_async(Account account, Gee.List<Jid> muc_jids, Plugins.SetInputFieldStatus input_status_callback) {
        var manager = stream_interactor.get_module<Manager>(Manager.IDENTITY);
        if (manager == null) {
            input_status_callback(new Plugins.InputFieldStatus("OpenPGP manager not available.", Plugins.InputFieldStatus.MessageType.ERROR, Plugins.InputFieldStatus.InputState.NO_SEND));
            return;
        }
        
        // Collect all key IDs first (this is fast, just DB lookup)
        var key_ids_to_check = new Gee.ArrayList<string>();
        foreach (Jid jid in muc_jids) {
            string? key_id = manager.get_key_id(account, jid);
            if (key_id == null) {
                input_status_callback(new Plugins.InputFieldStatus("A member's OpenPGP key is not configured: %s".printf(jid.to_string()), Plugins.InputFieldStatus.MessageType.ERROR, Plugins.InputFieldStatus.InputState.NO_SEND));
                return;
            }
            if (!key_ids_to_check.contains(key_id)) {
                key_ids_to_check.add(key_id);
            }
        }
        
        // Check keys in background thread
        new Thread<void*>("openpgp-check-muc-keys", () => {
            string? missing_key = null;
            
            foreach (string key_id in key_ids_to_check) {
                try {
                    var key = GPGHelper.get_public_key(key_id);
                    // Cache the result
                    Idle.add(() => {
                        if (manager != null) {
                            manager.cache_key(key_id, key);
                        }
                        return false;
                    });
                    
                    if (key == null) {
                        missing_key = key_id;
                        break;
                    }
                } catch (Error e) {
                    debug("OpenPGP: Failed to check MUC key %s: %s", key_id, e.message);
                    missing_key = key_id;
                    break;
                }
            }
            
            Idle.add(() => {
                if (missing_key != null) {
                    input_status_callback(new Plugins.InputFieldStatus("A member's OpenPGP key is not in your keyring: %s".printf(missing_key), Plugins.InputFieldStatus.MessageType.ERROR, Plugins.InputFieldStatus.InputState.NO_SEND));
                } else {
                    input_status_callback(new Plugins.InputFieldStatus("", Plugins.InputFieldStatus.MessageType.NONE, Plugins.InputFieldStatus.InputState.NORMAL));
                }
                return false;
            });
            
            return null;
        });
    }
    
    // Async fetch key and update input field status when complete
    private async void fetch_key_and_update_status(Entities.Conversation conversation, Plugins.SetInputFieldStatus input_status_callback) {
        if (xep0373_manager == null) return;
        
        // Request keys from contact via XEP-0373 PubSub
        yield xep0373_manager.request_keys(conversation.account, conversation.counterpart.bare_jid);
        
        // Wait a moment for the key to be imported and stored in DB
        // The signal handler in plugin.vala stores the key when received
        Timeout.add(500, () => {
            // Check if we now have the key
            string? key_id = db.get_contact_key(conversation.counterpart.bare_jid);
            
            if (key_id != null) {
                // Verify and cache in background thread
                string key_id_copy = key_id;
                new Thread<void*>("openpgp-verify-fetched", () => {
                    GPGHelper.Key? key = null;
                    try {
                        key = GPGHelper.get_public_key(key_id_copy);
                    } catch (Error e) {
                        debug("OpenPGP: Key check failed: %s", e.message);
                    }
                    
                    Idle.add(() => {
                        // Cache the key (or null if invalid)
                        var manager = stream_interactor.get_module<Manager>(Manager.IDENTITY);
                        if (manager != null) {
                            manager.cache_key(key_id_copy, key);
                        }
                        
                        if (key != null) {
                            debug("OpenPGP: Successfully fetched and cached key %s for %s", key_id_copy, conversation.counterpart.to_string());
                            input_status_callback(new Plugins.InputFieldStatus("", Plugins.InputFieldStatus.MessageType.NONE, Plugins.InputFieldStatus.InputState.NORMAL));
                        } else {
                            debug("OpenPGP: Key %s fetched but not in keyring", key_id_copy);
                            input_status_callback(new Plugins.InputFieldStatus("This contact's OpenPGP key is not in your keyring.", Plugins.InputFieldStatus.MessageType.ERROR, Plugins.InputFieldStatus.InputState.NO_SEND));
                        }
                        return false;
                    });
                    return null;
                });
            } else {
                // No key published by contact
                debug("OpenPGP: No XEP-0373 key published by %s", conversation.counterpart.to_string());
                input_status_callback(new Plugins.InputFieldStatus("This contact has not published an OpenPGP key.", Plugins.InputFieldStatus.MessageType.ERROR, Plugins.InputFieldStatus.InputState.NO_SEND));
            }
            return false; // Don't repeat timeout
        });
    }
}

}
