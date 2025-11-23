# 🔍 XEP UI Implementation Analysis

Detailed analysis of which XEPs have UI integration and which are backend-only.

**Date**: November 21, 2025  
**Version**: DinoX 0.6.0

---

## 📊 Summary Statistics

| Category | Count | Percentage |
|----------|-------|------------|
| **Total XEPs** | 60+ | 100% |
| **Full UI Integration** | 32 | ~53% |
| **Backend Only** | 24 | ~40% |
| **Partial/Incomplete** | 4 | ~7% |
| **Planned** | 6 | - |

---

## ✅ XEPs with Full UI Integration

### Messaging & Chat (11)
1. **XEP-0085** - Chat State Notifications
   - UI: "typing..." indicator
   - Location: `conversation_view/`

2. **XEP-0184** - Message Delivery Receipts
   - UI: Checkmarks for delivery/read status
   - Location: `message_widget.vala`

3. **XEP-0191** - Blocking Command ⭐ **NEW**
   - UI: Block/Unblock buttons in Contacts page
   - Location: `contacts_preferences_page.vala`, context menu
   - Files: `blocking_manager.vala`, UI badges

4. **XEP-0203** - Delayed Delivery
   - UI: Shows original timestamp for delayed messages
   - Location: Message metadata display

5. **XEP-0245** - The /me Command
   - UI: `/me` renders as italic action text
   - Location: Message rendering

6. **XEP-0308** - Last Message Correction
   - UI: Edit button on own messages + "edited" badge
   - Location: `message_widget.vala`, `message_item_widget_edit_mode.ui`
   - Signal: `activate_last_message_correction`

7. **XEP-0313** - Message Archive Management (MAM)
   - UI: Scroll to load history + Delete History feature
   - Location: `conversation_manager.vala`, context menu

8. **XEP-0333** - Chat Markers
   - UI: Read receipts shown in conversation
   - Location: Message status indicators

9. **XEP-0444** - Message Reactions
   - UI: Emoji picker button + reaction display
   - Location: `item_actions.vala`, `conversation_view.vala`
   - Service: `reactions.vala`

10. **XEP-0461** - Message Replies
    - UI: Quote/reply shown above message
    - Location: `quote.ui`, reply rendering

### Multi-User Chat (4)
11. **XEP-0045** - Multi-User Chat
    - UI: Full MUC interface with participant list
    - Location: `occupant_list.ui`, `muc_member_list_row.ui`

12. **XEP-0048/0402** - Bookmarks (Legacy & PEP)
    - UI: Room bookmarks shown in sidebar
    - Location: Conversation selector

13. **XEP-0249** - Direct MUC Invitations
    - UI: Invite dialog + notification system
    - Location: `join_room_dialog*.ui`

### File Transfer (5)
14. **XEP-0066** - Out of Band Data
    - UI: Direct URL links handled and clickable
    - Location: Message content parsing

15. **XEP-0234** - Jingle File Transfer
    - UI: Drag & drop file sending
    - Location: `file_send_overlay.ui`, `chat_input/`

16. **XEP-0264** - Jingle Content Thumbnails
    - UI: Image previews/thumbnails shown
    - Location: File display widgets

17. **XEP-0363** - HTTP File Upload
    - UI: Modern file upload with progress
    - Location: `file_default_widget.ui`

18. **XEP-0446/0447** - File Metadata & Stateless Sharing
    - UI: File info displayed (size, type)
    - Location: File message rendering

### Audio/Video Calls (3)
19. **XEP-0166/0167** - Jingle & RTP
    - UI: Full call UI with video display
    - Location: `call_widget.ui`

20. **XEP-0353** - Jingle Message Initiation
    - UI: Call notifications and accept/reject
    - Location: Call notification system

21. **XEP-0482** - Call Invites
    - UI: Modern call invitation UI
    - Location: Call management

### Encryption (5)
22. **XEP-0027** - Current Jabber OpenPGP Usage
    - UI: Via OpenPGP plugin
    - Location: `plugins/openpgp/`

