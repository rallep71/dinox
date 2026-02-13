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
            var group = new Adw.PreferencesGroup();
            group.title = _("OMEMO Encryption");
            group.description = _("No member JIDs available. This may be an anonymous room.");
            return group;
        }
        
        var main_group = new Adw.PreferencesGroup();
        main_group.title = _("OMEMO Encryption");
        main_group.description = _("Encryption keys for room members");
        
        int identity_id = plugin.db.identity.get_id(conversation.account.id);
        if (identity_id <= 0) return main_group;
        
        // Sort: own JID first, then other members
        var sorted_members = new Gee.ArrayList<Jid>();
        Jid? own_jid = null;
        foreach (Jid member_jid in members) {
            if (member_jid.equals_bare(conversation.account.bare_jid)) {
                own_jid = member_jid;
            } else {
                sorted_members.add(member_jid);
            }
        }
        if (own_jid != null) sorted_members.insert(0, own_jid);
        
        foreach (Jid member_jid in sorted_members) {
            // Local copy for closures — Vala foreach vars are re-bound each iteration
            Jid the_jid = member_jid;
            bool is_own = the_jid.equals_bare(conversation.account.bare_jid);
            
            var known_devices = new Gee.ArrayList<Row>();
            int hidden_count = 0;
            foreach (Row device in plugin.db.identity_meta.get_known_devices(identity_id, the_jid.bare_jid.to_string())) {
                long last_ts = device[plugin.db.identity_meta.last_active];
                if (last_ts > 0) {
                    known_devices.add(device);
                } else {
                    hidden_count++;
                }
            }
            // Sort known devices by last_active descending (most recent first)
            known_devices.sort((a, b) => {
                long a_ts = a[plugin.db.identity_meta.last_active];
                long b_ts = b[plugin.db.identity_meta.last_active];
                if (a_ts > b_ts) return -1;
                if (a_ts < b_ts) return 1;
                return 0;
            });
            
            var new_devices = new Gee.ArrayList<Row>();
            foreach (Row device in plugin.db.identity_meta.get_new_devices(identity_id, the_jid.bare_jid.to_string())) {
                new_devices.add(device);
            }
            
            int total = known_devices.size + new_devices.size;
            if (total == 0 && hidden_count == 0) continue;
            
            // Expander row per member
            var expander = new Adw.ExpanderRow();
            expander.title = is_own ? _("Your devices") : the_jid.bare_jid.to_string();
            if (hidden_count > 0 && total > 0) {
                expander.subtitle = ngettext("%d device", "%d devices", total).printf(total) + " (+%d inactive)".printf(hidden_count);
            } else if (hidden_count > 0) {
                expander.subtitle = "%d inactive devices".printf(hidden_count);
            } else {
                expander.subtitle = ngettext("%d device", "%d devices", total).printf(total);
            }
            
            // Auto-accept toggle per member
            var auto_accept_row = new Adw.SwitchRow();
            auto_accept_row.title = _("Encrypt to new devices");
            auto_accept_row.subtitle = is_own
                ? _("Automatically accept new keys from your other devices.")
                : _("Automatically accept new keys from this contact.");
            auto_accept_row.active = plugin.db.trust.get_blind_trust(identity_id, the_jid.bare_jid.to_string(), true);
            auto_accept_row.notify["active"].connect(() => {
                plugin.trust_manager.set_blind_trust(conversation.account, the_jid, auto_accept_row.active);
            });
            expander.add_row(auto_accept_row);
            
            // Known devices — clickable for trust management
            foreach (Row device in known_devices) {
                string? key_base64 = device[plugin.db.identity_meta.identity_key_public_base64];
                if (key_base64 == null) continue;
                
                string fingerprint = fingerprint_from_base64(key_base64);
                TrustLevel trust_level = (TrustLevel) device[plugin.db.identity_meta.trust_level];
                int32 dev_id = device[plugin.db.identity_meta.device_id];
                string? device_label = device[plugin.db.identity_meta.device_label];
                
                string title_text;
                if (device_label != null && device_label.length > 0) {
                    title_text = @"$(device_label) #$(dev_id)";
                } else {
                    title_text = is_own ? _("Your device") + @" #$(dev_id)" : @"Device #$(dev_id)";
                }
                
                var device_row = new Adw.ActionRow() { use_markup = true };
                device_row.title = title_text;
                
                // Build subtitle: fingerprint + trust + last seen
                long last_active_ts = device[plugin.db.identity_meta.last_active];
                string last_seen = "";
                if (last_active_ts > 0) {
                    var last_dt = new DateTime.from_unix_utc(last_active_ts);
                    var now = new DateTime.now_utc();
                    var diff = now.difference(last_dt);
                    int days_ago = (int)(diff / TimeSpan.DAY);
                    if (days_ago == 0) {
                        last_seen = _("today");
                    } else if (days_ago == 1) {
                        last_seen = _("yesterday");
                    } else if (days_ago < 30) {
                        last_seen = _("%d days ago").printf(days_ago);
                    } else if (days_ago < 365) {
                        int months = days_ago / 30;
                        last_seen = ngettext("%d month ago", "%d months ago", months).printf(months);
                    } else {
                        int years = days_ago / 365;
                        last_seen = ngettext("%d year ago", "%d years ago", years).printf(years);
                    }
                    last_seen = " · " + _("Last seen") + ": " + last_seen;
                }
                device_row.subtitle = fingerprint_markup(fingerprint) + "\n" + trust_level_to_string(trust_level) + last_seen;
                device_row.activatable = true;
                
                // Click opens ManageKeyDialog for trust management
                device_row.activated.connect(() => {
                    Row? updated = plugin.db.identity_meta.get_device(identity_id, the_jid.bare_jid.to_string(), dev_id);
                    if (updated == null) return;
                    var manage_dialog = new ManageKeyDialog(updated, plugin.db);
                    manage_dialog.set_transient_for((Gtk.Window) main_group.get_root());
                    manage_dialog.present();
                    manage_dialog.response.connect((resp) => {
                        if (resp == -1) {
                            plugin.trust_manager.delete_device(conversation.account, the_jid, dev_id);
                        } else {
                            plugin.trust_manager.set_device_trust(conversation.account, the_jid, dev_id, (TrustLevel) resp);
                        }
                    });
                });
                
                // Trust indicator icon
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
            
            // New/pending devices — with accept/reject buttons
            foreach (Row device in new_devices) {
                string? key_base64 = device[plugin.db.identity_meta.identity_key_public_base64];
                if (key_base64 == null) continue;
                
                int32 dev_id = device[plugin.db.identity_meta.device_id];
                string? device_label = device[plugin.db.identity_meta.device_label];
                
                string title_text;
                if (device_label != null && device_label.length > 0) {
                    title_text = @"$(device_label) #$(dev_id)";
                } else {
                    title_text = _("New device") + @" #$(dev_id)";
                }
                
                var device_row = new Adw.ActionRow() { use_markup = true };
                device_row.title = title_text;
                device_row.subtitle = fingerprint_markup(fingerprint_from_base64(key_base64));
                
                var accept_btn = new Gtk.Button.from_icon_name("check-plain-symbolic");
                accept_btn.add_css_class("suggested-action");
                accept_btn.valign = Gtk.Align.CENTER;
                accept_btn.tooltip_text = _("Accept key");
                
                var reject_btn = new Gtk.Button.from_icon_name("action-unavailable-symbolic");
                reject_btn.add_css_class("destructive-action");
                reject_btn.valign = Gtk.Align.CENTER;
                reject_btn.tooltip_text = _("Reject key");
                
                accept_btn.clicked.connect(() => {
                    plugin.trust_manager.set_device_trust(conversation.account, the_jid, dev_id, TrustLevel.TRUSTED);
                });
                reject_btn.clicked.connect(() => {
                    plugin.trust_manager.set_device_trust(conversation.account, the_jid, dev_id, TrustLevel.UNTRUSTED);
                });
                
                var btn_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
                btn_box.add_css_class("linked");
                btn_box.append(accept_btn);
                btn_box.append(reject_btn);
                device_row.add_suffix(btn_box);
                
                expander.add_row(device_row);
            }
            
            main_group.add(expander);
        }
        
        return main_group;
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
