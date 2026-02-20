# Monal Issue #1576: session-terminate Analysis

> **Date**: February 18, 2026
> **Monal Issue**: https://github.com/monal-im/Monal/issues/1576
> **Reporter**: jacquescomeaux
> **Affected**: Monal Stable 6.4.18 (1077), iOS 26.0
> **Counterpart**: DinoX (Dino fork) via standard Jingle RTP

---

## Summary

When DinoX (the calling party) ends a call by hanging up, Monal does **not** process the incoming `session-terminate` stanza. Instead, Monal waits for the RTP media stream to time out (~8 seconds), then sends its own `session-terminate` with `<connectivity-error/>`, and displays "Call ended: connection failed" to the user.

This is a **Monal-side bug**. DinoX sends a valid, XEP-0166-compliant `session-terminate` that Monal fails to act upon.

---

## Stanza Timeline (from the issue)

### 1. DinoX sends session-terminate (user hangs up)

```xml
<iq id='7b6b7a1d-4525-451e-98f6-7f3e3060ae69' type='set'
    to='****@jacquescomeaux.xyz/Monal-iOS.e6d89ff2'>
  <jingle xmlns='urn:xmpp:jingle:1'
          action='session-terminate'
          sid='57620B3A-F96E-46AA-BF68-EAB943129810'>
    <reason>
      <success/>
    </reason>
  </jingle>
</iq>
```

**Analysis**: Fully compliant with XEP-0166 Section 6.7. The `<success/>` reason element indicates a normal, user-initiated call end. The SID matches the active session.

### 2. ~8 seconds later: Monal sends its own session-terminate

```xml
<iq lang='en' type='set'
    to='****@jacquescomeaux.xyz/dino.c703afd7'
    from='****@jacquescomeaux.xyz/Monal-iOS.e6d89ff2'
    id='562A60C8-BCE5-4FE7-8432-64C1295DD7BD'>
  <jingle sid='57620B3A-F96E-46AA-BF68-EAB943129810'
          xmlns='urn:xmpp:jingle:1'
          action='session-terminate'>
    <reason>
      <connectivity-error/>
    </reason>
  </jingle>
</iq>
```

**Analysis**: Monal did not process DinoX's `session-terminate` from step 1. Instead, after ~8 seconds (typical RTP timeout), Monal detected that the media stream stopped and concluded there was a "connectivity error". It then sent its own `session-terminate` for the **same SID** -- a session that DinoX has already cleaned up.

### 3. DinoX responds with unknown-session error

```xml
<iq id='562A60C8-BCE5-4FE7-8432-64C1295DD7BD' type='error'
    to='****@jacquescomeaux.xyz/Monal-iOS.e6d89ff2'>
  <error type='cancel'>
    <item-not-found xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/>
    <unknown-session xmlns='urn:xmpp:jingle:errors:1'/>
  </error>
</iq>
```

**Analysis**: DinoX correctly responds with `<item-not-found>` + `<unknown-session/>` because it already terminated and removed this session in step 1. This is the correct behavior per XEP-0166 Section 6.7: after sending `session-terminate`, the session is destroyed.

### 4. Monal sends Jingle Message finish notification

```xml
<message lang='en' type='chat'
         to='****@jacquescomeaux.xyz/dino.c703afd7'
         from='****@jacquescomeaux.xyz/Monal-iOS.e6d89ff2'>
  <finish id='57620B3A-F96E-46AA-BF68-EAB943129810'
          xmlns='urn:xmpp:jingle-message:0'>
    <reason xmlns='urn:xmpp:jingle:1'>
      <connectivity-error/>
    </reason>
  </finish>
</message>
```

**Analysis**: Monal broadcasts a `<finish>` (XEP-0353) with `<connectivity-error/>` -- confirming it never processed the clean `<success/>` termination and instead believes the call failed due to network issues.

---

## DinoX session-terminate Implementation (Proof of Correctness)

### Sending session-terminate (DinoX hangs up)