23. **XEP-0373/0374** - OpenPGP for XMPP
    - UI: Modern PGP UI in plugin
    - Location: `plugins/openpgp/`

24. **XEP-0380** - Explicit Message Encryption
    - UI: Lock icon shows encryption status
    - Location: Message header icons

25. **XEP-0384** - OMEMO Encryption
    - UI: Full OMEMO UI + device management
    - Location: `plugins/omemo/`

### Account Management (2)
26. **XEP-0004** - Data Forms
    - UI: Used in registration & MUC config dialogs
    - Location: `add_account_dialog.vala`

27. **XEP-0077** - In-Band Registration
    - UI: Full registration UI in Add Account dialog
    - Location: `add_account_dialog.vala`, registration forms

---

## 🔧 XEPs Backend-Only (By Design)

These XEPs are infrastructure/protocol features with no UI needed:

### Core Protocol (5)
- **XEP-0030** - Service Discovery (queries server features)
- **XEP-0060** - PubSub (used by other XEPs)
- **XEP-0092** - Software Version (responds to queries)
- **XEP-0115** - Entity Capabilities (capability caching)
- **XEP-0199** - XMPP Ping (connection health checks)

### Message Infrastructure (5)
- **XEP-0280** - Message Carbons (transparent multi-device sync)
- **XEP-0334** - Message Processing Hints (server hints)
- **XEP-0359** - Unique Stanza IDs (message tracking)
- **XEP-0428** - Fallback Indication (compatibility layer)

### MUC Infrastructure (2)
- **XEP-0410** - MUC Self-Ping (reconnection detection)
- **XEP-0421** - Anonymous Occupant IDs (participant tracking)

### File Transfer Infrastructure (1)
- **XEP-0261** - Jingle In-Band Bytestreams (transport method)

### Call Infrastructure (6)
- **XEP-0176** - Jingle ICE-UDP Transport
- **XEP-0215** - External Service Discovery (TURN/STUN)
- **XEP-0294** - Jingle RTP Header Extensions
- **XEP-0320** - DTLS-SRTP (encryption)
- **XEP-0338** - Jingle Grouping Framework
- **XEP-0339** - Source-Specific Media Attributes

### Stream Management (3)
- **XEP-0198** - Stream Management (connection resilience)
- **XEP-0352** - Client State Indication (power management)
- **XEP-0368** - SRV over TLS (connection setup)

---

## ⚠️ XEPs with Backend but NO UI Yet

These are implemented in the protocol layer but lack user-facing features:

### 1. XEP-0424 - Message Retraction 🔥
**Status**: Backend ✅ | UI ❌

**What's Implemented**:
- Protocol support in `xmpp-vala/src/module/xep/0424_message_retraction.vala`
- Used internally for bulk delete history
- Handles incoming retraction messages

**What's Missing**:
- No UI to delete individual sent messages
- No "Delete for everyone" context menu option
- No visual indication of retracted messages

**Code Locations**:
```vala
// Backend exists:
xmpp-vala/src/module/xep/0424_message_retraction.vala
libdino/src/service/message_deletion.vala (uses it internally)
libdino/src/service/conversation_manager.vala (delete history)

// UI needed in:
main/src/ui/conversation_content_view/message_widget.vala
// Add context menu: "Delete message for everyone"
```

**Implementation Difficulty**: 🟢 Easy
- Backend already works
- Just need UI button in message context menu
- Similar to edit message feature

---

### 2. XEP-0425 - Message Moderation 🔥
**Status**: Backend ✅ | UI ✅

**What's Implemented**:
- Protocol support in `xmpp-vala/src/module/xep/0425_message_moderation.vala`
- Backend checks if user is MUC moderator
- Handles moderation messages from server
- **UI**: "Moderate message" action for moderators in `item_actions.vala`

**What's Missing**:
- No visual indication of moderated messages (tombstones)
- No moderation history/log

**Code Locations**:
```vala
// Backend exists:
xmpp-vala/src/module/xep/0425_message_moderation.vala
libdino/src/service/message_deletion.vala (has moderator checks)

// UI implemented in:
main/src/ui/conversation_content_view/item_actions.vala
// "Moderate message" dialog added
```

