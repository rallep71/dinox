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
using Gee;
using Dino.Entities;
using Dino.Security;

namespace Dino.Ui.ConversationSummary {

public class AudioFileMetaItem : FileMetaItem {
    private StreamInteractor stream_interactor;
    
    public AudioFileMetaItem(ContentItem content_item, StreamInteractor stream_interactor) {
        base(content_item, stream_interactor);
        this.stream_interactor = stream_interactor;
        
        // Auto-download audio files if not yet downloaded
        if (file_transfer.direction == FileTransfer.DIRECTION_RECEIVED && 
            file_transfer.state == FileTransfer.State.NOT_STARTED) {
            stream_interactor.get_module<FileManager>(FileManager.IDENTITY).download_file.begin(file_transfer);
        }
    }

    public override GLib.Object? get_widget(Plugins.ConversationItemWidgetInterface outer, Plugins.WidgetType type) {
        return new AudioPlayerWidget(file_transfer);
    }
}

public class AudioPlayerWidget : Box {
    private FileTransfer? file_transfer;
    private Button play_button;
    private DrawingArea waveform_area;
    private Label time_label;
    private Button speed_button;
    private Element? pipeline;
    private bool is_playing = false;
    private int64 duration = -1;
    private uint update_id = 0;
    private uint bus_watch_id = 0;
    private double playback_rate = 1.0;
    private File? temp_play_file = null;
    private int64 saved_position = 0; // saved position for resume after pause

    // Waveform data
    private double[] waveform_bars = {};
    private const int N_BARS = 50;
    private bool waveform_ready = false;
    private double playback_progress = 0.0; // 0.0 to 1.0
    private ArrayList<double?> scan_peaks = new ArrayList<double?>();
    private Element? scan_element = null;
    private uint scan_bus_watch_id = 0;
    private uint scan_timeout_id = 0;

    // C binding for GValueArray peak parsing (same as AudioRecorder)
    [CCode (cname = "dino_gva_get_nth")]
    private static extern unowned GLib.Value? gva_get_nth(void* value_array, uint index);

    public AudioPlayerWidget(FileTransfer file_transfer) {
        GLib.Object(orientation: Orientation.HORIZONTAL, spacing: 8);
        this.file_transfer = file_transfer;
        
        this.add_css_class("audio-player");
        this.margin_top = 4;
        this.margin_bottom = 4;
        this.margin_start = 8;
        this.margin_end = 8;
        this.halign = Align.FILL;
        this.hexpand = true;
        this.set_size_request(250, -1);

        play_button = new Button.from_icon_name("media-playback-start-symbolic");
        play_button.add_css_class("circular");
        play_button.add_css_class("flat");
        play_button.valign = Align.CENTER;
        play_button.clicked.connect(toggle_playback);
        append(play_button);

        // Stop pipeline when widget is unmapped (scrolled out of view, conversation switched)
        this.unmap.connect(() => {
            if (pipeline != null) {
                if (is_playing) {
                    // Save position before stopping
                    pipeline.query_position(Format.TIME, out saved_position);
                }
                stop();
            }
            cleanup_scan(); // Also stop any ongoing waveform scan
        });
        
        // Waveform display (replaces Scale slider)
        waveform_area = new DrawingArea();
        waveform_area.hexpand = true;
        waveform_area.valign = Align.CENTER;
        waveform_area.set_size_request(-1, 40);
        waveform_area.set_draw_func(draw_waveform);

        // Click-to-seek on waveform
        var click_gesture = new GestureClick();
        click_gesture.pressed.connect((n, x, y) => {
            if (duration > 0) {
                double fraction = x / waveform_area.get_width();
                fraction = double.max(0.0, double.min(1.0, fraction));
                if (pipeline == null) {
                    // Start playback from clicked position
                    setup_pipeline.begin((obj, res) => {
                        if (pipeline != null && duration > 0) {
                            seek_to((int64)(fraction * duration));
                        }
                    });
                } else {
                    seek_to((int64)(fraction * duration));
                }
            }
        });
        waveform_area.add_controller(click_gesture);

        // Drag-to-seek on waveform
        var drag_gesture = new GestureDrag();
        drag_gesture.drag_update.connect((offset_x, offset_y) => {
            if (duration > 0 && pipeline != null) {
                double start_x, start_y;
                drag_gesture.get_start_point(out start_x, out start_y);
                double fraction = (start_x + offset_x) / waveform_area.get_width();
                fraction = double.max(0.0, double.min(1.0, fraction));
                seek_to((int64)(fraction * duration));
            }
        });
        waveform_area.add_controller(drag_gesture);

        append(waveform_area);
        
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

        // Do NOT scan waveform automatically — no GStreamer pipeline until user clicks play
        // Placeholder bars are shown in draw_waveform when waveform_ready == false
    }

