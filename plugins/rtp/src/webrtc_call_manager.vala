/*
 * WebRTC Call Manager for DinoX
 * 
 * This is the central manager that bridges GStreamer's webrtcbin with
 * XMPP Jingle signaling. It handles:
 * 
 * 1. ICE candidates from webrtcbin → Jingle transport-info
 * 2. Jingle transport-info → webrtcbin ICE candidates  
 * 3. SDP offer/answer ↔ Jingle content description
 * 4. Media track management
 * 
 * The key insight is that webrtcbin has its own ICE agent (libnice-based),
 * and we need to extract/inject ICE candidates via Jingle signaling,
 * just like Conversations does with native WebRTC.
 * 
 * Copyright (C) 2025 DinoX Project
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#if WITH_WEBRTCBIN

using Gee;
using Xmpp;
using Xmpp.Xep;

namespace Dino.Plugins.Rtp {

/**
 * Manages a WebRTC call session
 * 
 * This bridges the GStreamer WebRTC pipeline with Jingle signaling.
 * It replaces the old rtpbin + separate libnice approach with
 * webrtcbin's integrated ICE handling.
 */
public class WebRTCCallManager : Object {
    
    // Signals for UI integration
    public signal void connection_established();
    public signal void connection_failed(string reason);
    public signal void remote_video_ready(Gst.Element sink);
    public signal void remote_audio_ready(Gst.Element sink);
    
    private weak Plugin plugin;
    private Jingle.Session session;
    private XmppStream stream;
    
    // GStreamer elements
    private Gst.Pipeline pipeline;
    private Gst.Element webrtcbin;
    private SdpJingleConverter converter;
    
    // State
    private bool is_initiator;
    private bool pipeline_started = false;
    private bool offer_created = false;
    
    // Pending ICE candidates (received before remote description set)
    private Gee.List<PendingIceCandidate> pending_remote_candidates;
    private bool remote_description_set = false;
    
    // Device references
    private Device? audio_input_device;
    private Device? video_input_device;
    
    // Signal handler IDs for proper cleanup
    private ulong on_ice_candidate_handler_id;
    private ulong on_connection_state_handler_id;
    private ulong on_ice_connection_state_handler_id;
    private ulong on_negotiation_needed_handler_id;
    private ulong pad_added_handler_id;
    
    private class PendingIceCandidate {
        public uint mline_index;
        public string? mid;
        public string candidate;
        
        public PendingIceCandidate(uint mline, string? mid, string candidate) {
            this.mline_index = mline;
            this.mid = mid;
            this.candidate = candidate;
        }
    }
    
    public WebRTCCallManager(Plugin plugin, Jingle.Session session, XmppStream stream, bool is_initiator) {
        this.plugin = plugin;
        this.session = session;
        this.stream = stream;
        this.is_initiator = is_initiator;
        this.converter = new SdpJingleConverter();
        this.pending_remote_candidates = new ArrayList<PendingIceCandidate>();
        
        debug("WebRTCCallManager created for session %s (initiator: %s)", 
              session.sid, is_initiator.to_string());
    }
    
    /**
     * Set input devices
     */
    public void set_devices(Device? audio_device, Device? video_device) {
        this.audio_input_device = audio_device;
        this.video_input_device = video_device;
    }
    
    /**
     * Initialize the WebRTC pipeline
     */
    public bool initialize() {
        debug("Initializing WebRTC pipeline for session %s", session.sid);
        
        // Create pipeline
        pipeline = new Gst.Pipeline(@"webrtc-$(session.sid)");
        if (pipeline == null) {
            critical("Failed to create GStreamer pipeline");
            return false;
        }
        
        // Create webrtcbin
        webrtcbin = Gst.ElementFactory.make("webrtcbin", "webrtc");
        if (webrtcbin == null) {
            critical("Failed to create webrtcbin element");
            return false;
        }
        
        // Configure webrtcbin for Jingle compatibility
        configure_webrtcbin();
        
        // Add to pipeline
        pipeline.add(webrtcbin);
        
        // Connect signals
        connect_signals();
        
        return true;
    }
    
