# DinoX - Development Plan

> **Fork Status**: Modern XMPP client - Independent development branch of [dino/dino](https://github.com/dino/dino)  
> **Last Updated**: November 22, 2025  
> **Version**: 0.6.2  
> **Original Repository**: https://github.com/dino/dino (572 open issues)

---

## Quick Links

- [Build Instructions](docs/BUILD.md)
- [Release Guide](docs/RELEASE.md)
- [Architecture Guide](docs/ARCHITECTURE.md)
- [XMPP Extensions Support](docs/XEP_SUPPORT.md)
- [XEP UI Implementation Analysis](docs/XEP_UI_ANALYSIS.md)
- [Database Schema](docs/DATABASE_SCHEMA.md)
- [Contributing Guidelines](docs/CONTRIBUTING.md)

---

## Mission Statement

DinoX addresses the slow development pace of the original Dino XMPP client while maintaining full XMPP protocol compliance. We focus on:

1. **Stability First** - Fix critical crashes, data loss, and memory leaks
2. **Modern UX** - Implement missing features users expect in 2025
3. **Performance** - Optimize database, reduce memory footprint
4. **Community-Driven** - Transparent development, fast issue response

---

## Current Status (November 20, 2025)

| Metric | Status | Details |
|--------|--------|---------|
| **XEPs Implemented** | ✓ 60+ | One of most compliant XMPP clients |
| **Open Upstream Issues** | ! 566 remaining | **Major cleanup** (Phase 1 & 2 completed) |
| **Database Schema** | ✓ **v32** | Custom server support + **persistent history clear** |
| **Memory Leaks** | ✓ Fixed | Issue #1766 - MAM cleanup implemented |
| **File Transfer Crashes** | ✓ Fixed | Issue #1764 - Stream cleanup on error |
| **Code Stability** | ✓ **High** | **0 Compiler Warnings**, Async/Error safety enforced |
| **GTK4 Migration** | ✓ Complete | Edit/delete buttons fixed, 0 deprecation warnings |
| **Message History** | ✓ **NEW** | Delete Conversation History with OMEMO support |
| **Contact Management** | ✓ **NEW** | Full roster management with block/mute features |
| **Systray** | ✓ Implemented | Issue #98 - StatusNotifierItem (108👍) |
| **Background Mode** | ✓ Implemented | Issue #299 - Keep running when window closed (54👍) |
| **Custom Server** | ✓ Implemented | Issue #115 - Advanced connection settings (26👍) |
| **Tech Stack** | ✓ Modern | GTK4 4.14.5, libadwaita 1.5, Meson, Vala |
| **Platform Support** | ! Linux Only | Desktop focus (GNOME/KDE) |
| **Build Status** | ✓ Clean | 541 targets, 0 errors, 0 GTK warnings |

---

## Development Roadmap

### Phase 1: Critical Stability (Q1 2026 - v0.6.0)

**Goal**: Make Dino rock-solid for daily use

| Priority | Issue | Component | Impact | Status |
|----------|-------|-----------|--------|--------|
| P0 | [#1764](https://github.com/dino/dino/issues/1764) | File Transfer | Segfault on upload error | ✓ FIXED |
| P0 | [#1766](https://github.com/dino/dino/issues/1766) | Memory | RAM grows to GB over days | ✓ FIXED |
| P1 | [#1746](https://github.com/dino/dino/issues/1746) | Sync | MAM/Carbon messages lost | ✓ FIXED |
| P1 | [#1779](https://github.com/dino/dino/issues/1779) | UX | Long messages truncated/unreadable | ✓ FIXED |

> **Note**: Issue [#1784](https://github.com/dino/dino/issues/1784) (database crash on long messages) was already fixed in upstream commit [d625058d](https://github.com/dino/dino/commit/d625058d) (Sept 2025). Database schema v30 uses TEXT columns supporting unlimited message size.

**Files Modified**:
- ✓ `libdino/src/service/file_manager.vala` - Stream cleanup on error (issue #1764)
- ✓ `libdino/src/service/history_sync.vala` - MAM stanza cleanup on error (issue #1766)
- ✓ `xmpp-vala/src/module/xep/0059_result_set_management.vala` - Page size 20→200 (issue #1746)
- ✓ `main/src/ui/conversation_content_view/message_widget.vala` - Limit 10k→100k chars (issue #1779)

**Status**: ✓ **COMPLETED** (November 19, 2025)  
**Time Spent**: 1 day  
**Commits**: `b65d6b72`, `65b8f47e`, `c3024d71`

---

### Phase 2: Codebase Modernization & Stabilization (Nov 2025 - v0.6.1)

**Goal**: Eliminate technical debt, fix unhandled errors, and ensure a clean build for long-term maintainability.

| Priority | Issue | Component | Impact | Status |
|----------|-------|-----------|--------|--------|
| P0 | **Unhandled Errors** | `libdino`, `plugins` | Potential crashes in edge cases (Crypto/IO) | ✓ FIXED |
| P1 | **Async Correctness** | System-wide | Race conditions / Unhandled promises | ✓ FIXED |
| P2 | **Compiler Warnings** | Build System | 50+ warnings reduced to 0 | ✓ FIXED |
| P2 | **VAPI Syntax** | `gnutls`, `libgcrypt` | Deprecated CCode syntax updated | ✓ FIXED |
| P2 | **i18n Bindings** | `libdino` | Fix `bindtextdomain` C compilation issues | ✓ FIXED |

**Key Improvements**:
- **Error Handling**: Added comprehensive `try/catch` blocks for `GLib.Error` and `Crypto.Error` across `libdino/src/service/` (Calls, FileSharing, Messages) and plugins (`ice`, `omemo`).
- **Async Safety**: Enforced explicit `.begin` syntax for all async void method calls to ensure proper execution context.
- **Clean Build**: Achieved a completely clean build (`meson compile`) with **0 warnings**, ensuring no hidden bugs from deprecated usage.
- **Runtime Verification**: Verified stability of OMEMO encryption, File Transfers, and Connection logic after refactoring.
- **Critical Fixes**:
    - Fixed `WeakMap` null return issue causing potential crashes in `libdino`.
    - Fixed `GValueArray` deprecation in RTP plugin while maintaining runtime stability (using C helper).

**Files Modified**:
- `libdino/src/service/*.vala` (Calls, Messages, FileSharing, etc.)
- `libdino/src/util/weak_map.vala` (Null safety)
- `plugins/ice/src/dtls_srtp.vala` & `gnutls.vapi`
- `plugins/omemo/src/` (Crypto logic, UI)
- `plugins/rtp/src/gst_fixes.c` (GStreamer deprecation helper)
- `xmpp-vala/src/` (Stream handling)

**Status**: ✓ **COMPLETED** (November 21, 2025)
**Commits**: `b5af8aab` (Fix errors), `1ab66e71` (Cleanup), `[Current]` (WeakMap/RTP fixes)

---

### READY Phase 3: Critical Bug Fixes Round 2 (Q1 2026 - v0.6.2)

**Goal**: Fix remaining P0/P1 stability issues + Complete missing XEP UIs

| Priority | Issue | Component | Impact | Complexity | Status |
|----------|-------|-----------|--------|------------|--------|
| P0 | [#440](https://github.com/dino/dino/issues/440) | OMEMO | Offline messages unreadable | Hard | ✓ FIXED |
| P0 | [#752](https://github.com/dino/dino/issues/752) | File Transfer | Cannot send files with OMEMO | Medium | ✓ FIXED |
| P0 | [#1271](https://github.com/dino/dino/issues/1271) | Calls | Stuck connecting with Conversations | Medium | ✓ FIXED |
| P1 | [#1559](https://github.com/dino/dino/issues/1559) | Calls | Echo cancellation broken | Hard | TODO |
| P1 | [#57](https://github.com/dino/dino/issues/57) | Security | Self-signed certs rejected | Medium | TODO |
| P1 | **User Status** | **Presence UI** | **Set own status / View partner status** | Medium | ✓ **COMPLETED** |
|  P1 | **XEP-0424** | **Message UI** | **Delete individual messages** | Easy | **DONE** |
|  P2 | **XEP-0425** | **MUC UI** | **Moderator message deletion** | Medium | **DONE** |

**Files to Modify**:
- `plugins/omemo/src/file_encryptor.vala` - OMEMO file encryption
- `plugins/omemo/src/message_encryptor.vala` - Offline message handling
- `plugins/rtp/src/device/` - Echo cancellation
- `xmpp-vala/src/core/` - Certificate validation
- **`main/src/ui/main_window.vala`** - User Status Selector
- **`main/src/ui/conversation_selector/conversation_selector_row.vala`** - Status Indicators
- **`main/src/ui/conversation_content_view/message_widget.vala`** - XEP-0424/0425 UI
- **`main/src/ui/conversation_content_view/item_actions.vala`** - Delete action

**XEP UI Implementation** (Backend already complete, see [XEP_UI_ANALYSIS.md](docs/XEP_UI_ANALYSIS.md)):

**User Status (Presence) UI** (2-3 days):
- Backend ✓ `libdino/src/service/presence_manager.vala` (Already handles presence updates)
- ✓ UI to set own status (Online, Away, Busy, Offline) via Systray & App Menu
- ✓ Visual indicator for chat partner's status in conversation list (Emoji-based)
- Implementation: Added status selector to Main Menu/Systray, added status Emojis to `ConversationSelectorRow`

**XEP-0424 - Message Retraction UI** (1-2 days):
- Backend ✓ `xmpp-vala/src/module/xep/0424_message_retraction.vala`
- Backend ✓ Used in `conversation_manager.vala` for bulk delete
- Missing: Context menu "Delete message for everyone" on own messages
- Implementation: Add action in `message_widget.vala`, call `MessageDeletion.delete_message_for_everyone()`

**XEP-0425 - Message Moderation UI** (2-3 days):
- Backend ✓ `xmpp-vala/src/module/xep/0425_message_moderation.vala`
- Backend ✓ Moderator checks in `message_deletion.vala`
- Missing: Context menu "Delete message (Moderator)" for MUC moderators
- Implementation: Check `is_muc_moderator` in UI, show option for others' messages

**Estimated Time**: 3-4 weeks (2 weeks bugs + 1 week XEP UIs)  
**Target Release**: End of December 2025

---

### DONE Phase 3: Top User-Requested Features (Q1-Q2 2026 - v0.7.0)

**Goal**: Implement most-wanted features (100+ reactions each!)

| Priority | Issue | Feature | Reactions | Complexity | Status |
|----------|-------|---------|-----------|------------|--------|
|  Feature | [#98](https://github.com/dino/dino/issues/98) | Systray Support | 108 👍 | Medium | ✓ DONE |
|  Feature | [#299](https://github.com/dino/dino/issues/299) | Background Mode | 54 👍 | Medium | ✓ DONE |
|  Feature | [#115](https://github.com/dino/dino/issues/115) | Custom Host/Port | 26 👍 | Easy | ✓ DONE |
|  UX | [#1796](https://github.com/dino/dino/issues/1796) | File Button Bug | - | Easy | ✓ FIXED |
|  UX | - | Remove Avatar Button | vCard avatar deletion | Easy | ✓ FIXED |
|  UX | - | Edit/Delete Message Buttons | Buttons not appearing after GTK4 migration | Easy | ✓ FIXED |
| P0 UX | [#472](https://github.com/dino/dino/issues/472) | **Delete Conversation History** | Clear chat history with persistence | Medium | ✓ **COMPLETED** |
| P0 UX | - | **Contact Management Suite** | Full roster management with block/mute | High | ✓ **COMPLETED** |
| P0 UX | - | Archive Conversation | Hide conversations without deleting | Easy | ✗ **REMOVED** |
|  UX | [#1380](https://github.com/dino/dino/issues/1380) | Spell Checking | - | Medium | DONE TODO |

**Files Created/Modified** (Systray Support #98 & Background Mode #299):
- ✓ `main/src/ui/systray.vala` - StatusNotifierItem & DBusMenu implementation
- ✓ `main/src/ui/application.vala` - Integration & Background mode logic
- ✓ `main/vapi/dbusmenu-glib-0.4.vapi` - Vala bindings for libdbusmenu
- ✓ `main/meson.build` - Build configuration

**Files Created/Modified** (Custom Host/Port #115):
- ✓ `libdino/src/entity/account.vala` - Added custom_host, custom_port fields
- ✓ `libdino/src/service/database.vala` - Schema v31, new columns
- ✓ `xmpp-vala/src/core/stream_connect.vala` - Optional host/port, skip SRV
- ✓ `libdino/src/service/connection_manager.vala` - Pass custom params
- ✓ `main/data/preferences_window/add_account_dialog.ui` - Advanced Settings UI
- ✓ `main/src/windows/preferences_window/add_account_dialog.vala` - Logic

**Files Modified** (Remove Avatar Button):
- ✓ `libdino/src/service/avatar_manager.vala` - vCard avatar removal + cache cleanup

**Files Modified** (Edit/Delete Message Buttons):
- ✓ `main/src/ui/conversation_content_view/message_widget.vala` - Removed `shortcut_action = false` on edit action
- ✓ `main/src/ui/conversation_content_view/item_actions.vala` - Removed `shortcut_action = false` on delete action
- ✓ `main/src/ui/conversation_content_view/conversation_view.vala` - Fixed button positioning with bounds checking

**Files Created/Modified** (Delete Conversation History #472 - **COMPLETED**):

**Core Implementation**:
- ✓ `libdino/src/service/database.vala` - Schema v31→v32: Added `history_cleared_at` column (LONG, Unix timestamp)
- ✓ `libdino/src/entity/conversation.vala` - Added `history_cleared_at` property with DB persistence
- ✓ `libdino/src/service/conversation_manager.vala` - Implemented `clear_conversation_history()` method
  - Batch deletion with XEP-0425 Message Retraction to server
  - Local DB cleanup (messages, content_items)
  - Force MAM re-sync by deleting mam_catchup entries
  - Set persistent `history_cleared_at` timestamp
  - Emit `conversation_cleared` signal
- ✓ `libdino/src/service/message_processor.vala` - `ClearedConversationFilterListener` to filter MAM messages
- ✓ `libdino/src/service/message_storage.vala` - `clear_conversation_cache()` method

**UI Components**:
- ✓ `main/src/ui/conversation_titlebar/menu_entry.vala` - Menu item + GTK 4.10 AlertDialog confirmation
- ✓ `main/src/ui/conversation_view_controller.vala` - Force reload view on history clear
- ✓ `main/src/ui/conversation_selector/conversation_selector_row.vala` - Update row on clear
- ✓ `main/src/ui/conversation_content_view/conversation_view.vala` - Force reload parameter

**OMEMO Integration** (Critical for encrypted chats):
- ✓ `plugins/omemo/src/plugin.vala` - `clear_bad_message_state()` method
- ✓ `plugins/omemo/src/ui/bad_messages_populator.vala` - Listen to `conversation_cleared` signal
- ✓ `plugins/omemo/src/logic/decrypt.vala` - Check `history_cleared_at` before marking messages undecryptable
- ✓ `plugins/omemo/src/logic/trust_manager.vala` - Check `history_cleared_at` before marking messages untrusted

**Technical Features**:
- ✓ **Persistent Deletion**: Messages stay deleted across app restarts
- ✓ **XEP-0425 Message Retraction**: Sends deletion requests to server (ejabberd 23.04+ support)
- ✓ **MAM Filter**: Prevents deleted messages from reappearing during sync
- ✓ **OMEMO Support**: Clears encryption warnings and prevents re-creation during MAM sync
- ✓ **Cache Management**: Clears all in-memory caches (stanza_id, server_id maps)
- ✓ **GTK 4.10 AlertDialog**: Modern confirmation dialog

**UX Flow**:
```
1. User clicks "Delete Conversation History" in menu
2. GTK AlertDialog: "Delete all message history?" [Cancel] [Delete]
3. Backend:
   - Delete local messages from database
   - Send XEP-0425 retractions to server
   - Set history_cleared_at = NOW()
   - Force MAM re-sync
4. MAM sync runs → Filter rejects messages older than history_cleared_at
5. Result: Empty conversation, contact remains in roster
```

**Commit**: `9c7262e4` - "feat: Add persistent 'Delete Conversation History' with OMEMO support"  
**Time Spent**: 8 hours (November 20, 2025)  
**Lines Changed**: +315, -28 (15 files modified)

---

**Files Created/Modified** (Contact Management Suite - **COMPLETED**):

**Core Services**:
- ✓ `libdino/src/service/blocking_manager.vala` - Fixed `stream_negotiated` signal, immediate UI updates
- ✓ `xmpp-vala/src/module/xep/0191_blocking_command.vala` - Local blocklist updates for responsiveness
- ✓ `libdino/src/service/conversation_manager.vala` - Enhanced `clear_conversation_history()` and `close_conversation()`

**Central Management UI**:
- ✓ `main/src/windows/preferences_window/contacts_preferences_page.vala` - **NEW** Full contact management page (396 lines)
  - Contact list with search/filter
  - Edit button (document-edit-symbolic) - Change display name with duplicate detection
  - Mute button (dino-bell-large-symbolic) - Toggle notifications (OFF/DEFAULT)
  - Block button (action-unavailable-symbolic) - XEP-0191 blocking with red highlight
  - Remove button (user-trash-symbolic) - Remove from roster with history cleanup
  - Auto-refresh on roster/blocking changes
  - All actions with confirmation dialogs
- ✓ `main/src/windows/preferences_window/preferences_dialog.vala` - Added "Contacts" navigation item
- ✓ `main/data/preferences_window/preferences_dialog.ui` - Added Contacts page to sidebar

**Context Menu Integration**:
- ✓ `main/src/ui/conversation_selector/conversation_selector_row.vala` - Right-click context menu on conversation rows
  - GestureClick controller for right-click detection
  - PopoverMenu with Edit/Mute/Block/Remove actions
  - Same confirmation dialogs as Contacts page
  - Reuses contact management logic

**Visual Status Badges**:
- ✓ `main/data/conversation_row.ui` - Added mute_image and blocked_image widgets
  - Mute icon: `dino-bell-large-none-symbolic` with orange/warning color
  - Block icon: `action-unavailable-symbolic` with red/error color
  - Positioned next to pinned icon with tooltips
- ✓ `main/src/ui/conversation_selector/conversation_selector_row.vala` - Badge update logic
  - `update_muted_icon()` - Shows/hides based on NotifySetting.OFF
  - `update_blocked_icon()` - Shows/hides based on BlockingManager status
  - Live updates via signal listeners (notify-setting, block_changed)

**Add Contact Dialog**:
- ✓ `main/src/ui/add_conversation/add_contact_dialog.vala` - Enhanced with validation
  - JID format validation
  - Duplicate contact detection
  - Account selection dropdown
  - Optional alias field

**Technical Features**:
- ✓ **XEP-0191 Blocking Command**: Full blocking support with server sync
- ✓ **Immediate UI Updates**: Fixed signal connection bug for instant feedback
- ✓ **Local Blocklist Cache**: Updates before server response for responsiveness
- ✓ **Notification Control**: Per-contact mute with NotifySetting (OFF/DEFAULT)
- ✓ **Full Cleanup**: History deletion, OMEMO data, roster removal
- ✓ **Live Status Badges**: Visual indicators for muted/blocked contacts
- ✓ **Duplicate Prevention**: Alias validation to avoid conflicts

**UX Flow Examples**:

*Block Contact*:
```
1. Right-click contact → "Block"
2. AlertDialog: "This will prevent [JID] from sending you messages" [Cancel] [Block]
3. Backend: BlockingManager.block() → XEP-0191 IQ → Local cache update
4. UI: Block icon appears immediately (red), status updates in Contacts page
```

*Mute Contact*:
```
1. Right-click contact → "Mute"
2. AlertDialog: "This will disable notifications from [JID]" [Cancel] [Mute]
3. Backend: conversation.notify_setting = OFF
4. UI: Mute icon appears (orange bell), notifications disabled
```

*Remove Contact*:
```
1. Right-click contact → "Remove Contact"
2. AlertDialog: "This will: • Delete all history • Remove from roster • Delete OMEMO data"
3. Backend: clear_history() → close_conversation() → RosterManager.remove_jid()
4. UI: Contact disappears from list and sidebar
```

**Commit**: `f77364fb` - "Add comprehensive contact management features"  
**Time Spent**: 6 hours (November 20, 2025)  
**Lines Changed**: +806, -8 (16 files modified)

---

**Removed Features**:

**Archive Conversation** ✗:
- **Reason**: XMPP model doesn't fit archiving - conversations are roster-based, not message threads
- **Alternative**: Use group chats for different topics, or remove contact to hide conversation

**Roster Management UI**:
- `main/data/menu_conversation.ui` - Add "Remove Contact" for 1:1 chats
- `main/src/ui/add_conversation/roster_list.vala` - Enhance existing roster display
- `main/src/ui/conversation_details.vala` - Add roster actions to contact details

**Technical Approach**:
```
┌─────────────────────────────────────────┐
│ Chat Management Architecture            │
├─────────────────────────────────────────┤
│ 1. Context Menu (right-click)           │
│    ├─ Delete Conversation (all chats)   │
│    ├─ Archive (hide/show toggle)        │
│    └─ Remove Contact (1:1 only)         │
│                                          │
│ 2. Database Layer                       │
│    ├─ DELETE messages WHERE conv_id     │
│    ├─ UPDATE conversation SET archived  │
│    └─ Keep contacts in roster           │
│                                          │
│ 3. UI Integration                       │
│    ├─ GtkPopoverMenu on row             │
│    ├─ Confirm dialogs for destructive   │
│    └─ Toast notifications for actions   │
└─────────────────────────────────────────┘
```

**UX Flow**:
1. **Right-click conversation** → Context menu
2. **Delete Conversation**: Confirm dialog → Clear all messages → Keep in roster
3. **Archive**: Toggle archived state → Hide from list (show with filter)
4. **Remove Contact**: Confirm → Remove from roster + delete conversation

**Files to Create/Modify** (Remaining):
- GTK4 spell checking integration

**Estimated Time**: 4-5 weeks  
**Time Spent**: 1 hour (Issue #115), 2 hours (Avatar removal), 1 hour (Edit/Delete buttons), **8 hours (Delete Conversation History - COMPLETED)**  
**Target Release**: End of February 2026 (Archive & Roster features pending)

---

### 🔵 Phase 4: Privacy & History Management (Q2 2026 - v0.8.0)

**Goal**: User control over data and privacy

| Priority | Issue | Feature | Why Important | Status |
|----------|-------|---------|---------------|--------|
| 🔐 Privacy | [#67](https://github.com/dino/dino/issues/67) | Auto-delete History | Limit retention (e.g., 7 days) | 🔵 TODO |
| 🔐 Privacy | [#472](https://github.com/dino/dino/issues/472) | Delete Conversation | Clear history without ending chat | ✓ **COMPLETED IN PHASE 3** |
| 🔐 Privacy | [#1317](https://github.com/dino/dino/issues/1317) | Blocking Fix | Blocked contacts still send messages | 🔵 TODO |

**Files to Modify**:
- `libdino/src/service/database.vala` - History cleanup
- `main/src/ui/conversation_selector/conversation_row.vala` - Delete UI
- `xmpp-vala/src/module/xep/0191_blocking_command.vala` - Blocking

**Estimated Time**: 2-3 weeks  
**Target Release**: End of March 2026

---

### 🟣 Phase 5: UX Polish & Minor Bugs (Q2 2026 - v0.8.5)

**Goal**: Smooth, polished experience

| Priority | Issue | Feature | User Impact | Status |
|----------|-------|---------|-------------|--------|
|  UX | [#1769](https://github.com/dino/dino/issues/1769) | Chat Scroll | Conversation jumps annoyingly | 🟣 TODO |
|  UX | [#1752](https://github.com/dino/dino/issues/1752) | Dark Mode | Requires app restart | 🟣 TODO |
|  UX | [#1787](https://github.com/dino/dino/issues/1787) | Notifications | Better desktop integration | 🟣 TODO |
| 😀 Feature | [#1776](https://github.com/dino/dino/issues/1776) | Emoji Reactions | Compatibility with Conversations | 🟣 TODO |

**Files to Modify**:
- `main/src/ui/conversation_view/conversation_view.vala` - Scroll behavior
- `main/src/ui/application.vala` - Dark mode live switching
- `libdino/src/service/notification_events.vala` - Notification handling
- `xmpp-vala/src/module/xep/0444_reactions.vala` - XEP-0444 update

**Estimated Time**: 3-4 weeks  
**Target Release**: End of April 2026

---

### 🔷 Phase 6: XEP Standards & Modern Features (Q3 2026 - v0.9.0)

**Goal**: Support latest XMPP standards

| Priority | XEP | Feature | Why Important | Status |
|----------|-----|---------|---------------|--------|
| 🆕 Feature | XEP-0388 | SASL2/FAST Auth | Modern servers require it | 🔷 TODO |
| 🆕 Feature | XEP-0357 | Push Notifications | Battery efficiency | 🔷 TODO |
|  Feature | XEP-0449 | Stickers | User expectation in 2025 | 🔷 TODO |
|  Feature | - | Export/Import | Data portability | 🔷 TODO |
|  Feature | - | Multi-Profile | Multiple accounts | 🔷 TODO |

**New Files to Create**:
- `xmpp-vala/src/module/xep/0388_sasl2.vala`
- `xmpp-vala/src/module/xep/0357_push.vala`
- `xmpp-vala/src/module/xep/0449_stickers.vala`
- `libdino/src/service/export_service.vala`
- UI components in `main/src/ui/stickers/`

**Estimated Time**: 6-8 weeks  
**Target Release**: End of June 2026

---

###  Phase 7: Technical Debt & Platform Support (Q3 2026 - v0.9.5)

**Goal**: Clean codebase + Platform expansion

| Task | Component | Problem | Solution | Status |
|------|-----------|---------|----------|--------|
|  Refactor | UI Code | GTK4/Libadwaita 1.5 Migration | AdwFlap→AdwOverlaySplitView, Dialog→Window+HeaderBar | ✓ DONE |
|  Build | Meson | Missing dependencies | Added libdbusmenu-glib, updated libadwaita | ✓ DONE |
|  Deployment | Flatpak | Missing libdbusmenu | Added module to manifest | ✓ DONE |
|  Deployment | Debian | No packaging files | Created debian/ control, rules, changelog | ✓ DONE |
|  Deployment | CI/CD | Missing dependencies | Updated GitHub Actions workflow | ✓ DONE |
|  Refactor | CSS System | StyleContext deprecated (GTK4.10) | Widget-scoped CSS providers | ✓ DONE |
|  Refactor | Database | v31 schema active, no tests | Migration test suite | ! PARTIAL |
|  Refactor | Notifications | Duplicate code (2 files) | Unified backend |  TODO |
|  Refactor | File Transfer | 400+ line state machine | Separate providers |  TODO |
| ! Refactor | Error Handling | 10+ error domains | Unified DinoError |  TODO |
|  Platform | [#309](https://github.com/dino/dino/issues/309) | Windows Support | Native Windows port |  TODO |

**Files Modified** (GTK4/Libadwaita 1.5 Migration):
- ✓ 40+ UI files migrated to modern APIs
- ✓ `AdwFlap` → `AdwOverlaySplitView` (deprecated in libadwaita 1.5)
- ✓ `Gtk.Dialog` → `Gtk.Window` + `AdwHeaderBar` pattern
- ✓ `preview_file_chooser_native.vala` removed (native GTK4 API)
- ✓ Notification handling modernized
- ✓ File widgets updated for GTK4 drag-and-drop
- ✓ CSS adjustments for libadwaita themes

**CSS System Refactoring** (GTK4.10+ Future-Proof):

**Current Problem**:
- Using deprecated `Gtk.StyleContext.add_provider_for_display()` (2 warnings)
- Global CSS providers attached to display (GTK3 pattern)
- Manual provider cleanup required

**New Architecture**:
```
┌─────────────────────────────────────────────┐
│ Widget-Scoped CSS (GTK4 Way)                │
├─────────────────────────────────────────────┤
│ 1. CssProvider per widget (not per display) │
│ 2. Automatic cleanup on widget destroy      │
│ 3. No StyleContext API usage                │
│ 4. CSS classes + inline styles              │
└─────────────────────────────────────────────┘
```

**Implementation Plan**:

**Phase 1: Refactor helper.vala CSS utilities** (1-2 hours)
- Replace `Gtk.StyleContext.add_provider_for_display()` 
- Use widget-scoped providers via `Gtk.Widget.add_css_class()`
- Store provider references in widget data for cleanup
- Keep backward-compatible API

**Files to Modify**:
- `main/src/ui/util/helper.vala`:
  - `force_css()` - Attach provider to widget, not display
  - `force_color()` - Use widget CSS data storage
  - `get_label_pango_color()` - Clean up properly
  
**Phase 2: Update call sites** (30 min)
- `main/src/ui/conversation_selector/conversation_selector_row.vala` (3 usages)
- `main/src/ui/conversation_content_view/message_widget.vala` (1 usage)
- `main/src/ui/util/preference_group.vala` (2 usages)

**Technical Approach**:
```vala
// OLD (deprecated):
Gtk.StyleContext.add_provider_for_display(display, provider, priority);

// NEW (GTK4 way):
widget.get_style_context().add_provider(provider, priority);
// OR use CSS classes + set_data() for lifecycle management
```

**Testing Strategy**:
1. Visual regression test (colors, styling unchanged)
2. Memory leak check (providers properly destroyed)
3. Performance test (no display-wide provider pollution)

**Benefits**:
- ✓ Zero deprecation warnings
- ✓ Better performance (widget-scoped, not display-wide)
- ✓ Automatic cleanup (widget lifecycle)
- ✓ Future-proof for GTK5
- ✓ Follows GTK4 best practices

**Status**: ✓ **COMPLETED** (Nov 20, 2025)  
**Time Spent**: 1 hour  
**Risk**: Low (backward-compatible API)

**Work Completed** (Nov 20, 2025):
- ✓ Fixed edit/delete message buttons not appearing (removed `shortcut_action = false`)
- ✓ Fixed button positioning using `compute_bounds()` 
- ✓ Refactored CSS system to widget-scoped providers (GTK4 best practices)
- ✓ Eliminated 2 StyleContext deprecation warnings
- ✓ Clean build: 0 errors, 0 StyleContext warnings, 541 targets compiled

**Commits**:
- `c9c6cc54` - fix(ui): restore edit/delete message button functionality
- `d1874703` - refactor(ui): modernize CSS system to GTK4 widget-scoped providers

---

**Original Benefits**:
- Easier onboarding for new contributors
- Fewer bugs from code duplication
- Faster feature development
- Windows user base expansion
- Modern UI/UX following GNOME HIG
- Future-proof against libadwaita deprecations

**Estimated Time**: 8-10 weeks (incl. Windows port)  
**Time Spent**: 4-6 hours (GTK4/libadwaita migration)  
**Target Release**: End of August 2026

---

###  Phase 8: 1.0 Stable Release (Q4 2026 - v1.0.0)

**Goal**: Production-ready, stable API

**Requirements**:
- ✓ Zero known crash bugs
- ✓ Memory usage <200MB for 7-day sessions
- ✓ 90%+ test coverage for critical paths
- ✓ Complete documentation (API, architecture, build)
- ✓ Performance benchmarks established
- ✓ Accessibility audit passed

**Target Release**: October 2026

---

## Issue Backlog (568 Remaining Issues)

### Overview by Category

| Category | Count | Top Priority Issues |
|----------|-------|---------------------|
|  **Bugs** | ~200 | Crashes, data loss, broken features |
|  **Features** | ~250 | UX improvements, new capabilities |
|  **XEPs** | ~50 | Protocol updates, standards compliance |
|  **UI/UX** | ~40 | Interface polish, accessibility |
|  **Platform** | ~15 | Windows, mobile, packaging |
| 🔐 **Security** | ~13 | Encryption, certificates, privacy |

**Total Upstream Issues**: 572  
**Fixed by us**: 6 (Phase 1: 4, Phase 3: 2 including **Delete Conversation History**)  
**Remaining**: 566

### Prioritization Strategy

1. **P0 (Critical)**: Crashes, data loss, security → Phases 1-2
2. **P1 (High)**: Broken features, major UX → Phases 2-3
3. **P2 (Medium)**: Minor bugs, nice features → Phases 4-5
4. **P3 (Low)**: Edge cases, enhancements → Phases 6-8

### Issue Tracking

We'll progressively add issues to phases as we work through them:
- ✓ Phase 1: Completed (4/4 issues)
- Phase 2: Defined (5 issues)
- Phase 3: Defined (5 issues)
- Phase 4: Defined (3 issues)
- Phase 5: Defined (4 issues)
- Phases 6-8: High-level goals, detailed issues TBD

**Approach**: Fix bugs systematically, implement popular features, then polish for 1.0

---

## XEP Protocol Compliance

**Total XEPs Implemented**: 60+ (see [XEP_SUPPORT.md](docs/XEP_SUPPORT.md))

### Implementation Status Breakdown

| Status | Count | Percentage | Description |
|--------|-------|------------|-------------|
| ✓ **Full UI** | ~32 | 53% | Complete backend + user interface |
|  **Backend Only** | ~24 | 40% | Protocol implemented, no UI needed |
| ! **Partial** | ~4 | 7% | Incomplete implementation |

### Recently Added (Dino Extended)

- ✓ **XEP-0191** (Blocking Command) - Full UI in Contacts page with status badges
- ✓ **XEP-0424** (Message Retraction) - Full UI implementation (Delete for everyone)
- ✓ **XEP-0425** (Message Moderation) - Backend complete, MUC moderator support

### Missing UI Work (Backend Ready)

**High Priority**:
1. **XEP-0425** - Message Moderation UI (MUC)
   - Missing: Context menu "Delete for everyone" on own messages
   - Complexity: DONE Easy - Just UI button needed

2. **XEP-0425** - MUC moderator message deletion UI (2-3 days)
   - Backend: ✓ Complete in `xmpp-vala/src/module/xep/0425_message_moderation.vala`
   - Missing: Context menu for moderators to delete others' messages
   - Complexity: READY Medium - Need moderator status checks

**Planned**:
- **XEP-0357** (Push Notifications) - Backend + UI needed
- **XEP-0388** (SASL2/FAST) - Modern authentication
- **XEP-0449** (Stickers) - Fun feature for users

 **[Full XEP Analysis](docs/XEP_UI_ANALYSIS.md)** - 400+ lines with code snippets, implementation difficulty, and priority recommendations

---

## Quick Build Guide

### One-Line Install (Ubuntu/Debian)

```bash
# Install all dependencies
sudo apt install -y meson ninja-build valac \
  libgtk-4-dev libadwaita-1-dev libglib2.0-dev libgee-0.8-dev \
  libsqlite3-dev libgcrypt20-dev libgstreamer1.0-dev \
  libgstreamer-plugins-base1.0-dev libnice-dev libsrtp2-dev \
  libgnutls28-dev libgpgme-dev libqrencode-dev libsoup-3.0-dev \
  libicu-dev libcanberra-dev libwebrtc-audio-processing-dev \
  libdbusmenu-glib-dev

# Build & run
meson setup build && meson compile -C build && ./build/main/dinox
```

📖 **[Full Build Instructions](docs/BUILD.md)** for other distros and Flatpak

---

## Bug Reporting

Found a bug? Please check:

1. ✓ [Existing Issues](../../issues) - Maybe it's already reported
2. ✓ [Upstream Issues](https://github.com/dino/dino/issues) - Check if it's in original
3. ✓ Latest build - Run `git pull && meson compile -C build`

[ Create Bug Report](../../issues/new?template=bug_report.md)

---

## Feature Requests

Have an idea? Check the [Feature Roadmap](#-development-roadmap) first.

[ Request Feature](../../issues/new?template=feature_request.md)

---

## Contributing

We welcome contributions! Please read [CONTRIBUTING.md](docs/CONTRIBUTING.md).

**Quick Start**:
```bash
git checkout -b feature/my-awesome-feature
# Make changes, test
meson test -C build
git commit -m "feat(omemo): add key verification dialog"
git push origin feature/my-awesome-feature
```

---

## Community

- **Issues**: [GitHub Issues](../../issues)
- **Discussions**: [GitHub Discussions](../../discussions)
- **Upstream XMPP**: `chat@dino.im`

---

## 📜 License

**GPL-3.0** (same as upstream Dino)

See [LICENSE](LICENSE) for full text.

---

**Last Updated**: November 20, 2025  
**Maintainer**: @rallep71  
**Status**: DONE Active Development
