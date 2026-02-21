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
using Xmpp;

using Xmpp;
using Dino.Entities;
using Dino.Ui.ChatInput;

namespace Dino.Ui {
private const string OPEN_CONVERSATION_DETAILS_URI = "x-dino:open-conversation-details";

public class ChatInputController : Object {

    public signal void activate_last_message_correction();
    public signal void file_picker_selected();
    public signal void clipboard_pasted();
    public signal void voice_message_recorded(string path);
    public signal void video_message_recorded(string path);

    public new string? conversation_display_name { get; set; }
    public string? conversation_topic { get; set; }

    private Conversation? conversation;
    private bool suppress_chat_state_on_text_change = false;
    private ChatInput.View chat_input;
    private Label status_description_label;

    private StreamInteractor stream_interactor;
    private Plugins.InputFieldStatus input_field_status;
    private ChatTextViewController chat_text_view_controller;

    private ContentItem? quoted_content_item = null;
    private AudioRecorder audio_recorder;
    private VoiceRecorderPopover? recorder_popover = null;
    private bool is_recording = false;
    private VideoRecorder video_recorder;
    private VideoRecorderPopover? video_popover = null;
    private bool is_video_recording = false;

    public ChatInputController(ChatInput.View chat_input, StreamInteractor stream_interactor) {
        this.chat_input = chat_input;
        this.status_description_label = chat_input.chat_input_status;
        this.stream_interactor = stream_interactor;
        this.chat_text_view_controller = new ChatTextViewController(chat_input.chat_text_view, stream_interactor);
        this.audio_recorder = new AudioRecorder();
        this.video_recorder = new VideoRecorder();

        chat_input.init(stream_interactor);

        reset_input_field_status();

        var text_input_key_events = new EventControllerKey() { name = "dino-text-input-controller-key-events" };
        text_input_key_events.key_pressed.connect(on_text_input_key_press);
        chat_input.chat_text_view.text_view.add_controller(text_input_key_events);

        chat_input.chat_text_view.text_view.paste_clipboard.connect(() => clipboard_pasted());
        chat_input.chat_text_view.text_view.buffer.changed.connect(on_text_input_changed);

        chat_text_view_controller.send_text.connect(send_text);

        chat_input.encryption_widget.encryption_changed.connect(on_encryption_changed);

        // chat_input.file_button.clicked.connect(() => file_picker_selected());
        chat_input.record_button.clicked.connect(show_recorder_popover);
        chat_input.video_record_button.clicked.connect(show_video_recorder_popover);
        chat_input.send_button.clicked.connect(send_text);

        stream_interactor.get_module<MucManager>(MucManager.IDENTITY).received_occupant_role.connect(update_moderated_input_status);
        stream_interactor.get_module<MucManager>(MucManager.IDENTITY).room_info_updated.connect(update_moderated_input_status);

        status_description_label.activate_link.connect((uri) => {
            if (uri == OPEN_CONVERSATION_DETAILS_URI){
                var variant = new Variant.tuple(new Variant[] {new Variant.int32(conversation.id), new Variant.string("about")});
                GLib.Application.get_default().activate_action("open-conversation-details", variant);
            }
            return true;
        });

        SimpleAction quote_action = new SimpleAction("quote", new VariantType.tuple(new VariantType[]{VariantType.INT32, VariantType.INT32}));
        quote_action.activate.connect((variant) => {
            int conversation_id = variant.get_child_value(0).get_int32();
            Conversation? conversation = stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY).get_conversation_by_id(conversation_id);
            if (conversation == null || !this.conversation.equals(conversation)) return;

            int content_item_id = variant.get_child_value(1).get_int32();
            ContentItem? content_item = stream_interactor.get_module<ContentItemStore>(ContentItemStore.IDENTITY).get_item_by_id(conversation, content_item_id);
            if (content_item == null) return;

            quoted_content_item = content_item;
            var quote_model = new Quote.Model.from_content_item(content_item, conversation, stream_interactor) { can_abort = true };
            quote_model.aborted.connect(() => {
                quoted_content_item = null;
                chat_input.unset_quoted_message();
            });
            chat_input.set_quoted_message(Quote.get_widget(quote_model));
        });
        GLib.Application.get_default().add_action(quote_action);
    }

