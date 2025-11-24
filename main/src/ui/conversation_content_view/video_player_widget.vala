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
using Gst;
using Xmpp;

using Dino.Entities;

namespace Dino.Ui.ConversationSummary {

public class VideoFileMetaItem : FileMetaItem {
    private StreamInteractor stream_interactor_ref;
    private FileItem file_item_ref;
    
    public VideoFileMetaItem(ContentItem content_item, StreamInteractor stream_interactor) {
        base(content_item, stream_interactor);
        this.stream_interactor_ref = stream_interactor;
        this.file_item_ref = content_item as FileItem;
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

    private FileTransfer file_transfer;
    private Gtk.Picture? video_picture = null;
    private Gtk.MediaFile? media_file = null;
    private Gtk.Widget? video_container = null;
    private FixedRatioPicture? preview_image = null;

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
        this.add_css_class("video-player-widget");

        this.file_transfer = file_transfer;
        
        install_action("file.open", null, (widget, action_name) => { ((VideoPlayerWidget) widget).open_file(); });
        install_action("file.save_as", null, (widget, action_name) => { ((VideoPlayerWidget) widget).save_file(); });

        // Setup menu button overlay
        MenuButton button = new MenuButton();
        button.icon_name = "view-more";
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

        file_transfer.bind_property("state", this, "file-transfer-state");
        this.notify["file-transfer-state"].connect(update_widget);
        
        this.file_transfer.bind_property("size", file_size_label, "label", BindingFlags.SYNC_CREATE, file_size_label_transform);
        this.file_transfer.bind_property("size", transmission_progress, "file-size", BindingFlags.SYNC_CREATE);
        this.file_transfer.bind_property("transferred-bytes", transmission_progress, "transferred-size", BindingFlags.SYNC_CREATE);
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
        file_size_label.visible = file_transfer != null && file_transfer.direction == FileTransfer.DIRECTION_RECEIVED && file_transfer.state == FileTransfer.State.NOT_STARTED && !file_transfer.sfs_sources.is_empty;
    }

    private bool file_size_label_transform(Binding binding, GLib.Value source_value, ref GLib.Value target_value) {
        int64 size = (int64) source_value;
        target_value.set_string(GLib.format_size((uint64) size));
        return true;
    }

    private async void update_widget() {
        debug("VideoPlayerWidget: update_widget state=%s", file_transfer.state.to_string());
        if (file_transfer.state == FileTransfer.State.COMPLETE) {
            if (state != State.VIDEO) {
                state = State.VIDEO;
                show_overlay_toolbar = true;
                transmission_progress.visible = false;
                
                File? file = file_transfer.get_file();
                if (file != null) {
                    setup_pipeline(file);
                }
            }
        } else {
            // Not complete (Downloading, Not Started, etc.)
            if (state != State.PREVIEW) {
                state = State.PREVIEW;
                show_overlay_toolbar = true;
                
                if (preview_image == null) {
                    preview_image = new FixedRatioPicture() { min_width=100, min_height=100, max_width=320, max_height=240 };
                    // Try to get a thumbnail if available, otherwise use a generic video icon
                    // For now, let's use a generic icon or empty
                    // TODO: Implement thumbnail extraction for videos
                    
                    // Use a placeholder icon for now
                    var icon_theme = Gtk.IconTheme.get_for_display(Gdk.Display.get_default());
                    if (icon_theme.has_icon("video-x-generic")) {
                        // This is a bit hacky, FixedRatioPicture expects a Paintable
                        // We might want to improve this later
                    }
                    stack.add_child(preview_image);
                }
                stack.set_visible_child(preview_image);
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

    private void setup_pipeline(File file) {
        debug("VideoPlayerWidget: setup_pipeline for %s", file.get_uri());
        if (video_picture == null) {
            video_picture = new Gtk.Picture();
            video_picture.content_fit = ContentFit.SCALE_DOWN;  // Scale down large videos
            video_picture.can_shrink = true;
            video_picture.halign = Align.START;
            video_picture.valign = Align.START;
            video_picture.hexpand = false;
            video_picture.vexpand = false;
            // Set max size but allow scaling down
            video_picture.set_size_request(400, 225);  // Minimum 400x225 (16:9)
            
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
        
        media_file = Gtk.MediaFile.for_file(file);
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

        // Show the container
        if (video_container != null) {
            stack.set_visible_child(video_container);
        }
    }

    private void open_file() {
        try {
            File? file = file_transfer.get_file();
            if (file != null) {
                AppInfo.launch_default_for_uri(file.get_uri(), null);
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
            try {
                File? target_file = save_dialog.save.end(res);
                if (target_file != null) {
                    File? source_file = file_transfer.get_file();
                    if (source_file != null) {
                        source_file.copy(target_file, GLib.FileCopyFlags.OVERWRITE, null);
                    }
                }
            } catch (GLib.Error e) {
                warning("Failed to save file: %s", e.message);
            }
        });
    }

    public override void dispose() {
        if (media_file != null) {
            media_file.set_playing(false);
            media_file = null;
        }
        if (video_picture != null) {
            video_picture.set_paintable(null);
        }
        base.dispose();
    }
}

}
