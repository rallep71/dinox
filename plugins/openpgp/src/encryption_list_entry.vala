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
        return null;
    }

    public string? get_encryption_icon_name(Entities.Conversation conversation, ContentItem content_item) {
        return null;
    }

    public void encryption_activated(Entities.Conversation conversation, Plugins.SetInputFieldStatus input_status_callback) {
        // Check if we have our own key configured
        try {
            GPGHelper.get_public_key(db.get_account_key(conversation.account) ?? "");
        } catch (Error e) {
            input_status_callback(new Plugins.InputFieldStatus("You didn't configure OpenPGP for this account. You can do that in the Accounts Dialog.", Plugins.InputFieldStatus.MessageType.ERROR, Plugins.InputFieldStatus.InputState.NO_SEND));
            return;
        }
        
        // Re-publish our key to ensure the contact can get it
        // This is important when switching to OpenPGP - the contact should receive our key immediately
        if (xep0373_manager != null) {
            debug("OpenPGP: Re-publishing own key for encryption activation");
            xep0373_manager.republish_key(conversation.account);
        }

        if (conversation.type_ == Conversation.Type.CHAT) {
            // First check if we already have the contact's key locally
            string? key_id = db.get_contact_key(conversation.counterpart.bare_jid);
            
            if (key_id != null) {
                // We have the key, verify it's in keyring
                try {
                    GPGHelper.get_keylist(key_id);
                    // Key is valid, encryption can proceed
                    debug("OpenPGP: Contact key found locally: %s", key_id);
                    return;
                } catch (Error e) {
                    input_status_callback(new Plugins.InputFieldStatus("This contact's OpenPGP key is not in your keyring.", Plugins.InputFieldStatus.MessageType.ERROR, Plugins.InputFieldStatus.InputState.NO_SEND));
                    return;
                }
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
            Gee.List<Jid> muc_jids = new Gee.ArrayList<Jid>();
            Gee.List<Jid>? occupants = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).get_occupants(conversation.counterpart, conversation.account);
            if (occupants != null) muc_jids.add_all(occupants);
            Gee.List<Jid>? offline_members = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).get_offline_members(conversation.counterpart, conversation.account);
            if (offline_members != null) muc_jids.add_all(offline_members);

            foreach (Jid jid in muc_jids) {
                string? key_id = stream_interactor.get_module<Manager>(Manager.IDENTITY).get_key_id(conversation.account, jid);
                if (key_id == null) {
                    input_status_callback(new Plugins.InputFieldStatus("A member's OpenPGP key is not in your keyring: %s / %s.".printf(jid.to_string(), key_id), Plugins.InputFieldStatus.MessageType.ERROR, Plugins.InputFieldStatus.InputState.NO_SEND));
                    return;
                }
            }
        }
    }
    
    // Async fetch key and update input field status when complete
    private async void fetch_key_and_update_status(Entities.Conversation conversation, Plugins.SetInputFieldStatus input_status_callback) {
        if (xep0373_manager == null) return;
        
        try {
            // Request keys from contact via XEP-0373 PubSub
            yield xep0373_manager.request_keys(conversation.account, conversation.counterpart.bare_jid);
            
            // Wait a moment for the key to be imported and stored in DB
            // The signal handler in plugin.vala stores the key when received
            Timeout.add(500, () => {
                // Check if we now have the key
                string? key_id = db.get_contact_key(conversation.counterpart.bare_jid);
                
                if (key_id != null) {
                    try {
                        GPGHelper.get_keylist(key_id);
                        // Success! Key was fetched and imported
                        debug("OpenPGP: Successfully fetched key %s for %s", key_id, conversation.counterpart.to_string());
                        input_status_callback(new Plugins.InputFieldStatus("", Plugins.InputFieldStatus.MessageType.NONE, Plugins.InputFieldStatus.InputState.NORMAL));
                    } catch (Error e) {
                        debug("OpenPGP: Key %s fetched but not in keyring: %s", key_id, e.message);
                        input_status_callback(new Plugins.InputFieldStatus("This contact's OpenPGP key is not in your keyring.", Plugins.InputFieldStatus.MessageType.ERROR, Plugins.InputFieldStatus.InputState.NO_SEND));
                    }
                } else {
                    // No key published by contact
                    debug("OpenPGP: No XEP-0373 key published by %s", conversation.counterpart.to_string());
                    input_status_callback(new Plugins.InputFieldStatus("This contact has not published an OpenPGP key.", Plugins.InputFieldStatus.MessageType.ERROR, Plugins.InputFieldStatus.InputState.NO_SEND));
                }
                return false; // Don't repeat timeout
            });
            
        } catch (Error e) {
            debug("OpenPGP: Failed to fetch XEP-0373 keys: %s", e.message);
            input_status_callback(new Plugins.InputFieldStatus("Failed to fetch contact's OpenPGP key: %s".printf(e.message), Plugins.InputFieldStatus.MessageType.ERROR, Plugins.InputFieldStatus.InputState.NO_SEND));
        }
    }
}

}
