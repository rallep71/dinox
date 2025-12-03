# WebRTC Integration Prototype for DinoX

## Overview

This prototype replaces the custom GStreamer RTP pipeline with GStreamer's `webrtcbin` element.
This approach provides native WebRTC compatibility with other clients like Conversations (Android),
Monal (iOS/macOS), and browser-based WebRTC implementations.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        DinoX RTP Plugin                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────────┐     ┌───────────────────────────────────┐    │
│  │  Jingle Session  │────▶│    SdpJingleConverter             │    │
│  │  (XMPP)          │◀────│    - SDP → Jingle                 │    │
│  │                  │     │    - Jingle → SDP                 │    │
│  └──────────────────┘     │    - ICE Candidate conversion     │    │
│           │               └───────────────────────────────────┘    │
│           │                           │                             │
│           ▼                           ▼                             │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │              WebRTCSessionManager                           │    │
│  │  - Manages WebRTC sessions                                  │    │
│  │  - Bridges Jingle signaling with WebRTC                     │    │
│  │  - Handles session lifecycle                                │    │
│  └────────────────────────────────────────────────────────────┘    │
│           │                                                         │
│           ▼                                                         │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │              WebRTCStream                                   │    │
│  │  - Uses GStreamer webrtcbin element                         │    │
│  │  - Automatic codec negotiation (VP9, VP8, H264, Opus)       │    │
│  │  - Built-in DTLS-SRTP encryption                            │    │
│  │  - ICE candidate gathering                                  │    │
│  └────────────────────────────────────────────────────────────┘    │
│           │                                                         │
│           ▼                                                         │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │              GStreamer Pipeline                             │    │
│  │                                                             │    │
│  │   videosrc ──▶ ┌──────────┐                                │    │
│  │                │          │ ──▶ network ──▶ remote peer    │    │
│  │   audiosrc ──▶ │webrtcbin │                                │    │
│  │                │          │ ◀── network ◀── remote peer    │    │
│  │   videosink◀── └──────────┘                                │    │
│  │   audiosink◀──                                              │    │
│  │                                                             │    │
│  └────────────────────────────────────────────────────────────┘    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Benefits of webrtcbin

1. **Native Codec Negotiation**: webrtcbin automatically negotiates codecs (VP9, VP8, H264, Opus)
   based on what both peers support. No manual pipeline configuration needed.

2. **Built-in DTLS-SRTP**: Encryption is handled automatically by webrtcbin.

3. **ICE Integration**: ICE candidate gathering and trickle ICE are handled natively.

4. **RTCP-MUX**: RTP and RTCP multiplexing is automatic.

5. **Compatibility**: Works with standard WebRTC implementations (Conversations, Monal, browsers).

## Files

| File | Purpose |
|------|---------|
| `webrtc_stream.vala` | Core WebRTC stream using webrtcbin element |
| `webrtc_session_manager.vala` | Session management and Jingle integration |
| `sdp_jingle_converter.vala` | SDP ↔ Jingle conversion (inspired by Monal) |
| `gstreamer-webrtc-1.0.vapi` | Vala bindings for GStreamer WebRTC |

## Key Differences from Current Implementation

### Current (Custom Pipelines)

```vala
// Current approach: Manual pipeline creation
pipe = new Gst.Pipeline("rtp-pipeline");
rtpbin = Gst.ElementFactory.make("rtpbin", "rtpbin");
// Manual vp9enc, vp9dec, opus encoder/decoder...
// Manual SRTP encryption
// Manual ICE candidate handling
```

### New (webrtcbin)

```vala
// New approach: webrtcbin handles everything
pipe = new Gst.Pipeline("webrtc-pipeline");
webrtcbin = Gst.ElementFactory.make("webrtcbin", "webrtc");
webrtcbin.set_property("bundle-policy", "max-bundle");
webrtcbin.set_property("stun-server", "stun://stun.l.google.com:19302");

// Add transceivers for audio/video
Signal.emit_by_name(webrtcbin, "add-transceiver", direction, caps);

// Connect signals for SDP/ICE
webrtcbin.connect("on-negotiation-needed", ...);
webrtcbin.connect("on-ice-candidate", ...);
webrtcbin.connect("pad-added", ...);
```

## Integration Steps

### Step 1: Basic Integration

1. Keep the existing `stream.vala` for backward compatibility
2. Add new `WebRTCStream` as alternative implementation
3. Use feature flag or configuration to switch between implementations

### Step 2: Jingle Integration

1. Modify `Module` to use `WebRTCSessionManager`
2. Convert incoming Jingle session-initiate to SDP
3. Set remote description on webrtcbin
4. Convert local SDP to Jingle for session-accept

### Step 3: ICE Integration

1. Collect local ICE candidates from webrtcbin
2. Convert to Jingle transport-info
3. Convert incoming transport-info to SDP candidates
4. Add to webrtcbin

## Example Usage

```vala
// Create session manager
var manager = new WebRTCSessionManager(plugin);

// Create outgoing call
var session = manager.create_session(peer_jid, with_video: true);

// Handle local SDP (send to peer via Jingle)
session.local_description_ready.connect((type, jingle_node) => {
    // Send jingle_node to peer
    send_jingle_iq(peer, jingle_node);
});

// Handle local ICE candidates
session.local_candidate_ready.connect((mid, candidate_node) => {
    // Send transport-info to peer
    send_transport_info(peer, mid, candidate_node);
});

// Start the call
session.start(audio_device, video_device);

// Handle incoming session-accept
manager.handle_session_accept(session_id, jingle_node);

// Handle incoming ICE candidates
manager.handle_transport_info(session_id, jingle_node);
```

## Dependencies

- `gstreamer-webrtc-1.0` (from gst-plugins-bad)
- `gstreamer-sdp-1.0`
- Existing GStreamer dependencies

## Testing

1. Test with Conversations (Android)
2. Test with Monal (iOS/macOS)  
3. Test with browser-based WebRTC (if available)

## Known Limitations

1. **SDP-Jingle Conversion Complexity**: Some edge cases in SDP ↔ Jingle conversion
   may require refinement based on testing with different clients.

2. **SRTP Key Exchange**: webrtcbin uses DTLS-SRTP. Some older SRTP implementations
   may need compatibility handling.

3. **Custom Codec Parameters**: Some custom parameters (like RTX) may need
   additional handling in the converter.

## Next Steps

1. **Test Build**: Compile and verify no errors
2. **Unit Tests**: Test SDP ↔ Jingle conversion
3. **Integration Tests**: Test with real XMPP calls
4. **Migration**: Gradually replace old Stream with WebRTCStream
