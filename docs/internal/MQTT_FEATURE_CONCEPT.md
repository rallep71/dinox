# DinoX MQTT Plugin — Feature-Konzept

**Status:** Konzeptphase  
**Erstellt:** 2026-02-26  
**Version:** v0.3 (Entwurf — Server-agnostisch + HA/Node-RED Integration)

---

## 1. Motivation

Sowohl **ejabberd** als auch **Prosody** bieten MQTT-Anbindung, sodass
DinoX unabhängig vom eingesetzten Server-Typ MQTT nutzen kann:

### ejabberd — Nativer MQTT-Broker (`mod_mqtt`)
- **Gleiche Authentifizierung** — XMPP-Accounts (`user@domain`) funktionieren als MQTT-Logins
- **Gleiche ACL / Security Policy** — einmal definiert, gilt für beide Protokolle
- **Gleiche DB-Backends** — kein zweiter Server nötig
- **MQTT 5.0 + 3.1.1** — volle Protokoll-Unterstützung
- Quelle: https://docs.ejabberd.im/admin/guide/mqtt/#benefits

### Prosody — MQTT↔PubSub Bridge (`mod_pubsub_mqtt`)
- **MQTT-Topics = XMPP-PubSub-Nodes** — MQTT-Publishes landen als XEP-0060 Items
- **Bidirektional** — XMPP-Clients können PubSub-Nodes subscriben, MQTT-Clients dasselbe Topic
- **Community-Modul** — Beta, von Matthew Wild (Prosody-Lead)
- **MQTT 3.1.1** — kein Auth, nur QoS 0
- **Topic-Format:** `<HOST>/<TYPE>/<NODE>` (z.B. `pubsub.example.org/json/sensors`)
- **Payload-Typen:** json (XEP-0335), utf8, atom_title
- Quelle: https://modules.prosody.im/mod_pubsub_mqtt

### Server-Vergleich

| Feature | ejabberd (`mod_mqtt`) | Prosody (`mod_pubsub_mqtt`) |
|---------|----------------------|-----------------------------|
| MQTT-Version | 5.0 + 3.1.1 | 3.1.1 |
| Auth | XMPP-Credentials | Keine (!) |
| QoS | 0, 1, 2 | Nur 0 |
| Architektur | Nativer Broker (eigener Topic-Space) | Bridge → XMPP PubSub (XEP-0060) |
| XMPP-PubSub-Bridge | **Nein** — MQTT-Topics und XEP-0060 getrennt | **Ja** — MQTT = PubSub-Node |
| Topic-Format | Frei wählbar | `<HOST>/<TYPE>/<NODE>` |
| Payloads | Beliebig | json, utf8, atom_title |
| Status | Production | Beta (Community-Modul) |
| TLS | ✓ (Port 8883) | ✓ (Port 8883) |
| Standard-Port | 1883 | 1883 |

DinoX kann **beide Server-Typen** nutzen, da libmosquitto MQTT 3.1.1+ spricht.

**Prosody-Alleinstellungsmerkmal:** Bei Prosody sind MQTT-Publishes automatisch
als Standard-XMPP-PubSub-Nodes (XEP-0060) lesbar — auch Clients **ohne**
MQTT-Unterstützung können die Daten empfangen. Bei ejabberd sind MQTT-Topics
und XMPP-PubSub getrennte Welten (sie teilen nur Auth/ACL/DB-Infrastruktur).

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
│
│  ┌──────────────────────────────────┐  ┌──────────────────────────────────────┐
│  │     ejabberd Server             │  │     Prosody Server                   │
│  │  ┌──────────┐  ┌──────────┐     │  │  ┌──────────┐  ┌────────────────┐    │
│  │  │ XMPP     │  │ mod_mqtt │     │  │  │ XMPP     │  │mod_pubsub_mqtt │    │
│  │  │ Modules  │  │ (native) │     │  │  │ Modules  │  │(→ PubSub XEP60)│    │
│  │  └──────────┘  └──────────┘     │  │  └──────────┘  └────────────────┘    │
│  └──────────────────────────────────┘  └──────────────────────────────────────┘
│           (MQTT 5.0 + 3.1.1)                    (MQTT 3.1.1 only)
└─┘
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
mqtt_server_type: string = "auto"    # "auto", "ejabberd", "prosody"
mqtt_use_xmpp_credentials: bool = true  # XMPP-Login wiederverwenden (nur ejabberd)
mqtt_username: string = ""           # nur wenn use_xmpp_credentials = false
mqtt_topics: string[] = []           # z.B. ["home/sensors/#", "bots/status/#"]
#
# Hinweis: Bei Prosody haben Topics das Format <HOST>/<TYPE>/<NODE>,
# z.B. "pubsub.example.org/json/sensors". DinoX kann das automatisch
# erkennen wenn mqtt_server_type = "auto".
```

---

## 5. Server-Konfiguration (Voraussetzung)

### 5.1 ejabberd

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

### 5.2 Prosody

```lua
-- Installation:
-- sudo prosodyctl install --server=https://modules.prosody.im/rocks/ mod_pubsub_mqtt

