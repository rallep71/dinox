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
| **XEPs Implemented** | [OK] **67** | One of most compliant XMPP clients |
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
| **Message Moderation (XEP-0425)** | v0.6.3 | Protocol | [DONE] Complete |
| **MUC Invitations** | v0.6.0 | XEP-0045/0249 | [DONE] Complete |
| **Message Reactions (XEP-0444)** | Inherited | Dino v0.4 | [DONE] Complete |
| **Message Replies (XEP-0461)** | Inherited | Dino v0.4 | [DONE] Complete |
| **Message Styling (XEP-0393)** | Inherited | Dino v0.1 | [DONE] Partial (bold/italic/strikethrough) |
| **MUJI Group Calls Phase 1** | v0.6.5.3 | XEP-0272 | [DONE] Complete |
| **Desktop Notifications Fix** | v0.6.5.4 | Critical bug | [DONE] Fixed |

---

## Development History

### [DONE] Phase 0: Inherited Features from Upstream Dino

**Goal**: Document features already present in forked codebase

These features were inherited from upstream Dino and are fully functional in DinoX:

#### XEP Protocol Support (7 XEPs)
- [DONE] **XEP-0047** (In-Band Bytestreams) - File transfer fallback method
  - Backend: `xmpp-vala/src/module/xep/0047_in_band_bytestreams.vala`
  - Used automatically when direct connections fail
  
- [DONE] **XEP-0298** (COIN - Conference Information) - Jingle conference metadata
  - Backend: `xmpp-vala/src/module/xep/0298_coin.vala`
  - Module: `libdino/src/service/calls.vala` line 539 (`coin_info_received`)
  
- [DONE] **XEP-0391** (Jingle Encrypted Transports) - Encrypted call framework
  - Backend: `libdino/src/service/call_peer_state.vala` (`ContentEncryption`)
  - Partial implementation for secure calls
  
- [DONE] **XEP-0392** (Consistent Color Generation) - Contact color algorithm
  - Backend: `xmpp-vala/src/module/xep/0392_consistent_color/`
  - UI: `main/src/ui/util/helper.vala` (`get_consistent_hex_color`)
  - Full implementation with unit tests
  
- [DONE] **XEP-0393** (Message Styling) - Bold/Italic/Strikethrough formatting
  - Backend: Protocol support in dino.doap
  - UI: `main/src/ui/chat_input/chat_text_view.vala` line 163-180
  - Keyboard shortcuts: **CTRL+B** (bold), **CTRL+I** (italic), **CTRL+S** (strikethrough)
  
- [DONE] **XEP-0396** (OMEMO Jingle) - OMEMO encryption for calls
  - Backend: `plugins/omemo/src/jingle/jet_omemo.vala`
  - Module: `plugins/omemo/src/dtls_srtp_verification_draft.vala`
  
- [DONE] **XEP-0454** (OMEMO Media Sharing) - Encrypted file sharing
  - Backend: Listed in dino.doap
  - Partial: No thumbnail support yet

#### Message Features (3 Features)
- [DONE] **XEP-0444** (Message Reactions) - Emoji reactions (since Dino v0.4)
  - Backend: `libdino/src/service/reactions.vala`
  - Protocol: `xmpp-vala/src/module/xep/0444_reactions.vala`
  - UI: `main/src/ui/conversation_content_view/item_actions.vala` line 78-90
  - Features: "Add reaction" button with emoji picker
  
- [DONE] **XEP-0461** (Message Replies) - Quote/reply to messages (since Dino v0.4)
  - Backend: `libdino/src/service/replies.vala`
  - Protocol: `xmpp-vala/src/module/xep/0461_replies.vala`
  - UI: `main/src/ui/conversation_content_view/quote_widget.vala`
  - Features: Quote display above message, reply context preservation
  
- [DONE] **Message Styling UI** - Rich text input
  - UI: Bold/Italic/Strikethrough tags in `chat_text_view.vala`
  - Database: `MarkupTable` for persistence
  - Rendering: Styled text display in message widgets

#### Infrastructure
- [DONE] GTK4/libadwaita 1.5 migration (from Dino upstream)
- [DONE] Modern Vala syntax and async patterns
- [DONE] PubSub-based XEP implementations
- [DONE] Jingle framework for calls and file transfers

**Status**: [DONE] **INHERITED** (Forked November 2025)

**Note**: These features required no DinoX-specific development but are essential to document for completeness.

---

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

### [DONE] Phase 7: MUC Administration (Inherited from Dino v0.4)

**Goal**: Complete MUC management features

| Priority | Feature | Complexity | Status |
|----------|---------|------------|--------|
| [DONE] | **MUC Invitations** | Easy | [DONE] **DONE** |
| [DONE] | **Affiliation Management UI** | Medium | [DONE] **DONE** |
| [DONE] | **Room Destruction** | Easy | [DONE] **DONE** |

