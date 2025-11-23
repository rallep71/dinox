# MUC Improvement Plan (XEP-0045)

This plan outlines the steps to bring Dino's Multi-User Chat (MUC) capabilities closer to feature parity with clients like Gajim, focusing on Administration and Usability.

## Phase 1: Invitations (Easy Win)
**Goal:** Allow users to invite contacts to the current MUC easily.

1.  **UI Entry Point**:
    *   Add an "Invite Contact" item to the Conversation Menu (top-right menu in the chat window).
    *   Alternatively/Additionally: Add an "Invite" button in the Conversation Details > Members section.
2.  **Selection Dialog**:
    *   Reuse or adapt `SelectContactDialog` to allow selecting multiple contacts from the roster.
3.  **Backend Implementation**:
    *   Connect the dialog result to `MucManager.invite()`.
    *   Ensure both Direct Invitations (XEP-0249) and Mediated Invitations (XEP-0045) are handled (Dino likely handles this, but we need to verify).

## Phase 2: Room Administration (Affiliations & Banning)
**Goal:** Allow Owners/Admins to manage the room's access lists (Bans, Members, Admins).

1.  **Backend Support**:
    *   Extend `MucManager` and `Xep.Muc.Module` to support querying and modifying affiliation lists (`admin` use cases in XEP-0045).
    *   Need methods like `get_affiliations(room, affiliation)` and `modify_affiliation(room, jid, affiliation)`.
2.  **UI - Administration Panel**:
    *   Add an "Administration" button in the Conversation Details (visible only if the user is Owner/Admin).
    *   Create a new Dialog/View `MucAdminDialog`.
3.  **UI - List Management**:
    *   Tabs or a Dropdown to switch between lists: **Owners**, **Admins**, **Members**, **Outcasts (Banned)**.
    *   Display the list of JIDs for the selected category.
    *   **Add Button**: Type a JID to add to the list (e.g., to ban someone).
    *   **Remove Button**: Remove a JID from the list (e.g., unban).

## Phase 3: Room Destruction
**Goal:** Allow Owners to permanently destroy a room.

1.  **UI**:
    *   Add a "Destroy Room" button in the Conversation Details (likely at the bottom, in red).
    *   **Crucial**: A confirmation dialog explaining this is irreversible.
2.  **Backend**:
    *   Implement `destroy_room` in `MucManager`.
    *   Handle the `destroy` element in the `muc#owner` namespace.

## Phase 4: Enhanced Status Feedback (Completed)
**Goal:** Provide clear feedback in the chat when administrative actions occur.

1.  **Status Codes**:
    *   ✓ Ensure `MucManager` emits signals for specific status codes (e.g., 301 for Ban, 307 for Kick, 321 for Affiliation Change).
2.  **Chat View**:
    *   ✓ Catch these signals and insert "System Messages" into the chat stream.
    *   ✓ Example: "User X has been banned by Admin Y: [Reason]".

---

## Execution Order
We will proceed in order: **Phase 1 -> Phase 2 -> Phase 3 -> Phase 4 (All Completed)**.