**Implementation Difficulty**: 🟢 Done
- UI action added
- Dialog distinguishes between Retraction (own) and Moderation (others)

---

## ⚠️ Partial Implementations

### XEP-0272 - Multiparty Jingle (Muji)
**Status**: Backend ⚠️ | UI ⚠️

**Issue**: Group calls partially work but have limitations
- 1-to-1 calls work perfectly
- Group calls may have audio/video sync issues
- Limited to certain MUC configurations

---

## 📋 Priority Recommendations

### High Priority (Should Have UI)
1. **XEP-0424 (Message Retraction)** 🔥
   - Users expect "Delete message" feature
   - Backend is ready, just needs UI
   - ~1-2 days work

2. **XEP-0425 (Message Moderation)** 🔥
   - Important for MUC moderators
   - Backend checks already exist
   - ~2-3 days work

### Medium Priority
3. **XEP-0272 (Muji) Improvements** ⚠️
   - Fix group call issues
   - Better than current state
   - Significant WebRTC work

### Low Priority (Future)
4. **XEP-0449 (Stickers)** 🟢
   - Nice to have, not essential
   - Requires custom UI
   - Fun feature for users

---

## 🎯 Next Steps for XEP-0424/0425 UI

### Step 1: XEP-0424 - Delete Own Messages
```vala
// In message_widget.vala, add to context menu:
if (can_retract_message(message_item)) {
    var delete_action = new Plugins.MessageAction();
    delete_action.name = "delete";
    delete_action.icon_name = "user-trash-symbolic";
    delete_action.tooltip = _("Delete message for everyone");
    delete_action.callback = (variant) => {
        stream_interactor.get_module(MessageDeletion.IDENTITY)
            .delete_message_for_everyone(conversation, message);
    };
    actions.add(delete_action);
}
```

### Step 2: XEP-0425 - Moderator Delete
```vala
// In message_widget.vala, add moderator check:
bool is_muc_moderator = conversation.type_ == Conversation.Type.GROUPCHAT &&
    stream_interactor.get_module(MucManager.IDENTITY)
        .is_moderator(conversation.account, conversation.counterpart);

if (is_muc_moderator && !message_item.message.from.equals(my_jid)) {
    var moderate_action = new Plugins.MessageAction();
    moderate_action.name = "moderate";
    moderate_action.icon_name = "dialog-warning-symbolic";
    moderate_action.tooltip = _("Delete message (Moderator)");
    moderate_action.callback = (variant) => {
        stream_interactor.get_module(MessageDeletion.IDENTITY)
            .moderate_message(conversation, message);
    };
    actions.add(moderate_action);
}
```

---

## 📚 Code References

### Key Files for XEP Implementation

**Backend Protocol**:
- `xmpp-vala/src/module/xep/` - All XEP implementations
- `libdino/src/service/module_manager.vala` - XEP module registration

**Frontend UI**:
- `main/src/ui/conversation_content_view/message_widget.vala` - Message UI
- `main/src/ui/conversation_content_view/item_actions.vala` - Action buttons
- `main/src/ui/conversation_view_controller.vala` - View coordination

**Services**:
- `libdino/src/service/reactions.vala` - XEP-0444 implementation
- `libdino/src/service/message_correction.vala` - XEP-0308 implementation
- `libdino/src/service/message_deletion.vala` - XEP-0424/0425 backend

---

## 🔄 Recent Changes (Dino Extended)

### Added in This Fork
- **XEP-0191 UI**: Full blocking UI in Contacts page
- **XEP-0424 Backend**: Used for delete conversation history
- **XEP-0425 Backend**: MUC moderation support
- **Status Badges**: Mute/block indicators in conversation list

### Inherited from Upstream
- All other XEPs were in upstream dino/dino
- Fork focused on adding missing UI features
- No protocol implementations removed

---

**Conclusion**: Dino Extended has excellent XEP coverage at the protocol level. Most XEPs that *should* have UI actually do. The main gaps are XEP-0424/0425 which would be straightforward to add.
