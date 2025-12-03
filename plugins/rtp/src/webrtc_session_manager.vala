/*
 * WebRTC Session Manager for DinoX
 * 
 * This class bridges WebRTC (webrtcbin) with XMPP Jingle signaling.
 * It handles:
 * - Session lifecycle (create, accept, terminate)
 * - SDP <-> Jingle conversion
 * - ICE candidate exchange
 * - Media track management
 * 
 * Copyright (C) 2025 DinoX Project
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using Gee;
using Xmpp;
using Xmpp.Xep;

namespace Dino.Plugins.Rtp {

    /**
     * WebRTC Session Manager
     * 
     * Manages WebRTC sessions and integrates them with Jingle signaling.
     */
    public class WebRTCSessionManager : Object {
        
        public signal void session_established(string session_id);
        public signal void session_terminated(string session_id, string reason);
        public signal void media_ready(string session_id, string media_type);
        
        private Plugin plugin;
        private HashMap<string, WebRTCSession> sessions;
        private SdpJingleConverter converter;
        
        public WebRTCSessionManager(Plugin plugin) {
            this.plugin = plugin;
            this.sessions = new HashMap<string, WebRTCSession>();
            this.converter = new SdpJingleConverter();
        }
        
        /**
         * Create a new outgoing WebRTC session (we are the initiator)
         */
        public WebRTCSession? create_session(Jid peer, bool with_video) {
            string session_id = generate_session_id();
            
            var session = new WebRTCSession(this, session_id, peer, true);
            session.with_video = with_video;
            
            if (!session.initialize()) {
                warning("Failed to initialize WebRTC session");
                return null;
            }
            
            sessions[session_id] = session;
            
            debug("Created outgoing WebRTC session %s to %s", session_id, peer.to_string());
            return session;
        }
        
        /**
         * Accept an incoming Jingle session-initiate
         */
        public WebRTCSession? accept_session(string session_id, Jid peer, 
                                              StanzaNode jingle_node) {
            if (sessions.has_key(session_id)) {
                warning("Session %s already exists", session_id);
                return null;
            }
            
            var session = new WebRTCSession(this, session_id, peer, false);
            
            if (!session.initialize()) {
                warning("Failed to initialize WebRTC session for accept");
                return null;
            }
            
            // Convert Jingle to SDP and set as remote description
            string sdp = converter.jingle_to_sdp(jingle_node, true);
            session.set_remote_sdp("offer", sdp);
            
            sessions[session_id] = session;
            
            debug("Accepting incoming WebRTC session %s from %s", session_id, peer.to_string());
            return session;
        }
        
        /**
         * Handle incoming Jingle session-accept
         */
        public void handle_session_accept(string session_id, StanzaNode jingle_node) {
            var session = sessions[session_id];
            if (session == null) {
                warning("Session %s not found for accept", session_id);
                return;
            }
            
            string sdp = converter.jingle_to_sdp(jingle_node, false);
            session.set_remote_sdp("answer", sdp);
        }
        
        /**
         * Handle incoming Jingle transport-info (ICE candidates)
         */
        public void handle_transport_info(string session_id, StanzaNode jingle_node) {
            var session = sessions[session_id];
            if (session == null) {
                warning("Session %s not found for transport-info", session_id);
                return;
            }
            
            // Extract candidates from Jingle
            var contents = jingle_node.get_subnodes("content");
            foreach (var content in contents) {
                string mid = content.get_attribute("name") ?? "0";
                
                var transport = content.get_subnode("transport");
                if (transport == null) continue;
                
                var candidates = transport.get_subnodes("candidate");
                foreach (var candidate in candidates) {
                    string candidate_str = converter.jingle_candidate_to_sdp_string(candidate);
                    session.add_ice_candidate(mid, 0, candidate_str);
                }
            }
        }
        
        /**
         * Handle incoming Jingle session-terminate
         */
        public void handle_session_terminate(string session_id, string reason) {
            var session = sessions[session_id];
            if (session == null) {
                debug("Session %s already terminated or not found", session_id);
                return;
            }
            
            session.terminate();
            sessions.unset(session_id);
            
            session_terminated(session_id, reason);
        }
        
        /**
         * Terminate a session locally
         */
        public void terminate_session(string session_id, string reason = "success") {
            var session = sessions[session_id];
            if (session == null) return;
            
            session.terminate();
            sessions.unset(session_id);
            
            session_terminated(session_id, reason);
        }
        
        /**
         * Get session by ID
         */
        public WebRTCSession? get_session(string session_id) {
            return sessions[session_id];
        }
        
        /**
         * Internal: Get the SDP-Jingle converter
         */
        internal SdpJingleConverter get_converter() {
            return converter;
        }
        
        /**
         * Internal: Get the plugin
         */
        internal Plugin get_plugin() {
            return plugin;
        }
        
        private string generate_session_id() {
            // Generate a random session ID
            return "webrtc-" + Uuid.string_random().substring(0, 8);
        }
    }
    
    /**
     * Individual WebRTC Session
     */
    public class WebRTCSession : Object {
        
        public signal void local_description_ready(string type, StanzaNode jingle);
        public signal void local_candidate_ready(string mid, StanzaNode candidate);
        public signal void connection_established();
        public signal void connection_failed(string reason);
        public signal void remote_video_ready(Gst.Element video_sink);
        public signal void remote_audio_ready();
        
        public string session_id { get; private set; }
        public Jid peer { get; private set; }
        public bool is_initiator { get; private set; }
        public bool with_video { get; set; default = false; }
        public bool is_connected { get; private set; default = false; }
        
        private weak WebRTCSessionManager manager;
        private WebRTCStream stream;
        private SdpJingleConverter converter;
        
        public WebRTCSession(WebRTCSessionManager manager, string session_id, 
                             Jid peer, bool is_initiator) {
            this.manager = manager;
            this.session_id = session_id;
            this.peer = peer;
            this.is_initiator = is_initiator;
            this.converter = manager.get_converter();
        }
        
        /**
         * Initialize the WebRTC stream
         */
        public bool initialize() {
            stream = new WebRTCStream(manager.get_plugin(), session_id, is_initiator);
            
            if (!stream.initialize()) {
                return false;
            }
            
            // Connect to stream signals
            stream.on_local_sdp.connect(on_local_sdp);
            stream.on_ice_candidate.connect(on_ice_candidate);
            stream.on_connection_state_changed.connect(on_connection_state);
            stream.on_remote_track_added.connect(on_remote_track);
            
            return true;
        }
        
        /**
         * Start the call (add tracks and begin negotiation)
         */
        public void start(Device? audio_device = null, Device? video_device = null) {
            debug("Starting WebRTC session %s", session_id);
            
            // Always add audio
            stream.add_audio_track(audio_device);
            
            // Add video if requested
            if (with_video) {
                stream.add_video_track(video_device);
            }
            
            // Start the pipeline
            stream.start();
            
            // If we're the initiator, create offer will be triggered by negotiation-needed
        }
        
        /**
         * Set remote SDP (from Jingle)
         */
        public void set_remote_sdp(string type, string sdp) {
            stream.set_remote_description(type, sdp);
        }
        
        /**
         * Add ICE candidate from remote peer
         */
        public void add_ice_candidate(string mid, int mline_index, string candidate) {
            stream.add_ice_candidate(mid, mline_index, candidate);
        }
        
        /**
         * Terminate the session
         */
        public void terminate() {
            debug("Terminating WebRTC session %s", session_id);
            stream.stop();
            is_connected = false;
        }
        
        /**
         * Mute/unmute audio
         */
        public void set_audio_muted(bool muted) {
            // TODO: Implement via webrtcbin transceiver
            debug("Set audio muted: %s", muted.to_string());
        }
        
        /**
         * Enable/disable video
         */
        public void set_video_enabled(bool enabled) {
            // TODO: Implement via webrtcbin transceiver
            debug("Set video enabled: %s", enabled.to_string());
        }
        
        /**
         * Get the GStreamer pipeline for custom video sink integration
         */
        public Gst.Pipeline? get_pipeline() {
            return stream.pipe;
        }
        
        // ==================== Signal Handlers ====================
        
        private void on_local_sdp(string type, string sdp) {
            debug("Local SDP ready (%s)", type);
            
            // Convert SDP to Jingle
            string action = (type == "offer") ? "session-initiate" : "session-accept";
            string initiator = is_initiator ? "me" : peer.to_string(); // Simplified
            
            StanzaNode jingle = converter.sdp_to_jingle(sdp, action, session_id, initiator);
            
            local_description_ready(type, jingle);
        }
        
        private void on_ice_candidate(string mid, int mline_index, string candidate) {
            debug("Local ICE candidate ready");
            
            // Convert to Jingle candidate
            StanzaNode cand_node = converter.parse_ice_candidate_to_jingle(mid, mline_index, candidate);
            
            local_candidate_ready(mid, cand_node);
        }
        
        private void on_connection_state(string state) {
            debug("Connection state: %s", state);
            
            if (state == "connected") {
                is_connected = true;
                connection_established();
            } else if (state == "failed" || state == "disconnected") {
                is_connected = false;
                connection_failed(state);
            }
        }
        
        private void on_remote_track(string media_type, Gst.Pad pad) {
            debug("Remote track added: %s", media_type);
            
            if (media_type == "video") {
                // Notify that video is ready
                // The actual video sink is created in WebRTCStream
                remote_video_ready(stream.pipe.get_by_name("video-display"));
            } else if (media_type == "audio") {
                remote_audio_ready();
            }
        }
    }
}
