using Dino.Entities;
using Gtk;
using Qlite;
using Xmpp;

namespace Dino.Plugins.Omemo {

// Helper function for async sleep
private async void sleep_async(uint milliseconds) {
    Timeout.add(milliseconds, () => {
        sleep_async.callback();
        return false;
    });
    yield;
}

public class EncryptionListEntry : Plugins.EncryptionListEntry, Object {
    private Plugin plugin;
    private Database db;

    public EncryptionListEntry(Plugin plugin) {
        this.plugin = plugin;
        this.db = plugin.db;
    }

    public Entities.Encryption encryption { get {
        return Entities.Encryption.OMEMO;
    }}

    public string name { get {
        return "OMEMO";
    }}

    public Object? get_encryption_icon(Entities.Conversation conversation, ContentItem content_item) {
        return null;
    }

    public string? get_encryption_icon_name(Entities.Conversation conversation, ContentItem content_item) {
        if (content_item.encryption != encryption) return null;

        RowOption row = db.content_item_meta.select( { db.identity_meta.trust_level } ).with(db.content_item_meta.content_item_id, "=", content_item.id)
            .join_on(db.identity_meta, @"$(db.identity_meta.address_name)=$(db.content_item_meta.address_name) AND $(db.identity_meta.device_id)=$(db.content_item_meta.device_id)")
            .single().row();


        if (row.is_present() && (TrustLevel) row[db.identity_meta.trust_level] == TrustLevel.VERIFIED) {
            return "dino-security-high-symbolic";
        }
        return null;
    }

    public void encryption_activated(Entities.Conversation conversation, Plugins.SetInputFieldStatus input_status_callback) {
        encryption_activated_async.begin(conversation, input_status_callback);
    }

    public async void encryption_activated_async(Entities.Conversation conversation, Plugins.SetInputFieldStatus input_status_callback) {
        if (conversation.type_ == Conversation.Type.GROUPCHAT_PM) {
            input_status_callback(new Plugins.InputFieldStatus("Can't use encryption in a groupchat private message.", Plugins.InputFieldStatus.MessageType.ERROR, Plugins.InputFieldStatus.InputState.NO_SEND));
            return;
        }
        
        // Check if our own OMEMO identity is initialized
        int identity_id = db.identity.get_id(conversation.account.id);
        if (identity_id < 0) {
            // Identity not yet created - OMEMO is still initializing (e.g. after Panic Wipe)
            input_status_callback(new Plugins.InputFieldStatus("OMEMO is initializing, please wait a moment...", Plugins.InputFieldStatus.MessageType.INFO, Plugins.InputFieldStatus.InputState.NO_SEND));
            
            // Wait for initialization (up to 5 seconds)
            for (int i = 0; i < 10; i++) {
                yield sleep_async(500);
                identity_id = db.identity.get_id(conversation.account.id);
                if (identity_id >= 0) break;
            }
            
            if (identity_id < 0) {
                input_status_callback(new Plugins.InputFieldStatus("OMEMO initialization failed. Please try again.", Plugins.InputFieldStatus.MessageType.ERROR, Plugins.InputFieldStatus.InputState.NO_SEND));
                return;
            }
            // Clear the "initializing" message
            input_status_callback(new Plugins.InputFieldStatus("", Plugins.InputFieldStatus.MessageType.NONE, Plugins.InputFieldStatus.InputState.NORMAL));
        }
        
        MucManager muc_manager = plugin.app.stream_interactor.get_module<MucManager>(MucManager.IDENTITY);
        Manager omemo_manager = plugin.app.stream_interactor.get_module<Manager>(Manager.IDENTITY);

        if (conversation.type_ == Conversation.Type.GROUPCHAT) {
            // MUC path: never fall through to 1:1 check (MUC JID has no OMEMO keys)
            bool is_private = muc_manager.is_private_room(conversation.account, conversation.counterpart);
            if (!is_private) {
                // Room features (disco#info) may not be loaded yet after (re)join — wait briefly
                for (int i = 0; i < 6; i++) {
                    yield sleep_async(500);
                    is_private = muc_manager.is_private_room(conversation.account, conversation.counterpart);
                    if (is_private) break;
                }
            }
            if (!is_private) {
                // Still not private after waiting — public room or features unavailable
                input_status_callback(new Plugins.InputFieldStatus("OMEMO can't be used in public (non-members-only) rooms.", Plugins.InputFieldStatus.MessageType.ERROR, Plugins.InputFieldStatus.InputState.NO_SEND));
                return;
            }
            var offline_members = muc_manager.get_offline_members(conversation.counterpart, conversation.account);
            if (offline_members == null) {
                // Offline members not available (still joining or offline)
                return;
            }
            foreach (Jid offline_member in offline_members) {
                bool ok = yield omemo_manager.ensure_get_keys_for_jid(conversation.account, offline_member);
                if (!ok) {
                    input_status_callback(new Plugins.InputFieldStatus("A member does not support OMEMO: %s".printf(offline_member.to_string()), Plugins.InputFieldStatus.MessageType.ERROR, Plugins.InputFieldStatus.InputState.NO_SEND));
                    return;
                }
            }
            return;
        }

        if (!(yield omemo_manager.ensure_get_keys_for_jid(conversation.account, conversation.counterpart.bare_jid))) {
            input_status_callback(new Plugins.InputFieldStatus("This contact does not support %s encryption".printf("OMEMO"), Plugins.InputFieldStatus.MessageType.ERROR, Plugins.InputFieldStatus.InputState.NO_SEND));
        }
    }

}
}
