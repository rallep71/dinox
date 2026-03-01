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

using Dino;
using Dino.Entities;
using Xmpp;

namespace Dino.Ui {

[GtkTemplate (ui = "/im/github/rallep71/DinoX/conversation_row.ui")]
public class ConversationSelectorRow : ListBoxRow {

    [GtkChild] protected unowned AvatarPicture picture;
    [GtkChild] protected unowned Label name_label;
    [GtkChild] protected unowned Label time_label;
    [GtkChild] protected unowned Label nick_label;
    [GtkChild] protected unowned Label message_label;
    [GtkChild] protected unowned Label unread_count_label;
    [GtkChild] protected unowned Image muted_image;
    [GtkChild] protected unowned Image blocked_image;
    [GtkChild] protected unowned Image pinned_image;
    [GtkChild] protected unowned Label status_label;
    [GtkChild] protected unowned Image muc_indicator;
    [GtkChild] protected unowned Image private_room_image;
    [GtkChild] public unowned Revealer main_revealer;

    public Conversation conversation { get; private set; }

    protected const int AVATAR_SIZE = 40;

    protected ContentItem? last_content_item;
    protected int num_unread = 0;
    private PopoverMenu? active_popover = null;
    private Widget? cached_groupchat_tooltip = null;
    // D14: Signal handler IDs for proper cleanup
    private ulong muc_room_info_handler_id;
    private ulong muc_subject_set_handler_id;
    private ulong content_new_item_handler_id;
    private ulong correction_handler_id;
    private ulong deletion_handler_id;
    private ulong conversation_cleared_handler_id;
    private ulong block_changed_handler_id;

    protected StreamInteractor stream_interactor;

    construct {
        name_label.attributes = new AttrList();
    }

    public ConversationSelectorRow(StreamInteractor stream_interactor, Conversation conversation) {
        this.conversation = conversation;
        this.stream_interactor = stream_interactor;

        var display_name_model = stream_interactor.get_module<ContactModels>(ContactModels.IDENTITY).get_display_name_model(conversation);
        display_name_model.bind_property("display-name", name_label, "label", BindingFlags.SYNC_CREATE);

        // Add right-click context menu for all conversations
        GestureClick gesture = new GestureClick();
        gesture.set_button(3); // Right click
        gesture.pressed.connect((n_press, x, y) => {
            show_context_menu(x, y);
        });
        add_controller(gesture);
        
        if (conversation.type_ == Conversation.Type.CHAT) {
            // Connect presence signals
            var pm = stream_interactor.get_module<PresenceManager>(PresenceManager.IDENTITY);
            pm.show_received.connect(on_presence_changed);
            pm.received_offline_presence.connect(on_presence_changed);
            pm.status_changed.connect(on_own_status_changed);
            
            // Initial update
            update_status();
        }

        if (conversation.type_ == Conversation.Type.GROUPCHAT) {
            muc_indicator.visible = true;
            muc_room_info_handler_id = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).room_info_updated.connect((account, jid) => {
                if (conversation != null && conversation.counterpart.equals_bare(jid) && conversation.account.equals(account)) {
                    update_read(true); // bubble color might have changed
                    update_private_room_indicator();
                }
            });
            update_private_room_indicator();
        }

        // Set tooltip
        switch (conversation.type_) {
            case Conversation.Type.CHAT:
                has_tooltip = Util.use_tooltips();
                query_tooltip.connect ((x, y, keyboard_tooltip, tooltip) => {
                    tooltip.set_custom(Util.widget_if_tooltips_active(generate_tooltip()));
                    return true;
                });
                break;
            case Conversation.Type.GROUPCHAT:
                has_tooltip = Util.use_tooltips();
                query_tooltip.connect ((x, y, keyboard_tooltip, tooltip) => {
                    if (cached_groupchat_tooltip == null) {
                        cached_groupchat_tooltip = generate_groupchat_tooltip();
                    }
                    tooltip.set_custom(Util.widget_if_tooltips_active(cached_groupchat_tooltip));
                    return true;
                });
                // Invalidate tooltip when subject changes
                muc_subject_set_handler_id = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).subject_set.connect((account, jid, subject) => {
                    if (conversation.account.equals(account) && conversation.counterpart.equals_bare(jid)) {
                        cached_groupchat_tooltip = null;
                        trigger_tooltip_query();
                    }
                });
                break;
            case Conversation.Type.GROUPCHAT_PM:
                break;
        }

