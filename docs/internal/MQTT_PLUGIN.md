# DinoX MQTT Plugin -- Developer Documentation

**Status:** Implemented (Phase 1-5 complete, HA Discovery + Command Topics)
**Created:** 2026-02-26
**Last updated:** 2026-03-02
**Version:** v1.5.0

See also: [MQTT User Guide](MQTT_UI_GUIDE.md)

---

## 1. Motivation

The DinoX MQTT plugin uses **libmosquitto** as a standard MQTT client and
connects to **any MQTT broker** -- no XMPP server integration required.
Users can subscribe and publish to any Mosquitto, HiveMQ, EMQX, CloudMQTT,
AWS IoT Core, or other MQTT 3.1.1/5.0 broker by simply entering the broker
address in the settings.

As a **bonus**, both ejabberd and Prosody offer built-in MQTT connectivity,
allowing DinoX to optionally reuse XMPP credentials or bridge MQTT topics
to XMPP PubSub:

### ejabberd -- Native MQTT Broker (`mod_mqtt`)
- **Shared Authentication** -- XMPP accounts (`user@domain`) work as MQTT logins
- **Shared ACL / Security Policy** -- defined once, applies to both protocols
- **Shared DB Backends** -- no second server needed
- **MQTT 5.0 + 3.1.1** -- full protocol support
- Source: https://docs.ejabberd.im/admin/guide/mqtt/#benefits

### Prosody -- MQTT-PubSub Bridge (`mod_pubsub_mqtt`)
- **MQTT Topics = XMPP PubSub Nodes** -- MQTT publishes land as XEP-0060 items
- **Bidirectional** -- XMPP clients can subscribe to PubSub nodes, MQTT clients to the same topic
- **Community Module** -- Beta, by Matthew Wild (Prosody lead)
- **MQTT 3.1.1** -- no auth, QoS 0 only
- **Topic Format:** `<HOST>/<TYPE>/<NODE>` (e.g. `pubsub.example.org/json/sensors`)
- **Payload Types:** json (XEP-0335), utf8, atom_title
- Source: https://modules.prosody.im/mod_pubsub_mqtt

### Server Comparison

| Feature | ejabberd (`mod_mqtt`) | Prosody (`mod_pubsub_mqtt`) |
|---------|-----------------------|-----------------------------|
| MQTT Version | 5.0 + 3.1.1 | 3.1.1 |
| Auth | XMPP Credentials | None |
| QoS | 0, 1, 2 | 0 only |
| Architecture | Native Broker (own topic space) | Bridge to XMPP PubSub (XEP-0060) |
| XMPP PubSub Bridge | No -- MQTT topics and XEP-0060 are separate | Yes -- MQTT = PubSub node |
| Topic Format | Freely configurable | `<HOST>/<TYPE>/<NODE>` |
| Payloads | Arbitrary | json, utf8, atom_title |
| Status | Production | Beta (community module) |
| TLS | Yes (Port 8883) | Yes (Port 8883, since Jan 2024) |
| Default Port | 1883 | 1883 |

DinoX works with **any MQTT broker**. The ejabberd/Prosody integration is
optional -- the plugin is a general-purpose MQTT client first.

**Prosody's Unique Advantage:** With Prosody, MQTT publishes are automatically
readable as standard XMPP PubSub nodes (XEP-0060) -- even clients **without**
MQTT support can receive the data. With ejabberd, MQTT topics and XMPP PubSub
are separate worlds (they only share auth/ACL/DB infrastructure).

---

## 2. Use Cases

### 2.1 IoT / Smart Home (Priority: high)
- Subscribe to sensor data (temperature, humidity, door status) via MQTT topics
- Values appear as chat messages from a virtual MQTT Bot
- Historical values as sparkline charts
- Alerts on threshold exceedance with configurable priorities

### 2.2 Home Assistant / Node-RED Integration (Priority: high)
- Connect to the same broker as HA and Node-RED
- HA Device Discovery publishes DinoX as a device with 8 entities
- Command topics allow HA to control DinoX (pause alerts, reconnect, refresh)
- Freetext chat messages forwarded to Node-RED via configurable topic
- **Note:** HA Discovery requires a real MQTT broker (Mosquitto, EMQX, etc.).
  It does not work with ejabberd or Prosody XMPP-MQTT (no retain/LWT support).
  Only Standalone and Per-Account Custom Broker modes support HA Discovery.

