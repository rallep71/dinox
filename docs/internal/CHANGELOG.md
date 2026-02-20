# Changelog

All notable changes to DinoX will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.1.2] - 2026-02-20

### Fixed
- **Video Message Preview Dark Screen**: Fixed video recorder preview staying black during recording. The `gdkpixbufsink` element (from `gst-plugins-good`) was unavailable, causing fallback to `fakesink` which has no `last-pixbuf` property. Replaced `fakesink` fallback with `appsink` that pulls RGBA frames and creates `Gdk.MemoryTexture` for the preview. Recording itself was unaffected (only the preview display).
- **Missing Runtime Dependency**: Added `gstreamer1.0-plugins-good` to all dependency lists (README, BUILD.md, CI workflows, release notes). This package provides `gdkpixbufsink` (video preview) and `mp4mux` (video container) at runtime.

### Changed
- **Version**: Bumped from 1.1.1.1 to 1.1.1.2
- **Build System**: Added `gstreamer-app-1.0` as core dependency for main binary (needed for appsink fallback in video preview).

## [1.1.1.1] - 2026-02-19

### Fixed
- **AudioRecorder MP4 Corruption**: Replaced pad probe buffer dropping with volume mute approach (0 to 1.8 after 200ms). Pad probes caused MP4 timestamp discontinuities resulting in corrupted audio files ("Diese Datei ist beschaedigt"). Silent buffers now flow continuously, avoiding timestamp gaps while PipeWire transient crackling is suppressed.

### Changed
- **Version**: Bumped from 1.1.1.0 to 1.1.1.1
- **Installation Docs**: Added GNOME Platform//48 runtime requirement to Flatpak instructions (README, website, release notes).

## [1.1.1.0] - 2026-02-19

### Added
- **Video Messages**: Record and send video messages with camera and microphone. New VideoRecorder module with GStreamer pipeline (pipewiresrc/v4l2src for video, autoaudiosrc for audio). H.264+AAC in MP4 container with hardware encoder fallback (vaapi/va/x264). Live camera preview in popover via gdkpixbufsink (20fps polling). Camera button next to microphone in chat input. Max 720p/30fps, max 120 seconds recording.
- **G.711 Fallback Codecs**: Added PCMU/PCMA (G.711) fallback codecs for SIP gateway compatibility in audio/video calls.
- **Monal Session-Terminate Analysis**: Documented Monal issue #1576 (session-terminate bug).

### Fixed
- **MUC Role/Affiliation Signals**: Role and affiliation change signals now only fire on actual changes, preventing redundant status messages and UI updates.
- **MUC Moderator Menu**: Fixed occupant menu role/affiliation display per XEP-0045. Moderator fallback for role status messages.
- **Botmother UI Fixes**: ejabberd test-before-save, vCard debounce, stream cleanup improvements.
- **Video Player Size**: Video player in chat capped at 400x225px using Gtk.Frame to prevent oversized display.
- **Video Recording Preview Freeze**: Popover destroyed after each recording to ensure fresh preview poll on subsequent recordings.
- **Video Recording Signal Leak**: Signal handlers (duration_changed, max_duration_reached) properly disconnected in popover dispose to prevent callbacks on destroyed widgets.
- **Audio Crackling**: First 200ms muted to suppress PipeWire connection transient crackling in video recordings.
- **AudioRecorder Source**: Changed from pipewiresrc (defaults to video) to autoaudiosrc for reliable audio capture.
- **AudioRecorder Double-Callback**: Added EOS-handled guard to prevent double yield-resume in stop_recording_async.
- **AudioRecorder Timer Leak**: cancel_recording now properly removes the duration update timer.
- **GStreamer Element Leak**: All GStreamer elements released after recording via cleanup_elements.
- **PubSub Log Level**: Downgraded PubSub IQ response log from warning to debug.

### Changed
- **Version**: Bumped from 1.1.0.9 to 1.1.1.0

## [1.1.0.9] - 2026-02-18

### Added
- **OMEMO Session Reset**: New "Reset session" and "Reset all sessions" actions in key management UI. Allows resetting broken Signal sessions without removing devices or trust levels. Available in ManageKeyDialog (per device), 1:1 encryption settings, and MUC member key views.

### Fixed
- **OMEMO IV Zeroing Bug**: Fixed critical encryption bug where the AES-GCM initialization vector was zeroed before being written to the outgoing stanza. Recipients received an all-zeros IV that did not match the IV used for encryption, causing decryption failures on all clients (Monal: GCM error, Monocles: silent failure). Introduced in commit 83fa504.
- **OMEMO Session Auto-Recovery**: Missing Signal sessions (SG_ERR_NO_SESSION) are now classified as recoverable instead of permanent failures. The retry mechanism automatically fetches bundles, establishes fresh sessions, and resends the message. Previously, messages to devices with missing sessions were silently dropped (marked WONTSEND).
- **OMEMO v4 Session Guard**: Detect and remove v4 (OMEMO 2) sessions in the v1 encryptor before they produce broken messages. Forces session re-establishment with correct v3 protocol.

### Changed
- **Version**: Bumped from 1.1.0.8 to 1.1.0.9

## [1.1.0.8] - 2026-02-18

### Fixed
- **Sticker Button Visibility**: Sticker button now correctly hides when stickers are disabled in settings. Added reactive binding to `stickers_enabled` setting.
- **Sticker Animation Toggle**: Toggling sticker animations on/off in settings now takes effect immediately. Stickers always loaded as animations; playback controlled by setting with reactive listener.
- **Tor Settings Label Truncation**: Shortened "Tor Network" tab title to "Tor" to prevent text truncation in narrow preferences window.
- **Tor Switches Visually Stuck**: Firewall and bridges toggle switches now update immediately. Fixed `state_set` handlers to set `.state` property before async operations.
- **Tor Controller Blocking UI**: Replaced synchronous `wait(null)` subprocess calls in Tor controller with async `wait_async()` to prevent blocking the GTK main loop.
- **Connection Manager Null Guard**: Added null check after async stream establishment to prevent critical assertion failure when account is removed during connection.
- **Minimum Window Width**: Increased `set_size_request` from 400 to 500 pixels to prevent Adwaita GtkStack width overflow warning.

### Changed
- **Version**: Bumped from 1.1.0.7 to 1.1.0.8

## [1.1.0.7] - 2026-02-18

### Added
- **Public XMPP Room Search**: Search all public XMPP servers via search.jabber.network API. Toggle between local server rooms and global public search in Browse Rooms dialog.
- **Subscription Status in Contact Details**: Show roster subscription state (Mutual, To, From, None) and pending requests in the About section of 1:1 contact details.
- **SASL Debug Logging**: Extended debug logging for all SASL mechanisms and authentication flow. New DEBUG.md documentation.
- **Scripts Documentation**: Documented all scripts in BUILD.md and CONTRIBUTING.md. Extended scan-dinox-latest-log.sh with SASL, OMEMO, OpenPGP, Botmother, Tor, and certificate pinning sections.

### Fixed
- **Duplicate X+Cancel Buttons**: Removed redundant close button from 10 dialogs total (bot create, contact browser, user search, select contact, join MUC, sticker import, and 4 previously fixed dialogs). Uses `decoration-layout=":"` on AdwHeaderBar.
- **Attachment Button Pop-in Lag**: File attachment button no longer flickers/appears late when switching conversations. Optimistic UI keeps button visible while stream is connecting.
- **GTK4 CSS Warning**: Replaced unsupported `max-width` CSS property with widget constraint.
- **Adwaita PreferencesDialog Warning**: Set minimum size on PreferencesDialog to suppress libadwaita warning.
- **All Compiler Warnings Eliminated**: Fixed unreachable catch clauses, unused variables/fields, implicit `.begin()` deprecated calls, `uint8[]` GObject property warnings, and Windows-conditional code warnings. Clean build: 626/626 targets, zero warnings.

### Changed
- **Version**: Bumped from 1.1.0.6 to 1.1.0.7
- **Security Audit Docs**: Updated documentation references.

## [1.1.0.6] - 2026-02-17

### Added
- **SCRAM-SHA-256**: Implemented SCRAM-SHA-256 SASL mechanism alongside existing SCRAM-SHA-1. Preferred over SHA-1 when server offers both.
- **SCRAM-SHA-512**: Implemented SCRAM-SHA-512 SASL mechanism. DinoX is the only XMPP client supporting this. Preference order: SHA-512 > SHA-256 > SHA-1.
- **SCRAM Channel Binding (-PLUS variants)**: All 6 SCRAM mechanisms now support TLS channel binding (SCRAM-SHA-1-PLUS, SCRAM-SHA-256-PLUS, SCRAM-SHA-512-PLUS). Uses `tls-exporter` (RFC 9266, GLib 2.74+) with automatic fallback to `tls-server-end-point` (RFC 5929, GLib 2.66+). Custom VAPI binding (`glib_fixes.vapi`) to fix upstream Vala NULL dereference bug in `g_tls_connection_get_channel_binding_data()`.
- **Channel Binding Downgrade Protection**: Per-account "MITM Protection" toggle in Account Preferences > Advanced Settings. When enabled, refuses login if server only offers non-PLUS SCRAM mechanisms, which may indicate a MITM stripping channel binding advertisements. Similar to Conversations/Monocles "MITM Protection" toggle.

### Security
- **SCRAM Nonce CSPRNG**: Replaced `GLib.Random` (Mersenne Twister) in SASL nonce generation with `/dev/urandom` (24 bytes, Base64-encoded). Mersenne Twister is not a CSPRNG and its state can be reconstructed from 624 observed outputs. Fallback to GLib.Random on systems without `/dev/urandom`.
- **Downgrade Attack Detection**: When `require_channel_binding` is enabled and the server advertises channel binding capability but only offers non-PLUS mechanisms, the SASL module logs a warning and refuses authentication to prevent MITM downgrade attacks.

### Changed
- **Version**: Bumped from 1.1.0.5 to 1.1.0.6
- **DB Version**: 36 -> 37 (new `require_channel_binding` column in account table)

## [1.1.0.5] - 2026-02-17

