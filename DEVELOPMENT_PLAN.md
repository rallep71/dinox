# 🚀 Dino Extended - Development Plan

> **Fork Status**: Independent development branch of [dino/dino](https://github.com/dino/dino)  
> **Last Updated**: November 19, 2025  
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
| **Database Schema** | ✅ v30 | Modern, supports unlimited message size |
| **Memory Leaks** | 🔴 Active | Issue #1766 - MAM history not freed |
| **Tech Stack** | ✅ Modern | GTK4, libadwaita 1.5, Meson, Vala |
| **Platform Support** | ⚠️ Linux Only | Desktop focus (GNOME/KDE) |

---

## 🎯 Development Roadmap

### 🔴 Phase 1: Critical Stability (Q1 2026 - v0.6.0)

**Goal**: Make Dino rock-solid for daily use

| Priority | Issue | Component | Impact | Status |
|----------|-------|-----------|--------|--------|
| 🔥 P0 | [#1764](https://github.com/dino/dino/issues/1764) | File Transfer | Segfault on upload error | 🔴 TODO |
| 🔥 P0 | [#1766](https://github.com/dino/dino/issues/1766) | Memory | RAM grows to GB over days | 🔴 TODO |
| ⚠️ P1 | [#1746](https://github.com/dino/dino/issues/1746) | Sync | MAM/Carbon messages lost | 🔴 TODO |
| ⚠️ P1 | [#1779](https://github.com/dino/dino/issues/1779) | UX | Long messages truncated/unreadable | 🔴 TODO |

> **Note**: Issue [#1784](https://github.com/dino/dino/issues/1784) (database crash on long messages) was already fixed in upstream commit [d625058d](https://github.com/dino/dino/commit/d625058d) (Sept 2025). Database schema v30 uses TEXT columns supporting unlimited message size.

**Files to Modify**:
- `plugins/http-files/src/file_sender.vala` - Null checks for segfault
- `libdino/src/service/message_processor.vala` - Memory management
- `xmpp-vala/src/module/xep/0313_mam.vala` - Message storage/cleanup
- `main/src/ui/conversation_view/message_widget.vala` - Long message display

**Estimated Time**: 2-3 weeks  
**Target Release**: End of January 2026

---

### 🟡 Phase 2: UX Polish (Q1-Q2 2026 - v0.7.0)

**Goal**: Smooth, modern chat experience

| Priority | Issue | Feature | User Impact | Status |
|----------|-------|---------|-------------|--------|
| 📱 UX | [#1769](https://github.com/dino/dino/issues/1769) | Chat Scroll | Conversation jumps annoyingly | 🟡 TODO |
| 🎨 UX | [#1752](https://github.com/dino/dino/issues/1752) | Dark Mode | Requires app restart | 🟡 TODO |
| 📎 UX | [#1796](https://github.com/dino/dino/issues/1796) | File Sending | Encryption change required | 🟡 TODO |
| 🔔 UX | [#1787](https://github.com/dino/dino/issues/1787) | Notifications | Better desktop integration | 🟡 TODO |

**Files to Modify**:
- `main/src/ui/conversation_view/conversation_view.vala` - Scroll behavior
- `main/src/ui/application.vala` - Dark mode live switching
- `main/src/ui/conversation_content_view/chat_input.vala` - File encryption UX
- `libdino/src/service/notification_events.vala` - Notification handling

**Estimated Time**: 3-4 weeks  
**Target Release**: End of March 2026

---

### 🟢 Phase 3: Feature Completeness (Q2 2026 - v0.8.0)

**Goal**: Support latest XMPP standards

| Priority | XEP | Feature | Why Important | Status |
|----------|-----|---------|---------------|--------|
| 🆕 Feature | XEP-0388 | SASL2/FAST Auth | Modern servers require it | 🟢 TODO |
| 🆕 Feature | XEP-0357 | Push Notifications | Battery efficiency | 🟢 TODO |
| 🎨 Feature | XEP-0449 | Stickers | User expectation in 2025 | 🟢 TODO |
| 🔧 Feature | - | Export/Import | Data portability | 🟢 TODO |
| 🔧 Feature | - | Multi-Profile | Multiple accounts | 🟢 TODO |

**New Files to Create**:
- `xmpp-vala/src/module/xep/0388_sasl2.vala`
- `xmpp-vala/src/module/xep/0357_push.vala`
- `xmpp-vala/src/module/xep/0449_stickers.vala`
- `libdino/src/service/export_service.vala`
- UI components in `main/src/ui/stickers/`

**Estimated Time**: 6-8 weeks  
**Target Release**: End of May 2026

---

### 🏗️ Phase 4: Technical Debt (Q3 2026 - v0.9.0)

**Goal**: Clean, maintainable codebase

| Task | Component | Problem | Solution | Status |
|------|-----------|---------|----------|--------|
| 🗄️ Refactor | Database | v30 schema, no tests | Migration test suite | 🔵 TODO |
| 🔔 Refactor | Notifications | Duplicate code (2 files) | Unified backend | 🔵 TODO |
| 📁 Refactor | File Transfer | 400+ line state machine | Separate providers | 🔵 TODO |
| ⚠️ Refactor | Error Handling | 10+ error domains | Unified DinoError | 🔵 TODO |

**Benefits**:
- Easier onboarding for new contributors
- Fewer bugs from code duplication
- Faster feature development

**Estimated Time**: 4-6 weeks  
**Target Release**: End of August 2026

---

### 🎉 Phase 5: 1.0 Stable (Q4 2026 - v1.0.0)

**Goal**: Production-ready, stable API

**Requirements**:
- ✅ Zero known crash bugs
- ✅ Memory usage <200MB for 7-day sessions
- ✅ 90%+ test coverage for critical paths
- ✅ Complete documentation (API, architecture, build)
- ✅ Performance benchmarks established
- ✅ Accessibility audit passed

**Target Release**: December 2026

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
  libicu-dev libcanberra-dev libwebrtc-audio-processing-dev

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

**Last Updated**: November 19, 2025  
**Maintainer**: @rallep71  
**Status**: 🟢 Active Development
