using Xmpp.Xep.JingleRtp;
using Gee;

public enum Dino.Plugins.Rtp.DeviceProtocol {
    OTHER,
    PIPEWIRE,
    V4L2,
    PULSEAUDIO,
    ALSA
}

public class Dino.Plugins.Rtp.Device : MediaDevice, Object {
    private const int[] common_widths = {320, 352, 416, 480, 640, 960, 1280, 1920, 2560, 3840};

    public Plugin plugin { get; private set; }
    public CodecUtil codec_util { get { return plugin.codec_util; } }
    public Gst.Device device { get; private set; }

    public string id { owned get { return device_name; }}
    public string display_name { owned get { return device_display_name; }}
    public string? detail_name { owned get {
        if (device == null || device.properties == null) return null;
        if (device.properties.has_field("alsa.card_name")) return device.properties.get_string("alsa.card_name");
        if (device.properties.has_field("alsa.name")) return device.properties.get_string("alsa.name");
        if (device.properties.has_field("alsa.id")) return device.properties.get_string("alsa.id");
        if (device.properties.has_field("api.v4l2.cap.card")) return device.properties.get_string("api.v4l2.cap.card");
        return null;
    }}
    public string? media { owned get {
        if (device == null) return _cached_media;
        if (device.has_classes("Audio")) {
            return "audio";
        } else if (device.has_classes("Video")) {
            return "video";
        } else {
            return null;
        }
    }}
    public bool incoming { get { return is_sink; } }

    public Gst.Pipeline pipe { get { return plugin.pipe; }}
    public bool is_source { get { return device != null && device.has_classes("Source"); }}
    public bool is_sink { get { return device != null && device.has_classes("Sink"); }}
    public bool is_monitor { get { return device != null && ((device.properties != null && device.properties.get_string("device.class") == "monitor") || (protocol == DeviceProtocol.PIPEWIRE && device.has_classes("Stream"))); } }
    public bool is_default { get {
        if (device == null || device.properties == null) return false;
        bool ret;
        device.properties.get_boolean("is-default", out ret);
        return ret;
    }}
    public DeviceProtocol protocol { get {
        if (device == null || device.properties == null) return DeviceProtocol.OTHER;
        if (device.properties.has_name("pulse-proplist")) return DeviceProtocol.PULSEAUDIO;
        if (device.properties.has_name("pipewire-proplist")) return DeviceProtocol.PIPEWIRE;
        if (device.properties.has_name("v4l2deviceprovider")) return DeviceProtocol.V4L2;
        return DeviceProtocol.OTHER;
    }}

    private string device_name;
    private string device_display_name;
    private string? _cached_media;

    private Gst.Caps device_caps;
    private Gst.Element element;
    private Gst.Element volume_element;
    private Gst.Element source_queue; // Queue before tee to stabilize source
    private Gst.Element tee;
    private Gst.Element dsp;
    private Gst.Base.Aggregator mixer;
    private Gst.Element filter;
    private Gst.Element? echo_convert;
    private Gst.Element? echo_resample;
    private Gst.Element? echo_filter;
    private Gst.Element? recv_volume; // Volume element for receive ramp-up
    private bool recv_ramp_done = false; // true after initial 200ms ramp-up
    private int sink_peers = 0; // Number of peers connected to this sink (for gain scaling)
    private int links;

    // Codecs
    private Gee.Map<PayloadType, Gst.Element> codecs = new HashMap<PayloadType, Gst.Element>(PayloadType.hash_func, PayloadType.equals_func);
    private Gee.Map<PayloadType, Gst.Element> codec_tees = new HashMap<PayloadType, Gst.Element>(PayloadType.hash_func, PayloadType.equals_func);

    // Payloaders
    private Gee.Map<PayloadType, Gee.Map<uint, Gst.Element>> payloaders = new HashMap<PayloadType, Gee.Map<uint, Gst.Element>>(PayloadType.hash_func, PayloadType.equals_func);
    private Gee.Map<PayloadType, Gee.Map<uint, Gst.Element>> payloader_tees = new HashMap<PayloadType, Gee.Map<uint, Gst.Element>>(PayloadType.hash_func, PayloadType.equals_func);
    private Gee.Map<PayloadType, Gee.Map<uint, uint>> payloader_links = new HashMap<PayloadType, Gee.Map<uint, uint>>(PayloadType.hash_func, PayloadType.equals_func);

    // Bitrate
    private Gee.Map<PayloadType, Gee.List<CodecBitrate>> codec_bitrates = new HashMap<PayloadType, Gee.List<CodecBitrate>>(PayloadType.hash_func, PayloadType.equals_func);

    // Bandwidth coordination: max total video upload budget (kbit/s).
    // With N outgoing peers the encoder is capped at MAX_VIDEO_UPLOAD_KBPS/N
    // so the aggregate upload stays within the budget.
    private const uint MAX_VIDEO_UPLOAD_KBPS = 2048;

    private class CodecBitrate {
        public uint bitrate;
        public int64 timestamp;

