# DinoX MQTT Plugin -- User Guide

**Version:** 1.5.0
**Last updated:** 2026-03-02

---

## 1. Overview

The DinoX MQTT plugin turns your XMPP chat client into an MQTT-capable
dashboard. It connects to any MQTT broker (Mosquitto, ejabberd, Prosody,
HiveMQ, AWS IoT, etc.) and displays incoming messages as chat messages
from a virtual **MQTT Bot** contact.

**Key features:**

- Subscribe to MQTT topics and receive data as bot chat messages
- 26 chat commands for full control (`/mqtt help`)
- Threshold alerts with 4 priority levels and desktop notifications
- MQTT-to-XMPP bridge (forward topics to real contacts)
- Publish presets (quick-action buttons for common publishes)
- Freetext publish (type natural language, forwarded to Node-RED)
- Home Assistant device discovery (DinoX appears as HA device)
- Per-account MQTT (reuse XMPP auth on ejabberd — in testing) + standalone broker
- Encrypted local database with 30-day message history
- Works independently -- no Home Assistant or XMPP server MQTT required

---

## 2. Getting Started

### 2.1 Three Client Modes

DinoX supports three MQTT client modes that can run simultaneously:

| Mode | Location | Broker | Authentication | Status |
|------|----------|--------|----------------|--------|
| **(A) Standalone** | Preferences → MQTT (Standalone) | Any external broker (Mosquitto, HA add-on, HiveMQ, AWS IoT…) | Manual (username + password) | **Stable** |
| **(B) Per-Account (XMPP)** | Account Settings → MQTT Bot (Account) | XMPP server domain (ejabberd `mod_mqtt` / Prosody `mod_pubsub_mqtt`) | Automatic (XMPP credentials for ejabberd, none for Prosody) | **Testing** |
| **(C) Per-Account (Custom)** | Account Settings → MQTT Bot (Account) | Any broker (manual host/port) | Manual (own username + password, XMPP auth OFF) | **Stable** |

Each connection gets its own bot contact, topics, alerts, bridges, and presets.
All modes are fully isolated.

**HA Discovery compatibility:** HA Discovery requires a real MQTT broker
(Mosquitto, EMQX, etc.) with retained messages and LWT support. It is
available in modes **(A) Standalone** and **(C) Per-Account Custom Broker**.
It is **not available** in mode **(B) Per-Account XMPP** because ejabberd
and Prosody do not support retained messages, LWT, or free topic hierarchies.

**Key distinction:**

- **(A) Standalone** is global — not bound to any XMPP account. Configured
  in the general Preferences. No server detection, no XMPP credentials,
  no ejabberd/Prosody-specific logic.
- **(B) and (C)** are per-account — each XMPP account can have its own
  MQTT connection, either using the XMPP server's built-in MQTT or any
  custom broker.

> **XMPP MQTT Notice:** Per-account MQTT using ejabberd's `mod_mqtt` or
> Prosody's `mod_pubsub_mqtt` (mode B) is currently in **testing** and has
> not been fully validated in production environments. Both ejabberd and
> Prosody XMPP-MQTT integration need thorough testing. If you require a
> reliable MQTT connection today, use mode (A) Standalone or mode (C)
> Per-Account Custom with a dedicated MQTT broker.

### 2.2 Minimum Requirements

- A working XMPP account in DinoX (required even for standalone mode)
- An MQTT broker to connect to (any broker, any network)
- Optional: libmosquitto installed (the plugin only loads when the library is present)

---

## 3. Per-Account Setup

Per-account MQTT can work in two ways:

- **XMPP-bound (testing):** Uses the XMPP server's built-in MQTT
  (ejabberd or Prosody). XMPP credentials can be shared.
- **Custom broker:** Any external MQTT broker with own credentials.
  Disable "Use XMPP Credentials" and enter custom host/auth.

### 3.1 Opening the Configuration

1. Open DinoX preferences (menu -> Preferences)
2. Select your XMPP account
3. Scroll to the bottom -- find the **MQTT Bot** section
4. Click **Manage MQTT Bot** to open the configuration dialog

### 3.2 MqttBotManagerDialog -- Root Page

The dialog uses a 5-page navigation layout. The root page contains:

**Connection group:**

| Field | Description |
|-------|-------------|
| Enable MQTT | Master switch for this account's MQTT connection |
| Server Type | Detected server type (ejabberd / Prosody / Unknown) -- read-only |
| Status | Current connection status (Connected / Disconnected / Disabled) |