### 2.3 MQTT-to-XMPP Bridge (Priority: medium)
- Forward MQTT messages to real XMPP contacts
- Configurable per-topic with wildcard matching and rate limiting
- Three format modes: full, payload-only, short

### 2.4 Bot Event Stream (Priority: medium)
- DinoX bots publish status events via MQTT
- Dashboard for bot monitoring (online/offline, message counters)

---

## 3. Architecture

### 3.0 Client Modes

The MQTT plugin supports **three independent client modes** that can all
run simultaneously without interference:

```
┌─────────────────────────────────────────────────────────────────┐
│  DinoX MQTT Plugin                                              │
│                                                                 │
│  ┌─────────────────────────────────────┐                        │
│  │  (A) Standalone MQTT Client         │  Preferences → MQTT    │
│  │  • Any external broker              │  (Standalone)          │
│  │  • Manual host/port/TLS/auth        │                        │
│  │  • No XMPP dependency               │                        │
│  │  • Global (not account-bound)       │                        │
│  │  • No server detection              │                        │
│  └─────────────────────────────────────┘                        │
│                                                                 │
│  ┌─────────────────────────────────────┐                        │
│  │  (B) Per-Account Client (XMPP)      │  Account Settings      │
│  │  • Broker = XMPP server domain      │  → MQTT Bot (Account)  │
│  │  • XMPP credentials (ejabberd)      │                        │
│  │  • Auto-detect server type          │  TESTING / BETA        │
│  │  • One client per XMPP account      │                        │
│  └─────────────────────────────────────┘                        │
│                                                                 │
│  ┌─────────────────────────────────────┐                        │
│  │  (C) Per-Account Client (Custom)    │  Account Settings      │
│  │  • Any broker (manual host/port)    │  → MQTT Bot (Account)  │
│  │  • Own username/password            │                        │
│  │  • XMPP auth OFF                    │                        │
│  │  • One client per XMPP account      │                        │
│  └─────────────────────────────────────┘                        │
│                                                                 │
│  Each client has its own:                                       │
│  • MqttClient instance (libmosquitto)                           │
│  • Bot conversation (virtual contact)                           │
│  • Topic subscriptions, alerts, bridges, presets                │
│  • HA Discovery device (unique ID per client)                   │
│  • Database entries (keyed by connection label)                 │
└─────────────────────────────────────────────────────────────────┘
```

**Mode (A) — Standalone:** Configured under Preferences → MQTT (Standalone).
Pure MQTT client for any broker (Mosquitto, HiveMQ, Home Assistant, AWS IoT, etc.).
No XMPP credentials, no server detection, no ejabberd/Prosody logic.
Connection label: `"standalone"`. HA Discovery device ID: `dinox_standalone`.

**Mode (B) — Per-Account XMPP:** Each XMPP account can bind to its XMPP
server's built-in MQTT (ejabberd `mod_mqtt` or Prosody `mod_pubsub_mqtt`).
Hostname is auto-filled from the account domain, XMPP credentials can be
reused for ejabberd. Server type is detected via XEP-0030.
**Note:** XMPP-bound MQTT (both ejabberd and Prosody) is currently in
testing and has not been fully validated in production. Use with caution.

