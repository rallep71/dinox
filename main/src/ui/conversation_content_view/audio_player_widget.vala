/*
 * Copyright (C) 2025 Ralf Peter <dinox@handwerker.jetzt>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

using Gtk;
using Gst;
using Dino.Entities;

namespace Dino.Ui.ConversationSummary {

public class AudioFileMetaItem : FileMetaItem {
    private StreamInteractor stream_interactor;
    
    public AudioFileMetaItem(ContentItem content_item, StreamInteractor stream_interactor) {
        base(content_item, stream_interactor);
        this.stream_interactor = stream_interactor;
        
        // Auto-download audio files if not yet downloaded
        if (file_transfer.direction == FileTransfer.DIRECTION_RECEIVED && 
            file_transfer.state == FileTransfer.State.NOT_STARTED) {
            stream_interactor.get_module(FileManager.IDENTITY).download_file.begin(file_transfer);
        }
    }

    public override GLib.Object? get_widget(Plugins.ConversationItemWidgetInterface outer, Plugins.WidgetType type) {
        return new AudioPlayerWidget(file_transfer);
    }
}

public class AudioPlayerWidget : Box {
    private FileTransfer file_transfer;
    private Button play_button;
    private Scale progress_scale;
    private Label time_label;
    private Button speed_button;
    private Element? pipeline;
    private bool is_playing = false;
    private int64 duration = -1;
    private uint update_id = 0;
    private uint bus_watch_id = 0;
    private double playback_rate = 1.0;

    public AudioPlayerWidget(FileTransfer file_transfer) {
        GLib.Object(orientation: Orientation.HORIZONTAL, spacing: 8);
        this.file_transfer = file_transfer;
        
        this.add_css_class("audio-player");
        this.margin_top = 4;
        this.margin_bottom = 4;
        this.margin_start = 8;
        this.margin_end = 8;
        this.halign = Align.START;
        this.hexpand = false;
        this.set_size_request(250, -1);
        
        // Listen for file download completion
        file_transfer.notify["path"].connect(() => {
            if (file_transfer.path != null && pipeline == null) {
                // File is now available, can setup pipeline if needed
            }
        });

        play_button = new Button.from_icon_name("media-playback-start-symbolic");
        play_button.add_css_class("circular");
        play_button.add_css_class("flat");
        play_button.valign = Align.CENTER;
        play_button.clicked.connect(toggle_playback);
        append(play_button);
        
        progress_scale = new Scale(Orientation.HORIZONTAL, null);
        progress_scale.hexpand = true;
        progress_scale.valign = Align.CENTER;
        progress_scale.draw_value = false;
        progress_scale.change_value.connect(on_seek);
        append(progress_scale);
        
        time_label = new Label("0:00");
        time_label.add_css_class("monospace");
        time_label.add_css_class("dim-label");
        time_label.valign = Align.CENTER;
        append(time_label);

        speed_button = new Button.with_label("1x");
        speed_button.add_css_class("flat");
        speed_button.add_css_class("small-button");
        speed_button.valign = Align.CENTER;
        speed_button.clicked.connect(toggle_speed);
        append(speed_button);
    }
    
    private void toggle_speed() {
        if (playback_rate == 1.0) playback_rate = 1.5;
        else if (playback_rate == 1.5) playback_rate = 2.0;
        else playback_rate = 1.0;
        
        speed_button.label = (playback_rate == 1.0) ? "1x" : "%.1fx".printf(playback_rate);
        
        if (pipeline != null) {
            int64 position = 0;
            pipeline.query_position(Format.TIME, out position);
            seek_to(position);
        }
    }
    
    private void toggle_playback() {
        if (is_playing) {
            pause();
        } else {
            play();
        }
    }
    
    private void play() {
        if (pipeline == null) {
            if (!setup_pipeline()) return;
        }
        
        pipeline.set_state(State.PLAYING);
        is_playing = true;
        play_button.icon_name = "media-playback-pause-symbolic";
        
        if (playback_rate != 1.0) {
             int64 position = 0;
             pipeline.query_position(Format.TIME, out position);
             seek_to(position);
        }
        
        if (update_id == 0) {
            update_id = Timeout.add(100, update_progress);
        }
    }
    
    private void pause() {
        if (pipeline != null) {
            pipeline.set_state(State.PAUSED);
        }
        is_playing = false;
        play_button.icon_name = "media-playback-start-symbolic";
        
        if (update_id != 0) {
            Source.remove(update_id);
            update_id = 0;
        }
    }

    private void stop() {
        if (pipeline != null) {
            pipeline.set_state(State.NULL);
            pipeline = null;
        }
        if (bus_watch_id != 0) {
            Source.remove(bus_watch_id);
            bus_watch_id = 0;
        }
        is_playing = false;
        play_button.icon_name = "media-playback-start-symbolic";
        
        if (update_id != 0) {
            Source.remove(update_id);
            update_id = 0;
        }
    }
    
    private bool setup_pipeline() {
        var file = file_transfer.get_file();
        if (file == null) {
            warning("Audio file not yet downloaded");
            return false;
        }
        
        pipeline = ElementFactory.make("playbin", "playbin");
        if (pipeline == null) {
            warning("Could not create playbin");
            return false;
        }
        
        pipeline.set("uri", file.get_uri());
        
        Gst.Bus bus = pipeline.get_bus();
        bus_watch_id = bus.add_watch(0, bus_callback);
        
        return true;
    }
    
    private bool bus_callback(Gst.Bus bus, Gst.Message msg) {
        switch (msg.type) {
            case Gst.MessageType.EOS:
                stop();
                seek_to(0);
                break;
            case Gst.MessageType.ERROR:
                GLib.Error err;
                string debug;
                msg.parse_error(out err, out debug);
                warning("Error: %s", err.message);
                stop();
                break;
            case Gst.MessageType.DURATION_CHANGED:
                query_duration();
                break;
            default:
                break;
        }
        return true;
    }
    
    private void query_duration() {
        if (pipeline != null && pipeline.query_duration(Format.TIME, out duration)) {
            progress_scale.set_range(0, (double)duration / Gst.SECOND);
        }
    }
    
    private bool update_progress() {
        if (pipeline != null) {
            int64 position;
            if (pipeline.query_position(Format.TIME, out position)) {
                progress_scale.set_value((double)position / Gst.SECOND);
                time_label.label = format_time(position);
            }
            
            if (duration == -1) query_duration();
        }
        return true;
    }
    
    private bool on_seek(ScrollType scroll, double value) {
        seek_to((int64)(value * Gst.SECOND));
        return false;
    }
    
    private void seek_to(int64 position) {
        if (pipeline != null) {
            pipeline.seek(playback_rate, Format.TIME, SeekFlags.FLUSH | SeekFlags.ACCURATE, 
                          Gst.SeekType.SET, position, Gst.SeekType.NONE, -1);
            progress_scale.set_value((double)position / Gst.SECOND);
            time_label.label = format_time(position);
        }
    }
    
    private string format_time(int64 ns) {
        int64 s = ns / Gst.SECOND;
        return "%d:%02d".printf((int)(s / 60), (int)(s % 60));
    }
    
    public override void dispose() {
        stop();
        base.dispose();
    }
}

}
