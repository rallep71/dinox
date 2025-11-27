# XEP Implementation Audit - DinoX vs Dino

**Date**: November 27, 2025  
**DinoX Version**: 0.6.5.4  
**Dino Wiki**: https://github.com/dino/dino/wiki/Supported-XEPs (Last updated: Mar 18, 2023)

## Purpose

Cross-reference Dino's claimed XEP support with actual DinoX implementation to identify:
1. Features claimed but not fully implemented
2. Features implemented but not documented
3. Discrepancies between backend and UI implementation

---

## Summary

| Category | Finding |
|----------|---------|
| **Total Dino Claims** | ~55 XEPs |
| **DinoX Documented** | 60+ XEPs |
| **Verified Discrepancies** | 5+ |
| **Missing Documentation** | 3+ |

---

## Critical Discrepancies

### 1. XEP-0249 (Direct MUC Invitations)

**Dino Wiki Claims**:
- Status: `partial`
- Note: "No support for sending"
- Since: v0.3

**DinoX Reality**:
- Status: **MISSING FROM DOCS**
- Backend: EXISTS (xmpp-vala/src/module/xep/0249_direct_muc_invitations.vala)
- UI Sending: **IMPLEMENTED** (main/src/ui/occupant_menu/view.vala line 269)
- UI Receiving: **IMPLEMENTED** (conversation notifications)

**Verdict**: Dino wiki is OUTDATED (from 2023). DinoX HAS sending support!

**Action**: Add XEP-0249 to XEP_SUPPORT.md as [DONE] with full UI

---

### 2. XEP-0444 (Message Reactions)

**Dino Wiki Claims**:
- Status: `complete`
- Since: v0.4

**DinoX Docs Claim**:
- Status: [DONE] Backend + UI
- Note: "Emoji reactions with picker"

**DinoX Reality**:
- Backend: EXISTS (libdino/src/service/reactions.vala)
- UI: EXISTS (main/src/ui/conversation_content_view/item_actions.vala line 78-90)
- Action: "Add reaction" button with emoji picker

**Verdict**: CORRECTLY DOCUMENTED

**But**: DEVELOPMENT_PLAN.md line 250 lists "Emoji Reactions" as [TODO]!

**Action**: Remove from Phase 10 TODO list - already implemented!

---

### 3. XEP-0461 (Message Replies)

**Dino Wiki Claims**:
- Status: `complete`
- Since: v0.4

**DinoX Docs Claim**:
- Status: [DONE] Backend + UI
- Note: "Quote/reply shown in messages"

**DinoX Reality**:
- Backend: EXISTS (libdino/src/service/replies.vala)
- UI: EXISTS (quote.ui, reply rendering)

**Verdict**: CORRECTLY DOCUMENTED

---

### 4. XEP-0424 (Message Retraction) & XEP-0425 (Message Moderation)

**Dino Wiki**:
- NOT LISTED (as of Mar 2023)

**DinoX Docs** (before recent fix):
- XEP-0424: Backend only, no UI
- XEP-0425: Backend only, no UI

**DinoX Reality** (verified Nov 27, 2025):
- XEP-0424: FULL UI ("Delete for everyone" button)
- XEP-0425: FULL UI ("Moderate message" for MUC moderators)

**Verdict**: DinoX has EXTENDED beyond upstream Dino!

**Action**: FIXED - Documentation updated Nov 27, 2025

---

### 5. XEP-0272 (Multiparty Jingle / MUJI)

**Dino Wiki Claims**:
- Status: `partial`
- Since: v0.3

**DinoX Docs Claim**:
- Status: [DONE] Backend + UI (Phase 1)
- Note: "Group calls with UI"

**DinoX Reality**:
- Backend: EXISTS (enhanced)
- UI: Phase 1 COMPLETE (v0.6.5.3)
- UI: Join button, participant grid, audio controls

**Verdict**: DinoX has SIGNIFICANTLY EXTENDED beyond Dino

**Action**: Documentation correct, but needs testing warning

---

### 6. XEP-0191 (Blocking Command)

**Dino Wiki Claims**:
- Status: `complete`
- Since: v0.1

**DinoX Docs Claim**:
- Status: [DONE] Backend + UI
- Note: "NEW: Block/Unblock in Contacts UI"

**DinoX Reality**:
- Backend: EXISTS (inherited from Dino)
- UI: **ENHANCED** - DinoX added Contacts page UI (v0.6.2)

**Verdict**: DinoX has IMPROVED beyond Dino

**Action**: Documentation correct

---

## Missing from Dino Wiki

These XEPs are implemented in DinoX but not listed in Dino's wiki:

1. **XEP-0424** - Message Retraction (DinoX only)
2. **XEP-0425** - Message Moderation (DinoX only)
3. **XEP-0428** - Fallback Indication (Dino has it, wiki missing)

---

## Missing from DinoX Docs

These XEPs are in Dino wiki but not in XEP_SUPPORT.md:

1. **XEP-0249** - Direct MUC Invitations (EXISTS, not documented)
2. **XEP-0298** - Delivering Conference Information to Jingle Participants (Coin)
3. **XEP-0391** - Jingle Encrypted Transports
4. **XEP-0396** - Jingle Encrypted Transports - OMEMO
5. **XEP-0454** - OMEMO Media sharing (partial)

---

## Dino Wiki XEPs to Verify

Need to check if these are truly implemented in DinoX:

| XEP | Title | Dino Status | Verify in DinoX |
|-----|-------|-------------|-----------------|
| 0047 | In-Band Bytestreams | complete | Check file transfers |
| 0048 | Bookmarks | deprecated | Check if migrated to 0402 |
| 0059 | Result Set Management | partial | Check MAM usage |
| 0082 | XMPP Date and Time Profiles | complete | Check timestamp handling |
| 0163 | Personal Eventing Protocol | complete | Check PubSub usage |
| 0177 | Jingle Raw UDP Transport | complete | Check call fallback |
| 0222 | Persistent Storage of Public Data | complete | Check bookmarks |
| 0223 | Persistent Storage of Private Data | complete | Check settings |
| 0293 | Jingle RTP Feedback Negotiation | partial | Check call quality |
| 0338 | Jingle Grouping Framework | partial | Check MUJI |
| 0339 | Source-Specific Media Attributes | partial | Check MUJI |
| 0391 | Jingle Encrypted Transports | partial | Check encrypted calls |
| 0392 | Consistent Color Generation | complete | Check contact colors |
| 0393 | Message Styling | partial | Check markdown support |
| 0398 | User Avatar to vCard Conversion | complete | Check avatar sync |

---

## Recommendations

1. **Update XEP_SUPPORT.md**:
   - Add XEP-0249 (Direct MUC Invitations)
   - Add XEP-0298, 0391, 0396, 0454 from Dino
   - Verify and add missing Jingle-related XEPs

2. **Fix DEVELOPMENT_PLAN.md**:
   - Remove XEP-0444 (Emoji Reactions) from Phase 10 TODO
   - Mark as completed feature

3. **Create Verification Tasks**:
   - Test all "partial" XEPs from Dino wiki
   - Document actual limitations
   - Update status based on testing

4. **Upstream Comparison**:
   - Track Dino's development (they may have added XEPs since Mar 2023)
   - Check if Dino wiki needs update
   - Consider contributing fixes upstream

---

## Next Steps

1. Run full XEP verification against code
2. Test each claimed feature in running app
3. Update all three docs: XEP_SUPPORT.md, XEP_UI_ANALYSIS.md, DEVELOPMENT_PLAN.md
4. Create issues for any truly missing features
