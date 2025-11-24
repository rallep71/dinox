# MUJI Group Calls - Improvement Plan

## Current Status Analysis

### ✅ Implemented (Backend)

1. **MUJI Protocol Module** (`xmpp-vala/src/module/xep/0272_muji.vala`)
   - `join_call()` - Join MUC and negotiate codecs
   - `GroupCall` class - Manages peers, real JIDs, payload intersection
   - Presence handling - Tracks peer joining/leaving
   - Codec negotiation - Computes payload intersection across all peers

2. **Service Layer** (`libdino/src/service/call_state.vala`)
   - `initiate_groupchat_call()` - Create MUJI MUC, invite participants
   - `join_group_call()` - Join existing group call
   - `convert_into_group_call()` - Create private MUC with proper config
   - Auto-configuration of room (members-only + non-anonymous)

3. **Call Management** (`libdino/src/service/calls.vala`)
   - `can_conversation_do_calls()` - Check if group calls possible
   - `can_initiate_groupcall()` - Check default MUC server configured
   - Integration with Jingle RTP for media streams

4. **UI Entry Point** (`main/src/ui/conversation_titlebar/call_entry.vala`)
   - Phone icon in titlebar
   - Menu: "Audio call" / "Video call"
   - Works for both 1:1 and group chats

### ⚠️ Partially Implemented / Needs Testing

1. **Media Handling**
   - Audio/video streams for multiple participants
   - Mute/unmute in group calls (backend exists, UI unclear)
   - Video stream handling with 3+ participants

2. **Call State UI**
   - Group call widget exists (`call_widget.vala`)
   - Shows "Calling..." and participant count
   - Missing: Active participant list, speaking indicators

3. **Error Handling**
   - Some checks exist (private room, default MUC server)
   - Missing: User-friendly error messages and guidance

### ❌ Missing Features

1. **UI Feedback**
   - No indicator that a room is "private" (supports group calls)
   - No warning if default MUC server not configured
   - No participant list during active call
   - No visual indicator for who is speaking
   - No individual volume controls

2. **Advanced Features**
   - Screen sharing in group calls
   - Call recording
   - Call quality indicators per participant
   - Bandwidth adaptation

## Improvement Priorities

### Priority 1: User Experience Basics

#### 1.1 Private Room Indicator in Conversation List

**Problem**: Users don't know which MUC rooms support group calls.

**Solution**: Add badge/icon next to private rooms.

**Implementation**:
- `ConversationRow` or `ConversationItemWidget` UI component
- Check `muc_manager.is_private_room()` for each MUC
- Show 🔒 icon or "Private" badge
- Tooltip: "Private room (supports group calls)"

**Files to modify**:
- `main/src/ui/conversation_selector/conversation_row.vala`
- `main/data/conversation_row.ui` (add icon widget)

**Estimated effort**: 2-3 hours

---

#### 1.2 Default MUC Server Warning

**Problem**: Users try to start group call but get silent failure if `default_muc_server` not set.

**Solution**: Show informative dialog with action button.

**Implementation**:
- In `call_entry.vala`: Check `can_initiate_groupcall()` before initiating
- If false, show `MessageDialog`:
  ```
  "Cannot start group call"
  "Please configure a default conference server in Account Settings."
  [Open Settings] [Cancel]
  ```
- "Open Settings" button opens account settings dialog

**Files to modify**:
- `main/src/ui/conversation_titlebar/call_entry.vala`
- `main/src/ui/application.vala` (for opening settings)

**Estimated effort**: 2-3 hours

---

#### 1.3 Active Group Call Participant List

**Problem**: During group call, users can't see who's in the call.

**Solution**: Extend `CallWindow` to show participant list for group calls.

**Implementation**:
- Detect if `call.direction == DIRECTION_OUTGOING` and `conversation.type_ == GROUPCHAT`
- Show sidebar with list of participants
- Use `group_call.peers` and `group_call.real_jids` from MUJI module
- Each entry: Avatar + Name + Connection status

