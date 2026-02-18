/*
 * WebRTC Module for DinoX
 * 
 * This module implements Jingle RTP (XEP-0167) using GStreamer's webrtcbin.
 * It replaces the legacy rtpbin-based implementation for better codec
 * compatibility with Conversations and Monal.
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
 * WebRTC-based Jingle RTP Module
 * 
 * This module handles:
 * - Codec negotiation (VP9, VP8, H.264, Opus)
 * - Media stream management via webrtcbin
 */
public class WebRTCModule : JingleRtp.Module {
    
    private weak Plugin plugin;
    
    public WebRTCModule(Plugin plugin) {
        base();
        this.plugin = plugin;
        
        debug("WebRTCModule initialized");
    }
    
    public override string get_ns() {
        return JingleRtp.NS_URI;
    }
    
    public override string get_id() {
        return JingleRtp.Module.IDENTITY.id;
    }
    
    /**
     * Get supported payload types for a media type
     */
    public override async Gee.List<JingleRtp.PayloadType> get_supported_payloads(string media) {
        var payloads = new ArrayList<JingleRtp.PayloadType>();
        
        if (media == "audio") {
            // Opus is the standard WebRTC audio codec
            var opus = new JingleRtp.PayloadType() {
                channels = 2,
                clockrate = 48000,
                name = "opus",
                id = 111
            };
            opus.parameters["useinbandfec"] = "1";
            opus.parameters["stereo"] = "1";
            payloads.add(opus);

            // G.711 fallback for SIP gateways (e.g. Cheogram) that don't support Opus
            var pcmu = new JingleRtp.PayloadType() { clockrate = 8000, name = "PCMU", id = 0, channels = 1 };
            payloads.add(pcmu);
            var pcma = new JingleRtp.PayloadType() { clockrate = 8000, name = "PCMA", id = 8, channels = 1 };
            payloads.add(pcma);
        } else if (media == "video") {
            // VP8 - best compatibility with Monal/Conversations, WebRTC mandatory codec
            var vp8 = new JingleRtp.PayloadType() {
                clockrate = 90000,
                name = "VP8",
                id = 96
            };
            vp8.rtcp_fbs.add(new JingleRtp.RtcpFeedback("nack", null));
            vp8.rtcp_fbs.add(new JingleRtp.RtcpFeedback("nack", "pli"));
            vp8.rtcp_fbs.add(new JingleRtp.RtcpFeedback("ccm", "fir"));
            vp8.rtcp_fbs.add(new JingleRtp.RtcpFeedback("goog-remb", null));
            payloads.add(vp8);
            
            // VP9 - optional, better quality but less compatible
            var vp9 = new JingleRtp.PayloadType() {
                clockrate = 90000,
                name = "VP9",
                id = 98
            };
            vp9.rtcp_fbs.add(new JingleRtp.RtcpFeedback("nack", null));
            vp9.rtcp_fbs.add(new JingleRtp.RtcpFeedback("nack", "pli"));
            vp9.rtcp_fbs.add(new JingleRtp.RtcpFeedback("ccm", "fir"));
            vp9.rtcp_fbs.add(new JingleRtp.RtcpFeedback("goog-remb", null));
            payloads.add(vp9);
        }
        
        return payloads;
    }
    
    /**
     * Check if a payload type is supported
     */
    public override async bool is_payload_supported(string media, JingleRtp.PayloadType payload_type) {
        string name = payload_type.name.up();
        
        if (media == "audio") {
            return name == "OPUS" || name == "PCMU" || name == "PCMA";
        } else if (media == "video") {
            return name == "VP9" || name == "VP8" || name == "H264";
        }
        
        return false;
    }
    
