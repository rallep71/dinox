/*
 * Copyright (C) 2025 Ralf Peter <dinox@handwerker.jetzt>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

using Gtk;
using Gee;

using Dino.Entities;

namespace Dino.Ui {

public class EncryptionButton {

    public signal void encryption_changed(Encryption encryption);

    private MenuButton menu_button;
    private Conversation? conversation;
    private string? current_icon;
    private StreamInteractor stream_interactor;
    private SimpleAction action;
    ulong conversation_encryption_handler_id = -1;

    public EncryptionButton(StreamInteractor stream_interactor, MenuButton menu_button) {
        this.stream_interactor = stream_interactor;
        this.menu_button = menu_button;

        // Build menu model including "Unencrypted" and all registered encryption entries
        Menu menu_model = new Menu();

        MenuItem unencrypted_item = new MenuItem(_("Unencrypted"), "enc.encryption");
        unencrypted_item.set_action_and_target_value("enc.encryption", new Variant.int32(Encryption.NONE));
        menu_model.append_item(unencrypted_item);

        var encryption_entries = new ArrayList<Plugins.EncryptionListEntry>();
        Application app = GLib.Application.get_default() as Application;
        encryption_entries.add_all(app.plugin_registry.encryption_list_entries.values);
        encryption_entries.sort((a,b) => b.name.collate(a.name));
        foreach (var e in encryption_entries) {
            MenuItem item = new MenuItem(e.name, "enc.encryption");
            item.set_action_and_target_value("enc.encryption", new Variant.int32(e.encryption));
            menu_model.append_item(item);
        }

        // Create action to act on menu selections (stateful => radio buttons)
        SimpleActionGroup action_group = new SimpleActionGroup();
        action = new SimpleAction.stateful("encryption", VariantType.INT32, new Variant.int32(Encryption.NONE));
        action.activate.connect((parameter) => {
            debug("EncryptionButton: action.activate called with %d", parameter.get_int32());
            if (conversation == null) {
                debug("EncryptionButton: conversation is NULL, returning");
                return;
            }
            debug("EncryptionButton: Setting encryption to %d for %s", parameter.get_int32(), conversation.counterpart.to_string());
            action.set_state(parameter);
            conversation.encryption = (Encryption) parameter.get_int32();
            encryption_changed(conversation.encryption);
        });
        action_group.add_action(action);
        menu_button.insert_action_group("enc", action_group);

        // Create and set popover menu
        Gtk.PopoverMenu popover_menu = new Gtk.PopoverMenu.from_model(menu_model);
        menu_button.popover = popover_menu;

        stream_interactor.get_module<MucManager>(MucManager.IDENTITY).room_info_updated.connect((account, muc_jid) => {
            if (conversation != null && conversation.account.equals(account) && conversation.counterpart.equals(muc_jid)) {
                check_encryption_validity();
                update_visibility();
            }
        });
    }

    // Check if encryption is still valid for this conversation
    // If room changed from private to public, disable encryption
    // If room changed from public to private, enable encryption (OMEMO preferred)
    private void check_encryption_validity() {
        if (conversation == null) return;
        if (conversation.type_ != Conversation.Type.GROUPCHAT) return;
        
        bool is_private = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).is_private_room(
            conversation.account, conversation.counterpart);
        
        if (!is_private && conversation.encryption != Encryption.NONE) {
            // Room became public - disable encryption
            conversation.encryption = Encryption.NONE;
            update_encryption_menu_state();
            update_encryption_menu_icon();
            encryption_changed(Encryption.NONE);
        } else if (is_private && conversation.encryption == Encryption.NONE) {
            // Room became private - enable OMEMO encryption by default
            conversation.encryption = Encryption.OMEMO;
            update_encryption_menu_state();
            update_encryption_menu_icon();
            encryption_changed(conversation.encryption);
        }
    }

    private void update_encryption_menu_state() {
        if (conversation == null) return;
        action.set_state(new Variant.int32(conversation.encryption));
        action.change_state(new Variant.int32(conversation.encryption));
    }

    private void set_icon(string icon) {
        if (icon != current_icon) {
            menu_button.set_icon_name(icon);
            current_icon = icon;
        }
    }

    private void update_encryption_menu_icon() {
        if (conversation == null) return;
        set_icon(conversation.encryption == Encryption.NONE ? "changes-allow-symbolic" : "changes-prevent-symbolic");
    }

    private void update_visibility() {
        if (conversation == null) {
            menu_button.visible = false;
            return;
        }
        // Hide encryption button for bot conversations (subscription suppressed = bot JID)
        if (stream_interactor.get_module<PresenceManager>(PresenceManager.IDENTITY).is_subscription_suppressed(conversation.counterpart)) {
            menu_button.visible = false;
            return;
        }
        if (conversation.encryption != Encryption.NONE) {
            menu_button.visible = true;
            return;
        }
        switch (conversation.type_) {
            case Conversation.Type.CHAT:
                menu_button.visible = true;
                break;
            case Conversation.Type.GROUPCHAT_PM:
                menu_button.visible = false;
                break;
            case Conversation.Type.GROUPCHAT:
                menu_button.visible = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).is_private_room(conversation.account, conversation.counterpart);
                break;
        }
    }

    public void set_conversation(Conversation conversation) {
        debug("EncryptionButton.set_conversation: Called with %s", conversation != null ? conversation.counterpart.to_string() : "NULL");
        if (conversation_encryption_handler_id != -1 && this.conversation != null) {
            this.conversation.disconnect(conversation_encryption_handler_id);
        }

        this.conversation = conversation;
        debug("EncryptionButton.set_conversation: this.conversation is now %s", this.conversation != null ? "SET" : "NULL");
        update_encryption_menu_state();
        update_encryption_menu_icon();
        update_visibility();
        encryption_changed(this.conversation.encryption);

        conversation_encryption_handler_id = conversation.notify["encryption"].connect(() => {
            update_encryption_menu_state();
            update_encryption_menu_icon();
        });
    }
}

}