    /**
     * Configure webrtcbin for optimal Jingle interoperability
     */
    private void configure_webrtcbin() {
        // Bundle policy - required for Jingle
        // 3 = max-bundle (all media in single transport)
        webrtcbin.set_property("bundle-policy", 3);
        
        // Use Google STUN server as fallback
        webrtcbin.set_property("stun-server", "stun://stun.l.google.com:19302");
        
        // ICE transport policy (0 = all, including relay/TURN)
        // webrtcbin.set_property("ice-transport-policy", 0);
        
        debug("webrtcbin configured: bundle-policy=max-bundle");
    }
    
    /**
     * Connect webrtcbin signals
     */
    private void connect_signals() {
        // ICE candidate generation
        on_ice_candidate_handler_id = webrtcbin.connect("signal::on-ice-candidate", 
            (Callback) on_local_ice_candidate, this);
        
        // Connection state changes  
        on_connection_state_handler_id = webrtcbin.connect("signal::notify::connection-state",
            (Callback) on_connection_state_changed, this);
        
        // ICE connection state
        on_ice_connection_state_handler_id = webrtcbin.connect("signal::notify::ice-connection-state",
            (Callback) on_ice_connection_state_changed, this);
        
        // Negotiation needed (for offers)
        on_negotiation_needed_handler_id = webrtcbin.connect("signal::on-negotiation-needed",
            (Callback) on_negotiation_needed, this);
        
        // Incoming media pads
        pad_added_handler_id = webrtcbin.pad_added.connect(on_incoming_pad);
    }
    
    /**
     * Add audio track
     */
    public void add_audio_track() {
        debug("Adding audio track");
        
        Gst.Element? source = null;
        
        if (audio_input_device != null && audio_input_device.device != null) {
            source = audio_input_device.device.create_element("audio-src");
        }
        if (source == null) {
            source = Gst.ElementFactory.make("autoaudiosrc", "audio-src");
        }
        if (source == null) {
            warning("No audio source available");
            return;
        }
        
        // Create encoding chain
        var queue = Gst.ElementFactory.make("queue", "audio-queue");
        var audioconvert = Gst.ElementFactory.make("audioconvert", null);
        var audioresample = Gst.ElementFactory.make("audioresample", null);
        var opusenc = Gst.ElementFactory.make("opusenc", "opus-encoder");
        var rtpopuspay = Gst.ElementFactory.make("rtpopuspay", "opus-pay");
        var capsfilter = Gst.ElementFactory.make("capsfilter", "audio-caps");
        
        if (opusenc == null || rtpopuspay == null) {
            warning("Missing Opus encoder elements");
            return;
        }
        
        // Configure Opus for realtime
        opusenc.set_property("bitrate", 48000);
        opusenc.set_property("audio-type", 2048); // voice
        opusenc.set_property("complexity", 5);
        
        // RTP payload
        rtpopuspay.set_property("pt", 111);
        
        // Caps
        var caps = Gst.Caps.from_string(
            "application/x-rtp,media=audio,encoding-name=OPUS,payload=111,clock-rate=48000");
        capsfilter.set_property("caps", caps);
        
        // Add and link
        pipeline.add_many(source, queue, audioconvert, audioresample, opusenc, rtpopuspay, capsfilter);
        
        source.link(queue);
        queue.link(audioconvert);
        audioconvert.link(audioresample);
        audioresample.link(opusenc);
        opusenc.link(rtpopuspay);
        rtpopuspay.link(capsfilter);
        
        // Link to webrtcbin
        var sinkpad = webrtcbin.request_pad_simple("sink_%u");
        if (sinkpad != null) {
            capsfilter.get_static_pad("src").link(sinkpad);
            debug("Audio track linked to webrtcbin pad %s", sinkpad.name);
        }
    }
    
