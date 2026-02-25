# DinoX - Development Plan

> **Last Updated**: February 25, 2026 (v1.1.4)
> **Current Release Line**: 1.1.4.x

This document is organized as a **chronological release timeline** first, followed by a **forward-looking roadmap**.

---

## Project Snapshot

| Metric | Status |
|--------|--------|
| **Current Version** | 1.1.4 |
| **XEPs Implemented** | ~78 |
| **Languages** | 47 (~85% translated) |
| **Build Status** | Clean |
| **GTK/libadwaita** | GTK4 4.14, libadwaita 1.5 |

---

## Timeline (Recent Releases)

### v1.1.4 (MUJI Group Calls Audit, OMEMO MUC Fixes, Audio & Network Improvements)

- **MUJI Group Calls Audit**: Fixed 14 findings (F1-F9) — signal leak in detach(), invite-retract with 60s timeout, MUC-leave on retract, nick collision retry (3 attempts), codecs_changed signal consumption, dead code removal.
- **Peer Limit**: MAX_MUJI_PEERS=4 with UI feedback ("Anruf voll" / "Call is full").
- **Timeout Separation**: 1:1 calls 30s, MUJI initiator 90s, MUJI receiver 30s, invite 60s.
- **OMEMO DTLS-SRTP**: 8 bug fixes in verification draft (null checks, key comparison, error handling).
- **OMEMO MUC**: Proactive key fetch, MAM real_jid resolution, empty occupant guard.
- **Audio Clipping Mitigation**: recv_gain = 1/sqrt(N) for multi-peer group calls.
- **Bandwidth Coordination**: Per-peer video bitrate cap (upload_budget/N), rebalance on peer join/leave.
- **Network Recovery**: End active calls on XMPP connection loss.

### v1.1.3.1 (MUC/Avatar/GTK Warning Fixes, Panic Wipe Resync, URL Preview)

- **MUC Close vs. Leave**: Separated hide from close/leave to prevent race conditions and unintended MUC departures.
- **Avatar Fixes**: Removed debug prints, fixed portrait resize, removed redundant DB reads, added MUC avatar remove button.
- **MUC Message Retraction**: Fixed wrong moderation ID, missing local feedback, feature cache race.
- **GTK Warnings**: Fixed AdwBreakpointBin min > natural height (vhomogeneous + measure() override), sidebar placeholder wrapping.
- **Panic Wipe Resync**: Added sync_not_before + panic marker to prevent MAM from restoring wiped data.
- **GLib-GObject-CRITICAL**: Fixed realize_id not reset after handler disconnect.
- **URL Preview vs. Reactions**: Fixed priority conflict (both priority 3), reactions moved to priority 4.
- **CI**: aarch64 builds now optional (allow-failure).

### v1.1.3.0 (GTK4 Crash Fix, SRTP/SOCKS5 Audit Tests, Legacy Code Cleanup)

- **GTK4 Call Window Segfault**: Recursive `gtk_window_close` in call window close handler. Added `closing` guard, removed `dispose()` during signal emission.
- **SRTP force_reset Bug**: `force_reset()` only reset encrypt stream, not decrypt counter. Found by RFC 3711 audit, 10 new tests.
- **SOCKS5/XEP-0260 Audit**: 14 new tests for SOCKS5 Bytestreams protocol logic. Tor toggle lag fixed.
- **HTTP-Files Tests**: 25 tests for URL regex, filename extraction, log sanitization. GCM tag always-append bug fixed.
- **SFS + Legacy Fixes**: Encryption propagation, legacy decrypt tag, UI widget fixes, Pango invalid UTF-8.
- **Legacy Code Removed**: ~400 lines dead code (ESFS registry, encryption fallback, avatar re-encryption, esfs_mode).
- **Testing Infrastructure**: 692 total tests (556 Meson + 136 standalone). `run_all_tests.sh` fixed (openpgp-test was missing). Complete source file reference in TESTING.md.

### v1.1.2.9 (UI-Bugfixes: Bookmark Close, Dialog Lag, Konto-Deaktivierung, MUC-Browser)

- **Bookmark Close Action Race**: `Idle.add()` um `popover.unparent()` — GTK4 schloss Popover bevor Aktion feuerte, `unparent()` entfernte Action-Group.
- **Role.NONE Warnung**: Fehlender Switch-Case in `status_populator.vala` behoben.
- **"Unterhaltung starten" Lag**: Sync Roster-Laden → verzögertes Batch-Laden (2er-Batches, 150ms initial, 10ms zwischen Batches).
- **Konto-Deaktivierung Konversationen**: Aktive Konversationen werden jetzt explizit geschlossen (OMEMO-sicherer Pfad).
- **MUC-Browser Schalter Lag**: `clear_list()` + `populate_list()` in `Idle.add()` gewrappt.

### v1.1.2.8 (Legacy Encryption Fallback, Avatar Decrypt Fix)

- **Legacy Encryption Fallback**: `decrypt_data()` auto-falls back to pre-v1.1.2.7 format (SALT=8, IV=16, TAG=8) when current format fails. Old avatars decrypted and silently re-encrypted to current format.
- **Avatar Decrypt Spam Fix**: `failed_decrypt_hashes` prevents repeated expensive PBKDF2 for corrupt files. `store_image()` pre-populates bytes cache.
- **Upgrade Recommendation**: Panic Wipe (`Ctrl+Shift+Alt+P`) for cleanest migration to new encryption parameters, or let auto-migration handle it.

### v1.1.2.7 (Security Audit Test Suite, AppImage KDE Icons, Flatpak H.264 Fix)

