using Gtk;
using Gee;
using Qlite;
using Dino.Entities;
using Xmpp;

namespace Dino.Plugins.Omemo {

public class ContactDetailsProvider : Plugins.ContactDetailsProvider, Object {
    public string id { get { return "omemo_info"; } }
    public string tab { get { return "encryption"; } }

    private Plugin plugin;

    public ContactDetailsProvider(Plugin plugin) {
        this.plugin = plugin;
    }

    public void populate(Conversation conversation, Plugins.ContactDetails contact_details, WidgetType type) { }

    public Object? get_widget(Conversation conversation) {
        if (conversation.type_ == Conversation.Type.CHAT) {
            // 1:1 Chat - show OMEMO widget for the counterpart
            var widget = new OmemoPreferencesWidget(plugin);
            widget.set_jid(conversation.account, conversation.counterpart);
            return widget;
        } else if (conversation.type_ == Conversation.Type.GROUPCHAT) {
            // MUC - show OMEMO widgets for all members with known real JIDs
            return create_muc_omemo_widget(conversation);
        }
        return null;
    }
    
    private Adw.PreferencesGroup? create_muc_omemo_widget(Conversation conversation) {
        Dino.Application? app = GLib.Application.get_default() as Dino.Application;
        if (app == null) return null;
        
        var muc_manager = app.stream_interactor.get_module<MucManager>(MucManager.IDENTITY);
        
        // Get offline members (these have real JIDs stored)
        Gee.List<Jid>? members = muc_manager.get_offline_members(conversation.counterpart, conversation.account);
        
        if (members == null || members.size == 0) {
            // No members with known JIDs - might be an anonymous MUC
            var group = new Adw.PreferencesGroup();
            group.title = _("OMEMO Encryption");
            group.description = _("No member JIDs available. This may be an anonymous room.");
            return group;
        }
        
        // Create a container for all member OMEMO widgets
        var main_group = new Adw.PreferencesGroup();
        main_group.title = _("OMEMO Encryption");
        main_group.description = _("Encryption keys for room members");
        
        // Add expander rows for each member
        foreach (Jid member_jid in members) {
            // Skip our own JID
            if (member_jid.equals_bare(conversation.account.bare_jid)) continue;
            
            // Check if we have any OMEMO keys for this member
            int identity_id = plugin.db.identity.get_id(conversation.account.id);
            if (identity_id <= 0) continue;
            
            // Count devices and collect them
            var devices = new Gee.ArrayList<Row>();
            foreach (Row device in plugin.db.identity_meta.get_known_devices(identity_id, member_jid.bare_jid.to_string())) {
                devices.add(device);
            }
            
            if (devices.size == 0) continue;
            
            // Create an expander row for this member
            var expander = new Adw.ExpanderRow();
            expander.title = member_jid.bare_jid.to_string();
            expander.subtitle = ngettext("%d device", "%d devices", devices.size).printf(devices.size);
            
            // Add device fingerprints
            foreach (Row device in devices) {
                string? key_base64 = device[plugin.db.identity_meta.identity_key_public_base64];
                if (key_base64 == null) continue;
                
                string fingerprint = fingerprint_from_base64(key_base64);
                TrustLevel trust_level = (TrustLevel) device[plugin.db.identity_meta.trust_level];
                
                var device_row = new Adw.ActionRow();
                device_row.title = format_fingerprint(fingerprint);
                device_row.subtitle = trust_level_to_string(trust_level);
                device_row.add_css_class("monospace");
                
                // Add trust indicator
                var trust_icon = new Gtk.Image();
                switch (trust_level) {
                    case TrustLevel.VERIFIED:
                        trust_icon.icon_name = "emblem-ok-symbolic";
                        trust_icon.add_css_class("success");
                        break;
                    case TrustLevel.TRUSTED:
                        trust_icon.icon_name = "emblem-default-symbolic";
                        trust_icon.add_css_class("success");
                        break;
                    case TrustLevel.UNTRUSTED:
                        trust_icon.icon_name = "dialog-warning-symbolic";
                        trust_icon.add_css_class("warning");
                        break;
                    default:
                        trust_icon.icon_name = "dialog-question-symbolic";
                        break;
                }
                device_row.add_suffix(trust_icon);
                
                expander.add_row(device_row);
            }
            
            main_group.add(expander);
        }
        
        return main_group;
    }
    
    private string format_fingerprint(string fingerprint) {
        // Format fingerprint in groups of 8 characters
        var builder = new StringBuilder();
        for (int i = 0; i < fingerprint.length; i++) {
            if (i > 0 && i % 8 == 0) {
                builder.append(" ");
            }
            builder.append_c(fingerprint[i]);
        }
        return builder.str;
    }
    
    private string trust_level_to_string(TrustLevel level) {
        switch (level) {
            case TrustLevel.VERIFIED:
                return _("Verified");
            case TrustLevel.TRUSTED:
                return _("Trusted");
            case TrustLevel.UNTRUSTED:
                return _("Untrusted");
            default:
                return _("Unknown");
        }
    }
}

}
