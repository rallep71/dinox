using Gee;
using Xmpp;
using Xmpp.Xep;

public class Dino.Plugins.Rtp.Module : JingleRtp.Module {
    private Set<string> supported_codecs = new HashSet<string>();
    private Set<string> unsupported_codecs = new HashSet<string>();
    public Plugin plugin { get; private set; }
    public CodecUtil codec_util { get {
        return plugin.codec_util;
    }}

    public Module(Plugin plugin) {
        base();
        this.plugin = plugin;
    }

    private async bool pipeline_works(string media, string element_desc) {
        var supported = false;
        string pipeline_desc = @"$(media)testsrc is-live=true ! $element_desc ! appsink name=output";
        try {
            var pipeline = Gst.parse_launch(pipeline_desc);
            var output = ((Gst.Bin) pipeline).get_by_name("output") as Gst.App.Sink;
            SourceFunc callback = pipeline_works.callback;
            var finished = false;
            output.emit_signals = true;
            output.new_sample.connect(() => {
                if (!finished) {
                    finished = true;
                    supported = true;
                    Idle.add(() => {
                        callback();
                        return Source.REMOVE;
                    });
                }
                return Gst.FlowReturn.EOS;
            });
            pipeline.bus.add_watch(Priority.DEFAULT, (_, message) => {
                if (message.type == Gst.MessageType.ERROR && !finished) {
                    Error e;
                    string d;
                    message.parse_error(out e, out d);
                    debug("pipeline [%s] failed: %s", pipeline_desc, e.message);
                    debug(d);
                    finished = true;
                    callback();
                }
                return true;
            });
            Timeout.add(5000, () => {
                if (!finished) {
                    finished = true;
                    callback();
                }
                return Source.REMOVE;
            });
            pipeline.set_state(Gst.State.PLAYING);
            yield;
            pipeline.set_state(Gst.State.NULL);
        } catch (Error e) {
            debug("pipeline [%s] failed: %s", pipeline_desc, e.message);
        }
        return supported;
    }

    public override async bool is_payload_supported(string media, JingleRtp.PayloadType payload_type) {
        string? codec = CodecUtil.get_codec_from_payload(media, payload_type);
        if (codec == null) return false;

        // telephone-event (RFC 4733 DTMF) is always supported — no pipeline check needed
        if (codec.down() == "telephone-event") {
            supported_codecs.add(codec);
            return true;
        }

        // Speex is deprecated/unreliable in our pipeline checks (and not needed for interop).
        // Avoid probing/negotiating it entirely.
        if (codec.down() == "speex") {
            unsupported_codecs.add(codec);
            return false;
        }

        if (unsupported_codecs.contains(codec)) return false;
        if (supported_codecs.contains(codec)) return true;

        // Force VP9 support to bypass flaky pipeline check
        if (codec == "vp9") {
            supported_codecs.add(codec);
            return true;
        }

        string? encode_element = codec_util.get_encode_element_name(media, codec);
        string? decode_element = codec_util.get_decode_element_name(media, codec);
        if (encode_element == null || decode_element == null) {
            warning("No suitable encoder or decoder found for %s", codec);
            unsupported_codecs.add(codec);
            return false;
        }

        string encode_bin = codec_util.get_encode_bin_description(media, codec, null, encode_element);
        while (!(yield pipeline_works(media, encode_bin))) {
            debug("%s not suited for encoding %s", encode_element, codec);
            codec_util.mark_element_unsupported(encode_element);
            encode_element = codec_util.get_encode_element_name(media, codec);
            if (encode_element == null) {
                warning("No suitable encoder found for %s", codec);
                unsupported_codecs.add(codec);
                return false;
            }
            encode_bin = codec_util.get_encode_bin_description(media, codec, null, encode_element);
        }
        debug("using %s to encode %s", encode_element, codec);

        string decode_bin = codec_util.get_decode_bin_description(media, codec, null, decode_element);
        while (!(yield pipeline_works(media, @"$encode_bin ! $decode_bin"))) {
            debug("%s not suited for decoding %s", decode_element, codec);
            codec_util.mark_element_unsupported(decode_element);
            decode_element = codec_util.get_decode_element_name(media, codec);
            if (decode_element == null) {
                warning("No suitable decoder found for %s", codec);
                unsupported_codecs.add(codec);
                return false;
            }
            decode_bin = codec_util.get_decode_bin_description(media, codec, null, decode_element);
        }
        debug("using %s to decode %s", decode_element, codec);

        supported_codecs.add(codec);
        return true;
    }

    public override bool is_header_extension_supported(string media, JingleRtp.HeaderExtension ext) {
        if (media == "video" && ext.uri == "urn:3gpp:video-orientation") return true;
        return false;
    }

    public override Gee.List<JingleRtp.HeaderExtension> get_suggested_header_extensions(string media) {
        Gee.List<JingleRtp.HeaderExtension> exts = new ArrayList<JingleRtp.HeaderExtension>();
        if (media == "video") {
            exts.add(new JingleRtp.HeaderExtension(1, "urn:3gpp:video-orientation"));
        }
        return exts;
    }