    public void set_conversation(Conversation conversation) {
        debug("ChatInputController.set_conversation: Called with %s", conversation != null ? conversation.counterpart.to_string() : "NULL");
        int64 t0_us = Dino.Ui.UiTiming.now_us();
        suppress_chat_state_on_text_change = true;
        reset_input_field_status();
        this.quoted_content_item = null;
        chat_input.unset_quoted_message();

        this.conversation = conversation;

        int64 t_enc_us = Dino.Ui.UiTiming.now_us();
        debug("ChatInputController.set_conversation: About to call encryption_widget.set_conversation");
        chat_input.encryption_widget.set_conversation(conversation);
        Dino.Ui.UiTiming.log_ms("ChatInputController.set_conversation: encryption_widget.set_conversation", t_enc_us);

        int64 t_view_us = Dino.Ui.UiTiming.now_us();
        chat_input.initialize_for_conversation(conversation);
        Dino.Ui.UiTiming.log_ms("ChatInputController.set_conversation: chat_input.initialize_for_conversation", t_view_us);

        int64 t_text_us = Dino.Ui.UiTiming.now_us();
        chat_text_view_controller.initialize_for_conversation(conversation);
        Dino.Ui.UiTiming.log_ms("ChatInputController.set_conversation: chat_text_view_controller.initialize_for_conversation", t_text_us);

        int64 t_mod_us = Dino.Ui.UiTiming.now_us();
        update_moderated_input_status(conversation.account);
        Dino.Ui.UiTiming.log_ms("ChatInputController.set_conversation: update_moderated_input_status", t_mod_us);

        suppress_chat_state_on_text_change = false;

        Dino.Ui.UiTiming.log_ms("ChatInputController.set_conversation: total", t0_us);
    }

    public void set_file_upload_active(bool active) {
        chat_input.set_file_upload_active(active);
    }

    private void on_encryption_changed(Encryption encryption) {
        debug("ChatInputController: on_encryption_changed called with %d", (int)encryption);
        reset_input_field_status();

        if (encryption == Encryption.NONE) {
            debug("ChatInputController: encryption is NONE, returning");
            return;
        }

        Application app = GLib.Application.get_default() as Application;
        debug("ChatInputController: Looking for encryption_entry for %d, registry has %d entries", 
              (int)encryption, app.plugin_registry.encryption_list_entries.size);
        var encryption_entry = app.plugin_registry.encryption_list_entries[encryption];
        if (encryption_entry != null) {
            debug("ChatInputController: Found encryption_entry '%s', calling encryption_activated", encryption_entry.name);
            encryption_entry.encryption_activated(conversation, set_input_field_status);
        } else {
            debug("ChatInputController: encryption_entry is NULL for %d!", (int)encryption);
        }
    }

    private void set_input_field_status(Plugins.InputFieldStatus? status) {
        input_field_status = status;

        chat_input.set_input_state(status.message_type);

        status_description_label.use_markup = status.contains_markup;

        status_description_label.label = status.message;

        chat_input.file_button.sensitive = status.input_state == Plugins.InputFieldStatus.InputState.NORMAL;
    }

    private void reset_input_field_status() {
        set_input_field_status(new Plugins.InputFieldStatus("", Plugins.InputFieldStatus.MessageType.NONE, Plugins.InputFieldStatus.InputState.NORMAL));
    }

    private void send_text() {
        // Don't do anything if we're in a NO_SEND state. Don't clear the chat input, don't send.
        if (input_field_status.input_state == Plugins.InputFieldStatus.InputState.NO_SEND) {
            chat_input.highlight_state_description();
            return;
        }

        string text = chat_input.chat_text_view.text_view.buffer.text;
        if (text.strip() == "") return;

        ContentItem? quoted_content_item_bak = quoted_content_item;
        var markups = chat_input.chat_text_view.get_markups();

        // Reset input state. Has do be done before parsing commands, because those directly return.
        chat_input.chat_text_view.text_view.buffer.text = "";
        chat_input.unset_quoted_message();
        quoted_content_item = null;

        if (text.has_prefix("/")) {
            string[] token = text.split(" ", 2);
            switch(token[0]) {
                case "/me":
                    // Just send as is.
                    break;
                case "/say":
                    if (token.length == 1) return;
                    text = token[1];
                    break;
                case "/kick":
                    stream_interactor.get_module<MucManager>(MucManager.IDENTITY).kick(conversation.account, conversation.counterpart, token[1]);
                    return;
                case "/affiliate":
                    if (token.length > 1) {
                        string[] user_role = token[1].split(" ");
                        if (user_role.length >= 2) {
                            string nick = string.joinv(" ", user_role[0:user_role.length - 1]).strip();
                            string role = user_role[user_role.length - 1].strip();
                            stream_interactor.get_module<MucManager>(MucManager.IDENTITY).change_affiliation(conversation.account, conversation.counterpart, nick, role);
                        }
                    }
                    return;
                case "/nick":
                    stream_interactor.get_module<MucManager>(MucManager.IDENTITY).change_nick.begin(conversation, token[1]);
                    return;
                case "/ping":
                    Xmpp.XmppStream? stream = stream_interactor.get_stream(conversation.account);
                    try {
                        stream.get_module<Xmpp.Xep.Ping.Module>(Xmpp.Xep.Ping.Module.IDENTITY).send_ping.begin(stream, conversation.counterpart.with_resource(token[1]));
                    } catch (Xmpp.InvalidJidError e) {
                        warning("Could not ping invalid Jid: %s", e.message);
                    }
                    return;
                case "/topic":
                    stream_interactor.get_module<MucManager>(MucManager.IDENTITY).change_subject(conversation.account, conversation.counterpart, token[1]);
                    return;
                default:
                    if (token[0].has_prefix("//")) {
                        text = text.substring(1);
                    } else {
                        string cmd_name = token[0].substring(1);
                        Dino.Application app = GLib.Application.get_default() as Dino.Application;
                        if (app != null && app.plugin_registry.text_commands.has_key(cmd_name)) {
                            string? new_text = app.plugin_registry.text_commands[cmd_name].handle_command(token[1], conversation);
                            if (new_text == null) return;
                            text = (!)new_text;
                        }
                    }
                    break;
            }
        }

        Dino.send_message(conversation, text, quoted_content_item_bak != null ? quoted_content_item_bak.id : 0, null, markups);
    }

