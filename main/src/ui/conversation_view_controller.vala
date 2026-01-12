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

using Dino.Entities;

namespace Dino.Ui {

public class ConversationViewController : Object {

    private Application app;
    private MainWindow main_window;
    private ConversationView view;
    public SearchMenuEntry search_menu_entry = new SearchMenuEntry();
    public ListView list_view = new ListView(null, null);
    private DropTarget drop_event_controller = new DropTarget(typeof(File), DragAction.COPY );

    private ChatInputController chat_input_controller;
    private StreamInteractor stream_interactor;
    private Conversation? conversation;

    private Binding? display_name_binding = null;

    private const string[] KEY_COMBINATION_CLOSE_CONVERSATION = {"<Ctrl>W", null};

    public ConversationViewController(MainWindow main_window, ConversationView view, StreamInteractor stream_interactor) {
        this.main_window = main_window;
        this.view = view;
        this.stream_interactor = stream_interactor;
        this.app = GLib.Application.get_default() as Application;

        this.chat_input_controller = new ChatInputController(view.chat_input, stream_interactor);
        chat_input_controller.activate_last_message_correction.connect(view.conversation_frame.activate_last_message_correction);
        chat_input_controller.file_picker_selected.connect(open_file_picker);
        chat_input_controller.clipboard_pasted.connect(on_clipboard_paste);
        chat_input_controller.voice_message_recorded.connect((path) => {
            // The audio recorder saves to a temp file.
            // FileManager.send_file will encrypt it to local storage and then upload it.
            // We just need to make sure we pass the file object.
            send_file(File.new_for_path(path));
        });

        view.chat_input.send_file_button.clicked.connect(() => {
            view.chat_input.attachment_popover.popdown();
            open_file_picker();
        });
        view.chat_input.send_location_button.clicked.connect(() => {
            view.chat_input.attachment_popover.popdown();
            send_location();
        });

        view.conversation_frame.init(stream_interactor);

        // drag 'n drop file upload
        drop_event_controller.drop.connect(this.on_drag_data_received);

        // forward key presses
        var key_controller = new EventControllerKey() { name = "dino-forward-to-input-key-events-1" };
        key_controller.key_pressed.connect(forward_key_press_to_chat_input);
        view.conversation_frame.add_controller(key_controller);

        var key_controller2 = new EventControllerKey() { name = "dino-forward-to-input-key-events-2" };
        key_controller2.key_pressed.connect(forward_key_press_to_chat_input);
        view.chat_input.add_controller(key_controller2);

        var key_controller3 = new EventControllerKey() { name = "dino-forward-to-input-key-events-3" };
        key_controller3.key_pressed.connect(forward_key_press_to_chat_input);
        main_window.conversation_headerbar.add_controller(key_controller3);

        var title_click_controller = new GestureClick();
        title_click_controller.pressed.connect((n_press, x, y) => {
            if (this.conversation != null) {
                var conversation_details = ConversationDetails.setup_dialog(this.conversation, this.stream_interactor);
                conversation_details.present(main_window);
            }
        });
        main_window.conversation_window_title.add_controller(title_click_controller);

//      goto-end floating button
        var vadjustment = view.conversation_frame.scrolled.vadjustment;
        vadjustment.notify["value"].connect(() => {
            bool button_active = vadjustment.value <  vadjustment.upper - vadjustment.page_size;
            view.goto_end_revealer.reveal_child = button_active;
            view.goto_end_revealer.visible = button_active;
        });
        view.goto_end_button.clicked.connect(() => {
            view.conversation_frame.initialize_for_conversation(conversation);
        });

        // Update conversation topic
        stream_interactor.get_module<MucManager>(MucManager.IDENTITY).subject_set.connect((account, jid, subject) => {
            if (conversation != null && conversation.counterpart.equals_bare(jid) && conversation.account.equals(account)) {
                update_conversation_topic(subject);
            }
        });

        stream_interactor.get_module<FileManager>(FileManager.IDENTITY).upload_available.connect(update_file_upload_status);
        
        // Listen for conversation history cleared signal
        stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY).conversation_cleared.connect((cleared_conversation) => {
            if (this.conversation != null && this.conversation.id == cleared_conversation.id) {
                // Force reload the conversation view to show empty chat
                view.conversation_frame.initialize_for_conversation(this.conversation, true);
            }
        });