    // Convert dB to perceptual 0.0-1.0 range (same curve as AudioRecorder)
    private double db_to_visual(double db) {
        if (db <= -60.0) return 0.0;
        double normalized = (db + 40.0) / 40.0;
        normalized = double.max(0.0, double.min(normalized, 1.0));
        return Math.sqrt(normalized);
    }

    private void draw_waveform(DrawingArea area, Cairo.Context cr, int width, int height) {
        int n = waveform_ready ? waveform_bars.length : N_BARS;
        if (n == 0) n = N_BARS;

        double bar_width = (double)width / n;
        double gap = 1.5;
        double draw_width = bar_width - gap;
        if (draw_width < 1.5) draw_width = 1.5;

        for (int i = 0; i < n; i++) {
            double level;
            if (waveform_ready && i < waveform_bars.length) {
                level = waveform_bars[i];
            } else {
                level = 0.12; // placeholder: small uniform bars before scan
            }
            level = double.min(level, 1.0);

            double bar_height = height * level;
            if (bar_height < 2.0) bar_height = 2.0;

            double x = i * bar_width;
            double y = (height - bar_height) / 2.0;

            // Color: played = accent blue, unplayed = dim grey
            double bar_fraction = (double)(i + 0.5) / n;
            if (bar_fraction <= playback_progress) {
                cr.set_source_rgb(0.2, 0.6, 1.0);
            } else {
                cr.set_source_rgba(0.5, 0.5, 0.5, 0.35);
            }

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

    // Scan audio file to extract waveform peak data (runs faster than real-time)
    private async void scan_waveform() {
        File? audio_file = null;

        // Reuse already-decrypted temp file from setup_pipeline if available
        if (temp_play_file != null) {
            audio_file = temp_play_file;
        } else {
            var file = file_transfer.get_file();
            if (file == null) return;

            // Decrypt if needed (reuse temp file for later playback)
            try {
                var app = (Dino.Application) GLib.Application.get_default();
                var enc = app.file_encryption;

                string temp_dir = Path.build_filename(Environment.get_user_cache_dir(), "dinox", "temp_audio");
                DirUtils.create_with_parents(temp_dir, 0700);

                string ext = "";
                if ("." in file_transfer.file_name) {
                    string[] parts = file_transfer.file_name.split(".");
                    ext = "." + parts[parts.length - 1];
                }
                string random_name = GLib.Uuid.string_random() + ext;
                string temp_path = Path.build_filename(temp_dir, random_name);

                temp_play_file = File.new_for_path(temp_path);

                var source_stream = file.read();
                var target_stream = temp_play_file.replace(null, false, GLib.FileCreateFlags.NONE);
                yield enc.decrypt_stream(source_stream, target_stream);
                try { source_stream.close(); } catch (Error e) {}
                try { target_stream.close(); } catch (Error e) {}

                audio_file = temp_play_file;
            } catch (Error e) {
                warning("Waveform scan: decrypt failed: %s", e.message);
                audio_file = file;
            }
        }

        if (audio_file == null) return;

        scan_peaks.clear();

        // Pipeline + uridecodebin — NO playbin, NO autoaudiosink, ZERO PipeWire
        // uridecodebin only decodes, it creates NO sinks
        var scan_pipe = new Gst.Pipeline("waveform-scanner");
        var sc_src = ElementFactory.make("uridecodebin", "sc-src");
        var sc_conv = ElementFactory.make("audioconvert", "sc-conv");
        var sc_resample = ElementFactory.make("audioresample", "sc-resample");
        var sc_caps = ElementFactory.make("capsfilter", "sc-caps");
        var sc_level = ElementFactory.make("level", "sc-level");
        var sc_sink = ElementFactory.make("fakesink", "sc-sink");

        if (sc_src == null || sc_conv == null || sc_resample == null || sc_caps == null || sc_level == null || sc_sink == null) {
            return;
        }

        sc_caps.set("caps", Caps.from_string("audio/x-raw, rate=8000, channels=1"));
        sc_level.set("interval", (uint64)50000000); // 50ms intervals → ~20 peaks/sec
        sc_level.set("post-messages", true);
        sc_sink.set("sync", false); // Process faster than real-time

        // Only decode audio streams (caps filter on uridecodebin)
        sc_src.set("caps", Caps.from_string("audio/x-raw"));

        scan_pipe.add_many(sc_src, sc_conv, sc_resample, sc_caps, sc_level, sc_sink);
        sc_conv.link(sc_resample);
        sc_resample.link(sc_caps);
        sc_caps.link(sc_level);
        sc_level.link(sc_sink);

        // Dynamic pad linking from uridecodebin
        sc_src.pad_added.connect((pad) => {
            var sink_pad = sc_conv.get_static_pad("sink");
            if (sink_pad != null && !sink_pad.is_linked()) {
                pad.link(sink_pad);
            }
        });

        sc_src.set("uri", audio_file.get_uri());
        scan_element = scan_pipe;

        Gst.Bus sbus = scan_pipe.get_bus();

        scan_bus_watch_id = sbus.add_watch(0, (bus, msg) => {
            if (msg.type == Gst.MessageType.ELEMENT && msg.src != null && msg.src.name == "sc-level") {
                unowned Gst.Structure st = msg.get_structure();
                if (st != null && st.has_field("peak")) {
                    unowned GLib.Value? pk = st.get_value("peak");
                    if (pk != null) {
                        void* boxed = pk.get_boxed();
                        if (boxed != null) {
                            unowned GLib.Value? v = gva_get_nth(boxed, 0);
                            if (v != null) {
                                scan_peaks.add(db_to_visual(v.get_double()));
                            }
                        }
                    }
                }
            } else if (msg.type == Gst.MessageType.EOS) {
                finalize_waveform();
                // Don't call Source.remove from inside callback — return false instead
                scan_bus_watch_id = 0;
                if (scan_timeout_id != 0) {
                    Source.remove(scan_timeout_id);
                    scan_timeout_id = 0;
                }
                if (scan_element != null) {
                    scan_element.set_state(State.NULL);
                    scan_element = null;
                }
                return false; // Removes this bus watch source
            } else if (msg.type == Gst.MessageType.ERROR) {
                scan_bus_watch_id = 0;
                if (scan_timeout_id != 0) {
                    Source.remove(scan_timeout_id);
                    scan_timeout_id = 0;
                }
                if (scan_element != null) {
                    scan_element.set_state(State.NULL);
                    scan_element = null;
                }
                return false; // Removes this bus watch source
            }
            return true;
        });

        scan_element.set_state(State.PLAYING);

        // Safety timeout: force cleanup if scan hangs (10 seconds)
        scan_timeout_id = Timeout.add(10000, () => {
            scan_timeout_id = 0; // Clear before cleanup to prevent double-remove
            if (scan_element != null) {
                debug("AudioPlayerWidget: scan timeout, forcing cleanup");
                finalize_waveform();
                cleanup_scan();
            }
            return false;
        });
    }

    private void finalize_waveform() {
        if (scan_peaks.size == 0) return;

        waveform_bars = new double[N_BARS];

        if (scan_peaks.size <= N_BARS) {
            // Fewer peaks than bars: spread evenly
            for (int i = 0; i < N_BARS; i++) {
                int src = (int)((double)i / N_BARS * scan_peaks.size);
                src = int.min(src, scan_peaks.size - 1);
                waveform_bars[i] = scan_peaks[src];
            }
        } else {
            // More peaks than bars: take max of each group for dynamic waveform
            double group_size = (double)scan_peaks.size / N_BARS;
            for (int i = 0; i < N_BARS; i++) {
                int start = (int)(i * group_size);
                int end = (int)((i + 1) * group_size);
                end = int.min(end, scan_peaks.size);
                double max_val = 0;
                for (int j = start; j < end; j++) {
                    double v = scan_peaks[j];
                    if (v > max_val) max_val = v;
                }
                waveform_bars[i] = max_val;
            }
        }

        waveform_ready = true;
        waveform_area.queue_draw();
    }

    private void cleanup_scan() {
        if (scan_timeout_id != 0) {
            Source.remove(scan_timeout_id);
            scan_timeout_id = 0;
        }
        // Remove bus watch FIRST to prevent callbacks during teardown
        if (scan_bus_watch_id != 0) {
            Source.remove(scan_bus_watch_id);
            scan_bus_watch_id = 0;
        }
        if (scan_element != null) {
            scan_element.set_state(State.NULL);
            scan_element = null;
        }
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
            setup_pipeline.begin((obj, res) => {
                // After pipeline is set up, seek to saved position if we have one
                if (pipeline != null && saved_position > 0) {
                    seek_to(saved_position);
                    saved_position = 0;
                }
            });
            return;
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
            update_id = Timeout.add(50, update_progress);
        }
    }
    
    private void pause() {
        // Save current position before stopping pipeline
        if (pipeline != null) {
            pipeline.query_position(Format.TIME, out saved_position);
        }
        is_playing = false;
        play_button.icon_name = "media-playback-start-symbolic";
        
        if (update_id != 0) {
            Source.remove(update_id);
            update_id = 0;
        }
        
        // Fully stop pipeline to release PipeWire/PulseAudio connection
        // Remove bus watch FIRST to prevent callbacks during teardown
        if (bus_watch_id != 0) {
            Source.remove(bus_watch_id);
            bus_watch_id = 0;
        }
        if (pipeline != null) {
            pipeline.set_state(State.NULL);
            pipeline = null;
        }
    }

    private void stop() {
        // Remove bus watch FIRST to prevent callbacks during teardown
        if (bus_watch_id != 0) {
            Source.remove(bus_watch_id);
            bus_watch_id = 0;
        }
        if (pipeline != null) {
            pipeline.set_state(State.NULL);
            pipeline = null;
        }
        is_playing = false;
        play_button.icon_name = "media-playback-start-symbolic";
        playback_progress = 0.0;
        waveform_area.queue_draw();
        
        if (update_id != 0) {
            Source.remove(update_id);
            update_id = 0;
        }
    }
    
    private async void setup_pipeline() {
        File file_to_play;

        // Reuse already-decrypted temp file from waveform scan if available
        if (temp_play_file != null) {
            file_to_play = temp_play_file;
        } else {
            var file = file_transfer.get_file();
            if (file == null) {
                // Already failed or download error? Don't wait
                if (file_transfer.state == FileTransfer.State.FAILED ||
                    (file_transfer.state == FileTransfer.State.NOT_STARTED && file_transfer.info != null)) {
                    play_button.icon_name = "dialog-error-symbolic";
                    play_button.sensitive = false;
                    play_button.tooltip_text = _("File corrupted or unavailable");
                    return;
                }

                // File not yet downloaded -- wait for download to complete or fail
                play_button.icon_name = "content-loading-symbolic";
                play_button.sensitive = false;

                bool resolved = false;
                ulong notify_path_id = 0;
                ulong notify_state_id = 0;
                SourceFunc cb = setup_pipeline.callback;

                notify_path_id = file_transfer.notify["path"].connect(() => {
                    if (file_transfer.path != null && !resolved) {
                        resolved = true;
                        Idle.add((owned) cb);
                    }
                });

                // Watch for FAILED or back to NOT_STARTED (download error)
                notify_state_id = file_transfer.notify["state"].connect(() => {
                    if ((file_transfer.state == FileTransfer.State.FAILED ||
                         file_transfer.state == FileTransfer.State.NOT_STARTED) && !resolved) {
                        resolved = true;
                        Idle.add((owned) cb);
                    }
                });

                // Safety timeout 30s
                uint timeout_id = Timeout.add(30000, () => {
                    if (!resolved) {
                        resolved = true;
                        cb();
                    }
                    return false;
                });

                yield;

                Source.remove(timeout_id);
                file_transfer.disconnect(notify_path_id);
                file_transfer.disconnect(notify_state_id);

                if (file_transfer.state == FileTransfer.State.FAILED ||
                    file_transfer.state == FileTransfer.State.NOT_STARTED) {
                    play_button.icon_name = "dialog-error-symbolic";
                    play_button.sensitive = false;
                    play_button.tooltip_text = _("File corrupted or unavailable");
                    return;
                }

                play_button.icon_name = "media-playback-start-symbolic";
                play_button.sensitive = true;

                file = file_transfer.get_file();
                if (file == null) {
                    warning("Audio file download timed out");
                    play_button.icon_name = "dialog-error-symbolic";
                    play_button.sensitive = false;
                    return;
                }
            }

            file_to_play = file;
            try {
                var app = (Dino.Application) GLib.Application.get_default();
                var enc = app.file_encryption;

                string temp_dir = Path.build_filename(Environment.get_user_cache_dir(), "dinox", "temp_audio");
                DirUtils.create_with_parents(temp_dir, 0700);

                string ext = "";
                if ("." in file_transfer.file_name) {
                    string[] parts = file_transfer.file_name.split(".");
                    ext = "." + parts[parts.length - 1];
                }
                string random_name = GLib.Uuid.string_random() + ext;
                string temp_path = Path.build_filename(temp_dir, random_name);
                temp_play_file = File.new_for_path(temp_path);

                var source_stream = file.read();
                var target_stream = temp_play_file.replace(null, false, GLib.FileCreateFlags.NONE);
                yield enc.decrypt_stream(source_stream, target_stream);
                try { source_stream.close(); } catch (Error e) {}
                try { target_stream.close(); } catch (Error e) {}

                file_to_play = temp_play_file;
            } catch (Error e) {
                warning("AudioPlayerWidget: Failed to decrypt audio: %s", e.message);
            }
        }

        // Use Pipeline + uridecodebin — NO playbin, NO autovideosink
        // Only autoaudiosink for the actual audio output (1 PipeWire entry, released on NULL)
        var play_pipe = new Gst.Pipeline("audio-playback");
        var play_src = ElementFactory.make("uridecodebin", "play-src");
        var play_conv = ElementFactory.make("audioconvert", "play-conv");
        var play_sink = ElementFactory.make("autoaudiosink", "play-sink");

        if (play_src == null || play_conv == null || play_sink == null) {
            warning("Could not create audio playback pipeline");
            return;
        }

        // Only decode audio (no video pads → no PipeWire video entry from album art)
        play_src.set("caps", Caps.from_string("audio/x-raw"));
        play_src.set("uri", file_to_play.get_uri());

        play_pipe.add_many(play_src, play_conv, play_sink);
        play_conv.link(play_sink);

        // Dynamic pad linking from uridecodebin
        play_src.pad_added.connect((pad) => {
            var sink_pad = play_conv.get_static_pad("sink");
            if (sink_pad != null && !sink_pad.is_linked()) {
                pad.link(sink_pad);
            }
        });

        pipeline = play_pipe;
        
        Gst.Bus bus = play_pipe.get_bus();
        bus_watch_id = bus.add_watch(0, bus_callback);
        
        // Lazy waveform scan: only now (first play click) do we create a scan pipeline.
        // The scan pipeline uses fakesink only — no PipeWire entry.
        if (!waveform_ready) {
            scan_waveform.begin();
        }
        
        // Start playing after setup
        play();
    }
    
    private bool bus_callback(Gst.Bus bus, Gst.Message msg) {
        switch (msg.type) {
            case Gst.MessageType.EOS:
                stop();
                time_label.label = format_time(0);
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
        pipeline.query_duration(Format.TIME, out duration);
    }
    
    private bool update_progress() {
        if (pipeline != null) {
            int64 position;
            if (pipeline.query_position(Format.TIME, out position)) {
                time_label.label = format_time(position);
                if (duration > 0) {
                    playback_progress = (double)position / (double)duration;
                    playback_progress = double.max(0.0, double.min(1.0, playback_progress));
                }
                waveform_area.queue_draw();
            }
            
            if (duration <= 0) query_duration();
        }
        return true;
    }
    
    private void seek_to(int64 position) {
        if (pipeline != null) {
            pipeline.seek(playback_rate, Format.TIME, SeekFlags.FLUSH | SeekFlags.ACCURATE, 
                          Gst.SeekType.SET, position, Gst.SeekType.NONE, -1);
            time_label.label = format_time(position);
            if (duration > 0) {
                playback_progress = (double)position / (double)duration;
                playback_progress = double.max(0.0, double.min(1.0, playback_progress));
            }
            waveform_area.queue_draw();
        }
    }
    
    private string format_time(int64 ns) {
        int64 s = ns / Gst.SECOND;
        return "%d:%02d".printf((int)(s / 60), (int)(s % 60));
    }
    
    public override void dispose() {
        stop();
        cleanup_scan();
        file_transfer = null;
        if (temp_play_file != null) {
            try {
                temp_play_file.delete(null);
            } catch (Error e) {}
            temp_play_file = null;
        }
        base.dispose();
    }
}

}
