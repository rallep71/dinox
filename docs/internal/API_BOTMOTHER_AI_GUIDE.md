# DinoX Botmother AI — API & User Guide

> Version 1.1 | February 2026

---

## Table of Contents

1. [Overview](#1-overview)
2. [Getting Started](#2-getting-started)
   - [2.1 Enable Botmother in Settings](#21-enable-botmother-in-settings)
   - [2.2 Your First Bot](#22-your-first-bot)
   - [2.3 Bot Modes](#23-bot-modes)
3. [Bot Management via Chat (Botfather)](#3-bot-management-via-chat-botfather)
   - [3.1 Botfather Commands](#31-botfather-commands)
   - [3.2 Creating a Bot](#32-creating-a-bot)
   - [3.3 Managing Bots](#33-managing-bots)
   - [3.4 Token Management](#34-token-management)
4. [Bot Management via UI (Bot Manager Dialog)](#4-bot-management-via-ui-bot-manager-dialog)
   - [4.1 Opening the Bot Manager](#41-opening-the-bot-manager)
   - [4.2 Bot List & Actions](#42-bot-list--actions)
   - [4.3 ejabberd Settings (for Dedicated Bots)](#43-ejabberd-settings-for-dedicated-bots)
5. [Dedicated Bot Chat — Interactive Menus](#5-dedicated-bot-chat--interactive-menus)
   - [5.1 Main Menu (/help)](#51-main-menu-help)
   - [5.2 AI Assistant (/ki)](#52-ai-assistant-ki)
   - [5.3 Telegram Bridge (/telegram)](#53-telegram-bridge-telegram)
   - [5.4 API Documentation (/api)](#54-api-documentation-api)
   - [5.5 API Server Settings (/api server)](#55-api-server-settings-api-server)
6. [AI Assistant — Setup & Usage](#6-ai-assistant--setup--usage)
   - [6.1 Supported Providers](#61-supported-providers)
   - [6.2 Quick Setup](#62-quick-setup)
   - [6.3 Talking to the AI](#63-talking-to-the-ai)
   - [6.4 System Prompt](#64-system-prompt)
   - [6.5 Changing Provider or Model](#65-changing-provider-or-model)
7. [Telegram Bridge — Setup & Usage](#7-telegram-bridge--setup--usage)
   - [7.1 Prerequisites](#71-prerequisites)
   - [7.2 Setup](#72-setup)
   - [7.3 Bridge Modes](#73-bridge-modes)
   - [7.4 Message Flow](#74-message-flow)
   - [7.5 Planned Features (Roadmap)](#75-planned-features-roadmap)
8. [HTTP API Reference](#8-http-api-reference)
   - [8.1 Authentication](#81-authentication)
   - [8.2 API Server Configuration](#82-api-server-configuration)
   - [8.3 Bot Management Endpoints (No Auth)](#83-bot-management-endpoints-no-auth)
   - [8.4 Bot Messaging Endpoints (Auth Required)](#84-bot-messaging-endpoints-auth-required)
   - [8.5 Webhook System](#85-webhook-system)
   - [8.6 Advanced Endpoints](#86-advanced-endpoints)
   - [8.7 ejabberd Admin Endpoints](#87-ejabberd-admin-endpoints)
   - [8.8 Telegram API Endpoints](#88-telegram-api-endpoints)
   - [8.9 AI API Endpoints](#89-ai-api-endpoints)
   - [8.10 Complete curl Examples](#810-complete-curl-examples)
   - [8.11 Python Examples](#811-python-examples)
9. [Settings Reference](#9-settings-reference)
   - [9.1 Application Settings (Preferences)](#91-application-settings-preferences)
   - [9.2 Per-Bot Settings (Database)](#92-per-bot-settings-database)
10. [Database Schema](#10-database-schema)
11. [DinoX Bot Server (Cloud Mode) — Coming Soon](#11-dinox-bot-server-cloud-mode--coming-soon)
12. [OpenClaw Integration](#12-openclaw-integration)

---

## 1. Overview

**Botmother** is DinoX's built-in bot platform. It lets you create, manage, and run XMPP bots directly from DinoX — no separate server or software needed.

**What you can do:**

- Create bots that respond to XMPP messages
- Connect an AI (OpenAI, Claude, Gemini, Groq, Mistral, DeepSeek, Perplexity, Ollama, OpenClaw) to any bot
- Bridge bot messages to/from Telegram
- Control bots via an HTTP API with webhooks
- Manage everything through chat commands or the graphical UI
- Run bots as your own account (Personal) or as independent XMPP accounts (Dedicated)

**Architecture:**

```
┌────────────────────────────────────────────────────┐
│                    DinoX App                       │
│                                                    │
│  ┌─────────────┐  ┌─────────────┐  ┌───────────┐   │
│  │  Botfather   │  │  Bot Chat   │  │    UI     │  │
│  │ (Self-Chat)  │  │  (Menus)    │  │ (Manager) │  │
│  └──────┬───────┘  └──────┬──────┘  └─────┬─────┘  │
│         │                 │               │        │
│  ┌──────┴─────────────────┴───────────────┴─────┐  │
│  │            Message Router                     │ │
│  └──────────────────┬────────────────────────────┘ │
│                     │                              │
│  ┌──────────┬───────┴────────┬──────────────────┐  │
│  │ Bot      │ Session Pool   │ HTTP Server      │  │
│  │ Registry │ (Personal +    │ (REST API +      │  │
│  │ (SQLite) │  Dedicated)    │  TLS)            │  │
│  └──────────┘ └──────────────┘ └────────────────┘  │
│                     │                              │
│  ┌──────────┬───────┴────────┬──────────────────┐  │
│  │ AI       │ Telegram       │ Webhook          │  │
│  │ Integr.  │ Bridge         │ Dispatcher       │  │
│  └──────────┘ └──────────────┘ └────────────────┘  │
└────────────────────────────────────────────────────┘
```

---

## 2. Getting Started

### 2.1 Enable Botmother in Settings

1. Open DinoX
2. Go to **Preferences** (gear icon or menu)
3. Scroll to the **Botmother** section
4. Toggle **"Enable Botmother"** ON

Once enabled, these additional settings appear:

| Setting | Description | Default |
|---------|-------------|---------|
| **API Server Mode** | `Local (localhost)` — HTTP, only accessible from this machine. `Network (0.0.0.0 + TLS)` — HTTPS, accessible from the network. | Local |
| **API Port** | Port number for the API server (1024–65535) | 7842 |
| **TLS Certificate** | Path to PEM certificate file (Network mode only). Leave empty for auto-generated self-signed. | (empty) |
| **TLS Private Key** | Path to PEM key file (Network mode only). Leave empty for auto-generated. | (empty) |

> **Note:** All settings are applied immediately — no restart required. The API server automatically restarts when you change mode, port, or TLS settings.

### 2.2 Your First Bot

There are two ways to create a bot:

**Option A — Via Chat (Botfather):**
1. Open the conversation with yourself (self-chat)
2. Type: `/newbot MyFirstBot`
3. Botmother replies with the bot's ID and API token

**Option B — Via UI (Bot Manager):**
1. Click the Botmother icon in the header bar, or go to the account menu
2. Click **"New Botmother"**
3. Enter a name and choose a mode
4. The bot is created with a generated token

### 2.3 Bot Modes

| Mode | How it Works | Best For |
|------|-------------|----------|
| **Personal** | Bot shares your XMPP account. Messages appear in your self-chat (Botmother conversation). | Quick experiments, personal automation, AI chat for yourself |
| **Dedicated** | Bot gets its own XMPP account (registered via ejabberd). Appears as a separate contact with its own JID, OMEMO keys, avatar, and roster. | Public bots, bots for other users, full separation |
| **DinoX Bot Server** | *Coming soon* — See [Section 11](#11-dinox-bot-server-cloud-mode--coming-soon) | Hosted bot infrastructure |

**Personal mode** requires no extra setup. **Dedicated mode** requires ejabberd admin API access (see [Section 4.3](#43-ejabberd-settings-for-dedicated-bots)).

#### Personal Mode — How it works in detail

In Personal mode, the bot shares your own XMPP account. DinoX automatically creates and **pins** a special conversation with yourself (self-chat). This pinned "Botmother" conversation is where you interact with the bot system:

- The conversation appears at the top of your chat list (pinned)
- When you send a `/` command in this self-chat, DinoX intercepts it and processes it as a Botfather command
- Non-command messages are forwarded to the bot's AI (if configured)
- The bot responds in the same self-chat
- If you disable Botmother for an account or globally, the self-chat is automatically unpinned and closed
- The self-chat is re-pinned automatically when Botmother is re-enabled

```
┌──────────────────────────┐
│  Chat List               │
│  📌 Botmother (You)      │  ← Pinned self-chat
│     Alice                │
│     Bob                  │
│     Group Chat           │
└──────────────────────────┘
```

> **Note:** Since the bot shares your account, messages sent by the bot via the HTTP API appear to come from your own JID. Other users cannot distinguish between you and the bot.

#### Dedicated Mode — How it works in detail

In Dedicated mode, each bot gets its own independent XMPP account. This provides full separation and security:

**Own XMPP Account:**
- DinoX registers a new account on your ejabberd server via the admin API
- The bot JID is generated automatically: `bot_<name>_<hash>@<server>`
- Example: `bot_weatherbot_c3a1@chat.example.com`
- The bot has its own password (stored in the database)

**Automatic OMEMO Encryption:**
- DinoX automatically generates OMEMO keys for the dedicated bot
- The conversation between you and the bot is **OMEMO-encrypted by default**
- The bot publishes its OMEMO device list and key bundles via PubSub
- All messages (both directions) are end-to-end encrypted
- No manual OMEMO setup needed — it happens automatically on first connection

**Owner-Only Binding:**
- The dedicated bot is **bound exclusively to its creator's JID**
- The bot **only accepts and processes messages from the owner**
- Messages from any other JID are silently ignored
- Subscription requests from non-owners are rejected
- The bot automatically approves mutual presence subscription with the owner
- This means: even if someone discovers the bot's JID, they cannot interact with it

**Automatic Conversation Setup:**
- When the dedicated bot connects, DinoX automatically:
  1. Creates a conversation for the bot in your chat list
  2. Enables OMEMO encryption on the conversation
  3. Sends/approves presence subscription (bot ↔ owner)
  4. Sets the bot's roster display name
  5. Publishes the bot's vCard (with avatar if configured)
  6. Makes PubSub nodes publicly accessible

**Separate Chat:**
- The dedicated bot appears as a **separate contact** in your chat list
- You chat with it just like chatting with any other person
- Slash commands (`/help`, `/ki`, `/telegram`, `/api`) work in this chat
- Non-command messages go to the AI (if configured)

```
┌──────────────────────────┐
│  Chat List               │
│  📌 Botmother (You)      │  ← Personal bots (self-chat)
│  🤖 WeatherBot 🔒        │  ← Dedicated bot (OMEMO encrypted)
│  🤖 SupportBot 🔒        │  ← Another dedicated bot
│     Alice                │
│     Bob                  │
└──────────────────────────┘

🔒 = OMEMO end-to-end encrypted
```

> **Security:** Dedicated bots are the recommended mode for any bot that handles sensitive data. The OMEMO encryption and owner-only binding ensure that bot communications are private and cannot be intercepted or hijacked.

---

## 3. Bot Management via Chat (Botfather)

The **Botfather** is a special handler that intercepts slash commands in your self-chat (the conversation where sender = yourself).

### 3.1 Botfather Commands

| Command | Arguments | Description |
|---------|-----------|-------------|
| `/start` | — | Show welcome message (alias for `/help`) |
| `/help` | — | Show all available commands with examples |
| `/newbot` | `<name>` | Create a new Personal bot (max 20 per account) |
| `/mybots` | — | List all your bots with status |
| `/deletebot` | `<ID>` | Delete a bot (dedicated bots also lose their XMPP account) |
| `/token` | `<ID>` | Regenerate API token (old one becomes invalid) |
| `/showtoken` | `<ID>` | Display the current token |
| `/revoke` | `<ID>` | Revoke token and disable bot |
| `/activate` | `<ID>` | Set bot status to active |
| `/deactivate` | `<ID>` | Set bot status to disabled |
| `/setcommands` | `<ID> /cmd - desc, ...` | Register custom bot commands |
| `/setdescription` | `<ID> <text>` | Set bot description |
| `/status` | `[ID]` | Without ID: system overview. With ID: detailed bot info |

### 3.2 Creating a Bot

```
You:        /newbot WeatherBot
Botmother:  Bot created!
            ID: 3
            Name: WeatherBot
            Mode: personal
            Token: bm_a7f2c...e91d
            
            API URL: http://localhost:7842/bot/
            Use the token in the Authorization header:
            Authorization: Bearer bm_a7f2c...e91d
```

To create a **dedicated** bot, use the Bot Manager UI (Section 4) and select "Dedicated" mode.

### 3.3 Managing Bots

**List all bots:**
```
You:        /mybots
Botmother:  Your bots:
            [1] WeatherBot (personal, active)
            [3] SupportBot (dedicated, active) — support_bot_c3a1@chat.example.com
            [5] TestBot (personal, disabled)
```

**Get detailed status:**
```
You:        /status 3
Botmother:  Bot: SupportBot
            ID: 3
            Mode: dedicated
            Status: active
            JID: support_bot_c3a1@chat.example.com
            Webhook: https://my-server.com/hook (active)
            Commands: /weather, /help
            
            API: http://localhost:7842/bot/
```

**Delete a bot:**
```
You:        /deletebot 5
Botmother:  Bot "TestBot" (ID: 5) deleted.
```
For dedicated bots, the XMPP account is also unregistered from ejabberd.

### 3.4 Token Management

Every bot has an API token used for authentication. Tokens start with `bm_`.

```
You:        /showtoken 3
Botmother:  Token for SupportBot (ID: 3):
            bm_a7f2c...e91d

You:        /token 3
Botmother:  New token generated for SupportBot:
            bm_x9k4d...7b2e
            (Old token is now invalid)

You:        /revoke 3
Botmother:  Token revoked. Bot "SupportBot" is now disabled.
```

---

## 4. Bot Management via UI (Bot Manager Dialog)

### 4.1 Opening the Bot Manager

The Bot Manager dialog provides a graphical interface for all bot operations. It communicates with the local API server.

### 4.2 Bot List & Actions

The main view shows all bots for the selected account:

```
┌─────────────────────────────────────────┐
│  Botmother — ralf@chat.example.com      │
├─────────────────────────────────────────┤
│  [✓] Botmother Active                   │
│      Enable Botmother for this account  │
├─────────────────────────────────────────┤
│                                         │
│  ● WeatherBot                           │
│    ID: 1 · personal · active            │
│    Token: bm_a7f2c...    [Copy] [↻] [✕] │
│                                         │
│  ● SupportBot                           │
│    ID: 3 · dedicated · active           │
│    support_bot_c3a1@chat.example.com    │
│    Token: bm_x9k4d...    [Copy] [↻] [✕] │
│                                         │
├─────────────────────────────────────────┤
│  ▸ Server Settings (ejabberd)           │
├─────────────────────────────────────────┤
│  Botmother API: http://127.0.0.1:7842   │
│                                         │
│              [+ New Botmother]          │
└─────────────────────────────────────────┘
```

**Available actions per bot:**

| Button | Action |
|--------|--------|
| Toggle switch | Activate / Deactivate bot |
| Copy | Copy token to clipboard |
| ↻ (Regenerate) | Generate new token (old one invalidated) |
| ✕ (Revoke) | Revoke token and disable bot |
| 🗑 (Delete) | Delete bot (with confirmation dialog) |

### 4.3 ejabberd Settings (for Dedicated Bots)

To use **Dedicated** mode, you need to configure the ejabberd admin API. Expand the **"Server Settings"** section:

| Field | Example | Description |
|-------|---------|-------------|
| API URL | `http://localhost:5443/api` | ejabberd REST API endpoint |
| XMPP Host | `chat.example.com` | The XMPP server hostname |
| Admin JID | `admin@chat.example.com` | Admin account for API authentication |
| Admin Password | `••••••••` | Admin account password |

Click **"Test"** to verify the connection, then **"Save"**.

> **Important:** Without ejabberd API access, you can only create Personal bots. Dedicated bots require ejabberd to register their own XMPP accounts.

---

## 5. Dedicated Bot Chat — Interactive Menus

When you have a **Dedicated** bot, it appears as a separate conversation. Open it to access interactive menus via slash commands.

### 5.1 Main Menu (/help)

```
You:    /help

Bot:    WeatherBot
        ════════════════════

        Status:
          AI: active (groq / llama-3.3-70b-versatile)
          Telegram: off

        ────────────────────
        Menus:
        /ki         - AI assistant setup & control
        /telegram   - Telegram bridge setup & control
        /api        - HTTP API & webhook documentation

        ────────────────────
        Basic commands:
        /help       - This menu
        /start      - Greeting
        /info       - Bot details

        ────────────────────
        Quick start:
        Just send a message for the AI!
```

### 5.2 AI Assistant (/ki)

The `/ki` menu controls the AI integration for this bot.

```
/ki             → AI main menu (status, available commands)
/ki on          → Enable AI responses
/ki off         → Disable AI, clear history
/ki status      → Current configuration details
/ki setup       → Provider selection menu
/ki setup <p>   → Setup help for a specific provider
/ki setup <provider> <key> <model>
                → Configure AI in one command
/ki model       → Show current model + alternatives
/ki model <name>→ Switch to a different model
/ki system      → Show current system prompt
/ki system <text> → Set a new system prompt
/ki clear       → Clear conversation history
/ki providers   → List all supported providers
```

**Example: Set up AI with Groq:**
```
You:    /ki setup groq gsk_abc123mykey llama-3.3-70b-versatile
Bot:    AI configured!
        Provider: groq
        Model: llama-3.3-70b-versatile
        AI is now active.
```

**Example: Talk to the AI:**
```
You:    What is the capital of France?
Bot:    The capital of France is Paris. It is the largest city in France
        and serves as the country's political, economic, and cultural center.
```

### 5.3 Telegram Bridge (/telegram)

```
/telegram           → Telegram main menu
/telegram on        → Enable bridge (must be configured first)
/telegram off       → Disable bridge, stop polling
/telegram status    → Current configuration
/telegram setup     → Step-by-step setup guide
/telegram setup <TOKEN> <CHAT_ID> [mode]
                    → Configure in one command
/telegram mode      → Show current mode
/telegram mode bridge  → Bidirectional (XMPP <-> Telegram)
/telegram mode forward → One-way (XMPP -> Telegram only)
/telegram test      → Test connection
```

### 5.4 API Documentation (/api)

The `/api` menu provides in-chat documentation for the HTTP API.

```
/api                → API overview (base URL, topics)
/api auth           → Authentication documentation
/api messages       → Send/receive messages (with curl examples)
/api webhook        → Webhook setup and format documentation
/api management     → Bot CRUD operations documentation
/api advanced       → Files, reactions, rooms, commands
/api examples       → Quick-start curl + Python code
/api server         → Server settings menu (see 5.5)
```

### 5.5 API Server Settings (/api server)

Change API server settings directly from chat:

```
/api server             → Current settings overview
/api server local       → Switch to localhost-only mode (HTTP)
/api server network     → Switch to all-interfaces mode (HTTPS + TLS)
/api server port <nr>   → Change port (1024-65535)
/api server status      → Detailed server status
/api server cert <path> → Set custom TLS certificate
/api server key <path>  → Set custom TLS key
/api server cert auto   → Reset to auto-generated self-signed cert
/api server renew-cert  → Delete and regenerate self-signed certificate
/api server delete-cert → Delete current self-signed certificate
```

All changes are applied automatically — no restart needed.

---

## 6. AI Assistant — Setup & Usage

### 6.1 Supported Providers

| Provider | API Key Required | Models | Notes |
|----------|-----------------|--------|-------|
| **OpenAI** | Yes | gpt-4o, gpt-4o-mini, gpt-4-turbo, o1 | Best quality, paid |
| **Claude** (Anthropic) | Yes | claude-sonnet-4-20250514, claude-3-haiku, claude-3-opus | High quality, paid |
| **Gemini** (Google) | Yes | gemini-2.0-flash, gemini-1.5-pro, gemini-pro | Free tier available |
| **Groq** | Yes (free) | llama-3.3-70b-versatile, mixtral-8x7b, gemma-7b | Very fast, free tier |
| **Mistral** | Yes | mistral-large-latest, mistral-medium, mistral-small | European provider |
| **DeepSeek** | Yes | deepseek-chat, deepseek-coder | Good value |
| **Perplexity** | Yes | sonar-medium, sonar-small | Search-augmented |
| **Ollama** | No (local) | llama3, phi3, gemma, mistral, codellama | Runs on your own machine |
| **OpenClaw** | Yes (token) | agent | Autonomous AI orchestrator, manages models internally |

### 6.2 Quick Setup

**Via chat command (one line):**
```
/ki setup groq YOUR_API_KEY llama-3.3-70b-versatile
```

**Via guided menu:**
```
/ki setup           → Shows provider list
/ki setup groq      → Shows Groq-specific help with signup link
```

**For Ollama (local, no key needed):**
```
/ki setup ollama - llama3
```
Use `-` as the API key placeholder for Ollama.

**For OpenClaw (autonomous agent):**
```
/ki setup openclaw YOUR_HOOKS_TOKEN agent
```
OpenClaw manages its own models internally. The `agent` model name tells DinoX to use the webhook API.

### 6.3 Talking to the AI

Once AI is active (`/ki on`), simply send any message without a `/` prefix:

```
You:    Explain quantum computing in simple terms
Bot:    Quantum computing uses quantum bits (qubits) instead of
        regular bits. While a normal bit is either 0 or 1, a qubit
        can be both at the same time (superposition)...
```

The bot maintains conversation history (up to 20 messages per user) for context-aware responses. Use `/ki clear` to reset the history.

### 6.4 System Prompt

The system prompt defines how the AI behaves:

```
/ki system                              → View current prompt
/ki system You are a helpful weatherbot → Set new prompt
```

Default: "Du bist ein hilfreicher Assistent." (translatable)

### 6.5 Changing Provider or Model

```
/ki providers             → List all providers with details
/ki model                 → Show current model + alternatives
/ki model mixtral-8x7b    → Switch model (same provider)
/ki setup openai KEY gpt-4o → Switch to a different provider
```

---

## 7. Telegram Bridge — Setup & Usage

### 7.1 Prerequisites

1. Create a Telegram bot via [@BotFather](https://t.me/BotFather) on Telegram
2. Get the bot token (format: `123456789:ABCdef...`)
3. Get the target chat ID (send a message to the bot, then check `https://api.telegram.org/bot<TOKEN>/getUpdates`)

### 7.2 Setup

**One-line setup:**
```
/telegram setup 123456789:ABCdef_ghijk 987654321
```

Parameters: `<TELEGRAM_BOT_TOKEN> <CHAT_ID> [bridge|forward]`

**Step-by-step:**
```
/telegram setup          → Shows the 3-step guide:

Step 1: Create a Telegram bot via @BotFather
Step 2: Get your chat ID
Step 3: Run: /telegram setup <TOKEN> <CHAT_ID>
```

**Verify connection:**
```
/telegram test           → Calls Telegram getMe API
```

### 7.3 Bridge Modes

| Mode | Direction | Description |
|------|-----------|-------------|
| **bridge** | XMPP ↔ Telegram | Messages flow both ways. Telegram messages appear in XMPP with `[Telegram] Name:` prefix. XMPP messages appear in Telegram with `[XMPP] jid:` prefix. |
| **forward** | XMPP → Telegram | Messages only go from XMPP to Telegram. Telegram replies are not forwarded. |

```
/telegram mode bridge    → Set bidirectional mode
/telegram mode forward   → Set forward-only mode
```

### 7.4 Message Flow

```
┌─────────┐                          ┌──────────┐
│  XMPP   │  ──── bridge mode ────>  │ Telegram │
│  User   │  <─── bridge mode ─────  │  Chat    │
│         │  ──── forward mode ───>  │          │
└─────────┘                          └──────────┘

Incoming Telegram: [Telegram] John: Hello!
Outgoing to TG:    [XMPP] user@server: Hi there!
```

Polling interval: every 3 seconds. Telegram API timeout: 1 second.

### 7.5 Planned Features (Roadmap)

The Telegram Bridge is being extended with several powerful features.
All items below are **planned** and not yet implemented.

#### 7.5.1 Media Forwarding

Full media support between XMPP and Telegram:

| Media Type | XMPP → Telegram | Telegram → XMPP |
|------------|------------------|------------------|
| Images / Photos | Uploaded via Telegram Bot API `sendPhoto` | Downloaded and shared as XMPP HTTP Upload |
| Files / Documents | Uploaded via `sendDocument` | Downloaded and offered as file transfer |
| Stickers | Converted to image and sent | Sticker image extracted and displayed inline |
| Voice Messages | Audio file forwarded as `sendVoice` | Audio downloaded, playable in XMPP client |
| Video | Forwarded as `sendVideo` | Downloaded via HTTP Upload |

```
XMPP User sends image
       │
       ▼
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ DinoX Bot    │────>│ HTTP Upload  │────>│ Telegram API │
│ receives     │     │ download URL │     │ sendPhoto    │
│ XMPP file    │     │              │     │              │
└──────────────┘     └──────────────┘     └──────────────┘

Telegram User sends photo
       │
       ▼
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ Telegram Bot │────>│ getFile +    │────>│ XMPP HTTP    │
│ API polling  │     │ download     │     │ Upload slot  │
│              │     │              │     │ + send URL   │
└──────────────┘     └──────────────┘     └──────────────┘
```

**Technical Notes:**
- File size limits follow Telegram API limits (20 MB download, 50 MB upload)
- Stickers are converted from WebP to PNG for XMPP compatibility
- XMPP HTTP Upload (XEP-0363) is used for incoming Telegram media

#### 7.5.2 Multi-Chat Bridging

Bridge multiple Telegram groups simultaneously from a single bot:

```
/telegram add <CHAT_ID_1> [alias]    → Add a Telegram group
/telegram add <CHAT_ID_2> [alias]    → Add another group
/telegram list                        → Show all bridged groups
/telegram remove <CHAT_ID>           → Remove a bridge
```

**Routing:**
- Each Telegram group maps to a separate XMPP conversation or MUC room
- Messages include a group prefix: `[TG:GroupName] User: message`
- The bot owner can send to a specific group: `/telegram send <alias> Hello!`
- Default target group can be set: `/telegram default <alias>`

```
                    ┌──── Telegram Group A ("Family")
DinoX Bot ──────────┼──── Telegram Group B ("Work")
                    ├──── Telegram Group C ("Project")
                    └──── Telegram DM (User X)
```

**Use Cases:**
- Monitor multiple Telegram communities from one XMPP client
- Cross-post announcements to several groups at once
- Aggregate messages from different Telegram groups in one place

#### 7.5.3 Bot Commands in Telegram

Allow Telegram users to send commands directly to the DinoX bot:

| Command | Description |
|---------|-------------|
| `/status` | Bot shows online status and bridge info |
| `/help` | Lists available commands for Telegram users |
| `/info` | Shows bot version and uptime |
| `/who` | Shows who is online on the XMPP side |
| `/ping` | Latency check (bot responds with pong + ms) |

**Custom Commands:**
- Bot owner can define custom commands via the XMPP side
- Commands can trigger automated responses or actions
- Example: `/weather Berlin` could query an API and respond in Telegram

```
Telegram User                    DinoX Bot
     │                               │
     │  /status                      │
     │──────────────────────────────>│
     │                               │ (checks XMPP + Bridge state)
     │  Bot is online                │
     │  Bridge: active (2 groups)    │
     │  Uptime: 3d 12h              │
     │<──────────────────────────────│
```

#### 7.5.4 Inline Buttons / Keyboards

Telegram inline keyboards and reply keyboards for interactive bot responses:

**Reply Keyboards:**
```json
{
  "keyboard": [
    [{"text": "Status"}, {"text": "Help"}],
    [{"text": "Send to XMPP"}]
  ],
  "resize_keyboard": true
}
```

**Inline Keyboards with Callbacks:**
```json
{
  "inline_keyboard": [
    [
      {"text": "Bridge ON", "callback_data": "bridge_on"},
      {"text": "Bridge OFF", "callback_data": "bridge_off"}
    ],
    [
      {"text": "Settings", "callback_data": "settings"}
    ]
  ]
}
```

**Use Cases:**
- Quick-action buttons for common operations
- Confirmation dialogs ("Are you sure? [Yes] [No]")
- Navigation menus for bot settings directly in Telegram
- Polls and surveys forwarded from XMPP to Telegram

#### 7.5.5 Admin Features (Moderate Telegram via XMPP)

Manage Telegram groups directly from your XMPP client:

| Command (in XMPP) | Telegram Action |
|--------------------|-----------------|
| `/telegram kick @user` | Remove user from Telegram group |
| `/telegram ban @user [duration]` | Ban user (optionally temporary) |
| `/telegram unban @user` | Unban user |
| `/telegram mute @user [duration]` | Restrict user from posting |
| `/telegram pin <message_id>` | Pin a message in the group |
| `/telegram title <new_title>` | Change group title |
| `/telegram photo <url>` | Change group photo |
| `/telegram members` | List group members |

**Moderation Flow:**
```
XMPP Owner                    DinoX Bot                  Telegram Group
     │                           │                            │
     │ /telegram kick @spammer   │                            │
     │──────────────────────────>│                            │
     │                           │ banChatMember API call     │
     │                           │───────────────────────────>│
     │                           │          OK                │
     │                           │<───────────────────────────│
     │ User @spammer removed     │                            │
     │<──────────────────────────│                            │
```

**Auto-Moderation (planned):**
- Spam detection with configurable word filters
- Auto-ban for specific patterns or link spam
- Rate limiting (max messages per minute per user)
- Welcome messages for new group members
- Logging of all moderation actions in XMPP

---

## 8. HTTP API Reference

### 8.1 Authentication

All bot-specific endpoints require a **Bearer token** in the `Authorization` header:

```
Authorization: Bearer bm_a7f2c...e91d
```

**How to get a token:**
- Created automatically when you create a bot (`/newbot` or via UI)
- View with `/showtoken <ID>`
- Regenerate with `/token <ID>`
- Manage via UI (copy/regenerate/revoke buttons)

**Response format (authenticated endpoints):**

Success:
```json
{
  "ok": true,
  "result": { ... }
}
```

Error:
```json
{
  "ok": false,
  "error_code": "401",
  "description": "Unauthorized"
}
```

**Rate limiting:** 30 requests per second per IP.

### 8.2 API Server Configuration

| Setting | Local Mode | Network Mode |
|---------|-----------|--------------|
| Bind Address | `127.0.0.1` | `0.0.0.0` |
| Protocol | HTTP | HTTPS (TLS required) |
| Default Port | 7842 | 7842 |
| TLS Certificate | Not used | Auto-generated self-signed, or custom PEM |
| Access | This machine only | Any network client |

**Change settings:**
- Via Preferences UI (Settings > Botmother section)
- Via chat: `/api server local`, `/api server network`, `/api server port 8443`
- Changes are applied automatically (server restarts within 500ms)

**Self-signed TLS certificates** are automatically generated using GnuTLS and stored at:
```
~/.local/share/dinox/api-tls/server.crt
~/.local/share/dinox/api-tls/server.key
```

### 8.3 Bot Management Endpoints (No Auth)

These endpoints manage bots themselves. In local mode, they don't require authentication.

---

#### `GET /health`

Health check. No authentication required.

**Response:**
```json
{
  "status": "ok",
  "version": "1.0.0",
  "active_bots": 3
}
```

**curl:**
```bash
curl http://localhost:7842/health
```

---

#### `POST /bot/create`

Create a new bot.

**Request body:**
```json
{
  "name": "MyBot",
  "account": "user@server.tld",
  "mode": "personal",
  "avatar": "<base64-encoded-image>",
  "avatar_type": "image/png"
}
```

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `name` | Yes | — | Bot display name |
| `account` | Yes | — | Owner JID (also accepts `"owner"`) |
| `mode` | No | `"personal"` | `"personal"`, `"dedicated"`, or `"cloud"` |
| `avatar` | No | — | Base64-encoded avatar image |
| `avatar_type` | No | — | MIME type of avatar (e.g. `"image/png"`) |

**Response (personal):**
```json
{
  "id": 1,
  "name": "MyBot",
  "token": "bm_a7f2c...e91d",
  "mode": "personal",
  "api_url": "http://localhost:7842/bot/",
  "hint": "Use token as Bearer in Authorization header"
}
```

**Response (dedicated):**
```json
{
  "id": 2,
  "name": "SupportBot",
  "token": "bm_x9k4d...7b2e",
  "mode": "dedicated",
  "jid": "bot_supportbot_c3a1@chat.example.com",
  "api_url": "http://localhost:7842/bot/",
  "hint": "Use token as Bearer in Authorization header"
}
```

**Errors:** 400 (missing fields, invalid mode), 429 (max 20 bots per owner), 502 (ejabberd registration failed for dedicated)

**curl:**
```bash
curl -X POST http://localhost:7842/bot/create \
  -H "Content-Type: application/json" \
  -d '{"name":"MyBot","account":"ralf@chat.example.com","mode":"personal"}'
```

---

#### `GET /bot/list`

List all bots. Optional filter by owner account.

**Query parameters:**
| Parameter | Required | Description |
|-----------|----------|-------------|
| `account` | No | Filter by owner JID |

**Response:**
```json
{
  "bots": [
    {
      "id": 1,
      "name": "MyBot",
      "jid": "",
      "mode": "personal",
      "status": "active",
      "description": "",
      "created_at": 1739478000,
      "token": "bm_a7f2c...e91d"
    },
    {
      "id": 2,
      "name": "SupportBot",
      "jid": "bot_supportbot_c3a1@chat.example.com",
      "mode": "dedicated",
      "status": "active",
      "description": "Customer support",
      "created_at": 1739478100,
      "token": "bm_x9k4d...7b2e"
    }
  ]
}
```

**curl:**
```bash
# All bots
curl http://localhost:7842/bot/list

# Filter by account
curl "http://localhost:7842/bot/list?account=ralf@chat.example.com"
```

---

#### `POST /bot/delete` or `DELETE /bot/delete?id=<ID>`

Delete a bot. For dedicated bots, also unregisters the XMPP account from ejabberd.

**Request body (POST):**
```json
{
  "id": 3
}
```

**Response:**
```json
{
  "deleted": true,
  "id": 3
}
```

For dedicated bots:
```json
{
  "deleted": true,
  "id": 3,
  "account_removed": true
}
```

**curl:**
```bash
curl -X DELETE "http://localhost:7842/bot/delete?id=3"
# or
curl -X POST http://localhost:7842/bot/delete \
  -H "Content-Type: application/json" \
  -d '{"id":3}'
```

---

#### `POST /bot/activate`

Activate or deactivate a bot.

**Request body:**
```json
{
  "id": 1,
  "active": true
}
```

**Response:**
```json
{
  "id": 1,
  "status": "active"
}
```

**curl:**
```bash
curl -X POST http://localhost:7842/bot/activate \
  -H "Content-Type: application/json" \
  -d '{"id":1,"active":true}'
```

---

#### `POST /bot/token`

Regenerate API token for a bot (old token becomes invalid).

**Request body:**
```json
{
  "id": 1
}
```

**Response:**
```json
{
  "id": 1,
  "token": "bm_new_token_here"
}
```

---

#### `POST /bot/revoke`

Revoke token and disable bot.

**Request body:**
```json
{
  "id": 1
}
```

**Response:**
```json
{
  "id": 1,
  "revoked": true,
  "status": "disabled"
}
```

---

#### `GET/POST /bot/account/status`

Check or toggle whether Botmother is enabled for a specific account.

**GET:** `?account=user@server`
```json
{
  "account": "user@server",
  "enabled": true
}
```

**POST:**
```json
{
  "account": "user@server",
  "enabled": false
}
```

---

### 8.4 Bot Messaging Endpoints (Auth Required)

All endpoints below require the `Authorization: Bearer <TOKEN>` header.

---

#### `POST /bot/sendMessage`

Send a message to a JID.

**Request body:**
```json
{
  "to": "user@server.tld",
  "text": "Hello from my bot!",
  "type": "chat"
}
```

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `to` | Yes | — | Recipient JID |
| `text` | Yes | — | Message text |
| `type` | No | `"chat"` | `"chat"` (1:1) or `"groupchat"` (MUC) |

**Response:**
```json
{
  "ok": true,
  "result": {
    "message_id": "uuid-123-456"
  }
}
```

**curl:**
```bash
curl -X POST http://localhost:7842/bot/sendMessage \
  -H "Authorization: Bearer bm_YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"to":"user@server.tld","text":"Hello!"}'
```

---

#### `GET /bot/getUpdates`

Long-poll for incoming messages (alternative to webhooks).

**Query parameters:**
| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `offset` | No | — | Return updates with ID > offset. Also deletes acknowledged updates. |
| `limit` | No | 100 | Max updates to return (1-100) |

**Response:**
```json
{
  "ok": true,
  "result": [
    {
      "update_id": 42,
      "type": "message",
      "data": {
        "from": "sender@server.tld",
        "to": "bot@server.tld",
        "body": "Hello bot!",
        "type": "chat",
        "stanza_id": "msg-uuid-789",
        "timestamp": 1707900000
      }
    }
  ]
}
```

**Usage pattern:**
```bash
# First call — get all pending updates
curl "http://localhost:7842/bot/getUpdates" \
  -H "Authorization: Bearer bm_YOUR_TOKEN"

# Next call — acknowledge update 42, get newer ones
curl "http://localhost:7842/bot/getUpdates?offset=43" \
  -H "Authorization: Bearer bm_YOUR_TOKEN"
```

---

#### `GET /bot/getMe`

Get information about the authenticated bot.

**Response:**
```json
{
  "ok": true,
  "result": {
    "id": 1,
    "name": "MyBot",
    "jid": "",
    "mode": "personal",
    "status": "active",
    "description": "",
    "created_at": 1739478000,
    "token": "bm_a7f2c...e91d"
  }
}
```

---

#### `GET /bot/getInfo`

Extended bot information including commands and active sessions.

**Response:**
```json
{
  "ok": true,
  "result": {
    "bot": {
      "id": 1,
      "name": "MyBot",
      "mode": "personal",
      "status": "active"
    },
    "commands": [
      {"command": "weather", "description": "Get weather info"},
      {"command": "help", "description": "Show help"}
    ],
    "active_sessions": 0
  }
}
```

---

### 8.5 Webhook System

Instead of polling with `getUpdates`, you can set up a webhook to receive messages via HTTP POST.

#### `POST /bot/setWebhook`

**Request body:**
```json
{
  "url": "https://my-server.com/webhook/bot1"
}
```

**Response:**
```json
{
  "ok": true,
  "result": {
    "webhook_url": "https://my-server.com/webhook/bot1",
    "secret": "hmac_secret_for_signature_verification"
  }
}
```

> **Important:** Save the `secret` — it's used to verify webhook signatures.

#### `POST /bot/deleteWebhook`

No body required.

**Response:**
```json
{
  "ok": true,
  "result": true
}
```

#### Webhook Delivery Format

DinoX sends incoming messages as HTTP POST to your webhook URL:

**Headers:**
```
Content-Type: application/json
User-Agent: DinoX-BotAPI/1.0
X-Bot-Signature: sha256=<HMAC-SHA256(secret, payload)>
X-Bot-Delivery: <unique-uuid>
```

**Body:**
```json
{
  "update_type": "message",
  "data": {
    "from": "sender@server.tld",
    "to": "bot@server.tld",
    "body": "Hello!",
    "type": "chat",
    "stanza_id": "msg-uuid-123",
    "timestamp": 1707900000
  }
}
```

**Retry behavior:** Up to 3 attempts with exponential backoff (1s, 2s, 4s). Timeout: 10 seconds per attempt.

#### Verify Webhook Signature (Python)

```python
import hmac
import hashlib

def verify_signature(payload: bytes, signature: str, secret: str) -> bool:
    expected = "sha256=" + hmac.new(
        secret.encode(), payload, hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(expected, signature)

# In your webhook handler:
signature = request.headers.get("X-Bot-Signature")
is_valid = verify_signature(request.body, signature, YOUR_WEBHOOK_SECRET)
```

---

### 8.6 Advanced Endpoints

All require `Authorization: Bearer <TOKEN>`.

---

#### `POST /bot/sendFile`

Send a file via OOB (Out-of-Band Data, XEP-0066).

**Request body:**
```json
{
  "to": "user@server.tld",
  "url": "https://example.com/photo.jpg",
  "caption": "Check out this photo!"
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `to` | Yes | Recipient JID |
| `url` | Yes | URL of the file to send |
| `caption` | No | Text caption alongside the file |

---

#### `POST /bot/sendReaction`

Send a reaction (emoji) to a specific message.

**Request body:**
```json
{
  "to": "user@server.tld",
  "message_id": "msg-uuid-123",
  "reaction": "👍"
}
```

---

#### `POST /bot/joinRoom`

Join a MUC (Multi-User Chat) room.

**Request body:**
```json
{
  "room": "general@conference.server.tld",
  "nick": "MyBot"
}
```

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `room` | Yes | — | Room JID |
| `nick` | No | Bot name | Nickname in the room |

---

#### `POST /bot/leaveRoom`

Leave a MUC room.

**Request body:**
```json
{
  "room": "general@conference.server.tld"
}
```

---

#### `POST /bot/setCommands`

Register custom slash commands for the bot.

**Request body:**
```json
{
  "commands": [
    {"command": "weather", "description": "Get weather for a city"},
    {"command": "news", "description": "Show latest news"},
    {"command": "help", "description": "Show available commands"}
  ]
}
```

---

#### `GET /bot/getCommands`

Get the list of registered commands.

**Response:**
```json
{
  "ok": true,
  "result": [
    {"command": "weather", "description": "Get weather for a city"},
    {"command": "news", "description": "Show latest news"}
  ]
}
```

---

### 8.7 ejabberd Admin Endpoints

These endpoints manage the ejabberd server connection for dedicated bots.

#### `GET /bot/ejabberd/settings`

Get current ejabberd configuration (password is masked).

**Response:**
```json
{
  "api_url": "http://localhost:5443/api",
  "admin_jid": "admin@chat.example.com",
  "admin_password": "********",
  "host": "chat.example.com",
  "configured": true
}
```

#### `POST /bot/ejabberd/settings`

Save ejabberd configuration.

**Request body:**
```json
{
  "api_url": "http://localhost:5443/api",
  "admin_jid": "admin@chat.example.com",
  "admin_password": "your_password",
  "host": "chat.example.com"
}
```

**Response:**
```json
{
  "saved": true,
  "configured": true
}
```

#### `POST /bot/ejabberd/test`

Test ejabberd API connectivity.

**Response:**
```json
{
  "connected": true,
  "response": "ok"
}
```

---

### 8.8 Telegram API Endpoints

All endpoints require `Authorization: Bearer <TOKEN>`.

---

#### `POST /bot/telegram/setup`

Configure the Telegram bridge for a bot.

**Request body:**
```json
{
  "token": "123456789:ABCdef_ghijk",
  "chat_id": "987654321",
  "mode": "bridge"
}
```

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `token` | Yes | -- | Telegram Bot API token |
| `chat_id` | Yes | -- | Target Telegram chat ID |
| `mode` | No | `"bridge"` | `"bridge"` (bidirectional) or `"forward"` (XMPP -> TG only) |

**Response:**
```json
{
  "configured": true,
  "chat_id": "987654321",
  "mode": "bridge"
}
```

**curl:**
```bash
curl -X POST http://localhost:7842/bot/telegram/setup \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"token":"123456:ABC","chat_id":"987654321","mode":"bridge"}'
```

---

#### `GET /bot/telegram/status`

Get Telegram bridge status for a bot.

**Response:**
```json
{
  "enabled": true,
  "configured": true,
  "chat_id": "987654321",
  "mode": "bridge"
}
```

**curl:**
```bash
curl http://localhost:7842/bot/telegram/status \
  -H "Authorization: Bearer $TOKEN"
```

---

#### `POST /bot/telegram/enable`

Enable or disable the Telegram bridge.

**Request body:**
```json
{
  "enabled": true
}
```

**Response:**
```json
{
  "enabled": true
}
```

**curl:**
```bash
curl -X POST http://localhost:7842/bot/telegram/enable \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"enabled":true}'
```

---

#### `POST /bot/telegram/send`

Send a message to Telegram via the bridge.

**Request body:**
```json
{
  "text": "Hello from the API!"
}
```

**Response:**
```json
{
  "sent": true
}
```

**curl:**
```bash
curl -X POST http://localhost:7842/bot/telegram/send \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"text":"Hello Telegram!"}'
```

---

#### `POST /bot/telegram/test`

Test the Telegram bot token (calls Telegram `getMe` API).

**Response:**
```json
{
  "connected": true,
  "info": "Telegram verbunden!\nBot: MyBot (@mybot_bot)"
}
```

**curl:**
```bash
curl -X POST http://localhost:7842/bot/telegram/test \
  -H "Authorization: Bearer $TOKEN"
```

---

### 8.9 AI API Endpoints

All endpoints require `Authorization: Bearer <TOKEN>`.

---

#### `POST /bot/ai/setup`

Configure the AI provider for a bot.

**Request body:**
```json
{
  "provider": "openai",
  "api_key": "sk-abc123",
  "model": "gpt-4o"
}
```

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `provider` | Yes | -- | Provider name (openai, claude, gemini, groq, mistral, deepseek, perplexity, ollama, openclaw) |
| `api_key` | No | `"-"` | API key (use `"-"` for Ollama) |
| `model` | Yes | -- | Model name (e.g. `gpt-4o`, `llama3`, `agent`) |

**Response:**
```json
{
  "configured": true,
  "provider": "openai",
  "model": "gpt-4o"
}
```

**curl:**
```bash
curl -X POST http://localhost:7842/bot/ai/setup \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"provider":"groq","api_key":"gsk_abc","model":"llama-3.3-70b-versatile"}'
```

---

#### `GET /bot/ai/status`

Get AI configuration status.

**Response:**
```json
{
  "enabled": true,
  "configured": true,
  "type": "openai",
  "model": "gpt-4o",
  "endpoint": "https://api.openai.com/v1/chat/completions"
}
```

**curl:**
```bash
curl http://localhost:7842/bot/ai/status \
  -H "Authorization: Bearer $TOKEN"
```

---

#### `POST /bot/ai/enable`

Enable or disable the AI for a bot.

**Request body:**
```json
{
  "enabled": true
}
```

**Response:**
```json
{
  "enabled": true
}
```

---

#### `POST /bot/ai/ask`

Send a question to the AI and get a response.

**Request body:**
```json
{
  "message": "What is the capital of France?"
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `message` | Yes | The question or prompt (also accepts `"text"`) |
| `from` (query) | No | Sender identifier for conversation history (default: `"api-client"`) |

**Response:**
```json
{
  "response": "The capital of France is Paris."
}
```

**curl:**
```bash
curl -X POST http://localhost:7842/bot/ai/ask \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"message":"What is the capital of France?"}'
```

---

### 8.10 Complete curl Examples

```bash
# === SETUP ===

# Check server health
curl http://localhost:7842/health

# Create a personal bot
curl -X POST http://localhost:7842/bot/create \
  -H "Content-Type: application/json" \
  -d '{"name":"MyBot","account":"ralf@chat.example.com"}'

# Create a dedicated bot (requires ejabberd)
curl -X POST http://localhost:7842/bot/create \
  -H "Content-Type: application/json" \
  -d '{"name":"SupportBot","account":"ralf@chat.example.com","mode":"dedicated"}'

# List all bots
curl http://localhost:7842/bot/list

# === MESSAGING ===

TOKEN="bm_YOUR_TOKEN_HERE"

# Send a message
curl -X POST http://localhost:7842/bot/sendMessage \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"to":"user@chat.example.com","text":"Hello from the API!"}'

# Send a file
curl -X POST http://localhost:7842/bot/sendFile \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"to":"user@chat.example.com","url":"https://example.com/image.jpg","caption":"Look!"}'

# Send a reaction
curl -X POST http://localhost:7842/bot/sendReaction \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"to":"user@chat.example.com","message_id":"msg-uuid","reaction":"👍"}'

# Get incoming messages (polling)
curl "http://localhost:7842/bot/getUpdates" \
  -H "Authorization: Bearer $TOKEN"

# Acknowledge and get next
curl "http://localhost:7842/bot/getUpdates?offset=43" \
  -H "Authorization: Bearer $TOKEN"

# === WEBHOOKS ===

# Set webhook
curl -X POST http://localhost:7842/bot/setWebhook \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"url":"https://my-server.com/webhook"}'

# Delete webhook
curl -X POST http://localhost:7842/bot/deleteWebhook \
  -H "Authorization: Bearer $TOKEN"

# === ROOMS ===

# Join a MUC room
curl -X POST http://localhost:7842/bot/joinRoom \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"room":"general@conference.chat.example.com","nick":"MyBot"}'

# Leave a room
curl -X POST http://localhost:7842/bot/leaveRoom \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"room":"general@conference.chat.example.com"}'

# === COMMANDS ===

# Register bot commands
curl -X POST http://localhost:7842/bot/setCommands \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"commands":[{"command":"help","description":"Show help"},{"command":"weather","description":"Get weather"}]}'

# Get registered commands
curl "http://localhost:7842/bot/getCommands" \
  -H "Authorization: Bearer $TOKEN"

# === BOT INFO ===

# Get bot info
curl "http://localhost:7842/bot/getMe" \
  -H "Authorization: Bearer $TOKEN"

# Get extended info
curl "http://localhost:7842/bot/getInfo" \
  -H "Authorization: Bearer $TOKEN"

# === MANAGEMENT ===

# Regenerate token
curl -X POST http://localhost:7842/bot/token \
  -H "Content-Type: application/json" \
  -d '{"id":1}'

# Revoke token
curl -X POST http://localhost:7842/bot/revoke \
  -H "Content-Type: application/json" \
  -d '{"id":1}'

# Activate bot
curl -X POST http://localhost:7842/bot/activate \
  -H "Content-Type: application/json" \
  -d '{"id":1,"active":true}'

# Deactivate bot
curl -X POST http://localhost:7842/bot/activate \
  -H "Content-Type: application/json" \
  -d '{"id":1,"active":false}'

# Delete bot
curl -X DELETE "http://localhost:7842/bot/delete?id=1"

# === TELEGRAM BRIDGE ===

# Setup Telegram bridge
curl -X POST http://localhost:7842/bot/telegram/setup \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"token":"123456:ABC-DEF","chat_id":"987654321","mode":"bridge"}'

# Check Telegram status
curl http://localhost:7842/bot/telegram/status \
  -H "Authorization: Bearer $TOKEN"

# Enable/disable Telegram
curl -X POST http://localhost:7842/bot/telegram/enable \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"enabled":true}'

# Send message to Telegram
curl -X POST http://localhost:7842/bot/telegram/send \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"text":"Hello Telegram!"}'

# Test Telegram connection
curl -X POST http://localhost:7842/bot/telegram/test \
  -H "Authorization: Bearer $TOKEN"

# === AI ===

# Setup AI provider
curl -X POST http://localhost:7842/bot/ai/setup \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"provider":"groq","api_key":"gsk_abc","model":"llama-3.3-70b-versatile"}'

# Setup OpenClaw
curl -X POST http://localhost:7842/bot/ai/setup \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"provider":"openclaw","api_key":"oc_token","model":"agent"}'

# Check AI status
curl http://localhost:7842/bot/ai/status \
  -H "Authorization: Bearer $TOKEN"

# Enable AI
curl -X POST http://localhost:7842/bot/ai/enable \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"enabled":true}'

# Ask the AI a question
curl -X POST http://localhost:7842/bot/ai/ask \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"message":"What is quantum computing?"}'
```

### 8.11 Python Examples

#### Simple Bot (Polling)

```python
import requests
import time

API_URL = "http://localhost:7842"
TOKEN = "bm_YOUR_TOKEN_HERE"
HEADERS = {
    "Authorization": f"Bearer {TOKEN}",
    "Content-Type": "application/json"
}

def send_message(to: str, text: str):
    """Send a message to a JID."""
    r = requests.post(f"{API_URL}/bot/sendMessage",
                      headers=HEADERS,
                      json={"to": to, "text": text})
    return r.json()

def get_updates(offset: int = 0):
    """Poll for incoming messages."""
    r = requests.get(f"{API_URL}/bot/getUpdates",
                     headers=HEADERS,
                     params={"offset": offset} if offset else {})
    return r.json()

# Main polling loop
offset = 0
print("Bot started. Waiting for messages...")

while True:
    response = get_updates(offset)

    if response.get("ok"):
        updates = response.get("result", [])
        for update in updates:
            update_id = update["update_id"]
            data = update["data"]
            sender = data["from"]
            text = data.get("body", "")

            print(f"Message from {sender}: {text}")

            # Echo bot: repeat back what was said
            send_message(sender, f"You said: {text}")

            offset = update_id + 1

    time.sleep(2)
```

#### Webhook Bot (Flask)

```python
import hmac
import hashlib
import json
import requests
from flask import Flask, request, jsonify

app = Flask(__name__)

API_URL = "http://localhost:7842"
TOKEN = "bm_YOUR_TOKEN_HERE"
WEBHOOK_SECRET = "your_webhook_secret"
HEADERS = {
    "Authorization": f"Bearer {TOKEN}",
    "Content-Type": "application/json"
}

def verify_signature(payload: bytes, signature: str) -> bool:
    """Verify the webhook signature."""
    expected = "sha256=" + hmac.new(
        WEBHOOK_SECRET.encode(), payload, hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(expected, signature)

def send_message(to: str, text: str):
    """Send a reply."""
    requests.post(f"{API_URL}/bot/sendMessage",
                  headers=HEADERS,
                  json={"to": to, "text": text})

@app.route("/webhook", methods=["POST"])
def handle_webhook():
    signature = request.headers.get("X-Bot-Signature", "")
    if not verify_signature(request.data, signature):
        return jsonify({"error": "invalid signature"}), 403

    data = request.json
    if data.get("update_type") == "message":
        msg = data["data"]
        sender = msg["from"]
        text = msg.get("body", "")

        # Process the message
        if text.lower() == "ping":
            send_message(sender, "Pong! 🏓")
        else:
            send_message(sender, f"Received: {text}")

    return jsonify({"ok": True})

if __name__ == "__main__":
    # Register webhook first
    r = requests.post(f"{API_URL}/bot/setWebhook",
                      headers=HEADERS,
                      json={"url": "https://your-server.com/webhook"})
    print(f"Webhook registered: {r.json()}")

    app.run(host="0.0.0.0", port=5000)
```

#### Bot with Commands

```python
import requests

API_URL = "http://localhost:7842"
TOKEN = "bm_YOUR_TOKEN_HERE"
HEADERS = {
    "Authorization": f"Bearer {TOKEN}",
    "Content-Type": "application/json"
}

# Register commands
commands = [
    {"command": "hello", "description": "Get a greeting"},
    {"command": "time",  "description": "Get current time"},
    {"command": "help",  "description": "Show available commands"}
]

requests.post(f"{API_URL}/bot/setCommands",
              headers=HEADERS,
              json={"commands": commands})

# Handle commands in your polling/webhook handler
def handle_command(sender: str, text: str):
    if text == "/hello":
        return "Hello! Nice to meet you! 👋"
    elif text == "/time":
        from datetime import datetime
        return f"Current time: {datetime.now().strftime('%H:%M:%S')}"
    elif text == "/help":
        return "Available commands:\n/hello - Get a greeting\n/time - Get current time\n/help - This message"
    else:
        return f"Unknown command: {text}"
```

---

## 9. Settings Reference

### 9.1 Application Settings (Preferences)

These settings are in DinoX Preferences > Botmother section and apply globally.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `bot_features_enabled` | Boolean | `false` | Master toggle for the entire Botmother system |
| `api_mode` | String | `"local"` | `"local"` (HTTP on 127.0.0.1) or `"network"` (HTTPS on 0.0.0.0) |
| `api_port` | Integer | `7842` | API server port (1024-65535) |
| `api_tls_cert` | String | `""` | Custom TLS certificate path (empty = auto-generate) |
| `api_tls_key` | String | `""` | Custom TLS key path (empty = auto-generate) |

### 9.2 Per-Bot Settings (Database)

These are stored in the bot registry database (`~/.local/share/dinox/bot_registry.db`) in the `settings` table.

**AI settings per bot:**

| Key | Values | Description |
|-----|--------|-------------|
| `bot_{id}_ai_enabled` | `"true"` / `"false"` | AI active for this bot |
| `bot_{id}_ai_type` | `"openai"`, `"claude"`, `"gemini"`, `"groq"`, `"mistral"`, `"deepseek"`, `"perplexity"`, `"ollama"`, `"openclaw"` | AI provider type |
| `bot_{id}_ai_endpoint` | URL | Provider API endpoint |
| `bot_{id}_ai_key` | String | API key (empty for Ollama) |
| `bot_{id}_ai_model` | String | Model name |
| `bot_{id}_ai_system` | String | System prompt |

**Telegram settings per bot:**

| Key | Values | Description |
|-----|--------|-------------|
| `bot_{id}_tg_enabled` | `"true"` / `"false"` | Telegram bridge active |
| `bot_{id}_tg_token` | String | Telegram Bot API token |
| `bot_{id}_tg_chat_id` | String | Target Telegram chat ID |
| `bot_{id}_tg_mode` | `"bridge"` / `"forward"` | Bridge mode |

**Account settings:**

| Key | Values | Description |
|-----|--------|-------------|
| `botmother_account_enabled:{jid}` | `"true"` / `"false"` | Botmother enabled for account |

**ejabberd settings:**

| Key | Values | Description |
|-----|--------|-------------|
| `ejabberd_api_url` | URL | ejabberd REST API URL |
| `ejabberd_host` | String | XMPP server hostname |
| `ejabberd_admin_jid` | String | Admin JID |
| `ejabberd_admin_password` | String | Admin password |

---

## 10. Database Schema

**Location:** `~/.local/share/dinox/bot_registry.db` (SQLite, WAL mode)

**Current version:** 3

### Tables

#### `bot`

| Column | Type | Description |
|--------|------|-------------|
| `id` | INTEGER PK | Auto-increment bot ID |
| `name` | TEXT | Display name |
| `jid` | TEXT | Bot's XMPP JID (dedicated mode only) |
| `token_hash` | TEXT UNIQUE | SHA-256 hash of the API token |
| `token_raw` | TEXT | Raw API token (stored since DB v2) |
| `owner_jid` | TEXT | Owner's XMPP JID |
| `description` | TEXT | Bot description |
| `permissions` | TEXT | Permission level (default: `"all"`) |
| `status` | TEXT | `"active"` or `"disabled"` |
| `mode` | TEXT | `"personal"`, `"dedicated"`, or `"cloud"` |
| `created_at` | INTEGER | Unix timestamp of creation |
| `last_active` | INTEGER | Unix timestamp of last activity |
| `webhook_url` | TEXT | Webhook delivery URL |
| `webhook_secret` | TEXT | HMAC-SHA256 secret |
| `webhook_enabled` | INTEGER | 0 or 1 |
| `bot_password` | TEXT | XMPP password (dedicated mode, added in DB v3) |

#### `bot_command`

| Column | Type | Description |
|--------|------|-------------|
| `id` | INTEGER PK | Auto-increment |
| `bot_id` | INTEGER | Foreign key to `bot.id` |
| `command` | TEXT | Command name (without `/`) |
| `description` | TEXT | Command description |

#### `update_queue`

| Column | Type | Description |
|--------|------|-------------|
| `id` | INTEGER PK | Auto-increment update ID |
| `bot_id` | INTEGER | Foreign key to `bot.id` |
| `update_type` | TEXT | e.g. `"message"` |
| `payload` | TEXT | JSON payload |
| `created_at` | INTEGER | Unix timestamp |

#### `settings`

| Column | Type | Description |
|--------|------|-------------|
| `key` | TEXT PK | Setting key |
| `value` | TEXT | Setting value |

#### `audit_log`

| Column | Type | Description |
|--------|------|-------------|
| `id` | INTEGER PK | Auto-increment |
| `bot_id` | INTEGER | Related bot ID |
| `action` | TEXT | Action name (e.g. `"create"`, `"delete"`, `"token_regen"`) |
| `details` | TEXT | Action details |
| `ip_address` | TEXT | Client IP |
| `timestamp` | INTEGER | Unix timestamp |

---

## 11. DinoX Bot Server (Cloud Mode) — Coming Soon

> **Status: In Development**
>
> Cloud mode is the third bot mode alongside Personal and Dedicated. While the API already accepts `"mode": "cloud"` when creating bots, the full server-side infrastructure is not yet implemented.

### Current Bot Modes vs. Cloud

| Feature | Personal | Dedicated | Cloud (planned) |
|---------|----------|-----------|-----------------|
| Own XMPP account | No (shares yours) | Yes | Yes |
| Own XMPP stream | No | Yes | Yes |
| Requires DinoX running | Yes | Yes | **No** |
| Requires ejabberd API | No | Yes | Yes |
| Survives app restart | Session only | Yes | **Yes** |
| Multi-user bots | No | Owner only | **Yes** |
| Scalable | No | Limited | **Yes** |
| OMEMO encryption | Via owner | Own keys | **Own keys** |
| Administration | Chat + UI | Chat + UI + API | **API + Web Panel** |

### Planned Cloud Features

**1. Standalone Bot Server**
- Bots run as a server-side service independent of the DinoX desktop app
- The API server runs as a standalone daemon/process
- Bots stay online 24/7 without requiring DinoX to be open

**2. Multi-Tenant Architecture**
- Multiple users can create and manage bots on the same server
- Per-user quotas and permissions
- Shared infrastructure with isolated bot instances

**3. Web Administration Panel**
- Browser-based dashboard for bot management
- Real-time monitoring of bot activity and metrics
- Log viewer and analytics
- No DinoX app required for administration

**4. Enhanced Scalability**
- Connection pooling for XMPP streams
- Load balancing across multiple bot instances
- Horizontal scaling for high-traffic bots
- Message queue integration (for high throughput)

**5. Advanced Bot Features**
- Scheduled messages and cron-like triggers
- Bot-to-bot communication
- Persistent conversation state (beyond in-memory)
- Plugin system for custom bot logic
- File storage and media handling

**6. Deployment Options**
- Docker container with docker-compose setup
- Systemd service for Linux servers
- Configuration via environment variables or config file
- Prometheus metrics endpoint for monitoring

### How Cloud Mode Will Work

```
┌──────────────────────────────────────────────────┐
│              DinoX Bot Server                    │
│                                                  │
│  ┌──────────────┐  ┌─────────────────────────┐   │
│  │ HTTP API     │  │ XMPP Connection Manager │   │
│  │ (REST +      │  │  - Bot streams           │  │
│  │  WebSocket)  │  │  - OMEMO per bot         │  │
│  └──────┬───────┘  │  - Auto-reconnect        │  │
│         │          └──────────┬──────────────┘   │
│         │                    │                   │
│  ┌──────┴────────────────────┴──────────────┐    │
│  │            Bot Runtime Engine             │   │
│  │  - Message routing                        │   │
│  │  - AI integration                         │   │
│  │  - Telegram bridge                        │   │
│  │  - Webhook dispatch                       │   │
│  │  - Command handling                       │   │
│  └──────────────────────────────────────────┘    │
│                                                  │
│  ┌──────────────┐  ┌────────────────────────┐    │
│  │ Database     │  │ Web Admin Panel        │    │
│  │ (PostgreSQL  │  │ (Vue.js / React)       │    │
│  │  or SQLite)  │  │                        │    │
│  └──────────────┘  └────────────────────────┘    │
└──────────────────────────────────────────────────┘
```

### Migration Path

When Cloud mode is ready, existing bots can be migrated:

1. **Personal → Cloud**: Bot gets its own XMPP account, moves to the server
2. **Dedicated → Cloud**: Bot stream transferred to server management
3. **Cloud → Dedicated**: Bot moved back to local DinoX management

The API remains backward-compatible — existing tokens and endpoints will continue to work.

---

## 12. OpenClaw Integration

> **Status: Basic integration implemented (v1.1)**
>
> OpenClaw is available as the 9th AI provider. The agent webhook API
> (`POST /hooks/agent`) is fully supported. Direction 1 (OpenClaw connects
> to DinoX as XMPP client) is planned for a future release.

OpenClaw (https://openclaw.ai/) is a **self-hosted autonomous AI agent** —
not an AI itself, but an orchestrator that manages AI models (Claude, GPT,
Ollama, ...) and uses them as tools. Think of n8n without UI, on steroids.
It runs on your PC or VPS, acts proactively, browses the web, runs commands,
has persistent memory, and manages its own skills and automations.

**OpenClaw is NOT an AI provider.** The 8 providers in Chapter 6 are passive
language models (a brain). OpenClaw is an active agent with hands and eyes
(like a worker that uses those brains). It decides which model to use, when
to browse, when to run a shell command, and when to reach out proactively.

### How the Connection Works

There are two directions — same pattern as Telegram:

**Direction 1: OpenClaw connects to DinoX (like Telegram)**

With Telegram, you create a bot via @BotFather, get a token, and give it to
OpenClaw. OpenClaw connects itself and listens for messages. The same model
could work for XMPP — give OpenClaw the bot's JID and credentials, and it
connects as an XMPP client.

**Direction 2: DinoX connects to OpenClaw (via Webhook API)**

OpenClaw exposes a webhook endpoint. DinoX sends messages to it, gets
responses back. This works today with OpenClaw's existing API:

```bash
# Send a message to OpenClaw and get a response
curl -X POST http://localhost:18789/hooks/agent \
  -H "Authorization: Bearer <OPENCLAW_HOOKS_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"message": "Check if my website is online"}'
```

This is the same pattern as our existing AI providers: text in, text out.
The difference is that OpenClaw might browse the web, run commands, or
use multiple AI models internally before responding.

### What DinoX Needs

The integration is minimal — our existing bot architecture already handles
this pattern:

1. A new provider entry `"openclaw"` in the `/ki` menu
2. URL field for the OpenClaw Gateway (default: `http://localhost:18789`)
3. Token field for the webhook auth token
4. Send user messages as `POST /hooks/agent` requests
5. Display responses in the bot chat

```
/ki provider openclaw
/ki url http://localhost:18789
/ki token <OPENCLAW_HOOKS_TOKEN>
/ki on
```

That is all. OpenClaw handles everything else internally — models, tools,
memory, skills, automations. DinoX does not manage or configure any of it.

### Requirements

- OpenClaw installed and running (`npm install -g openclaw@latest`)
- Node.js >= 22 on the OpenClaw host
- Network access from DinoX to OpenClaw Gateway (port 18789)
- Webhook hooks enabled in OpenClaw config with a token

For OpenClaw setup, configuration, and usage details, see the official docs:
https://docs.openclaw.ai/

---

*This document covers DinoX Botmother version 1.1.x. For updates, see the [CHANGELOG](CHANGELOG.md).*
