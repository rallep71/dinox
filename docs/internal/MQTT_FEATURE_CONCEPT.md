# DinoX MQTT Plugin — Feature-Konzept

**Status:** Konzeptphase  
**Erstellt:** 2026-02-26  
**Version:** v0.1 (Entwurf)

---

## 1. Motivation

ejabberd bietet seit v19.02 einen eingebauten MQTT-Broker (`mod_mqtt`), der die
gleiche Infrastruktur wie XMPP nutzt:

- **Gleiche Authentifizierung** — XMPP-Accounts (`user@domain`) funktionieren als MQTT-Logins
- **Gleiche ACL / Security Policy** — einmal definiert, gilt für beide Protokolle
- **Gleiche DB-Backends** — kein zweiter Server nötig
- **MQTT 5.0 + 3.1.1** — modernes Publish/Subscribe-Protokoll

Quelle: https://docs.ejabberd.im/admin/guide/mqtt/#benefits

DinoX kann diese Infrastruktur nutzen, um **leichtgewichtiges Event-Streaming**
neben dem regulären XMPP-Messaging anzubieten.

---

## 2. Use Cases

### 2.1 IoT / Smart Home Dashboard (Priorität: hoch)
- Sensordaten (Temperatur, Luftfeuchtigkeit, Türstatus) über MQTT-Topics subscriben
- Werte in einer dedizierten UI-Ansicht anzeigen (Kacheln/Widgets)
- Historische Werte als Sparkline-Diagramm
- Alerts bei Schwellwertüberschreitung

### 2.2 Bot-Event-Stream (Priorität: mittel)
- DinoX-Bots publizieren Status-Events über MQTT statt XMPP-Messages
- Leichtgewichtiger als volle XMPP-Stanzas
- Dashboard für Bot-Monitoring (online/offline, Nachrichtenzähler)

### 2.3 Push Notifications (Priorität: niedrig)
- MQTT als leichtgewichtiger Wakeup-Kanal für Mobile
- Battery-effizient durch dauerhaft offene TCP-Verbindung mit Keepalive
- Alternative zu XEP-0357 Push (das einen externen Push-Server braucht)

### 2.4 Cross-Protocol Bridging (Priorität: niedrig)
- MQTT-Nachrichten in XMPP-Chat weiterleiten und umgekehrt
- Brücke zwischen IoT-Welt und Chat-Welt

---

## 3. Architektur

```
┌─────────────────────────────────────────────────┐
│                    DinoX                        │
│                                                 │
│  ┌──────────┐   ┌──────────┐   ┌────────────┐  │
│  │ XMPP     │   │ MQTT     │   │ MQTT       │  │
│  │ Module   │   │ Plugin   │   │ UI Panel   │  │
│  │(existing)│   │(new)     │   │(new)       │  │
│  └─────┬────┘   └─────┬────┘   └─────┬──────┘  │
│        │              │              │          │
│        │    ┌─────────┴─────────┐    │          │
│        │    │ MqttClient        │    │          │
│        │    │ (libmosquitto)    │    │          │
│        │    └─────────┬─────────┘    │          │
│        │              │              │          │
└────────┼──────────────┼──────────────┼──────────┘
         │              │              │
    XMPP │         MQTT │              │ Signals
   (5222)│        (1883)│              │
         │              │              │
┌────────┴──────────────┴──────────────┘
│           ejabberd Server
│   ┌──────────┐  ┌──────────┐
│   │ XMPP     │  │ mod_mqtt │
│   │ Modules  │  │ (Broker) │
│   └──────────┘  └──────────┘
└─────────────────────────────────────┘
```

### 3.1 Komponenten

| Komponente | Datei | Beschreibung |
|-----------|-------|--------------|
| `Plugin` | `plugin.vala` | RootInterface, registriert sich bei DinoX, verwaltet Lifecycle |
| `MqttClient` | `mqtt_client.vala` | Wrapper um libmosquitto — connect, subscribe, publish, disconnect |
| `TopicManager` | `topic_manager.vala` | Verwaltet Topic-Subscriptions, parsed eingehende Payloads |
| `MqttSettingsWidget` | `settings_widget.vala` | GTK4-UI für MQTT-Konfiguration (Broker, Port, Topics) |
| `MqttDashboard` | `dashboard.vala` | GTK4-Panel mit Sensor-Kacheln und Event-Stream |
| Vala VAPI | `vapi/mosquitto.vapi` | Vala-Bindings für libmosquitto C-API |

