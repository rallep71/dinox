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
using Adw;

using Dino.Entities;

namespace Dino.Ui.ChatInput {

public class StickerChooser : Popover {
    private StreamInteractor stream_interactor;
    private Conversation? conversation;

    private bool needs_reload = true;

    private Gtk.Box root_box = new Gtk.Box(Orientation.VERTICAL, 6);
    private Gtk.Box header_box = new Gtk.Box(Orientation.HORIZONTAL, 6);
    private Gtk.MenuButton pack_button;
    private Gtk.Label pack_label = new Gtk.Label("");
    private Gtk.Popover pack_popover = new Gtk.Popover();
    private Gtk.ListBox pack_list = new Gtk.ListBox();
    // 0 = None, 1..N map to packs[0..N-1]
    private uint selected_pack = 0;
    private Gtk.Button manage_button;
    private GLib.ListStore sticker_store = new GLib.ListStore(typeof(Dino.Stickers.StickerItem));
    private Gtk.GridView grid;
    private Gtk.ScrolledWindow scroller = new Gtk.ScrolledWindow();
    private Gtk.Stack content_stack = new Gtk.Stack();
    private Gtk.Label empty_label = new Gtk.Label("");

    private Gee.List<Dino.Stickers.StickerPack> packs = new ArrayList<Dino.Stickers.StickerPack>();

    private uint populate_generation = 0;

    private const int THUMB_SIZE = 48;
    private const int THUMB_CACHE_LIMIT = 256;

    private static bool is_supported_raster_sticker_source(string source_path, string? media_type) {
        string lower_path = source_path.down();
        if (lower_path.has_suffix(".svg") || lower_path.has_suffix(".svgz")) {
            return false;
        }

        if (media_type != null && media_type != "") {
            string mt = media_type.down();
            // Be conservative: avoid SVG and only allow common raster formats.
            if (mt == "image/png" || mt == "image/apng" || mt == "image/jpeg" || mt == "image/jpg" || mt == "image/webp" || mt == "image/gif") {
                return true;
            }
            if (mt.has_prefix("image/svg")) {
                return false;
            }
        }

        // Best-effort fallback when mime-type is missing/incorrect.
        return lower_path.has_suffix(".png") || lower_path.has_suffix(".apng") || lower_path.has_suffix(".jpg") || lower_path.has_suffix(".jpeg") || lower_path.has_suffix(".webp") || lower_path.has_suffix(".gif");
    }

    private class ThumbJob {
        public WeakRef picture_weak;
        public Dino.Stickers.StickerItem item;
        public uint generation;
        public bool allow_decode;

        public ThumbJob(Gtk.Picture picture, Dino.Stickers.StickerItem item, uint generation, bool allow_decode) {
            this.picture_weak = WeakRef(picture);
            this.item = item;
            this.generation = generation;
            this.allow_decode = allow_decode;
        }
    }

    private GLib.AsyncQueue<ThumbJob> thumb_queue = new GLib.AsyncQueue<ThumbJob>();
    private Gee.HashMap<string, Gdk.Texture> thumb_cache = new Gee.HashMap<string, Gdk.Texture>();
    private bool thumb_worker_started = false;

    private bool popover_open = false;

    private string? current_pack_id;

