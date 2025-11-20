# Systray Support für Dino

## Übersicht

Dino hat jetzt Systray-Support (System Tray Icon) für Linux-Desktop-Umgebungen implementiert. Dies erlaubt es, Dino in die Systemleiste zu minimieren und im Hintergrund laufen zu lassen.

## Implementierung

Die Implementierung nutzt **StatusNotifierItem** (SNI) über D-Bus, den modernen freedesktop.org-Standard für Systemleisten-Icons. Dies ist kompatibel mit GTK4 und funktioniert Desktop-umgebung-agnostisch.

### Technische Details

- **Standard**: StatusNotifierItem via org.kde.StatusNotifierItem D-Bus Interface
- **Menü-Protokoll**: DBusMenu via `libdbusmenu-glib` (kompatibel mit Canonical DBusMenu Spezifikation)
- **Dateien**:
  - `main/src/ui/systray.vala` - StatusNotifierItem Interface, DBusMenu Server und SystrayManager
  - `main/src/ui/application.vala` - Integration in Dino Application
  - `main/vapi/dbusmenu-glib-0.4.vapi` - Vala Bindings für libdbusmenu-glib

### Komponenten

1. **StatusNotifierItem**: D-Bus Interface mit Properties (status, icon_name, title, category) und Methoden (Activate, SecondaryActivate, ContextMenu)
2. **DBusMenu Server**: Stellt das Kontextmenü über D-Bus bereit (`/MenuBar`), was eine korrekte Darstellung in allen Desktop-Umgebungen (inkl. Cinnamon) garantiert.
3. **SystrayManager**: Verwaltet D-Bus Service, Icon-Status, Window-Sichtbarkeit
4. **StatusNotifierWatcher**: Interface zur Registrierung beim System-Tray-Service

## Desktop-Umgebungen-Kompatibilität

### Voll unterstützt (native SNI-Unterstützung):
- ✅ **KDE Plasma** (alle Versionen)
- ✅ **XFCE** 4.14+ (mit xfce4-statusnotifier-plugin)
- ✅ **Cinnamon** (native Unterstützung)
- ✅ **MATE** 1.24+ (native Unterstützung)

### Mit Extension:
- ⚠️ **GNOME**: Benötigt [AppIndicator/KStatusNotifierItem Extension](https://extensions.gnome.org/extension/615/appindicator-support/)

### Nicht unterstützt:
- ❌ Sehr alte Desktop-Umgebungen ohne SNI-Support

## Funktionen

### Aktuell implementiert:
- ✅ Icon in der Systemleiste
- ✅ Linksklick: Fenster anzeigen/verstecken (Toggle)
- ✅ Rechtsklick-Kontextmenü (Show/Hide, Quit)
- ✅ Window schließen minimiert zum Tray statt zu beenden
- ✅ Hintergrund-Betrieb mit verstecktem Fenster

### Geplant:
- ⏳ Attention-Icon bei neuen Nachrichten
- ⏳ Einstellungsoption zum Aktivieren/Deaktivieren

## Verwendung

1. **Starte Dino**: Das Systray-Icon erscheint automatisch in der Systemleiste
2. **Fenster verstecken**: Schließe das Dino-Fenster (X) - es wird in den Tray minimiert
3. **Fenster anzeigen**: Linksklick auf das Systray-Icon
4. **Dino beenden**: Über Menü "Quit" oder Strg+Q

## D-Bus Testing

### StatusNotifierItem prüfen:
```bash
# Liste aller D-Bus Services mit "Status"
dbus-send --session --dest=org.freedesktop.DBus --type=method_call --print-reply \
  /org/freedesktop/DBus org.freedesktop.DBus.ListNames | grep -i status

# Registrierte StatusNotifierItems abrufen
dbus-send --session --dest=org.kde.StatusNotifierWatcher --type=method_call --print-reply \
  /StatusNotifierWatcher org.freedesktop.DBus.Properties.Get \
  string:"org.kde.StatusNotifierWatcher" string:"RegisteredStatusNotifierItems"

# StatusNotifierItem aktivieren (simuliert Linksklick)
dbus-send --session --dest=:1.XXX --type=method_call --print-reply \
  /StatusNotifierItem org.kde.StatusNotifierItem.Activate int32:0 int32:0
```

## Debugging

### Systray-Logs:
```bash
# Starte Dino mit Debug-Ausgabe
G_MESSAGES_DEBUG=all ./build/main/dino 2>&1 | grep -i systray
```

Expected output:
- `Systray: StatusNotifierItem registered on D-Bus`
- `Systray: Registered with StatusNotifierWatcher`

### Fehlerbehebung:

**Icon erscheint nicht:**
1. Prüfe ob StatusNotifierWatcher läuft:
   ```bash
   dbus-send --session --dest=org.kde.StatusNotifierWatcher --print-reply \
     /StatusNotifierWatcher org.kde.StatusNotifierWatcher.IsStatusNotifierHostRegistered
   ```
2. GNOME: Installiere AppIndicator Extension
3. XFCE: Installiere `xfce4-statusnotifier-plugin`

**Window schließt komplett statt zu minimieren:**
- Überprüfe ob `close_request` Handler aktiv ist (sollte automatisch bei Systray-Initialisierung gesetzt werden)

## Issue References

- Issue #98: Systray support (seit 2017, 82 👍, 26 ❤️)
- Issue #1723: Application doesn't run in background (verwandt)

## Weitere Informationen

- [freedesktop.org StatusNotifierItem Specification](https://www.freedesktop.org/wiki/Specifications/StatusNotifierItem/)
- [KDE StatusNotifierItem D-Bus Interface](https://www.freedesktop.org/wiki/Specifications/StatusNotifierItem/StatusNotifierItem/)
