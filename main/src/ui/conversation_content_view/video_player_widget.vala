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
    private Gtk.Widget? video_container = null;
    private FixedRatioPicture? preview_image = null;

    // Raw GStreamer playback (replaces Gtk.MediaFile for full PipeWire control)
    private Gst.Element? playback_pipeline = null;
    private Gst.Element? playback_vsink = null;   // fakesink with enable-last-sample
    private uint playback_bus_watch = 0;
    private uint frame_update_timer = 0;
    private bool is_video_playing = false;

    // Video player controls
    private Gtk.Box? controls_bar = null;
    private Gtk.Scale? seek_scale = null;
    private Gtk.Label? time_label = null;
    private Gtk.Button? play_pause_btn = null;
    private Gtk.Button? stop_btn = null;
    private int64 playback_duration = -1;
    private bool seeking = false;

    private Gtk.ScrolledWindow? watched_scrolled = null;
    private Gtk.Adjustment? watched_vadjustment = null;
    private ulong watched_vadjustment_handler_id = 0;
    private bool preview_initialized = false;
    private bool preview_generating = false;
    private bool pipeline_active = false;

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
            // Resume if paused
            if (playback_pipeline != null && !is_video_playing) {
                playback_pipeline.set_state(Gst.State.PLAYING);
                is_video_playing = true;
                start_play_button.visible = false;
                if (play_pause_btn != null) play_pause_btn.icon_name = "media-playback-pause-symbolic";
                return;
            }
            if (pipeline_active) return; // guard against double-click
            File? file = file_transfer.get_file();
            if (file != null) {
                start_play_button.visible = false;
                setup_pipeline.begin(file);
            }
        });
        overlay.add_overlay(start_play_button);

        this.notify["mapped"].connect(() => {
            if (!this.get_mapped()) {
                // Synchronously destroy pipeline on unmap (conversation switch, window close)
                cleanup_playback();
                if (start_play_button != null) start_play_button.visible = true;
                disconnect_scroll_watch();
            } else {
                // Generate preview thumbnail if not yet done.
                // This uses fakesink only (NO PipeWire entry) and destroys immediately.
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

        // Build video player controls bar (hidden until playback starts)
        controls_bar = new Gtk.Box(Orientation.HORIZONTAL, 4);
        controls_bar.halign = Align.FILL;
        controls_bar.valign = Align.END;
        controls_bar.margin_start = 4;
        controls_bar.margin_end = 4;
        controls_bar.margin_bottom = 4;
        controls_bar.add_css_class("osd");
        controls_bar.add_css_class("toolbar");
        controls_bar.visible = false;

        play_pause_btn = new Gtk.Button.from_icon_name("media-playback-pause-symbolic");
        play_pause_btn.add_css_class("flat");
        play_pause_btn.valign = Align.CENTER;
        play_pause_btn.clicked.connect(() => {
            if (playback_pipeline == null) return;
            if (is_video_playing) {
                playback_pipeline.set_state(Gst.State.PAUSED);
                is_video_playing = false;
                play_pause_btn.icon_name = "media-playback-start-symbolic";
                if (start_play_button != null) start_play_button.visible = true;
            } else {
                playback_pipeline.set_state(Gst.State.PLAYING);
                is_video_playing = true;
                play_pause_btn.icon_name = "media-playback-pause-symbolic";
                if (start_play_button != null) start_play_button.visible = false;
            }
        });
        controls_bar.append(play_pause_btn);

        seek_scale = new Gtk.Scale.with_range(Orientation.HORIZONTAL, 0.0, 1.0, 0.01);
        seek_scale.hexpand = true;
        seek_scale.draw_value = false;
        seek_scale.valign = Align.CENTER;

        // Drag-start: pause seeking so timer doesn't override
        seek_scale.change_value.connect((scroll, val) => {
            seeking = true;
            if (playback_pipeline != null && playback_duration > 0) {
                int64 pos = (int64)(val * playback_duration);
                playback_pipeline.seek_simple(Gst.Format.TIME,
                    Gst.SeekFlags.FLUSH | Gst.SeekFlags.ACCURATE, pos);
                update_time_label(pos, playback_duration);
            }
            // Release seek lock after a short delay so timer resumes
            Timeout.add(100, () => { seeking = false; return false; });
            return false;
        });
        controls_bar.append(seek_scale);

        time_label = new Gtk.Label("0:00 / 0:00");
        time_label.add_css_class("monospace");
        time_label.valign = Align.CENTER;
        time_label.width_chars = 13;
        time_label.xalign = 1.0f;
        controls_bar.append(time_label);

        stop_btn = new Gtk.Button.from_icon_name("media-playback-stop-symbolic");
        stop_btn.add_css_class("flat");
        stop_btn.valign = Align.CENTER;
        stop_btn.clicked.connect(() => {
            cleanup_playback();
            if (controls_bar != null) controls_bar.visible = false;
            if (start_play_button != null) start_play_button.visible = true;
            if (preview_image != null) stack.set_visible_child(preview_image);
        });
        controls_bar.append(stop_btn);

        overlay.set_child(stack);
        overlay.set_measure_overlay(stack, true);
        overlay.add_overlay(file_size_label);
        overlay.add_overlay(transmission_progress);
        overlay.add_overlay(controls_bar);
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
                
                // Generate preview thumbnail (uses fakesink only, no PipeWire, destroyed immediately)
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

            // Extract first frame using uridecodebin — NO playbin, NO autoaudiosink
            // uridecodebin only decodes, it creates NO sinks → ZERO PipeWire connections
            var pipe = new Gst.Pipeline("thumb-pipe");
            var thumb_src = ElementFactory.make("uridecodebin", "thumb-src");
            var vconv = ElementFactory.make("videoconvert", "thumb-vc");
            var vcaps_elem = ElementFactory.make("capsfilter", "thumb-vcaps");
            var vsink = ElementFactory.make("fakesink", "thumb-vs");

            if (thumb_src == null || vconv == null || vcaps_elem == null || vsink == null) {
                debug("VideoPlayerWidget: missing GStreamer elements for thumbnail");
                show_fallback_preview();
                preview_generating = false;
                return;
            }

            vcaps_elem.set("caps", Gst.Caps.from_string("video/x-raw,format=RGBA"));
            vsink.set("enable-last-sample", true);

            // Only decode video streams (no audio → no autoaudiosink)
            thumb_src.set("caps", Gst.Caps.from_string("video/x-raw"));
            thumb_src.set("uri", temp_preview_file.get_uri());

            pipe.add_many(thumb_src, vconv, vcaps_elem, vsink);
            vconv.link(vcaps_elem);
            vcaps_elem.link(vsink);

            // Dynamic pad linking from uridecodebin (decoded video pads)
            thumb_src.pad_added.connect((pad) => {
                var sink_pad = vconv.get_static_pad("sink");
                if (sink_pad != null && !sink_pad.is_linked()) {
                    pad.link(sink_pad);
                }
            });

            // Use async state change + bus watch instead of blocking get_state()
            Gst.Bus thumb_bus = pipe.get_bus();
            bool preroll_done = false;
            SourceFunc callback = generate_preview.callback;

            uint thumb_bus_watch = thumb_bus.add_watch(0, (bus, msg) => {
                if (msg.type == Gst.MessageType.ASYNC_DONE || msg.type == Gst.MessageType.ERROR) {
                    if (!preroll_done) {
                        preroll_done = true;
                        Idle.add((owned) callback);
                    }
                }
                return true;
            });

            // Safety timeout 3s
            uint timeout_id = Timeout.add(3000, () => {
                if (!preroll_done) {
                    preroll_done = true;
                    callback();
                }
                return false;
            });

            pipe.set_state(Gst.State.PAUSED);
            yield;

            Source.remove(thumb_bus_watch);
            // timeout may have already fired, try removing anyway
            Source.remove(timeout_id);

            // Check if pipeline reached PAUSED (prerolled first frame)
            Gst.State cur_state, pend_state;
            pipe.get_state(out cur_state, out pend_state, 0); // non-blocking check

            if (cur_state == Gst.State.PAUSED) {
                // Get last-sample from the fakesink directly
                Gst.Sample? sample = null;
                var sink_val = GLib.Value(typeof(Gst.Sample));
                vsink.get_property("last-sample", ref sink_val);
                sample = (Gst.Sample?) sink_val.dup_boxed();

                if (sample != null) {
                    var buf = sample.get_buffer();
                    var caps = sample.get_caps();
                    if (buf != null && caps != null && caps.get_size() > 0) {
                        unowned Gst.Structure st = caps.get_structure(0);
                        int width = 0, height = 0;
                        st.get_int("width", out width);
                        st.get_int("height", out height);

                        if (width > 0 && height > 0) {
                            Gst.MapInfo map;
                            if (buf.map(out map, Gst.MapFlags.READ)) {
                                var bytes = new GLib.Bytes(map.data);
                                size_t row_stride = (size_t)(width * 4);
                                var texture = new Gdk.MemoryTexture(width, height,
                                    Gdk.MemoryFormat.R8G8B8A8, bytes, row_stride);

                                if (preview_image == null) {
                                    preview_image = new FixedRatioPicture() { min_width=100, min_height=100, max_width=320, max_height=240 };
                                    stack.add_child(preview_image);
                                }
                                preview_image.paintable = texture;
                                stack.set_visible_child(preview_image);
                                buf.unmap(map);
                                debug("VideoPlayerWidget: preview thumbnail captured as static texture (%dx%d)", width, height);
                            }
                        }
                    }
                }
            } else {
                debug("VideoPlayerWidget: pipeline did not reach PAUSED, no thumbnail");
                show_fallback_preview();
            }

            // Immediately destroy pipeline → zero PipeWire footprint
            pipe.set_state(Gst.State.NULL);

            preview_initialized = true;
            preview_generating = false;
            debug("VideoPlayerWidget: preview generation complete, pipeline destroyed");
        } catch (Error e) {
            preview_generating = false;
            warning("VideoPlayerWidget: Failed to generate preview: %s", e.message);
            show_fallback_preview();
        }
    }

    private void show_fallback_preview() {
        if (preview_image == null) {
            var icon = new Gtk.Image.from_icon_name("video-x-generic");
            icon.pixel_size = 96;
            stack.add_named(icon, "fallback");
            stack.set_visible_child(icon);
        }
    }

    // Deterministic cleanup: synchronously destroy GStreamer pipeline → PipeWire released immediately
    private void cleanup_playback() {
        is_video_playing = false;
        // 1. Stop frame rendering timer
        if (frame_update_timer != 0) {
            Source.remove(frame_update_timer);
            frame_update_timer = 0;
        }
        // 2. Remove bus watch BEFORE pipeline teardown (prevents callbacks during destruction)
        if (playback_bus_watch != 0) {
            Source.remove(playback_bus_watch);
            playback_bus_watch = 0;
        }
        // 3. Set pipeline to NULL — this is SYNCHRONOUS and immediately releases PipeWire
        if (playback_pipeline != null) {
            playback_pipeline.set_state(Gst.State.NULL);
            playback_pipeline = null;
        }
        playback_vsink = null;
        // 4. Clear Picture paintable
        if (video_picture != null) {
            video_picture.set_paintable(null);
        }
        // 5. Reset controls state
        playback_duration = -1;
        seeking = false;
        pipeline_active = false;
    }

    private File? temp_play_file = null;

    private async void setup_pipeline(File file) {
        if (pipeline_active) return;
        pipeline_active = true;
        debug("VideoPlayerWidget: setup_pipeline");
        
        // Reuse already-decrypted temp file from preview if available
        File file_to_play;
        if (temp_preview_file != null) {
            file_to_play = temp_preview_file;
            debug("VideoPlayerWidget: reusing preview temp file");
        } else if (temp_play_file != null) {
            file_to_play = temp_play_file;
            debug("VideoPlayerWidget: reusing existing temp file");
        } else {
            // Decrypt file
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
                file_to_play = file;
            }
        }

        // Destroy any existing pipeline
        cleanup_playback();
        pipeline_active = true;

        if (video_picture == null) {
            video_picture = new Gtk.Picture();
            video_picture.content_fit = ContentFit.CONTAIN;
            video_picture.can_shrink = true;
            video_picture.halign = Align.FILL;
            video_picture.valign = Align.FILL;
            video_picture.hexpand = false;
            video_picture.vexpand = false;

            // Click on video to toggle pause/play
            var click = new GestureClick();
            click.pressed.connect((n, x, y) => {
                if (playback_pipeline != null && is_video_playing) {
                    playback_pipeline.set_state(Gst.State.PAUSED);
                    is_video_playing = false;
                    if (start_play_button != null) start_play_button.visible = true;
                    if (play_pause_btn != null) play_pause_btn.icon_name = "media-playback-start-symbolic";
                } else if (playback_pipeline != null && !is_video_playing) {
                    playback_pipeline.set_state(Gst.State.PLAYING);
                    is_video_playing = true;
                    if (start_play_button != null) start_play_button.visible = false;
                    if (play_pause_btn != null) play_pause_btn.icon_name = "media-playback-pause-symbolic";
                }
            });
            video_picture.add_controller(click);
            
            var frame = new Gtk.Frame(null);
            frame.set_child(video_picture);
            frame.halign = Align.START;
            frame.valign = Align.START;
            frame.hexpand = false;
            frame.vexpand = false;
            frame.set_size_request(400, 225);
            frame.overflow = Gtk.Overflow.HIDDEN;
            
            var box = new Gtk.Box(Orientation.VERTICAL, 0);
            box.halign = Align.START;
            box.valign = Align.START;
            box.hexpand = false;
            box.vexpand = false;
            
            box.append(frame);
            
            video_container = box;
            stack.add_child(video_container);
        }

        // Pipeline + uridecodebin — NO playbin, no internal autoaudiosink/autovideosink
        // Video: uridecodebin → videoconvert → capsfilter(RGBA) → fakesink (frame polling)
        // Audio: uridecodebin → audioconvert → autoaudiosink (1 PipeWire entry, closed on NULL)
        var play_pipe = new Gst.Pipeline("video-playback");
        var play_src = ElementFactory.make("uridecodebin", "play-src");
        var vconv = ElementFactory.make("videoconvert", "play-vc");
        var vcaps = ElementFactory.make("capsfilter", "play-vcaps");
        playback_vsink = ElementFactory.make("fakesink", "play-vs");
        var aconv = ElementFactory.make("audioconvert", "play-ac");
        var asink = ElementFactory.make("autoaudiosink", "play-as");

        if (play_src == null || vconv == null || vcaps == null || playback_vsink == null || aconv == null || asink == null) {
            warning("VideoPlayerWidget: missing playback elements");
            pipeline_active = false;
            if (start_play_button != null) start_play_button.visible = true;
            return;
        }

        vcaps.set("caps", Gst.Caps.from_string("video/x-raw,format=RGBA"));
        playback_vsink.set("enable-last-sample", true);
        playback_vsink.set("sync", true);

        play_src.set("uri", file_to_play.get_uri());

        play_pipe.add_many(play_src, vconv, vcaps, playback_vsink, aconv, asink);
        vconv.link(vcaps);
        vcaps.link(playback_vsink);
        aconv.link(asink);

        // Dynamic pad linking: audio pads → audioconvert, video pads → videoconvert
        play_src.pad_added.connect((pad) => {
            var pad_caps = pad.get_current_caps();
            if (pad_caps == null) pad_caps = pad.query_caps(null);
            if (pad_caps == null || pad_caps.get_size() == 0) return;
            unowned Gst.Structure st = pad_caps.get_structure(0);
            string pad_type = st.get_name();
            if (pad_type.has_prefix("video/")) {
                var sink_pad = vconv.get_static_pad("sink");
                if (sink_pad != null && !sink_pad.is_linked()) {
                    pad.link(sink_pad);
                }
            } else if (pad_type.has_prefix("audio/")) {
                var sink_pad = aconv.get_static_pad("sink");
                if (sink_pad != null && !sink_pad.is_linked()) {
                    pad.link(sink_pad);
                }
            }
        });

        playback_pipeline = play_pipe;

        // Bus watch for EOS/Error
        Gst.Bus bus = playback_pipeline.get_bus();
        playback_bus_watch = bus.add_watch(0, (b, msg) => {
            if (msg.type == Gst.MessageType.EOS) {
                debug("VideoPlayerWidget: EOS, releasing pipeline");
                cleanup_playback();
                if (controls_bar != null) controls_bar.visible = false;
                if (start_play_button != null) start_play_button.visible = true;
                if (preview_image != null) stack.set_visible_child(preview_image);
            } else if (msg.type == Gst.MessageType.ERROR) {
                GLib.Error err;
                string dbg;
                msg.parse_error(out err, out dbg);
                warning("VideoPlayerWidget: playback error: %s", err.message);
                cleanup_playback();
                if (controls_bar != null) controls_bar.visible = false;
                if (start_play_button != null) start_play_button.visible = true;
            }
            return true;
        });

        // Show video container
        if (video_container != null) {
            stack.set_visible_child(video_container);
        }

        // Start playing — PipeWire audio entry opens NOW
        playback_pipeline.set_state(Gst.State.PLAYING);
        is_video_playing = true;
        playback_duration = -1;

        // Show controls bar
        if (controls_bar != null) controls_bar.visible = true;
        if (play_pause_btn != null) play_pause_btn.icon_name = "media-playback-pause-symbolic";
        if (time_label != null) time_label.label = "0:00 / 0:00";
        if (seek_scale != null) seek_scale.set_value(0.0);

        // Frame rendering timer: poll fakesink at ~30fps and paint to Picture + update controls
        frame_update_timer = Timeout.add(33, () => {
            update_video_frame();
            return true;
        });

        debug("VideoPlayerWidget: playback started (raw GStreamer, no Gtk.MediaFile)");
    }

    // Pull the latest video frame from fakesink and render it as a texture
    private void update_video_frame() {
        if (playback_vsink == null || video_picture == null) return;

        var sink_val = GLib.Value(typeof(Gst.Sample));
        playback_vsink.get_property("last-sample", ref sink_val);
        Gst.Sample? sample = (Gst.Sample?) sink_val.dup_boxed();
        if (sample == null) return;

        var buf = sample.get_buffer();
        var caps = sample.get_caps();
        if (buf == null || caps == null || caps.get_size() == 0) return;

        unowned Gst.Structure st = caps.get_structure(0);
        int width = 0, height = 0;
        st.get_int("width", out width);
        st.get_int("height", out height);
        if (width <= 0 || height <= 0) return;

        Gst.MapInfo map;
        if (buf.map(out map, Gst.MapFlags.READ)) {
            var bytes = new GLib.Bytes(map.data);
            size_t row_stride = (size_t)(width * 4);
            var texture = new Gdk.MemoryTexture(width, height,
                Gdk.MemoryFormat.R8G8B8A8, bytes, row_stride);
            video_picture.set_paintable(texture);
            buf.unmap(map);
        }

        // Update seek bar and time label (skip while user is dragging)
        if (!seeking && playback_pipeline != null) {
            // Query duration once
            if (playback_duration <= 0) {
                playback_pipeline.query_duration(Gst.Format.TIME, out playback_duration);
            }

            int64 position = 0;
            if (playback_pipeline.query_position(Gst.Format.TIME, out position) && playback_duration > 0) {
                double frac = (double)position / (double)playback_duration;
                if (seek_scale != null) seek_scale.set_value(frac.clamp(0.0, 1.0));
                update_time_label(position, playback_duration);
            }
        }
    }

    private void update_time_label(int64 position_ns, int64 duration_ns) {
        if (time_label == null) return;
        time_label.label = "%s / %s".printf(format_time(position_ns), format_time(duration_ns));
    }

    private string format_time(int64 ns) {
        int64 s = ns / Gst.SECOND;
        int m = (int)(s / 60);
        int sec = (int)(s % 60);
        return "%d:%02d".printf(m, sec);
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
        cleanup_playback();
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

    private void update_playback_visibility() {
        // Generate preview thumbnail when scrolling into view (if not done yet).
        // Safe: uses fakesink only (zero PipeWire entries), pipeline destroyed immediately.
        if (playback_pipeline == null) {
            try_lazy_preview_init();
        }
    }
}

}
