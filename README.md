<div align="center">

<img src="dinox.svg" width="120" alt="DinoX Logo">

# DinoX

[![License: GPL-3.0](https://img.shields.io/badge/License-GPL%203.0-blue.svg)](LICENSE)
[![GTK4](https://img.shields.io/badge/GTK-4.14.5-4a86cf.svg)](https://www.gtk.org/)
[![Vala](https://img.shields.io/badge/Vala-0.56-744c9e.svg)](https://vala.dev/)
[![Release](https://img.shields.io/github/v/release/rallep71/dinox)](https://github.com/rallep71/dinox/releases)

**Modern XMPP client with extended features**

Active fork of [dino/dino](https://github.com/dino/dino) with faster development and community-requested features

[Features](#-extended-features) • [Install](#-installation) • [Build](#-build-from-source) • [Documentation](#-documentation) • [Contribute](#-contribute)

</div>

---

## 🚀 What is DinoX?

DinoX is a modern, user-friendly XMPP (Jabber) messaging client for Linux built with **GTK4** and **Vala**. It's an active fork of Dino that adds features the community has been requesting for years.

**Key Features:**
- 🔒 **End-to-End Encryption** - OMEMO & OpenPGP support
- 📞 **Voice & Video Calls** - High-quality audio/video communication
- 📁 **File Transfers** - Easy sharing of files and media
- 👥 **Group Chats** - Full MUC (Multi-User Chat) support
- 🎨 **Modern UI** - Clean interface with libadwaita design
- 📡 **60+ XEPs** - Extensive XMPP protocol support

> **Status**: ✅ Active development | 🔄 Based on upstream master | 📊 Database schema v32

## ✨ Extended Features

DinoX adds features that are **missing in upstream Dino** but highly requested by the community:

### 🎯 New Features

| Feature | Status | Upstream Issue |
|---------|--------|----------------|
| **🔔 System Tray Support** | ✅ Complete | [#98](https://github.com/dino/dino/issues/98) |
| StatusNotifierItem with background mode | | Keep running when window closed |
| **🔧 Custom Server Settings** | ✅ Complete | [#115](https://github.com/dino/dino/issues/115) |
| Advanced connection options | | Manual host/port configuration |
| **🗑️ Delete Conversation History** | ✅ Complete | [#472](https://github.com/dino/dino/issues/472) |
| Persistent history clearing | | Remove all messages permanently |
| **👥 Contact Management Suite** | ✅ Complete | Multiple issues |
| Edit/Mute/Block/Remove contacts | | Full contact control with UI |
| **🏷️ Status Badges** | ✅ Complete | Community request |
| Visual indicators | | See muted/blocked status at a glance |
| **📋 Context Menu** | ✅ Complete | UX improvement |
| Right-click on conversations | | Quick access to common actions |

### 🐛 Bug Fixes

- ✅ **Memory Leak Fixes** - MAM cleanup ([#1766](https://github.com/dino/dino/issues/1766))
- ✅ **File Transfer Fixes** - Segfault prevention ([#1764](https://github.com/dino/dino/issues/1764))

📋 See [DEVELOPMENT_PLAN.md](DEVELOPMENT_PLAN.md) for complete feature list and roadmap.

## 📦 Installation

### Option 1: Download Release

**📥 [Download Latest Release](https://github.com/rallep71/dinox/releases/latest)**

Available formats:
- 📦 **Flatpak** - Universal Linux package (x86_64, aarch64)
- 📄 **Source Tarball** - Build from source

```bash
# Install Flatpak
flatpak install dinox-0.6.0-x86_64.flatpak

# Run DinoX
flatpak run im.github.rallep71.DinoX
```

### Option 2: Build from Source

**Requirements**: GTK4 4.0+, libadwaita 1.5+, libdbusmenu-glib

```bash
# Clone repository
git clone https://github.com/rallep71/dinox.git
cd dinox

# Install dependencies (Debian/Ubuntu/Mint)
sudo apt install -y build-essential meson ninja-build valac \
  libgtk-4-dev libadwaita-1-dev libglib2.0-dev libgee-0.8-dev \
  libsqlite3-dev libicu-dev libdbusmenu-glib-dev libgcrypt20-dev \
  libgpgme-dev libqrencode-dev libsoup-3.0-dev

# Build and run
meson setup build
meson compile -C build
./build/main/dino

# Install system-wide (optional)
sudo meson install -C build
```

📖 For other distributions see [docs/BUILD.md](docs/BUILD.md).

## 🎮 Quick Start

After installation, you can:

1. **Add Account** - Configure your XMPP account (e.g., `user@jabber.org`)
2. **Enable System Tray** - Settings → Background Mode (keep running when closed)
3. **Customize Server** - Advanced → Connection Settings (if needed)
4. **Manage Contacts** - Right-click on conversations for options

### Debug Mode

```bash
# Run with debug logging
DINO_LOG_LEVEL=debug ./build/main/dino

# Or for Flatpak
flatpak run --env=DINO_LOG_LEVEL=debug im.github.rallep71.DinoX
```

## 📚 Documentation

| Document | Description |
|----------|-------------|
| 📖 [Build Instructions](docs/BUILD.md) | Complete build guide for all distros |
| 🏗️ [Architecture Overview](docs/ARCHITECTURE.md) | Code structure and design |
| 🔧 [Development Plan](DEVELOPMENT_PLAN.md) | Roadmap and completed features |
| 📡 [XMPP Extensions](docs/XEP_SUPPORT.md) | Supported XEPs (60+) |
| 🗄️ [Database Schema](docs/DATABASE_SCHEMA.md) | SQLite schema documentation |
| 🎨 [Logo Guide](docs/LOGO_CREATION_GUIDE.md) | Logo creation and branding |
| 📦 [Flathub Guide](docs/FLATHUB.md) | Publishing to Flathub |
| ⚖️ [Legal & Branding](docs/LEGAL_BRANDING.md) | License and trademark info |

## 🤝 Contribute

We welcome contributions! Here's how you can help:

- 🐛 **Report Bugs** - Use [GitHub Issues](https://github.com/rallep71/dinox/issues)
- 💡 **Feature Requests** - Check [DEVELOPMENT_PLAN.md](DEVELOPMENT_PLAN.md) first
- 🔧 **Pull Requests** - Welcome! Discuss bigger changes first
- 🌍 **Translations** - Help translate via upstream Dino project
- ⭐ **Star the Repo** - Show your support!

## 🔗 Resources

| Resource | Link |
|----------|------|
| **Upstream Project** | [dino/dino](https://github.com/dino/dino) |
| **Official Website** | [dino.im](https://dino.im) |
| **XMPP Community** | `chat@dino.im` |
| **Releases** | [GitHub Releases](https://github.com/rallep71/dinox/releases) |
| **Issues** | [Bug Tracker](https://github.com/rallep71/dinox/issues) |

## 📊 Project Stats

- **XEP Support**: 60+ XMPP Extension Protocols
- **Database Schema**: v32 (compatible with upstream)
- **Active Development**: Regular updates and bug fixes
- **License**: GPL-3.0 (same as upstream)

---

## 📄 License

**GPL-3.0** - Same as upstream Dino

```
DinoX - Modern XMPP client with extended features
Copyright (C) 2016-2025 Dino Team (original authors)
Copyright (C) 2025 Ralf Peter (fork maintainer)

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.
```

See [LICENSE](LICENSE) for the full license text.

---

<div align="center">

**Made with ❤️ by the XMPP community**

[⭐ Star on GitHub](https://github.com/rallep71/dinox) • [🐛 Report Issues](https://github.com/rallep71/dinox/issues) • [📖 Read Docs](docs/)

</div>
