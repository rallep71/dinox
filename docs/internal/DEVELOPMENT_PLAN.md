# DinoX - Development Plan

> **Last Updated**: February 13, 2026
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

### v0.9.9.9 (MUC OMEMO, Notification Sounds, Call Ringtone)

- **MUC OMEMO**: Per-member trust management, key visibility, own keys section, double widget fetch fix, undecryptable warning fix for own JID.
- **OMEMO v1/v2 MUC Version Selection**: v2 only used when ALL recipients support it. Prevents v1 clients from losing messages.
- **OMEMO Stale Device Cleanup**: `cleanup_stale_own_devices()` on every connect -- publishes clean device list, removes stale bundles from server.
- **OMEMO Device List JID Filter**: Filters out PubSub service components and MUC room JIDs from device list processing.
- **OMEMO Cleanup on MUC Destroy**: Automatically removes OMEMO data stored under room JID when room is destroyed.
- **MUC Destroy Room**: Full cleanup chain with error handling. Right-click context menu for room owners.
- **Channel Dialog**: Fixed 5 bugs -- duplicate entries, missing lock icon, broken type check, invisible password field, stuck join button.
- **OMEMO MUC Encryption After Rejoin**: Fixed false "does not support encryption" by waiting for room features before checking.
- **OMEMO Solo/Self-Only Encryption**: Allows sending in MUC when only own device is present.
- **OMEMO Device Display**: Filters inactive devices, sorts by last activity, shows "Last seen" per device.
- **Status/Presence (6 Bugs)**: Persistence, systray sync, status dots, XA color distinction.
- **Avatar Preload Race**: Pre-load avatar hashes before signal connections.
- **Notification Sound Plugin**: Enabled by default on all Linux builds (native, Flatpak, AppImage) via libcanberra.
- **Call Ringtone**: Incoming calls play `phone-incoming-call` sound event in 3-second loop via libcanberra.
- **Double Ringtone Prevention**: Freedesktop notification uses `suppress-sound=true` so only the plugin controls audio.

### v0.9.9.8 (Ghost Messages & Avatar Sync)

- **Undecryptable OMEMO Ghost Messages**: Failed decryptions no longer stored as plaintext. Message body cleared on failure.
- **MAM Re-sync After History Clear**: MAM catchup ranges preserved to prevent archive re-sync.
- **Avatar Sync (6 Bugs)**: Fixed cache invalidation, re-fetch on reconnect, empty hash handling, PubSub item fetch, Base64 whitespace.

### v0.9.9.7 (Clipboard Fix)

- **Clipboard Paste Lag**: Fixed UI lag from unconditional `read_texture_async`. Now checks format before attempting read.

### v0.9.9.6 (OMEMO Session Conflict & GTK4 Stability)

- **OMEMO v1/v2 Session Conflict**: Fixed `SG_ERR_LEGACY_MESSAGE` failures from shared session store. v1 detects v4 sessions, v2 no longer creates sessions for v1 JIDs.
- **GTK4 Double Dispose Crash**: Added null guards and sentinel resets to prevent double-free in dispose().

### v0.9.9.5 (OMEMO Fingerprints & Device Labels)

- **OMEMO Fingerprint Display**: Standardized XEP-0384 format (8 groups of 8 hex digits).
- **OMEMO Device Labels**: Published for v1+v2, fetched from remote v2 device lists.
- **Server Cleanup on Account Deletion**: Full PubSub cleanup before XEP-0077 unregistration.

### v0.9.9.4 (OMEMO Device Management & Session Repair)

- **OMEMO Device Management**: PubSub device list management, device removal, detailed info dialog.
- **OMEMO Session Auto-Repair**: Detects and repairs broken sessions automatically.
- **OMEMO Session Thrashing Guard**: Cooldown period prevents rapid rebuild loops.
- **OMEMO Broken Bundle Handling**: Broken bundles counted as "lost" instead of "unknown".
- **OMEMO Bundle Retry**: Auto-retry every 10 minutes, up to 5 attempts.
- **Account Deletion**: Complete cascade delete across 25+ tables.
- **Clear Cache**: Purges 10 database cache tables plus filesystem cache.

### v0.9.9.3 (Stability & Debug Cleanup)

- **CRITICAL Fix**: Resolved `dino_entities_file_transfer_get_mime_type: assertion 'self != NULL' failed` crash caused by dangling GObject bind_property bindings. Proper lifecycle management with unbind() in dispose().
- **Debug Output Cleanup**: Removed 57 leftover debug print/warning statements across the codebase.
- **Thumbnail Parsing**: Fixed SFS/thumbnail metadata parsing for incoming file transfers with XEP-0264 thumbnails.
- **OMEMO 1 + 2 Stabilization**: Continued stabilization of dual-protocol OMEMO support.

### v0.9.9.2 (Server Certificate Info)

- **Server Certificate Info (GitHub Issue #10)**: Account preferences now show TLS certificate details -- status, issuer, validity period, and SHA-256 fingerprint. Pinned certificates can be removed from the UI.
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
- **OpenPGP Manager**: Unified key management UI for XEP-0373/0374 -- key generation, selection, deletion, revocation. Automatic key exchange via PEP, no keyserver needed.
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
| **Notification Sounds (Windows)** | Linux notification sounds (messages + call ringtone) are complete via libcanberra. Windows needs a native backend (PlaySound/XAudio2) since libcanberra is not available. | TODO |
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
