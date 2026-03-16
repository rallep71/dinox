# DinoX unter Windows selbst kompilieren

Vollständige Anleitung zum Bauen von DinoX aus dem GitHub-Quellcode auf Windows 10/11.

## Voraussetzungen

- Windows 10 oder 11 (64-Bit)
- ca. 5 GB freier Speicherplatz (MSYS2 + Abhängigkeiten)
- Internetverbindung

---

## Schritt 1: MSYS2 installieren

1. Lade MSYS2 von **https://www.msys2.org/** herunter und installiere es (Standard: `C:\msys64`)
2. **Wichtig:** Öffne nach der Installation die **MINGW64**-Shell (nicht die MSYS- oder UCRT-Shell!)
   - Startmenü → „MSYS2 MINGW64"
   - Die Titelleiste muss **MINGW64** zeigen

---

## Schritt 2: System aktualisieren

Nach der Installation muss MSYS2 **zweimal** aktualisiert werden. Zuerst:

```bash
pacman -Syu
```

Das Terminal schließt sich automatisch, weil die MSYS2-Runtime selbst aktualisiert wird. Das ist normal. **Terminal erneut öffnen** (MINGW64!) und den gleichen Befehl nochmal ausführen:

```bash
pacman -Syu
```

Erst beim zweiten Mal werden alle Pakete tatsächlich heruntergeladen und aktualisiert. Diesen Schritt **nicht** überspringen — sonst sind die Paketdatenbanken veraltet und nachfolgende Installationen schlagen mit „Could not connect to server"-Fehlern fehl.

---

## Schritt 3: Alle Abhängigkeiten installieren

Alles in einem Befehl (einfach kopieren und einfügen):

```bash
pacman -S --noconfirm \
    git \
    tar \
    base-devel \
    mingw-w64-x86_64-toolchain \
    mingw-w64-x86_64-vala \
    mingw-w64-x86_64-meson \
    mingw-w64-x86_64-ninja \
    mingw-w64-x86_64-pkgconf \
    mingw-w64-x86_64-cmake \
    mingw-w64-x86_64-python \
    mingw-w64-x86_64-gtk4 \
    mingw-w64-x86_64-libadwaita \
    mingw-w64-x86_64-glib2 \
    mingw-w64-x86_64-glib-networking \
    mingw-w64-x86_64-gdk-pixbuf2 \
    mingw-w64-x86_64-libgee \
    mingw-w64-x86_64-libsoup3 \
    mingw-w64-x86_64-json-glib \
    mingw-w64-x86_64-sqlcipher \
    mingw-w64-x86_64-sqlite3 \
    mingw-w64-x86_64-icu \
    mingw-w64-x86_64-libgcrypt \
    mingw-w64-x86_64-gpgme \
    mingw-w64-x86_64-gnutls \
    mingw-w64-x86_64-qrencode \
    mingw-w64-x86_64-libsecret \
    mingw-w64-x86_64-libsrtp \
    mingw-w64-x86_64-libnice \
    mingw-w64-x86_64-gstreamer \
    mingw-w64-x86_64-gst-plugins-base \
    mingw-w64-x86_64-gst-plugins-good \
    mingw-w64-x86_64-gst-plugins-bad \
    mingw-w64-x86_64-gst-libav \
    mingw-w64-x86_64-opus \
    mingw-w64-x86_64-openh264 \
    mingw-w64-x86_64-libvpx \
    mingw-w64-x86_64-protobuf-c \
    mingw-w64-x86_64-openssl \
    mingw-w64-x86_64-librsvg \
    mingw-w64-x86_64-hicolor-icon-theme \
    mingw-w64-x86_64-adwaita-icon-theme \
    mingw-w64-x86_64-cantarell-fonts \
    mingw-w64-x86_64-mosquitto \
    mingw-w64-x86_64-tor \
    mingw-w64-x86_64-go \
    mingw-w64-x86_64-imagemagick
```

> Bei der Frage `(default=all)` einfach Enter drücken.
>
> **Hinweis:** Warnungen wie „dependency cycle detected" (harfbuzz/freetype, libwebp/libtiff) sind normal und harmlos — das sind bekannte zirkuläre Abhängigkeiten in MSYS2, die pacman korrekt auflöst.

---

## Schritt 4: Lyrebird bauen (Tor Pluggable Transport)

Lyrebird wird für die Tor-Unterstützung (obfs4 + WebTunnel) benötigt und ist nicht als MSYS2-Paket verfügbar:

