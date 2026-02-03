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

# ============================================
# Main executable (must be in dist/ root)
# ============================================
echo "[3/8] Copying main executable..."
cp build/main/dinox.exe dist/

# ============================================
# Core DLLs (must be next to dinox.exe for Windows DLL loading)
# ============================================
echo "[4/8] Copying Core DLLs..."
cp build/libdino/libdino-0.dll dist/
cp build/xmpp-vala/libxmpp-vala-0.dll dist/
cp build/qlite/libqlite-0.dll dist/
cp build/crypto-vala/libcrypto-vala-0.dll dist/
echo "  ✓ libdino-0.dll, libxmpp-vala-0.dll, libqlite-0.dll, libcrypto-vala-0.dll"

# ============================================
# Plugins (loaded dynamically from plugins/)
# ============================================
echo "[5/8] Copying Plugins..."
find build/plugins -name "*.dll" -exec cp {} dist/plugins/ \;
echo "  ✓ $(ls dist/plugins/*.dll 2>/dev/null | wc -l) plugins copied"

# ============================================
# Helper executables (all in bin/)
# ============================================
echo "[6/8] Copying helper executables to bin/..."

# GPG executables (for OpenPGP and encrypted backups)
if [ -f "/mingw64/bin/gpg.exe" ]; then
    cp /mingw64/bin/gpg.exe dist/bin/
    echo "  ✓ gpg.exe"
fi
if [ -f "/mingw64/bin/gpg-agent.exe" ]; then
    cp /mingw64/bin/gpg-agent.exe dist/bin/
    echo "  ✓ gpg-agent.exe"
fi
if [ -f "/mingw64/bin/gpgconf.exe" ]; then
    cp /mingw64/bin/gpgconf.exe dist/bin/
    echo "  ✓ gpgconf.exe"
fi
if [ -f "/mingw64/bin/pinentry-w32.exe" ]; then
    cp /mingw64/bin/pinentry-w32.exe dist/bin/
    echo "  ✓ pinentry-w32.exe"
elif [ -f "/usr/bin/pinentry-w32.exe" ]; then
    cp /usr/bin/pinentry-w32.exe dist/bin/
    echo "  ✓ pinentry-w32.exe"
fi

# GPGME spawn helper (needed by GPGME library - MUST be next to exe or in PATH)
if [ -f "/mingw64/bin/gpgme-w32spawn.exe" ]; then
    cp /mingw64/bin/gpgme-w32spawn.exe dist/bin/
    # ALSO copy to dist/ root as GPGME looks there first!
    cp /mingw64/bin/gpgme-w32spawn.exe dist/
    echo "  ✓ gpgme-w32spawn.exe (bin/ + root)"
elif command -v gpgme-w32spawn.exe &> /dev/null; then
    cp "$(command -v gpgme-w32spawn.exe)" dist/bin/
    cp "$(command -v gpgme-w32spawn.exe)" dist/
    echo "  ✓ gpgme-w32spawn.exe (bin/ + root)"
else
    echo "  ⚠ Warning: gpgme-w32spawn.exe not found!"
fi

# NOTE: Do NOT copy tar.exe! Windows 10+ has a built-in tar.exe in System32
# that works with native Windows paths. Our MSYS2 tar.exe has path conversion
# issues that cause "Cannot connect to C:" errors on user machines.
echo "  ℹ tar.exe: Using Windows built-in (C:\\Windows\\System32\\tar.exe)"

# OpenSSL (for backup encryption - simpler than GPG, no agent needed)
if [ -f "/mingw64/bin/openssl.exe" ]; then
    cp /mingw64/bin/openssl.exe dist/bin/
    echo "  ✓ openssl.exe"
elif [ -f "/usr/bin/openssl.exe" ]; then
    cp /usr/bin/openssl.exe dist/bin/
    echo "  ✓ openssl.exe"
else
    echo "  ⚠ Warning: openssl.exe not found! Encrypted backups will not work."
fi

# Tor
if command -v tor &> /dev/null; then
    cp "$(which tor)" dist/bin/tor.exe
    echo "  ✓ tor.exe"
elif [ -f "/mingw64/bin/tor.exe" ]; then
    cp /mingw64/bin/tor.exe dist/bin/
    echo "  ✓ tor.exe"
else
    echo "  ⚠ Warning: tor not found! Anonymous connections will not work."
fi

# obfs4proxy (Tor bridge support)
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
    echo "  ✓ obfs4proxy.exe"
else
    echo "  ⚠ Warning: obfs4proxy not found! Bridges might not work."
fi

# ============================================
# Resources (share/)
# ============================================
echo "[7/8] Copying resources..."

# CA Certificates (needed for TLS)
if [ -f "/mingw64/ssl/certs/ca-bundle.crt" ]; then
    cp /mingw64/ssl/certs/ca-bundle.crt dist/ssl/certs/
    # Also copy to dist/ root for backwards compatibility
    cp /mingw64/ssl/certs/ca-bundle.crt dist/
    echo "  ✓ CA certificates"
fi

# Icons
if [ -d "main/data/icons/hicolor" ]; then
    cp -r main/data/icons/hicolor dist/share/icons/
    echo "  ✓ Icons"
fi

# ============================================
# Summary
# ============================================
echo ""
echo "[8/8] Build complete!"
echo ""
echo "Directory structure:"
echo "  dist/"
echo "  ├── dinox.exe              (main application)"
echo "  ├── gpgme-w32spawn.exe     (GPGME helper)"
echo "  ├── lib*.dll               (core libraries)"
echo "  ├── bin/"
echo "  │   ├── gpg.exe            (OpenPGP encryption)"
echo "  │   ├── openssl.exe        (backup encryption)"
echo "  │   ├── tor.exe            (anonymity)"
echo "  │   └── obfs4proxy.exe     (bridges)"
echo "  ├── plugins/"
echo "  │   └── *.dll              (feature plugins)"
echo "  ├── share/icons/           (application icons)"
echo "  └── ssl/certs/             (CA certificates)"
echo ""
echo "Note: tar.exe uses Windows built-in (C:\\Windows\\System32\\tar.exe)"
echo ""
echo "You can now run: ./dist/dinox.exe"
