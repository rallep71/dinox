# 🔧 Build Instructions - Dino Extended

Complete guide to building Dino from source on various Linux distributions.

---

## 📋 Table of Contents

- [Prerequisites](#prerequisites)
- [Debian/Ubuntu](#debianubuntu)
- [Fedora/RHEL/CentOS](#fedorarhel)
- [Arch Linux](#arch-linux)
- [openSUSE](#opensuse)
- [Building from Source](#building-from-source)
- [Flatpak Build](#flatpak-build)
- [Development Setup](#development-setup)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Build Tools

- **Meson** ≥ 1.3.0
- **Ninja** (build backend)
- **Vala** compiler (valac)
- **GCC/G++** (C/C++ compiler)
- **pkg-config**

### Core Dependencies

| Library | Min Version | Purpose |
|---------|-------------|---------|
| GTK4 | 4.0+ | UI framework |
| libadwaita | 1.5+ | Modern GNOME widgets |
| GLib/GIO | 2.74+ | Core utilities |
| libgee | 0.8+ | Data structures |
| SQLite | 3.24+ | Database |
| ICU | any | Unicode support |

### Optional Dependencies (Plugins)

| Library | Plugin | Feature |
|---------|--------|---------|
| GStreamer 1.0 | rtp | Voice/video calls |
| libnice ≥0.1.15 | ice | NAT traversal for calls |
| libsrtp2 | crypto | Encrypted calls |
| libgcrypt | crypto | Encryption |
| libomemo-c 0.5.1 | omemo | OMEMO encryption |
| gpgme 1.13+ | openpgp | OpenPGP encryption |
| libsoup3 | http-files | HTTP file uploads |
| libqrencode | omemo | QR code device verification |
| libcanberra | notification-sound | Sound notifications |
| webrtc-audio-processing | rtp | Audio preprocessing |

---

## Debian/Ubuntu

### Ubuntu 24.04 LTS / Debian 13 (Trixie)

```bash
# Install build tools
sudo apt update
sudo apt install -y build-essential meson ninja-build \
  valac pkg-config git cmake

# Install GTK4 and core dependencies
sudo apt install -y \
  libgtk-4-dev \
  libadwaita-1-dev \
  libglib2.0-dev \
  libgio2.0-dev \
  libgee-0.8-dev \
  libsqlite3-dev \
  libicu-dev

# Install plugin dependencies
sudo apt install -y \
  libgcrypt20-dev \
  libgpgme-dev \
  libqrencode-dev \
  libsoup-3.0-dev \
  libcanberra-dev

# Install call support (optional but recommended)
sudo apt install -y \
  libgstreamer1.0-dev \
  libgstreamer-plugins-base1.0-dev \
  libgstreamer-plugins-bad1.0-dev \
  gstreamer1.0-plugins-good \
  gstreamer1.0-plugins-bad \
  libnice-dev \
  libsrtp2-dev \
  libgnutls28-dev \
  libwebrtc-audio-processing-dev

# Build libomemo-c (not in Ubuntu repos)
cd /tmp
wget https://github.com/dino/libomemo-c/releases/download/v0.5.1/libomemo-c-0.5.1.tar.gz
tar xf libomemo-c-0.5.1.tar.gz
cd libomemo-c-0.5.1
meson setup build -Ddefault_library=static -Dtests=false
meson compile -C build
sudo meson install -C build
cd ~
```

### Ubuntu 22.04 LTS

```bash
# GTK4 and libadwaita might need backports
sudo add-apt-repository ppa:paultag/gnome-45
sudo apt update

# Then follow Ubuntu 24.04 instructions above
```

---

## Fedora/RHEL

### Fedora 40+

```bash
# Install build tools
sudo dnf install -y gcc gcc-c++ meson ninja-build \
  vala pkgconf git cmake

# Install GTK4 and core dependencies
sudo dnf install -y \
  gtk4-devel \
  libadwaita-devel \
  glib2-devel \
  gee-devel \
  sqlite-devel \
  libicu-devel

# Install plugin dependencies
sudo dnf install -y \
  libgcrypt-devel \
  gpgme-devel \
  qrencode-devel \
  libsoup3-devel \
  libcanberra-devel

# Install call support
sudo dnf install -y \
  gstreamer1-devel \
  gstreamer1-plugins-base-devel \
  gstreamer1-plugins-good \
  gstreamer1-plugins-bad-free \
  libnice-devel \
  libsrtp-devel \
  gnutls-devel \
  webrtc-audio-processing-devel

# Build libomemo-c
cd /tmp
wget https://github.com/dino/libomemo-c/releases/download/v0.5.1/libomemo-c-0.5.1.tar.gz
tar xf libomemo-c-0.5.1.tar.gz
cd libomemo-c-0.5.1
meson setup build -Ddefault_library=static -Dtests=false
meson compile -C build
sudo meson install -C build
cd ~
```

---

## Arch Linux

### Arch/Manjaro

```bash
# Install from official repos
sudo pacman -S meson vala gtk4 libadwaita glib2 libgee \
  sqlite libgcrypt gstreamer gst-plugins-base \
  gst-plugins-good gst-plugins-bad libnice libsrtp \
  gnutls gpgme qrencode libsoup3 icu libcanberra \
  webrtc-audio-processing git cmake

# Build libomemo-c
cd /tmp
wget https://github.com/dino/libomemo-c/releases/download/v0.5.1/libomemo-c-0.5.1.tar.gz
tar xf libomemo-c-0.5.1.tar.gz
cd libomemo-c-0.5.1
meson setup build -Ddefault_library=static -Dtests=false
meson compile -C build
sudo meson install -C build
cd ~
```

**Note**: Arch often has very recent package versions, so usually no issues.

---

## openSUSE

### Tumbleweed (Rolling)

```bash
# Install build tools
sudo zypper install -y meson ninja vala gcc gcc-c++ \
  pkgconf git cmake

# Install GTK4 and core
sudo zypper install -y \
  gtk4-devel \
  libadwaita-devel \
  glib2-devel \
  libgee-devel \
  sqlite3-devel \
  libicu-devel

# Install plugin dependencies
sudo zypper install -y \
  libgcrypt-devel \
  gpgme-devel \
  qrencode-devel \
  libsoup-devel \
  libcanberra-devel

# Install call support
sudo zypper install -y \
  gstreamer-devel \
  gstreamer-plugins-base-devel \
  libnice-devel \
  libsrtp2-devel \
  gnutls-devel \
  webrtc-audio-processing-devel

# Build libomemo-c (same as other distros)
```

---

## Building from Source

### Clone Repository

```bash
git clone https://github.com/rallep71/dino.git
cd dino
```

### Configure Build

```bash
# Default build (all plugins enabled)
meson setup build

# Custom configuration
meson setup build \
  --prefix=/usr \
  --buildtype=debugoptimized \
  -Dplugin-rtp=true \
  -Dplugin-omemo=true \
  -Dplugin-openpgp=true \
  -Dplugin-http-files=true \
  -Dplugin-ice=true \
  -Dplugin-notification-sound=true
```

**Build Types**:
- `debug` - No optimization, full debug symbols
- `debugoptimized` - Some optimization, debug symbols (recommended for development)
- `release` - Full optimization, stripped binaries
- `minsize` - Optimize for size

### Compile

```bash
# Compile (uses all CPU cores by default)
meson compile -C build

# Or with limited cores (e.g., 2)
meson compile -C build -j 2
```

### Run Locally (No Install)

```bash
# Run directly from build directory
./build/main/dino

# With debug logging
DINO_LOG_LEVEL=debug ./build/main/dino

# With verbose XMPP logging
G_MESSAGES_DEBUG=all ./build/main/dino
```

### Install System-Wide

```bash
# Install to /usr/local (or --prefix you specified)
sudo meson install -C build

# Uninstall
sudo ninja -C build uninstall
```

---

## Flatpak Build

### Install Flatpak SDK

```bash
# Install flatpak-builder
sudo apt install flatpak-builder  # Debian/Ubuntu
sudo dnf install flatpak-builder  # Fedora

# Add Flathub
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# Install GNOME SDK 49
flatpak install -y flathub org.gnome.Platform//49 org.gnome.Sdk//49
```

### Build Flatpak

```bash
cd /path/to/dino

# Build and install locally
flatpak-builder --user --install --force-clean \
  build-flatpak im.dino.Dino.json

# Run Flatpak
flatpak run im.dino.Dino
```

### Export Flatpak

```bash
# Create repository
flatpak-builder --repo=repo --force-clean \
  build-flatpak im.dino.Dino.json

# Build single-file bundle
flatpak build-bundle repo dino-extended.flatpak im.dino.Dino

# Install bundle on another system
flatpak install dino-extended.flatpak
```

---

## Development Setup

### IDE Setup (VS Code / Codium)

```bash
# Install Vala extension
code --install-extension prince781.vala

# Open workspace
code /path/to/dino
```

**VS Code settings** (`.vscode/settings.json`):
```json
{
  "vala.languageServerPath": "/usr/bin/vala-language-server",
  "files.associations": {
    "*.vala": "vala",
    "*.ui": "xml"
  }
}
```

### Generate Documentation

```bash
# Install valadoc
sudo apt install valadoc  # Debian/Ubuntu
sudo dnf install valadoc  # Fedora

# Generate docs
valadoc --pkg gtk4 --pkg libadwaita-1 --pkg gee-0.8 \
  -o docs/api libdino/src/**/*.vala xmpp-vala/src/**/*.vala

# View docs
xdg-open docs/api/index.html
```

### Run Tests

```bash
# Run all tests
meson test -C build

# Run specific test suite
meson test -C build libdino:jid
meson test -C build xmpp-vala:stanza

# Verbose output
meson test -C build --verbose
```

### Debug with GDB

```bash
# Build with debug symbols
meson setup build --buildtype=debug

# Run in GDB
gdb --args ./build/main/dino

# GDB commands:
# (gdb) run
# (gdb) backtrace  # after crash
# (gdb) break main  # set breakpoint
```

### Memory Leak Detection

```bash
# Install valgrind
sudo apt install valgrind

# Run with leak check
valgrind --leak-check=full --show-leak-kinds=all \
  --track-origins=yes --verbose \
  --log-file=valgrind-out.txt \
  ./build/main/dino

# Check results
less valgrind-out.txt
```

---

## Troubleshooting

### Common Errors

#### Error: `Dependency 'gtk4' not found`

**Solution**: Install GTK4 development files
```bash
sudo apt install libgtk-4-dev  # Debian/Ubuntu
sudo dnf install gtk4-devel    # Fedora
```

#### Error: `Dependency 'libadwaita-1' version '>= 1.5' not found`

**Solution**: Your distro has old libadwaita. Either:
1. Upgrade to newer distro version
2. Build libadwaita from source:
```bash
git clone https://gitlab.gnome.org/GNOME/libadwaita.git
cd libadwaita
meson setup build -Dexamples=false -Dtests=false
meson compile -C build
sudo meson install -C build
```

#### Error: `Program 'valac' not found`

**Solution**: Install Vala compiler
```bash
sudo apt install valac
```

#### Error: `meson version is 0.61 but project requires >= 1.3.0`

**Solution**: Install newer Meson via pip
```bash
sudo apt remove meson  # Remove old version
pip3 install --user meson
# Add ~/.local/bin to PATH
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

#### Error: `libomemo-c not found`

**Solution**: Build libomemo-c manually (see distro-specific instructions above)

#### GStreamer plugin errors at runtime

**Solution**: Install GStreamer plugins
```bash
sudo apt install gstreamer1.0-plugins-good gstreamer1.0-plugins-bad
```

### Build Logs

```bash
# Check meson log for configuration issues
cat build/meson-logs/meson-log.txt

# Check compile log for errors
cat build/meson-logs/compile-log.txt
```

### Clean Build

```bash
# Remove build directory and start fresh
rm -rf build
meson setup build
meson compile -C build
```

---

## Platform-Specific Notes

### Wayland vs X11

Dino uses GTK4 which prefers Wayland but falls back to X11.

**Force X11**:
```bash
GDK_BACKEND=x11 ./build/main/dino
```

**Force Wayland**:
```bash
GDK_BACKEND=wayland ./build/main/dino
```

### High DPI Displays

GTK4 auto-detects scaling. To force:
```bash
GDK_SCALE=2 ./build/main/dino
```

### PipeWire (Audio/Video)

Modern distros use PipeWire for audio. If calls don't work:
```bash
# Check PipeWire status
systemctl --user status pipewire pipewire-pulse

# Restart if needed
systemctl --user restart pipewire pipewire-pulse
```

---

## Performance Tuning

### Optimize Build

```bash
# Maximum optimization
meson setup build --buildtype=release

# Link-time optimization (slower build, faster runtime)
meson setup build --buildtype=release -Db_lto=true
```

### Reduce Memory Usage

```bash
# Disable debug symbols in release builds
meson setup build --buildtype=release --strip
```

---

## Next Steps

After successful build:

1. 📖 Read [ARCHITECTURE.md](ARCHITECTURE.md) to understand codebase
2. 🐛 Check [GitHub Issues](https://github.com/rallep71/dino/issues) for bugs to fix
3. 👥 Read [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines

---

**Questions?** Open an issue: https://github.com/rallep71/dino/issues
