# 📡 XMPP Extension Protocol (XEP) Support

Complete list of XEPs implemented in DinoX with differentiated implementation status.

**Total XEPs**: 60+  
**Compliance**: One of the most protocol-compliant XMPP clients

---

## 📊 Status Legend

| Icon | Status | Description |
|------|--------|-------------|
| ✅ | **Full** | Complete backend + UI implementation |
| 🔧 | **Backend** | Protocol implemented, no/minimal UI |
| ⚠️ | **Partial** | Incomplete implementation |
| 🚧 | **Planned** | Scheduled for future release |

---

## ✅ Core Protocol

| XEP | Title | Backend | UI | Notes |
|-----|-------|---------|----|----|
| [XEP-0004](https://xmpp.org/extensions/xep-0004.html) | Data Forms | ✅ | ✅ | Used in registration, MUC config |
| [XEP-0030](https://xmpp.org/extensions/xep-0030.html) | Service Discovery | ✅ | 🔧 | Backend only, no UI needed |
| [XEP-0060](https://xmpp.org/extensions/xep-0060.html) | Publish-Subscribe (PubSub) | ✅ | 🔧 | Backend only, used by other XEPs |
| [XEP-0077](https://xmpp.org/extensions/xep-0077.html) | In-Band Registration | ✅ | ✅ | Full UI in Add Account dialog |
| [XEP-0092](https://xmpp.org/extensions/xep-0092.html) | Software Version | ✅ | 🔧 | Backend only, no UI needed |
| [XEP-0115](https://xmpp.org/extensions/xep-0115.html) | Entity Capabilities | ✅ | 🔧 | Backend only, no UI needed |

---

## 💬 Messaging

| XEP | Title | Backend | UI | Notes |
|-----|-------|---------|----|----|
| [XEP-0085](https://xmpp.org/extensions/xep-0085.html) | Chat State Notifications | ✅ | ✅ | "typing..." indicator shown |
| [XEP-0184](https://xmpp.org/extensions/xep-0184.html) | Message Delivery Receipts | ✅ | ✅ | Checkmarks for delivery/read |
| [XEP-0191](https://xmpp.org/extensions/xep-0191.html) | Blocking Command | ✅ | ✅ | **NEW**: Block/Unblock in Contacts UI |
| [XEP-0199](https://xmpp.org/extensions/xep-0199.html) | XMPP Ping | ✅ | 🔧 | Backend only, connection health |
| [XEP-0203](https://xmpp.org/extensions/xep-0203.html) | Delayed Delivery | ✅ | ✅ | Shows original timestamp |
| [XEP-0245](https://xmpp.org/extensions/xep-0245.html) | The /me Command | ✅ | ✅ | `/me` renders as action |
| [XEP-0280](https://xmpp.org/extensions/xep-0280.html) | Message Carbons | ✅ | 🔧 | Backend sync, no UI needed |
| [XEP-0308](https://xmpp.org/extensions/xep-0308.html) | Last Message Correction | ✅ | ✅ | Edit button + "edited" badge |
| [XEP-0313](https://xmpp.org/extensions/xep-0313.html) | Message Archive Management (MAM) | ✅ | ✅ | History scroll + delete history |
| [XEP-0333](https://xmpp.org/extensions/xep-0333.html) | Chat Markers | ✅ | ✅ | Read receipts shown |
| [XEP-0334](https://xmpp.org/extensions/xep-0334.html) | Message Processing Hints | ✅ | 🔧 | Backend hints, no UI |
| [XEP-0359](https://xmpp.org/extensions/xep-0359.html) | Unique and Stable Stanza IDs | ✅ | 🔧 | Backend only, message tracking |
| [XEP-0424](https://xmpp.org/extensions/xep-0424.html) | Message Retraction | ✅ | 🔧 | **Backend only**, no delete UI yet |
| [XEP-0425](https://xmpp.org/extensions/xep-0425.html) | Message Moderation | ✅ | 🔧 | **Backend only**, MUC moderator feature |
| [XEP-0428](https://xmpp.org/extensions/xep-0428.html) | Fallback Indication | ✅ | 🔧 | Backend only, compatibility |
| [XEP-0444](https://xmpp.org/extensions/xep-0444.html) | Message Reactions | ✅ | ✅ | Emoji reactions with picker |
| [XEP-0461](https://xmpp.org/extensions/xep-0461.html) | Message Replies | ✅ | ✅ | Quote/reply shown in messages |

---

## 👥 Multi-User Chat (MUC)

| XEP | Title | Backend | UI | Notes |
|-----|-------|---------|----|----|
| [XEP-0045](https://xmpp.org/extensions/xep-0045.html) | Multi-User Chat | ✅ | ✅ | Full MUC UI with roles |
| [XEP-0048](https://xmpp.org/extensions/xep-0048.html) | Bookmarks (Legacy) | ✅ | ✅ | Bookmarks shown in sidebar |
| [XEP-0249](https://xmpp.org/extensions/xep-0249.html) | Direct MUC Invitations | ✅ | ✅ | Invite dialog + notifications |
| [XEP-0402](https://xmpp.org/extensions/xep-0402.html) | PEP Native Bookmarks | ✅ | ✅ | Modern bookmark storage |
| [XEP-0410](https://xmpp.org/extensions/xep-0410.html) | MUC Self-Ping | ✅ | 🔧 | Backend only, reconnection |
| [XEP-0421](https://xmpp.org/extensions/xep-0421.html) | Anonymous occupant identifiers | ✅ | 🔧 | Backend tracking, no UI |

---

## 📁 File Transfer

| XEP | Title | Backend | UI | Notes |
|-----|-------|---------|----|----|
| [XEP-0066](https://xmpp.org/extensions/xep-0066.html) | Out of Band Data | ✅ | ✅ | Direct URL links handled |
| [XEP-0234](https://xmpp.org/extensions/xep-0234.html) | Jingle File Transfer | ✅ | ✅ | Drag & drop file sending |
| [XEP-0261](https://xmpp.org/extensions/xep-0261.html) | Jingle In-Band Bytestreams | ✅ | 🔧 | Backend transport method |
| [XEP-0264](https://xmpp.org/extensions/xep-0264.html) | Jingle Content Thumbnails | ✅ | ✅ | Image previews shown |
| [XEP-0363](https://xmpp.org/extensions/xep-0363.html) | HTTP File Upload | ✅ | ✅ | Modern file sharing UI |
| [XEP-0446](https://xmpp.org/extensions/xep-0446.html) | File metadata element | ✅ | ✅ | File info displayed |
| [XEP-0447](https://xmpp.org/extensions/xep-0447.html) | Stateless File Sharing | ✅ | ✅ | Multi-source downloads |

---

## 📞 Audio/Video Calls

| XEP | Title | Backend | UI | Notes |
|-----|-------|---------|----|----|
| [XEP-0166](https://xmpp.org/extensions/xep-0166.html) | Jingle | ✅ | ✅ | Full call UI with controls |
| [XEP-0167](https://xmpp.org/extensions/xep-0167.html) | Jingle RTP Sessions | ✅ | ✅ | Audio/video streaming |
| [XEP-0176](https://xmpp.org/extensions/xep-0176.html) | Jingle ICE-UDP Transport | ✅ | 🔧 | Backend connection handling |
| [XEP-0215](https://xmpp.org/extensions/xep-0215.html) | External Service Discovery | ✅ | 🔧 | TURN/STUN discovery |
| [XEP-0272](https://xmpp.org/extensions/xep-0272.html) | Multiparty Jingle (Muji) | ⚠️ | ⚠️ | Backend complete, minimally tested |
| [XEP-0294](https://xmpp.org/extensions/xep-0294.html) | Jingle RTP Header Extensions | ✅ | 🔧 | Backend media handling |
| [XEP-0320](https://xmpp.org/extensions/xep-0320.html) | Use of DTLS-SRTP in Jingle | ✅ | 🔧 | Backend encryption |
| [XEP-0338](https://xmpp.org/extensions/xep-0338.html) | Jingle Grouping Framework | ✅ | 🔧 | Backend media grouping |
| [XEP-0339](https://xmpp.org/extensions/xep-0339.html) | Source-Specific Media Attributes | ✅ | 🔧 | Backend SSRC handling |
| [XEP-0353](https://xmpp.org/extensions/xep-0353.html) | Jingle Message Initiation | ✅ | ✅ | Call notifications shown |
| [XEP-0482](https://xmpp.org/extensions/xep-0482.html) | Call Invites | ✅ | ✅ | Modern call invitations |

---

## 🔐 Encryption

| XEP | Title | Backend | UI | Notes |
|-----|-------|---------|----|----|
| [XEP-0027](https://xmpp.org/extensions/xep-0027.html) | Current Jabber OpenPGP Usage | ✅ | ✅ | Legacy PGP via plugin |
| [XEP-0373](https://xmpp.org/extensions/xep-0373.html) | OpenPGP for XMPP | ✅ | ✅ | Modern PGP via plugin |
| [XEP-0374](https://xmpp.org/extensions/xep-0374.html) | OpenPGP for XMPP Instant Messaging | ✅ | ✅ | PGP message encryption |
| [XEP-0380](https://xmpp.org/extensions/xep-0380.html) | Explicit Message Encryption | ✅ | ✅ | Lock icon shows encryption |
| [XEP-0384](https://xmpp.org/extensions/xep-0384.html) | OMEMO Encryption | ✅ | ✅ | Full OMEMO UI + device mgmt |

---

## 🔌 Stream Management

| XEP | Title | Backend | UI | Notes |
|-----|-------|---------|----|----|
| [XEP-0198](https://xmpp.org/extensions/xep-0198.html) | Stream Management | ✅ | 🔧 | Backend only, connection resilience |
| [XEP-0352](https://xmpp.org/extensions/xep-0352.html) | Client State Indication | ✅ | 🔧 | Backend power management |
| [XEP-0368](https://xmpp.org/extensions/xep-0368.html) | SRV records for XMPP over TLS | ✅ | 🔧 | Backend connection setup |

---

## 🚧 Planned / Missing UI

| XEP | Title | Backend | UI Status | Priority | Notes |
|-----|-------|---------|-----------|----------|-------|
| [XEP-0357](https://xmpp.org/extensions/xep-0357.html) | Push Notifications | ❌ | ❌ | 🔥 High | Planned for v0.8.0 |
| [XEP-0388](https://xmpp.org/extensions/xep-0388.html) | Extensible SASL (SASL2) | ❌ | ❌ | 🔥 High | Planned for v0.8.0 |
| [XEP-0386](https://xmpp.org/extensions/xep-0386.html) | Bind 2 | ❌ | ❌ | 🔥 High | Planned for v0.8.0 |
| [XEP-0424](https://xmpp.org/extensions/xep-0424.html) | Message Retraction | ✅ | ❌ | ⚠️ High | **Backend done**, needs delete message UI |
| [XEP-0425](https://xmpp.org/extensions/xep-0425.html) | Message Moderation | ✅ | ❌ | ⚠️ Medium | **Backend done**, MUC moderator UI needed |
| [XEP-0449](https://xmpp.org/extensions/xep-0449.html) | Stickers | ❌ | ❌ | 🟢 Low | Planned for v0.8.0 |

---

## 📝 Implementation Notes

### ✅ Recently Added (Dino Extended)
- **XEP-0191 (Blocking Command)**: Full UI in Contacts management page
- **XEP-0424 (Message Retraction)**: Backend implemented, used in delete history
- **XEP-0425 (Message Moderation)**: Backend implemented for MUC

### 🔧 Backend-Only XEPs
These are fully implemented but have no/minimal UI (by design):
- **XEP-0030, 0060, 0092, 0115**: Service discovery infrastructure
- **XEP-0199**: XMPP ping for connection health
- **XEP-0280**: Message carbons (transparent sync)
- **XEP-0334**: Message processing hints
- **XEP-0359**: Stanza IDs (backend message tracking)
- **XEP-0428**: Fallback indication (compatibility layer)
- **Stream Management**: XEP-0198, 0352, 0368

### ⚠️ Needs UI Work
- **XEP-0424**: Delete individual messages (currently only bulk delete)
- **XEP-0425**: MUC message moderation UI for moderators

---

## 📚 Related Documentation

- 📋 [Development Plan](../DEVELOPMENT_PLAN.md) - Roadmap and feature status
- 🔍 [XEP UI Analysis](XEP_UI_ANALYSIS.md) - Detailed implementation analysis with code snippets
- 🏛️ [Architecture Guide](ARCHITECTURE.md) - Codebase structure
- 🔧 [Build Instructions](BUILD.md) - How to compile

---

**Last Updated**: November 21, 2025  
**Version**: DinoX 0.6.0
