# DinoX MQTT Plugin — Feature Concept

**Status:** Concept Phase  
**Created:** 2026-02-26  
**Version:** v0.6 (Draft — Bot-Conversation UX Concept)

---

## 1. Motivation

The DinoX MQTT plugin uses **libmosquitto** as a standard MQTT client and
connects to **any MQTT broker** — no XMPP server integration required.
Users can subscribe and publish to any Mosquitto, HiveMQ, EMQX, CloudMQTT,
AWS IoT Core, or other MQTT 3.1.1/5.0 broker by simply entering the broker
address in the settings.

As a **bonus**, both ejabberd and Prosody offer built-in MQTT connectivity,
allowing DinoX to optionally reuse XMPP credentials or bridge MQTT topics
to XMPP PubSub:

### ejabberd — Native MQTT Broker (`mod_mqtt`)
- **Shared Authentication** — XMPP accounts (`user@domain`) work as MQTT logins
- **Shared ACL / Security Policy** — defined once, applies to both protocols
- **Shared DB Backends** — no second server needed
- **MQTT 5.0 + 3.1.1** — full protocol support
- Source: https://docs.ejabberd.im/admin/guide/mqtt/#benefits

### Prosody — MQTT↔PubSub Bridge (`mod_pubsub_mqtt`)
- **MQTT Topics = XMPP PubSub Nodes** — MQTT publishes land as XEP-0060 items
- **Bidirectional** — XMPP clients can subscribe to PubSub nodes, MQTT clients to the same topic
- **Community Module** — Beta, by Matthew Wild (Prosody lead)
- **MQTT 3.1.1** — no auth, QoS 0 only
- **Topic Format:** `<HOST>/<TYPE>/<NODE>` (e.g. `pubsub.example.org/json/sensors`)
- **Payload Types:** json (XEP-0335), utf8, atom_title
- Source: https://modules.prosody.im/mod_pubsub_mqtt

### Server Comparison

