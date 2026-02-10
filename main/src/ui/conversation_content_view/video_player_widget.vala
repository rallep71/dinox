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
using Graphene;
using Gst;
using Xmpp;

using Dino.Entities;
using Dino.Security;

namespace Dino.Ui.ConversationSummary {

public class VideoFileMetaItem : FileMetaItem {
    private StreamInteractor stream_interactor_ref;
    private FileItem file_item_ref;
    
    public VideoFileMetaItem(ContentItem content_item, StreamInteractor stream_interactor) {
        base(content_item, stream_interactor);
        this.stream_interactor_ref = stream_interactor;
        this.file_item_ref = content_item as FileItem;
        
        // Auto-download video files if not yet downloaded
        if (file_transfer.direction == FileTransfer.DIRECTION_RECEIVED && 
            file_transfer.state == FileTransfer.State.NOT_STARTED) {
            stream_interactor.get_module<FileManager>(FileManager.IDENTITY).download_file.begin(file_transfer);
        }
    }

    public override GLib.Object? get_widget(Plugins.ConversationItemWidgetInterface outer, Plugins.WidgetType type) {
        return new VideoPlayerWidget(file_transfer);
    }

    // Override to provide message actions (Reply, Reaction, Delete)
    // but exclude Open/Save as those are in the video's overlay menu
    public override Gee.List<Plugins.MessageAction>? get_item_actions(Plugins.WidgetType type) {
        if (file_transfer.provider != FileManager.HTTP_PROVIDER_ID && file_transfer.provider != FileManager.SFS_PROVIDER_ID) return null;

        Gee.List<Plugins.MessageAction> actions = new ArrayList<Plugins.MessageAction>();

        actions.add(get_reply_action(content_item, file_item_ref.conversation, stream_interactor_ref));
        actions.add(get_reaction_action(content_item, file_item_ref.conversation, stream_interactor_ref));

        var delete_action = get_delete_action(content_item, file_item_ref.conversation, stream_interactor_ref);
        if (delete_action != null) actions.add(delete_action);

        return actions;
    }
}

public class VideoPlayerWidget : Widget {
    enum State {
        EMPTY,
        PREVIEW,
        VIDEO
    }
    private State state = State.EMPTY;

    private Stack stack = new Stack() { transition_duration=600, transition_type=StackTransitionType.CROSSFADE, hhomogeneous=true, vhomogeneous=true, interpolate_size=false };
    private Overlay overlay = new Overlay();

    private bool show_overlay_toolbar = false;
    private Gtk.Box overlay_toolbar = new Gtk.Box(Orientation.VERTICAL, 0) { halign=Align.START, valign=Align.START, margin_top=10, margin_start=10, margin_end=10, margin_bottom=10, vexpand=false, visible=false };
    private Label file_size_label = new Label(null) { halign=Align.START, valign=Align.END, margin_bottom=4, margin_start=4, visible=false };

    private FileTransfer? file_transfer;
    private Binding? ft_state_binding = null;
    private Binding? ft_size_binding1 = null;
    private Binding? ft_size_binding2 = null;
    private Binding? ft_bytes_binding = null;
    private Gtk.Picture? video_picture = null;
    private Gtk.MediaFile? media_file = null;
    private Gtk.Widget? video_container = null;
    private FixedRatioPicture? preview_image = null;

    private Gtk.ScrolledWindow? watched_scrolled = null;
    private Gtk.Adjustment? watched_vadjustment = null;
    private ulong watched_vadjustment_handler_id = 0;
    private bool paused_by_visibility = false;
    private bool preview_initialized = false;
    private bool preview_generating = false;

    private Button? start_play_button = null;

    private FileTransmissionProgress transmission_progress = new FileTransmissionProgress() { halign=Align.CENTER, valign=Align.CENTER, visible=false };

    construct {
        layout_manager = new BinLayout();
    }

