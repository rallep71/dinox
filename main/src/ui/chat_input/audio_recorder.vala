/*
 * Copyright (C) 2025 Ralf Peter <dinox@handwerker.jetzt>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

using Gst;

namespace Dino.Ui.ChatInput {

public class AudioRecorder : GLib.Object {
    private Pipeline pipeline;
    private Element source;
    private Element volume;
    private Element level;
    private Element convert;
    private Element resample;
    private Element capsfilter;
    private Element? noise_suppressor;  // webrtcdsp noise suppression (optional)
    private Element compressor;
    private Element convert2;  // S16LE → F32LE for encoder
    private Element encoder;
    private Element parser;
    private Element muxer;
    private Element sink;
    private Gst.Bus? bus;
    private uint timeout_id = 0;
    private int64 start_time = 0;
    public const int MAX_DURATION_SECONDS = 300; // 5 minutes max recording

    // Direct C binding to avoid GLib.ValueArray deprecation warning (deprecated since GLib 2.32)
    // GStreamer's level element still uses GValueArray internally
    // Wrapper casts void* to GValueArray* to match the C signature
    [CCode (cname = "dino_gva_get_nth")]
    private static extern unowned GLib.Value? gva_get_nth(void* value_array, uint index);

    public string? current_output_path { get; private set; }
    public bool is_recording { get; private set; default = false; }

    public signal void level_changed(double peak);
    public signal void duration_changed(string text);
    public signal void max_duration_reached();

    public AudioRecorder() {
    }

    ~AudioRecorder() {
        if (is_recording) {
            cancel_recording();
        }
    }

    public void start_recording(string output_path) throws Error {
        debug("AudioRecorder.start_recording: output_path=%s", output_path);
        if (is_recording) return;

        current_output_path = output_path;

        pipeline = new Pipeline("audio-recorder");
        // Always use autoaudiosrc - auto-detects PipeWire/PulseAudio/ALSA
        source = ElementFactory.make("autoaudiosrc", "source");
        volume = ElementFactory.make("volume", "volume");
        level = ElementFactory.make("level", "level");
        convert = ElementFactory.make("audioconvert", "convert");
        resample = ElementFactory.make("audioresample", "resample");
        capsfilter = ElementFactory.make("capsfilter", "capsfilter");
        compressor = ElementFactory.make("audiodynamic", "compressor");
        encoder = ElementFactory.make("avenc_aac", "encoder");
        if (encoder == null) {
            encoder = ElementFactory.make("voaacenc", "encoder");
        }
        parser = ElementFactory.make("aacparse", "parser");
        muxer = ElementFactory.make("mp4mux", "muxer");
        sink = ElementFactory.make("filesink", "sink");

        if (source == null || volume == null || level == null || convert == null || resample == null || capsfilter == null || encoder == null || parser == null || muxer == null || sink == null) {
            throw new Error(Quark.from_string("AudioRecorder"), 0, "Could not create GStreamer elements. Missing plugins? (good/bad/ugly/libav)");
        }

        // 48kHz mono S16LE -- matches PipeWire native rate, avoids resampling artifacts
        // S16LE is required for webrtc noise suppression processing
        capsfilter.set("caps", Caps.from_string("audio/x-raw, rate=48000, channels=1, format=S16LE"));

        // WebRTC noise suppression (optional) - reduces constant background hiss/noise
        // Requires gst-plugins-bad with webrtc-audio-processing library
        noise_suppressor = ElementFactory.make("webrtcdsp", "noise-suppressor");
        if (noise_suppressor != null) {
            noise_suppressor.set("noise-suppression", true);
            noise_suppressor.set("gain-control", false);  // we handle gain via volume element
            debug("AudioRecorder: webrtcdsp noise suppression enabled");
        } else {
            debug("AudioRecorder: webrtcdsp not available, recording without noise suppression");
        }

        // Second audioconvert: S16LE (after NS+compressor) → F32LE (for avenc_aac)
        convert2 = ElementFactory.make("audioconvert", "convert2");

        // Log which encoder is actually being used
        string encoder_name = encoder.get_factory().get_name();
        debug("AudioRecorder: using encoder '%s'", encoder_name);

        if (encoder_name == "avenc_aac") {
            encoder.set("bitrate", 96000); // avenc_aac: 96kbps for clear mono speech
        } else if (encoder_name == "voaacenc") {
            encoder.set("bitrate", 128000); // voaacenc: needs higher bitrate for comparable quality
        }

        // Start muted - unmute after 200ms to suppress PipeWire transient crackling
        volume.set("volume", 0.0);

        // Soft-knee compressor/limiter to prevent clipping and reduce dynamic range
        // Threshold 0.5 = -6 dB, ratio 0.3 = ~3:1 compression above threshold
        if (compressor != null) {
            compressor.set("characteristics", 1); // soft-knee
            compressor.set("mode", 0);            // compressor
            compressor.set("threshold", 0.5f);    // activate at 50% amplitude (-6 dB)
            compressor.set("ratio", 0.3f);        // compress to ~30% of excess (≈3:1)
        }
        
        // Try to enable faststart for web/streaming compatibility (moves moov atom to beginning)
        // Note: faststart might not be available in older GStreamer versions, but it's standard in recent ones.
        // We just set it; if it doesn't exist, GStreamer will emit a warning but continue.
        muxer.set("faststart", true); // Enabled for iOS/Android compatibility

        sink.set("location", output_path);
        level.set("interval", 100000000); // 100ms
        level.set("post-messages", true);

        // Add base elements to pipeline
        pipeline.add_many(source, volume, level, convert, resample, capsfilter, convert2, encoder, parser, muxer, sink);
        // Add optional processing elements
        if (noise_suppressor != null) {
            pipeline.add(noise_suppressor);
        }
        if (compressor != null) {
            pipeline.add(compressor);
        }

        // Link common prefix: source → volume → level → convert → resample → capsfilter
        bool linked = source.link(volume) && volume.link(level) && level.link(convert) && convert.link(resample) && resample.link(capsfilter);

        // Link optional chain: capsfilter → [webrtcdsp] → [compressor] → convert2
        Element last = capsfilter;
        if (noise_suppressor != null) {
            linked = linked && last.link(noise_suppressor);
            last = noise_suppressor;
        }
        if (compressor != null) {
            linked = linked && last.link(compressor);
            last = compressor;
        }
        linked = linked && last.link(convert2);

        // Link common suffix: convert2 → encoder → parser → muxer → sink
        linked = linked && convert2.link(encoder) && encoder.link(parser) && parser.link(muxer) && muxer.link(sink);
        if (!linked) {
             throw new Error(Quark.from_string("AudioRecorder"), 0, "Could not link GStreamer elements");
        }

        bus = pipeline.get_bus();
        bus.add_signal_watch();
        bus.message.connect(on_bus_message);

        pipeline.set_state(State.PLAYING);
        is_recording = true;
        start_time = GLib.get_monotonic_time();

        // Unmute after PipeWire transient has passed (200ms)
        // Silent buffers still flow (no timestamp gaps), only transient crackling is suppressed
        Timeout.add(200, () => {
            if (volume != null && is_recording) {
                volume.set("volume", 1.8);
            }
            return false;
        });

        timeout_id = Timeout.add(100, update_duration);
    }

    // Convert dB to perceptual 0.0-1.0 range with non-linear curve
    // Speech typically sits at -30 to -10 dB; linear mapping makes this 3-30% which is too flat.
    // This curve maps -40 dB -> 0.0, -20 dB -> 0.5, 0 dB -> 1.0 (perceptually natural)
    private double db_to_visual(double db) {
        if (db <= -60.0) return 0.0;
        // Normalize to 0.0-1.0 range: -40 dB = 0.0, 0 dB = 1.0
        double normalized = (db + 40.0) / 40.0;
        normalized = double.max(0.0, double.min(normalized, 1.0));
        // Square root curve for perceptual scaling (boosts quiet values)
        return Math.sqrt(normalized);
    }

    private void on_bus_message(Gst.Bus bus, Gst.Message msg) {
        if (msg.type == MessageType.ELEMENT && msg.src == level) {

            unowned Gst.Structure structure = msg.get_structure();
            if (structure != null && structure.has_field("peak")) {
                unowned GLib.Value? peak_value = structure.get_value("peak");
                if (peak_value != null) {
                    void* peak_boxed = peak_value.get_boxed();
                    if (peak_boxed != null) {
                        unowned GLib.Value? first_val = gva_get_nth(peak_boxed, 0);
                        if (first_val != null) {
                            level_changed(db_to_visual(first_val.get_double()));
                            return;
                        }
                    }
                }
                // Fallback: try "rms" field
                unowned GLib.Value? rms_value = structure.get_value("rms");
                if (rms_value != null) {
                    void* rms_boxed = rms_value.get_boxed();
                    if (rms_boxed != null) {
                        unowned GLib.Value? first_val = gva_get_nth(rms_boxed, 0);
                        if (first_val != null) {
                            level_changed(db_to_visual(first_val.get_double()));
                            return;
                        }
                    }
                }
            }
        }
    }

    private bool update_duration() {
        if (!is_recording) return false;
        int64 now = GLib.get_monotonic_time();
        int64 diff = now - start_time;
        int seconds = (int)(diff / 1000000);
        int mins = seconds / 60;
        int secs = seconds % 60;

        if (seconds >= MAX_DURATION_SECONDS) {
            duration_changed("%d:%02d".printf(mins, secs));
            max_duration_reached();
            return false;
        }

        // Show remaining time in last 30 seconds
        if (seconds >= MAX_DURATION_SECONDS - 30) {
            int remaining = MAX_DURATION_SECONDS - seconds;
            duration_changed("%d:%02d (-%ds)".printf(mins, secs, remaining));
        } else {
            duration_changed("%d:%02d".printf(mins, secs));
        }
        return true;
    }

    public async void stop_recording_async() {
        debug("AudioRecorder.stop_recording_async: called");
        if (timeout_id != 0) {
            Source.remove(timeout_id);
            timeout_id = 0;
        }
        if (pipeline != null && is_recording) {
            debug("AudioRecorder.stop_recording_async: sending EOS");
            pipeline.send_event(new Event.eos());
            
            // Wait for EOS or Error
            ulong signal_id = 0;
            SourceFunc callback = stop_recording_async.callback;
            
            bool eos_handled = false;
            signal_id = bus.message.connect((bus, msg) => {
                if (!eos_handled && (msg.type == Gst.MessageType.EOS || msg.type == Gst.MessageType.ERROR)) {
                    eos_handled = true;
                    debug("AudioRecorder.stop_recording_async: Received %s", msg.type.to_string());
                    Idle.add((owned) callback);
                }
            });
            
            // Safety timeout (2 seconds)
            uint timeout_source = 0;
            timeout_source = Timeout.add(2000, () => {
                debug("AudioRecorder.stop_recording_async: Timeout reached");
                callback();
                timeout_source = 0;
                return false;
            });
            
            yield;
            debug("AudioRecorder.stop_recording_async: finished yield");
            
            if (timeout_source != 0) {
                Source.remove(timeout_source);
                timeout_source = 0;
            }
            if (bus != null) {
                bus.disconnect(signal_id);
                // Important: Remove the signal watch to stop the bus from polling the main loop
                bus.remove_signal_watch();
                bus = null;
            }
            
            if (pipeline != null) {
                pipeline.set_state(State.NULL);
                pipeline = null;
            }
            is_recording = false;
        }
    }

    public void stop_recording() {
        stop_recording_async.begin();
    }

    public void cancel_recording() {
        if (timeout_id != 0) {
            Source.remove(timeout_id);
            timeout_id = 0;
        }
        if (pipeline != null) {
            if (bus != null) {
                bus.remove_signal_watch();
                bus = null;
            }
            pipeline.set_state(State.NULL);
            pipeline = null;
            is_recording = false;
        }
        if (current_output_path != null) {
            FileUtils.unlink(current_output_path);
            current_output_path = null;
        }
    }
}

}
