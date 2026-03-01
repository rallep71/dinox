#!/bin/bash
set -e

# ============================================================================
# Custom dependency builder for CI
#
# Usage:
#   ./scripts/ci-build-deps.sh           Build & install all dependencies
#   ./scripts/ci-build-deps.sh --clean   Remove previously installed dependencies
#
# TODO: Check periodically for newer versions!
# Current versions (last checked/verified: 2025-06-25):
#   SQLCipher              4.6.1   https://github.com/sqlcipher/sqlcipher/releases
#   webrtc-audio-processing v2.1   https://gitlab.freedesktop.org/pulseaudio/webrtc-audio-processing/-/tags
#   libnice                0.1.23  https://gitlab.freedesktop.org/libnice/libnice/-/tags
#   protobuf-c             1.5.2   https://github.com/protobuf-c/protobuf-c/releases
#   libomemo-c             (fork)  https://github.com/rallep71/libomemo-c
#   mosquitto              2.1.2   https://mosquitto.org/download/
#
# When updating versions: bump the *_VER variables below. The CI cache
# key is derived from this file's hash, so any edit auto-invalidates caches.
# ============================================================================

# Checks if running as root, otherwise use sudo
SUDO=""
if [ "$(id -u)" != "0" ]; then
    SUDO="sudo"
fi

# ---------------------------------------------------------------------------
# --clean mode: remove all previously installed custom dependencies
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--clean" ]]; then
    echo "Cleaning custom-built dependencies..."

    # SQLCipher
    $SUDO rm -f  /usr/bin/sqlcipher
    $SUDO rm -f  /usr/lib/libsqlcipher*
    $SUDO rm -rf /usr/include/sqlcipher
    $SUDO rm -f  /usr/lib/pkgconfig/sqlcipher.pc

    # webrtc-audio-processing
    $SUDO rm -f  /usr/lib/x86_64-linux-gnu/libwebrtc-audio-processing-1*
    $SUDO rm -f  /usr/lib/libwebrtc-audio-processing-1*
    $SUDO rm -rf /usr/include/webrtc-audio-processing-1
    $SUDO rm -f  /usr/lib/x86_64-linux-gnu/pkgconfig/webrtc-audio-processing-1.pc
    $SUDO rm -f  /usr/lib/pkgconfig/webrtc-audio-processing-1.pc
    $SUDO rm -f  /usr/lib/x86_64-linux-gnu/libwebrtc-audio-coding-1*
    $SUDO rm -f  /usr/lib/libwebrtc-audio-coding-1*
    $SUDO rm -f  /usr/lib/x86_64-linux-gnu/pkgconfig/webrtc-audio-coding-1.pc
    $SUDO rm -f  /usr/lib/pkgconfig/webrtc-audio-coding-1.pc

    # libnice
    $SUDO rm -f  /usr/lib/x86_64-linux-gnu/libnice*
    $SUDO rm -f  /usr/lib/libnice*
    $SUDO rm -rf /usr/include/nice
    $SUDO rm -rf /usr/include/stun
    $SUDO rm -f  /usr/lib/x86_64-linux-gnu/pkgconfig/nice.pc
    $SUDO rm -f  /usr/lib/pkgconfig/nice.pc
    $SUDO rm -f  /usr/lib/x86_64-linux-gnu/girepository-1.0/Nice-0.1.typelib
    $SUDO rm -f  /usr/lib/girepository-1.0/Nice-0.1.typelib
    $SUDO rm -f  /usr/share/gir-1.0/Nice-0.1.gir

    # protobuf-c
    $SUDO rm -f  /usr/lib/libprotobuf-c*
    $SUDO rm -rf /usr/include/protobuf-c
    $SUDO rm -f  /usr/lib/pkgconfig/libprotobuf-c.pc
    $SUDO rm -f  /usr/include/google/protobuf-c/protobuf-c.h

    # libomemo-c
    $SUDO rm -f  /usr/lib/libomemo-c*
    $SUDO rm -rf /usr/include/omemo

    # mosquitto
    $SUDO rm -f  /usr/lib/libmosquitto*
    $SUDO rm -f  /usr/include/mosquitto.h
    $SUDO rm -f  /usr/include/mosquitto_broker.h
    $SUDO rm -f  /usr/include/mosquitto_plugin.h
    $SUDO rm -f  /usr/include/mqtt_protocol.h
    $SUDO rm -f  /usr/lib/pkgconfig/libmosquitto.pc
    $SUDO rm -f  /usr/lib/pkgconfig/libmosquittopp.pc

    $SUDO ldconfig
    echo "Custom dependencies removed."
    exit 0
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
# Fix for abseil-cpp >= 20250814: Nullability template aliases (absl::Nullable<T>,
# absl::Nonnull<T>, absl::NullabilityUnknown<T>) were removed. They were identity
# aliases (using Nullable = T;) so stripping them is a no-op semantically.
# Upstream hasn't fixed this yet (as of master 2026-03).
find webrtc -name '*.h' -o -name '*.cc' | \
    xargs perl -pi -e 's/absl::(Nullable|Nonnull|NullabilityUnknown)<((?:[^<>]|<(?:[^<>]|<[^<>]*>)*>)*)>/\2/g'
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

# 4. protobuf-c (runtime library only, no compiler — avoids protobuf C++ dependency)
# Ubuntu 24.04 ships 1.4.1 which has a memory corruption bug in protobuf_c_message_unpack()
# fixed in 1.5.1 (PR #703). Build 1.5.2 from source.
echo "Building protobuf-c..."
PROTOBUFC_VER=1.5.2
wget -q -O "protobuf-c-${PROTOBUFC_VER}.tar.gz" "https://github.com/protobuf-c/protobuf-c/releases/download/v${PROTOBUFC_VER}/protobuf-c-${PROTOBUFC_VER}.tar.gz"
tar xf "protobuf-c-${PROTOBUFC_VER}.tar.gz"
cd "protobuf-c-${PROTOBUFC_VER}"
./configure --prefix=/usr --disable-protoc
make $MAKE_ARGS
$SUDO make install
$SUDO ldconfig
cd ..
rm -rf "protobuf-c-${PROTOBUFC_VER}" "protobuf-c-${PROTOBUFC_VER}.tar.gz"
echo "protobuf-c $(pkg-config --modversion libprotobuf-c 2>/dev/null || echo '?') installed."

# 5. libomemo-c
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

# 6. mosquitto (client library only — no broker, no CLI tools)
# Ubuntu 24.04 ships 2.0.18; build 2.1.2 for latest security & protocol fixes.
echo "Building mosquitto..."
MOSQUITTO_VER=2.1.2
wget -q -O "mosquitto-${MOSQUITTO_VER}.tar.gz" "https://mosquitto.org/files/source/mosquitto-${MOSQUITTO_VER}.tar.gz"
tar xf "mosquitto-${MOSQUITTO_VER}.tar.gz"
cd "mosquitto-${MOSQUITTO_VER}"
cmake -DCMAKE_INSTALL_PREFIX=/usr \
      -DWITH_BROKER=OFF \
      -DWITH_CLIENTS=OFF \
      -DWITH_APPS=OFF \
      -DWITH_PLUGINS=OFF \
      -DWITH_TESTS=OFF \
      -DWITH_DOCS=OFF \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
      .
make $MAKE_ARGS
$SUDO make install
$SUDO ldconfig
cd ..
rm -rf "mosquitto-${MOSQUITTO_VER}" "mosquitto-${MOSQUITTO_VER}.tar.gz"
echo "mosquitto $(pkg-config --modversion libmosquitto 2>/dev/null || echo '?') installed."

echo "Dependencies built and installed."
