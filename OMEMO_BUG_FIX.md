# OMEMO Decryption Bug Fix - Session 2025-11-27

## Bug Description

### Symptoms
- Old/inactive 1:1 chats show `[This message is OMEMO encrypted]` instead of decrypting messages
- Bug occurs when:
  1. DinoX is closed and reopened (new session)
  2. Other client (e.g., Monal) sends OMEMO encrypted message to old chat
  3. DinoX cannot decrypt: shows `[This message is OMEMO encrypted]`
- After DinoX sends a message back, encryption works again in both directions
- **Important:** This bug does NOT occur in Monal or other XMPP clients

### Reproduction Steps
1. Have an old 1:1 chat between DinoX and Monal (never deleted/cleaned)
2. Close DinoX completely
3. Reopen DinoX (fresh session)
4. From Monal: Send OMEMO encrypted message to DinoX
5. **Result:** DinoX shows `[This message is OMEMO encrypted]` (cannot decrypt)
6. From DinoX: Send any OMEMO message to Monal
7. **Result:** Now Monal → DinoX encryption works again

## Root Cause Analysis

### Technical Details
- When DinoX starts a new session, it requests its own device list from PubSub
- However, it does NOT actively republish/announce the device list to subscribers
- Other clients (like Monal) have the **old/stale device list** cached
- Monal encrypts messages for DinoX's **old device ID** (from cache)
- DinoX has a **new device ID** (or session), cannot decrypt messages encrypted for old ID
- When DinoX sends a message, it automatically publishes device list → Monal updates cache → encryption works

### Why Monal Doesn't Have This Bug
- Monal actively manages and republishes device lists on connect
- Other clients immediately get updated device list from Monal
- No stale device ID issues

### Code Location
File: `plugins/omemo/src/logic/manager.vala`
Function: `on_stream_negotiated()`

**Before Fix:**
```vala
private void on_stream_negotiated(Account account, XmppStream stream) {
    StreamModule module = stream_interactor.module_manager.get_module(account, StreamModule.IDENTITY);
    if (module != null) {
        module.request_user_devicelist.begin(stream, account.bare_jid);
    }
}
```

Only requested device list, did not republish → subscribers keep stale cache.

## Fix Implementation

### Solution
Force republish device list on every connect to trigger PEP notification to all subscribers.

### Code Changes

**File:** `plugins/omemo/src/logic/manager.vala`

**Modified Function:** `on_stream_negotiated()`
```vala
private void on_stream_negotiated(Account account, XmppStream stream) {
    StreamModule module = stream_interactor.module_manager.get_module(account, StreamModule.IDENTITY);
    if (module != null) {
        // Request our device list - this will automatically trigger republish if needed
        module.request_user_devicelist.begin(stream, account.bare_jid, (obj, res) => {
            module.request_user_devicelist.end(res);
            // Force republish of device list to notify all subscribers
            republish_device_list(account, stream);
        });
    }
}
```

**New Function:** `republish_device_list()`
```vala
private void republish_device_list(Account account, XmppStream stream) {
    int identity_id = db.identity.get_id(account.id);
    if (identity_id < 0) return;

    // Build device list with all known active devices
    ArrayList<int32> devices = new ArrayList<int32>();
    foreach (Row row in db.identity_meta.with_address(identity_id, account.bare_jid.to_string())
            .with(db.identity_meta.now_active, "=", true)) {
        devices.add(row[db.identity_meta.device_id]);
    }

    // Create device list stanza node
    StanzaNode list_node = new StanzaNode.build("list", Xep.Omemo.NS_URI).add_self_xmlns();
    foreach (int32 device_id in devices) {
        list_node.put_node(new StanzaNode.build("device", Xep.Omemo.NS_URI)
            .put_attribute("id", device_id.to_string()));
    }

    // Publish to trigger PEP notification to all subscribers
    // NODE_DEVICELIST = "eu.siacs.conversations.axolotl.devicelist"
    stream.get_module(Xep.Pubsub.Module.IDENTITY).publish.begin(stream, account.bare_jid, 
        Xep.Omemo.NS_URI + ".devicelist", null, list_node);
    
    debug("Republished device list for %s with %d devices", account.bare_jid.to_string(), devices.size);
}
```

### How It Works
1. DinoX connects to XMPP server
2. `on_stream_negotiated()` is triggered
3. Requests own device list from PubSub
4. **NEW:** Immediately republishes device list with all active devices
5. PubSub sends PEP notification to all subscribers (including Monal)
6. Monal receives updated device list with current DinoX device ID
7. Monal encrypts future messages for correct device ID
8. DinoX can decrypt incoming messages immediately

## Testing

### Test Date
2025-11-27

### Test Result
✅ **PASSED** - Initial test successful

### Test Procedure
1. Built DinoX with fix: `cd /media/linux/SSD128/xmpp/build && ninja`
2. Started DinoX: `./main/dinox`
3. Opened old 1:1 chat with Monal
4. Sent OMEMO encrypted message from Monal → DinoX
5. **Result:** Message decrypted successfully, no `[This message is OMEMO encrypted]` error

### Follow-Up Testing Needed
- [ ] Test after several hours of inactivity
- [ ] Test in Flatpak version
- [ ] Test with multiple devices
- [ ] Test with group chats (MUC)

## Previous Fix Attempts

### Attempt 1 (Failed)
**File:** `plugins/omemo/src/logic/decrypt.vala` line 193
**Change:** Removed `if (device == null)` condition to always update device list on prekey messages
**Result:** Bug persisted - fix was too late, message already undecryptable

### Attempt 2 (Failed)
**File:** `plugins/omemo/src/logic/decrypt.vala` line 91
**Change:** Added republish device list when receiving undecryptable message
**Result:** Bug persisted - too late, Monal already encrypted with stale device list

### Attempt 3 (Success)
**File:** `plugins/omemo/src/logic/manager.vala` 
**Change:** Proactive republish on stream connect (before any messages)
**Result:** ✅ Success - subscribers get updated device list immediately

## Related Files

### Modified Files
- `plugins/omemo/src/logic/manager.vala` - Main fix

### Related Files (Not Modified)
- `plugins/omemo/src/logic/decrypt.vala` - Contains decryption logic and failed fix attempts
- `plugins/omemo/src/protocol/stream_module.vala` - Device list parsing and PubSub management
- `plugins/omemo/src/logic/database.vala` - OMEMO database schema

## Commit Information

### Changes to Commit
```bash
git add plugins/omemo/src/logic/manager.vala
git commit -m "Fix OMEMO decryption in old chats by republishing device list on connect

- Force republish device list when stream is negotiated
- Triggers PEP notification to all subscribers with current device ID
- Prevents stale device list cache in other clients
- Fixes 'This message is OMEMO encrypted' error in inactive chats

Fixes issue where DinoX couldn't decrypt incoming OMEMO messages
after restart until it sent a message first."
```

## Notes

- Bug only affects **receiving** encrypted messages after DinoX restart
- Sending from DinoX always worked (triggers device list update automatically)
- Fix is proactive: prevents problem before it occurs
- Should also improve OMEMO reliability with other XMPP clients
- May reduce OMEMO session negotiation delays

## Monitoring

If bug reappears, check:
1. Debug output: Look for "Republished device list for X with Y devices"
2. Verify PEP notification is actually sent to subscribers
3. Check if other client receives and processes device list update
4. Verify device ID consistency in database vs. current session
5. Test with `G_MESSAGES_DEBUG=all` for full OMEMO debug output
