# 🚀 Dino Extended - Development Plan

> **Fork Status**: Independent development branch of [dino/dino](https://github.com/dino/dino)  
> **Last Updated**: November 20, 2025  
> **Version**: 0.5.0-extended  
> **Original Repository**: https://github.com/dino/dino (572 open issues)

---

## 📋 Quick Links

- 🔧 [Build Instructions](docs/BUILD.md)
- 🏛️ [Architecture Guide](docs/ARCHITECTURE.md)
- 📡 [XMPP Extensions Support](docs/XEP_SUPPORT.md)
- 🗄️ [Database Schema](docs/DATABASE_SCHEMA.md)
- 👥 [Contributing Guidelines](docs/CONTRIBUTING.md)

---

## 🎯 Mission Statement

This fork addresses the slow development pace of the original Dino XMPP client while maintaining full XMPP protocol compliance. We focus on:

1. **Stability First** - Fix critical crashes, data loss, and memory leaks
2. **Modern UX** - Implement missing features users expect in 2025
3. **Performance** - Optimize database, reduce memory footprint
4. **Community-Driven** - Transparent development, fast issue response

---

## 🚦 Current Status

| Metric | Status | Details |
|--------|--------|---------|
| **XEPs Implemented** | ✅ 60+ | One of most compliant XMPP clients |
| **Open Upstream Issues** | ⚠️ 572 | We'll prioritize top 50 critical ones |
| **Database Schema** | ✅ v31 | Modern, unlimited messages + custom server |
| **Memory Leaks** | ✅ Fixed | Issue #1766 - MAM cleanup implemented |
| **Tech Stack** | ✅ Modern | GTK4, libadwaita 1.5, Meson, Vala |
| **Platform Support** | ⚠️ Linux Only | Desktop focus (GNOME/KDE) |

---

## 🎯 Development Roadmap

### 🔴 Phase 1: Critical Stability (Q1 2026 - v0.6.0)

**Goal**: Make Dino rock-solid for daily use

| Priority | Issue | Component | Impact | Status |
|----------|-------|-----------|--------|--------|
| 🔥 P0 | [#1764](https://github.com/dino/dino/issues/1764) | File Transfer | Segfault on upload error | ✅ FIXED |
| 🔥 P0 | [#1766](https://github.com/dino/dino/issues/1766) | Memory | RAM grows to GB over days | ✅ FIXED |
| ⚠️ P1 | [#1746](https://github.com/dino/dino/issues/1746) | Sync | MAM/Carbon messages lost | ✅ FIXED |
| ⚠️ P1 | [#1779](https://github.com/dino/dino/issues/1779) | UX | Long messages truncated/unreadable | ✅ FIXED |

> **Note**: Issue [#1784](https://github.com/dino/dino/issues/1784) (database crash on long messages) was already fixed in upstream commit [d625058d](https://github.com/dino/dino/commit/d625058d) (Sept 2025). Database schema v30 uses TEXT columns supporting unlimited message size.

**Files Modified**:
- ✅ `libdino/src/service/file_manager.vala` - Stream cleanup on error (issue #1764)
- ✅ `libdino/src/service/history_sync.vala` - MAM stanza cleanup on error (issue #1766)
- ✅ `xmpp-vala/src/module/xep/0059_result_set_management.vala` - Page size 20→200 (issue #1746)
- ✅ `main/src/ui/conversation_content_view/message_widget.vala` - Limit 10k→100k chars (issue #1779)

**Status**: ✅ **COMPLETED** (November 19, 2025)  
**Time Spent**: 1 day  
**Commits**: `b65d6b72`, `65b8f47e`, `c3024d71`

---

### 🟡 Phase 2: Critical Bug Fixes Round 2 (Q1 2026 - v0.6.1)

**Goal**: Fix remaining P0/P1 stability issues

| Priority | Issue | Component | Impact | Complexity | Status |
|----------|-------|-----------|--------|------------|--------|
| 🔥 P0 | [#440](https://github.com/dino/dino/issues/440) | OMEMO | Offline messages unreadable | Hard | ✅ FIXED |
| 🔥 P0 | [#752](https://github.com/dino/dino/issues/752) | File Transfer | Cannot send files with OMEMO | Medium | ✅ FIXED |
| 🔥 P0 | [#1271](https://github.com/dino/dino/issues/1271) | Calls | Stuck connecting with Conversations | Medium | ✅ FIXED |
| ⚠️ P1 | [#1559](https://github.com/dino/dino/issues/1559) | Calls | Echo cancellation broken | Hard | 🔴 TODO |
| ⚠️ P1 | [#57](https://github.com/dino/dino/issues/57) | Security | Self-signed certs rejected | Medium | 🔴 TODO |

**Files to Modify**:
- `plugins/omemo/src/file_encryptor.vala` - OMEMO file encryption
- `plugins/omemo/src/message_encryptor.vala` - Offline message handling
- `plugins/rtp/src/device/` - Echo cancellation
- `xmpp-vala/src/core/` - Certificate validation

**Estimated Time**: 2-3 weeks  
**Target Release**: End of December 2025

---

### 🟢 Phase 3: Top User-Requested Features (Q1-Q2 2026 - v0.7.0)

**Goal**: Implement most-wanted features (100+ reactions each!)

| Priority | Issue | Feature | Reactions | Complexity | Status |
|----------|-------|---------|-----------|------------|--------|
| ⭐ Feature | [#98](https://github.com/dino/dino/issues/98) | Systray Support | 108 👍 | Medium | ✅ DONE |
| ⭐ Feature | [#299](https://github.com/dino/dino/issues/299) | Background Mode | 54 👍 | Medium | ✅ DONE |
| ⭐ Feature | [#115](https://github.com/dino/dino/issues/115) | Custom Host/Port | 26 👍 | Easy | ✅ DONE |
| 🎨 UX | [#1796](https://github.com/dino/dino/issues/1796) | File Button Bug | - | Easy | ✅ FIXED |
| 🎨 UX | - | Remove Avatar Button | vCard avatar deletion | Easy | ✅ FIXED |
| 🎨 UX | - | Edit/Delete Message Buttons | Buttons not appearing after GTK4 migration | Easy | ✅ FIXED |
| 🎨 UX | [#1380](https://github.com/dino/dino/issues/1380) | Spell Checking | - | Medium | 🟢 TODO |

**Files Created/Modified** (Systray Support #98 & Background Mode #299):
- ✅ `main/src/ui/systray.vala` - StatusNotifierItem & DBusMenu implementation
- ✅ `main/src/ui/application.vala` - Integration & Background mode logic
- ✅ `main/vapi/dbusmenu-glib-0.4.vapi` - Vala bindings for libdbusmenu
- ✅ `main/meson.build` - Build configuration

**Files Created/Modified** (Custom Host/Port #115):
- ✅ `libdino/src/entity/account.vala` - Added custom_host, custom_port fields
- ✅ `libdino/src/service/database.vala` - Schema v31, new columns
- ✅ `xmpp-vala/src/core/stream_connect.vala` - Optional host/port, skip SRV
- ✅ `libdino/src/service/connection_manager.vala` - Pass custom params
- ✅ `main/data/preferences_window/add_account_dialog.ui` - Advanced Settings UI
- ✅ `main/src/windows/preferences_window/add_account_dialog.vala` - Logic

**Files Modified** (Remove Avatar Button):
- ✅ `libdino/src/service/avatar_manager.vala` - vCard avatar removal + cache cleanup

**Files Modified** (Edit/Delete Message Buttons):
- ✅ `main/src/ui/conversation_content_view/message_widget.vala` - Removed `shortcut_action = false` on edit action
- ✅ `main/src/ui/conversation_content_view/item_actions.vala` - Removed `shortcut_action = false` on delete action
- ✅ `main/src/ui/conversation_content_view/conversation_view.vala` - Fixed button positioning with bounds checking

**Files to Create/Modify** (Remaining):
- GTK4 spell checking integration

**Estimated Time**: 4-5 weeks  
**Time Spent**: 1 hour (Issue #115), 2 hours (Avatar removal), 1 hour (Edit/Delete buttons)  
**Target Release**: End of February 2026

---

### 🔵 Phase 4: Privacy & History Management (Q2 2026 - v0.8.0)

**Goal**: User control over data and privacy

| Priority | Issue | Feature | Why Important | Status |
|----------|-------|---------|---------------|--------|
| 🔐 Privacy | [#67](https://github.com/dino/dino/issues/67) | Auto-delete History | Limit retention (e.g., 7 days) | 🔵 TODO |
| 🔐 Privacy | [#472](https://github.com/dino/dino/issues/472) | Delete Conversation | Clear history without ending chat | 🔵 TODO |
| 🔐 Privacy | [#1317](https://github.com/dino/dino/issues/1317) | Blocking Fix | Blocked contacts still send messages | 🔵 TODO |

**Files to Modify**:
- `libdino/src/service/database.vala` - History cleanup
- `main/src/ui/conversation_selector/conversation_row.vala` - Delete UI
- `xmpp-vala/src/module/xep/0191_blocking_command.vala` - Blocking

**Estimated Time**: 2-3 weeks  
**Target Release**: End of March 2026

---

### 🟣 Phase 5: UX Polish & Minor Bugs (Q2 2026 - v0.8.5)

**Goal**: Smooth, polished experience

| Priority | Issue | Feature | User Impact | Status |
|----------|-------|---------|-------------|--------|
| 📱 UX | [#1769](https://github.com/dino/dino/issues/1769) | Chat Scroll | Conversation jumps annoyingly | 🟣 TODO |
| 🎨 UX | [#1752](https://github.com/dino/dino/issues/1752) | Dark Mode | Requires app restart | 🟣 TODO |
| 🔔 UX | [#1787](https://github.com/dino/dino/issues/1787) | Notifications | Better desktop integration | 🟣 TODO |
| 😀 Feature | [#1776](https://github.com/dino/dino/issues/1776) | Emoji Reactions | Compatibility with Conversations | 🟣 TODO |

**Files to Modify**:
- `main/src/ui/conversation_view/conversation_view.vala` - Scroll behavior
- `main/src/ui/application.vala` - Dark mode live switching
- `libdino/src/service/notification_events.vala` - Notification handling
- `xmpp-vala/src/module/xep/0444_reactions.vala` - XEP-0444 update

**Estimated Time**: 3-4 weeks  
**Target Release**: End of April 2026

---

### 🔷 Phase 6: XEP Standards & Modern Features (Q3 2026 - v0.9.0)

**Goal**: Support latest XMPP standards

| Priority | XEP | Feature | Why Important | Status |
|----------|-----|---------|---------------|--------|
| 🆕 Feature | XEP-0388 | SASL2/FAST Auth | Modern servers require it | 🔷 TODO |
| 🆕 Feature | XEP-0357 | Push Notifications | Battery efficiency | 🔷 TODO |
| 🎨 Feature | XEP-0449 | Stickers | User expectation in 2025 | 🔷 TODO |
| 🔧 Feature | - | Export/Import | Data portability | 🔷 TODO |
| 🔧 Feature | - | Multi-Profile | Multiple accounts | 🔷 TODO |

**New Files to Create**:
- `xmpp-vala/src/module/xep/0388_sasl2.vala`
- `xmpp-vala/src/module/xep/0357_push.vala`
- `xmpp-vala/src/module/xep/0449_stickers.vala`
- `libdino/src/service/export_service.vala`
- UI components in `main/src/ui/stickers/`

**Estimated Time**: 6-8 weeks  
**Target Release**: End of June 2026

---

### 🏗️ Phase 7: Technical Debt & Platform Support (Q3 2026 - v0.9.5)

**Goal**: Clean codebase + Platform expansion

| Task | Component | Problem | Solution | Status |
|------|-----------|---------|----------|--------|
| 🔧 Refactor | UI Code | GTK4/Libadwaita 1.5 Migration | AdwFlap→AdwOverlaySplitView, Dialog→Window+HeaderBar | ✅ DONE |
| 🔧 Build | Meson | Missing dependencies | Added libdbusmenu-glib, updated libadwaita | ✅ DONE |
| 📦 Deployment | Flatpak | Missing libdbusmenu | Added module to manifest | ✅ DONE |
| 📦 Deployment | Debian | No packaging files | Created debian/ control, rules, changelog | ✅ DONE |
| 📦 Deployment | CI/CD | Missing dependencies | Updated GitHub Actions workflow | ✅ DONE |
| 🎨 Refactor | CSS System | StyleContext deprecated (GTK4.10) | Widget-scoped CSS providers | 🟡 IN PROGRESS |
| 🗄️ Refactor | Database | v31 schema active, no tests | Migration test suite | ⚠️ PARTIAL |
| 🔔 Refactor | Notifications | Duplicate code (2 files) | Unified backend | 🏗️ TODO |
| 📁 Refactor | File Transfer | 400+ line state machine | Separate providers | 🏗️ TODO |
| ⚠️ Refactor | Error Handling | 10+ error domains | Unified DinoError | 🏗️ TODO |
| 🪟 Platform | [#309](https://github.com/dino/dino/issues/309) | Windows Support | Native Windows port | 🏗️ TODO |

**Files Modified** (GTK4/Libadwaita 1.5 Migration):
- ✅ 40+ UI files migrated to modern APIs
- ✅ `AdwFlap` → `AdwOverlaySplitView` (deprecated in libadwaita 1.5)
- ✅ `Gtk.Dialog` → `Gtk.Window` + `AdwHeaderBar` pattern
- ✅ `preview_file_chooser_native.vala` removed (native GTK4 API)
- ✅ Notification handling modernized
- ✅ File widgets updated for GTK4 drag-and-drop
- ✅ CSS adjustments for libadwaita themes

**CSS System Refactoring** (GTK4.10+ Future-Proof):

**Current Problem**:
- Using deprecated `Gtk.StyleContext.add_provider_for_display()` (2 warnings)
- Global CSS providers attached to display (GTK3 pattern)
- Manual provider cleanup required

**New Architecture**:
```
┌─────────────────────────────────────────────┐
│ Widget-Scoped CSS (GTK4 Way)                │
├─────────────────────────────────────────────┤
│ 1. CssProvider per widget (not per display) │
│ 2. Automatic cleanup on widget destroy      │
│ 3. No StyleContext API usage                │
│ 4. CSS classes + inline styles              │
└─────────────────────────────────────────────┘
```

**Implementation Plan**:

**Phase 1: Refactor helper.vala CSS utilities** (1-2 hours)
- Replace `Gtk.StyleContext.add_provider_for_display()` 
- Use widget-scoped providers via `Gtk.Widget.add_css_class()`
- Store provider references in widget data for cleanup
- Keep backward-compatible API

**Files to Modify**:
- `main/src/ui/util/helper.vala`:
  - `force_css()` - Attach provider to widget, not display
  - `force_color()` - Use widget CSS data storage
  - `get_label_pango_color()` - Clean up properly
  
**Phase 2: Update call sites** (30 min)
- `main/src/ui/conversation_selector/conversation_selector_row.vala` (3 usages)
- `main/src/ui/conversation_content_view/message_widget.vala` (1 usage)
- `main/src/ui/util/preference_group.vala` (2 usages)

**Technical Approach**:
```vala
// OLD (deprecated):
Gtk.StyleContext.add_provider_for_display(display, provider, priority);

// NEW (GTK4 way):
widget.get_style_context().add_provider(provider, priority);
// OR use CSS classes + set_data() for lifecycle management
```

**Testing Strategy**:
1. Visual regression test (colors, styling unchanged)
2. Memory leak check (providers properly destroyed)
3. Performance test (no display-wide provider pollution)

**Benefits**:
- ✅ Zero deprecation warnings
- ✅ Better performance (widget-scoped, not display-wide)
- ✅ Automatic cleanup (widget lifecycle)
- ✅ Future-proof for GTK5
- ✅ Follows GTK4 best practices

**Status**: 🟡 **READY TO IMPLEMENT** (Nov 20, 2025)  
**Time Required**: 2-3 hours total  
**Risk**: Low (backward-compatible API)

**Recent Work** (Nov 20, 2025):
- ✅ Fixed edit/delete message buttons not appearing (removed `shortcut_action = false`)
- ✅ Fixed button positioning using `compute_bounds()` 
- ✅ Clean build: 0 errors, 541 targets compiled successfully
- ✅ Only 2 StyleContext deprecation warnings remaining (to be fixed in CSS refactoring)

---

**Original Benefits**:
- Easier onboarding for new contributors
- Fewer bugs from code duplication
- Faster feature development
- Windows user base expansion
- Modern UI/UX following GNOME HIG
- Future-proof against libadwaita deprecations

**Estimated Time**: 8-10 weeks (incl. Windows port)  
**Time Spent**: 4-6 hours (GTK4/libadwaita migration)  
**Target Release**: End of August 2026

---

### 🎉 Phase 8: 1.0 Stable Release (Q4 2026 - v1.0.0)

**Goal**: Production-ready, stable API

**Requirements**:
- ✅ Zero known crash bugs
- ✅ Memory usage <200MB for 7-day sessions
- ✅ 90%+ test coverage for critical paths
- ✅ Complete documentation (API, architecture, build)
- ✅ Performance benchmarks established
- ✅ Accessibility audit passed

**Target Release**: October 2026

---

## 📊 Issue Backlog (568 Remaining Issues)

### Overview by Category

| Category | Count | Top Priority Issues |
|----------|-------|---------------------|
| 🐛 **Bugs** | ~200 | Crashes, data loss, broken features |
| ✨ **Features** | ~250 | UX improvements, new capabilities |
| 📡 **XEPs** | ~50 | Protocol updates, standards compliance |
| 🎨 **UI/UX** | ~40 | Interface polish, accessibility |
| 📱 **Platform** | ~15 | Windows, mobile, packaging |
| 🔐 **Security** | ~13 | Encryption, certificates, privacy |

**Total Upstream Issues**: 572  
**Fixed by us**: 5 (Phase 1: 4, Phase 3: 1)  
**Remaining**: 567

### Prioritization Strategy

1. **P0 (Critical)**: Crashes, data loss, security → Phases 1-2
2. **P1 (High)**: Broken features, major UX → Phases 2-3
3. **P2 (Medium)**: Minor bugs, nice features → Phases 4-5
4. **P3 (Low)**: Edge cases, enhancements → Phases 6-8

### Issue Tracking

We'll progressively add issues to phases as we work through them:
- ✅ Phase 1: Completed (4/4 issues)
- 🎯 Phase 2: Defined (5 issues)
- 🎯 Phase 3: Defined (5 issues)
- 🎯 Phase 4: Defined (3 issues)
- 🎯 Phase 5: Defined (4 issues)
- 📋 Phases 6-8: High-level goals, detailed issues TBD

**Approach**: Fix bugs systematically, implement popular features, then polish for 1.0

---

## 🏗️ Quick Build Guide

### One-Line Install (Ubuntu/Debian)

```bash
# Install all dependencies
sudo apt install -y meson ninja-build valac \
  libgtk-4-dev libadwaita-1-dev libglib2.0-dev libgee-0.8-dev \
  libsqlite3-dev libgcrypt20-dev libgstreamer1.0-dev \
  libgstreamer-plugins-base1.0-dev libnice-dev libsrtp2-dev \
  libgnutls28-dev libgpgme-dev libqrencode-dev libsoup-3.0-dev \
  libicu-dev libcanberra-dev libwebrtc-audio-processing-dev \
  libdbusmenu-glib-dev

# Build & run
meson setup build && meson compile -C build && ./build/main/dino
```

📖 **[Full Build Instructions](docs/BUILD.md)** for other distros and Flatpak

---

## 🐛 Bug Reporting

Found a bug? Please check:

1. ✅ [Existing Issues](../../issues) - Maybe it's already reported
2. ✅ [Upstream Issues](https://github.com/dino/dino/issues) - Check if it's in original
3. ✅ Latest build - Run `git pull && meson compile -C build`

[🐛 Create Bug Report](../../issues/new?template=bug_report.md)

---

## 💡 Feature Requests

Have an idea? Check the [Feature Roadmap](#-development-roadmap) first.

[💡 Request Feature](../../issues/new?template=feature_request.md)

---

## 👥 Contributing

We welcome contributions! Please read [CONTRIBUTING.md](docs/CONTRIBUTING.md).

**Quick Start**:
```bash
git checkout -b feature/my-awesome-feature
# Make changes, test
meson test -C build
git commit -m "feat(omemo): add key verification dialog"
git push origin feature/my-awesome-feature
```

---

## 📞 Community

- **Issues**: [GitHub Issues](../../issues)
- **Discussions**: [GitHub Discussions](../../discussions)
- **Upstream XMPP**: `chat@dino.im`

---

## 📜 License

**GPL-3.0** (same as upstream Dino)

See [LICENSE](LICENSE) for full text.

---

**Last Updated**: November 20, 2025  
**Maintainer**: @rallep71  
**Status**: 🟢 Active Development
