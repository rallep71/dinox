/*
 * SDP to Jingle Converter for DinoX
 * 
 * Converts between WebRTC SDP (Session Description Protocol) 
 * and XMPP Jingle format.
 * 
 * Inspired by Monal's sdp-to-jingle Rust implementation.
 * 
 * SDP Format (RFC 4566):
 *   v=0
 *   o=- 12345 2 IN IP4 127.0.0.1
 *   s=-
 *   t=0 0
 *   m=audio 9 UDP/TLS/RTP/SAVPF 111
 *   a=rtpmap:111 opus/48000/2
 *   ...
 * 
 * Jingle Format (XEP-0166, XEP-0167):
 *   <jingle action="session-initiate">
 *     <content name="audio">
 *       <description xmlns="urn:xmpp:jingle:apps:rtp:1" media="audio">
 *         <payload-type id="111" name="opus" clockrate="48000" channels="2"/>
 *       </description>
 *       <transport xmlns="urn:xmpp:jingle:transports:ice-udp:1">
 *         <candidate .../>
 *       </transport>
 *     </content>
 *   </jingle>
 * 
 * Copyright (C) 2025 DinoX Project
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using Gee;
using Xmpp;

namespace Dino.Plugins.Rtp {

    /**
     * Represents a parsed SDP payload type
     */
    public class SdpPayloadType {
        public int id;
        public string name;
        public uint clockrate;
        public uint channels;
        public HashMap<string, string> parameters;
        public ArrayList<string> rtcp_fb;
        
        public SdpPayloadType() {
            parameters = new HashMap<string, string>();
            rtcp_fb = new ArrayList<string>();
        }
    }
    
    /**
     * Represents a parsed SDP media description
     */
    public class SdpMedia {
        public string media_type;  // audio, video
        public int port;
        public string protocol;    // UDP/TLS/RTP/SAVPF
        public ArrayList<int> payload_types;
        public ArrayList<SdpPayloadType> codecs;
        public string ice_ufrag;
        public string ice_pwd;
        public string fingerprint;
        public string fingerprint_hash;
        public string setup;       // active, passive, actpass
        public string mid;
        public ArrayList<SdpCandidate> candidates;
        public bool rtcp_mux;
        public string direction;   // sendrecv, sendonly, recvonly
        
        public SdpMedia() {
            payload_types = new ArrayList<int>();
            codecs = new ArrayList<SdpPayloadType>();
            candidates = new ArrayList<SdpCandidate>();
            rtcp_mux = false;
            direction = "sendrecv";
        }
    }
    
    /**
     * Represents a parsed ICE candidate
     */
    public class SdpCandidate {
        public string foundation;
        public int component;
        public string protocol;
        public int priority;
        public string ip;
        public int port;
        public string type;        // host, srflx, prflx, relay
        public string? raddr;
        public int? rport;
        public string? generation;
        public string? ufrag;
    }
    
    /**
     * SDP to Jingle Converter
     */
    public class SdpJingleConverter {
        
        private const string NS_JINGLE = "urn:xmpp:jingle:1";
        private const string NS_JINGLE_RTP = "urn:xmpp:jingle:apps:rtp:1";
        private const string NS_JINGLE_RTP_AUDIO = "urn:xmpp:jingle:apps:rtp:audio";
        private const string NS_JINGLE_RTP_VIDEO = "urn:xmpp:jingle:apps:rtp:video";
        private const string NS_JINGLE_ICE_UDP = "urn:xmpp:jingle:transports:ice-udp:1";
        private const string NS_JINGLE_DTLS = "urn:xmpp:jingle:apps:dtls:0";
        private const string NS_JINGLE_RTCP_FB = "urn:xmpp:jingle:apps:rtp:rtcp-fb:0";
        
        /**
         * Parse SDP string into media descriptions
         */
        public ArrayList<SdpMedia> parse_sdp(string sdp) {
            var media_list = new ArrayList<SdpMedia>();
            SdpMedia? current_media = null;
            
            string[] lines = sdp.split("\n");
            
            string session_ice_ufrag = "";
            string session_ice_pwd = "";
            string session_fingerprint = "";
            string session_fingerprint_hash = "";
            string session_setup = "";
            
            foreach (string raw_line in lines) {
                string line = raw_line.strip();
                if (line.length < 2) continue;
                
                string type = line.substring(0, 1);
                string value = line.substring(2);
                
                switch (type) {
                    case "m":
                        // New media section
                        if (current_media != null) {
                            // Apply session-level attributes if not set at media level
                            apply_session_attrs(current_media, session_ice_ufrag, session_ice_pwd,
                                               session_fingerprint, session_fingerprint_hash, session_setup);
                            media_list.add(current_media);
                        }
                        current_media = parse_media_line(value);
                        break;
                        
                    case "a":
                        // Attribute line
                        if (current_media != null) {
                            parse_media_attribute(current_media, value);
                        } else {
                            // Session-level attribute
                            if (value.has_prefix("ice-ufrag:")) {
                                session_ice_ufrag = value.substring(10);
                            } else if (value.has_prefix("ice-pwd:")) {
                                session_ice_pwd = value.substring(8);
                            } else if (value.has_prefix("fingerprint:")) {
                                var parts = value.substring(12).split(" ", 2);
                                if (parts.length == 2) {
                                    session_fingerprint_hash = parts[0];
                                    session_fingerprint = parts[1];
                                }
                            } else if (value.has_prefix("setup:")) {
                                session_setup = value.substring(6);
                            }
                        }
                        break;
                        
                    case "c":
                        // Connection info - parse if needed for ICE
                        break;
                }
            }
            
            // Add last media section
            if (current_media != null) {
                apply_session_attrs(current_media, session_ice_ufrag, session_ice_pwd,
                                   session_fingerprint, session_fingerprint_hash, session_setup);
                media_list.add(current_media);
            }
            
            return media_list;
        }
        
        private void apply_session_attrs(SdpMedia media, string ufrag, string pwd,
                                         string fp, string fp_hash, string setup) {
            if (media.ice_ufrag == null || media.ice_ufrag == "") media.ice_ufrag = ufrag;
            if (media.ice_pwd == null || media.ice_pwd == "") media.ice_pwd = pwd;
            if (media.fingerprint == null || media.fingerprint == "") media.fingerprint = fp;
            if (media.fingerprint_hash == null || media.fingerprint_hash == "") media.fingerprint_hash = fp_hash;
            if (media.setup == null || media.setup == "") media.setup = setup;
        }
        
        private SdpMedia parse_media_line(string value) {
            var media = new SdpMedia();
            
            // m=audio 9 UDP/TLS/RTP/SAVPF 111 0 8
            string[] parts = value.split(" ");
            if (parts.length >= 4) {
                media.media_type = parts[0];
                media.port = int.parse(parts[1]);
                media.protocol = parts[2];
                
                for (int i = 3; i < parts.length; i++) {
                    int pt = int.parse(parts[i]);
                    media.payload_types.add(pt);
                }
            }
            
            return media;
        }
        
        private void parse_media_attribute(SdpMedia media, string attr) {
            if (attr.has_prefix("rtpmap:")) {
                // a=rtpmap:111 opus/48000/2
                parse_rtpmap(media, attr.substring(7));
            } else if (attr.has_prefix("fmtp:")) {
                // a=fmtp:111 minptime=10;useinbandfec=1
                parse_fmtp(media, attr.substring(5));
            } else if (attr.has_prefix("rtcp-fb:")) {
                // a=rtcp-fb:96 nack
                parse_rtcp_fb(media, attr.substring(8));
            } else if (attr.has_prefix("ice-ufrag:")) {
                media.ice_ufrag = attr.substring(10);
            } else if (attr.has_prefix("ice-pwd:")) {
                media.ice_pwd = attr.substring(8);
            } else if (attr.has_prefix("fingerprint:")) {
                var parts = attr.substring(12).split(" ", 2);
                if (parts.length == 2) {
                    media.fingerprint_hash = parts[0];
                    media.fingerprint = parts[1];
                }
            } else if (attr.has_prefix("setup:")) {
                media.setup = attr.substring(6);
            } else if (attr.has_prefix("mid:")) {
                media.mid = attr.substring(4);
            } else if (attr.has_prefix("candidate:")) {
                parse_candidate(media, attr.substring(10));
            } else if (attr == "rtcp-mux") {
                media.rtcp_mux = true;
            } else if (attr == "sendrecv" || attr == "sendonly" || 
                       attr == "recvonly" || attr == "inactive") {
                media.direction = attr;
            }
        }
        
        private void parse_rtpmap(SdpMedia media, string value) {
            // 111 opus/48000/2
            string[] parts = value.split(" ", 2);
            if (parts.length < 2) return;
            
            int pt_id = int.parse(parts[0]);
            string[] codec_parts = parts[1].split("/");
            
            var pt = get_or_create_payload_type(media, pt_id);
            pt.name = codec_parts[0].up();
            if (codec_parts.length > 1) {
                pt.clockrate = (uint)int.parse(codec_parts[1]);
            }
            if (codec_parts.length > 2) {
                pt.channels = (uint)int.parse(codec_parts[2]);
            }
        }
        
        private void parse_fmtp(SdpMedia media, string value) {
            // 111 minptime=10;useinbandfec=1
            string[] parts = value.split(" ", 2);
            if (parts.length < 2) return;
            
            int pt_id = int.parse(parts[0]);
            var pt = get_or_create_payload_type(media, pt_id);
            
            string[] params = parts[1].split(";");
            foreach (string param in params) {
                string[] kv = param.split("=", 2);
                if (kv.length == 2) {
                    pt.parameters[kv[0].strip()] = kv[1].strip();
                }
            }
        }
        
        private void parse_rtcp_fb(SdpMedia media, string value) {
            // 96 nack
            // 96 nack pli
            // 96 goog-remb
            string[] parts = value.split(" ", 2);
            if (parts.length < 2) return;
            
            int pt_id = int.parse(parts[0]);
            var pt = get_or_create_payload_type(media, pt_id);
            pt.rtcp_fb.add(parts[1]);
        }
        
        private void parse_candidate(SdpMedia media, string value) {
            // foundation component protocol priority ip port typ type [raddr addr] [rport port]
            // Example: 1 1 UDP 2122260223 192.168.1.100 51820 typ host generation 0
            
            string[] parts = value.split(" ");
            if (parts.length < 8) return;
            
            var candidate = new SdpCandidate();
            candidate.foundation = parts[0];
            candidate.component = int.parse(parts[1]);
            candidate.protocol = parts[2];
            candidate.priority = int.parse(parts[3]);
            candidate.ip = parts[4];
            candidate.port = int.parse(parts[5]);
            // parts[6] should be "typ"
            candidate.type = parts[7];
            
            // Parse optional extensions
            for (int i = 8; i < parts.length - 1; i += 2) {
                switch (parts[i]) {
                    case "raddr":
                        candidate.raddr = parts[i + 1];
                        break;
                    case "rport":
                        candidate.rport = int.parse(parts[i + 1]);
                        break;
                    case "generation":
                        candidate.generation = parts[i + 1];
                        break;
                    case "ufrag":
                        candidate.ufrag = parts[i + 1];
                        break;
                }
            }
            
            media.candidates.add(candidate);
        }
        
        private SdpPayloadType get_or_create_payload_type(SdpMedia media, int id) {
            foreach (var pt in media.codecs) {
                if (pt.id == id) return pt;
            }
            var pt = new SdpPayloadType();
            pt.id = id;
            media.codecs.add(pt);
            return pt;
        }
        
        /**
         * Convert SDP to Jingle XML
         */
        public StanzaNode sdp_to_jingle(string sdp, string action, string session_id, 
                                         string initiator) {
            var media_list = parse_sdp(sdp);
            
            var jingle = new StanzaNode.build("jingle", NS_JINGLE);
            jingle.put_attribute("action", action);
            jingle.put_attribute("sid", session_id);
            jingle.put_attribute("initiator", initiator);
            
            foreach (var media in media_list) {
                var content = media_to_jingle_content(media);
                jingle.put_node(content);
            }
            
            return jingle;
        }
        
        private StanzaNode media_to_jingle_content(SdpMedia media) {
            var content = new StanzaNode.build("content", NS_JINGLE);
            content.put_attribute("creator", "initiator");
            content.put_attribute("name", media.mid ?? media.media_type);
            content.put_attribute("senders", direction_to_senders(media.direction));
            
            // RTP Description
            var description = new StanzaNode.build("description", NS_JINGLE_RTP);
            description.put_attribute("media", media.media_type);
            
            foreach (var codec in media.codecs) {
                var pt_node = new StanzaNode.build("payload-type", NS_JINGLE_RTP);
                pt_node.put_attribute("id", codec.id.to_string());
                pt_node.put_attribute("name", codec.name);
                pt_node.put_attribute("clockrate", codec.clockrate.to_string());
                if (codec.channels > 0 && codec.channels != 1) {
                    pt_node.put_attribute("channels", codec.channels.to_string());
                }
                
                // Parameters
                foreach (var entry in codec.parameters.entries) {
                    var param = new StanzaNode.build("parameter", NS_JINGLE_RTP);
                    param.put_attribute("name", entry.key);
                    param.put_attribute("value", entry.value);
                    pt_node.put_node(param);
                }
                
                // RTCP Feedback
                foreach (var fb in codec.rtcp_fb) {
                    var fb_node = new StanzaNode.build("rtcp-fb", NS_JINGLE_RTCP_FB);
                    string[] fb_parts = fb.split(" ", 2);
                    fb_node.put_attribute("type", fb_parts[0]);
                    if (fb_parts.length > 1) {
                        fb_node.put_attribute("subtype", fb_parts[1]);
                    }
                    pt_node.put_node(fb_node);
                }
                
                description.put_node(pt_node);
            }
            
            // RTCP-MUX
            if (media.rtcp_mux) {
                description.put_node(new StanzaNode.build("rtcp-mux", NS_JINGLE_RTP));
            }
            
            content.put_node(description);
            
            // ICE Transport
            var transport = new StanzaNode.build("transport", NS_JINGLE_ICE_UDP);
            if (media.ice_ufrag != null && media.ice_ufrag != "") {
                transport.put_attribute("ufrag", media.ice_ufrag);
            }
            if (media.ice_pwd != null && media.ice_pwd != "") {
                transport.put_attribute("pwd", media.ice_pwd);
            }
            
            // DTLS Fingerprint
            if (media.fingerprint != null && media.fingerprint != "") {
                var fingerprint = new StanzaNode.build("fingerprint", NS_JINGLE_DTLS);
                fingerprint.put_attribute("hash", media.fingerprint_hash);
                fingerprint.put_attribute("setup", media.setup);
                fingerprint.put_node(new StanzaNode.text(media.fingerprint));
                transport.put_node(fingerprint);
            }
            
            // ICE Candidates
            foreach (var cand in media.candidates) {
                var cand_node = candidate_to_jingle(cand);
                transport.put_node(cand_node);
            }
            
            content.put_node(transport);
            
            return content;
        }
        
        private StanzaNode candidate_to_jingle(SdpCandidate candidate) {
            var node = new StanzaNode.build("candidate", NS_JINGLE_ICE_UDP);
            node.put_attribute("foundation", candidate.foundation);
            node.put_attribute("component", candidate.component.to_string());
            node.put_attribute("protocol", candidate.protocol.down());
            node.put_attribute("priority", candidate.priority.to_string());
            node.put_attribute("ip", candidate.ip);
            node.put_attribute("port", candidate.port.to_string());
            node.put_attribute("type", candidate.type);
            
            if (candidate.raddr != null) {
                node.put_attribute("rel-addr", candidate.raddr);
            }
            if (candidate.rport != null) {
                node.put_attribute("rel-port", candidate.rport.to_string());
            }
            if (candidate.generation != null) {
                node.put_attribute("generation", candidate.generation);
            }
            
            return node;
        }
        
        private string direction_to_senders(string direction) {
            switch (direction) {
                case "sendrecv": return "both";
                case "sendonly": return "initiator";
                case "recvonly": return "responder";
                case "inactive": return "none";
                default: return "both";
            }
        }
        
        // ==================== Jingle to SDP ====================
        
        /**
         * Convert Jingle XML to SDP
         */
        public string jingle_to_sdp(StanzaNode jingle, bool is_offer) {
            var sb = new StringBuilder();
            
            // SDP Session Description
            sb.append("v=0\n");
            sb.append("o=- %lld 2 IN IP4 127.0.0.1\n".printf(get_monotonic_time()));
            sb.append("s=-\n");
            sb.append("t=0 0\n");
            sb.append("a=group:BUNDLE ");
            
            // Collect all content names for BUNDLE
            var contents = jingle.get_subnodes("content", NS_JINGLE);
            var bundle_names = new ArrayList<string>();
            foreach (var content in contents) {
                string name = content.get_attribute("name");
                if (name != null) {
                    bundle_names.add(name);
                }
            }
            sb.append(string.joinv(" ", bundle_names.to_array()));
            sb.append("\n");
            
            // Add media sections
            foreach (var content in contents) {
                string media_sdp = jingle_content_to_sdp(content, is_offer);
                sb.append(media_sdp);
            }
            
            return sb.str;
        }
        
        private string jingle_content_to_sdp(StanzaNode content, bool is_offer) {
            var sb = new StringBuilder();
            
            string name = content.get_attribute("name") ?? "0";
            string senders = content.get_attribute("senders") ?? "both";
            
            var description = content.get_subnode("description", NS_JINGLE_RTP);
            var transport = content.get_subnode("transport", NS_JINGLE_ICE_UDP);
            
            if (description == null) return "";
            
            string media_type = description.get_attribute("media") ?? "audio";
            
            // Collect payload types
            var payload_types = description.get_subnodes("payload-type", NS_JINGLE_RTP);
            var pt_ids = new ArrayList<string>();
            foreach (var pt in payload_types) {
                string id = pt.get_attribute("id");
                if (id != null) pt_ids.add(id);
            }
            
            // m= line
            sb.append(@"m=$(media_type) 9 UDP/TLS/RTP/SAVPF ");
            sb.append(string.joinv(" ", pt_ids.to_array()));
            sb.append("\n");
            
            sb.append("c=IN IP4 0.0.0.0\n");
            sb.append("a=rtcp:9 IN IP4 0.0.0.0\n");
            
            // ICE credentials
            if (transport != null) {
                string ufrag = transport.get_attribute("ufrag");
                string pwd = transport.get_attribute("pwd");
                if (ufrag != null) sb.append(@"a=ice-ufrag:$(ufrag)\n");
                if (pwd != null) sb.append(@"a=ice-pwd:$(pwd)\n");
                
                // DTLS fingerprint
                var fingerprint = transport.get_subnode("fingerprint", NS_JINGLE_DTLS);
                if (fingerprint != null) {
                    string hash = fingerprint.get_attribute("hash") ?? "sha-256";
                    string setup = fingerprint.get_attribute("setup") ?? "actpass";
                    string fp_value = fingerprint.get_string_content() ?? "";
                    sb.append(@"a=fingerprint:$(hash) $(fp_value)\n");
                    sb.append(@"a=setup:$(setup)\n");
                }
                
                // ICE candidates
                var candidates = transport.get_subnodes("candidate", NS_JINGLE_ICE_UDP);
                foreach (var cand in candidates) {
                    string cand_sdp = jingle_candidate_to_sdp(cand);
                    sb.append(@"a=$(cand_sdp)\n");
                }
            }
            
            sb.append(@"a=mid:$(name)\n");
            
            // Check for rtcp-mux
            if (description.get_subnode("rtcp-mux", NS_JINGLE_RTP) != null) {
                sb.append("a=rtcp-mux\n");
            }
            
            // Direction
            sb.append(@"a=$(senders_to_direction(senders))\n");
            
            // Payload type details
            foreach (var pt in payload_types) {
                string id = pt.get_attribute("id") ?? "0";
                string pt_name = pt.get_attribute("name") ?? "";
                string clockrate = pt.get_attribute("clockrate") ?? "8000";
                string channels = pt.get_attribute("channels");
                
                string rtpmap = @"$(id) $(pt_name)/$(clockrate)";
                if (channels != null && channels != "1") {
                    rtpmap += @"/$(channels)";
                }
                sb.append(@"a=rtpmap:$(rtpmap)\n");
                
                // Parameters (fmtp)
                var parameters = pt.get_subnodes("parameter", NS_JINGLE_RTP);
                if (parameters.size > 0) {
                    sb.append(@"a=fmtp:$(id) ");
                    var params = new ArrayList<string>();
                    foreach (var param in parameters) {
                        string pname = param.get_attribute("name");
                        string pvalue = param.get_attribute("value");
                        if (pname != null && pvalue != null) {
                            params.add(@"$(pname)=$(pvalue)");
                        }
                    }
                    sb.append(string.joinv(";", params.to_array()));
                    sb.append("\n");
                }
                
                // RTCP Feedback
                var rtcp_fbs = pt.get_subnodes("rtcp-fb", NS_JINGLE_RTCP_FB);
                foreach (var fb in rtcp_fbs) {
                    string fb_type = fb.get_attribute("type");
                    string fb_subtype = fb.get_attribute("subtype");
                    if (fb_type != null) {
                        string fb_line = @"$(id) $(fb_type)";
                        if (fb_subtype != null) {
                            fb_line += @" $(fb_subtype)";
                        }
                        sb.append(@"a=rtcp-fb:$(fb_line)\n");
                    }
                }
            }
            
            return sb.str;
        }
        
        private string jingle_candidate_to_sdp(StanzaNode candidate) {
            string foundation = candidate.get_attribute("foundation") ?? "1";
            string component = candidate.get_attribute("component") ?? "1";
            string protocol = candidate.get_attribute("protocol")?.up() ?? "UDP";
            string priority = candidate.get_attribute("priority") ?? "1";
            string ip = candidate.get_attribute("ip") ?? "0.0.0.0";
            string port = candidate.get_attribute("port") ?? "9";
            string type = candidate.get_attribute("type") ?? "host";
            
            var sb = new StringBuilder();
            sb.append(@"candidate:$(foundation) $(component) $(protocol) $(priority) $(ip) $(port) typ $(type)");
            
            string rel_addr = candidate.get_attribute("rel-addr");
            string rel_port = candidate.get_attribute("rel-port");
            if (rel_addr != null) sb.append(@" raddr $(rel_addr)");
            if (rel_port != null) sb.append(@" rport $(rel_port)");
            
            string generation = candidate.get_attribute("generation");
            if (generation != null) sb.append(@" generation $(generation)");
            
            return sb.str;
        }
        
        private string senders_to_direction(string senders) {
            switch (senders) {
                case "both": return "sendrecv";
                case "initiator": return "sendonly";
                case "responder": return "recvonly";
                case "none": return "inactive";
                default: return "sendrecv";
            }
        }
        
        // ==================== ICE Candidate Helpers ====================
        
        /**
         * Parse a single ICE candidate line and return Jingle XML
         */
        public StanzaNode parse_ice_candidate_to_jingle(string mid, int mline_index, 
                                                         string candidate_str) {
            var media = new SdpMedia();
            
            // Remove "candidate:" prefix if present
            string cand_value = candidate_str;
            if (cand_value.has_prefix("candidate:")) {
                cand_value = cand_value.substring(10);
            }
            
            parse_candidate(media, cand_value);
            
            if (media.candidates.size > 0) {
                return candidate_to_jingle(media.candidates[0]);
            }
            
            // Return empty candidate node on parse failure
            return new StanzaNode.build("candidate", NS_JINGLE_ICE_UDP);
        }
        
        /**
         * Convert Jingle candidate to SDP format
         */
        public string jingle_candidate_to_sdp_string(StanzaNode candidate) {
            return "candidate:" + jingle_candidate_to_sdp(candidate);
        }
    }
}