Component "pubsub.example.org" "pubsub"
    modules_enabled = { "pubsub_mqtt" }

-- Optional: Ports (global section)
mqtt_ports = { 1883 }
mqtt_tls_ports = { 8883 }
```

**Achtung:** Prosody's `mod_pubsub_mqtt` hat aktuell **keine Authentifizierung**
und nur **QoS 0**. Für Produktionsumgebungen sollte der MQTT-Port durch
Firewall-Regeln oder VPN geschützt werden.

---

## 6. Implementierungsplan

### Phase 1: Grundgerüst (v1.2.0)
- [x] Plugin-Skeleton erstellen (meson.build, plugin.vala, register_plugin.vala)
- [x] Vala VAPI für libmosquitto schreiben
- [ ] MqttClient: connect/disconnect/subscribe/publish
- [ ] GLib Main Loop Integration (GSource auf mosquitto fd)
- [ ] Server-Typ-Erkennung (ejabberd vs Prosody, Topic-Format-Handling)
- [ ] Settings-UI: Enable/Disable, Broker, Port, TLS, Server-Typ
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
| MQTT 5.0 vs 3.1.1 | libmosquitto unterstützt beides; ejabberd→5.0, Prosody→3.1.1 |
| Prosody kein Auth | MQTT-Port mit Firewall/VPN sichern, DinoX warnt in Settings |
| Prosody Topic-Format | Plugin erkennt Server-Typ und passt Topic-Prefix automatisch an |
| Battery Drain durch offene Verbindung | MQTT hat eingebautes Keep-Alive, deutlich effizienter als XMPP-Polling |

---

## 8. Integration: Home Assistant & Node-RED

### 8.1 Übersicht

Home Assistant (HA) und Node-RED sind die beiden wichtigsten Smart-Home-Plattformen
und beide haben **erstklassige MQTT-Unterstützung**:

| Plattform | MQTT-Feature | Details |
|-----------|-------------|---------|
| **Home Assistant** | Eingebaute MQTT-Integration | Auto-Discovery (`homeassistant/+/…/config`), Publish/Subscribe, MQTT 3.1.1 + 5.0 |
| **Node-RED** | `mqtt in` / `mqtt out` Nodes | Verbindet sich mit beliebigem Broker, JSON-Parsing, Flows |

DinoX kann sich als **MQTT-Client** mit dem gleichen Broker verbinden, den auch
HA und Node-RED nutzen, und so dieselben Sensordaten, Events und Aktoren empfangen.

### 8.2 Netzwerk-Szenarien

#### Szenario A: Alles lokal (LAN)

```
┌─────────────────── Lokales Netzwerk (192.168.x.x) ──────────────────┐
│                                                                      │
│  ┌──────────┐    ┌──────────────────┐    ┌──────────────────┐       │
│  │  DinoX   │    │  Home Assistant  │    │    Node-RED      │       │
│  │ (Desktop)│    │  (Raspberry Pi)  │    │ (Docker/RPi)     │       │
│  └────┬─────┘    └───────┬──────────┘    └───────┬──────────┘       │
│       │                  │                       │                   │
│       │     MQTT (1883)  │         MQTT (1883)   │                   │
│       └─────────┬────────┴───────────────────────┘                   │
│                 │                                                     │
│       ┌─────────┴─────────┐                                          │
│       │   MQTT-Broker     │  ← ejabberd mod_mqtt                     │
│       │ (ejabberd/Prosody │    ODER Prosody mod_pubsub_mqtt          │
│       │  ODER Mosquitto)  │    ODER standalone Mosquitto              │
│       └───────────────────┘                                          │
└──────────────────────────────────────────────────────────────────────┘
```

**Einfachster Fall:** Alle Geräte im gleichen Netzwerk.
- DinoX verbindet sich zu `mqtt://192.168.x.x:1883`
- Keine TLS nötig (optional empfohlen)
- Kein Internet-Zugang erforderlich