    private void on_text_input_changed() {
        bool has_text = chat_input.chat_text_view.text_view.buffer.text.strip() != "";
        chat_input.send_button.sensitive = has_text;

        if (suppress_chat_state_on_text_change || conversation == null) {
            return;
        }
        
        if (has_text) {
            stream_interactor.get_module<ChatInteraction>(ChatInteraction.IDENTITY).on_message_entered(conversation);
        } else {
            stream_interactor.get_module<ChatInteraction>(ChatInteraction.IDENTITY).on_message_cleared(conversation);
        }
    }

    private void update_moderated_input_status(Account account, Xmpp.Jid? jid = null) {
        if (conversation != null && conversation.type_ == Conversation.Type.GROUPCHAT){
            Xmpp.Jid? own_jid = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).get_own_jid(conversation.counterpart, conversation.account);
            if (own_jid == null) {
                // Check if we are banned or kicked (not joined)
                // If we are not joined, we might want to show a "Join" button or similar status
                // For now, just disable input if we are not joined?
                // Actually, if own_jid is null, we are not in the room.
                // But we might want to allow typing if we can rejoin?
                // Let's check if we are banned.
                return;
            }
            if (stream_interactor.get_module<MucManager>(MucManager.IDENTITY).is_moderated_room(conversation.account, conversation.counterpart) &&
                    stream_interactor.get_module<MucManager>(MucManager.IDENTITY).get_role(own_jid, conversation.account) == Xmpp.Xep.Muc.Role.VISITOR) {
                string msg_str = _("This conference does not allow you to send messages.") + " <a href=\"" + OPEN_CONVERSATION_DETAILS_URI + "\">" + _("Request permission") + "</a>";
                set_input_field_status(new Plugins.InputFieldStatus(msg_str, Plugins.InputFieldStatus.MessageType.ERROR, Plugins.InputFieldStatus.InputState.NO_SEND, true));
            } else {
                reset_input_field_status();
            }
        }
    }

    private bool on_text_input_key_press(uint keyval, uint keycode, Gdk.ModifierType state) {
        if (keyval == Gdk.Key.Up && chat_input.chat_text_view.text_view.buffer.text == "") {
            activate_last_message_correction();
            return true;
        } else {
            chat_input.do_focus();
        }
        return false;
    }

    private void show_recorder_popover() {
        if (recorder_popover == null) {
            recorder_popover = new VoiceRecorderPopover(audio_recorder);
            recorder_popover.set_parent(chat_input.record_button);
            
            recorder_popover.send_clicked.connect(() => {
                if (is_recording) {
                    is_recording = false;
                    stop_recording();
                }
                recorder_popover.popdown();
            });
            
            recorder_popover.cancel_clicked.connect(() => {
                if (is_recording) {
                    is_recording = false;
                    cancel_recording();
                }
                recorder_popover.popdown();
            });
            
            recorder_popover.closed.connect(() => {
                if (is_recording) {
                    is_recording = false;
                    cancel_recording();
                }
            });
        }
        
        recorder_popover.popup();
        start_recording();
    }

    private void start_recording() {
        try {
            string path = Path.build_filename(Environment.get_tmp_dir(), "dino_voice_%s.m4a".printf(new DateTime.now_local().format("%Y%m%d%H%M%S")));
            debug("ChatInputController.start_recording: path=%s", path);
            audio_recorder.start_recording(path);
            is_recording = true;
            chat_input.record_button.icon_name = "media-record-symbolic";
            chat_input.record_button.add_css_class("destructive-action");
        } catch (Error e) {
            warning("Failed to start recording: %s", e.message);
        }
    }

    private void stop_recording() {
        debug("ChatInputController.stop_recording: called");
        audio_recorder.stop_recording();
        debug("ChatInputController.stop_recording: pipeline closed");
        
        chat_input.record_button.icon_name = "microphone-sensitivity-medium-symbolic";
        chat_input.record_button.remove_css_class("destructive-action");

        if (audio_recorder.current_output_path != null) {
            File f = File.new_for_path(audio_recorder.current_output_path);
            try {
                FileInfo info = f.query_info(FileAttribute.STANDARD_SIZE, FileQueryInfoFlags.NONE);
                debug("ChatInputController.stop_recording: file size=%lld", info.get_size());
                if (info.get_size() > 0) {
                    debug("ChatInputController.stop_recording: emitting voice_message_recorded");
                    voice_message_recorded(audio_recorder.current_output_path);
                } else {
                    warning("Recorded audio file is empty, not sending.");
                    FileUtils.unlink(audio_recorder.current_output_path);
                }
            } catch (Error e) {
                debug("ChatInputController.stop_recording: Error checking file: %s", e.message);
                warning("Failed to check recorded audio file: %s", e.message);
            }
        }
    }
    
    private void cancel_recording() {
        audio_recorder.cancel_recording();
        
        chat_input.record_button.icon_name = "microphone-sensitivity-medium-symbolic";
        chat_input.record_button.remove_css_class("destructive-action");
    }

    // === Video Recording ===

    private void show_video_recorder_popover() {
        if (video_popover == null) {
            video_popover = new VideoRecorderPopover(video_recorder);
            video_popover.set_parent(chat_input.video_record_button);

            video_popover.send_clicked.connect(() => {
                if (is_video_recording) {
                    is_video_recording = false;
                    stop_video_recording();
                }
                video_popover.popdown();
            });

            video_popover.cancel_clicked.connect(() => {
                if (is_video_recording) {
                    is_video_recording = false;
                    cancel_video_recording();
                }
                video_popover.popdown();
            });

            video_popover.closed.connect(() => {
                if (is_video_recording) {
                    is_video_recording = false;
                    cancel_video_recording();
                }
                // Destroy popover so preview poll restarts fresh next time
                video_popover.unparent();
                video_popover = null;
            });
        }

        video_popover.popup();
        start_video_recording();
    }

    private void start_video_recording() {
        try {
            string path = Path.build_filename(Environment.get_tmp_dir(),
                "dino_video_%s.mp4".printf(new DateTime.now_local().format("%Y%m%d%H%M%S")));
            debug("ChatInputController.start_video_recording: path=%s", path);
            video_recorder.start_recording(path);
            is_video_recording = true;
            chat_input.video_record_button.icon_name = "media-record-symbolic";
            chat_input.video_record_button.add_css_class("destructive-action");
        } catch (Error e) {
            warning("Failed to start video recording: %s", e.message);
        }
    }

    private void stop_video_recording() {
        debug("ChatInputController.stop_video_recording: called");
        string? path = video_recorder.current_output_path;
        video_recorder.stop_recording();
        debug("ChatInputController.stop_video_recording: pipeline closed");

        chat_input.video_record_button.icon_name = "camera-video-symbolic";
        chat_input.video_record_button.remove_css_class("destructive-action");

        if (path != null) {
            File f = File.new_for_path(path);
            try {
                FileInfo info = f.query_info(FileAttribute.STANDARD_SIZE, FileQueryInfoFlags.NONE);
                debug("ChatInputController.stop_video_recording: file size=%lld", info.get_size());
                if (info.get_size() > 0) {
                    debug("ChatInputController.stop_video_recording: emitting video_message_recorded");
                    video_message_recorded(path);
                } else {
                    warning("Recorded video file is empty, not sending.");
                    FileUtils.unlink(path);
                }
            } catch (Error e) {
                warning("Failed to check recorded video file: %s", e.message);
            }
        }
    }

    private void cancel_video_recording() {
        video_recorder.cancel_recording();
        chat_input.video_record_button.icon_name = "camera-video-symbolic";
        chat_input.video_record_button.remove_css_class("destructive-action");
    }
}

}
