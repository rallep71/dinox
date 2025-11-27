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
        meson setup "$BUILD_DIR" --prefix=/usr
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

# Set GStreamer plugin path
export GST_PLUGIN_PATH="$APPDIR/usr/lib/gstreamer-1.0:$GST_PLUGIN_PATH"

# Set locale
export LOCPATH="$APPDIR/usr/share/locale"

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
    
    # Remove old AppImage
    rm -f "$APPIMAGE_NAME"
    
    # Create AppImage
    log_info "Running appimagetool..."
    ARCH=x86_64 "$BUILD_DIR/appimagetool-x86_64.AppImage" "$APPDIR" "$APPIMAGE_NAME"
    
    if [ -f "$APPIMAGE_NAME" ]; then
        log_info "AppImage created successfully: $APPIMAGE_NAME"
        log_info "Size: $(du -h "$APPIMAGE_NAME" | cut -f1)"
        log_info ""
        log_info "To test: ./$APPIMAGE_NAME"
        log_info "To install: Move to ~/Applications or ~/.local/bin/"
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