#### Szenario B: XMPP-Server im Internet, Smart Home lokal

```
┌─── Internet ─────────────┐     ┌─── Lokales Netzwerk ─────────────┐
│                           │     │                                   │
│  ┌───────────────────┐    │     │  ┌────────────────┐              │
│  │ ejabberd/Prosody  │    │     │  │ Home Assistant  │              │
│  │ (XMPP + MQTT)     │    │     │  └───────┬────────┘              │
│  │ mqtt.example.org  │    │     │          │                        │
│  └────────┬──────────┘    │     │  ┌───────┴────────┐              │
│           │               │     │  │ Mosquitto       │              │
│           │ TLS (8883)    │     │  │ (HA Add-on)     │              │
│           │               │     │  │ Port 1883       │              │
└───────────┼───────────────┘     │  └───────┬────────┘              │
            │                      │          │                        │
    ┌───────┴──────┐               │  ┌───────┴────────┐              │
    │    DinoX     │               │  │    Node-RED     │              │
    │ (überall)    │               │  └────────────────┘              │
    └──────────────┘               └──────────────────────────────────┘
```

**Häufigster Fall im Praxis:** XMPP-Server im Internet, Smart Home lokal.

**Zwei Broker-Optionen:**

1. **DinoX → lokaler Mosquitto (HA Add-on)**
   - DinoX verbindet sich direkt zum lokalen Mosquitto (Port-Forwarding oder VPN)
   - Vorteil: Alle HA-Sensoren direkt sichtbar
   - Nachteil: Lokaler Broker muss erreichbar sein

2. **Mosquitto-Bridge** (empfohlen)
   - Lokaler Mosquitto leitet ausgewählte Topics an ejabberd/Prosody weiter
   - DinoX verbindet sich nur zum Internet-Broker
   - Konfiguration in `/etc/mosquitto/conf.d/bridge.conf`:

```
# Lokaler Mosquitto → ejabberd/Prosody Bridge
connection xmpp-bridge
address mqtt.example.org:8883
bridge_capath /etc/ssl/certs
remote_username user@example.org
remote_password geheim
topic home/sensors/# out 1
topic home/actuators/# both 1
topic dinox/# in 1
```

#### Szenario C: Alles im Internet / Cloud

```
┌─── Internet / Cloud ──────────────────────────────────────────────┐
│                                                                    │
│  ┌───────────────┐   ┌───────────────┐   ┌───────────────┐       │
│  │   DinoX       │   │ Home Assistant │   │   Node-RED    │       │
│  │   (Client)    │   │   (Cloud/VPS)  │   │   (Cloud)     │       │
│  └───────┬───────┘   └───────┬───────┘   └───────┬───────┘       │
│          │                   │                   │                 │
│          │     TLS (8883)    │      TLS (8883)   │                 │
│          └──────────┬────────┴───────────────────┘                 │
│                     │                                               │
│           ┌─────────┴──────────┐                                    │
│           │  ejabberd/Prosody  │                                    │
│           │  (MQTT + XMPP)    │                                    │
│           └────────────────────┘                                    │
└────────────────────────────────────────────────────────────────────┘
```

**TLS ist Pflicht.** Alle Clients nutzen Port 8883 mit Zertifikatsvalidierung.

### 8.3 Home Assistant Anbindung

**HA verbindet sich zum gleichen MQTT-Broker wie DinoX.** Die Konfiguration erfolgt
in HA unter „Settings → Devices & Services → MQTT":

- **Broker:** IP/Hostname des ejabberd/Prosody/Mosquitto
- **Port:** 1883 (lokal) oder 8883 (TLS)
- **Username/Password:** XMPP-Credentials (ejabberd) oder leer (Prosody)

**HA MQTT Discovery:** HA registriert Geräte automatisch über Topics wie:
```
homeassistant/sensor/wohnzimmer_temp/config   → Konfiguration (JSON)
homeassistant/sensor/wohnzimmer_temp/state    → Messwerte
```

**DinoX kann diese Topics subscriben** und die Sensordaten im Dashboard anzeigen:
```
# Beispiel: Alle HA-Sensoren empfangen
mqtt_topics: ["homeassistant/sensor/#", "homeassistant/binary_sensor/#"]
```