        public CodecBitrate(uint bitrate) {
            this.bitrate = bitrate;
            this.timestamp = get_monotonic_time();
        }
    }

    public Device(Plugin plugin, Gst.Device device) {
        this.plugin = plugin;
        update(device);
    }

    public bool matches(Gst.Device device) {
        if (this.device == null) return false;
        if (this.device.name == device.name) return true;
        return false;
    }

    public void set_digital_gain_db(int gain_db, bool manual_mode) {
#if WITH_VOICE_PROCESSOR
        if (dsp != null && dsp is VoiceProcessor) {
            debug("Device: invoking VoiceProcessor set_gain_db");
            ((VoiceProcessor) dsp).set_gain_db(gain_db, manual_mode);
        } else {
            debug("Device: dsp is null or not VoiceProcessor. dsp=%s", dsp == null ? "null" : dsp.get_type().name());
        }
#endif
    }

    public void update(Gst.Device device) {
        this.device = device;
        this.device_name = device.name;
        this.device_display_name = device.display_name;
        // Cache media type so it's available even after device ref is released
        if (device.has_classes("Audio")) {
            _cached_media = "audio";
        } else if (device.has_classes("Video")) {
            _cached_media = "video";
        } else {
            _cached_media = null;
        }
    }

    public Gst.Element? link_sink() {
        if (!is_sink) return null;
        if (element == null) create();
        links++;
        if (mixer != null) {
            sink_peers++;
            Gst.Element rate = Gst.ElementFactory.make("audiorate", @"$(id)_rate_$(Random.next_int())");
            pipe.add(rate);
            rate.link(mixer);
            update_recv_gain();
            return rate;
        }
        if (media == "audio") return filter;
        return element;
    }

    public Gst.Element? link_source(PayloadType? payload_type = null, uint ssrc = 0, int seqnum_offset = -1, uint32 timestamp_offset = 0) {
        if (!is_source) return null;
        if (element == null) create();
        links++;
        if (payload_type != null && ssrc != 0 && tee != null) {
            bool new_codec = false;
            string? codec = CodecUtil.get_codec_from_payload(media, payload_type);
            if (!codecs.has_key(payload_type)) {
                codecs[payload_type] = codec_util.get_encode_bin_without_payloader(media, payload_type, @"$(id)_$(codec)_encoder");
                pipe.add(codecs[payload_type]);
                new_codec = true;
            }
            if (!codec_tees.has_key(payload_type)) {
                codec_tees[payload_type] = Gst.ElementFactory.make("tee", @"$(id)_$(codec)_tee");
                codec_tees[payload_type].@set("allow-not-linked", true);
                pipe.add(codec_tees[payload_type]);
                codecs[payload_type].link(codec_tees[payload_type]);
            }
            if (!payloaders.has_key(payload_type)) {
                payloaders[payload_type] = new HashMap<uint, Gst.Element>();
            }
            if (!payloaders[payload_type].has_key(ssrc)) {
                payloaders[payload_type][ssrc] = codec_util.get_payloader_bin(media, payload_type, @"$(id)_$(codec)_$(ssrc)");
                var payload = (Gst.RTP.BasePayload) ((Gst.Bin) payloaders[payload_type][ssrc]).get_by_name(@"$(id)_$(codec)_$(ssrc)_rtp_pay");
                payload.ssrc = ssrc;
                payload.seqnum_offset = seqnum_offset;
                if (timestamp_offset != 0) {
                    payload.timestamp_offset = timestamp_offset;
                }
                pipe.add(payloaders[payload_type][ssrc]);
                codec_tees[payload_type].link(payloaders[payload_type][ssrc]);
                debug("Payload for %s with %s using ssrc %u, seqnum_offset %u, timestamp_offset %u", media, codec, ssrc, seqnum_offset, timestamp_offset);
            }
            if (!payloader_tees.has_key(payload_type)) {
                payloader_tees[payload_type] = new HashMap<uint, Gst.Element>();
            }
            if (!payloader_tees[payload_type].has_key(ssrc)) {
                payloader_tees[payload_type][ssrc] = Gst.ElementFactory.make("tee", @"$(id)_$(codec)_$(ssrc)_tee");
                payloader_tees[payload_type][ssrc].@set("allow-not-linked", true);
                pipe.add(payloader_tees[payload_type][ssrc]);
                payloaders[payload_type][ssrc].link(payloader_tees[payload_type][ssrc]);
            }
            if (!payloader_links.has_key(payload_type)) {
                payloader_links[payload_type] = new HashMap<uint, uint>();
            }
            if (!payloader_links[payload_type].has_key(ssrc)) {
                payloader_links[payload_type][ssrc] = 1;
            } else {
                payloader_links[payload_type][ssrc] = payloader_links[payload_type][ssrc] + 1;
            }
            if (new_codec) {
                tee.link(codecs[payload_type]);
            }
            // Bandwidth coordination: immediately cap encoder bitrate
            // when a new outgoing peer is added for video.
            if (media == "video" && payloaders.has_key(payload_type) && payloaders[payload_type].size > 1) {
                uint budget = MAX_VIDEO_UPLOAD_KBPS / (uint)payloaders[payload_type].size;
                if (budget < 128) budget = 128;
                debug("Bandwidth: new peer #%d, capping encoder to %u kbps",
                      payloaders[payload_type].size, budget);
                update_bitrate(payload_type, budget);
            }
            return payloader_tees[payload_type][ssrc];
        }
        if (tee != null) return tee;
        return element;
    }

