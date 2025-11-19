# 🏛️ Architecture Guide - Dino Extended

Deep dive into Dino's codebase structure, design patterns, and key components.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Directory Structure](#directory-structure)
- [Core Components](#core-components)
- [XMPP Protocol Layer](#xmpp-protocol-layer)
- [Plugin System](#plugin-system)
- [Database Layer](#database-layer)
- [Message Flow](#message-flow)

---

## 🎯 Overview

Dino follows a **layered architecture**:

```
┌─────────────────────────────────────────┐
│          UI Layer (GTK4)                │  main/
│  Windows, Widgets, View Models          │
└───────────────┬─────────────────────────┘
                │
┌───────────────▼─────────────────────────┐
│       Application Layer                 │  libdino/
│  Services, Business Logic, Database     │
└───────────────┬─────────────────────────┘
                │
┌───────────────▼─────────────────────────┐
│       XMPP Protocol Layer               │  xmpp-vala/
│  Stanza handling, XEP implementations   │
└───────────────┬─────────────────────────┘
                │
┌───────────────▼─────────────────────────┐
│         Network Layer                   │  GIO/GLib
│  Sockets, TLS, DNS                      │
└─────────────────────────────────────────┘

         Plugins (cross-cutting)
    ┌──────────────────────────┐
    │  OMEMO, OpenPGP, RTP,    │  plugins/
    │  HTTP Files, ICE         │
    └──────────────────────────┘
```

**Key Principles**:
- **Separation of Concerns**: UI doesn't know about XMPP details
- **Service-Oriented**: `StreamInteractor` acts as service locator
- **Plugin Architecture**: Optional features as loadable modules
- **Asynchronous**: Heavy operations use Vala's `async`/`yield`

---

## 📁 Directory Structure

See [BUILD.md](BUILD.md) for detailed directory listing.

**Key Components**:
- `libdino/` - Core application logic
- `xmpp-vala/` - XMPP protocol (60+ XEPs)
- `main/` - GTK4 UI
- `plugins/` - Optional features (OMEMO, RTP, etc.)
- `qlite/` - SQLite wrapper
- `crypto-vala/` - Encryption utilities

---

## ��️ Core Components

### 1. Application

**File**: `libdino/src/application.vala`

**Purpose**: Application initialization

**Responsibilities**:
- Initialize database
- Create StreamInteractor
- Load plugins
- Start XMPP connections

### 2. StreamInteractor

**File**: `libdino/src/service/stream_interactor.vala`

**Purpose**: Central service coordinator (Service Locator pattern)

Contains 20+ services:
- MessageProcessor
- RosterManager
- PresenceManager
- MucManager
- FileManager
- CallState
- etc.

### 3. Database

**File**: `libdino/src/entity/database.vala`

**Current Version**: 30

See [DATABASE_SCHEMA.md](DATABASE_SCHEMA.md) for details.

---

## 📡 XMPP Protocol Layer

### XmppStream

**File**: `xmpp-vala/src/core/xmpp_stream.vala`

Manages single XMPP connection with 30+ protocol modules.

### XEP Modules

Located in `xmpp-vala/src/module/xep/`

See [XEP_SUPPORT.md](XEP_SUPPORT.md) for full list.

**Example**: XEP-0184 (Message Receipts)
```vala
public class Module : XmppStreamModule {
    public signal void receipt_received(XmppStream stream, Jid jid, string id);
    
    public void send_received(XmppStream stream, Jid jid, string id) {
        // Send receipt stanza
    }
}
```

---

## 🔌 Plugin System

**Registry**: `libdino/src/plugin/registry.vala`

**Plugin Interface**: `RootInterface`

**Encryption Plugin**: `EncryptionPlugin` interface

**Example**: OMEMO Plugin
- Entry: `plugins/omemo/src/plugin.vala`
- Implements encryption/decryption
- Adds UI components
- Hooks into message pipeline

---

## 🗄️ Database Layer

### qlite Wrapper

**Location**: `qlite/src/`

Provides type-safe SQLite access:
```vala
RowIterator rows = select()
    .with(message.account_id, "=", account.id)
    .order_by(message.time, "DESC")
    .limit(50);
```

---

## 📨 Message Flow

### Sending
```
ChatInput → MessageProcessor → EncryptionPlugin → XmppStream → Server
```

### Receiving
```
Server → XmppStream → MessageModule → MessageProcessor → Database → UI
```

---

**For more details, see [BUILD.md](BUILD.md) and [XEP_SUPPORT.md](XEP_SUPPORT.md)**
