/*
 * Copyright (C) 2025 Ralf Peter <dinox@handwerker.jetzt>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

using Gtk;
using Dino.Entities;
using Xmpp;

namespace Dino.Ui {

public class StickerPackImportDialog : Adw.Window {
    private StreamInteractor stream_interactor;

    private bool preview_started = false;
    private bool accounts_initialized = false;

    private void run_after_next_frame(owned GLib.SourceFunc fn) {
        uint tick_id = 0;
        tick_id = this.add_tick_callback((widget, frame_clock) => {
            widget.remove_tick_callback(tick_id);
            fn();
            return Source.REMOVE;
        });
    }

    private AccountComboBox account_combo = new AccountComboBox();
    private Label title_label = new Label("") { xalign = 0.0f, wrap = true };
    private Label summary_label = new Label("") { xalign = 0.0f, wrap = true };
    private Gtk.Spinner spinner = new Gtk.Spinner() { spinning = false, visible = true };
    private Button import_button = new Button.with_label(_("Import")) { sensitive = false };
    private Button copy_uri_button = new Button.with_label(_("Copy Share URI")) { sensitive = false };

    private Jid source_jid;
    private string node;
    private string item;

    private Dino.Stickers.StickerPack? pack;

    public StickerPackImportDialog(StreamInteractor stream_interactor, Jid source_jid, string node, string item) {
        this.stream_interactor = stream_interactor;
        this.source_jid = source_jid;
        this.node = node;
        this.item = item;

        this.title = _("Import Sticker Pack");
        this.default_width = 420;
        this.default_height = 200;

        var box = new Gtk.Box(Orientation.VERTICAL, 12);
        box.margin_top = 12;
        box.margin_bottom = 12;
        box.margin_start = 12;
        box.margin_end = 12;

        // Important for UX: do NOT initialize accounts here.
        // `stream_interactor.get_accounts()` can be slow and would delay showing
        // the window (including the spinner) by several seconds.
        account_combo.sensitive = false;
        box.append(account_combo);

        box.append(spinner);
        box.append(title_label);
        box.append(summary_label);

        var buttons = new Gtk.Box(Orientation.HORIZONTAL, 6) { halign = Align.END };
        buttons.append(copy_uri_button);
        buttons.append(import_button);
        box.append(buttons);

        this.content = box;

        import_button.clicked.connect(start_import);
        copy_uri_button.clicked.connect(copy_share_uri);

        // Load preview (best-effort). Start only after the window is mapped so
        // the UI (spinner + window) can actually render before any synchronous
        // work in the async call chain blocks the main loop.
        this.map.connect(() => {
            if (preview_started) return;
            preview_started = true;

            // Show busy UI immediately and wait for the next frame so it is
            // actually rendered before any potentially blocking work starts.
            spinner.spinning = true;
            title_label.label = _("Loading…");
            summary_label.label = "";

            run_after_next_frame(() => {
                initial_load.begin();
                return Source.REMOVE;
            });
        });
    }

    private async void initial_load() {
        if (!accounts_initialized) {
            account_combo.initialize(stream_interactor);
            accounts_initialized = true;
            account_combo.sensitive = true;
        }

        // Let the combobox render its content before starting network preview.
        run_after_next_frame(() => {
            preview.begin();
            return Source.REMOVE;
        });
    }

    private async void yield_to_mainloop() {
        Idle.add(() => {
            yield_to_mainloop.callback();
            return Source.REMOVE;
        });
        yield;
    }

    private void start_import() {
        // Make the busy UI visible first, then start the async work on the next
        // main-loop iteration so the spinner can render immediately.
        spinner.spinning = true;
        import_button.sensitive = false;
        copy_uri_button.sensitive = false;
        title_label.label = _("Importing…");
        summary_label.label = "";

        // Wait for a rendered frame so the spinner is visible before starting
        // any potentially blocking work.
        run_after_next_frame(() => {
            var account = account_combo.active_account;
            if (account == null) {
                title_label.label = _("No account available");
                spinner.spinning = false;
                return Source.REMOVE;
            }
            do_import.begin(account);
            return Source.REMOVE;
        });
    }

    private async void preview() {
        spinner.spinning = true;
        title_label.label = _("Loading…");
        summary_label.label = "";

        import_button.sensitive = false;
        copy_uri_button.sensitive = false;

        // Ensure the busy UI is rendered before doing anything that might block.
        yield yield_to_mainloop();

        var account = account_combo.active_account;
        if (account == null) {
            title_label.label = _("No account available");
            spinner.spinning = false;
            return;
        }

        try {
            var stickers = stream_interactor.get_module(Dino.Stickers.IDENTITY);
            if (stickers == null) throw new Dino.StickerError.NOT_CONNECTED("Stickers module unavailable");
            pack = yield stickers.preview_pack(account, source_jid, node, item);
            title_label.label = pack.name ?? pack.pack_id;
            summary_label.label = pack.summary ?? "";
            import_button.sensitive = true;
            copy_uri_button.sensitive = true;
        } catch (Error e) {
            title_label.label = _("Failed to import sticker pack");
            summary_label.label = e.message;
        } finally {
            spinner.spinning = false;
        }
    }

    private async void do_import(Account account) {
        // Ensure the busy UI is rendered before doing anything that might block.
        yield yield_to_mainloop();

        try {
            var stickers = stream_interactor.get_module(Dino.Stickers.IDENTITY);
            if (stickers == null) throw new Dino.StickerError.NOT_CONNECTED("Stickers module unavailable");
            pack = yield stickers.import_pack(account, source_jid, node, item);
            this.close();
        } catch (Error e) {
            title_label.label = _("Failed to import sticker pack");
            summary_label.label = e.message;
            import_button.sensitive = true;
            copy_uri_button.sensitive = pack != null;
        } finally {
            spinner.spinning = false;
        }
    }

    private void copy_share_uri() {
        var account = account_combo.active_account;
        if (account == null || pack == null) return;

        string share_jid = account.bare_jid.to_string();
        string node_enc = Uri.escape_string(Xmpp.Xep.Stickers.NS_URI, null, false);
        string item_enc = Uri.escape_string(pack.pack_id, null, false);
        string uri = @"xmpp:$(share_jid)?pubsub;action=retrieve;node=$(node_enc);item=$(item_enc)";

        var clipboard = this.get_display().get_clipboard();
        clipboard.set_text(uri);
    }
}

}