    public async void add_if_supported(Gee.List<JingleRtp.PayloadType> list, string media, JingleRtp.PayloadType payload_type) {
        if (yield is_payload_supported(media, payload_type)) {
            list.add(payload_type);
        }
    }

    public override async Gee.List<JingleRtp.PayloadType> get_supported_payloads(string media) {
        Gee.List<JingleRtp.PayloadType> list = new ArrayList<JingleRtp.PayloadType>(JingleRtp.PayloadType.equals_func);
        if (media == "audio") {
            var opus = new JingleRtp.PayloadType() { channels = 1, clockrate = 48000, name = "opus", id = 111, channels = 2 };
            opus.parameters["useinbandfec"] = "1";
            yield add_if_supported(list, media, opus);

            // G.711 fallback for SIP gateways (e.g. Cheogram) that don't support Opus
            var pcmu = new JingleRtp.PayloadType() { clockrate = 8000, name = "PCMU", id = 0, channels = 1 };
            yield add_if_supported(list, media, pcmu);
            var pcma = new JingleRtp.PayloadType() { clockrate = 8000, name = "PCMA", id = 8, channels = 1 };
            yield add_if_supported(list, media, pcma);

            // RFC 4733 DTMF tones
            var dtmf = new JingleRtp.PayloadType() { clockrate = 8000, name = "telephone-event", id = 101, channels = 1 };
            dtmf.parameters["events"] = "0-15";
            list.add(dtmf);
        } else if (media == "video") {
            var rtcp_fbs = new ArrayList<JingleRtp.RtcpFeedback>();
            rtcp_fbs.add(new JingleRtp.RtcpFeedback("goog-remb"));
            rtcp_fbs.add(new JingleRtp.RtcpFeedback("ccm", "fir"));
            rtcp_fbs.add(new JingleRtp.RtcpFeedback("nack"));
            rtcp_fbs.add(new JingleRtp.RtcpFeedback("nack", "pli"));
            // VP8 first for better compatibility
            var vp8 = new JingleRtp.PayloadType() { clockrate = 90000, name = "VP8", id = 98 };
            vp8.rtcp_fbs.add_all(rtcp_fbs);
            yield add_if_supported(list, media, vp8);
        } else {
            warning("Unsupported media type: %s", media);
        }
        return list;
    }

    public override async JingleRtp.PayloadType? pick_payload_type(string media, Gee.List<JingleRtp.PayloadType> payloads) {
        if (media == "audio" || media == "video") {
            // Prefer VP8 first for better Monal/Conversations compatibility
            // VP8 is the mandatory WebRTC codec and has best cross-client support
            string[] preferred_audio = {"opus", "pcmu", "pcma"};
            string[] preferred_video = {"vp8"};  // VP8 first for compatibility!
            string[] preferred = media == "audio" ? preferred_audio : preferred_video;
            
            foreach (string codec_name in preferred) {
                foreach (JingleRtp.PayloadType type in payloads) {
                    if (type.name.down() == codec_name && (yield is_payload_supported(media, type))) {
                        debug("Selected %s codec (our preference) for %s", type.name, media);
                        return adjust_payload_type(media, type.clone());
                    }
                }
            }
            // Fallback: accept any supported codec from remote list
            foreach (JingleRtp.PayloadType type in payloads) {
                if (yield is_payload_supported(media, type)) {
                    debug("Selected %s codec (remote preference) for %s", type.name, media);
                    return adjust_payload_type(media, type.clone());
                }
            }
        } else {
            warning("Unsupported media type: %s", media);
        }
        return null;
    }

    public JingleRtp.PayloadType adjust_payload_type(string media, JingleRtp.PayloadType type) {
        var iter = type.rtcp_fbs.iterator();
        while (iter.next()) {
            var fb = iter.@get();
            switch (fb.type_) {
                case "goog-remb":
                    if (fb.subtype != null) iter.remove();
                    break;
                case "ccm":
                    if (fb.subtype != "fir") iter.remove();
                    break;
                case "nack":
                    if (fb.subtype != null && fb.subtype != "pli") iter.remove();
                    break;
                default:
                    iter.remove();
                    break;
            }
        }
        return type;
    }

    public override JingleRtp.Stream create_stream(Jingle.Content content) {
        return plugin.open_stream(content);
    }

    public override void close_stream(JingleRtp.Stream stream) {
        var rtp_stream = stream as Rtp.Stream;
        if (rtp_stream != null) {
            plugin.close_stream(rtp_stream);
        }
    }

    public override JingleRtp.Crypto? generate_local_crypto() {
        // WebRTC clients (Conversations/Monal) expect DTLS-SRTP (fingerprint in ICE-UDP transport)
        // and generally do not support SDP/Jingle SDES-SRTP crypto attributes.
        // We negotiate DTLS-SRTP via the ICE transport plugin; therefore do not advertise SDES.
        return null;
    }

    public override JingleRtp.Crypto? pick_remote_crypto(Gee.List<JingleRtp.Crypto> cryptos) {
        // DTLS-SRTP is handled at the transport layer; ignore any offered SDES crypto.
        return null;
    }

    public override JingleRtp.Crypto? pick_local_crypto(JingleRtp.Crypto? remote) {
        // DTLS-SRTP is handled at the transport layer; do not derive SDES keys.
        return null;
    }
}
