#!/bin/bash
set -e

# ============================================================================
# Custom dependency builder for CI
#
# TODO: Check periodically for newer versions!
# Current versions (last checked/verified: 2026-02-24):
#   SQLCipher              4.6.1   https://github.com/sqlcipher/sqlcipher/releases
#   webrtc-audio-processing v2.1   https://gitlab.freedesktop.org/pulseaudio/webrtc-audio-processing/-/tags
#   libnice                0.1.23  https://gitlab.freedesktop.org/libnice/libnice/-/tags
#   libomemo-c             (fork)  https://github.com/rallep71/libomemo-c
#
# When updating versions: bump the *_VER variables below. The CI cache
# key is derived from this file's hash, so any edit auto-invalidates caches.
# ============================================================================

# Checks if running as root, otherwise use sudo
SUDO=""
if [ "$(id -u)" != "0" ]; then
    SUDO="sudo"
fi

# Build parallelism
NINJA_ARGS=""
MAKE_ARGS="-j$(nproc)"
MESON_OPTS=""

echo "Running Unicode Security Scan..."
python3 scripts/scan_unicode.py

if [ $? -ne 0 ]; then
    echo "Unicode scan failed! Potential unsafe hidden chars found."
    exit 1
fi

echo "Building dependencies..."

# 1. SQLCipher with FTS5 support
# Ubuntu's libsqlcipher-dev lacks FTS5. Build from source to enable it.
echo "Building SQLCipher with FTS5..."
SQLCIPHER_VER=4.6.1
wget -q -O "sqlcipher-${SQLCIPHER_VER}.tar.gz" "https://github.com/sqlcipher/sqlcipher/archive/v${SQLCIPHER_VER}.tar.gz"
tar xf "sqlcipher-${SQLCIPHER_VER}.tar.gz"
cd "sqlcipher-${SQLCIPHER_VER}"
./configure --prefix=/usr --enable-tempstore=yes --enable-fts5 \
  CFLAGS="-DSQLITE_HAS_CODEC -DSQLITE_ENABLE_COLUMN_METADATA -DSQLITE_ENABLE_FTS3 -DSQLITE_ENABLE_FTS3_PARENTHESIS -DSQLITE_ENABLE_FTS4 -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_UNLOCK_NOTIFY -DSQLITE_ENABLE_DBSTAT_VTAB -DSQLITE_SOUNDEX" \
  LDFLAGS="-lcrypto"
make $MAKE_ARGS
$SUDO make install
$SUDO ldconfig
cd ..
rm -rf "sqlcipher-${SQLCIPHER_VER}" "sqlcipher-${SQLCIPHER_VER}.tar.gz"
echo "SQLCipher $(sqlcipher :memory: 'select sqlite_version();' 2>/dev/null) with FTS5 installed."

# 2. webrtc-audio-processing
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

# 3. libnice
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

# 4. libomemo-c
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
