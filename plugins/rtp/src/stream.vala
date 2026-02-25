using Gee;
using Xmpp;

private static extern GLib.List<unowned Gst.Structure> rtp_get_source_stats_structures(Gst.Structure stats);

public class Dino.Plugins.Rtp.Stream : Xmpp.Xep.JingleRtp.Stream {
    public uint8 rtpid { get; private set; }

    public Plugin plugin { get; private set; }
    public Gst.Pipeline pipe { get {
        return plugin.pipe;
    }}
    public Gst.Element rtpbin { get {
        return plugin.rtpbin;
    }}
    public CodecUtil codec_util { get {
        return plugin.codec_util;
    }}
    private Gst.App.Sink send_rtp;
    private Gst.App.Sink send_rtcp;
    private Gst.App.Src recv_rtp;
    private Gst.App.Src recv_rtcp;
    private Gst.Element decode;
    private Gst.RTP.BaseDepayload decode_depay;
    private Gst.Element input;
    private Gst.Element? input_queue; // Queue for input decoupling
    private Gst.Pad input_pad;
    private Gst.Element output;
    private Gst.Element session;

    private Device _input_device;
    public Device input_device { get { return _input_device; } set {
        if (sending && !paused) {
            var input = this.input;
            set_input(value != null ? value.link_source(payload_type, our_ssrc, next_seqnum_offset, next_timestamp_offset) : null);
            if (this._input_device != null) this._input_device.unlink(input);
        }
        this._input_device = value;
    }}
    private Device _output_device;
    public Device output_device { get { return _output_device; } set {
        if (output != null) remove_output(output);
        if (value != null && receiving) add_output(value.link_sink());
        this._output_device = value;
    }}

    public bool created { get; private set; default = false; }
    public bool paused { get; private set; default = false; }
    private bool push_recv_data = false;
    private uint our_ssrc = Random.next_int();
    private int next_seqnum_offset = -1;
    private uint32 next_timestamp_offset_base = 0;
    private int64 next_timestamp_offset_stamp = 0;
    private uint32 next_timestamp_offset { get {
        if (next_timestamp_offset_base == 0) return 0;
        int64 monotonic_diff = get_monotonic_time() - next_timestamp_offset_stamp;
        return next_timestamp_offset_base + (uint32)((double)monotonic_diff / 1000000.0 * payload_type.clockrate);
    } }
    private uint32 participant_ssrc = 0;

    private Gst.Pad recv_rtcp_sink_pad;
    private Gst.Pad recv_rtp_sink_pad;
    private Gst.Pad recv_rtp_src_pad;
    private Gst.Pad send_rtcp_src_pad;
    private Gst.Pad send_rtp_sink_pad;
    private Gst.Pad send_rtp_src_pad;

    private Crypto.Srtp.Session? crypto_session = new Crypto.Srtp.Session();

    // DTMF support (RFC 4733 via on_new_sample injection)
    private bool dtmf_active = false;          // Currently sending DTMF
    private int dtmf_event_code = -1;          // Current event code (0-15)
    private uint8 dtmf_payload_type = 0;       // Negotiated PT for telephone-event
    private uint32 dtmf_clockrate = 8000;
    private uint32 dtmf_start_timestamp = 0;   // RTP timestamp at DTMF start
    private bool dtmf_marker_sent = false;     // Marker bit sent on first packet
    private int dtmf_end_counter = 0;          // End packet redundancy counter
    private uint32 dtmf_duration_samples = 0;   // Duration threshold in audio clockrate units
    private Gee.LinkedList<int> dtmf_pending = new Gee.LinkedList<int>();  // Thread-safe via dtmf_mutex
    private GLib.Mutex dtmf_mutex = GLib.Mutex();

    // Signal handler IDs for proper cleanup
    private ulong senders_changed_handler_id;
    private ulong feedback_rtcp_handler_id;
    private ulong send_rtp_eos_handler_id;
    private ulong send_rtcp_eos_handler_id;
    private ulong send_rtp_new_sample_handler_id;
    private ulong send_rtcp_new_sample_handler_id;
#if GST_1_20
    private ulong send_rtp_event_handler_id;
#endif
    private Object? internal_session;

    public Stream(Plugin plugin, Xmpp.Xep.Jingle.Content content) {
        base(content);
        this.plugin = plugin;
        this.rtpid = plugin.next_free_id();

        senders_changed_handler_id = content.notify["senders"].connect_after(on_senders_changed);
    }

    public void on_senders_changed() {
        if (sending && input == null) {
            input_device = input_device;
        }
        if (receiving && output == null) {
            output_device = output_device;
        }
    }

    /**
     * Send a DTMF tone via RFC 4733 telephone-event.
     * DTMF packets are injected directly in on_new_sample by replacing audio
     * buffers with RFC 4733 event packets. This keeps the same seqnum stream
     * and avoids any pipeline modifications or SRTP conflicts.
     * @param digit The DTMF digit: 0-9, *, #, A-D (mapped to event codes 0-15)
     * @param duration_ms Duration of the tone in milliseconds (default 250)
     */
    public void send_dtmf(char digit, uint duration_ms = 250) {
        if (media != "audio" || !sending || !created) {
            warning("Cannot send DTMF: stream not ready (media=%s, sending=%s, created=%s)", media, sending.to_string(), created.to_string());
            return;
        }

        int event_code = dtmf_digit_to_event(digit);
        if (event_code < 0) {
            warning("Invalid DTMF digit: %c", digit);
            return;
        }

        // Resolve PT on first use (main thread only, before streaming starts)
        if (dtmf_payload_type == 0) {
            resolve_dtmf_payload_type();
        }
        if (dtmf_payload_type == 0) {
            debug("telephone-event not negotiated, DTMF not available");
            return;
        }

        // Push digit+duration into thread-safe queue — streaming thread picks it up
        // Encode: event_code in low 8 bits, duration_ms in high 24 bits
        int encoded = (int)((duration_ms << 8) | (event_code & 0xFF));
        dtmf_mutex.@lock();
        dtmf_pending.offer(encoded);
        dtmf_mutex.unlock();
        debug("DTMF digit '%c' (event %d) queued for streaming thread", digit, event_code);
    }

    private void start_dtmf_digit_internal(int event_code, uint duration_ms) {
        debug("Streaming thread: starting DTMF event %d (duration %u ms)", event_code, duration_ms);

        // Start DTMF injection — all state mutations on streaming thread only
        dtmf_event_code = event_code;
        dtmf_marker_sent = false;
        dtmf_start_timestamp = 0;  // Will be set from first intercepted audio packet
        dtmf_end_counter = 0;
        // Calculate duration threshold in audio clockrate units (no main-loop timer)
        dtmf_duration_samples = (uint32)(duration_ms * payload_type.clockrate / 1000);
        dtmf_active = true;
    }