    /**
     * Add video track
     */
    public void add_video_track() {
        debug("Adding video track");
        
        Gst.Element? source = null;
        
        if (video_input_device != null && video_input_device.device != null) {
            source = video_input_device.device.create_element("video-src");
        }
        if (source == null) {
            source = Gst.ElementFactory.make("autovideosrc", "video-src");
        }
        if (source == null) {
            warning("No video source available");
            return;
        }
        
        // Create encoding chain
        var queue = Gst.ElementFactory.make("queue", "video-queue");
        var videoconvert = Gst.ElementFactory.make("videoconvert", null);
        var videoscale = Gst.ElementFactory.make("videoscale", null);
        var videorate = Gst.ElementFactory.make("videorate", null);
        var rawcaps = Gst.ElementFactory.make("capsfilter", "video-rawcaps");
        
        // Raw video caps - 720p@30fps
        var raw = Gst.Caps.from_string("video/x-raw,width=1280,height=720,framerate=30/1");
        rawcaps.set_property("caps", raw);
        
        // Choose encoder: VP9 > VP8 > H264
        Gst.Element? encoder = null;
        Gst.Element? payloader = null;
        string encoding_name = "VP9";
        int pt = 98;
        
        // Try VP9 first
        encoder = Gst.ElementFactory.make("vp9enc", "video-encoder");
        if (encoder != null) {
            configure_vp9_encoder(encoder);
            payloader = Gst.ElementFactory.make("rtpvp9pay", "video-pay");
            encoding_name = "VP9";
            pt = 98;
            debug("Using VP9 encoder");
        }
        
        // Fallback to VP8
        if (encoder == null) {
            encoder = Gst.ElementFactory.make("vp8enc", "video-encoder");
            if (encoder != null) {
                configure_vp8_encoder(encoder);
                payloader = Gst.ElementFactory.make("rtpvp8pay", "video-pay");
                encoding_name = "VP8";
                pt = 97;
                debug("Using VP8 encoder");
            }
        }
        
        // Fallback to H264
        if (encoder == null) {
            encoder = Gst.ElementFactory.make("x264enc", "video-encoder");
            if (encoder != null) {
                configure_h264_encoder(encoder);
                payloader = Gst.ElementFactory.make("rtph264pay", "video-pay");
                encoding_name = "H264";
                pt = 102;
                debug("Using H264 encoder");
            }
        }
        
        if (encoder == null || payloader == null) {
            warning("No video encoder available");
            return;
        }
        
        payloader.set_property("pt", pt);
        // Set picture-id-mode for WebRTC compatibility (VP9/VP8)
        if (encoding_name == "VP9" || encoding_name == "VP8") {
            payloader.set_property("picture-id-mode", 2); // 15-bit mode
        }
        
        // RTP caps
        var rtpcaps = Gst.ElementFactory.make("capsfilter", "video-rtpcaps");
        var caps = Gst.Caps.from_string(
            @"application/x-rtp,media=video,encoding-name=$(encoding_name),payload=$(pt),clock-rate=90000");
        rtpcaps.set_property("caps", caps);
        
        // Add and link
        pipeline.add_many(source, queue, videoconvert, videoscale, videorate, rawcaps, encoder, payloader, rtpcaps);
        
        source.link(queue);
        queue.link(videoconvert);
        videoconvert.link(videoscale);
        videoscale.link(videorate);
        videorate.link(rawcaps);
        rawcaps.link(encoder);
        encoder.link(payloader);
        payloader.link(rtpcaps);
        
        // Link to webrtcbin
        var sinkpad = webrtcbin.request_pad_simple("sink_%u");
        if (sinkpad != null) {
            rtpcaps.get_static_pad("src").link(sinkpad);
            debug("Video track linked to webrtcbin pad %s", sinkpad.name);
        }
    }
    
    private void configure_vp9_encoder(Gst.Element enc) {
        enc.set_property("deadline", 1); // realtime
        enc.set_property("cpu-used", 4);
        enc.set_property("target-bitrate", 1000000);
        enc.set_property("keyframe-max-dist", 30);  // Keyframe every ~1 second at 30fps
        enc.set_property("error-resilient", 1);     // Enable error resilience
    }
    
    private void configure_vp8_encoder(Gst.Element enc) {
        enc.set_property("deadline", 1);
        enc.set_property("cpu-used", 4);
        enc.set_property("target-bitrate", 1000000);
        enc.set_property("keyframe-max-dist", 30);  // Keyframe every ~1 second at 30fps
        enc.set_property("error-resilient", 3);     // VP8 partitions: 0x01 | 0x02
    }
    
    private void configure_h264_encoder(Gst.Element enc) {
        enc.set_property("tune", 4); // zerolatency
        enc.set_property("speed-preset", 2); // superfast
        enc.set_property("bitrate", 1000);
        enc.set_property("key-int-max", 60);
    }
    
    /**
     * Start the pipeline and initiate negotiation
     */
    public void start() {
        if (pipeline_started) return;
        
        debug("Starting WebRTC pipeline");
        pipeline.set_state(Gst.State.PLAYING);
        pipeline_started = true;
    }
    