```bash
cd /tmp
LYREBIRD_VER=0.8.1
LYREBIRD_TAG="lyrebird-${LYREBIRD_VER}"
curl -sL -o "lyrebird-${LYREBIRD_VER}.tar.gz" \
  "https://gitlab.torproject.org/api/v4/projects/417/repository/archive.tar.gz?sha=${LYREBIRD_TAG}"
tar xf "lyrebird-${LYREBIRD_VER}.tar.gz"
cd lyrebird-${LYREBIRD_TAG}-*
CGO_ENABLED=0 go build -trimpath -ldflags '-s -w' -o lyrebird.exe ./cmd/lyrebird
cp lyrebird.exe /mingw64/bin/
lyrebird.exe --version
```

---

## Schritt 5: webrtc-audio-processing v2.1 bauen

MSYS2 hat nur Version 1.x, DinoX braucht aber v2.1 für die beste Audio-Qualität bei Anrufen. Muss von Source gebaut werden:

```bash
cd /tmp
WEBRTC_VER=2.1
curl -sL -o "webrtc-audio-processing-${WEBRTC_VER}.tar.gz" \
  "https://freedesktop.org/software/pulseaudio/webrtc-audio-processing/webrtc-audio-processing-${WEBRTC_VER}.tar.gz"
tar xf "webrtc-audio-processing-${WEBRTC_VER}.tar.gz"
cd "webrtc-audio-processing-${WEBRTC_VER}"
# Fix für GCC 13+: Ab dieser Version wird #include <cstdint> nicht mehr
# automatisch über andere Header mitgezogen. Ohne diesen Fix gibt es
# Compilerfehler ("uint32_t / int64_t was not declared"). Der sed-Befehl
# fügt die fehlende Zeile als erste Zeile in die betroffenen Dateien ein.
for f in webrtc/rtc_base/trace_event.h \
         webrtc/modules/audio_processing/aec3/multi_channel_content_detector.h; do
    if ! grep -q '#include <cstdint>' "$f" 2>/dev/null; then
        sed -i '1s|^|#include <cstdint>\n|' "$f"
    fi
done
# Fix für abseil-cpp >= 20250814: Neuere Versionen definieren absl::Nullable
# und absl::Nonnull Annotationen, die webrtc v2.1 nicht kennt. Ohne diesen
# Fix gibt es Compilerfehler ("absl::Nullable has not been declared").
# Der sed-Befehl entfernt die Annotationen und lässt nur den Pointer-Typ übrig.
sed -i 's/absl::Nullable<\([^>]*\)>/\1/g; s/absl::Nonnull<\([^>]*\)>/\1/g' \
    webrtc/api/scoped_refptr.h \
    webrtc/api/make_ref_counted.h \
    webrtc/api/audio/audio_processing.h \
    webrtc/modules/audio_processing/aec_dump/aec_dump_factory.h \
    webrtc/modules/audio_processing/aec_dump/null_aec_dump_factory.cc \
    webrtc/modules/audio_processing/audio_processing_impl.cc \
    webrtc/modules/audio_processing/audio_processing_impl.h
# Fix für MinGW: windows.h zieht intern winsock.h (v1) ein, was mit
# winsock2.h kollidiert. WIN32_LEAN_AND_MEAN hilft bei MinGW leider nicht
# (nur bei MSVC). Deshalb wird die harmlose Warnung per -Wno-cpp unterdrückt.
python3 << 'PYEOF'
import re
text = open('meson.build').read()
text = re.sub(r"\nadd_global_arguments[^\n]*Wno-cpp[^\n]*\n", '\n', text)
m = re.search(r"^\)", text, re.MULTILINE)
if m:
    pos = m.end()
    text = text[:pos] + "\nadd_global_arguments('-Wno-cpp', language: ['c', 'cpp'])" + text[pos:]
open('meson.build', 'w').write(text)
PYEOF
grep 'Wno-cpp' meson.build  # Muss genau 1x erscheinen
meson setup build --wipe --prefix=/mingw64
ninja -C build
ninja -C build install
pkg-config --modversion webrtc-audio-processing-2
```

---

## Schritt 6: libomemo-c bauen (OMEMO-Verschlüsselung)

libomemo-c ist nicht in den MSYS2-Repos verfügbar und muss aus dem Quellcode gebaut werden:

```bash
cd /tmp
git clone --depth 1 https://github.com/rallep71/libomemo-c.git
cd libomemo-c
mkdir build && cd build
cmake -G Ninja \
    -DCMAKE_INSTALL_PREFIX=/mingw64 \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    ..
ninja
ninja install
```

Prüfen ob es erkannt wird:

```bash
pkg-config --modversion libomemo-c
```

