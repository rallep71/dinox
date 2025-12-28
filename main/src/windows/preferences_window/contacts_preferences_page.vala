using Dino.Entities;
using Gee;
using Gtk;
using Xmpp;

public class Dino.Ui.PreferencesWindowContacts : Adw.PreferencesPage {

    public signal void contact_chosen(Account account, Jid jid);

    private Adw.PreferencesGroup contacts_group;
    private HashMap<string, Adw.ActionRow> contact_rows = new HashMap<string, Adw.ActionRow>();
    private bool signals_connected = false;

    public ViewModel.PreferencesDialog model { get; set; }

    construct {
        this.title = _("Contacts");
        this.icon_name = "avatar-default-symbolic";

        this.notify["model"].connect(() => {
            setup_signals_and_refresh();
        });
        
        // Also check on map in case model is already set
        this.map.connect(() => {
            setup_signals_and_refresh();
        });
    }
    
    private void setup_signals_and_refresh() {
        if (model == null || model.stream_interactor == null) return;
        
        // Connect signals only once
        if (!signals_connected) {
            model.update.connect(refresh);
            
            var roster_manager = model.stream_interactor.get_module(RosterManager.IDENTITY);
            roster_manager.updated_roster_item.connect((account, jid, roster_item) => {
                refresh();
            });
            roster_manager.removed_roster_item.connect((account, jid, roster_item) => {
                refresh();
            });
            roster_manager.mutual_subscription.connect((account, jid) => {
                refresh();
            });
            
            var blocking_manager = model.stream_interactor.get_module(BlockingManager.IDENTITY);
            blocking_manager.block_changed.connect((account, jid) => {
                refresh();
            });
            
            signals_connected = true;
        }
        
        refresh();
    }

    private void refresh() {
        // Check if model is initialized
        if (model == null || model.stream_interactor == null) {
            return;
        }

        if (contacts_group != null) this.remove(contacts_group);

        contacts_group = new Adw.PreferencesGroup() { title=_("Contacts")};
        Button add_contact_button = new Button.from_icon_name("list-add-symbolic");
        add_contact_button.add_css_class("flat");
        add_contact_button.tooltip_text = _("Add Contact");
        contacts_group.header_suffix = add_contact_button;

        this.add(contacts_group);

        add_contact_button.clicked.connect(() => {
            AddContactDialog add_contact_dialog = new AddContactDialog(model.stream_interactor);
            add_contact_dialog.present((Widget)this.get_root());
        });

        contact_rows.clear();
        bool has_contacts = false;

        // Collect all roster contacts from all accounts
        var contacts = new ArrayList<ContactInfo>();
        foreach (Account account in model.stream_interactor.get_accounts()) {
            if (!account.enabled) continue;
            
            var roster = model.stream_interactor.get_module(RosterManager.IDENTITY).get_roster(account);
            if (roster == null) continue;

            foreach (Roster.Item roster_item in roster) {
                contacts.add(new ContactInfo(account, roster_item.jid, roster_item.name));
            }
        }

        // Sort contacts by display name
        contacts.sort((a, b) => {
            string name_a = a.display_name ?? a.jid.to_string();
            string name_b = b.display_name ?? b.jid.to_string();
            return name_a.collate(name_b);
        });

        // Create rows for each contact
        foreach (ContactInfo contact_info in contacts) {
            var row = new Adw.ActionRow();
            row.title = contact_info.display_name ?? contact_info.jid.to_string();
            row.subtitle = contact_info.jid.to_string();

            // Avatar and conversation
            var conversation = model.stream_interactor.get_module(ConversationManager.IDENTITY)
                .create_conversation(contact_info.jid, contact_info.account, Conversation.Type.CHAT);
            var avatar_model = new ViewModel.CompatAvatarPictureModel(model.stream_interactor).set_conversation(conversation);
            row.add_prefix(new AvatarPicture() { valign=Align.CENTER, height_request=35, width_request=35, model = avatar_model });

            // Edit button
            var edit_button = new Button.from_icon_name("document-edit-symbolic");
            edit_button.valign = Align.CENTER;
            edit_button.add_css_class("flat");
            edit_button.add_css_class("circular");
            edit_button.tooltip_text = _("Edit Alias");
            
            edit_button.clicked.connect(() => {
                on_edit_contact(contact_info.account, contact_info.jid, contact_info.display_name);
            });
            
            row.add_suffix(edit_button);

            // Mute button
            bool is_muted = conversation.get_notification_setting(model.stream_interactor) == Conversation.NotifySetting.OFF;
            var mute_button = new Button.from_icon_name(is_muted ? "dino-bell-large-none-symbolic" : "dino-bell-large-symbolic");
            mute_button.valign = Align.CENTER;
            mute_button.add_css_class("flat");
            mute_button.add_css_class("circular");
            mute_button.tooltip_text = is_muted ? _("Unmute") : _("Mute");
            
            mute_button.clicked.connect(() => {
                var conv = model.stream_interactor.get_module(ConversationManager.IDENTITY)
                    .create_conversation(contact_info.jid, contact_info.account, Conversation.Type.CHAT);
                bool currently_muted = conv.get_notification_setting(model.stream_interactor) == Conversation.NotifySetting.OFF;
                on_mute_contact(contact_info.account, contact_info.jid, currently_muted, conv);
            });
            
            row.add_suffix(mute_button);

            // Block button
            bool is_blocked = model.stream_interactor.get_module(BlockingManager.IDENTITY).is_blocked(contact_info.account, contact_info.jid);
            var block_button = new Button.from_icon_name(is_blocked ? "action-unavailable-symbolic" : "action-unavailable-symbolic");
            block_button.valign = Align.CENTER;
            block_button.add_css_class("flat");
            block_button.add_css_class("circular");
            block_button.tooltip_text = is_blocked ? _("Unblock Contact") : _("Block Contact");
            if (is_blocked) {
                block_button.add_css_class("error");
            }
            
            block_button.clicked.connect(() => {
                // Check current status at click time, not at button creation time
                bool currently_blocked = model.stream_interactor.get_module(BlockingManager.IDENTITY).is_blocked(contact_info.account, contact_info.jid);
                on_block_contact(contact_info.account, contact_info.jid, currently_blocked);
            });
            
            row.add_suffix(block_button);

            // Remove button
            var remove_button = new Button.from_icon_name("user-trash-symbolic");
            remove_button.valign = Align.CENTER;
            remove_button.add_css_class("flat");
            remove_button.add_css_class("circular");
            remove_button.tooltip_text = _("Remove Contact");
            
            remove_button.clicked.connect(() => {
                on_remove_contact(contact_info.account, contact_info.jid, row);
            });
            
            row.add_suffix(remove_button);
            row.activatable = false;

            contacts_group.add(row);
            contact_rows[contact_info.account.id.to_string() + ":" + contact_info.jid.to_string()] = row;
            has_contacts = true;
        }

        // Show placeholder if no contacts
        if (!has_contacts) {
            contacts_group.add(new Adw.ActionRow() { 
                title=_("No contacts"),
                subtitle=_("Add contacts to start chatting")
            });
        }
    }

