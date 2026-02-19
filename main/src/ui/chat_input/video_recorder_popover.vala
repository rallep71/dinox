/*
 * Copyright (C) 2025 Ralf Peter <dinox@handwerker.jetzt>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

using Gtk;

namespace Dino.Ui.ChatInput {

public class VideoRecorderPopover : Popover {
    private VideoRecorder recorder;
    private Label timer_label;
    private DrawingArea rec_indicator;
    private Picture preview_picture;
    private bool indicator_visible = true;
    private uint blink_id = 0;
    private uint preview_poll_id = 0;
    private ulong duration_handler_id = 0;
    private ulong max_duration_handler_id = 0;

    public signal void send_clicked();
    public signal void cancel_clicked();

    public VideoRecorderPopover(VideoRecorder recorder) {
        this.recorder = recorder;

        // Allow the popover to be large enough for video preview
        this.width_request = 360;

        Box main_box = new Box(Orientation.VERTICAL, 8);
        main_box.margin_start = 12;
        main_box.margin_end = 12;
        main_box.margin_top = 10;
        main_box.margin_bottom = 10;

        // Header: recording indicator + title
        Box header_box = new Box(Orientation.HORIZONTAL, 8);
        header_box.halign = Align.CENTER;

        // Pulsing red recording dot
        rec_indicator = new DrawingArea();
        rec_indicator.set_size_request(12, 12);
        rec_indicator.valign = Align.CENTER;
        rec_indicator.set_draw_func((area, cr, w, h) => {
            if (indicator_visible) {
                cr.set_source_rgb(0.9, 0.1, 0.1);
                cr.arc(w / 2.0, h / 2.0, w / 2.0 - 1, 0, 2 * Math.PI);
                cr.fill();
            }
        });
        header_box.append(rec_indicator);

        Label title = new Label(_("Video Message"));
        title.add_css_class("title-4");
        header_box.append(title);

        // Timer to the right of title
        timer_label = new Label("0:00");
        timer_label.add_css_class("monospace");
        timer_label.margin_start = 12;
        header_box.append(timer_label);

        main_box.append(header_box);

        // Video preview area with aspect frame
        var aspect_frame = new AspectFrame(0.5f, 0.5f, 16.0f / 9.0f, false);
        aspect_frame.set_size_request(336, 189); // 16:9 at 336px width

        preview_picture = new Picture();
        preview_picture.content_fit = ContentFit.CONTAIN;
        preview_picture.add_css_class("video-preview");
        preview_picture.set_size_request(336, 189);
        // Dark background for preview area
        preview_picture.add_css_class("card");

        aspect_frame.set_child(preview_picture);
        main_box.append(aspect_frame);

        // Buttons
        Box button_box = new Box(Orientation.HORIZONTAL, 10);
        button_box.halign = Align.CENTER;
        button_box.margin_top = 4;

        Button cancel_btn = new Button.with_label(_("Cancel"));
        cancel_btn.clicked.connect(() => cancel_clicked());
        button_box.append(cancel_btn);

        Button send_btn = new Button.with_label(_("Send"));
        send_btn.add_css_class("suggested-action");
        send_btn.clicked.connect(() => send_clicked());
        button_box.append(send_btn);

        main_box.append(button_box);

        set_child(main_box);

        duration_handler_id = recorder.duration_changed.connect((text) => {
            timer_label.label = text;
        });

        // Auto-send when max duration is reached
        max_duration_handler_id = recorder.max_duration_reached.connect(() => {
            send_clicked();
        });

        // Blink recording indicator every 600ms
        blink_id = Timeout.add(600, () => {
            indicator_visible = !indicator_visible;
            rec_indicator.queue_draw();
            return true;
        });

        // Continuously poll for preview frames (~20fps)
        preview_poll_id = Timeout.add(50, () => {
            if (!recorder.is_recording) return false;
            Gdk.Texture? texture = recorder.get_preview_texture();
            if (texture != null) {
                preview_picture.paintable = texture;
            }
            return true;
        });
    }

    public override void dispose() {
        if (blink_id != 0) {
            Source.remove(blink_id);
            blink_id = 0;
        }
        if (preview_poll_id != 0) {
            Source.remove(preview_poll_id);
            preview_poll_id = 0;
        }
        // Disconnect signal handlers to prevent callbacks on destroyed widgets
        if (duration_handler_id != 0 && recorder != null) {
            recorder.disconnect(duration_handler_id);
            duration_handler_id = 0;
        }
        if (max_duration_handler_id != 0 && recorder != null) {
            recorder.disconnect(max_duration_handler_id);
            max_duration_handler_id = 0;
        }
        recorder = null;
        base.dispose();
    }
}
}