    public StickerChooser(StreamInteractor stream_interactor) {
        this.stream_interactor = stream_interactor;

        this.has_arrow = true;
        // Chat input sits at the bottom; prefer opening upwards.
        this.position = Gtk.PositionType.TOP;

        // Allow dismissing by clicking outside of the popover.
        this.autohide = true;
        this.focusable = true;

        this.closed.connect(() => {
            popover_open = false;
            cancel_population();
        });

        // Track real visibility (MenuButton drives popup/popdown).
        this.notify["visible"].connect(() => {
            popover_open = this.visible;
            if (!popover_open) {
                cancel_population();
                return;
            }

            // If we became visible and are already rooted, ensure content is ready.
            if (this.get_root() != null) {
                if (needs_reload) {
                    reload();
                } else {
                    refresh_grid();
                }
            }
            
            // Ensure the popover has focus so it can capture outside clicks for autohide.
            Idle.add(() => {
                if (this.visible) this.grab_focus();
                return false;
            });
        });

        // `set_open(true)` can be triggered before the popover is actually attached to a root
        // (depending on MenuButton timing). Only start heavy work once we have a root.
        this.notify["root"].connect(() => {
            if (this.visible && this.get_root() != null) {
                if (needs_reload) {
                    reload();
                } else {
                    refresh_grid();
                }
            }
        });

        ensure_thumb_worker();

        // Pack selector: use a MenuButton+Popover+ListBox instead of Gtk.DropDown.
        pack_label.xalign = 0.0f;
        pack_label.ellipsize = Pango.EllipsizeMode.END;

        pack_button = new Gtk.MenuButton();
        pack_button.add_css_class("flat");
        pack_button.hexpand = true;
        pack_button.set_child(pack_label);

        // Configure pack popover.
        pack_popover.has_arrow = true;
        pack_popover.autohide = true;

        pack_list.selection_mode = Gtk.SelectionMode.SINGLE;
        pack_list.activate_on_single_click = true;
        pack_list.row_activated.connect((row) => {
            on_pack_row_activated(row);
        });

        var pack_scroller = new Gtk.ScrolledWindow();
        pack_scroller.propagate_natural_width = true;
        pack_scroller.propagate_natural_height = false;
        pack_scroller.min_content_height = 220;
        pack_scroller.set_child(pack_list);
        pack_popover.set_child(pack_scroller);

        pack_button.set_popover(pack_popover);

        manage_button = new Gtk.Button.from_icon_name("emblem-system-symbolic");
        manage_button.add_css_class("flat");
        manage_button.tooltip_text = _("Manage Sticker Packs");
        manage_button.clicked.connect(open_manager);

        var close_button = new Gtk.Button.from_icon_name("window-close-symbolic");
        close_button.add_css_class("flat");
        close_button.tooltip_text = _("Close");
        close_button.clicked.connect(() => this.popdown());

        header_box.hexpand = true;
        header_box.append(pack_button);
        header_box.append(manage_button);
        header_box.append(close_button);

        var factory = new Gtk.SignalListItemFactory();
        factory.setup.connect((obj) => {
            var list_item = obj as Gtk.ListItem;
            if (list_item == null) return;
            var btn = new StickerButton(this);
            list_item.child = btn;
        });
        factory.bind.connect((obj) => {
            var list_item = obj as Gtk.ListItem;
            if (list_item == null) return;
            var btn = list_item.child as StickerButton;
            if (btn == null) return;
            var it = list_item.get_item() as Dino.Stickers.StickerItem;
            btn.bind_item(it, populate_generation);
        });
        factory.unbind.connect((obj) => {
            var list_item = obj as Gtk.ListItem;
            if (list_item == null) return;
            var btn = list_item.child as StickerButton;
            if (btn == null) return;
            btn.unbind_item();
        });

        var selection = new Gtk.NoSelection(sticker_store);
        grid = new Gtk.GridView(selection, factory);
        grid.max_columns = 8;
        grid.min_columns = 4;

        scroller.hexpand = true;
        scroller.vexpand = true;
        // Ensure the popover doesn't shrink to one-column layout.
        scroller.propagate_natural_width = false;
        scroller.propagate_natural_height = false;
        scroller.min_content_width = 420;
        scroller.min_content_height = 260;
        scroller.set_child(grid);

        empty_label.wrap = true;
        empty_label.justify = Gtk.Justification.CENTER;

        content_stack.hexpand = true;
        content_stack.vexpand = true;
        content_stack.hhomogeneous = false;
        content_stack.vhomogeneous = false;
        content_stack.add_named(scroller, "grid");
        content_stack.add_named(empty_label, "empty");

        root_box.margin_top = 8;
        root_box.margin_bottom = 8;
        root_box.margin_start = 8;
        root_box.margin_end = 8;

        root_box.append(header_box);
        root_box.append(content_stack);

        this.set_child(root_box);
    }