**Broker group:**

| Field | Description |
|-------|-------------|
| Hostname | Broker address. Leave empty to use the account domain (recommended for ejabberd/Prosody) |
| Port | Default: 1883 (unencrypted), 8883 (TLS) |
| TLS Encryption | Enable encrypted connection |

**Authentication group:**

| Field | Description |
|-------|-------------|
| Use XMPP Credentials | Reuse XMPP login for MQTT (recommended for ejabberd) |
| MQTT Username | Manual username (greyed out when XMPP auth is on) |
| MQTT Password | Manual password (greyed out when XMPP auth is on) |

**Navigation rows** to sub-pages:

| Row | Destination |
|-----|-------------|
| Topic Subscriptions | Manage subscribed topics |
| Publish and Freetext | Configure freetext publish and presets |
| Alert Rules | View and remove alert rules |
| Bridge Rules | View and remove bridge rules |

**Home Assistant Discovery group** (hidden in XMPP mode -- see note below):

| Field | Description |
|-------|-------------|
| Enable HA Discovery | Register DinoX as a device in Home Assistant |
| Discovery Prefix | Topic prefix (default: "homeassistant") |

**Note:** The Discovery group is only visible when "Custom Broker" is selected
as connection mode. ejabberd and Prosody XMPP-MQTT do not support retained
messages or LWT, which HA Discovery requires. When XMPP mode is selected,
the group is hidden and Discovery is automatically disabled.

**Save and Apply** button at the bottom saves all changes and immediately
connects, disconnects, or reconnects as needed.

### 3.3 Topics Page

**Subscribe to a new topic:**

1. Enter a topic name (e.g. `home/sensors/#`)
2. Select the QoS level from the dropdown (QoS 0, 1, or 2)
3. Click **Subscribe**
4. The topic appears in the "Active Subscriptions" list

**Remove a topic:**

- Click the remove button next to the topic in the list

MQTT wildcards are supported: `+` matches one level, `#` matches all remaining levels.

**Note:** Changes are saved when you click **Save and Apply** on the root page.

### 3.4 Publish and Freetext Page

**Freetext Publish (Node-RED integration):**

When enabled, messages typed in the bot chat (without the `/mqtt` prefix)
are automatically published to a configured topic. A system like Node-RED
can receive and process these messages.

| Field | Description |
|-------|-------------|
| Enable Freetext Publish | Activate freetext forwarding |
| Publish Topic | Target topic (e.g. `home/commands`) |
| Response Topic | Topic for responses (e.g. `home/commands/response`) |

The response topic is automatically subscribed. Responses appear as bot messages.

**Publish Presets:**

Predefined publish actions. Add presets via the UI form or the `/mqtt preset add`
chat command. Each preset has a name, topic, and payload. Execute a preset with
`/mqtt preset <name>` in the bot chat.

### 3.5 Alert Rules Page

Displays all configured alert rules with their topic pattern, operator,
threshold, and priority. Rules can be removed with the remove button.

**Adding rules** is done via the bot chat command:

```
/mqtt alert home/temperature temperature > 30
/mqtt alert home/door/front OPEN critical
```

### 3.6 Bridge Rules Page

Displays all MQTT-to-XMPP bridge rules. Each rule maps an MQTT topic pattern
to an XMPP contact (JID). Rules can be removed with the remove button.

**Adding rules** is done via the bot chat command:

```
/mqtt bridge home/alerts/# admin@example.org
/mqtt bridge home/sensors/temp bob@example.org payload_only
```

Bridge format options: `full` (topic + payload), `payload_only`, `short`.

---

## 4. Standalone Setup

The standalone MQTT client is configured in DinoX Preferences under the
**MQTT (Standalone)** page. This is a pure MQTT client with no XMPP
dependency — it connects to any external broker.

1. Open DinoX preferences (menu → Preferences)
2. Select the **MQTT (Standalone)** page
3. **Enable Standalone MQTT** → ON
4. Enter broker **Host** (IP or hostname, e.g. `192.168.1.100`)
5. Enter **Port** (default: 1883, or 8883 for TLS)
6. Enable **TLS** for non-local connections
7. Enter **Username** and **Password** if required by the broker
8. Add **Topic Subscriptions** (comma-separated)
9. Optionally open the **Bot Manager** for publish presets, alerts,
   bridges, freetext, and HA Discovery

