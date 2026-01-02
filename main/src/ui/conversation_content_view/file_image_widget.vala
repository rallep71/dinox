using Gee;
using Gdk;
using Gtk;
using Graphene;
using Xmpp;

using Dino.Entities;
using Dino.Security;

namespace Dino.Ui {

public class FileImageWidget : Widget {
    enum State {
        EMPTY,
        PREVIEW,
        IMAGE
    }
    private State state = State.EMPTY;

    private Stack stack = new Stack() { transition_duration=600, transition_type=StackTransitionType.CROSSFADE, hhomogeneous = false, vhomogeneous = false, interpolate_size = true };
    private Overlay overlay = new Overlay();

    private bool show_image_overlay_toolbar = false;
    private Gtk.Box image_overlay_toolbar = new Gtk.Box(Orientation.VERTICAL, 0) { halign=Align.END, valign=Align.START, margin_top=10, margin_start=10, margin_end=10, margin_bottom=10, vexpand=false, visible=false };
    private Label file_size_label = new Label(null) { halign=Align.START, valign=Align.END, margin_bottom=4, margin_start=4, visible=false };

    private FileTransfer file_transfer;

    private uint animation_timeout_id = 0;
    private Gdk.PixbufAnimationIter? sticker_anim_iter = null;
    private FixedRatioPicture? sticker_anim_picture = null;

    private Gtk.ScrolledWindow? watched_scrolled = null;
    private Gtk.Adjustment? watched_vadjustment = null;
    private ulong watched_vadjustment_handler_id = 0;

    private const int FIRST_FRAME_CACHE_MAX_ENTRIES = 128;
    private static Gee.HashMap<string, Gdk.Texture> first_frame_cache = new Gee.HashMap<string, Gdk.Texture>();
    private static Gee.LinkedList<string> first_frame_lru = new Gee.LinkedList<string>();

    private uint load_generation = 0;
    private Cancellable? load_cancellable = null;

    private FileTransmissionProgress transmission_progress = new FileTransmissionProgress() { halign=Align.CENTER, valign=Align.CENTER, visible=false };

    construct {
        layout_manager = new BinLayout();
    }

    private static void cache_first_frame(string key, Gdk.Texture texture) {
        if (key == "") return;

        if (first_frame_cache.has_key(key)) {
            first_frame_lru.remove(key);
        }

        first_frame_cache[key] = texture;
        first_frame_lru.add(key);

        while (first_frame_lru.size > FIRST_FRAME_CACHE_MAX_ENTRIES) {
            string oldest = first_frame_lru.get(0);
            first_frame_lru.remove_at(0);
            first_frame_cache.unset(oldest);
        }
    }

    private static Gdk.Texture? get_cached_first_frame(string key) {
        if (key == "") return null;
        if (!first_frame_cache.has_key(key)) return null;

        // Touch LRU
        first_frame_lru.remove(key);
        first_frame_lru.add(key);

        return first_frame_cache[key];
    }

    private void disconnect_scroll_watch() {
        if (watched_vadjustment != null && watched_vadjustment_handler_id != 0) {
            watched_vadjustment.disconnect(watched_vadjustment_handler_id);
            watched_vadjustment_handler_id = 0;
        }
        watched_vadjustment = null;
        watched_scrolled = null;
    }

    private void pause_animation() {
        if (animation_timeout_id != 0) {
            Source.remove(animation_timeout_id);
            animation_timeout_id = 0;
        }
    }

    private void reset_loading_and_animation() {
        pause_animation();
        sticker_anim_iter = null;
        sticker_anim_picture = null;

        if (load_cancellable != null) {
            load_cancellable.cancel();
            load_cancellable = null;
        }
    }

