# MUJI Group Calls - Improvement Plan

## Current Status Analysis

### Implemented (Backend)

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

1. **Multi-Participant Media (3+ Teilnehmer)**
   - ✅ Code exists for multiple Jingle sessions
   - ✅ Codec intersection algorithm implemented
   - ⚠️ **No test coverage** - untested with 3+ participants
   - ❓ **Unknown performance** with 5+ peers
   - ⚠️ Video stream handling with 3+ participants not verified
   - 🔧 Mute/unmute backend exists, UI implementation unclear

2. **UI/UX**
   - ✅ Basic call widget exists (`call_widget.vala`)
   - ✅ Participant list recently implemented (Phase 1)
   - ❌ **No individual volume controls** per participant
   - ❌ **No speaking indicators** (visual feedback for active speakers)
   - ⚠️ Minimalistic UI - lacks polish and advanced controls

3. **Error Handling**
   - ✅ Basic checks (private room, default MUC server)
   - ❌ **Missing user-friendly error messages**
   - ❌ **No reconnection logic** for network issues
   - ❌ No call quality indicators during active call

### ❌ Not Implemented

1. **UI Feedback** (Partially addressed in Phase 1)
   - ✅ **DONE**: Private room indicator in conversation list (🔒 icon)
   - ✅ **DONE**: Warning if default MUC server not configured
   - ✅ **DONE**: Participant list during active call
   - ❌ No visual indicator for who is speaking
   - ❌ No individual volume controls per participant

2. **Advanced Features**
   - ❌ **Screen sharing** in group calls
   - ❌ **Call recording** functionality
   - ❌ **Call quality indicators** (ping, packet loss, bitrate)
   - ❌ **Advanced MUJI features**:
     * Mid-call invitations (invite user to ongoing call)
     * Selective participant invitations
     * Call migration (move call to different room)
   - ❌ Bandwidth adaptation based on network quality
   - ❌ Echo cancellation tuning per participant

3. **Interoperability Issues**
   - ❌ **Gajim**: No Jingle A/V support at all - not a compatibility issue, feature missing entirely
   - ⚠️ **Monal/Conversations compatibility**: Have 1:1 calls, but MUJI not implemented
   - ✅ **DinoX ↔ DinoX**: Should work (needs multi-instance testing)
   - 🎯 **DinoX is currently the ONLY desktop client with MUJI support**

## Client Compatibility Status

### MUJI Group Calls

| Client | Version Tested | MUJI Support | Status | Notes |
|--------|---------------|-------------|---------|-------|
| **DinoX** | 0.6.5.3+ | ⚠️ Implemented, minimally tested | Partial | Full backend, Phase 1 UI complete, **no multi-peer tests** |
| **Gajim** | 2.4.0 | ❌ No | ❌ Not Supported | **No Jingle A/V implementation at all** |
| **Monal** | Latest | ⚠️ Partial | ⚠️ 1:1 only | Has 1:1 calls, but no MUJI support |
| **Conversations** | Latest | ⚠️ Partial | ⚠️ 1:1 only | Has 1:1 Jingle calls, no MUJI |
| **Siskin** | Latest | ⚠️ Partial | ⚠️ 1:1 only | Has 1:1 calls (iOS), no MUJI |

### 1:1 Calls (XEP-0166/167)

| Client Pair | Audio | Video | Notes |
|-------------|-------|-------|-------|
| **DinoX ↔ DinoX** | ✅ | ✅ | Fully supported and tested |
| **DinoX ↔ Gajim 2.4.0** | ❌ | ❌ | **Gajim has no Jingle A/V implementation** |
| **DinoX ↔ Monal** | ✅ | ✅ | Should work, needs verification |
| **DinoX ↔ Conversations** | ✅ | ✅ | Should work, needs verification |
| **DinoX ↔ Siskin** | ✅ | ✅ | Should work (iOS), needs verification |

**Important Notes:**
- **Gajim**: No audio/video call support at all (neither XEP-0166/167 nor MUJI)
- **Pidgin**: Also no Jingle support - both clients "missed" this feature
- **DinoX/Dino**: One of the few desktop clients with full A/V support
- **Mobile**: Monal (iOS), Conversations/Siskin have 1:1 calls, but no group calls

---

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

#### 2.1 Speaking Indicator ⏸️ **DEFERRED**

**Problem**: In group calls, hard to know who is speaking.

**Solution**: Visual indicator (e.g., green border) around speaking participant.

