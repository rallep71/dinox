# Debugging DinoX

DinoX has extensive built-in debug logging across all subsystems. This guide covers how to capture and analyze logs on every supported platform.

---

## Quick Start

| Platform | Command |
|----------|---------|
| **Linux (build)** | `DINO_LOG_LEVEL=debug ./build/main/dinox` |
| **Flatpak** | `flatpak run --env=DINO_LOG_LEVEL=debug im.github.rallep71.DinoX` |
| **AppImage** | `DINO_LOG_LEVEL=debug ./DinoX-*.AppImage` |
| **Windows** | `set DINO_LOG_LEVEL=debug` then `dinox.exe > dinox.log 2>&1` |

---

## Environment Variables

| Variable | Values | Purpose |
|----------|--------|---------|
| `DINO_LOG_LEVEL` | `error`, `warning`, `info` (default), `debug` | Controls DinoX application log verbosity |
| `G_MESSAGES_DEBUG` | `all` or specific domain(s) | GLib log domain filter. Set to `all` to see all domains |
| `GST_DEBUG` | `0`–`9`, or per-element patterns | GStreamer pipeline debug level |

### Log Levels

| Level | What it shows |
|-------|---------------|
| `error` | Fatal errors only |
| `warning` | Errors + warnings |
| `info` | General information (default) |
| `debug` | Full detail — recommended for bug reports |

### GLib Log Domains

DinoX uses dedicated log domains per module. You can filter with `G_MESSAGES_DEBUG`:

| Domain | Module |
|--------|--------|
| `dino` | Main UI application |
| `libdino` | Core library (connection, encryption, certificate pinning, services) |
| `xmpp-vala` | XMPP protocol (SASL/SCRAM, TLS, XEPs, OpenPGP key ops) |
| `qlite` | Database layer (SQLite/SQLCipher) |
| `crypto-vala` | Cryptographic operations |
| `OMEMO` | OMEMO encryption plugin |
| `OpenPGP` | OpenPGP encryption plugin |
| `rtp` | Audio/video calls (RTP/Jingle) |
| `ice` | ICE/DTLS-SRTP (call transport) |
| `bot-features` | Botmother bot framework (Telegram, AI, webhooks) |

Example — show only OMEMO and connection logs:

```bash
G_MESSAGES_DEBUG="OMEMO,libdino" DINO_LOG_LEVEL=debug ./build/main/dinox
```

---

## Helper Scripts

DinoX includes scripts for reproducible debugging sessions:

### Start a Debug Session

```bash
scripts/run-dinox-debug.sh
```

This automatically:
- Sets `DINO_LOG_LEVEL=debug`, `GST_DEBUG=3`, `G_MESSAGES_DEBUG=all`
- Writes a timestamped log file under `logs/`
- Records PID to `logs/dinox.pid`
- Links latest log in `logs/dinox-runinfo-latest.txt`

Override defaults:

```bash
GST_DEBUG=5 scripts/run-dinox-debug.sh          # More GStreamer detail
scripts/run-dinox-debug.sh --restart             # Stop running instance first
```

### Stop DinoX

```bash
scripts/stop-dinox.sh
```

Sends `SIGINT` (clean shutdown), falls back to `SIGTERM` after 2 seconds.

### Scan Latest Log

```bash
scripts/scan-dinox-latest-log.sh
```

Searches the latest log for:
- Warnings, errors, critical messages
- Audio underflows / discontinuities
- ICE/DTLS startup buffering
- libnice TURN refresh warnings

---

## Debugging by Subsystem

### Connection & TLS

Debug connection lifecycle, DNS resolution, TLS handshake, and certificate verification:

```bash
G_MESSAGES_DEBUG="libdino,xmpp-vala" DINO_LOG_LEVEL=debug ./build/main/dinox 2>&1 | grep -iE "connection|stream|tls|dns|srv|sasl|certificate|pinned"
```

