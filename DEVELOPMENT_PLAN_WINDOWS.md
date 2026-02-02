# Windows Portierung (DinoX)

## Übersicht
Ziel ist es, DinoX unter Windows 10/11 lauffähig zu machen.
**Tech Stack:** MSYS2 (Mingw-w64) Umgebung.

## Build-Umgebung (MSYS2)
Wir nutzen `mingw-w64-x86_64` Packete.

**Benötigte Pakete (pacman):**
*   **Basis:** `git`, `meson`, `ninja`, `gcc`, `pkg-config`, `vala`, `gobject-introspection`
*   **GTK/UI:** `mingw-w64-x86_64-gtk4`, `mingw-w64-x86_64-libadwaita`
*   **Core:** `mingw-w64-x86_64-glib2`, `mingw-w64-x86_64-gee`
*   **Netzwerk/Crypto:** `mingw-w64-x86_64-libsoup3`, `mingw-w64-x86_64-gnutls`, `mingw-w64-x86_64-libgcrypt`, `mingw-w64-x86_64-gpgme`
*   **Datenbank:** `mingw-w64-x86_64-sqlcipher`
*   **Multimedia:** `mingw-w64-x86_64-gstreamer`, `mingw-w64-x86_64-gst-plugins-base`, `mingw-w64-x86_64-gst-plugins-good`, `mingw-w64-x86_64-gst-plugins-bad`, `mingw-w64-x86_64-gst-libav`
*   **Spezial:** `mingw-w64-x86_64-libnice`, `mingw-w64-x86_64-libsignal-protocol-c` (falls verfügbar, sonst bauen), `mingw-w64-x86_64-qrencode`

## Bekannte Hürden (Portierungs-Aufgaben)

### 1. D-Bus & Notifications
*   DinoX nutzt `libcanberra` für Sounds (Linux-spezifisch) und D-Bus für Notifications.
*   **Aufgabe:** `#if linux` Guards um D-Bus Code (z.B. MPRIS Unterstützung, AppMenu wenn via D-Bus).
*   **Lösung:** GTK4 `GNotification` sollte weitgehend auf Windows Toast Notifications mappen.

### 2. Libsecret (Passwort-Speicher)
*   `libsecret` hat unter Windows oft Tücken (benötigt oft `wincred` Backend Kompilierung).
*   **Strategie:** Prüfen, ob `mingw-w64-x86_64-libsecret` das Windows-Backend aktiviert hat. Falls nicht, müssen wir einen Fallback für Windows implementieren (z.B. Speicherung in der SQLCipher DB).

### 3. Dateipfade
*   Harcodierte Pfade wie `/usr/share` müssen durch `Glib.Environment.get_user_data_dir()` etc. ersetzt werden.

### 4. Installer (MSI/EXE)
*   Nach dem erfolgreichen Kompilieren müssen wir alle DLLs bündeln (`glib-compile-schemas` etc. laufen lassen).
*   Tool: Entweder ein PowerShell-Script, das alles zusammenkopiert, oder **WiX Toolset** für saubere MSIs.

## Roadmap

* [ ] **Phase 1: Kompilieren** (MSYS2 Setup, Abhängigkeiten installieren, Build-Fehler fixen)
* [ ] **Phase 2: Starten** (Runtime-Crashes fixen, fehlende DLLs finden, `glib-compile-resources`)
* [ ] **Phase 3: Features prüfen** (Geht Netzwerk? Gehen Bilder? Geht Video?)
* [ ] **Phase 4: Packaging** (Automatisiertes Erstellen eines ZIP/Installers via GitHub Actions)
