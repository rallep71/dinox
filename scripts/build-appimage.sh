#!/bin/bash
# DinoX AppImage Build Script
# Creates a portable AppImage for DinoX that runs on any Linux distribution

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/build"
APPDIR="$BUILD_DIR/AppDir"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Copy ELF dependencies recursively into AppDir.
# This is critical for GStreamer: plugins are discovered by filename, but if
# their dependent shared libraries are missing, GStreamer will silently skip
# loading them (resulting in missing audio/video/webrtc capabilities).
copy_elf_deps_recursive() {
    local file="$1"
    local dest_lib_dir="$2"

    if [ -z "$file" ] || [ ! -e "$file" ]; then
        return 0
    fi
    if [ -z "$dest_lib_dir" ]; then
        return 1
    fi
    mkdir -p "$dest_lib_dir"

    # Track processed binaries by basename in the destination.
    # (Good enough for AppDir bundling and avoids infinite recursion.)
    if [ -z "${__DINOX_DEPS_SEEN_INIT}" ]; then
        declare -gA __DINOX_DEPS_SEEN
        __DINOX_DEPS_SEEN_INIT=1
    fi

    # ldd output contains absolute paths in different columns; extract any token
    # that begins with '/' and strip trailing punctuation.
    local dep
    while IFS= read -r dep; do
        dep="${dep%)}"
        dep="${dep%(}"
        [ -e "$dep" ] || continue

        local base
        base="$(basename "$dep")"
        if [ -n "${__DINOX_DEPS_SEEN[$base]}" ]; then
            continue
        fi
        __DINOX_DEPS_SEEN[$base]=1

        # Copy the dependency into AppDir.
        cp -L "$dep" "$dest_lib_dir/" 2>/dev/null || true

        # Recurse into the copied file (if present).
        if [ -e "$dest_lib_dir/$base" ]; then
            copy_elf_deps_recursive "$dest_lib_dir/$base" "$dest_lib_dir"
        fi
    done < <(ldd "$file" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i ~ /^\//) print $i}')
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v meson &> /dev/null; then
        log_error "meson not found. Please install: sudo apt install meson"
        exit 1
    fi
    
    if ! command -v ninja &> /dev/null; then
        log_error "ninja not found. Please install: sudo apt install ninja-build"
        exit 1
    fi
    
    if ! command -v patchelf &> /dev/null; then
        log_error "patchelf not found. Please install: sudo apt install patchelf"
        exit 1
    fi
    
    log_info "All prerequisites satisfied!"
}

# Download appimagetool if not present
get_appimagetool() {
    APPIMAGETOOL="$BUILD_DIR/appimagetool-x86_64.AppImage"
    
    if [ ! -f "$APPIMAGETOOL" ]; then
        log_info "Downloading appimagetool..."
        wget -O "$APPIMAGETOOL" https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage
        chmod +x "$APPIMAGETOOL"
    else
        log_info "appimagetool already present"
    fi
}

# Build DinoX
build_dinox() {
    log_info "Building DinoX..."
    
    cd "$PROJECT_ROOT"
    
    if [ ! -d "$BUILD_DIR" ]; then
        log_info "Setting up build directory..."
        meson setup "$BUILD_DIR" --prefix=/usr -Dplugin-notification-sound=enabled
    else
        # Ensure release AppImages include notification sounds
        meson configure "$BUILD_DIR" -Dplugin-notification-sound=enabled
    fi
    
    log_info "Compiling..."
    ninja -C "$BUILD_DIR"
    
    log_info "Build completed!"
}

# Create AppDir structure
create_appdir() {
    log_info "Creating AppDir structure..."
    
    # Clean old AppDir
    rm -rf "$APPDIR"
    mkdir -p "$APPDIR"
    
    # Install to AppDir
    log_info "Installing to AppDir..."
    DESTDIR="$APPDIR" meson install -C "$BUILD_DIR"
    
    # Create standard AppImage directories
    mkdir -p "$APPDIR/usr/bin"
    mkdir -p "$APPDIR/usr/lib"
    mkdir -p "$APPDIR/usr/share/applications"
    mkdir -p "$APPDIR/usr/share/icons/hicolor/scalable/apps"
    mkdir -p "$APPDIR/usr/share/metainfo"
    
    log_info "AppDir structure created!"
}

# Copy dependencies
copy_dependencies() {
    log_info "Copying runtime dependencies..."
    
    # Move from /usr/local to /usr for AppImage standard
    if [ -d "$APPDIR/usr/local" ]; then
        log_info "Moving files from /usr/local to /usr..."
        cp -r "$APPDIR/usr/local"/* "$APPDIR/usr/" 2>/dev/null || true
        rm -rf "$APPDIR/usr/local"
    fi
    
    DINOX_BIN="$APPDIR/usr/bin/dinox"
    LIB_DIR="$APPDIR/usr/lib"
    
    # Copy/consolidate libraries from x86_64-linux-gnu to main lib dir
    if [ -d "$LIB_DIR/x86_64-linux-gnu" ]; then
        log_info "Consolidating libraries..."
        cp -L "$LIB_DIR/x86_64-linux-gnu"/*.so* "$LIB_DIR/" 2>/dev/null || true
        # Also copy plugins
        if [ -d "$LIB_DIR/x86_64-linux-gnu/dino" ]; then
            mkdir -p "$LIB_DIR/dino"
            cp -r "$LIB_DIR/x86_64-linux-gnu/dino"/* "$LIB_DIR/dino/" 2>/dev/null || true
        fi
    fi
    
    # Copy plugins
    log_info "Copying plugins..."
    mkdir -p "$APPDIR/usr/lib/dino/plugins"
    cp -r "$BUILD_DIR"/plugins/*/*.so "$APPDIR/usr/lib/dino/plugins/" 2>/dev/null || true
    
    # Copy GStreamer plugins
    log_info "Copying GStreamer plugins..."
    mkdir -p "$APPDIR/usr/lib/gstreamer-1.0"

    # Try to detect the host GStreamer plugin directory (portable across distros/CI).
    GST_PLUGIN_DIR=""
    if command -v pkg-config &>/dev/null; then
        GST_PLUGIN_DIR="$(pkg-config --variable=pluginsdir gstreamer-1.0 2>/dev/null || true)"
    fi
    if [ -z "$GST_PLUGIN_DIR" ]; then
        GST_PLUGIN_DIR="/usr/lib/x86_64-linux-gnu/gstreamer-1.0"
    fi

    # Copy gst-plugin-scanner.
    # Without a working scanner, GStreamer may fail to scan bundled plugins,
    # resulting in missing webrtc/audio/video capabilities at runtime.
    GST_SCANNER_DIR=""
    if command -v pkg-config &>/dev/null; then
        GST_SCANNER_DIR="$(pkg-config --variable=pluginscannerdir gstreamer-1.0 2>/dev/null || true)"
    fi
    if [ -z "$GST_SCANNER_DIR" ]; then
        GST_SCANNER_DIR="/usr/lib/x86_64-linux-gnu/gstreamer1.0/gstreamer-1.0"
    fi
    if [ -x "$GST_SCANNER_DIR/gst-plugin-scanner" ]; then
        cp -L "$GST_SCANNER_DIR/gst-plugin-scanner" "$APPDIR/usr/lib/gstreamer-1.0/" 2>/dev/null || true
    else
        log_warn "Could not find executable gst-plugin-scanner at: $GST_SCANNER_DIR/gst-plugin-scanner"
    fi
    
    for plugin in \
        libgstcoreelements.so \
        libgstplayback.so \
        libgstaudiorate.so \
        libgsttypefindfunctions.so \
        libgstvideoconvertscale.so \
        libgstaudioconvert.so \
        libgstaudioresample.so \
        libgstvolume.so \
        libgstapp.so \
        libgstvideoparsersbad.so \
        libgstvideofilter.so \
        libgstgtk4.so \
        libgstlibav.so \
        libgstopenh264.so \
        libgstnice.so \
        libgstrtp.so \
        libgstrtpmanager.so \
        libgstdtls.so \
        libgstsrtp.so \
        libgstaudiotestsrc.so \
        libgstvideotestsrc.so \
        libgstwebrtc.so \
        libgstpulseaudio.so \
        libgstalsa.so \
        libgstautodetect.so \
        libgstpipewire.so \
        libgstv4l2.so \
        libgstvideo4linux2.so \
        libgstcamerabin.so \
        libgstvideorate.so \
        libgstaudiomixer.so \
        libgstaudioparsers.so \
        libgstopus.so \
        libgstvpx.so \
        libgstjpeg.so \
        libgstpng.so \
        libgstalaw.so \
        libgstmulaw.so \
        libgstinterleave.so \
        libgstlevel.so
    do
        find "$GST_PLUGIN_DIR" -name "$plugin" -exec cp {} "$APPDIR/usr/lib/gstreamer-1.0/" \; 2>/dev/null || true
    done
    
    # Copy GStreamer plugin scanner
    if [ -f "/usr/lib/x86_64-linux-gnu/gstreamer1.0/gstreamer-1.0/gst-plugin-scanner" ]; then
        cp /usr/lib/x86_64-linux-gnu/gstreamer1.0/gstreamer-1.0/gst-plugin-scanner "$APPDIR/usr/lib/gstreamer-1.0/"
    elif [ -f "/usr/libexec/gstreamer-1.0/gst-plugin-scanner" ]; then
        cp /usr/libexec/gstreamer-1.0/gst-plugin-scanner "$APPDIR/usr/lib/gstreamer-1.0/"
    fi

    # Copy shared-library dependencies for DinoX, Dino plugins, and bundled GStreamer plugins.
    # Without this, GitHub-built AppImages often miss webrtc/opus/vpx/libsrtp/etc at runtime.
    log_info "Resolving and copying shared library dependencies (this may take a moment)..."
    unset __DINOX_DEPS_SEEN_INIT
    unset __DINOX_DEPS_SEEN

    if [ -x "$APPDIR/usr/bin/dinox" ]; then
        copy_elf_deps_recursive "$APPDIR/usr/bin/dinox" "$APPDIR/usr/lib"
    fi
    if [ -d "$APPDIR/usr/lib/dino/plugins" ]; then
        for f in "$APPDIR/usr/lib/dino/plugins"/*.so*; do
            [ -e "$f" ] || continue
            copy_elf_deps_recursive "$f" "$APPDIR/usr/lib"
        done
    fi
    if [ -d "$APPDIR/usr/lib/gstreamer-1.0" ]; then
        for f in "$APPDIR/usr/lib/gstreamer-1.0"/*.so* "$APPDIR/usr/lib/gstreamer-1.0/gst-plugin-scanner"; do
            [ -e "$f" ] || continue
            copy_elf_deps_recursive "$f" "$APPDIR/usr/lib"
        done
    fi
    
    # Copy PulseAudio and audio libraries
    log_info "Copying audio libraries..."
    for lib in libpulse.so* libpulse-simple.so* libpulsecommon-*.so libasound.so* \
               libpipewire-0.3.so* libspa-0.2.so* libsndfile.so* libFLAC.so* \
               libvorbis.so* libvorbisenc.so* libogg.so* \
               libcanberra.so* libcanberra-gtk3.so* \
               libsqlcipher.so* libsecret-1.so* libgcrypt.so* \
               libwebrtc-audio-processing.so*; do
        find /usr/lib/x86_64-linux-gnu -maxdepth 1 -name "$lib" -exec cp -L {} "$APPDIR/usr/lib/" \; 2>/dev/null || true
    done

    # Copy libcanberra driver modules (pulse/alsa)
    if [ -d "/usr/lib/x86_64-linux-gnu/libcanberra-0.30" ]; then
        mkdir -p "$APPDIR/usr/lib/libcanberra-0.30"
        cp -L /usr/lib/x86_64-linux-gnu/libcanberra-0.30/*.so "$APPDIR/usr/lib/libcanberra-0.30/" 2>/dev/null || true
    fi
    
    log_info "Dependencies copied!"
}

# Create AppRun launcher
create_apprun() {
    log_info "Creating AppRun launcher..."
    
    cat > "$APPDIR/AppRun" << 'EOF'
#!/bin/bash
# AppRun launcher for DinoX

APPDIR="$(dirname "$(readlink -f "$0")")"

# Set library path
export LD_LIBRARY_PATH="$APPDIR/usr/lib:$LD_LIBRARY_PATH"

# Set plugin path
export DINO_PLUGIN_DIR="$APPDIR/usr/lib/dino/plugins"

# Set GStreamer plugin paths
# Make sure bundled plugins are discoverable, but do not block system plugins.
# (Hard-overriding system plugin paths can silently remove capabilities like
# video codecs/webrtc elements depending on what's bundled.)
export GST_PLUGIN_PATH="$APPDIR/usr/lib/gstreamer-1.0${GST_PLUGIN_PATH:+:$GST_PLUGIN_PATH}"
export GST_PLUGIN_PATH_1_0="$APPDIR/usr/lib/gstreamer-1.0${GST_PLUGIN_PATH_1_0:+:$GST_PLUGIN_PATH_1_0}"

# libcanberra loads backend drivers (pulse/alsa/...) via dlopen from a module dir.
# When libcanberra is bundled, the compiled-in module path may point to the host
# filesystem, so set it explicitly to the bundled directory.
if [ -d "$APPDIR/usr/lib/libcanberra-0.30" ]; then
    export CANBERRA_MODULE_PATH="$APPDIR/usr/lib/libcanberra-0.30${CANBERRA_MODULE_PATH:+:$CANBERRA_MODULE_PATH}"
fi

# Don't fork for plugin scanning - avoids issues with bundled scanner
export GST_REGISTRY_FORK=no

# Prefer a bundled gst-plugin-scanner (if present), fall back to system.
for scanner in \
    "$APPDIR/usr/lib/gstreamer-1.0/gst-plugin-scanner" \
    "/usr/libexec/gstreamer-1.0/gst-plugin-scanner" \
    "/usr/lib/x86_64-linux-gnu/gstreamer1.0/gstreamer-1.0/gst-plugin-scanner" \
    "/usr/lib/gstreamer-1.0/gst-plugin-scanner"; do
    if [ -x "$scanner" ]; then
        export GST_PLUGIN_SCANNER="$scanner"
        break
    fi
done

# Set GStreamer registry (per-user cache)
export GST_REGISTRY="$HOME/.cache/dinox/gstreamer-1.0/registry.x86_64.bin"
mkdir -p "$(dirname "$GST_REGISTRY")"

# PulseAudio configuration - use system socket if available
if [ -z "$PULSE_SERVER" ]; then
    if [ -S "$XDG_RUNTIME_DIR/pulse/native" ]; then
        export PULSE_SERVER="unix:$XDG_RUNTIME_DIR/pulse/native"
    fi
fi

# Prefer PulseAudio for libcanberra notification sounds when available.
# (libcanberra loads its backend drivers via dlopen; forcing pulse avoids silent fallbacks.)
if [ -S "$XDG_RUNTIME_DIR/pulse/native" ]; then
    export CANBERRA_DRIVER=pulse
fi

# Allow PipeWire access
export PIPEWIRE_RUNTIME_DIR="${PIPEWIRE_RUNTIME_DIR:-$XDG_RUNTIME_DIR}"

# Set locale - use bundled translations but keep system locale settings
# This allows the app to use German, French, etc. based on system LANG
export TEXTDOMAINDIR="$APPDIR/usr/share/locale"

# Set GSettings schema path
export GSETTINGS_SCHEMA_DIR="$APPDIR/usr/share/glib-2.0/schemas:$GSETTINGS_SCHEMA_DIR"

# Run DinoX
exec "$APPDIR/usr/bin/dinox" "$@"
EOF
    
    chmod +x "$APPDIR/AppRun"
    log_info "AppRun created!"
}

# Create desktop file
create_desktop_file() {
    log_info "Creating desktop file..."
    
    cat > "$APPDIR/im.github.rallep71.DinoX.desktop" << EOF
[Desktop Entry]
Name=DinoX
GenericName=Jabber/XMPP Client
Comment=Modern XMPP/Jabber chat client
Exec=dinox %U
Icon=im.github.rallep71.DinoX
Terminal=false
Type=Application
Categories=Network;InstantMessaging;Chat;
MimeType=x-scheme-handler/xmpp;
Keywords=chat;messaging;im;xmpp;jabber;
StartupNotify=true
StartupWMClass=dinox
EOF
    
    # Copy to standard location
    cp "$APPDIR/im.github.rallep71.DinoX.desktop" "$APPDIR/usr/share/applications/"
    
    log_info "Desktop file created!"
}

# Copy icon
copy_icon() {
    log_info "Copying application icon..."
    
    ICON_SOURCE="$PROJECT_ROOT/main/data/icons/hicolor/scalable/apps/im.github.rallep71.DinoX.svg"
    ICON_DEST="$APPDIR/usr/share/icons/hicolor/scalable/apps/im.github.rallep71.DinoX.svg"
    
    if [ -f "$ICON_SOURCE" ]; then
        cp "$ICON_SOURCE" "$ICON_DEST"
        # Also copy to AppDir root for AppImage
        cp "$ICON_SOURCE" "$APPDIR/im.github.rallep71.DinoX.svg"
        log_info "Icon copied!"
    else
        log_warn "Icon not found at $ICON_SOURCE"
    fi
}

# Create AppImage
create_appimage() {
    log_info "Creating AppImage..."
    
    cd "$BUILD_DIR"
    
    # Get version
    VERSION=$(cat "$PROJECT_ROOT/VERSION" | grep RELEASE | awk '{print $2}')
    APPIMAGE_NAME="DinoX-$VERSION-x86_64.AppImage"
    
    # Remove old AppImage and zsync
    rm -f "$APPIMAGE_NAME"
    rm -f "$APPIMAGE_NAME.zsync"
    
    # Remove blacklisted libraries that should come from the host system
    # These cause crashes when bundled (glibc incompatibility)
    log_info "Removing blacklisted system libraries..."
    BLACKLIST=(
        "libc.so*"
        "libm.so*"
        "libdl.so*"
        "librt.so*"
        "libpthread.so*"
        "libresolv.so*"
        "libstdc++.so*"
        "libgcc_s.so*"
        "ld-linux*.so*"
        "libnss_*.so*"
        "libdrm.so*"
        "libxcb.so*"
        "libxcb-*.so*"
        "libX11.so*"
        "libX11-xcb.so*"
        "libXext.so*"
        "libXi.so*"
        "libXfixes.so*"
        "libXrender.so*"
        "libXcursor.so*"
        "libXdamage.so*"
        "libXrandr.so*"
        "libXcomposite.so*"
        "libwayland-*.so*"
        "libasound.so*"
        "libfontconfig.so*"
        "libfreetype.so*"
        "libharfbuzz.so*"
        "libcom_err.so*"
        "libexpat.so*"
        "libgpg-error.so*"
        "libz.so*"
        "libpipewire-0.3.so*"
        "libfribidi.so*"
        "libgmp.so*"
        "libGL.so*"
        "libGLX.so*"
        "libGLdispatch.so*"
        "libEGL.so*"
    )
    
    for pattern in "${BLACKLIST[@]}"; do
        find "$APPDIR/usr/lib" -name "$pattern" -delete 2>/dev/null || true
    done
    
    # Keep gst-plugin-scanner if present.
    # We prefer using a bundled scanner for portability; it will use host glibc.
    
    log_info "Blacklisted libraries removed!"
    
    # Update information for AppImageUpdate (GitHub Releases)
    UPDATE_INFO="gh-releases-zsync|rallep71|dinox|latest|DinoX-*-x86_64.AppImage.zsync"
    
    # Create AppImage with update information and zsync
    log_info "Running appimagetool with update support..."
    ARCH=x86_64 "$BUILD_DIR/appimagetool-x86_64.AppImage" \
        --updateinformation "$UPDATE_INFO" \
        "$APPDIR" "$APPIMAGE_NAME"
    
    if [ -f "$APPIMAGE_NAME" ]; then
        log_info "AppImage created successfully: $APPIMAGE_NAME"
        log_info "Size: $(du -h "$APPIMAGE_NAME" | cut -f1)"
        
        # Check for zsync file
        if [ -f "$APPIMAGE_NAME.zsync" ]; then
            log_info "Zsync file created: $APPIMAGE_NAME.zsync"
            log_info "Delta updates enabled!"
        fi
        
        log_info ""
        log_info "To test: ./$APPIMAGE_NAME"
        log_info "To install: Move to ~/Applications or ~/.local/bin/"
        log_info "To update: Use AppImageUpdate or run with --appimage-update"
    else
        log_error "Failed to create AppImage!"
        exit 1
    fi
}

# Main execution
main() {
    log_info "DinoX AppImage Builder"
    log_info "======================"
    echo ""
    
    check_prerequisites
    get_appimagetool
    build_dinox
    create_appdir
    copy_dependencies
    create_apprun
    create_desktop_file
    copy_icon
    create_appimage
    
    echo ""
    log_info "AppImage build completed successfully!"
}

main "$@"