    /**
     * Stop the pipeline
     */
    public void stop() {
        if (!pipeline_started) return;
        
        debug("Stopping WebRTC pipeline");
        
        // Disconnect signal handlers before stopping pipeline
        if (webrtcbin != null) {
            if (on_ice_candidate_handler_id != 0 && SignalHandler.is_connected(webrtcbin, on_ice_candidate_handler_id)) {
                SignalHandler.disconnect(webrtcbin, on_ice_candidate_handler_id);
            }
            on_ice_candidate_handler_id = 0;
            
            if (on_connection_state_handler_id != 0 && SignalHandler.is_connected(webrtcbin, on_connection_state_handler_id)) {
                SignalHandler.disconnect(webrtcbin, on_connection_state_handler_id);
            }
            on_connection_state_handler_id = 0;
            
            if (on_ice_connection_state_handler_id != 0 && SignalHandler.is_connected(webrtcbin, on_ice_connection_state_handler_id)) {
                SignalHandler.disconnect(webrtcbin, on_ice_connection_state_handler_id);
            }
            on_ice_connection_state_handler_id = 0;
            
            if (on_negotiation_needed_handler_id != 0 && SignalHandler.is_connected(webrtcbin, on_negotiation_needed_handler_id)) {
                SignalHandler.disconnect(webrtcbin, on_negotiation_needed_handler_id);
            }
            on_negotiation_needed_handler_id = 0;
            
            if (pad_added_handler_id != 0 && SignalHandler.is_connected(webrtcbin, pad_added_handler_id)) {
                SignalHandler.disconnect(webrtcbin, pad_added_handler_id);
            }
            pad_added_handler_id = 0;
        }
        
        pipeline.set_state(Gst.State.NULL);
        pipeline_started = false;
    }
    
    /**
     * Handle local ICE candidate from webrtcbin
     * Convert to Jingle transport-info and send
     */
    private static void on_local_ice_candidate(Gst.Element webrtcbin, 
                                                uint mline_index, 
                                                string candidate,
                                                WebRTCCallManager self) {
        debug("Local ICE candidate (mline=%u): %s", mline_index, candidate);
        
        // Parse ICE candidate
        // Format: "candidate:foundation component protocol priority ip port type ..."
        var ice_candidate = self.parse_ice_candidate(candidate);
        if (ice_candidate == null) {
            warning("Failed to parse ICE candidate");
            return;
        }
        
        // Send via Jingle transport-info
        self.send_ice_candidate(mline_index, ice_candidate);
    }
    
    /**
     * Parse ICE candidate string to Jingle format
     */
    private JingleIceUdp.Candidate? parse_ice_candidate(string candidate_str) {
        // Format: candidate:foundation component protocol priority ip port type [raddr rport] [generation]
        // Example: candidate:1 1 UDP 2122252543 192.168.1.100 54321 typ host
        
        if (!candidate_str.has_prefix("candidate:")) {
            return null;
        }
        
        string[] parts = candidate_str.split(" ");
        if (parts.length < 8) {
            return null;
        }
        
        var candidate = new JingleIceUdp.Candidate();
        
        // Parse foundation (remove "candidate:" prefix)
        candidate.foundation = parts[0].substring(10);
        
        // Component ID
        candidate.component = (uint8) int.parse(parts[1]);
        
        // Protocol
        candidate.protocol = parts[2].down();
        
        // Priority
        candidate.priority = (uint32) uint64.parse(parts[3]);
        
        // IP address
        candidate.ip = parts[4];
        
        // Port
        candidate.port = (uint16) int.parse(parts[5]);
        
        // Type (skip "typ" keyword)
        if (parts[6] == "typ" && parts.length > 7) {
            candidate.type_ = parts[7];
        }
        
        // Related address/port for relay/srflx
        for (int i = 8; i < parts.length - 1; i++) {
            if (parts[i] == "raddr") {
                candidate.rel_addr = parts[i + 1];
            } else if (parts[i] == "rport") {
                candidate.rel_port = (uint16) int.parse(parts[i + 1]);
            } else if (parts[i] == "generation") {
                candidate.generation = (uint8) int.parse(parts[i + 1]);
            }
        }
        
        // Generate unique ID
        candidate.id = @"$(candidate.foundation)-$(candidate.component)";
        
        return candidate;
    }
    