**File**: `xmpp-vala/src/module/xep/0166_jingle/session.vala`, lines 410-440

```vala
public void terminate(ReasonElement reason, string? reason_text, string? local_reason) {
    if (state == State.ENDED) return;  // Already ended, no double-terminate

    string reason_str;
    if (local_reason != null) {
        reason_str = @"local session-terminate: $(local_reason)";
    } else {
        reason_str = "local session-terminate";
    }

    // Build session-terminate stanza with reason
    StanzaNode terminate_jingle = new StanzaNode.build("jingle", NS_URI)
        .add_self_xmlns()
        .put_attribute("action", "session-terminate")
        .put_attribute("sid", sid);

    StanzaNode reason_node = new StanzaNode.build("reason", NS_URI);
    reason_node.put_node(new StanzaNode.build(reason.to_string(), NS_URI));
    if (reason_text != null) {
        reason_node.put_node(new StanzaNode.build("text", NS_URI).put_node(new StanzaNode.text(reason_text)));
    }
    terminate_jingle.put_node(reason_node);

    Iq.Stanza iq = new Iq.Stanza.set(terminate_jingle) { to = peer_full_jid };
    stream.get_module<Iq.Module>(Iq.Module.IDENTITY).send_iq(stream, iq);

    // Clean up locally
    foreach (Content content in contents) {
        content.terminate(true, reason.to_string(), reason_text);
    }
    state = State.ENDED;
    terminated(stream, true, reason.to_string(), reason_text);
}
```

Key points:
- State guard: `if (state == State.ENDED) return` prevents double-terminate
- Standard `<reason><success/></reason>` for user-initiated hangup
- Session state set to `ENDED` immediately after sending
- `terminated` signal fires, which triggers session removal from the session map

### Receiving session-terminate (remote hangs up)

**File**: `xmpp-vala/src/module/xep/0166_jingle/session.vala`, lines 283-318

```vala
private void handle_session_terminate(StanzaNode jingle, Iq.Stanza iq) throws IqError {
    string? reason_text = null;
    string? reason_name = null;
    StanzaNode? reason_node = iq.stanza.get_deep_subnode(NS_URI + ":jingle", NS_URI + ":reason");
    if (reason_node != null) {
        // Parse reason element
        StanzaNode? specific_reason_node = null;
        StanzaNode? text_node = null;
        foreach (StanzaNode node in reason_node.sub_nodes) {
            if (node.name == "text") {
                text_node = node;
            } else if (node.ns_uri == NS_URI) {
                specific_reason_node = node;
            }
        }
        reason_name = specific_reason_node != null ? specific_reason_node.name : null;
        reason_text = text_node != null ? text_node.get_string_content() : null;
    }

    // Terminate all content streams
    foreach (Content content in contents) {
        content.terminate(false, reason_name, reason_text);
    }

    // Send IQ result acknowledgment
    stream.get_module<Iq.Module>(Iq.Module.IDENTITY).send_iq(stream, new Iq.Stanza.result(iq));

    // Mark session as ended
    state = State.ENDED;
    terminated(stream, false, reason_name, reason_text);
}
```

Key points:
- **Synchronous processing** -- no async delay, no timeout dependency
- Sends `<iq type='result'>` acknowledgment immediately (XEP-0166 requirement)
- All content streams terminated immediately
- State set to `ENDED`
- `terminated` signal removes session from the map

### Session lookup for incoming IQ

**File**: `xmpp-vala/src/module/xep/0166_jingle/jingle_module.vala`, lines 195-220