    public void set_conversation(Conversation? conversation) {
        this.conversation = conversation;
        needs_reload = true;

        // Avoid doing heavy pack reload on every chat switch.
        // Only reload when the user actually opens the popover (or if it is already open).
        if (this.visible && this.get_root() != null) {
            reload();
        } else {
            cancel_population();
            clear_sticker_store();
            content_stack.visible_child_name = "empty";

            // Avoid showing a stale pack selection from a previous conversation.
            selected_pack = 0;
            update_pack_label();
            select_pack_row(selected_pack);
            current_pack_id = null;
        }
    }

    public void set_open(bool open) {
        if (popover_open == open) return;
        popover_open = open;
        if (!popover_open) {
            cancel_population();
            return;
        }
        if (this.get_root() != null) {
            if (needs_reload) {
                reload();
            } else {
                refresh_grid();
            }
        }
    }

    private void cancel_population() {
        populate_generation++;
        // Drop queued thumbnail work; generation check also prevents stale UI updates.
        drain_thumb_queue();
    }

    private void clear_sticker_store() {
        while (sticker_store.get_n_items() > 0) {
            sticker_store.remove(0);
        }
    }

    private void ensure_thumb_worker() {
        if (thumb_worker_started) return;
        thumb_worker_started = true;

        new Thread<void*>("sticker-thumb-worker", () => {
            while (true) {
                ThumbJob job = thumb_queue.pop();
                var stickers = stream_interactor.get_module<Dino.Stickers>(Dino.Stickers.IDENTITY);

                // Decode/scaling can be expensive (especially animated WebP). Do it off the UI thread.
                Pixbuf? pixbuf = null;
                try {
                    if (job.allow_decode) {
                        Bytes? bytes = stickers.get_thumbnail_bytes_for_item(job.item);
                        if (bytes != null) {
                            var stream = new MemoryInputStream.from_data(bytes.get_data(), null);
                            pixbuf = new Pixbuf.from_stream(stream);
                        } else {
                            // Fallback to source if thumb not available (yet)
                            bytes = stickers.get_sticker_bytes(job.item);
                            if (bytes != null) {
                                var stream = new MemoryInputStream.from_data(bytes.get_data(), null);
                                pixbuf = new Pixbuf.from_stream_at_scale(stream, THUMB_SIZE, THUMB_SIZE, true);
                                pixbuf = pixbuf.apply_embedded_orientation();
                            }
                        }
                    }
                } catch (Error e) {
                    pixbuf = null;
                }

                var path = job.item.local_path; // Use local path as cache key
                var gen = job.generation;

                Idle.add(() => {
                    // Only apply if still relevant for the current visible grid.
                    if (gen != populate_generation) return false;
                    if (!popover_open || this.get_root() == null) return false;

                    Gtk.Picture? picture = (Gtk.Picture?) job.picture_weak.get();
                    if (picture == null) return false;

                    var expected_source = picture.get_data<string>("thumb_source");
                    if (expected_source == null || expected_source == "" || expected_source != job.item.local_path) {
                        return false;
                    }

                    if (thumb_cache.has_key(path)) {
                        picture.paintable = thumb_cache[path];
                        return false;
                    }

                    if (pixbuf != null) {
                        var tex = Gdk.Texture.for_pixbuf(pixbuf);
                        thumb_cache[path] = tex;
                        if (thumb_cache.size > THUMB_CACHE_LIMIT) {
                            thumb_cache.clear();
                        }
                        picture.paintable = tex;
                    } else {
                        // Avoid triggering a second decode on the UI thread.
                        picture.paintable = null;
                        picture.file = null;
                    }
                    return false;
                });

                // Throttle to keep the UI smooth on slower machines.
                Thread.usleep(30 * 1000);
            }
        });
    }

