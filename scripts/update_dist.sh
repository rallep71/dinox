#!/bin/bash
set -e

echo "================================================"
echo "  DinoX Windows Distribution Builder"
echo "================================================"
echo ""

# Create clean directory structure
echo "[1/8] Creating directory structure..."
mkdir -p dist/bin
mkdir -p dist/lib
mkdir -p dist/plugins
mkdir -p dist/share/icons
mkdir -p dist/ssl/certs

# Clean up old messy files from dist/ root (from previous bad builds)
echo "[2/8] Cleaning up old files..."
rm -f dist/http-files.dll 2>/dev/null || true
rm -f dist/ice.dll 2>/dev/null || true
rm -f dist/openpgp.dll 2>/dev/null || true
rm -f dist/libtor-manager.dll 2>/dev/null || true
rm -f dist/notification-sound.dll 2>/dev/null || true
rm -f dist/rtp.dll 2>/dev/null || true
rm -f dist/omemo.dll 2>/dev/null || true
rm -f dist/obfs4proxy 2>/dev/null || true  # Linux version without .exe
rm -f dist/tor.exe 2>/dev/null || true     # Stale Linux ELF or old MSYS2 binary
rm -f dist/tor 2>/dev/null || true         # Linux binary without .exe

# ============================================
# Main executable (must be in dist/ root)
# ============================================
echo "[3/8] Copying main executable..."
cp build/main/dinox.exe dist/

# Remove legacy launcher script if present (dinox.exe handles everything now;
# keeping the .bat file caused confusion because it opens a CMD window).
rm -f dist/dinox.bat 2>/dev/null || true

# ============================================
# Core DLLs (must be next to dinox.exe for Windows DLL loading)
# ============================================
echo "[4/8] Copying Core DLLs..."
cp build/libdino/libdino-0.dll dist/
cp build/xmpp-vala/libxmpp-vala-0.dll dist/
cp build/qlite/libqlite-0.dll dist/
cp build/crypto-vala/libcrypto-vala-0.dll dist/
echo "  [OK] libdino-0.dll, libxmpp-vala-0.dll, libqlite-0.dll, libcrypto-vala-0.dll"

# ============================================
# System DLLs from MSYS2 (required for standalone Windows execution)
# ============================================
echo "[4b/8] Copying MSYS2 system DLLs..."
MINGW_BIN="/mingw64/bin"