### 3.2 Abhängigkeiten

| Library | Paket | Zweck |
|---------|-------|-------|
| libmosquitto | `libmosquitto-dev` | MQTT 5.0/3.1.1 Client-Bibliothek (C, pkg-config) |
| GLib | (vorhanden) | Main Loop Integration, GSource für mosquitto fd |
| GTK4 | (vorhanden) | UI-Widgets für Dashboard |

### 3.3 Main Loop Integration

libmosquitto läuft normalerweise mit eigenem Thread (`mosquitto_loop_start()`).
Für GTK-Integration besser: `mosquitto_loop_read/write/misc()` mit
GLib.IOChannel/GSource auf dem mosquitto-Socket — so läuft alles im GTK Main Loop
ohne Threading-Probleme.

---

## 4. MQTT-Konfiguration

```
# Gespeichert in DinoX-Settings (GSettings oder DB)
mqtt_enabled: bool = false
mqtt_broker_host: string = ""        # leer = gleicher Host wie XMPP
mqtt_broker_port: int = 1883         # 8883 für TLS
mqtt_use_tls: bool = true
mqtt_use_xmpp_credentials: bool = true  # XMPP-Login wiederverwenden
mqtt_username: string = ""           # nur wenn use_xmpp_credentials = false
mqtt_topics: string[] = []           # z.B. ["home/sensors/#", "bots/status/#"]
```

---

## 5. ejabberd Server-Konfiguration (Voraussetzung)

```yaml
listen:
  -
    port: 1883
    module: mod_mqtt
    backlog: 1000
  -
    port: 8883
    module: mod_mqtt
    backlog: 1000
    tls: true

modules:
  mod_mqtt:
    access_publish:
      "#":
        - allow
    access_subscribe:
      "#":
        - allow
```

---

## 6. Implementierungsplan

### Phase 1: Grundgerüst (v1.2.0)
- [x] Plugin-Skeleton erstellen (meson.build, plugin.vala, register_plugin.vala)
- [ ] Vala VAPI für libmosquitto schreiben
- [ ] MqttClient: connect/disconnect/subscribe/publish
- [ ] GLib Main Loop Integration (GSource auf mosquitto fd)
- [ ] Settings-UI: Enable/Disable, Broker, Port, TLS
- [ ] Auto-Connect wenn XMPP verbunden

### Phase 2: Dashboard (v1.2.1)
- [ ] Topic-Manager: Subscribe, Payload-Parsing (JSON, plain text)
- [ ] Dashboard-Widget: Kacheln mit Topic-Name + letztem Wert
- [ ] Sidebar-Eintrag für MQTT-Dashboard
- [ ] Topic-Verwaltung in Settings

### Phase 3: Alerts & History (v1.3.0)
- [ ] Schwellwert-Alerts (Notification wenn Wert > X)
- [ ] Sparkline-Diagramme für Verlauf (letzte 24h)
- [ ] MQTT-Events in Chat-Conversation weiterleiten können
- [ ] Retained Messages Support

### Phase 4: Advanced (v1.4.0)
- [ ] MQTT → XMPP Bridge (topics als Chat-Messages)
- [ ] Bot-Monitoring-Dashboard
- [ ] Windows-Build: libmosquitto Cross-Compile
- [ ] QoS Level Konfiguration (0/1/2)

---

## 7. Risiken & Offene Fragen

| Risiko | Mitigation |
|--------|-----------|
| libmosquitto nicht auf allen Plattformen verfügbar | Optional Dependency, Plugin wird nur geladen wenn lib vorhanden |
| Windows Cross-Compile | mosquitto hat CMake-Build, muss für MSYS2/MinGW angepasst werden |
| Threading vs Main Loop | GSource-Integration statt mosquitto_loop_start() |
| MQTT 5.0 vs 3.1.1 | libmosquitto unterstützt beides, default auf 5.0 |
| Battery Drain durch offene Verbindung | MQTT hat eingebautes Keep-Alive, deutlich effizienter als XMPP-Polling |

---

## 8. Referenzen

- [ejabberd MQTT Guide](https://docs.ejabberd.im/admin/guide/mqtt/)
- [libmosquitto API](https://mosquitto.org/api/files/mosquitto-h.html)
- [MQTT 5.0 Spec](https://docs.oasis-open.org/mqtt/mqtt/v5.0/mqtt-v5.0.html)
- [Eclipse Paho](https://www.eclipse.org/paho/) (alternative Client-Lib)