    private void drain_thumb_queue() {
        ThumbJob? job;
        while ((job = thumb_queue.try_pop()) != null) {
        }
    }

    private void reload() {
        needs_reload = false;

        cancel_population();
        clear_sticker_store();
        content_stack.visible_child_name = "empty";
        clear_pack_list();

        if (conversation == null) return;

        var app = Dino.Application.get_default();
        if (!app.settings.stickers_enabled) return;

        var stickers = stream_interactor.get_module<Dino.Stickers>(Dino.Stickers.IDENTITY);
        if (stickers == null) {
            empty_label.label = _("Stickers are unavailable");
            return;
        }

        packs = stickers.get_packs(conversation.account);

        // Populate pack list: first "None", then packs.
        append_pack_row(_("None"), null);
        foreach (var p in packs) {
            string label = p.name != null && p.name != "" ? p.name : p.pack_id;
            append_pack_row(label, p.pack_id);
        }



        // Default to "None" on startup/reload (avoid showing stale pack selection).
        selected_pack = 0;
        current_pack_id = null;
        update_pack_label();
        select_pack_row(selected_pack);

        if (packs.size == 0) {
            empty_label.label = _("No sticker packs yet.");
        } else {
            empty_label.label = _("No stickers selected");
        }

        // Ensure the visible content matches the selected pack.
        refresh_grid();
    }

    private void clear_pack_list() {
        Gtk.Widget? child = pack_list.get_first_child();
        while (child != null) {
            Gtk.Widget? next = child.get_next_sibling();
            pack_list.remove(child);
            child = next;
        }
    }

    private void append_pack_row(string label, string? pack_id) {
        var row = new Gtk.ListBoxRow();
        var lbl = new Gtk.Label(label);
        lbl.xalign = 0.0f;
        lbl.margin_top = 6;
        lbl.margin_bottom = 6;
        lbl.margin_start = 10;
        lbl.margin_end = 10;
        row.set_child(lbl);
        row.set_data<string>("pack_id", pack_id != null ? pack_id : "");
        pack_list.append(row);
    }

    private void select_pack_row(uint index) {
        // index maps to row position (0..N). Best-effort.
        int i = 0;
        for (Gtk.Widget? child = pack_list.get_first_child(); child != null; child = child.get_next_sibling()) {
            var row = child as Gtk.ListBoxRow;
            if (row == null) continue;
            if (i == (int) index) {
                pack_list.select_row(row);
                break;
            }
            i++;
        }
    }

    private void update_pack_label() {
        if (selected_pack == 0) {
            pack_label.label = _("None");
            return;
        }
        uint pack_index = selected_pack - 1;
        if (pack_index >= packs.size) {
            pack_label.label = _("None");
            return;
        }
        var p = packs[(int) pack_index];
        pack_label.label = (p.name != null && p.name != "") ? p.name : p.pack_id;
    }

    private void on_pack_row_activated(Gtk.ListBoxRow row) {
        // Determine row index.
        int idx = row.get_index();
        if (idx < 0) return;

        selected_pack = (uint) idx;
        update_pack_label();

        // Close pack chooser first.
        pack_popover.popdown();

        refresh_grid();

        // Restore focus to our popover so outside click can dismiss it.
        Idle.add(() => {
            if (this.visible) this.grab_focus();
            return false;
        });
    }

    private void open_manager() {
        if (conversation == null) return;

        Gtk.Window? parent = this.get_root() as Gtk.Window;
        this.popdown();

        var dialog = new Dino.Ui.StickerManagerDialog(stream_interactor, conversation);
        if (parent != null) dialog.set_transient_for(parent);
        dialog.present();

        // Reload when the manager is closed, in case packs were added/removed.
        dialog.close_request.connect(() => {
            dialog.destroy();
            reload();
            return true;
        });
    }