    public VideoPlayerWidget(FileTransfer file_transfer) {
        debug("VideoPlayerWidget: init");
        this.halign = Align.START;
        this.valign = Align.START;
        this.hexpand = false;
        this.vexpand = false;
        this.set_size_request(320, 180);
        this.add_css_class("video-player-widget");

        this.file_transfer = file_transfer;

        start_play_button = new Button.from_icon_name("media-playback-start-symbolic");
        start_play_button.add_css_class("osd");
        start_play_button.add_css_class("circular");
        start_play_button.valign = Align.CENTER;
        start_play_button.halign = Align.CENTER;
        start_play_button.width_request = 64;
        start_play_button.height_request = 64;
        start_play_button.visible = false;
        start_play_button.clicked.connect(() => {
            File? file = file_transfer.get_file();
            if (file != null) {
                start_play_button.visible = false;
                setup_pipeline.begin(file);
            }
        });
        overlay.add_overlay(start_play_button);

        this.notify["mapped"].connect(() => {
            if (!this.get_mapped()) {
                pause_for_visibility();
                disconnect_scroll_watch();
            } else {
                update_playback_visibility();
                // Lazy init: generate preview only when widget becomes visible
                try_lazy_preview_init();
            }
        });
        
        install_action("file.open", null, (widget, action_name) => { ((VideoPlayerWidget) widget).open_file.begin(); });
        install_action("file.save_as", null, (widget, action_name) => { ((VideoPlayerWidget) widget).save_file(); });

        // Setup menu button overlay
        MenuButton button = new MenuButton();
        button.icon_name = "view-more-symbolic";
        Menu menu_model = new Menu();
        menu_model.append(_("Open"), "file.open");
        menu_model.append(_("Save as…"), "file.save_as");
        Gtk.PopoverMenu popover_menu = new Gtk.PopoverMenu.from_model(menu_model);
        button.popover = popover_menu;
        overlay_toolbar.append(button);
        overlay_toolbar.add_css_class("card");
        overlay_toolbar.add_css_class("toolbar");
        overlay_toolbar.add_css_class("compact-card-toolbar");
        overlay_toolbar.set_cursor_from_name("default");

        file_size_label.add_css_class("file-details");

        overlay.set_child(stack);
        overlay.set_measure_overlay(stack, true);
        overlay.add_overlay(file_size_label);
        overlay.add_overlay(transmission_progress);
        overlay.add_overlay(overlay_toolbar);
        overlay.set_clip_overlay(overlay_toolbar, true);

        overlay.insert_after(this, null);

        EventControllerMotion this_motion_events = new EventControllerMotion();
        this.add_controller(this_motion_events);
        this_motion_events.enter.connect((controller, x, y) => {
            var widget = controller.widget as VideoPlayerWidget;
            if (widget != null) {
                widget.on_motion_event_enter();
            }
        });
        attach_on_motion_event_leave(this_motion_events, button);
        
        // Note: Click to play/pause is handled by Gtk.MediaControls
        // which is added when the video loads

        update_widget.begin();

        ft_state_binding = file_transfer.bind_property("state", this, "file-transfer-state");
        this.notify["file-transfer-state"].connect(update_widget);
        
        ft_size_binding1 = this.file_transfer.bind_property("size", file_size_label, "label", BindingFlags.SYNC_CREATE, file_size_label_transform);
        ft_size_binding2 = this.file_transfer.bind_property("size", transmission_progress, "file-size", BindingFlags.SYNC_CREATE);
        ft_bytes_binding = this.file_transfer.bind_property("transferred-bytes", transmission_progress, "transferred-size", BindingFlags.SYNC_CREATE);
    }

    public FileTransfer.State file_transfer_state { get; set; }

    ~VideoPlayerWidget() {
    }

