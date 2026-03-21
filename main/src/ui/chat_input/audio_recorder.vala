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
    private Element convert2;  // S16LE → F32LE for encoder
    private Element encoder;
    private Element parser;
    private Element muxer;
    private Element sink;
    private Gst.Bus? bus;
    private uint bus_watch_id = 0;
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
    public signal void recording_error(string message);

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
        var app = (Dino.Ui.Application) GLib.Application.get_default();
        source = app.av_device_service.create_audio_source(app.settings.msg_audio_input_device);
        volume = ElementFactory.make("volume", "volume");
        level = ElementFactory.make("level", "level");
        convert = ElementFactory.make("audioconvert", "convert");
        resample = ElementFactory.make("audioresample", "resample");
        capsfilter = ElementFactory.make("capsfilter", "capsfilter");
        encoder = ElementFactory.make("avenc_aac", "encoder");
        if (encoder == null) {
            encoder = ElementFactory.make("voaacenc", "encoder");
        }
        if (encoder == null) {
            // Windows Media Foundation AAC — available on Windows 10+
            encoder = ElementFactory.make("mfaacenc", "encoder");
        }
        parser = ElementFactory.make("aacparse", "parser");
        muxer = ElementFactory.make("mp4mux", "muxer");
        sink = ElementFactory.make("filesink", "sink");

        if (source == null || volume == null || level == null || convert == null || resample == null || capsfilter == null || encoder == null || parser == null || muxer == null || sink == null) {
            string[] missing = {};
            if (source == null) missing += "audio source";
            if (volume == null) missing += "volume (gstreamer)";
            if (level == null) missing += "level (gst-plugins-good)";
            if (convert == null) missing += "audioconvert (gst-plugins-base)";
            if (resample == null) missing += "audioresample (gst-plugins-base)";
            if (capsfilter == null) missing += "capsfilter (gstreamer)";
            if (encoder == null) missing += "AAC encoder (avenc_aac/voaacenc/mfaacenc)";
            if (parser == null) missing += "aacparse (gst-plugins-good)";
            if (muxer == null) missing += "mp4mux (gst-plugins-good)";
            if (sink == null) missing += "filesink (gstreamer)";
            throw new Error(Quark.from_string("AudioRecorder"), 0,
                "Could not create GStreamer elements. Missing: %s".printf(string.joinv(", ", missing)));
        }

        // 48kHz mono S16LE -- matches PipeWire native rate, avoids resampling artifacts
        // S16LE is required for webrtc noise suppression processing
        capsfilter.set("caps", Caps.from_string("audio/x-raw, rate=48000, channels=1, format=S16LE"));

        // Second audioconvert: S16LE (after NS+compressor) → F32LE (for avenc_aac)
        convert2 = ElementFactory.make("audioconvert", "convert2");

        string encoder_name = encoder.get_factory().get_name();
        if (encoder_name == "avenc_aac" || encoder_name == "voaacenc") {
            // 64kbps is decent for mono AAC-LC
            encoder.set("bitrate", 64000);
        } else if (encoder_name == "mfaacenc") {
            // mfaacenc: bitrate in bps
            encoder.set("bitrate", (uint) 64000);
        }

        // Start muted - unmute after 400ms to suppress PipeWire transient crackling
        volume.set("volume", 0.0);

        // Try to enable faststart for web/streaming compatibility (moves moov atom to beginning)
        // Note: faststart might not be available in older GStreamer versions, but it's standard in recent ones.
        // We just set it; if it doesn't exist, GStreamer will emit a warning but continue.
        muxer.set("faststart", true); // Enabled for iOS/Android compatibility

        sink.set("location", output_path);
        level.set("interval", 100000000); // 100ms
        level.set("post-messages", true);

        // Add all elements to pipeline
        // Clean chain: source → volume → level → convert → resample → capsfilter → convert2 → encoder → parser → muxer → sink
        // No audio processing (noise gate, compressor etc.) — pass-through for cleanest signal
        pipeline.add_many(source, volume, level, convert, resample, capsfilter, convert2, encoder, parser, muxer, sink);
        bool linked = source.link(volume) && volume.link(level) && level.link(convert)
            && convert.link(resample) && resample.link(capsfilter) && capsfilter.link(convert2)
            && convert2.link(encoder) && encoder.link(parser) && parser.link(muxer) && muxer.link(sink);
        if (!linked) {
             throw new Error(Quark.from_string("AudioRecorder"), 0, "Could not link GStreamer elements");
        }

        bus = pipeline.get_bus();
        bus_watch_id = bus.add_watch(0, (b, msg) => {
            if (msg.type == MessageType.ERROR) {
                Error err;
                string debug_info;
                msg.parse_error(out err, out debug_info);
                warning("AudioRecorder: Pipeline error: %s (%s)", err.message, debug_info ?? "(none)");
                Idle.add(() => {
                    cancel_recording();
                    recording_error(err.message);
                    return false;
                });
                return false;
            }
            if (msg.type == MessageType.ELEMENT && level != null && msg.src == level) {
                unowned Gst.Structure structure = msg.get_structure();
                if (structure != null && structure.has_field("peak")) {
                    unowned GLib.Value? peak_value = structure.get_value("peak");
                    if (peak_value != null) {
                        void* peak_boxed = peak_value.get_boxed();
                        if (peak_boxed != null) {
                            unowned GLib.Value? first_val = gva_get_nth(peak_boxed, 0);
                            if (first_val != null) {
                                level_changed(db_to_visual(first_val.get_double()));
                                return true;
                            }
                        }
                    }
                    unowned GLib.Value? rms_value = structure.get_value("rms");
                    if (rms_value != null) {
                        void* rms_boxed = rms_value.get_boxed();
                        if (rms_boxed != null) {
                            unowned GLib.Value? first_val = gva_get_nth(rms_boxed, 0);
                            if (first_val != null) {
                                level_changed(db_to_visual(first_val.get_double()));
                                return true;
                            }
                        }
                    }
                }
            }
            return true;
        });

        pipeline.set_state(State.PLAYING);
        is_recording = true;
        start_time = GLib.get_monotonic_time();

        // Unmute after PipeWire transient has passed (400ms)
        // Volume 1.0 = no software amplification → cleanest signal, system mic gain handles level
        Timeout.add(400, () => {
            if (volume != null && is_recording) {
                volume.set("volume", 1.0);
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

    public void stop_recording() {
        debug("AudioRecorder.stop_recording: called");
        if (timeout_id != 0) {
            Source.remove(timeout_id);
            timeout_id = 0;
        }
        if (pipeline != null && is_recording) {
            // 1. Remove bus watch FIRST — prevents callbacks during teardown
            if (bus_watch_id != 0) {
                Source.remove(bus_watch_id);
                bus_watch_id = 0;
            }
            
            // 2. Send EOS so mp4mux writes the moov atom
            pipeline.send_event(new Event.eos());
            
            // 3. Wait for muxer to finalize (10s — faststart rewrites the entire file)
            if (bus != null) {
                var msg = bus.timed_pop_filtered(10 * Gst.SECOND,
                    Gst.MessageType.EOS | Gst.MessageType.ERROR);
                if (msg == null) {
                    warning("AudioRecorder: EOS timeout after 10s — MP4 may be incomplete");
                } else if (msg.type == Gst.MessageType.ERROR) {
                    Error err;
                    string dbg;
                    msg.parse_error(out err, out dbg);
                    warning("AudioRecorder: Pipeline error during finalization: %s", err.message);
                }
                bus = null;
            }
            
            // 4. Kill pipeline — synchronously releases PipeWire connection
            pipeline.set_state(State.NULL);
            pipeline = null;
            is_recording = false;
            cleanup_elements();
            debug("AudioRecorder.stop_recording: pipeline closed");
        }
    }

    public void cancel_recording() {
        if (timeout_id != 0) {
            Source.remove(timeout_id);
            timeout_id = 0;
        }
        if (pipeline != null) {
            if (bus_watch_id != 0) {
                Source.remove(bus_watch_id);
                bus_watch_id = 0;
            }
            bus = null;
            pipeline.set_state(State.NULL);
            pipeline = null;
            is_recording = false;
            cleanup_elements();
        }
        if (current_output_path != null) {
            FileUtils.unlink(current_output_path);
            current_output_path = null;
        }
    }

    private void cleanup_elements() {
        source = null;
        volume = null;
        level = null;
        convert = null;
        resample = null;
        capsfilter = null;
        convert2 = null;
        encoder = null;
        parser = null;
        muxer = null;
        sink = null;
    }
}

}
