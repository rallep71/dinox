using Gtk;
using Gee;

[GtkTemplate (ui = "/im/github/rallep71/DinoX/preferences_window/audio_video_preferences_page.ui")]
public class Dino.Ui.AudioVideoPreferencesPage : Adw.PreferencesPage {

    [GtkChild] unowned Adw.ComboRow call_mic_row;
    [GtkChild] unowned Adw.ComboRow call_speaker_row;
    [GtkChild] unowned Adw.ComboRow call_camera_row;
    [GtkChild] unowned Adw.ComboRow msg_mic_row;
    [GtkChild] unowned Adw.ComboRow msg_speaker_row;
    [GtkChild] unowned Adw.ComboRow msg_camera_row;
    [GtkChild] unowned Adw.ActionRow test_mic_row;
    [GtkChild] unowned Adw.ActionRow test_speaker_row;
    [GtkChild] unowned Adw.ActionRow test_camera_row;
    [GtkChild] unowned Adw.ActionRow refresh_row;

    private AudioVideoDeviceService device_service;
    private Dino.Entities.Settings settings;
    private bool populating = false;
    private bool wired = false;

    private Gst.Pipeline? test_pipeline;
    private Gtk.Window? preview_window;
    private bool testing = false;
    private string? mic_test_file;
    private string? original_test_mic_subtitle;
    private string? original_test_speaker_subtitle;
    private string? original_test_camera_subtitle;

    construct {
        original_test_mic_subtitle = test_mic_row.subtitle;
        original_test_speaker_subtitle = test_speaker_row.subtitle;
        original_test_camera_subtitle = test_camera_row.subtitle;
    }

    public void populate() {
        var app = (Dino.Ui.Application) GLib.Application.get_default();
        device_service = app.av_device_service;
        settings = app.settings;

        populating = true;

        populate_combo(call_mic_row, device_service.get_audio_input_devices(),
                       settings.call_audio_input_device);
        populate_combo(call_speaker_row, device_service.get_audio_output_devices(),
                       settings.call_audio_output_device);
        populate_combo(call_camera_row, device_service.get_video_input_devices(),
                       settings.call_video_device);
        populate_combo(msg_mic_row, device_service.get_audio_input_devices(),
                       settings.msg_audio_input_device);
        populate_combo(msg_speaker_row, device_service.get_audio_output_devices(),
                       settings.msg_audio_output_device);
        populate_combo(msg_camera_row, device_service.get_video_input_devices(),
                       settings.msg_video_device);

        populating = false;

        if (!wired) {
            wire_auto_save(call_mic_row, (v) => { settings.call_audio_input_device = v; });
            wire_auto_save(call_speaker_row, (v) => { settings.call_audio_output_device = v; });
            wire_auto_save(call_camera_row, (v) => { settings.call_video_device = v; });
            wire_auto_save(msg_mic_row, (v) => { settings.msg_audio_input_device = v; });
            wire_auto_save(msg_speaker_row, (v) => { settings.msg_audio_output_device = v; });
            wire_auto_save(msg_camera_row, (v) => { settings.msg_video_device = v; });

            test_mic_row.activated.connect(test_microphone);
            test_speaker_row.activated.connect(test_speaker);
            test_camera_row.activated.connect(test_camera);

            refresh_row.activated.connect(() => {
                device_service.rescan();
                populate();
            });

            device_service.devices_changed.connect(() => {
                populate();
            });

            wired = true;
        }
    }

    private delegate void SaveFunc(string val);

    private void wire_auto_save(Adw.ComboRow row, owned SaveFunc save) {
        row.notify["selected"].connect(() => {
            if (!populating) {
                save(get_combo_value(row));
            }
        });
    }

    private void populate_combo(Adw.ComboRow row, Gee.List<DeviceInfo> devices,
                                string saved_name) {
        var model = new Gtk.StringList(null);
        model.append(_("System Default"));
        uint selected = 0;
        for (int i = 0; i < devices.size; i++) {
            model.append(devices[i].display_name);
            if (devices[i].display_name == saved_name) {
                selected = i + 1;
            }
        }
        row.model = model;
        row.selected = selected;
    }

    private string get_combo_value(Adw.ComboRow row) {
        uint sel = row.selected;
        if (sel == 0) return "";
        var string_list = row.model as Gtk.StringList;
        if (string_list == null) return "";
        return string_list.get_string(sel);
    }

    // ─── Test functions ─────────────────────────────

    private void stop_test_pipeline() {
        if (test_pipeline != null) {
            test_pipeline.set_state(Gst.State.NULL);
            test_pipeline = null;
        }
        if (preview_window != null) {
            preview_window.close();
            preview_window = null;
        }
    }

