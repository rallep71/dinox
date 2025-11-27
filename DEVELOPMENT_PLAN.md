# DinoX - Development Plan

> **Fork Status**: Modern XMPP client - Independent development branch of [dino/dino](https://github.com/dino/dino)  
> **Last Updated**: November 27, 2025
> **Version**: 0.6.5.4
> **Original Repository**: https://github.com/dino/dino (572 open issues)

---

## Quick Links

- [Build Instructions](docs/BUILD.md)
- [Release Guide](docs/RELEASE.md)
- [Architecture Guide](docs/ARCHITECTURE.md)
- [XMPP Extensions Support](docs/XEP_SUPPORT.md)
- [MUJI Group Calls Guide](docs/MUJI_GROUP_CALLS.md)
- [MUJI Improvements Plan](docs/MUJI_IMPROVEMENTS.md)
- [MUC Improvements Plan](MUC_IMPROVEMENT_PLAN.md)
- [Database Schema](docs/DATABASE_SCHEMA.md)
- [Contributing Guidelines](docs/CONTRIBUTING.md)

---

## Mission Statement

DinoX addresses the slow development pace of the original Dino XMPP client while maintaining full XMPP protocol compliance. We focus on:

1. **Stability First** - Fix critical crashes, data loss, and memory leaks
2. **Modern UX** - Implement missing features users expect in 2025
3. **Performance** - Optimize database, reduce memory footprint
4. **Community-Driven** - Transparent development, fast issue response

---

## Current Status (November 27, 2025)

| Metric | Status | Details |
|--------|--------|---------|
| **Version** | [OK] **v0.6.5.4** | Latest stable release |
| **XEPs Implemented** | [OK] 60+ | One of most compliant XMPP clients |
| **Database Schema** | [OK] **v32** | Custom server + history clear + background mode |
| **Build Status** | [OK] **Clean** | 0 compiler warnings, 0 errors, 541 targets |
| **Code Quality** | [OK] **High** | Async/Error safety enforced, WeakMap null checks |
| **GTK/libadwaita** | [OK] **Modern** | GTK4 4.14.5, libadwaita 1.5, 0 deprecation warnings |
| **Memory Leaks** | [OK] **Fixed** | MAM cleanup, GStreamer resource handling |
| **Platform Support** | [WARNING] **Linux Only** | Desktop focus (GNOME/KDE) |

### [DONE] Completed Features (2025)

| Feature | Version | Upstream Issue | Status |
|---------|---------|----------------|--------|
| **System Tray** | v0.6.0 | [#98](https://github.com/dino/dino/issues/98) (108) | [DONE] Complete |
| **Background Mode Toggle** | v0.6.5.4 | [#299](https://github.com/dino/dino/issues/299) (54) | [DONE] Complete |
| **Custom Server Settings** | v0.6.1 | [#115](https://github.com/dino/dino/issues/115) (26) | [DONE] Complete |
| **Delete Conversation History** | v0.6.2 | [#472](https://github.com/dino/dino/issues/472) | [DONE] Complete |
| **Contact Management Suite** | v0.6.2 | Multiple | [DONE] Complete |
| **Voice Messages (AAC/m4a)** | v0.6.4 | Interop | [DONE] Complete |
| **Video Player (H.264/HEVC)** | v0.6.5 | Stability | [DONE] Complete |
| **Message Retraction (XEP-0424)** | v0.6.3 | Protocol | [DONE] Complete |
| **MUC Invitations** | v0.6.0 | XEP-0045/0249 | [DONE] Complete |
| **MUJI Group Calls Phase 1** | v0.6.5.3 | XEP-0272 | [DONE] Complete |
| **Desktop Notifications Fix** | v0.6.5.4 | Critical bug | [DONE] Fixed |

---

## Development History

### [DONE] Phase 1: Critical Stability (v0.6.0 - Nov 2025)

**Goal**: Make Dino rock-solid for daily use

**Completed**:
- [DONE] [#1764](https://github.com/dino/dino/issues/1764) - File Transfer segfault on upload error
- [DONE] [#1766](https://github.com/dino/dino/issues/1766) - Memory leak (RAM grows to GB over days)
- [DONE] [#1746](https://github.com/dino/dino/issues/1746) - MAM/Carbon messages lost
- [DONE] [#1779](https://github.com/dino/dino/issues/1779) - Long messages truncated

**Status**: [DONE] **COMPLETED** (November 19, 2025)

---

### [DONE] Phase 2: Codebase Modernization (v0.6.1 - Nov 2025)

**Goal**: Eliminate technical debt, achieve clean build

**Completed**:
- [DONE] Unhandled errors fixed (try/catch blocks everywhere)
- [DONE] Async correctness enforced (explicit `.begin` syntax)
- [DONE] 50+ compiler warnings eliminated
- [DONE] VAPI syntax updated (gnutls, libgcrypt)
- [DONE] WeakMap null safety improved
- [DONE] GValueArray deprecation fixed (RTP plugin)

**Status**: [DONE] **COMPLETED** (November 21, 2025)

---

### [DONE] Phase 3: Audio & Interaction Polish (v0.6.4 - Nov 2025)

**Goal**: Fix audio compatibility and message interaction

**Completed**:
- [DONE] Audio format switch to m4a/AAC (iOS/Android compatible)
- [DONE] Persistent message deletion (no reappearance on restart)
- [DONE] File deletion context menu for all file types
- [DONE] Quote widget right-click fix
- [DONE] Empty message prevention
- [DONE] Zombie process fix (GStreamer cleanup)

**Status**: [DONE] **COMPLETED** (November 23, 2025)

---

### [DONE] Phase 4: Video Playback & Flatpak (v0.6.5 - Nov 2025)

**Goal**: Robust inline video playback

**Completed**:
- [DONE] Video player widget (Gtk.AspectFrame + Gtk.MediaFile)
- [DONE] Layout stability (no chat view collapse)
- [DONE] Aspect ratio fix (16:9 enforcement)
- [DONE] Flatpak codecs (ffmpeg-full extension for H.264/HEVC)
- [DONE] SFS fixes for MUC private messages
- [DONE] Video/audio player fixes for private conversations

**Status**: [DONE] **COMPLETED** (November 24, 2025)

---

### [DONE] Phase 5: MUJI Group Calls Phase 1 (v0.6.5.3 - Nov 2025)

**Goal**: Make MUJI discoverable and user-friendly

**Completed**:
- [DONE] Participant list sidebar during group calls
- [DONE] Private room creation checkbox (auto-config)
- [DONE] Private room indicator ( icon in conversation list)
- [DONE] MUC server warning dialog
- [DONE] Group call button only visible for MUC
- [DONE] Entity capabilities hash mismatch fix (improves MUJI detection)

**Backend**: [DONE] Complete (XEP-0272 fully implemented)  
**UI Phase 1**: [DONE] Complete  
**Testing**: [WARNING] **Not tested with 3+ participants yet!**

**Status**: [DONE] **COMPLETED** (November 25, 2025)

**See**: [MUJI_GROUP_CALLS.md](docs/MUJI_GROUP_CALLS.md), [MUJI_IMPROVEMENTS.md](docs/MUJI_IMPROVEMENTS.md)

---

### [DONE] Phase 6: Background Mode & Notifications (v0.6.5.4 - Nov 2025)

**Goal**: Configurable quit behavior and reliable notifications

**Completed**:
- [DONE] Background Mode Toggle in Preferences → General
  - ON (default): Window closes to systray, app keeps running
  - OFF: Window close triggers application quit
- [DONE] Systray Quit menu with proper XMPP disconnect
- [DONE] Notification system deadlock fix (register_notification_provider)
- [DONE] Flatpak exit handling (Process.exit(0) for clean termination)

**Status**: [DONE] **COMPLETED** (November 27, 2025)

---

##  Roadmap - What's Next

### [TODO] Phase 7: MUC Administration (v0.6.6 - Dec 2025)

**Goal**: Complete MUC management features

| Priority | Feature | Complexity | Status |
|----------|---------|------------|--------|
| [DONE] | **MUC Invitations** | Easy | [DONE] **DONE** |
| P1 | **Affiliation Management UI** | Medium | [TODO] TODO |
| P2 | **Room Destruction** | Easy | [TODO] TODO |

**MUC Invitations** [DONE] **ALREADY IMPLEMENTED**:
- [DONE] Available via **Occupant Menu** (user icon in titlebar)
- [DONE] "Invite" button opens contact selection dialog
- [DONE] Backend: `MucManager.invite()` fully functional
- [DONE] UI: `main/src/ui/occupant_menu/view.vala` - Complete implementation
- [DONE] Also prepared in conversation menu (currently commented out)

**Implementation Details**:
- `main/src/ui/occupant_menu/view.vala:269` - `on_invite_clicked()`
- `main/src/ui/conversation_titlebar/menu_entry.vala:91` - Alternative entry point (commented)
- `libdino/src/service/muc_manager.vala:230` - `invite()` method
- Supports both XEP-0045 (Mediated) and XEP-0249 (Direct) invitations

**See**: [MUC_IMPROVEMENT_PLAN.md](MUC_IMPROVEMENT_PLAN.md) for details

**Target**: End of December 2025

---

### [TODO] Phase 8: MUJI Group Calls Phase 2 (v0.6.7 - Q1 2026)

**Goal**: Enhance group call experience

| Priority | Feature | Complexity | Status |
|----------|---------|------------|--------|
| P1 | **Individual Volume Controls** | Medium | [TODO] TODO |
| P2 | **Call Quality Indicators** | Medium | [TODO] TODO |
| P2 | **Better Error Messages** | Easy | [TODO] TODO |
| P3 | **Speaking Indicator** | Hard | [DEFERRED] DEFERRED |

**Speaking Indicator**: Postponed to avoid breaking working 1:1 calls

**Critical**: 
- [WARNING] **MUJI needs testing with 3+ participants!**
- [WARNING] **Performance unknown with 5+ peers**

**See**: [MUJI_IMPROVEMENTS.md](docs/MUJI_IMPROVEMENTS.md) for roadmap

**Target**: End of February 2026

---

### [TODO] Phase 9: Critical Bug Fixes (v0.7.0 - Q1 2026)

**Goal**: Fix remaining P1 bugs

| Priority | Issue | Component | Complexity | Status |
|----------|-------|-----------|------------|--------|
| P1 | [#1559](https://github.com/dino/dino/issues/1559) | Echo Cancellation | Hard | [TODO] TODO |
| P1 | [#57](https://github.com/dino/dino/issues/57) | Self-signed Certs | Medium | [TODO] TODO |
| P2 | [#1380](https://github.com/dino/dino/issues/1380) | Spell Checking | Medium | [TODO] TODO |

**Files to modify**:
- `plugins/rtp/src/device/` - Echo cancellation
- `xmpp-vala/src/core/` - Certificate validation
- GTK4 spell checking integration

**Target**: End of March 2026

---

### [TODO] Phase 10: UX Polish (v0.7.5 - Q2 2026)

**Goal**: Smooth, polished experience

| Priority | Issue | Feature | Complexity | Status |
|----------|-------|---------|------------|--------|
| P2 | [#1769](https://github.com/dino/dino/issues/1769) | Chat Scroll Fix | Medium | [TODO] TODO |
| P2 | [#1752](https://github.com/dino/dino/issues/1752) | Dark Mode (no restart) | Easy | [TODO] TODO |
| P2 | [#1787](https://github.com/dino/dino/issues/1787) | Better Notifications | Medium | [TODO] TODO |
| P3 | [#1776](https://github.com/dino/dino/issues/1776) | Emoji Reactions | Medium | [TODO] TODO |

**Target**: End of April 2026

---

### [TODO] Phase 11: Modern XEP Support (v0.8.0 - Q2 2026)

**Goal**: Support latest XMPP standards

| Priority | XEP | Feature | Complexity | Status |
|----------|-----|---------|------------|--------|
| P1 | XEP-0388 | SASL2/FAST Auth | Hard | [TODO] TODO |
| P1 | XEP-0357 | Push Notifications | Hard | [TODO] TODO |
| P2 | XEP-0449 | Stickers | Medium | [TODO] TODO |
| P3 | - | Export/Import | Medium | [TODO] TODO |

**New files to create**:
- `xmpp-vala/src/module/xep/0388_sasl2.vala`
- `xmpp-vala/src/module/xep/0357_push.vala`
- `xmpp-vala/src/module/xep/0449_stickers.vala`

**Target**: End of June 2026

---

###  Phase 12: Platform Expansion (v0.9.0 - Q3 2026)

**Goal**: Windows support and packaging

| Priority | Feature | Complexity | Status |
|----------|---------|------------|--------|
| P2 | Windows Native Port | Very Hard |  TODO |
| P3 | Android (via GTK4) | Very Hard |  TODO |
| P3 | macOS (via GTK4) | Hard |  TODO |

**Target**: End of August 2026

---

###  Phase 13: 1.0 Stable Release (Q4 2026 - v1.0.0)

**Goal**: Production-ready, stable API

**Requirements**:
- [DONE] Zero known crash bugs
- [DONE] Memory usage <200MB for 7-day sessions
- [DONE] 90%+ test coverage for critical paths
- [DONE] Complete documentation
- [DONE] Performance benchmarks established
- [DONE] Accessibility audit passed

**Target**: October 2026

---

## Issue Backlog

### Upstream Issues Statistics

| Metric | Count | Notes |
|--------|-------|-------|
| **Total Upstream** | 572 | github.com/dino/dino |
| **Fixed by DinoX** | 15+ | Stability, UX, Features |
| **Remaining** | ~557 | Prioritized by impact |

### Issue Categories

| Category | Count | Top Priority |
|----------|-------|--------------|
|  **Bugs** | ~200 | Crashes, data loss |
|  **Features** | ~250 | UX improvements |
|  **XEPs** | ~50 | Protocol updates |
|  **UI/UX** | ~40 | Interface polish |
|  **Platform** | ~15 | Windows, mobile |
|  **Security** | ~13 | Encryption, privacy |

---

## XEP Protocol Compliance

**Total XEPs Implemented**: 60+

See [XEP_SUPPORT.md](docs/XEP_SUPPORT.md) for full list.

### Implementation Status

| Status | Count | Percentage |
|--------|-------|------------|
| [DONE] **Full (Backend + UI)** | ~32 | 53% |
|  **Backend Only** | ~24 | 40% |
| [WARNING] **Partial** | ~4 | 7% |

### Recently Added

- [DONE] XEP-0191 (Blocking Command) - Full UI
- [DONE] XEP-0272 (MUJI) - Group calls with UI
- [DONE] XEP-0424 (Message Retraction) - Full UI
- [DONE] XEP-0425 (Message Moderation) - Backend complete

---

## Testing Status

### [DONE] Tested & Stable

- 1:1 Audio/Video Calls (DinoX ↔ DinoX)
- File transfers (HTTP, Jingle)
- OMEMO encryption (1:1 and MUC)
- Message sync (MAM, Carbons)
- Contact management (Block, Mute, Remove)
- Voice messages (AAC/m4a)
- Video playback (H.264, HEVC)

### [WARNING] Needs Testing

- **MUJI Group Calls with 3+ participants**
- **Performance with 5+ participants in group call**
- **Interop with other MUJI clients** (currently DinoX is the only desktop client with MUJI)
- Echo cancellation edge cases

---

## Known Issues

### Critical (P0)
None! 

### High Priority (P1)
- [WARNING] Echo cancellation broken in some configurations ([#1559](https://github.com/dino/dino/issues/1559))
- [WARNING] Self-signed certificates rejected ([#57](https://github.com/dino/dino/issues/57))

### Medium Priority (P2)
- Chat scroll behavior jumpy ([#1769](https://github.com/dino/dino/issues/1769))
- Dark mode requires restart ([#1752](https://github.com/dino/dino/issues/1752))

---

## Quick Build Guide

### One-Line Install (Ubuntu/Debian)

```bash
sudo apt install -y meson ninja-build valac libgtk-4-dev libadwaita-1-dev \
  libglib2.0-dev libgee-0.8-dev libsqlite3-dev libgcrypt20-dev \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libnice-dev \
  libsrtp2-dev libgnutls28-dev libgpgme-dev libqrencode-dev \
  libsoup-3.0-dev libicu-dev libcanberra-dev libwebrtc-audio-processing-dev \
  libdbusmenu-glib-dev

meson setup build && meson compile -C build && ./build/main/dinox
```

📖 **[Full Build Instructions](docs/BUILD.md)** for other distros and Flatpak

---

## Contributing

We welcome contributions! Please read [CONTRIBUTING.md](docs/CONTRIBUTING.md).

**Quick Start**:
```bash
git checkout -b feature/my-awesome-feature
# Make changes, test
meson test -C build
git commit -m "feat: add awesome feature"
git push origin feature/my-awesome-feature
```

---

## Community

- **Issues**: [GitHub Issues](../../issues)
- **Discussions**: [GitHub Discussions](../../discussions)
- **Matrix**: `#dinox:matrix.org` (coming soon)

---

## License

**GPL-3.0** (same as upstream Dino)

See [LICENSE](LICENSE) for full text.

---

**Last Updated**: November 27, 2025  
**Maintainer**: @rallep71  
**Status**: [DONE] Active Development