- **Security Audit Test Suite**: 506 Meson + 136 standalone = 642 tests. 6 suites, spec-based naming. Found and fixed 21 bugs (T-1 through T-21).
- **Flatpak H.264 Fix**: Add `GST_PLUGIN_PATH=/app/lib/ffmpeg` + `autodownload: true` for ffmpeg-full extension. Old Radeon GPUs can now record video messages.
- **AppImage KDE Icons (GitHub #14)**: Bundle Adwaita scalable + symbolic icons for KDE Plasma compatibility.
- **AppImage VAAPI Segfault**: Remove bundled `libgstvaapi.so` (crashes on old Radeon). Host VAAPI still works via GST_PLUGIN_PATH prepending.
- **File Manager Log Spam**: `warning()` → `debug()` for "Don't have download data (yet)" race condition.
- **Documentation**: SECURITY_AUDIT.md updated with test-suite bugs. TESTING.md with Developer Quick Reference. README Testing link.

### v1.1.2.6 (AppImage TLS Fix, File Upload Crash, DTMF Debounce)

- **AppImage TLS Fix**: Bundle glib-networking (libgiognutls.so) + set GIO_EXTRA_MODULES in AppRun. Fixes GitHub #13.
- **File Upload Null Check**: Null check for prepare_send_file() result prevents CRITICAL assertion crash.
- **DTMF Debounce**: 300ms per-digit debounce prevents double-send on fast clicks.

### v1.1.2.5 (Audio Quality, DTMF Thread-Safety, Outgoing Ringback)

- **DTMF Thread-Safety**: Mutex-protected queue replaces unsynchronized LinkedList. Fixes SIGSEGV, stream errors, one-directional audio after DTMF.
- **DTMF Local Tones**: Silence keepalive + volume gating for reliable playback during audio and video calls.
- **Audio Quality Tuning**: WebRTC APM: NS kModerate, AEC desktop, AGC kFixedDigital 6dB, transient suppression disabled.
- **Opus FEC**: `packet-loss-percentage=10` for forward error correction on lossy networks.
- **Receive Audio Ramp-Up**: 200ms volume fade-in prevents crackling at call start.
- **Outgoing Ringback Tone**: `phone-outgoing-calling` plays immediately on outgoing calls.

### v1.1.2.4 (PopoverMenu, Flatpak H.264, MUC Corrections, ESFS Auth)

- **PopoverMenu Unparent**: Right-click context menu popover now unparented on close. Fixes GTK "Broken accounting of active state" warning.
- **Flatpak OpenH264**: Build OpenH264 v2.4.1 as Flatpak module. Video recording works without optional ffmpeg-full extension.
- **MUC Correction Fallback**: Fall back to nick matching for MUC corrections when occupant IDs (XEP-0421) are unavailable.
- **ESFS GCM Auth Tag**: Try authenticated GCM decryption first, fall back to tag-less mode for interop. Eliminates per-file warnings.

### v1.1.2.3 (Database Security Audit, FTS5 & Preferences Fix)

- **Preferences Lazy Loading**: Contacts page defers roster population until visible; Encryption page defers OMEMO key queries. Dirty-state tracking refreshes on next map. Reuses existing AccountDetails. Fixes lag when opening preferences.
- **bot_registry.db Encrypted**: Bot registry now encrypted with SQLCipher (same key as dino.db). Auto-migrates plaintext DBs.
- **File Permissions**: All DB files chmod 600 (including WAL/SHM).
- **Secure Delete**: `PRAGMA secure_delete = ON` for bot_registry.db.
- **Duplicate Conversations**: UNIQUE constraint + dedup migration on `(account_id, jid_id, type_)`.
- **Orphan Cleanup**: Migration removes orphaned messages and real_jid entries.
- **Foreign Keys**: `PRAGMA foreign_keys = ON` enforced per connection.
- **Auto-Vacuum**: `auto_vacuum = INCREMENTAL` with one-time VACUUM conversion.
- **File Transfer Index**: New index on `(account_id, counterpart_id)`.
- **FTS4 → FTS5**: Runtime detection, conditional upgrade, FTS4 fallback. SQLCipher now built from source with `--enable-fts5` in CI/Flatpak.
- **DB VERSION**: 37 → 39.

### v1.1.2.2 (UI Performance & Avatar Cache Fix)

- **Bookmark Close Lag**: `part()` (sync socket write + bookmark update) blocked UI before collapse animation. Fix: schedule via `Idle.add()`, animation runs first.
- **Systray Quit Lag**: Window stayed visible during disconnect. Fix: hide window instantly, remove duplicate cleanup and unused safety timer.
- **Avatar Cache Destroyed on Shutdown**: `cleanup_temp_files()` deleted encrypted avatar files every quit → 6s re-fetch on restart. Fix: stop deleting AES-encrypted avatar cache.
- **Avatar Bytes Cache**: Added in-memory LRU cache (200 entries) for decrypted avatar bytes — no more file I/O + AES decrypt per access.
- **Avatar Rebuild Debounce**: MUC avatar tiles debounced (150ms) to prevent repeated full rebuilds during login. Occupant avatar changes handled by individual tiles, not full rebuild.
- **Animation**: Conversation row slide-up reduced 200ms → 120ms.

### v1.1.2.1 (CRITICAL: Systray OMEMO Identity Fix)

- **Systray Quit Destroyed OMEMO Keys**: Systray called `disconnect_account()` per account (fires `account_removed` → OMEMO keys deleted) BEFORE `shutdown()` ran. Fix: use `disconnect_all()`.
- **Reconnect/Disable Account Destroyed OMEMO Keys**: Preferences reconnect and account disable also called `disconnect_account()`. Fix: use `connection_manager` directly.
- `stream_interactor.disconnect_account()` now only used when user explicitly removes an account.

### v1.1.2.0 (Video Profile + Audio Playback Fix)

- **Constrained Baseline Profile**: All H.264 encoders forced to Constrained Baseline via capsfilter. High profile was rejected by Android media players (Monocles, Conversations).
- **Video Audio Playback**: Added missing `audioresample` in video player pipeline. Without it, decoded AAC could not negotiate sample rate with audio sink.

### v1.1.1.9 (Video Message Compatibility Fix)

- **VP8/WebM Removal**: Removed VP8/WebM fallback — Monocles/Conversations can't play WebM. H.264/MP4 only.
- **MP4 moov atom Fix**: EOS timeout 1s→5s. Without sufficient wait, mp4mux never writes the moov atom → all MP4s were corrupted.
- **VAAPI Encoder Test Fix**: Added `videoconvert` to test pipeline. Hardware encoders need format negotiation, not raw I420.
- **MP4 faststart**: moov atom at file beginning for progressive playback.

### v1.1.1.8 (CRITICAL: OMEMO Identity Persistence Fix)

- **OMEMO Identity Persistence**: Shutdown was destroying all OMEMO identity keys via `account_removed` signal. Every restart generated new OMEMO identities (new device IDs, new keypairs). Fix: `disconnect_all()` closes sockets without triggering account removal. Affects v1+v2.

### v1.1.1.7 (OMEMO v2 Phantom Fix, Encoder Validation, VP8 Fallback)

- **OMEMO v2 Phantom Fix**: Fixed v2 device list causing phantom devices to re-appear endlessly. Cleanup now runs after v2 list, PubSub node uses `max_items=1`, republish uses fixed item_id `"current"`, bundles only fetched for active devices.
- **Encoder Runtime Validation**: Each video encoder tested with 1-frame pipeline before use. Catches broken `openh264enc` (factory exists but lib fails at runtime).
- **VP8/WebM Fallback**: ~~Added `vp8enc` as ultimate fallback~~ (removed in v1.1.1.9).
- **Pipeline Error → Auto Cancel**: Broken pipelines now cancel recording + show error dialog instead of freezing the app.
- **Graceful Shutdown**: Systray quit disconnects all XMPP accounts with 3s timeout before exit.

### v1.1.1.6 (Pipeline Leak Fix, Video Thumbnails, Audio Cleanup)

- **PipeWire Pipeline Leaks**: No GStreamer pipeline until user clicks play. Full cleanup on stop/dispose.
- **Video Thumbnail Preview**: Fixed `is_in_viewport()` reference widget bug + deferred init with retry for unmapped widgets.
- **Video Player Controls**: Seek bar, time display, play/pause, stop button re-enabled for inline videos.
- **Audio Pipeline Cleanup**: Removed `audiodynamic` noise gate/compressor (caused scratching artifacts). Clean pass-through, volume=1.0.
- **openh264enc Fallback**: 5th H.264 encoder fallback for Flatpak (GNOME Platform runtime).
- **Audio Quality**: voaacenc 64→128kbps, avenc_aac 64→96kbps.
- **AppImage Dependencies**: Removed unused libgstgtk4.so, added libgstgdkpixbuf.so + libgstx264.so.

### v1.1.1.5 (GtkBox Warning Fix, Video Encoder Flatpak Fix)

- **GtkBox Warning Fix**: Removed `width_request=400` on URL preview card_box (was minimum, not maximum). Fixed baseline bug in NaturalDirectionBoxLayout.
- **Video Encoder Flatpak Fix**: Added `avenc_h264` (ffmpeg) as fallback H.264 encoder. Made `h264parse` optional. Video recording now works in Flatpak without gst-plugins-ugly/bad.
- **Error Diagnostics**: Video recorder now reports exactly which GStreamer element is missing instead of generic "Need: gstreamer-gtk4".

### v1.1.1.4 (Plugin Load Order, Flatpak Fixes)

- **Plugin Load Order Fix**: `bot-features.so` depends on `omemo.so` at runtime. Plugin loader now sorts dependencies-first and retries failed plugins in a second pass.
- **Flatpak login1 D-Bus**: Added `--system-talk-name=org.freedesktop.login1` for suspend/resume detection.

### v1.1.1.3 (Pango Crash Fix, Markup Escaping)

- **Pango cursor_pos Assertion Fix**: Reset `label.selectable` before text update to invalidate stale cursor index. Moved `unbreak_space` before AttrList byte index computation (NBSP is 2 bytes vs 1). Recompute `/me` bold/italic indices after NBSP expansion.
- **Markup Escaping**: Escape `status_text` in conversation selector tooltip and reaction emoji in reactions widget to prevent Pango parse errors.

### v1.1.1.2 (Video Preview Fix, Runtime Dependency)

- **Video Preview Dark Screen Fix**: `gdkpixbufsink` unavailable caused black preview during video recording. Replaced `fakesink` fallback with `appsink` pulling RGBA frames into `Gdk.MemoryTexture`.
- **Missing gst-plugins-good**: Added `gstreamer1.0-plugins-good` to all build/install docs and CI workflows.
- **Build System**: Added `gstreamer-app-1.0` as core dependency for main binary.

### v1.1.1.1 (AudioRecorder Fix, Installation Docs)

- **AudioRecorder MP4 Corruption Fix**: Replaced pad probe buffer dropping with volume mute (0 to 1.8 after 200ms). Pad probes caused timestamp gaps in MP4 container, producing corrupted audio files.
- **Installation Docs**: Added GNOME Platform//48 runtime requirement to Flatpak instructions in README, website and release notes.

### v1.1.1.0 (Video Messages, MUC Fixes, AudioRecorder Hardening)

- **Video Messages**: Record and send video messages with camera+microphone. GStreamer pipeline with pipewiresrc/v4l2src (video) and autoaudiosrc (audio), H.264+AAC in MP4, HW encoder fallback (vaapi/va/x264). Live preview via gdkpixbufsink. Camera button in chat input. Max 720p/30fps, 120s.
- **G.711 Fallback Codecs**: PCMU/PCMA for SIP gateway compatibility.
- **MUC Role/Affiliation Fixes**: Signals only fire on actual changes, moderator menu per XEP-0045, role status messages.
- **Botmother UI Fixes**: ejabberd test-before-save, vCard debounce, stream cleanup.
- **Video Player Size Cap**: 400x225px Gtk.Frame prevents oversized inline video.
- **Recording Lifecycle Fixes**: Popover destroyed after each recording (fresh preview), signal handlers disconnected in dispose, GStreamer elements released.
- **AudioRecorder Hardening**: autoaudiosrc instead of pipewiresrc, double-callback guard, timer leak fix, PipeWire transient mute.

### v1.1.0.9 (OMEMO Session Reset, IV Fix, Auto-Recovery)

- **OMEMO Session Reset UI**: New "Reset session" and "Reset all sessions" actions in key management. Available per device (ManageKeyDialog), per contact (encryption settings), and per MUC member. Deletes broken Signal sessions while preserving keys and trust levels. Fresh sessions are negotiated automatically on next message.
- **OMEMO IV Zeroing Fix**: Fixed critical bug where AES-GCM IV was zeroed before being placed in the outgoing stanza. All recipients received a zeroed IV that didn't match the encryption IV, causing universal decryption failure.
- **OMEMO Session Auto-Recovery**: SG_ERR_NO_SESSION errors now trigger automatic bundle fetch and session rebuild instead of silently dropping messages.
- **OMEMO v4 Session Guard**: v4 sessions in the v1 encryptor are detected and replaced with correct v3 sessions.

### v1.1.0.8 (Sticker & Tor UI Fixes, Connection Stability)

- **Sticker Button Visibility Fix**: Sticker button now hides when stickers are disabled in settings. Reactive binding to `stickers_enabled`.
- **Sticker Animation Toggle Fix**: Toggling sticker animations on/off takes effect immediately. Always loads as animation; playback controlled by setting.
- **Tor Settings UI Fixes**: Shortened tab title to "Tor", fixed visually stuck firewall/bridges switches, replaced blocking subprocess calls with async.
- **Connection Manager Null Guard**: Prevents critical assertion failure when account removed during async stream establishment.
- **Minimum Window Width**: Raised from 400 to 500px to prevent Adwaita GtkStack width overflow.

### v1.1.0.7 (Public Room Search, UX Polish, Zero Warnings)

- **Public XMPP Room Search**: Search all public XMPP servers via search.jabber.network API in Browse Rooms dialog. Toggle between local disco and global public search.
- **Subscription Status**: Show roster subscription state (Mutual, To, From, None) and pending requests in contact details.
- **Duplicate Close Button Fix**: Removed redundant X+Cancel from 10 dialogs (decoration-layout).
- **Attachment Button Lag Fix**: Optimistic UI keeps file button visible while XMPP stream still connecting.
- **All Compiler Warnings Eliminated**: Unreachable catches, unused vars, implicit .begin(), uint8[] GObject properties, Windows-conditional extern/methods. 626/626 targets, zero warnings.
- **GTK/Adwaita Warnings Fixed**: CSS max-width replaced with widget constraint, PreferencesDialog minimum size set.
- **SASL Debug Logging & Scripts**: Extended debug logging, documented all scripts, extended log scanner.

### v1.1.0.6 (SCRAM Channel Binding & Downgrade Protection)

- **SCRAM-SHA-256/512**: Implemented SCRAM-SHA-256 and SCRAM-SHA-512 alongside existing SCRAM-SHA-1. Preference order: SHA-512 > SHA-256 > SHA-1.
- **SCRAM Channel Binding (-PLUS)**: All 6 SCRAM variants (SHA-1, SHA-256, SHA-512, and their -PLUS counterparts). Channel binding uses tls-exporter (RFC 9266, GLib 2.74+) with fallback to tls-server-end-point (RFC 5929, GLib 2.66+). Custom VAPI binding to fix upstream Vala NULL dereference bug.
- **SCRAM Nonce CSPRNG**: Replaced GLib.Random (Mersenne Twister) with /dev/urandom for SASL nonce generation (24 bytes, Base64-encoded).
- **Channel Binding Downgrade Protection**: Per-account MITM protection toggle in Advanced Settings. When enabled, refuses login if server does not offer SCRAM-*-PLUS mechanisms (possible downgrade attack). Similar to Conversations/Monocles "MITM Protection" toggle. DB version 37.
- **DinoX Exclusive**: Only XMPP client supporting all 6 SCRAM variants including SHA-512-PLUS.

### v1.1.0.5 (Comprehensive Security Audit)

- **Crypto Security Audit (23 Findings)**: Full audit of 39 crypto-related files and 15 OpenPGP files. 6 critical, 11 medium, 3 low findings in OMEMO/Signal layer plus 3 findings in OpenPGP layer -- all fixed and verified.
- **Critical Fixes**: AES-GCM tag verification bypass, XML injection in OMEMO key exchange, SASL SCRAM nonce truncation, Double Ratchet key reuse via duplicate XML elements, PKCS#5 padding oracle, pre-key exhaustion without replenishment.
- **Medium Fixes**: HKDF salt handling, trust store race conditions, session store unbounded growth, bundle fetch without verification, missing replay protection logging, cleartext key material in logs, Signal session serialization integrity, certificate chain validation, stale device ID publishing, multi-device decryption race, X3DH SPK signature verification.
- **OpenPGP Fixes**: Secure temp file deletion (zero-overwrite before unlink), secure temp file permissions (0600 via FileCreateFlags.PRIVATE), CSPRNG random padding replacing Mersenne Twister.
- **Security Audit Documentation**: SECURITY_AUDIT.md report, security-audit.html web page, website and README navigation links.
- **OMEMO v2 Implementation Story**: Full documentation of OMEMO v2 implementation journey.

### v1.1.0.4 (URL Link Preview, Voice Message Waveform, AppImage Icons)

- **URL Link Preview**: Telegram-style preview cards for URLs in chat messages. Fetches OpenGraph metadata (title, description, image, site name) with in-memory cache. Accent-color left border, optional 80x80 thumbnail, clickable to open browser.
- **Voice Message Waveform (Recorder)**: Real waveform display using peak dB from GStreamer `level` element. 60-bar red waveform with pulsing record indicator and age-based opacity gradient. 5-minute max duration with countdown.
- **Voice Message Waveform (Player)**: 50-bar waveform visualization (blue=played, grey=unplayed) replacing the slider. Faster-than-realtime scan via `playbin`+`level`+`fakesink`. Click/drag seek.
- **Voice Message Audio Quality**: 48kHz mono, +5 dB volume, 230ms pre-roll mute, soft-knee compressor to prevent clipping.
- **File Provider URL Bug Fix**: Receiver no longer sees "unknown file to download" for URL messages. Fixed `oob_url ?? message.body` fallback logic.
- **Video DMABuf Fix (Issue #11)**: Filter out DMABuf/DMA_DRM caps in video device selection. Fixes 0 kbps video on older V4L2 drivers.
- **OMEMO File Decryption Fix**: Fixed double-decryption bug in `file_encryption.vala` GCM auth state.
- **Subscription Notification Fix**: Fixed persistent "Send request" notification in DinoX-to-DinoX chats. Load `ask` field from DB, suppress for active conversations.
- **AppImage Icons**: Copy all 6 icon sizes, set XDG_DATA_DIRS in AppRun, SNI IconThemePath property.
- **Telegram Bridge**: Downgrade timeout warnings to debug level.

### v1.1.0.3 (DTMF Support, Dialpad UI, Clickable Bot Commands)

- **DTMF Support (RFC 4733)**: Full telephone-event DTMF for audio and video calls. Direct RTP packet injection into the audio stream (same seqnum/SSRC/SRTP path). Supports 0-9, *, #, A-D with 250ms default duration. Dynamic payload type resolution from negotiated session.
- **Dialpad UI**: New `CallDialpad` popover with 3x4 grid and telephone-style sublabels. Accessible via dialpad button during active calls. Automatic digit queuing for fast input.
- **Clickable Bot Command Menus**: All interactive bot menus (`/help`, `/ki`, `/telegram`, `/api`) generate clickable `xmpp:` URIs. Users click commands instead of typing them.
- **Dialpad Auto-Hide Fix**: `is_menu_active()` now checks the dialpad popover, preventing the 3-second auto-hide timer from closing the dialpad during video calls.
- **DTMF Video Call Lag Fix**: Replaced GLib main-loop timers (`Timeout.add`/`Idle.add`) with RTP-timestamp-based timing in the streaming thread. Duration measured in audio clockrate samples, independent of UI thread load.

### v1.1.0.2 (i18n Password Dialogs, Website Fixes)

- **Password Dialog i18n**: All 22 German gettext msgid strings in password dialogs converted to English. Non-German users previously saw German fallback text.
- **Translation Format-Spec Fixes**: Fixed format-spec errors in 12 .po files caused by `msguniq` concatenating duplicate `msgstr` values.
- **Website**: Fixed XMPP contact URI from `?join` (MUC) to `?message` (regular JID). Clarified footer text about REST API.

### v1.1.0.1 (Telegram Inline Media, /clear Command)

- **Telegram Inline Media Display**: Photos, videos, audio and GIFs from Telegram now display inline in XMPP conversations via two-message approach (info text + bare URL).
- **Telegram Sticker Handling**: Static `.webp` stickers forwarded as inline images. Animated `.tgs`/`.webm` converted to emoji representation.
- **`/clear` Command**: Clean bot conversations -- clears AI history (RAM) and local SQLite DB. Optional `/clear mam` deletes ejabberd MAM archive.
- **Telegram 409 Polling Fix**: Per-bot polling lock, long polling (25s), `deleteWebhook` on startup, 5-second backoff on HTTP 409.

### v1.1.0.0 (AI Integration, Telegram Bridge, TLS API Server)

- **AI Integration (9 Providers)**: OpenAI, Claude, Gemini, Groq, Mistral, DeepSeek, Perplexity, Ollama and OpenClaw. Per-bot provider/model/endpoint/API key settings.
- **OpenClaw Agent Support**: 9th AI provider -- autonomous agent integration via `{"message": "..."}` POST with Bearer token auth.
- **Telegram Bridge**: Bidirectional XMPP-to-Telegram message bridge with polling mode, auto-reconnect, and connection testing.
- **HTTP API Extensions**: 9 new REST endpoints for Telegram (5) and AI (4). Total: 31 REST endpoints.
- **TLS API Server**: Auto-generated self-signed certificates (cert_gen.c). Configurable via preferences UI.
- **Auto-Restart API Server**: Server restarts automatically when settings change (port, TLS, certificates).
- **Dedicated Bot Mode with OMEMO**: Full OMEMO encryption for bots with session pool management.
- **Interactive Menu System**: BotFather-style chat menus for `/help`, `/ki`, `/telegram`, `/api`.
- **API_BOTMOTHER_AI_GUIDE.md**: Comprehensive 12-chapter documentation (bot management, AI, Telegram, HTTP API, TLS).

### v1.0.1.0 (Botmother Chat Interface)

- **Botmother Chat Interface**: Interactive bot management via self-chat commands (BotFather-style). Commands: `/newbot`, `/mybots`, `/deletebot`, `/token`, `/showtoken`, `/revoke`, `/activate`, `/deactivate`, `/setcommands`, `/setdescription`, `/status`, `/help`.
- **BotManagerDialog**: GTK4/libadwaita dialog showing all bots with status icons, mode, token copy, and delete.
- **BotCreateDialog**: Create bots with name and mode selection.
- **Per-Account Botmother Toggle**: Enable/disable Botmother per account.
- **Auto-Pin Self-Chat**: Botmother self-chat conversation auto-pinned when account has bots.
- **OMEMO Race Condition Fix**: `message_states.unset()` outside lock caused concurrent HashMap modification crash.
- **SQLite Upsert Fix**: Missing conflict column in `set_setting()` caused empty `ON CONFLICT()` SQL.

### v1.0.0.0 (Bot-Features Plugin, Ad-Hoc Commands)

- **XEP-0050 Ad-Hoc Commands**: XMPP module for executing, listing and handling ad-hoc commands.
- **Bot-Features Plugin**: Local HTTP API (localhost:7842) for bot management and XMPP message routing. Token auth, rate limiting, webhooks, 16 REST endpoints.
- **Sticker Publish Fix**: `publish_pack()` uploaded AES-256-GCM encrypted files instead of plaintext. Now decrypts to temp file.
- **Sticker Chooser Lag Fix**: O(n^2) `remove(0)` loop replaced with `remove_all()` (O(1)).
- **Sticker Thumbnail Speed**: Reduced `Thread.usleep` from 30ms to 2ms, increasing throughput from ~33 to ~500 thumbs/sec.

### v0.9.9.9 (MUC OMEMO, Notification Sounds, Call Ringtone)

- **MUC OMEMO**: Per-member trust management, key visibility, own keys section, double widget fetch fix, undecryptable warning fix for own JID.
- **OMEMO v1/v2 MUC Version Selection**: v2 only used when ALL recipients support it. Prevents v1 clients from losing messages.
- **OMEMO Stale Device Cleanup**: `cleanup_stale_own_devices()` on every connect -- publishes clean device list, removes stale bundles from server.
- **OMEMO Device List JID Filter**: Filters out PubSub service components and MUC room JIDs from device list processing.
- **OMEMO Cleanup on MUC Destroy**: Automatically removes OMEMO data stored under room JID when room is destroyed.
- **MUC Destroy Room**: Full cleanup chain with error handling. Right-click context menu for room owners.
- **Channel Dialog**: Fixed 5 bugs -- duplicate entries, missing lock icon, broken type check, invisible password field, stuck join button.
- **OMEMO MUC Encryption After Rejoin**: Fixed false "does not support encryption" by waiting for room features before checking.
- **OMEMO Solo/Self-Only Encryption**: Allows sending in MUC when only own device is present.
- **OMEMO Device Display**: Filters inactive devices, sorts by last activity, shows "Last seen" per device.
- **Status/Presence (6 Bugs)**: Persistence, systray sync, status dots, XA color distinction.
- **Avatar Preload Race**: Pre-load avatar hashes before signal connections.
- **Notification Sound Plugin**: Enabled by default on all Linux builds (native, Flatpak, AppImage) via libcanberra.
- **Call Ringtone**: Incoming calls play `phone-incoming-call` sound event in 3-second loop via libcanberra.
- **Double Ringtone Prevention**: Freedesktop notification uses `suppress-sound=true` so only the plugin controls audio.

### v0.9.9.8 (Ghost Messages & Avatar Sync)

- **Undecryptable OMEMO Ghost Messages**: Failed decryptions no longer stored as plaintext. Message body cleared on failure.
- **MAM Re-sync After History Clear**: MAM catchup ranges preserved to prevent archive re-sync.
- **Avatar Sync (6 Bugs)**: Fixed cache invalidation, re-fetch on reconnect, empty hash handling, PubSub item fetch, Base64 whitespace.

### v0.9.9.7 (Clipboard Fix)

- **Clipboard Paste Lag**: Fixed UI lag from unconditional `read_texture_async`. Now checks format before attempting read.

### v0.9.9.6 (OMEMO Session Conflict & GTK4 Stability)

- **OMEMO v1/v2 Session Conflict**: Fixed `SG_ERR_LEGACY_MESSAGE` failures from shared session store. v1 detects v4 sessions, v2 no longer creates sessions for v1 JIDs.
- **GTK4 Double Dispose Crash**: Added null guards and sentinel resets to prevent double-free in dispose().

### v0.9.9.5 (OMEMO Fingerprints & Device Labels)

- **OMEMO Fingerprint Display**: Standardized XEP-0384 format (8 groups of 8 hex digits).
- **OMEMO Device Labels**: Published for v1+v2, fetched from remote v2 device lists.
- **Server Cleanup on Account Deletion**: Full PubSub cleanup before XEP-0077 unregistration.

### v0.9.9.4 (OMEMO Device Management & Session Repair)

- **OMEMO Device Management**: PubSub device list management, device removal, detailed info dialog.
- **OMEMO Session Auto-Repair**: Detects and repairs broken sessions automatically.
- **OMEMO Session Thrashing Guard**: Cooldown period prevents rapid rebuild loops.
- **OMEMO Broken Bundle Handling**: Broken bundles counted as "lost" instead of "unknown".
- **OMEMO Bundle Retry**: Auto-retry every 10 minutes, up to 5 attempts.
- **Account Deletion**: Complete cascade delete across 25+ tables.
- **Clear Cache**: Purges 10 database cache tables plus filesystem cache.

### v0.9.9.3 (Stability & Debug Cleanup)

- **CRITICAL Fix**: Resolved `dino_entities_file_transfer_get_mime_type: assertion 'self != NULL' failed` crash caused by dangling GObject bind_property bindings. Proper lifecycle management with unbind() in dispose().
- **Debug Output Cleanup**: Removed 57 leftover debug print/warning statements across the codebase.
- **Thumbnail Parsing**: Fixed SFS/thumbnail metadata parsing for incoming file transfers with XEP-0264 thumbnails.
- **OMEMO 1 + 2 Stabilization**: Continued stabilization of dual-protocol OMEMO support.

### v0.9.9.2 (Server Certificate Info)

- **Server Certificate Info (GitHub Issue #10)**: Account preferences now show TLS certificate details -- status, issuer, validity period, and SHA-256 fingerprint. Pinned certificates can be removed from the UI.
- **App Icon Fix**: Fixed light/white app icon in AppImage and Flatpak (GResource SVG priority issue).
- **Menu Order**: Moved "Panic Wipe" to bottom of hamburger menu to prevent accidental activation.

### v0.9.9.1 (OMEMO 2 Support)

- **OMEMO 2 (XEP-0384 v0.8+)**: Full implementation of OMEMO 2 with backward compatibility to legacy OMEMO. Dual-stack: Legacy OMEMO + Modern OMEMO 2 for seamless migration.
- **SCE Envelope Layer (XEP-0420)**: Stanza Content Encryption used by OMEMO 2.
- **Crypto**: HKDF-SHA-256 / AES-256-CBC / HMAC-SHA-256 via libgcrypt.
- **HTTP File Transfer with Self-Signed Certificates**: All HTTP file operations now respect pinned certificates.

### v0.9.9.0 (Backup/Restore & Security)

- **Backup/Restore after Panic Wipe**: Fixed critical bug where restoring a backup after Panic Wipe failed due to password mismatch. Clear dialog now asks for backup's original password.
- **Backup Password Leak**: OpenSSL no longer passes passwords via command line. Passwords piped via stdin.

### v0.9.8.8 (Windows GStreamer & System Tray)

- **Windows GStreamer Plugins**: Fixed DLL loading failures. Auto-dependency detection now scans plugin subdirectories.
- **Windows OMEMO & RTP Plugins**: Fixed plugin loading failures by copying before dependency scan.
- **Windows UX**: No batch file needed, no terminal window, app icon embedded in .exe.
- **System Tray (Linux)**: Restored StatusNotifierItem systray with libdbusmenu. Platform-conditional implementation.

### v0.9.8.7 (SHA256 Checksums)

- **SHA256 Checksums**: All binary downloads now include SHA256 checksum files.
- **AppImage Filename**: Fixed missing version number in filenames.

### v0.9.8.6 (Certificate Pinning & Native ARM CI)

- **Certificate Pinning SQL Fix**: Fixed SQL syntax error in upsert query for pinning self-signed certificates.
- **Native ARM CI**: Switched aarch64 builds from QEMU emulation to native GitHub ARM64 runners (`ubuntu-24.04-arm`).

### v0.9.8.5 (Windows Port & OpenPGP Overhaul)

- **Windows Support**: DinoX is now available for Windows 10/11 (MSYS2/MINGW64). Automated CI/CD via GitHub Actions.
- **XEP-0027 (OpenPGP Legacy)**: Full implementation of legacy OpenPGP signing and encryption for maximum client interoperability.
- **OpenPGP Manager**: Unified key management UI for XEP-0373/0374 -- key generation, selection, deletion, revocation. Automatic key exchange via PEP, no keyserver needed.
- **Self-Signed Certificate Trust**: TOFU certificate pinning for self-hosted XMPP servers.
- **PGP Key Revocation**: Revoke keys with XEP-0373 announcement to contacts.
- **Stability fixes**: Video freeze, file transfer crash guards, GStreamer plugins, hash verification.

### v0.9.8.0 (Audio & Usability Polish)

- **Adjustable Audio Gain**: Implemented manual audio gain control (Post-Processing) with slider ui to bypass WebRTC limits.
- **Input Device Selection**: Explicit selection of audio input device in settings.

### v0.9.7.0 (Stable Tor & Multi-Arch)

- **Network Reliability**: Fixed race conditions during Tor startup; implemented port waiting logic to prevent "Connection Refused".
- **Bundling**: Explicitly bundled `tor` and `obfs4proxy` in AppImage/Flatpak for "Out of the Box" functionality.
- **Infrastructure**: Added fully automated Aarch64 (ARM64) builds via QEMU CI pipelines.

### v0.9.6.0 (Sender Identity & Registration)

- **Sender Identity**: Explicit account selection for starting chats, joining/creating MUCs.
- **Registration**: In-Band Registration (XEP-0077) with CAPTCHA support.
- **UI**: Responsive MUC browser and creation dialogs.

### v0.9.5.0 (UX & MUC Avatars)

- **MUC Avatars**: Full XEP-0486 implementation including persistence, resizing (192px), and conversion.
- **UI Refinements**: Redesigned header bar, Status Menu moved to dedicated button with dynamic reachability colors.
- **Maintenance**: Deprecated "Help" button in favor of streamlined UI.

## Forward-Looking Roadmap

### Q3/Q4 2026: macOS & BSD Porting

**Goal:** Bring DinoX to macOS and BSD (FreeBSD, OpenBSD).

- **macOS**: GTK4/libadwaita via Homebrew or MacPorts. Native .app bundle with code signing.
- **FreeBSD/OpenBSD**: Port via pkg/ports system. Adapt Tor/Obfs4proxy integration for BSD init systems.
- **CI**: Extend GitHub Actions with macOS runners; FreeBSD via cross-compilation or VM-based CI.

### Q1 2026: Security Enhancements

| Item | Description | Status |
|------|-------------|--------|
| **Comprehensive Security Audit** | Full audit of 54 crypto-related files (39 OMEMO/Signal + 15 OpenPGP). 23 findings identified and fixed. Documentation published as SECURITY_AUDIT.md and security-audit.html. | DONE |
| **OMEMO: Reject Unencrypted Messages** | When OMEMO encryption is active for a conversation, unencrypted incoming messages are currently accepted and displayed. `conversation.encryption` only controls outgoing messages — no pipeline listener checks encryption status on the receive path. Add a new `MessageListener` (between `DECRYPT` and `STORE`) that checks `conversation.encryption != Encryption.NONE && message.encryption == Encryption.NONE` and either discards the message or marks it with a warning. Affected files: `libdino/src/service/message_processor.vala` (pipeline), `plugins/omemo/src/logic/decrypt.vala`, `plugins/omemo/src/logic/decrypt_v2.vala`. Consider adding a per-conversation setting "Allow unencrypted messages" (default: warn, options: allow/warn/reject). | TODO |

### Q2 2026: Modern Authentication & XEPs

| XEP / Feature | Description | Implementation TODO | Status |
|----------------|-------------|---------------------|--------|
| **SCRAM-SHA-256** | Modern SASL authentication | Implement SCRAM-SHA-256 mechanism alongside existing SCRAM-SHA-1. Conversations, Monal, and Gajim already support this. Affected files: `xmpp-vala/src/module/sasl.vala`, `xmpp-vala/src/module/xep/plain_sasl.vala`. Add SHA-256 hash function to SCRAM negotiation, prefer SHA-256 over SHA-1 when server offers both. | DONE |
| **SCRAM-SHA-1-PLUS** | TLS Channel Binding | Implement `tls-exporter` (RFC 9266) and `tls-server-end-point` (RFC 5929) channel binding for SCRAM-SHA-1-PLUS. Prevents MITM attacks on SASL authentication. Uses GLib `g_tls_connection_get_channel_binding_data()` with custom VAPI binding to fix upstream bug. | DONE |
| **SCRAM-SHA-256-PLUS** | SHA-256 with Channel Binding | Combined SCRAM-SHA-256 with TLS channel binding. Prefers `tls-exporter` (GLib 2.74+) with fallback to `tls-server-end-point` (GLib 2.66+). | DONE |
| **SCRAM-SHA-512-PLUS** | SHA-512 with Channel Binding | Combined SCRAM-SHA-512 with TLS channel binding. DinoX is the only XMPP client supporting this. Same channel binding infrastructure as SHA-256-PLUS. | DONE |
| **SCRAM Nonce CSPRNG** | Cryptographic nonce generation | Replace `GLib.Random` (Mersenne Twister) in SASL nonce generation with `/dev/urandom` or `gcry_randomize()`. Current implementation uses a non-cryptographic PRNG for security-critical nonce generation. | DONE |
| **Channel Binding Downgrade Protection** | MITM protection toggle | Per-account toggle to require SCRAM-*-PLUS mechanisms. When enabled, login is refused if server only offers non-PLUS mechanisms (possible MITM stripping channel binding). Similar to Conversations/Monocles "MITM Protection" toggle. DB version 37, UI in Advanced Settings. | DONE |
| **XEP-0357** | Push Notifications | Add/verify push enable/disable flow per account, server capability discovery, and end-to-end testing with common push components. | TODO |
| **XEP-0388** | SASL2 / FAST | Implement SASL2 negotiation and FAST token handling; ensure interaction with XEP-0198 stream management and session resumption remains correct. | TODO |
| **XEP-0386** | Bind 2 | Implement Bind2 negotiation and integrate with session establishment; verify multi-device and reconnection behavior. | TODO |

### Q3 2026: Advanced media

| Item | Description | Status |
|------|-------------|--------|
| **Notification Sounds (Windows)** | Linux notification sounds (messages + call ringtone) are complete via libcanberra. Windows needs a native backend (PlaySound/XAudio2) since libcanberra is not available. | TODO |
| **Screen Sharing** | Share desktop or windows during calls | TODO |
| **Whiteboard** | Collaborative drawing (protocol TBD) | CONCEPT |

### Q4 2026: 1.0 milestone

The milestone for a "feature complete" and rock-solid release.

**Requirements**:
- Zero P1 (crash) bugs.
- Memory usage < 200MB for 7-day sessions.
- Comprehensive security audit.
- 3+ months of beta testing without major regressions.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to set up your development environment and submit Pull Requests.

```bash
meson setup build
ninja -C build
./build/main/dinox
```

---

**Maintainer**: @rallep71