    private static double get_target_bitrate(Gst.Caps caps) {
        if (caps == null || caps.get_size() == 0) return uint.MAX;
        unowned Gst.Structure? that = caps.get_structure(0);
        int num = 0, den = 0, width = 0, height = 0;
        if (!that.has_field("width") || !that.get_int("width", out width)) return uint.MAX;
        if (!that.has_field("height") || !that.get_int("height", out height)) return uint.MAX;
        if (!that.has_field("framerate")) return uint.MAX;
        Value framerate = that.get_value("framerate");
        if (framerate.type() != typeof(Gst.Fraction)) return uint.MAX;
        num = Gst.Value.get_fraction_numerator(framerate);
        den = Gst.Value.get_fraction_denominator(framerate);
        double pxs = ((double)num/(double)den) * (double)width * (double)height;
        double br = Math.sqrt(Math.sqrt(pxs)) * 100.0 - 3700.0;
        if (br < 128.0) return 128.0;
        return br;
    }

    private Gst.Caps get_active_caps(PayloadType payload_type) {
        return codec_util.get_rescale_caps(codecs[payload_type]) ?? device_caps;
    }

    private void apply_caps(PayloadType payload_type, Gst.Caps caps) {
        plugin.pause();
        debug("Set scaled caps to %s", caps.to_string());
        codec_util.update_rescale_caps(codecs[payload_type], caps);
        plugin.unpause();
    }

    private void apply_width(PayloadType payload_type, int new_width, uint bitrate) {
        int device_caps_width, device_caps_height, active_caps_width, device_caps_framerate_num, device_caps_framerate_den;
        device_caps.get_structure(0).get_int("width", out device_caps_width);
        device_caps.get_structure(0).get_int("height", out device_caps_height);
        device_caps.get_structure(0).get_fraction("framerate", out device_caps_framerate_num, out device_caps_framerate_den);
        Gst.Caps active_caps = get_active_caps(payload_type);
        if (active_caps != null && active_caps.get_size() > 0) {
            active_caps.get_structure(0).get_int("width", out active_caps_width);
        } else {
            active_caps_width = device_caps_width;
        }
        if (new_width == active_caps_width) return;
        int new_height = device_caps_height * new_width / device_caps_width;
        if ((new_height % 2) != 0) {
            new_height += 1;
        }
        Gst.Caps new_caps;
        if (device_caps_framerate_den != 0) {
            new_caps = new Gst.Caps.simple("video/x-raw", "width", typeof(int), new_width, "height", typeof(int), new_height, "framerate", typeof(Gst.Fraction), device_caps_framerate_num, device_caps_framerate_den, null);
        } else {
            new_caps = new Gst.Caps.simple("video/x-raw", "width", typeof(int), new_width, "height", typeof(int), new_height, null);
        }
        double required_bitrate = get_target_bitrate(new_caps);
        debug("Changing resolution width from %d to %d (requires bitrate %f, current target is %u)", active_caps_width, new_width, required_bitrate, bitrate);
        if (bitrate < required_bitrate && new_width > active_caps_width) return;
        apply_caps(payload_type, new_caps);
    }

