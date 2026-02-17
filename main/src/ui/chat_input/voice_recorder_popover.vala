/*
 * Copyright (C) 2025 Ralf Peter <dinox@handwerker.jetzt>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

using Gtk;
using Cairo;
using Gee;

namespace Dino.Ui.ChatInput {

public class VoiceRecorderPopover : Popover {
    private AudioRecorder recorder;
    private Label timer_label;
    private DrawingArea rec_indicator;
    private DrawingArea waveform;
    private ArrayList<double?> samples = new ArrayList<double?>();
    private const int MAX_SAMPLES = 60;
    private bool indicator_visible = true;
    private uint blink_id = 0;
    
    public signal void send_clicked();
    public signal void cancel_clicked();

    public VoiceRecorderPopover(AudioRecorder recorder) {
        this.recorder = recorder;
        
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

        Label title = new Label(_("Voice Message"));
        title.add_css_class("title-4");
        header_box.append(title);
        main_box.append(header_box);
        
        // Timer + waveform row
        Box content_box = new Box(Orientation.HORIZONTAL, 8);
        
        timer_label = new Label("0:00");
        timer_label.add_css_class("monospace");
        timer_label.valign = Align.CENTER;
        content_box.append(timer_label);
        
        waveform = new DrawingArea();
        waveform.set_size_request(300, 48);
        waveform.hexpand = true;
        waveform.set_draw_func(draw_waveform);
        content_box.append(waveform);
        
        main_box.append(content_box);
        
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
        
        recorder.duration_changed.connect((text) => {
            timer_label.label = text;
        });
        
        recorder.level_changed.connect((level) => {
            samples.add(level);
            if (samples.size > MAX_SAMPLES) {
                samples.remove_at(0);
            }
            waveform.queue_draw();
        });

        // Auto-send when max duration is reached
        recorder.max_duration_reached.connect(() => {
            send_clicked();
        });
        
        // Initialize with empty samples
        for (int i = 0; i < MAX_SAMPLES; i++) samples.add(0.0);

        // Blink recording indicator every 600ms
        blink_id = Timeout.add(600, () => {
            indicator_visible = !indicator_visible;
            rec_indicator.queue_draw();
            return true;
        });
    }
    
    private void draw_waveform(DrawingArea area, Context cr, int width, int height) {
        double bar_width = (double)width / MAX_SAMPLES;
        double gap = 1.5;
        double draw_width = bar_width - gap;
        if (draw_width < 1.5) draw_width = 1.5;
        
        for (int i = 0; i < samples.size; i++) {
            double level = samples[i];
            // Values are already perceptually scaled by db_to_visual() in AudioRecorder
            level = Math.fmin(level, 1.0);
            
            double bar_height = height * level;
            if (bar_height < 2.0) bar_height = 2.0;
            
            double x = i * bar_width;
            double y = (height - bar_height) / 2.0;

            // Color: recent bars brighter, older ones fade
            double age = 1.0 - (double)i / MAX_SAMPLES;
            double alpha = 0.5 + 0.5 * (1.0 - age * 0.6);
            cr.set_source_rgba(0.9, 0.15, 0.15, alpha); // Red tone for recording
            
            // Rounded rectangle (pill-shaped bars)
            double radius = draw_width / 2.0;
            if (radius > bar_height / 2.0) radius = bar_height / 2.0;
            
            cr.new_sub_path();
            cr.arc(x + radius, y + radius, radius, Math.PI, 3 * Math.PI / 2);
            cr.arc(x + draw_width - radius, y + radius, radius, 3 * Math.PI / 2, 0);
            cr.arc(x + draw_width - radius, y + bar_height - radius, radius, 0, Math.PI / 2);
            cr.arc(x + radius, y + bar_height - radius, radius, Math.PI / 2, Math.PI);
            cr.close_path();
            
            cr.fill();
        }
    }

    public override void dispose() {
        if (blink_id != 0) {
            Source.remove(blink_id);
            blink_id = 0;
        }
        base.dispose();
    }
}
}