    private static void attach_on_motion_event_leave(EventControllerMotion this_motion_events, MenuButton button) {
        this_motion_events.leave.connect((controller) => {
            if (button.popover != null && button.popover.visible) return;

            var widget = controller.widget as VideoPlayerWidget;
            if (widget != null) {
                widget.overlay_toolbar.visible = false;
                widget.file_size_label.visible = false;
            }
        });
    }

    private void on_motion_event_enter() {
        overlay_toolbar.visible = show_overlay_toolbar;
        if (file_transfer == null) return;
        file_size_label.visible = file_transfer.direction == FileTransfer.DIRECTION_RECEIVED && file_transfer.state == FileTransfer.State.NOT_STARTED && !file_transfer.sfs_sources.is_empty;
    }

    private bool file_size_label_transform(Binding binding, GLib.Value source_value, ref GLib.Value target_value) {
        int64 size = (int64) source_value;
        target_value.set_string(GLib.format_size((uint64) size));
        return true;
    }

    private async void update_widget() {
        if (file_transfer == null) return;
        debug("VideoPlayerWidget: update_widget state=%s", file_transfer.state.to_string());
        if (file_transfer.state == FileTransfer.State.COMPLETE) {
            if (state != State.VIDEO) {
                state = State.VIDEO;
                show_overlay_toolbar = true;
                transmission_progress.visible = false;
                
                // Show placeholder immediately, preview is generated lazily
                // when the widget scrolls into the viewport
                if (preview_image == null) {
                    var placeholder = stack.get_child_by_name("placeholder");
                    if (placeholder == null) {
                        var icon = new Gtk.Image.from_icon_name("video-x-generic");
                        icon.pixel_size = 96;
                        stack.add_named(icon, "placeholder");
                        placeholder = icon;
                    }
                    stack.set_visible_child(placeholder);
                }
                if (start_play_button != null) start_play_button.visible = true;
                
                // If already in viewport, generate preview now
                try_lazy_preview_init();
            }
        } else {
            // Not complete (Downloading, Not Started, etc.)
            if (state != State.PREVIEW) {
                state = State.PREVIEW;
                show_overlay_toolbar = true;
                
                if (preview_image != null) {
                    stack.set_visible_child(preview_image);
                } else {
                    var placeholder = stack.get_child_by_name("placeholder");
                    if (placeholder == null) {
                        var icon = new Gtk.Image.from_icon_name("video-x-generic");
                        icon.pixel_size = 96;
                        stack.add_named(icon, "placeholder");
                        placeholder = icon;
                    }
                    stack.set_visible_child(placeholder);
                }
                // stack.set_visible_child(preview_image); // Removed this line as we handle it above
            }

            if (file_transfer.state == FileTransfer.State.IN_PROGRESS) {
                transmission_progress.visible = true;
                transmission_progress.state = FileTransmissionProgress.State.DOWNLOADING;
            } else if (file_transfer.state == FileTransfer.State.NOT_STARTED) {
                transmission_progress.visible = true;
                transmission_progress.state = FileTransmissionProgress.State.DOWNLOAD_NOT_STARTED;
            } else {
                transmission_progress.visible = false;
            }
        }
    }

    private File? temp_preview_file = null;
    private Gtk.MediaFile? preview_media = null;

    private void try_lazy_preview_init() {
        if (preview_initialized || preview_generating) return;
        if (file_transfer == null) return;
        if (file_transfer.state != FileTransfer.State.COMPLETE) return;
        if (!this.get_mapped()) return;

        // Connect scroll watcher so we get called when scrolling
        ensure_scroll_watch();

        if (!is_in_viewport()) return;

        File? file = file_transfer.get_file();
        if (file == null) return;

        preview_generating = true;
        generate_preview.begin(file);
    }