# GTK4 and Adwaita
SYSTEM_DLLS=(
    # GTK4 core
    "libgtk-4-1.dll"
    "libadwaita-1-0.dll"
    "libgdk_pixbuf-2.0-0.dll"
    "libcairo-2.dll"
    "libcairo-gobject-2.dll"
    "libcairo-script-interpreter-2.dll"
    
    # Pango text rendering deps
    "libpango-1.0-0.dll"
    "libpangocairo-1.0-0.dll"
    "libpangowin32-1.0-0.dll"
    "libpangoft2-1.0-0.dll"
    "libthai-0.dll"
    "libdatrie-1.dll"
    
    # GLib family
    "libglib-2.0-0.dll"
    "libgobject-2.0-0.dll"
    "libgio-2.0-0.dll"
    "libgmodule-2.0-0.dll"
    "libgthread-2.0-0.dll"
    
    # Image format support
    "libpng16-16.dll"
    "libjpeg-8.dll"
    "libtiff-6.dll"
    "libwebp-7.dll"
    "libwebpdemux-2.dll"
    "librsvg-2-2.dll"
    
    # Graphics
    "libpixman-1-0.dll"
    "libfreetype-6.dll"
    "libfontconfig-1.dll"
    "libharfbuzz-0.dll"
    "libharfbuzz-gobject-0.dll"
    "libharfbuzz-subset-0.dll"
    "libfribidi-0.dll"
    "libgraphene-1.0-0.dll"
    "libepoxy-0.dll"
    
    # Compression
    "zlib1.dll"
    "libbz2-1.dll"
    "libbrotlidec.dll"
    "libbrotlicommon.dll"
    "liblzma-5.dll"
    "libzstd.dll"
    
    # Crypto/SSL
    "libssl-3-x64.dll"
    "libcrypto-3-x64.dll"
    "libgcrypt-20.dll"
    "libgpg-error-0.dll"
    "libassuan-0.dll"
    "libnpth-0.dll"
    "libgpgme-11.dll"
    
    # Network
    "libsoup-3.0-0.dll"
    "libnghttp2-14.dll"
    "libpsl-5.dll"
    "libidn2-0.dll"
    "libunistring-5.dll"
    
    # SQLite
    "libsqlite3-0.dll"
    
    # Other dependencies
    "libintl-8.dll"
    "libiconv-2.dll"
    "libpcre2-8-0.dll"
    "libffi-8.dll"
    "libexpat-1.dll"
    "libxml2-2.dll"
    "libsecret-1-0.dll"
    "libdeflate.dll"
    "libjbig-0.dll"
    "libLerc.dll"
    "libgraphite2.dll"
    "liblzo2-2.dll"
    "libsharpyuv-0.dll"
    "libnghttp3-9.dll"
    "libngtcp2-111.dll"
    "libngtcp2_crypto_ossl-0.dll"
    "libssh2-1.dll"
    
    # GStreamer (for RTP/audio)
    "libgstreamer-1.0-0.dll"
    "libgstbase-1.0-0.dll"
    "libgstaudio-1.0-0.dll"
    "libgstvideo-1.0-0.dll"
    "libgstsdp-1.0-0.dll"
    "libgstrtp-1.0-0.dll"
    "libgstwebrtc-1.0-0.dll"
    "libgstapp-1.0-0.dll"
    "libgstpbutils-1.0-0.dll"
    "libgstgl-1.0-0.dll"
    "libgstcodecs-1.0-0.dll"
    "libnice-10.dll"
    "liborc-0.4-0.dll"
    
    # Windows-specific
    "libwinpthread-1.dll"
    "libstdc++-6.dll"
    "libgcc_s_seh-1.dll"
    
    # ICU (internationalization - for webkit/soup)
    "libicuuc78.dll"
    "libicuin78.dll"
    "libicudt78.dll"
    
    # Gee (collections library)
    "libgee-0.8-2.dll"
    
    # QREncode
    "libqrencode-4.dll"
    
    # Audio/Video codecs (needed by GStreamer plugins)
    "libopus-0.dll"
    "libopenh264-7.dll"
    "libvpx-1.dll"
    
    # Vorbis/Ogg/FLAC (needed by matroska/WebM audio, voice messages)
    "libvorbis-0.dll"
    "libvorbisenc-2.dll"
    "libvorbisfile-3.dll"
    "libogg-0.dll"
    "libFLAC-12.dll"
    "libmpg123-0.dll"
    
    # Note: FFmpeg DLLs (libavcodec, etc.) are NOT listed here.
    # If mingw-w64-x86_64-ffmpeg is installed, the gst-libav plugin and
    # its FFmpeg deps are picked up automatically by step 4e (auto-detect).
    
    # Signal protocol (not in MSYS2's standard packages, built separately for OMEMO)
    # "libsignal-protocol-c-2.dll"
    
    # SRTPv2 for RTP
    "libsrtp2-1.dll"
    
    # AppStream (dependency of libadwaita/GTK4 on newer MSYS2)
    "libappstream-5.dll"
    "libcurl-4.dll"
    "libxmlb-2.dll"
    "libyaml-0-2.dll"
    
    # Additional GStreamer libs (transitive deps of RTP/video plugins)
    "libgstallocators-1.0-0.dll"
    "libgstd3d11-1.0-0.dll"
    "libgstd3d12-1.0-0.dll"
    "libgstd3dshader-1.0-0.dll"
    "libgstplay-1.0-0.dll"
    "libgstplayer-1.0-0.dll"
    "libgsttag-1.0-0.dll"
    "libgstfft-1.0-0.dll"
    
    # Signal protocol (OMEMO encryption)
    "libomemo-c-0.dll"
    
    # GnuTLS + deps (required by ice plugin / libnice for DTLS)
    "libgnutls-30.dll"
    "libnettle-8.dll"
    "libhogweed-6.dll"
    "libgmp-10.dll"
    "libtasn1-6.dll"
    "libp11-kit-0.dll"
    
    # JSON-GLib (required by tor-manager plugin)
    "libjson-glib-1.0-0.dll"
    
    # MQTT (required by mqtt plugin — pacman -S mingw-w64-x86_64-mosquitto)
    "libmosquitto.dll"
    "libprotobuf-c-1.dll"
    "libcjson-1.dll"
    
    # Tor async networking (transitive dep of tor.exe)
    # MSYS2 may use either libevent-2-1-7.dll or libevent-7.dll depending on version
    "libevent-2-1-7.dll"
    "libevent_core-2-1-7.dll"
    "libevent_extra-2-1-7.dll"
    "libevent-7.dll"
    "libevent_core-7.dll"
    "libevent_extra-7.dll"
    
    # SQLCipher (if using encrypted DB instead of plain sqlite)
    "libsqlcipher-0.dll"
)