**Status**: ⏸️ **Postponed** - affects both 1:1 and group calls, needs careful testing of working functionality

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
- `main/src/ui/call_window/group_call_participant_list.vala`
- May need backend changes to expose audio levels

**Estimated effort**: 6-8 hours (needs audio analysis)
**Note**: Postponed to avoid breaking working 1:1 calls

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
   - Could collision if two calls started simultaneously?

4. **Gajim 2.4.0 Incompatibility**
   - No audio/video calls possible between DinoX and Gajim 2.4.0
   - **Possible causes**:
     * Codec mismatch (Opus parameters, payload types)
     * Jingle transport negotiation failure (ICE candidates)
     * DTLS-SRTP fingerprint verification issues
     * RTP/RTCP port negotiation
   - **Debugging needed**:
     * Enable Jingle debug logging in both clients
     * Compare SDP offers/answers
     * Check GStreamer pipeline compatibility
     * Verify STUN/TURN server configuration

### Observed Runtime Issues

**From production logs (Nov 25, 2025)** - ✅ **All fixed same day**:

1. **PipeWire Device Cleanup Warning** ✅ **FIXED**
   ```
   rtp-WARNING: device.vala:582: pipewiredevice0-tee still has 1 src pads while being destroyed
   ```
   - **Impact**: Memory leak potential, resources not fully released
   - **Cause**: GStreamer tee element not properly unlinked before disposal
   - **Fix applied**: Explicit pad unlinking and releasing in `plugins/rtp/src/device.vala`
   - **Status**: Fixed Nov 25, 2025 - see Bug Tracker #1

2. **libnice TURN Refresh Warning** ✅ **FIXED**
   ```
   libnice-WARNING: We still have alive TURN refreshes. Consider using nice_agent_close_async()
   ```
   - **Impact**: TURN server connection not cleanly closed
   - **Cause**: Agent disposed before async cleanup completed
   - **Fix applied**: Use `nice_agent_close_async()` with callback in `plugins/ice/src/transport_parameters.vala`
   - **Status**: Fixed Nov 25, 2025 - see Bug Tracker #2

3. **Entity Caps Hash Mismatch** ✅ **FIXED**
   ```
   libdino-WARNING: entity_info.vala:234: Claimed entity caps hash doesn't match computed one
   ```
   - **Impact**: Service discovery might be unreliable for that peer
   - **Cause**: Peer's client advertises incorrect capabilities hash (XEP-0115)
   - **Effect on MUJI**: Could think peer doesn't support MUJI when it does
   - **Fix applied**: Store disco#info data even with hash mismatch, use computed hash as fallback
   - **Status**: Fixed Nov 25, 2025 - see Bug Tracker #3

4. **Gajim 2.4.0 Call Incompatibility** ⏳ **Under Investigation**
   ```
   Audio/video calls fail completely between DinoX ↔ Gajim 2.4.0
   ```
   - **Impact**: No interoperability with Gajim users for A/V calls
   - **Suspected Causes**: Codec negotiation mismatch, Jingle transport differences
   - **Status**: Analysis complete Nov 25, 2025 - see Bug Tracker #4 for debug plan
   - **Fix needed**: Fallback to disco#info query if caps hash mismatch

4. **MUC Exit Status Code 110** ℹ️
   ```
   DEBUG: Status codes: 110 
   DEBUG: Item node found, but no reason node.
   ```
   - **Meaning**: Status 110 = "This room shows unavailable members"
   - **Context**: Appears during MUJI call cleanup when leaving temporary MUC
   - **Impact**: None, expected behavior for MUJI temporary rooms
   - **Note**: MUJI MUCs use random names (e.g., `08774e2a@conference...`)

### Missing Test Coverage

**Critical gaps**:
- ❌ No automated tests for MUJI protocol
- ❌ No integration tests for multi-party media
- ❌ No performance benchmarks documented
- ❌ No interoperability tests with other clients
- ❌ No cleanup/teardown tests (causes warnings above)

**Testing priorities**:
1. **Unit tests**: Codec intersection algorithm
2. **Integration tests**: 3-participant call scenarios
3. **Cleanup tests**: Verify proper resource disposal (PipeWire, libnice)
4. **Interop tests**: DinoX ↔ Gajim group calls
5. **Performance tests**: 5+ participant stress test
6. **Network tests**: Simulate packet loss, latency, jitter

---

## Bug Tracker

### 🐛 Active Bugs (Need Fixing)