    /**
     * Build an RFC 4733 telephone-event RTP packet by replacing the audio
     * payload in an existing RTP buffer. Preserves SSRC and seqnum from the
     * original audio packet for seamless SRTP continuity.
     *
     * RFC 4733 payload format (4 bytes):
     *   0                   1                   2                   3
     *   0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
     *  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
     *  |     event     |E R| volume    |          duration             |
     *  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
     */
    private uint8[]? build_dtmf_rtp_packet(uint8[] audio_rtp_data) {
        if (audio_rtp_data.length < 12) return null;  // Minimum RTP header size

        // Parse the RTP header from the audio packet
        uint8 version_flags = audio_rtp_data[0];
        // uint8 pt_marker = audio_rtp_data[1];
        uint16 seqnum = (uint16)((audio_rtp_data[2] << 8) | audio_rtp_data[3]);
        uint32 timestamp = (uint32)((audio_rtp_data[4] << 24) | (audio_rtp_data[5] << 16) |
                                     (audio_rtp_data[6] << 8) | audio_rtp_data[7]);
        // SSRC is bytes 8-11

        // Set start timestamp from first audio packet
        if (dtmf_start_timestamp == 0) {
            dtmf_start_timestamp = timestamp;
        }

        // Calculate duration in RTP timestamp units
        uint32 duration_ts = timestamp - dtmf_start_timestamp;
        if (duration_ts > 65535) duration_ts = 65535;  // Max 16-bit duration

        // Auto-trigger end when duration reached (driven by RTP timestamps, not main loop)
        if (dtmf_end_counter == 0 && dtmf_duration_samples > 0 && duration_ts >= dtmf_duration_samples) {
            dtmf_end_counter = 3;
            debug("DTMF ending (duration %u >= %u samples), sending %d end packets", (uint)duration_ts, (uint)dtmf_duration_samples, dtmf_end_counter);
        }

        bool is_end = (dtmf_end_counter > 0);
        bool is_marker = !dtmf_marker_sent;

        // Build new RTP packet: 12-byte header + 4-byte RFC 4733 payload
        uint8[] packet = new uint8[16];

        // RTP header
        packet[0] = version_flags & 0xF0;  // V=2, P=0, X=0, CC=0
        packet[0] = (packet[0] & 0xC0) | 0x00;  // Clear extension/CSRC bits
        packet[0] = 0x80;  // V=2, no padding, no extension, CC=0
        packet[1] = dtmf_payload_type;
        if (is_marker) packet[1] |= 0x80;  // Marker bit on first DTMF packet

        // Seqnum from original audio packet
        packet[2] = (uint8)(seqnum >> 8);
        packet[3] = (uint8)(seqnum & 0xFF);

        // Timestamp: use the START timestamp (constant during entire DTMF event)
        packet[4] = (uint8)(dtmf_start_timestamp >> 24);
        packet[5] = (uint8)((dtmf_start_timestamp >> 16) & 0xFF);
        packet[6] = (uint8)((dtmf_start_timestamp >> 8) & 0xFF);
        packet[7] = (uint8)(dtmf_start_timestamp & 0xFF);

        // SSRC: copy from original audio packet
        packet[8] = audio_rtp_data[8];
        packet[9] = audio_rtp_data[9];
        packet[10] = audio_rtp_data[10];
        packet[11] = audio_rtp_data[11];

        // RFC 4733 payload (4 bytes)
        packet[12] = (uint8)dtmf_event_code;        // Event code
        packet[13] = is_end ? (uint8)0x80 : (uint8)0x00;  // E bit + R=0
        packet[13] |= 10;                            // Volume = 10 dBm0
        packet[14] = (uint8)((duration_ts >> 8) & 0xFF);   // Duration high byte
        packet[15] = (uint8)(duration_ts & 0xFF);          // Duration low byte

        if (is_marker) {
            dtmf_marker_sent = true;
        }

        if (is_end) {
            dtmf_end_counter--;
            if (dtmf_end_counter <= 0) {
                dtmf_active = false;
                dtmf_event_code = -1;
                debug("DTMF completed (all end packets sent, last seq=%u)", seqnum);

                // Check for next queued digit (mutex-protected)
                dtmf_mutex.@lock();
                if (!dtmf_pending.is_empty) {
                    int next_encoded = dtmf_pending.poll();
                    dtmf_mutex.unlock();
                    int next_code = next_encoded & 0xFF;
                    uint next_dur = (uint)(next_encoded >> 8);
                    if (next_dur == 0) next_dur = 250;
                    start_dtmf_digit_internal(next_code, next_dur);
                } else {
                    dtmf_mutex.unlock();
                }
            }
        }

        return packet;
    }

    /**
     * Resolve the negotiated telephone-event payload type from the session parameters.
     */
    private void resolve_dtmf_payload_type() {
        var content_params = content.content_params as Xmpp.Xep.JingleRtp.Parameters;
        if (content_params == null) return;

        foreach (var pt in content_params.payload_types) {
            if (pt.name != null && pt.name.down() == "telephone-event") {
                dtmf_payload_type = (uint8)pt.id;
                dtmf_clockrate = pt.clockrate > 0 ? pt.clockrate : 8000;
                debug("Resolved DTMF payload type: PT %u, clockrate %u", dtmf_payload_type, dtmf_clockrate);
                return;
            }
        }
    }

    private static int dtmf_digit_to_event(char digit) {
        if (digit >= '0' && digit <= '9') return digit - '0';
        if (digit == '*') return 10;
        if (digit == '#') return 11;
        if (digit >= 'A' && digit <= 'D') return 12 + (digit - 'A');
        if (digit >= 'a' && digit <= 'd') return 12 + (digit - 'a');
        return -1;
    }