    public void update_bitrate(PayloadType payload_type, uint bitrate) {
        if (codecs.has_key(payload_type)) {
            lock(codec_bitrates);
            if (!codec_bitrates.has_key(payload_type)) {
                codec_bitrates[payload_type] = new ArrayList<CodecBitrate>();
            }
            codec_bitrates[payload_type].add(new CodecBitrate(bitrate));
            var remove = new ArrayList<CodecBitrate>();
            foreach (CodecBitrate rate in codec_bitrates[payload_type]) {
                if (rate.timestamp < get_monotonic_time() - 5000000L) {
                    remove.add(rate);
                    continue;
                }
                if (rate.bitrate < bitrate) {
                    bitrate = rate.bitrate;
                }
            }
            codec_bitrates[payload_type].remove_all(remove);
            if (media == "video") {
                if (bitrate < 128) bitrate = 128;
                // Multi-peer bandwidth coordination: cap at per-peer budget
                int source_peers = get_source_peer_count(payload_type);
                if (source_peers > 1) {
                    uint per_peer_budget = MAX_VIDEO_UPLOAD_KBPS / (uint)source_peers;
                    if (per_peer_budget < 128) per_peer_budget = 128;
                    if (bitrate > per_peer_budget) {
                        debug("Bandwidth: cap %u -> %u kbps (%d peers, %u total)",
                              bitrate, per_peer_budget, source_peers, MAX_VIDEO_UPLOAD_KBPS);
                        bitrate = per_peer_budget;
                    }
                }
                Gst.Caps active_caps = get_active_caps(payload_type);
                double max_bitrate = get_target_bitrate(device_caps) * 2;
                double current_target_bitrate = get_target_bitrate(active_caps);
                int device_caps_width, active_caps_width;
                device_caps.get_structure(0).get_int("width", out device_caps_width);
                if (active_caps != null && active_caps.get_size() > 0) {
                    active_caps.get_structure(0).get_int("width", out active_caps_width);
                } else {
                    active_caps_width = device_caps_width;
                }
                if (bitrate < 0.75 * current_target_bitrate && active_caps_width > common_widths[0]) {
                    // Lower video resolution
                    int i = 1;
                    for(; i < common_widths.length && common_widths[i] < active_caps_width; i++);if (common_widths[i] != active_caps_width) {
                        debug("Decrease resolution to ensure target bitrate (%u) is in reach (current resolution target bitrate is %f)", bitrate, current_target_bitrate);
                    }
                    apply_width(payload_type, common_widths[i-1], bitrate);
                } else if (bitrate > 2 * current_target_bitrate && active_caps_width < device_caps_width) {
                    // Higher video resolution
                    int i = 0;
                    for(; i < common_widths.length && common_widths[i] <= active_caps_width; i++);
                    if (common_widths[i] != active_caps_width) {
                        debug("Increase resolution to make use of available bandwidth of target bitrate (%u) (current resolution target bitrate is %f)", bitrate, current_target_bitrate);
                    }
                    if (common_widths[i] > device_caps_width) {
                        // We never scale up, so just stick with what the device gives
                        apply_width(payload_type, device_caps_width, bitrate);
                    } else if (common_widths[i] != active_caps_width) {
                        apply_width(payload_type, common_widths[i], bitrate);
                    }
                }
                if (bitrate > max_bitrate) bitrate = (uint) max_bitrate;
            }
            codec_util.update_bitrate(media, payload_type, codecs[payload_type], bitrate);
            unlock(codec_bitrates);
        }
    }

    public void unlink(Gst.Element? link = null) {
        if (links <= 0) {
            critical("Link count below zero.");
            return;
        }
        if (link != null && is_source && tee != null) {
            PayloadType payload_type = payloader_tees.first_match((entry) => entry.value.any_match((entry) => entry.value == link)).key;
            uint ssrc = payloader_tees[payload_type].first_match((entry) => entry.value == link).key;
            payloader_links[payload_type][ssrc] = payloader_links[payload_type][ssrc] - 1;
            if (payloader_links[payload_type][ssrc] == 0) {
                plugin.pause();

                codec_tees[payload_type].unlink(payloaders[payload_type][ssrc]);
                payloaders[payload_type][ssrc].set_locked_state(true);
                payloaders[payload_type][ssrc].set_state(Gst.State.NULL);
                payloaders[payload_type][ssrc].unlink(payloader_tees[payload_type][ssrc]);
                pipe.remove(payloaders[payload_type][ssrc]);
                payloaders[payload_type].unset(ssrc);
                payloader_tees[payload_type][ssrc].set_locked_state(true);
                payloader_tees[payload_type][ssrc].set_state(Gst.State.NULL);
                pipe.remove(payloader_tees[payload_type][ssrc]);
                payloader_tees[payload_type].unset(ssrc);

                payloader_links[payload_type].unset(ssrc);
                plugin.unpause();
                // Bandwidth coordination: peer left, raise budget for remaining peers
                if (media == "video" && payloaders.has_key(payload_type) && payloaders[payload_type].size > 0) {
                    uint budget = MAX_VIDEO_UPLOAD_KBPS / (uint)payloaders[payload_type].size;
                    if (budget < 128) budget = 128;
                    debug("Bandwidth: peer left, raising cap to %u kbps (%d peers)",
                          budget, payloaders[payload_type].size);
                    update_bitrate(payload_type, budget);
                }
            }
            if (payloader_links[payload_type].size == 0) {
                plugin.pause();

                tee.unlink(codecs[payload_type]);
                codecs[payload_type].set_locked_state(true);
                codecs[payload_type].set_state(Gst.State.NULL);
                codecs[payload_type].unlink(codec_tees[payload_type]);
                pipe.remove(codecs[payload_type]);
                codecs.unset(payload_type);
                codec_tees[payload_type].set_locked_state(true);
                codec_tees[payload_type].set_state(Gst.State.NULL);
                pipe.remove(codec_tees[payload_type]);
                codec_tees.unset(payload_type);

                payloaders.unset(payload_type);
                payloader_tees.unset(payload_type);
                payloader_links.unset(payload_type);
                plugin.unpause();
            }
        }
        if (link != null && is_sink && mixer != null) {
            plugin.pause();
            link.set_locked_state(true);
            Gst.Base.AggregatorPad mixer_sink_pad = (Gst.Base.AggregatorPad) link.get_static_pad("src").get_peer();
            link.get_static_pad("src").unlink(mixer_sink_pad);
            mixer_sink_pad.set_active(false);
            link.set_state(Gst.State.NULL);
            pipe.remove(link);
            mixer.release_request_pad(mixer_sink_pad);
            plugin.unpause();
            sink_peers = int.max(0, sink_peers - 1);
            update_recv_gain();
        }
        links--;
        if (links == 0) {
            destroy();
        }
    }