# DLLs that are optional (statically linked or only present with certain packages)
OPTIONAL_DLLS=(
    "libomemo-c-0.dll"    # statically linked — only exists if built with BUILD_SHARED_LIBS
    "libyaml-0-2.dll"     # only present if mingw-w64-x86_64-libyaml is installed (AppStream dep)
)

DLL_COUNT=0
for dll in "${SYSTEM_DLLS[@]}"; do
    if [ -f "$MINGW_BIN/$dll" ]; then
        cp "$MINGW_BIN/$dll" dist/
        DLL_COUNT=$((DLL_COUNT + 1))
    else
        # Try alternative names (version numbers may differ)
        FOUND=false
        for alt in "$MINGW_BIN"/${dll%%-*}*.dll; do
            if [ -f "$alt" ]; then
                cp "$alt" dist/
                DLL_COUNT=$((DLL_COUNT + 1))
                FOUND=true
                break
            fi
        done
        if [ "$FOUND" = false ]; then
            # Check if this DLL is in the optional list
            IS_OPTIONAL=false
            for opt in "${OPTIONAL_DLLS[@]}"; do
                if [ "$dll" = "$opt" ]; then
                    IS_OPTIONAL=true
                    break
                fi
            done
            if [ "$IS_OPTIONAL" = true ]; then
                echo "  [INFO] Optional, not found: $dll"
            else
                echo "  [WARN] Not found: $dll"
            fi
        fi
    fi
done
echo "  [OK] $DLL_COUNT system DLLs copied"

# Copy GDK-Pixbuf loaders (for image format support)
# MUST copy into dist/lib/gdk-pixbuf-2.0/ (not dist/lib/) so the directory
# structure matches what GDK_PIXBUF_MODULEDIR points to.
if [ -d "/mingw64/lib/gdk-pixbuf-2.0" ]; then
    mkdir -p dist/lib/gdk-pixbuf-2.0
    cp -r /mingw64/lib/gdk-pixbuf-2.0/* dist/lib/gdk-pixbuf-2.0/
    echo "  [OK] GDK-Pixbuf loaders"
fi

# Copy GIO modules (for GVFS, etc.)
if [ -d "/mingw64/lib/gio" ]; then
    mkdir -p dist/lib/gio
    cp -r /mingw64/lib/gio/* dist/lib/gio/
    echo "  [OK] GIO modules"
fi

# Copy GStreamer plugins (for audio/video)
if [ -d "/mingw64/lib/gstreamer-1.0" ]; then
    # Clean old plugins to avoid stale DLLs from previous runs
    rm -rf dist/lib/gstreamer-1.0
    mkdir -p dist/lib/gstreamer-1.0
    # Only copy essential plugins to keep size manageable
    # Note: wasapi2 replaces both old wasapi and directsound on Windows 10+
    for plugin in coreelements audioconvert audioresample audiorate volume autodetect \
                  wasapi2 rtp rtpmanager srtp dtls nice webrtc \
                  opus vpx openh264 x264 voaac app audioparsers \
                  playback typefindfunctions videoconvert videoscale videofilter \
                  videorate videoparsersbad d3d11 d3d12 mediafoundation \
                  isomp4 audiofx libav \
                  videotestsrc audiotestsrc audiomixer \
                  matroska ogg vorbis flac wavparse gdkpixbuf \
                  mpg123 alaw mulaw; do
        for f in /mingw64/lib/gstreamer-1.0/*${plugin}*.dll; do
            [ -f "$f" ] && cp "$f" dist/lib/gstreamer-1.0/
        done
    done
    echo "  [OK] GStreamer plugins"
fi

# ============================================
# Plugins (loaded dynamically from plugins/)
# Copy BEFORE auto-detect so their dependencies get resolved too
# ============================================
echo "[4d/8] Copying DinoX Plugins..."
find build/plugins -name "*.dll" -exec cp {} dist/plugins/ \;
echo "  [OK] $(ls dist/plugins/*.dll 2>/dev/null | wc -l) plugins copied"

# Clean up any stale core DLLs that may have landed in plugins/ from earlier builds.
# These are NOT plugins and would cause "register_plugin not found" errors.
for core_dll in libdino-0.dll libxmpp-vala-0.dll libqlite-0.dll libcrypto-vala-0.dll; do
    rm -f "dist/plugins/$core_dll" 2>/dev/null
done

# ============================================
# Translation files (.mo) for in-app language switching
# Without these, gettext cannot find translations and the app stays English.
# Structure: dist/locale/<lang>/LC_MESSAGES/<package>.mo
# ============================================
echo "[4e/8] Copying translation files..."
MO_COUNT=0
# Main app translations (dino.mo)
for mo in build/main/po/*/LC_MESSAGES/dino.mo; do
    [ -f "$mo" ] || continue
    lang=$(echo "$mo" | sed 's|.*/po/\([^/]*\)/LC_MESSAGES/.*|\1|')
    mkdir -p "dist/locale/$lang/LC_MESSAGES"
    cp "$mo" "dist/locale/$lang/LC_MESSAGES/"
    MO_COUNT=$((MO_COUNT + 1))
