using Pango;
using Gee;
using Xmpp;
using Dino.Entities;
using Gtk;

namespace Dino.Ui {

    public class ParticipantWidget : Box {

        public Overlay overlay = new Overlay();
        public Widget main_widget;
        public HeaderBar header_bar = new HeaderBar() { valign=Align.START };
        public Label title_label = new Label("");
        public Label subtitle_label = new Label("");
        public Box inner_box = new Box(Orientation.HORIZONTAL, 0) { margin_start=5, margin_top=5, hexpand=true };
        public Box title_box = new Box(Orientation.VERTICAL, 0) { valign=Align.CENTER, hexpand=true };
        public MenuButton encryption_button = new MenuButton() { opacity=0, has_frame=false, height_request=30, width_request=30, margin_end=5 };
        public CallEncryptionButtonController encryption_button_controller;
        public MenuButton menu_button = new MenuButton() { icon_name="view-more-symbolic", has_frame=false };
        public Button invite_button = new Button.from_icon_name("contact-new-symbolic") { has_frame=false };
        public bool shows_video = false;
        public string? participant_name;
        public bool show_volume_control { get; set; default = false; }

        // Volume control for this participant (only shown in group calls)
        private Box volume_box = new Box(Orientation.HORIZONTAL, 6) { valign=Align.END, halign=Align.CENTER, margin_bottom=10, margin_start=20, margin_end=20 };
        private Image volume_icon = new Image.from_icon_name("audio-volume-high-symbolic") { margin_end=4 };
        private Gtk.Scale volume_scale = new Gtk.Scale.with_range(Orientation.HORIZONTAL, 0.0, 1.0, 0.05) { 
            draw_value=false, 
            hexpand=true,
            width_request=120
        };
        public signal void volume_changed(double volume);

        bool is_highest_row = false;
        bool is_start_row = false;
        public bool controls_active { get; set; }
        public bool may_show_invite_button { get; set; }

        public signal void debug_information_clicked();
        public signal void invite_button_clicked();

        class construct {
            install_action("menu.debuginfo", null, (widget, action_name) => { ((ParticipantWidget) widget).debug_information_clicked(); });
        }

        public ParticipantWidget(string participant_name) {
            encryption_button_controller = new CallEncryptionButtonController(encryption_button);

            this.participant_name = participant_name;

            Box titles_box = new Box(Orientation.VERTICAL, 0) { valign=Align.CENTER };
            titles_box.add_css_class("titles");
            title_label.attributes = new AttrList();
            title_label.attributes.insert(Pango.attr_weight_new(Weight.BOLD));
            titles_box.append(title_label);
            subtitle_label.attributes = new AttrList();
            subtitle_label.attributes.insert(Pango.attr_scale_new(Pango.Scale.SMALL));
            subtitle_label.add_css_class("dim-label");
            titles_box.append(subtitle_label);

            header_bar.set_title_widget(titles_box);
            title_label.label = participant_name;

            header_bar.add_css_class("participant-header-bar");
            header_bar.pack_start(invite_button);
            header_bar.pack_start(encryption_button);
            header_bar.pack_end(menu_button);

            create_menu();

            invite_button.clicked.connect(() => invite_button_clicked());

            // Setup volume control slider
            volume_scale.set_value(1.0);
            volume_box.append(volume_icon);
            volume_box.append(volume_scale);
            volume_box.add_css_class("participant-volume-box");
            volume_scale.value_changed.connect(() => {
                double vol = volume_scale.get_value();
                update_volume_icon(vol);
                volume_changed(vol);
            });

            this.append(overlay);
            overlay.add_overlay(header_bar);
            overlay.add_overlay(volume_box);
            volume_box.visible = false;  // Hidden by default, shown only in group calls

            this.notify["controls-active"].connect(reveal_or_hide_controls);
            this.notify["may-show-invite-button"].connect(reveal_or_hide_controls);
            this.notify["show-volume-control"].connect(reveal_or_hide_controls);
        }

        public void on_row_changed(bool is_highest, bool is_lowest, bool is_start, bool is_end) {
            this.is_highest_row = is_highest;
            this.is_start_row = is_start;

            header_bar.show_title_buttons = is_highest_row;
            if (is_highest_row) {
                Gtk.Settings? gtk_settings = Gtk.Settings.get_default();
                if (gtk_settings != null) {
                    string[] buttons = gtk_settings.gtk_decoration_layout.split(":");
                    header_bar.decoration_layout = (is_start ? buttons[0] : "") + ":" + (is_end && buttons.length == 2 ? buttons[1] : "");
                }
            }
            reveal_or_hide_controls();
        }

        public void set_video(Widget widget) {
            shows_video = true;
            widget.visible = true;
            set_participant_widget(widget);
        }

        public void set_placeholder(Conversation? conversation, StreamInteractor stream_interactor) {
            shows_video = false;
            Box box = new Box(Orientation.HORIZONTAL, 0);
            box.add_css_class("video-placeholder-box");
            AvatarPicture avatar = new AvatarPicture() { hexpand=true, vexpand=true, halign=Align.CENTER, valign=Align.CENTER, height_request=100, width_request=100 };
            if (conversation != null) {
                avatar.model = new ViewModel.CompatAvatarPictureModel(stream_interactor).set_conversation(conversation);
            } else {
                avatar.model = new ViewModel.CompatAvatarPictureModel(stream_interactor).add("?");
            }
            box.append(avatar);

            set_participant_widget(box);
        }

        private void set_participant_widget(Widget widget) {
            widget.hexpand = widget.vexpand = true;
            main_widget = widget;
            overlay.set_child(main_widget);
        }

        private void create_menu() {
            Menu menu_model = new Menu();
            menu_model.append(_("Debug information"), "menu.debuginfo");
            Gtk.PopoverMenu popover_menu = new Gtk.PopoverMenu.from_model(menu_model);
            menu_button.popover = popover_menu;
        }

        public void set_status(string state) {
            subtitle_label.visible = true;

            if (state == "requested") {
                subtitle_label.label =  _("Calling…");
            } else if (state == "ringing") {
                subtitle_label.label = _("Ringing…");
            } else if (state == "establishing") {
                subtitle_label.label = _("Connecting…");
            } else {
                subtitle_label.visible = false;
            }
        }

        public void set_volume(double volume) {
            volume_scale.set_value(volume);
            update_volume_icon(volume);
        }

        public double get_volume() {
            return volume_scale.get_value();
        }

        private void update_volume_icon(double volume) {
            if (volume <= 0.0) {
                volume_icon.icon_name = "audio-volume-muted-symbolic";
            } else if (volume < 0.33) {
                volume_icon.icon_name = "audio-volume-low-symbolic";
            } else if (volume < 0.66) {
                volume_icon.icon_name = "audio-volume-medium-symbolic";
            } else {
                volume_icon.icon_name = "audio-volume-high-symbolic";
            }
        }

        public bool is_menu_active() {
            return false;
        }

        private void reveal_or_hide_controls() {
            header_bar.opacity = controls_active ? 1.0 : 0.0;
            volume_box.visible = show_volume_control;
            volume_box.opacity = (controls_active && show_volume_control) ? 1.0 : 0.0;
            invite_button.visible = may_show_invite_button && is_highest_row && is_start_row;
        }

        public override void dispose() {
            main_widget = null;
            overlay = null;
            base.dispose();
        }
    }
}