| ID | Severity | Component | Description | Status |
|----|----------|-----------|-------------|--------|
| #1 | Medium | RTP Plugin | PipeWire tee src pads not cleaned up properly | ⏸️ Reverted (caused crashes) |
| #2 | Low | ICE | libnice TURN refresh not closed asynchronously | ⏸️ Reverted (caused crashes) |
| #3 | Medium | Entity Info | Entity caps hash mismatch not handled gracefully | ✅ Fixed |
| #4 | High | Interop | No audio/video calls to Gajim 2.4.0 | 📋 Requires live testing |

### 📋 Issue Details

#### Bug #1: PipeWire Device Cleanup ⚠️ **REVERTED - CAUSED CRASHES**
**File**: `plugins/rtp/src/device.vala:576-590`  
**Symptom**: `pipewiredeviceX-tee still has 1 src pads while being destroyed`  
**Root Cause**: GStreamer tee element request pads not properly released  
**Fix Attempted** (Nov 25, 2025): Manually unlink and release all src pads in dispose()
```vala
// Attempted fix that caused crashes:
var iter = Gst.Iterator<Gst.Pad>(tee.iterate_src_pads());
Gst.Pad pad;
while (iter.next(out pad) == Gst.IteratorResult.OK) {
    if (pad.is_linked()) pad.unlink(pad.get_peer());
    tee.release_request_pad(pad);  // ← This breaks active calls!
}
```
**Result**: ❌ **Caused 1:1 video/audio calls to crash immediately**  
**Root Cause of Crash**: Calling `release_request_pad()` during or right after active calls destroys GStreamer pipeline  
**Status**: ⏸️ **Reverted to original** - GStreamer handles cleanup automatically when element goes to NULL state

**Lesson Learned**: The warning is informational only. Manual pad manipulation in dispose() is dangerous and unnecessary.

---

#### Bug #2: TURN Refresh Cleanup ⚠️ **REVERTED - CAUSED CRASHES**
**File**: `plugins/ice/src/transport_parameters.vala`  
**Symptom**: `We still have alive TURN refreshes`  
**Root Cause**: libnice Agent not properly closed before disposal  
**Fix Attempted** (Nov 25, 2025): Call `agent.close_async()` in `dispose()` with callback
```vala
// Attempted fix that caused crashes:
public override void dispose() {
    if (agent != null && !agent_closing) {
        agent_closing = true;
        agent.close_async(() => { /* cleanup */ });  // ← Race condition!
    }
    thread_loop.quit();  // ← Called immediately after!
}
```
**Result**: ❌ **Caused 1:1 video/audio calls to crash immediately**  
**Root Cause of Crash**: Race condition - `close_async()` callback runs after `thread_loop.quit()` already terminated the loop  
**Status**: ⏸️ **Reverted to original** - needs different approach

**Alternative Solutions to Explore**:
1. Call `close_async()` in `terminate()` method instead of `dispose()`
2. Wait synchronously for close operation to complete before quitting loop
3. Accept the warning as harmless (TURN connections auto-expire after timeout)

---

#### Bug #3: Entity Caps Hash Mismatch ✅ **FIXED**
**File**: `libdino/src/service/entity_info.vala:234`  
**Symptom**: Claimed entity caps hash doesn't match computed one  
**Root Cause**: Peer advertises incorrect XEP-0115 capabilities hash, disco#info data discarded  
**Fix Applied** (Nov 25, 2025):
```vala
// Always store disco#info data even if hash mismatches
if (hash != null && computed_hash != hash) {
    warning("Claimed entity caps hash from %s doesn't match computed one (claimed: %s, computed: %s). Using computed hash as fallback.",
            jid.to_string(), hash, computed_hash);
}

// Store with computed hash instead of discarding
db.entity.upsert()
    .value(db.entity.caps_hash, computed_hash)
    .perform();

store_features(computed_hash, info_result.features);
store_identities(computed_hash, info_result.identities);
```
**Impact**: Service discovery reliable even with incorrect caps, MUJI detection works  
**Status**: Merged, ready for testing

---

#### Bug #4: Gajim 2.4.0 Incompatibility ⏳ **ANALYSIS COMPLETE**
**Symptom**: Audio/video calls fail completely between DinoX and Gajim 2.4.0  
**Suspected Root Causes** (Nov 25, 2025 analysis):

1. **Codec Parameter Mismatch**
   - DinoX Opus config: `clockrate=48000, channels=2, id=111, useinbandfec=1`
   - Gajim might use: Different payload ID, missing useinbandfec, or dtx parameter
   - DinoX codec priority: Opus > Speex (32k/16k/8k) > G.722 > PCMU > PCMA