    private async void generate_preview(File encrypted_file) {
        debug("VideoPlayerWidget: generating preview thumbnail");
        try {
            var app = (Dino.Application) GLib.Application.get_default();
            var enc = app.file_encryption;

            string temp_dir = Path.build_filename(Environment.get_user_cache_dir(), "dinox", "temp_video");
            DirUtils.create_with_parents(temp_dir, 0700);

            string ext = "";
            if ("." in file_transfer.file_name) {
                string[] parts = file_transfer.file_name.split(".");
                ext = "." + parts[parts.length - 1];
            }
            string random_name = "preview_" + GLib.Uuid.string_random() + ext;
            string temp_path = Path.build_filename(temp_dir, random_name);
            temp_preview_file = File.new_for_path(temp_path);

            var source_stream = encrypted_file.read();
            var target_stream = temp_preview_file.replace(null, false, GLib.FileCreateFlags.NONE);
            yield enc.decrypt_stream(source_stream, target_stream);
            try { source_stream.close(); } catch (Error e) {}
            try { target_stream.close(); } catch (Error e) {}

            // Use Gtk.MediaFile to extract the first frame as a still image.
            // With playing=false it loads the video and shows the first frame.
            preview_media = Gtk.MediaFile.for_file(temp_preview_file);
            preview_media.loop = false;
            preview_media.playing = false;

            if (preview_image == null) {
                preview_image = new FixedRatioPicture() { min_width=100, min_height=100, max_width=320, max_height=240 };
                stack.add_child(preview_image);
            }
            preview_image.paintable = preview_media;
            stack.set_visible_child(preview_image);

            preview_initialized = true;
            preview_generating = false;
            debug("VideoPlayerWidget: preview thumbnail set");
        } catch (Error e) {
            preview_generating = false;
            warning("VideoPlayerWidget: Failed to generate preview: %s", e.message);
            // Fallback: show generic video icon
            if (preview_image == null) {
                var icon = new Gtk.Image.from_icon_name("video-x-generic");
                icon.pixel_size = 96;
                stack.add_named(icon, "fallback");
                stack.set_visible_child(icon);
            }
        }
    }

    private File? temp_play_file = null;

    private async void setup_pipeline(File file) {
        debug("VideoPlayerWidget: setup_pipeline for %s", file.get_uri());
        
        File file_to_play = file;
        try {
            var app = (Dino.Application) GLib.Application.get_default();
            var enc = app.file_encryption;
            
            string temp_dir = Path.build_filename(Environment.get_user_cache_dir(), "dinox", "temp_video");
            DirUtils.create_with_parents(temp_dir, 0700);
            
            // Obfuscate filename to prevent leaking info via file listing
            string ext = "";
            if ("." in file_transfer.file_name) {
                string[] parts = file_transfer.file_name.split(".");
                ext = "." + parts[parts.length - 1];
            }
            string random_name = GLib.Uuid.string_random() + ext;
            
            string temp_path = Path.build_filename(temp_dir, random_name);
            temp_play_file = File.new_for_path(temp_path);
            
            var source_stream = file.read();
            var target_stream = temp_play_file.replace(null, false, GLib.FileCreateFlags.NONE);
            
            yield enc.decrypt_stream(source_stream, target_stream);
            
            try { source_stream.close(); } catch (Error e) {}
            try { target_stream.close(); } catch (Error e) {}
            
            file_to_play = temp_play_file;
        } catch (Error e) {
            warning("VideoPlayerWidget: Failed to decrypt video: %s", e.message);
            // Fallback to original file (maybe it wasn't encrypted?)
        }

        if (video_picture == null) {
            video_picture = new Gtk.Picture();
            video_picture.content_fit = ContentFit.SCALE_DOWN;  // Scale down large videos
            video_picture.can_shrink = true;
            video_picture.halign = Align.START;
            video_picture.valign = Align.START;
            video_picture.hexpand = false;
            video_picture.vexpand = false;
            // Set max size but allow scaling down
            video_picture.set_size_request(320, 180);  // Minimum 320x180 (16:9)
            
            // Create aspect frame to maintain ratio
            var aspect_frame = new Gtk.AspectFrame(0.0f, 0.0f, 16.0f/9.0f, false);
            aspect_frame.set_child(video_picture);
            aspect_frame.halign = Align.START;
            aspect_frame.valign = Align.START;
            aspect_frame.hexpand = false;
            aspect_frame.vexpand = false;
            
            // Create a box to hold the video and controls
            var box = new Gtk.Box(Orientation.VERTICAL, 0);
            box.halign = Align.START;
            box.valign = Align.START;
            box.hexpand = false;
            box.vexpand = false;
            
            box.append(aspect_frame);
            
            video_container = box;
            stack.add_child(video_container);
        }
        
        media_file = Gtk.MediaFile.for_file(file_to_play);
        ensure_scroll_watch();
        media_file.notify["error"].connect(() => {
            if (media_file.error != null) {
                warning("VideoPlayerWidget: Media file error for %s: %s", file.get_basename(), media_file.error.message);
            }
        });
        media_file.notify["prepared"].connect(() => {
            debug("VideoPlayerWidget: Media file prepared: %s (has_video: %s, has_audio: %s)", 
                  file.get_basename(), 
                  media_file.has_video.to_string(), 
                  media_file.has_audio.to_string());
        });
        media_file.loop = false;
        media_file.playing = false;
        
        video_picture.set_paintable(media_file);
        
        // Add controls if not already added
        var box = video_container as Gtk.Box;
        if (box != null) {
            Gtk.Widget? existing_controls = box.get_last_child();
            if (existing_controls != null && existing_controls is Gtk.MediaControls) {
                ((Gtk.MediaControls)existing_controls).media_stream = media_file;
            } else {
                var controls = new Gtk.MediaControls(media_file);
                controls.halign = Align.START;
                controls.hexpand = false;
                controls.set_size_request(400, -1);  // Match video width
                box.append(controls);
            }
        }
        
        debug("VideoPlayerWidget: set_paintable done");

        update_playback_visibility();

        // Show the container
        if (video_container != null) {
            stack.set_visible_child(video_container);
        }
    }