    public override void create() {
        plugin.pause();

        // Create i/o if needed

        if (input == null && sending) {
            input_device = input_device;
        }
        if (output == null && receiving && media == "audio") {
            output_device = output_device;
        }

        // Create app elements
        send_rtp = Gst.ElementFactory.make("appsink", @"rtp_sink_$rtpid") as Gst.App.Sink;
        send_rtp.async = false;
        send_rtp.caps = CodecUtil.get_caps(media, payload_type, false);
        send_rtp.emit_signals = true;
        send_rtp.sync = false;
        send_rtp.drop = false;
        send_rtp.@set("max-buffers", 1);
        send_rtp.wait_on_eos = false;
        send_rtp_new_sample_handler_id = send_rtp.new_sample.connect(on_new_sample);
#if GST_1_20
        send_rtp_event_handler_id = send_rtp.new_serialized_event.connect(on_new_event);
#endif
        send_rtp_eos_handler_id = GLib.Signal.connect(send_rtp, "eos", (GLib.Callback)on_eos_static, this);
        pipe.add(send_rtp);
        send_rtp.sync_state_with_parent();

        send_rtcp = Gst.ElementFactory.make("appsink", @"rtcp_sink_$rtpid") as Gst.App.Sink;
        send_rtcp.async = false;
        send_rtcp.caps = new Gst.Caps.empty_simple("application/x-rtcp");
        send_rtcp.emit_signals = true;
        send_rtcp.sync = false;
        send_rtcp.drop = false;
        send_rtcp.wait_on_eos = false;
        send_rtcp_new_sample_handler_id = send_rtcp.new_sample.connect(on_new_sample);
        send_rtcp_eos_handler_id = GLib.Signal.connect(send_rtcp, "eos", (GLib.Callback)on_eos_static, this);
        pipe.add(send_rtcp);
        send_rtcp.sync_state_with_parent();

        recv_rtp = Gst.ElementFactory.make("appsrc", @"rtp_src_$rtpid") as Gst.App.Src;
        recv_rtp.caps = CodecUtil.get_caps(media, payload_type, true);
        recv_rtp.do_timestamp = true;
        recv_rtp.format = Gst.Format.TIME;
        recv_rtp.is_live = true;
        recv_rtp.stream_type = Gst.App.StreamType.STREAM;
        pipe.add(recv_rtp);
        recv_rtp.sync_state_with_parent();

        recv_rtcp = Gst.ElementFactory.make("appsrc", @"rtcp_src_$rtpid") as Gst.App.Src;
        recv_rtcp.do_timestamp = true;
        recv_rtcp.format = Gst.Format.TIME;
        recv_rtcp.is_live = true;
        recv_rtcp.stream_type = Gst.App.StreamType.STREAM;
        pipe.add(recv_rtcp);
        recv_rtcp.sync_state_with_parent();

        // Connect RTCP
        // Connect RTCP
        send_rtcp_src_pad = rtpbin.request_pad_simple(@"send_rtcp_src_$rtpid");
        send_rtcp_src_pad.link(send_rtcp.get_static_pad("sink"));
        recv_rtcp_sink_pad = rtpbin.request_pad_simple(@"recv_rtcp_sink_$rtpid");
        recv_rtcp.get_static_pad("src").link(recv_rtcp_sink_pad);

        // Connect input
        send_rtp_sink_pad = rtpbin.request_pad_simple(@"send_rtp_sink_$rtpid");
        if (input != null) {
            input_pad = input.request_pad_simple(@"src_$rtpid");
            input_pad.link(send_rtp_sink_pad);
        }

        decode = codec_util.get_decode_bin(media, payload_type, @"decode_$rtpid");
        decode_depay = (Gst.RTP.BaseDepayload)((Gst.Bin)decode).get_by_name(@"decode_$(rtpid)_rtp_depay");
        pipe.add(decode);
        decode.sync_state_with_parent();
        if (output != null) {
            decode.link(output);
        }

        // Connect RTP
        recv_rtp_sink_pad = rtpbin.request_pad_simple(@"recv_rtp_sink_$rtpid");
        recv_rtp.get_static_pad("src").link(recv_rtp_sink_pad);

        created = true;
        push_recv_data = true;
        plugin.unpause();

        GLib.Signal.emit_by_name(rtpbin, "get-session", rtpid, out session);
        if (session != null && remb_enabled) {
            session.@get("internal-session", out internal_session);
            if (internal_session != null) {
                feedback_rtcp_handler_id = GLib.Signal.connect(internal_session, "on-feedback-rtcp", (GLib.Callback)on_feedback_rtcp, this);
            }
            Timeout.add(1000, () => remb_adjust());
        }
        if (input_device != null && media == "video") {
            input_device.update_bitrate(payload_type, target_send_bitrate);
        }
    }

