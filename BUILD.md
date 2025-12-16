# Building DinoX from Source

This guide provides detailed instructions for building DinoX on various Linux distributions.

## General Requirements

*   **Compiler:** GCC or Clang
*   **Build System:** Meson (>= 0.56.0), Ninja
*   **Language:** Vala (>= 0.48)
*   **Toolkit:** GTK4, Libadwaita

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
- **webrtc-audio-processing (optional):** If present, it enables echo cancellation / noise suppression / AGC. DinoX builds and runs without it.

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
    libqrencode-dev \
    libsoup-3.0-dev \
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev \
    libgstreamer-plugins-bad1.0-dev \
    libwebrtc-audio-processing-dev \
    libnice-dev \
    libgnutls28-dev \
    libsrtp2-dev
```

### Fedora

```bash
sudo dnf install \
    gcc \
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
    qrencode-devel \
    libsoup3-devel \
    gstreamer1-devel \
    gstreamer1-plugins-base-devel \
    gstreamer1-plugins-bad-free-devel \
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
    qrencode \
    libsoup3 \
    gstreamer \
    gst-plugins-base \
    gst-plugins-bad \
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
