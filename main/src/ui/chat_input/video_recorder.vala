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
    private uint bus_watch_id = 0;
    private uint timeout_id = 0;
    private int64 start_time = 0;
    private bool error_cancelling = false; // prevent re-entrant cancel from bus callback
    public const int MAX_DURATION_SECONDS = 120; // 2 minutes

    public string? current_output_path { get; private set; }
    public bool is_recording { get; private set; default = false; }

    // GdkPixbuf sink element for live preview in the popover
    public Element? gtk_sink { get; private set; }

    // Static encoder cache: probed once per app session, reused for all recordings.
    // Avoids 2s+ per-encoder probe on every recording (4 encoders × 2s = 8s+ on Windows).
    private static string? cached_h264_factory = null;
    private static bool encoder_cache_probed = false;

    public signal void duration_changed(string text);
    public signal void max_duration_reached();
    public signal void recording_error(string message);
    public signal void recording_stopped(string? output_path);

    public VideoRecorder() {
    }

    /**
     * Detect the Linux distribution from /etc/os-release and return
     * a distro-specific install hint for GStreamer H.264 encoder packages.
     */
    private static string get_h264_install_hint() {
#if WINDOWS
        return "MSYS2/MINGW64: pacman -S mingw-w64-x86_64-gst-plugins-ugly "
             + "mingw-w64-x86_64-gst-libav\n"
             + "Then re-run: bash scripts/update_dist.sh";
#else
        string? os_id = null;
        try {
            string contents;
            FileUtils.get_contents("/etc/os-release", out contents);
            foreach (string line in contents.split("\n")) {
                // Match ID= or ID_LIKE= to detect derivative distros too
                if (line.has_prefix("ID=")) {
                    os_id = line.substring(3).replace("\"", "").down();
                    break;
                }
            }
        } catch (FileError e) {
            // /etc/os-release not found
        }

        if (os_id != null) {
            if (os_id.contains("opensuse") || os_id.contains("suse")) {
                return "openSUSE: sudo zypper install gstreamer-plugins-ugly gstreamer-plugins-libav "
                     + "(Packman-Repo erforderlich: https://ftp.gwdg.de/pub/linux/misc/packman/suse/)";
            }
            if (os_id.contains("fedora") || os_id.contains("rhel") || os_id.contains("centos")) {
                return "Fedora/RHEL: sudo dnf install gstreamer1-plugins-ugly gstreamer1-libav "
                     + "(RPM Fusion repo may be required: https://rpmfusion.org/)";
            }
            if (os_id.contains("arch") || os_id.contains("manjaro") || os_id.contains("endeavouros")) {
                return "Arch: sudo pacman -S gst-plugins-ugly gst-libav";
            }
        }
        // Debian/Ubuntu default (also fallback for unknown distros)
        return "Debian/Ubuntu: sudo apt install gstreamer1.0-plugins-ugly gstreamer1.0-libav "
             + "(or gstreamer1.0-vaapi for Intel/AMD hardware encoding)";
#endif
    }

    ~VideoRecorder() {
        if (is_recording) {
            cancel_recording();
        }
    }

    /**
     * Test if a video encoder actually works by running a 1-frame test pipeline.
     * ElementFactory.make() can succeed even when the underlying library is broken
     * (e.g. openh264enc on systems without the Cisco OpenH264 binary).
     */
    private bool test_video_encoder(string factory_name) {
        try {
            int64 t0 = GLib.get_monotonic_time();
            // Use videoconvert before the encoder so hardware encoders (VAAPI, VA)
            // can negotiate their preferred input format instead of raw I420.
            var test_pipe = Gst.parse_launch(
                "videotestsrc num-buffers=1 ! video/x-raw,width=160,height=120,framerate=1/1 ! videoconvert ! %s ! fakesink".printf(factory_name));
            if (test_pipe == null) return false;

            test_pipe.set_state(State.PLAYING);
            var test_bus = ((Pipeline)test_pipe).get_bus();
            // 500ms is plenty for encoding a single 160x120 frame.
            // Previously 2s (and before that 5s) — caused 8-20s+ startup
            // delay when multiple unavailable encoders were probed sequentially
            // (each timeout + NULL state-change cleanup on Windows COM/MF).
            var msg = test_bus.timed_pop_filtered(500 * Gst.MSECOND,
                MessageType.ERROR | MessageType.EOS);
            bool works = (msg != null && msg.type == MessageType.EOS);
            test_pipe.set_state(State.NULL);
            int64 elapsed_ms = (GLib.get_monotonic_time() - t0) / 1000;
            if (!works) {
                debug("VideoRecorder: encoder test FAILED for %s (%lldms)", factory_name, elapsed_ms);
            } else {
                debug("VideoRecorder: encoder test OK for %s (%lldms)", factory_name, elapsed_ms);
            }
            return works;
        } catch (Error e) {
            debug("VideoRecorder: encoder test exception for %s: %s", factory_name, e.message);
            return false;
        }
    }

    /**
     * Try to create and validate a video encoder element.
     * Returns the element if both factory creation and runtime test succeed, null otherwise.
     */
    private Element? try_create_encoder(string factory_name, string element_name) {
        if (ElementFactory.find(factory_name) == null) return null;
        if (!test_video_encoder(factory_name)) return null;
        return ElementFactory.make(factory_name, element_name);
    }

    public void start_recording(string output_path) throws Error {
        int64 t_start = GLib.get_monotonic_time();
        debug("VideoRecorder.start_recording: output_path=%s", output_path);
        if (is_recording) return;

        current_output_path = output_path; // may be overridden later if WebM fallback is used

        pipeline = new Pipeline("video-recorder");

        // === VIDEO branch ===
        var app = (Dino.Ui.Application) GLib.Application.get_default();
        int64 t0 = GLib.get_monotonic_time();
        video_source = app.av_device_service.create_video_source(app.settings.msg_video_device);
        warning("VideoRecorder TIMING: create_video_source = %lldms", (GLib.get_monotonic_time() - t0) / 1000);
        video_source.set("do-timestamp", true);
        video_convert = ElementFactory.make("videoconvert", "video-convert");
        video_scale = ElementFactory.make("videoscale", "video-scale");
        if (video_scale != null) {
            video_scale.set("add-borders", true);
        }
        video_rate = ElementFactory.make("videorate", "video-rate");
        video_capsfilter = ElementFactory.make("capsfilter", "video-caps");
        video_queue = ElementFactory.make("queue", "video-queue");

        // Source-side capsfilter: constrain negotiation to video/x-raw formats
        // the camera actually supports.  Without this, videoscale/videorate
        // broaden downstream caps to ranges ([1,MAX]) that propagate back to
        // pipewiresrc, which PipeWire >= 1.2 rejects with EINVAL (-22).
        // This mirrors the proven approach from the RTP call pipeline (device.vala).
        Element? video_src_capsfilter = null;
        var all_device_caps = app.av_device_service.get_video_device_caps(
            app.settings.msg_video_device);
        if (all_device_caps != null) {
            var raw_only = new Gst.Caps.empty();
            for (uint i = 0; i < all_device_caps.get_size(); i++) {
                unowned Gst.Structure s = all_device_caps.get_structure(i);
                unowned Gst.CapsFeatures? f = all_device_caps.get_features(i);
                if (!s.has_name("video/x-raw")) continue;
                if (f != null && f.contains("memory:DMABuf")) continue;
                if (s.has_field("format")) {
                    unowned string? fmt = s.get_string("format");
                    if (fmt == "DMA_DRM") continue;
                }
                raw_only.append_structure_full(s.copy(),
                    f != null ? f.copy() : null);
            }
            if (!raw_only.is_empty()) {
                video_src_capsfilter = ElementFactory.make("capsfilter", "video-src-caps");
                if (video_src_capsfilter != null) {
                    video_src_capsfilter.set("caps", raw_only);
                    debug("VideoRecorder: source-side caps = %s", raw_only.to_string());
                }
            }
        }

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

        // H.264 encoder selection
        int64 t_enc = GLib.get_monotonic_time();
#if WINDOWS
        // Windows portable: we bundle everything, no probing needed.
        // Just create the encoder directly — zero overhead.
        video_encoder = ElementFactory.make("mfh264enc", "video-encoder");
        if (video_encoder != null) {
            video_encoder.set("bitrate", (uint) 1500); // kbps
            debug("VideoRecorder: using mfh264enc (Windows MF, no probe)");
        }
        if (video_encoder == null) {
            video_encoder = ElementFactory.make("x264enc", "video-encoder");
            if (video_encoder != null) {
                video_encoder.set("speed-preset", 2); // superfast
                video_encoder.set("tune", 4); // zerolatency
                video_encoder.set("bitrate", 1500); // kbps
                video_encoder.set("key-int-max", 60);
                debug("VideoRecorder: using x264enc (no probe)");
            }
        }
        if (video_encoder == null) {
            video_encoder = ElementFactory.make("openh264enc", "video-encoder");
            if (video_encoder != null) {
                video_encoder.set("bitrate", 1500000); // bps
                video_encoder.set("complexity", 1);
                debug("VideoRecorder: using openh264enc (no probe)");
            }
        }
#else
        // Linux: probe encoders because we don't control what's installed.
        // Use static cache to avoid re-probing on subsequent recordings.
        if (encoder_cache_probed && cached_h264_factory != null) {
            video_encoder = ElementFactory.make(cached_h264_factory, "video-encoder");
            if (video_encoder != null) {
                debug("VideoRecorder: using cached encoder '%s'", cached_h264_factory);
            } else {
                encoder_cache_probed = false;
                cached_h264_factory = null;
            }
        }
        if (video_encoder == null && !encoder_cache_probed) {
            encoder_cache_probed = true;
            // Hardware first
            video_encoder = try_create_encoder("vaapih264enc", "video-encoder");
            if (video_encoder != null) cached_h264_factory = "vaapih264enc";
            if (video_encoder == null) {
                video_encoder = try_create_encoder("vah264enc", "video-encoder");
                if (video_encoder != null) cached_h264_factory = "vah264enc";
            }
            // Software fallbacks
            if (video_encoder == null) {
                video_encoder = try_create_encoder("x264enc", "video-encoder");
                if (video_encoder != null) cached_h264_factory = "x264enc";
            }
            if (video_encoder == null) {
                video_encoder = try_create_encoder("avenc_h264", "video-encoder");
                if (video_encoder != null) cached_h264_factory = "avenc_h264";
            }
            if (video_encoder == null) {
                video_encoder = try_create_encoder("openh264enc", "video-encoder");
                if (video_encoder != null) cached_h264_factory = "openh264enc";
            }
        }
        // Configure encoder-specific properties (Linux path)
        if (video_encoder != null) {
            string enc_name = video_encoder.get_factory() != null ? video_encoder.get_factory().get_name() : "";
            if (enc_name == "x264enc") {
                video_encoder.set("speed-preset", 2);
                video_encoder.set("tune", 4);
                video_encoder.set("bitrate", 1500);
                video_encoder.set("key-int-max", 60);
            } else if (enc_name == "avenc_h264") {
                video_encoder.set("bitrate", 1500000);
                video_encoder.set("max-threads", 2);
            } else if (enc_name == "openh264enc") {
                video_encoder.set("bitrate", 1500000);
                video_encoder.set("complexity", 1);
            }
        }
#endif
        warning("VideoRecorder TIMING: encoder selection = %lldms", (GLib.get_monotonic_time() - t_enc) / 1000);

        if (video_encoder == null) {
            string hint = get_h264_install_hint();
            throw new Error(Quark.from_string("VideoRecorder"), 0,
                "No working H.264 video encoder found.\n\n%s".printf(hint));
        }
        debug("VideoRecorder: using encoder %s",
              video_encoder.get_factory() != null ? video_encoder.get_factory().get_name() : "?");

        // Parser: h264parse for proper MP4 muxing (optional but recommended)
        video_parser = ElementFactory.make("h264parse", "video-parser");
        if (video_parser == null) {
            debug("h264parse not available, will link encoder directly to muxer");
        }

        // === AUDIO branch ===
        // Audio source for the video recording's audio track
        t0 = GLib.get_monotonic_time();
        audio_source = app.av_device_service.create_audio_source(app.settings.msg_audio_input_device);
        warning("VideoRecorder TIMING: create_audio_source = %lldms", (GLib.get_monotonic_time() - t0) / 1000);
        t0 = GLib.get_monotonic_time();
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
        if (audio_encoder == null) {
            // Windows Media Foundation AAC — available on Windows 10+
            audio_encoder = ElementFactory.make("mfaacenc", "audio-encoder");
        }
        audio_parser = ElementFactory.make("aacparse", "audio-parser");

        // === Muxer + Sink ===
        muxer = ElementFactory.make("mp4mux", "muxer");
        if (muxer != null) {
            // faststart: moves moov atom to the beginning of the file after EOS,
            // so the video can start playing before fully downloaded.
            muxer.set("faststart", true);
        }
        sink = ElementFactory.make("filesink", "sink");
        warning("VideoRecorder TIMING: create audio+muxer elements = %lldms", (GLib.get_monotonic_time() - t0) / 1000);

        current_output_path = output_path;

        // Validate all required elements - log which ones are missing for diagnostics
        string[] missing = {};
        if (video_source == null) missing += "video_source (pipewiresrc/v4l2src)";
        if (video_convert == null) missing += "videoconvert (gst-plugins-base)";
        if (video_scale == null) missing += "videoscale (gst-plugins-base)";
        if (video_rate == null) missing += "videorate (gst-plugins-base)";
        if (video_capsfilter == null) missing += "capsfilter (gstreamer)";
        if (video_encoder == null) missing += "video encoder (all tested: vaapih264enc, vah264enc, x264enc, avenc_h264, openh264enc, vp8enc — none available/working)";
        if (tee == null) missing += "tee (gstreamer)";
        if (preview_queue == null) missing += "queue (gstreamer)";
        if (video_queue == null) missing += "queue (gstreamer)";
        if (audio_source == null) missing += "autoaudiosrc (gst-plugins-base)";
        if (audio_convert == null) missing += "audioconvert (gst-plugins-base)";
        if (audio_resample == null) missing += "audioresample (gst-plugins-base)";
        if (audio_capsfilter == null) missing += "capsfilter (gstreamer)";
        if (audio_encoder == null) missing += "AAC encoder (avenc_aac, voaacenc, or mfaacenc)";
        if (audio_parser == null) missing += "aacparse (gst-plugins-good)";
        if (audio_queue == null) missing += "queue (gstreamer)";
        if (muxer == null) missing += "mp4mux (gst-plugins-good)";
        if (sink == null) missing += "filesink (gstreamer)";
        if (missing.length > 0) {
            string details = string.joinv(", ", missing);
            throw new Error(Quark.from_string("VideoRecorder"), 0,
                "Could not create GStreamer elements. Missing: %s. Install: gst-plugins-good, gst-plugins-bad, gst-plugins-ugly, gst-libav".printf(details));
        }

        // Configure video caps: fixed VGA 640x480@24fps — sufficient for
        // video messages and much lighter on CPU than 720p@30fps.
        // Range caps like [1,1280] propagate backwards to pipewiresrc which
        // rejects them with EINVAL (-22) on PipeWire >= 1.2.
        // videoscale (add-borders=true) preserves aspect ratio.
        video_capsfilter.set("caps", Caps.from_string(
            "video/x-raw, width=640, height=480, framerate=24/1"));

        // Configure audio caps: 48kHz mono
        audio_capsfilter.set("caps", Caps.from_string(
            "audio/x-raw, rate=48000, channels=1, format=S16LE"));

        // Mute during PipeWire connection transient, unmute after stabilization
        audio_volume.set("volume", 0.0);

        // Audio encoder bitrate
        string audio_enc_name = audio_encoder.get_factory().get_name();
        debug("VideoRecorder: using audio encoder '%s'", audio_enc_name);
        if (audio_enc_name == "avenc_aac" || audio_enc_name == "voaacenc") {
            audio_encoder.set("bitrate", 96000);
        } else if (audio_enc_name == "mfaacenc") {
            // mfaacenc uses bitrate in bps
            audio_encoder.set("bitrate", (uint) 96000);
        } else if (audio_enc_name == "vorbisenc") {
            audio_encoder.set("bitrate", 96000);
        } else if (audio_enc_name == "opusenc") {
            audio_encoder.set("bitrate", 96000);
        }

        sink.set("location", current_output_path);

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
        t0 = GLib.get_monotonic_time();
        pipeline.add_many(video_source, video_convert, video_scale, video_rate,
            video_capsfilter, tee, video_queue, video_encoder,
            preview_queue, preview_convert, preview_sink,
            audio_source, audio_volume, audio_convert, audio_resample, audio_capsfilter,
            audio_queue, audio_convert2, audio_encoder,
            muxer, sink);
        if (video_src_capsfilter != null) {
            pipeline.add(video_src_capsfilter);
        }
        if (video_parser != null) {
            pipeline.add(video_parser);
        }
        if (audio_parser != null) {
            pipeline.add(audio_parser);
        }
        warning("VideoRecorder TIMING: add elements = %lldms", (GLib.get_monotonic_time() - t0) / 1000);

        // Link video chain — skip ALL link checks and specify explicit pad names.
        // On Windows, gst_element_link_pads_full with null names calls
        // gst_element_get_compatible_pad() which triggers caps queries back to
        // mfvideosrc (Media Foundation device enumeration, ~seconds).
        // With NOTHING flag + explicit pads, linking is just pointer assignment.
        // Actual caps negotiation happens at set_state(PLAYING).
        t0 = GLib.get_monotonic_time();
        int64 t_link;
        var FAST = Gst.PadLinkCheck.NOTHING;

        // video_source → [src_capsfilter →] video_convert → video_scale → video_rate → video_caps → tee
        t_link = GLib.get_monotonic_time();
        if (video_src_capsfilter != null) {
            if (!video_source.link_pads("src", video_src_capsfilter, "sink", FAST) ||
                !video_src_capsfilter.link_pads("src", video_convert, "sink", FAST)) {
                throw new Error(Quark.from_string("VideoRecorder"), 0,
                    "Could not link video source → source capsfilter");
            }
        } else {
            if (!video_source.link_pads("src", video_convert, "sink", FAST)) {
                throw new Error(Quark.from_string("VideoRecorder"), 0,
                    "Could not link video source → videoconvert");
            }
        }
        warning("VideoRecorder TIMING: link src→convert = %lldms",
                (GLib.get_monotonic_time() - t_link) / 1000);
        t_link = GLib.get_monotonic_time();
        if (!video_convert.link_pads("src", video_scale, "sink", FAST) ||
            !video_scale.link_pads("src", video_rate, "sink", FAST) ||
            !video_rate.link_pads("src", video_capsfilter, "sink", FAST) ||
            !video_capsfilter.link_pads("src", tee, "sink", FAST)) {
            throw new Error(Quark.from_string("VideoRecorder"), 0,
                "Could not link video source chain");
        }
        warning("VideoRecorder TIMING: link convert→tee = %lldms",
                (GLib.get_monotonic_time() - t_link) / 1000);

        // Tee → preview branch: preview_queue → preview_convert → preview_sink
        t_link = GLib.get_monotonic_time();
        var tee_preview_pad = tee.request_pad_simple("src_%u");
        var preview_queue_pad = preview_queue.get_static_pad("sink");
        if (tee_preview_pad.link(preview_queue_pad, FAST) != PadLinkReturn.OK) {
            throw new Error(Quark.from_string("VideoRecorder"), 0,
                "Could not link tee to preview queue");
        }
        if (!preview_queue.link_pads("src", preview_convert, "sink", FAST) ||
            !preview_convert.link_pads("src", preview_sink, "sink", FAST)) {
            throw new Error(Quark.from_string("VideoRecorder"), 0,
                "Could not link preview branch");
        }
        warning("VideoRecorder TIMING: link preview = %lldms",
                (GLib.get_monotonic_time() - t_link) / 1000);

        // Tee → record branch: video_queue → video_encoder → [video_parser →] muxer
        t_link = GLib.get_monotonic_time();
        var tee_record_pad = tee.request_pad_simple("src_%u");
        var record_queue_pad = video_queue.get_static_pad("sink");
        if (tee_record_pad.link(record_queue_pad, FAST) != PadLinkReturn.OK) {
            throw new Error(Quark.from_string("VideoRecorder"), 0,
                "Could not link tee to record queue");
        }
        if (!video_queue.link_pads("src", video_encoder, "sink", FAST)) {
            throw new Error(Quark.from_string("VideoRecorder"), 0,
                "Could not link video_queue → video_encoder");
        }
        Element last_video = video_encoder;
        if (video_parser != null) {
            if (!last_video.link_pads("src", video_parser, "sink", FAST)) {
                throw new Error(Quark.from_string("VideoRecorder"), 0,
                    "Could not link video chain → h264parse");
            }
            last_video = video_parser;
        }
        // muxer uses request pads: video_%u, audio_%u or sink_%u depending on muxer
        if (!last_video.link_pads("src", muxer, null, FAST)) {
            throw new Error(Quark.from_string("VideoRecorder"), 0,
                "Could not link video chain → muxer");
        }
        warning("VideoRecorder TIMING: link record = %lldms",
                (GLib.get_monotonic_time() - t_link) / 1000);

        // Audio chain: source → volume → convert → resample → caps → queue → convert2 → encoder → parser → muxer
        // No audio processing (noise gate, compressor etc.) — pass-through for cleanest signal
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
        if (!audio_capsfilter.link(audio_queue)) {
            throw new Error(Quark.from_string("VideoRecorder"), 0, "Could not link audio_capsfilter → audio_queue");
        }
        if (!audio_queue.link(audio_convert2)) {
            throw new Error(Quark.from_string("VideoRecorder"), 0, "Could not link audio_queue → audio_convert2");
        }
        if (!audio_convert2.link(audio_encoder)) {
            throw new Error(Quark.from_string("VideoRecorder"), 0, "Could not link audio_convert2 → audio_encoder");
        }
        if (audio_parser != null) {
            // AAC path: encoder → parser → muxer
            if (!audio_encoder.link(audio_parser)) {
                throw new Error(Quark.from_string("VideoRecorder"), 0, "Could not link audio_encoder → audio_parser");
            }
            if (!audio_parser.link(muxer)) {
                throw new Error(Quark.from_string("VideoRecorder"), 0, "Could not link audio_parser → muxer");
            }
        } else {
            // No parser available: link encoder directly to muxer
            if (!audio_encoder.link(muxer)) {
                throw new Error(Quark.from_string("VideoRecorder"), 0, "Could not link audio_encoder → muxer");
            }
        }

        // Muxer → sink
        if (!muxer.link(sink)) {
            throw new Error(Quark.from_string("VideoRecorder"), 0,
                "Could not link muxer to sink");
        }
        warning("VideoRecorder TIMING: link pipeline TOTAL = %lldms", (GLib.get_monotonic_time() - t0) / 1000);

        // Store preview sink reference for the popover to access
        gtk_sink = preview_sink;

        bus = pipeline.get_bus();
        error_cancelling = false;
        bus_watch_id = bus.add_watch(0, (b, msg) => {
            if (msg.type == MessageType.ERROR) {
                Error err;
                string debug_info;
                msg.parse_error(out err, out debug_info);
                warning("VideoRecorder: Pipeline error: %s (%s)", err.message, debug_info);
                // Cancel recording on pipeline error to prevent app freeze.
                // The pipeline is broken and won't produce valid output.
                if (!error_cancelling) {
                    error_cancelling = true;
                    string user_msg = err.message;
                    // Schedule cancel on idle to avoid re-entrant issues
                    Idle.add(() => {
                        cancel_recording();
                        recording_error(user_msg);
                        return false;
                    });
                }
                return false; // stop watching — we're cancelling
            } else if (msg.type == MessageType.WARNING) {
                Error warn;
                string debug_info;
                msg.parse_warning(out warn, out debug_info);
                debug("VideoRecorder: Pipeline warning: %s (%s)", warn.message, debug_info);
            }
            return true;
        });

        // Start directly in PLAYING - live sources (pipewiresrc, autoaudiosrc)
        // don't produce data in PAUSED state and may block preroll.
        // Direct PLAYING start is the reliable approach for live pipelines.
        t0 = GLib.get_monotonic_time();
        var state_ret = pipeline.set_state(State.PLAYING);
        warning("VideoRecorder TIMING: set_state(PLAYING) = %lldms (ret=%s)",
              (GLib.get_monotonic_time() - t0) / 1000,
              state_ret.to_string());
        warning("VideoRecorder TIMING: TOTAL start_recording = %lldms",
              (GLib.get_monotonic_time() - t_start) / 1000);
        is_recording = true;
        start_time = GLib.get_monotonic_time();
        timeout_id = Timeout.add(100, update_duration);

        // Unmute after PipeWire transient has passed (400ms)
        // Volume 1.0 = no software amplification → cleanest signal
        Timeout.add(400, () => {
            if (audio_volume != null && is_recording) {
                audio_volume.set("volume", 1.0);
            }
            return false;
        });
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

    // Counter for blocking pad probes — when both video + audio sources
    // have injected EOS, the muxer will finalize and post EOS on the bus.
    private int eos_pending = 0;

    public void stop_recording() {
        warning("VideoRecorder.stop_recording: called");
        if (timeout_id != 0) {
            Source.remove(timeout_id);
            timeout_id = 0;
        }
        if (pipeline == null || !is_recording) {
            recording_stopped(null);
            return;
        }

        is_recording = false;

        // Remove the error-handling bus watch — we install our own EOS watch below
        if (bus_watch_id != 0) {
            Source.remove(bus_watch_id);
            bus_watch_id = 0;
        }

        // === EOS via blocking pad probes ===
        // Live sources (pipewiresrc, mfvideosrc, wasapi2src) IGNORE
        // send_event(EOS). The reliable GStreamer pattern is:
        // 1. Install a blocking probe on each source's src pad
        // 2. In the probe callback, push EOS downstream programmatically
        // 3. This injects EOS into the data flow from the correct thread
        // 4. mp4mux receives EOS on both sink pads → writes moov atom → posts EOS on bus
        int64 t_eos_start = GLib.get_monotonic_time();
        eos_pending = 0;

        Gst.Pad? v_src_pad = (video_source != null) ? video_source.get_static_pad("src") : null;
        Gst.Pad? a_src_pad = (audio_source != null) ? audio_source.get_static_pad("src") : null;

        if (v_src_pad != null) eos_pending++;
        if (a_src_pad != null) eos_pending++;

        if (eos_pending == 0) {
            // No sources? Just kill pipeline.
            finalize_stop(t_eos_start);
            return;
        }

        // Watch bus for EOS from the muxer
        Pipeline pipe = pipeline;
        Gst.Bus? the_bus = bus;
        string? path = current_output_path;
        pipeline = null;
        bus = null;

        // Install blocking probes. When the probe fires, the source's
        // streaming thread is blocked — perfect moment to inject EOS.
        if (v_src_pad != null) {
            v_src_pad.add_probe(
                Gst.PadProbeType.BLOCK_DOWNSTREAM,
                (pad, info) => {
                    pad.get_peer().send_event(new Event.eos());
                    debug("VideoRecorder: EOS injected on video source pad");
                    return Gst.PadProbeReturn.REMOVE;
                });
        }
        if (a_src_pad != null) {
            a_src_pad.add_probe(
                Gst.PadProbeType.BLOCK_DOWNSTREAM,
                (pad, info) => {
                    pad.get_peer().send_event(new Event.eos());
                    debug("VideoRecorder: EOS injected on audio source pad");
                    return Gst.PadProbeReturn.REMOVE;
                });
        }

        // Wait for EOS in a background thread so the UI isn't blocked.
        new Thread<void>("video-stop", () => {
            // Wait for muxer to finalize (moov atom). 5s is generous.
            if (the_bus != null) {
                var msg = the_bus.timed_pop_filtered(5 * Gst.SECOND,
                    Gst.MessageType.EOS | Gst.MessageType.ERROR);
                if (msg == null) {
                    warning("VideoRecorder: EOS timeout after 5s — MP4 may be incomplete");
                } else if (msg.type == Gst.MessageType.ERROR) {
                    Error err;
                    string dbg;
                    msg.parse_error(out err, out dbg);
                    warning("VideoRecorder: error during finalization: %s", err.message);
                } else {
                    warning("VideoRecorder: EOS received — MP4 finalized OK");
                }
            }
            warning("VideoRecorder TIMING: EOS wait = %lldms",
                    (GLib.get_monotonic_time() - t_eos_start) / 1000);

            // Kill pipeline
            int64 t0 = GLib.get_monotonic_time();
            pipe.set_state(State.NULL);
            warning("VideoRecorder TIMING: set_state(NULL) = %lldms",
                    (GLib.get_monotonic_time() - t0) / 1000);
            warning("VideoRecorder TIMING: TOTAL stop_recording = %lldms",
                    (GLib.get_monotonic_time() - t_eos_start) / 1000);

            // Signal completion back on the main thread
            Idle.add(() => {
                cleanup_elements();
                recording_stopped(path);
                return false;
            });
        });
    }

    private void finalize_stop(int64 t_start) {
        if (pipeline != null) {
            pipeline.set_state(State.NULL);
            pipeline = null;
        }
        bus = null;
        string? path = current_output_path;
        cleanup_elements();
        warning("VideoRecorder TIMING: TOTAL stop_recording = %lldms",
                (GLib.get_monotonic_time() - t_start) / 1000);
        recording_stopped(path);
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