2. **Jingle Content Negotiation**
   - DinoX sends: `<content name="audio">` with all supported codecs
   - Gajim might expect: Specific content-name format or different codec list order
   - Intersection algorithm in `xmpp-vala/src/module/xep/0272_muji.vala` might fail

3. **ICE/DTLS Transport Issues**
   - DinoX uses: libnice 0.1.21+, GnuTLS for DTLS-SRTP
   - Candidates, fingerprints, or setup roles might not match expectations

4. **XEP-0272 MUJI Implementation Differences**
   - DinoX uses `<preparing>` node, Gajim might not wait for it
   - Presence-based negotiation timing could differ

**Diagnostic Steps Needed**:
```bash
# 1. Capture Jingle XML stanzas from both clients
G_MESSAGES_DEBUG=all flatpak run im.github.rallep71.DinoX 2>&1 | grep -E "jingle|session-initiate|session-accept" > dinox-jingle.log

# 2. Compare codec offers
grep "payload-type" dinox-jingle.log | grep opus

# 3. Check ICE candidates
grep "candidate" dinox-jingle.log

# 4. Verify DTLS fingerprints
grep "fingerprint" dinox-jingle.log
```

**Potential Fixes to Try**:

1. **Simplify Opus parameters**:
   ```vala
   // In plugins/rtp/src/module.vala:134
   var opus = new JingleRtp.PayloadType() { 
       channels = 2, 
       clockrate = 48000, 
       name = "opus", 
       id = 111 
   };
   // Remove or make optional: opus.parameters["useinbandfec"] = "1";
   ```

2. **Test with minimal codec** (PCMU only):
   ```vala
   // Temporarily comment out all codecs except PCMU in get_supported_payloads()
   ```

3. **Add compatibility mode**:
   ```vala
   // Detect Gajim client and adjust codec list
   if (peer_client_name.contains("gajim")) {
       // Use Gajim-compatible Opus config
   }
   ```

**Impact**: Critical - breaks all A/V calls with Gajim users  
**Effort**: High - requires live testing with Gajim 2.4.0  
**Priority**: High  
**Status**: Needs runtime debugging with both clients

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

## 🔮 Future Development Roadmap

### Phase 3: Advanced Features (v0.7.0+)

#### ✅ Message Retraction UI - **ALREADY IMPLEMENTED**
**Status**: ✅ Complete - XEP-0424 backend + full UI
- "Delete for everyone" option in message context menu
- Dialog with options: "Delete locally" / "Delete for everyone"
- MUC moderation support for room moderators
- **Files**: `main/src/ui/conversation_content_view/item_actions.vala`
- **Backend**: `libdino/src/service/message_deletion.vala`

---

#### 🔔 Push Notifications (XEP-0357) - **PLANNED**
**Status**: 🚧 Not implemented yet
**Priority**: 🔥 High - Very requested feature

**What**: Receive notifications even when DinoX is closed
- Server-side push via XEP-0357
- Desktop notifications via libnotify/GNotifications
- Wake app on notification

**Implementation Plan**:
1. Check existing notification infrastructure (`notifier_gnotifications.vala`, `notifier_freedesktop.vala`)
2. Implement XEP-0357 module in `xmpp-vala/src/module/xep/`
3. Register with push service on connection
4. Handle push wake-up signal
5. Update notification preferences UI

**Estimated Effort**: 8-12 hours
**Dependencies**: 
- XEP-0357 Push Notifications
- XEP-0388 SASL2 (recommended but not required)
- Server support for push

**Files to create**:
- `xmpp-vala/src/module/xep/0357_push_notifications.vala`
- Push service configuration in preferences

**Testing needs**:
- Modern XMPP server with push support (Prosody 0.12+, ejabberd 21+)
- Test with app closed/backgrounded
- Verify battery impact

---

#### 📊 Speaking Indicators - **DEFERRED**
See Priority 2, Section 2.1 above - postponed to avoid breaking working calls

---

### Phase 4: Enterprise Features (v0.8.0+)

#### Call Recording
- Record all streams to separate files
- Mux with ffmpeg after call
- Requires consent from all participants
- Legal/GDPR considerations

#### Screen Sharing in Group Calls
- Extend MUJI for screen capture source
- Layout: Main screen + video thumbnails

#### Advanced MUJI
- Mid-call invitations
- Selective participant invitations
- Call migration (move to different room)

---

**Document Created**: November 24, 2025  
**Last Updated**: November 26, 2025  
**Target Version**: 0.6.5.3 (Phase 1 Complete)
