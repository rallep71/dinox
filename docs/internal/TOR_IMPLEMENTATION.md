# DinoX Tor-Netzwerk Implementierung (Intern)

**Status:** Experimentell / Stabilisiert
**Datum:** 9. Januar 2026
**Autor:** DinoX Dev Team (Agent)

## 1. Übersicht

Dieses Dokument beschreibt die Architektur und Funktionsweise des `tor-manager` Plugins für DinoX. Das Ziel ist es, eine robuste Integration des Tor-Netzwerks bereitzustellen, die "Split-Brain"-Zustände (Schalter AUS, aber Verbindung über Tor AN) verhindert und Abstürze des Tor-Hintergrundprozesses sicher handhabt.

## 2. Projektstruktur

Das Plugin folgt einer strikten Trennung ("Separation of Concerns") zwischen UI, Geschäftslogik und System-Prozess-Steuerung.

```
plugins/tor-manager/
├── meson.build                   # Build-System Definition
└── src/
    ├── plugin.vala               # Lifecycle & Einstiegspunkt
    ├── register_plugin.vala      # Boilerplate für die Plugin-Registrierung
    ├── settings_page.vala        # UI: Der "Schalter" in den Einstellungen
    ├── tor_manager.vala          # Logic: Zustandsverwaltung & DB-Sync
    └── tor_controller.vala       # Low-Level: Prozesssteuerung (Start/Kill)
```

### Design-Entscheidungen zur Struktur

*   **Trennung von Manager und Controller:**
    *   `TorManager` kümmert sich um den *Soll-Zustand* der Anwendung (Ist der Schalter an? Welche Accounts müssen über Tor laufen?).
    *   `TorController` ist rein operativ. Er weiß nichts von Accounts, er weiß nur, wie man das `tor` Binary startet, überwacht und (wichtig!) gewaltsam beendet ("Zombie Killing").
*   **Settings-Isolation:**
    *   Die UI (`settings_page.vala`) enthält keine Logik. Sie bindet lediglich den Switch an die Methoden `set_enabled()` des Managers.

## 3. Komponenten-Details

### 3.1 Plugin (`src/plugin.vala`)
- **Funktion:** Einstiegspunkt. Registriert den `TorManager` im `StreamInteractor` von Dino.
- **Shutdown-Hook:** Implementiert `shutdown()`. Hier wird das Flag `prepare_shutdown()` gesetzt, um zu verhindern, dass das reguläre Beenden als "Absturz" interpretiert wird.

### 3.2 TorManager (`src/tor_manager.vala`)
- **Funktion:** Das "Gehirn" der Operation. Es verwaltet den logischen Zustand (AN/AUS) und synchronisiert diesen mit der Datenbank und den aktiven Konten.
- **Kernmethoden:**
    - `restore_state()`: Prüft beim Start die DB. Wenn Tor AUS ist, ruft es `cleanup_lingering_proxies()` auf (Selbstheilung).
    - `cleanup_lingering_proxies()`: Der "Sicherheits-Schrubber". Läuft in zwei Phasen (IDs sammeln -> DB updaten), um `ConcurrentModification`-Fehler zu vermeiden.
    - `on_process_exited()`: Unterscheidet zwischen gewolltem Stop (User drückt Schalter) und Crash/Kill (Automatischer Restart oder Reset).

### 3.3 TorController (`src/tor_controller.vala`)
- **Funktion:** Der "Hausmeister" für den `tor` Prozess.
- **Robustness Features:**
    - **Zombie Killer:** Vor jedem Start wird `pkill -9 -f dino/tor/torrc` ausgeführt. Dies garantiert, dass keine alten Prozesse Port 9155 blockieren.
    - **Port-Release-Delay:** Nach dem Kill wird 300ms gewartet, damit der Kernel den Port freigibt.

## 4. Ablauf-Logik

### 4.1 Start von DinoX
1. `Plugin` initialisiert `TorManager`.
2. `TorManager` ruft `restore_state()` auf.
    - **Szenario A (Tor war AN):** Startet `TorController`.
    - **Szenario B (Tor war AUS):** Ruft `cleanup_lingering_proxies()` auf, um Reste eines früheren Absturzes zu bereinigen.

### 4.2 Starten von Tor (User schaltet AN)
1. Controller killt Zombies auf Port 9155.
2. Controller startet neuen `tor` Prozess.
3. Manager iteriert über alle Accounts und setzt Proxy auf `socks5` (127.0.0.1:9155).
4. Accounts reconnected.

### 4.3 Beenden von Tor (User schaltet AUS oder Absturz)
1. Manager stoppt Controller.
2. Manager ruft `cleanup_lingering_proxies()` auf:
    - Entfernt SOCKS5 aus DB.
    - Trennt Verbindungen im RAM.
    - Erzwingt Reconnect über Clearnet.

### 4.4 Beenden von DinoX (App Exit)
1. `Plugin.shutdown()` wird gefeuert.
2. Setzt Flag `is_shutting_down = true`.
3. Stoppt Tor-Prozess.
4. `on_process_exited` wird ignoriert (DB-Status bleibt erhalten).

## 5. Bekannte Probleme & Lösungen

- **Port 9155 Blockiert:** Gelöst durch "Robust Zombie Killer" in `TorController`.
- **Datenbank-Absturz:** Gelöst durch Trennung von Selektion (Lesen) und Update (Schreiben).
- **Split-Brain (Switch OFF / Tor ON):** Gelöst durch proaktives Cleanup beim Start.