    /**
     * Send ICE candidate via Jingle transport-info
     */
    private void send_ice_candidate(uint mline_index, JingleIceUdp.Candidate candidate) {
        // Get content name for mline index
        string? content_name = get_content_name_for_mline(mline_index);
        if (content_name == null) {
            warning("No content found for mline %u", mline_index);
            return;
        }
        
        // Find the content
        Jingle.Content? content = null;
        foreach (var c in session.contents) {
            if (c.content_name == content_name) {
                content = c;
                break;
            }
        }
        
        if (content == null) {
            warning("Content %s not found in session", content_name);
            return;
        }
        
        // Get transport parameters
        var transport_params = content.transport_params as JingleIceUdp.IceUdpTransportParameters;
        if (transport_params == null) {
            warning("No ICE-UDP transport params for content %s", content_name);
            return;
        }
        
        // Add candidate and send transport-info
        transport_params.add_local_candidate_threadsafe(candidate);
        
        debug("Sent ICE candidate via Jingle transport-info: %s", candidate.id);
    }
    
    /**
     * Map mline index to Jingle content name
     */
    private string? get_content_name_for_mline(uint mline_index) {
        // In standard WebRTC, mline 0 is audio, mline 1 is video
        // But this depends on the order in the SDP
        
        int idx = 0;
        foreach (var content in session.contents) {
            var params = content.content_params as JingleRtp.Parameters;
            if (params == null) continue;
            
            if (idx == mline_index) {
                return content.content_name;
            }
            idx++;
        }
        
        // Fallback: try common content names
        if (mline_index == 0) return "audio";
        if (mline_index == 1) return "video";
        
        return null;
    }
    
    /**
     * Handle remote ICE candidate from Jingle transport-info
     */
    public void add_remote_ice_candidate(string content_name, JingleIceUdp.Candidate candidate) {
        uint mline_index = get_mline_for_content(content_name);
        string candidate_str = format_ice_candidate(candidate);
        
        debug("Remote ICE candidate for %s (mline=%u): %s", 
              content_name, mline_index, candidate_str);
        
        if (!remote_description_set) {
            // Queue candidate until remote description is set
            pending_remote_candidates.add(
                new PendingIceCandidate(mline_index, content_name, candidate_str));
            return;
        }
        
        // Add to webrtcbin
        webrtcbin.emit_by_name("add-ice-candidate", mline_index, candidate_str);
    }
    
    /**
     * Map content name to mline index
     */
    private uint get_mline_for_content(string content_name) {
        int idx = 0;
        foreach (var content in session.contents) {
            if (content.content_name == content_name) {
                return idx;
            }
            idx++;
        }
        
        // Fallback
        if (content_name == "audio") return 0;
        if (content_name == "video") return 1;
        
        return 0;
    }
    
    /**
     * Format Jingle candidate to ICE candidate string
     */
    private string format_ice_candidate(JingleIceUdp.Candidate c) {
        var sb = new StringBuilder();
        sb.append(@"candidate:$(c.foundation) $(c.component) $(c.protocol.up()) $(c.priority) $(c.ip) $(c.port) typ $(c.type_)");
        
        if (c.rel_addr != null && c.rel_addr != "") {
            sb.append(@" raddr $(c.rel_addr) rport $(c.rel_port)");
        }
        
        if (c.generation > 0) {
            sb.append(@" generation $(c.generation)");
        }
        
        return sb.str;
    }
    
    /**
     * Flush pending ICE candidates after remote description is set
     */
    private void flush_pending_candidates() {
        if (pending_remote_candidates.size == 0) return;
        
        debug("Flushing %d pending ICE candidates", pending_remote_candidates.size);
        
        foreach (var pending in pending_remote_candidates) {
            webrtcbin.emit_by_name("add-ice-candidate", pending.mline_index, pending.candidate);
        }
        
        pending_remote_candidates.clear();
    }
    
    /**
     * Create SDP offer and convert to Jingle
     */
    public void create_offer() {
        if (offer_created) return;
        offer_created = true;
        
        debug("Creating SDP offer");
        
        var promise = new Gst.Promise.with_change_func((p) => {
            on_offer_created(p);
        });
        
        webrtcbin.emit_by_name("create-offer", null, promise);
    }
    
