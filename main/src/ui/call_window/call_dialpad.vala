using Gtk;
using Gst;

public class Dino.Ui.CallDialpad : Gtk.Popover {

    public signal void digit_pressed(char digit);

    private const string[] BUTTON_LABELS = {
        "1", "2", "3",
        "4", "5", "6",
        "7", "8", "9",
        "*", "0", "#"
    };

    private const string[] BUTTON_SUBLABELS = {
        "", "ABC", "DEF",
        "GHI", "JKL", "MNO",
        "PQRS", "TUV", "WXYZ",
        "", "+", ""
    };

    // DTMF dual-tone frequencies (low, high) per digit
    private const int[] DTMF_LOW  = { 697, 697, 697, 770, 770, 770, 852, 852, 852, 941, 941, 941 };
    private const int[] DTMF_HIGH = { 1209, 1336, 1477, 1209, 1336, 1477, 1209, 1336, 1477, 1209, 1336, 1477 };

    // Persistent tone pipeline — created once, reused for all tones
    private Gst.Pipeline? tone_pipeline = null;
    private Gst.Element? tone_src_low = null;
    private Gst.Element? tone_src_high = null;
    private Gst.Element? vol_low = null;
    private Gst.Element? vol_high = null;
    private uint tone_timeout_id = 0;
    private bool pipeline_ready = false;

    public CallDialpad() {
        var grid = new Grid() {
            row_spacing = 6,
            column_spacing = 6,
            margin_start = 12,
            margin_end = 12,
            margin_top = 12,
            margin_bottom = 12
        };

        for (int i = 0; i < BUTTON_LABELS.length; i++) {
            int row = i / 3;
            int col = i % 3;

            var box = new Box(Orientation.VERTICAL, 0) {
                halign = Align.CENTER,
                valign = Align.CENTER
            };

            var main_label = new Label(BUTTON_LABELS[i]) {
                halign = Align.CENTER
            };
            main_label.add_css_class("dtmf-digit");

            box.append(main_label);

            if (BUTTON_SUBLABELS[i] != "") {
                var sub_label = new Label(BUTTON_SUBLABELS[i]) {
                    halign = Align.CENTER
                };
                sub_label.add_css_class("dtmf-sublabel");
                sub_label.add_css_class("dim-label");
                box.append(sub_label);
            }

            var button = new Button() {
                child = box,
                width_request = 64,
                height_request = 52
            };
            button.add_css_class("flat");
            button.add_css_class("dtmf-button");

            string digit_str = BUTTON_LABELS[i];
            int tone_idx = i;
            button.clicked.connect(() => {
                play_local_tone(tone_idx);
                digit_pressed(digit_str[0]);
            });

            grid.attach(button, col, row, 1, 1);
        }

        this.set_child(grid);
        this.has_arrow = true;
        this.position = PositionType.TOP;

        // Create the persistent tone pipeline once (in READY state)
        ensure_pipeline();

        // Destroy pipeline when popover closes
        this.closed.connect(() => {
            destroy_pipeline();
        });
    }

    private void ensure_pipeline() {
        if (pipeline_ready) return;
        try {
            // Pipeline stays in PLAYING permanently.
            // Silence keepalive branch keeps audiomixer/sink alive at all times.
            // Volume elements on tone branches: volume=0.0 → silent, volume=0.3 → tone.
            // Unlike valve (abrupt cut → click), volume gives smooth gating.
            string desc = "audiotestsrc wave=silence is-live=true ! audio/x-raw,rate=44100 ! audiomixer name=mix ! autoaudiosink  audiotestsrc name=src_lo wave=sine freq=697 is-live=true ! volume name=vol_lo volume=0.0 ! audio/x-raw,rate=44100 ! mix.  audiotestsrc name=src_hi wave=sine freq=1209 is-live=true ! volume name=vol_hi volume=0.0 ! audio/x-raw,rate=44100 ! mix.";
            tone_pipeline = (Gst.Pipeline) Gst.parse_launch(desc);
            tone_src_low = tone_pipeline.get_by_name("src_lo");
            tone_src_high = tone_pipeline.get_by_name("src_hi");
            vol_low = tone_pipeline.get_by_name("vol_lo");
            vol_high = tone_pipeline.get_by_name("vol_hi");
            tone_pipeline.set_state(Gst.State.PLAYING);
            pipeline_ready = true;
        } catch (Error e) {
            debug("DTMF tone pipeline creation failed: %s", e.message);
        }
    }

    private void play_local_tone(int idx) {
        ensure_pipeline();
        if (!pipeline_ready || vol_low == null || vol_high == null) return;

        // Cancel previous tone-off timer
        if (tone_timeout_id != 0) {
            GLib.Source.remove(tone_timeout_id);
            tone_timeout_id = 0;
        }

        // Set frequencies and unmute
        tone_src_low.@set("freq", (double) DTMF_LOW[idx]);
        tone_src_high.@set("freq", (double) DTMF_HIGH[idx]);
        vol_low.@set("volume", 0.3);
        vol_high.@set("volume", 0.3);

        // Mute after 150ms
        tone_timeout_id = GLib.Timeout.add(150, () => {
            if (vol_low != null) vol_low.@set("volume", 0.0);
            if (vol_high != null) vol_high.@set("volume", 0.0);
            tone_timeout_id = 0;
            return false;
        });
    }

    private void destroy_pipeline() {
        if (tone_timeout_id != 0) {
            GLib.Source.remove(tone_timeout_id);
            tone_timeout_id = 0;
        }
        if (tone_pipeline != null) {
            tone_pipeline.set_state(Gst.State.NULL);
            tone_pipeline = null;
        }
        tone_src_low = null;
        tone_src_high = null;
        vol_low = null;
        vol_high = null;
        pipeline_ready = false;
    }

    ~CallDialpad() {
        destroy_pipeline();
    }
}