**What is NOT on the standalone page:**

- No "Connection Mode" selector (this IS the standalone mode)
- No server type detection (ejabberd/Prosody detection is XMPP-specific)
- No "Use XMPP Credentials" option
- No Prosody-specific hints or warnings

The standalone connection runs independently of any XMPP account's MQTT.
Both per-account and standalone can be active simultaneously.

---

## 5. Setup Walkthroughs

### 5.1 ejabberd Server (Testing)

> **Note:** XMPP-bound MQTT via ejabberd is currently in testing and
> needs further validation before production use.

1. Open account preferences → MQTT Bot (Account) → Manage Account MQTT Bot
2. **Enable MQTT** -> ON
3. **Hostname** -> leave empty (uses account domain automatically)
4. **Port** -> 1883
5. **Use XMPP Credentials** -> ON (recommended, ejabberd shares auth)
6. Go to Topics page: subscribe to `home/sensors/#` (QoS 0)
7. Go back, click **Save and Apply**
8. Status should change to "Connected"

### 5.2 Prosody Server (Testing)

> **Note:** XMPP-bound MQTT via Prosody is currently in testing and
> needs further validation. Prosody's `mod_pubsub_mqtt` is a community
> module with limitations (QoS 0 only, no authentication).

1. Open account preferences → MQTT Bot (Account) → Manage Account MQTT Bot
2. **Enable MQTT** -> ON
3. Server Type shows "Prosody (mod_pubsub_mqtt)" (read-only)
4. **Hostname** -> leave empty
5. **Port** -> 1883
6. **Use XMPP Credentials** -> OFF (Prosody has no MQTT auth)
7. **Username/Password** -> leave empty
8. Go to Topics page: subscribe with **QoS 0** only (Prosody limitation)
9. Go back, click **Save and Apply**

**Note:** Prosody topics use the format `<HOST>/<TYPE>/<NODE>` (e.g.
`pubsub.example.org/json/sensors`). DinoX auto-detects this format.

### 5.3 Standalone Broker (Mosquitto / Home Assistant)

1. Open DinoX preferences → **MQTT (Standalone)**
2. **Enable** -> ON
3. **Broker Host** -> IP or hostname of your broker (e.g. `192.168.1.100`)
4. **Port** -> 1883 (or 8883 for TLS)
5. **TLS** -> recommended for non-local connections
6. **Username / Password** -> as configured on your broker
7. Add topic subscriptions
8. Save

### 5.4 Per-Account Custom Broker

You can also configure a custom (non-XMPP) MQTT broker for a specific
account. This is identical to standalone but bound to an account context:

1. Open account preferences → MQTT Bot (Account) → Manage Account MQTT Bot
2. **Enable MQTT** → ON
3. **Hostname** → enter your broker address (e.g. `mqtt.example.com`)
4. **Port** → 1883 or 8883 (TLS)
5. **Use XMPP Credentials** → OFF
6. **Username / Password** → your MQTT credentials
7. Go to Topics page: subscribe to desired topics
8. Go back, click **Save &amp; Apply**

---

## 6. Using the MQTT Bot

### 6.1 Bot Conversation

Once MQTT is enabled and connected, an **MQTT Bot** contact appears in your
conversation list. Per-account bots show the account JID in the name
(e.g. "MQTT Bot (user@example.org)"), standalone bots show "MQTT Bot".

Incoming MQTT messages appear as chat bubbles from the bot, with the topic
name as a header and the payload as the message body. JSON payloads are
automatically formatted for readability.

### 6.2 Sending Commands

Type commands in the bot chat input to control MQTT. All commands start
with `/mqtt` followed by the command name. Type `/mqtt help` for a full
list.

### 6.3 Three Ways to Publish

| Method | Example | When to use |
|--------|---------|-------------|
| Preset button | `/mqtt preset kitchen_light` | Frequently used, predefined actions |
| Freetext chat | Type "kitchen light on" (no /mqtt prefix) | Flexible commands, Node-RED processes them |
| `/mqtt publish` | `/mqtt publish home/light/set ON` | Direct access to any topic |

---

## 7. Command Reference

All 26 commands are listed below. Commands typed in a bot conversation only
affect that connection.

### 7.1 Connection and Status

| Command | Description |
|---------|-------------|
| `/mqtt status` | Show connection status, broker, subscribed topics, alert/bridge counts |
| `/mqtt config` | Show current connection configuration details |
| `/mqtt reconnect` | Force disconnect and reconnect to the broker |