    private int last_packets_lost = -1;
    private uint64 last_packets_received = 0;
    private uint64 last_octets_received = 0;
    private uint max_target_receive_bitrate = 0;
    private int64 last_remb_time = 0;
    private bool remb_adjust() {
        unowned Gst.Structure? stats;
        if (session == null) {
            debug("Session for %u finished, turning off remb adjustment", rtpid);
            return Source.REMOVE;
        }
        session.get("stats", out stats);
        if (stats == null) {
            warning("No stats for session %u", rtpid);
            return Source.REMOVE;
        }
        if (!stats.has_field("source-stats")) {
            warning("No source-stats for session %u", rtpid);
            return Source.REMOVE;
        }
        GLib.List<unowned Gst.Structure> source_stats = rtp_get_source_stats_structures(stats);

        if (input_device == null) return Source.CONTINUE;

        foreach (unowned Gst.Structure source_stat in source_stats) {
            uint32 ssrc;
            if (!source_stat.get_uint("ssrc", out ssrc)) continue;
            if (ssrc == participant_ssrc) {
                int packets_lost;
                uint64 packets_received, octets_received;
                source_stat.get_int("packets-lost", out packets_lost);
                source_stat.get_uint64("packets-received", out packets_received);
                source_stat.get_uint64("octets-received", out octets_received);
                int new_lost = packets_lost - last_packets_lost;
                if (new_lost < 0) new_lost = 0;
                uint64 new_received = packets_received - last_packets_received;
                if (packets_received < last_packets_received) new_received = 0;
                uint64 new_octets = octets_received - last_octets_received;
                if (octets_received < last_octets_received) octets_received = 0;
                if (new_received == 0) continue;
                last_packets_lost = packets_lost;
                last_packets_received = packets_received;
                last_octets_received = octets_received;
                double loss_rate = (double)new_lost / (double)(new_lost + new_received);
                uint new_target_receive_bitrate;
                if (new_lost <= 0 || loss_rate < 0.02) {
                    new_target_receive_bitrate = (uint)(1.08 * (double)target_receive_bitrate);
                } else if (loss_rate > 0.1) {
                    new_target_receive_bitrate = (uint)((1.0 - 0.5 * loss_rate) * (double)target_receive_bitrate);
                } else {
                    new_target_receive_bitrate = target_receive_bitrate;
                }
                if (last_remb_time == 0) {
                    last_remb_time = get_monotonic_time();
                } else {
                    int64 time_now = get_monotonic_time();
                    int64 time_diff = time_now - last_remb_time;
                    last_remb_time = time_now;
                    uint actual_bitrate = (uint)(((double)new_octets * 8.0) * (double)time_diff / 1000.0 / 1000000.0);
                    new_target_receive_bitrate = uint.max(new_target_receive_bitrate, (uint)(0.9 * (double)actual_bitrate));
                    max_target_receive_bitrate = uint.max((uint)(1.5 * (double)actual_bitrate), max_target_receive_bitrate);
                    new_target_receive_bitrate = uint.min(new_target_receive_bitrate, max_target_receive_bitrate);
                }
                new_target_receive_bitrate = uint.max(16, new_target_receive_bitrate); // Never go below 16
                if (new_target_receive_bitrate != target_receive_bitrate) {
                    target_receive_bitrate = new_target_receive_bitrate;
                    uint8[] data = new uint8[] {
                        143, 206, 0, 5,
                        0, 0, 0, 0,
                        0, 0, 0, 0,
                        'R', 'E', 'M', 'B',
                        1, 0, 0, 0,
                        0, 0, 0, 0
                    };
                    data[4] = (uint8)((our_ssrc >> 24) & 0xff);
                    data[5] = (uint8)((our_ssrc >> 16) & 0xff);
                    data[6] = (uint8)((our_ssrc >> 8) & 0xff);
                    data[7] = (uint8)(our_ssrc & 0xff);
                    uint8 br_exp = 0;
                    uint32 br_mant = target_receive_bitrate * 1000;
                    uint8 bits = (uint8)Math.log2(br_mant);
                    if (bits > 16) {
                        br_exp = (uint8)bits - 16;
                        br_mant = br_mant >> br_exp;
                    }
                    data[17] = (uint8)((br_exp << 2) | ((br_mant >> 16) & 0x3));
                    data[18] = (uint8)((br_mant >> 8) & 0xff);
                    data[19] = (uint8)(br_mant & 0xff);
                    data[20] = (uint8)((ssrc >> 24) & 0xff);
                    data[21] = (uint8)((ssrc >> 16) & 0xff);
                    data[22] = (uint8)((ssrc >> 8) & 0xff);
                    data[23] = (uint8)(ssrc & 0xff);
                    encrypt_and_send_rtcp(data);
                }
            }
        }
        return Source.CONTINUE;
    }

    private static void on_feedback_rtcp(Gst.Element session, uint type, uint fbtype, uint sender_ssrc, uint media_ssrc, Gst.Buffer? fci, Stream self) {
        if (self.input_device != null && self.media == "video" && type == 206 && fbtype == 15 && fci != null && sender_ssrc == self.participant_ssrc) {
            // https://tools.ietf.org/html/draft-alvestrand-rmcat-remb-03
            uint8[] data;
            fci.extract_dup(0, fci.get_size(), out data);
            if (data[0] != 'R' || data[1] != 'E' || data[2] != 'M' || data[3] != 'B') return;
            uint8 br_exp = data[5] >> 2;
            uint32 br_mant = (((uint32)data[5] & 0x3) << 16) + ((uint32)data[6] << 8) + (uint32)data[7];
            self.target_send_bitrate = (br_mant << br_exp) / 1000;
            self.input_device.update_bitrate(self.payload_type, self.target_send_bitrate);
        }
    }

    private void prepare_local_crypto() {
        if (local_crypto != null && local_crypto.is_valid && !crypto_session.has_encrypt) {
            crypto_session.set_encryption_key(local_crypto.crypto_suite, local_crypto.key, local_crypto.salt);
            debug("Setting up encryption (sdes_key_params_present=%s)", (local_crypto.key_params != null && local_crypto.key_params.length > 0).to_string());
        }
    }

    bool flip = false;
    uint8 rotation = 0;
#if GST_1_20
    private bool on_new_event(Gst.App.Sink sink) {
        if (sink == null || sink != send_rtp) {
            return false;
        }
        Gst.MiniObject obj = sink.try_pull_object(0);
        if (obj.type == typeof(Gst.Event)) {
            unowned Gst.TagList tags;
            if (((Gst.Event)obj).type == Gst.EventType.TAG) {
                ((Gst.Event)obj).parse_tag(out tags);
                Gst.Video.OrientationMethod orientation_method;
                Gst.Video.Orientation.from_tag(tags, out orientation_method);
                switch (orientation_method) {
                    case Gst.Video.OrientationMethod.IDENTITY:
                    case Gst.Video.OrientationMethod.VERT:
                    default:
                        rotation = 0;
                        break;
                    case Gst.Video.OrientationMethod.@90R:
                    case Gst.Video.OrientationMethod.UL_LR:
                        rotation = 1;
                        break;
                    case Gst.Video.OrientationMethod.@180:
                    case Gst.Video.OrientationMethod.HORIZ:
                        rotation = 2;
                        break;
                    case Gst.Video.OrientationMethod.@90L:
                    case Gst.Video.OrientationMethod.UR_LL:
                        rotation = 3;
                        break;
                }
                switch (orientation_method) {
                    case Gst.Video.OrientationMethod.IDENTITY:
                    case Gst.Video.OrientationMethod.@90R:
                    case Gst.Video.OrientationMethod.@180:
                    case Gst.Video.OrientationMethod.@90L:
                    default:
                        flip = false;
                        break;
                    case Gst.Video.OrientationMethod.VERT:
                    case Gst.Video.OrientationMethod.UL_LR:
                    case Gst.Video.OrientationMethod.HORIZ:
                    case Gst.Video.OrientationMethod.UR_LL:
                        flip = true;
                        break;
                }
            }
        }
        return false;
    }
#endif