        // Headerbar plugins
        app.plugin_registry.register_contact_titlebar_entry(new MenuEntry(stream_interactor));
        app.plugin_registry.register_contact_titlebar_entry(search_menu_entry);
        app.plugin_registry.register_contact_titlebar_entry(new OccupantsEntry(stream_interactor));
        app.plugin_registry.register_contact_titlebar_entry(new CallTitlebarEntry(stream_interactor));
        foreach(var entry in app.plugin_registry.conversation_titlebar_entries) {
            Widget? button = entry.get_widget(Plugins.WidgetType.GTK4) as Widget;
            if (button == null) {
                continue;
            }
            main_window.conversation_headerbar.pack_end(button);
        }

        Shortcut shortcut = new Shortcut(new KeyvalTrigger(Key.U, ModifierType.CONTROL_MASK), new CallbackAction(() => {
            if (conversation == null) return false;
            stream_interactor.get_module<FileManager>(FileManager.IDENTITY).is_upload_available.begin(conversation, (_, res) => {
                if (stream_interactor.get_module<FileManager>(FileManager.IDENTITY).is_upload_available.end(res)) {
                    open_file_picker();
                }
            });
            return false;
        }));
        ((Gtk.Window)view.get_root()).add_shortcut(shortcut);

        SimpleAction close_conversation_action = new SimpleAction("close-current-conversation", null);
        close_conversation_action.activate.connect(() => {
            stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY).close_conversation(conversation);
        });
        app.add_action(close_conversation_action);
        app.set_accels_for_action("app.close-current-conversation", KEY_COMBINATION_CLOSE_CONVERSATION);
    }

    public void select_conversation(Conversation? conversation, bool default_initialize_conversation) {
        int64 t0_us = Dino.Ui.UiTiming.now_us();
        if (this.conversation != null) {
            conversation.notify["encryption"].disconnect(update_file_upload_status);
        }

        this.conversation = conversation;

        // Set list model onto list view
//        Dino.Application app = GLib.Application.get_default() as Dino.Application;
//        var map_list_model = get_conversation_content_model(new ContentItemMetaModel(app.db, conversation, stream_interactor), stream_interactor);
//        NoSelection selection_model = new NoSelection(map_list_model);
//        view.list_view.set_model(selection_model);
//        view.at_current_content = true;

        conversation.notify["encryption"].connect(update_file_upload_status);

        int64 t_input_us = Dino.Ui.UiTiming.now_us();
        chat_input_controller.set_conversation(conversation);
        Dino.Ui.UiTiming.log_ms("ConversationViewController.select_conversation: chat_input_controller.set_conversation", t_input_us);

        if (display_name_binding != null) display_name_binding.unbind();
        int64 t_title_us = Dino.Ui.UiTiming.now_us();
        var display_name_model = stream_interactor.get_module<ContactModels>(ContactModels.IDENTITY).get_display_name_model(conversation);
        display_name_binding = display_name_model.bind_property("display-name", main_window.conversation_window_title, "title", BindingFlags.SYNC_CREATE);
        Dino.Ui.UiTiming.log_ms("ConversationViewController.select_conversation: display_name_model+bind", t_title_us);

        int64 t_topic_us = Dino.Ui.UiTiming.now_us();
        update_conversation_topic();
        Dino.Ui.UiTiming.log_ms("ConversationViewController.select_conversation: update_conversation_topic", t_topic_us);

        int64 t_plugins_us = Dino.Ui.UiTiming.now_us();
        foreach(Plugins.ConversationTitlebarEntry e in this.app.plugin_registry.conversation_titlebar_entries) {
            e.set_conversation(conversation);
        }
        Dino.Ui.UiTiming.log_ms("ConversationViewController.select_conversation: titlebar_entries.set_conversation", t_plugins_us);

        if (default_initialize_conversation) {
            int64 t_view_us = Dino.Ui.UiTiming.now_us();
            view.conversation_frame.initialize_for_conversation(conversation);
            Dino.Ui.UiTiming.log_ms("ConversationViewController.select_conversation: conversation_frame.initialize_for_conversation", t_view_us);
        }

        update_file_upload_status.begin();

        Dino.Ui.UiTiming.log_ms("ConversationViewController.select_conversation: total", t0_us);
    }

    public void unset_conversation() {
        main_window.conversation_window_title.title = null;
        main_window.conversation_window_title.subtitle = null;
    }

    private async void update_file_upload_status() {
        if (conversation == null) return;

        bool upload_available = yield stream_interactor.get_module<FileManager>(FileManager.IDENTITY).is_upload_available(conversation);
        chat_input_controller.set_file_upload_active(upload_available);

        if (upload_available) {
            if (drop_event_controller.widget == null) {
                view.add_controller(drop_event_controller);
            }
        } else {
            if (drop_event_controller.widget != null) {
                view.remove_controller(drop_event_controller);
            }
        }
    }

    private void update_conversation_topic(string? subtitle = null) {
        string? str = null;
        if (subtitle != null) {
            str = Util.summarize_whitespaces_to_space(subtitle);
        } else if (conversation.type_ == Conversation.Type.GROUPCHAT) {
            string? subject = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).get_groupchat_subject(conversation.counterpart, conversation.account);
            if (subject != null) {
                str = Util.summarize_whitespaces_to_space(subject);
            }
        }

        main_window.conversation_window_title.subtitle = str;
    }

    private async void on_clipboard_paste() {
        try {
            Clipboard clipboard = view.get_clipboard();
            Gdk.Texture? texture = yield clipboard.read_texture_async(null); // TODO critical
            if (texture != null) {
                var file_name = Path.build_filename(FileManager.get_storage_dir(), Xmpp.random_uuid() + ".png");
                texture.save_to_png(file_name);
                open_send_file_overlay(File.new_for_path(file_name));
            }
        } catch (IOError.NOT_SUPPORTED e) {
            // Format not supported, ignore
        } catch (Error e) {
            warning("Failed to read texture from clipboard: %s", e.message);
        }
    }

    private bool on_drag_data_received(DropTarget target, Value val, double x, double y) {
        if (val.type() == typeof(File)) {
            open_send_file_overlay((File)val);
            return true;
        }
        return false;
    }

    private void open_file_picker() {
        debug("ConversationViewController: open_file_picker called");
        var chooser = new Gtk.FileDialog();
        chooser.title = _("Select file");
        chooser.accept_label = _("Select");

        chooser.open.begin(view.get_root() as Gtk.Window, null, (obj, res) => {
            try {
                File file = chooser.open.end(res);
                debug("ConversationViewController: File selected: %s", file.get_path());
                open_send_file_overlay(file);
            } catch (Error e) {
                warning("ConversationViewController: File picker error: %s", e.message);
            }
        });
    }

    private void open_send_file_overlay(File file) {
        debug("ConversationViewController: open_send_file_overlay called for %s", file.get_path());
        FileInfo file_info;
        try {
            file_info = file.query_info("*", FileQueryInfoFlags.NONE);
        } catch (Error e) {
            warning("Failed querying info for file %s", file.get_path());
            return;
        }

        FileSendOverlay file_send_overlay = new FileSendOverlay(file, file_info);
        file_send_overlay.send_file.connect(send_file);

        stream_interactor.get_module<FileManager>(FileManager.IDENTITY).get_file_size_limits.begin(conversation, (_, res) => {
            HashMap<int, long> limits = stream_interactor.get_module<FileManager>(FileManager.IDENTITY).get_file_size_limits.end(res);
            bool something_works = false;
            foreach (var limit in limits.values) {
                if (limit >= file_info.get_size()) {
                    something_works = true;
                }
            }
            if (!something_works && limits.has_key(0)) {
                if (!something_works && file_info.get_size() > limits[0] && file_send_overlay != null) {
                    file_send_overlay.set_file_too_large();
                }
            }
        });

        file_send_overlay.closed.connect(() => {
            // We don't want drag'n'drop to be active while the overlay is active
            update_file_upload_status.begin();
        });

        file_send_overlay.present(view);
        debug("ConversationViewController: file_send_overlay presented");

        update_file_upload_status.begin();
    }

    private void send_file(File file) {
        debug("ConversationViewController: send_file called for %s", file.get_path());
        stream_interactor.get_module<FileManager>(FileManager.IDENTITY).send_file.begin(file, conversation);
    }

    private bool forward_key_press_to_chat_input(EventControllerKey key_controller, uint keyval, uint keycode, Gdk.ModifierType state) {
        if (view.get_root().get_focus() is TextView) {
            return false;
        }

        // Don't forward / change focus on Control / Alt
        if (keyval == Gdk.Key.Control_L || keyval == Gdk.Key.Control_R ||
                keyval == Gdk.Key.Alt_L || keyval == Gdk.Key.Alt_R) {
            return false;
        }
        // Don't forward / change focus on Control + ...
        if ((state & ModifierType.CONTROL_MASK) > 0) {
            return false;
        }

        return key_controller.forward(view.chat_input.chat_text_view.text_view);
    }

    private void send_location() {
        debug("ConversationViewController: send_location called");
        LocationManager.get_default().get_location.begin(null, (obj, res) => {
            try {
                double lat, lon, accuracy;
                LocationManager.get_default().get_location.end(res, out lat, out lon, out accuracy);
                debug("ConversationViewController: Location retrieved successfully");
                send_location_message(lat, lon, accuracy);
            } catch (Error e) {
                warning("ConversationViewController: Failed to get location: %s", e.message);
                var dialog = new Adw.MessageDialog(main_window, _("Failed to get location"), e.message);
                dialog.add_response("close", _("Close"));
                dialog.present();
            }
        });
    }

    private void send_location_message(double lat, double lon, double accuracy) {
        debug("ConversationViewController: Sending location message: %f, %f", lat, lon);
        if (conversation == null) {
            warning("ConversationViewController: Conversation is null!");
            return;
        }
        
        string lat_str = "%.6f".printf(lat).replace(",", ".");
        string lon_str = "%.6f".printf(lon).replace(",", ".");
        string body = "geo:%s,%s".printf(lat_str, lon_str);
        
        // Use MessageProcessor to create the message. This ensures it's saved to the DB and has correct IDs/timestamps.
        Entities.Message message = stream_interactor.get_module<MessageProcessor>(MessageProcessor.IDENTITY).create_out_message(body, conversation);
        
        var user_loc = new Xmpp.Xep.UserLocation.UserLocation.create();
        user_loc.lat = lat;
        user_loc.lon = lon;
        user_loc.accuracy = accuracy;
        
        ulong signal_id = 0;
        signal_id = stream_interactor.get_module<MessageProcessor>(MessageProcessor.IDENTITY).pre_message_send.connect((msg, stanza, conv) => {
            if (msg == message) {
                stanza.stanza.put_node(user_loc.node);
                debug("ConversationViewController: Injected location node: %s", user_loc.node.to_string());
                stream_interactor.get_module<MessageProcessor>(MessageProcessor.IDENTITY).disconnect(signal_id);
            }
        });
        
        stream_interactor.get_module<ContentItemStore>(ContentItemStore.IDENTITY).insert_message(message, conversation);
        stream_interactor.get_module<MessageProcessor>(MessageProcessor.IDENTITY).send_xmpp_message(message, conversation);
        stream_interactor.get_module<MessageProcessor>(MessageProcessor.IDENTITY).message_sent(message, conversation);
        debug("ConversationViewController: send_xmpp_message called");
    }
}
}