    private async void open_file() {
        try {
            File? file = file_transfer.get_file();
            if (file != null) {
                var app = (Dino.Application) GLib.Application.get_default();
                var enc = app.file_encryption;

                string temp_dir = Path.build_filename(Environment.get_user_cache_dir(), "dinox", "temp_open");
                DirUtils.create_with_parents(temp_dir, 0700);

                string temp_path = Path.build_filename(temp_dir, file_transfer.file_name);
                File temp_file = File.new_for_path(temp_path);

                var source_stream = file.read();
                var target_stream = temp_file.replace(null, false, GLib.FileCreateFlags.NONE);
                
                yield enc.decrypt_stream(source_stream, target_stream);
                
                try { source_stream.close(); } catch (Error e) {}
                try { target_stream.close(); } catch (Error e) {}

#if WINDOWS
                string win_path = temp_file.get_path().replace("/", "\\");
                Process.spawn_command_line_async("cmd.exe /c start \"\" \"" + win_path + "\"");
#else
                AppInfo.launch_default_for_uri(temp_file.get_uri(), null);
#endif
            }
        } catch (GLib.Error err) {
            warning("Failed to open file: %s", err.message);
        }
    }

    private void save_file() {
        var save_dialog = new Gtk.FileDialog();
        save_dialog.title = _("Save as…");
        save_dialog.initial_name = file_transfer.file_name;

        save_dialog.save.begin(this.get_root() as Gtk.Window, null, (obj, res) => {
            save_file_finish.begin(obj, res);
        });
    }

    private async void save_file_finish(GLib.Object? obj, AsyncResult res) {
        var save_dialog = (Gtk.FileDialog) obj;
        try {
            File? target_file = save_dialog.save.end(res);
            if (target_file != null) {
                File? source_file = file_transfer.get_file();
                if (source_file != null) {
                    var app = (Dino.Application) GLib.Application.get_default();
                    var enc = app.file_encryption;

                    var source_stream = source_file.read();
                    var target_stream = target_file.replace(null, false, GLib.FileCreateFlags.NONE);

                    yield enc.decrypt_stream(source_stream, target_stream);
                    
                    try { source_stream.close(); } catch (Error e) {}
                    try { target_stream.close(); } catch (Error e) {}
                }
            }
        } catch (GLib.Error e) {
            warning("Failed to save file: %s", e.message);
        }
    }

