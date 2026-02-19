using Gdk;
using Gee;
using Gtk;

using Dino.Entities;
using Xmpp;
using Dino.Ui.ViewModel;

namespace Dino.Ui.ChatInput {

[GtkTemplate (ui = "/im/github/rallep71/DinoX/chat_input.ui")]
public class View : Box {

    public string text {
        owned get { return chat_text_view.text_view.buffer.text; }
        set { chat_text_view.text_view.buffer.text = value; }
    }

    private StreamInteractor stream_interactor;
    private Conversation? conversation;
    private HashMap<Conversation, string> entry_cache = new HashMap<Conversation, string>(Conversation.hash_func, Conversation.equals_func);

    [GtkChild] public unowned Box quote_box;
    [GtkChild] public unowned AvatarPicture account_avatar;
    [GtkChild] public unowned ChatTextView chat_text_view;
    [GtkChild] public unowned MenuButton file_button;
    [GtkChild] public unowned Button send_file_button;
    [GtkChild] public unowned Button send_location_button;
    [GtkChild] public unowned Popover attachment_popover;
    [GtkChild] public unowned Button record_button;
    [GtkChild] public unowned Button video_record_button;
    [GtkChild] public unowned MenuButton emoji_button;
    [GtkChild] public unowned MenuButton sticker_button;
    [GtkChild] public unowned MenuButton encryption_button;
    [GtkChild] public unowned Button send_button;
    [GtkChild] public unowned Separator file_separator;
    [GtkChild] public unowned Label chat_input_status;

    public EncryptionButton encryption_widget;
    private StickerChooser? sticker_chooser;

    public View init(StreamInteractor stream_interactor) {
        this.stream_interactor = stream_interactor;

        encryption_widget = new EncryptionButton(stream_interactor, encryption_button);

        EmojiChooser chooser = new EmojiChooser();
        chooser.emoji_picked.connect((emoji) => {
            chat_text_view.text_view.buffer.insert_at_cursor(emoji, emoji.data.length);
        });
        chooser.closed.connect(do_focus);

        emoji_button.set_popover(chooser);

        sticker_chooser = new StickerChooser(stream_interactor);
        sticker_button.set_popover(sticker_chooser);
        sticker_button.tooltip_text = Util.string_if_tooltips_active(_("Stickers"));

        // Hide sticker button when stickers are disabled in settings
        var app = Dino.Application.get_default();
        sticker_button.visible = app.settings.stickers_enabled;
        app.settings.notify["stickers-enabled"].connect(() => {
            sticker_button.visible = app.settings.stickers_enabled;
        });

        // Defensive: keep MenuButton state in sync when the popover is dismissed programmatically
        // (e.g. by selecting a sticker) or by outside clicks.
        sticker_chooser.closed.connect(() => {
            if (sticker_button.active) sticker_button.active = false;
        });

        file_button.tooltip_text = Util.string_if_tooltips_active(_("Send a file"));

        return this;
    }

    public void set_file_upload_active(bool active) {
        file_button.visible = active;
        file_separator.visible = active;
    }

    public void initialize_for_conversation(Conversation conversation) {
        int64 t0_us = Dino.Ui.UiTiming.now_us();

        int64 t_cache_prev_us = Dino.Ui.UiTiming.now_us();
        if (this.conversation != null) entry_cache[this.conversation] = chat_text_view.text_view.buffer.text;
        Dino.Ui.UiTiming.log_ms("ChatInput.View.initialize_for_conversation: cache_prev", t_cache_prev_us);

        int64 t_set_conv_us = Dino.Ui.UiTiming.now_us();
        this.conversation = conversation;
        Dino.Ui.UiTiming.log_ms("ChatInput.View.initialize_for_conversation: set_conversation", t_set_conv_us);

        int64 t_clear_us = Dino.Ui.UiTiming.now_us();
        chat_text_view.text_view.buffer.text = "";
        Dino.Ui.UiTiming.log_ms("ChatInput.View.initialize_for_conversation: clear_buffer", t_clear_us);

        int64 t_restore_us = Dino.Ui.UiTiming.now_us();
        if (entry_cache.has_key(conversation)) {
            chat_text_view.text_view.buffer.text = entry_cache[conversation];
        }
        Dino.Ui.UiTiming.log_ms("ChatInput.View.initialize_for_conversation: restore_draft", t_restore_us);

        int64 t_focus_us = Dino.Ui.UiTiming.now_us();
        do_focus();
        Dino.Ui.UiTiming.log_ms("ChatInput.View.initialize_for_conversation: focus", t_focus_us);

        int64 t_sticker_us = Dino.Ui.UiTiming.now_us();
        if (sticker_chooser != null) {
            sticker_chooser.set_conversation(conversation);
        }
        var self_conv = new Conversation(conversation.account.bare_jid, conversation.account, Conversation.Type.CHAT);
        account_avatar.model = new ViewModel.CompatAvatarPictureModel(stream_interactor).set_conversation(self_conv);
        Dino.Ui.UiTiming.log_ms("ChatInput.View.initialize_for_conversation: sticker_chooser", t_sticker_us);

        Dino.Ui.UiTiming.log_ms("ChatInput.View.initialize_for_conversation: total", t0_us);
    }

    public void set_input_state(Plugins.InputFieldStatus.MessageType message_type) {
        switch (message_type) {
            case Plugins.InputFieldStatus.MessageType.NONE:
                this.remove_css_class("dino-input-warning");
                this.remove_css_class("dino-input-error");
                break;
            case Plugins.InputFieldStatus.MessageType.INFO:
                this.remove_css_class("dino-input-warning");
                this.remove_css_class("dino-input-error");
                break;
            case Plugins.InputFieldStatus.MessageType.WARNING:
                this.add_css_class("dino-input-warning");
                this.remove_css_class("dino-input-error");
                break;
            case Plugins.InputFieldStatus.MessageType.ERROR:
                this.remove_css_class("dino-input-warning");
                this.add_css_class("dino-input-error");
                break;
        }
    }

    public void highlight_state_description() {
        chat_input_status.add_css_class("input-status-highlight-once");
        Timeout.add(500, () => {
            chat_input_status.remove_css_class("input-status-highlight-once");
            return false;
        });
    }

    public void set_quoted_message(Widget quote_widget) {
        Widget? quote_box_child = quote_box.get_first_child();
        if (quote_box_child != null) quote_box.remove(quote_box_child);
        quote_box.append(quote_widget);
        quote_box.visible = true;
    }

    public void unset_quoted_message() {
        Widget? quote_box_child = quote_box.get_first_child();
        if (quote_box_child != null) quote_box.remove(quote_box_child);
        quote_box.visible = false;
    }

    public void do_focus() {
        chat_text_view.text_view.grab_focus();
    }
}

}
