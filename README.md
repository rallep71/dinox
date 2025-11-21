<img src="https://dino.im/img/logo.svg" width="80">

# DinoX

**Modern XMPP client - Active fork of [dino/dino](https://github.com/dino/dino) with extended features**

DinoX is a modern XMPP messaging client for Linux using GTK4 and Vala.
It supports calls, OMEMO encryption, file transfers, group chats and more.

> **Status**: Active development | Based on upstream master | Database schema v32

## ✨ Extended Features

This fork adds features that are missing in upstream Dino:

- ✅ **System Tray Support** - StatusNotifierItem with background mode (Issue [#98](https://github.com/dino/dino/issues/98))
- ✅ **Custom Server Settings** - Advanced connection options (Issue [#115](https://github.com/dino/dino/issues/115))
- ✅ **Delete Conversation History** - Persistent history clearing (Issue [#472](https://github.com/dino/dino/issues/472))
- ✅ **Contact Management Suite** - Edit/Mute/Block/Remove contacts with UI
- ✅ **Status Badges** - Visual indicators for muted/blocked contacts
- ✅ **Context Menu** - Quick access via right-click on conversations
- ✅ **Memory Leak Fixes** - MAM cleanup (Issue [#1766](https://github.com/dino/dino/issues/1766))
- ✅ **File Transfer Fixes** - Segfault prevention (Issue [#1764](https://github.com/dino/dino/issues/1764))

See [DEVELOPMENT_PLAN.md](DEVELOPMENT_PLAN.md) for complete feature list and roadmap.

## 📦 Installation

### From Source

**Dependencies**: GTK4 4.0+, libadwaita 1.5+, libdbusmenu-glib

```bash
# Clone repository
git clone https://github.com/rallep71/dinox.git
cd dino

# Install dependencies (Debian/Ubuntu/Mint)
sudo apt install -y build-essential meson ninja-build valac \
  libgtk-4-dev libadwaita-1-dev libglib2.0-dev libgee-0.8-dev \
  libsqlite3-dev libicu-dev libdbusmenu-glib-dev libgcrypt20-dev \
  libgpgme-dev libqrencode-dev libsoup-3.0-dev

# Build and run
meson setup build
meson compile -C build
./build/main/dino
```

For other distributions see [docs/BUILD.md](docs/BUILD.md).

## 🚀 Quick Start

```bash
# Run directly from build directory
./build/main/dino

# With debug logging
DINO_LOG_LEVEL=debug ./build/main/dino

# Install system-wide
sudo meson install -C build
```

## 📚 Documentation

- 📖 [Build Instructions](docs/BUILD.md) - Complete build guide for all distros
- 🏗️ [Architecture Overview](docs/ARCHITECTURE.md) - Code structure and design
- 🔧 [Development Plan](DEVELOPMENT_PLAN.md) - Roadmap and completed features
- 📡 [XMPP Extensions](docs/XEP_SUPPORT.md) - Supported XEPs
- 🗄️ [Database Schema](docs/DATABASE_SCHEMA.md) - SQLite schema documentation

## 🤝 Contribute

- **Report Issues**: Use GitHub Issues for bug reports
- **Feature Requests**: Check [DEVELOPMENT_PLAN.md](DEVELOPMENT_PLAN.md) first
- **Pull Requests**: Welcome! Discuss bigger changes first
- **Translations**: Help translate via upstream Dino

## 🔗 Resources

- **Upstream**: [dino/dino](https://github.com/dino/dino) - Original project
- **Website**: [dino.im](https://dino.im) - Official Dino website
- **XMPP Channel**: `chat@dino.im` - Community chat

License
-------
    Dino - XMPP messaging app using GTK/Vala
    Copyright (C) 2016-2025 Dino contributors

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
