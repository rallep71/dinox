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

public class VideoRecorder : GLib.Object {
    private Pipeline pipeline;
    private Element video_source;
    private Element video_convert;
    private Element video_scale;
    private Element video_rate;
    private Element video_capsfilter;
    private Element video_encoder;
    private Element? video_parser;
    private Element video_queue;
    private Element audio_source;
    private Element audio_convert;
    private Element audio_resample;
    private Element audio_capsfilter;
    private Element audio_volume;
    private Element? noise_suppressor;  // webrtcdsp noise suppression (optional)
    private Element audio_encoder;
    private Element audio_convert2;
    private Element audio_parser;
    private Element audio_queue;
    private Element muxer;
    private Element sink;
    private Element tee;
    private Element preview_queue;
    private Element preview_convert;
    private Element preview_sink;
    private bool preview_is_pixbufsink = false;
    private Gst.Bus? bus;
    private uint timeout_id = 0;
    private int64 start_time = 0;
    public const int MAX_DURATION_SECONDS = 120; // 2 minutes

    public string? current_output_path { get; private set; }
    public bool is_recording { get; private set; default = false; }

    // GdkPixbuf sink element for live preview in the popover
    public Element? gtk_sink { get; private set; }

    public signal void duration_changed(string text);
    public signal void max_duration_reached();

    public VideoRecorder() {
    }

    ~VideoRecorder() {
        if (is_recording) {
            cancel_recording();
        }
    }

