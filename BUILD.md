# Building DinoX from Source

This guide provides detailed instructions for building DinoX on various Linux distributions.

## General Requirements

*   **Compiler:** GCC or Clang
*   **Build System:** Meson (>= 0.56.0), Ninja
*   **Language:** Vala (>= 0.48)
*   **Toolkit:** GTK4, Libadwaita

## Dependencies

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
    libwebrtc-audio-processing-dev \
    libnice-dev \
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
    webrtc-audio-processing-devel \
    libnice-devel \
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
    webrtc-audio-processing \
    libnice \
    libsrtp
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
