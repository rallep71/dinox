# MUJI Group Calls in DinoX

## Overview

DinoX partially implements XEP-0272 (Multiparty Jingle - MUJI) for audio/video group calls in Multi-User Chat (MUC) rooms. This document explains the requirements, configuration, and current implementation status.

## Requirements

### Private Room Configuration

MUJI group calls **only work in private rooms**. A private room is defined as:
- **members-only** (muc#roomconfig_membersonly)
- **non-anonymous** (muc#roomconfig_whois = anyone)

### Why Private Rooms?

Private rooms are required for security and privacy:
1. **Members-only**: Prevents unauthorized users from joining the call
2. **Non-anonymous**: All participants' real JIDs are visible (required for direct media connections)

### Additional Requirements

- Default MUC server must be configured in account settings
- All participants must support XEP-0272 (MUJI)
- Server must support XEP-0045 (MUC) with private room features

## Creating a Private Room

### Method 1: Room Creation Dialog

When creating a new room in DinoX:

1. Open "Join/Create Room" dialog
2. Enter room name and server
3. Click "Advanced Settings"
4. Enable:
   - ☑ **Members-only** (`muc#roomconfig_membersonly`)
   - ☑ **Show real JIDs** (`muc#roomconfig_whois = anyone`)

### Method 2: Configure Existing Room

If you're the room owner:

1. Right-click room in conversation list
2. Select "Room Configuration"
3. Find "Access Control" section
4. Enable:
   - ☑ **Members-only room**
   - ☑ **Who can see real JIDs?** → Select "Anyone"

### Method 3: XMPP Server Admin Interface

Most XMPP servers provide web interfaces (e.g., Prosody, ejabberd admin panel):

1. Navigate to MUC room settings
2. Set `muc#roomconfig_membersonly = true`
3. Set `muc#roomconfig_whois = anyone`

## Verifying Private Room Status

### In DinoX Code

The function `is_private_room()` in `libdino/src/service/muc_manager.vala` checks:

```vala
public bool is_private_room(Account account, Jid jid) {
    Xmpp.XmppStream? stream = stream_interactor.get_stream(account);
    if (stream == null) return false;
    
    return stream.get_flag(Xep.Muc.Flag.IDENTITY).has_room_feature(jid, Xep.Muc.Feature.MEMBERS_ONLY) &&
           stream.get_flag(Xep.Muc.Flag.IDENTITY).has_room_feature(jid, Xep.Muc.Feature.NON_ANONYMOUS);
}
```

### Manual Check

Query room features using XMPP client tools:
```xml
<iq type='get' to='room@conference.example.org' id='disco1'>
  <query xmlns='http://jabber.org/protocol/disco#info'/>
</iq>
```

Look for:
- `muc_membersonly` feature
- `muc_nonanonymous` feature

## Initiating a Group Call

### From DinoX UI

1. Open a private MUC room
2. Click the **phone icon** (📞) in the conversation header
3. DinoX will initiate a MUJI group call

### Prerequisites Check

DinoX performs these checks in `libdino/src/service/calls.vala`:

```vala
public bool can_initiate_groupcall(Conversation conversation) {
    if (conversation.type_ != Conversation.Type.GROUPCHAT) return false;
    
    // Must be a private room
    if (!muc_manager.is_private_room(conversation.account, conversation.counterpart.bare_jid)) {
        return false;
    }
    
    // Default MUC server must be configured
    if (default_muc_server[conversation.account] == null) return false;
    
    return true;
}
```

## Configuration in DinoX

### Setting Default MUC Server

1. Open **Settings** → **Accounts**
2. Select your account
3. Click **Advanced Settings**
4. Set **Default conference server** (e.g., `conference.example.org`)

### Checking MUJI Support

DinoX automatically detects if the server and other clients support MUJI through service discovery (XEP-0030).

## Current Implementation Status

### [DONE] Implemented

- Private room detection (`is_private_room()`)
- Group call initiation (`initiate_groupchat_call()`)
- MUJI protocol module (`xmpp-vala/src/module/xep/0272_muji.vala`)
- UI checks for group call availability

### [WARNING] Partial / Needs Testing

- Media negotiation for multiple participants
- Call state synchronization across clients
- Mute/unmute in group calls
- Video stream handling with multiple participants

### [NO] Not Implemented

- Screen sharing in group calls
- Recording group calls
- Call quality indicators for each participant
- Individual volume controls

## Troubleshooting

### Runtime Warnings (Non-Critical)

**You may see these warnings in the logs - they are known issues but don't prevent calls from working:**

1. **PipeWire Device Cleanup Warning**
   ```
   rtp-WARNING: pipewiredeviceX-tee still has 1 src pads while being destroyed
   ```
   - **Meaning**: Audio/video device not fully cleaned up after call
   - **Impact**: Minor memory leak, but no functional issues
   - **When**: Appears at end of every call
   - **Action**: Safe to ignore, fix planned for future release

2. **libnice TURN Warning**
   ```
   libnice-WARNING: We still have alive TURN refreshes
   ```
   - **Meaning**: TURN server connection not cleanly closed
   - **Impact**: Minor, TURN session remains active briefly
   - **When**: Appears at end of calls using TURN relay
   - **Action**: Safe to ignore, will be fixed in next version

3. **Entity Caps Hash Mismatch**
   ```
   libdino-WARNING: Claimed entity caps hash doesn't match computed one
   ```
   - **Meaning**: Another client advertises incorrect capabilities
   - **Impact**: Might incorrectly detect MUJI support
   - **When**: Occasionally with certain clients
   - **Action**: DinoX will query capabilities directly if needed

### "Cannot start group call" Error

**Possible causes:**

1. **Not a private room**
   - Solution: Configure room as members-only + non-anonymous

2. **Default MUC server not set**
   - Solution: Add default conference server in account settings

3. **Peer doesn't support MUJI**
   - Solution: Ensure other participants use MUJI-compatible clients

4. **Network/firewall issues**
   - Solution: Check STUN/TURN server configuration

5. **Entity caps hash mismatch**
   - Symptom: Call button available but clicking does nothing
   - Solution: Restart both clients to refresh capabilities

### Room Not Detected as Private

**Debug steps:**

1. Check room features:
   ```bash
   # Using xmpp-console or similar tool
   disco info room@conference.example.org
   ```

2. Look for features:
   - `http://jabber.org/protocol/muc#membersonly`
   - `http://jabber.org/protocol/muc#nonanonymous`

3. Reconfigure room if features are missing

### Enable Debug Logging

**For detailed MUJI troubleshooting:**

```bash
# Run DinoX with full debug output
G_MESSAGES_DEBUG=all flatpak run im.github.rallep71.DinoX 2>&1 | tee dinox-debug.log

# Filter for specific topics:
# MUJI-specific logs:
grep -i "muji\|group.call" dinox-debug.log

# MUC presence tracking:
grep "on_received_unavailable\|on_received_available" dinox-debug.log

# Jingle negotiation:
grep -i "jingle\|session" dinox-debug.log

# Entity capabilities:
grep "entity caps\|disco#info" dinox-debug.log
```

**Useful debug patterns to look for:**

1. **MUJI MUC Creation**:
   ```
   DEBUG: Converting call to groupcall [random-id]@conference.example.org
   DEBUG: [account] MUJI joining as [hex-nick]
   ```

2. **Peer Joining**:
   ```
   DEBUG: Muji peer joined [real-jid] / [muc-jid/nick]
   DEBUG: Group call peer joined: [jid]
   ```

3. **Peer Leaving**:
   ```
   DEBUG: on_received_unavailable from [muc-jid/nick]
   DEBUG: Status codes: 110
   DEBUG: Muji peer left [jid]
   ```

4. **Codec Negotiation**:
   ```
   DEBUG: Payload intersection computed for [media]
   DEBUG: Using codec: opus/48000/2
   ```

## Testing MUJI Group Calls

### Test Setup

1. Create a test private room:
   ```
   testcall@conference.example.org
   - Members-only: [OK]
   - Non-anonymous: [OK]
   ```

2. Join with 2-3 test accounts (DinoX or other MUJI clients)

3. Configure default MUC server on all accounts

4. Initiate group call from one client

5. Accept call on other clients

### Expected Behavior

- All participants see "Group call in progress"
- Audio streams from all participants are mixed
- Each participant can mute/unmute themselves
- Call continues until all participants leave

## Related XEPs

- **XEP-0045**: Multi-User Chat (MUC) - base protocol
- **XEP-0166**: Jingle - media negotiation
- **XEP-0167**: Jingle RTP Sessions - audio/video
- **XEP-0272**: Multiparty Jingle (MUJI) - group calls
- **XEP-0353**: Jingle Message Initiation
- **XEP-0482**: Call Invites

## Client Compatibility

### MUJI Group Calls Support

| Client | Version | Support | Notes |
|--------|---------|---------|-------|
| **DinoX** | 0.6.5+ | [WARNING] Implemented, untested | Backend complete, needs multi-peer testing |
| **Gajim** | 2.4.0+ | [DONE] Full | Built-in support, well-tested |
| **Monal** | All | [NO] None | Only 1:1 calls supported |
| **Conversations** | All | [NO] None | Only 1:1 calls supported |

### 1:1 Call Compatibility

| DinoX ↔ Client | Status | Known Issues |
|----------------|--------|--------------|
| **DinoX** | [DONE] Works | - |
| **Gajim 2.4.0** | [NO] Broken | Audio/video calls fail - codec/negotiation mismatch |
| **Monal** | [WARNING] Untested | Should work, needs verification |
| **Conversations** | [WARNING] Untested | Should work, needs verification |

### Troubleshooting Gajim 2.4.0 Incompatibility

**Problem**: No audio/video calls possible between DinoX and Gajim 2.4.0

**Possible Causes**:
1. **Codec mismatch**: Opus parameters (useinbandfec, dtx) differ
2. **ICE negotiation failure**: STUN/TURN candidates incompatible
3. **DTLS-SRTP**: Certificate/fingerprint verification issues
4. **Jingle version**: Different XEP-0166/167 interpretations

**Debug Steps**:
```bash
# Enable debug logging in DinoX
G_MESSAGES_DEBUG=all flatpak run im.github.rallep71.DinoX 2>&1 | grep -i jingle

# In Gajim: Preferences → Advanced → Show Logs → Filter: "jingle"
```

**What to look for**:
- SDP offer/answer exchanges
- ICE candidate gathering
- DTLS handshake errors
- Codec negotiation failures

**Workarounds**:
- Use DinoX ↔ DinoX for 1:1 calls
- Use Gajim ↔ Gajim if both parties have it
- For MUJI: Ensure all participants use compatible clients

---

## Known Limitations

### Not Implemented

- [NO] **Screen sharing** in group calls
- [NO] **Call recording** functionality
- [NO] **Call quality indicators** (per-participant metrics)
- [NO] **Individual volume controls** for each participant
- [NO] **Speaking indicators** (visual feedback)
- [NO] **Mid-call invitations** (invite to ongoing call)
- [NO] **Reconnection logic** after network interruption

### Partially Implemented

- [WARNING] **Multi-participant media**: Code exists, not tested with 3+ peers
- [WARNING] **Error handling**: Basic checks, no user-friendly messages
- [WARNING] **Performance**: Unknown with 5+ participants

---

## Future Improvements

### Priority 1: Stabilization & Testing

- [ ] Test with 3+ DinoX participants
- [ ] Document multi-instance test setup
- [ ] Fix Gajim 2.4.0 compatibility issues
- [ ] Add automated MUJI protocol tests
- [ ] Improve error messages and user feedback

### Priority 2: UI/UX Enhancements

- [x] [DONE] Participant list in active group call
- [ ] Individual volume controls per participant
- [ ] Visual indicators for who is speaking
- [ ] Call quality indicators (ping, packet loss)
- [ ] Better call state visualization

### Priority 3: Advanced Features

- [ ] Screen sharing support
- [ ] Call recording (with consent)
- [ ] Virtual backgrounds
- [ ] Noise cancellation tuning
- [ ] Bandwidth adaptation
- [ ] Mid-call participant invitations

## References

- [XEP-0272: Multiparty Jingle (MUJI)](https://xmpp.org/extensions/xep-0272.html)
- [XEP-0045: Multi-User Chat](https://xmpp.org/extensions/xep-0045.html)
- DinoX code: `libdino/src/service/calls.vala`
- DinoX code: `xmpp-vala/src/module/xep/0272_muji.vala`

---

**Last Updated**: November 25, 2025  
**DinoX Version**: 0.6.5.2+  
**Status**: Backend complete, UI improvements in progress
