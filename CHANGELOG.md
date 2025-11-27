# Changelog

All notable changes to DinoX will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.6.8] - 2025-11-27

### Added
- **Dark Mode Toggle** - Manual color scheme control in Preferences → General
  - New "Appearance" section with "Color Scheme" dropdown
  - Three options: "Default (Follow System)", "Light", "Dark"
  - **Instant switching** - Changes apply immediately without restart
  - Persistent setting saved to database
  - Fixes upstream issue [#1752](https://github.com/dino/dino/issues/1752) (requested by 54+ users)
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
  - **Participant List Sidebar** - Live participant list during group calls with connection status (✓ connected, ⟳ connecting)
  - **Private Room Creation** - Checkbox "Create as private room" automatically configures rooms as members-only, non-anonymous, and persistent
  - **Private Room Indicator** - 🔒 icon in conversation list and group chat dialogs for private rooms
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

**First release as DinoX - Complete fork and rebranding!**

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

## [0.5.0] - Upstream Base

This is the base version from [dino/dino](https://github.com/dino/dino) that we forked from.

[Unreleased]: https://github.com/rallep71/dinox/compare/v0.6.5...HEAD
[0.6.5.2]: https://github.com/rallep71/dinox/releases/tag/v0.6.5.2
[0.6.5.1]: https://github.com/rallep71/dinox/releases/tag/v0.6.5.1
[0.6.5]: https://github.com/rallep71/dinox/releases/tag/v0.6.5
[0.6.3]: https://github.com/rallep71/dinox/releases/tag/v0.6.3
[0.6.2]: https://github.com/rallep71/dinox/releases/tag/v0.6.2
[0.6.1]: https://github.com/rallep71/dinox/releases/tag/v0.6.1
[0.6.0]: https://github.com/rallep71/dinox/releases/tag/v0.6.0
[0.5.0]: https://github.com/dino/dino/releases/tag/v0.5.0