```vala
public async void handle_iq_set(XmppStream stream, Iq.Stanza iq) throws IqError {
    StanzaNode? jingle_node = iq.stanza.get_subnode("jingle", NS_URI);
    string? sid = jingle_node.get_attribute("sid");
    string? action = jingle_node.get_attribute("action");

    Session? session = yield stream.get_flag(Flag.IDENTITY).get_session(sid);

    if (action == "session-initiate") {
        if (session != null) {
            // SID conflict
            send error CONDITION_CONFLICT
            return;
        }
        yield handle_session_initiate(stream, sid, jingle_node, iq);
        return;
    }

    if (session == null) {
        // Session not found -- already terminated or never existed
        StanzaNode unknown_session = new StanzaNode.build("unknown-session", ERROR_NS_URI).add_self_xmlns();
        stream.get_module<Iq.Module>(Iq.Module.IDENTITY).send_iq(stream,
            new Iq.Stanza.error(iq, new ErrorStanza.item_not_found(unknown_session)) { to=iq.from });
        return;
    }

    session.handle_iq_set(action, jingle_node, iq);
}
```

Key points:
- If a `session-terminate` arrives for an unknown SID, DinoX correctly returns `<item-not-found>` + `<unknown-session/>`
- This is exactly what happens in step 3 of the stanza timeline: Monal sends a late terminate for a session DinoX already cleaned up

### Session removal on terminated signal

**File**: `xmpp-vala/src/module/xep/0166_jingle/jingle_module.vala`, lines 115, 163

```vala
// When we initiate:
session.terminated.connect((session, stream, _1, _2, _3) => {
    stream.get_flag(Flag.IDENTITY).remove_session(session.sid);
});

// When we receive initiation:
session.terminated.connect((stream) => {
    stream.get_flag(Flag.IDENTITY).remove_session(sid);
});
```

The session is removed from the map **immediately** when the `terminated` signal fires. Any subsequent IQ for this SID will get `unknown-session`.

---

## Root Cause: Monal Bug -- Inverted Condition in session-terminate Handler

> **Updated**: February 20, 2026
> **Monal developer response**: tmolitor-stud-tu claims session-terminate handling is "already implemented" and links to:
> - develop: https://github.com/monal-im/Monal/blob/develop/Monal/Classes/MLCall.m#L1671
> - stable: https://github.com/monal-im/Monal/blob/stable/Monal/Classes/MLCall.m#L1604

### Code Analysis of Monal's session-terminate handler

The session-terminate handling lives inside `processIncomingSDP:` in `MLCall.m`. Here is the relevant code (identical in both stable and develop branches):

```objc
// handle session-terminate: fake jmi finish message and handle it
else if([iqNode check:@"{urn:xmpp:jingle:1}jingle<action=session-terminate>"])
{
    if(self.jmiProceed == nil)
    {
        DDLogDebug(@"Got jingle session-terminate after jmi proceed, faking incoming jmi:finish for Conversations compatibility...");
        // --> fakes a <finish> JMI stanza
        XMPPMessage* jmiNode = ...;
        [jmiNode addChildNode:[[MLXMLNode alloc] initWithElement:@"finish" ...]];
        [self.voipProcessor handleIncomingJMIStanza:jmiNode onAccount:self.account];
    }
    else
    {
        DDLogDebug(@"Got jingle session-terminate before even receiving jmi proceed, faking incoming jmi:reject for unknown-client compatibility...");
        // --> fakes a <reject> JMI stanza
        XMPPMessage* jmiNode = ...;
        [jmiNode addChildNode:[[MLXMLNode alloc] initWithElement:@"reject" ...]];
        [self.voipProcessor handleIncomingJMIStanza:jmiNode onAccount:self.account];
    }
    return;
}
```

### Bug: The condition is inverted

The `if/else` branches are **swapped relative to the log messages and intended behavior**:

| Condition | Log message says | Actually means | Action taken | Correct action |
|-----------|-----------------|----------------|-------------|----------------|
| `jmiProceed == nil` | "after jmi proceed" | Proceed was **NOT** received | Fakes `<finish>` | Should fake `<reject>` |
| `jmiProceed != nil` | "before even receiving jmi proceed" | Proceed **WAS** received | Fakes `<reject>` | Should fake `<finish>` |

**The log messages describe the correct intended logic, but the condition is backwards.**

