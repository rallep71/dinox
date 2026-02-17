# Building DinoX from Source

This guide provides detailed instructions for building DinoX on Linux and Windows.

## General Requirements

*   **Compiler:** GCC or Clang
*   **Build System:** Meson (>= 0.56.0), Ninja
*   **Language:** Vala (>= 0.48)
*   **Toolkit:** GTK4, Libadwaita
*   **Multimedia:** GStreamer, PipeWire

## Dependencies

Notes:

- DinoX uses Meson `dependency()` / pkg-config for most third-party libraries. That means it links against whatever is installed in your build environment (including `/usr/local` if present).
- Audio/video calling support (RTP/Jingle) needs additional GStreamer + ICE/DTLS/SRTP dependencies; see “Audio/Video calling stack” below.

### Version notes (calls / RTP plugin)

For a plain “build from source” on a Linux distro, DinoX will use the versions available in your system packages. For **releases**, the effective versions are controlled by the packaging:

- **Flatpak:** pinned/built as defined in [im.github.rallep71.DinoX.json](im.github.rallep71.DinoX.json).
- **AppImage:** a curated set of runtime libs/plugins is bundled; versions depend on what the AppImage build environment provides and what the build workflow bundles.

In particular:

- **libnice (ICE):** DinoX call support is known to have issues with older libnice versions. The release builds bundle/build **libnice 0.1.23**; for distro/source builds you should use **libnice >= 0.1.23**.
- **“webrtc” in DinoX does NOT mean Google/libwebrtc:** DinoX uses **GStreamer** (not the full Google WebRTC stack). The relevant pieces are the GStreamer plugins from `gst-plugins-bad` (DTLS/SRTP/WebRTC elements) plus `libnice` for ICE.
- **webrtc-audio-processing (Highly Recommended):** This library provides professional-grade Echo Cancellation (AEC), Noise Suppression (NS), and Automatic Gain Control (AGC).
    - Without it, calls may have echo or background noise.
    - DinoX detects it at build time. If found, it is used automatically.

#### Building webrtc-audio-processing 2.1 (Manual)

If your distribution does not provide `webrtc-audio-processing` or has an older version (check with `pkg-config --modversion webrtc-audio-processing`), you should build version 2.1 from source to ensure the best audio quality.

```bash
# 1. Download and extract
wget https://freedesktop.org/software/pulseaudio/webrtc-audio-processing/webrtc-audio-processing-2.1.tar.xz
tar xf webrtc-audio-processing-2.1.tar.xz
cd webrtc-audio-processing-2.1

# 2. Build and install
meson setup build --prefix=/usr/local
ninja -C build
sudo ninja -C build install

# 3. Update library cache
sudo ldconfig

# 4. Verify installation
pkg-config --modversion webrtc-audio-processing
# Should output: 2.1
```

#### Quick checks (distro/source builds)

```bash
pkg-config --modversion nice
pkg-config --modversion gstreamer-1.0
pkg-config --modversion gstreamer-plugins-bad-1.0
pkg-config --modversion webrtc-audio-processing || true

# Elements provided by gst-plugins-bad (names may vary by distro build options)
gst-inspect-1.0 webrtcbin >/dev/null
gst-inspect-1.0 dtlsenc  >/dev/null
gst-inspect-1.0 srtpenc  >/dev/null
```

### Debian / Ubuntu / Linux Mint

```bash
sudo apt update
sudo apt install \
    build-essential \
    git \
    meson \
    ninja-build \
    valac \
    libgtk-4-dev \
    libadwaita-1-dev \
    libglib2.0-dev \
    libgee-0.8-dev \
    libsqlcipher-dev \
    libsecret-1-dev \
    libicu-dev \
    libdbusmenu-glib-dev \
    libgcrypt20-dev \
    libgpgme-dev \
    libomemo-c-dev \
    libjson-glib-dev \
    libqrencode-dev \
    libsoup-3.0-dev \
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev \
    libgstreamer-plugins-bad1.0-dev \
    gstreamer1.0-pipewire \
    libwebrtc-audio-processing-dev \
    libnice-dev \
    libgnutls28-dev \
    libsrtp2-dev
```