    private void on_offer_created(Gst.Promise promise) {
        if (promise.wait() != Gst.PromiseResult.REPLIED) {
            warning("Failed to create offer");
            return;
        }
        
        var reply = promise.get_reply();
        if (reply == null) {
            warning("Offer reply is null");
            return;
        }
        
        Gst.WebRTCSessionDescription offer;
        reply.get("offer", typeof(Gst.WebRTCSessionDescription), out offer);
        
        if (offer == null) {
            warning("Offer is null");
            return;
        }
        
        // Set local description
        var set_promise = new Gst.Promise.with_change_func((p) => {
            debug("Local offer set");
        });
        webrtcbin.emit_by_name("set-local-description", offer, set_promise);
        
        string sdp = offer.sdp.as_text();
        debug("Created SDP offer:\n%s", sdp);
        
        // Convert to Jingle and update session
        // Note: The actual Jingle message is handled by the session
    }
    
    /**
     * Set remote description from Jingle session-initiate/accept
     */
    public void set_remote_description_from_jingle(bool is_offer) {
        // Build SDP from Jingle contents
        string sdp = build_sdp_from_session(is_offer);
        
        debug("Setting remote %s:\n%s", is_offer ? "offer" : "answer", sdp);
        
        Gst.WebRTCSDPType sdp_type = is_offer ? 
            Gst.WebRTCSDPType.OFFER : Gst.WebRTCSDPType.ANSWER;
        
        Gst.SDP.Message sdp_msg;
        if (Gst.SDP.Message.new_from_text(sdp, out sdp_msg) != Gst.SDP.Result.OK) {
            warning("Failed to parse SDP");
            return;
        }
        
        var desc = Gst.WebRTCSessionDescription.new(sdp_type, (owned) sdp_msg);
        
        var promise = new Gst.Promise.with_change_func((p) => {
            debug("Remote description set");
            remote_description_set = true;
            
            // Flush pending candidates
            flush_pending_candidates();
            
            // If we got an offer, create answer
            if (is_offer) {
                create_answer();
            }
        });
        
        webrtcbin.emit_by_name("set-remote-description", desc, promise);
    }
    
    /**
     * Create SDP answer
     */
    public void create_answer() {
        debug("Creating SDP answer");
        
        var promise = new Gst.Promise.with_change_func((p) => {
            on_answer_created(p);
        });
        
        webrtcbin.emit_by_name("create-answer", null, promise);
    }
    
    private void on_answer_created(Gst.Promise promise) {
        if (promise.wait() != Gst.PromiseResult.REPLIED) {
            warning("Failed to create answer");
            return;
        }
        
        var reply = promise.get_reply();
        if (reply == null) {
            warning("Answer reply is null");
            return;
        }
        
        Gst.WebRTCSessionDescription answer;
        reply.get("answer", typeof(Gst.WebRTCSessionDescription), out answer);
        
        if (answer == null) {
            warning("Answer is null");
            return;
        }
        
        // Set local description
        var set_promise = new Gst.Promise.with_change_func((p) => {
            debug("Local answer set");
        });
        webrtcbin.emit_by_name("set-local-description", answer, set_promise);
        
        string sdp = answer.sdp.as_text();
        debug("Created SDP answer:\n%s", sdp);
    }
    
    /**
     * Build SDP from Jingle session contents
     */
    private string build_sdp_from_session(bool is_offer) {
        var sb = new StringBuilder();
        
        // SDP header
        sb.append("v=0\r\n");
        sb.append(@"o=- $(session.sid.hash()) 2 IN IP4 127.0.0.1\r\n");
        sb.append("s=DinoX\r\n");
        sb.append("t=0 0\r\n");
        sb.append("a=group:BUNDLE");
        
        // Add content names to BUNDLE
        foreach (var content in session.contents) {
            sb.append(@" $(content.content_name)");
        }
        sb.append("\r\n");
        sb.append("a=msid-semantic: WMS\r\n");
        
        // Add media sections
        foreach (var content in session.contents) {
            string media_section = build_media_section(content, is_offer);
            sb.append(media_section);
        }
        
        return sb.str;
    }
    