    private Gst.FlowReturn on_new_sample(Gst.App.Sink sink) {
        if (sink == null) {
            debug("Sink is null");
            return Gst.FlowReturn.EOS;
        }
        if (sink != send_rtp && sink != send_rtcp) {
            warning("unknown sample");
            return Gst.FlowReturn.NOT_SUPPORTED;
        }
        Gst.Sample sample = sink.pull_sample();
        Gst.Buffer buffer = sample.get_buffer();
        if (sink == send_rtp) {
            uint buffer_ssrc = 0, buffer_seq = 0;
            Gst.RTP.Buffer rtp_buffer;
            if (Gst.RTP.Buffer.map(buffer, Gst.MapFlags.READ, out rtp_buffer)) {
                buffer_ssrc = rtp_buffer.get_ssrc();
                buffer_seq = rtp_buffer.get_seq();
                next_seqnum_offset = rtp_buffer.get_seq() + 1;
                next_timestamp_offset_base = rtp_buffer.get_timestamp();
                next_timestamp_offset_stamp = get_monotonic_time();
                rtp_buffer.unmap();
            }
#if GLIB_2_64
            if (our_ssrc != buffer_ssrc) {
                warning_once("Sending RTP %s buffer seq %u with SSRC %u when our ssrc is %u", media, buffer_seq, buffer_ssrc, our_ssrc);
            }
#endif
            // DTMF: check pending queue from main thread (mutex-protected)
            if (!dtmf_active) {
                dtmf_mutex.@lock();
                if (!dtmf_pending.is_empty) {
                    int encoded = dtmf_pending.poll();
                    dtmf_mutex.unlock();
                    int evt = encoded & 0xFF;
                    uint dur = (uint)(encoded >> 8);
                    if (dur == 0) dur = 250;
                    start_dtmf_digit_internal(evt, dur);
                } else {
                    dtmf_mutex.unlock();
                }
            }
            // DTMF injection: replace audio buffer with RFC 4733 packet
            if (dtmf_active && dtmf_event_code >= 0) {
                uint8[] audio_data;
                buffer.extract_dup(0, buffer.get_size(), out audio_data);
                uint8[]? dtmf_packet = build_dtmf_rtp_packet(audio_data);
                if (dtmf_packet != null) {
                    prepare_local_crypto();
                    encrypt_and_send_rtp((owned) dtmf_packet);
                    return Gst.FlowReturn.OK;
                }
            }
        }

#if GST_1_20
        if (sink == send_rtp) {
            Xmpp.Xep.JingleRtp.HeaderExtension? ext = header_extensions.first_match((it) => it.uri == "urn:3gpp:video-orientation");
            if (ext != null) {
                buffer = (Gst.Buffer) buffer.make_writable();
                Gst.RTP.Buffer rtp_buffer;
                if (Gst.RTP.Buffer.map(buffer, Gst.MapFlags.WRITE, out rtp_buffer)) {
                    uint8[] extension_data = new uint8[1];
                    bool camera = false;
                    extension_data[0] = extension_data[0] | (rotation & 0x3);
                    if (flip) extension_data[0] = extension_data[0] | 0x4;
                    if (camera) extension_data[0] = extension_data[0] | 0x8;
                    rtp_buffer.add_extension_onebyte_header(ext.id, extension_data);
                }
            }
        }
#endif

        prepare_local_crypto();

        uint8[] data;
        buffer.extract_dup(0, buffer.get_size(), out data);
        if (sink == send_rtp) {
            encrypt_and_send_rtp((owned) data);
        } else if (sink == send_rtcp) {
            encrypt_and_send_rtcp((owned) data);
        }
        return Gst.FlowReturn.OK;
    }

    private void encrypt_and_send_rtp(owned uint8[] data) {
        Bytes bytes;
        if (crypto_session.has_encrypt) {
            try {
                bytes = new Bytes.take(crypto_session.encrypt_rtp(data));
            } catch (Crypto.Error e) {
                warning("Failed to encrypt RTP: %s", e.message);
                return;
            }
        } else {
            bytes = new Bytes.take(data);
        }
        on_send_rtp_data(bytes);
    }

    private void encrypt_and_send_rtcp(owned uint8[] data) {
        Bytes bytes;
        if (crypto_session.has_encrypt) {
            try {
                bytes = new Bytes.take(crypto_session.encrypt_rtcp(data));
            } catch (Crypto.Error e) {
                warning("Failed to encrypt RTCP: %s", e.message);
                return;
            }
        } else {
            bytes = new Bytes.take(data);
        }
        if (rtcp_mux) {
            on_send_rtp_data(bytes);
        } else {
            on_send_rtcp_data(bytes);
        }
    }

    private static Gst.PadProbeReturn drop_probe() {
        return Gst.PadProbeReturn.DROP;
    }

    private static void on_eos_static(Gst.App.Sink sink, Stream self) {
        debug("EOS on %s", sink.name);
        if (sink == self.send_rtp) {
            Idle.add(() => { self.on_send_rtp_eos(); return Source.REMOVE; });
        } else if (sink == self.send_rtcp) {
            Idle.add(() => { self.on_send_rtcp_eos(); return Source.REMOVE; });
        }
    }

    private void on_send_rtp_eos() {
        if (send_rtp_src_pad != null) {
            send_rtp_src_pad.unlink(send_rtp.get_static_pad("sink"));
            send_rtp_src_pad = null;
        }
        send_rtp.set_locked_state(true);
        send_rtp.set_state(Gst.State.NULL);
        // This happens async, so pipe might be gone by now.
        if (pipe != null) pipe.remove(send_rtp);
        send_rtp = null;
        debug("Stopped sending RTP for %u", rtpid);
    }

    private void on_send_rtcp_eos() {
        send_rtcp.set_locked_state(true);
        send_rtcp.set_state(Gst.State.NULL);
        // This happens async, so pipe might be gone by now.
        if (pipe != null) pipe.remove(send_rtcp);
        send_rtcp = null;
        debug("Stopped sending RTCP for %u", rtpid);
    }

