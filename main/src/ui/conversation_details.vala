/*
 * Copyright (C) 2025 Ralf Peter <dinox@handwerker.jetzt>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

using Dino;
using Dino.Entities;
using Xmpp;
using Xmpp.Xep;
using Gee;
using Gtk;

namespace Dino.Ui.ConversationDetails {

    public void populate_dialog(Model.ConversationDetails model, Conversation conversation, StreamInteractor stream_interactor) {
        model.conversation = conversation;
        model.display_name = stream_interactor.get_module<ContactModels>(ContactModels.IDENTITY).get_display_name_model(conversation);
        model.blocked = stream_interactor.get_module<BlockingManager>(BlockingManager.IDENTITY).is_blocked(model.conversation.account, model.conversation.counterpart);
        model.domain_blocked = stream_interactor.get_module<BlockingManager>(BlockingManager.IDENTITY).is_blocked(model.conversation.account, model.conversation.counterpart.domain_jid);

        if (conversation.type_ == Conversation.Type.CHAT || conversation.type_ == Conversation.Type.GROUPCHAT_PM || conversation.type_ == Conversation.Type.GROUPCHAT) {
            fetch_vcard.begin(model, conversation, stream_interactor);
        }

        if (conversation.type_ == Conversation.Type.GROUPCHAT) {
            stream_interactor.get_module<MucManager>(MucManager.IDENTITY).get_config_form.begin(conversation.account, conversation.counterpart, (_, res) => {
                model.data_form = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).get_config_form.end(res);
                if (model.data_form == null) {
                    return;
                }
                model.data_form_bak = model.data_form.stanza_node.to_string();
            });
        }
    }

    public void bind_dialog(Model.ConversationDetails model, ViewModel.ConversationDetails view_model, StreamInteractor stream_interactor) {
        // Set some data once
        view_model.avatar = new ViewModel.CompatAvatarPictureModel(stream_interactor).set_conversation(model.conversation);
        view_model.show_blocked = model.conversation.type_ == Conversation.Type.CHAT && stream_interactor.get_module<BlockingManager>(BlockingManager.IDENTITY).is_supported(model.conversation.account);
        view_model.show_remove_contact = model.conversation.type_ == Conversation.Type.CHAT;  // Only show for 1:1 chats
        view_model.members_sorted.set_model(model.members);
        view_model.members.set_map_func((item) => {
            var conference_member = (Ui.Model.ConferenceMember) item;
            Jid? nick_jid = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).get_occupant_jid(model.conversation.account, model.conversation.counterpart, conference_member.jid);
            return new Ui.ViewModel.ConferenceMemberListRow() {
                avatar = new ViewModel.CompatAvatarPictureModel(stream_interactor).add_participant(model.conversation, conference_member.jid),
                name = nick_jid != null ? nick_jid.resourcepart : conference_member.jid.localpart,
                jid = conference_member.jid.to_string(),
                affiliation = conference_member.affiliation
            };
        });
        view_model.account_jid = stream_interactor.get_accounts().size > 1 ? model.conversation.account.bare_jid.to_string() : null;

        if (model.domain_blocked) {
            view_model.blocked = DOMAIN;
        } else if (model.blocked) {
            view_model.blocked = USER;
        } else {
            view_model.blocked = UNBLOCK;
        }

        // Bind properties
        model.display_name.bind_property("display-name", view_model, "name", BindingFlags.SYNC_CREATE);
        model.conversation.bind_property("notify-setting", view_model, "notification", BindingFlags.SYNC_CREATE, (_, from, ref to) => {
            switch (model.conversation.get_notification_setting(stream_interactor)) {
                case ON:
                    to = ViewModel.ConversationDetails.NotificationSetting.ON;
                    break;
                case OFF:
                    to = ViewModel.ConversationDetails.NotificationSetting.OFF;
                    break;
                case HIGHLIGHT:
                    to = ViewModel.ConversationDetails.NotificationSetting.HIGHLIGHT;
                    break;
                case DEFAULT:
                    // A "default" setting should have been resolved to the actual default value
                    assert_not_reached();
            }
            return true;
        });
        model.conversation.bind_property("notify-setting", view_model, "notification-is-default", BindingFlags.SYNC_CREATE, (_, from, ref to) => {
            var notify_setting = (Conversation.NotifySetting) from;
            to = notify_setting == Conversation.NotifySetting.DEFAULT;
            return true;
        });
        model.conversation.bind_property("pinned", view_model, "pinned", BindingFlags.SYNC_CREATE, (_, from, ref to) => {
            var from_int = (int) from;
            to = from_int > 0;
            return true;
        });
        model.conversation.bind_property("type-", view_model, "notification-options", BindingFlags.SYNC_CREATE, (_, from, ref to) => {
            var ty = (Conversation.Type) from;
            to = ty == Conversation.Type.GROUPCHAT ? ViewModel.ConversationDetails.NotificationOptions.ON_HIGHLIGHT_OFF : ViewModel.ConversationDetails.NotificationOptions.ON_OFF;
            return true;
        });
        model.bind_property("data-form", view_model, "room-configuration-rows", BindingFlags.SYNC_CREATE, (_, from, ref to) => {
            var data_form = (DataForms.DataForm) from;
            if (data_form == null) return true;
            var list_store = new GLib.ListStore(typeof(ViewModel.PreferencesRow.Any));

            foreach (var field in data_form.fields) {
                var field_view_model = Util.get_data_form_field_view_model(field);
                if (field_view_model != null) {
                    list_store.append(field_view_model);
                }
            }

            to = list_store;
            return true;
        });

        view_model.pin_changed.connect(() => {
            model.conversation.pinned = model.conversation.pinned == 1 ? 0 : 1;
        });
        view_model.block_changed.connect((action) => {
            switch (action) {
                case USER:
                    stream_interactor.get_module<BlockingManager>(BlockingManager.IDENTITY).block(model.conversation.account, model.conversation.counterpart);
                    stream_interactor.get_module<BlockingManager>(BlockingManager.IDENTITY).unblock(model.conversation.account, model.conversation.counterpart.domain_jid);
                    break;
                case DOMAIN:
                    stream_interactor.get_module<BlockingManager>(BlockingManager.IDENTITY).block(model.conversation.account, model.conversation.counterpart.domain_jid);
                    break;
                case UNBLOCK:
                    stream_interactor.get_module<BlockingManager>(BlockingManager.IDENTITY).unblock(model.conversation.account, model.conversation.counterpart);
                    stream_interactor.get_module<BlockingManager>(BlockingManager.IDENTITY).unblock(model.conversation.account, model.conversation.counterpart.domain_jid);
                    break;
            }
            view_model.blocked = action;
        });
        view_model.remove_contact.connect(() => {
            // Delete conversation history first, then remove contact from roster
            stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY).clear_conversation_history(model.conversation);
            stream_interactor.get_module<RosterManager>(RosterManager.IDENTITY).remove_jid(model.conversation.account, model.conversation.counterpart);
            stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY).close_conversation(model.conversation);
        });
        view_model.notification_changed.connect((setting) => {
            switch (setting) {
                case ON:
                    model.conversation.notify_setting = ON;
                    break;
                case OFF:
                    model.conversation.notify_setting = OFF;
                    break;
                case HIGHLIGHT:
                    model.conversation.notify_setting = HIGHLIGHT;
                    break;
                case DEFAULT:
                    model.conversation.notify_setting = DEFAULT;
                    break;
            }
        });

        view_model.notification_flipped.connect(() => {
            model.conversation.notify_setting = view_model.notification == ON ? Conversation.NotifySetting.OFF : Conversation.NotifySetting.ON;
        });

        model.notify["vcard4"].connect(() => { update_vcard_rows(model, view_model); });
        model.notify["vcard-temp"].connect(() => { update_vcard_rows(model, view_model); });
        model.notify["pep-nickname"].connect(() => { update_vcard_rows(model, view_model); });
    }

    public void set_about_rows(Model.ConversationDetails model, ViewModel.ConversationDetails view_model, StreamInteractor stream_interactor, Gtk.Widget? parent) {
        var xmpp_addr_row = new ViewModel.PreferencesRow.Text();
        xmpp_addr_row.title = _("XMPP Address");
        xmpp_addr_row.text = model.conversation.counterpart.to_string();
        view_model.about_rows.append(xmpp_addr_row);

        // Show own Role/Affiliation in MUC rooms
        var muc_module = stream_interactor.get_module<MucManager>(MucManager.IDENTITY);
        var room_jid = model.conversation.counterpart.bare_jid;
        if (model.conversation.type_ == Conversation.Type.GROUPCHAT && muc_module.is_joined(room_jid, model.conversation.account)) {
            // Get own MUC JID (room@conf/nickname) to query own role
            var own_muc_jid = muc_module.get_own_jid(room_jid, model.conversation.account);
            if (own_muc_jid != null) {
                var role = muc_module.get_role(own_muc_jid, model.conversation.account);
                if (role != null && role != Xmpp.Xep.Muc.Role.NONE) {
                    var role_row = new ViewModel.PreferencesRow.Text();
                    role_row.title = _("Your Role");
                    switch (role) {
                        case Xmpp.Xep.Muc.Role.MODERATOR: role_row.text = _("Moderator"); break;
                        case Xmpp.Xep.Muc.Role.PARTICIPANT: role_row.text = _("Participant"); break;
                        case Xmpp.Xep.Muc.Role.VISITOR: role_row.text = _("Visitor"); break;
                        default: role_row.text = _("None"); break;
                    }
                    view_model.about_rows.append(role_row);
                }

                var affiliation = muc_module.get_affiliation(room_jid, own_muc_jid, model.conversation.account);
                if (affiliation != null && affiliation != Xmpp.Xep.Muc.Affiliation.NONE) {
                    var affiliation_row = new ViewModel.PreferencesRow.Text();
                    affiliation_row.title = _("Your Affiliation");
                    switch (affiliation) {
                        case Xmpp.Xep.Muc.Affiliation.OWNER: affiliation_row.text = _("Owner"); break;
                        case Xmpp.Xep.Muc.Affiliation.ADMIN: affiliation_row.text = _("Admin"); break;
                        case Xmpp.Xep.Muc.Affiliation.MEMBER: affiliation_row.text = _("Member"); break;
                        case Xmpp.Xep.Muc.Affiliation.OUTCAST: affiliation_row.text = _("Outcast"); break;
                        default: affiliation_row.text = _("None"); break;
                    }
                    view_model.about_rows.append(affiliation_row);
                }
            }
        }

        if (model.conversation.type_ == Conversation.Type.CHAT) {
            var about_row = new ViewModel.PreferencesRow.Entry() {
                title = _("Display name"),
                text = model.display_name.display_name
            };
            about_row.changed.connect(() => {
                if (about_row.text != model.display_name.display_name) {
                    stream_interactor.get_module<RosterManager>(RosterManager.IDENTITY).set_jid_handle(model.conversation.account, model.conversation.counterpart, about_row.text);
                }
            });
            view_model.about_rows.append(about_row);

            // Subscription status row
            var roster_mgr = stream_interactor.get_module<RosterManager>(RosterManager.IDENTITY);
            var roster_item = roster_mgr.get_roster_item(model.conversation.account, model.conversation.counterpart);
            if (roster_item != null) {
                string sub_text;
                switch (roster_item.subscription) {
                    case Xmpp.Roster.Item.SUBSCRIPTION_BOTH:
                        sub_text = _("Mutual");
                        break;
                    case Xmpp.Roster.Item.SUBSCRIPTION_TO:
                        sub_text = _("To (you see them, they don't see you)");
                        break;
                    case Xmpp.Roster.Item.SUBSCRIPTION_FROM:
                        sub_text = _("From (they see you, you don't see them)");
                        break;
                    default:
                        sub_text = _("None");
                        break;
                }
                if (roster_item.subscription_requested) {
                    sub_text += " " + _("(request pending)");
                }
                var sub_row = new ViewModel.PreferencesRow.Text() {
                    title = _("Subscription"),
                    text = sub_text
                };
                view_model.about_rows.append(sub_row);
            }
        }
        if (model.conversation.type_ == Conversation.Type.GROUPCHAT) {
            var topic = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).get_groupchat_subject(model.conversation.counterpart, model.conversation.account);

            Ui.ViewModel.PreferencesRow.Any preferences_row = null;
            Jid? own_muc_jid = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).get_own_jid(model.conversation.counterpart, model.conversation.account);
            if (own_muc_jid != null) {
                Xep.Muc.Role? own_role = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).get_role(own_muc_jid, model.conversation.account);
                if (own_role != null) {
                    if (own_role == MODERATOR) {
                        var preferences_row_entry = new ViewModel.PreferencesRow.Entry() {
                            title = _("Topic"),
                            text = topic
                        };
                        preferences_row_entry.changed.connect(() => {
                            if (preferences_row_entry.text != topic) {
                                stream_interactor.get_module<MucManager>(MucManager.IDENTITY).change_subject(model.conversation.account, model.conversation.counterpart, preferences_row_entry.text);
                            }
                        });
                        preferences_row = preferences_row_entry;
                    }
                }
            }
            if (preferences_row == null && topic != null && topic != "") {
                preferences_row = new ViewModel.PreferencesRow.Text() {
                    title = _("Topic"),
                    text = Util.parse_add_markup(topic, null, true, true)
                };
            }
            if (preferences_row != null) {
                view_model.about_rows.append(preferences_row);
            }

            // Administration Button
            if (own_muc_jid != null) {
                Xep.Muc.Affiliation? own_affiliation = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).get_affiliation(model.conversation.counterpart, own_muc_jid, model.conversation.account);
                if (own_affiliation == OWNER || own_affiliation == ADMIN) {
                    var change_avatar_button = new ViewModel.PreferencesRow.Button() {
                        title = _("Avatar"),
                        button_text = _("Change Avatar")
                    };
                    change_avatar_button.clicked.connect(() => {
                        change_muc_avatar.begin(stream_interactor, model.conversation.account, model.conversation.counterpart, parent);
                    });
                    view_model.settings_rows.append(change_avatar_button);

                    var admin_button = new ViewModel.PreferencesRow.Button() {
                        title = _("Permissions"),
                        button_text = _("Manage Affiliations")
                    };
                    admin_button.clicked.connect(() => {
                        var admin_dialog = new MucAdminDialog(stream_interactor, model.conversation.account, model.conversation.counterpart);
                        // Try to find a window to be transient for
                        if (parent != null) {
                            var window = parent.get_root() as Gtk.Window;
                            admin_dialog.present(window);
                        } else {
                            // Fallback if no parent found, though present() requires one.
                            // We might need to find the active window from application
                            var app = GLib.Application.get_default() as Gtk.Application;
                            admin_dialog.present(app.active_window);
                        }
                    });
                    view_model.settings_rows.append(admin_button);
                }

                if (own_affiliation == OWNER) {
                    var destroy_button = new ViewModel.PreferencesRow.Button() {
                        title = _("Danger Zone"),
                        button_text = _("Destroy Room")
                    };
                    // TODO: Style this button red if possible, but PreferencesRow.Button doesn't expose style classes easily yet
                    
                    destroy_button.clicked.connect(() => {
                        var confirm_dialog = new Adw.AlertDialog(
                            _("Destroy Room?"),
                            _("Are you sure you want to permanently destroy this room? This action cannot be undone and all history will be lost for all participants.")
                        );
                        confirm_dialog.add_response("cancel", _("Cancel"));
                        confirm_dialog.add_response("destroy", _("Destroy"));
                        confirm_dialog.set_response_appearance("destroy", Adw.ResponseAppearance.DESTRUCTIVE);
                        confirm_dialog.default_response = "cancel";
                        confirm_dialog.close_response = "cancel";
                        
                        confirm_dialog.choose.begin(parent, null, (obj, res) => {
                            string response = confirm_dialog.choose.end(res);
                            if (response == "destroy") {
                                stream_interactor.get_module<MucManager>(MucManager.IDENTITY).destroy_room.begin(model.conversation.account, model.conversation.counterpart, null, (obj2, res2) => {
                                    try {
                                        stream_interactor.get_module<MucManager>(MucManager.IDENTITY).destroy_room.end(res2);
                                        if (parent != null) {
                                            // If parent is an Adw.Dialog, we can try to close it.
                                            // But Adw.Dialog doesn't have a close() method in all versions, or it might be 'close()'
                                            // Casting to our Dialog class which inherits Adw.Dialog
                                            var dlg = parent as Adw.Dialog;
                                            if (dlg != null) dlg.close();
                                        }
                                    } catch (GLib.Error e) {
                                        Gtk.Window? window = null;
                                        if (parent != null) window = parent.get_root() as Gtk.Window;
                                        var error_dialog = new Adw.AlertDialog(_("Failed to destroy room"), e.message);
                                        error_dialog.add_response("close", _("Close"));
                                        error_dialog.present(window);
                                    }
                                });
                            }
                        });
                    });
                    view_model.settings_rows.append(destroy_button);
                }
            }
        }
        
        // Disappearing Messages - available for all conversation types
        var expiry_row = new ViewModel.PreferencesRow.ComboBox();
        expiry_row.title = _("Auto-delete messages");
        expiry_row.items.add(_("Never"));
        expiry_row.items.add(_("After 15 minutes"));
        expiry_row.items.add(_("After 30 minutes"));
        expiry_row.items.add(_("After 1 hour"));
        expiry_row.items.add(_("After 24 hours"));
        expiry_row.items.add(_("After 7 days"));
        expiry_row.items.add(_("After 30 days"));

        // Set current value
        switch (model.conversation.message_expiry_seconds) {
            case 900: expiry_row.active_item = 1; break;    // 15 min
            case 1800: expiry_row.active_item = 2; break;   // 30 min
            case 3600: expiry_row.active_item = 3; break;   // 1 hour
            case 86400: expiry_row.active_item = 4; break;  // 24 hours
            case 604800: expiry_row.active_item = 5; break; // 7 days
            case 2592000: expiry_row.active_item = 6; break; // 30 days
            default: expiry_row.active_item = 0; break;
        }

        // Save on change
        expiry_row.notify["active-item"].connect(() => {
            switch (expiry_row.active_item) {
                case 1: model.conversation.message_expiry_seconds = 900; break;    // 15 min
                case 2: model.conversation.message_expiry_seconds = 1800; break;   // 30 min
                case 3: model.conversation.message_expiry_seconds = 3600; break;   // 1 hour
                case 4: model.conversation.message_expiry_seconds = 86400; break;  // 24 hours
                case 5: model.conversation.message_expiry_seconds = 604800; break; // 7 days
                case 6: model.conversation.message_expiry_seconds = 2592000; break; // 30 days
                default: model.conversation.message_expiry_seconds = 0; break;
            }
        });

        view_model.settings_rows.append(expiry_row);
    }

    public Dialog setup_dialog(Conversation conversation, StreamInteractor stream_interactor) {
        var dialog = new Dialog();
        var model = new Model.ConversationDetails();
        model.populate(stream_interactor, conversation);
        bind_dialog(model, dialog.model, stream_interactor);

        set_about_rows(model, dialog.model, stream_interactor, dialog);

        dialog.closed.connect(() => {
            // Only send the config form if something was changed
            if (model.data_form != null && model.data_form_bak != null) {
                string current = model.data_form.stanza_node.to_string();
                if (model.data_form_bak != current) {
                    stream_interactor.get_module<MucManager>(MucManager.IDENTITY).set_config_form.begin(conversation.account, conversation.counterpart, model.data_form);
                }
            }
        });

        Plugins.ContactDetails contact_details = new Plugins.ContactDetails();
        contact_details.add_settings_action_row.connect((entry_row_model) => {
            dialog.model.settings_rows.append((Ui.ViewModel.PreferencesRow.Any) entry_row_model);
        });
        Application app = GLib.Application.get_default() as Application;
        app.plugin_registry.register_contact_details_entry(new ContactDetails.SettingsProvider(stream_interactor));
        app.plugin_registry.register_contact_details_entry(new ContactDetails.PermissionsProvider(stream_interactor));

        foreach (Plugins.ContactDetailsProvider provider in app.plugin_registry.contact_details_entries) {
            var preferences_group = (Adw.PreferencesGroup) provider.get_widget(conversation);
            if (preferences_group != null) {
                dialog.add_encryption_tab_element(preferences_group);
            }
            provider.populate(conversation, contact_details, Plugins.WidgetType.GTK4);
        }

        return dialog;
    }

    private async void fetch_vcard(Model.ConversationDetails model, Conversation conversation, StreamInteractor stream_interactor) {
        Jid target_jid = conversation.counterpart;
        bool is_muc_occupant = (conversation.type_ == Conversation.Type.GROUPCHAT_PM);

        if (is_muc_occupant) {
            var real_jid = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).get_real_jid(conversation.counterpart, conversation.account);
            if (real_jid != null) {
                target_jid = real_jid;
                is_muc_occupant = false; // It's now a real user JID
            }
        }

        // For normal users (not MUC occupants), always use the bare JID for vCard requests
        if (!is_muc_occupant) {
            target_jid = target_jid.bare_jid;
        }

        var stream = stream_interactor.get_stream(conversation.account);
        if (stream == null) {
            return;
        }

        // Try XEP-0292
        var vcard4_module = stream.get_module<Xmpp.Xep.VCard4.Module>(Xmpp.Xep.VCard4.Module.IDENTITY);
        if (vcard4_module != null) {
            var vcard4 = yield vcard4_module.request(stream, target_jid);
            if (vcard4 != null) {
                model.vcard4 = vcard4;
                // If we have vCard4, we might still want to check PEP nickname if vCard4 nickname is missing?
                // But usually vCard4 is authoritative.
            }
        }

        // Try PEP Nickname (XEP-0172)
        var pubsub_module = stream.get_module<Xmpp.Xep.Pubsub.Module>(Xmpp.Xep.Pubsub.Module.IDENTITY);
        if (pubsub_module != null) {
            var items = yield pubsub_module.request_all(stream, target_jid, "http://jabber.org/protocol/nick");
            if (items != null && items.size > 0) {
                var item = items[0];
                var nick_node = item.get_subnode("nick", "http://jabber.org/protocol/nick");
                if (nick_node != null) {
                    var nick = nick_node.get_string_content();
                    if (nick != null) {
                        model.pep_nickname = nick;
                    }
                }
            }
        }
        
        // Try XEP-0054
        var vcard_temp = yield Xmpp.Xep.VCard.fetch_vcard(stream, target_jid);
        if (vcard_temp != null) {
            model.vcard_temp = vcard_temp;
        }
    }

    private void update_vcard_rows(Model.ConversationDetails model, ViewModel.ConversationDetails view_model) {
        view_model.vcard_rows.remove_all();
        
        string? fn = null;
        string? nickname = null;
        string? note = null;
        string? bday = null;
        string? address = null;
        
        Gee.List<string> emails = new Gee.ArrayList<string>();
        Gee.List<string> phones = new Gee.ArrayList<string>();
        Gee.List<string> urls = new Gee.ArrayList<string>();
        Gee.List<string> roles = new Gee.ArrayList<string>();
        Gee.List<string> titles = new Gee.ArrayList<string>();
        Gee.List<string> orgs = new Gee.ArrayList<string>();

        string? tz = null;
        string? gender = null;

        Gee.List<string> impps = new Gee.ArrayList<string>();

        // 1. Try vCard4 first
        if (model.vcard4 != null) {
            fn = model.vcard4.full_name;
            nickname = model.vcard4.nickname;
            note = model.vcard4.note;
            bday = model.vcard4.bday;
            tz = model.vcard4.tz;
            gender = model.vcard4.gender;
            
            emails.add_all(model.vcard4.emails);
            phones.add_all(model.vcard4.tels);
            urls.add_all(model.vcard4.urls);
            roles.add_all(model.vcard4.roles);
            titles.add_all(model.vcard4.titles);
            orgs.add_all(model.vcard4.orgs);
            
            foreach (var impp in model.vcard4.impps) {
                impps.add(impp);
            }
            
            // Construct address string for vCard4
            var parts = new ArrayList<string>();
            if (model.vcard4.adr_street != null) parts.add(model.vcard4.adr_street);
            
            // Handle PCode and POBox
            string? pcode = model.vcard4.adr_pcode;
            if (pcode == null) pcode = model.vcard4.adr_pobox; // Fallback if Gajim puts zip in pobox
            
            if (pcode != null && model.vcard4.adr_locality != null) {
                parts.add(pcode + " " + model.vcard4.adr_locality);
            } else {
                if (pcode != null) parts.add(pcode);
                if (model.vcard4.adr_locality != null) parts.add(model.vcard4.adr_locality);
            }
            if (model.vcard4.adr_region != null) parts.add(model.vcard4.adr_region);
            if (model.vcard4.adr_country != null) parts.add(model.vcard4.adr_country);
            
            if (parts.size > 0) {
                address = string.joinv(", ", parts.to_array());
            }
        }

        // 2. Fallback / Merge with vCard-temp
        if (model.vcard_temp != null) {
            if (fn == null || fn == "") fn = model.vcard_temp.full_name;
            if (nickname == null || nickname == "") nickname = model.vcard_temp.nickname;
            if (note == null || note == "") note = model.vcard_temp.description;
            if (bday == null || bday == "") bday = model.vcard_temp.birthday;
            
            foreach (var email in model.vcard_temp.emails) {
                if (!emails.contains(email)) emails.add(email);
            }
            foreach (var phone in model.vcard_temp.phones) {
                if (!phones.contains(phone)) phones.add(phone);
            }
            foreach (var url in model.vcard_temp.urls) {
                if (!urls.contains(url)) urls.add(url);
            }
            foreach (var role in model.vcard_temp.roles) {
                if (!roles.contains(role)) roles.add(role);
            }
            foreach (var title in model.vcard_temp.titles) {
                if (!titles.contains(title)) titles.add(title);
            }
            foreach (var org in model.vcard_temp.organizations) {
                if (!orgs.contains(org)) orgs.add(org);
            }

            // If address is still missing, try vCard-temp
            if (address == null || address == "") {
                var parts = new ArrayList<string>();
                if (model.vcard_temp.adr_street != null) parts.add(model.vcard_temp.adr_street);
                if (model.vcard_temp.adr_pcode != null && model.vcard_temp.adr_locality != null) {
                    parts.add(model.vcard_temp.adr_pcode + " " + model.vcard_temp.adr_locality);
                } else {
                    if (model.vcard_temp.adr_pcode != null) parts.add(model.vcard_temp.adr_pcode);
                    if (model.vcard_temp.adr_locality != null) parts.add(model.vcard_temp.adr_locality);
                }
                if (model.vcard_temp.adr_region != null) parts.add(model.vcard_temp.adr_region);
                if (model.vcard_temp.adr_country != null) parts.add(model.vcard_temp.adr_country);
                
                if (parts.size > 0) {
                    address = string.joinv(", ", parts.to_array());
                }
            }
        }

        if (model.pep_nickname != null) {
            nickname = model.pep_nickname;
        }

        if (fn != null && fn != "") view_model.vcard_rows.append(new ViewModel.PreferencesRow.Text() { title = _("Full Name"), text = fn });
        if (nickname != null && nickname != "") view_model.vcard_rows.append(new ViewModel.PreferencesRow.Text() { title = _("Nickname"), text = nickname });
        
        // Requested Sort Order:
        // Gender, Birthday, Address, Email, IM Address, Phone, Organization, Title, Role, Timezone, URL, Note

        if (gender != null && gender != "") {
            string display_gender = gender;
            if (gender == "M") display_gender = _("Male");
            else if (gender == "F") display_gender = _("Female");
            else if (gender == "O") display_gender = _("Other");
            else if (gender == "N") display_gender = _("None");
            else if (gender == "U") display_gender = _("Unknown");
            
            view_model.vcard_rows.append(new ViewModel.PreferencesRow.Text() { title = _("Gender"), text = display_gender });
        }

        if (bday != null && bday != "") view_model.vcard_rows.append(new ViewModel.PreferencesRow.Text() { title = _("Birthday"), text = bday });
        
        if (address != null && address != "") view_model.vcard_rows.append(new ViewModel.PreferencesRow.Text() { title = _("Address"), text = address });
        
        foreach (var email in emails) if (email != "") view_model.vcard_rows.append(new ViewModel.PreferencesRow.Text() { title = _("Email"), text = email });
        
        foreach (var impp in impps) if (impp != "") view_model.vcard_rows.append(new ViewModel.PreferencesRow.Text() { title = _("IM Address"), text = impp });
        
        foreach (var phone in phones) if (phone != "") view_model.vcard_rows.append(new ViewModel.PreferencesRow.Text() { title = _("Phone"), text = phone });
        
        foreach (var org in orgs) if (org != "") view_model.vcard_rows.append(new ViewModel.PreferencesRow.Text() { title = _("Organization"), text = org });
        
        foreach (var title in titles) if (title != "") view_model.vcard_rows.append(new ViewModel.PreferencesRow.Text() { title = _("Title"), text = title });
        
        foreach (var role in roles) if (role != "") view_model.vcard_rows.append(new ViewModel.PreferencesRow.Text() { title = _("Role"), text = role });
        
        if (tz != null && tz != "") view_model.vcard_rows.append(new ViewModel.PreferencesRow.Text() { title = _("Timezone"), text = tz });
        
        foreach (var url in urls) if (url != "") view_model.vcard_rows.append(new ViewModel.PreferencesRow.Text() { title = _("URL"), text = url });
        
        if (note != null && note != "") view_model.vcard_rows.append(new ViewModel.PreferencesRow.Text() { title = _("Note"), text = note });
    }

    private async void change_muc_avatar(StreamInteractor stream_interactor, Account account, Jid room_jid, Gtk.Widget? parent) {
        var dialog = new Gtk.FileDialog();
        dialog.title = _("Select Avatar");
        var filter = new Gtk.FileFilter();
        filter.add_pixbuf_formats();
        filter.name = _("Images");
        
        var filters = new GLib.ListStore(typeof(Gtk.FileFilter));
        filters.append(filter);
        dialog.filters = filters;
        dialog.default_filter = filter;

        Gtk.Window? window = null;
        if (parent != null) {
            window = parent.get_root() as Gtk.Window;
        }

        try {
            File file = yield dialog.open(window, null);
            if (file == null) return;
            
            // Resize image if necessary (limit to 192px)
            const int MAX_PIXEL = 192;
            var file_stream = yield file.read_async();
            var pixbuf = yield new Gdk.Pixbuf.from_stream_async(file_stream);
            yield file_stream.close_async();

            if (pixbuf.width >= pixbuf.height && pixbuf.width > MAX_PIXEL) {
                int dest_height = (int) ((float) MAX_PIXEL / pixbuf.width * pixbuf.height);
                pixbuf = pixbuf.scale_simple(MAX_PIXEL, dest_height, Gdk.InterpType.BILINEAR);
            } else if (pixbuf.height > pixbuf.width && pixbuf.height > MAX_PIXEL) {
                int dest_width = (int) ((float) MAX_PIXEL / pixbuf.height * pixbuf.width);
                pixbuf = pixbuf.scale_simple(dest_width, MAX_PIXEL, Gdk.InterpType.BILINEAR);
            }

            uint8[] buffer;
            pixbuf.save_to_buffer(out buffer, "png");
            Bytes bytes = new Bytes(buffer);
            
            var stream = stream_interactor.get_stream(account);
            if (stream != null) {
                debug("Updating MUC avatar for %s...", room_jid.to_string());
                // Fetch existing vCard first to preserve other fields (description, etc.)
                var vcard = yield Xmpp.Xep.VCard.fetch_vcard(stream, room_jid);
                if (vcard == null) vcard = new Xmpp.Xep.VCard.VCardInfo();
                vcard.photo = bytes;
                vcard.photo_type = "image/png";
                yield Xmpp.Xep.VCard.publish_vcard(stream, vcard, room_jid);
                debug("MUC vCard published.");
                
                string hash = Checksum.compute_for_bytes(ChecksumType.SHA1, bytes);
                var avatar_manager = stream_interactor.get_module<AvatarManager>(AvatarManager.IDENTITY);
                yield avatar_manager.store_image(hash, bytes);
                avatar_manager.on_vcard_avatar_received(account, room_jid, hash);
                debug("MUC avatar updated locally.");
            }
        } catch (Error e) {
            warning("Failed to select or upload avatar: %s", e.message);
        }
    }
}