    // Number of outgoing peers sharing the video encoder for a codec.
    // Used to divide the upload budget fairly.
    private int get_source_peer_count(PayloadType payload_type) {
        if (!payloaders.has_key(payload_type)) return 1;
        return int.max(1, payloaders[payload_type].size);
    }

    // Compute target receive gain: 1/sqrt(N) to prevent clipping when
    // multiple peers speak simultaneously through the audiomixer.
    // 1 peer = 1.0, 2 = 0.71, 3 = 0.58, 4 = 0.50, 5 = 0.45
    private double get_target_recv_gain() {
        if (sink_peers <= 1) return 1.0;
        return 1.0 / Math.sqrt((double) sink_peers);
    }

    // Adjust recv_volume to current target gain (only after ramp-up is done)
    private void update_recv_gain() {
        if (!recv_ramp_done || recv_volume == null) return;
        double target = get_target_recv_gain();
        debug("Recv gain updated: %d peers -> %.2f", sink_peers, target);
        recv_volume.@set("volume", target);
    }

    private Gst.Caps get_best_caps() {
        if (media == "audio") {
            return Gst.Caps.from_string("audio/x-raw,rate=48000,channels=1");
        } else if (media == "video" && device != null && device.caps.get_size() > 0) {
            int best_index = -1;
            Value? best_fraction = null;
            int best_fps = 0;
            int best_width = 0;
            int best_height = 0;
            for (int i = 0; i < device.caps.get_size(); i++) {
                unowned Gst.Structure? that = device.caps.get_structure(i);
                unowned Gst.CapsFeatures? features = device.caps.get_features(i);
                Value? best_fraction_now = null;
                if (!that.has_name("video/x-raw")) continue;
                // Skip DMABuf/DRM caps — older V4L2 drivers (e.g. Haswell)
                // advertise DMA_DRM caps they cannot actually deliver, causing
                // the pipeline to starve (0 kbps sent).
                if (features != null && features.contains("memory:DMABuf")) continue;
                if (that.has_field("format")) {
                    unowned string? fmt = that.get_string("format");
                    if (fmt == "DMA_DRM") continue;
                }
                int num = 0, den = 0, width = 0, height = 0;
                if (!that.has_field("framerate")) continue;
                Value framerate = that.get_value("framerate");
                if (framerate.type() == typeof(Gst.Fraction)) {
                    num = Gst.Value.get_fraction_numerator(framerate);
                    den = Gst.Value.get_fraction_denominator(framerate);
                } else if (framerate.type() == typeof(Gst.ValueList)) {
                    for(uint j = 0; j < Gst.ValueList.get_size(framerate); j++) {
                        Value fraction = Gst.ValueList.get_value(framerate, j);
                        int in_num = Gst.Value.get_fraction_numerator(fraction);
                        int in_den = Gst.Value.get_fraction_denominator(fraction);
                        int fps = den > 0 ? (num/den) : 0;
                        int in_fps = in_den > 0 ? (in_num/in_den) : 0;
                        if (in_fps > fps) {
                            best_fraction_now = fraction;
                            num = in_num;
                            den = in_den;
                        }
                    }
                } else {
                    debug("Unknown type for framerate: %s", framerate.type_name());
                }
                if (den == 0) continue;
                if (!that.has_field("width") || !that.get_int("width", out width)) continue;
                if (!that.has_field("height") || !that.get_int("height", out height)) continue;
                int fps = num/den;
                if (best_fps < fps || best_fps == fps && best_width < width || best_fps == fps && best_width == width && best_height < height) {
                    best_fps = fps;
                    best_width = width;
                    best_height = height;
                    best_index = i;
                    best_fraction = best_fraction_now;
                }
            }
            if (best_index == -1) {
                // No caps in first round, try without framerate
                int target_pixel_count = 1280 * 720;
                double target_pixel_ratio = 16.0 / 9.0;
                double best_diversion_factor = 0.0;

                for (int i = 0; i < device.caps.get_size(); i++) {
                    unowned Gst.Structure? that = device.caps.get_structure(i);
                    unowned Gst.CapsFeatures? features = device.caps.get_features(i);
                    if (!that.has_name("video/x-raw") || !features.contains("memory:SystemMemory")) continue;
                    int width = 0, height = 0;
                    if (!that.has_field("width") || !that.get_int("width", out width) || width == 0) continue;
                    if (!that.has_field("height") || !that.get_int("height", out height) || height == 0) continue;

                    int pixel_count = width * height;
                    double pixel_count_diversion_factor;
                    if (pixel_count > target_pixel_count)
                        pixel_count_diversion_factor = (double)pixel_count / target_pixel_count;
                    else
                        pixel_count_diversion_factor = (double)target_pixel_count / pixel_count;

                    double pixel_ratio;
                    if (width > height)
                        pixel_ratio = (double)width / height;
                    else
                        pixel_ratio = (double)height / width;

                    double ratio_diversion_factor;
                    if (pixel_ratio > target_pixel_ratio)
                        ratio_diversion_factor = pixel_ratio / target_pixel_ratio;
                    else
                        ratio_diversion_factor = target_pixel_ratio / pixel_ratio;

                    // 1.0 is the best possible value. Any diversion from
                    // target_pixel_count or target_pixel_ratio increases it.
                    double diversion_factor = pixel_count_diversion_factor * ratio_diversion_factor;

                    if (best_index == -1 || diversion_factor < best_diversion_factor) {
                        best_index = i;
                        best_width = width;
                        best_height = height;
                        best_diversion_factor = diversion_factor;
                    }
                }
            }
            if (best_index == -1) {
                warning("No suitable caps found, falling back to first cap");
                best_index = 0;
            }
            Gst.Caps res = caps_copy_nth(device.caps, best_index);
            unowned Gst.Structure? that = res.get_structure(0);
            Value? framerate = that.get_value("framerate");
            if (framerate != null && framerate.type() == typeof(Gst.ValueList) && best_fraction != null) {
                that.set_value("framerate", best_fraction);
            } else if (framerate == null) {
                // The source does not support framerate negotiation. Just set a
                // reasonable value. The source might be able to honor it and
                // should ignore it otherwise.
                that.@set("framerate", typeof(Gst.Fraction), 30, 1, null);
            }
            debug("Selected caps %s", res.to_string());
            return res;
        } else if (device.caps.get_size() > 0) {
            return caps_copy_nth(device.caps, 0);
        } else {
            return new Gst.Caps.any();
        }
    }