    public override void destroy() {
        // Disconnect signal handlers first
        if (senders_changed_handler_id != 0 && content != null) {
            content.disconnect(senders_changed_handler_id);
            senders_changed_handler_id = 0;
        }
        if (feedback_rtcp_handler_id != 0 && internal_session != null) {
            SignalHandler.disconnect(internal_session, feedback_rtcp_handler_id);
            feedback_rtcp_handler_id = 0;
        }
        internal_session = null;
        session = null;
        crypto_session = null;
        
        // Stop network communication
        push_recv_data = false;
        created = false;
        if (recv_rtp != null) recv_rtp.end_of_stream();
        if (recv_rtcp != null) recv_rtcp.end_of_stream();
        
        // Disconnect all appsink signals before destroying elements
        if (send_rtp != null) {
            if (send_rtp_new_sample_handler_id != 0 && SignalHandler.is_connected(send_rtp, send_rtp_new_sample_handler_id)) {
                SignalHandler.disconnect(send_rtp, send_rtp_new_sample_handler_id);
                send_rtp_new_sample_handler_id = 0;
            }
            if (send_rtp_eos_handler_id != 0 && SignalHandler.is_connected(send_rtp, send_rtp_eos_handler_id)) {
                SignalHandler.disconnect(send_rtp, send_rtp_eos_handler_id);
                send_rtp_eos_handler_id = 0;
            }
#if GST_1_20
            if (send_rtp_event_handler_id != 0 && SignalHandler.is_connected(send_rtp, send_rtp_event_handler_id)) {
                SignalHandler.disconnect(send_rtp, send_rtp_event_handler_id);
                send_rtp_event_handler_id = 0;
            }
#endif
        }
        if (send_rtcp != null) {
            if (send_rtcp_new_sample_handler_id != 0 && SignalHandler.is_connected(send_rtcp, send_rtcp_new_sample_handler_id)) {
                SignalHandler.disconnect(send_rtcp, send_rtcp_new_sample_handler_id);
                send_rtcp_new_sample_handler_id = 0;
            }
            if (send_rtcp_eos_handler_id != 0 && SignalHandler.is_connected(send_rtcp, send_rtcp_eos_handler_id)) {
                SignalHandler.disconnect(send_rtcp, send_rtcp_eos_handler_id);
                send_rtcp_eos_handler_id = 0;
            }
        }

        // Clean up DTMF state
        dtmf_active = false;
        dtmf_event_code = -1;
        dtmf_payload_type = 0;
        // Drain pending DTMF queue
        dtmf_mutex.@lock();
        dtmf_pending.clear();
        dtmf_mutex.unlock();

        // Disconnect input device
        if (input != null) {
            if (input_queue != null) {
                input_pad.unlink(input_queue.get_static_pad("sink"));
                input_queue.set_state(Gst.State.NULL);
                pipe.remove(input_queue);
                input_queue = null;
            } else {
                input_pad.unlink(send_rtp_sink_pad);
            }
            input.release_request_pad(input_pad);
            input_pad = null;
        }
        if (this._input_device != null) {
            if (!paused) this._input_device.unlink(input);
            this._input_device = null;
            this.input = null;
        }

        // Inject EOS (handlers already disconnected, so clean up inline)
        if (send_rtp_sink_pad != null) {
            send_rtp_sink_pad.send_event(new Gst.Event.eos());
        }

        // Clean up send_rtp appsink (EOS handler won't fire since we disconnected it)
        if (send_rtp_src_pad != null) {
            send_rtp_src_pad.unlink(send_rtp.get_static_pad("sink"));
            send_rtp_src_pad = null;
        }
        if (send_rtp != null) {
            send_rtp.set_locked_state(true);
            send_rtp.set_state(Gst.State.NULL);
            if (pipe != null) pipe.remove(send_rtp);
            send_rtp = null;
        }
        if (send_rtcp != null) {
            send_rtcp.set_locked_state(true);
            send_rtcp.set_state(Gst.State.NULL);
            if (pipe != null) pipe.remove(send_rtcp);
            send_rtcp = null;
        }

        // Disconnect decode
        if (recv_rtp_src_pad != null) {
            recv_rtp_src_pad.add_probe(Gst.PadProbeType.BLOCK, drop_probe);
            recv_rtp_src_pad.unlink(decode.get_static_pad("sink"));
        }

        // Disconnect output
        if (output != null) {
            decode.get_static_pad("src").add_probe(Gst.PadProbeType.BLOCK, drop_probe);
            if (output_queue != null) {
                decode.unlink(output_queue);
                output_queue.unlink(output);
                output_queue.set_state(Gst.State.NULL);
                pipe.remove(output_queue);
                output_queue = null;
            } else {
                decode.unlink(output);
            }
        }

        // Disconnect output device
        if (this._output_device != null) {
            this._output_device.unlink(output);
            this._output_device = null;
        }
        output = null;

        // Destroy decode
        if (decode != null) {
            decode.set_locked_state(true);
            decode.set_state(Gst.State.NULL);
            pipe.remove(decode);
            decode = null;
            decode_depay = null;
        }

        // Disconnect and remove RTP input
        if (recv_rtp != null) {
            recv_rtp.get_static_pad("src").unlink(recv_rtp_sink_pad);
            recv_rtp.set_locked_state(true);
            recv_rtp.set_state(Gst.State.NULL);
            pipe.remove(recv_rtp);
            recv_rtp = null;
        }

        // Disconnect and remove RTCP input
        if (recv_rtcp != null) {
            recv_rtcp.get_static_pad("src").unlink(recv_rtcp_sink_pad);
            recv_rtcp.set_locked_state(true);
            recv_rtcp.set_state(Gst.State.NULL);
            pipe.remove(recv_rtcp);
            recv_rtcp = null;
        }

        // Release rtp pads
        if (send_rtp_sink_pad != null) {
            rtpbin.release_request_pad(send_rtp_sink_pad);
            send_rtp_sink_pad = null;
        }
        if (recv_rtp_sink_pad != null) {
            rtpbin.release_request_pad(recv_rtp_sink_pad);
            recv_rtp_sink_pad = null;
        }
        if (send_rtcp_src_pad != null) {
            rtpbin.release_request_pad(send_rtcp_src_pad);
            send_rtcp_src_pad = null;
        }
        if (recv_rtcp_sink_pad != null) {
            rtpbin.release_request_pad(recv_rtcp_sink_pad);
            recv_rtcp_sink_pad = null;
        }
    }

    private void prepare_remote_crypto() {
        if (remote_crypto != null && remote_crypto.is_valid && !crypto_session.has_decrypt) {
            crypto_session.set_decryption_key(remote_crypto.crypto_suite, remote_crypto.key, remote_crypto.salt);
            debug("Setting up decryption (sdes_key_params_present=%s)", (remote_crypto.key_params != null && remote_crypto.key_params.length > 0).to_string());
        }
    }

    private uint16 previous_incoming_video_orientation_degree = uint16.MAX;
    public signal void incoming_video_orientation_changed(uint16 degree);

