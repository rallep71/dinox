#!/bin/bash
set -e

# Checks if running as root, otherwise use sudo
SUDO=""
if [ "$(id -u)" != "0" ]; then
    SUDO="sudo"
fi

# Detect System Architecture for Parallelism Control
ARCH="$(uname -m)"
MESON_OPTS=""
if [ "$ARCH" == "aarch64" ]; then
    echo "Running on aarch64 - Limiting parallelism and optimization to avoid OOM/Segfaults"
    # Switch to Clang for better memory efficiency with templates
    export CC=clang
    export CXX=clang++
    
    NINJA_ARGS="-j 1"
    MAKE_ARGS="-j 1"
    # Reduce optimization to save memory/prevent compiler crashes in QEMU
    # Also disable debug info (-g) to reduce memory usage during linking
    MESON_OPTS="-Doptimization=0 -Ddebug=false"
else
    NINJA_ARGS=""
    MAKE_ARGS="-j$(nproc)"
fi

echo "Running Unicode Security Scan..."
python3 scripts/scan_unicode.py

if [ $? -ne 0 ]; then
    echo "Unicode scan failed! Potential unsafe hidden chars found."
    exit 1
fi

echo "Building dependencies..."

# 1. webrtc-audio-processing
echo "Building webrtc-audio-processing..."
WEBRTC_VER=v2.1
wget -O "webrtc-audio-processing-${WEBRTC_VER}.tar.gz" "https://gitlab.freedesktop.org/pulseaudio/webrtc-audio-processing/-/archive/${WEBRTC_VER}/webrtc-audio-processing-${WEBRTC_VER}.tar.gz"
tar xf "webrtc-audio-processing-${WEBRTC_VER}.tar.gz"
cd "webrtc-audio-processing-${WEBRTC_VER}"
meson setup build --prefix=/usr $MESON_OPTS
ninja -C build $NINJA_ARGS
$SUDO ninja -C build install
$SUDO ldconfig
cd ..
rm -rf "webrtc-audio-processing-${WEBRTC_VER}" "webrtc-audio-processing-${WEBRTC_VER}.tar.gz"

# 2. libnice
echo "Building libnice..."
LIBNICE_VER=0.1.23
wget -O "libnice-${LIBNICE_VER}.tar.gz" "https://gitlab.freedesktop.org/libnice/libnice/-/archive/${LIBNICE_VER}/libnice-${LIBNICE_VER}.tar.gz"
tar xf "libnice-${LIBNICE_VER}.tar.gz"
cd "libnice-${LIBNICE_VER}"
meson setup build --prefix=/usr -Dtests=disabled -Dgtk_doc=disabled $MESON_OPTS
ninja -C build $NINJA_ARGS
$SUDO ninja -C build install
$SUDO ldconfig
cd ..
rm -rf "libnice-${LIBNICE_VER}" "libnice-${LIBNICE_VER}.tar.gz"

# 3. libomemo-c
echo "Building libomemo-c..."
if [ -d "libomemo-c" ]; then rm -rf libomemo-c; fi
git clone https://github.com/rallep71/libomemo-c.git
cd libomemo-c
mkdir build
cd build
cmake -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_POSITION_INDEPENDENT_CODE=ON ..
make $MAKE_ARGS
$SUDO make install
$SUDO ldconfig
cd ../..
rm -rf libomemo-c

echo "Dependencies built and installed."
