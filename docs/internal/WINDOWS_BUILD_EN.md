# Building DinoX on Windows

Complete guide for compiling DinoX from GitHub source on Windows 10/11.

## Prerequisites

- Windows 10 or 11 (64-bit)
- Approx. 5 GB free disk space (MSYS2 + dependencies)
- Internet connection

---

## Step 1: Install MSYS2

1. Download and install MSYS2 from **https://www.msys2.org/** (default: `C:\msys64`)
2. **Important:** Open the **MINGW64** shell (not the MSYS or UCRT shell!)
   - Start Menu → "MSYS2 MINGW64"
   - The title bar must show **MINGW64**

---

## Step 2: Update the system

After the first launch of MINGW64, you **must** run the update twice:

```bash
pacman -Syu
```

The terminal will close automatically (because the MSYS2 runtime itself gets updated). This is normal. **Reopen the MINGW64 terminal** and run the same command again:

```bash
pacman -Syu
```

Only on this second run will MSYS2 actually download and install all package updates. Do **not** skip this step — otherwise the package databases are out of date and subsequent installs may fail with "Could not connect to server" errors.

---

## Step 3: Install all dependencies

Copy and paste this single command:

```bash
pacman -S --noconfirm \
    git \
    tar \
    base-devel \
    mingw-w64-x86_64-toolchain \
    mingw-w64-x86_64-vala \
    mingw-w64-x86_64-meson \
    mingw-w64-x86_64-ninja \
    mingw-w64-x86_64-pkgconf \
    mingw-w64-x86_64-cmake \
    mingw-w64-x86_64-python \
    mingw-w64-x86_64-gtk4 \
    mingw-w64-x86_64-libadwaita \
    mingw-w64-x86_64-glib2 \
    mingw-w64-x86_64-glib-networking \
    mingw-w64-x86_64-gdk-pixbuf2 \
    mingw-w64-x86_64-libgee \
    mingw-w64-x86_64-libsoup3 \
    mingw-w64-x86_64-json-glib \
    mingw-w64-x86_64-sqlcipher \
    mingw-w64-x86_64-sqlite3 \
    mingw-w64-x86_64-icu \
    mingw-w64-x86_64-libgcrypt \
    mingw-w64-x86_64-gpgme \
    mingw-w64-x86_64-gnutls \
    mingw-w64-x86_64-qrencode \
    mingw-w64-x86_64-libsecret \
    mingw-w64-x86_64-libsrtp \
    mingw-w64-x86_64-libnice \
    mingw-w64-x86_64-gstreamer \
    mingw-w64-x86_64-gst-plugins-base \
    mingw-w64-x86_64-gst-plugins-good \
    mingw-w64-x86_64-gst-plugins-bad \
    mingw-w64-x86_64-gst-libav \
    mingw-w64-x86_64-opus \
    mingw-w64-x86_64-openh264 \
    mingw-w64-x86_64-libvpx \
    mingw-w64-x86_64-protobuf-c \
    mingw-w64-x86_64-openssl \
    mingw-w64-x86_64-librsvg \
    mingw-w64-x86_64-hicolor-icon-theme \
    mingw-w64-x86_64-adwaita-icon-theme \
    mingw-w64-x86_64-cantarell-fonts \
    mingw-w64-x86_64-mosquitto \
    mingw-w64-x86_64-tor \
    mingw-w64-x86_64-go \
    mingw-w64-x86_64-imagemagick
```

> When prompted with `(default=all)`, just press Enter.
>
> **Note:** Warnings like "dependency cycle detected" (harfbuzz/freetype, libwebp/libtiff) are normal and harmless — these are known circular dependencies in MSYS2 that pacman resolves correctly.

---

## Step 4: Build lyrebird (Tor pluggable transport)

Lyrebird provides obfs4 + WebTunnel support for Tor and is not available as an MSYS2 package:

```bash
cd /tmp
LYREBIRD_VER=0.8.1
LYREBIRD_TAG="lyrebird-${LYREBIRD_VER}"
curl -sL -o "lyrebird-${LYREBIRD_VER}.tar.gz" \
  "https://gitlab.torproject.org/api/v4/projects/417/repository/archive.tar.gz?sha=${LYREBIRD_TAG}"
tar xf "lyrebird-${LYREBIRD_VER}.tar.gz"
cd lyrebird-${LYREBIRD_TAG}-*
CGO_ENABLED=0 go build -trimpath -ldflags '-s -w' -o lyrebird.exe ./cmd/lyrebird
cp lyrebird.exe /mingw64/bin/
lyrebird.exe --version
```

---

## Step 5: Build webrtc-audio-processing v2.1

MSYS2 only provides version 1.x, but DinoX needs v2.1 for the best audio quality during calls. Must be built from source:

```bash
cd /tmp
WEBRTC_VER=2.1
curl -sL -o "webrtc-audio-processing-${WEBRTC_VER}.tar.gz" \
  "https://freedesktop.org/software/pulseaudio/webrtc-audio-processing/webrtc-audio-processing-${WEBRTC_VER}.tar.gz"
tar xf "webrtc-audio-processing-${WEBRTC_VER}.tar.gz"
cd "webrtc-audio-processing-${WEBRTC_VER}"
# Fix for GCC 13+: Starting with this version, #include <cstdint> is no
# longer implicitly included via other headers. Without this fix you get
# compile errors ("uint32_t / int64_t was not declared"). The sed command
# inserts the missing line at the top of each affected file.
for f in webrtc/rtc_base/trace_event.h \
         webrtc/modules/audio_processing/aec3/multi_channel_content_detector.h; do
    if ! grep -q '#include <cstdint>' "$f" 2>/dev/null; then
        sed -i '1s|^|#include <cstdint>\n|' "$f"
    fi
done
# Fix for abseil-cpp >= 20250814: Newer versions define absl::Nullable and
# absl::Nonnull annotations that webrtc v2.1 doesn't understand. Without this
# fix you get compile errors ("absl::Nullable has not been declared").
# The sed command strips the annotations, leaving just the raw pointer type.
sed -i 's/absl::Nullable<\([^>]*\)>/\1/g; s/absl::Nonnull<\([^>]*\)>/\1/g' \
    webrtc/api/scoped_refptr.h \
    webrtc/api/make_ref_counted.h \
    webrtc/api/audio/audio_processing.h \
    webrtc/modules/audio_processing/aec_dump/aec_dump_factory.h \
    webrtc/modules/audio_processing/aec_dump/null_aec_dump_factory.cc \
    webrtc/modules/audio_processing/audio_processing_impl.cc \
    webrtc/modules/audio_processing/audio_processing_impl.h
# Fix for MinGW: windows.h pulls in winsock.h (v1) which conflicts with
# winsock2.h. WIN32_LEAN_AND_MEAN does not help on MinGW (only on MSVC).
# The warning is harmless, so we suppress it with -Wno-cpp.
python3 << 'PYEOF'
import re
text = open('meson.build').read()
text = re.sub(r"\nadd_global_arguments[^\n]*Wno-cpp[^\n]*\n", '\n', text)
m = re.search(r"^\)", text, re.MULTILINE)
if m:
    pos = m.end()
    text = text[:pos] + "\nadd_global_arguments('-Wno-cpp', language: ['c', 'cpp'])" + text[pos:]
open('meson.build', 'w').write(text)
PYEOF
grep 'Wno-cpp' meson.build  # Must appear exactly once
meson setup build --wipe --prefix=/mingw64
ninja -C build
ninja -C build install
pkg-config --modversion webrtc-audio-processing-2
```

---

## Step 6: Build libomemo-c (OMEMO encryption)

libomemo-c is not available in the MSYS2 repos and must be built from source:

```bash
cd /tmp
git clone --depth 1 https://github.com/rallep71/libomemo-c.git
cd libomemo-c
mkdir build && cd build
cmake -G Ninja \
    -DCMAKE_INSTALL_PREFIX=/mingw64 \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    ..
ninja
ninja install
```

Verify it is detected:

```bash
pkg-config --modversion libomemo-c
```

Should output `0.5.1` (or higher).

---