Sollte `0.5.1` (oder höher) ausgeben.

---

## Schritt 7: DinoX-Quellcode klonen

```bash
cd ~
git clone https://github.com/rallep71/dinox.git
cd dinox
```

---

## Schritt 8: Windows-Icon (nur bei Icon-Änderungen)

Die Datei `main/data/dinox.ico` ist bereits im Repo enthalten. Dieser Schritt ist nur nötig, wenn du die App-Icons geändert hast und die `.ico` neu generieren willst:

```bash
magick \
    main/data/icons/hicolor/16x16/apps/im.github.rallep71.DinoX.png \
    main/data/icons/hicolor/32x32/apps/im.github.rallep71.DinoX.png \
    main/data/icons/hicolor/48x48/apps/im.github.rallep71.DinoX.png \
    main/data/icons/hicolor/128x128/apps/im.github.rallep71.DinoX.png \
    main/data/icons/hicolor/256x256/apps/im.github.rallep71.DinoX.png \
    main/data/dinox.ico
```

---

## Schritt 9: Konfigurieren (Meson)

```bash
meson setup build \
    -Dplugin-omemo=enabled \
    -Dplugin-rtp=enabled \
    -Dplugin-openpgp=enabled \
    -Dplugin-ice=enabled \
    -Dplugin-http-files=enabled
```

Meson zeigt am Ende alle gefundenen Abhängigkeiten an. Prüfe, dass keine wichtigen mit `NO` markiert sind.

---

## Schritt 10: Kompilieren

```bash
ninja -C build
```

Der Build dauert einige Minuten. Am Ende sollte `dinox.exe` unter `build/main/` liegen.

---

## Schritt 11: Distribution erstellen

Das Skript sammelt die EXE, alle nötigen DLLs, Plugins, Icons und Daten:

```bash
bash scripts/update_dist.sh
```

Danach liegt alles im `dist/`-Ordner.

---

## Schritt 12: Starten

```bash
./dist/dinox.exe
```

Oder den `dist/`-Ordner an einen beliebigen Ort kopieren und `dinox.exe` direkt starten — keine Installation nötig.

---

## Debug-Modus

Falls Probleme auftreten, mit Debug-Ausgabe starten:

```bash
G_MESSAGES_DEBUG=all ./dist/dinox.exe 2>&1 | tee dinox-debug.log
```

Die Datei `dinox-debug.log` enthält dann alle Diagnose-Informationen.

---

## Neubauen nach Code-Änderungen

Bei reinen Code-Änderungen (ohne neue Abhängigkeiten) reicht:

```bash
cd ~/dinox
ninja -C build
bash scripts/update_dist.sh
```

Bei Änderungen an `meson.build` oder `meson_options.txt`:

```bash
meson setup build --wipe
ninja -C build
bash scripts/update_dist.sh
```

---

## Zusammenfassung aller Befehle

Für Eilige — alles ab Schritt 3 in einem Block:

```bash
# Abhängigkeiten (Schritt 3)
pacman -S --noconfirm git tar base-devel \
    mingw-w64-x86_64-{toolchain,vala,meson,ninja,pkgconf,cmake,python} \
    mingw-w64-x86_64-{gtk4,libadwaita,glib2,glib-networking,gdk-pixbuf2,libgee} \
    mingw-w64-x86_64-{libsoup3,json-glib,sqlcipher,sqlite3,icu} \
    mingw-w64-x86_64-{libgcrypt,gpgme,gnutls,qrencode,libsecret,libsrtp,libnice} \
    mingw-w64-x86_64-{gstreamer,gst-plugins-base,gst-plugins-good,gst-plugins-bad,gst-libav} \
    mingw-w64-x86_64-{opus,openh264,libvpx,protobuf-c} \
    mingw-w64-x86_64-{openssl,librsvg,hicolor-icon-theme,adwaita-icon-theme,cantarell-fonts} \
    mingw-w64-x86_64-{mosquitto,tor,go,imagemagick}

# Lyrebird (Schritt 4)
cd /tmp
LYREBIRD_VER=0.8.1 && LYREBIRD_TAG="lyrebird-${LYREBIRD_VER}"
curl -sL -o "lyrebird-${LYREBIRD_VER}.tar.gz" \
  "https://gitlab.torproject.org/api/v4/projects/417/repository/archive.tar.gz?sha=${LYREBIRD_TAG}"
tar xf "lyrebird-${LYREBIRD_VER}.tar.gz"
cd lyrebird-${LYREBIRD_TAG}-* && CGO_ENABLED=0 go build -trimpath -ldflags '-s -w' -o lyrebird.exe ./cmd/lyrebird
cp lyrebird.exe /mingw64/bin/

# webrtc-audio-processing v2.1 (Schritt 5)
cd /tmp
WEBRTC_VER=2.1
curl -sL -o "webrtc-audio-processing-${WEBRTC_VER}.tar.gz" \
  "https://freedesktop.org/software/pulseaudio/webrtc-audio-processing/webrtc-audio-processing-${WEBRTC_VER}.tar.gz"
tar xf "webrtc-audio-processing-${WEBRTC_VER}.tar.gz" && cd "webrtc-audio-processing-${WEBRTC_VER}"
for f in webrtc/rtc_base/trace_event.h \
         webrtc/modules/audio_processing/aec3/multi_channel_content_detector.h; do
    if ! grep -q '#include <cstdint>' "$f" 2>/dev/null; then
        sed -i '1s|^|#include <cstdint>\n|' "$f"
    fi
done
sed -i 's/absl::Nullable<\([^>]*\)>/\1/g; s/absl::Nonnull<\([^>]*\)>/\1/g' \
    webrtc/api/scoped_refptr.h webrtc/api/make_ref_counted.h \
    webrtc/api/audio/audio_processing.h \
    webrtc/modules/audio_processing/aec_dump/aec_dump_factory.h \
    webrtc/modules/audio_processing/aec_dump/null_aec_dump_factory.cc \
    webrtc/modules/audio_processing/audio_processing_impl.cc \
    webrtc/modules/audio_processing/audio_processing_impl.h
python3 << 'PYEOF'
import re
text = open('meson.build').read()
text = re.sub(r"\nadd_global_arguments[^\n]*Wno-cpp[^\n]*\n", '\n', text)
m = re.search(r"^\)", text, re.MULTILINE)
if m:
    pos = m.end()
    text = text[:pos] + "\nadd_global_arguments('-Wno-cpp', language: ['c', 'cpp'])" + text[pos:]
open('meson.build', 'w').write(text)
PYEOF
meson setup build --wipe --prefix=/mingw64 && ninja -C build && ninja -C build install

# libomemo-c (Schritt 6)
cd /tmp && git clone --depth 1 https://github.com/rallep71/libomemo-c.git
cd libomemo-c && mkdir build && cd build
cmake -G Ninja -DCMAKE_INSTALL_PREFIX=/mingw64 -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 ..
ninja && ninja install

# DinoX klonen und bauen (Schritte 7-11)
cd ~ && git clone https://github.com/rallep71/dinox.git && cd dinox
meson setup build -Dplugin-omemo=enabled -Dplugin-rtp=enabled -Dplugin-openpgp=enabled -Dplugin-ice=enabled -Dplugin-http-files=enabled
ninja -C build
bash scripts/update_dist.sh

# Neubauen (wenn Repo schon vorhanden)
cd ~/dinox && git pull
# Nur Code-Änderungen:
ninja -C build && bash scripts/update_dist.sh
# Bei meson.build-Änderungen (--wipe rekonfiguriert komplett):
meson setup build --wipe -Dplugin-omemo=enabled -Dplugin-rtp=enabled -Dplugin-openpgp=enabled -Dplugin-ice=enabled -Dplugin-http-files=enabled
ninja -C build && bash scripts/update_dist.sh
# Falls --wipe fehlschlägt (korrupter Build-Ordner):
rm -rf build
meson setup build -Dplugin-omemo=enabled -Dplugin-rtp=enabled -Dplugin-openpgp=enabled -Dplugin-ice=enabled -Dplugin-http-files=enabled
ninja -C build && bash scripts/update_dist.sh

# Starten
./dist/dinox.exe
```

---

## Häufige Probleme

| Problem | Lösung |
|---------|--------|
| `command not found: meson` | Falsche Shell? Muss **MINGW64** sein, nicht MSYS |
| `libomemo-c not found` | Schritt 5 (libomemo-c bauen) wiederholen |
| `webrtc-audio-processing not found` | Nicht schlimm — wird als `auto` übersprungen, Calls funktionieren trotzdem |
| Terminal schließt sich bei `pacman -Syu` | Normal — Terminal neu öffnen, `pacman -Su` ausführen |
| `ninja: error: loading 'build.ninja'` | Erst `meson setup build` ausführen |
| DLLs fehlen beim Start | `bash scripts/update_dist.sh` nochmal ausführen |
| `couldn't load font "Adwaita Mono"` | `pacman -S mingw-w64-x86_64-cantarell-fonts` installieren und `update_dist.sh` erneut starten |
