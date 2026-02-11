# DinoX - Development Plan

> **Last Updated**: February 10, 2026
> **Current Release Line**: 0.9.9.x

This document is organized as a **chronological release timeline** first, followed by a **forward-looking roadmap**.

---

## Project Snapshot

| Metric | Status |
|--------|--------|
| **Release Line** | 0.9.9.x |
| **XEPs Implemented** | ~78 |
| **Languages** | 47 (~85% translated) |
| **Build Status** | Clean |
| **GTK/libadwaita** | GTK4 4.14, libadwaita 1.5 |

---

## Timeline (Recent Releases)

### v0.9.9.3 (Stability & Debug Cleanup)

- **CRITICAL Fix**: Resolved `dino_entities_file_transfer_get_mime_type: assertion 'self != NULL' failed` crash caused by dangling GObject bind_property bindings. Proper lifecycle management with unbind() in dispose().
- **Debug Output Cleanup**: Removed 57 leftover debug print/warning statements across the codebase.
- **Thumbnail Parsing**: Fixed SFS/thumbnail metadata parsing for incoming file transfers with XEP-0264 thumbnails.
- **OMEMO 1 + 2 Stabilization**: Continued stabilization of dual-protocol OMEMO support.

### v0.9.9.2 (Server Certificate Info)

- **Server Certificate Info (GitHub Issue #10)**: Account preferences now show TLS certificate details — status, issuer, validity period, and SHA-256 fingerprint. Pinned certificates can be removed from the UI.
- **App Icon Fix**: Fixed light/white app icon in AppImage and Flatpak (GResource SVG priority issue).
- **Menu Order**: Moved "Panic Wipe" to bottom of hamburger menu to prevent accidental activation.

### v0.9.9.1 (OMEMO 2 Support)

- **OMEMO 2 (XEP-0384 v0.8+)**: Full implementation of OMEMO 2 with backward compatibility to legacy OMEMO. Dual-stack: Legacy OMEMO + Modern OMEMO 2 for seamless migration.
- **SCE Envelope Layer (XEP-0420)**: Stanza Content Encryption used by OMEMO 2.
- **Crypto**: HKDF-SHA-256 / AES-256-CBC / HMAC-SHA-256 via libgcrypt.
- **HTTP File Transfer with Self-Signed Certificates**: All HTTP file operations now respect pinned certificates.

### v0.9.9.0 (Backup/Restore & Security)

- **Backup/Restore after Panic Wipe**: Fixed critical bug where restoring a backup after Panic Wipe failed due to password mismatch. Clear dialog now asks for backup's original password.
- **Backup Password Leak**: OpenSSL no longer passes passwords via command line. Passwords piped via stdin.

### v0.9.8.8 (Windows GStreamer & System Tray)

- **Windows GStreamer Plugins**: Fixed DLL loading failures. Auto-dependency detection now scans plugin subdirectories.
- **Windows OMEMO & RTP Plugins**: Fixed plugin loading failures by copying before dependency scan.
- **Windows UX**: No batch file needed, no terminal window, app icon embedded in .exe.
- **System Tray (Linux)**: Restored StatusNotifierItem systray with libdbusmenu. Platform-conditional implementation.

### v0.9.8.7 (SHA256 Checksums)

- **SHA256 Checksums**: All binary downloads now include SHA256 checksum files.
- **AppImage Filename**: Fixed missing version number in filenames.

### v0.9.8.6 (Certificate Pinning & Native ARM CI)

- **Certificate Pinning SQL Fix**: Fixed SQL syntax error in upsert query for pinning self-signed certificates.
- **Native ARM CI**: Switched aarch64 builds from QEMU emulation to native GitHub ARM64 runners (`ubuntu-24.04-arm`).

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