    private void test_microphone() {
        if (testing) return;
        testing = true;
        stop_test_pipeline();

        string mic_name = get_combo_value(call_mic_row);
        string spk_name = get_combo_value(call_speaker_row);

        // Record 2s to a temp WAV file, then play it back
        mic_test_file = Path.build_filename(Environment.get_tmp_dir(), "dinox_mic_test.wav");

        test_mic_row.subtitle = _("Recording…");

        // Phase 1: Record
        var pipeline = new Gst.Pipeline("mic-test-record");
        var source = device_service.create_audio_source(mic_name);
        var convert = Gst.ElementFactory.make("audioconvert", "convert");
        var resample = Gst.ElementFactory.make("audioresample", "resample");
        var wavenc = Gst.ElementFactory.make("wavenc", "encoder");
        var sink = Gst.ElementFactory.make("filesink", "sink");

        if (source == null || convert == null || resample == null || wavenc == null || sink == null) {
            test_mic_row.subtitle = original_test_mic_subtitle;
            testing = false;
            warning("Mic test: failed to create pipeline elements");
            return;
        }

        sink.set_property("location", mic_test_file);

        pipeline.add_many(source, convert, resample, wavenc, sink);
        source.link(convert);
        convert.link(resample);
        resample.link(wavenc);
        wavenc.link(sink);

        test_pipeline = pipeline;

        var bus = pipeline.get_bus();
        bus.add_watch(Priority.DEFAULT, (b, msg) => {
            if (msg.type == Gst.MessageType.EOS) {
                pipeline.set_state(Gst.State.NULL);
                if (test_pipeline == pipeline) {
                    play_back_mic_test(spk_name);
                }
                return false;
            }
            if (msg.type == Gst.MessageType.ERROR) {
                Error err;
                string debug;
                msg.parse_error(out err, out debug);
                warning("Mic test record error: %s", err.message);
                pipeline.set_state(Gst.State.NULL);
                test_mic_row.subtitle = original_test_mic_subtitle;
                testing = false;
                return false;
            }
            return true;
        });

        pipeline.set_state(Gst.State.PLAYING);

        // Send EOS after 5 seconds to stop recording
        Timeout.add(5000, () => {
            if (test_pipeline == pipeline) {
                pipeline.send_event(new Gst.Event.eos());
            }
            return false;
        });
    }

    private void play_back_mic_test(string spk_name) {
        test_mic_row.subtitle = _("Playing back…");

        var pipeline = new Gst.Pipeline("mic-test-playback");
        var source = Gst.ElementFactory.make("uridecodebin", "source");
        var convert = Gst.ElementFactory.make("audioconvert", "convert");
        var resample = Gst.ElementFactory.make("audioresample", "resample");
        var sink = device_service.create_audio_sink(spk_name);

        if (source == null || convert == null || resample == null || sink == null) {
            warning("Mic test playback: failed to create elements (source=%s convert=%s resample=%s sink=%s)",
                source != null ? "ok" : "NULL", convert != null ? "ok" : "NULL",
                resample != null ? "ok" : "NULL", sink != null ? "ok" : "NULL");
            test_mic_row.subtitle = original_test_mic_subtitle;
            testing = false;
            return;
        }

        source.set_property("uri", File.new_for_path(mic_test_file).get_uri());

        pipeline.add_many(source, convert, resample, sink);
        convert.link(resample);
        resample.link(sink);

        // uridecodebin pads are dynamic
        source.pad_added.connect((pad) => {
            var sink_pad = convert.get_static_pad("sink");
            if (sink_pad != null && !sink_pad.is_linked()) {
                pad.link(sink_pad);
            }
        });

        test_pipeline = pipeline;

        var bus = pipeline.get_bus();
        bus.add_watch(Priority.DEFAULT, (b, msg) => {
            if (msg.type == Gst.MessageType.EOS || msg.type == Gst.MessageType.ERROR) {
                pipeline.set_state(Gst.State.NULL);
                test_mic_row.subtitle = original_test_mic_subtitle;
                testing = false;
                // Clean up temp file
                if (mic_test_file != null) {
                    FileUtils.remove(mic_test_file);
                    mic_test_file = null;
                }
                return false;
            }
            return true;
        });

        pipeline.set_state(Gst.State.PLAYING);
    }