**MUC Invitations** [DONE] **IMPLEMENTED**:
- [DONE] Available via **Occupant Menu** (user icon in titlebar)
- [DONE] "Invite" button opens contact selection dialog
- [DONE] Backend: `MucManager.invite()` fully functional
- [DONE] UI: `main/src/ui/occupant_menu/view.vala:269` - Complete implementation
- [DONE] Supports both XEP-0045 (Mediated) and XEP-0249 (Direct) invitations

**Affiliation Management** [DONE] **FULLY IMPLEMENTED**:
- [DONE] **Make Admin / Revoke Admin** - Owner can promote/demote admins
- [DONE] **Make Owner** - Transfer ownership to another user
- [DONE] **Make Member / Revoke Membership** - Manage member list (members-only rooms)
- [DONE] **Ban (Permanent)** - Permanent outcast affiliation
- [DONE] **Ban (Timed)** - 10/15/30 minute temporary bans
- [DONE] **Kick** - Temporarily remove from room
- [DONE] **Mute/Unmute** - Voice control (visitor/participant role)
- [DONE] **Block/Unblock** - XEP-0191 blocking integration
- [DONE] **Permission Checks** - Owner/Admin hierarchy enforced
- [DONE] UI: `main/src/ui/occupant_menu/view.vala:143-167`
- [DONE] Message Context: `main/src/ui/conversation_content_view/item_actions.vala:45-76`

**Room Destruction** [DONE] **IMPLEMENTED**:
- [DONE] "Destroy Room" button in conversation details (Owner only)
- [DONE] Confirmation dialog with destructive styling
- [DONE] Error handling and feedback
- [DONE] UI: `main/src/ui/conversation_details.vala:218-257`
- [DONE] Backend: `MucManager.destroy_room()`

**Status**: [DONE] **COMPLETED** (Inherited from upstream Dino v0.4)

**See**: [MUC_IMPROVEMENT_PLAN.md](MUC_IMPROVEMENT_PLAN.md) for details

---

### [TODO] Phase 8: MUJI Group Calls Phase 2 (v0.6.7 - Q1 2026)

**Goal**: Enhance group call experience

| Priority | Feature | Complexity | Status |
|----------|---------|------------|--------|
| P1 | **Individual Volume Controls** | Medium | [TODO] TODO |
| P2 | **Call Quality Indicators** | Medium | [PARTIAL] Backend ready |
| P2 | **Better Error Messages** | Easy | [DONE] Audio/Video errors |
| P3 | **Speaking Indicator** | Hard | [DEFERRED] DEFERRED |

**Individual Volume Controls**: 
- Backend has volume/gain support (`voice_processor.vala`)
- No UI implementation yet

**Call Quality Indicators**:
- Backend tracks bandwidth, packet info (`content_parameters.vala`)
- No UI to display quality metrics yet

