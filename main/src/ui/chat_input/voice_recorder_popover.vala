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
    private DrawingArea waveform;
    private ArrayList<double?> samples = new ArrayList<double?>();
    private const int MAX_SAMPLES = 40;
    
    public signal void send_clicked();
    public signal void cancel_clicked();

    public VoiceRecorderPopover(AudioRecorder recorder) {
        this.recorder = recorder;
        
        Box main_box = new Box(Orientation.VERTICAL, 10);
        main_box.margin_start = 10;
        main_box.margin_end = 10;
        main_box.margin_top = 10;
        main_box.margin_bottom = 10;
        
        Label title = new Label(_("Voice Message"));
        title.add_css_class("title-4");
        main_box.append(title);
        
        Box content_box = new Box(Orientation.HORIZONTAL, 10);
        
        timer_label = new Label("0:00");
        timer_label.add_css_class("monospace");
        content_box.append(timer_label);
        
        waveform = new DrawingArea();
        waveform.set_size_request(200, 30);
        waveform.set_draw_func(draw_waveform);
        content_box.append(waveform);
        
        main_box.append(content_box);
        
        Box button_box = new Box(Orientation.HORIZONTAL, 10);
        button_box.halign = Align.CENTER;
        
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
        
        // Initialize with some empty samples
        for (int i = 0; i < MAX_SAMPLES; i++) samples.add(0.0);
    }
    
    private void draw_waveform(DrawingArea area, Context cr, int width, int height) {
        // Background
        // cr.set_source_rgba(0.9, 0.9, 0.9, 0.5);
        // cr.rectangle(0, 0, width, height);
        // cr.fill();
        
        // Draw bars
        cr.set_source_rgb(0.2, 0.6, 1.0); // Blueish
        
        double bar_width = (double)width / MAX_SAMPLES;
        double gap = 1.0;
        double draw_width = bar_width - gap;
        if (draw_width < 1.0) draw_width = 1.0;
        
        for (int i = 0; i < samples.size; i++) {
            double level = samples[i];
            // Values are already perceptually scaled by db_to_visual() in AudioRecorder
            level = Math.fmin(level, 1.0);
            
            double bar_height = height * level;
            if (bar_height < 2.0) bar_height = 2.0; // Minimum height
            
            double x = i * bar_width;
            double y = (height - bar_height) / 2.0;
            
            // Rounded rectangle
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
}
}
