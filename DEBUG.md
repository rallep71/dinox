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
| `libdino` | Core library (connection, encryption, services) |
| `xmpp-vala` | XMPP protocol implementation |
| `qlite` | Database layer (SQLite/SQLCipher) |
| `crypto-vala` | Cryptographic operations |
| `OMEMO` | OMEMO encryption plugin |
| `OpenPGP` | OpenPGP encryption plugin |
| `rtp` | Audio/video calls (RTP/Jingle) |
| `ice` | ICE/DTLS-SRTP (call transport) |

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
- SASL mechanism selection and authentication
- Network monitor online/offline state changes
- Suspend/resume handling

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

### OpenPGP Encryption

Debug OpenPGP key management, publishing, and message encrypt/decrypt:

```bash
G_MESSAGES_DEBUG="OpenPGP" DINO_LOG_LEVEL=debug ./build/main/dinox 2>&1 | grep -i "openpgp\|pgp\|gpg"
```

**What's logged:**
- XEP-0373 key publish/retract operations
- PubSub node creation and metadata publishing
- Key import/export with length validation
- Fingerprint logging for key verification
- SCE (Stanza Content Encryption) envelope parsing

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

### Tor Not Connecting

```bash
DINO_LOG_LEVEL=debug ./build/main/dinox 2>&1 | grep -iE "\[TOR\]|socks|proxy|bridge"
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