**Better Error Messages** [PARTIAL]:
- [DONE] Audio device errors shown (`call_window_controller.vala:312`)
- [DONE] Video device errors shown (`call_window_controller.vala:340`)
- [ ] TODO: Network quality/connection issues

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
| P1 | [#1559](https://github.com/dino/dino/issues/1559) | Echo Cancellation | Hard | [PARTIAL] Backend ready |
| P1 | [#57](https://github.com/dino/dino/issues/57) | Self-signed Certs | Medium | [PARTIAL] Basic handling |
| P2 | [#1380](https://github.com/dino/dino/issues/1380) | Spell Checking | Medium | [BLOCKED] GTK4 |

**Echo Cancellation** [PARTIAL]:
- [DONE] WebRTC Audio Processing Library integrated
- [DONE] AEC (Acoustic Echo Cancellation) implemented (`voice_processor.vala:21`)
- [DONE] AGC (Automatic Gain Control) implemented
- [DONE] EchoProbe for playback monitoring
- [ ] TODO: Fine-tuning, configuration UI, testing with various hardware

**Self-signed Certificates** [PARTIAL]:
- [DONE] TLS error detection (`stream_connect.vala:21`)
- [DONE] Invalid cert callback mechanism (`TlsXmppStream.OnInvalidCert`)
- [DONE] Notification on TLS errors
- [ ] TODO: User dialog to accept/pin self-signed certs
- [ ] TODO: Certificate pinning storage
- [ ] TODO: Per-account cert trust settings

**Spell Checking** [BLOCKED]:
- [INFO] Setting exists: `check_spelling` (default: true)
- [BLOCKED] "There is currently no spell checking for GTK4" (`settings.vala:71`)
- [INFO] No UI for setting (hidden)
- [ ] TODO: Wait for GTK4 spell check library
- [ ] TODO: Consider GtkSpell alternative or native GTK4 API

**Files to modify**:
- `plugins/rtp/src/voice_processor.vala` - Echo cancellation tuning
- `main/src/ui/` - Certificate trust dialog
- `libdino/src/service/` - Certificate storage
- GTK4 spell checking integration (when available)

**Target**: End of March 2026

---

### [TODO] Phase 10: UX Polish (v0.7.5 - Q2 2026)

**Goal**: Smooth, polished experience

| Priority | Issue | Feature | Complexity | Status |
|----------|-------|---------|------------|--------|
| P2 | [#1769](https://github.com/dino/dino/issues/1769) | Chat Scroll Fix | Medium | [TODO] TODO |
| P2 | [#1752](https://github.com/dino/dino/issues/1752) | Dark Mode Toggle | Easy | [TODO] TODO |
| P2 | [#1787](https://github.com/dino/dino/issues/1787) | Better Notifications | Medium | [PARTIAL] Basic done |

**Dark Mode** [TODO]:
- [INFO] `Adw.StyleManager` already used (`helper.vala:150`)
- [INFO] System dark mode detection works
- [ ] TODO: Add appearance toggle in Preferences → General
- [ ] TODO: Save preference (light/dark/auto)
- [ ] TODO: Apply without restart using `StyleManager.set_color_scheme()`

**Notifications** [PARTIAL]:
- [DONE] Desktop notifications fixed (v0.6.5.4)
- [DONE] FreeDesktop + GNotifications support
- [ ] TODO: Per-conversation notification settings
- [ ] TODO: Notification preview customization
- [ ] TODO: Do Not Disturb mode

**Target**: End of April 2026

---

### [TODO] Phase 11: Modern XEP Support (v0.8.0 - Q2 2026)

**Goal**: Support latest XMPP standards

| Priority | XEP | Feature | Complexity | Status |
|----------|-----|---------|------------|--------|
| P1 | XEP-0388 | SASL2/FAST Auth | Hard | [TODO] Future |
| P1 | XEP-0386 | Bind 2 | Hard | [TODO] Future |
| P1 | XEP-0357 | Push Notifications | Hard | [TODO] Future |
| P2 | XEP-0449 | Stickers | Medium | [TODO] Future |
| P3 | - | Export/Import | Medium | [TODO] Future |

**Note**: These are modern XMPP 2.0 features currently under development in the protocol. Implementation timeline depends on server adoption and protocol stabilization.

**New files to create**:
- `xmpp-vala/src/module/xep/0388_sasl2.vala`
- `xmpp-vala/src/module/xep/0386_bind2.vala`
- `xmpp-vala/src/module/xep/0357_push.vala`
- `xmpp-vala/src/module/xep/0449_stickers.vala`

**Target**: End of June 2026 (subject to protocol readiness)

---

###  Phase 12: Platform Expansion (v0.9.0 - Q3 2026+)

**Goal**: Windows support and packaging

| Priority | Feature | Complexity | Status |
|----------|---------|------------|--------|
| P2 | Windows Native Port | Very Hard |  FUTURE |
| P3 | Android (via GTK4) | Very Hard |  FUTURE |
| P3 | macOS (via GTK4) | Hard |  FUTURE |

**Note**: Platform expansion requires significant GTK4 ecosystem maturity and cross-platform testing infrastructure. Current focus is on Linux desktop experience.

**Target**: End of August 2026 (optimistic, likely Q4 2026+)

---

###  Phase 13: 1.0 Stable Release (Q4 2026+ - v1.0.0)

**Goal**: Production-ready, stable API

**Requirements**:
- [ ] Zero known P1 crash bugs
- [ ] Memory usage <200MB for 7-day sessions
- [ ] 90%+ test coverage for critical paths
- [ ] Complete documentation
- [ ] All Phase 1-9 features complete
- [ ] 3+ months beta testing period
- [ ] Performance benchmarks established
- [ ] Accessibility audit passed

**Current Status**: 
- v0.6.5.5 (November 2025)
- Focus: Stability, bug fixes, inherited feature verification
- Path to 1.0: Complete Phases 7-10, address critical bugs, extensive testing

**Target**: Q4 2026 or later (depends on phases 7-11 completion)
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

### Implementation Status (November 27, 2025)

| Status | Count | Percentage |
|--------|-------|------------|
| [DONE] **Full (Backend + UI)** | 36 | 54% |
|  **Backend Only** | 28 | 42% |
| [WARNING] **Partial** | 3 | 4% |
| **Total XEPs** | **67** | 100% |

### DinoX Extensions (Beyond Upstream Dino)

- [DONE] XEP-0191 (Blocking Command) - Enhanced UI in Contacts page
- [DONE] XEP-0272 (MUJI) - Full Phase 1 UI with participant grid
- [DONE] XEP-0424 (Message Retraction) - "Delete for everyone" button
- [DONE] XEP-0425 (Message Moderation) - "Moderate message" for moderators
- [DONE] System Tray - Background mode toggle
- [DONE] Custom Server Settings - Connection customization
- [DONE] Contact Management - Block/unblock, search, filtering

### Verified from Upstream Dino

- [DONE] XEP-0444 (Message Reactions) - Emoji picker + reaction display
- [DONE] XEP-0461 (Message Replies) - Quote widget in chat
- [DONE] XEP-0393 (Message Styling) - Bold/Italic/Strikethrough (CTRL+B/I/S)
- [DONE] XEP-0392 (Consistent Colors) - Contact color generation
- [DONE] XEP-0047 (In-Band Bytestreams) - File transfer fallback
- [DONE] XEP-0298 (COIN) - Conference information
- [DONE] XEP-0396 (OMEMO Jingle) - Encrypted calls

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