### 7.2 Topic Management

| Command | Description |
|---------|-------------|
| `/mqtt subscribe <topic>` | Subscribe to a topic (wildcards: `+` single level, `#` all levels) |
| `/mqtt unsubscribe <topic>` | Unsubscribe from a topic |
| `/mqtt topics` | List all active subscriptions with last received values |
| `/mqtt manager` | Open the visual topic/bridge/alert manager dialog |

### 7.3 Publishing

| Command | Description |
|---------|-------------|
| `/mqtt publish <topic> <payload>` | Publish a message to a topic |
| `/mqtt preset add <name> <topic> <payload>` | Create a new publish preset |
| `/mqtt preset remove <index>` | Remove a preset by its list index |
| `/mqtt preset <name>` | Execute a named preset (publish its payload) |
| `/mqtt presets` | List all configured publish presets |

### 7.4 Alerts and Notifications

| Command | Description |
|---------|-------------|
| `/mqtt alert <topic> [field] <op> <value> [priority]` | Add a threshold alert rule |
| `/mqtt alerts` | List all alert rules with their status |
| `/mqtt rmalert <index>` | Remove an alert rule by its list index |
| `/mqtt priority <topic> <level>` | Set per-topic notification priority (normal/alert/critical/silent) |
| `/mqtt pause` | Pause all alert notifications |
| `/mqtt resume` | Resume alert notifications |

**Alert operators:** `>`, `<`, `>=`, `<=`, `==`, `!=`, `contains`

**Alert examples:**

```
/mqtt alert home/temperature temperature > 30
/mqtt alert home/door/front OPEN critical
/mqtt alert home/sensors/# humidity >= 80 alert
```

### 7.5 History and Charts

| Command | Description |
|---------|-------------|
| `/mqtt history <topic>` | Show recent values for a topic (from database) |
| `/mqtt chart <topic>` | Show a Unicode sparkline chart for numeric topics |
| `/mqtt qos <topic> <0/1/2>` | Set per-topic QoS level |

### 7.6 Bridges

| Command | Description |
|---------|-------------|
| `/mqtt bridge <topic> <jid> [format]` | Add MQTT-to-XMPP bridge rule |
| `/mqtt bridges` | List all bridge rules |
| `/mqtt rmbridge <index>` | Remove a bridge rule by its list index |

**Bridge format options:**

| Format | Output |
|--------|--------|
| `full` | Topic name + full payload (default) |
| `payload_only` | Only the payload, no topic name |
| `short` | Abbreviated format |

**Bridge example:**

```
/mqtt bridge home/alerts/# admin@example.org
/mqtt bridge home/sensors/temp bob@example.org payload_only
```

Messages matching the topic pattern are forwarded to the XMPP contact.
Rate limiting prevents flooding (minimum 2 seconds between forwards).

### 7.7 Database

| Command | Description |
|---------|-------------|
| `/mqtt dbstats` | Show database row counts and retention periods per table |
| `/mqtt purge` | Manually trigger database cleanup (same as auto-purge) |

### 7.8 Home Assistant Discovery

| Command | Description |
|---------|-------------|
| `/mqtt discovery on` | Enable HA device discovery |
| `/mqtt discovery off` | Disable HA device discovery |
| `/mqtt discovery refresh` | Re-publish discovery config and all entity states |
| `/mqtt discovery prefix <value>` | Change the discovery prefix (default: "homeassistant") |

### 7.9 Help

| Command | Description |
|---------|-------------|
| `/mqtt help` | Show the complete command reference |

---

## 8. Home Assistant Integration

### 8.1 What It Does

When HA Discovery is enabled, DinoX registers itself as a device in Home Assistant.
HA will show DinoX with 8 entities that you can use in dashboards, automations,
and scripts.

**Important:** HA Discovery requires a **real MQTT broker** (Mosquitto, EMQX,
HiveMQ, etc.) that both DinoX and Home Assistant connect to as clients.
It does **not** work with ejabberd or Prosody XMPP-MQTT because these
XMPP servers do not support retained messages, LWT, or free topic hierarchies
that HA Discovery depends on.

Supported modes:
- **(A) Standalone** -- always connects to a real broker
- **(C) Per-Account Custom Broker** -- user provides a real broker hostname