    private Gtk.ScrolledWindow? find_scrolled_window() {
        Widget? w = this;
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
            update_animation_state();
        });
    }

    private bool is_in_viewport() {
        if (watched_scrolled == null || watched_vadjustment == null) return true;

        Widget? content = watched_scrolled.get_child();
        if (content == null) return true;

        Graphene.Rect bounds;
        if (!this.compute_bounds(content, out bounds)) return true;

        double top = watched_vadjustment.value;
        double bottom = top + watched_vadjustment.page_size;

        double y1 = bounds.origin.y;
        double y2 = y1 + bounds.size.height;

        // Small margin to avoid rapid toggling near edges.
        const double margin = 64.0;
        return (y2 >= (top - margin)) && (y1 <= (bottom + margin));
    }

    private void update_animation_state() {
        if (sticker_anim_iter == null || sticker_anim_picture == null) return;

        ensure_scroll_watch();

        bool should_animate = this.visible && this.get_mapped() && is_in_viewport();
        if (should_animate) {
            if (animation_timeout_id == 0) {
                schedule_next_sticker_frame();
            }
        } else {
            pause_animation();
        }
    }

    private class LoadResult : Object {
        public Gdk.Pixbuf? pixbuf;
        public Gdk.PixbufAnimation? animation;
    }

    private void schedule_next_sticker_frame() {
        if (sticker_anim_iter == null || sticker_anim_picture == null) return;

        int delay_ms = sticker_anim_iter.get_delay_time();
        if (delay_ms < 20) delay_ms = 100;

        animation_timeout_id = Timeout.add((uint) delay_ms, () => {
            if (sticker_anim_iter == null || sticker_anim_picture == null) return false;

            // Only animate while visible (mapped + within viewport).
            if (!this.visible || !this.get_mapped() || !is_in_viewport()) {
                animation_timeout_id = 0;
                return false;
            }

            sticker_anim_iter.advance(null);
            sticker_anim_picture.paintable = Texture.for_pixbuf(sticker_anim_iter.get_pixbuf());

            schedule_next_sticker_frame();
            return false;
        });
    }

    public FileImageWidget(int MAX_WIDTH=600, int MAX_HEIGHT=300) {
        this.halign = Align.START;

        this.add_css_class("file-image-widget");

        // Setup menu button overlay
        MenuButton button = new MenuButton();
        button.icon_name = "view-more";
        Menu menu_model = new Menu();
        menu_model.append(_("Open"), "file.open");
        menu_model.append(_("Save as…"), "file.save_as");
        Gtk.PopoverMenu popover_menu = new Gtk.PopoverMenu.from_model(menu_model);
        button.popover = popover_menu;
        image_overlay_toolbar.append(button);
        image_overlay_toolbar.add_css_class("card");
        image_overlay_toolbar.add_css_class("toolbar");
        image_overlay_toolbar.add_css_class("compact-card-toolbar");
        image_overlay_toolbar.set_cursor_from_name("default");

        file_size_label.add_css_class("file-details");

        overlay.set_child(stack);
        overlay.set_measure_overlay(stack, true);
        overlay.add_overlay(file_size_label);
        overlay.add_overlay(transmission_progress);
        overlay.add_overlay(image_overlay_toolbar);
        overlay.set_clip_overlay(image_overlay_toolbar, true);

        overlay.insert_after(this, null);

        GestureClick gesture_click_controller = new GestureClick();
        gesture_click_controller.button = 1; // listen for left clicks
        gesture_click_controller.released.connect(on_image_clicked);
        stack.add_controller(gesture_click_controller);

        EventControllerMotion this_motion_events = new EventControllerMotion();
        this.add_controller(this_motion_events);
        this_motion_events.enter.connect((controller, x, y) => {
            var widget = controller.widget as FileImageWidget;
            if (widget != null) {
                widget.on_motion_event_enter();
            }
        });
        attach_on_motion_event_leave(this_motion_events, button);

        this.notify["mapped"].connect(() => {
            if (!this.get_mapped()) {
                pause_animation();
                disconnect_scroll_watch();
            } else {
                update_animation_state();
            }
        });
    }

    private static void attach_on_motion_event_leave(EventControllerMotion this_motion_events, MenuButton button) {
        this_motion_events.leave.connect((controller) => {
            if (button.popover != null && button.popover.visible) return;

            var widget = controller.widget as FileImageWidget;
            if (widget != null) {
                widget.image_overlay_toolbar.visible = false;
                widget.file_size_label.visible = false;
            }
        });
    }

    private void on_motion_event_enter() {
        image_overlay_toolbar.visible = show_image_overlay_toolbar;
        file_size_label.visible = file_transfer != null && file_transfer.direction == FileTransfer.DIRECTION_RECEIVED && file_transfer.state == FileTransfer.State.NOT_STARTED && !file_transfer.sfs_sources.is_empty;
    }

    public async void set_file_transfer(FileTransfer file_transfer) {
        this.file_transfer = file_transfer;

        this.file_transfer.bind_property("size", file_size_label, "label", BindingFlags.SYNC_CREATE, file_size_label_transform);
        this.file_transfer.bind_property("size", transmission_progress, "file-size", BindingFlags.SYNC_CREATE);
        this.file_transfer.bind_property("transferred-bytes", transmission_progress, "transferred-size");

        file_transfer.notify["state"].connect(refresh_state);
        file_transfer.sources_changed.connect(refresh_state);
        refresh_state();
    }

    private static bool file_size_label_transform(Binding binding, Value from_value, ref Value to_value) {
        to_value = FileDefaultWidget.get_size_string((int64) from_value);
        return true;
    }

    private void refresh_state() {
        if ((state == EMPTY || state == PREVIEW) && file_transfer.path != null) {
            load_from_file.begin(file_transfer.get_file(), file_transfer.file_name);
            show_image_overlay_toolbar = true;
            this.set_cursor_from_name("zoom-in");

            state = IMAGE;
        } else if (state == EMPTY && file_transfer.thumbnails.size > 0) {
            load_from_thumbnail.begin(file_transfer);

            transmission_progress.visible = true;
            show_image_overlay_toolbar = false;

            state = PREVIEW;
        }

        if (file_transfer.state == IN_PROGRESS || file_transfer.state == NOT_STARTED || file_transfer.state == FAILED) {
            transmission_progress.visible = true;
            show_image_overlay_toolbar = false;
        } else if (transmission_progress.visible) {
            Timeout.add(250, () => {
                transmission_progress.transferred_size = transmission_progress.file_size;
                transmission_progress.visible = false;
                show_image_overlay_toolbar = true;
                return false;
            });
        }

        if (file_transfer.direction == FileTransfer.DIRECTION_RECEIVED) {
            if (file_transfer.state == IN_PROGRESS) {
                transmission_progress.state = DOWNLOADING;
            } else if (file_transfer.sfs_sources.is_empty) {
                transmission_progress.state = UNKNOWN_SOURCE;
            } else if (file_transfer.state == NOT_STARTED) {
                transmission_progress.state = DOWNLOAD_NOT_STARTED;
            } else if (file_transfer.state == FAILED) {
                transmission_progress.state = DOWNLOAD_NOT_STARTED_FAILED_BEFORE;
            }
        } else if (file_transfer.direction == FileTransfer.DIRECTION_SENT) {
            if (file_transfer.state == IN_PROGRESS) {
                transmission_progress.state = UPLOADING;
            } else if (file_transfer.state == FAILED) {
                transmission_progress.state = UPLOAD_FAILED;
            }
        }
    }

    public async void load_from_file(File file, string file_name) throws GLib.Error {
        reset_loading_and_animation();
        FixedRatioPicture image = new FixedRatioPicture() { min_width=100, min_height=100, max_width=600, max_height=300 };

        // Show placeholder immediately to avoid blocking chat switching.
        stack.add_child(image);
        stack.set_visible_child(image);

        uint gen = ++load_generation;
        var cancellable = new Cancellable();
        load_cancellable = cancellable;

        bool is_sticker = this.file_transfer != null && this.file_transfer.is_sticker;
        bool animations_enabled = true;
        if (is_sticker) {
            animations_enabled = Dino.Application.get_default().settings.sticker_animations_enabled;
        }

        string? local_path = file.get_path();

        // Avoid SVG stickers: gdk-pixbuf SVG loader can crash in some Flatpak runtimes.
        if (is_sticker) {
            string? mt = this.file_transfer.mime_type;
            if (mt != null && mt != "" && mt.down().has_prefix("image/svg")) {
                return;
            }
            if (local_path != null && local_path != "") {
                string lower_path = local_path.down();
                if (lower_path.has_suffix(".svg") || lower_path.has_suffix(".svgz")) {
                    return;
                }
            }
        }

        // If we have a cached first frame for an animated sticker, show it immediately.
        if (is_sticker && animations_enabled && local_path != null && local_path != "") {
            var cached = get_cached_first_frame(local_path);
            if (cached != null) {
                image.paintable = cached;
            }
        }

        // Background decode for static images and non-webp stickers.
        new Thread<void*>("dinox-image-decode", () => {
                var out = new LoadResult();
                if (cancellable.is_cancelled()) {
                    return null;
                }

                try {
                    var app = (Dino.Application) GLib.Application.get_default();
                    var enc = app.file_encryption;
                    
                    uint8[] data;
                    if (local_path != null && local_path != "") {
                        FileUtils.get_data(local_path, out data);
                    } else {
                        return null;
                    }
                    
                    MemoryInputStream stream = null;
                    try {
                        uint8[] plaintext = enc.decrypt_data(data);
                        stream = new MemoryInputStream.from_data(plaintext, null);
                    } catch (Error e) {
                        // Decryption failed, assume plaintext
                        stream = new MemoryInputStream.from_data(data, null);
                    }

                    if (is_sticker && animations_enabled) {
                        Gdk.PixbufAnimation anim;
                        anim = new Gdk.PixbufAnimation.from_stream(stream);
                        out.animation = anim;
                    } else {
                        out.pixbuf = new Pixbuf.from_stream(stream);
                    }
                } catch (Error e) {
                    // Keep out empty.
                }

                Idle.add(() => {
                    if (this.load_generation != gen) return false;
                    if (cancellable.is_cancelled()) return false;

                    if (out.animation != null && is_sticker && animations_enabled && !out.animation.is_static_image()) {
                        var iter = out.animation.get_iter(null);
                        var first_tex = Texture.for_pixbuf(iter.get_pixbuf());
                        image.paintable = first_tex;
                        if (local_path != null && local_path != "") {
                            cache_first_frame(local_path, first_tex);
                        }
                        sticker_anim_iter = iter;
                        sticker_anim_picture = image;
                        update_animation_state();
                        return false;
                    }

                    if (out.animation != null && out.animation.is_static_image()) {
                        var pb = out.animation.get_static_image();
                        pb = pb.apply_embedded_orientation();
                        image.paintable = Texture.for_pixbuf(pb);
                        return false;
                    }

                    if (out.pixbuf != null) {
                        var pb = out.pixbuf.apply_embedded_orientation();
                        image.paintable = Texture.for_pixbuf(pb);
                    }
                    return false;
                });

                return null;
            });
    }

    public async void load_from_thumbnail(FileTransfer file_transfer) throws GLib.Error {
        this.file_transfer = file_transfer;

        Gdk.Pixbuf? pixbuf = null;
        foreach (Xep.JingleContentThumbnails.Thumbnail thumbnail in file_transfer.thumbnails) {
            pixbuf = parse_thumbnail(thumbnail);
            if (pixbuf != null) {
                break;
            }
        }
        if (pixbuf == null) {
            warning("Can't load thumbnails of file %s", file_transfer.file_name);
            throw new Error(-1, 0, "Error loading preview image");
        }
        // TODO: should this be executed? If yes, before or after scaling
        pixbuf = pixbuf.apply_embedded_orientation();

        if (file_transfer.width > 0 && file_transfer.height > 0) {
            pixbuf = pixbuf.scale_simple(file_transfer.width, file_transfer.height, InterpType.BILINEAR);
        } else {
            warning("Preview: Not scaling image, width: %d, height: %d\n", file_transfer.width, file_transfer.height);
        }
        if (pixbuf == null) {
            warning("Can't scale thumbnail %s", file_transfer.file_name);
            throw new Error(-1, 0, "Error scaling preview image");
        }

        FixedRatioPicture image = new FixedRatioPicture() { min_width=100, min_height=100, max_width=600, max_height=300 };
        image.paintable = Texture.for_pixbuf(pixbuf);
        stack.add_child(image);
        stack.set_visible_child(image);
    }

    public void on_image_clicked(GestureClick gesture_click_controller, int n_press, double x, double y) {
        if (this.file_transfer.state != COMPLETE) return;

        switch (gesture_click_controller.get_device().source) {
            case Gdk.InputSource.TOUCHSCREEN:
            case Gdk.InputSource.PEN:
                if (n_press == 1) {
                    image_overlay_toolbar.visible = !image_overlay_toolbar.visible;
                } else if (n_press == 2) {
                    this.activate_action("file.open", null);
                    image_overlay_toolbar.visible = false;
                }
                break;
            default:
                this.activate_action("file.open", null);
                image_overlay_toolbar.visible = false;
                break;
        }
    }

    public static Pixbuf? parse_thumbnail(Xep.JingleContentThumbnails.Thumbnail thumbnail) {
        MemoryInputStream input_stream = new MemoryInputStream.from_data(thumbnail.data.get_data());
        try {
            return new Pixbuf.from_stream(input_stream);
        } catch (Error e) {
            warning("Failed to parse thumbnail: %s", e.message);
            return null;
        }
    }

    public static bool can_display(FileTransfer file_transfer) {
        var app = Dino.Application.get_default();
        if (file_transfer.is_sticker && !app.settings.stickers_enabled) {
            return false;
        }

        if (file_transfer.is_sticker && file_transfer.mime_type != null && file_transfer.mime_type != "" && file_transfer.mime_type.down().has_prefix("image/svg")) {
            return false;
        }

        return file_transfer.mime_type != null && Dino.Util.is_pixbuf_supported_mime_type(file_transfer.mime_type) &&
                (file_transfer.state == FileTransfer.State.COMPLETE || file_transfer.thumbnails.size > 0);
    }

    public override void dispose() {
        reset_loading_and_animation();
        disconnect_scroll_watch();
        if (overlay != null && overlay.parent != null) overlay.unparent();
        base.dispose();
    }
}

}
