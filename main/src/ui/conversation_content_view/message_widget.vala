/*
 * Copyright (C) 2025 Ralf Peter <dinox@handwerker.jetzt>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

using Gee;
using Gdk;
using Gtk;
using Pango;
using Xmpp;

using Dino.Entities;

namespace Dino.Ui.ConversationSummary {

public class MessageMetaItem : ContentMetaItem {

    enum AdditionalInfo {
        NONE,
        PENDING,
        DELIVERY_FAILED
    }

    private StreamInteractor stream_interactor;
    private MessageItem message_item;
    public Message.Marked marked { get; set; }
    public Plugins.ConversationItemWidgetInterface outer = null;

    MessageItemEditMode? edit_mode = null;
    ChatTextViewController? controller = null;
    AdditionalInfo additional_info = AdditionalInfo.NONE;

    ulong realize_id = -1;
    ulong marked_notify_handler_id = -1;
    uint pending_timeout_id = -1;

    public Label label = new Label("") { use_markup=true, xalign=0, selectable=true, wrap=true, wrap_mode=Pango.WrapMode.WORD_CHAR, hexpand=true, vexpand=true };

    public MessageMetaItem(ContentItem content_item, StreamInteractor stream_interactor) {
        base(content_item);
        message_item = content_item as MessageItem;
        this.stream_interactor = stream_interactor;

        stream_interactor.get_module<MessageCorrection>(MessageCorrection.IDENTITY).received_correction.connect(on_updated_item);
        stream_interactor.get_module<MessageDeletion>(MessageDeletion.IDENTITY).item_deleted.connect(on_updated_item);

        label.activate_link.connect(on_label_activate_link);

        Message message = ((MessageItem) content_item).message;
        if (message.direction == Message.DIRECTION_SENT && !(message.marked in Message.MARKED_RECEIVED)) {
            var binding = message.bind_property("marked", this, "marked");
            marked_notify_handler_id = this.notify["marked"].connect(() => {
                // Currently "pending", but not anymore
                if (additional_info == AdditionalInfo.PENDING &&
                        message.marked != Message.Marked.SENDING && message.marked != Message.Marked.UNSENT) {
                    update_label();
                }

                // Currently "error", but not anymore
                if (additional_info == AdditionalInfo.DELIVERY_FAILED && message.marked != Message.Marked.ERROR) {
                    update_label();
                }

                // Currently not error, but should be
                if (additional_info != AdditionalInfo.DELIVERY_FAILED && message.marked == Message.Marked.ERROR) {
                    update_label();
                }

                // Nothing bad can happen anymore
                if (message.marked in Message.MARKED_RECEIVED) {
                    binding.unbind();
                    this.disconnect(marked_notify_handler_id);
                    marked_notify_handler_id = -1;
                }
            });
        }

        update_label();
    }

    private void generate_markup_text(ContentItem item, Label label) {
        MessageItem message_item = item as MessageItem;
        Conversation conversation = message_item.conversation;
        Message message = message_item.message;

        // Get a copy of the markup spans, such that we can modify them
        var markups = new ArrayList<Xep.MessageMarkup.Span>();
        foreach (var markup in message.get_markups()) {
            markups.add(new Xep.MessageMarkup.Span() { types=markup.types, start_char=markup.start_char, end_char=markup.end_char });
        }

        string markup_text = message.body;

        var attrs = new AttrList();
        label.set_attributes(attrs);

        if (markup_text == null) return; // TODO remove

        // Increased limit from 10,000 to 100,000 characters (issue #1779)
        // Most XMPP servers limit messages to ~262KB, so 100k chars is reasonable
        // Extremely long messages (>100k) are truncated with a notice
        bool message_truncated = false;
        if (markup_text.length > 100000) {
            markup_text = markup_text.substring(0, 100000);
            message_truncated = true;
        }

        bool theme_dependent = false;

        markup_text = Util.remove_fallbacks_adjust_markups(markup_text, message.quoted_item_id > 0, message.get_fallbacks(), markups);

        var bold_attr = Pango.attr_weight_new(Pango.Weight.BOLD);
        var italic_attr = Pango.attr_style_new(Pango.Style.ITALIC);

        bool is_me_message = false;
        string me_display_name = "";

        // Prefix message with name instead of /me
        if (markup_text.has_prefix("/me ")) {
            string display_name = Util.get_participant_display_name(stream_interactor, conversation, message.from);
            markup_text = display_name + " " + markup_text.substring(4);
            is_me_message = true;
            me_display_name = display_name;

            foreach (Xep.MessageMarkup.Span span in markups) {
                int length = display_name.char_count() - 4 + 1;
                span.start_char += length;
                span.end_char += length;
            }
        }

        // Work around pango bug - must happen BEFORE computing AttrList byte indices,
        // because NBSP (U+00A0) is 2 bytes in UTF-8 vs 1 byte for regular space
        markup_text = Util.unbreak_space_around_non_spacing_mark((owned) markup_text);

        // Compute /me bold/italic AFTER unbreak_space so byte indices are correct
        if (is_me_message) {
            // Recompute byte length after potential NBSP expansion
            int name_byte_len = markup_text.index_of_nth_char(me_display_name.char_count());
            bold_attr.end_index = name_byte_len;
            italic_attr.end_index = name_byte_len;
            attrs.insert(bold_attr.copy());
            attrs.insert(italic_attr.copy());
        }

        foreach (var markup in markups) {
            foreach (var ty in markup.types) {
                Attribute attr = null;
                switch (ty) {
                    case Xep.MessageMarkup.SpanType.EMPHASIS:
                        attr = Pango.attr_style_new(Pango.Style.ITALIC);
                        break;
                    case Xep.MessageMarkup.SpanType.STRONG_EMPHASIS:
                        attr = Pango.attr_weight_new(Pango.Weight.BOLD);
                        break;
                    case Xep.MessageMarkup.SpanType.DELETED:
                        attr = Pango.attr_strikethrough_new(true);
                        break;
                }
                attr.start_index = markup_text.index_of_nth_char(markup.start_char);
                attr.end_index = markup_text.index_of_nth_char(markup.end_char);
                attrs.insert(attr.copy());
            }
        }

        if (conversation.type_ == Conversation.Type.GROUPCHAT) {
            markup_text = Util.parse_add_markup_theme(markup_text, conversation.nickname, true, true, true, Util.is_dark_theme(this.label), ref theme_dependent);
        } else {
            markup_text = Util.parse_add_markup_theme(markup_text, null, true, true, true, Util.is_dark_theme(this.label), ref theme_dependent);
        }

        int only_emoji_count = Util.get_only_emoji_count(markup_text);
        if (only_emoji_count != -1) {
            string size_str = only_emoji_count < 5 ? "xx-large" : "large";
            markup_text = @"<span size=\'$size_str\'>" + markup_text + "</span>";
        }

        string dim_color = Util.is_dark_theme(this.label) ? "#BDBDBD" : "#707070";

        if (message.body == "") {
            markup_text = @"<i><span size='small' color='$dim_color'>%s</span></i>".printf(_("Message deleted"));
            theme_dependent = true;
        }
        if (message.edit_to != null) {
            markup_text += @"  <span size='small' color='$dim_color'>(%s)</span>".printf(_("edited"));
            theme_dependent = true;
        }
        if (message_truncated) {
            markup_text += @"\n<i><span size='small' color='$dim_color'>[%s]</span></i>".printf(_("Message truncated - exceeds 100,000 characters"));
            theme_dependent = true;
        }

        // Append message status info
        additional_info = AdditionalInfo.NONE;
        if (message.direction == Message.DIRECTION_SENT && (message.marked == Message.Marked.SENDING || message.marked == Message.Marked.UNSENT)) {
            // Append "pending..." iff message has not been sent yet
            if (message.time.compare(new DateTime.now_utc().add_seconds(-10)) < 0) {
                markup_text += @"  <span size='small' color='$dim_color'>%s</span>".printf(_("pending…"));
                theme_dependent = true;
                additional_info = AdditionalInfo.PENDING;
            } else {
                int time_diff = (- (int) message.time.difference(new DateTime.now_utc()) / 1000);
                if (pending_timeout_id != -1) Source.remove(pending_timeout_id);
                pending_timeout_id = Timeout.add(10000 - time_diff, () => {
                    update_label();
                    pending_timeout_id = -1;
                    return false;
                });
            }
        } else if (message.direction == Message.DIRECTION_SENT && message.marked == Message.Marked.ERROR) {
            // Append "delivery failed" if there was a server error
            string error_color = Util.rgba_to_hex(Util.get_label_pango_color(label, "@error_color"));
            markup_text += "  <span size='small' color='%s'>%s</span>".printf(error_color, _("delivery failed"));
            theme_dependent = true;
            additional_info = AdditionalInfo.DELIVERY_FAILED;
        }

        if (theme_dependent && realize_id == -1) {
            realize_id = label.realize.connect(update_label);
        } else if (!theme_dependent && realize_id != -1) {
            label.disconnect(realize_id);
        }

        // Reset selectable before changing text to avoid stale cursor index
        // (Pango-CRITICAL: pango_layout_get_cursor_pos assertion failure)
        label.selectable = false;
        label.label = markup_text;
        label.selectable = true;
    }

    public void update_label() {
        generate_markup_text(content_item, label);
    }

    private Widget? create_map_widget(string geo_uri) {
        debug("MessageMetaItem: Creating map widget for URI: %s", geo_uri);
        // geo:lat,lon
        string content = geo_uri.substring(4);
        string[] parts = content.split(",");
        if (parts.length < 2) {
            debug("MessageMetaItem: Invalid geo URI format (split count: %d)", parts.length);
            return null;
        }

        double lat = double.parse(parts[0].replace(",", "."));
        double lon = double.parse(parts[1].replace(",", "."));
        debug("MessageMetaItem: Parsed coordinates: %f, %f", lat, lon);

        // Calculate OSM tile (Zoom 15)
        int zoom = 15;
        double lat_rad = lat * Math.PI / 180.0;
        double n = Math.pow(2, zoom);
        int xtile = (int)(n * ((lon + 180.0) / 360.0));
        int ytile = (int)(n * (1.0 - (Math.log(Math.tan(lat_rad) + 1.0/Math.cos(lat_rad)) / Math.PI)) / 2.0);
        
        string tile_url = "https://tile.openstreetmap.org/%d/%d/%d.png".printf(zoom, xtile, ytile);
        debug("MessageMetaItem: Tile URL: %s", tile_url);

        Box box = new Box(Orientation.VERTICAL, 0);
        box.add_css_class("message-content"); // Reuse message styling if possible
        box.halign = Align.START;
        box.hexpand = false;
        
        Overlay overlay = new Overlay();
        overlay.set_size_request(256, 256);
        overlay.halign = Align.START;
        overlay.hexpand = false;

        Picture picture = new Picture();
        picture.content_fit = ContentFit.COVER;
        picture.can_shrink = true;
        
        // Fetch image
        var session = new Soup.Session();
        session.user_agent = "DinoX/0.0"; // Identify nicely
        var msg = new Soup.Message("GET", tile_url);
        
        session.send_and_read_async.begin(msg, Priority.DEFAULT, null, (obj, res) => {
            try {
                Bytes bytes = session.send_and_read_async.end(res);
                if (bytes != null) {
                    debug("MessageMetaItem: Map tile downloaded (%d bytes)", (int)bytes.get_size());
                    // Use Pixbuf to decode the PNG data
                    var stream = new MemoryInputStream.from_bytes(bytes);
                    var pixbuf = new Gdk.Pixbuf.from_stream(stream);
                    var texture = Gdk.Texture.for_pixbuf(pixbuf);
                    picture.set_paintable(texture);
                } else {
                    debug("MessageMetaItem: Map tile download returned null bytes");
                }
            } catch (Error e) {
                warning("Failed to load map tile: %s", e.message);
            }
        });

        overlay.set_child(picture);

        // Add Marker
        Image marker = new Image.from_icon_name("mark-location-symbolic");
        marker.pixel_size = 32;
        marker.halign = Align.CENTER;
        marker.valign = Align.CENTER;
        marker.add_css_class("error"); // Use error color (usually red) for visibility
        overlay.add_overlay(marker);

        box.append(overlay);
        
        Label caption = new Label("Open OpenStreetMap");
        caption.add_css_class("dim-label");
        caption.margin_top = 5;
        box.append(caption);

        var gesture = new GestureClick();
        gesture.pressed.connect(() => {
            string link = "https://www.openstreetmap.org/?mlat=%s&mlon=%s#map=16/%s/%s".printf(parts[0], parts[1], parts[0], parts[1]);
            var launcher = new Gtk.UriLauncher(link);
            launcher.launch.begin(null, null, (obj, res) => {
                try {
                    launcher.launch.end(res);
                } catch (Error e) {
                    warning("Failed to open link: %s", e.message);
                }
            });
        });
        box.add_controller(gesture);
        box.set_cursor(new Gdk.Cursor.from_name("pointer", null));

        return box;
    }

    public override Object? get_widget(Plugins.ConversationItemWidgetInterface outer, Plugins.WidgetType type) {
        this.outer = outer;

        this.notify["in-edit-mode"].connect(on_in_edit_mode_changed);

        Widget? main_widget = label;

        if (message_item.message.body != null && message_item.message.body.has_prefix("geo:")) {
            var map_widget = create_map_widget(message_item.message.body);
            if (map_widget != null) {
                outer.set_widget(map_widget, Plugins.WidgetType.GTK4, 2);
                main_widget = map_widget;
            } else {
                outer.set_widget(label, Plugins.WidgetType.GTK4, 2);
            }
        } else {
            outer.set_widget(label, Plugins.WidgetType.GTK4, 2);
        }

        if (message_item.message.quoted_item_id > 0) {
            var quoted_content_item = stream_interactor.get_module<ContentItemStore>(ContentItemStore.IDENTITY).get_item_by_id(message_item.conversation, message_item.message.quoted_item_id);
            if (quoted_content_item != null) {
                var quote_model = new Quote.Model.from_content_item(quoted_content_item, message_item.conversation, stream_interactor);
                quote_model.jump_to.connect(() => {
                    GLib.Application.get_default().activate_action("jump-to-conversation-message", new GLib.Variant.tuple(new GLib.Variant[] { new GLib.Variant.int32(message_item.conversation.id), new GLib.Variant.int32(quoted_content_item.id) }));
                });
                var quote_widget = Quote.get_widget(quote_model);
                outer.set_widget(quote_widget, Plugins.WidgetType.GTK4, 1);
            }
        }

        // URL link preview (Telegram-style)
        string? preview_url = Dino.Ui.extract_preview_url(message_item.message.body);
        if (preview_url != null) {
            var preview_widget = new Dino.Ui.UrlPreviewWidget(preview_url);
            outer.set_widget(preview_widget, Plugins.WidgetType.GTK4, 3);
        }

        return main_widget;
    }

    public override Gee.List<Plugins.MessageAction>? get_item_actions(Plugins.WidgetType type) {
        if (in_edit_mode) return null;

        Gee.List<Plugins.MessageAction> actions = new ArrayList<Plugins.MessageAction>();

        bool correction_allowed = stream_interactor.get_module<MessageCorrection>(MessageCorrection.IDENTITY).is_own_correction_allowed(message_item.conversation, message_item.message);
        if (correction_allowed) {
            Plugins.MessageAction action1 = new Plugins.MessageAction();
            action1.name = "correction";
            action1.icon_name = "document-edit-symbolic";
            action1.tooltip = _("Edit message");
            action1.callback = () => {
                this.in_edit_mode = true;
            };
            actions.add(action1);
        }

        actions.add(get_reply_action(content_item, message_item.conversation, stream_interactor));
        actions.add(get_reaction_action(content_item, message_item.conversation, stream_interactor));

        // var kick_action = get_kick_action(content_item, message_item.conversation, stream_interactor);
        // if (kick_action != null) actions.add(kick_action);

        // var ban_action = get_ban_action(content_item, message_item.conversation, stream_interactor);
        // if (ban_action != null) actions.add(ban_action);

        var delete_action = get_delete_action(content_item, message_item.conversation, stream_interactor);
        if (delete_action != null) actions.add(delete_action);

        return actions;
    }

    private void on_in_edit_mode_changed() {
        if (in_edit_mode == false) return;
        bool allowed = stream_interactor.get_module<MessageCorrection>(MessageCorrection.IDENTITY).is_own_correction_allowed(message_item.conversation, message_item.message);
        if (allowed) {
            MessageItem message_item = content_item as MessageItem;
            Message message = message_item.message;

            edit_mode = new MessageItemEditMode();
            controller = new ChatTextViewController(edit_mode.chat_text_view, stream_interactor);
            Conversation conversation = message_item.conversation;
            controller.initialize_for_conversation(conversation);

            edit_mode.cancelled.connect(() => {
                in_edit_mode = false;
                outer.set_widget(label, Plugins.WidgetType.GTK4, 2);
            });
            edit_mode.send.connect(() => {
                string text = edit_mode.chat_text_view.text_view.buffer.text;
                var markups = edit_mode.chat_text_view.get_markups();
                Dino.send_message(message_item.conversation, text, message_item.message.quoted_item_id, message_item.message, markups);

                in_edit_mode = false;
                outer.set_widget(label, Plugins.WidgetType.GTK4, 2);
            });

            edit_mode.chat_text_view.set_text(message);

            outer.set_widget(edit_mode, Plugins.WidgetType.GTK4, 2);
            edit_mode.chat_text_view.text_view.grab_focus();
        } else {
            this.in_edit_mode = false;
        }
    }

    private void on_updated_item(ContentItem content_item) {
        if (this.content_item.id == content_item.id) {
            this.content_item = content_item;
            message_item = content_item as MessageItem;
            update_label();
        }
    }

    public bool on_label_activate_link(string uri) {
        // Always handle xmpp URIs with Dino
        if (!uri.has_prefix("xmpp:")) return false;

        // Bot command links: send command directly in the current conversation
        if (uri.contains("?message;body=")) {
            int body_idx = uri.index_of("?message;body=") + "?message;body=".length;
            string? body = GLib.Uri.unescape_string(uri.substring(body_idx));
            if (body != null && body != "" && message_item != null) {
                Conversation conv = message_item.conversation;
                Dino.send_message(conv, body, 0, null, new Gee.ArrayList<Xmpp.Xep.MessageMarkup.Span>());
                return true;
            }
        }

        File file = File.new_for_uri(uri);
        Dino.Application.get_default().open(new File[]{file}, "");
        return true;
    }

    public override void dispose() {
        if (stream_interactor != null) {
            stream_interactor.get_module<MessageCorrection>(MessageCorrection.IDENTITY).received_correction.disconnect(on_updated_item);
            stream_interactor.get_module<MessageDeletion>(MessageDeletion.IDENTITY).item_deleted.disconnect(on_updated_item);
            this.notify["in-edit-mode"].disconnect(on_in_edit_mode_changed);
            stream_interactor = null;
        }
        if (marked_notify_handler_id != -1) {
            this.disconnect(marked_notify_handler_id);
            marked_notify_handler_id = -1;
        }
        if (realize_id != -1) {
            label.disconnect(realize_id);
            realize_id = -1;
        }
        if (pending_timeout_id != -1) {
            Source.remove(pending_timeout_id);
            pending_timeout_id = -1;
        }
        if (label != null) {
            label.unparent();
            label.dispose();
            label = null;
        }
        base.dispose();
    }
}

[GtkTemplate (ui = "/im/github/rallep71/DinoX/message_item_widget_edit_mode.ui")]
public class MessageItemEditMode : Box {

    public signal void cancelled();
    public signal void send();

    [GtkChild] public unowned MenuButton emoji_button;
    [GtkChild] public unowned ChatTextView chat_text_view;
    [GtkChild] public unowned Button cancel_button;
    [GtkChild] public unowned Button send_button;
    [GtkChild] public unowned Frame frame;

    construct {
        Util.force_css(frame, "* { border-radius: 3px; padding: 0px 7px; }");

        EmojiChooser chooser = new EmojiChooser();
        chooser.emoji_picked.connect((emoji) => {
            chat_text_view.text_view.buffer.insert_at_cursor(emoji, emoji.data.length);
        });
        emoji_button.set_popover(chooser);

        chat_text_view.text_view.buffer.changed.connect_after(on_text_view_changed);

        cancel_button.clicked.connect(() => cancelled());
        send_button.clicked.connect(() => send());
        chat_text_view.cancel_input.connect(() => cancelled());
        chat_text_view.send_text.connect(() => send());
    }

    private void on_text_view_changed() {
        send_button.sensitive = chat_text_view.text_view.buffer.text != "";
    }
}

}