done
# Plugin translations (dino-omemo.mo, dino-openpgp.mo, etc.)
for mo in build/plugins/*/po/*/LC_MESSAGES/*.mo; do
    [ -f "$mo" ] || continue
    lang=$(echo "$mo" | sed 's|.*/po/\([^/]*\)/LC_MESSAGES/.*|\1|')
    mkdir -p "dist/locale/$lang/LC_MESSAGES"
    cp "$mo" "dist/locale/$lang/LC_MESSAGES/"
    MO_COUNT=$((MO_COUNT + 1))
done
echo "  [OK] $MO_COUNT translation files copied"

# ============================================
# AUTO-DETECT missing DLL dependencies (recursive!)
# This scans ALL DLLs/EXEs in dist/ using objdump to find their
# imports, then copies any missing DLL from MSYS2's /mingw64/bin/.
# Repeats until no new DLLs are discovered (transitive resolution).
# This eliminates the need to manually track every dependency.
# ============================================
echo "[4e/8] Auto-detecting missing DLL dependencies..."
AUTO_COUNT=0
PASS=0
while true; do
    PASS=$((PASS + 1))
    FOUND_NEW=false
    
    # Collect all DLL imports from everything in dist/ including subdirs
    ALL_DEPS=$(objdump -p dist/*.dll dist/*.exe dist/plugins/*.dll \
        dist/lib/gstreamer-1.0/*.dll dist/lib/gio/modules/*.dll 2>/dev/null \
        | grep "DLL Name:" | awk '{print $3}' | sort -u)
    
    for dep_name in $ALL_DEPS; do
        # Skip if already in dist/
        [ -f "dist/$dep_name" ] && continue
        
        # Copy from MSYS2 if available (system DLLs like kernel32.dll
        # won't be in /mingw64/bin/ so they're skipped automatically)
        if [ -f "$MINGW_BIN/$dep_name" ]; then
            cp "$MINGW_BIN/$dep_name" dist/
            echo "  + Pass $PASS: $dep_name"
            AUTO_COUNT=$((AUTO_COUNT + 1))
            FOUND_NEW=true
        fi
    done
    
    # Stop when no new DLLs were found
    if [ "$FOUND_NEW" = false ]; then
        break
    fi
    
    # Safety: max 10 passes to avoid infinite loops
    if [ $PASS -ge 10 ]; then
        echo "  [WARN] Stopped after $PASS passes (safety limit)"
        break
    fi
done
if [ $AUTO_COUNT -gt 0 ]; then
    echo "  [OK] Auto-copied $AUTO_COUNT additional DLLs in $PASS passes"
else
    echo "  [OK] No missing dependencies detected"
fi

# ============================================
# Helper executables (all in bin/)
# ============================================
echo "[5/8] Copying helper executables to bin/..."

# GPG executables (for OpenPGP and encrypted backups)
if [ -f "/mingw64/bin/gpg.exe" ]; then
    cp /mingw64/bin/gpg.exe dist/bin/
    echo "  [OK] gpg.exe"
fi
if [ -f "/mingw64/bin/gpg-agent.exe" ]; then
    cp /mingw64/bin/gpg-agent.exe dist/bin/
    echo "  [OK] gpg-agent.exe"
fi
if [ -f "/mingw64/bin/gpgconf.exe" ]; then
    cp /mingw64/bin/gpgconf.exe dist/bin/
    echo "  [OK] gpgconf.exe"
fi
if [ -f "/mingw64/bin/pinentry-w32.exe" ]; then
    cp /mingw64/bin/pinentry-w32.exe dist/bin/
    echo "  [OK] pinentry-w32.exe"
elif [ -f "/usr/bin/pinentry-w32.exe" ]; then
    cp /usr/bin/pinentry-w32.exe dist/bin/
    echo "  [OK] pinentry-w32.exe"
fi

# GPGME spawn helper (needed by GPGME library - MUST be next to exe or in PATH)
if [ -f "/mingw64/bin/gpgme-w32spawn.exe" ]; then
    cp /mingw64/bin/gpgme-w32spawn.exe dist/bin/
    # ALSO copy to dist/ root as GPGME looks there first!
    cp /mingw64/bin/gpgme-w32spawn.exe dist/
    echo "  [OK] gpgme-w32spawn.exe (bin/ + root)"
elif command -v gpgme-w32spawn.exe &> /dev/null; then
    cp "$(command -v gpgme-w32spawn.exe)" dist/bin/
    cp "$(command -v gpgme-w32spawn.exe)" dist/
    echo "  [OK] gpgme-w32spawn.exe (bin/ + root)"
else
    echo "  [WARN] Warning: gpgme-w32spawn.exe not found!"
fi

# NOTE: Do NOT copy tar.exe! Windows 10+ has a built-in tar.exe in System32
# that works with native Windows paths. Our MSYS2 tar.exe has path conversion
# issues that cause "Cannot connect to C:" errors on user machines.
echo "  [INFO] tar.exe: Using Windows built-in (C:\\Windows\\System32\\tar.exe)"

# OpenSSL (for backup encryption - simpler than GPG, no agent needed)
if [ -f "/mingw64/bin/openssl.exe" ]; then
    cp /mingw64/bin/openssl.exe dist/bin/
    echo "  [OK] openssl.exe"
elif [ -f "/usr/bin/openssl.exe" ]; then
    cp /usr/bin/openssl.exe dist/bin/
    echo "  [OK] openssl.exe"
else
    echo "  [WARN] Warning: openssl.exe not found! Encrypted backups will not work."
fi

# Tor - MUST use MinGW64 native build, NOT the MSYS2/Cygwin version
# The MSYS2 /usr/bin/tor is a Cygwin binary that Windows reports as "16-bit incompatible"
if [ -f "/mingw64/bin/tor.exe" ]; then
    cp /mingw64/bin/tor.exe dist/bin/
    echo "  [OK] tor.exe (mingw64 native)"
elif command -v tor &> /dev/null; then
    TOR_PATH="$(which tor)"
    # Only use if it's from mingw64, not from /usr/bin (MSYS2/Cygwin)
    if [[ "$TOR_PATH" == /mingw64/* ]]; then
        cp "$TOR_PATH" dist/bin/tor.exe
        echo "  [OK] tor.exe"
    else
        echo "  [WARN] Warning: tor found at $TOR_PATH but it's not a native Windows build!"
        echo "    Install mingw-w64-x86_64-tor: pacman -S mingw-w64-x86_64-tor"
    fi
else
    echo "  [WARN] Warning: tor not found! Anonymous connections will not work."
    echo "    Install: pacman -S mingw-w64-x86_64-tor"
fi

# lyrebird (Tor pluggable transport: obfs4 + WebTunnel) — preferred over obfs4proxy
LYREBIRD_PATH=""
if [ -f "/mingw64/bin/lyrebird.exe" ]; then
    LYREBIRD_PATH="/mingw64/bin/lyrebird.exe"
elif [ -f "$HOME/go/bin/lyrebird.exe" ]; then
    LYREBIRD_PATH="$HOME/go/bin/lyrebird.exe"
elif command -v lyrebird.exe &> /dev/null; then
    LYREBIRD_PATH="$(which lyrebird.exe)"
fi

if [ -n "$LYREBIRD_PATH" ]; then
    cp "$LYREBIRD_PATH" dist/bin/lyrebird.exe
    echo "  [OK] lyrebird.exe (supports obfs4 + WebTunnel)"
else
    echo "  [WARN] Warning: lyrebird not found! WebTunnel bridges will not work."
    echo "    Build from source: go install gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/lyrebird/cmd/lyrebird@latest"
fi

# obfs4proxy (Tor bridge support — fallback if lyrebird is unavailable)
OBFS4_PATH=""
if [ -f "$HOME/go/bin/obfs4proxy.exe" ]; then
    OBFS4_PATH="$HOME/go/bin/obfs4proxy.exe"
elif [ -f "/mingw64/bin/obfs4proxy.exe" ]; then
    OBFS4_PATH="/mingw64/bin/obfs4proxy.exe"
elif command -v obfs4proxy.exe &> /dev/null; then
    OBFS4_PATH="$(which obfs4proxy.exe)"
fi

if [ -n "$OBFS4_PATH" ]; then
    cp "$OBFS4_PATH" dist/bin/obfs4proxy.exe
    echo "  [OK] obfs4proxy.exe (obfs4 fallback)"
else
    echo "  [INFO] obfs4proxy not found (lyrebird provides obfs4 support)"
fi

# Tor GeoIP data files (needed for bridge/country selection)
GEOIP_SRC=""
for gp in /mingw64/share/tor/geoip C:/msys64/mingw64/share/tor/geoip; do
    if [ -f "$gp" ]; then
        GEOIP_SRC="$(dirname "$gp")"
        break
    fi
done
if [ -n "$GEOIP_SRC" ]; then
    mkdir -p dist/share/tor
    cp "$GEOIP_SRC/geoip" dist/share/tor/ 2>/dev/null && echo "  [OK] geoip"
    cp "$GEOIP_SRC/geoip6" dist/share/tor/ 2>/dev/null && echo "  [OK] geoip6"
else
    echo "  [WARN] GeoIP files not found. Tor may have trouble selecting bridges."
fi

# ============================================
# Resources (share/)
# ============================================
echo "[6/8] Copying resources..."

# CA Certificates (needed for TLS)
CA_BUNDLE=""
for ca_path in /mingw64/ssl/certs/ca-bundle.crt \
               /mingw64/etc/ssl/certs/ca-bundle.crt \
               /etc/ssl/certs/ca-bundle.crt \
               /usr/ssl/certs/ca-bundle.crt \
               /mingw64/ssl/cert.pem; do
    if [ -f "$ca_path" ]; then
        CA_BUNDLE="$ca_path"
        break
    fi
done
if [ -n "$CA_BUNDLE" ]; then
    cp "$CA_BUNDLE" dist/ssl/certs/ca-bundle.crt
    cp "$CA_BUNDLE" dist/ca-bundle.crt
    echo "  [OK] CA certificates (from $CA_BUNDLE)"
else
    echo "  [WARN] No CA certificate bundle found! TLS connections may fail."
    echo "         Install: pacman -S ca-certificates"
fi

# GTK4 schemas (needed for settings)
if [ -d "/mingw64/share/glib-2.0/schemas" ]; then
    mkdir -p dist/share/glib-2.0/schemas
    cp /mingw64/share/glib-2.0/schemas/gschemas.compiled dist/share/glib-2.0/schemas/ 2>/dev/null || true
    cp /mingw64/share/glib-2.0/schemas/*.xml dist/share/glib-2.0/schemas/ 2>/dev/null || true
    echo "  [OK] GLib schemas"
fi

# Adwaita icons (needed for GTK4/libadwaita UI)
if [ -d "/mingw64/share/icons/Adwaita" ]; then
    mkdir -p dist/share/icons
    cp -r /mingw64/share/icons/Adwaita dist/share/icons/
    echo "  [OK] Adwaita icons"
fi

# Adwaita fonts (libadwaita 1.6+ uses Adwaita Sans/Mono)
if [ -d "/mingw64/share/fonts/adwaita" ]; then
    mkdir -p dist/share/fonts
    cp -r /mingw64/share/fonts/adwaita dist/share/fonts/
    echo "  [OK] Adwaita fonts"
elif [ -d "/mingw64/share/fonts/Adwaita" ]; then
    mkdir -p dist/share/fonts
    cp -r /mingw64/share/fonts/Adwaita dist/share/fonts/
    echo "  [OK] Adwaita fonts"
fi

# Fontconfig configuration (so bundled fonts are found)
mkdir -p dist/etc/fonts
if [ -d "/mingw64/etc/fonts" ]; then
    cp -r /mingw64/etc/fonts/* dist/etc/fonts/
    echo "  [OK] Fontconfig config copied from MSYS2"
fi
# Generate a proper fonts.conf that maps generic families to Windows fonts.
# Without this, fontconfig's "Sans" resolves to a random font (often
# "Microsoft Sans Serif" which looks terrible with freetype).
# This also ensures our bundled fonts dir and Windows system fonts are scanned.
mkdir -p dist/etc/fonts/conf.d
cat > dist/etc/fonts/fonts.conf <<'FCEOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>

  <!-- Font directories -->
  <dir>WINDOWSFONTDIR</dir>
  <dir prefix="relative">../share/fonts</dir>

  <!-- Cache directory -->
  <cachedir>LOCAL_APPDATA_FONTCONFIG_CACHE</cachedir>
  <cachedir prefix="xdg">fontconfig</cachedir>

  <!-- Map generic families to Windows system fonts -->
  <alias>
    <family>sans-serif</family>
    <prefer>
      <family>Segoe UI</family>
      <family>Arial</family>
      <family>Noto Sans</family>
    </prefer>
  </alias>

  <alias>
    <family>Sans</family>
    <prefer>
      <family>Segoe UI</family>
      <family>Arial</family>
    </prefer>
  </alias>

  <alias>
    <family>serif</family>
    <prefer>
      <family>Times New Roman</family>
      <family>Georgia</family>
      <family>Noto Serif</family>
    </prefer>
  </alias>

  <alias>
    <family>monospace</family>
    <prefer>
      <family>Consolas</family>
      <family>Cascadia Mono</family>
      <family>Courier New</family>
    </prefer>
  </alias>

  <alias>
    <family>system-ui</family>
    <prefer>
      <family>Segoe UI</family>
    </prefer>
  </alias>

  <!-- Default rendering: slight hinting + subpixel antialiasing -->
  <match target="font">
    <edit name="antialias" mode="assign"><bool>true</bool></edit>
    <edit name="hinting" mode="assign"><bool>true</bool></edit>
    <edit name="hintstyle" mode="assign"><const>hintslight</const></edit>
    <edit name="rgba" mode="assign"><const>rgb</const></edit>
    <edit name="lcdfilter" mode="assign"><const>lcddefault</const></edit>
  </match>

  <!-- Include additional conf files -->
  <include ignore_missing="yes" prefix="relative">conf.d</include>
  <include ignore_missing="yes" prefix="relative">local.conf</include>

</fontconfig>
FCEOF
echo "  [OK] Fontconfig fonts.conf created (Windows font aliases)"

# Keep local.conf as an override for bundled font paths
cat > dist/etc/fonts/local.conf <<'FCEOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <!-- Bundled DinoX fonts -->
  <dir prefix="relative">../share/fonts</dir>
  <dir>WINDOWSFONTDIR</dir>
</fontconfig>
FCEOF
echo "  [OK] Fontconfig local.conf created"

# Hicolor icons (fallback icon theme)
if [ -d "/mingw64/share/icons/hicolor" ]; then
    cp -r /mingw64/share/icons/hicolor dist/share/icons/
    echo "  [OK] Hicolor icons"
fi

# GTK4 settings — generate custom settings.ini for Windows.
# The MSYS2 default has no font rendering or decoration config.
mkdir -p dist/share/gtk-4.0
cat > dist/share/gtk-4.0/settings.ini <<'GTKEOF'
[Settings]
gtk-font-name=Segoe UI 10
gtk-hint-font-metrics=1
gtk-decoration-layout=close,minimize,maximize:
gtk-xft-antialias=1
gtk-xft-hinting=1
gtk-xft-hintstyle=hintslight
gtk-xft-rgba=rgb
GTKEOF
echo "  [OK] GTK settings (font, hinting, decoration layout)"

# Pixbuf loaders cache — regenerate for portable paths.
# The MSYS2 cache file has absolute paths like /mingw64/lib/... which
# won't exist on the user's machine.  gdk-pixbuf-query-loaders produces
# a cache with paths relative to the current directory.
if [ -d "dist/lib/gdk-pixbuf-2.0/2.10.0/loaders" ]; then
    if command -v gdk-pixbuf-query-loaders >/dev/null 2>&1; then
        GDK_PIXBUF_MODULEDIR="$(cd dist/lib/gdk-pixbuf-2.0/2.10.0/loaders && pwd -W 2>/dev/null || pwd)" \
            gdk-pixbuf-query-loaders > dist/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache
        echo "  [OK] Pixbuf loaders cache (regenerated for portable paths)"
    elif [ -f "/mingw64/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache" ]; then
        cp /mingw64/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache dist/lib/gdk-pixbuf-2.0/2.10.0/
        echo "  [OK] Pixbuf loaders cache (copied from MSYS2, paths may need relocation)"
    fi
fi

# Application icons — copy image files, NOT index.theme!
# CRITICAL: The system hicolor index.theme (copied above) lists ALL standard
# directories (scalable/actions, scalable/status, scalable/devices, etc.).
# The project's index.theme only lists */apps and would BREAK icon discovery
# for all custom dino-* and system icons in other categories.
if [ -d "main/data/icons/hicolor" ]; then
    for size_dir in main/data/icons/hicolor/*/; do
        [ -d "$size_dir" ] || continue
        size=$(basename "$size_dir")
        for cat_dir in "$size_dir"*/; do
            [ -d "$cat_dir" ] || continue
            cat=$(basename "$cat_dir")
            mkdir -p "dist/share/icons/hicolor/$size/$cat"
            cp "$cat_dir"* "dist/share/icons/hicolor/$size/$cat/" 2>/dev/null || true
        done
    done
    echo "  [OK] DinoX app icons (system index.theme preserved)"
fi

# Custom symbolic icons (dino-*, small-x-*, check-plain-*)
# These are also embedded in the GResource, but installing them to the hicolor
# theme on the filesystem ensures they are found even if GTK4's automatic
# resource_base_path icon discovery fails (common on Windows).
if [ -d "main/data/icons/scalable" ]; then
    for subdir in actions devices mimetypes status; do
        src="main/data/icons/scalable/$subdir"
        if [ -d "$src" ]; then
            mkdir -p "dist/share/icons/hicolor/scalable/$subdir"
            cp "$src"/*.svg "dist/share/icons/hicolor/scalable/$subdir/"
        fi
    done
    echo "  [OK] DinoX custom symbolic icons (hicolor fallback)"
fi

# Remove stale GTK3 icon-theme.cache files — these cause GTK4 to skip
# scanning directories for new icons on some systems.
find dist/share/icons -name 'icon-theme.cache' -delete 2>/dev/null || true

# ============================================
# Pre-generate GStreamer plugin registry cache
# Without this, the first start has to load+inspect every plugin DLL
# (~39 DLLs) which takes 30-60+ seconds on Windows.
# The registry is a binary cache of plugin capabilities (elements,
# formats, codecs). With a pre-built registry, Gst.init() just reads
# the cache file → start in <1 second.
# ============================================
echo "[6b/8] Pre-generating GStreamer registry cache..."
DIST_ABS="$(cd dist && pwd -W 2>/dev/null || pwd)"
GST_DIR="$DIST_ABS/lib/gstreamer-1.0"
GST_REG="$GST_DIR/registry.bin"
if [ -d "dist/lib/gstreamer-1.0" ] && command -v gst-inspect-1.0 >/dev/null 2>&1; then
    GST_PLUGIN_PATH="$GST_DIR" \
    GST_PLUGIN_SYSTEM_PATH="" \
    GST_REGISTRY="$GST_REG" \
    gst-inspect-1.0 >/dev/null 2>&1
    if [ -f "$GST_REG" ]; then
        REG_SIZE=$(du -h "$GST_REG" 2>/dev/null | cut -f1)
        echo "  [OK] Registry cache created ($REG_SIZE)"
    else
        echo "  [WARN] gst-inspect-1.0 ran but no registry file was created"
    fi
else
    echo "  [SKIP] gst-inspect-1.0 not found — registry will be built on first start"
fi

# ============================================
# Summary
# ============================================
echo ""
echo "[7/8] Build complete!"
echo ""
echo "Directory structure:"
echo "  dist/"
echo "  |-- dinox.exe              (main application - run this!)"
echo "  |-- *.dll                  (system + core libraries)"
echo "  |-- bin/"
echo "  |   |-- gpg.exe            (OpenPGP encryption)"
echo "  |   |-- openssl.exe        (backup encryption)"
echo "  |   |-- tor.exe            (anonymity)"
echo "  |   |-- lyrebird.exe       (obfs4 + WebTunnel bridges)"
echo "  |   \-- obfs4proxy.exe     (obfs4 bridge fallback)"
echo "  |-- lib/"
echo "  |   |-- gdk-pixbuf-2.0/    (image loaders)"
echo "  |   |-- gio/               (GIO modules)"
echo "  |   \-- gstreamer-1.0/     (audio/video plugins)"
echo "  |-- plugins/"
echo "  |   \-- *.dll              (DinoX feature plugins)"
echo "  |-- share/"
echo "  |   |-- glib-2.0/schemas/  (GSettings)"
echo "  |   \-- icons/             (Adwaita + app icons)"
echo "  \-- ssl/certs/             (CA certificates)"
echo ""
echo "To run: Double-click dinox.exe"
echo ""
