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
    private Gtk.Button close_button;
    private Gtk.Button import_button = new Gtk.Button.with_label(_("Import…"));
    private Gtk.Button folder_button = new Gtk.Button.with_label(_("Folder…"));
    private Gtk.Button publish_button = new Gtk.Button.with_label(_("Publish"));
    private Gtk.Button remove_button = new Gtk.Button.with_label(_("Remove"));
    private Gtk.Spinner busy_spinner = new Gtk.Spinner() { spinning = false, visible = false };
    private GLib.ListStore sticker_store = new GLib.ListStore(typeof(Dino.Stickers.StickerItem));
    private Gtk.GridView grid;
    private Gtk.ScrolledWindow scroller = new Gtk.ScrolledWindow();
    private Gtk.Stack content_stack = new Gtk.Stack();
    private Gtk.Label empty_label = new Gtk.Label("");

    private Gtk.Box import_box = new Gtk.Box(Orientation.VERTICAL, 8);
    private Gtk.Label import_hint_label = new Gtk.Label("");
    private Gtk.Entry import_entry = new Gtk.Entry();
    private Gtk.Label import_error_label = new Gtk.Label("");

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
            if (mt == "image/png" || mt == "image/jpeg" || mt == "image/jpg" || mt == "image/webp" || mt == "image/gif") {
                return true;
            }
            if (mt.has_prefix("image/svg")) {
                return false;
            }
        }

        // Best-effort fallback when mime-type is missing/incorrect.
        return lower_path.has_suffix(".png") || lower_path.has_suffix(".jpg") || lower_path.has_suffix(".jpeg") || lower_path.has_suffix(".webp") || lower_path.has_suffix(".gif");
    }

    private class ThumbJob {
        public WeakRef picture_weak;
        public string source_path;
        public string? thumb_path;
        public uint generation;
        public bool allow_decode;

        public ThumbJob(Gtk.Picture picture, string source_path, string? thumb_path, uint generation, bool allow_decode) {
            this.picture_weak = WeakRef(picture);
            this.source_path = source_path;
            this.thumb_path = thumb_path;
            this.generation = generation;
            this.allow_decode = allow_decode;
        }
    }

    private GLib.AsyncQueue<ThumbJob> thumb_queue = new GLib.AsyncQueue<ThumbJob>();
    private Gee.HashMap<string, Gdk.Texture> thumb_cache = new Gee.HashMap<string, Gdk.Texture>();
    private bool thumb_worker_started = false;

    private bool popover_open = false;

    private bool busy = false;

    private string? current_pack_id;

    private string? pending_select_pack_name;

    private void set_busy_state(bool busy, string? publish_label = null, string? remove_label = null, string? folder_label = null) {
        this.busy = busy;

        busy_spinner.visible = busy;
        busy_spinner.spinning = busy;

        pack_button.sensitive = !busy;
        import_button.sensitive = !busy;
        folder_button.sensitive = !busy;
        publish_button.sensitive = !busy;
        remove_button.sensitive = !busy;
        // Allow closing the popover while background operations run.
        close_button.sensitive = true;

        if (busy) {
            if (publish_label != null) publish_button.label = publish_label;
            if (remove_label != null) remove_button.label = remove_label;
            if (folder_label != null) folder_button.label = folder_label;
        } else {
            publish_button.label = _("Publish");
            remove_button.label = _("Remove");
            folder_button.label = _("Folder…");
            import_button.label = _("Import…");
            update_publish_button_state();
            update_remove_button_state();
        }
    }

    public StickerChooser(StreamInteractor stream_interactor) {
        this.stream_interactor = stream_interactor;

        this.has_arrow = true;
        // Chat input sits at the bottom; prefer opening upwards.
        this.position = Gtk.PositionType.TOP;

        // Allow dismissing by clicking outside of the popover.
        // User-reported: only Escape worked.
        this.autohide = true;

        this.closed.connect(() => {
            popover_open = false;
            cancel_population();
            reset_inline_import_ui();
        });

        // Track real visibility (MenuButton drives popup/popdown).
        this.notify["visible"].connect(() => {
            popover_open = this.visible;
            if (!popover_open) {
                cancel_population();
                reset_inline_import_ui();
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
        // Gtk.DropDown uses an internal popover/grab that (in this app) breaks first-time
        // outside-click dismissal of the parent StickerChooser popover.
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

        import_button.add_css_class("flat");
        import_button.clicked.connect(show_inline_import_ui);

        folder_button.add_css_class("flat");
        folder_button.clicked.connect(open_folder_import);

        publish_button.add_css_class("flat");
        publish_button.sensitive = false;
        publish_button.clicked.connect(on_publish_clicked);

        remove_button.add_css_class("flat");
        remove_button.sensitive = false;
        remove_button.clicked.connect(on_remove_clicked);

        close_button = new Gtk.Button.from_icon_name("window-close-symbolic");
        close_button.add_css_class("flat");
        close_button.tooltip_text = _("Close");
        close_button.clicked.connect(() => {
            this.popdown();
        });

        header_box.hexpand = true;
        header_box.append(pack_button);
        header_box.append(import_button);
        header_box.append(folder_button);
        header_box.append(publish_button);
        header_box.append(remove_button);
        header_box.append(busy_spinner);
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
        // Important for UX: when switching to the xmpp: import view, don't keep
        // the large grid height; size to the visible child instead.
        content_stack.hhomogeneous = false;
        content_stack.vhomogeneous = false;
        content_stack.add_named(scroller, "grid");
        content_stack.add_named(empty_label, "empty");

        // Compact import view: minimal vertical padding around the entry.
        import_box.hexpand = true;
        import_box.vexpand = false;
        import_box.halign = Align.FILL;
        import_box.valign = Align.START;
        import_box.margin_top = 12;
        import_box.margin_bottom = 12;

        import_hint_label.label = _("Paste an xmpp: sticker pack link and press Enter.");
        import_hint_label.wrap = true;
        import_hint_label.justify = Gtk.Justification.CENTER;

        import_entry.placeholder_text = _("xmpp:…");
        import_entry.width_chars = 40;
        import_entry.activates_default = true;

        import_error_label.wrap = true;
        import_error_label.justify = Gtk.Justification.CENTER;
        import_error_label.visible = false;

        import_box.append(import_hint_label);
        import_box.append(import_entry);
        import_box.append(import_error_label);

        content_stack.add_named(import_box, "import");
        content_stack.visible_child_name = "empty";

        root_box.margin_top = 8;
        root_box.margin_bottom = 8;
        root_box.margin_start = 8;
        root_box.margin_end = 8;

        root_box.append(header_box);
        root_box.append(content_stack);

        this.set_child(root_box);

        import_entry.activate.connect(() => {
            start_import_from_inline_entry();
        });
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
            update_remove_button_state();
            update_publish_button_state();
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

                // Decode/scaling can be expensive (especially animated WebP). Do it off the UI thread.
                Pixbuf? pixbuf = null;
                try {
                    if (job.allow_decode) {
                        if (job.thumb_path != null && job.thumb_path != "" && FileUtils.test(job.thumb_path, FileTest.EXISTS)) {
                            pixbuf = new Pixbuf.from_file(job.thumb_path);
                        } else {
                            pixbuf = new Pixbuf.from_file_at_scale(job.source_path, THUMB_SIZE, THUMB_SIZE, true);
                            pixbuf = pixbuf.apply_embedded_orientation();
                            if (job.thumb_path != null && job.thumb_path != "") {
                                try {
                                    DirUtils.create_with_parents(Path.get_dirname(job.thumb_path), 0700);
                                    pixbuf.save(job.thumb_path, "png");
                                } catch (Error e) {
                                    // best effort
                                }
                            }
                        }
                    }
                } catch (Error e) {
                    pixbuf = null;
                }

                var path = (job.thumb_path != null && job.thumb_path != "" && FileUtils.test(job.thumb_path, FileTest.EXISTS)) ? job.thumb_path : job.source_path;
                var gen = job.generation;

                Idle.add(() => {
                    // Only apply if still relevant for the current visible grid.
                    if (gen != populate_generation) return false;
                    if (!popover_open || this.get_root() == null) return false;

                    Gtk.Picture? picture = (Gtk.Picture?) job.picture_weak.get();
                    if (picture == null) return false;

                    var expected_source = picture.get_data<string>("thumb_source");
                    if (expected_source == null || expected_source == "" || expected_source != job.source_path) {
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

        var stickers = stream_interactor.get_module(Dino.Stickers.IDENTITY);
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

        update_remove_button_state();
        update_publish_button_state();

        if (pending_select_pack_name != null) {
            for (int i = 0; i < packs.size; i++) {
                if (packs[i].name != null && packs[i].name == pending_select_pack_name) {
                    selected_pack = (uint) (i + 1);
                    pending_select_pack_name = null;
                    update_pack_label();
                    select_pack_row(selected_pack);
                    refresh_grid();
                    return;
                }
            }
            pending_select_pack_name = null;
        }

        // Default to "None" on startup/reload (avoid showing stale pack selection).
        selected_pack = 0;
        current_pack_id = null;
        update_pack_label();
        select_pack_row(selected_pack);

        if (packs.size == 0) {
            empty_label.label = _("No sticker packs yet. Use Import… to add one.");
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

    private void open_folder_import() {
        if (conversation == null) return;

        Gtk.Window? parent = this.get_root() as Gtk.Window;
        // Close the popover before opening dialogs; otherwise it keeps an input grab.
        this.popdown();
        var chooser = new Gtk.FileDialog();
        chooser.title = _("Select sticker folder");
        chooser.accept_label = _("Select");

        chooser.select_folder.begin(parent, null, (obj, res) => {
            try {
                File folder = chooser.select_folder.end(res);
                string? path = folder.get_path();
                if (path == null || path == "") return;

                var dialog = new Dino.Ui.StickerPackFolderImportDialog(stream_interactor, conversation.account, path);
                if (parent != null) dialog.set_transient_for(parent);
                dialog.hide_on_close = false;
                dialog.pack_created.connect((pack_name) => {
                    pending_select_pack_name = pack_name;
                });
                dialog.close_request.connect(() => {
                    dialog.destroy();
                    reload();
                    return true;
                });

                Idle.add(() => {
                    dialog.present();
                    return false;
                });
            } catch (Error e) {
                // ignore cancel
            }
        });
    }

    private bool try_parse_sticker_pack_uri(string uri, out Xmpp.Jid source_jid, out string node, out string item) {
        source_jid = null;
        node = "";
        item = "";

        string trimmed = uri.strip();
        if (!trimmed.has_prefix("xmpp:")) return false;

        string rest = trimmed.substring("xmpp:".length);
        int qpos = rest.index_of("?");
        if (qpos < 0) return false;

        string jid_str = rest.substring(0, qpos);
        string query_str = rest.substring(qpos + 1);
        if (jid_str == "" || query_str == "") return false;

        try {
            source_jid = new Xmpp.Jid(jid_str);
        } catch (Xmpp.InvalidJidError e) {
            return false;
        }

        string[] parts = query_str.split(";");
        if (parts.length < 2) return false;
        if (parts[0] != "pubsub") return false;

        var options = new HashMap<string, string>();
        for (int i = 1; i < parts.length; i++) {
            string p = parts[i];
            int eq = p.index_of("=");
            if (eq <= 0) continue;
            string k = p.substring(0, eq);
            string v = p.substring(eq + 1);
            options[k] = Uri.unescape_string(v);
        }

        if (!options.has_key("action") || options["action"] != "retrieve") return false;
        if (!options.has_key("node") || options["node"] != Xmpp.Xep.Stickers.NS_URI) return false;
        if (!options.has_key("item") || options["item"] == "") return false;

        node = options["node"];
        item = options["item"];
        return true;
    }

    private void reset_inline_import_ui() {
        set_inline_import_mode(false);
        import_error_label.visible = false;
        import_error_label.label = "";
        import_entry.text = "";
        if (content_stack.visible_child_name == "import") {
            content_stack.visible_child_name = "empty";
        }
    }

    private void set_inline_import_mode(bool enabled) {
        // Keep the close button available for mouse-only users.
        header_box.visible = true;
        pack_button.visible = !enabled;
        import_button.visible = !enabled;
        folder_button.visible = !enabled;
        publish_button.visible = !enabled;
        remove_button.visible = !enabled;
        close_button.visible = true;
    }

    private void show_inline_import_ui() {
        cancel_population();
        clear_sticker_store();

        set_inline_import_mode(true);
        import_error_label.visible = false;
        import_error_label.label = "";
        content_stack.visible_child_name = "import";

        // Focus the entry as soon as the popover has switched content.
        Idle.add(() => {
            import_entry.grab_focus();
            return false;
        });
    }

    private void start_import_from_inline_entry() {
        Gtk.Window? parent = this.get_root() as Gtk.Window;

        Xmpp.Jid src;
        string node;
        string item;
        if (!try_parse_sticker_pack_uri(import_entry.text, out src, out node, out item)) {
            import_error_label.label = _("Invalid sticker pack link");
            import_error_label.visible = true;
            return;
        }

        // Close the popover before presenting the window; Gtk.Popover grabs input
        // and would otherwise block interaction with the import window.
        this.popdown();

        var dialog = new Dino.Ui.StickerPackImportDialog(stream_interactor, src, node, item);
        if (parent != null) dialog.set_transient_for(parent);
        dialog.hide_on_close = false;
        dialog.close_request.connect(() => {
            dialog.destroy();
            reload();
            return true;
        });

        Idle.add(() => {
            dialog.present();
            return false;
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
            update_remove_button_state();
            update_publish_button_state();
            return;
        }

        uint pack_index = selected_pack - 1;
        if (pack_index >= packs.size) return;

        string pack_id = packs[(int) pack_index].pack_id;
        current_pack_id = pack_id;
        update_remove_button_state();
        update_publish_button_state();

        var stickers = stream_interactor.get_module(Dino.Stickers.IDENTITY);
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

    private void update_remove_button_state() {
        if (conversation == null) {
            remove_button.sensitive = false;
            return;
        }
        if (pack_list.get_first_child() == null) {
            remove_button.sensitive = false;
            return;
        }
        if (selected_pack == 0) {
            remove_button.sensitive = false;
            return;
        }
        uint pack_index = selected_pack - 1;
        remove_button.sensitive = pack_index < packs.size;
    }

    private void update_publish_button_state() {
        if (conversation == null) {
            publish_button.sensitive = false;
            return;
        }
        if (pack_list.get_first_child() == null) {
            publish_button.sensitive = false;
            return;
        }
        if (selected_pack == 0) {
            publish_button.sensitive = false;
            return;
        }
        uint pack_index = selected_pack - 1;
        publish_button.sensitive = pack_index < packs.size;
    }

    private void on_publish_clicked() {
        if (conversation == null) return;
        if (busy) return;

        if (selected_pack == 0) return;
        uint pack_index = selected_pack - 1;
        if (pack_index >= packs.size) return;

        string pack_id = packs[(int) pack_index].pack_id;

        Gtk.Window? parent = this.get_root() as Gtk.Window;
        // Close the popover so it doesn't block the result dialogs.
        this.popdown();

        set_busy_state(true, _("Publishing…"));

        var stickers = stream_interactor.get_module(Dino.Stickers.IDENTITY);
        if (stickers == null) {
            var err = new Adw.AlertDialog(_("Stickers are unavailable"), _("Stickers module unavailable"));
            err.add_response("ok", _("OK"));
            err.default_response = "ok";
            err.close_response = "ok";
            if (parent != null) err.present(parent);

            set_busy_state(false);
            return;
        }

        stickers.publish_pack.begin(conversation.account, pack_id, (obj, res) => {
            try {
                string uri = stickers.publish_pack.end(res);
                var clipboard = this.get_display().get_clipboard();
                clipboard.set_text(uri);

                var ok = new Adw.AlertDialog(_("Sticker pack published"), _("Share link copied to clipboard:\n%s").printf(uri));
                ok.add_response("ok", _("OK"));
                ok.default_response = "ok";
                ok.close_response = "ok";
                if (parent != null) ok.present(parent);

                reload();
            } catch (Error e) {
                var err = new Adw.AlertDialog(_("Failed to publish sticker pack"), e.message);
                err.add_response("ok", _("OK"));
                err.default_response = "ok";
                err.close_response = "ok";
                if (parent != null) err.present(parent);
            }

            set_busy_state(false);
        });
    }

    private void on_remove_clicked() {
        if (conversation == null) return;
        if (busy) return;

        if (selected_pack == 0) return;
        uint pack_index = selected_pack - 1;
        if (pack_index >= packs.size) return;

        string pack_id = packs[(int) pack_index].pack_id;
        string title = packs[(int) pack_index].name != null && packs[(int) pack_index].name != "" ? packs[(int) pack_index].name : pack_id;

        Gtk.Window? parent = this.get_root() as Gtk.Window;
        // Close the popover so the confirmation dialog is clickable.
        this.popdown();
        var dialog = new Adw.AlertDialog(
            _("Remove sticker pack?"),
            _("This will delete the downloaded files and remove the pack from your list: %s").printf(title)
        );
        dialog.add_response("cancel", _("Cancel"));
        dialog.add_response("remove", _("Remove"));
        dialog.set_response_appearance("remove", Adw.ResponseAppearance.DESTRUCTIVE);
        dialog.default_response = "cancel";
        dialog.close_response = "cancel";

        dialog.response.connect((response) => {
            if (response != "remove") return;
            var stickers = stream_interactor.get_module(Dino.Stickers.IDENTITY);
            if (stickers == null) return;

            // Removing can be slow (recursive delete); run it off the UI thread so we can show feedback.
            set_busy_state(true, null, _("Removing…"));
            weak StickerChooser weak_self = this;
            new Thread<void*>("remove-sticker-pack", () => {
                string? error_message = null;
                try {
                    stickers.remove_pack(conversation.account, pack_id);
                } catch (Error e) {
                    error_message = e.message;
                }

                Idle.add(() => {
                    StickerChooser? self = weak_self;
                    if (self == null) return false;
                    self.set_busy_state(false);

                    if (error_message != null) {
                        Gtk.Window? p = self.get_root() as Gtk.Window;
                        var err = new Adw.AlertDialog(_("Failed to remove sticker pack"), error_message);
                        err.add_response("ok", _("OK"));
                        err.default_response = "ok";
                        err.close_response = "ok";
                        if (p != null) err.present(p);
                    }

                    self.reload();
                    return false;
                });

                return null;
            });
        });

        if (parent != null) {
            dialog.present(parent);
        }
    }

    private void on_sticker_clicked(Dino.Stickers.StickerItem? item) {
        if (item == null) return;
        if (conversation == null) return;
        if (current_pack_id == null) return;

        var stickers_click = stream_interactor.get_module(Dino.Stickers.IDENTITY);
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

            string? disk_thumb = Dino.Stickers.get_thumbnail_path_for_item(it);
            if (disk_thumb != null && disk_thumb != "" && FileUtils.test(disk_thumb, FileTest.EXISTS)) {
                if (chooser.thumb_cache.has_key(disk_thumb)) {
                    picture.paintable = chooser.thumb_cache[disk_thumb];
                    return;
                }
            } else {
                disk_thumb = null;
            }

            // Avoid decoding SVG/non-raster stickers (gdk-pixbuf SVG loader is unstable in some runtimes).
            if (!StickerChooser.is_supported_raster_sticker_source(it.local_path, it.media_type)) {
                return;
            }

            chooser.thumb_queue.push(new ThumbJob(picture, it.local_path, Dino.Stickers.get_thumbnail_path_for_item(it), generation, true));
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
