# DinoX - Development Plan

> **Last Updated**: December 3, 2025
> **Version**: 0.8.4

---

## Current Status

| Metric | Status |
|--------|--------|
| **Version** | v0.8.4 |
| **XEPs Implemented** | ~70 |
| **Languages** | 47 (100% translated) |
| **Build Status** | Clean |
| **GTK/libadwaita** | GTK4 4.14, libadwaita 1.5 |

---

## Recently Completed (v0.8.0 - v0.8.4)

### Video & Audio (v0.8.4)
- **WebRTC Video Calls**: Full support for VP8, VP9, and H.264 codecs.
- **ICE-TCP**: Fallback connectivity for restrictive firewalls (RFC 6544).
- **Hardware Acceleration**: VA-API support for video encoding/decoding.

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

Focus on polishing the new video call features and general app stability.

| Feature | Description | Status |
|---------|-------------|--------|
| **Call Quality UI** | Display packet loss, jitter, and resolution during calls | IN PROGRESS (Backend Ready) |
| **Echo Cancellation** | Fine-tune WebRTC AEC settings for Linux audio subsystems | IN PROGRESS |
| **Spell Checking** | Re-enable spell checking (waiting for GTK4 GtkTextView support) | BLOCKED |
| **Performance** | Optimize memory usage for long-running sessions | TODO |

### Phase 10: Modern XEPs & Engagement (Q2 2026)

Adding features that make chatting more expressive and mobile-friendly.

| XEP | Feature | Status |
|-----|---------|--------|
| **XEP-0449** | **Stickers**: Support for sticker packs and sending | TODO |
| **XEP-0357** | **Push Notifications**: Better integration for mobile/sleep states | TODO |
| **XEP-0388** | **SASL2 / FAST**: Faster authentication and stream resumption | TODO |
| **XEP-0386** | **Bind 2**: Improved multi-device handling | TODO |

### Phase 11: Advanced Media & Collaboration (Q3 2026)

Expanding WebRTC capabilities beyond 1:1 calls.

| Feature | Description | Status |
|---------|-------------|--------|
| **Screen Sharing** | Share desktop or specific windows during calls | TODO |
| **Group Calls** | MUJI (XEP-0272) support for 3+ participants | PLANNED |
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
