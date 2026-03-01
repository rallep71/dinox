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
- **protobuf-c:** Ubuntu 24.04 ships 1.4.1 which has a memory corruption bug in `protobuf_c_message_unpack()` (fixed in 1.5.1). Release builds use **protobuf-c 1.5.2**.
- **mosquitto:** Ubuntu 24.04 ships 2.0.18. Release builds use **mosquitto 2.1.2** for latest security/protocol fixes.
- **libomemo-c (OMEMO):** Ubuntu 24.04 ships 0.5.0. Release builds use **libomemo-c 0.5.1** from the [rallep71 fork](https://github.com/rallep71/libomemo-c).
- **"webrtc" in DinoX does NOT mean Google/libwebrtc:** DinoX uses **GStreamer** (not the full Google WebRTC stack). The relevant pieces are the GStreamer plugins from `gst-plugins-bad` (DTLS/SRTP/WebRTC elements) plus `libnice` for ICE.

> **Recommended:** Use `scripts/ci-build-deps.sh` to build all custom dependencies from source with the same versions as the CI/release builds. This replaces SQLCipher, webrtc-audio-processing, libnice, protobuf-c, libomemo-c, and mosquitto with tested versions.
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

# 1b. Fix for abseil-cpp >= 20250814 (e.g. Arch Linux):
#     Only needed if your abseil-cpp is version 20250814 or newer.
ABSEIL_VER=$(pkg-config --modversion absl_base 2>/dev/null || echo "0")
if [[ "$ABSEIL_VER" > "20250813" ]]; then
    echo "Patching for abseil-cpp $ABSEIL_VER..."
    # Download patch from DinoX repo (or use local copy from scripts/patches/)
    wget -q -O /tmp/webrtc-abseil.patch \
        "https://raw.githubusercontent.com/rallep71/dinox/master/scripts/patches/webrtc-audio-processing-v2.1-remove-abseil-nullability.patch"
    patch -p1 < /tmp/webrtc-abseil.patch
fi

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
# Core dependencies
pkg-config --modversion nice
pkg-config --modversion gstreamer-1.0
pkg-config --modversion gstreamer-plugins-bad-1.0
pkg-config --modversion webrtc-audio-processing || true

# SQLCipher FTS support (FTS5 recommended for better search performance)
sqlcipher :memory: "PRAGMA compile_options;" 2>/dev/null | grep -i FTS

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
    libjson-glib-dev \
    libqrencode-dev \
    libsoup-3.0-dev \
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev \
    libgstreamer-plugins-bad1.0-dev \
    gstreamer1.0-pipewire \
    libnice-dev \
    libgnutls28-dev \
    libsrtp2-dev \
    libcjson-dev \
    gstreamer1.0-plugins-good

# Then build custom dependencies from source (protobuf-c, mosquitto, libomemo-c, etc.)
./scripts/ci-build-deps.sh
```

> **Note:** `ci-build-deps.sh` builds protobuf-c 1.5.2, mosquitto 2.1.2, libomemo-c 0.5.1, SQLCipher 4.6.1 (FTS5), webrtc-audio-processing 2.1, and libnice 0.1.23 from source. These replace the (often outdated) Ubuntu packages.

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
    json-glib-devel \
    qrencode-devel \
    libsoup3-devel \
    gstreamer1-devel \
    gstreamer1-plugins-base-devel \
    gstreamer1-plugins-bad-free-devel \
    pipewire-gstreamer \
    libnice-devel \
    gnutls-devel \
    libsrtp2-devel \
    gstreamer1-plugins-good

# Then build custom dependencies from source
./scripts/ci-build-deps.sh
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
    json-glib \
    qrencode \
    libsoup3 \
    gstreamer \
    gst-plugins-base \
    gst-plugins-good \
    gst-plugins-bad \
    gst-plugin-pipewire \
    libnice \
    gnutls \
    libsrtp

# Then build custom dependencies from source
./scripts/ci-build-deps.sh
```

### SQLCipher with FTS5 (Full-Text Search)

DinoX uses SQLCipher for encrypted local databases. Distribution packages of SQLCipher typically include FTS3/FTS4 but **not FTS5**. DinoX detects FTS5 availability at runtime and uses it automatically when available, falling back to FTS4 otherwise.

FTS5 provides better ranking, faster prefix queries, and lower memory usage for message search.

#### Check your system

```bash
# Check which FTS modules your SQLCipher supports
sqlcipher :memory: "PRAGMA compile_options;" 2>/dev/null | grep -i FTS
# Expected output with FTS5:
# ENABLE_FTS3
# ENABLE_FTS4
# ENABLE_FTS5
```

#### Building SQLCipher with FTS5 (recommended)

If your system SQLCipher lacks FTS5, build from source:

```bash
# 1. Download
wget -q https://github.com/sqlcipher/sqlcipher/archive/v4.6.1.tar.gz
tar xf v4.6.1.tar.gz && cd sqlcipher-4.6.1

# 2. Configure with FTS5
./configure --prefix=/usr --enable-tempstore=yes --enable-fts5 \
  CFLAGS="-DSQLITE_HAS_CODEC -DSQLITE_ENABLE_COLUMN_METADATA -DSQLITE_ENABLE_FTS3 -DSQLITE_ENABLE_FTS3_PARENTHESIS -DSQLITE_ENABLE_FTS4 -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_UNLOCK_NOTIFY -DSQLITE_ENABLE_DBSTAT_VTAB" \
  LDFLAGS="-lcrypto"

# 3. Build and install
make -j$(nproc)
sudo make install
sudo ldconfig

# 4. Verify
sqlcipher :memory: "PRAGMA compile_options;" | grep -i FTS5
# Should output: ENABLE_FTS5
```

> **Note:** After installing from source, you may need to remove the distribution package (`sudo apt remove libsqlcipher-dev libsqlcipher1`) to avoid library conflicts. The AppImage and Flatpak builds handle this automatically.

> **Note:** `scripts/ci-build-deps.sh` builds SQLCipher from source with FTS5 automatically. If you use it to prepare your build environment, no manual SQLCipher build is needed.

### Audio/Video calling stack

- **Required for A/V calls (RTP/Jingle):** GStreamer core + `gst-plugins-bad` (DTLS/SRTP/WebRTC libs), `libnice` (ICE), `libsrtp2` (SRTP), `gnutls` (DTLS).
- **Optional (recommended) for better audio quality:** `webrtc-audio-processing` enables AEC/NS/AGC if present. The build works without it.

If you want to build DinoX without call support, you can disable the plugin:

```bash
meson setup build -Dplugin-rtp=false
```

### Plugin Build Options

All plugins can be individually enabled or disabled at build time via Meson options.
Use `-D<option>=enabled`, `disabled`, or `auto` (default for most).

```bash
# Show current plugin configuration
meson configure build | grep plugin

# Example: disable RTP and enable MQTT explicitly
meson setup build -Dplugin-rtp=disabled -Dplugin-mqtt=enabled

# Reconfigure an existing build directory (no wipe needed)
meson setup build --reconfigure -Dplugin-omemo=disabled

# Alternative: meson configure (same effect)
meson configure build -Dplugin-omemo=disabled
```

| Meson Option | Default | Description | Dependency |
|---|---|---|---|
| `plugin-http-files` | enabled | HTTP file upload (XEP-0363) | -- |
| `plugin-ice` | enabled | Peer-to-peer connectivity (ICE/STUN/TURN) | libnice |
| `plugin-omemo` | enabled | End-to-end encryption (OMEMO) | libgcrypt, libsignal-protocol-c |
| `plugin-openpgp` | enabled | End-to-end encryption (OpenPGP/XEP-0373) | gpgme |
| `plugin-rtp` | enabled | Voice/video calls (Jingle RTP) | GStreamer, libnice, libsrtp2 |
| `plugin-notification-sound` | auto | Notification sounds | libcanberra |
| `plugin-rtp-h264` | auto | H.264 video codec for calls | GStreamer bad plugins |
| `plugin-rtp-msdk` | disabled | Intel MediaSDK hardware encoding | Intel Media SDK |
| `plugin-rtp-vaapi` | auto | VA-API hardware video acceleration | gstreamer-vaapi |
| `plugin-rtp-v4l2` | disabled | V4L2 stateful video codec | kernel V4L2 |
| `plugin-rtp-v4l2-sl` | auto | V4L2 stateless video codec | kernel V4L2 |
| `plugin-rtp-webrtc-audio-processing` | auto | Echo cancellation, noise suppression, AGC | webrtc-audio-processing |
| `plugin-mqtt` | auto | MQTT IoT/event integration | libmosquitto |

> **auto** = built if the required dependency is found, otherwise silently skipped.
> **enabled** = build fails if the dependency is missing.
> **disabled** = plugin is never built, even if the dependency is available.

### MQTT Plugin (Optional)

The MQTT plugin bridges IoT/event messages from an MQTT broker into XMPP conversations. It requires `libmosquitto` (the Mosquitto client library) at build time.

- **Meson option:** `plugin-mqtt` (default: `auto`)
- **Dependency:** `libmosquitto` (detected via pkg-config)
- When set to `auto` (default), the plugin is built if `libmosquitto` is found, otherwise silently skipped.

```bash
# Check if libmosquitto is available
pkg-config --modversion libmosquitto

# Verify MQTT plugin was built
meson configure build | grep mqtt
# Expected: plugin-mqtt  auto  [enabled]

# Force-disable MQTT plugin
meson setup build -Dplugin-mqtt=disabled

# Force-enable (fails if libmosquitto not installed)
meson setup build -Dplugin-mqtt=enabled
```

#### Install libmosquitto

`scripts/ci-build-deps.sh` builds **mosquitto 2.1.2** from source automatically (recommended). For manual install:

| Distro | Command | Version |
|--------|---------|---------|
| ci-build-deps.sh | `./scripts/ci-build-deps.sh` | **2.1.2** (recommended) |
| Debian/Ubuntu (apt) | `sudo apt install libmosquitto-dev` | 2.0.18 (older) |
| Fedora | `sudo dnf install mosquitto-devel` | varies |
| Arch Linux | `sudo pacman -S mosquitto` | latest |
| MSYS2 (Windows) | `pacman -S mingw-w64-x86_64-mosquitto` | latest |
| Flatpak | Built from source in manifest | **2.1.2** |

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
    mingw-w64-x86_64-mosquitto \
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
| `scripts/ci-build-deps.sh` | CI pipeline script: runs `scripts/scan_unicode.py`, then builds **SQLCipher** (with FTS5), **webrtc-audio-processing**, **libnice**, **protobuf-c**, **libomemo-c**, and **mosquitto** from source. Used in automated builds and AppImage CI to prepare dependencies. |
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