    public void start_recording(string output_path) throws Error {
        debug("VideoRecorder.start_recording: output_path=%s", output_path);
        if (is_recording) return;

        current_output_path = output_path;

        pipeline = new Pipeline("video-recorder");

        // === VIDEO branch ===
        if (ElementFactory.find("pipewiresrc") != null) {
            video_source = ElementFactory.make("pipewiresrc", "video-source");
            // PipeWire auto-detects camera via downstream video caps negotiation
        } else {
            video_source = ElementFactory.make("v4l2src", "video-source");
        }
        video_convert = ElementFactory.make("videoconvert", "video-convert");
        video_scale = ElementFactory.make("videoscale", "video-scale");
        video_rate = ElementFactory.make("videorate", "video-rate");
        video_capsfilter = ElementFactory.make("capsfilter", "video-caps");
        video_queue = ElementFactory.make("queue", "video-queue");

        // Tee for preview + recording
        tee = ElementFactory.make("tee", "video-tee");
        preview_queue = ElementFactory.make("queue", "preview-queue");
        preview_convert = ElementFactory.make("videoconvert", "preview-convert");

        // GdkPixbuf sink for live preview - available in gst-plugins-good
        preview_sink = ElementFactory.make("gdkpixbufsink", "preview-sink");
        if (preview_sink != null) {
            preview_is_pixbufsink = true;
        } else {
            // Fallback: use appsink to pull RGBA frames manually
            preview_is_pixbufsink = false;
            preview_sink = ElementFactory.make("appsink", "preview-sink");
            if (preview_sink != null) {
                preview_sink.set("sync", true);
                preview_sink.set("max-buffers", 1);
                preview_sink.set("drop", true);
                preview_sink.set("emit-signals", false);
                preview_sink.set("caps", Caps.from_string("video/x-raw, format=RGBA"));
            }
            debug("gdkpixbufsink not available, using appsink for preview");
        }

        // H.264 encoder - try hardware first, then software fallbacks
        video_encoder = ElementFactory.make("vaapih264enc", "video-encoder");
        if (video_encoder == null) {
            video_encoder = ElementFactory.make("vah264enc", "video-encoder");
        }
        if (video_encoder == null) {
            video_encoder = ElementFactory.make("x264enc", "video-encoder");
            if (video_encoder != null) {
                // Software encoder: tune for speed and low latency
                video_encoder.set("speed-preset", 2); // superfast
                video_encoder.set("tune", 4); // zerolatency
                video_encoder.set("bitrate", 1500); // kbps (x264enc takes kbps)
                video_encoder.set("key-int-max", 60);
            }
        }
        if (video_encoder == null) {
            // Fallback: avenc_h264 from gst-libav (ffmpeg) - available in Flatpak via ffmpeg-full extension
            video_encoder = ElementFactory.make("avenc_h264", "video-encoder");
            if (video_encoder != null) {
                debug("Using avenc_h264 (ffmpeg) as H.264 encoder fallback");
                video_encoder.set("bitrate", 1500000); // bps (avenc uses bps, not kbps)
                video_encoder.set("max-threads", 2);
            }
        }
        if (video_encoder == null) {
            // Fallback: openh264enc from gst-plugins-bad - available in GNOME Platform runtime (Flatpak)
            video_encoder = ElementFactory.make("openh264enc", "video-encoder");
            if (video_encoder != null) {
                debug("Using openh264enc as H.264 encoder fallback");
                video_encoder.set("bitrate", 1500000); // bps
                video_encoder.set("complexity", 1);     // medium complexity
            }
        }
        // h264parse is optional - avenc_h264 output can go directly to mp4mux
        video_parser = ElementFactory.make("h264parse", "video-parser");
        if (video_parser == null) {
            debug("h264parse not available, will link encoder directly to muxer");
        }

        // === AUDIO branch ===
        // Always use autoaudiosrc for audio - it auto-detects PipeWire/PulseAudio/ALSA
        // (pipewiresrc defaults to video and stream-properties don't reliably force audio)
        audio_source = ElementFactory.make("autoaudiosrc", "audio-source");
        audio_convert = ElementFactory.make("audioconvert", "audio-convert");
        audio_resample = ElementFactory.make("audioresample", "audio-resample");
        audio_capsfilter = ElementFactory.make("capsfilter", "audio-caps");
        audio_volume = ElementFactory.make("volume", "audio-volume");
        audio_queue = ElementFactory.make("queue", "audio-queue");
        // Second audioconvert: S16LE (from capsfilter) -> F32LE (for avenc_aac)
        audio_convert2 = ElementFactory.make("audioconvert", "audio-convert2");
        audio_encoder = ElementFactory.make("avenc_aac", "audio-encoder");
        if (audio_encoder == null) {
            audio_encoder = ElementFactory.make("voaacenc", "audio-encoder");
        }
        audio_parser = ElementFactory.make("aacparse", "audio-parser");

        // WebRTC noise suppression for audio (optional) - reduces constant background hiss/noise
        noise_suppressor = ElementFactory.make("webrtcdsp", "audio-noise-suppressor");
        if (noise_suppressor != null) {
            noise_suppressor.set("noise-suppression", true);
            noise_suppressor.set("gain-control", false);  // we handle gain via volume element
            debug("VideoRecorder: webrtcdsp audio noise suppression enabled");
        } else {
            debug("VideoRecorder: webrtcdsp not available, recording audio without noise suppression");
        }

        // === Muxer + Sink ===
        muxer = ElementFactory.make("mp4mux", "muxer");
        sink = ElementFactory.make("filesink", "sink");

        // Validate all required elements - log which ones are missing for diagnostics
        string[] missing = {};
        if (video_source == null) missing += "video_source (pipewiresrc/v4l2src)";
        if (video_convert == null) missing += "videoconvert (gst-plugins-base)";
        if (video_scale == null) missing += "videoscale (gst-plugins-base)";
        if (video_rate == null) missing += "videorate (gst-plugins-base)";
        if (video_capsfilter == null) missing += "capsfilter (gstreamer)";
        if (video_encoder == null) missing += "h264 encoder (x264enc from gst-plugins-ugly, vaapih264enc/vah264enc from gst-plugins-bad, avenc_h264 from gst-libav, or openh264enc from gst-plugins-bad)";
        if (tee == null) missing += "tee (gstreamer)";
        if (preview_queue == null) missing += "queue (gstreamer)";
        if (video_queue == null) missing += "queue (gstreamer)";
        if (audio_source == null) missing += "autoaudiosrc (gst-plugins-base)";
        if (audio_convert == null) missing += "audioconvert (gst-plugins-base)";
        if (audio_resample == null) missing += "audioresample (gst-plugins-base)";
        if (audio_capsfilter == null) missing += "capsfilter (gstreamer)";
        if (audio_encoder == null) missing += "AAC encoder (avenc_aac from gst-libav, or voaacenc from gst-plugins-bad)";
        if (audio_parser == null) missing += "aacparse (gst-plugins-good)";
        if (audio_queue == null) missing += "queue (gstreamer)";
        if (muxer == null) missing += "mp4mux (gst-plugins-good)";
        if (sink == null) missing += "filesink (gstreamer)";
        if (missing.length > 0) {
            string details = string.joinv(", ", missing);
            throw new Error(Quark.from_string("VideoRecorder"), 0,
                "Could not create GStreamer elements. Missing: %s. Install: gst-plugins-good, gst-plugins-bad, gst-plugins-ugly, gst-libav".printf(details));
        }

        // Configure video caps: max 720p, max 30fps - accept lower resolutions
        video_capsfilter.set("caps", Caps.from_string(
            "video/x-raw, width=[1,1280], height=[1,720], framerate=[1/1,30/1]"));

        // Configure audio caps: 48kHz mono
        audio_capsfilter.set("caps", Caps.from_string(
            "audio/x-raw, rate=48000, channels=1, format=S16LE"));

        // Mute during PipeWire connection transient, unmute after stabilization
        audio_volume.set("volume", 0.0);

        // AAC bitrate for audio in video
        string audio_enc_name = audio_encoder.get_factory().get_name();
        debug("VideoRecorder: using audio encoder '%s'", audio_enc_name);
        if (audio_enc_name == "avenc_aac") {
            audio_encoder.set("bitrate", 96000);  // avenc_aac: 96kbps for clear mono speech
        } else if (audio_enc_name == "voaacenc") {
            audio_encoder.set("bitrate", 128000); // voaacenc: needs higher bitrate for comparable quality
        }

        sink.set("location", output_path);

        // Queue settings for smooth recording
        video_queue.set("max-size-time", (uint64)3000000000); // 3s buffer
        video_queue.set("max-size-buffers", 0);
        video_queue.set("max-size-bytes", 0);
        audio_queue.set("max-size-time", (uint64)3000000000);
        audio_queue.set("max-size-buffers", 0);
        audio_queue.set("max-size-bytes", 0);
        preview_queue.set("max-size-buffers", 3);
        preview_queue.set("leaky", 2); // downstream = drop oldest

        // Add all elements to pipeline
        pipeline.add_many(video_source, video_convert, video_scale, video_rate,
            video_capsfilter, tee, video_queue, video_encoder,
            preview_queue, preview_convert, preview_sink,
            audio_source, audio_volume, audio_convert, audio_resample, audio_capsfilter,
            audio_queue, audio_convert2, audio_encoder, audio_parser,
            muxer, sink);
        if (video_parser != null) {
            pipeline.add(video_parser);
        }
        if (noise_suppressor != null) {
            pipeline.add(noise_suppressor);
        }

        // Link video source chain up to tee
        // video_source → video_convert → video_scale → video_rate → video_caps → tee
        if (!video_source.link(video_convert) || !video_convert.link(video_scale) ||
            !video_scale.link(video_rate) || !video_rate.link(video_capsfilter) ||
            !video_capsfilter.link(tee)) {
            throw new Error(Quark.from_string("VideoRecorder"), 0,
                "Could not link video source chain");
        }

        // Tee → preview branch: preview_queue → preview_convert → preview_sink
        var tee_preview_pad = tee.request_pad_simple("src_%u");
        var preview_queue_pad = preview_queue.get_static_pad("sink");
        if (tee_preview_pad.link(preview_queue_pad) != PadLinkReturn.OK) {
            throw new Error(Quark.from_string("VideoRecorder"), 0,
                "Could not link tee to preview queue");
        }
        if (!preview_queue.link(preview_convert) || !preview_convert.link(preview_sink)) {
            throw new Error(Quark.from_string("VideoRecorder"), 0,
                "Could not link preview branch");
        }

        // Tee → record branch: video_queue → video_encoder → [video_parser →] muxer
        var tee_record_pad = tee.request_pad_simple("src_%u");
        var record_queue_pad = video_queue.get_static_pad("sink");
        if (tee_record_pad.link(record_queue_pad) != PadLinkReturn.OK) {
            throw new Error(Quark.from_string("VideoRecorder"), 0,
                "Could not link tee to record queue");
        }
        if (!video_queue.link(video_encoder)) {
            throw new Error(Quark.from_string("VideoRecorder"), 0,
                "Could not link video_queue → video_encoder");
        }
        if (video_parser != null) {
            // encoder → parser → muxer
            if (!video_encoder.link(video_parser) || !video_parser.link(muxer)) {
                throw new Error(Quark.from_string("VideoRecorder"), 0,
                    "Could not link video_encoder → video_parser → muxer");
            }
        } else {
            // encoder → muxer directly (avenc_h264 output is compatible with mp4mux)
            if (!video_encoder.link(muxer)) {
                throw new Error(Quark.from_string("VideoRecorder"), 0,
                    "Could not link video_encoder → muxer");
            }
        }

        // Audio chain: audio_source → volume → convert → resample → caps → [webrtcdsp] → queue → convert2 → encoder → parser → muxer
        if (!audio_source.link(audio_volume)) {
            throw new Error(Quark.from_string("VideoRecorder"), 0, "Could not link audio_source → audio_volume");
        }
        if (!audio_volume.link(audio_convert)) {
            throw new Error(Quark.from_string("VideoRecorder"), 0, "Could not link audio_volume → audio_convert");
        }
        if (!audio_convert.link(audio_resample)) {
            throw new Error(Quark.from_string("VideoRecorder"), 0, "Could not link audio_convert → audio_resample");
        }
        if (!audio_resample.link(audio_capsfilter)) {
            throw new Error(Quark.from_string("VideoRecorder"), 0, "Could not link audio_resample → audio_capsfilter");
        }
        // Link optional noise suppression between capsfilter and queue
        Element audio_last = audio_capsfilter;
        if (noise_suppressor != null) {
            if (!audio_last.link(noise_suppressor)) {
                throw new Error(Quark.from_string("VideoRecorder"), 0, "Could not link audio_capsfilter → webrtcdsp");
            }
            audio_last = noise_suppressor;
        }
        if (!audio_last.link(audio_queue)) {
            throw new Error(Quark.from_string("VideoRecorder"), 0, "Could not link audio chain → audio_queue");
        }
        if (!audio_queue.link(audio_convert2)) {
            throw new Error(Quark.from_string("VideoRecorder"), 0, "Could not link audio_queue → audio_convert2");
        }
        if (!audio_convert2.link(audio_encoder)) {
            throw new Error(Quark.from_string("VideoRecorder"), 0, "Could not link audio_convert2 → audio_encoder");
        }
        if (!audio_encoder.link(audio_parser)) {
            throw new Error(Quark.from_string("VideoRecorder"), 0, "Could not link audio_encoder → audio_parser");
        }
        if (!audio_parser.link(muxer)) {
            throw new Error(Quark.from_string("VideoRecorder"), 0, "Could not link audio_parser → muxer");
        }

        // Muxer → sink
        if (!muxer.link(sink)) {
            throw new Error(Quark.from_string("VideoRecorder"), 0,
                "Could not link muxer to sink");
        }

        // Store preview sink reference for the popover to access
        gtk_sink = preview_sink;

        bus = pipeline.get_bus();
        bus.add_signal_watch();
        bus.message.connect(on_bus_message);

        // Start directly in PLAYING - live sources (pipewiresrc, autoaudiosrc)
        // don't produce data in PAUSED state and may block preroll.
        // Direct PLAYING start is the reliable approach for live pipelines.
        pipeline.set_state(State.PLAYING);
        is_recording = true;
        start_time = GLib.get_monotonic_time();
        timeout_id = Timeout.add(100, update_duration);

        // Unmute after PipeWire transient has passed (200ms)
        // Volume 0→1.5: silent buffers still flow, no timestamp gaps
        Timeout.add(200, () => {
            if (audio_volume != null && is_recording) {
                audio_volume.set("volume", 1.5);
            }
            return false;
        });
    }