| Feature | ejabberd (`mod_mqtt`) | Prosody (`mod_pubsub_mqtt`) |
|---------|----------------------|-----------------------------|
| MQTT Version | 5.0 + 3.1.1 | 3.1.1 |
| Auth | XMPP Credentials | None (!) |
| QoS | 0, 1, 2 | 0 only |
| Architecture | Native Broker (own topic space) | Bridge → XMPP PubSub (XEP-0060) |
| XMPP PubSub Bridge | **No** — MQTT topics and XEP-0060 are separate | **Yes** — MQTT = PubSub node |
| Topic Format | Freely configurable | `<HOST>/<TYPE>/<NODE>` |
| Payloads | Arbitrary | json, utf8, atom_title |
| Status | Production | Beta (community module) |
| TLS | Yes (Port 8883) | Yes (Port 8883, [since Jan 2024](https://hg.prosody.im/prosody-modules/rev/801f64e6d4e9)) |
| Default Port | 1883 | 1883 |

DinoX works with **any MQTT broker**. The ejabberd/Prosody integration is
optional — the plugin is a general-purpose MQTT client first.

**Prosody's Unique Advantage:** With Prosody, MQTT publishes are automatically
readable as standard XMPP PubSub nodes (XEP-0060) — even clients **without**
MQTT support can receive the data. With ejabberd, MQTT topics and XMPP PubSub
are separate worlds (they only share auth/ACL/DB infrastructure).

---

## 2. Use Cases

### 2.1 IoT / Smart Home Dashboard (Priority: high)
- Subscribe to sensor data (temperature, humidity, door status) via MQTT topics
- Display values in a dedicated UI view (tiles/widgets)
- Historical values as sparkline charts
- Alerts on threshold exceedance

### 2.2 Bot Event Stream (Priority: medium)
- DinoX bots publish status events via MQTT instead of XMPP messages
- More lightweight than full XMPP stanzas
- Dashboard for bot monitoring (online/offline, message counters)

### 2.3 Push Notifications (Priority: low)
- MQTT as lightweight wakeup channel for mobile
- Battery-efficient via persistent TCP connection with keepalive
- Alternative to XEP-0357 Push (which requires an external push server)

### 2.4 Cross-Protocol Bridging (Priority: low)
- Forward MQTT messages to XMPP chat and vice versa
- Bridge between IoT world and chat world

---

## 3. Architecture

```
┌─────────────────────────────────────────────────┐
│                    DinoX                        │
│                                                 │
│  ┌──────────┐   ┌──────────┐   ┌────────────┐   │
│  │ XMPP     │   │ MQTT     │   │ MQTT       │   │
│  │ Module   │   │ Plugin   │   │ UI Panel   │   │
│  │(existing)│   │(new)     │   │(new)       │   │
│  └─────┬────┘   └─────┬────┘   └─────┬──────┘   │
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
│  │     ejabberd Server              │  │     Prosody Server                   │
│  │  ┌──────────┐  ┌──────────┐      │  │  ┌──────────┐  ┌────────────────┐    │
│  │  │ XMPP     │  │ mod_mqtt │      │  │  │ XMPP     │  │mod_pubsub_mqtt │    │
│  │  │ Modules  │  │ (native) │      │  │  │ Modules  │  │(→ PubSub XEP60)│    │
│  │  └──────────┘  └──────────┘      │  │  └──────────┘  └────────────────┘    │
│  └──────────────────────────────────┘  └──────────────────────────────────────┘
│           (MQTT 5.0 + 3.1.1)                    (MQTT 3.1.1 only)
└─┘
```

### 3.1 Components

| Component | File | Description |
|-----------|------|-------------|
| `Plugin` | `plugin.vala` | RootInterface, registers with DinoX, manages lifecycle |
| `MqttClient` | `mqtt_client.vala` | Wrapper around libmosquitto — connect, subscribe, publish, disconnect |
| `TopicManager` | `topic_manager.vala` | Manages topic subscriptions, parses incoming payloads |
| `MqttSettingsWidget` | `settings_widget.vala` | GTK4 UI for MQTT configuration (broker, port, topics) |
| `MqttDashboard` | `dashboard.vala` | GTK4 panel with sensor tiles and event stream |
| Vala VAPI | `vapi/mosquitto.vapi` | Vala bindings for libmosquitto C API |

### 3.2 Dependencies

| Library | Package | Purpose |
|---------|---------|---------|
| libmosquitto | `libmosquitto-dev` | MQTT 5.0/3.1.1 client library (C, pkg-config) |
| GLib | (existing) | Main loop integration, GSource for mosquitto fd |
| GTK4 | (existing) | UI widgets for dashboard |

### 3.3 Main Loop Integration

libmosquitto normally runs with its own thread (`mosquitto_loop_start()`).
For GTK integration it's better to use `mosquitto_loop_read/write/misc()` with
GLib.IOChannel/GSource on the mosquitto socket — this way everything runs in the
GTK main loop without threading issues.

---

## 4. MQTT Configuration

```
# Stored in DinoX settings (GSettings or DB)
mqtt_enabled: bool = false
mqtt_broker_host: string = ""        # any broker: IP, hostname, or domain
mqtt_broker_port: int = 1883         # 8883 for TLS
mqtt_use_tls: bool = true
mqtt_server_type: string = "auto"    # "auto", "ejabberd", "prosody", "standalone"
mqtt_use_xmpp_credentials: bool = false # true = reuse XMPP login (ejabberd only)
mqtt_username: string = ""           # broker credentials (standalone / Prosody)
mqtt_password: string = ""           # broker credentials
mqtt_topics: string[] = []           # e.g. ["home/sensors/#", "bots/status/#"]
#
# Note: With Prosody, topics use the format <HOST>/<TYPE>/<NODE>,
# e.g. "pubsub.example.org/json/sensors". DinoX can auto-detect
# this when mqtt_server_type = "auto".
```

---

## 5. Server Configuration (Prerequisite)

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

**Warning:** Prosody's `mod_pubsub_mqtt` supports TLS on port 8883
([added Jan 2024](https://hg.prosody.im/prosody-modules/rev/801f64e6d4e9))
but still has **no authentication** and only **QoS 0**. TLS encrypts the
connection but does not restrict access. For production environments, the
MQTT port should be protected by firewall rules or VPN.

---

## 6. UX Concept: Bot-Conversation Paradigm

### 6.1 Core Idea

MQTT data is **not** displayed in a separate dashboard, sidebar, or tab.  
Instead, a **virtual bot contact** (e.g. `MQTT Bot`) appears in the regular  
conversation list. All MQTT messages arrive as **chat messages from this bot**,  
and the user can send **commands** to the bot via the chat input.

**Why Bot-Conversation instead of Dashboard?**

- DinoX is a **chat client** — a conversation-based UI is the natural paradigm
- No new navigation concepts needed (sidebar entries, tab bars, floating panels)
- Notifications work like any other chat (badge, sound, unread counter)
- Mobile-friendly — same layout on desktop and mobile
- Users already understand how to interact with bots in chat

### 6.2 Visibility & Lifecycle

The MQTT Bot follows strict visibility rules:

| State | Bot visible? | Behavior |
|-------|-------------|----------|
| MQTT disabled in settings | **No** | Bot does not appear in contact list |
| MQTT enabled, not connected | **Yes** (greyed out) | Shows "Connecting…" or "Offline" status |
| MQTT enabled, connected, no data yet | **Yes** | Shows "Waiting for data…" |
| **Data arrives on subscribed topic** | **Yes + notification** | Bot appears immediately, badge/sound like a real message |
| MQTT disabled after use | **No** | Bot disappears from contact list, history preserved in DB |

**Key rule:** The bot **must become visible as soon as a subscribed value arrives** —  
even if the user has never opened the bot conversation. This is push-notification  
behavior: if you subscribe to `home/sensors/benzinpreis` and a value comes in,  
the bot appears with a notification like:

```
MQTT Bot
  Benzin: 1,299 EUR/L (Tanke Aral, 14:32)
```

This way the user does not need to actively check for MQTT data — the **data comes  
to the user**, just like a message from a real contact.

### 6.3 Message Display

Incoming MQTT messages appear as chat bubbles from the bot:

```
┌──────────────────────────────────────────────────┐
│  MQTT Bot                                   ≡    │
│                                                  │
│  ┌─────────────────────────────────────────────┐ │
│  │ [topic] home/sensors/temperature            │ │
│  │ Temperature: 22.1°C                    14:32│ │
│  └─────────────────────────────────────────────┘ │
│                                                  │
│  ┌─────────────────────────────────────────────┐ │
│  │ [topic] home/sensors/door/front             │ │
│  │ Door: OPEN [!]                         14:33│ │
│  └─────────────────────────────────────────────┘ │
│                                                  │
│  ┌─────────────────────────────────────────────┐ │
│  │ [topic] benzin/preise/aral_karlsruhe        │ │
│  │ Benzin: 1,299 EUR/L                   14:35 │ │
│  └─────────────────────────────────────────────┘ │
│                                                  │
│  ┌───────────────────────────────────┐  [Send]   │
│  │ /mqtt subscribe home/alerts/#     │           │
│  └───────────────────────────────────┘           │
└──────────────────────────────────────────────────┘
```

**Message formatting rules:**

- Topic name displayed as header (small, grey)
- Payload parsed: JSON values extracted and formatted, plain text shown as-is
- Timestamp from receive time (or MQTT 5.0 User Property if available)
- Retained messages marked with [pinned] icon
- Alert thresholds trigger [!] warning icon and notification sound

### 6.4 Chat Commands

The user types commands in the chat input to control MQTT:

| Command | Action |
|---------|--------|
| `/mqtt status` | Show connection status, broker, subscribed topics |
| `/mqtt subscribe <topic>` | Subscribe to a new topic (wildcards supported) |
| `/mqtt unsubscribe <topic>` | Unsubscribe from a topic |
| `/mqtt publish <topic> <payload>` | Publish a message to a topic |
| `/mqtt topics` | List all active subscriptions with last values |
| `/mqtt alert <topic> <condition>` | Set threshold alert (e.g. `/mqtt alert temp > 30`) |
| `/mqtt history <topic>` | Show last N values for a topic |
| `/mqtt pause` | Pause all messages (bot stays visible but stops showing data) |
| `/mqtt resume` | Resume message display |

**Alternative:** Instead of slash commands, a **toolbar button** in the bot  
conversation header could open a settings popover for topic management.

### 6.5 Per-Account Bot vs Standalone Bot

DinoX supports both **per-account** and **standalone** MQTT connections.  
Each connection gets its **own bot contact**:

| Mode | Bot Name | When Used |
|------|----------|-----------|
| Per-account (ejabberd) | `MQTT Bot (user@example.org)` | MQTT via ejabberd `mod_mqtt` — reuses XMPP auth |
| Per-account (Prosody) | `MQTT Bot (user@example.org)` | MQTT via Prosody `mod_pubsub_mqtt` — topics bridged to PubSub |
| Standalone | `MQTT Bot` | Direct connection to any MQTT broker |

**Multiple bots are possible** — e.g. one per XMPP account (each with its own  
ejabberd MQTT broker) plus one standalone connection to a local Mosquitto.  
Each bot is a separate conversation.

### 6.6 ejabberd-Specific UX

When the XMPP server is ejabberd with `mod_mqtt`:

- **Auto-detect:** DinoX can check for `mod_mqtt` via XEP-0030 Service Discovery
- **Shared auth:** MQTT login = XMPP credentials → no separate username/password in UI
- **Topic isolation:** MQTT topics are separate from XMPP PubSub — the bot shows
  only MQTT data, no PubSub crossover
- **MQTT 5.0 features:** User Properties in messages can carry metadata (units, labels)
- **Settings hint:** "Your server supports MQTT — enable MQTT Bot to receive sensor data"

### 6.7 Prosody-Specific UX

When the XMPP server is Prosody with `mod_pubsub_mqtt`:

- **Topic format:** Topics follow `<HOST>/<TYPE>/<NODE>` — DinoX must present this
  clearly, e.g. show `pubsub.example.org/json/sensors` as "sensors (JSON)"
- **No auth:** No username/password required — DinoX should show a security warning
  ("MQTT port is open without authentication — use TLS + firewall")
- **PubSub bridge:** MQTT publishes are visible as XEP-0060 PubSub items — the bot
  could show a hint: "This data is also available via XMPP PubSub"
- **QoS 0 only:** Messages may be lost — bot could show a disclaimer for unreliable
  topics or offer retry/polling as fallback
- **Payload types:** Prosody supports `json`, `utf8`, `atom_title` — the bot should
  auto-detect and format accordingly

### 6.8 Settings Location

MQTT settings are placed in:

**Per-account mode:**
```
Preferences → Accounts → [Account Name] → MQTT
  [x] Enable MQTT Bot
  Server type: [Auto-detect | ejabberd | Prosody | Custom Broker]
  Broker: ________ Port: ____
  [x] Use XMPP credentials (ejabberd only)
  Topics: [ home/sensors/# ] [+]
```

**Standalone mode:**
```
Preferences → MQTT (global)
  [x] Enable Standalone MQTT Bot
  Broker: ________ Port: ____
  Username: ________ Password: ________
  [x] TLS
  Topics: [ home/sensors/# ] [+]
```

### 6.9 Notification Behavior

The MQTT Bot uses the **same notification system** as regular chat contacts:

- **Unread badge** on the bot conversation when new MQTT data arrives
- **Desktop notification** for alert messages (threshold exceeded, critical state)
- **Sound** configurable per topic or globally (default: standard message sound)
- **Do Not Disturb** respected — MQTT messages are silenced in DND mode
- **Quiet mode** option: data arrives silently (no badge/sound), user checks manually

**Priority levels for MQTT messages:**

| Priority | Trigger | Notification |
|----------|---------|-------------|
| Normal | Regular sensor data | Unread badge only |
| Alert | Threshold exceeded (`/mqtt alert`) | Badge + desktop notification |
| Critical | User-defined critical topics | Badge + notification + sound |
| Silent | Status updates, heartbeats | No notification, visible in history |

---

## 7. Implementation Plan

### Phase 1: Foundation (v1.2.0)
- [x] Create plugin skeleton (meson.build, plugin.vala, register_plugin.vala)
- [x] Write Vala VAPI for libmosquitto
- [x] Windows build: MSYS2 package verified, meson.build + update_dist.sh adapted
- [x] Flatpak build: Mosquitto module added to manifest
- [x] MqttClient: connect/disconnect/subscribe/publish (real libmosquitto calls)
- [x] GLib main loop integration (IOChannel + Timeout on mosquitto socket)
- [x] Auto-connect when XMPP is connected (env-var config for Phase 1)
- [x] Reconnection logic (auto-reconnect after 5 s, re-subscribe topics)
- [x] Server type detection (ejabberd vs Prosody via XEP-0030 disco)
- [x] Settings UI: enable/disable, broker, port, TLS, server type

### Phase 2: Bot-Conversation (v1.2.1)
- [x] Virtual bot contact: create MQTT Bot entity in conversation list
- [x] Bot visibility lifecycle (appear on data, disappear on disable)
- [x] Incoming MQTT messages → chat message bubbles (topic header + payload)
- [x] Payload parsing: JSON value extraction, plain text
- [x] Bot per-account + standalone (separate conversations)
- [x] Chat commands: `/mqtt subscribe`, `/mqtt publish`, `/mqtt status`, `/mqtt topics`
- [ ] ejabberd auto-detect (XEP-0030 → `mod_mqtt`) + shared auth hint
- [ ] Prosody topic format display (`<HOST>/<TYPE>/<NODE>` → human-readable)

### Phase 3: Alerts & Notifications (v1.3.0)
- [x] Threshold alerts (`/mqtt alert <topic> <condition>`)
- [x] Notification priority system (normal / alert / critical / silent)
- [x] Alert messages with warning icon + desktop notification + sound
- [x] Topic-level notification settings (per-topic sound/silent)
- [x] History: last N values per topic in bot conversation
- [ ] Prosody security warning (no auth → warning in settings + bot)

### Phase 4: Advanced (v1.4.0)
- [ ] MQTT → XMPP bridge (forward MQTT topics to real XMPP contacts)
- [ ] Sparkline charts for topic history in bot conversation
- [ ] QoS level configuration (0/1/2, per topic)
- [ ] MQTT 5.0 User Properties display (units, labels from ejabberd)
- [ ] Bot toolbar: visual topic manager (subscribe/unsubscribe without commands)

---

## 8. Risks & Open Questions

| Risk | Mitigation |
|------|-----------|
| libmosquitto not available on all platforms | Optional dependency, plugin only loads when lib is present |
| ~~Windows cross-compile~~ | **Resolved:** MSYS2 has `mingw-w64-x86_64-mosquitto` (v2.0.22+) as a prebuilt package — no CMake build needed. `pacman -S mingw-w64-x86_64-mosquitto` installs DLL, headers, pkg-config. Auto-detect in `update_dist.sh` copies `libmosquitto.dll` automatically. |
| ~~Flatpak build~~ | **Resolved:** Mosquitto module added to `im.github.rallep71.DinoX.json` (CMake, client lib only, no broker/CLI). |
| ~~Threading vs main loop~~ | **Resolved:** IOChannel watch on mosquitto fd + Timeout for loop_misc(). TCP connect runs in GLib.Thread to avoid blocking the GUI. No threading issues. |
| MQTT 5.0 vs 3.1.1 | libmosquitto supports both; ejabberd→5.0, Prosody→3.1.1 |
| Prosody no auth | Secure MQTT port with firewall/VPN, DinoX warns in settings |
| Prosody topic format | Plugin detects server type and adapts topic prefix automatically |
| Battery drain from open connection | MQTT has built-in keep-alive, significantly more efficient than XMPP polling |

---

## 9. Integration: Home Assistant & Node-RED

### 9.1 Overview

Home Assistant (HA) and Node-RED are the two most important smart home platforms,
and both have **first-class MQTT support**:

| Platform | MQTT Feature | Details |
|----------|-------------|---------|
| **Home Assistant** | Built-in MQTT integration | Auto-discovery (`homeassistant/+/…/config`), publish/subscribe, MQTT 3.1.1 + 5.0 |
| **Node-RED** | `mqtt in` / `mqtt out` nodes | Connects to any broker, JSON parsing, flows |

DinoX can connect as an **MQTT client** to the same broker that HA and Node-RED
use, receiving the same sensor data, events, and actuator states.

### 9.2 Network Scenarios

#### Scenario A: All Local (LAN)

```
┌─────────────────── Local Network (192.168.x.x) ─────────────────────-┐
│                                                                      │
│  ┌──────────┐    ┌──────────────────┐    ┌──────────────────┐        │
│  │  DinoX   │    │  Home Assistant  │    │    Node-RED      │        │
│  │ (Desktop)│    │  (Raspberry Pi)  │    │ (Docker/RPi)     │        │
│  └────┬─────┘    └───────┬──────────┘    └───────┬──────────┘        │
│       │                  │                       │                   │
│       │     MQTT (1883)  │         MQTT (1883)   │                   │
│       └─────────┬────────┴───────────────────────┘                   │
│                 │                                                    │
│       ┌─────────┴─────────┐                                          │
│       │   MQTT Broker     │  ← ejabberd mod_mqtt                     │
│       │ (ejabberd/Prosody │    OR Prosody mod_pubsub_mqtt            │
│       │  OR Mosquitto)    │    OR standalone Mosquitto               │
│       └───────────────────┘                                          │
└──────────────────────────────────────────────────────────────────────┘
```

**Simplest case:** All devices on the same network.
- DinoX connects to `mqtt://192.168.x.x:1883`
- No TLS needed (optionally recommended)
- No internet access required

#### Scenario B: XMPP Server on Internet, Smart Home Local

```
┌─── Internet ─────────────┐     ┌─── Local Network ────────────────┐
│                          │     │                                  │
│  ┌───────────────────┐   │     │  ┌────────────────┐              │
│  │ ejabberd/Prosody  │   │     │  │ Home Assistant │              │
│  │ (XMPP + MQTT)     │   │     │  └───────┬────────┘              │
│  │ mqtt.example.org  │   │     │          │                       │
│  └────────┬──────────┘   │     │  ┌───────┴────────┐              │
│           │              │     │  │ Mosquitto      │              │
│           │ TLS (8883)   │     │  │ (HA Add-on)    │              │
│           │              │     │  │ Port 1883      │              │
└───────────┼──────────────┘     │  └───────┬────────┘              │
            │                    │          │                       │
    ┌───────┴──────┐             │  ┌───────┴────────┐              │
    │    DinoX     │             │  │    Node-RED    │              │
    │ (anywhere)   │             │  └────────────────┘              │
    └──────────────┘             └──────────────────────────────────┘
```

**Most common real-world case:** XMPP server on the internet, smart home local.

**Two broker options:**

1. **DinoX → local Mosquitto (HA add-on)**
   - DinoX connects directly to local Mosquitto (port forwarding or VPN)
   - Advantage: All HA sensors directly visible
   - Disadvantage: Local broker must be reachable

2. **Mosquitto Bridge** (recommended)
   - Local Mosquitto forwards selected topics to ejabberd/Prosody
   - DinoX only connects to the internet broker
   - Configuration in `/etc/mosquitto/conf.d/bridge.conf`:

```
# Local Mosquitto → ejabberd/Prosody Bridge
connection xmpp-bridge
address mqtt.example.org:8883
bridge_capath /etc/ssl/certs
remote_username user@example.org
remote_password secret
topic home/sensors/# out 1
topic home/actuators/# both 1
topic dinox/# in 1
```

#### Scenario C: Everything on Internet / Cloud

```
┌─── Internet / Cloud ──────────────────────────────────────────────┐
│                                                                   │
│  ┌───────────────┐   ┌───────────────┐   ┌───────────────┐        │
│  │   DinoX       │   │ Home Assistant│   │   Node-RED    │        │
│  │   (Client)    │   │   (Cloud/VPS) │   │   (Cloud)     │        │
│  └───────┬───────┘   └───────┬───────┘   └───────┬───────┘        │
│          │                   │                   │                │
│          │     TLS (8883)    │      TLS (8883)   │                │
│          └──────────┬────────┴───────────────────┘                │
│                     │                                             │
│           ┌─────────┴──────────┐                                  │
│           │  ejabberd/Prosody  │                                  │
│           │  (MQTT + XMPP)     │                                  │
│           └────────────────────┘                                  │
└───────────────────────────────────────────────────────────────────┘
```

**TLS is mandatory.** All clients use port 8883 with certificate validation.

### 9.3 Home Assistant Integration

**HA connects to the same MQTT broker as DinoX.** Configuration is done
in HA under "Settings → Devices & Services → MQTT":

- **Broker:** IP/hostname of ejabberd/Prosody/Mosquitto
- **Port:** 1883 (local) or 8883 (TLS)
- **Username/Password:** XMPP credentials (ejabberd) or empty (Prosody)

**HA MQTT Discovery:** HA automatically registers devices via topics like:
```
homeassistant/sensor/living_room_temp/config   → Configuration (JSON)
homeassistant/sensor/living_room_temp/state    → Readings
```

**DinoX can subscribe to these topics** and display sensor data in the dashboard:
```
# Example: Receive all HA sensors
mqtt_topics: ["homeassistant/sensor/#", "homeassistant/binary_sensor/#"]
```

**Control actuators** (e.g. light on/off):
```
# Publish to HA command topic
topic: homeassistant/switch/irrigation/set
payload: ON
```

### 9.4 Node-RED Integration

Node-RED connects via the `mqtt-broker` node to the same broker:

```
┌──────────┐    ┌─────────────────┐    ┌──────────────┐
│ Sensor   │───→│ Node-RED Flow   │───→│ MQTT Broker  │───→ DinoX
│ (HTTP/   │    │ (Processing,    │    │              │
│  GPIO)   │    │  Formatting)    │    │              │
└──────────┘    └─────────────────┘    └──────────────┘
```

**Example Node-RED Flow** (JSON import):
```json
[
  {"id":"mqtt-out","type":"mqtt out","topic":"home/sensors/temperature",
   "broker":"mqtt-broker-node","qos":"1","retain":"true"},
  {"id":"mqtt-broker-node","type":"mqtt-broker",
   "broker":"mqtt.example.org","port":"8883","tls":"true",
   "credentials":{"user":"user@example.org","password":"secret"}}
]
```

Node-RED can also **consume DinoX events**:
```
# Node-RED subscribes to DinoX bot topics
topic: dinox/bots/status/#
```

### 9.5 Recommended Topic Hierarchy

To avoid collisions, the following structure is recommended:

```
home/                          ← Smart Home (HA / Node-RED)
  sensors/
    temperature/living_room    → {"value": 22.1, "unit": "°C"}
    humidity/bedroom           → {"value": 45, "unit": "%"}
    door/front_door            → {"state": "closed"}
  actuators/
    light/living_room/set      → ON / OFF
    thermostat/living_room/set → {"target": 21.0}

homeassistant/                 ← HA Discovery (automatic)
  sensor/…/config
  binary_sensor/…/config

dinox/                         ← DinoX-specific topics
  bots/status/#                → Bot status events
  notifications/#              → Push notifications
  bridge/#                     → XMPP↔MQTT bridge messages

nodered/                       ← Node-RED flows
  alerts/#                     → Processed alerts
  automations/#                → Automation status
```

### 9.6 Network Security

| Scenario | Recommendation |
|----------|---------------|
| LAN-only | TLS optional, firewall on port 1883 (LAN only) |
| Internet | **TLS mandatory** (port 8883), username+password |
| Mixed (bridge) | Bridge with TLS, local broker without TLS acceptable |
| Prosody (no auth) | MQTT port reachable **only** via LAN/VPN |

**DinoX settings UI should warn** when:
- TLS disabled for non-local IP
- Prosody (no auth) with internet access

---

## 10. References

- [ejabberd MQTT Guide](https://docs.ejabberd.im/admin/guide/mqtt/)
- [Prosody mod_pubsub_mqtt](https://modules.prosody.im/mod_pubsub_mqtt)
- [Prosody mod_pubsub_mqtt TLS commit (Jan 2024)](https://hg.prosody.im/prosody-modules/rev/801f64e6d4e9)
- [Prosody PubSub Docs](https://prosody.im/doc/pubsub)
- [Home Assistant MQTT Integration](https://www.home-assistant.io/integrations/mqtt/)
- [Home Assistant MQTT Discovery](https://www.home-assistant.io/integrations/mqtt/#mqtt-discovery)
- [Node-RED MQTT Nodes](https://nodered.org/docs/user-guide/messages)
- [Mosquitto Bridge Configuration](https://mosquitto.org/man/mosquitto-conf-5.html)
- [XEP-0060: PubSub](https://xmpp.org/extensions/xep-0060.html)
- [XEP-0335: JSON Containers](https://xmpp.org/extensions/xep-0335.html)
- [libmosquitto API](https://mosquitto.org/api/files/mosquitto-h.html)
- [MQTT 5.0 Spec](https://docs.oasis-open.org/mqtt/mqtt/v5.0/mqtt-v5.0.html)
- [Eclipse Paho](https://www.eclipse.org/paho/) (alternative client lib)