### Fedora

```bash
sudo dnf install \
    gcc \
    git \
    meson \
    ninja-build \
    vala \
    gtk4-devel \
    libadwaita-devel \
    glib2-devel \
    libgee-devel \
    sqlcipher-devel \
    libsecret-devel \
    libicu-devel \
    libdbusmenu-glib-devel \
    libgcrypt-devel \
    gpgme-devel \
    libomemo-c-devel \
    json-glib-devel \
    qrencode-devel \
    libsoup3-devel \
    gstreamer1-devel \
    gstreamer1-plugins-base-devel \
    gstreamer1-plugins-bad-free-devel \
    pipewire-gstreamer \
    webrtc-audio-processing-devel \
    libnice-devel \
    gnutls-devel \
    libsrtp2-devel
```

### Arch Linux / Manjaro

```bash
sudo pacman -S \
    base-devel \
    meson \
    ninja \
    vala \
    gtk4 \
    libadwaita \
    glib2 \
    libgee \
    sqlcipher \
    libsecret \
    icu \
    libdbusmenu-glib \
    libgcrypt \
    gpgme \
    libomemo-c \
    json-glib \
    qrencode \
    libsoup3 \
    gstreamer \
    gst-plugins-base \
    gst-plugins-bad \
    gst-plugin-pipewire \
    webrtc-audio-processing \
    libnice \
    gnutls \
    libsrtp

```

### Audio/Video calling stack

- **Required for A/V calls (RTP/Jingle):** GStreamer core + `gst-plugins-bad` (DTLS/SRTP/WebRTC libs), `libnice` (ICE), `libsrtp2` (SRTP), `gnutls` (DTLS).
- **Optional (recommended) for better audio quality:** `webrtc-audio-processing` enables AEC/NS/AGC if present. The build works without it.

If you want to build DinoX without call support, you can disable the plugin:

```bash
meson setup build -Dplugin-rtp=false
```

### Windows (MSYS2 / MINGW64)

DinoX can be built on Windows 10/11 using the MSYS2 environment with the MINGW64 toolchain.

#### 1. Install MSYS2