    private void on_bus_message(Gst.Bus bus, Gst.Message msg) {
        if (msg.type == MessageType.ERROR) {
            Error err;
            string debug_info;
            msg.parse_error(out err, out debug_info);
            warning("VideoRecorder: Pipeline error: %s (%s)", err.message, debug_info);
        } else if (msg.type == MessageType.WARNING) {
            Error warn;
            string debug_info;
            msg.parse_warning(out warn, out debug_info);
            debug("VideoRecorder: Pipeline warning: %s (%s)", warn.message, debug_info);
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

    // Get the latest preview frame as a texture
    public Gdk.Texture? get_preview_texture() {
        if (gtk_sink == null) return null;

        if (preview_is_pixbufsink) {
            // gdkpixbufsink exposes a "last-pixbuf" property
            GLib.Value val = GLib.Value(typeof(Gdk.Pixbuf));
            gtk_sink.get_property("last-pixbuf", ref val);
            Gdk.Pixbuf? pixbuf = val.get_object() as Gdk.Pixbuf;
            if (pixbuf == null) return null;
            return Gdk.Texture.for_pixbuf(pixbuf);
        }

        // Fallback: pull RGBA sample from appsink
        var appsink = (Gst.App.Sink) gtk_sink;
        var sample = appsink.try_pull_sample(0);
        if (sample == null) return null;

        unowned Gst.Caps? caps = sample.get_caps();
        if (caps == null || caps.get_size() == 0) return null;
        unowned Gst.Structure structure = caps.get_structure(0);
        int width = 0, height = 0;
        structure.get_int("width", out width);
        structure.get_int("height", out height);
        if (width <= 0 || height <= 0) return null;

        var buffer = sample.get_buffer();
        if (buffer == null) return null;
        Gst.MapInfo map;
        if (!buffer.map(out map, Gst.MapFlags.READ)) return null;

        // Copy RGBA pixel data and create texture
        var bytes = new GLib.Bytes(map.data[0:map.size]);
        buffer.unmap(map);
        return new Gdk.MemoryTexture(width, height, Gdk.MemoryFormat.R8G8B8A8, bytes, width * 4);
    }

    public async void stop_recording_async() {
        debug("VideoRecorder.stop_recording_async: called");
        if (timeout_id != 0) {
            Source.remove(timeout_id);
            timeout_id = 0;
        }
        if (pipeline != null && is_recording) {
            debug("VideoRecorder.stop_recording_async: sending EOS");
            pipeline.send_event(new Event.eos());

            // Wait for EOS or Error
            ulong signal_id = 0;
            SourceFunc callback = stop_recording_async.callback;

            bool eos_handled = false;
            signal_id = bus.message.connect((bus, msg) => {
                if (!eos_handled && (msg.type == Gst.MessageType.EOS || msg.type == Gst.MessageType.ERROR)) {
                    eos_handled = true;
                    debug("VideoRecorder.stop_recording_async: Received %s", msg.type.to_string());
                    Idle.add((owned) callback);
                }
            });

            // Safety timeout (5 seconds - video muxing takes longer than audio)
            uint timeout_source = 0;
            timeout_source = Timeout.add(5000, () => {
                debug("VideoRecorder.stop_recording_async: Timeout reached");
                callback();
                timeout_source = 0;
                return false;
            });

            yield;
            debug("VideoRecorder.stop_recording_async: finished yield");

            if (timeout_source != 0) {
                Source.remove(timeout_source);
                timeout_source = 0;
            }
            if (bus != null) {
                bus.disconnect(signal_id);
                bus.remove_signal_watch();
                bus = null;
            }

            if (pipeline != null) {
                pipeline.set_state(State.NULL);
                pipeline = null;
            }
            is_recording = false;
            cleanup_elements();
        }
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
            cleanup_elements();
        }
        if (current_output_path != null) {
            FileUtils.unlink(current_output_path);
            current_output_path = null;
        }
    }

    private void cleanup_elements() {
        gtk_sink = null;
        video_source = null;
        video_convert = null;
        video_scale = null;
        video_rate = null;
        video_capsfilter = null;
        video_encoder = null;
        video_parser = null;
        video_queue = null;
        audio_source = null;
        audio_convert = null;
        audio_resample = null;
        audio_capsfilter = null;
        audio_volume = null;
        audio_encoder = null;
        audio_convert2 = null;
        audio_parser = null;
        audio_queue = null;
        muxer = null;
        sink = null;
        tee = null;
        preview_queue = null;
        preview_convert = null;
        preview_sink = null;
    }
}

}