**Data available**:
- `group_call.peers` - List of MUC JIDs (e.g., `room@muc/nick`)
- `group_call.real_jids` - Map from MUC JID to real JID
- `group_call.peer_joined` / `peer_left` signals

**Files to modify**:
- `main/src/ui/call_window/call_window.vala` (add sidebar)
- `main/src/ui/call_window/call_window_controller.vala` (populate list)
- New file: `main/src/ui/call_window/participant_list_widget.vala`

**Estimated effort**: 4-6 hours

---

### Priority 2: Enhanced Group Call Experience

#### 2.1 Speaking Indicator

**Problem**: In group calls, hard to know who is speaking.

**Solution**: Visual indicator (e.g., green border) around speaking participant.

**Implementation**:
- Use audio level detection from RTP stream
- Threshold: Consider "speaking" if audio level > X dB
- Update participant list entry with visual indicator
- Could also show audio level bar

**Data sources**:
- `Plugins.VideoCallPlugin.get_audio_level()` or similar
- GStreamer `level` element on audio stream

**Files to modify**:
- `main/src/ui/call_window/participant_list_widget.vala`
- May need backend changes to expose audio levels

**Estimated effort**: 6-8 hours (needs audio analysis)

---

#### 2.2 Individual Volume Controls

**Problem**: Some participants too loud/quiet.

**Solution**: Volume slider per participant.

**Implementation**:
- Add `Scale` widget to each participant entry
- Range: 0-200% (0.0-2.0 gain)
- Apply gain to participant's audio stream via GStreamer
- Persist per-JID in local settings

**Files to modify**:
- `main/src/ui/call_window/participant_list_widget.vala`
- Backend: Need to expose per-stream volume control

**Estimated effort**: 4-6 hours

---

### Priority 3: Advanced Features

#### 3.1 Group Call Invitations

**Current**: All MUC occupants are auto-invited when call starts.

**Improvement**: Allow selective invitations.

**Implementation**:
- Before starting group call, show participant picker dialog
- List all MUC occupants with checkboxes
- Only invite selected participants to MUJI MUC

**Files to create**:
- `main/src/ui/conversation_content_view/group_call_invite_dialog.vala`

**Estimated effort**: 6-8 hours

---

#### 3.2 Screen Sharing in Group Calls

**Current**: Screen sharing only in 1:1 calls.

**Implementation**:
- Extend MUJI presence to include screen sharing content
- Same approach as video, but with screen capture source
- Show screen share in main window area, thumbnails for video streams

**Files to modify**:
- `xmpp-vala/src/module/xep/0272_muji.vala` (add screen share support)
- `libdino/src/service/call_state.vala` (screen share toggle)
- `main/src/ui/call_window/call_window.vala` (layout for screen + videos)

**Estimated effort**: 12-16 hours (complex media handling)

---

#### 3.3 Call Recording

**Implementation**:
- Record all audio/video streams to separate files
- Mux together with ffmpeg after call ends
- Requires consent from all participants (legal requirement)
- Show recording indicator to all participants

**Legal/Ethical Considerations**:
- Must inform all participants that recording is active
- Some jurisdictions require explicit consent
- GDPR compliance for storage

**Estimated effort**: 16-20 hours (+ legal review)

---

## Implementation Roadmap

### Phase 1: Basic UX (v0.6.6)
**Target**: Make MUJI more discoverable and user-friendly

- [ ] Private room indicator in conversation list
- [ ] Default MUC server warning dialog
- [ ] Active group call participant list
- [ ] Update MUJI_GROUP_CALLS.md with UI screenshots

**Timeline**: 1-2 weeks

---

### Phase 2: Enhanced Experience (v0.6.7)
**Target**: Improve group call quality and control

- [ ] Speaking indicator
- [ ] Individual volume controls
- [ ] Better error messages
- [ ] Call quality indicators (ping, packet loss)

**Timeline**: 2-3 weeks

---

### Phase 3: Advanced Features (v0.7.0)
**Target**: Feature parity with modern conferencing tools