Not supported:
- **(B) Per-Account XMPP** (ejabberd/Prosody) -- Discovery is automatically
  disabled and hidden in the UI

### 8.2 Enabling Discovery

**Via the UI:**
- In the MqttBotManagerDialog (Custom Broker mode or standalone settings page),
  enable the "HA Discovery" switch and set the prefix (default: "homeassistant")

**Via chat command:**
```
/mqtt discovery on
/mqtt discovery prefix homeassistant
```

### 8.3 Entities in Home Assistant

Once discovery is enabled, the following entities appear in HA:

| Entity | Type | Description |
|--------|------|-------------|
| Connectivity | Binary Sensor | Shows whether DinoX is connected to the broker |
| Subscriptions | Sensor | Number of active topic subscriptions |
| Bridges | Sensor | Number of active bridge rules |
| Alerts | Sensor | Number of active alert rules |
| Status | Sensor | Summary text (subscriptions, bridges, alerts, paused state) |
| Alerts Pause | Switch | Pause/resume alert evaluation from HA |
| Reconnect | Button | Trigger a reconnect from HA |
| Refresh | Button | Refresh all entity states from HA |

### 8.4 Controlling DinoX from HA

The switch and button entities allow HA to control DinoX:

- **Alerts Pause switch:** Turn ON to pause alerts, OFF to resume. Useful in
  HA automations (e.g. pause alerts during maintenance windows).
- **Reconnect button:** Press to force DinoX to disconnect and reconnect.
- **Refresh button:** Press to make DinoX re-publish all entity states.

### 8.5 Availability

DinoX uses MQTT Last Will and Testament (LWT) for availability tracking:

- When DinoX connects: publishes "online" (retained)
- When DinoX disconnects cleanly: publishes "offline" (retained)
- When DinoX crashes: the broker publishes "offline" via LWT

HA shows the device as unavailable when the availability topic reads "offline".

### 8.6 After HA Restarts

DinoX subscribes to the HA status topic (`<prefix>/status`). When HA sends
its birth message ("online") after a restart, DinoX automatically re-publishes
the full discovery config and all entity states. No manual intervention needed.

### 8.7 Independence from HA

MQTT Discovery is completely opt-in and disabled by default. When disabled,
all other MQTT functionality (subscriptions, alerts, bridges, freetext,
commands) works exactly the same. DinoX is a general-purpose MQTT client
first -- HA integration is an optional bonus.

---

## 9. Alert System

### 9.1 How Alerts Work

Alerts monitor incoming MQTT messages against user-defined rules. When a
condition is met, the message priority changes and a notification is triggered.

### 9.2 Creating Alert Rules

```
/mqtt alert <topic_pattern> [json_field] <operator> <threshold> [priority]
```

| Parameter | Description |
|-----------|-------------|
| `topic_pattern` | MQTT topic (wildcards supported) |
| `json_field` | Optional: extract this field from JSON payloads |
| `operator` | One of: `>`, `<`, `>=`, `<=`, `==`, `!=`, `contains` |
| `threshold` | Value to compare against |
| `priority` | Optional: `alert` (default), `critical`, `normal`, `silent` |

### 9.3 Priority Levels

| Priority | Behavior |
|----------|----------|
| Silent | No notification, message visible in history only |
| Normal | Unread badge on bot conversation |
| Alert | Badge + desktop notification |
| Critical | Badge + desktop notification + sound |

### 9.4 Managing Alerts

- `/mqtt alerts` -- list all rules with index numbers
- `/mqtt rmalert <index>` -- remove a rule by index
- `/mqtt pause` -- temporarily pause all alert evaluation
- `/mqtt resume` -- resume alert evaluation
- Alert rules can also be toggled and removed in the Alert Rules page
  of the MqttBotManagerDialog

### 9.5 Alert Cooldown

Each rule has a cooldown period (default: 60 seconds). After triggering,
the same rule will not trigger again until the cooldown expires. This
prevents notification flooding from high-frequency topics.

---

## 10. MQTT-to-XMPP Bridge

### 10.1 How Bridges Work

Bridge rules forward MQTT messages to real XMPP contacts. When a message
arrives on a matching topic, it is sent as an XMPP chat message to the
configured JID.

### 10.2 Creating Bridge Rules

```
/mqtt bridge <topic_pattern> <jid> [format]
```