        content_new_item_handler_id = stream_interactor.get_module<ContentItemStore>(ContentItemStore.IDENTITY).new_item.connect((item, c) => {
            if (conversation.equals(c)) {
                content_item_received(item);
            }
        });
        correction_handler_id = stream_interactor.get_module<MessageCorrection>(MessageCorrection.IDENTITY).received_correction.connect((item) => {
            if (last_content_item != null && last_content_item.id == item.id) {
                content_item_received(item);
            }
        });
        deletion_handler_id = stream_interactor.get_module<MessageDeletion>(MessageDeletion.IDENTITY).item_deleted.connect((item) => {
            if (last_content_item != null && last_content_item.id == item.id) {
                content_item_received(item);
            }
        });
        conversation_cleared_handler_id = stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY).conversation_cleared.connect((cleared_conversation) => {
            if (conversation.id == cleared_conversation.id) {
                last_content_item = null;
                update_message_label();
                update_time_label();
            }
        });

        last_content_item = stream_interactor.get_module<ContentItemStore>(ContentItemStore.IDENTITY).get_latest(conversation);

        picture.model = new ViewModel.CompatAvatarPictureModel(stream_interactor).set_conversation(conversation);
        conversation.notify["read-up-to-item"].connect(() => update_read());
        conversation.notify["pinned"].connect(() => { update_pinned_icon(); });
        conversation.notify["notify-setting"].connect(() => { update_muted_icon(); });
        
        // Listen for block status changes
        if (conversation.type_ == Conversation.Type.CHAT) {
            block_changed_handler_id = stream_interactor.get_module<BlockingManager>(BlockingManager.IDENTITY).block_changed.connect((account, jid) => {
                if (conversation.account.equals(account) && conversation.counterpart.equals_bare(jid)) {
                    update_blocked_icon();
                }
            });
        }

        update_name_label();
        update_pinned_icon();
        update_muted_icon();
        update_blocked_icon();
        content_item_received();
    }

    ~ConversationSelectorRow() {
        if (conversation.type_ == Conversation.Type.CHAT) {
            var pm = stream_interactor.get_module<PresenceManager>(PresenceManager.IDENTITY);
            pm.show_received.disconnect(on_presence_changed);
            pm.received_offline_presence.disconnect(on_presence_changed);
            pm.status_changed.disconnect(on_own_status_changed);
        }
        // D14: Disconnect all registered signal handlers to prevent leaks
        // Use is_connected() guard: module instance from get_module() during finalization
        // may differ from the one used during construction.
        var muc_mgr = stream_interactor.get_module<MucManager>(MucManager.IDENTITY);
        if (muc_room_info_handler_id != 0 && muc_mgr != null && SignalHandler.is_connected(muc_mgr, muc_room_info_handler_id)) {
            SignalHandler.disconnect(muc_mgr, muc_room_info_handler_id);
        }
        if (muc_subject_set_handler_id != 0 && muc_mgr != null && SignalHandler.is_connected(muc_mgr, muc_subject_set_handler_id)) {
            SignalHandler.disconnect(muc_mgr, muc_subject_set_handler_id);
        }
        var cis = stream_interactor.get_module<ContentItemStore>(ContentItemStore.IDENTITY);
        if (content_new_item_handler_id != 0 && cis != null && SignalHandler.is_connected(cis, content_new_item_handler_id)) {
            SignalHandler.disconnect(cis, content_new_item_handler_id);
        }
        var mc = stream_interactor.get_module<MessageCorrection>(MessageCorrection.IDENTITY);
        if (correction_handler_id != 0 && mc != null && SignalHandler.is_connected(mc, correction_handler_id)) {
            SignalHandler.disconnect(mc, correction_handler_id);
        }
        var md = stream_interactor.get_module<MessageDeletion>(MessageDeletion.IDENTITY);
        if (deletion_handler_id != 0 && md != null && SignalHandler.is_connected(md, deletion_handler_id)) {
            SignalHandler.disconnect(md, deletion_handler_id);
        }
        var cm = stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY);
        if (conversation_cleared_handler_id != 0 && cm != null && SignalHandler.is_connected(cm, conversation_cleared_handler_id)) {
            SignalHandler.disconnect(cm, conversation_cleared_handler_id);
        }
        var bm = stream_interactor.get_module<BlockingManager>(BlockingManager.IDENTITY);
        if (block_changed_handler_id != 0 && bm != null && SignalHandler.is_connected(bm, block_changed_handler_id)) {
            SignalHandler.disconnect(bm, block_changed_handler_id);
        }
    }

    public void update() {
        update_time_label();
    }

    public void content_item_received(ContentItem? ci = null) {
        // D3: If a new item is provided and is newer than cached, use it directly
        // instead of querying the DB (avoids N+1 on every incoming message)
        if (ci != null && (last_content_item == null || ci.compare(last_content_item) >= 0)) {
            last_content_item = ci;
        } else {
            last_content_item = stream_interactor.get_module<ContentItemStore>(ContentItemStore.IDENTITY).get_latest(conversation) ?? ci;
        }
        update_message_label();
        update_time_label();
        update_read();
    }

    public void dismiss_popover() {
        if (active_popover != null) {
            active_popover.popdown();
            active_popover.unparent();
            active_popover = null;
        }
    }

    public async void colapse() {
        dismiss_popover();
        main_revealer.set_transition_type(RevealerTransitionType.SLIDE_UP);
        main_revealer.set_reveal_child(false);

        // Animations can be diabled (=> child_revealed immediately false). Wait for completion in case they're enabled.
        if (main_revealer.child_revealed) {
            main_revealer.notify["child-revealed"].connect(() => {
                Idle.add(colapse.callback);
            });
            yield;
        }
    }

    protected void update_name_label() {
        name_label.label = Util.get_conversation_display_name(stream_interactor, conversation);
    }

    private void update_pinned_icon() {
        pinned_image.visible = conversation.pinned != 0;
    }

    private void update_muted_icon() {
        muted_image.visible = (conversation.notify_setting == Conversation.NotifySetting.OFF);
    }

    private void update_blocked_icon() {
        if (conversation.type_ == Conversation.Type.CHAT) {
            bool is_blocked = stream_interactor.get_module<BlockingManager>(BlockingManager.IDENTITY).is_blocked(conversation.account, conversation.counterpart);
            blocked_image.visible = is_blocked;
        } else {
            blocked_image.visible = false;
        }
    }

    protected void update_time_label(DateTime? new_time = null) {
        if (last_content_item != null) {
            time_label.visible = true;
            time_label.label = get_relative_time(last_content_item.time.to_local());
        }
    }

    protected void update_message_label() {
        if (last_content_item != null) {
            switch (last_content_item.type_) {
                case MessageItem.TYPE:
                    MessageItem message_item = last_content_item as MessageItem;
                    Message last_message = message_item.message;

                    string body = Dino.message_body_without_reply_fallback(last_message);
                    bool me_command = body.has_prefix("/me ");

                    /* If we have a /me command, we always show the display
                     * name, and we don't set me_is_me on
                     * get_participant_display_name, since that will return
                     * "Me" (internationalized), whereas /me commands expect to
                     * be in the third person. We also omit the colon in this
                     * case, and strip off the /me prefix itself. */

                    if (conversation.type_ == Conversation.Type.GROUPCHAT || me_command) {
                        nick_label.label = Util.get_participant_display_name(stream_interactor, conversation, last_message.from, !me_command);
                    } else if (last_message.direction == Message.DIRECTION_SENT) {
                        nick_label.label = _("Me");
                    } else {
                        nick_label.label = "";
                    }

                    if (me_command) {
                        /* Don't slice off the space after /me */
                        body = body.slice("/me".length, body.length);
                    } else if (nick_label.label.length > 0) {
                        /* TODO: Is this valid for RTL languages? */
                        nick_label.label += ": ";
                    }

                    if (message_item.message.body == "") {
                        change_label_attribute(message_label, attr_style_new(Pango.Style.ITALIC));
                        message_label.label = _("Message deleted");
                    } else {
                        change_label_attribute(message_label, attr_style_new(Pango.Style.NORMAL));
                        message_label.label = Util.summarize_whitespaces_to_space(body);
                    }

                    break;
                case FileItem.TYPE:
                    FileItem file_item = last_content_item as FileItem;
                    FileTransfer transfer = file_item.file_transfer;
                    if (transfer == null) break;

                    if (conversation.type_ == Conversation.Type.GROUPCHAT) {
                        // TODO properly display nick for oneself
                        nick_label.label = Util.get_participant_display_name(stream_interactor, conversation, file_item.file_transfer.from, true) + ": ";
                    } else {
                        nick_label.label = transfer.direction == Message.DIRECTION_SENT ? _("Me") + ": " : "";
                    }

                    bool file_is_image = transfer.mime_type != null && transfer.mime_type.has_prefix("image");
                    change_label_attribute(message_label, attr_style_new(Pango.Style.ITALIC));
                    if (transfer.direction == Message.DIRECTION_SENT) {
                        message_label.label = (file_is_image ? _("Image sent") : _("File sent") );
                    } else {
                        message_label.label = (file_is_image ? _("Image received") : _("File received") );
                    }
                    break;
                case CallItem.TYPE:
                    CallItem call_item = (CallItem) last_content_item;
                    Call call = call_item.call;

                    nick_label.label = call.direction == Call.DIRECTION_OUTGOING ? _("Me") + ": " : "";
                    change_label_attribute(message_label, attr_style_new(Pango.Style.ITALIC));
                    message_label.label = call.direction == Call.DIRECTION_OUTGOING ? _("Outgoing call") : _("Incoming call");
                    break;
            }
            nick_label.visible = true;
            message_label.visible = true;
        }
    }

    private static void change_label_attribute(Label label, owned Attribute attribute) {
        AttrList copy = label.attributes.copy();
        copy.change((owned) attribute);
        label.attributes = copy;
    }

    private bool update_read_pending = false;
    private bool update_read_pending_force = false;
    protected void update_read(bool force_update = false) {
        if (force_update) update_read_pending_force = true;
        if (update_read_pending) return;
        update_read_pending = true;
        Idle.add(() => {
            bool force = update_read_pending_force;
            update_read_pending = false;
            update_read_pending_force = false;
            update_read_idle(force);
            return Source.REMOVE;
        }, Priority.LOW);
    }

    private void update_read_idle(bool force_update = false) {
        int current_num_unread = stream_interactor.get_module<ChatInteraction>(ChatInteraction.IDENTITY).get_num_unread(conversation);
        if (num_unread == current_num_unread && !force_update) return;
        num_unread = current_num_unread;

        if (num_unread == 0) {
            unread_count_label.visible = false;

            change_label_attribute(name_label, attr_weight_new(Weight.NORMAL));
            change_label_attribute(time_label, attr_weight_new(Weight.NORMAL));
            change_label_attribute(nick_label, attr_weight_new(Weight.NORMAL));
            change_label_attribute(message_label, attr_weight_new(Weight.NORMAL));
        } else {
            unread_count_label.label = num_unread.to_string();
            unread_count_label.visible = true;

            if (conversation.get_notification_setting(stream_interactor) == Conversation.NotifySetting.ON) {
                unread_count_label.add_css_class("unread-count-notify");
                unread_count_label.remove_css_class("unread-count");
            } else {
                unread_count_label.add_css_class("unread-count");
                unread_count_label.remove_css_class("unread-count-notify");
            }

            change_label_attribute(name_label, attr_weight_new(Weight.BOLD));
            change_label_attribute(time_label, attr_weight_new(Weight.BOLD));
            change_label_attribute(nick_label, attr_weight_new(Weight.BOLD));
            change_label_attribute(message_label, attr_weight_new(Weight.BOLD));
        }
    }

    private Widget generate_groupchat_tooltip() {
        Grid grid = new Grid() { row_spacing=5, column_homogeneous=false, column_spacing=5, margin_start=7, margin_end=7, margin_top=7, margin_bottom=7 };

        // JID as title
        Label jid_label = new Label(conversation.counterpart.bare_jid.to_string()) { valign=Align.START, xalign=0 };
        jid_label.attributes = new AttrList();
        jid_label.attributes.insert(attr_weight_new(Weight.BOLD));
        grid.attach(jid_label, 0, 0, 2, 1);

        int row = 1;

        // Room topic/subject
        string? topic = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).get_groupchat_subject(conversation.counterpart, conversation.account);
        // topic can legitimately be null for rooms without a subject set
        if (topic != null && topic.strip() != "") {
            Label topic_title = new Label(_("Thema:")) { valign=Align.START, xalign=0 };
            topic_title.attributes = new AttrList();
            topic_title.attributes.insert(attr_style_new(Style.ITALIC));
            grid.attach(topic_title, 0, row, 1, 1);

            // Limit topic length for tooltip
            string display_topic = topic.strip();
            if (display_topic.length > 100) {
                display_topic = display_topic.substring(0, 100) + "…";
            }
            Label topic_label = new Label(display_topic) { valign=Align.START, xalign=0, wrap=true, max_width_chars=40 };
            grid.attach(topic_label, 1, row, 1, 1);
            row++;
        }

        // Room features (private/public, members-only, etc.)
        MucManager muc_manager = stream_interactor.get_module<MucManager>(MucManager.IDENTITY);
        var features = new StringBuilder();
        
        if (muc_manager.is_private_room(conversation.account, conversation.counterpart)) {
            features.append(_("Privat"));
        } else {
            features.append(_("Öffentlich"));
        }

        if (features.len > 0) {
            Label features_title = new Label(_("Typ:")) { valign=Align.START, xalign=0 };
            features_title.attributes = new AttrList();
            features_title.attributes.insert(attr_style_new(Style.ITALIC));
            grid.attach(features_title, 0, row, 1, 1);

            Label features_label = new Label(features.str) { valign=Align.START, xalign=0 };
            grid.attach(features_label, 1, row, 1, 1);
            row++;
        }

        return grid;
    }

    private static Regex dino_resource_regex = /^dino\.[a-f0-9]{8}$/;

    private Widget generate_tooltip() {
        Grid grid = new Grid() { row_spacing=5, column_homogeneous=false, column_spacing=5, margin_start=7, margin_end=7, margin_top=7, margin_bottom=7 };

        Label label = new Label(conversation.counterpart.to_string()) { valign=Align.START, xalign=0 };
        label.attributes = new AttrList();
        label.attributes.insert(attr_weight_new(Weight.BOLD));

        grid.attach(label, 0, 0, 2, 1);

        Gee.List<Jid>? full_jids = stream_interactor.get_module<PresenceManager>(PresenceManager.IDENTITY).get_full_jids(conversation.counterpart, conversation.account);
        if (full_jids == null) return grid;

        for (int i = 0; i < full_jids.size; i++) {
            Jid full_jid = full_jids[i];
            string? show = stream_interactor.get_module<PresenceManager>(PresenceManager.IDENTITY).get_last_show(full_jid, conversation.account);
            string? status_msg = stream_interactor.get_module<PresenceManager>(PresenceManager.IDENTITY).get_last_status_msg(full_jid, conversation.account);

            string? status_text = null;
            if (show == Presence.Stanza.SHOW_AWAY) {
                status_text = _("Away");
            } else if (show == Presence.Stanza.SHOW_XA) {
                status_text = _("Not Available");
            } else if (show == Presence.Stanza.SHOW_DND) {
                status_text = _("Busy");
            } else {
                status_text = _("Online");
            }

            int i_cache = i;
            stream_interactor.get_module<EntityInfo>(EntityInfo.IDENTITY).get_identity.begin(conversation.account, full_jid, (_, res) => {
                Xep.ServiceDiscovery.Identity? identity = stream_interactor.get_module<EntityInfo>(EntityInfo.IDENTITY).get_identity.end(res);

                Image image = new Image() { hexpand=false, valign=Align.CENTER };
                if (identity != null && (identity.type_ == Xep.ServiceDiscovery.Identity.TYPE_PHONE || identity.type_ == Xep.ServiceDiscovery.Identity.TYPE_TABLET)) {
                    image.set_from_icon_name("dino-device-phone-symbolic");
                } else {
                    image.set_from_icon_name("dino-device-desktop-symbolic");
                }

                if (show == Presence.Stanza.SHOW_AWAY) {
                    Util.force_color(image, "#FF9800");
                } else if (show == Presence.Stanza.SHOW_XA || show == Presence.Stanza.SHOW_DND) {
                    Util.force_color(image, "#FF5722");
                } else {
                    Util.force_color(image, "#4CAF50");
                }

                var sb = new StringBuilder();
                if (identity != null && identity.name != null) {
                    sb.append(identity.name);
                } else if (full_jid.resourcepart != null && dino_resource_regex.match(full_jid.resourcepart)) {
                    sb.append("Dino");
                } else if (full_jid.resourcepart != null) {
                    sb.append(full_jid.resourcepart);
                } else {
                    return;
                }
                if (status_text != null) {
                    sb.append(" <i>(").append(GLib.Markup.escape_text(status_text)).append(")</i>");
                }
                if (status_msg != null && status_msg != "") {
                    sb.append("\n<small>").append(GLib.Markup.escape_text(status_msg)).append("</small>");
                }

                Label resource = new Label(sb.str) { use_markup=true, hexpand=true, xalign=0 };

                grid.attach(image, 0, i_cache + 1, 1, 1);
                grid.attach(resource, 1, i_cache + 1, 1, 1);
            });
        }
        return grid;
    }

    private static string get_relative_time(DateTime datetime) {
         DateTime now = new DateTime.now_local();
         TimeSpan timespan = now.difference(datetime);
         if (timespan > 365 * TimeSpan.DAY) {
             return datetime.get_year().to_string();
         } else if (timespan > 7 * TimeSpan.DAY) {
             // Day and month
             // xgettext:no-c-format
             return datetime.format(_("%b %d"));
         } else if (timespan > 2 * TimeSpan.DAY) {
             return datetime.format("%a");
         } else if (datetime.get_day_of_month() != now.get_day_of_month()) {
             return _("Yesterday");
         } else if (timespan > 9 * TimeSpan.MINUTE) {
             return datetime.format(Util.is_24h_format() ?
                /* xgettext:no-c-format */ /* Time in 24h format (w/o seconds) */ _("%H∶%M") :
                /* xgettext:no-c-format */ /* Time in 12h format (w/o seconds) */ _("%l∶%M %p"));
         } else if (timespan > 1 * TimeSpan.MINUTE) {
             ulong mins = (ulong) (timespan.abs() / TimeSpan.MINUTE);
             return n("%i min ago", "%i mins ago", mins).printf(mins);
         } else {
             return _("Just now");
         }
    }

    private void show_context_menu(double x, double y) {
        var menu = new Menu();
        var action_group = new SimpleActionGroup();
        
        if (conversation.type_ == Conversation.Type.GROUPCHAT) {
            // MUC/Groupchat options
            menu.append(_("Conversation Details"), "row.details");
            menu.append(_("Invite Contact"), "row.invite");
            
            // Mute/Unmute
            bool is_muted = (conversation.notify_setting == Conversation.NotifySetting.OFF);
            menu.append(is_muted ? _("Unmute") : _("Mute"), "row.mute");
            
            menu.append(_("Delete Conversation History"), "row.clear");
            menu.append(_("Leave and Close"), "row.close");
            
            // Show "Destroy Room" only for owners
            Jid? own_muc_jid = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).get_own_jid(conversation.counterpart, conversation.account);
            if (own_muc_jid != null) {
                Xep.Muc.Affiliation? own_aff = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).get_affiliation(conversation.counterpart, own_muc_jid, conversation.account);
                if (own_aff == Xep.Muc.Affiliation.OWNER) {
                    menu.append(_("Destroy Room"), "row.destroy");
                }
            }
            
            // Details action
            var details_action = new SimpleAction("details", null);
            details_action.activate.connect(() => {
                var variant = new GLib.Variant.tuple(new GLib.Variant[] {new GLib.Variant.int32(conversation.id), new GLib.Variant.string("about")});
                GLib.Application.get_default().activate_action("open-conversation-details", variant);
            });
            action_group.add_action(details_action);
            
            // Invite action
            var invite_action = new SimpleAction("invite", null);
            invite_action.activate.connect(() => {
                show_invite_dialog();
            });
            action_group.add_action(invite_action);
            
            // Mute action
            var mute_action = new SimpleAction("mute", null);
            mute_action.activate.connect(() => {
                toggle_mute();
            });
            action_group.add_action(mute_action);
            
            // Clear history action
            var clear_action = new SimpleAction("clear", null);
            clear_action.activate.connect(() => {
                show_clear_history_dialog();
            });
            action_group.add_action(clear_action);
            
            // Close conversation action (leave MUC and close)
            var close_action = new SimpleAction("close", null);
            close_action.activate.connect(() => {
                GLib.Application.get_default().activate_action("close-conversation", new GLib.Variant.int32(conversation.id));
            });
            action_group.add_action(close_action);
            
            // Destroy room action (only added to menu for owners)
            var destroy_action = new SimpleAction("destroy", null);
            destroy_action.activate.connect(() => {
                show_destroy_room_dialog();
            });
            action_group.add_action(destroy_action);
            
        } else {
            // 1:1 Chat options
            menu.append(_("Conversation Details"), "row.details");
            menu.append(_("Edit Alias"), "row.edit");
            
            // Mute/Unmute
            bool is_muted = (conversation.notify_setting == Conversation.NotifySetting.OFF);
            menu.append(is_muted ? _("Unmute") : _("Mute"), "row.mute");
            
            // Block/Unblock
            bool is_blocked = stream_interactor.get_module<BlockingManager>(BlockingManager.IDENTITY).is_blocked(conversation.account, conversation.counterpart);
            menu.append(is_blocked ? _("Unblock") : _("Block"), "row.block");
            
            menu.append(_("Delete Conversation History"), "row.clear");
            menu.append(_("Close"), "row.close");
            menu.append(_("Remove Contact"), "row.remove");
            
            // Details action
            var details_action = new SimpleAction("details", null);
            details_action.activate.connect(() => {
                var variant = new GLib.Variant.tuple(new GLib.Variant[] {new GLib.Variant.int32(conversation.id), new GLib.Variant.string("about")});
                GLib.Application.get_default().activate_action("open-conversation-details", variant);
            });
            action_group.add_action(details_action);
            
            // Edit action
            var edit_action = new SimpleAction("edit", null);
            edit_action.activate.connect(() => {
                show_edit_dialog();
            });
            action_group.add_action(edit_action);
            
            // Mute action
            var mute_action = new SimpleAction("mute", null);
            mute_action.activate.connect(() => {
                toggle_mute();
            });
            action_group.add_action(mute_action);
            
            // Block action
            var block_action = new SimpleAction("block", null);
            block_action.activate.connect(() => {
                toggle_block();
            });
            action_group.add_action(block_action);
            
            // Close conversation action
            var close_action = new SimpleAction("close", null);
            close_action.activate.connect(() => {
                GLib.Application.get_default().activate_action("close-conversation", new GLib.Variant.int32(conversation.id));
            });
            action_group.add_action(close_action);

            // Clear history action
            var clear_action = new SimpleAction("clear", null);
            clear_action.activate.connect(() => {
                show_clear_history_dialog();
            });
            action_group.add_action(clear_action);
            
            // Remove action
            var remove_action = new SimpleAction("remove", null);
            remove_action.activate.connect(() => {
                show_remove_dialog();
            });
            action_group.add_action(remove_action);
        }
        
        this.insert_action_group("row", action_group);
        
        // Dismiss any existing popover first
        dismiss_popover();
        
        // Show popover menu
        var popover = new PopoverMenu.from_model(menu);
        active_popover = popover;
        popover.set_parent(this);
        popover.set_pointing_to({ (int)x, (int)y, 1, 1 });
        popover.closed.connect(() => {
            Idle.add(() => {
                if (active_popover == popover) {
                    popover.unparent();
                    active_popover = null;
                }
                return false;
            });
        });
        popover.popup();
    }

    private void show_edit_dialog() {
        var dialog = new Adw.AlertDialog(
            _("Edit Alias"),
            null
        );
        
        var entry = new Entry() {
            placeholder_text = _("Alias"),
            text = stream_interactor.get_module<RosterManager>(RosterManager.IDENTITY).get_roster_item(conversation.account, conversation.counterpart)?.name ?? ""
        };
        
        dialog.set_extra_child(entry);
        dialog.add_response("cancel", _("Cancel"));
        dialog.add_response("save", _("Save"));
        dialog.set_response_appearance("save", SUGGESTED);
        dialog.set_default_response("save");
        dialog.set_close_response("cancel");
        
        dialog.response.connect((response) => {
            if (response == "save") {
                string new_alias = entry.text.strip();
                if (new_alias.length > 0) {
                    stream_interactor.get_module<RosterManager>(RosterManager.IDENTITY).set_jid_handle(conversation.account, conversation.counterpart, new_alias);
                }
            }
        });
        
        dialog.present((Window)this.get_root());
    }

    private void toggle_mute() {
        bool currently_muted = (conversation.notify_setting == Conversation.NotifySetting.OFF);
        
        if (currently_muted) {
            // Unmute
            var dialog = new Adw.AlertDialog(
                _("Unmute contact?"),
                _("This will enable notifications from %s.").printf(conversation.counterpart.to_string())
            );
            dialog.add_response("cancel", _("Cancel"));
            dialog.add_response("unmute", _("Unmute"));
            dialog.set_response_appearance("unmute", SUGGESTED);
            dialog.set_default_response("unmute");
            dialog.set_close_response("cancel");
            
            dialog.response.connect((response) => {
                if (response == "unmute") {
                    conversation.notify_setting = Conversation.NotifySetting.DEFAULT;
                }
            });
            
            dialog.present((Window)this.get_root());
        } else {
            // Mute
            var dialog = new Adw.AlertDialog(
                _("Mute contact?"),
                _("This will disable notifications from %s.").printf(conversation.counterpart.to_string())
            );
            dialog.add_response("cancel", _("Cancel"));
            dialog.add_response("mute", _("Mute"));
            dialog.set_response_appearance("mute", DESTRUCTIVE);
            dialog.set_default_response("mute");
            dialog.set_close_response("cancel");
            
            dialog.response.connect((response) => {
                if (response == "mute") {
                    conversation.notify_setting = Conversation.NotifySetting.OFF;
                }
            });
            
            dialog.present((Window)this.get_root());
        }
    }

    private void toggle_block() {
        bool currently_blocked = stream_interactor.get_module<BlockingManager>(BlockingManager.IDENTITY).is_blocked(conversation.account, conversation.counterpart);
        
        if (currently_blocked) {
            // Unblock
            var dialog = new Adw.AlertDialog(
                _("Unblock contact?"),
                _("This will allow %s to send you messages again.").printf(conversation.counterpart.to_string())
            );
            dialog.add_response("cancel", _("Cancel"));
            dialog.add_response("unblock", _("Unblock"));
            dialog.set_response_appearance("unblock", SUGGESTED);
            dialog.set_default_response("unblock");
            dialog.set_close_response("cancel");
            
            dialog.response.connect((response) => {
                if (response == "unblock") {
                    stream_interactor.get_module<BlockingManager>(BlockingManager.IDENTITY).unblock(conversation.account, conversation.counterpart);
                }
            });
            
            dialog.present((Window)this.get_root());
        } else {
            // Block
            var dialog = new Adw.AlertDialog(
                _("Block contact?"),
                _("This will prevent %s from sending you messages.").printf(conversation.counterpart.to_string())
            );
            dialog.add_response("cancel", _("Cancel"));
            dialog.add_response("block", _("Block"));
            dialog.set_response_appearance("block", DESTRUCTIVE);
            dialog.set_default_response("block");
            dialog.set_close_response("cancel");
            
            dialog.response.connect((response) => {
                if (response == "block") {
                    stream_interactor.get_module<BlockingManager>(BlockingManager.IDENTITY).block(conversation.account, conversation.counterpart);
                }
            });
            
            dialog.present((Window)this.get_root());
        }
    }

    private void show_remove_dialog() {
        var dialog = new Adw.AlertDialog(
            _("Remove contact?"),
            _("This will:\n• Delete all conversation history\n• Remove %s from your contact list\n\nThis action cannot be undone.").printf(conversation.counterpart.to_string())
        );
        dialog.add_response("cancel", _("Cancel"));
        dialog.add_response("remove", _("Remove"));
        dialog.set_response_appearance("remove", DESTRUCTIVE);
        dialog.set_default_response("cancel");
        dialog.set_close_response("cancel");
        
        dialog.response.connect((response) => {
            if (response == "remove") {
                // Clear conversation history
                stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY).clear_conversation_history(conversation);
                
                // Close conversation
                stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY).close_conversation(conversation);
                
                // Remove from roster
                stream_interactor.get_module<RosterManager>(RosterManager.IDENTITY).remove_jid(conversation.account, conversation.counterpart);
            }
        });
        
        dialog.present((Window)this.get_root());
    }

    private void show_invite_dialog() {
        var accounts = new ArrayList<Account>();
        accounts.add(conversation.account);

        SelectContactDialog dialog = new SelectContactDialog(stream_interactor, accounts);
        dialog.title = _("Invite Contact");
        dialog.ok_button.label = _("Invite");
        
        var root = this.get_root() as Gtk.Window;

        dialog.selected.connect((account, jid) => {
            stream_interactor.get_module<MucManager>(MucManager.IDENTITY).invite(conversation.account, conversation.counterpart, jid);
            dialog.close();
        });
        
        dialog.present(root);
    }

    private void show_clear_history_dialog() {
        var dialog = new Adw.AlertDialog(
            _("Delete all message history?"),
            _("This will permanently delete all messages in this conversation. This action cannot be undone.")
        );

        Gtk.CheckButton? global_check = null;
        if (conversation.type_ == Conversation.Type.CHAT) {
            global_check = new Gtk.CheckButton.with_label(_("Also delete for chat partner"));
            global_check.halign = Gtk.Align.CENTER;
            dialog.set_extra_child(global_check);
        }

        dialog.add_response("cancel", _("Cancel"));
        dialog.add_response("delete", _("Delete"));
        dialog.set_response_appearance("delete", DESTRUCTIVE);
        dialog.set_default_response("cancel");
        dialog.set_close_response("cancel");
        
        dialog.response.connect((response) => {
            if (response == "delete") {
                bool global = global_check != null && global_check.active;
                stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY).clear_conversation_history(conversation, global);
            }
        });
        
        dialog.present((Window)this.get_root());
    }

    private void show_destroy_room_dialog() {
        var dialog = new Adw.AlertDialog(
            _("Destroy Room?"),
            _("Are you sure you want to permanently destroy this room? This action cannot be undone and all history will be lost for all participants.")
        );
        dialog.add_response("cancel", _("Cancel"));
        dialog.add_response("destroy", _("Destroy"));
        dialog.set_response_appearance("destroy", DESTRUCTIVE);
        dialog.set_default_response("cancel");
        dialog.set_close_response("cancel");
        
        dialog.response.connect((response) => {
            if (response == "destroy") {
                stream_interactor.get_module<MucManager>(MucManager.IDENTITY).destroy_room.begin(conversation.account, conversation.counterpart, null, (obj, res) => {
                    try {
                        stream_interactor.get_module<MucManager>(MucManager.IDENTITY).destroy_room.end(res);
                        // destroy_room now handles: bookmark removal + part + conversation close
                    } catch (GLib.Error e) {
                        var error_dialog = new Adw.AlertDialog(_("Failed to destroy room"), e.message);
                        error_dialog.add_response("close", _("Close"));
                        error_dialog.present((Window)this.get_root());
                    }
                });
            }
        });
        
        dialog.present((Window)this.get_root());
    }

    private void on_presence_changed(Jid jid, Account account) {
        if (account == conversation.account && jid.bare_jid.equals(conversation.counterpart)) {
            // For own-account conversations, the dot is managed by
            // on_own_status_changed() using the global status the user set.
            // Received presence from other resources (e.g. Monal-iOS still
            // "online") would overwrite it with incorrect data, so skip.
            foreach (Account acc in stream_interactor.get_accounts()) {
                if (acc.bare_jid.equals(conversation.counterpart)) {
                    return;
                }
            }
            update_status();
        }
    }

    /**
     * Called when the user changes their own global status.
     * If the conversation counterpart is one of the user's own accounts,
     * update the dot immediately using the new show value — bypassing
     * the Presence.Flag cache which won't be updated until the server
     * echoes the presence back.
     */
    private void on_own_status_changed(string show, string? status_msg) {
        if (conversation.type_ != Conversation.Type.CHAT) return;
        foreach (Account acc in stream_interactor.get_accounts()) {
            if (acc.bare_jid.equals(conversation.counterpart)) {
                // Counterpart is one of our own accounts — update immediately
                string emoji = "🟢";
                if (show == "away") {
                    emoji = "🟠";
                } else if (show == "dnd") {
                    emoji = "🔴";
                } else if (show == "xa") {
                    emoji = "⭕";
                }
                status_label.label = emoji;
                status_label.visible = true;
                return;
            }
        }
    }

    private void update_status() {
        if (conversation.type_ != Conversation.Type.CHAT) {
            status_label.visible = false;
            return;
        }

        Gee.List<Jid>? full_jids = stream_interactor.get_module<PresenceManager>(PresenceManager.IDENTITY).get_full_jids(conversation.counterpart, conversation.account);
        
        string? best_show = null;
        if (full_jids != null) {
            foreach (Jid full_jid in full_jids) {
                string? show = stream_interactor.get_module<PresenceManager>(PresenceManager.IDENTITY).get_last_show(full_jid, conversation.account);
                if (show == null) continue;
                
                if (best_show == null) {
                    best_show = show;
                } else {
                    if (score_show(show) > score_show(best_show)) {
                        best_show = show;
                    }
                }
            }
        }

        if (best_show != null) {
            status_label.visible = true;
            string emoji = "🟢";

            if (best_show == "away") {
                emoji = "🟠";
            } else if (best_show == "dnd") {
                emoji = "🔴";
            } else if (best_show == "xa") {
                emoji = "⭕";
            }

            status_label.label = emoji;
        } else {
            status_label.visible = false;
        }
    }

    private int score_show(string show) {
        if (show == "chat") return 5;
        if (show == "online") return 4;
        if (show == "away") return 3;
        if (show == "dnd") return 2;
        if (show == "xa") return 1;
        return 0;
    }

    private void update_private_room_indicator() {
        if (conversation.type_ != Conversation.Type.GROUPCHAT) {
            private_room_image.visible = false;
            return;
        }

        bool is_private = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).is_private_room(
            conversation.account, 
            conversation.counterpart
        );
        
        private_room_image.visible = is_private;
    }
}

}
