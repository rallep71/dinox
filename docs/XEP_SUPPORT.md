#  XMPP Extension Protocol (XEP) Support

Complete list of XEPs implemented in DinoX with differentiated implementation status.

**Total XEPs**: 60+  
**Compliance**: One of the most protocol-compliant XMPP clients

---

##  Status Legend

| Icon | Status | Description |
|------|--------|-------------|
| [DONE] | **Full** | Complete backend + UI implementation |
|  | **Backend** | Protocol implemented, no/minimal UI |
| [WARNING] | **Partial** | Incomplete implementation |
| 🚧 | **Planned** | Scheduled for future release |

---

## [DONE] Core Protocol

| XEP | Title | Backend | UI | Notes |
|-----|-------|---------|----|----|
| [XEP-0004](https://xmpp.org/extensions/xep-0004.html) | Data Forms | [DONE] | [DONE] | Used in registration, MUC config |
| [XEP-0030](https://xmpp.org/extensions/xep-0030.html) | Service Discovery | [DONE] |  | Backend only, no UI needed |
| [XEP-0060](https://xmpp.org/extensions/xep-0060.html) | Publish-Subscribe (PubSub) | [DONE] |  | Backend only, used by other XEPs |
| [XEP-0077](https://xmpp.org/extensions/xep-0077.html) | In-Band Registration | [DONE] | [DONE] | Full UI in Add Account dialog |
| [XEP-0092](https://xmpp.org/extensions/xep-0092.html) | Software Version | [DONE] |  | Backend only, no UI needed |
| [XEP-0115](https://xmpp.org/extensions/xep-0115.html) | Entity Capabilities | [DONE] |  | Backend only, no UI needed |

---

## 💬 Messaging

| XEP | Title | Backend | UI | Notes |
|-----|-------|---------|----|----|
| [XEP-0085](https://xmpp.org/extensions/xep-0085.html) | Chat State Notifications | [DONE] | [DONE] | "typing..." indicator shown |
| [XEP-0184](https://xmpp.org/extensions/xep-0184.html) | Message Delivery Receipts | [DONE] | [DONE] | Checkmarks for delivery/read |
| [XEP-0191](https://xmpp.org/extensions/xep-0191.html) | Blocking Command | [DONE] | [DONE] | **NEW**: Block/Unblock in Contacts UI |
| [XEP-0199](https://xmpp.org/extensions/xep-0199.html) | XMPP Ping | [DONE] |  | Backend only, connection health |
| [XEP-0203](https://xmpp.org/extensions/xep-0203.html) | Delayed Delivery | [DONE] | [DONE] | Shows original timestamp |
| [XEP-0245](https://xmpp.org/extensions/xep-0245.html) | The /me Command | [DONE] | [DONE] | `/me` renders as action |
| [XEP-0280](https://xmpp.org/extensions/xep-0280.html) | Message Carbons | [DONE] |  | Backend sync, no UI needed |
| [XEP-0308](https://xmpp.org/extensions/xep-0308.html) | Last Message Correction | [DONE] | [DONE] | Edit button + "edited" badge |
| [XEP-0313](https://xmpp.org/extensions/xep-0313.html) | Message Archive Management (MAM) | [DONE] | [DONE] | History scroll + delete history |
| [XEP-0333](https://xmpp.org/extensions/xep-0333.html) | Chat Markers | [DONE] | [DONE] | Read receipts shown |
| [XEP-0334](https://xmpp.org/extensions/xep-0334.html) | Message Processing Hints | [DONE] |  | Backend hints, no UI |
| [XEP-0359](https://xmpp.org/extensions/xep-0359.html) | Unique and Stable Stanza IDs | [DONE] |  | Backend only, message tracking |
| [XEP-0424](https://xmpp.org/extensions/xep-0424.html) | Message Retraction | [DONE] | [DONE] | Delete button "Delete for everyone" |
| [XEP-0425](https://xmpp.org/extensions/xep-0425.html) | Message Moderation | [DONE] | [DONE] | MUC moderator "Moderate message" UI |
| [XEP-0428](https://xmpp.org/extensions/xep-0428.html) | Fallback Indication | [DONE] |  | Backend only, compatibility |
| [XEP-0444](https://xmpp.org/extensions/xep-0444.html) | Message Reactions | [DONE] | [DONE] | Emoji reactions with picker |
| [XEP-0461](https://xmpp.org/extensions/xep-0461.html) | Message Replies | [DONE] | [DONE] | Quote/reply shown in messages |

---

## 👥 Multi-User Chat (MUC)

| XEP | Title | Backend | UI | Notes |
|-----|-------|---------|----|----|
| [XEP-0045](https://xmpp.org/extensions/xep-0045.html) | Multi-User Chat | [DONE] | [DONE] | Full MUC UI with roles |
| [XEP-0048](https://xmpp.org/extensions/xep-0048.html) | Bookmarks (Legacy) | [DONE] | [DONE] | Bookmarks shown in sidebar |
| [XEP-0249](https://xmpp.org/extensions/xep-0249.html) | Direct MUC Invitations | [DONE] | [DONE] | Invite dialog + notifications |
| [XEP-0402](https://xmpp.org/extensions/xep-0402.html) | PEP Native Bookmarks | [DONE] | [DONE] | Modern bookmark storage |
| [XEP-0410](https://xmpp.org/extensions/xep-0410.html) | MUC Self-Ping | [DONE] |  | Backend only, reconnection |
| [XEP-0421](https://xmpp.org/extensions/xep-0421.html) | Anonymous occupant identifiers | [DONE] |  | Backend tracking, no UI |

---

##  File Transfer

| XEP | Title | Backend | UI | Notes |
|-----|-------|---------|----|----|
| [XEP-0066](https://xmpp.org/extensions/xep-0066.html) | Out of Band Data | [DONE] | [DONE] | Direct URL links handled |
| [XEP-0234](https://xmpp.org/extensions/xep-0234.html) | Jingle File Transfer | [DONE] | [DONE] | Drag & drop file sending |
| [XEP-0261](https://xmpp.org/extensions/xep-0261.html) | Jingle In-Band Bytestreams | [DONE] |  | Backend transport method |
| [XEP-0264](https://xmpp.org/extensions/xep-0264.html) | Jingle Content Thumbnails | [DONE] | [DONE] | Image previews shown |
| [XEP-0363](https://xmpp.org/extensions/xep-0363.html) | HTTP File Upload | [DONE] | [DONE] | Modern file sharing UI |
| [XEP-0446](https://xmpp.org/extensions/xep-0446.html) | File metadata element | [DONE] | [DONE] | File info displayed |
| [XEP-0447](https://xmpp.org/extensions/xep-0447.html) | Stateless File Sharing | [DONE] | [DONE] | Multi-source downloads |

---

## 📞 Audio/Video Calls

| XEP | Title | Backend | UI | Notes |
|-----|-------|---------|----|----|
| [XEP-0166](https://xmpp.org/extensions/xep-0166.html) | Jingle | [DONE] | [DONE] | Full call UI with controls |
| [XEP-0167](https://xmpp.org/extensions/xep-0167.html) | Jingle RTP Sessions | [DONE] | [DONE] | Audio/video streaming |
| [XEP-0176](https://xmpp.org/extensions/xep-0176.html) | Jingle ICE-UDP Transport | [DONE] |  | Backend connection handling |
| [XEP-0215](https://xmpp.org/extensions/xep-0215.html) | External Service Discovery | [DONE] |  | TURN/STUN discovery |
| [XEP-0272](https://xmpp.org/extensions/xep-0272.html) | Multiparty Jingle (Muji) | [WARNING] | [WARNING] | Backend complete, minimally tested |
| [XEP-0294](https://xmpp.org/extensions/xep-0294.html) | Jingle RTP Header Extensions | [DONE] |  | Backend media handling |
| [XEP-0320](https://xmpp.org/extensions/xep-0320.html) | Use of DTLS-SRTP in Jingle | [DONE] |  | Backend encryption |
| [XEP-0338](https://xmpp.org/extensions/xep-0338.html) | Jingle Grouping Framework | [DONE] |  | Backend media grouping |
| [XEP-0339](https://xmpp.org/extensions/xep-0339.html) | Source-Specific Media Attributes | [DONE] |  | Backend SSRC handling |
| [XEP-0353](https://xmpp.org/extensions/xep-0353.html) | Jingle Message Initiation | [DONE] | [DONE] | Call notifications shown |
| [XEP-0482](https://xmpp.org/extensions/xep-0482.html) | Call Invites | [DONE] | [DONE] | Modern call invitations |

---

##  Encryption

| XEP | Title | Backend | UI | Notes |
|-----|-------|---------|----|----|
| [XEP-0027](https://xmpp.org/extensions/xep-0027.html) | Current Jabber OpenPGP Usage | [DONE] | [DONE] | Legacy PGP via plugin |
| [XEP-0373](https://xmpp.org/extensions/xep-0373.html) | OpenPGP for XMPP | [DONE] | [DONE] | Modern PGP via plugin |
| [XEP-0374](https://xmpp.org/extensions/xep-0374.html) | OpenPGP for XMPP Instant Messaging | [DONE] | [DONE] | PGP message encryption |
| [XEP-0380](https://xmpp.org/extensions/xep-0380.html) | Explicit Message Encryption | [DONE] | [DONE] | Lock icon shows encryption |
| [XEP-0384](https://xmpp.org/extensions/xep-0384.html) | OMEMO Encryption | [DONE] | [DONE] | Full OMEMO UI + device mgmt |

---

## 🔌 Stream Management

| XEP | Title | Backend | UI | Notes |
|-----|-------|---------|----|----|
| [XEP-0198](https://xmpp.org/extensions/xep-0198.html) | Stream Management | [DONE] |  | Backend only, connection resilience |
| [XEP-0352](https://xmpp.org/extensions/xep-0352.html) | Client State Indication | [DONE] |  | Backend power management |
| [XEP-0368](https://xmpp.org/extensions/xep-0368.html) | SRV records for XMPP over TLS | [DONE] |  | Backend connection setup |

---

## 🚧 Planned / Missing UI

| XEP | Title | Backend | UI Status | Priority | Notes |
|-----|-------|---------|-----------|----------|-------|
| [XEP-0357](https://xmpp.org/extensions/xep-0357.html) | Push Notifications | [NO] | [NO] |  High | Planned for v0.8.0 |
| [XEP-0388](https://xmpp.org/extensions/xep-0388.html) | Extensible SASL (SASL2) | [NO] | [NO] |  High | Planned for v0.8.0 |
| [XEP-0386](https://xmpp.org/extensions/xep-0386.html) | Bind 2 | [NO] | [NO] |  High | Planned for v0.8.0 |
| [XEP-0449](https://xmpp.org/extensions/xep-0449.html) | Stickers | [NO] | [NO] | [TODO] Low | Planned for v0.8.0 |

---

##  Implementation Notes

### [DONE] Recently Added (DinoX Extended)
- **XEP-0191 (Blocking Command)**: Full UI in Contacts management page with block/unblock buttons
- **XEP-0424 (Message Retraction)**: Full UI with "Delete for everyone" button (own messages)
- **XEP-0425 (Message Moderation)**: Full UI with "Moderate message" button (MUC moderators)

###  Backend-Only XEPs
These are fully implemented but have no/minimal UI (by design):
- **XEP-0030, 0060, 0092, 0115**: Service discovery infrastructure
- **XEP-0199**: XMPP ping for connection health
- **XEP-0280**: Message carbons (transparent sync)
- **XEP-0334**: Message processing hints
- **XEP-0359**: Stanza IDs (backend message tracking)
- **XEP-0428**: Fallback indication (compatibility layer)
- **Stream Management**: XEP-0198, 0352, 0368

### [DONE] All Core XEPs Have UI
All messaging, MUC, file transfer, and call-related XEPs now have complete UI implementations.

---

##  Related Documentation

-  [Development Plan](../DEVELOPMENT_PLAN.md) - Roadmap and feature status
-  [XEP UI Analysis](XEP_UI_ANALYSIS.md) - Detailed implementation analysis with code snippets
-  [Architecture Guide](ARCHITECTURE.md) - Codebase structure
-  [Build Instructions](BUILD.md) - How to compile

---

**Last Updated**: November 27, 2025  
**Version**: DinoX 0.6.5.4