    /**
     * Build SDP media section from Jingle content
     */
    private string build_media_section(Jingle.Content content, bool is_offer) {
        var sb = new StringBuilder();
        
        var rtp_params = content.content_params as JingleRtp.Parameters;
        if (rtp_params == null) return "";
        
        var ice_params = content.transport_params as JingleIceUdp.IceUdpTransportParameters;
        
        string media = rtp_params.media;
        string profile = "RTP/SAVPF"; // SRTP with feedback
        
        // Collect payload types
        var pts = new ArrayList<int>();
        foreach (var pt in rtp_params.payload_types) {
            pts.add((int) pt.id);
        }
        
        string pt_list = "";
        foreach (int pt in pts) {
            pt_list += @" $(pt)";
        }
        
        // Media line
        sb.append(@"m=$(media) 9 $(profile)$(pt_list)\r\n");
        sb.append("c=IN IP4 0.0.0.0\r\n");
        
        // ICE credentials
        if (ice_params != null) {
            if (is_offer) {
                sb.append(@"a=ice-ufrag:$(ice_params.local_ufrag)\r\n");
                sb.append(@"a=ice-pwd:$(ice_params.local_pwd)\r\n");
            } else {
                sb.append(@"a=ice-ufrag:$(ice_params.remote_ufrag ?? ice_params.local_ufrag)\r\n");
                sb.append(@"a=ice-pwd:$(ice_params.remote_pwd ?? ice_params.local_pwd)\r\n");
            }
        }
        
        // Fingerprint for DTLS-SRTP
        if (ice_params != null && ice_params.own_fingerprint != null) {
            sb.append(@"a=fingerprint:sha-256 $(format_fingerprint(ice_params.own_fingerprint))\r\n");
            sb.append(@"a=setup:$(ice_params.own_setup ?? "actpass")\r\n");
        }
        
        sb.append(@"a=mid:$(content.content_name)\r\n");
        
        // Direction
        if (content.senders == Jingle.Senders.BOTH) {
            sb.append("a=sendrecv\r\n");
        } else if (content.senders == Jingle.Senders.INITIATOR) {
            sb.append(session.we_initiated ? "a=sendonly\r\n" : "a=recvonly\r\n");
        } else if (content.senders == Jingle.Senders.RESPONDER) {
            sb.append(session.we_initiated ? "a=recvonly\r\n" : "a=sendonly\r\n");
        } else {
            sb.append("a=inactive\r\n");
        }
        
        // RTCP mux
        if (rtp_params.rtcp_mux) {
            sb.append("a=rtcp-mux\r\n");
        }
        
        // Payload types
        foreach (var pt in rtp_params.payload_types) {
            string codec_name = pt.name.up();
            int clockrate = (int) pt.clockrate;
            
            if (media == "audio" && pt.channels > 1) {
                sb.append(@"a=rtpmap:$(pt.id) $(codec_name)/$(clockrate)/$(pt.channels)\r\n");
            } else {
                sb.append(@"a=rtpmap:$(pt.id) $(codec_name)/$(clockrate)\r\n");
            }
            
            // fmtp
            if (pt.parameters.size > 0) {
                string fmtp = "";
                foreach (var entry in pt.parameters.entries) {
                    if (fmtp != "") fmtp += ";";
                    fmtp += @"$(entry.key)=$(entry.value)";
                }
                sb.append(@"a=fmtp:$(pt.id) $(fmtp)\r\n");
            }
            
            // RTCP feedback
            foreach (var fb in pt.rtcp_fbs) {
                if (fb.subtype != null && fb.subtype != "") {
                    sb.append(@"a=rtcp-fb:$(pt.id) $(fb.type_) $(fb.subtype)\r\n");
                } else {
                    sb.append(@"a=rtcp-fb:$(pt.id) $(fb.type_)\r\n");
                }
            }
        }
        
        // ICE candidates
        if (ice_params != null) {
            var candidates = is_offer ? ice_params.local_candidates : ice_params.remote_candidates;
            foreach (var c in candidates) {
                sb.append(@"a=candidate:$(c.foundation) $(c.component) $(c.protocol.up()) $(c.priority) $(c.ip) $(c.port) typ $(c.type_)");
                if (c.rel_addr != null && c.rel_addr != "") {
                    sb.append(@" raddr $(c.rel_addr) rport $(c.rel_port)");
                }
                sb.append("\r\n");
            }
        }
        
        return sb.str;
    }
    
    private string format_fingerprint(uint8[] fp) {
        var sb = new StringBuilder();
        for (int i = 0; i < fp.length; i++) {
            if (i > 0) sb.append(":");
            sb.append("%02X".printf(fp[i]));
        }
        return sb.str;
    }
    
