/*
 * Copyright (C) 2025 Ralf Peter <dinox@handwerker.jetzt>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

using Gtk;
using Dino.Entities;

namespace Dino.Ui.ConversationSummary {

public class ExpiryNotification : Object {
    private StreamInteractor stream_interactor;
    private Conversation? conversation;
    private ConversationView? conversation_view;
    private Box? current_notification;
    private ulong notify_handler_id = 0;

    public ExpiryNotification(StreamInteractor stream_interactor) {
        this.stream_interactor = stream_interactor;
    }

    public void init(Conversation conversation, ConversationView conversation_view) {
        // Cleanup previous connection
        if (this.conversation != null && notify_handler_id != 0) {
            this.conversation.disconnect(notify_handler_id);
            notify_handler_id = 0;
        }
        
        this.conversation = conversation;
        this.conversation_view = conversation_view;
        
        update_notification();
        
        // Update notification when setting changes
        notify_handler_id = conversation.notify["message-expiry-seconds"].connect(update_notification);
    }

    public void close() {
        if (current_notification != null && conversation_view != null) {
            conversation_view.remove_notification(current_notification);
            current_notification = null;
        }
        if (conversation != null && notify_handler_id != 0) {
            conversation.disconnect(notify_handler_id);
            notify_handler_id = 0;
        }
    }

    private void update_notification() {
        // Remove old notification
        if (current_notification != null) {
            conversation_view.remove_notification(current_notification);
            current_notification = null;
        }
        
        if (conversation.message_expiry_seconds == 0) return;
        
        // Create new notification
        current_notification = new Box(Orientation.HORIZONTAL, 8) { margin_start = 8, margin_end = 8 };
        
        var icon = new Image.from_icon_name("alarm-symbolic");
        icon.add_css_class("warning");
        
        string time_text = get_time_text(conversation.message_expiry_seconds);
        var label = new Label(_("Messages in this chat will be deleted %s").printf(time_text));
        
        current_notification.append(icon);
        current_notification.append(label);
        
        conversation_view.add_notification(current_notification);
    }
    
    private string get_time_text(int seconds) {
        switch (seconds) {
            case 900: return _("after 15 minutes");
            case 1800: return _("after 30 minutes");
            case 3600: return _("after 1 hour");
            case 86400: return _("after 24 hours");
            case 604800: return _("after 7 days");
            case 2592000: return _("after 30 days");
            default: return "";
        }
    }
}

}