| Parameter | Description |
|-----------|-------------|
| `topic_pattern` | MQTT topic (wildcards supported) |
| `jid` | Target XMPP contact (e.g. `admin@example.org`) |
| `format` | `full` (default), `payload_only`, or `short` |

### 10.3 Rate Limiting

To prevent flooding, bridges enforce a minimum 2-second interval between
forwarded messages per rule.

### 10.4 Managing Bridges

- `/mqtt bridges` -- list all rules with index numbers
- `/mqtt rmbridge <index>` -- remove a rule by index
- Bridge rules can also be removed in the Bridge Rules page of the
  MqttBotManagerDialog

---

## 11. Server-Type Adaptive Behavior

> **XMPP MQTT is in testing:** The ejabberd and Prosody MQTT integration
> (per-account mode B) has not been fully validated. Use standalone mode
> (A) or per-account custom mode (C) for production use.

When using per-account MQTT with an XMPP server (mode B), DinoX auto-detects
the server's MQTT capabilities via XEP-0030 Service Discovery and adapts
the UI accordingly. This does **not** apply to standalone mode (A) or
per-account custom mode (C).

| Feature | ejabberd | Prosody | Custom / Standalone |
|---------|----------|---------|---------------------|
| Host field | Auto-filled: account domain | Auto-filled: account domain | Manual entry required |
| XMPP credentials switch | Visible, default ON | Hidden (no MQTT auth) | Hidden (not applicable) |
| Username/Password | Greyed out (from XMPP) | Greyed out + "No auth" hint | Editable (own credentials) |
| QoS selection | 0, 1, 2 | 0 only (Prosody limitation) | 0, 1, 2 |
| Security warning | None | "No authentication — restrict access via firewall" | TLS warning if non-local |
| Topic format hint | None | "Format: host/type/node" | None |
| Server detection | Via XEP-0030 | Via XEP-0030 | Not available |

---

## 12. Database and History

### 12.1 What Is Stored

DinoX stores MQTT data in an encrypted local database (`mqtt.db`):

| Data | Retention |
|------|-----------|
| Received messages | 30 days |
| Freetext exchanges | 30 days |
| Connection events | 90 days |
| Publish history | 30 days |
| Topic statistics | Unlimited (aggregated, 1 row per topic) |
| Alert/Bridge/Preset rules | Unlimited (user-managed) |
| Retained message cache | Unlimited (1 row per topic) |

### 12.2 Automatic Cleanup

The database is cleaned automatically at startup and every 6 hours.
Old entries beyond their retention period are deleted. No manual
intervention is needed.

### 12.3 Manual Commands

- `/mqtt dbstats` -- view database statistics (row counts, sizes)
- `/mqtt purge` -- trigger cleanup immediately

---

## 13. Sparkline Charts

For topics that receive numeric data, you can view a sparkline chart:

```
/mqtt chart home/sensors/temperature
```

This shows a Unicode block chart of recent values with min, max, and
average statistics. The chart uses data from the persistent database,
so it works across restarts.

---

## 14. Security Notes

### 14.1 TLS

DinoX shows a warning when connecting to a non-local broker without TLS.
For internet-facing connections, always enable TLS (port 8883).

### 14.2 Prosody

Prosody's `mod_pubsub_mqtt` has no MQTT authentication. Anyone who can
reach the MQTT port can subscribe and publish. Protect the port with
firewall rules or VPN.

### 14.3 Database Encryption

All local MQTT data is encrypted with your DinoX master password using
SQLCipher. The encryption key is shared across all DinoX databases.

---

## 15. Troubleshooting

| Problem | Solution |
|---------|----------|
| Bot does not appear | Check that MQTT is enabled and at least one XMPP account is connected |
| Status shows "Disconnected" | Verify broker host, port, and credentials. Check TLS setting. |
| No messages arriving | Check topic subscriptions (`/mqtt topics`). Verify the topic pattern matches what the broker publishes. |
| "Connection refused" | Broker may be down, port blocked, or wrong credentials |
| Topics show QoS 0 only | Prosody limitation -- only QoS 0 is supported |
| HA does not show DinoX device | Enable discovery (`/mqtt discovery on`), verify prefix matches HA config |
| Alerts not triggering | Check `/mqtt alerts` for rule status. Alerts may be paused (`/mqtt resume`). Check cooldown period. |
| Freetext not working | Enable freetext publish in the Publish page. Configure publish and response topics. |
| High disk usage | Run `/mqtt purge` or wait for automatic cleanup (every 6 hours) |