### Security
- **Comprehensive Crypto Security Audit**: Full audit of 39 crypto-related files and 15 OpenPGP files across the entire codebase. 23 findings identified and fixed (6 critical, 11 medium, 3 low in OMEMO/Signal layer + 3 in OpenPGP layer). Covers OMEMO v1/v2, Signal Protocol, X3DH key exchange, Double Ratchet, session management, and OpenPGP encryption.
- **Critical: AES-GCM Tag Verification** (Finding #1): `helper.c` `gcm_decrypt` was ignoring the GCM authentication tag entirely. AES-GCM without tag verification is equivalent to AES-CTR -- no integrity or authenticity protection. Fixed to always verify the 128-bit tag via `gcry_cipher_checktag()`.
- **Critical: XML Injection in OMEMO Key Exchange** (Finding #2): `simple_iks.vala` `StanzaNode.put_node()` inserted child XML nodes using unescaped string concatenation. Malicious JIDs or content could inject arbitrary XML into XMPP stanzas, potentially hijacking OMEMO key exchanges. Fixed to use proper DOM-based child insertion.
- **Critical: SASL SCRAM Nonce Truncation** (Finding #3): `sasl.vala` `get_nonce()` generated a 32-byte random array but Base64-encoded only the first 16 bytes. This halved the nonce entropy from 256 to 128 bits. Fixed to encode the full 32-byte array.
- **Critical: Double Ratchet Key Reuse** (Finding #4): `simple_iks.vala` `get_node()`/`get_subnode()` returned the first matching XML child without verifying uniqueness. An attacker could inject duplicate `<key>` elements in OMEMO messages, causing the receiver to process the wrong key material. Fixed to validate no duplicate children exist.
- **Critical: PKCS#5 Padding Oracle** (Finding #5): `simple_iks.vala` lacked timing-safe padding validation. The PKCS#5 unpadding returned distinguishable error types depending on padding content, enabling classic padding oracle attacks. Fixed to use constant-time comparison.
- **Critical: Pre-Key Exhaustion** (Finding #6): `pre_key_store.vala` had no lower bound check on remaining pre-keys. An attacker could exhaust all pre-keys by initiating many sessions, degrading to unsigned key exchange. Fixed to auto-replenish when count drops below threshold.
- **Medium: HKDF Salt Handling** (Finding #7): HKDF used an empty byte array instead of a proper zero-filled salt of hash length, weakening key derivation. Fixed across `hkdf.vala` to use 32-byte zero salt per RFC 5869.
- **Medium: Trust Store Race Conditions** (Finding #8): Identity key trust decisions were not atomic. Concurrent access could lead to inconsistent trust state. Fixed with proper synchronization.
- **Medium: Session Store Unbounded Growth** (Finding #9): Session store had no limit on stored sessions per recipient. A misbehaving peer could cause memory exhaustion. Fixed with maximum session count and LRU eviction.
- **Medium: Bundle Fetch Without Verification** (Finding #10): Fetched OMEMO bundles were used without verifying the identity key matched the expected fingerprint. Fixed to validate identity key consistency.
- **Medium: Missing Replay Protection Logging** (Finding #11): Duplicate pre-key messages were silently accepted without logging. Added audit logging for potential replay attempts.
- **Medium: Cleartext Key Material in Logs** (Finding #12): Debug logging could leak key material in plaintext. Replaced with redacted output in all crypto-related log statements.
- **Medium: Signal Session Serialization** (Finding #13): Session serialization used Vala's default serializer without integrity protection. Added HMAC verification for serialized session data.
- **Medium: Missing Certificate Chain Validation** (Finding #14): TLS certificate chain validation was incomplete for OMEMO-related HTTP uploads. Fixed to perform full chain verification.
- **Medium: Stale Device ID in Published List** (Finding #15): Own device IDs were published without checking if the corresponding bundle still existed. Fixed to verify bundle availability before publishing.
- **Medium: Race in Multi-Device Decryption** (Finding #16): Concurrent decryption from multiple devices could corrupt shared state. Fixed with per-device decryption locks.
- **Medium: X3DH Without SPK Signature Verification** (Finding #17): X3DH initial key exchange accepted signed pre-keys without verifying the Ed25519 signature against the identity key. Fixed to always verify SPK signatures.
- **Low: PRG Seed Entropy** (Finding #18): The pseudo-random generator was seeded with system time instead of `/dev/urandom`. Fixed to use OS-provided entropy source.
- **Low: IV/Nonce Counter Overflow** (Finding #19): AES-GCM nonce counter had no overflow check. After 2^32 messages in a single session, the nonce would wrap. Added overflow detection with automatic session renegotiation.
- **Low: Hardcoded Key Lengths** (Finding #20): Key lengths were hardcoded as magic numbers. Replaced with named constants for maintainability and auditability.
- **Medium: OpenPGP Temp File Plaintext Exposure** (Finding #21): Temporary files containing plaintext in `gpg_cli_helper.vala` were deleted with `FileUtils.remove()` (simple `unlink()`). Plaintext remained recoverable on disk. Fixed with `secure_delete_file()` that zero-overwrites before unlinking.
- **Medium: OpenPGP Temp File Permissions** (Finding #22): Temporary files were created with default umask (typically 0644), readable by other users. Fixed with `secure_write_file()` and `secure_write_data()` using `FileCreateFlags.PRIVATE` (0600 permissions).
- **Low: OpenPGP XEP-0374 rpad Uses Weak PRNG** (Finding #23): `generate_random_padding()` in `0374_openpgp_content.vala` used `GLib.Random` (Mersenne Twister) for random padding. While padding is not secret, predictable padding could leak message length information. Replaced with `/dev/urandom` CSPRNG.

### Added
- **Security Audit Documentation** (`SECURITY_AUDIT.md`): Comprehensive security audit report covering scope, methodology, 23 findings with severity classifications, fix descriptions, and verification status. Includes OMEMO v2 implementation story, SCRAM comparison table, and known limitations.
- **Security Audit Web Page** (`docs/security-audit.html`): Full HTML version of the security audit accessible via the DinoX website at dinox.handwerker.jetzt/security-audit.html.
- **Website Navigation**: Added "Security Audit" link to main website navigation bar.
- **README Navigation**: Added "Security Audit" link after "Contributing" in README.md.
- **OMEMO v2 Implementation Story**: Documented the full OMEMO v2 implementation journey including challenges, architectural decisions, and lessons learned.

### Changed
- **Version**: Bumped from 1.1.0.4 to 1.1.0.5

## [1.1.0.4] - 2026-02-17

### Added
- **URL Link Preview**: Telegram-style preview cards for URLs in chat messages. Fetches OpenGraph metadata (title, description, image, site name) with fallback to `<title>` and `<meta name="description">`. Preview cards show optional thumbnail (80x80), site name, bold title, and description with accent-color left border. Clickable to open URL in browser. In-memory cache to avoid redundant fetches. Skips `aesgcm://` URLs (OMEMO file transfers).
- **Voice Message Waveform (Recorder)**: Real waveform display using peak dB from GStreamer `level` element with non-linear `sqrt` curve instead of random bars. 300x48px waveform (60 bars, red) with pulsing record indicator, age-based opacity gradient, and auto-send on max duration (5 minutes with countdown in last 30s).
- **Voice Message Waveform (Player)**: Replace slider with 50-bar waveform visualization (blue=played, grey=unplayed). Faster-than-realtime waveform scan via `playbin`+`level`+`fakesink`. Click/drag seek support. Download-wait logic with loading icon and error state handling.
- **Voice Message Audio Quality**: 48kHz mono S16LE capsfilter to match PipeWire native rate. Volume 1.8x (+5 dB) with 230ms pre-roll mute to suppress PipeWire transient crackling at recording start. `audiodynamic` soft-knee compressor to prevent clipping.

### Fixed
- **File Provider URL Bug**: Receiver saw "unknown file to download" instead of URL messages. `file_provider.vala` used `oob_url ?? message.body` fallback — when no OOB element was present, a plain URL in the message body was treated as a file transfer. Now only uses OOB when present, or message body only for `aesgcm://` (OMEMO encrypted file transfers).
- **Video Call DMABuf Caps (GitHub Issue #11)**: Older V4L2 drivers (e.g. Haswell ThinkPad T440) advertise `video/x-raw(memory:DMABuf)` caps via PipeWire that they cannot actually deliver, causing 0 kbps outgoing video. `get_best_caps()` now filters out DMABuf and DMA_DRM format caps in Round 1, falling back to SystemMemory caps.
- **OMEMO File Decryption**: Fixed double-decryption bug in `file_encryption.vala` `decrypt_stream` where the `n < TAG_SIZE` branch corrupted GCM auth state by decrypting data twice.
- **Subscription Notification Loop**: Opening a chat with a DinoX contact always showed "Send subscription request" at the top, even though chat worked normally. Two bugs: (1) The `ask` field was stored to DB but never loaded back in `RosterStoreImpl` constructor, so DinoX forgot that a subscription request was already sent. (2) The notification now suppressed entirely for conversations with existing message activity (`last_active != null`), since subscription is only needed for presence/status updates, not messaging.
- **Telegram Bridge Timeout Spam**: Long-polling timeout responses from Telegram API logged as `WARNING`. Demoted to `debug` level since timeouts are normal behavior for long polling.
- **AppImage Missing Icons**: Icons missing in menu, systray, and About dialog on fresh AppImage installations. Three fixes: (1) `build-appimage.sh` now copies all 6 icon sizes (16/32/48/128/256/512px) instead of only 256px, and generates icon cache. (2) `AppRun` sets `XDG_DATA_DIRS` to include `$APPDIR/usr/share`. (3) `application.vala` sets `XDG_DATA_DIRS` programmatically when `APPDIR` env var is present (safety net).
- **AppImage Systray Icon**: SNI `StatusNotifierItem` now exposes `IconThemePath` D-Bus property pointing to `$APPDIR/usr/share/icons` when running as AppImage, so desktop environments can find the icon.

### Changed
- **Version**: Bumped from 1.1.0.3 to 1.1.0.4

## [1.1.0.3] - 2026-02-16

### Added
- **Clickable Bot Command Menus**: All interactive bot menus (`/help`, `/ki`, `/telegram`, `/api` and their sub-menus) now generate clickable `xmpp:` URIs. Users can click commands directly instead of typing them. Links display only the command text (e.g. `/ki`) instead of the full URI. Clicking sends the command in the current conversation without opening an external dialog or switching accounts.
- **DTMF Support (RFC 4733)**: Full telephone-event DTMF implementation for audio and video calls. DTMF tones are sent as RFC 4733 RTP packets by injecting them directly into the audio RTP stream (replacing audio payloads during tone duration). This preserves the same sequence number stream and SSRC, avoiding any SRTP replay protection conflicts. Supports digits 0-9, *, #, A-D with configurable duration (default 250ms). Payload type is dynamically resolved from the negotiated session parameters (typically PT 101 at 8kHz or PT 110 at 48kHz depending on remote client).
- **Dialpad UI**: New `CallDialpad` popover widget with 3x4 grid (0-9, *, #) including telephone-style sublabels (ABC, DEF, etc.). Accessible via dialpad button in the call bottom bar during active audio/video calls. Digits queued automatically when typing faster than tone duration to prevent dropped inputs.
- **SIP & DTMF Analysis Document**: Comprehensive 8-section analysis (`docs/internal/SIP_DTMF_ANALYSIS.md`) covering the Jingle call stack, codec inventory, DTMF methods (RFC 4733 vs XEP-0181), ejabberd mod_sip evaluation, SIP-Gateway compatibility (Opal.im), and implementation roadmap.

### Fixed
- **Dialpad Disappearing During Video Calls**: The call window's auto-hide timer (3 seconds of no mouse movement) was closing the dialpad popover because `is_menu_active()` only checked audio/video settings popovers. Now also checks the dialpad popover state, keeping controls visible while the dialpad is open.
- **DTMF Lag During Video Calls**: DTMF timing was driven by `Timeout.add()` and `Idle.add()` on the GLib main loop, which is heavily loaded during video rendering. Replaced with RTP-timestamp-based timing in the streaming thread — duration is now measured in audio clockrate samples (e.g. 12000 samples = 250ms at 48kHz), completely independent of UI thread load.

### Changed
- **Version**: Bumped from 1.1.0.2 to 1.1.0.3

## [1.1.0.2] - 2026-02-16

### Fixed
- **Password dialog i18n**: All 22 German gettext msgid strings in password dialogs (unlock, set password, change DB password, backup restore) converted to English. Non-German/non-English users previously saw German fallback text instead of their language.
- **change_password_dialog.vala**: Wrapped 2 hardcoded English strings (`"Error: %s"`, `"Wrong current password"`) in `_()` for translation.
- **Translation files (.po)**: Updated all 47 language files with new English msgids. Fixed format-spec errors in 12 .po files caused by `msguniq` concatenating duplicate `msgstr` values.

### Changed
- **Website**: Fixed XMPP contact URI from `?join` (MUC) to `?message` (regular JID) in contact section and footer.
- **Website**: Clarified footer text — AI is available via extensible REST API with 9 providers, not built-in.
- **Version**: Bumped from 1.1.0.1 to 1.1.0.2

## [1.1.0.1] - 2026-02-15

### Added
- **Telegram Inline Media Display**: Photos, videos, audio and GIFs sent from Telegram now display inline in XMPP conversations. Previously they appeared as `[photo] URL` text. Solution: Two-message approach — info text followed by bare URL so Dino's file provider regex matches and triggers inline rendering.
- **Telegram Sticker Handling**: Static `.webp` stickers are forwarded as inline images. Animated `.tgs` and video `.webm` stickers are converted to their emoji representation (since these formats cannot be displayed inline).
- **`/clear` Command**: New bot command to clean up dedicated bot conversations. Clears AI conversation history (RAM) and local DinoX SQLite database. Optional `/clear mam` deletes the global ejabberd MAM archive (with warning that it affects all users).
- **ejabberd MAM Delete API**: `EjabberdApi.delete_mam_messages()` method for server-side MAM archive cleanup via ejabberd REST API (`delete_old_mam_messages`).

### Fixed
- **Telegram 409 Polling Conflicts**: Added per-bot polling lock, long polling (25s timeout), `deleteWebhook` on startup, and 5-second backoff on HTTP 409 errors using monotonic time skip to prevent rapid re-polling.

### Changed
- **Debug Logging**: Downgraded verbose media detection logs from `message()` to `debug()` for cleaner runtime output.
- **Version**: Bumped from 1.1.0.0 to 1.1.0.1

## [1.1.0.0] - 2026-02-15

### Added
- **AI Integration (9 Providers)**: Full AI chat integration with support for OpenAI, Claude, Gemini, Groq, Mistral, DeepSeek, Perplexity, Ollama and OpenClaw. Configurable via interactive `/ki` chat menu or HTTP API. Requires Botmother to be set up first. Per-bot provider, model, endpoint and API key settings with persistent storage. Each provider is independently enable/disable-able per bot. See [API_BOTMOTHER_AI_GUIDE.md](API_BOTMOTHER_AI_GUIDE.md) for full documentation.
- **OpenClaw Agent Support**: OpenClaw as 9th AI provider — autonomous agent integration via simple `{"message": "..."}` POST with Bearer token auth. Flexible JSON response parsing (tries response/text/message/content/reply/result fields, falls back to raw body).
- **Telegram Bridge**: Bidirectional XMPP-to-Telegram message bridge. Configure via `/telegram` chat command or HTTP API. Supports polling mode with auto-reconnect, message forwarding in both directions, and connection testing.
- **HTTP API Extensions (Telegram)**: 5 new REST endpoints — `/bot/telegram/setup` (POST), `/bot/telegram/status` (GET), `/bot/telegram/enable` (POST), `/bot/telegram/send` (POST), `/bot/telegram/test` (POST).
- **HTTP API Extensions (AI)**: 4 new REST endpoints — `/bot/ai/setup` (POST), `/bot/ai/status` (GET), `/bot/ai/enable` (POST), `/bot/ai/ask` (POST). Total: 31 REST endpoints.
- **TLS API Server**: HTTP API server now supports TLS with auto-generated self-signed certificates (cert_gen.c). Configurable via preferences UI (enable/disable TLS, port, certificate paths).
- **Auto-Restart API Server**: API server automatically restarts when settings change (port, TLS toggle, certificate paths) without requiring app restart.
- **Dedicated Bot Mode with OMEMO**: Bots operate with full OMEMO encryption support. Session pool management for concurrent encrypted bot conversations.
- **Interactive Menu System**: BotFather-style chat menus for `/help`, `/ki` (AI setup/providers/models), `/telegram` (bridge config), and `/api` (server settings). Rich formatted output with inline options.
- **i18n Audit**: ~195 German strings changed to English with `_()` gettext wrappers across 6 source files for proper internationalization.
- **API_BOTMOTHER_AI_GUIDE.md**: Comprehensive 12-chapter documentation covering bot management, AI integration, Telegram bridge, HTTP API (31 endpoints), TLS setup, and curl/Python examples.

### Changed
- **Version**: Bumped from 1.0.1.0 to 1.1.0.0
- **meson.build**: Project version updated to 1.1.0.0
- **DOAP files**: Added release entries for 1.0.0.0, 1.0.1.0, 1.1.0.0. Updated dino.doap.in URLs to dinox.handwerker.jetzt, added Windows to OS list, fixed repository URL.

## [1.0.1.0] - 2026-02-13

### Added
- **Botmother Chat Interface**: Interactive bot management via self-chat commands (Telegram BotFather-style). Commands: `/newbot`, `/mybots`, `/deletebot`, `/token`, `/showtoken`, `/revoke`, `/activate`, `/deactivate`, `/setcommands`, `/setdescription`, `/status`, `/help`. Modern output with emoji icons, line separators, JSON examples and curl usage. **Note: Currently only "Personal" (local) mode is functional. "Group" and "Broadcast" modes are not yet implemented.**
- **Botmother UI — BotManagerDialog**: GTK4/libadwaita dialog showing all bots with status icons (🟢/🔴), mode, token copy button, and delete button. Auto-refreshes on focus. Accessible via Settings → Account → "Botmother".
- **Botmother UI — BotCreateDialog**: Create new bots with name and mode selection (Personal/Group/Broadcast). Note: Currently only "Personal" (local) mode is implemented and tested.
- **Per-Account Botmother Toggle**: AdwSwitchRow in BotManagerDialog to enable/disable Botmother per account. Disabling unpins and closes the self-chat conversation. Global toggle in general settings overrides per-account settings.
- **Bot Activate/Deactivate**: `/activate <ID>` and `/deactivate <ID>` commands to set bots active or disabled. Disabled bots reject API requests. Status visible in `/mybots` and UI.
- **Token Display**: `/showtoken <ID>` shows the current API token. Token plaintext stored in new `token_raw` DB column (DB schema v1→v2 migration). Previously only the SHA-256 hash was stored.
- **Auto-Pin Self-Chat**: Botmother self-chat conversation is automatically pinned when the account has bots and Botmother is enabled. Unpinned and closed when disabled or last bot deleted.

### Fixed
- **OMEMO Race Condition (MessageState NULL Crash)**: `message_states.unset()` in `on_pre_message_send` was outside the `lock(message_states)` block, causing concurrent HashMap modification during iteration. Iterator yielded stale keys → `message_states[msg]` returned NULL → crash on property access. Fix: Added missing lock, switched from `keys` + re-lookup to `entries` iterator, added null guards.
- **SQLite Upsert Crash**: `set_setting()` in BotRegistry called `upsert().value(key_, key)` without marking it as the conflict column. Generated SQL had empty `ON CONFLICT ()`. Fix: `.value(key_, key, true)` to set the upsert conflict key.
- **GTK Warning in OccupantMenu**: `Gtk-WARNING: Allocating size to GtkPopoverMenu without calling measure()`. Fix: Deferred `hide()` call via `Idle.add()`.
- **Bot-Features DB Migration**: Adding `token_raw` column without bumping DB version caused `no such column: token_raw` crash on existing databases. Fix: Set `min_version = 2` on the column and bumped `VERSION` from 1 to 2 for Qlite auto-migration.

## [1.0.0.0] - 2026-02-13

### Added
- **XEP-0050 Ad-Hoc Commands**: New XMPP module for executing, listing and handling ad-hoc commands.
- **Bot-Features Plugin**: New plugin providing a local HTTP API (localhost:7842) for bot management and XMPP message routing. Includes token authentication, rate limiting, webhook support, and 16 REST endpoints (create, delete, list, sendMessage, getUpdates, setWebhook, sendFile, setCommands, joinRoom, leaveRoom, sendReaction, getMe, getInfo, getCommands, deleteWebhook, health).

### Fixed
- **Sticker Publish Uploads Encrypted Garbage**: `publish_pack()` uploaded sticker files directly from disk, but those files are AES-256-GCM encrypted at rest. Recipients received undecryptable ciphertext and the HTTP slot size was wrong (ciphertext > plaintext). Now decrypts to a temp file before uploading and reports the correct plaintext size.
- **Sticker Chooser Lag (O(n^2) Clear)**: `clear_sticker_store()` used `remove(0)` in a loop. GLib.ListStore is array-backed, so each removal shifted all remaining elements. 40 stickers = 1600 element shifts. Replaced with `remove_all()` (O(1)).
- **Sticker Thumbnail Worker Too Slow**: Background thumb worker had `Thread.usleep(30ms)` between every thumbnail decode. 40 stickers = 1.2 seconds of pure sleep. Reduced to 2ms (CPU yield only), increasing throughput from ~33 to ~500 thumbs/sec.
- **Sticker Thumb Cache Flash**: When the 256-entry thumbnail cache overflowed, `thumb_cache.clear()` wiped all entries at once, forcing a visible re-decode flash of every thumbnail in view. Now evicts only ~half the entries via iterator, preserving recently used textures.

## [0.9.9.9] - 2026-02-13

### Fixed
- **Status/Presence (6 Bugs Fixed)**: Global status setting was broken in multiple ways:
  - Changing status show (Online/Away/DND/XA) discarded the status message — now preserves the current message
  - Status was not persisted to database — restarting DinoX always reset to "online". Now saved/restored via DB settings
  - Main window menu and systray always initialized to "online" regardless of actual status — now reads from PresenceManager
  - "Away" and "Extended Away" (XA) had identical orange color in the status menu — XA now uses gray (`dim-label`)
  - Initial presence broadcast after stream negotiation always sent "online" before the correct status — now injects show/status via `pre_send_presence_stanza` hook, eliminating the brief flash
  - Status message dialog and sending chain were functional but status message was only visible in conversation list tooltip on hover (by design)
- **Conversation List Status Dots**: Emoji status dots (🟢🟠🔴⭕) next to own-account JIDs in the conversation list did not update when changing status. Added `on_own_status_changed()` handler connected to `PresenceManager.status_changed` signal.
- **Status Dot Flickering**: After changing status, dots briefly showed the correct emoji but then reverted. Root cause: incoming presence from other connected resources (e.g. Monal-iOS still "online") triggered `update_status()` via `on_presence_changed`, overwriting the manually set dot. Fix: `on_presence_changed` now skips `update_status()` for own-account conversations — those are managed exclusively by `on_own_status_changed`.
- **Green Dot Hidden**: Status dots showed correctly for Away/DND/XA but the green dot for "online" was always hidden. The `on_own_status_changed` handler had a special case hiding the dot for "online". Removed — all four states now always display their emoji.
- **External Contact Avatars Missing on Startup**: Avatars for external contacts in the conversation list were blank after launching DinoX — only appearing after clicking the conversation. Root cause: Race condition where `ConversationManager` created sidebar rows (triggering avatar lookup) before `AvatarManager` had loaded hashes from the database. Fix: Pre-load all avatar hashes in the `AvatarManager` constructor, before any signal connections.
- **MUC OMEMO Own Keys Not Visible**: In MUC conversation details, OMEMO keys for the own JID were filtered out. Now shows "Your devices" section first, followed by each MUC member's devices.
- **MUC OMEMO Trust Management**: Clicking a member's device row in MUC OMEMO details now opens ManageKeyDialog for that JID. Added auto-accept toggle (blind trust) per member and accept/reject for new/changed devices.
- **MUC OMEMO Double Widget Fetch**: `conversation_details.vala` called `get_widget()` twice per provider — once to check null, once to add. Now caches the result.
- **MUC OMEMO Undecryptable Warning for Own JID**: "Does not trust this device" banner was shown for own JID in MUC context when other own devices couldn't decrypt. Now skipped for own JID.
- **MUC Destroy Room**: Destroy room IQ errors were silently swallowed. Now checks `is_error()` on IQ result and throws `GLib.IOError.FAILED` with error text.
- **MUC Destroy Room Cleanup**: `destroy_room()` now performs full cleanup chain: send destroy IQ → remove bookmark → remove from mucs_joined → send exit presence → cancel MAM sync → close conversation.
- **OMEMO v1/v2 MUC Version Selection**: In MUC, if one member was v2-only, the entire message was sent as v2 — v1 clients couldn't decrypt. Fixed: v2 is now only used when ALL MUC recipients are v2-capable. Default changed from `use_v2=false` (escalate on first v2-only) to `use_v2=true` (downgrade on first v1-only).
- **OMEMO Stale Device Accumulation**: Old device IDs from previous installations, AppImage tests, and other clients accumulated on the PubSub device list but were never removed. New `cleanup_stale_own_devices()` runs on every connect: deactivates all non-own devices in the local DB, publishes a clean device list (v1+v2) containing only the current device, and deletes stale bundle nodes (v1) / retracts stale bundle items (v2) from the server.
- **MUC Duplicate in Channel Dialog**: Opening "Kanal beitreten" could show the same MUC twice if bookmark events arrived during refresh. `add_conference()` now deduplicates by JID, and `refresh_conferences()` properly clears the widget cache after removing list items.
- **MUC Lock Icon Missing on Startup**: Private room lock icon in "Kanal beitreten" was always missing on first open because it only checked in-memory MUC flags (empty on startup). Now uses `is_private_room()` which also checks the database for cached disco#info features.
- **Channel Dialog Type Check**: The "Join" button enable/disable logic used an incorrect GLib type check (`row.get_type().is_a(typeof(AddListRow))`) that always returned false. Fixed to `row.child is AddListRow`.
- **Channel Dialog Password Field**: Setting a conference password targeted the wrong stack widget (`nick_stack` instead of `password_stack`), making the password label invisible.
- **Channel Dialog Join Button Stuck**: If the JID entered in the join dialog was invalid, the "Join" button remained disabled with spinner text permanently. Now restores the button to "Join" with sensitivity before showing the error.
- **OMEMO "Does Not Support Encryption" in MUC After Rejoin**: Activating OMEMO in a MUC after rejoin falsely reported the room doesn't support encryption. Root cause: `is_private_room()` returned false because disco#info features weren't loaded yet, causing the code to fall into the 1:1 path which checked OMEMO keys for the MUC JID (always fails). Fix: For GROUPCHAT conversations, never fall through to 1:1 code path; wait up to 3 seconds for room features to load.
- **OMEMO Solo MUC Encryption**: Sending an encrypted message in a MUC where no other members have OMEMO devices (solo room) was rejected with WONTSEND. Now allows self-only encryption when recipients list is empty in groupchat context.
- **OMEMO Self-Only Encryption**: When only our own device was in a MUC (no other OMEMO-capable members), encryption failed because `other_devices == 0` rejection didn't distinguish from `own_devices == 0`. Now checks separately: only aborts if own devices are missing, allows sending when only own devices exist.
- **OMEMO Stale Devices in MUC Member Display**: `get_known_devices()` and `get_new_devices()` did not filter by `now_active`, showing old/inactive devices that were no longer published on the server. Added `now_active = true` filter to both queries.
- **OMEMO MUC Device Display Improved**: MUC member device list now filters out devices with no communication history (`last_active` is null), sorts remaining devices by most recent activity first, and shows "Last seen: today/yesterday/X days ago" per device. Inactive device count shown in subtitle (e.g. "+3 inactive").
- **OMEMO Device List Refresh**: `insert_device_list()` previously overwrote `last_active` timestamps for **all** devices on every PubSub device-list update, making the field meaningless. Now only sets `last_active` for genuinely new devices; existing devices retain their decryption-based timestamps.
- **OMEMO Cleanup on MUC Destroy**: When a MUC room is destroyed, OMEMO data (identity_meta, session, trust entries) stored under the room JID is now automatically cleaned up. Member keys stored under real JIDs are intentionally preserved since they are shared with 1:1 conversations.
- **OMEMO Device List JID Filter**: `on_device_list_loaded()` (v1 and v2) now filters out non-user JIDs such as PubSub service components (`pubsub.example.com`) and MUC room JIDs. Previously these created garbage entries in identity_meta and trust tables that could never be used.
- **Double Ringtone Prevention**: Freedesktop notification for incoming calls previously set `sound-name=phone-incoming-call` as a hint, causing some desktop environments (GNOME) to play their own ringtone in addition to the plugin's ringtone. Replaced with `suppress-sound=true` so only the notification-sound plugin controls all audio feedback.

### Added
- **MUC Destroy Room Menu**: Right-click context menu on MUC conversations now shows "Destroy Room" option (only visible for room owners).
- **Notification Sound Plugin Enabled by Default**: The libcanberra notification sound plugin is now compiled and loaded by default on Linux. Previously it was disabled and only built in Flatpak/AppImage. Fixed null safety issues, added error handling for context creation, and set `plugin-notification-sound` meson option from `disabled` to `auto`.
- **Call Ringtone**: Incoming audio/video calls now play the `phone-incoming-call` freedesktop sound event via libcanberra in a 3-second loop until the call is accepted, rejected, or missed. Previously only the notification daemon hint was used, which many desktop environments silently ignored.

## [0.9.9.8] - 2026-02-12

### Fixed
- **Undecryptable OMEMO Ghost Messages**: When OMEMO decryption failed (missing session, ratchet mismatch, etc.), the sender's fallback body text `[This message is OMEMO encrypted]` was stored as a normal plaintext message. These ghost messages accumulated in conversations and could never be decrypted. Now both v1 and v2 decrypt listeners clear the message body on failure, causing the pipeline's empty-message filter to silently drop them.
- **MAM Re-sync After History Clear**: Clearing conversation history previously deleted MAM catchup ranges, forcing a complete archive re-sync from the server on next startup. This caused all old messages to reappear as undecryptable OMEMO blobs (since the ratchet had moved forward). MAM catchup ranges are now preserved, so only new messages are fetched after clearing.
- **Cleared Conversation Filter**: Hardened the MAM message filter for cleared conversations — now falls back to `message.time` when `server_time` is null, and uses inclusive timestamp comparison to properly filter edge-case messages at the exact clear boundary.
- **Avatar Sync (6 Bugs Fixed)**: Avatars were unreliable — sometimes showing, sometimes blank, especially after Clear Cache or reconnect:
  - In-memory avatar hash caches were not cleared after DB purge → stale data, failed fetches with no retry
  - No re-fetch on reconnect — if an avatar file was missing, it stayed blank permanently until a new presence arrived
  - Empty SHA1 hash from `<photo/>` in XEP-0153 presence was stored as a valid hash, causing phantom fetch attempts
  - XEP-0084 (PubSub) avatar fetch used `request_all()` instead of `request_item(hash)` → wrong avatar version returned → SHA1 mismatch → silent failure
  - vCard `fetch_image()` did not strip whitespace from Base64 BINVAL (unlike `VCardInfo.from_node()`) → multi-line base64 caused SHA1 mismatch → avatar silently lost
  - Empty/null hash IDs in `on_user_avatar_received`/`on_vcard_avatar_received` not filtered

### Important — Upgrade Notice
> **Users upgrading from v0.9.9.7 or earlier should delete their local database and perform a fresh start.**
> Previous versions stored undecryptable OMEMO fallback text as plaintext messages and had inconsistent avatar cache state.
> To clean up:
> 1. Close DinoX
> 2. Delete `~/.local/share/dinox/dino.db`
> 3. Delete `~/.cache/dinox/` (avatar + file cache)
> 4. Restart DinoX — accounts will reconnect, MAM will sync fresh messages, avatars will be re-fetched
>
> Alternatively, use **Settings → Clear Cache** (clears avatars, thumbnails, MAM sync state) and then manually clear old conversations that show ghost messages.

## [0.9.9.7] - 2026-02-12

### Fixed
- **Clipboard Paste Lag**: Fixed UI lag on every paste event (Ctrl+V). `read_texture_async` was called unconditionally, causing GDK to probe all clipboard formats including unsupported ones like `image/x-xpixmap`, blocking the main thread. Now checks clipboard formats first and only attempts texture read when a supported image format (PNG, JPEG, BMP, GIF, TIFF, WebP, SVG) is present.

## [0.9.9.6] - 2026-02-12

### Fixed
- **OMEMO v1/v2 Session Conflict**: Fixed `SG_ERR_LEGACY_MESSAGE` decryption failures caused by v1 and v2 OMEMO sharing the same Signal Protocol session store. When a v2 bundle arrived first, it created a version-4 session that the v1 encryptor would use without the correct cipher version, producing unreadable messages. Fix: (1) v1 `start_session` now detects v4 sessions and replaces them with v3, (2) v2 sessions are no longer created for JIDs that have v1 devices, (3) `SG_ERR_LEGACY_MESSAGE` now triggers automatic session repair.
- **GTK4 Double Dispose Crash**: Fixed `GLib-GObject-CRITICAL` errors from `dispose()` being called multiple times on GTK4 widgets (`MessageWidget`, `ConversationView`, `ListRow`, `CallWidget`). Added null guards and sentinel resets to prevent double-free.

## [0.9.9.5] - 2026-02-12

### Added
- **OMEMO Fingerprint Display**: Fingerprints are now displayed in standardized XEP-0384 §8 format (8 groups of 8 hex digits) across all OMEMO UI views — device management, trust dialogs, and key verification.
- **OMEMO Device Labels**: Own device label (e.g. "DinoX - Linux") is now automatically set and published for both OMEMO v1 and v2. Remote device labels (e.g. "Kaidan - KDE Flatpak", "Conversations - Pixel 8") are fetched from v2 device lists and displayed in all device management views.
- **Server Cleanup on Account Deletion**: Deleting an account from the server now performs a full PubSub cleanup before XEP-0077 unregistration — removes the v2 device list, v1 device list, and all individual OMEMO v1 bundle nodes (`eu.siacs.conversations.axolotl.bundles:DEVICE_ID`) from the server.

### Fixed
- **GTK Widget Assertion**: Fixed `gtk_widget_set_parent: assertion 'child->priv->parent == NULL' failed` error caused by widget reparenting during UI updates.

## [0.9.9.4] - 2026-02-12

### Fixed
- **OMEMO Device Management**: Fixed PubSub device list management — devices can now be properly removed from the server. Device management dialog shows detailed device information including labels, trust status, and last activity.
- **OMEMO Session Auto-Repair**: Automatically detects and repairs broken OMEMO sessions by clearing corrupt session data and re-fetching bundles, preventing permanent message decryption failures.
- **OMEMO Session Thrashing Guard**: Prevents rapid session rebuild loops by tracking recent repairs and skipping redundant re-keying within a cooldown period.
- **OMEMO Broken Bundle Handling**: Devices with broken bundles (empty identity key, signed prekey, or signature) are now counted as "lost" instead of "unknown", allowing messages to be sent to other working devices instead of blocking encryption entirely.
- **OMEMO V2 Bundle Fetch on Delay**: When an OMEMO V2 encrypted message triggers a delayed bundle fetch, the V2 bundle is now correctly requested. Previously only the legacy bundle was fetched, causing messages to hang indefinitely.
- **Account Deletion**: Deleting an account now performs a complete cascade delete across 25+ database tables, preventing orphaned data from remaining after account removal.
- **Clear Cache**: The "Clear Cache" function now properly purges 10 database cache tables (avatar, entity_feature, entity_identity, roster, settings, mam_catchup, etc.) in addition to clearing the file system cache directory.

### Added
- **OMEMO Bundle Retry**: When a device's bundle cannot be fetched, it is automatically retried every 10 minutes (up to 5 attempts) before being permanently marked as unavailable.
- **OMEMO Device Labels**: Device labels are now stored in the database and displayed in the OMEMO device management UI alongside device IDs and trust status.

### Improved
- **Repository Cleanup**: Removed obsolete files (icon_backup/, meson_options.txt, cross_file.txt, check_translations.py, OMEMO2_IMPLEMENTATION_PLAN.md). Moved documentation files to docs/internal/.

## [0.9.9.3] - 2026-02-10

### Fixed
- **CRITICAL: bind_property Lifecycle Fix**: Fixed `dino_entities_file_transfer_get_mime_type: assertion 'self != NULL' failed` crash caused by dangling GObject bind_property bindings. FileWidget, FileImageWidget, VideoPlayerWidget, and AudioPlayerWidget now store Binding references and unbind them in dispose(), preventing access to destroyed FileTransfer objects during widget recycling.
- **Thumbnail Parsing**: Fixed SFS/thumbnail metadata parsing for incoming file transfers with XEP-0264 thumbnails.

### Improved
- **Debug Output Cleanup**: Removed 57 leftover debug print/warning statements across the codebase for cleaner runtime output.
- **OMEMO 1 + 2 End-to-End Encryption**: Stabilized dual-protocol OMEMO support (legacy XEP-0384 v0.3 + modern v0.8) introduced in v0.9.9.1.

## [0.9.9.2] - 2026-02-09

### Added
- **Server Certificate Info (GitHub Issue #10)**: Account preferences now show the TLS certificate details of the connected XMPP server — status (CA-signed or pinned), issuer, validity period, and SHA-256 fingerprint. Pinned (self-signed) certificates can be removed directly from the UI. Certificate details are also shown in the "Trust This Certificate" dialog during account setup.

### Fixed
- **App Icon in About Dialog**: Fixed app icon appearing light/white in AppImage and Flatpak builds. The GResource-bundled SVG (base64-wrapped PNG) was being prioritized by GTK4/librsvg and rendered with a light background. Removed SVG from GResource so GTK resolves the icon from installed hicolor PNGs.

### Improved
- **App Icon Rounded Corners**: All app icon sizes (16–512px) now have slightly rounded corners to avoid the "Minecraft cube" look on desktop environments like Linux Mint Cinnamon.
- **Menu Order**: Moved "Panic Wipe" to the bottom of the hamburger menu, below "About DinoX", to prevent accidental activation.

## [0.9.9.1] - 2026-02-09

### Added
- **OMEMO 2 Support (XEP-0384 v0.8+)**: Full implementation of OMEMO 2 with backward compatibility to legacy OMEMO. Includes SCE envelope layer (XEP-0420), OMEMO 2 XML parsers, bundle/stream management for `urn:xmpp:omemo:2` namespace, and HKDF-SHA-256 / AES-256-CBC / HMAC-SHA-256 crypto primitives via libgcrypt. OMEMO 2 device lists and bundles are published and subscribed alongside legacy OMEMO. Interop testing pending (Kaidan Flatpak currently broken).

### Fixed
- **HTTP File Transfer with Self-Signed Certificates**: Fixed file upload/download failing when the XMPP server uses a self-signed certificate. Previously, only the XMPP connection checked pinned certificates — HTTP uploads (PUT), downloads (GET), metadata requests (HEAD), and sticker uploads all rejected self-signed certs even when the user had already accepted them. Now all HTTP file operations respect pinned certificates from the database.

## [0.9.9.0] - 2026-02-09

### Fixed
- **Backup/Restore after Panic Wipe**: Fixed critical bug where restoring a backup after a Panic Wipe would fail because the database was encrypted with the original password, but the app tried to open it with the newly set password. After restore, DinoX now shows a clear dialog asking for the backup's original database password. Panic Wipe is disabled during this phase to prevent accidental data loss.
- **Backup Password Leak**: OpenSSL backup encryption/decryption no longer passes the password via command line (`-pass pass:...`). Passwords are now securely piped via stdin (`-pass stdin`), preventing exposure in process listings (`/proc/PID/cmdline`) and log output.

## [0.9.8.8] - 2026-02-09
### Fixed
- **Windows GStreamer Plugins**: Fixed GStreamer plugin DLL loading failures (d3d11, d3d12, isomp4, libav, rtpmanager, webrtc). The auto-dependency detection now scans GStreamer plugin subdirectory for missing DLLs. Moved GStreamer/GIO/GDK-Pixbuf copy steps before auto-detect to ensure all transitive dependencies are resolved.
- **Windows OMEMO & RTP Plugins**: Fixed `omemo.dll` and `rtp.dll` failing to load ("Das angegebene Modul wurde nicht gefunden"). DinoX plugins are now copied before the auto-dependency scan so their transitive DLL dependencies are resolved automatically.
- **Windows About Dialog**: Debug Information now shows all 3 data paths (Data & Database, Configuration, Cache) instead of combining Data and Configuration into one line. On Windows these are separate directories.

### Improved
- **Windows: No more batch file needed**: `dinox.exe` now sets all required environment variables (GTK paths, GStreamer plugins, SSL certificates) internally on startup. Users can double-click `dinox.exe` directly — the batch file is kept only as a legacy fallback.
- **Windows: No terminal window**: `dinox.exe` now uses the Windows GUI subsystem (`-mwindows`), so launching it no longer opens a console window in the background.
- **Windows: App icon in .exe**: The DinoX application icon is now embedded in `dinox.exe` via a Windows resource file, so it shows in Explorer, taskbar, and Alt+Tab.

### Fixed
- **System Tray (Linux)**: Restored full StatusNotifierItem systray with libdbusmenu that was accidentally removed during Windows porting. Linux users have tray icon, background mode, and status menu back. Added `GApplication.hold()` fallback for GNOME desktops without AppIndicator extension.
- **Platform Split**: Systray implementation is now platform-conditional — Linux gets full SNI/dbusmenu tray, Windows gets clean quit-on-close behavior.

## [0.9.8.7] - 2026-02-09

### Added
- **SHA256 Checksums**: All binary downloads (AppImages, Flatpaks, Windows zip) now include SHA256 checksum files for integrity verification.

### Fixed
- **AppImage Filename**: Fixed missing version number in AppImage filenames (was `DinoX--aarch64.AppImage`, now `DinoX-0.9.8.7-aarch64.AppImage`).

## [0.9.8.6] - 2026-02-09

### Fixed
- **Certificate Pinning**: Fixed SQL syntax error when pinning self-signed certificates. The upsert query had empty `ON CONFLICT()` and a leading comma in the INSERT column list because `domain` was not marked as a key column. Clicking "Trust This Certificate" now works correctly.
- **CI/CD**: Switched aarch64 AppImage and Flatpak builds from QEMU emulation to native GitHub ARM64 runners (`ubuntu-24.04-arm`). Eliminates compiler crashes and dramatically improves build speed.

## [0.9.8.5] - 2026-02-08

### Added
- **Windows Support**: DinoX is now available for Windows 10/11 via MSYS2/MINGW64. Automated CI/CD builds with GitHub Actions produce ready-to-use Windows distribution archives.
- **XEP-0027 (OpenPGP Legacy)**: Full implementation of legacy OpenPGP signing and encryption for maximum interoperability with older XMPP clients (Gajim, Psi, etc.).
- **OpenPGP Manager (XEP-0373/0374)**: Completely reworked OpenPGP key management. The OpenPGP manager now handles key generation, key selection, key deletion, and key revocation in one unified UI. Key exchange happens automatically via PEP (XEP-0373) — no more manual keyserver exchange required.
- **PGP Key Revocation**: Added key revocation options (revoke, revoke+delete, delete-only) in OpenPGP key management dialog with XEP-0373 revocation announcement to all contacts.
- **Self-Signed Certificate Trust**: Added "Trust This Certificate" dialog for self-signed TLS certificates (GitHub Issue #9). Uses Certificate Pinning (TOFU) with SHA-256 fingerprint stored in database.
- **GitHub Actions CI/CD**: Added Windows CI/CD workflow using MSYS2/MINGW64 with automated build, artifact upload, and optional release creation on tag push.

### Fixed
- **Video Freeze**: Fixed video preview freeze with lazy viewport-based initialization.
- **File Transfer Crash**: Added null guards to prevent CRITICAL assertion during widget recycling.
- **App Icon (Windows)**: Embedded SVG app icon in GResource bundle for reliable display on Windows. Added hicolor/index.theme for GTK icon theme discovery.
- **GStreamer Plugins**: Fixed plugin names (audiofx instead of scaletempo), added isomp4 and libav plugins.
- **Hash Verification**: Hash verification now always runs on decrypted plaintext; warns but keeps file on mismatch.
- **Certificate Dialog**: Fixed reconnect logic to properly disconnect before reconnecting.
- **GTK Markup**: Fixed `&` to `&amp;` in encryption preferences entry.
- **Flatpak**: Removed duplicate webrtc-audio-processing module from manifest.

## [0.9.8.4] - 2026-01-24

### Fixed
- **UI Performance**: Fixed a freeze in the progress bar during file uploads by throttling property update notifications.
- **Message Retraction**: Implemented robust XEP-0424 support with "Dual Stack" strategy (XEP-0422 Fastening + Legacy V1 Child) to ensure compatibility with both modern clients (Conversations) and legacy clients (Monal/iOS).
- **Interoperability**: Corrected message ID usage in Group Chats (preferring XEP-0359 Origin IDs over Server IDs) to fix retraction failures with Android clients.

## [0.9.8.3] - 2026-01-24

### Fixed
- **File Transfer**: Fixed a critical issue where sending video files would hang indefinitely (UI freeze) if metadata extraction stalled. Added a robust timeout mechanism to ensure sending proceeds even if metadata fails.
- **Stability**: Fixed a crash (`malloc(): smallbin double linked list corrupted`) and persistent `GtkStack` warnings in the file preview widget caused by race conditions during widget cleanup.

## [0.9.8.2] - 2026-01-24

### Fixed
- **Media**: Fixed inline playback for encrypted MOV/MP4 videos. Videos are now decrypted to a temporary file for playback with Gtk.Video/GStreamer.
- **UI**: Fixed `GtkStack` warnings ("child not found") in file preview widgets.
- **Localization**: Fixed a regression where English users were prompted for the database password in German.

## [0.9.8.1] - 2026-01-23

### Fixed
- **Stability**: Fixed a critical "double free" crash when canceling or completing encrypted file uploads (HTTP Upload / AES-GCM).
- **Performance**: Disabled checksum calculation for files larger than 50MB. This prevents UI freezes and "Source ID not found" crashes when sending large video files.

## [0.9.8.0] - 2026-01-19

### Added
- **Audio**: Implemented manual audio gain (post-processing) with a new UI slider to bypass WebRTC AGC limits. This allows increasing microphone volume significantly beyond standard levels.

## [0.9.7.9] - 2026-01-13

### Added
- **Audio/Video Backend**: Added native **PipeWire support** (`pipewiresrc`) as the primary audio source for Calls and Voice Notes. This massively improves stability and quality on modern Linux distributions (Mint, Fedora, Arch) and fixes "Device not found" errors.
- **Voice Notes**: Added a +8dB volume boost to voice messages to fix low microphone volume issues.
- **Voice Notes**: Enabled "Faststart" (Web Optimized) for MP4 recordings. This ensures compatibility with iOS devices and the Conversations app, which previously refused to play DinoX voice notes.

### Changed
- **Tor Manager**: Enhanced connection logic and settings UI:
    - Included a **Firewall Mode** to restrict Tor traffic to ports 80 and 443 only.
    - Added an intelligent **Bridge Filter** for OBFS4 that prioritizes bridges on ports 80/443 for better reachability in restrictive networks.
    - Improved UI clarity for adding custom bridges.
- **UI**: Various refinements to Conversation View, File Sending Overlay, and Dialogs for a smoother user experience.

### Fixed
- **Packaging**: Correctly bundled `gstreamer1.0-pipewire` in **AppImage** and compiled a minimal `pipewire` GStreamer plugin for **Flatpak**. This ensures the new PipeWire backend works reliably in sandboxed environments and prevents fallback to incompatible audio drivers.
- **UI Responsiveness**: Fixed layout rendering issues in the Preferences dialog (specifically Tor settings). The settings window now adapts correctly to narrow window sizes (mobile layout), ensuring all controls remain accessible without being cut off.

## [0.9.7.8] - 2026-01-12

### Fixed
- **Release Integrity**: Included all pending critical code fixes (Audio, Avatars, Refactoring) that were missing in v0.9.7.7 due to a build system error.
- **Audio Sensitivity**: Reverted internal digital gain boost from 15dB to safe 6dB default to prevent clipping/distortion with high-quality microphones (e.g., USB DACs).
- **Crash Fix**: Resolved a critical segmentation fault when ending video/voice calls caused by GStreamer buffer refcounting race conditions. Implemented deep buffer copying for the native WebRTC thread.

## [0.9.7.7] - 2026-01-12

### Note
- This release was tagged incorrectly without the intended code changes. Please use v0.9.7.8.

## [0.9.7.6] - 2026-01-11

### Fixed
- **Interoperability**: When setting a user avatar, it is now published to both PEP (XEP-0084, OMEMO-encrypted capable) and vCard-temp (XEP-0054, legacy compatibility). This fixes avatar visibility issues in clients like Conversations.

## [0.9.7.5] - 2026-01-10

### Fixed
- **AppImage**: Bundled missing GStreamer plugins (`libgstisomp4`, `libgstvoaacenc`) to fix AppImage audio recording error "Could not create GStreamer elements".
- **AppImage**: Bundled essential GStreamer audio conversion and playback elements (`audioconvert`, `playback`, `volume`) to ensure reliable audio I/O.

## [0.9.7.4] - 2026-01-10

### Fixed
- **Stability**: Added additional null-checks for peer fingerprints to preventing crashes if the Jingle negotiation is incomplete or malformed (further hardening against Monal interoperability issues).

## [0.9.7.3] - 2026-01-10

### Fixed
- **Stability**: Fixed a segmentation fault (crash) during video call setup when the remote client (e.g., Monal) does not specify a fingerprint hashing algorithm. Defaulting to SHA-256 in such cases.

## [0.9.7.2] - 2026-01-10

### Fixed
- **Call Interoperability**: Fixed video calls failing when initiated from DinoX to certain iOS clients (Monal/Siskin). 
  - Added support for **SHA-512**, **SHA-384**, and **SHA-1** DTLS fingerprints.
  - Added case-insensitive handling of fingerprint algorithms.

## [0.9.7.1] - 2026-01-10

### Added
- **Hardware Acceleration**: Added `gstreamer1.0-vaapi` to AppImage build to enable hardware-accelerated video enc/decoding (VAAPI) for smoother video calls and reduced CPU usage.

### Fixed
- **UI/Theming**: Removed usage of SVG icons in AppImage. Now enforcing PNG icons to resolve issue where icons appeared light/invisible on dark themes.

## [0.9.7.0] - 2026-01-10

### Added
- **Out-of-the-Box Tor & Privacy**
  - **Integrated Tor & Obfs4proxy**: The application now comes with Tor and Obfs4proxy pre-bundled and pre-configured for instant use (AppImage & Flatpak). No manual installation of Tor is required.
  - **Zero-Config Privacy**: Simply enable Tor in the account settings, and DinoX handles the process management, bridge configuration, and SOCKS5 proxy setup automatically.
  - **Stable Connectivity**: Implemented smart connection handling to wait for Tor circuits to stabilize before connecting XMPP, preventing connection errors on startup.

### Fixed
- **Startup Sync**: Solved race conditions where the account would try to connect before the local Tor process was ready.
- **Log Hygiene**: Reduced terminal noise by moving verbose connection logs to debug level, keeping the console clean for production use.

### Infrastructure
- **Universal Linux Support (Multi-Arch)**
  - Full automated build support for **Aarch64 (ARM64)** and **x86_64**, ensuring the "Out of the Box" privacy experience works on standard PCs, Raspberry Pis, and ARM laptops.

## [0.9.6.0] - 2026-01-09

### Added
- **Sender Identity Selection**
  - Select which account to use when starting a new chat (1:1).
  - Select account when joining or creating a Group Chat (MUC).
  - Chat Input displays the avatar of the currently selected sending account.
  - Accounts can be engaged/disabled in backend, hiding them from the UI.
- **In-Band Registration (XEP-0077)**
  - Register new accounts directly from the client.
    Portable Zip:   - Change password support.
  - Support for CAPTCHA forms (XEP-0158) and Data Forms validation.
- **UI Responsiveness**
  - Improved responsiveness in Room Browser Dialog (ellipsized text).
  - Fixed layout issues in "Create Group Chat" dialog for smaller screens.

### Changed
- Replaced deprecated `Gtk.ComboBoxText` with `Gtk.DropDown` for better GTK4 compliance.
- Improved "Add Conversation" workflow with integrated account selection.

## [0.9.5.0] - 2026-01-08

### Added
- **MUC Avatars (XEP-0486)**
  - Full support for setting, updating, and displaying group chat avatars.
  - Automatic resizing and conversion to PNG.
  - Robust persistence via vCard support on MUC JIDs.
- **Status UI**
  - Moved status selection from hamburger menu to a dedicated button in the header bar.
  - Status icon changes color based on reachability (Green/Orange/Red).

### Removed
- **Help Button**
  - "Join Channel Help" button removed from header bar.

## [0.9.4.0] - 2026-01-08

### Added
- **User Search Integration (XEP-0055)**
  - Implemented direct "Search Directory" option in the "Start Conversation" dialog.
  - Integration with server-side User Directories (JUD).
  - Improved handling of XEP-0004 Data Forms (`<item>` parsing support), enabling robust search results.
- **UI Tweaks**
  - Removed logo from empty chat placeholder for a cleaner look.

## [0.9.3.0] - 2026-01-02

### Added
- **Full Local Encryption**
  - All local files (`files/`, `avatars/`, `stickers/`) are now transparently encrypted at rest using AES-256-GCM.
  - Migrated `pgp.db` to SQLCipher (previously unencrypted).
- **Secure Deletion**
  - Added "Also delete for chat partner" option to "Clear History" dialog for 1:1 chats (triggers XEP-0424).
  - Implemented **Smart Throttling** for message retraction (max 5 msgs/sec) to prevent server disconnects/bans during bulk deletion.
  - Enforced zero-trace cleanup of decrypted cache files (`~/.cache/dinox`) on application exit (including Tray Quit).
- **UI Improvements**
  - Updated "About" dialog to correctly reflect data storage paths (`~/.local/share/dinox`).

## [0.9.2.0] - 2026-01-02

### Added
- **Encrypted File Upload**
  - Added support for encrypted file uploads in OMEMO-encrypted chats.
  - Implemented **AES-GCM URI Scheme** (`aesgcm://`) for compatibility with Conversations, Monal, and Gajim.
  - Implemented **XEP-0448** (Encryption for Stateless File Sharing) for future-proof, standard-compliant encryption.
  - Files are encrypted on-the-fly during upload (AES-256-GCM).
  - Keys are transmitted securely within the OMEMO-encrypted message.

## [0.9.1.0] - 2026-01-01

### Added
- **XEP Support**
  - Added support for vCard4 (XEP-0292).
  - Added support for User Nickname (XEP-0172).
  - Added fallback support for vCard-temp (XEP-0054).
- **Translations**
  - Added translations for Privacy settings in 47 languages.

### Fixed
- **System Tray**
  - Fixed issue where tray icon would not reappear after shell restart.
- **Application Lifecycle**
  - Fixed clean shutdown when using Ctrl+Q (now properly routed through SystrayManager).

## [0.9.0.0] - 2025-12-31

### Fixed
- **UI/Layout**
  - Fixed responsive layout for video player in chat (now scales correctly on smaller screens).
  - Fixed responsive layout for map previews (OSM) in chat (prevented full-width stretching).
  - Adjusted audio player layout for better responsiveness.
- **Translations**
  - Fixed syntax errors in translation files (PO) that caused build failures.
  - Updated and corrected fuzzy translations across multiple languages.

## [0.8.6.15] - 2025-12-31

### Added
- **Location Sharing (XEP-0080)**
  - Added ability to send current location (requires GeoClue2).
  - Added "Send Location" button to chat input menu.
  - Added "Share Location" toggle in Preferences (Privacy section).
  - Implemented XEP-0080 (User Location) for publishing location.
- **Geo URI / Map Preview**
  - Added inline map preview for `geo:` URIs (XEP-0080).
  - Added "Open OpenStreetMap" link and click-to-open behavior.
  - Added location marker pin.
- **Status & Presence**
  - Added "Status" menu to application menu (Online, Away, Busy, Not Available).
  - Added "Set Status Message..." dialog to set custom presence status.
  - Added presence status indicator (emoji) to conversation list rows.
- **Notifications**
  - Added "Mute/Unmute" button to conversation details dialog.
  - Added mute status indicator to conversation list rows.

## [0.8.6.14] - 2025-12-28

### Added
- **Sticker UI Refactor**
  - Redesigned Sticker Manager with modern UI.
  - Added support for APNG (Animated PNG) stickers.
  - Added "Share" and "Publish" buttons for sticker packs.
  - Added a "Close" button to the sticker chooser popover.

## [0.8.6.13] - 2025-12-28

### Fixed
- **UI/Dialogs**
  - Fixed "Leave Conversation" button in conversation details dialog not working.
  - Fixed responsiveness issues when opening conversation details from chat input (e.g., "You are not a member of this room").
  - Fixed empty dialogs by removing `show-title-buttons` property from UI files (Libadwaita 1.5+ compatibility).

## [0.8.6.12] - 2025-12-28

### Changed
- **Audio Tuning**
  - Reduced AGC compression gain from 9dB to 6dB to prevent amplification of residual echo.
  - Enabled WebRTC Transient Suppression to filter out impulsive noises (keyboard clicks, etc.).

## [0.8.6.11] - 2025-12-28

### Fixed
- **Calls (Echo Cancellation)**
  - Fixed a critical issue where AEC was not wired into the pipeline, causing severe echo for remote parties.
  - Enabled "Mobile Mode" and "Adaptive Digital" AGC for better audio quality on Linux devices.

### Changed
- **Build / Dependencies**
  - Removed support for the obsolete `webrtc-audio-processing` v0.3 library to prevent build regressions.
  - Flatpak and AppImage builds now strictly use `webrtc-audio-processing` v2.1 (Jan 2025).

## [0.8.6.10] - 2025-12-20

### Fixed
- **Calls (AppImage / GitHub Releases)**
  - Bundle the missing GStreamer `audiorate` plugin (`libgstaudiorate.so`) so 1:1 call audio works reliably (e.g., Monal interop).

## [0.8.6.9] - 2025-12-19

### Changed
- **Branding**
  - Replaced the DinoX logo/icon across the app (bundled icons), README, and website assets.

### Fixed
- **UI markup helper**
  - Avoid `string_slice` CRITICALs by guarding against invalid fallback slice ranges.

### Added
- **Calls (debug only)**
  - Extra VoiceProcessor init debug logging (AEC/NS/AGC/VAD flags) when debug logging is enabled.

## [0.8.6.8] - 2025-12-19

### Fixed
- **Startup (Flatpak)**
  - Fix a crash in the HTTP file upload plugin caused by re-entrant recursion when hopping to libsoup's main context.

## [0.8.6.7] - 2025-12-19

### Fixed
- **Build (Flatpak/AppImage)**
  - Fix Vala compile error by disambiguating `Spinner` between `Gtk.Spinner` and `Adw.Spinner`.

## [0.8.6.6] - 2025-12-19

### Security
- **Encrypted local data is now mandatory**
  - DinoX requires a password at startup to open the encrypted SQLCipher database (no plaintext fallback).
- **Panic wipe**
  - Added a Panic Wipe action (menu + shortcut `Ctrl+Shift+Alt+P`).
  - After 3 failed unlock attempts, DinoX wipes local data and exits.

### Added
- **Change database password**
  - Preferences → Database Maintenance → Change Database Password (SQLCipher `PRAGMA rekey`).
- **OpenPGP keyring isolation**
  - OpenPGP plugin uses an app-scoped `GNUPGHOME` so Panic Wipe removes OpenPGP material.

### Fixed
- **Guards against log spam / CRITICALs**
  - Avoid CRITICAL errors when message retraction is requested without a message reference ID.
  - Validate reply fallback ranges before slicing strings.
- **Flatpak SVG loader crash (stickers)**
  - Avoid triggering the gdk-pixbuf SVG loader from background metadata/thumbnail generation by blacklisting SVG mime types and skipping files that look like SVG/SVGZ (gzip).
- **Stickers import responsiveness**
  - Generate sticker thumbnails off the main thread to avoid UI stalls.
- **HTTP MainContext handling (libsoup)**
  - Avoid re-entrant recursion by using `GLib.MainContext.is_owner()` checks.
- **Unlock window placement (X11)**
  - Center the unlock window on X11 (best-effort; helps Cinnamon/Muffin).

## [0.8.6.4] - 2025-12-19

- Prevent crashes on sticker pack import/publish caused by SVG data mislabeled as raster images by sniffing file contents and skipping SVG thumbnail generation.
- Improve feedback for long-running sticker pack actions by disabling controls while operations are running.

## [0.8.6.3] - 2025-12-19

### Fixed
- **Sticker SVG crash (Flatpak)**
  - Avoid decoding/displaying SVG stickers in the UI (sticker chooser thumbnails + inline sticker rendering) to prevent gdk-pixbuf SVG loader crashes.

## [0.8.6.2] - 2025-12-18

### Fixed
- **Sticker pack import stability**
  - Avoid generating thumbnails for non-raster sticker types (e.g. SVG) during import to prevent Flatpak crashes.
- **Flatpak translations (GitHub bundle installs)**
  - Ship translations in the main app by disabling `separate-locales` in the Flatpak manifest.

## [0.8.6.1] - 2025-12-18

### Fixed
- **Flatpak startup stability**
  - Fixed libsoup assertion crash by ensuring HTTP sessions are used on their creating `GLib.MainContext`.
- **Sticker chooser (GTK4)**
  - Removed invalid `modal` popover property usage to avoid runtime GObject criticals.
- **Database (Qlite/SQLCipher)**
  - Reduced log noise for plaintext fallback and added best-effort automatic plaintext-encrypted migration when a key is provided.

## [0.8.6] - 2025-12-18

### Added
- **Stickers (XEP-0449)**
  - End-to-end support for sending and receiving stickers (`urn:xmpp:stickers:0`).
  - Sticker packs: import via `xmpp:` PubSub links, publish packs to PEP, and share pack URIs.
  - New preferences: **Enable Stickers** and **Enable Sticker Animations**.

### Fixed
- **GitHub AppImage: missing audio / media capabilities**
  - Bundled `gst-plugin-scanner` and resolved/copy shared-library dependencies recursively.
  - Improved GStreamer plugin discovery behavior to avoid silently missing WebRTC/audio/video elements.
- **Sticker chooser stability & performance**
  - Avoided reload spikes on chat switch by deferring heavy reloads until the popover is opened.
  - Fixed a thumbnail update use-after-free by using `WeakRef`-based lifetime checks.
- **GTK4 build compatibility**
  - Replaced deprecated `mapped` property usage with `get_mapped()`.

### Documentation / Translations
- Updated gettext extraction for sticker UI and refreshed translations (incl. German fixes for the new sticker settings).

### Changed
- **Media rendering / performance**
  - Animated sticker playback and inline video playback now react to visibility (mapped + in-viewport) to reduce CPU/battery usage.
  - Added a small first-frame cache for animated stickers to improve perceived performance.
  - File/image loads are cancellable to avoid blocking chat switching.
- **UI timing logs**
  - Added optional UI timing instrumentation via `DINOX_UI_TIMING`.
- **Release engineering (GitHub Actions)**
  - AppImage/Flatpak artifacts are versioned from tags and attached to the GitHub Release.
  - Release body generation now includes Flatpak bundle install instructions.

### Notes
- `webrtc-audio-processing` (AEC/NS/AGC) remains supported when present; builds remain functional without it.

## [0.8.5] - 2025-12-16

This release significantly improves 1:1 Jingle audio/video call interoperability with
**Conversations (Android)** and **Monal (iOS)** while keeping DinoX’s existing media stack
(GStreamer RTP/rtpbin + libnice ICE + DTLS-SRTP).

### Changed
- **Interop profile (WebRTC-compatible Jingle subset)**
  - Prefer **ICE-UDP** + **DTLS-SRTP** only (no SDES-SRTP) to match modern WebRTC clients.
  - Streamlined codec negotiation to a minimal baseline for better cross-client compatibility.
- **RTP jitter handling (Monal startup)**
  - Increased rtpbin latency and disabled aggressive startup dropping to eliminate initial “knacken”
    (audio crackle) reported with Monal.

### Fixed
- **Startup artifacts (DTLS/SRTP timing)**
  - Reduced audible pops/crackle at call start by handling packets that arrive before DTLS-SRTP is
    fully ready, instead of dropping them outright.
- **Call teardown robustness**
  - Addressed GLib signal disconnect warnings during cleanup (double-disconnect / stale handler IDs).
  - Adjusted ICE teardown ordering to avoid a libnice-related crash observed during TURN refresh
    cleanup paths.

### Technical
- **Codecs / negotiation**
  - Narrowed baseline call codecs to **Opus (audio)** and **VP8 (video)** for reliable interop.
  - Disabled legacy/optional paths that caused negotiation or compatibility issues (e.g. SDES-SRTP,
    Speex).
- **Audio processing (webrtc-audio-processing)**
  - Improved EchoProbe reverse-stream feeding stability (consistent 10ms chunking).
  - Stabilized delay estimation / stream delay adjustments to improve AEC convergence and reduce echo.

### Documentation
- **Debugging calls (reproducible logs)**
  - Added helper scripts for starting/stopping full-debug runs with reliable PID + log tracking:
    `scripts/run-dinox-debug.sh`, `scripts/stop-dinox.sh`, `scripts/scan-dinox-latest-log.sh`.
  - Extended `DEBUG.md` with a detailed, copy/paste workflow for collecting and scanning call logs.

### Notes
- DinoX now diverges more clearly from upstream Dino in the A/V call pipeline and interoperability
  focus. The goal is stable cross-client calling (Conversations/Monal) using the existing
  GStreamer/libnice/DTLS-SRTP stack rather than switching to a full Google/libwebrtc-based stack.
- Known noise: libnice may still emit “alive TURN refreshes” warnings on teardown in some setups;
  this is currently treated as a warning (no observed crash in follow-up runs).
- Thanks to sponsor **@jacquescomeaux** for supporting DinoX.

## [0.8.4] - 2025-12-03

### Added
- **WebRTC Video Calls** - Complete implementation of video calls
  - Added support for VP8, VP9, and H.264 codecs
  - Implemented ICE-TCP candidate support (RFC 6544) for better connectivity in restrictive networks
  - Improved codec negotiation logic
- **Security Hardening**
  - Fixed a Path Traversal vulnerability in file transfer (sanitizing filenames)
  - Verified and documented SQLCipher database encryption

## [0.8.3] - 2025-12-02

### Added
- **Video Codec Improvements** - Enhanced video call quality and compatibility
  - Enabled H.264 codec by default for better compatibility
  - Enabled VA-API hardware acceleration by default for GStreamer >= 1.26
  - Replaced deprecated VA-API elements with modern alternatives
  - Optimized x264 encoding speed preset (faster instead of ultrafast)
  - Added fallback to H.264 software decoder from ffmpeg/libav if hardware decoding fails
  - Removed VP9 support to streamline codec negotiation

## [0.8.2] - 2025-12-01

### Security
- **Database Encryption** - Implemented full database encryption using SQLCipher to protect local user data
- **System Hardening** - Improved overall system security and data protection

### Changed
- **Build Process** - Hardened build process and improved dependency management
- **Code Cleanup** - Removed internal development artifacts
- **Logging Improvements** - Replaced raw print statements with proper GLib structured logging (debug/warning) for better system integration
- **UI** - Updated copyright information in About dialog

## [0.8.1] - 2025-12-01

### Added
- **Full OpenPGP Localization** - Completed translations for all 47 supported languages
  - Added missing translations for OpenPGP key management and preferences
  - Languages updated: ar, bg, ca, cs, da, de, el, en, eo, es, et, eu, fa, fi, fr, gl, he, hi, hr, hu, ia, id, ie, is, it, ja, kab, ko, lb, lt, lv, nb, nl, oc, pl, pt, pt_BR, ro, ru, sq, sv, ta, th, tr, uk, vi, zh_CN, zh_TW

## [0.8.0] - 2025-12-01

### Added
- **Disappearing Messages** - Auto-delete messages after configurable time periods
  - Timer options: 15 minutes, 30 minutes, 1 hour, 24 hours, 7 days, 30 days
  - Per-conversation setting in conversation details
  - Visual banner in chat showing current auto-delete setting
  - Own messages deleted globally via XEP-0424 (server + local)
  - Received messages deleted locally only
  - Background timer checks every 5 minutes for expired messages
  - Database schema updated (version 34) with `message_expiry_seconds` column

- **MUC Password Bookmark Sync** - Room passwords now saved to bookmarks
  - When changing room password in settings, bookmark is automatically updated
  - Fixes issue where room password changes prevented auto-join on restart

### Technical
- New `expiry_notification.vala` for chat banner display
- Extended `ContentItemStore` with `get_items_older_than()` method
- Extended `MessageDeletion` with timer and expiry checking
- Extended `Conversation` entity with `message_expiry_seconds` property
- Extended `muc_manager.vala` to sync password changes to bookmarks

## [0.7.9] - 2025-11-30

### Added
- **OpenPGP Key Management Dialog** - New dedicated dialog for managing PGP keys
  - Key selection dropdown showing all available secret keys
  - Key fingerprint display with proper formatting
  - Generate new PGP key functionality (creates ED25519 key with 2-year expiry)
  - Delete key button with confirmation dialog
  - Password verification before key operations

### Fixed
- **Window Size Bug** - Fixed window not appearing after factory reset
  - Added minimum window size (400x300) to prevent invisible windows
  - Fallback to default 900x600 when config values are 0 or invalid
  
- **OMEMO Decryption Logging** - Added more debug output for session issues
  - Logs sender address when starting/continuing session for decryption
  - Helps diagnose OMEMO session desynchronization problems

### Changed
- **Certificate Pinning UI** - Simplified certificate display
  - Show SHA-256 in addition to SHA-1 fingerprint
  - Better fingerprint formatting with colons

### Technical
- New `key_management_dialog.vala` for OpenPGP key operations
- Extended GPGHelper with `get_all_key_info()` for CLI-based key name retrieval
- Improved OMEMO debug logging in `decrypt.vala`

## [0.7.8] - 2025-11-30

### Added
- **TLS Certificate Pinning** - Support for self-hosted XMPP servers with self-signed certificates
  - Certificate trust/pin dialog like Conversations Android (GitHub issue #1801)
  - Shows certificate details: SHA-256 fingerprint, issuer, validity period
  - "Trust Certificate" button in account preferences when TLS errors occur
  - Stores pinned certificate fingerprints in database
  - Supports unpinning/removing trusted certificates

### Technical
- New `pinned_certificate` database table (database version 33)
- `CertificateManager` service for fingerprint calculation and validation
- Extended `ConnectionError` with TLS certificate and flags properties
- Extended `XmppStreamResult` with peer certificate property

## [0.7.7] - 2025-11-30

### Added
- **Database Maintenance** - New "Clean Database" option in hamburger menu
  - Removes orphaned records (messages without conversation, etc.)
  - VACUUM optimization for smaller database files
  - Shows count of cleaned entries

- **Backup & Restore** - Complete data backup functionality
  - Full backup of `~/.local/share/dinox/` and `~/.config/dinox/`
  - Optional **GPG encryption** with AES-256 (password-protected)
  - Restore from unencrypted (`.tar.gz`) or encrypted (`.tar.gz.gpg`) backups
  - Automatic detection of encrypted backups
  - All settings (Dark/Light mode, etc.) correctly restored
  - Automatic app restart after restore

### Fixed
- **Backup Restore** - Settings no longer overwritten on shutdown after restore
  - Uses `Process.exit(0)` instead of `quit()` to preserve restored data
  
- **Password Dialogs** - Improved UX for backup password entry
  - Enter key now works properly (no double-click needed)
  - Uses `Gtk.PasswordEntry` for better focus handling

### Technical
- GPG integration with `--pinentry-mode loopback` for headless password handling
- Secure password handling with `Shell.quote()`
- Progress spinner during backup/restore operations

## [0.7.6] - 2025-11-29

### Fixed
- **Call Stability** - Fixed null pointer crash in GStreamer device cleanup
- **OMEMO Call Sessions** - Auto-refresh stale OMEMO bundles when call decryption fails
- **Audio Quality** - Prefer Opus codec (48kHz) over legacy PCMA (8kHz) for much better sound

### Changed
- Volume slider now only shown in group calls (not needed for 1:1 calls)
- Codec selection prioritizes high-quality codecs: Opus > Speex > G.722 > PCMU > PCMA

## [0.7.5] - 2025-11-29

### Added
- **Individual Volume per Participant** - Each call participant has their own volume slider
  - Volume slider visible on hover over participant video
  - Icon changes based on volume level (muted/low/medium/high)
  - Works for 1:1 calls and MUJI group calls
  - Real-time adjustment of incoming audio per participant

- **V4L2 Hardware Decoding** - ARM device support (Raspberry Pi, etc.)
  - V4L2 stateful decoder support (opt-in)
  - V4L2 stateless decoder support (auto, requires GStreamer 1.26+)
  - H.264, VP8, VP9 hardware decoding on ARM
  - Based on dino/dino#1781 by Robert Mader

### Changed
- Updated VAAPI decoder names to new `va*` prefix (vah264dec, vavp8dec, vavp9dec)
- About dialog: "DinoX Maintainer" now listed first, "Dino Project" instead of "original authors"

## [0.7.4] - 2025-11-29

### Added
- **Volume Controls** - Microphone and speaker volume sliders in call settings
  - Slider controls for microphone input level
  - Slider controls for speaker output level
  - Works for 1:1 calls and MUJI group calls
  - Real-time volume adjustment during calls

### Changed
- Updated website with new screenshots
- Added new development plan

## [0.7.3] - 2025-11-29

### Fixed
- **GStreamer Plugin Scanner** - Fixed "External plugin loader failed" warning
  - Removed bundled gst-plugin-scanner (doesn't work without libc)
  - Set GST_REGISTRY_FORK=no to avoid forking issues
  - AppImage now uses system gst-plugin-scanner with proper fallbacks
  - Based on GStreamer documentation and msys2/MINGW-packages#20492

## [0.7.2] - 2025-11-29

### Fixed
- **AppImage System Libraries** - Fixed crashes caused by bundled system libraries
  - Removed blacklisted libraries (libc, libstdc++, libX11, libwayland, etc.)
  - AppImage now uses host system libraries as required by AppImage specification
  - Fixes "undefined symbol: __tunable_is_initialized" errors
  - Should now pass AppImageHub compatibility tests

### Added
- **AppImage Auto-Updates** - zsync support for delta updates
  - AppImage can now update itself using appimagetool's built-in updater
  - Generates .zsync file alongside AppImage for efficient updates
  - Uses GitHub Releases as update source

### Changed
- **Website & Documentation** - Updated download references
  - Website now points to GitHub Releases for downloads
  - README updated to use GitHub Releases

## [0.7.1] - 2025-11-28

### Changed
- **Dark Theme as Default** - DinoX now starts with dark theme by default
  - New installations will have dark mode enabled automatically
  - Existing users keep their chosen setting
  - Can still be changed in Preferences → General → Appearance

### Fixed
- **AppImage Audio/Video Support** - Fixed voice and video calls in AppImage builds
  - Added missing GStreamer plugins: `gstreamer1.0-nice`, `pulseaudio`, `pipewire`, `alsa`, `v4l2`
  - Fixed `gst-plugin-scanner` path for proper plugin detection
  - Bundled all required WebRTC plugins (nice, srtp, dtls, webrtc)
  - Camera and microphone now properly detected in AppImage

- **AppImage Locale Support** - Fixed translations not working in AppImage
  - Added `TEXTDOMAINDIR` environment variable support
  - AppImage now respects system locale (LANG, LC_ALL)
  - All 45 languages now work correctly in AppImage builds

### Documentation
- **BUILD.md Updated** - Added missing build dependencies
  - Added `gstreamer1.0-nice` to Debian/Ubuntu build instructions
  - Added `gstreamer1-plugins-bad-free-extras` to Fedora instructions
  - New "AppImage Build" section with complete build guide
  - GStreamer plugin troubleshooting section added

## [0.7] - 2025-11-28

### Changed
- **Complete Translation Overhaul** - All 45 languages now at 100% translation coverage (361/361 strings)
  - Previously: Most languages were at 70-85%
  - Now: Every single language is fully translated
  - Languages: Arabic, Catalan, Czech, Danish, German, Greek, Esperanto, Spanish, Estonian, Basque, Persian, Finnish, French, Galician, Hindi, Hungarian, Armenian, Indonesian, Interlingue, Icelandic, Italian, Japanese, Kabyle, Korean, Luxembourgish, Lithuanian, Latvian, Norwegian Bokmål, Dutch, Occitan, Polish, Portuguese, Brazilian Portuguese, Romanian, Russian, Sinhala, Albanian, Swedish, Tamil, Thai, Turkish, Ukrainian, Vietnamese, Chinese (Simplified), Chinese (Traditional)

## [0.6.9] - 2025-11-28

### Added
- **Backup User Data** - Complete data backup functionality in Preferences → General
  - One-click backup of all DinoX data (database, keys, settings)
  - Creates timestamped `.tar.gz` archive (e.g., `dinox-backup-20251128-143022.tar.gz`)
  - File chooser dialog to select save location
  - Progress notification with toast messages
  - Success notification shows backup file size
  - Includes both `~/.local/share/dinox` and `~/.config/dinox` directories

- **User Data Locations** - View data paths in Preferences → General
  - Shows Config, Data, and Cache directory locations
  - Helpful for manual backup or troubleshooting
  - Info dialog with backup instructions

- **MUC Room Privacy Control** - Comprehensive room privacy management
  - Automatic OMEMO enable/disable when room privacy changes
  - When room becomes **public**: OMEMO automatically disabled with warning
  - When room becomes **private**: OMEMO automatically enabled
  - System notification messages sent to room when privacy changes
  - Automatic member addition when switching to members-only (prevents Status 322 kicks)
  - Feature cache refresh after config change (lock icon updates immediately)

### Improved
- **MUC Tooltip Enhancements** - Better room information display
  - Room subject/topic now displayed in conversation list tooltips
  - Tooltip shows: Account, Room JID, Subject, Member count
  - First line of multi-line subjects shown with "..." indicator
  - Empty subjects hidden from tooltip (cleaner display)
  
- **MUC Room Name Updates** - Room configuration changes now properly reflected
  - Bookmark name updated when room name changed in config
  - Room name in sidebar updates immediately after config change
  - Room info refresh triggered after configuration saved

### Technical Details
- Backend: `libdino/src/service/muc_manager.vala` - Extended `set_config_form` with privacy detection
- New function: `add_occupants_as_members()` - Auto-adds users when switching to members-only
- New function: `send_room_notification()` - Sends groupchat messages about privacy changes
- New function: `refresh_features()` in `entity_info.vala` - Invalidates and refreshes entity cache
- UI: `encryption_button.vala` - Added `check_encryption_validity()` for auto OMEMO toggle
- UI: `application.vala` - Added `create_backup()` and `perform_backup()` functions

## [0.6.8] - 2025-11-27

### Added
- **Dark Mode Toggle** - Manual color scheme control in Preferences → General
  - New "Appearance" section with "Color Scheme" dropdown
  - Three options: "Default (Follow System)", "Light", "Dark"
  - Instant switching - Changes apply immediately without restart
  - Persistent setting saved to database
  - Implementation: `Adw.StyleManager` with `FORCE_LIGHT`, `FORCE_DARK`, or `DEFAULT` modes

### Technical Details
- Backend: `libdino/src/entity/settings.vala` - Added `color_scheme` property
- UI: New "Appearance" preferences group with ComboRow
- Live updates: `settings.notify["color-scheme"]` signal triggers instant theme change
- No restart required - immediate visual feedback

## [0.6.7] - 2025-11-27

### Added
- **Browse Contacts** - New contact browser dialog in Start Conversation
  - Click magnifying glass icon to browse all roster contacts
  - Search/filter contacts by name or JID
  - Square avatars matching system design (unlike round MUC avatars)
  - Consistent UX with Browse Rooms dialog
  - Implementation: `main/src/ui/add_conversation/contact_browser_dialog.vala`

### Improved
- **Browse Rooms Enhancements** - Better MUC discovery and joining experience
  - Deduplicate rooms by JID (fixes confusing "dinomuc (2)" duplicate entries)
  - Display member count as subtitle ("N members" parsed from room names)
  - Mark already-joined rooms with green "Joined" label
  - Change button to "Open" for joined rooms (was "Join")
  - Double-click joined rooms to open conversation directly
  - Filter out already-joined rooms from Join Channel suggestions
  - Implementation: `main/src/ui/add_conversation/room_browser_dialog.vala`

### Fixed
- **Leave Group** - Now actually leaves MUC rooms instead of just removing bookmark
  - Previous "Delete Group" only removed bookmark, didn't send room part
  - Now calls `MucManager.part()` before `remove_bookmark()`
  - Renamed to "Leave Group" for clarity
  - Implementation: `main/src/ui/add_conversation/add_conference_dialog.vala`
- **Placeholder Text** - Context-specific search field hints
  - "Search or enter channel address..." for Join Channel dialog
  - "Search or enter contact address..." for Start Conversation dialog
- **Compiler Warnings** - Removed 2 unreachable catch clause warnings
  - Fixed `Bus.get_proxy()` error handling (only throws IOError, not generic Error)
  - Removed try-catch from `int.parse()` (doesn't throw exceptions)
  - Fixed `new Jid()` to catch specific `InvalidJidError` instead of generic `Error`

## [0.6.6] - 2025-11-27

### Added
- **Conversation List Context Menu** - Right-click context menu on conversation entries in sidebar
  - **MUC Options**: Conversation Details, Invite Contact, Mute/Unmute, Delete Conversation History, Leave and Close
  - **1:1 Chat Options**: Conversation Details, Edit Alias, Mute/Unmute, Block/Unblock, Delete Conversation History, Remove Contact
  - Provides unified UX matching three-dot menu functionality
  - Especially useful for quick MUC invitations directly from bookmarks
  - Implementation: `main/src/ui/conversation_selector/conversation_selector_row.vala`

### Changed
- **MUC Invite Access** - Invite feature now accessible from three locations:
  1. Occupant menu (user icon in titlebar)
  2. Three-dot menu in conversation titlebar
  3. Right-click context menu on conversation list _(new)_

## [0.6.5.5] - 2025-11-27

### Fixed
- **OMEMO Decryption Bug** - Fixed critical bug where incoming OMEMO encrypted messages showed "[This message is OMEMO encrypted]" in old/inactive chats after DinoX restart
  - Root cause: Other clients had stale device list cache with old DinoX device ID
  - Solution: Force republish device list on connect to notify all subscribers
  - Impact: Encryption now works immediately after restart without sending a message first
  - See OMEMO_BUG_FIX.md for detailed technical analysis

## [0.6.5.4] - 2025-11-27

### Added
- **Background Mode Toggle** - New "Keep Running in Background" setting in Preferences → General
  - ON (default): Window closes to systray, app keeps running
  - OFF: Window close triggers application quit
  - Systray Quit menu properly disconnects XMPP and exits process cleanly
  - Fixes Flatpak background process issue with proper Process.exit(0)

### Fixed
- **Desktop Notifications** - Resolved notification system deadlock that prevented notifications from appearing
  - Fixed infinite wait in register_notification_provider()
  - First provider now set immediately without waiting
  - Desktop notifications for incoming messages and calls now work correctly

## [0.6.5.3] - 2025-11-25

### Added
- **MUJI Group Calls - Phase 1** - Complete implementation of XEP-0272 (Jingle Multiparty) UI enhancements
  - **Participant List Sidebar** - Live participant list during group calls with connection status
  - **Private Room Creation** - Checkbox "Create as private room" automatically configures rooms as members-only, non-anonymous, and persistent
  - **Private Room Indicator** - Lock icon in conversation list and group chat dialogs for private rooms
  - **MUC Server Warning** - Warning dialog when no default conference server is configured
  - **Group Call Button** - "Start group call" button now only visible for MUC conversations

### Fixed
- **Entity Capabilities** - Fixed XEP-0115 hash mismatch handling by saving disco#info data with computed hash as fallback, improving MUJI capability detection

### Documentation
- **MUJI_GROUP_CALLS.md** - Complete guide for MUJI group calls (414 lines)
- **MUJI_IMPROVEMENTS.md** - Detailed implementation plan and bug tracker (691 lines)

## [0.6.5.2] - 2025-11-24

### Fixed
- **SFS (Stateless File Sharing)** - Fixed file sharing in MUC private messages
  - Added support for GROUPCHAT_PM conversation type
  - Fixed null file_sharing_id handling to prevent crashes
  - Parse SFS metadata (mime_type) from incoming messages
- **Audio Player** - Fixed voice message playback in private conversations
  - Added automatic download for received audio files
  - Fixed file availability check before pipeline setup
- **Video Player** - Fixed video display in private conversations
  - Added automatic download for received video files
  - Parse mime_type from SFS element for correct widget selection

## [0.6.5.1] - 2025-11-24

### Fixed
- **Video Player Layout** - Fixed video sizing issues where videos appeared too small or expanded beyond chat boundaries
  - Videos now have consistent size (400x225 pixels, 16:9 aspect ratio)
  - AspectFrame maintains proper aspect ratio for all video formats
  - MediaControls width matches video width (400px)
- **Video Player UI** - Resolved UI conflicts and positioning issues
  - Videos appear left-aligned next to username (not full-width)
  - Message actions (Reply, Reaction, Delete) remain visible on the right
  - Video menu (Open, Save) positioned top-left to avoid conflicts
  - Eliminated size jumps when loading multiple videos in chat
- **Video Format Support** - Enhanced codec compatibility
  - MP4 playback working correctly
  - MOV (iPhone) playback working correctly  
  - WebM playback working correctly with GStreamer plugins

## [0.6.5] - 2025-11-23

### Added
- **Video Player** - Implemented a robust video player using `Gtk.AspectFrame` and `Gtk.MediaFile` for stable playback in chat.
- **Flatpak Codecs** - Added `org.freedesktop.Platform.ffmpeg-full` extension to Flatpak manifest to support H.264/HEVC (iPhone/Android videos) out of the box.

### Fixed
- **Chat Layout** - Prevented chat view from collapsing when displaying video messages.

## [0.6.4] - 2025-11-23

### Added
- **Audio Recording** - Switched to **m4a/AAC** format (MPEG-4 container, AAC-LC, 44.1kHz, 64kbps) for full compatibility with Android (Conversations) and iOS (Monal/Siskin).
- **Audio Streaming** - Enabled `faststart` (moov atom at beginning) for instant playback of voice messages.

### Fixed
- **Zombie Process** - Fixed application hang on exit caused by incorrect GStreamer deinitialization.
- **Message Deletion** - Fixed deleted messages reappearing after restart (implemented persistent "hide" flag in database).
- **File Deletion** - Fixed missing context menu for file messages, allowing deletion of all file types.
- **Quote Interaction** - Fixed right-click on quoted messages triggering "jump to message" instead of opening the context menu.
- **Empty Messages** - Prevented sending empty or whitespace-only messages which caused "Message deleted" errors.
- **Flatpak Audio** - Added missing permissions (`org.freedesktop.ScreenSaver`, `org.mpris.MediaPlayer2.Dino`) to ensure audio recording/playback works correctly in Flatpak.

## [0.6.3] - 2025-11-23

### Added
- **Timed Bans** - Ban users from MUCs for 10, 15, or 30 minutes (auto-unban).
- **Moderation Menu** - Comprehensive menu for MUC admins/owners:
    - Kick users
    - Ban users (Permanent or Timed)
    - Change Affiliations (Make Admin, Make Owner, Make Member, Revoke)
    - Mute/Unmute users (Voice management)
- **UI Polish** - Improved occupant menu layout:
    - Left-aligned buttons for better readability
    - Compact spacing
    - Section headers (Moderation, Administration)

### Fixed
- **Server Compatibility** - Added workaround for servers missing Status Code 110 (Self-Presence).
- **Menu Behavior** - Fixed popup menu not closing after action selection.

## [0.6.2] - 2025-11-22

### Added
- **Message Retraction** - Added "Delete for everyone" vs "Delete locally" dialog (XEP-0424).

### Fixed
- **Systray Icon** - Fixed missing permissions in Flatpak manifest (`org.kde.StatusNotifierWatcher`).
- **Release Notes** - Cleaned up release notes format.

## [0.6.1] - 2025-11-22

### Added
- **User Status** - Set global presence status (Online, Away, DND, Invisible) via main menu.

### Fixed
- **Flatpak Build** - Fixed `libdbusmenu` installation path issue causing build failures.

## [0.6.0] - 2025-11-21

**First release of DinoX!**

### Added
- **Systray Support** (#98) - StatusNotifierItem with libdbusmenu
- **Background Mode** (#299) - Keep running when window closed
- **Custom Server Settings** (#115) - Advanced connection options
- **Delete Conversation History** (#472) - Clear chat with XEP-0425 persistence
- **Contact Management Suite**:
  - Central Contacts management page in Preferences
  - Edit contact names with duplicate detection
  - Mute contacts (disable notifications)
  - Block contacts (XEP-0191 Blocking Command)
  - Remove contacts from roster with full cleanup
  - Right-click context menu on conversation rows
  - Visual status badges (mute icon, block icon)
- **XEP-0191** (Blocking Command) - Full UI implementation
- **XEP-0424** (Message Retraction) - Backend support for delete history
- **XEP-0425** (Message Moderation) - Backend support for MUC

### Fixed
- **Memory Leak** (#1766) - MAM cleanup prevents GB RAM growth
- **File Transfer Crash** (#1764) - Segfault on upload error
- **Message Sync** (#1746) - MAM/Carbon messages no longer lost
- **Long Messages** (#1779) - Increased limit to 100k characters
- **OMEMO Offline Messages** (#440) - Fixed unreadable messages
- **OMEMO File Transfer** (#752) - Can now send files with encryption
- **Call Connection** (#1271) - No longer stuck with Conversations app
- **File Button Bug** (#1796) - UI button now visible
- **Avatar Deletion** - Added remove avatar button
- **Edit/Delete Message Buttons** - Fixed GTK4 migration issues
- **Blocking Manager** - Fixed immediate UI updates

### Changed
- **GTK4 Migration** - Complete migration to GTK4 4.14.5
- **Libadwaita 1.5** - Updated to latest version
- **Database Schema v32** - Added `history_cleared_at` column
- **MAM Batch Size** - Increased from 20 to 200 for faster sync
- **Message Display** - 10k → 100k character limit
- **Project Rebranding**:
  - Binary renamed: `dino` → `dinox`
  - App ID changed: `im.dino.Dino` → `im.github.rallep71.DinoX`
  - All icons renamed to DinoX branding
  - Repository moved to `rallep71/dinox`
  - Professional logo and badges
- **Icon Installation** - Added PNG icons (16px-512px) for systray support
- **Build System**:
  - GitHub Actions CI/CD with Flatpak builds
  - Multi-architecture support (x86_64, aarch64)
  - Automated releases with artifacts

### Removed
- Archive conversation feature (doesn't fit XMPP model)

### Technical
- 0 GTK deprecation warnings
- 541 build targets compile cleanly
- XEP compliance: 60+ protocols supported
- Full OMEMO support with history management
- Flatpak packaging with complete dependency management
- libdbusmenu integration for StatusNotifierItem/AppIndicator support
- Meson build system with automated translations (50+ languages)

[Unreleased]: https://github.com/rallep71/dinox/compare/v0.8.6.12...HEAD
[0.8.6.12]: https://github.com/rallep71/dinox/releases/tag/v0.8.6.12
[0.8.6.11]: https://github.com/rallep71/dinox/releases/tag/v0.8.6.11
[0.8.6.10]: https://github.com/rallep71/dinox/releases/tag/v0.8.6.10
[0.8.6.9]: https://github.com/rallep71/dinox/releases/tag/v0.8.6.9
[0.8.6.8]: https://github.com/rallep71/dinox/releases/tag/v0.8.6.8
[0.8.6.7]: https://github.com/rallep71/dinox/releases/tag/v0.8.6.7
[0.8.6.6]: https://github.com/rallep71/dinox/releases/tag/v0.8.6.6
[0.8.6.4]: https://github.com/rallep71/dinox/releases/tag/v0.8.6.4
[0.8.6.3]: https://github.com/rallep71/dinox/releases/tag/v0.8.6.3
[0.8.6.2]: https://github.com/rallep71/dinox/releases/tag/v0.8.6.2
[0.8.6.1]: https://github.com/rallep71/dinox/releases/tag/v0.8.6.1
[0.8.6]: https://github.com/rallep71/dinox/releases/tag/v0.8.6
[0.8.5]: https://github.com/rallep71/dinox/releases/tag/v0.8.5
[0.7.3]: https://github.com/rallep71/dinox/releases/tag/v0.7.3
[0.7.2]: https://github.com/rallep71/dinox/releases/tag/v0.7.2
[0.7.1]: https://github.com/rallep71/dinox/releases/tag/v0.7.1
[0.7.8]: https://github.com/rallep71/dinox/releases/tag/v0.7.8
[0.7.7]: https://github.com/rallep71/dinox/releases/tag/v0.7.7
[0.7.6]: https://github.com/rallep71/dinox/releases/tag/v0.7.6
[0.7.5]: https://github.com/rallep71/dinox/releases/tag/v0.7.5
[0.7.4]: https://github.com/rallep71/dinox/releases/tag/v0.7.4
[0.7.3]: https://github.com/rallep71/dinox/releases/tag/v0.7.3
[0.7.2]: https://github.com/rallep71/dinox/releases/tag/v0.7.2
[0.7.1]: https://github.com/rallep71/dinox/releases/tag/v0.7.1
[0.7]: https://github.com/rallep71/dinox/releases/tag/v0.7
[0.6.9]: https://github.com/rallep71/dinox/releases/tag/v0.6.9
[0.6.8]: https://github.com/rallep71/dinox/releases/tag/v0.6.8
[0.6.7]: https://github.com/rallep71/dinox/releases/tag/v0.6.7
[0.6.6]: https://github.com/rallep71/dinox/releases/tag/v0.6.6
[0.6.5.5]: https://github.com/rallep71/dinox/releases/tag/v0.6.5.5
[0.6.5.4]: https://github.com/rallep71/dinox/releases/tag/v0.6.5.4
[0.6.5.3]: https://github.com/rallep71/dinox/releases/tag/v0.6.5.3
[0.6.5.2]: https://github.com/rallep71/dinox/releases/tag/v0.6.5.2
[0.6.5.1]: https://github.com/rallep71/dinox/releases/tag/v0.6.5.1
[0.6.5]: https://github.com/rallep71/dinox/releases/tag/v0.6.5
[0.6.3]: https://github.com/rallep71/dinox/releases/tag/v0.6.3
[0.6.2]: https://github.com/rallep71/dinox/releases/tag/v0.6.2
[0.6.1]: https://github.com/rallep71/dinox/releases/tag/v0.6.1
[0.6.0]: https://github.com/rallep71/dinox/releases/tag/v0.6.0