### How this causes the observed behavior

For a **normal established call** (the standard case reported in this issue):

1. Call is set up via JMI: propose -> proceed -> session-initiate -> session-accept -> connected
2. At this point: `self.jmiProceed != nil` (it was set when the proceed was sent/received)
3. Remote party (DinoX/Dino) hangs up -> sends `session-terminate` with `<success/>`
4. Monal receives it in `processIncomingSDP:`, matches the SID
5. **Because `jmiProceed != nil`, Monal enters the `else` branch**
6. Monal fakes a `<reject>` JMI stanza instead of a `<finish>`
7. The JMI handler (`handleIncomingJMIStanza`) likely ignores the `<reject>` because the call is already past the ringing phase and fully connected
8. **Result: The session-terminate has no effect**
9. No IQ result is sent back to the caller (XEP-0166 violation)
10. WebRTC eventually detects the RTP stream stopped (~8 seconds)
11. ICE state changes to disconnected/failed
12. `delayedEnd:2.0` fires -> `end` with `isConnected = NO` + `wasConnectedOnce = YES` -> `MLCallFinishReasonConnectivityError`
13. Monal sends its own `session-terminate` with `<connectivity-error/>`
14. User sees "Call ended: connection failed" instead of a clean hangup

### Additional issue: No IQ result acknowledgment

The session-terminate handler does `return;` without ever sending an IQ result (`initAsResponseTo:iqNode`). Per XEP-0166 Section 6.7, the receiver MUST acknowledge `session-terminate` with an IQ result:

> Upon receiving the session-terminate, the other party MUST acknowledge it by returning an IQ result.

### The fix

The condition should be:

```objc
if(self.jmiProceed != nil)   // <-- was: == nil
{
    // Call was established via JMI -> fake <finish>
    ...
}
else
{
    // No JMI proceed -> call was set up without JMI (e.g. direct Jingle) -> fake <reject>
    ...
}
```

And an IQ result should be sent before returning:
```objc
[self.account send:[[XMPPIQ alloc] initAsResponseTo:iqNode]];
```

---

## Evidence Summary

| Step | What happens | Who is responsible |
|------|-------------|-------------------|
| 1 | DinoX sends valid `session-terminate` with `<success/>` | DinoX (correct) |
| 2 | Monal receives it but enters wrong branch (fakes `<reject>` instead of `<finish>`) | **Monal bug** |
| 3 | JMI handler ignores the reject for an already-connected call | **Monal bug** |
| 4 | No IQ result sent back | **Monal bug (XEP-0166 violation)** |
| 5 | ~8s later Monal detects RTP timeout, sends its own terminate | Monal (consequence of bug) |
| 6 | DinoX replies `unknown-session` (session already cleaned up) | DinoX (correct) |
| 7 | Monal shows "connection failed" instead of clean hangup | Monal (wrong UX) |

---

## XEP-0166 Compliance Reference

From **XEP-0166 Section 6.7** (Session Terminate):

> In order to terminate a session, the terminating party MUST send a `session-terminate` action to the other party. Upon receiving the `session-terminate`, the other party MUST acknowledge it by returning an IQ result and SHOULD terminate all resources associated with the session.

DinoX complies fully:
- Sends `session-terminate` with `<success/>` reason on user hangup
- Processes incoming `session-terminate` synchronously and immediately
- Sends IQ result acknowledgment
- Cleans up all session state and content streams
- Returns `unknown-session` for stanzas targeting already-terminated sessions

---

## Conclusion

This is a **Monal bug** caused by an **inverted condition** in `MLCall.m` `processIncomingSDP:`. The code that tmolitor-stud-tu linked as proof of implementation is exactly the code that contains the bug. The `if(self.jmiProceed == nil)` check is backwards, causing all established JMI calls to fake a `<reject>` instead of a `<finish>` when a `session-terminate` is received, which effectively makes the session-terminate a no-op for connected calls.
