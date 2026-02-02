#!/bin/bash
set -e

echo "Updating dist/ directory..."
mkdir -p dist/plugins

# Copy Exe
echo "Copying dinox.exe"
cp build/main/dinox.exe dist/

# Copy Core DLLs
echo "Copying Core DLLs"
cp build/libdino/libdino-0.dll dist/
cp build/xmpp-vala/libxmpp-vala-0.dll dist/
cp build/qlite/libqlite-0.dll dist/
cp build/crypto-vala/libcrypto-vala-0.dll dist/

# Copy gpgme-w32spawn.exe (Required for GPGME on Windows)
# This executable is needed for GPGME to spawn child processes (like gpg.exe)
if [ -f "/mingw64/bin/gpgme-w32spawn.exe" ]; then
    echo "Copying gpgme-w32spawn.exe..."
    cp /mingw64/bin/gpgme-w32spawn.exe dist/
elif command -v gpgme-w32spawn.exe &> /dev/null; then
    echo "Copying gpgme-w32spawn.exe..."
    cp "$(command -v gpgme-w32spawn.exe)" dist/
else
    echo "Warning: gpgme-w32spawn.exe not found! OpenPGP plugin might fail with error 16383."
fi

# Copy Plugins
echo "Copying Plugins"
# Find all dlls in build/plugins and copy them to dist/plugins
find build/plugins -name "*.dll" -exec cp {} dist/plugins/ \;

# Copy Tor (if available)
if command -v tor &> /dev/null; then
  echo "Copying Tor..."
  cp $(which tor) dist/
else
  echo "Warning: tor not found in path. Please install mingw-w64-x86_64-tor"
fi

# Copy obfs4proxy (if available)
OBFS4_PATH=""
if command -v obfs4proxy &> /dev/null; then
    OBFS4_PATH=$(which obfs4proxy)
elif [ -f "$HOME/go/bin/obfs4proxy.exe" ]; then
    OBFS4_PATH="$HOME/go/bin/obfs4proxy.exe"
elif [ -f "/mingw64/bin/obfs4proxy.exe" ]; then
    OBFS4_PATH="/mingw64/bin/obfs4proxy.exe"
fi

if [ -n "$OBFS4_PATH" ]; then
  echo "Copying obfs4proxy from $OBFS4_PATH..."
  cp "$OBFS4_PATH" dist/
else
  echo "Warning: obfs4proxy not found. Bridges might not work."
  echo "  (Tip: Install Go with 'pacman -S mingw-w64-x86_64-go' and then run:"
  echo "   'go install gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/obfs4.git/obfs4proxy@latest')"
fi

# Copy CA Certificates (MSYS2 GnuTLS needs this!)
if [ -f "/mingw64/ssl/certs/ca-bundle.crt" ]; then
    echo "Copying CA Bundle..."
    mkdir -p dist/ssl/certs
    cp /mingw64/ssl/certs/ca-bundle.crt dist/ssl/certs/
    cp /mingw64/ssl/certs/ca-bundle.crt dist/
fi

# Copy Icons
echo "Copying Icons..."
mkdir -p dist/share/icons
if [ -d "main/data/icons/hicolor" ]; then
    cp -r main/data/icons/hicolor dist/share/icons/
fi

echo "Done. You can now try running ./dist/dinox.exe"