**Mode (C) — Per-Account Custom:** Same dialog as (B), but the user enters
a custom broker hostname, disables "Use XMPP Credentials", and provides own
MQTT username/password. Functionally identical to standalone, but bound to
an account context (appears under that account's settings).

### 3.0.1 HA Discovery Compatibility

HA Discovery requires a **real MQTT broker** (Mosquitto, EMQX, HiveMQ, etc.)
that supports retained messages, Last Will and Testament (LWT), and free topic
hierarchies. XMPP server MQTT does **not** meet these requirements:

| Feature | Mosquitto / EMQX | ejabberd (mod_mqtt) | Prosody (mod_pubsub_mqtt) |
|---------|------------------|---------------------|--------------------------|
| Retained messages | Yes | No (not persistent) | No |
| LWT (Last Will) | Yes | Limited | No |
| Free topic hierarchy | Yes | Yes | No (HOST/pubsub/NODE only) |
| HA Discovery compatible | **Yes** | **No** | **No** |

**Consequence:** HA Discovery is only available in:
- **(A) Standalone** -- always connects to a real broker
- **(C) Per-Account Custom Broker** -- user provides a real broker hostname

It is **not available** in **(B) Per-Account XMPP** (ejabberd/Prosody).
The UI hides the Discovery section when XMPP mode is selected, and the
runtime skips Discovery even if the config flag is set.

### 3.0.2 HA Discovery Uniqueness

Each client publishes its own HA device with a unique identifier:

| Client | Device ID | Device Name | Availability Topic |
|--------|-----------|-------------|--------------------|
| Standalone | `dinox_standalone` | DinoX MQTT (Standalone) | `dinox/standalone/availability` |
| Account `user@srv.de` | `dinox_user_srv_de` | DinoX MQTT (user@srv.de) | `dinox/user_srv_de/availability` |
| Account `bot@other.org` | `dinox_bot_other_org` | DinoX MQTT (bot@other.org) | `dinox/bot_other_org/availability` |

Standalone and Custom Broker clients can have HA Discovery enabled
simultaneously without conflicts. XMPP mode clients cannot use Discovery.

### 3.0.3 Client Isolation

| Resource | Isolated per client |
|----------|---------------------|
| libmosquitto connection | Yes -- Separate socket, separate MQTT session |
| Topic subscriptions | Yes -- Each client subscribes to its own topics |
| Alert rules | Yes -- Stored per connection label in DB |
| Bridge rules | Yes -- Stored per connection label in DB |
| Publish presets | Yes -- Stored per connection label in DB |
| Freetext config | Yes -- Per client |
| HA Discovery device | Yes -- Unique device ID, unique topics |
| Bot conversation | Yes -- Separate virtual contact per client |
| Message history | Yes -- Keyed by connection label in DB |
| Connection state | Yes -- Independent connect/disconnect/reconnect |

### 3.1 Network Topology

```
+------------------------------------------------+
|                    DinoX                       |
|                                                |
|  +----------+   +----------+   +------------+  |
|  | XMPP     |   | MQTT     |   | MQTT       |  |
|  | Module   |   | Plugin   |   | UI         |  |
|  |(existing)|   |          |   |            |  |
|  +----+-----+   +----+-----+   +-----+------+  |
|       |              |              |          |
|       |    +---------+----------+   |          |
|       |    | MqttClient         |   |          |
|       |    | (libmosquitto)     |   |          |
|       |    +---------+----------+   |          |
|       |              |              |          |
+-------+--------------+--------------+----------+
        |              |              |
   XMPP |         MQTT |              | Signals
  (5222)|        (1883)|              |
        |              |              |
        v              v              v
  +------------------+  +-------------------+
  | ejabberd/Prosody |  | Any MQTT Broker   |
  | (XMPP + MQTT)    |  | (Mosquitto, etc.) |
  +------------------+  +-------------------+
```

### 3.2 Components
|-----------|------|-------|-------------|
| `Plugin` | `plugin.vala` | 1397 | Main plugin class: lifecycle, config, routing, discovery integration |
| `MqttClient` | `mqtt_client.vala` | 656 | libmosquitto wrapper: MQTT 5.0, LWT, GLib main loop, auto-reconnect |
| `MqttConnectionConfig` | `connection_config.vala` | 248 | Per-connection config model (26 properties incl. discovery) |
| `MqttDatabase` | `database.vala` | 709 | Encrypted SQLite database (9 tables), auto-purge, retention |
| `ServerDetector` | `server_detector.vala` | 175 | XEP-0030 disco for ejabberd/Prosody MQTT detection |
| `MqttBotConversation` | `bot_conversation.vala` | 475 | Virtual bot contact per connection, message injection |
| `MqttCommandHandler` | `command_handler.vala` | 1475 | 26 chat commands (`/mqtt help` for full list) |
| `MqttAlertManager` | `alert_manager.vala` | 948 | Threshold alerts, 4 priorities, 7 operators, sparklines |
| `MqttBridgeManager` | `bridge_manager.vala` | 374 | MQTT-to-XMPP bridge with wildcard matching, rate limiting |
| `MqttDiscoveryManager` | `discovery_manager.vala` | 633 | HA Device Discovery (8 entities), command topics, LWT |
| `MqttBotManagerDialog` | `mqtt_bot_manager_dialog.vala` | 996 | Adw.Dialog: 5-page MQTT management dialog (per-account + standalone) |
| `MqttTopicManagerDialog` | `topic_manager_dialog.vala` | 413 | Adw.Dialog: visual topic/bridge/alert management |
| `MqttStandaloneSettingsPage` | `settings_page.vala` | 513 | Adw.PreferencesPage: standalone broker config + discovery |
| `MqttUtils` | `mqtt_utils.vala` | 256 | Pure utility functions (topic matching, sparklines, formatting) |
| Vala VAPI | `vapi/mosquitto.vapi` | 247 | Vala bindings for libmosquitto C API (MQTT 5.0 + 3.1.1) |

**Total:** 9,547 lines across 15 source files.

### 3.3 Dependencies

| Library | Package | Purpose |
|---------|---------|---------|
| libmosquitto | `libmosquitto-dev` | MQTT 5.0/3.1.1 client library (C, pkg-config) |
| GLib / GIO | (existing) | Main loop integration, GSource for mosquitto fd |
| GTK4 + libadwaita | (existing) | UI dialogs and settings pages |
| Qlite | (existing) | SQLite ORM for mqtt.db |
| json-glib | (existing) | JSON serialization for configs and payloads |

### 3.4 Main Loop Integration

libmosquitto normally runs with its own thread (`mosquitto_loop_start()`).
DinoX instead uses `mosquitto_loop_read/write/misc()` with GLib.IOChannel
on the mosquitto socket fd. This way everything runs in the GTK main loop
without threading issues. TCP connect runs in a GLib.Thread to avoid
blocking the GUI during DNS resolution.

### 3.5 Signals

The plugin exposes two signals for external consumers:

```vala
public signal void message_received(string source, string topic, string payload);
public signal void connection_changed(string source, bool connected);
```

---

## 4. Configuration Model

### 4.1 MqttConnectionConfig

Each MQTT connection (per-account or standalone) has its own `MqttConnectionConfig`
with 26 properties:

| Category | Properties |
|----------|------------|
| Connection | `enabled`, `broker_host`, `broker_port`, `tls` |
| Auth | `use_xmpp_auth`, `username`, `password` |
| Topics | `topics`, `topic_qos_json`, `topic_priorities_json` |
| Bot | `bot_enabled`, `bot_name` |
| Server | `server_type` |
| Freetext | `freetext_enabled`, `freetext_publish_topic`, `freetext_response_topic`, `freetext_qos`, `freetext_retain` |
| Discovery | `discovery_enabled` (default: false), `discovery_prefix` (default: "homeassistant") |
| JSON blobs | `alerts_json`, `bridges_json`, `publish_presets_json` |

### 4.2 Storage

**Per-account settings** are stored in the `account_settings` table (key-value pairs
per account ID). Keys are defined in the `AccountKey` namespace (24 constants).

**Standalone settings** are stored in the global `settings` table. Keys are defined
in the `StandaloneKey` namespace (22 constants).

Legacy global settings are automatically migrated on first start (`MigrationKey`).

### 4.3 Environment Variable Overrides

For testing, the following environment variables override settings:

- `DINOX_MQTT_HOST`, `DINOX_MQTT_PORT`, `DINOX_MQTT_USER`, `DINOX_MQTT_PASS`
- `DINOX_MQTT_TOPICS`, `DINOX_MQTT_TLS`

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
(added Jan 2024) but still has **no authentication** and only **QoS 0**.
TLS encrypts the connection but does not restrict access. For production
environments, the MQTT port should be protected by firewall rules or VPN.

---

## 6. UX Concept: Bot-Conversation Paradigm

### 6.1 Core Idea

MQTT data is **not** displayed in a separate dashboard, sidebar, or tab.
Instead, a **virtual bot contact** (e.g. `MQTT Bot`) appears in the regular
conversation list. All MQTT messages arrive as **chat messages from this bot**,
and the user can send **commands** to the bot via the chat input.

**Why Bot-Conversation instead of Dashboard?**

- DinoX is a **chat client** -- a conversation-based UI is the natural paradigm
- No new navigation concepts needed (sidebar entries, tab bars, floating panels)
- Notifications work like any other chat (badge, sound, unread counter)
- Mobile-friendly -- same layout on desktop and mobile
- Users already understand how to interact with bots in chat

### 6.2 Bot JID Schema

Each connection gets a unique synthetic JID:

| Connection | Bot JID | Display Name |
|-----------|----------|--------------|
| Per-account (user@example.org) | `mqtt-bot@mqtt.local/user@example.org` | "MQTT Bot (user@example.org)" |
| Standalone | `mqtt-bot@mqtt.local/standalone` | "MQTT Bot" (or custom name) |

The resource part of the JID differentiates bots. Each bot has a unique
conversation in the database.

### 6.3 Bot Visibility Rules

| State | Bot visible? | Behavior |
|-------|--------------|----------|
| MQTT disabled in settings | No | Bot does not appear in contact list |
| MQTT enabled, not connected | Yes (greyed out) | Shows "Connecting..." or "Offline" status |
| MQTT enabled, connected, no data yet | Yes | Shows "Waiting for data..." |
| Data arrives on subscribed topic | Yes + notification | Bot appears with badge/sound |
| MQTT disabled after use | No | Bot disappears, history preserved in DB |

### 6.4 Priority Levels

| Priority | Trigger | Notification |
|----------|---------|--------------|
| Normal | Regular sensor data | Unread badge only |
| Alert | Threshold exceeded (`/mqtt alert`) | Badge + desktop notification |
| Critical | User-defined critical topics | Badge + notification + sound |
| Silent | Status updates, heartbeats | No notification, visible in history |

---

## 7. Chat Commands

The `MqttCommandHandler` provides 26 commands. All commands typed in a bot
conversation scope to that connection only.

| Command | Aliases | Description |
|---------|---------|-------------|
| `/mqtt status` | | Show connection status, broker, subscriptions, alerts |
| `/mqtt subscribe <topic>` | `sub` | Subscribe to a new topic (+ and # wildcards) |
| `/mqtt unsubscribe <topic>` | `unsub` | Unsubscribe from a topic |
| `/mqtt publish <topic> <payload>` | `pub` | Publish a message to a topic |
| `/mqtt topics` | `list` | List all active subscriptions with last values |
| `/mqtt alert <topic> [field] <op> <value> [priority]` | | Add a threshold alert rule |
| `/mqtt alerts` | | List all alert rules |
| `/mqtt rmalert <index>` | `delalert` | Remove an alert rule by index |
| `/mqtt priority <topic> <level>` | `prio` | Set per-topic notification priority |
| `/mqtt history <topic>` | `hist` | Show last values for a topic (from DB) |
| `/mqtt pause` | | Pause all alert notifications |
| `/mqtt resume` | | Resume alert notifications |
| `/mqtt qos <topic> <0/1/2>` | | Set per-topic QoS level |
| `/mqtt chart <topic>` | `sparkline` | Show sparkline chart for numeric topic |
| `/mqtt bridge <topic> <jid> [format]` | | Add MQTT-to-XMPP bridge rule |
| `/mqtt bridges` | | List all bridge rules |
| `/mqtt rmbridge <index>` | `delbridge` | Remove a bridge rule by index |
| `/mqtt manager` | `manage` | Open visual topic/bridge/alert manager dialog |
| `/mqtt dbstats` | `db` | Show database row counts and retention periods |
| `/mqtt purge` | | Manually trigger database cleanup |
| `/mqtt preset add <name> <topic> <payload>` | | Add a publish preset |
| `/mqtt preset remove <index>` | | Remove a preset by index |
| `/mqtt preset <name>` | | Execute a named preset (publish) |
| `/mqtt presets` | | List all publish presets |
| `/mqtt config` | | Show current connection configuration |
| `/mqtt discovery <on/off/refresh/prefix>` | | Manage HA Discovery |
| `/mqtt reconnect` | | Force disconnect and reconnect |
| `/mqtt help` | `?` | Show command reference |

---

## 8. Database (`mqtt.db`)

### 8.1 Overview

MQTT runtime data is stored in a **separate encrypted SQLite database** (`mqtt.db`),
following the DinoX plugin pattern (like `omemo.db`, `pgp.db`). Located at
`~/.local/share/dinox/mqtt.db` (Linux) or `%APPDATA%\dinox\mqtt.db` (Windows).

The database uses `app.db_key` for SQLCipher encryption, WAL journal mode,
and `PRAGMA synchronous = NORMAL`.

### 8.2 Tables (9)

| # | Table | Purpose | Retention |
|---|-------|---------|-----------|
| 1 | `mqtt_messages` | Received messages (persistent history) | 30 days |
| 2 | `mqtt_freetext` | Freetext publish/response log | 30 days |
| 3 | `mqtt_connection_log` | Connect/disconnect/error events | 90 days |
| 4 | `mqtt_topic_stats` | Per-topic aggregate statistics (UPSERT) | Unlimited (1 row/topic) |
| 5 | `mqtt_alert_rules` | Alert rules (UUID PK) | Unlimited (user-managed) |
| 6 | `mqtt_bridge_rules` | Bridge rules MQTT-to-XMPP (UUID PK) | Unlimited (user-managed) |
| 7 | `mqtt_publish_presets` | Predefined publish actions (UUID PK) | Unlimited (user-managed) |
| 8 | `mqtt_publish_history` | Outgoing publish audit log | 30 days |
| 9 | `mqtt_retained_cache` | Local retained message cache (1 row/topic) | Unlimited |

### 8.3 Auto-Purge

- Runs at startup and every 6 hours
- Deletes messages/freetext/publish_history older than 30 days
- Deletes connection_log older than 90 days
- VACUUM after >1000 rows deleted
- Manual trigger: `/mqtt purge`

### 8.4 Key Methods

| Method | Description |
|--------|-------------|
| `record_message()` | Store message + update topic_stats + update retained_cache |
| `record_freetext()` | Log freetext publish/response exchange |
| `record_connection_event()` | Log connect/disconnect/error event |
| `record_publish()` | Log outgoing publish with source (manual/preset/freetext) |
| `get_topic_history()` | Get last N messages for a topic |
| `get_topic_history_all()` | Get history across all connections |
| `get_all_topic_stats()` | Get aggregate stats for a connection |
| `get_stats_summary()` | Get row counts for `/mqtt dbstats` |
| `purge_expired()` | Run retention cleanup |

---

## 9. Home Assistant Discovery

### 9.1 Overview

When enabled, DinoX registers itself as a device in Home Assistant using the
HA MQTT Device Discovery protocol. This is opt-in (disabled by default) and
does not affect any other MQTT functionality.

### 9.2 Device Discovery Format

DinoX publishes a single retained JSON message to:

```
<prefix>/device/<node_id>/config
```

Where `<prefix>` defaults to `homeassistant` and `<node_id>` is derived from
the sanitized connection key (e.g. `dinox_user_at_example_org`).

The config message contains `dev` (device info), `o` (origin), `avty`
(availability), and `cmps` (components) -- following the HA device discovery
format.

### 9.3 Entities (8)

| Entity | Platform | Description | State Topic |
|--------|----------|-------------|-------------|
| `connectivity` | binary_sensor | Online/Offline connectivity | `dinox/<node>/connectivity/state` |
| `subscriptions` | sensor | Active topic subscription count | `dinox/<node>/subscriptions/state` |
| `bridges` | sensor | Active bridge rule count | `dinox/<node>/bridges/state` |
| `alerts` | sensor | Active alert rule count | `dinox/<node>/alerts/state` |
| `status` | sensor | Status summary text | `dinox/<node>/status/state` |
| `alerts_pause` | switch | Pause/resume alerts (ON/OFF) | `dinox/<node>/alerts_pause/state` |
| `reconnect` | button | Force reconnect (PRESS) | -- |
| `refresh` | button | Refresh all states (PRESS) | -- |

### 9.4 Availability (LWT)

The availability topic `dinox/<node>/availability` uses Last Will and Testament:

- **LWT** (set before connect): payload "offline" (retained)
- **Birth** (published after connect): payload "online" (retained)
- **Shutdown**: payload "offline" published explicitly

### 9.5 Command Topics

HA can control DinoX through command topics:

| Command Topic | Accepted Values | Action |
|---------------|-----------------|--------|
| `dinox/<node>/alerts_pause/set` | ON / OFF | Pause or resume alert evaluation |
| `dinox/<node>/reconnect/set` | PRESS | Disconnect and reconnect to broker |
| `dinox/<node>/refresh/set` | PRESS | Re-publish all entity states |

### 9.6 HA Status Subscription

DinoX subscribes to `<prefix>/status` (the HA birth message topic). When HA
sends "online" after a restart, DinoX re-publishes the full discovery config
and all entity states, ensuring HA always has current data.

### 9.7 Topic Structure Summary

```
<prefix>/device/<node>/config       -- Device discovery config (retained)
<prefix>/status                     -- HA birth message (subscribed)
dinox/<node>/availability           -- Online/offline (retained, LWT)
dinox/<node>/<entity>/state         -- Entity state values (retained)
dinox/<node>/<entity>/set           -- Command topics (switch + buttons)
```

---

## 10. Integration: Home Assistant and Node-RED

### 10.1 Network Scenarios

#### Scenario A: All Local (LAN)

All devices on the same network. DinoX connects to `mqtt://192.168.x.x:1883`.

#### Scenario B: XMPP Server on Internet, Smart Home Local

Most common case. Two options:

1. **Direct:** DinoX connects to local Mosquitto (port forwarding or VPN)
2. **Bridge** (recommended): Local Mosquitto forwards topics to internet broker

```
# /etc/mosquitto/conf.d/bridge.conf
connection xmpp-bridge
address mqtt.example.org:8883
bridge_capath /etc/ssl/certs
remote_username user@example.org
remote_password secret
topic home/sensors/# out 1
topic home/actuators/# both 1
topic dinox/# in 1
```

#### Scenario C: Everything on Internet

TLS mandatory (port 8883) for all clients.

### 10.2 Recommended Topic Hierarchy

```
home/                          -- Smart Home (HA / Node-RED)
  sensors/
    temperature/living_room    {"value": 22.1, "unit": "C"}
    humidity/bedroom           {"value": 45, "unit": "%"}
  actuators/
    light/living_room/set      ON / OFF
homeassistant/                 -- HA Discovery (automatic)
  device/.../config
dinox/                         -- DinoX device topics
  <node>/availability          online / offline
  <node>/<entity>/state        Entity state values
  <node>/<entity>/set          Command topics
nodered/                       -- Node-RED flows
  alerts/#
  automations/#
```

### 10.3 Node-RED Freetext Integration

DinoX can forward freetext chat messages to a configurable MQTT topic,
allowing Node-RED to process natural language commands:

```
User types: "kitchen light on"
  -> Published to: home/commands
  -> Node-RED processes and responds on: home/commands/response
  -> Response appears in bot chat: "OK: Kitchen light turned on"
```

### 10.4 Network Security

| Scenario | Recommendation |
|----------|----------------|
| LAN-only | TLS optional, firewall on port 1883 |
| Internet | TLS mandatory (port 8883), username+password |
| Mixed (bridge) | Bridge with TLS, local without TLS acceptable |
| Prosody (no auth) | MQTT port reachable only via LAN/VPN |

DinoX shows a TLS warning when connecting to a non-local broker without TLS.

---

## 11. Implementation History

All phases are complete.

### Phase 1: Foundation (v1.2.0)
- Plugin skeleton, Vala VAPI for libmosquitto
- MqttClient: MQTT 5.0, GLib main loop, auto-reconnect
- Server detection (ejabberd/Prosody via XEP-0030)
- Settings UI, Windows/Flatpak builds

### Phase 2: Bot-Conversation + Per-Account Architecture (v1.2.1)
- Virtual bot contact per connection (unique JID per account/standalone)
- MqttConnectionConfig model (replaces global settings)
- MqttBotManagerDialog (5-page Adw.NavigationView dialog)
- Per-account config load/save via account_settings table
- Chat commands: subscribe, publish, status, topics, presets, config, reconnect
- Freetext publish (chat messages to configurable topic)

### Phase 3: Alerts and Notifications (v1.3.0)
- Threshold alerts with 7 operators and 4 priority levels
- Alert cooldown, JSON field extraction, wildcard matching
- Sparkline charts for numeric topic history
- Per-topic QoS and priority settings

### Phase 4: Advanced Features (v1.4.0)
- MQTT-to-XMPP bridge with rate limiting and 3 format modes
- MQTT Database: 9 tables, encrypted SQLite, auto-purge
- Legacy JSON-to-DB migration for alert/bridge rules
- Topic manager dialog (visual subscribe/unsubscribe/bridge/alert management)

### Phase 5: Polish (v1.5.0)
- TLS warning for non-local brokers
- Prosody security banners
- Per-connection context in TopicManagerDialog
- 26 MQTT-specific unit tests (8 test suites, all passing)

### Discovery and Command Topics (v1.5.0)
- HA Device Discovery protocol (single config message, 8 entities)
- 3 command topics: alerts_pause (switch), reconnect (button), refresh (button)
- LWT for availability, HA birth message subscription
- Discovery UI in both settings page and bot manager dialog
- `/mqtt discovery` command (on/off/refresh/prefix)

---

## 12. Resolved Risks

| Risk | Mitigation |
|------|------------|
| libmosquitto not available | Optional dependency, plugin only loads when lib is present |
| Windows cross-compile | MSYS2 `mingw-w64-x86_64-mosquitto` package, auto-detected |
| Flatpak build | Mosquitto module in manifest (CMake, client lib only) |
| Threading vs main loop | IOChannel on mosquitto fd, TCP connect in GLib.Thread |
| MQTT 5.0 vs 3.1.1 | libmosquitto supports both; ejabberd 5.0, Prosody 3.1.1 |
| Prosody no auth | Firewall/VPN + DinoX warning in settings |
| Prosody topic format | Auto-detected via server type, format adapted |
| DB bloat | Auto-purge every 6h, VACUUM after large deletes |

---

## 13. Internationalization

All user-facing strings use `_()` for gettext translation (GETTEXT_PACKAGE = "dino").
Over 350 translatable strings across 11 source files. Protocol constants
(ON/OFF, PRESS, topic paths, JSON keys, MDI icon names) are intentionally
not translated.

---

## 14. Build and Test

```bash
# Build
meson setup build
ninja -C build

# Run MQTT tests (8 test suites, 26 tests)
ninja -C build test
# or specifically:
./build/plugins/mqtt/mqtt-test
```

Test files: `tests/mqtt_tests.vala`, `tests/mqtt_config_tests.vala`,
`tests/mqtt_localhost_tests.vala`.

---

## 15. References

- [ejabberd MQTT Guide](https://docs.ejabberd.im/admin/guide/mqtt/)
- [Prosody mod_pubsub_mqtt](https://modules.prosody.im/mod_pubsub_mqtt)
- [Prosody PubSub Docs](https://prosody.im/doc/pubsub)
- [Home Assistant MQTT Integration](https://www.home-assistant.io/integrations/mqtt/)
- [Home Assistant MQTT Discovery](https://www.home-assistant.io/integrations/mqtt/#mqtt-discovery)
- [Node-RED MQTT Nodes](https://nodered.org/docs/user-guide/messages)
- [Mosquitto Bridge Configuration](https://mosquitto.org/man/mosquitto-conf-5.html)
- [XEP-0060: PubSub](https://xmpp.org/extensions/xep-0060.html)
- [XEP-0335: JSON Containers](https://xmpp.org/extensions/xep-0335.html)
- [libmosquitto API](https://mosquitto.org/api/files/mosquitto-h.html)
- [MQTT 5.0 Spec](https://docs.oasis-open.org/mqtt/mqtt/v5.0/mqtt-v5.0.html)