    // Backport from gst_caps_copy_nth added in GStreamer 1.16
    private static Gst.Caps caps_copy_nth(Gst.Caps source, uint index) {
        Gst.Caps target = new Gst.Caps.empty();
        target.flags = source.flags;
        target.append_structure_full(source.get_structure(index).copy(), source.get_features(index).copy());
        return target;
    }

    private void create() {
        if (device == null) {
            warning("Cannot create device %s — Gst.Device already released", id);
            return;
        }
        debug("Creating device %s", id);
        plugin.pause();
        element = device.create_element(id);
        if (is_sink) {
            element.@set("async", false);
            element.@set("sync", false);
        }
        pipe.add(element);
        // element.sync_state_with_parent(); // Moved to after linking
        device_caps = get_best_caps();
        if (is_source) {
            element.@set("do-timestamp", true);
            filter = Gst.ElementFactory.make("capsfilter", @"caps_filter_$id");
            filter.@set("caps", device_caps);
            pipe.add(filter);
            filter.sync_state_with_parent();
            element.link(filter);
            element.sync_state_with_parent();
#if WITH_VOICE_PROCESSOR
            if (media == "audio" && plugin.echoprobe != null) {
                dsp = new VoiceProcessor(plugin.echoprobe as EchoProbe, element as Gst.Audio.StreamVolume);
                dsp.name = @"dsp_$id";
                pipe.add(dsp);
                dsp.sync_state_with_parent();
                filter.link(dsp);
            }
#endif
            tee = Gst.ElementFactory.make("tee", @"tee_$id");
            tee.@set("allow-not-linked", true);
            pipe.add(tee);
            tee.sync_state_with_parent();

            // Insert Source Queue for stability
            source_queue = Gst.ElementFactory.make("queue", @"src_q_$id");
            pipe.add(source_queue);
            source_queue.sync_state_with_parent();

            // Insert Software Volume Control (Post-Processing)
            if (media == "audio") {
                volume_element = Gst.ElementFactory.make("volume", @"vol_$id");
                // Start muted, ramp up over 200ms to avoid PipeWire/PulseAudio init transients
                volume_element.@set("volume", 0.0);
                pipe.add(volume_element);
                volume_element.sync_state_with_parent();
                
                (dsp ?? filter).link(volume_element);
                volume_element.link(source_queue);

                // Smooth ramp-up: 0→1.0 in 200ms (10 steps of 20ms)
                int ramp_step = 0;
                GLib.Timeout.add(20, () => {
                    if (volume_element == null) return false;
                    ramp_step++;
                    double vol = ramp_step / 10.0;
                    if (vol >= 1.0) {
                        volume_element.@set("volume", 1.0);
                        return false;
                    }
                    volume_element.@set("volume", vol);
                    return true;
                });
            } else {
                (dsp ?? filter).link(source_queue);
            }
            source_queue.link(tee);
        }
        if (is_sink) {
            if (media == "audio") {
                mixer = (Gst.Base.Aggregator) Gst.ElementFactory.make("audiomixer", @"mixer_$id");
                pipe.add(mixer);
                mixer.sync_state_with_parent();

                // Volume ramp-up on receive path to prevent initial crackling
                recv_volume = Gst.ElementFactory.make("volume", @"recv_vol_$id");
                pipe.add(recv_volume);
                recv_volume.@set("volume", 0.0);
                recv_volume.sync_state_with_parent();
                mixer.link(recv_volume);
                // Ramp up from 0.0 to target over 200ms (10 steps x 20ms)
                // Target gain is 1/sqrt(N) to prevent clipping with N peers
                double recv_vol = 0.0;
                GLib.Timeout.add(20, () => {
                    double target = get_target_recv_gain();
                    recv_vol += target / 10.0;
                    if (recv_volume == null) return false;
                    if (recv_vol >= target) {
                        recv_volume.@set("volume", target);
                        recv_ramp_done = true;
                        return false;
                    }
                    recv_volume.@set("volume", recv_vol);
                    return true;
                });

                if (plugin.echoprobe != null && !plugin.echoprobe.get_static_pad("src").is_linked()) {
                    // Ensure the echo reference matches VoiceProcessor's expected format (48kHz/mono/S16LE)
                    // to avoid caps mismatches (e.g. stereo from some peers/devices) degrading AEC.
                    echo_convert = Gst.ElementFactory.make("audioconvert", @"echo_convert_$id");
                    echo_resample = Gst.ElementFactory.make("audioresample", @"echo_resample_$id");
                    echo_filter = Gst.ElementFactory.make("capsfilter", @"echo_caps_$id");
                    if (echo_convert != null && echo_resample != null && echo_filter != null) {
                        echo_filter.@set("caps", Gst.Caps.from_string("audio/x-raw,rate=48000,channels=1,layout=interleaved,format=S16LE"));
                        pipe.add(echo_convert);
                        pipe.add(echo_resample);
                        pipe.add(echo_filter);
                        echo_convert.sync_state_with_parent();
                        echo_resample.sync_state_with_parent();
                        echo_filter.sync_state_with_parent();

                        recv_volume.link(echo_convert);
                        echo_convert.link(echo_resample);
                        echo_resample.link(echo_filter);
                        echo_filter.link(plugin.echoprobe);
                        plugin.echoprobe.link(element);
                    } else {
                        recv_volume.link(plugin.echoprobe);
                        plugin.echoprobe.link(element);
                    }
                } else {
                    filter = Gst.ElementFactory.make("capsfilter", @"caps_filter_$id");
                    filter.@set("caps", device_caps);
                    pipe.add(filter);
                    filter.sync_state_with_parent();
                    recv_volume.link(filter);
                    filter.link(element);
                }
            }
            element.sync_state_with_parent();
        }
        plugin.unpause();
    }