    public override void on_recv_rtp_data(Bytes bytes) {
        if (rtcp_mux && bytes.length >= 2 && bytes.get(1) >= 192 && bytes.get(1) < 224) {
            on_recv_rtcp_data(bytes);
            return;
        }
#if GST_1_16
        {
            Gst.Buffer buffer = new Gst.Buffer.wrapped_bytes(bytes);
            Gst.RTP.Buffer rtp_buffer;
            uint buffer_ssrc = 0, buffer_seq = 0;
            if (Gst.RTP.Buffer.map(buffer, Gst.MapFlags.READ, out rtp_buffer)) {
                buffer_ssrc = rtp_buffer.get_ssrc();
                buffer_seq = rtp_buffer.get_seq();
                rtp_buffer.unmap();
            }
        }
#endif
        if (push_recv_data) {
            prepare_remote_crypto();

            Gst.Buffer buffer;
            if (crypto_session.has_decrypt) {
                try {
                    buffer = new Gst.Buffer.wrapped(crypto_session.decrypt_rtp(bytes.get_data()));
                } catch (Error e) {
                    warning("%s (%d)", e.message, e.code);
                    return;
                }
            } else {
#if GST_1_16
                buffer = new Gst.Buffer.wrapped_bytes(bytes);
#else
                buffer = new Gst.Buffer.wrapped(bytes.get_data());
#endif
            }

            Gst.RTP.Buffer rtp_buffer;
            if (Gst.RTP.Buffer.map(buffer, Gst.MapFlags.READ, out rtp_buffer)) {
                if (rtp_buffer.get_extension()) {
                    Xmpp.Xep.JingleRtp.HeaderExtension? ext = header_extensions.first_match((it) => it.uri == "urn:3gpp:video-orientation");
                    if (ext != null) {
                        unowned uint8[] extension_data;
                        if (rtp_buffer.get_extension_onebyte_header(ext.id, 0, out extension_data) && extension_data.length == 1) {
                            uint8 rotation = extension_data[0] & 0x3;
                            uint16 rotation_degree = uint16.MAX;
                            switch(rotation) {
                                case 0: rotation_degree = 0; break;
                                case 1: rotation_degree = 90; break;
                                case 2: rotation_degree = 180; break;
                                case 3: rotation_degree = 270; break;
                            }
                            if (rotation_degree != previous_incoming_video_orientation_degree) {
                                incoming_video_orientation_changed(rotation_degree);
                                previous_incoming_video_orientation_degree = rotation_degree;
                            }
                        }
                    }
                }
                rtp_buffer.unmap();
            }

#if VALA_0_50
            recv_rtp.push_buffer((owned) buffer);
#else
            Gst.FlowReturn ret;
            GLib.Signal.emit_by_name(recv_rtp, "push-buffer", buffer, out ret);
#endif
        }
    }

    public override void on_recv_rtcp_data(Bytes bytes) {
        if (push_recv_data) {
            prepare_remote_crypto();

            Gst.Buffer buffer;
            if (crypto_session.has_decrypt) {
                try {
                    buffer = new Gst.Buffer.wrapped(crypto_session.decrypt_rtcp(bytes.get_data()));
                } catch (Error e) {
                    warning("%s (%d)", e.message, e.code);
                    return;
                }
            } else {
#if GST_1_16
                buffer = new Gst.Buffer.wrapped_bytes(bytes);
#else
                buffer = new Gst.Buffer.wrapped(bytes.get_data());
#endif
            }

#if VALA_0_50
            recv_rtcp.push_buffer((owned) buffer);
#else
            Gst.FlowReturn ret;
            GLib.Signal.emit_by_name(recv_rtcp, "push-buffer", buffer, out ret);
#endif
        }
    }

    public override void on_rtp_ready() {
        // If full frame has been sent before the connection was ready, the counterpart would only display our video after the next full frame.
        // Send a full frame to let the counterpart display our video asap
        rtpbin.send_event(new Gst.Event.custom(
                Gst.EventType.CUSTOM_UPSTREAM,
                new Gst.Structure("GstForceKeyUnit", "all-headers", typeof(bool), true, null))
        );
    }

    public override void on_rtcp_ready() {
        int rtp_session_id = (int) rtpid;
        uint64 max_delay = int.MAX;
        Object rtp_session;
        bool rtp_sent;
        GLib.Signal.emit_by_name(rtpbin, "get-internal-session", rtp_session_id, out rtp_session);
        GLib.Signal.emit_by_name(rtp_session, "send-rtcp-full", max_delay, out rtp_sent);
        debug("RTCP is ready, resending rtcp: %s", rtp_sent.to_string());
    }

    public void on_ssrc_pad_added(uint32 ssrc, Gst.Pad pad) {
        debug("New ssrc %u with pad %s", ssrc, pad.name);
        if (participant_ssrc != 0 && participant_ssrc != ssrc) {
            warning("Got second ssrc on stream (old: %u, new: %u), ignoring", participant_ssrc, ssrc);
            return;
        }
        participant_ssrc = ssrc;
        recv_rtp_src_pad = pad;
        if (decode != null) {
            plugin.pause();
            debug("Link %s to %s decode for %s", recv_rtp_src_pad.name, media, name);
            recv_rtp_src_pad.link(decode.get_static_pad("sink"));
            plugin.unpause();
        }
    }

    public void on_send_rtp_src_added(Gst.Pad pad) {
        send_rtp_src_pad = pad;
        if (send_rtp != null) {
            plugin.pause();
            debug("Link %s to %s send_rtp for %s", send_rtp_src_pad.name, media, name);
            send_rtp_src_pad.link(send_rtp.get_static_pad("sink"));
            plugin.unpause();
        }
    }

    public void set_input(Gst.Element? input) {
        set_input_and_pause(input, paused);
    }

    private void set_input_and_pause(Gst.Element? input, bool paused) {
        if (created && this.input != null) {
            if (this.input_queue != null) {
                 this.input_pad.unlink(this.input_queue.get_static_pad("sink"));
                 var queue_src = this.input_queue.get_static_pad("src");
                 var queue_peer = queue_src.get_peer();
                 if (queue_peer != null) {
                     queue_src.unlink(queue_peer);
                 }
                 this.input_queue.set_state(Gst.State.NULL);
                 pipe.remove(this.input_queue);
                 this.input_queue = null;
            } else {
                 var input_peer = this.input_pad.get_peer();
                 if (input_peer != null) {
                     this.input_pad.unlink(input_peer);
                 }
            }
            this.input.release_request_pad(this.input_pad);
            this.input_pad = null;
            this.input = null;
        }

        this.input = input;
        this.paused = paused;

        if (created && sending && !paused && input != null) {
            plugin.pause();
            input_pad = input.request_pad_simple(@"src_$rtpid");
            
            // Add decoupling queue for source
            this.input_queue = Gst.ElementFactory.make("queue", @"input_queue_$rtpid");
            pipe.add(this.input_queue);
            this.input_queue.sync_state_with_parent();

            input_pad.link(this.input_queue.get_static_pad("sink"));
            this.input_queue.get_static_pad("src").link(send_rtp_sink_pad);
            plugin.unpause();
        }
    }