    private void refresh_grid() {
        // Avoid heavy sticker decoding/scaling work unless the user actually opened the popover.
        // Note: changing pack_dropdown.selected triggers refresh_grid via notify.
        if (!popover_open || this.get_root() == null) {
            cancel_population();
            clear_sticker_store();
            content_stack.visible_child_name = "empty";
            return;
        }

        cancel_population();
        clear_sticker_store();
        content_stack.visible_child_name = "empty";
        if (conversation == null) return;

        if (pack_list.get_first_child() == null) return;

        if (selected_pack == 0) {
            empty_label.label = _("No stickers selected");
            current_pack_id = null;
            return;
        }

        uint pack_index = selected_pack - 1;
        if (pack_index >= packs.size) return;

        string pack_id = packs[(int) pack_index].pack_id;
        current_pack_id = pack_id;

        var stickers = stream_interactor.get_module<Dino.Stickers>(Dino.Stickers.IDENTITY);
        if (stickers == null) return;

        var items = stickers.get_items(conversation.account, pack_id);
        if (items.size == 0) {
            empty_label.label = _("No stickers in this pack");
            return;
        }

        content_stack.visible_child_name = "grid";

        // GridView virtualizes items: only visible rows are created/bound.
        foreach (var it in items) {
            sticker_store.append(it);
        }
    }



    private void on_sticker_clicked(Dino.Stickers.StickerItem? item) {
        if (item == null) return;
        if (conversation == null) return;
        if (current_pack_id == null) return;

        var stickers_click = stream_interactor.get_module<Dino.Stickers>(Dino.Stickers.IDENTITY);
        if (stickers_click == null) return;
        stickers_click.send_sticker.begin(conversation, current_pack_id, item, (obj, res) => {
            try {
                stickers_click.send_sticker.end(res);
            } catch (Error e) {
                // best effort
            }
        });
        this.popdown();
    }

    private class StickerButton : Gtk.Button {
        private weak StickerChooser? chooser;
        private Gtk.Picture picture = new Gtk.Picture();
        private Dino.Stickers.StickerItem? item;

        public StickerButton(StickerChooser chooser) {
            this.chooser = chooser;
            this.add_css_class("flat");

            // Add spacing between grid cells (GridView spacing isn't available in our gtk4.vapi).
            this.margin_top = 3;
            this.margin_bottom = 3;
            this.margin_start = 3;
            this.margin_end = 3;

            picture.can_shrink = true;
            picture.content_fit = ContentFit.CONTAIN;
            picture.width_request = THUMB_SIZE;
            picture.height_request = THUMB_SIZE;
            this.child = picture;

            this.clicked.connect(() => {
                var c = this.chooser;
                if (c == null) return;
                c.on_sticker_clicked(item);
            });
        }

        public void bind_item(Dino.Stickers.StickerItem? it, uint generation) {
            item = it;
            picture.paintable = null;
            picture.file = null;

            if (chooser == null) return;
            if (it == null || it.local_path == null) return;

            // Track current requested path to avoid stale updates when GTK recycles list items.
            picture.set_data<string>("thumb_source", it.local_path);

            if (chooser.thumb_cache.has_key(it.local_path)) {
                picture.paintable = chooser.thumb_cache[it.local_path];
                return;
            }

            // Avoid decoding SVG/non-raster stickers (gdk-pixbuf SVG loader is unstable in some runtimes).
            if (!StickerChooser.is_supported_raster_sticker_source(it.local_path, it.media_type)) {
                return;
            }

            chooser.thumb_queue.push(new ThumbJob(picture, it, generation, true));
        }

        public void unbind_item() {
            item = null;
            picture.set_data<string>("thumb_source", "");
            picture.paintable = null;
            picture.file = null;
        }
    }
}

}