    /**
     * Handle connection state changes
     */
    private static void on_connection_state_changed(Gst.Element webrtcbin,
                                                     GLib.ParamSpec pspec,
                                                     WebRTCCallManager self) {
        int state;
        webrtcbin.get("connection-state", out state);
        
        string state_name;
        switch (state) {
            case 0: state_name = "new"; break;
            case 1: state_name = "connecting"; break;
            case 2: state_name = "connected"; break;
            case 3: state_name = "disconnected"; break;
            case 4: state_name = "failed"; break;
            case 5: state_name = "closed"; break;
            default: state_name = "unknown"; break;
        }
        
        debug("WebRTC connection state: %s", state_name);
        
        if (state == 2) { // connected
            self.connection_established();
        } else if (state == 4) { // failed
            self.connection_failed("WebRTC connection failed");
        }
    }
    
    private static void on_ice_connection_state_changed(Gst.Element webrtcbin,
                                                         GLib.ParamSpec pspec,
                                                         WebRTCCallManager self) {
        int state;
        webrtcbin.get("ice-connection-state", out state);
        
        string state_name;
        switch (state) {
            case 0: state_name = "new"; break;
            case 1: state_name = "checking"; break;
            case 2: state_name = "connected"; break;
            case 3: state_name = "completed"; break;
            case 4: state_name = "failed"; break;
            case 5: state_name = "disconnected"; break;
            case 6: state_name = "closed"; break;
            default: state_name = "unknown"; break;
        }
        
        debug("ICE connection state: %s", state_name);
    }
    
    private static void on_negotiation_needed(Gst.Element webrtcbin, 
                                               WebRTCCallManager self) {
        debug("Negotiation needed");
        
        // For initiator, create offer
        if (self.is_initiator && !self.offer_created) {
            self.create_offer();
        }
    }
    
    /**
     * Handle incoming media pads
     */
    private void on_incoming_pad(Gst.Pad pad) {
        if (pad.direction != Gst.PadDirection.SRC) return;
        
        debug("Incoming WebRTC pad: %s", pad.name);
        
        // Create decodebin for incoming stream
        var decodebin = Gst.ElementFactory.make("decodebin3", null);
        if (decodebin == null) {
            warning("Failed to create decodebin");
            return;
        }
        
        decodebin.pad_added.connect(on_decoded_pad);
        
        pipeline.add(decodebin);
        decodebin.sync_state_with_parent();
        
        pad.link(decodebin.get_static_pad("sink"));
    }
    
    private void on_decoded_pad(Gst.Pad pad) {
        var caps = pad.get_current_caps();
        if (caps == null) return;
        
        unowned Gst.Structure structure = caps.get_structure(0);
        string media_type = structure.get_name();
        
        debug("Decoded media: %s", media_type);
        
        if (media_type.has_prefix("audio/x-raw")) {
            // Create audio output chain
            var audioconvert = Gst.ElementFactory.make("audioconvert", null);
            var audioresample = Gst.ElementFactory.make("audioresample", null);
            var audiosink = Gst.ElementFactory.make("autoaudiosink", null);
            
            pipeline.add_many(audioconvert, audioresample, audiosink);
            audioconvert.sync_state_with_parent();
            audioresample.sync_state_with_parent();
            audiosink.sync_state_with_parent();
            
            pad.link(audioconvert.get_static_pad("sink"));
            audioconvert.link(audioresample);
            audioresample.link(audiosink);
            
            remote_audio_ready(audiosink);
            
        } else if (media_type.has_prefix("video/x-raw")) {
            // Create video output chain
            var videoconvert = Gst.ElementFactory.make("videoconvert", null);
            var videosink = Gst.ElementFactory.make("autovideosink", null);
            
            pipeline.add_many(videoconvert, videosink);
            videoconvert.sync_state_with_parent();
            videosink.sync_state_with_parent();
            
            pad.link(videoconvert.get_static_pad("sink"));
            videoconvert.link(videosink);
            
            remote_video_ready(videosink);
        }
    }
    
    /**
     * Get video sink for external rendering
     */
    public Gst.Element? get_video_sink() {
        // Create a tee to split video for local preview
        // Return the appropriate sink based on use case
        return null;
    }
    
    /**
     * Cleanup resources
     */
    public void dispose() {
        stop();
        pipeline = null;
        webrtcbin = null;
    }
}

} // namespace Dino.Plugins.Rtp

#endif // WITH_WEBRTCBIN