Download and install MSYS2 from [msys2.org](https://www.msys2.org/). Then open the **MINGW64** shell (not the MSYS shell).

#### 2. Install dependencies

```bash
pacman -Syu
pacman -S --noconfirm \
    mingw-w64-x86_64-gcc \
    mingw-w64-x86_64-vala \
    mingw-w64-x86_64-meson \
    mingw-w64-x86_64-ninja \
    mingw-w64-x86_64-pkg-config \
    mingw-w64-x86_64-cmake \
    mingw-w64-x86_64-gtk4 \
    mingw-w64-x86_64-libadwaita \
    mingw-w64-x86_64-glib2 \
    mingw-w64-x86_64-libgee \
    mingw-w64-x86_64-sqlcipher \
    mingw-w64-x86_64-icu \
    mingw-w64-x86_64-libgcrypt \
    mingw-w64-x86_64-gpgme \
    mingw-w64-x86_64-qrencode \
    mingw-w64-x86_64-libsoup3 \
    mingw-w64-x86_64-gstreamer \
    mingw-w64-x86_64-gst-plugins-base \
    mingw-w64-x86_64-gst-plugins-good \
    mingw-w64-x86_64-gst-plugins-bad \
    mingw-w64-x86_64-gst-plugins-ugly \
    mingw-w64-x86_64-gst-libav \
    mingw-w64-x86_64-libnice \
    mingw-w64-x86_64-gnutls \
    mingw-w64-x86_64-libsrtp \
    mingw-w64-x86_64-python \
    mingw-w64-x86_64-glib-networking \
    mingw-w64-x86_64-sqlite3 \
    mingw-w64-x86_64-hicolor-icon-theme \
    mingw-w64-x86_64-adwaita-icon-theme \
    git \
    tar
```

#### 3. Build libomemo-c (required, not available in MSYS2)

```bash
git clone https://github.com/rallep71/libomemo-c.git
cd libomemo-c
mkdir build && cd build
cmake -G Ninja \
    -DCMAKE_INSTALL_PREFIX=/mingw64 \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    ..
ninja
ninja install
cd ../..
```

#### 4. Build DinoX

```bash
git clone https://github.com/rallep71/dinox.git
cd dinox
meson setup build --prefix=/mingw64
ninja -C build
```

#### 5. Create distribution archive

The `scripts/update_dist.sh` script collects the built executable, all required DLLs, and runtime data into a `dist/` folder:

```bash
bash scripts/update_dist.sh
```

The resulting `dist/` directory contains everything needed to run DinoX on Windows. Run `dinox.exe` directly.

#### Windows notes

- **Tor/Obfs4proxy**: Bundled and fully functional on Windows. Tor and obfs4proxy bridges work out of the box.
- **libsecret/D-Bus**: Not used on Windows. Passwords are handled differently.
- **libcanberra**: Notification sounds (message + call ringtone) are enabled by default on all Linux builds (native, Flatpak, AppImage) via `auto` detection. Not available on Windows (libcanberra is Linux-only). See [Development Plan](DEVELOPMENT_PLAN.md) for cross-platform notification sound plans.
- **webrtc-audio-processing**: MSYS2 provides version 0.3 and 1.x. DinoX auto-detects and uses whatever is available. Version 2.x is not yet packaged for MSYS2.
```

## Build Instructions

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/rallep71/dinox.git
    cd dinox
    ```

2.  **Configure the build:**
    ```bash
    meson setup build
    ```

    If you have multiple versions of a dependency installed (e.g. `/usr` and `/usr/local`), Meson/pkg-config may pick the one that comes first on your `PKG_CONFIG_PATH`. For reproducible results, build in a clean environment (container/VM) or pin `PKG_CONFIG_PATH` explicitly.

3.  **Compile:**
    ```bash
    ninja -C build
    ```

4.  **Run:**
    ```bash
    ./build/main/dinox
    ```

## Troubleshooting

### SQLCipher VAPI Issues
DinoX uses a bundled VAPI file for SQLCipher (`qlite/vapi/sqlcipher.vapi`) because most distributions do not provide one. The build system is configured to use this automatically. If you encounter errors related to `sqlcipher`, ensure you have the `sqlcipher` development package installed (headers and libraries).

### Missing Dependencies
If Meson complains about a missing dependency, check the error message. It usually tells you exactly which library is missing. You can search for the package name in your distribution's package manager.

### Flatpak vs AppImage dependency sourcing


- **Flatpak** ([im.github.rallep71.DinoX.json](im.github.rallep71.DinoX.json)) uses `org.gnome.Platform` as runtime. GStreamer/libnice/etc come from the Flatpak runtime, not your host system.
- **AppImage** ([scripts/build-appimage.sh](scripts/build-appimage.sh)) bundles a selection of runtime libraries and GStreamer plugins from the build machine into the AppDir. The effective versions therefore depend on what’s installed on the build host. For best results, build the AppImage in a controlled environment.

### How to check exact versions (Flatpak / AppImage)

#### Flatpak

Check the installed app metadata and query versions from *inside the sandbox*:

```bash
# Shows DinoX version and runtime
flatpak info im.github.rallep71.DinoX

# Library versions inside the sandbox
flatpak run --command=sh im.github.rallep71.DinoX -c "pkg-config --modversion nice"
flatpak run --command=sh im.github.rallep71.DinoX -c "pkg-config --modversion gstreamer-1.0"
flatpak run --command=sh im.github.rallep71.DinoX -c "pkg-config --modversion gstreamer-plugins-bad-1.0"
flatpak run --command=sh im.github.rallep71.DinoX -c "pkg-config --modversion webrtc-audio-processing || true"

# Verify SQLCipher compile flags (FTS support)
flatpak run --command=sh im.github.rallep71.DinoX -c "printf '%s\\n' '.mode list' 'pragma compile_options;' | sqlcipher :memory: 2>/dev/null | grep -E 'FTS3|FTS4|FTS5' || true"
```

Release Flatpaks may also pin/build specific dependency versions directly in the manifest (for example `libnice`) in [im.github.rallep71.DinoX.json](im.github.rallep71.DinoX.json).

#### AppImage

The official AppImage release bundles key runtime libraries and GStreamer plugins. To inspect what your downloaded AppImage contains:

```bash
chmod +x DinoX-*.AppImage

# Extract into ./squashfs-root/
./DinoX-*.AppImage --appimage-extract

# Check for the key call-related GStreamer plugins
ls -la squashfs-root/usr/lib/gstreamer-1.0 | grep -E 'libgst(nice|dtls|srtp|webrtc)\\.so' || true

# Locate a bundled libnice shared library (path can vary)
find squashfs-root -maxdepth 5 -type f -name 'libnice*.so*' -print
```

If you want deterministic AppImage dependency versions, build in a clean/controlled environment (container/VM) and avoid mixing host system GStreamer plugins with the bundled set.

---

## Scripts Reference

All scripts live in the `scripts/` directory. Debug scripts are documented in [DEBUG.md](DEBUG.md#helper-scripts).

### Build & Distribution

| Script | Purpose |
|--------|--------|
| `scripts/build-appimage.sh` | Build a portable AppImage for Linux. Auto-detects architecture (x86_64/aarch64), copies runtime libraries, GStreamer plugins, and icons into an AppDir, then packages it with `appimagetool`. Use on a clean build host for reproducible results. |
| `scripts/update_dist.sh` | Collect the Windows build into a `dist/` folder: `dinox.exe`, all required DLLs, GStreamer plugins, Tor/obfs4proxy binaries, SSL certs, icons. Run after `ninja -C build` in MSYS2. |
| `scripts/ci-build-deps.sh` | CI pipeline script: runs `scripts/scan_unicode.py`, then builds `webrtc-audio-processing` from source. Used in automated builds to prepare dependencies. |
| `scripts/dinox.bat` | Windows launcher (legacy/fallback). Sets `PATH` and launches `dinox.exe`. Kept for backward compatibility — `dinox.exe` now sets all environment variables internally. |

### Release

| Script | Purpose |
|--------|--------|
| `scripts/release.sh <version>` | Full release workflow: validates version format, updates `VERSION`, `debian/changelog`, `dino.doap`, creates annotated Git tag, and pushes. Requires clean working tree. |
| `scripts/release_helper.sh <version>` | Lighter release helper: updates `CHANGELOG.md` (inserts version heading under `[Unreleased]`), `VERSION`, `dino.doap`, and `debian/changelog`. Does not tag or push. |

### Security & Quality

| Script | Purpose |
|--------|--------|
| `scripts/scan_unicode.py` | Scan source files for hidden/dangerous Unicode characters (zero-width, BiDi overrides, homoglyphs). Run from the project root. Used in CI via `ci-build-deps.sh`. Usage: `python3 scripts/scan_unicode.py [--verbose]` |

### Translation

| Script | Purpose |
|--------|--------|
| `scripts/translate_all.py` | Batch-insert missing translation strings into all `.po` files under `main/po/`. Adds `msgid`/`msgstr` entries for new UI strings. |
| `scripts/analyze_translations.py` | Analyze specific translation keys across all `.po` files to check coverage. |

### Development

| Script | Purpose |
|--------|--------|
| `scripts/create_openpgp_patches.sh [dino_path]` | Generate diff patches between DinoX and original Dino for the OpenPGP porting work. Outputs patch files to `patches/`. |

### Debug

| Script | Purpose |
|--------|--------|
| `scripts/run-dinox-debug.sh` | Start DinoX with full debug logging. See [DEBUG.md](DEBUG.md#start-a-debug-session). |
| `scripts/stop-dinox.sh` | Stop a running debug instance. See [DEBUG.md](DEBUG.md#stop-dinox). |
| `scripts/scan-dinox-latest-log.sh` | Scan latest debug log for issues. See [DEBUG.md](DEBUG.md#scan-latest-log). |