    /**
     * Pick the best payload type from offered options
     */
    public override async JingleRtp.PayloadType? pick_payload_type(string media, Gee.List<JingleRtp.PayloadType> payloads) {
        // Priority order for video: VP8 first (most compatible with Monal/Conversations), then VP9
        string[] video_priority = { "VP8", "VP9" };
        
        if (media == "video") {
            foreach (string codec_name in video_priority) {
                foreach (var payload in payloads) {
                    if (payload.name.up() == codec_name) {
                        debug("WebRTC: Selected %s codec for video", codec_name);
                        return payload;
                    }
                }
            }
        } else if (media == "audio") {
            // Strict priority: Opus > PCMU > PCMA
            string[] audio_priority = { "OPUS", "PCMU", "PCMA" };
            foreach (string codec_name in audio_priority) {
                foreach (var payload in payloads) {
                    if (payload.name.up() == codec_name) {
                        debug("WebRTC: Selected %s codec for audio", codec_name);
                        return payload;
                    }
                }
            }
        }
        
        // Fallback: return first supported
        foreach (var payload in payloads) {
            if (yield is_payload_supported(media, payload)) {
                debug("WebRTC: Fallback to %s for %s", payload.name, media);
                return payload;
            }
        }
        
        return null;
    }
    
    /**
     * Generate local SRTP crypto
     */
    public override JingleRtp.Crypto? generate_local_crypto() {
        uint8[] key_and_salt = new uint8[30];
        Crypto.randomize(key_and_salt);
        return JingleRtp.Crypto.create(JingleRtp.Crypto.AES_CM_128_HMAC_SHA1_80, key_and_salt);
    }
    
    public override JingleRtp.Crypto? pick_remote_crypto(Gee.List<JingleRtp.Crypto> cryptos) {
        foreach (JingleRtp.Crypto crypto in cryptos) {
            if (crypto.is_valid) return crypto;
        }
        return null;
    }
    
    public override JingleRtp.Crypto? pick_local_crypto(JingleRtp.Crypto? remote) {
        // Use standard SRTP crypto for stream encryption
        if (remote == null || !remote.is_valid) return null;
        uint8[] key_and_salt = new uint8[30];
        Crypto.randomize(key_and_salt);
        return remote.rekey(key_and_salt);
    }
    
    /**
     * Create a new media stream using the standard Stream/VideoStream classes
     * WebRTCModule only overrides codec negotiation (get_supported_payloads, pick_payload_type)
     * but uses the existing, working Stream classes for the actual media pipeline
     * 
     * Note: webrtcbin cannot be used directly because Dino uses Jingle ICE-UDP
     * for transport, which is separate from webrtcbin's internal ICE.
     */
    public override JingleRtp.Stream create_stream(Jingle.Content content) {
        string content_name = content.content_name;
        var content_params = content.content_params as JingleRtp.Parameters;
        
        debug("WebRTCModule: Creating stream for %s (media=%s)", 
              content_name, content_params?.media ?? "unknown");
        
        // Use the plugin's open_stream which creates Stream/VideoStream
        // These classes properly integrate with Jingle ICE transport
        return plugin.open_stream(content);
    }
    
    /**
     * Close and cleanup a stream
     */
    public override void close_stream(JingleRtp.Stream stream) {
        var rtp_stream = stream as Stream;
        if (rtp_stream != null) {
            plugin.close_stream(rtp_stream);
        }
    }
    
    /**
     * Check if a header extension is supported
     */
    public override bool is_header_extension_supported(string media, JingleRtp.HeaderExtension ext) {
        string uri = ext.uri;
        return uri.has_prefix("urn:ietf:params:rtp-hdrext:");
    }
    
    /**
     * Get suggested header extensions for a media type
     */
    public override Gee.List<JingleRtp.HeaderExtension> get_suggested_header_extensions(string media) {
        var extensions = new ArrayList<JingleRtp.HeaderExtension>();
        
        extensions.add(new JingleRtp.HeaderExtension(
            3, "urn:ietf:params:rtp-hdrext:sdes:abs-send-time"
        ));
        
        if (media == "video") {
            extensions.add(new JingleRtp.HeaderExtension(
                4, "urn:3gpp:video-orientation"
            ));
        }
        
        return extensions;
    }
}

} // namespace Dino.Plugins.Rtp

#endif // WITH_WEBRTCBIN
