# DinoX - Development Plan

> **Last Updated**: December 19, 2025
> **Version**: 0.8.6

---

## Current Status

| Metric | Status |
|--------|--------|
| **Version** | v0.8.6 |
| **XEPs Implemented** | ~70 |
| **Languages** | 47 (100% translated) |
| **Build Status** | Clean |
| **GTK/libadwaita** | GTK4 4.14, libadwaita 1.5 |

---

## Recently Completed (v0.8.0 - v0.8.6)

### Video & Audio (v0.8.4)
- **WebRTC Video Calls**: Full support for VP8, VP9, and H.264 codecs.
- **ICE-TCP**: Fallback connectivity for restrictive firewalls (RFC 6544).
- **Hardware Acceleration**: VA-API support for video encoding/decoding.

### Audio/Video call interoperability (v0.8.5)

Goal: stable cross-client 1:1 calling with **Conversations (Android)** and **Monal (iOS)** while keeping DinoX’s media stack (GStreamer + libnice + DTLS-SRTP).

- **Interop profile**: prefer **ICE-UDP** + **DTLS-SRTP** only (no SDES-SRTP).
- **Codec baseline**: focus on **Opus** (audio) + **VP8** (video) for reliable negotiation.
- **Startup/teardown stability**: reduced startup artifacts and improved cleanup ordering.

### Release engineering / packaging hotfixes (v0.8.5.x)

Focus: make GitHub release assets reliable for end users (Flatpak/AppImage).

- **AppImage/Flatpak: libnice 0.1.23** bundled/built deterministically (avoids known issues with older libnice such as 0.1.21).
- **Flatpak: SQLCipher FTS4 enabled** to fix startup failure `no such module: fts4`.
- **Release notes**: hotfix tags reuse the base release notes (0.8.5) to keep the changelog readable.

### Messaging / expressiveness (v0.8.6)

- **XEP-0449 Stickers**: end-to-end sticker support (`urn:xmpp:stickers:0`).
	- Receive/display, send, import packs via `xmpp:` PubSub links, publish packs to PEP, share URIs.
	- Preferences toggles for stickers and sticker animations.
	- Sticker chooser UX hardened (deferred reloads + explicit close button).

### Packaging robustness (v0.8.6)

- **GitHub AppImage: media/audio reliability**
	- Bundle `gst-plugin-scanner` and recursively copy missing shared-library dependencies.
	- Avoid silently missing GStreamer capabilities (WebRTC/audio/video) due to incomplete bundling.
- **Notifications**: ensure notification sound plugin is enabled in release builds.

### Security & Privacy (v0.8.2 - v0.8.3)
- **Database Encryption**: Full SQLCipher integration protecting local data.
- **Disappearing Messages**: Auto-deletion timers (XEP-0424).
- **Path Traversal Fix**: Hardened file transfer handling.
- **TLS Pinning**: Trust management for self-signed certificates.

### Usability (v0.8.0 - v0.8.1)
- **OpenPGP Management**: New UI for key generation and management.
- **MUC Improvements**: Password sync with bookmarks.

---

## Roadmap

### Phase 9: Refinement & Quality (Q1 2026)

Focus on polishing call interoperability and general app stability.

| Feature | Description | Status |
|---------|-------------|--------|
| **Call Quality UI** | Display packet loss, jitter, and resolution during calls | IN PROGRESS (Backend Ready) |
| **Echo Cancellation** | Fine-tune `webrtc-audio-processing` AEC settings for Linux audio subsystems | IN PROGRESS |
| **Spell Checking** | Re-enable spell checking (waiting for GTK4 GtkTextView support) | BLOCKED |
| **Performance** | Optimize memory usage for long-running sessions | TODO |
| **Encrypted Local Attachments (Optional)** | Optionally store cached/downloaded attachments encrypted at rest (separate from SQLCipher DB encryption) | TODO |

### Phase 10: Modern XEPs & Engagement (Q2 2026)

Adding features that make chatting more expressive and mobile-friendly.

| XEP | Feature | Status |
|-----|---------|--------|
| **XEP-0357** | **Push Notifications**: Better integration for mobile/sleep states | TODO |
| **XEP-0388** | **SASL2 / FAST**: Faster authentication and stream resumption | TODO |
| **XEP-0386** | **Bind 2**: Improved multi-device handling | TODO |

### Phase 11: Advanced Media & Collaboration (Q3 2026)

Expanding calling capabilities beyond 1:1 calls.

| Feature | Description | Status |
|---------|-------------|--------|
| **Screen Sharing** | Share desktop or specific windows during calls | TODO |
| **Group Calls** | MUJI (XEP-0272) support for 3+ participants | IMPLEMENTED |
| **Whiteboard** | Collaborative drawing (XEP-0284 or similar) | CONCEPT |

### Phase 12: 1.0 Release (Q4 2026)

The milestone for a "Feature Complete" and rock-solid release.

**Requirements**:
- Zero P1 (Crash) bugs.
- Memory usage < 200MB for 7-day sessions.
- Comprehensive security audit.
- 3+ months of beta testing without major regressions.

---

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for details on how to set up your development environment and submit Pull Requests.

```bash
# Quick Start
meson setup build
ninja -C build
./build/main/dinox
```

---

**Maintainer**: @rallep71
