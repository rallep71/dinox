# DinoX - Development Plan

> **Last Updated**: February 8, 2026
> **Current Release Line**: 0.9.8.x

This document is organized as a **chronological release timeline** first, followed by a **forward-looking roadmap**.

---

## Project Snapshot

| Metric | Status |
|--------|--------|
| **Release Line** | 0.9.8.x |
| **XEPs Implemented** | ~78 |
| **Languages** | 47 (~85% translated) |
| **Build Status** | Clean |
| **GTK/libadwaita** | GTK4 4.14, libadwaita 1.5 |

---

## Timeline (Recent Releases)

### v0.9.8.5 (Windows Port & OpenPGP Overhaul)

- **Windows Support**: DinoX is now available for Windows 10/11 (MSYS2/MINGW64). Automated CI/CD via GitHub Actions.
- **XEP-0027 (OpenPGP Legacy)**: Full implementation of legacy OpenPGP signing and encryption for maximum client interoperability.
- **OpenPGP Manager**: Unified key management UI for XEP-0373/0374 — key generation, selection, deletion, revocation. Automatic key exchange via PEP, no keyserver needed.
- **Self-Signed Certificate Trust**: TOFU certificate pinning for self-hosted XMPP servers.
- **PGP Key Revocation**: Revoke keys with XEP-0373 announcement to contacts.
- **Stability fixes**: Video freeze, file transfer crash guards, GStreamer plugins, hash verification.

### v0.9.8.0 (Audio & Usability Polish)

- **Adjustable Audio Gain**: Implemented manual audio gain control (Post-Processing) with slider ui to bypass WebRTC limits.
- **Input Device Selection**: Explicit selection of audio input device in settings.

### v0.9.7.0 (Stable Tor & Multi-Arch)

- **Network Reliability**: Fixed race conditions during Tor startup; implemented port waiting logic to prevent "Connection Refused".
- **Bundling**: Explicitly bundled `tor` and `obfs4proxy` in AppImage/Flatpak for "Out of the Box" functionality.
- **Infrastructure**: Added fully automated Aarch64 (ARM64) builds via QEMU CI pipelines.

### v0.9.6.0 (Sender Identity & Registration)

- **Sender Identity**: Explicit account selection for starting chats, joining/creating MUCs.
- **Registration**: In-Band Registration (XEP-0077) with CAPTCHA support.
- **UI**: Responsive MUC browser and creation dialogs.

### v0.9.5.0 (UX & MUC Avatars)

- **MUC Avatars**: Full XEP-0486 implementation including persistence, resizing (192px), and conversion.
- **UI Refinements**: Redesigned header bar, Status Menu moved to dedicated button with dynamic reachability colors.
- **Maintenance**: Deprecated "Help" button in favor of streamlined UI.

## Forward-Looking Roadmap

### Q2/Q3 2026: OMEMO 2 (urn:xmpp:omemo:2)

- **Compatibility**: Dual-stack implementation (Legacy OMEMO + Modern OMEMO 2) for seamless migration.
- **Security**: Improved ciphers, enhanced forward secrecy, and modern key agreement.
- **Interop**: Ensure compatibility with Conversations, Monal, and other clients adopting OMEMO 2.

### Q3/Q4 2026: macOS & BSD Porting

**Goal:** Bring DinoX to macOS and BSD (FreeBSD, OpenBSD).

- **macOS**: GTK4/libadwaita via Homebrew or MacPorts. Native .app bundle with code signing.
- **FreeBSD/OpenBSD**: Port via pkg/ports system. Adapt Tor/Obfs4proxy integration for BSD init systems.
- **CI**: Extend GitHub Actions with macOS runners; FreeBSD via cross-compilation or VM-based CI.

### Q2 2026: Modern XEPs

| XEP | Feature | Implementation TODO |
|-----|---------|---------------------|
| **XEP-0357** | Push Notifications | Add/verify push enable/disable flow per account, server capability discovery, and end-to-end testing with common push components. |
| **XEP-0388** | SASL2 / FAST | Implement SASL2 negotiation and FAST token handling; ensure interaction with XEP-0198 stream management and session resumption remains correct. |
| **XEP-0386** | Bind 2 | Implement Bind2 negotiation and integrate with session establishment; verify multi-device and reconnection behavior. |

### Q3 2026: Advanced media

| Item | Description | Status |
|------|-------------|--------|
| **Notification Sounds** | Cross-platform notification sounds for messages and calls. Currently only built in Flatpak (via libcanberra). Needs: enable by default on Linux, implement Windows-native backend (PlaySound/XAudio2), remove libcanberra hard dependency. | TODO |
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