## Step 7: Clone the DinoX source code

```bash
cd ~
git clone https://github.com/rallep71/dinox.git
cd dinox
```

---

## Step 8: Windows icon (only if icons changed)

The file `main/data/dinox.ico` is already included in the repo. This step is only needed if you changed the app icons and want to regenerate the `.ico`:

```bash
magick \
    main/data/icons/hicolor/16x16/apps/im.github.rallep71.DinoX.png \
    main/data/icons/hicolor/32x32/apps/im.github.rallep71.DinoX.png \
    main/data/icons/hicolor/48x48/apps/im.github.rallep71.DinoX.png \
    main/data/icons/hicolor/128x128/apps/im.github.rallep71.DinoX.png \
    main/data/icons/hicolor/256x256/apps/im.github.rallep71.DinoX.png \
    main/data/dinox.ico
```

---

## Step 9: Configure (Meson)

```bash
meson setup build \
    -Dplugin-omemo=enabled \
    -Dplugin-rtp=enabled \
    -Dplugin-openpgp=enabled \
    -Dplugin-ice=enabled \
    -Dplugin-http-files=enabled
```

Meson will list all found dependencies at the end. Check that no important ones are marked `NO`.

---

## Step 10: Compile

```bash
ninja -C build
```

The build takes a few minutes. When done, `dinox.exe` will be at `build/main/`.

---

## Step 11: Create distribution bundle

This script collects the EXE, all required DLLs, plugins, icons and data:

```bash
bash scripts/update_dist.sh
```

Everything ends up in the `dist/` folder.

---

## Step 12: Run

```bash
./dist/dinox.exe
```

Or copy the `dist/` folder anywhere and run `dinox.exe` directly — no installation required.

---

## Debug mode

If you encounter problems, start with debug output:

```bash
G_MESSAGES_DEBUG=all ./dist/dinox.exe 2>&1 | tee dinox-debug.log
```

The file `dinox-debug.log` will contain all diagnostic information.

---

## Rebuilding after code changes

For code-only changes (no new dependencies):

```bash
cd ~/dinox
ninja -C build
bash scripts/update_dist.sh
```

If `meson.build` or `meson_options.txt` changed:

```bash
meson setup build --wipe
ninja -C build
bash scripts/update_dist.sh
```

---

## Quick reference (all commands)

For the impatient — everything from step 3 onward in one block:

```bash
# Dependencies (Step 3)
pacman -S --noconfirm git tar base-devel \
    mingw-w64-x86_64-{toolchain,vala,meson,ninja,pkgconf,cmake,python} \
    mingw-w64-x86_64-{gtk4,libadwaita,glib2,glib-networking,gdk-pixbuf2,libgee} \
    mingw-w64-x86_64-{libsoup3,json-glib,sqlcipher,sqlite3,icu} \
    mingw-w64-x86_64-{libgcrypt,gpgme,gnutls,qrencode,libsecret,libsrtp,libnice} \
    mingw-w64-x86_64-{gstreamer,gst-plugins-base,gst-plugins-good,gst-plugins-bad,gst-libav} \
    mingw-w64-x86_64-{opus,openh264,libvpx,protobuf-c} \
    mingw-w64-x86_64-{openssl,librsvg,hicolor-icon-theme,adwaita-icon-theme,cantarell-fonts} \
    mingw-w64-x86_64-{mosquitto,tor,go,imagemagick}

# Lyrebird (Step 4)
cd /tmp
LYREBIRD_VER=0.8.1 && LYREBIRD_TAG="lyrebird-${LYREBIRD_VER}"
curl -sL -o "lyrebird-${LYREBIRD_VER}.tar.gz" \
  "https://gitlab.torproject.org/api/v4/projects/417/repository/archive.tar.gz?sha=${LYREBIRD_TAG}"
tar xf "lyrebird-${LYREBIRD_VER}.tar.gz"
cd lyrebird-${LYREBIRD_TAG}-* && CGO_ENABLED=0 go build -trimpath -ldflags '-s -w' -o lyrebird.exe ./cmd/lyrebird
cp lyrebird.exe /mingw64/bin/

# webrtc-audio-processing v2.1 (Step 5)
cd /tmp
WEBRTC_VER=2.1
curl -sL -o "webrtc-audio-processing-${WEBRTC_VER}.tar.gz" \
  "https://freedesktop.org/software/pulseaudio/webrtc-audio-processing/webrtc-audio-processing-${WEBRTC_VER}.tar.gz"
tar xf "webrtc-audio-processing-${WEBRTC_VER}.tar.gz" && cd "webrtc-audio-processing-${WEBRTC_VER}"
for f in webrtc/rtc_base/trace_event.h \
         webrtc/modules/audio_processing/aec3/multi_channel_content_detector.h; do
    if ! grep -q '#include <cstdint>' "$f" 2>/dev/null; then
        sed -i '1s|^|#include <cstdint>\n|' "$f"
    fi
done
sed -i 's/absl::Nullable<\([^>]*\)>/\1/g; s/absl::Nonnull<\([^>]*\)>/\1/g' \
    webrtc/api/scoped_refptr.h webrtc/api/make_ref_counted.h \
    webrtc/api/audio/audio_processing.h \
    webrtc/modules/audio_processing/aec_dump/aec_dump_factory.h \
    webrtc/modules/audio_processing/aec_dump/null_aec_dump_factory.cc \
    webrtc/modules/audio_processing/audio_processing_impl.cc \
    webrtc/modules/audio_processing/audio_processing_impl.h
python3 << 'PYEOF'
import re
text = open('meson.build').read()
text = re.sub(r"\nadd_global_arguments[^\n]*Wno-cpp[^\n]*\n", '\n', text)
m = re.search(r"^\)", text, re.MULTILINE)
if m:
    pos = m.end()
    text = text[:pos] + "\nadd_global_arguments('-Wno-cpp', language: ['c', 'cpp'])" + text[pos:]
open('meson.build', 'w').write(text)
PYEOF
meson setup build --wipe --prefix=/mingw64 && ninja -C build && ninja -C build install
cd /tmp && git clone --depth 1 https://github.com/rallep71/libomemo-c.git
cd libomemo-c && mkdir build && cd build
cmake -G Ninja -DCMAKE_INSTALL_PREFIX=/mingw64 -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 ..
ninja && ninja install

# Clone and build DinoX (Steps 7-11)
cd ~ && git clone https://github.com/rallep71/dinox.git && cd dinox
meson setup build -Dplugin-omemo=enabled -Dplugin-rtp=enabled -Dplugin-openpgp=enabled -Dplugin-ice=enabled -Dplugin-http-files=enabled
ninja -C build
bash scripts/update_dist.sh

# Rebuild (if repo already exists)
cd ~/dinox && git pull
# Code-only changes:
ninja -C build && bash scripts/update_dist.sh
# If meson.build changed (--wipe reconfigures completely):
meson setup build --wipe -Dplugin-omemo=enabled -Dplugin-rtp=enabled -Dplugin-openpgp=enabled -Dplugin-ice=enabled -Dplugin-http-files=enabled
ninja -C build && bash scripts/update_dist.sh
# If --wipe fails (corrupt build directory):
rm -rf build
meson setup build -Dplugin-omemo=enabled -Dplugin-rtp=enabled -Dplugin-openpgp=enabled -Dplugin-ice=enabled -Dplugin-http-files=enabled
ninja -C build && bash scripts/update_dist.sh

# Run
./dist/dinox.exe
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `command not found: meson` | Wrong shell? Must be **MINGW64**, not MSYS |
| `libomemo-c not found` | Repeat step 5 (build libomemo-c) |
| `webrtc-audio-processing not found` | Not critical — skipped with `auto`, calls still work |
| Terminal closes during `pacman -Syu` | Normal — reopen terminal, run `pacman -Su` |
| `ninja: error: loading 'build.ninja'` | Run `meson setup build` first |
| Missing DLLs on startup | Run `bash scripts/update_dist.sh` again |
| `couldn't load font "Adwaita Mono"` | Install `pacman -S mingw-w64-x86_64-cantarell-fonts` and re-run `update_dist.sh` |