    public override void dispose() {
        // Unbind all file_transfer property bindings
        if (ft_state_binding != null) { ft_state_binding.unbind(); ft_state_binding = null; }
        if (ft_size_binding1 != null) { ft_size_binding1.unbind(); ft_size_binding1 = null; }
        if (ft_size_binding2 != null) { ft_size_binding2.unbind(); ft_size_binding2 = null; }
        if (ft_bytes_binding != null) { ft_bytes_binding.unbind(); ft_bytes_binding = null; }
        file_transfer = null;

        disconnect_scroll_watch();
        if (media_file != null) {
            media_file.set_playing(false);
            media_file = null;
        }
        if (preview_media != null) {
            preview_media = null;
        }
        if (temp_play_file != null) {
            try {
                temp_play_file.delete(null);
            } catch (Error e) {}
            temp_play_file = null;
        }
        if (temp_preview_file != null) {
            try {
                temp_preview_file.delete(null);
            } catch (Error e) {}
            temp_preview_file = null;
        }
        if (video_picture != null) {
            video_picture.set_paintable(null);
        }
        if (preview_image != null) {
            preview_image.paintable = null;
        }
        base.dispose();
    }

    private void disconnect_scroll_watch() {
        if (watched_vadjustment != null && watched_vadjustment_handler_id != 0) {
            watched_vadjustment.disconnect(watched_vadjustment_handler_id);
            watched_vadjustment_handler_id = 0;
        }
        watched_vadjustment = null;
        watched_scrolled = null;
    }

    private Gtk.ScrolledWindow? find_scrolled_window() {
        Gtk.Widget? w = this;
        while (w != null) {
            if (w is Gtk.ScrolledWindow) {
                return (Gtk.ScrolledWindow) w;
            }
            w = w.get_parent();
        }
        return null;
    }

    private void ensure_scroll_watch() {
        if (watched_scrolled != null) return;

        watched_scrolled = find_scrolled_window();
        if (watched_scrolled == null) return;

        watched_vadjustment = watched_scrolled.vadjustment;
        if (watched_vadjustment == null) return;

        watched_vadjustment_handler_id = watched_vadjustment.value_changed.connect(() => {
            update_playback_visibility();
        });
    }

    private bool is_in_viewport() {
        if (watched_scrolled == null || watched_vadjustment == null) return true;

        Gtk.Widget? content = watched_scrolled.get_child();
        if (content == null) return true;

        Graphene.Rect bounds;
        if (!this.compute_bounds(content, out bounds)) return true;

        double top = watched_vadjustment.value;
        double bottom = top + watched_vadjustment.page_size;
        double y1 = bounds.origin.y;
        double y2 = y1 + bounds.size.height;

        const double margin = 64.0;
        return (y2 >= (top - margin)) && (y1 <= (bottom + margin));
    }

    private void pause_for_visibility() {
        if (media_file == null) return;

        if (media_file.playing) {
            paused_by_visibility = true;
            media_file.playing = false;
        }
    }

    private void update_playback_visibility() {
        if (media_file == null) {
            // No active playback — but check if we need to lazy-init preview
            ensure_scroll_watch();
            try_lazy_preview_init();
            return;
        }

        ensure_scroll_watch();

        bool should_be_active = this.visible && this.get_mapped() && is_in_viewport();
        if (!should_be_active) {
            pause_for_visibility();
            return;
        }

        if (paused_by_visibility) {
            paused_by_visibility = false;
            media_file.playing = true;
        }
    }
}

}