**What's logged:**
- Connect attempts, disconnects, reconnections with retry timing
- DNS SRV record resolution (`_xmpp-client._tcp`, `_xmpps-client._tcp`)
- TLS certificate validation (trust flags, `.onion` exceptions)
- Certificate pinning (pin/unpin, fingerprint comparison)
- StartTLS handshake, proxy resolver setup
- SASL mechanism selection and authentication (see [SASL / SCRAM](#sasl--scram-authentication) below)
- Network monitor online/offline state changes
- Suspend/resume handling

### SASL / SCRAM Authentication

Debug SCRAM mechanism negotiation, channel binding, and downgrade protection:

```bash
G_MESSAGES_DEBUG="xmpp-vala" DINO_LOG_LEVEL=debug ./build/main/dinox 2>&1 | grep -i "SASL:"
```

**What's logged (debug level):**
- **Mechanism discovery**: `SASL: Server offers: SCRAM-SHA-512-PLUS, SCRAM-SHA-256-PLUS, ... | Channel binding: available (tls-exporter) | Downgrade protection: off` — lists all server-offered mechanisms, channel binding availability with type (`tls-exporter` / `tls-unique` / `none`), and per-account downgrade protection status
- **Mechanism selection**: `SASL: Selected SCRAM-SHA-512-PLUS for chat.example.com` — shows which mechanism was chosen after priority evaluation
- **Authentication success**: `SASL: Authenticated via SCRAM-SHA-512-PLUS at chat.example.com` — confirms successful SCRAM handshake

**Warnings (always visible):**
- `SCRAM: Server iteration count too low (<count>), rejecting` — server PBKDF2 iteration count below safe minimum
- `Channel binding required but no -PLUS mechanism available at <host> (possible downgrade attack)` — downgrade protection triggered, login refused
- `Refusing PLAIN authentication without TLS to <host>` — plaintext auth blocked on unencrypted connection
- `No supported mechanism provided by server at <host>` — no usable auth mechanism found

**Mechanism priority order (highest to lowest):**

With channel binding available:
1. SCRAM-SHA-512-PLUS
2. SCRAM-SHA-256-PLUS
3. SCRAM-SHA-1-PLUS

Without channel binding (or fallback when `-PLUS` unavailable):
1. SCRAM-SHA-512
2. SCRAM-SHA-256
3. SCRAM-SHA-1
4. PLAIN (over TLS only)

### Certificate Pinning

Debug certificate pinning, fingerprint validation, and `.onion` exceptions:

```bash
G_MESSAGES_DEBUG="libdino" DINO_LOG_LEVEL=debug ./build/main/dinox 2>&1 | grep -iE "certificate|pinned|fingerprint|onion"
```

**What's logged (debug level):**
- `Certificate pinned for domain <host> with fingerprint <fp>` — new pin stored
- `Certificate unpinned for domain <host>` — pin removed
- `Certificate for <host> matches pinned fingerprint` — pin verified on connect
- `Certificate for <host> matches pinned fingerprint, accepting` — TLS/HTTP accepted via pin match
- `Accepting certificate from .onion domain <host> with unknown CA` — Tor hidden service TLS exception

**Warnings:**
- `Certificate for <host> changed from pinned fingerprint! Old: <fp>, New: <fp>` — possible MITM, fingerprint mismatch

### OMEMO Encryption

Debug OMEMO key exchange, session management, and encrypt/decrypt operations:

```bash
G_MESSAGES_DEBUG="OMEMO" DINO_LOG_LEVEL=debug ./build/main/dinox 2>&1 | grep -i omemo
```

**What's logged:**
- **OMEMO Legacy** (`eu.siacs.conversations.axolotl`): session creation, decrypt failures, unknown devices
- **OMEMO 2** (`urn:xmpp:omemo:2`): new sessions, bundle fetching, device list management, SCE envelope parsing
- Pre-key store initialization, signed pre-key validation
- Session store errors, identity key mismatches
- DTLS-SRTP verification for encrypted calls via OMEMO
- Device ID matching: `Is ours? <remote_id> =? <own_id>` for each incoming key element

### OpenPGP Encryption

Debug OpenPGP key management, publishing, and message encrypt/decrypt:

```bash
G_MESSAGES_DEBUG="xmpp-vala,OpenPGP" DINO_LOG_LEVEL=debug ./build/main/dinox 2>&1 | grep -i "XEP-0373\|openpgp\|pgp"
```

**What's logged:**
- **Key publishing**: `XEP-0373: Publishing to node: <node>`, publish result (SUCCESS/FAILED), metadata date
- **Key fetching**: PubSub item count, per-item processing, base64 key length, decoded key length, fingerprint
- **Self-test**: `XEP-0373: Self-test SUCCESS - found <n> key(s)` or `Self-test FAILED` after publishing
- **Key unpublishing**: Node deletion, metadata clearing
- **Key updates**: `XEP-0373: Received public key update from <jid>` on PubSub notifications
- SCE (Stanza Content Encryption) envelope parsing
- PubSub node creation and access model configuration

### Audio/Video Calls

Debug the full call stack — GStreamer pipelines, ICE negotiation, DTLS handshake, codec selection:

```bash
GST_DEBUG=3 G_MESSAGES_DEBUG="rtp,ice" DINO_LOG_LEVEL=debug ./build/main/dinox 2>&1 | tee /tmp/dinox-call.log
```

For more GStreamer detail (very verbose):

```bash
GST_DEBUG="webrtc*:5,nice*:5,dtls*:5,srtp*:5,rtp*:4,pulse*:5,pipewire*:5" \
G_MESSAGES_DEBUG="rtp,ice" DINO_LOG_LEVEL=debug ./build/main/dinox 2>&1 | tee /tmp/dinox-call.log
```

**What's logged:**
- Codec encode/decode pipeline descriptions (Opus, VP8)
- SRTP encryption/decryption setup, SSRC handling
- ICE candidate gathering, STUN/TURN server DNS resolution
- DTLS handshake progress and timeout detection
- Pre-ready SRTP packet buffering with counts
- RTP keyframe detection, inter-frame dropping
- RTCP readiness, REMB bandwidth adjustment
- VoiceProcessor setup (AEC/AGC/Noise Suppression status)

#### Verifying Audio Processing

To check that echo cancellation and noise suppression are active:

```bash
grep "VoiceProcessor" /tmp/dinox-call.log
```

Expected output:
```
rtp-Message: ... VoiceProcessor.setup(...)
rtp-Message: ... VoiceProcessor.start(echo_probe=yes, ...)
```

If missing, `webrtc-audio-processing` may not be installed. See [BUILD.md](BUILD.md#building-webrtc-audio-processing-21-manual).

#### DTMF (Dial Tones)

Debug DTMF digit sending, local tone playback, and thread-safety:

```bash
G_MESSAGES_DEBUG="rtp" DINO_LOG_LEVEL=debug ./build/main/dinox 2>&1 | grep -iE "dtmf|dial|tone"
```

**What's logged:**
- DTMF digit enqueue (main thread → mutex-protected queue)
- DTMF digit dequeue and RTP event generation (streaming thread)
- Local tone playback start/stop (audiotestsrc frequency gating)
- Debounce filtering (same digit within 300ms ignored)

**Common issues:**
- **No DTMF sound during video calls**: Check that the silence keepalive branch is active in the GStreamer pipeline
- **Double-digit sends**: Should not happen after v1.1.2.6 (300ms debounce). If it recurs, check `call_dialpad.vala` debounce logic
- **SIGSEGV on DTMF press**: Fixed in v1.1.2.5 (mutex-protected queue). If crash recurs, check that `dtmf_mutex` is being acquired in both `send_dtmf()` and `build_dtmf_rtp_packet()`

### Tor & Obfs4proxy

Debug Tor process management, bridge transport detection, and connection routing:

```bash
DINO_LOG_LEVEL=debug ./build/main/dinox 2>&1 | grep -iE "\[TOR\]|TorController|obfs4|bridge|socks"
```

**What's logged:**
- Tor executable detection and path discovery
- Tor process start (PID), port selection, zombie cleanup
- `torrc` content (with `[TOR-DEBUG]` prefix)
- Obfs4proxy bridge transport lookup
- SOCKS proxy configuration
- State file cleanup on exit

### Database

Debug SQLCipher encryption, SQL queries, and maintenance operations:

```bash
G_MESSAGES_DEBUG="qlite,libdino" DINO_LOG_LEVEL=debug ./build/main/dinox 2>&1 | grep -iE "sqlcipher|pragma|database|rekey|vacuum|fts|backup"
```

**What's logged:**
- SQLCipher PRAGMA configuration (`key`, `journal_mode=WAL`, `synchronous=NORMAL`, `secure_delete=ON`)
- Database password change (`PRAGMA rekey`) with success/failure
- FTS (full-text search) index rebuild on migration
- Backup WAL checkpoint (`PRAGMA wal_checkpoint(TRUNCATE)`)
- SQL trace mode (per-query tracing when compiled with debug flag)
- Plaintext-to-encrypted database migration

#### Database File Locations

| Database | Path | Key Source | Purpose |
|----------|------|------------|---------|
| `dino.db` | `~/.local/share/dinox/dino.db` | User password (Preferences) | Main database (accounts, conversations, messages, roster) |
| `pgp.db` | `~/.local/share/dinox/pgp.db` | User password (Preferences) | OpenPGP keys and account settings |
| `bot_registry.db` | `~/.local/share/dinox/bot_registry.db` | User password (Preferences) | Botmother bot configuration and tokens |
| `omemo.db` | `~/.local/share/dinox/omemo.db` | Auto-generated key (see below) | OMEMO identity keys, sessions, pre-keys |
| WAL journals | `*.db-wal`, `*.db-shm` | — | Write-ahead log (auto-managed by SQLite) |

Flatpak path: `~/.var/app/im.github.rallep71.DinoX/data/dinox/`

> **Important:** `omemo.db` uses a **different key** than the other databases! It uses an auto-generated 64-char hex key stored in the system keyring (GNOME Keyring / KDE Wallet) or in `~/.local/share/dinox/omemo.key` (Windows / no keyring).

#### Inspecting Databases with sqlcipher CLI

DinoX databases are encrypted with SQLCipher (default settings, no custom cipher parameters). To open them interactively:

```bash
# Install sqlcipher CLI
sudo apt install sqlcipher    # Debian/Ubuntu
sudo pacman -S sqlcipher       # Arch

# Open dino.db (replace YOUR_PASSWORD with the password set in DinoX preferences)
sqlcipher ~/.local/share/dinox/dino.db
```

Once inside the sqlcipher shell, you **must** provide the key as the very first statement — before any other query or PRAGMA. If anything runs before `PRAGMA key`, SQLCipher treats the database as unkeyed and all subsequent operations will fail with `Error: file is not a database`:

```sql
-- FIRST COMMAND — must be the very first statement, nothing before it!
PRAGMA key = 'YOUR_PASSWORD';

-- Verify access works (if this fails: wrong password or DB not encrypted)
SELECT count(*) FROM sqlite_master;
```

**Common mistakes that cause `Error: file is not a database`:**
1. Running any query or PRAGMA before `PRAGMA key` (even `PRAGMA user_version`)
2. Wrong password (check DinoX → Preferences → Database Password)
3. Using a `sqlite3` binary instead of `sqlcipher` — standard SQLite cannot open encrypted databases
4. Mismatched SQLCipher major version (e.g. DB created with SQLCipher 4.x, opened with 3.x) — in that case add `PRAGMA cipher_compatibility = 4;` right after `PRAGMA key`

**Step-by-step example (copy-paste ready):**

```bash
sqlcipher ~/.local/share/dinox/dino.db "PRAGMA key = 'test123'; SELECT count(*) FROM message;"
```

Or interactively:

```
$ sqlcipher ~/.local/share/dinox/dino.db
sqlite> PRAGMA key = 'test123';
ok
sqlite> SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;
_fts_message
_meta
account
conversation
message
...
sqlite> SELECT count(*) FROM message;
251
```

> **Tip:** Dot-commands like `.tables` and `.schema` only work in interactive mode, not in one-liner form. Use `SELECT name FROM sqlite_master WHERE type='table';` for one-liners.

> **Note:** DinoX uses SQLCipher with default settings — no `cipher_page_size`, `kdf_iter`, or `cipher_compatibility` overrides. The `PRAGMA key` alone is sufficient. DinoX escapes single quotes in the password, so if your password contains `'`, double it: `PRAGMA key = 'it''s a test';`

#### Opening omemo.db (Different Key!)

`omemo.db` does **not** use the user password. It uses an auto-generated key stored in the system secrets service. To retrieve and use it:

```bash
# Get the OMEMO key from GNOME Keyring / KDE Wallet
OMEMO_KEY=$(secret-tool lookup db_name omemo.db)

# Open omemo.db
sqlcipher ~/.local/share/dinox/omemo.db "PRAGMA key = '$OMEMO_KEY'; SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;"
```

If `secret-tool` is not installed: `sudo apt install libsecret-tools`

On Windows or systems without a secrets service, the key is stored in `~/.local/share/dinox/omemo.key`:

```bash
# Fallback: read key from file
OMEMO_KEY=$(cat ~/.local/share/dinox/omemo.key)
sqlcipher ~/.local/share/dinox/omemo.db "PRAGMA key = '$OMEMO_KEY'; SELECT count(*) FROM identity;"
```

#### Useful OMEMO Debug Queries

```sql
PRAGMA key = '<OMEMO_KEY>';

-- List all OMEMO identities (one per account)
SELECT * FROM identity;

-- List known devices for a contact
SELECT address_name, device_id, trust_level, now_active, device_label
FROM identity_meta WHERE address_name LIKE '%user@example.com%';

-- Trust levels: 0=UNKNOWN, 1=TRUSTED, 2=UNTRUSTED, 3=VERIFIED

-- Count active sessions
SELECT count(*) FROM session;

-- Check pre-key availability
SELECT count(*) FROM pre_key;
SELECT count(*) FROM signed_pre_key;
```

#### Opening pgp.db and bot_registry.db

Both use the same user password as `dino.db`:

```bash
# PGP database
sqlcipher ~/.local/share/dinox/pgp.db "PRAGMA key = 'YOUR_PASSWORD'; SELECT * FROM account_setting;"

# Bot registry database
sqlcipher ~/.local/share/dinox/bot_registry.db "PRAGMA key = 'YOUR_PASSWORD'; SELECT * FROM bot;"
```

#### Useful Debug Queries

```sql
-- Check database schema version
PRAGMA user_version;

-- List all accounts
SELECT id, bare_jid, resourcepart, enabled FROM account;

-- List all conversations with unread counts
SELECT c.id, j.bare_jid, c.type_, c.read_up_to, c.notify_setting
FROM conversation c JOIN jid j ON c.jid_id = j.id;

-- Recent messages for a conversation
SELECT m.id, m.body, m.time, j.bare_jid AS sender
FROM message m JOIN jid j ON m.counterpart_id = j.id
WHERE m.conversation_id = 1
ORDER BY m.time DESC LIMIT 20;

-- Check OMEMO identity keys
SELECT identity_id, address_name, device_id, trusted_identity
FROM identity;

-- Check FTS index health
SELECT count(*) FROM message_fts;

-- Database size and WAL status
PRAGMA page_count;
PRAGMA page_size;
PRAGMA wal_checkpoint(PASSIVE);

-- Check auto-vacuum mode (should be 2 = INCREMENTAL)
PRAGMA auto_vacuum;

-- Run incremental vacuum manually
PRAGMA incremental_vacuum(100);
```

#### Database Recovery

If a database is corrupted:

```bash
# Check integrity
sqlcipher ~/.local/share/dinox/dino.db "PRAGMA key = 'YOUR_PASSWORD'; PRAGMA integrity_check;"

# Export and reimport (last resort)
sqlcipher ~/.local/share/dinox/dino.db \
  "PRAGMA key = 'YOUR_PASSWORD'; .dump" > dump.sql
mv ~/.local/share/dinox/dino.db ~/.local/share/dinox/dino.db.corrupt
sqlcipher ~/.local/share/dinox/dino.db \
  "PRAGMA key = 'YOUR_PASSWORD'; .read dump.sql"
```

### File Transfers

Debug HTTP file upload, encrypted file sharing, and download:

```bash
G_MESSAGES_DEBUG="all" DINO_LOG_LEVEL=debug ./build/main/dinox 2>&1 | grep -iE "upload|download|file_sender|file_provider|sfs|oob"
```

**What's logged:**
- Upload slot requests (XEP-0363)
- SFS/OOB element creation
- Encryption mode selection (AES-GCM)
- URL sanitization in logs (sensitive parts stripped)
- Legacy message parsing with OMEMO/normal detection

### Botmother (Bot-Features Plugin)

Debug the bot framework including bot sessions, Telegram bridging, bot OMEMO encryption, AI integration, webhooks, and the HTTP management server:

```bash
G_MESSAGES_DEBUG="all" DINO_LOG_LEVEL=debug ./build/main/dinox 2>&1 | grep -iE "Botmother|BotOmemo|BotRouter|SessionPool|Telegram:|AI:|Webhook"
```

**What's logged:**

#### Botmother Core
- Bot registry open/close, PRAGMA configuration
- HTTP server start (port, network/localhost mode), restart on settings change
- Bot conversation setup and room-join orchestration
- Owner JID validation, subscription approval/rejection
- `Botmother: Disabled in settings, skipping initialization` when plugin is off

#### Bot OMEMO (BotOmemo)
- OMEMO context initialization per bot
- Per-bot key generation, bundle publishing, pre-key persistence
- Session store load/save with device IDs
- Encrypt/decrypt failures per bot with device details
- Device list management, vCard publishing

#### Telegram Bridge
- Webhook deletion on startup, long-poll lifecycle
- Animated/video sticker-to-emoji conversion
- Media type detection, file URL resolution
- AES-GCM encrypted file download, decryption, and re-upload
- Poll timeouts (normal re-poll vs. 409 conflict backoff)
- Send/upload HTTP status codes on failure

#### Session Pool
- Per-bot XMPP connection status, JID validation
- Subscription requests from non-owner JIDs (rejected with warning)
- Message filtering — non-owner messages ignored with warning
- OMEMO send fallback to plaintext on encryption failure
- Stream error and reconnection handling

#### AI Integration
- Request/response status for each backend: OpenAI, Claude, Gemini, Ollama, OpenClaw
- HTTP status codes on API failures
- Token/model selection logging

#### Webhooks
- Dispatch to subscriber URL with HTTP status
- Retry/failure logging

### Notification Sound

The notification-sound plugin has minimal logging:

```bash
G_MESSAGES_DEBUG="all" DINO_LOG_LEVEL=debug ./build/main/dinox 2>&1 | grep -i "NotificationSound"
```

**Warnings:**
- `NotificationSound: Failed to create libcanberra context (error <code>)` — audio notification system init failed

### History Synchronization (MAM)

```bash
G_MESSAGES_DEBUG="libdino" DINO_LOG_LEVEL=debug ./build/main/dinox 2>&1 | grep -iE "mam|history_sync|archive"
```

---

## Platform-Specific Debugging

### Linux (Build from Source)

```bash
# Full debug
DINO_LOG_LEVEL=debug G_MESSAGES_DEBUG=all ./build/main/dinox 2>&1 | tee dinox-debug.log

# Or use the helper script
scripts/run-dinox-debug.sh
```

### Flatpak

```bash
# Basic debug
flatpak run --env=DINO_LOG_LEVEL=debug im.github.rallep71.DinoX

# Full debug with GStreamer
flatpak run \
  --env=DINO_LOG_LEVEL=debug \
  --env=G_MESSAGES_DEBUG=all \
  --env=GST_DEBUG=2,pulse*:5,pipewire*:5,audiobasesink:5,webrtc*:4,rtp*:4 \
  im.github.rallep71.DinoX 2>&1 | tee /tmp/dinox-flatpak.log
```

#### Inspecting Flatpak Sandbox

```bash
# Check library versions inside sandbox
flatpak run --command=sh im.github.rallep71.DinoX -c "pkg-config --modversion nice"
flatpak run --command=sh im.github.rallep71.DinoX -c "pkg-config --modversion gstreamer-1.0"

# Check audio sinks
flatpak run --command=sh --devel im.github.rallep71.DinoX
gst-inspect-1.0 autoaudiosink pulsesink pipewiresink 2>/dev/null | head -n 30
env | grep -E 'PULSE|PIPEWIRE|GST_'
```

### AppImage

```bash
# Basic debug
DINO_LOG_LEVEL=debug ./DinoX-*.AppImage

# Full debug with audio diagnostics
G_MESSAGES_DEBUG=all \
GST_DEBUG=2,pulse*:5,pipewire*:5,audiobasesink:5,webrtc*:4,rtp*:4 \
DINO_LOG_LEVEL=debug \
./DinoX-*.AppImage 2>&1 | tee /tmp/dinox-appimage.log
```

#### Inspecting AppImage Contents

```bash
./DinoX-*.AppImage --appimage-extract >/dev/null
ls squashfs-root/usr/lib/gstreamer-1.0 | grep -E 'libgst(nice|dtls|srtp|webrtc)\.so'
./squashfs-root/usr/bin/gst-inspect-1.0 autoaudiosink pulsesink 2>/dev/null | head -n 30
```

### Windows

DinoX on Windows runs as a native GUI application. All environment variables (GStreamer, SSL, icons) are configured automatically by `dinox.exe`.

#### Basic Debug

```cmd
set DINO_LOG_LEVEL=debug
dinox.exe
```

#### Log to File

```cmd
set DINO_LOG_LEVEL=debug
dinox.exe > dinox-debug.log 2>&1
```

#### GStreamer Debug (Windows)

```cmd
set GST_DEBUG=3
set DINO_LOG_LEVEL=debug
dinox.exe > dinox-debug.log 2>&1
```

#### Common Windows Issues

| Issue | Solution |
|-------|----------|
| Missing DLL error | Ensure you extracted the full ZIP and run from the extracted directory |
| GStreamer plugins not found | Check that `lib/gstreamer-1.0/` exists in the distribution folder |
| No audio | Windows uses `wasapisink`/`wasapisrc`. Debug with `GST_DEBUG=wasapi*:5,audiobasesink:5` |

---

## Common Debugging Scenarios

### No Sound in Calls

1. Check GStreamer audio plugins:
   ```bash
   gst-inspect-1.0 autoaudiosink autoaudiosrc pulsesink pipewiresink 2>/dev/null
   ```

2. Check PipeWire integration:
   ```bash
   gst-inspect-1.0 pipewiresink pipewiresrc 2>/dev/null
   ```

3. Run with audio-focused debug:
   ```bash
   GST_DEBUG="pulse*:5,pipewire*:5,audiobasesink:5,audiobasesrc:5" \
   G_MESSAGES_DEBUG="rtp" DINO_LOG_LEVEL=debug ./build/main/dinox 2>&1 | tee audio.log
   ```

### OMEMO Not Working

```bash
G_MESSAGES_DEBUG="OMEMO" DINO_LOG_LEVEL=debug ./build/main/dinox 2>&1 | grep -i "omemo\|bundle\|session\|device"
```

### Connection Failing

```bash
G_MESSAGES_DEBUG="libdino,xmpp-vala" DINO_LOG_LEVEL=debug ./build/main/dinox 2>&1 | grep -iE "connect|tls|sasl|dns|error"
```

### Login / Authentication Failing

Check which SCRAM mechanism is selected and whether channel binding or downgrade protection is interfering:

```bash
G_MESSAGES_DEBUG="xmpp-vala" DINO_LOG_LEVEL=debug ./build/main/dinox 2>&1 | grep -i "SASL:\|SCRAM:\|channel.bind\|mechanism"
```

If you see `Channel binding required but no -PLUS mechanism available` — the downgrade protection toggle is ON but the server doesn't offer `-PLUS` mechanisms. Either disable downgrade protection in account settings or check TLS configuration on the server.

### Tor Not Connecting

```bash
DINO_LOG_LEVEL=debug ./build/main/dinox 2>&1 | grep -iE "\[TOR\]|socks|proxy|bridge"
```

### TLS Not Available (AppImage)

If you see `GDummyTlsBackend` or "TLS support is not available" (especially in AppImage):

```bash
# Check which GIO TLS backend is loaded
G_MESSAGES_DEBUG=all ./DinoX-*.AppImage 2>&1 | grep -i "gio-tls-backend\|GDummyTls\|giognutls\|GIO_EXTRA_MODULES"
```

**Root cause:** `glib-networking` (provides `libgiognutls.so`) is not installed on the host and was not bundled in the AppImage. Fixed in v1.1.2.6.

**Workaround (older AppImages):**
```bash
# Install glib-networking on the host
sudo apt install glib-networking    # Debian/Ubuntu
sudo pacman -S glib-networking       # Arch
```

**Verify GIO modules inside AppImage:**
```bash
./DinoX-*.AppImage --appimage-extract >/dev/null
ls squashfs-root/usr/lib/gio/modules/
# Should contain: libgiognutls.so
```

### GTK Warnings

Common GTK warnings and their meaning:

| Warning | Cause | Status |
|---------|-------|--------|
| `Broken accounting of active state for widget (GtkPopoverMenu)` | PopoverMenu not unparented on close | Fixed in v1.1.2.4 / v1.1.2.6 |
| `Accessible role for GtkBox cannot be changed` | GTK4 internal — accessible role set after widget realization | Harmless, GTK4 bug |
| `Trying to snapshot GtkPopover without a current allocation` | Popover rendered before layout pass | Harmless, timing-related |

To suppress GTK debug noise and focus on app logic:

```bash
G_MESSAGES_DEBUG="libdino,xmpp-vala,OMEMO,rtp" DINO_LOG_LEVEL=debug ./build/main/dinox 2>&1 | grep -v "Gtk-WARNING"
```

---

## Command Line Options

| Option | Description |
|--------|-------------|
| `--version` | Print DinoX version and exit |

---

## Reporting Bugs

When filing an issue, please include:

1. **DinoX version** — check About dialog, or run with `--version`
2. **Operating system** — distribution + version (e.g. Ubuntu 24.04, Windows 11)
3. **Installation method** — Flatpak, AppImage, Windows ZIP, or built from source
4. **Debug log** — run with `DINO_LOG_LEVEL=debug` and attach the relevant output
5. **Steps to reproduce** — minimal sequence to trigger the issue

Submit issues at: https://github.com/rallep71/dinox/issues