- [ ] Group call invitations (selective)
- [ ] Screen sharing in group calls
- [ ] Virtual backgrounds
- [ ] Noise cancellation
- [ ] Recording (with consent)

**Timeline**: 1-2 months

---

## Testing Strategy

### Test Environment Setup

1. **Test Server**: Use local Prosody or ejabberd instance
   ```bash
   # Prosody example
   prosodyctl adduser alice@localhost
   prosodyctl adduser bob@localhost
   prosodyctl adduser charlie@localhost
   ```

2. **Create Test Room**:
   ```bash
   # Join as owner, configure as private
   /join testcall@conference.localhost
   /configure
   # Set: members-only = true, whois = anyone
   ```

3. **Multiple Clients**: 3+ DinoX instances or mix with other MUJI clients

### Test Cases

#### TC1: Basic Group Call (3 participants)
- **Setup**: 3 users in private MUC
- **Steps**:
  1. User A starts audio call
  2. Users B and C join
  3. All users speak
- **Expected**: All hear each other clearly
- **Status**: ⚠️ Needs testing

#### TC2: Join Ongoing Call
- **Setup**: Call already in progress
- **Steps**:
  1. Users A and B in call
  2. User C joins MUC
  3. User C clicks "Join call"
- **Expected**: User C joins seamlessly
- **Status**: ⚠️ Needs testing

#### TC3: Video Call (3+ participants)
- **Setup**: 3+ users in private MUC
- **Steps**:
  1. User A starts video call
  2. Others join
- **Expected**: All video streams visible
- **Status**: ⚠️ Needs testing (layout?)

#### TC4: Participant Leaves Mid-Call
- **Steps**:
  1. 3 users in call
  2. User B closes DinoX
  3. User B's MUC presence goes offline
- **Expected**: Call continues with remaining participants
- **Status**: ⚠️ Needs testing

#### TC5: Network Issues
- **Setup**: Simulate packet loss
- **Expected**: Audio continues, visual indicator of quality
- **Status**: ❌ No quality indicators yet

### Performance Benchmarks

- **2 participants**: Baseline
- **3-5 participants**: Target use case
- **10+ participants**: Stress test

**Metrics to track**:
- CPU usage (per participant)
- Memory usage
- Audio latency
- Video frame rate
- Bandwidth consumption

---

## Technical Debt

### Known Issues

1. **Codec Negotiation Complexity**
   - Current implementation computes intersection of all participants
   - What if new participant joins with limited codecs?
   - May need renegotiation mechanism

2. **MUC Affiliation Management**
   - Currently sets all occupants as "owner" in MUJI MUC
   - Could be more fine-grained (member, admin, owner)

3. **Call ID Management**
   - Uses random nick `%08x` for MUJI MUC
   - Could be more descriptive (e.g., `alice-call-1234`)

### Code Quality Improvements

1. **Add Unit Tests**
   - Mock MUJI presence handling
   - Test payload intersection algorithm
   - Test private room detection

2. **Improve Error Handling**
   - Graceful degradation if MUJI MUC creation fails
   - Retry logic for network issues
   - Better logging for debugging

3. **Documentation**
   - Add inline comments to MUJI module
   - Document signals and their guarantees
   - Architecture diagram for group calls

---

## Resources

### XEP References
- [XEP-0272: Multiparty Jingle (MUJI)](https://xmpp.org/extensions/xep-0272.html)
- [XEP-0167: Jingle RTP Sessions](https://xmpp.org/extensions/xep-0167.html)
- [XEP-0176: Jingle ICE-UDP Transport](https://xmpp.org/extensions/xep-0176.html)

### Similar Implementations
- **Gajim**: Has MUJI support (reference implementation)
- **Movim**: Web-based, WebRTC group calls
- **Conversations**: Android, focus on 1:1 calls

### Development Tools
- **Wireshark**: Capture XMPP stanzas for debugging
- **xmpp-console**: Manual stanza testing
- **GStreamer Inspector**: Debug media pipelines

---

**Document Created**: November 24, 2025  
**Last Updated**: November 24, 2025  
**Target Version**: 0.6.6 (Phase 1)
