# Changelog

All notable changes to DinoX will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
- **Stickers import responsiveness**
  - Generate sticker thumbnails off the main thread to avoid UI stalls.
- **HTTP MainContext handling (libsoup)**
  - Avoid re-entrant recursion by using `GLib.MainContext.is_owner()` checks.
- **Unlock window placement (X11)**
  - Center the unlock window on X11 (best-effort; helps Cinnamon/Muffin).

## [0.8.6.5] - 2025-12-19

### Fixed
- **Flatpak SVG loader crash (stickers)**
  - Avoid triggering the gdk-pixbuf SVG loader from background metadata/thumbnail generation by blacklisting SVG mime types and skipping files that look like SVG/SVGZ (gzip).

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
  - Reduced log noise for plaintext fallback and added best-effort automatic plaintextencrypted migration when a key is provided.

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

[Unreleased]: https://github.com/rallep71/dinox/compare/v0.8.6.6...HEAD
[0.8.6.6]: https://github.com/rallep71/dinox/releases/tag/v0.8.6.6
[0.8.6.5]: https://github.com/rallep71/dinox/releases/tag/v0.8.6.5
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