    public void pause() {
        if (paused) return;
        var input = this.input;
        set_input_and_pause(null, true);
        if (input != null && input_device != null) input_device.unlink(input);
    }

    public void unpause() {
        if (!paused) return;
        set_input_and_pause(input_device != null ? input_device.link_source(payload_type, our_ssrc, next_seqnum_offset, next_timestamp_offset) : null, false);
        input_device.update_bitrate(payload_type, target_send_bitrate);
    }

    public uint get_participant_ssrc(Xmpp.Jid participant) {
        if (participant.equals(content.session.peer_full_jid)) {
            return participant_ssrc;
        }
        return 0;
    }

    ulong block_probe_handler_id = 0;
    private Gst.Element? output_queue;

    public virtual void add_output(Gst.Element element, Xmpp.Jid? participant = null) {
        if (output != null) {
            critical("add_output() invoked more than once");
            return;
        }
        if (participant != null) {
            critical("add_output() invoked with participant when not supported");
            return;
        }
        this.output = element;
        if (created) {
            plugin.pause();
            
            // Add queue to decouple decoding from output (fixes pipeline warnings)
            output_queue = Gst.ElementFactory.make("queue", @"audio_out_queue_$rtpid");
            pipe.add(output_queue);
            output_queue.sync_state_with_parent();

            decode.link(output_queue);
            output_queue.link(element);

            if (block_probe_handler_id != 0) {
                decode.get_static_pad("src").remove_probe(block_probe_handler_id);
            }
            plugin.unpause();
        }
    }

    public virtual void remove_output(Gst.Element element) {
        if (output != element) {
            critical("remove_output() invoked without prior add_output()");
            return;
        }
        if (created) {
            block_probe_handler_id = decode.get_static_pad("src").add_probe(Gst.PadProbeType.BLOCK, drop_probe);
            
            if (output_queue != null) {
                decode.unlink(output_queue);
                output_queue.unlink(element);
                output_queue.set_state(Gst.State.NULL);
                pipe.remove(output_queue);
                output_queue = null;
            } else {
                decode.unlink(element);
            }
        }
        if (this._output_device != null) {
            this._output_device.unlink(element);
            this._output_device = null;
        }
        this.output = null;
    }
}

public class Dino.Plugins.Rtp.VideoStream : Stream {
    private Gee.List<Gst.Element> outputs = new ArrayList<Gst.Element>();
    private Gee.Map<Gst.Element, Gst.Element> output_queues = new HashMap<Gst.Element, Gst.Element>();
    private Gst.Element output_tee;
    private Gst.Element rotate;
    private ulong incoming_video_orientation_changed_handler;

    public VideoStream(Plugin plugin, Xmpp.Xep.Jingle.Content content) {
        base(plugin, content);
        if (media != "video") critical("VideoStream created for non-video media");
    }

    public override void create() {
        incoming_video_orientation_changed_handler = incoming_video_orientation_changed.connect(on_video_orientation_changed);
        plugin.pause();
        rotate = Gst.ElementFactory.make("videoflip", @"video_rotate_$rtpid");
        pipe.add(rotate);
        
        // Add Pre-Queue for rotation
        var rot_queue = Gst.ElementFactory.make("queue", @"video_rotate_queue_$rtpid");
        pipe.add(rot_queue);
        rot_queue.sync_state_with_parent();

        output_tee = Gst.ElementFactory.make("tee", @"video_tee_$rtpid");
        output_tee.@set("allow-not-linked", true);
        pipe.add(output_tee);

        // Link rotate -> rot_queue -> output_tee
        rotate.link(rot_queue);
        rot_queue.link(output_tee);

        add_output(rotate);
        base.create();
        foreach (Gst.Element output in outputs) {
            var queue = Gst.ElementFactory.make("queue", null);
            pipe.add(queue);
            queue.sync_state_with_parent();
            output_tee.link(queue);
            queue.link(output);
            output_queues.set(output, queue);
        }
        plugin.unpause();
    }

    private void on_video_orientation_changed(uint16 degree) {
        if (rotate != null) {
            switch (degree) {
                case 0:
                    rotate.@set("method", 0);
                    break;
                case 90:
                    rotate.@set("method", 1);
                    break;
                case 180:
                    rotate.@set("method", 2);
                    break;
                case 270:
                    rotate.@set("method", 3);
                    break;
            }
        }
    }

    public override void destroy() {
        foreach (Gst.Element output in outputs) {
            var queue = output_queues.get(output);
            if (queue != null) {
                output_tee.unlink(queue);
                queue.unlink(output);
                queue.set_state(Gst.State.NULL);
                pipe.remove(queue);
            } else {
                output_tee.unlink(output);
            }
        }
        output_queues.clear();
        base.destroy();
        
        rotate.set_locked_state(true);
        rotate.set_state(Gst.State.NULL);
        
        // Remove rotation queue if it exists
        var rot_queue = pipe.get_by_name(@"video_rotate_queue_$rtpid");
        if (rot_queue != null) {
             rotate.unlink(rot_queue);
             rot_queue.unlink(output_tee);
             rot_queue.set_state(Gst.State.NULL);
             pipe.remove(rot_queue);
        } else {
             rotate.unlink(output_tee);
        }

        pipe.remove(rotate);
        rotate = null;
        output_tee.set_locked_state(true);
        output_tee.set_state(Gst.State.NULL);
        pipe.remove(output_tee);
        output_tee = null;
        disconnect(incoming_video_orientation_changed_handler);
    }

    public override void add_output(Gst.Element element, Xmpp.Jid? participant) {
        if (element == output_tee || element == rotate) {
            base.add_output(element);
            return;
        }
        outputs.add(element);
        if (output_tee != null) {
            var queue = Gst.ElementFactory.make("queue", null);
            pipe.add(queue);
            queue.sync_state_with_parent();
            output_tee.link(queue);
            queue.link(element);
            output_queues.set(element, queue);
        }
    }

    public override void remove_output(Gst.Element element) {
        if (element == output_tee || element == rotate) {
            base.remove_output(element);
            return;
        }
        outputs.remove(element);
        if (output_tee != null) {
            var queue = output_queues.get(element);
            if (queue != null) {
                output_tee.unlink(queue);
                queue.unlink(element);
                queue.set_state(Gst.State.NULL);
                pipe.remove(queue);
                output_queues.unset(element);
            } else {
                output_tee.unlink(element);
            }
        }
    }
}