    private void test_speaker() {
        if (testing) return;
        testing = true;
        stop_test_pipeline();

        string spk_name = get_combo_value(call_speaker_row);

        test_speaker_row.subtitle = _("Testing…");

        var pipeline = new Gst.Pipeline("speaker-test");
        var source = Gst.ElementFactory.make("audiotestsrc", "source");
        var convert = Gst.ElementFactory.make("audioconvert", "convert");
        var resample = Gst.ElementFactory.make("audioresample", "resample");
        var sink = device_service.create_audio_sink(spk_name);

        if (source == null || convert == null || resample == null || sink == null) {
            test_speaker_row.subtitle = original_test_speaker_subtitle;
            testing = false;
            warning("Speaker test: failed to create pipeline elements");
            return;
        }

        source.set_property("wave", 0); // sine
        source.set_property("freq", 440.0);
        source.set_property("num-buffers", 48000 / 1024);  // ~1 second at 48kHz

        pipeline.add_many(source, convert, resample, sink);
        source.link(convert);
        convert.link(resample);
        resample.link(sink);

        test_pipeline = pipeline;

        var bus = pipeline.get_bus();
        bus.add_watch(Priority.DEFAULT, (b, msg) => {
            if (msg.type == Gst.MessageType.EOS || msg.type == Gst.MessageType.ERROR) {
                pipeline.set_state(Gst.State.NULL);
                test_speaker_row.subtitle = original_test_speaker_subtitle;
                testing = false;
                return false;
            }
            return true;
        });

        pipeline.set_state(Gst.State.PLAYING);

        // Stop after 1 second
        Timeout.add(1000, () => {
            if (test_pipeline == pipeline) {
                pipeline.send_event(new Gst.Event.eos());
            }
            return false;
        });
    }

    private void test_camera() {
        if (testing) return;
        testing = true;
        stop_test_pipeline();

        string cam_name = get_combo_value(call_camera_row);

        test_camera_row.subtitle = _("Testing…");

        var pipeline = new Gst.Pipeline("camera-test");
        var source = device_service.create_video_source(cam_name);
        var convert = Gst.ElementFactory.make("videoconvert", "convert");
        var scale = Gst.ElementFactory.make("videoscale", "scale");
        var rate = Gst.ElementFactory.make("videorate", "rate");
        var capsfilter = Gst.ElementFactory.make("capsfilter", "caps");
        var sink = Gst.ElementFactory.make("gdkpixbufsink", "sink");

        if (source == null || convert == null || scale == null || rate == null || capsfilter == null) {
            // gdkpixbufsink may not be available, fall back to fakesink
            if (sink == null) {
                sink = Gst.ElementFactory.make("fakesink", "sink");
            }
            if (source == null || convert == null || scale == null || rate == null || capsfilter == null || sink == null) {
                test_camera_row.subtitle = original_test_camera_subtitle;
                testing = false;
                warning("Camera test: failed to create pipeline elements");
                return;
            }
        }

        var caps = Gst.Caps.from_string("video/x-raw,width=320,height=240,framerate=15/1");
        capsfilter.set_property("caps", caps);

        pipeline.add_many(source, convert, scale, rate, capsfilter, sink);
        source.link(convert);
        convert.link(scale);
        scale.link(rate);
        rate.link(capsfilter);
        capsfilter.link(sink);

        test_pipeline = pipeline;

        // Create preview window if gdkpixbufsink is available
        Gtk.Picture? picture = null;

        if (sink.get_factory() != null && sink.get_factory().get_name() == "gdkpixbufsink") {
            this.preview_window = new Gtk.Window();
            this.preview_window.title = _("Camera Preview");
            this.preview_window.default_width = 320;
            this.preview_window.default_height = 240;
            this.preview_window.resizable = false;

            picture = new Gtk.Picture();
            this.preview_window.child = picture;
            this.preview_window.present();

            // Poll for pixbuf updates
            Timeout.add(66, () => { // ~15fps
                if (test_pipeline != pipeline) return false;
                Value val = Value(typeof(Gdk.Pixbuf));
                sink.get_property("last-pixbuf", ref val);
                Gdk.Pixbuf? pixbuf = val.get_object() as Gdk.Pixbuf;
                if (pixbuf != null && picture != null) {
                    var texture = Gdk.Texture.for_pixbuf(pixbuf);
                    picture.paintable = texture;
                }
                return test_pipeline == pipeline;
            });
        }

        var bus = pipeline.get_bus();
        bus.add_watch(Priority.DEFAULT, (b, msg) => {
            if (msg.type == Gst.MessageType.ERROR) {
                Error err;
                string debug;
                msg.parse_error(out err, out debug);
                warning("Camera test error: %s", err.message);
                pipeline.set_state(Gst.State.NULL);
                test_camera_row.subtitle = original_test_camera_subtitle;
                if (this.preview_window != null) { this.preview_window.close(); this.preview_window = null; }
                testing = false;
                return false;
            }
            return true;
        });

        pipeline.set_state(Gst.State.PLAYING);

        // Auto-close after 5 seconds
        Timeout.add(5000, () => {
            if (test_pipeline == pipeline) {
                pipeline.set_state(Gst.State.NULL);
                test_pipeline = null;
                test_camera_row.subtitle = original_test_camera_subtitle;
                if (this.preview_window != null) { this.preview_window.close(); this.preview_window = null; }
                testing = false;
            }
            return false;
        });
    }
}
