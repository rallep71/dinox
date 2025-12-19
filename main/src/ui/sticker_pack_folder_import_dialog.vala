using Gtk;
using Adw;
using Dino.Entities;
using Xmpp;

namespace Dino.Ui {

public class StickerPackFolderImportDialog : Adw.Window {
    private StreamInteractor stream_interactor;
    private Account account;
    private string folder_path;

    private bool busy = false;

    private Label title_label = new Label("") { xalign = 0.0f, wrap = true };
    private Label summary_label = new Label("") { xalign = 0.0f, wrap = true, selectable = true };
    private Spinner spinner = new Spinner() { spinning = false, visible = false };

    private Button cancel_button = new Button.with_label(_("Cancel"));
    private Button local_button = new Button.with_label(_("Local only"));
    private Button publish_button = new Button.with_label(_("Publish & copy link"));

    private Button copy_button = new Button.with_label(_("Copy Share URI")) { sensitive = false };
    private Button close_button = new Button.with_label(_("Close"));

    private Gtk.Box actions_box = new Gtk.Box(Orientation.VERTICAL, 6) { halign = Align.FILL, hexpand = true };
    private Gtk.Box result_box = new Gtk.Box(Orientation.VERTICAL, 6) { halign = Align.FILL, hexpand = true, visible = false };

    private string? share_uri;

    public signal void pack_created(string pack_name);

    public StickerPackFolderImportDialog(StreamInteractor stream_interactor, Account account, string folder_path) {
        this.stream_interactor = stream_interactor;
        this.account = account;
        this.folder_path = folder_path;

        this.title = _("Create sticker pack");
        this.default_width = 460;
        this.default_height = 240;

        var box = new Gtk.Box(Orientation.VERTICAL, 12);
        box.margin_top = 12;
        box.margin_bottom = 12;
        box.margin_start = 12;
        box.margin_end = 12;

        // Adw.Window does not support gtk_window_set_titlebar(); keep header inside content.
        var header = new Adw.HeaderBar();

        // Title line with spinner (spinner shows immediately when starting).
        var title_row = new Gtk.Box(Orientation.HORIZONTAL, 8);
        spinner.valign = Align.START;
        title_row.append(spinner);
        title_row.append(title_label);

        title_label.label = _("Create sticker pack");
        summary_label.label = _("Do you want to keep this pack local, or also publish it so you can share an xmpp: link?");

        publish_button.add_css_class("suggested-action");

        // Stack actions under each other (old dialog style).
        cancel_button.halign = Align.FILL;
        cancel_button.hexpand = true;
        local_button.halign = Align.FILL;
        local_button.hexpand = true;
        publish_button.halign = Align.FILL;
        publish_button.hexpand = true;
        copy_button.halign = Align.FILL;
        copy_button.hexpand = true;
        close_button.halign = Align.FILL;
        close_button.hexpand = true;

        actions_box.append(publish_button);
        actions_box.append(local_button);
        actions_box.append(cancel_button);

        result_box.append(copy_button);
        result_box.append(close_button);

        box.append(header);
        box.append(title_row);
        box.append(summary_label);
        box.append(new Gtk.Separator(Orientation.HORIZONTAL));
        box.append(actions_box);
        box.append(result_box);

        // Keep the dialog width pleasant.
        var clamp = new Adw.Clamp() { maximum_size = 520, tightening_threshold = 520, child = box, halign = Align.FILL };
        this.content = clamp;

        cancel_button.clicked.connect(() => this.close());
        close_button.clicked.connect(() => this.close());
        copy_button.clicked.connect(() => {
            if (share_uri == null || share_uri == "") return;
            var clipboard = this.get_display().get_clipboard();
            clipboard.set_text(share_uri);
        });

        local_button.clicked.connect(() => start_create(false));
        publish_button.clicked.connect(() => start_create(true));
    }

    private void set_busy(bool busy) {
        this.busy = busy;

        spinner.visible = busy;
        spinner.spinning = busy;

        cancel_button.sensitive = !busy;
        local_button.sensitive = !busy;
        publish_button.sensitive = !busy;

        copy_button.sensitive = !busy && share_uri != null && share_uri != "";
        close_button.sensitive = !busy;
    }

    private void show_done_state(string title, string body, bool show_copy) {
        title_label.label = title;
        summary_label.label = body;

        actions_box.visible = false;
        result_box.visible = true;

        copy_button.visible = show_copy;
        copy_button.sensitive = show_copy && share_uri != null && share_uri != "";
    }

    private void start_create(bool publish) {
        if (busy) return;

        // Show feedback immediately; then start the async operation on the next
        // main-loop iteration so the spinner actually renders before heavy work.
        set_busy(true);
        title_label.label = _("Creating…");
        summary_label.label = "";
        share_uri = null;
        copy_button.sensitive = false;
        actions_box.visible = true;
        result_box.visible = false;

        Idle.add(() => {
            create.begin(publish);
            return false;
        });
    }

    private async void create(bool publish) {
        try {
            var stickers = stream_interactor.get_module(Dino.Stickers.IDENTITY);
            if (stickers == null) throw new Dino.StickerError.NOT_CONNECTED("Stickers module unavailable");

            string uri = yield stickers.create_pack_from_folder(account, folder_path, publish);
            share_uri = (uri != null && uri != "") ? uri : null;

            // Best-effort: the pack name tends to be the folder basename.
            pack_created(Path.get_basename(folder_path));

            if (publish && share_uri != null) {
                var clipboard = this.get_display().get_clipboard();
                clipboard.set_text(share_uri);
                show_done_state(_("Sticker pack published"), _("Share link (copied to clipboard):\n%s").printf(share_uri), true);
            } else {
                show_done_state(_("Sticker pack created"), _("The sticker pack is now available locally."), false);
            }
        } catch (Error e) {
            show_done_state(_("Failed to create sticker pack"), e.message, false);
        } finally {
            set_busy(false);
        }
    }
}

}
