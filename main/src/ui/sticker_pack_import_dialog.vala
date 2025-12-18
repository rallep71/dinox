using Gtk;
using Dino.Entities;
using Xmpp;

namespace Dino.Ui {

public class StickerPackImportDialog : Adw.Window {
    private StreamInteractor stream_interactor;

    private AccountComboBox account_combo = new AccountComboBox();
    private Label title_label = new Label("") { xalign = 0.0f, wrap = true };
    private Label summary_label = new Label("") { xalign = 0.0f, wrap = true };
    private Spinner spinner = new Spinner() { spinning = true };
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

        account_combo.initialize(stream_interactor);
        box.append(account_combo);

        box.append(spinner);
        box.append(title_label);
        box.append(summary_label);

        var buttons = new Gtk.Box(Orientation.HORIZONTAL, 6) { halign = Align.END };
        buttons.append(copy_uri_button);
        buttons.append(import_button);
        box.append(buttons);

        this.content = box;

        import_button.clicked.connect(() => do_import.begin());
        copy_uri_button.clicked.connect(copy_share_uri);

        // Load preview (best-effort)
        preview.begin();
    }

    private async void preview() {
        spinner.visible = true;
        title_label.label = _("Loading…");
        summary_label.label = "";

        import_button.sensitive = false;
        copy_uri_button.sensitive = false;

        var account = account_combo.active_account;
        if (account == null) {
            title_label.label = _("No account available");
            spinner.visible = false;
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
            spinner.visible = false;
        }
    }

    private async void do_import() {
        var account = account_combo.active_account;
        if (account == null) return;

        spinner.visible = true;
        import_button.sensitive = false;
        copy_uri_button.sensitive = false;
        title_label.label = _("Importing…");
        summary_label.label = "";

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
            spinner.visible = false;
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