    /**
     * Called when the pipeline is being destroyed. All child elements
     * go with it — just null references so create() re-builds them.
     * Also release the Gst.Device ref so that the GstDeviceProvider
     * (and its PipeWire connection) can be finalized.
     */
    public void on_pipe_destroyed() {
        device = null;
        element = null;
        mixer = null;
        tee = null;
        filter = null;
        source_queue = null;
        volume_element = null;
        dsp = null;
        recv_volume = null;
        echo_convert = null;
        echo_resample = null;
        echo_filter = null;
        codecs.clear();
        codec_tees.clear();
        payloaders.clear();
        payloader_tees.clear();
        payloader_links.clear();
        codec_bitrates.clear();
        links = 0;
        sink_peers = 0;
        recv_ramp_done = false;
    }

    private void destroy() {
        if (pipe == null) {
            // Pipeline already torn down
            on_pipe_destroyed();
            debug("Destroyed device %s (pipe already gone)", id);
            return;
        }
        if (is_sink) {
            if (mixer != null) {
                int linked_sink_pads = 0;
                mixer.foreach_sink_pad((_, pad) => {
                    if (pad.is_linked()) linked_sink_pads++;
                    return true;
                });
                if (linked_sink_pads > 0) {
                    warning("%s-mixer still has %i sink pads while being destroyed", id, linked_sink_pads);
                }
                if (plugin.echoprobe != null) {
                    if (echo_filter != null) echo_filter.unlink(plugin.echoprobe);
                    if (echo_resample != null && echo_filter != null) echo_resample.unlink(echo_filter);
                    if (echo_convert != null && echo_resample != null) echo_convert.unlink(echo_resample);
                    if (recv_volume != null && echo_convert != null) recv_volume.unlink(echo_convert);
                    else if (recv_volume != null) recv_volume.unlink(plugin.echoprobe);
                    if (recv_volume != null) mixer.unlink(recv_volume);
                    else mixer.unlink(plugin.echoprobe);
                } else if (element != null) {
                    mixer.unlink(element);
                }
            }
            if (echo_filter != null) {
                echo_filter.set_locked_state(true);
                echo_filter.set_state(Gst.State.NULL);
                pipe.remove(echo_filter);
                echo_filter = null;
            }
            if (echo_resample != null) {
                echo_resample.set_locked_state(true);
                echo_resample.set_state(Gst.State.NULL);
                pipe.remove(echo_resample);
                echo_resample = null;
            }
            if (echo_convert != null) {
                echo_convert.set_locked_state(true);
                echo_convert.set_state(Gst.State.NULL);
                pipe.remove(echo_convert);
                echo_convert = null;
            }
            if (filter != null && element != null) {
                filter.set_locked_state(true);
                filter.set_state(Gst.State.NULL);
                filter.unlink(element);
                pipe.remove(filter);
                filter = null;
            }
            if (recv_volume != null) {
                recv_volume.set_locked_state(true);
                recv_volume.set_state(Gst.State.NULL);
                pipe.remove(recv_volume);
                recv_volume = null;
            }
            if (plugin.echoprobe != null && element != null) {
                plugin.echoprobe.unlink(element);
            }
        }
        if (is_source) {
            // 1. Unlink the full source chain to break pad reference cycles.
            //    gst_bin_remove() does NOT unlink pads, so we must do it
            //    explicitly to avoid elements keeping each other alive.
            if (element != null && filter != null) element.unlink(filter);
            if (filter != null && dsp != null) filter.unlink(dsp);
            else if (filter != null && volume_element != null) filter.unlink(volume_element);
            else if (filter != null && source_queue != null) filter.unlink(source_queue);
            if (dsp != null && volume_element != null) dsp.unlink(volume_element);
            else if (dsp != null && source_queue != null) dsp.unlink(source_queue);
            if (volume_element != null && source_queue != null) volume_element.unlink(source_queue);
            if (source_queue != null && tee != null) source_queue.unlink(tee);

            // 2. Stop execution of all elements
            if (tee != null) tee.set_state(Gst.State.NULL);
            if (source_queue != null) source_queue.set_state(Gst.State.NULL);
            if (volume_element != null) volume_element.set_state(Gst.State.NULL);
            if (dsp != null) dsp.set_state(Gst.State.NULL);
            if (filter != null) filter.set_state(Gst.State.NULL);
            
            foreach (var map in payloader_tees.values) {
                foreach (var pt in map.values) pt.set_state(Gst.State.NULL);
            }
            foreach (var map in payloaders.values) {
                foreach (var p in map.values) p.set_state(Gst.State.NULL);
            }
            foreach (var t in codec_tees.values) t.set_state(Gst.State.NULL);
            foreach (var c in codecs.values) c.set_state(Gst.State.NULL);

            // 3. Remove auxiliary chains (Codecs/Payloaders)
            foreach (var map in payloader_tees.values) {
                foreach (var pt in map.values) pipe.remove(pt);
            }
            payloader_tees.clear();

            foreach (var map in payloaders.values) {
                foreach (var p in map.values) pipe.remove(p);
            }
            payloaders.clear();
            payloader_links.clear();

            foreach (var t in codec_tees.values) pipe.remove(t);
            codec_tees.clear();

            foreach (var c in codecs.values) pipe.remove(c);
            codecs.clear();
            codec_bitrates.clear();

            // 4. Remove main chain elements (reverse data-flow order)
            if (tee != null) {
                pipe.remove(tee);
                tee = null;
            }
            if (source_queue != null) {
                pipe.remove(source_queue);
                source_queue = null;
            }
            if (volume_element != null) {
                pipe.remove(volume_element);
                volume_element = null;
            }
            if (dsp != null) {
                pipe.remove(dsp);
                dsp = null;
            }
            if (filter != null) {
                pipe.remove(filter);
                filter = null;
            }
        }
        if (element != null) {
            element.set_locked_state(true);
            element.set_state(Gst.State.NULL);
            pipe.remove(element);
            element = null;
        }
        if (mixer != null) {
            mixer.set_locked_state(true);
            mixer.set_state(Gst.State.NULL);
            pipe.remove(mixer);
            mixer = null;
        }
        debug("Destroyed device %s", id);
    }

    public double get_volume() {
        if (volume_element != null) {
            double vol = 1.0;
            volume_element.get("volume", out vol);
            return vol;
        }
        if (element == null) return 1.0;
        var stream_volume = element as Gst.Audio.StreamVolume;
        if (stream_volume == null) return 1.0;
        return stream_volume.get_volume(Gst.Audio.StreamVolumeFormat.LINEAR);
    }

    public void set_volume(double volume) {
        if (volume_element != null) {
            volume_element.set("volume", volume);
            return;
        }
        if (element == null) return;
        var stream_volume = element as Gst.Audio.StreamVolume;
        if (stream_volume == null) return;
        stream_volume.set_volume(Gst.Audio.StreamVolumeFormat.LINEAR, volume.clamp(0.0, 1.0));
    }
}
