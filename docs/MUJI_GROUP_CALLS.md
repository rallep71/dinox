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

### ✅ Implemented

- Private room detection (`is_private_room()`)
- Group call initiation (`initiate_groupchat_call()`)
- MUJI protocol module (`xmpp-vala/src/module/xep/0272_muji.vala`)
- UI checks for group call availability

### ⚠️ Partial / Needs Testing

- Media negotiation for multiple participants
- Call state synchronization across clients
- Mute/unmute in group calls
- Video stream handling with multiple participants

### ❌ Not Implemented

- Screen sharing in group calls
- Recording group calls
- Call quality indicators for each participant
- Individual volume controls

## Troubleshooting

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

## Testing MUJI Group Calls

### Test Setup

1. Create a test private room:
   ```
   testcall@conference.example.org
   - Members-only: ✓
   - Non-anonymous: ✓
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

## Future Improvements

### Priority 1: Stabilization

- [ ] Test with 3+ participants
- [ ] Fix any media synchronization issues
- [ ] Improve error handling and user feedback

### Priority 2: Features

- [ ] Show participant list in active group call
- [ ] Individual volume controls
- [ ] Visual indicators for who is speaking
- [ ] Call recording (with consent)

### Priority 3: Advanced

- [ ] Screen sharing support
- [ ] Virtual backgrounds
- [ ] Noise cancellation
- [ ] Bandwidth adaptation

## References

- [XEP-0272: Multiparty Jingle (MUJI)](https://xmpp.org/extensions/xep-0272.html)
- [XEP-0045: Multi-User Chat](https://xmpp.org/extensions/xep-0045.html)
- DinoX code: `libdino/src/service/calls.vala`
- DinoX code: `xmpp-vala/src/module/xep/0272_muji.vala`

---

**Last Updated**: November 24, 2025  
**DinoX Version**: 0.6.5.2+
