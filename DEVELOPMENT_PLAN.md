# DinoX - Development Plan

> **Last Updated**: January 9, 2026
> **Current Release Line**: 0.9.6.x

This document is organized as a **chronological release timeline** first, followed by a **forward-looking roadmap**.

---

## Project Snapshot

| Metric | Status |
|--------|--------|
| **Release Line** | 0.9.6.x |
| **XEPs Implemented** | ~78 |
| **Languages** | 47 (100% translated) |
| **Build Status** | Clean |
| **GTK/libadwaita** | GTK4 4.14, libadwaita 1.5 |

---

## Timeline (Recent Releases)

### v0.9.6.0 (Sender Identity & Registration)

- **Sender Identity**: Explicit account selection for starting chats, joining/creating MUCs.
- **Registration**: In-Band Registration (XEP-0077) with CAPTCHA support.
- **UI**: Responsive MUC browser and creation dialogs.

### v0.9.5.0 (UX & MUC Avatars)

- **MUC Avatars**: Full XEP-0486 implementation including persistence, resizing (192px), and conversion.
- **UI Refinements**: Redesigned header bar, Status Menu moved to dedicated button with dynamic reachability colors.
- **Maintenance**: Deprecated "Help" button in favor of streamlined UI.

### Next Big Step: Tor Support

- **Network**: Implement Tor connection support (SOCKS5 proxy).
- **Privacy**: Allow connecting via Tor for enhanced anonymity (similar to Gajim).

### v0.9.4.0 (User Search Integration)

- **User Search**: Integrated Jabber User Directory Search (XEP-0055).
- **Backend**: Improved XEP-0004 Data Forms parser (support for `<item>`).
- **UI**: Refined "Start Conversation" dialog and placeholder screens.

### v0.9.3.0 (Full Local Encryption)

- **Full Local Encryption**: Transparent encryption for all local files (`files/`, `avatars/`, `stickers/`) using AES-256-GCM.
- **Secure Deletion**:
  - **Global History Deletion**: Option to delete conversation history for both parties (XEP-0424) in 1:1 chats.
  - **Smart Throttling**: Rate-limited retraction queue (5 msgs/sec) to prevent server disconnects/bans.
  - **Zero-Trace Shutdown**: Enforced cleanup of decrypted cache files (`~/.cache/dinox`) on application exit.
- **PGP Database Encryption**: Migrated `pgp.db` to SQLCipher.

### v0.9.2.0 (Encrypted File Sharing)

- **Encrypted File Upload**: Support for OMEMO-encrypted file sharing.
- **Compatibility**: Implemented `aesgcm://` scheme for Conversations/Monal/Gajim interoperability.
- **Standards**: Implemented XEP-0448 (Encryption for Stateless File Sharing).

### v0.9.1.0 (Privacy & Standards)

- **XEP Support**: vCard4 (XEP-0292), User Nickname (XEP-0172), vCard-temp (XEP-0054).
- **Privacy**: Translated privacy settings in 47 languages.
- **Fixes**: System tray icon persistence and clean shutdown.

### v0.8.6.15 (Map Preview)

- **Geo URI Support**: Inline map previews for `geo:` URIs with OpenStreetMap tiles and location markers.

### v0.8.6 (Messaging / expressiveness + packaging)

- **XEP-0449 Stickers**: end-to-end sticker support (`urn:xmpp:stickers:0`).
  - Receive/display, send, import packs via `xmpp:` PubSub links, publish packs to PEP, share URIs.
  - Preferences toggles for stickers and sticker animations.
  - Sticker chooser UX hardened (deferred reloads + explicit close button).
- **GitHub AppImage: media/audio reliability**
  - Bundle `gst-plugin-scanner` and recursively copy missing shared-library dependencies.
  - Avoid silently missing GStreamer capabilities (WebRTC/audio/video) due to incomplete bundling.
- **Notifications**: ensure notification sound plugin is enabled in release builds.

### v0.8.5 (Audio/Video call interoperability)

Goal: stable cross-client 1:1 calling with **Conversations (Android)** and **Monal (iOS)** while keeping DinoX’s media stack (GStreamer + libnice + DTLS-SRTP).

- **Interop profile**: prefer **ICE-UDP** + **DTLS-SRTP** only (no SDES-SRTP).
- **Codec baseline**: focus on **Opus** (audio) + **VP8** (video) for reliable negotiation.
- **Startup/teardown stability**: reduced startup artifacts and improved cleanup ordering.

### v0.8.5.x (Release engineering / packaging hotfixes)

Focus: make GitHub release assets reliable for end users (Flatpak/AppImage).

- **AppImage/Flatpak: libnice 0.1.23** bundled/built deterministically (avoids known issues with older libnice such as 0.1.21).
- **Flatpak: SQLCipher FTS4 enabled** to fix startup failure `no such module: fts4`.
- **Release notes**: hotfix tags reuse the base release notes (0.8.5) to keep the changelog readable.

### v0.8.4 (Video & audio)

- **WebRTC Video Calls**: support for VP8, VP9, and H.264 codecs.
- **ICE-TCP**: fallback connectivity for restrictive firewalls (RFC 6544).
- **Hardware Acceleration**: VA-API support for video encoding/decoding.

### v0.8.0 - v0.8.3 (Security, privacy, usability)

- **Database Encryption**: SQLCipher integration protecting local data.
- **Disappearing Messages**: auto-deletion timers (XEP-0424).
- **Path Traversal Fix**: hardened file transfer handling.
- **TLS Pinning**: trust management for self-signed certificates.
- **OpenPGP Management**: UI for key generation and management.
- **MUC Improvements**: password sync with bookmarks.

---

## Roadmap (Next Work)

### v0.9.4.0 (Call Quality & Performance)

Focus: Audio/Video improvements and performance optimization.

| Item | Description | Status |
|------|-------------|--------|
| **Call Quality UI** | Display packet loss, jitter, and resolution during calls | IN PROGRESS (backend ready) |
| **Echo Cancellation** | Fine-tune `webrtc-audio-processing` AEC settings across Linux audio setups | IN PROGRESS |
| **Spell Checking** | Re-enable spell checking (waiting for GTK4 GtkTextView support) | BLOCKED |
| **Performance** | Optimize memory usage for long-running sessions | TODO |

### Q2 2026: Modern XEPs (explicit TODOs)

| XEP | Feature | Implementation TODO |
|-----|---------|---------------------|
| **XEP-0357** | Push Notifications | Add/verify push enable/disable flow per account, server capability discovery, and end-to-end testing with common push components. |
| **XEP-0388** | SASL2 / FAST | Implement SASL2 negotiation and FAST token handling; ensure interaction with XEP-0198 stream management and session resumption remains correct. |
| **XEP-0386** | Bind 2 | Implement Bind2 negotiation and integrate with session establishment; verify multi-device and reconnection behavior. |

### Q3 2026: Advanced media

| Item | Description | Status |
|------|-------------|--------|
| **Screen Sharing** | Share desktop or windows during calls | TODO |
| **Whiteboard** | Collaborative drawing (protocol TBD) | CONCEPT |

### Q4 2026: 1.0 milestone

The milestone for a "feature complete" and rock-solid release.

**Requirements**:
- Zero P1 (crash) bugs.
- Memory usage < 200MB for 7-day sessions.
- Comprehensive security audit.
- 3+ months of beta testing without major regressions.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to set up your development environment and submit Pull Requests.

```bash
meson setup build
ninja -C build
./build/main/dinox
```

---

**Maintainer**: @rallep71