**Aktoren steuern** (z.B. Licht an/aus):
```
# Publish an HA-Command-Topic
topic: homeassistant/switch/irrigation/set
payload: ON
```

### 8.4 Node-RED Anbindung

Node-RED verbindet sich über den `mqtt-broker`-Node zum gleichen Broker:

```
┌──────────┐    ┌─────────────────┐    ┌──────────────┐
│ Sensor   │───→│ Node-RED Flow   │───→│ MQTT Broker  │───→ DinoX
│ (HTTP/   │    │ (Verarbeitung,  │    │              │
│  GPIO)   │    │  Formatierung)  │    │              │
└──────────┘    └─────────────────┘    └──────────────┘
```

**Beispiel Node-RED Flow** (JSON-Import):
```json
[
  {"id":"mqtt-out","type":"mqtt out","topic":"home/sensors/temperature",
   "broker":"mqtt-broker-node","qos":"1","retain":"true"},
  {"id":"mqtt-broker-node","type":"mqtt-broker",
   "broker":"mqtt.example.org","port":"8883","tls":"true",
   "credentials":{"user":"user@example.org","password":"geheim"}}
]
```

Node-RED kann auch **DinoX-Events konsumieren**:
```
# Node-RED subscribes auf DinoX-Bot-Topics
topic: dinox/bots/status/#
```

### 8.5 Empfohlene Topic-Hierarchie

Um Kollisionen zu vermeiden, empfiehlt sich folgende Struktur:

```
home/                          ← Smart Home (HA / Node-RED)
  sensors/
    temperature/wohnzimmer     → {"value": 22.1, "unit": "°C"}
    humidity/schlafzimmer      → {"value": 45, "unit": "%"}
    door/haustuer              → {"state": "closed"}
  actuators/
    light/wohnzimmer/set       → ON / OFF
    thermostat/wohnzimmer/set  → {"target": 21.0}

homeassistant/                 ← HA Discovery (automatisch)
  sensor/…/config
  binary_sensor/…/config

dinox/                         ← DinoX-eigene Topics
  bots/status/#                → Bot-Status-Events
  notifications/#              → Push-Notifications
  bridge/#                     → XMPP↔MQTT Bridge-Messages

nodered/                       ← Node-RED Flows
  alerts/#                     → Verarbeitete Alarme
  automations/#                → Automations-Status
```

### 8.6 Netzwerk-Sicherheit

| Szenario | Empfehlung |
|----------|-----------|
| LAN-only | TLS optional, Firewall auf Port 1883 (nur LAN) |
| Internet | **TLS Pflicht** (Port 8883), Username+Passwort |
| Gemischt (Bridge) | Bridge mit TLS, lokaler Broker ohne TLS akzeptabel |
| Prosody (kein Auth) | MQTT-Port **nur** im LAN/VPN erreichbar machen |

**DinoX Settings-UI sollte warnen** wenn:
- TLS deaktiviert bei nicht-lokaler IP
- Prosody (kein Auth) bei Internet-Zugang

---

## 9. Referenzen

- [ejabberd MQTT Guide](https://docs.ejabberd.im/admin/guide/mqtt/)
- [Prosody mod_pubsub_mqtt](https://modules.prosody.im/mod_pubsub_mqtt)
- [Prosody PubSub Doku](https://prosody.im/doc/pubsub)
- [Home Assistant MQTT Integration](https://www.home-assistant.io/integrations/mqtt/)
- [Home Assistant MQTT Discovery](https://www.home-assistant.io/integrations/mqtt/#mqtt-discovery)
- [Node-RED MQTT Nodes](https://nodered.org/docs/user-guide/messages)
- [Mosquitto Bridge Konfiguration](https://mosquitto.org/man/mosquitto-conf-5.html)
- [XEP-0060: PubSub](https://xmpp.org/extensions/xep-0060.html)
- [XEP-0335: JSON Containers](https://xmpp.org/extensions/xep-0335.html)
- [libmosquitto API](https://mosquitto.org/api/files/mosquitto-h.html)
- [MQTT 5.0 Spec](https://docs.oasis-open.org/mqtt/mqtt/v5.0/mqtt-v5.0.html)
- [Eclipse Paho](https://www.eclipse.org/paho/) (alternative Client-Lib)