    private void on_mute_contact(Account account, Jid jid, bool currently_muted, Conversation conversation) {
        if (currently_muted) {
            // Unmute contact
            var dialog = new Adw.AlertDialog(
                _("Unmute contact?"),
                _("This will enable notifications from %s.").printf(jid.to_string())
            );
            dialog.add_response("cancel", _("Cancel"));
            dialog.add_response("unmute", _("Unmute"));
            dialog.set_response_appearance("unmute", Adw.ResponseAppearance.SUGGESTED);
            dialog.default_response = "unmute";
            dialog.close_response = "cancel";

            dialog.response.connect((response) => {
                if (response == "unmute") {
                    conversation.notify_setting = Conversation.NotifySetting.DEFAULT;
                    refresh();
                }
            });

            dialog.present(this);
        } else {
            // Mute contact
            var dialog = new Adw.AlertDialog(
                _("Mute contact?"),
                _("This will disable notifications from %s.").printf(jid.to_string())
            );
            dialog.add_response("cancel", _("Cancel"));
            dialog.add_response("mute", _("Mute"));
            dialog.set_response_appearance("mute", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.default_response = "cancel";
            dialog.close_response = "cancel";

            dialog.response.connect((response) => {
                if (response == "mute") {
                    conversation.notify_setting = Conversation.NotifySetting.OFF;
                    refresh();
                }
            });

            dialog.present(this);
        }
    }

    private void on_block_contact(Account account, Jid jid, bool currently_blocked) {
        if (currently_blocked) {
            // Unblock contact
            var dialog = new Adw.AlertDialog(
                _("Unblock contact?"),
                _("This will allow %s to send you messages again.").printf(jid.to_string())
            );
            dialog.add_response("cancel", _("Cancel"));
            dialog.add_response("unblock", _("Unblock"));
            dialog.set_response_appearance("unblock", Adw.ResponseAppearance.SUGGESTED);
            dialog.default_response = "unblock";
            dialog.close_response = "cancel";

            dialog.response.connect((response) => {
                if (response == "unblock") {
                    model.stream_interactor.get_module(BlockingManager.IDENTITY).unblock(account, jid);
                    refresh();
                }
            });

            dialog.present(this);
        } else {
            // Block contact
            var dialog = new Adw.AlertDialog(
                _("Block contact?"),
                _("This will prevent %s from sending you messages.").printf(jid.to_string())
            );
            dialog.add_response("cancel", _("Cancel"));
            dialog.add_response("block", _("Block"));
            dialog.set_response_appearance("block", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.default_response = "cancel";
            dialog.close_response = "cancel";

            dialog.response.connect((response) => {
                if (response == "block") {
                    model.stream_interactor.get_module(BlockingManager.IDENTITY).block(account, jid);
                    refresh();
                }
            });

            dialog.present(this);
        }
    }

    private void on_remove_contact(Account account, Jid jid, Adw.ActionRow row) {
        var dialog = new Adw.AlertDialog(
            _("Remove contact?"),
            _("This will remove %s from your contact list and delete all conversation history.").printf(jid.to_string())
        );
        dialog.add_response("cancel", _("Cancel"));
        dialog.add_response("remove", _("Remove"));
        dialog.set_response_appearance("remove", Adw.ResponseAppearance.DESTRUCTIVE);
        dialog.default_response = "cancel";
        dialog.close_response = "cancel";

        dialog.response.connect((response) => {
            if (response == "remove") {
                // Get conversation and clear history first
                var conversation = model.stream_interactor.get_module(ConversationManager.IDENTITY)
                    .get_conversation(jid.bare_jid, account, Conversation.Type.CHAT);
                
                if (conversation != null) {
                    model.stream_interactor.get_module(ConversationManager.IDENTITY).clear_conversation_history(conversation);
                    model.stream_interactor.get_module(ConversationManager.IDENTITY).close_conversation(conversation);
                }
                
                // Remove from roster (list will auto-refresh via removed_roster_item signal)
                model.stream_interactor.get_module(RosterManager.IDENTITY).remove_jid(account, jid);
            }
        });

        dialog.present(this);
    }

    private void on_edit_contact(Account account, Jid jid, string? current_alias) {
        var dialog = new Adw.AlertDialog(
            _("Edit Contact Alias"),
            _("Change the display name for %s").printf(jid.to_string())
        );
        
        // Create entry for alias
        var entry = new Entry();
        entry.text = current_alias ?? "";
        entry.placeholder_text = _("Alias (optional)");
        entry.hexpand = true;
        
        var box = new Box(Orientation.VERTICAL, 12);
        box.append(entry);
        dialog.set_extra_child(box);
        
        dialog.add_response("cancel", _("Cancel"));
        dialog.add_response("save", _("Save"));
        dialog.set_response_appearance("save", Adw.ResponseAppearance.SUGGESTED);
        dialog.default_response = "save";
        dialog.close_response = "cancel";
        
        // Validate alias on change
        entry.changed.connect(() => {
            string new_alias = entry.text.strip();
            bool is_valid = true;
            
            // Check for duplicate aliases (excluding current contact)
            if (new_alias != "" && new_alias != current_alias) {
                foreach (Account acc in model.stream_interactor.get_accounts()) {
                    var roster = model.stream_interactor.get_module(RosterManager.IDENTITY).get_roster(acc);
                    if (roster == null) continue;
                    
                    foreach (Roster.Item item in roster) {
                        // Skip the current contact
                        if (acc.equals(account) && item.jid.equals_bare(jid)) continue;
                        
                        if (item.name != null && item.name == new_alias) {
                            is_valid = false;
                            break;
                        }
                    }
                    if (!is_valid) break;
                }
            }
            
            dialog.set_response_enabled("save", is_valid);
            
            if (!is_valid && new_alias != "") {
                entry.add_css_class("error");
            } else {
                entry.remove_css_class("error");
            }
        });
        
        dialog.response.connect((response) => {
            if (response == "save") {
                string new_alias = entry.text.strip();
                string? alias_to_set = new_alias == "" ? null : new_alias;
                
                // Update roster item alias
                model.stream_interactor.get_module(RosterManager.IDENTITY).set_jid_handle(account, jid, alias_to_set);
            }
        });
        
        dialog.present(this);
    }

    private class ContactInfo {
        public Account account;
        public Jid jid;
        public string? display_name;

        public ContactInfo(Account account, Jid jid, string? display_name) {
            this.account = account;
            this.jid = jid;
            this.display_name = display_name;
        }
    }
}
