# OMEMO 2 (XEP-0384 v0.9) — Full Implementation Plan for DinoX

**Date:** 2026-02-09  
**Status:** Planning complete — ready for implementation  
**Goal:** Add OMEMO 2 support with backward compatibility to legacy OMEMO, testable against Kaidan

---

## 1. Analysis: Current OMEMO Implementation

### 1.1 Protocol Version
- Current implementation uses **legacy namespace** `eu.siacs.conversations.axolotl` (OMEMO 0.3.x / XEP-0384 v0.2)
- **NOT** `urn:xmpp:omemo:2` (XEP-0384 v0.8+)

### 1.2 Crypto Stack
- **libomemo-c** (fork of libsignal-protocol-c) with Vala bindings
- **libgcrypt** for AES-GCM, HMAC-SHA-256, SHA-512, CSPRNG, Curve25519, XEdDSA, HKDF
- Custom cipher constant `SG_CIPHER_AES_GCM_NOPADDING = 1000`

### 1.3 PEP Nodes
- Device list: `eu.siacs.conversations.axolotl.devicelist`
- Bundles: `eu.siacs.conversations.axolotl.bundles:<device_id>` (one node per device)

### 1.4 Database
- **omemo.db** (encrypted), Version 5
- Tables: `identity`, `identity_meta`, `trust`, `session`, `signed_pre_key`, `pre_key`, `content_item_meta`
- Trust levels: VERIFIED(0), TRUSTED(1), UNTRUSTED(2), UNKNOWN(3)
- 100 pre-keys published, max 5 own devices

### 1.5 Key Files

#### xmpp-vala Abstract Layer
- `xmpp-vala/src/module/xep/0384_omemo/omemo_encryptor.vala` — Abstract `OmemoEncryptor`, `EncryptionData` class (builds `<encrypted>` XML), `EncryptionResult`, `EncryptState`
- `xmpp-vala/src/module/xep/0384_omemo/omemo_decryptor.vala` — Abstract `OmemoDecryptor`, `ParsedData` class, `parse_node()` for legacy XML

#### Plugin Protocol Layer
- `plugins/omemo/src/protocol/stream_module.vala` — PEP handling, bundle publish/fetch, device list management
- `plugins/omemo/src/protocol/bundle.vala` — Bundle XML parser (legacy format: `<signedPreKeyPublic>`, `<identityKey>`, etc.)
- `plugins/omemo/src/protocol/message_flag.vala` — Message flag marker

#### Plugin Logic Layer
- `plugins/omemo/src/logic/encrypt.vala` — `OmemoEncryptor`: AES-128-GCM with 16-byte key + 12-byte IV. For each trusted device: `SessionCipher.encrypt(keytag)` where keytag = key(16) || auth_tag(16) = 32 bytes. Builds `<encrypted>` XML.
- `plugins/omemo/src/logic/decrypt.vala` — `OmemoDecryptor`: Parses `<encrypted>`, finds `<key rid=our_id>`, `SessionCipher.decrypt_pre_key_message()` or `decrypt_message()`, AES-128-GCM decrypts payload.
- `plugins/omemo/src/logic/manager.vala` — Message state machine, device management
- `plugins/omemo/src/logic/database.vala` — Database schema/migration
- `plugins/omemo/src/logic/trust_manager.vala` — Trust management, blind trust, identity key pinning

#### Native Bridge
- `plugins/omemo/src/native/context.vala` — NativeContext wrapper for libomemo-c
- `plugins/omemo/src/native/store.vala` — SessionBuilder/SessionCipher creation
- `plugins/omemo/src/native/helper.c/h` — libgcrypt crypto provider (AES-GCM/CBC/CTR, HMAC-SHA-256, SHA-512, CSPRNG)

### 1.6 libomemo-c VAPI Key Finding

The `plugins/omemo/vapi/libomemo-c.vapi` contains `_omemo` variant functions:
- `ec_public_key_serialize_omemo()` — Bare X25519 key **without** 0x05 type prefix byte
- `pre_key_signal_message_deserialize_omemo()` — registration_id passed separately (not in wire format)
- `signal_message_deserialize_omemo()` — OMEMO-specific deserialization
- `session_signed_pre_key_get_signature_omemo` — OMEMO signature handling

These `_omemo` variants are **infrastructure already partially ready for OMEMO 2 wire format**.

---

## 2. Spec Differences: Legacy OMEMO vs. OMEMO 2

| Aspect | Legacy (0.3.x) | OMEMO 2 (v0.8+/v0.9) |
|---|---|---|
| **Namespace** | `eu.siacs.conversations.axolotl` | `urn:xmpp:omemo:2` |
| **Device list node** | `eu.siacs.conversations.axolotl.devicelist` | `urn:xmpp:omemo:2:devices` |
| **Bundles node** | `eu.siacs.conversations.axolotl.bundles:<device_id>` (per-device node) | `urn:xmpp:omemo:2:bundles` (single node, multi-item, `item_id=device_id`) |
| **Message XML** | `<key rid="...">`, flat list under `<header>` | `<keys jid="..."><key rid="..." kex="true/false">`, grouped by JID |
| **IV in XML** | Explicit `<iv>` child of `<header>` | No `<iv>` in XML — derived via HKDF |
| **Bundle XML elements** | `<signedPreKeyPublic>`, `<signedPreKeySignature>`, `<identityKey>`, `<preKeyPublic>` | `<spk>`, `<spks>`, `<ik>`, `<pk>` |
| **Payload encryption** | AES-128-GCM (16-byte key, 12-byte IV) | AES-256-CBC + HMAC-SHA-256 via HKDF (32-byte key, 16-byte IV, "OMEMO Payload" info) |
| **Key material per device** | 32 bytes (16-byte key + 16-byte GCM auth tag) | 48 bytes (32-byte key + 16-byte HMAC) |
| **Content wrapping** | Direct `<body>` text as plaintext input | SCE envelope: `<envelope xmlns="urn:xmpp:sce:1">` (XEP-0420) |
| **Double Ratchet HKDF info** | Signal defaults ("WhisperRatchet", etc.) | "OMEMO Root Chain", "OMEMO Message Key Material", "OMEMO X3DH" |
| **Protobuf wire format** | WhisperMessage, PreKeyWhisperMessage | OMEMOMessage, OMEMOAuthenticatedMessage, OMEMOKeyExchange |
| **Key serialization** | With 0x05 type prefix byte | Bare X25519 keys (no prefix) — `_omemo` variants in libomemo-c |
| **DR inner encryption** | AES-CBC-256 + HMAC-SHA-256 (same as OMEMO 2) | AES-256-CBC + HMAC-SHA-256 with specific HKDF info strings |
| **Empty messages** | 0-byte key+tag | 32 zero-bytes encrypted with DR |
| **Heartbeat** | Not specified | MUST send heartbeat on counter ≥ 53 |
| **`<store>` hint** | Not required | MUST include `<store xmlns="urn:xmpp:hints"/>` |

---

## 3. XEP-0420 SCE (Stanza Content Encryption)

OMEMO 2 uses SCE to wrap message content before encryption:

```xml
<envelope xmlns='urn:xmpp:sce:1'>
  <content>
    <body xmlns='jabber:client'>Hello World!</body>
    <!-- other encrypted extension elements -->
  </content>
  <rpad>RANDOM_PADDING_0_TO_200_CHARS</rpad>
  <from jid='romeo@montague.lit'/>
  <!-- <to jid='...' /> MUST be present for MUC messages -->
</envelope>
```

### OMEMO 2 SCE Profile Requirements:
- **MUST** contain `<rpad/>` (random padding, 0-200 random chars)
- **MAY** contain `<time stamp="..."/>` (anti-replay)
- **SHOULD** contain `<from jid="..."/>` (anti-spoofing)
- **MUST** contain `<to jid="..."/>` in group chats (anti-redirect)
- Body element **MUST** have `xmlns='jabber:client'`

---

## 4. OMEMO 2 Message XML Structure

### 4.1 Encrypted Message

```xml
<message to='juliet@capulet.lit' from='romeo@montague.lit' id='send1'>
  <encrypted xmlns='urn:xmpp:omemo:2'>
    <header sid='27183'>
      <keys jid='juliet@capulet.lit'>
        <key rid='31415'>b64/encoded/data</key>
      </keys>
      <keys jid='romeo@montague.lit'>
        <key rid='1337'>b64/encoded/data</key>
        <key kex='true' rid='12321'>b64/encoded/data</key>
      </keys>
    </header>
    <payload>base64/encoded/encrypted/sce/envelope</payload>
  </encrypted>
  <store xmlns='urn:xmpp:hints'/>
</message>
```

### 4.2 Device List

```xml
<devices xmlns='urn:xmpp:omemo:2'>
  <device id='12345' />
  <device id='4223' label='Gajim on Ubuntu Linux' labelsig='b64/data' />
</devices>
```

PEP node: `urn:xmpp:omemo:2:devices`, access model: `open`

### 4.3 Bundle

```xml
<bundle xmlns='urn:xmpp:omemo:2'>
  <spk id='0'>b64/signed_pre_key</spk>
  <spks>b64/signature</spks>
  <ik>b64/identity_key</ik>
  <prekeys>
    <pk id='0'>b64/pre_key</pk>
    <pk id='1'>b64/pre_key</pk>
    <!-- ... up to 100 -->
    <pk id='99'>b64/pre_key</pk>
  </prekeys>
</bundle>
```

PEP node: `urn:xmpp:omemo:2:bundles`, item_id = device_id, `pubsub#max_items=max`, access model: `open`

---

## 5. OMEMO 2 Encryption Algorithm

### 5.1 Message Encryption (Payload)
1. Generate 32 bytes cryptographically secure random → `key`
2. HKDF-SHA-256: input=`key`, salt=256 zero-bits, info=`"OMEMO Payload"` → 80 bytes
3. Split: 32-byte `enc_key` + 32-byte `auth_key` + 16-byte `IV`
4. AES-256-CBC with PKCS#7 padding: encrypt SCE envelope XML → `ciphertext`
5. HMAC-SHA-256(`auth_key`, `ciphertext`) → truncate to 16 bytes → `hmac`
6. For each device: Double Ratchet encrypt(`key` || `hmac` = 48 bytes) → per-device key element

### 5.2 Message Decryption (Payload)
1. Double Ratchet decrypt → `key` (32) || `hmac` (16)
2. HKDF-SHA-256: input=`key`, salt=256 zero-bits, info=`"OMEMO Payload"` → 80 bytes
3. Split: 32-byte `enc_key` + 32-byte `auth_key` + 16-byte `IV`
4. Verify HMAC-SHA-256(`auth_key`, `ciphertext`) == `hmac`
5. AES-256-CBC decrypt with PKCS#7 unpadding → SCE envelope XML
6. Parse SCE envelope → extract `<body>` from `<content>`

### 5.3 Double Ratchet Inner Encryption (per-device key)
1. From message key `mk`: HKDF-SHA-256, input=`mk`, salt=256 zero-bits, info=`"OMEMO Message Key Material"` → 80 bytes
2. Split: 32-byte `enc_key` + 32-byte `auth_key` + 16-byte `IV`
3. AES-256-CBC with PKCS#7: encrypt the 48-byte key||hmac → `ciphertext`
4. Build `OMEMOMessage.proto` (without ciphertext), serialize
5. `CONCAT(ad, OMEMOMessage)` = associated_data || serialized_proto
6. Add ciphertext to proto, re-serialize
7. HMAC-SHA-256(`auth_key`, ad || serialized_proto) → truncate to 16 bytes
8. Pack into `OMEMOAuthenticatedMessage.proto` (mac + message)
9. If key exchange: wrap in `OMEMOKeyExchange.proto`

### 5.4 Protobuf Schemas
```protobuf
message OMEMOMessage {
    required uint32 n          = 1;  // message number
    required uint32 pn         = 2;  // previous chain length
    required bytes  dh_pub     = 3;  // ratchet public key
    optional bytes  ciphertext = 4;
}

message OMEMOAuthenticatedMessage {
    required bytes mac     = 1;       // truncated HMAC
    required bytes message = 2;       // serialized OMEMOMessage
}

message OMEMOKeyExchange {
    required uint32 pk_id  = 1;       // pre key id
    required uint32 spk_id = 2;       // signed pre key id
    required bytes  ik     = 3;       // identity key (Ed25519 form)
    required bytes  ek     = 4;       // ephemeral key
    required OMEMOAuthenticatedMessage message = 5;
}
```

---

## 6. Architecture: Dual-Protocol Support

```
┌─────────────────────────────────────────┐
│              DinoX UI                    │
│  (Encryption.OMEMO / Encryption.OMEMO2) │
├────────────┬────────────────────────────┤
│  Legacy    │       OMEMO 2              │
│  Encryptor │   Omemo2Encryptor          │
│  Decryptor │   Omemo2Decryptor          │
├────────────┤────────────────────────────┤
│            │  SCE Envelope Layer         │
│            │  (XEP-0420)                │
├────────────┴────────────────────────────┤
│        Shared Signal Protocol Layer      │
│  (libomemo-c: sessions, ratchet, keys)  │
│  (Shared Store, same identity key pair)  │
├──────────────────────────────────────────┤
│     Shared OMEMO Database (omemo.db)     │
│  + protocol_version column (0=legacy,    │
│    2=omemo2)                             │
└──────────────────────────────────────────┘
```

### Key Design Decisions:
1. **Same identity key pair** shared between legacy and OMEMO 2 (same device)
2. **Same device ID** for both protocols
3. **Separate PEP nodes** (publish to both legacy and OMEMO 2 nodes)
4. **Separate sessions in DB** possible (protocol version flag differentiates)
5. **Receive both** — decrypt messages from either protocol
6. **Send preference** — use OMEMO 2 when peer supports it, fall back to legacy
7. **Dual publish** — device list and bundles published to both namespaces

---

## 7. Critical Technical Challenge: Double Ratchet Parameters

### Problem
libomemo-c uses Signal Protocol's HKDF info strings internally:
- `"WhisperRatchet"` for root chain
- `"WhisperMessageKeys"` for message keys

OMEMO 2 spec mandates:
- `"OMEMO Root Chain"` for root chain (KDF_RK)
- `"OMEMO Message Key Material"` for message keys (ENCRYPT)
- `"OMEMO X3DH"` for X3DH key exchange

### Impact
If Kaidan's QXmpp uses the spec-correct strings and libomemo-c uses Signal's strings, sessions will **NOT interoperate** because HKDF outputs will differ.

### Solution Strategy
1. **Phase 1:** Test with libomemo-c as-is. Many OMEMO 2 implementations pragmatically use Signal defaults for compatibility.
2. **If interop fails:** Check what QXmpp actually uses and adapt:
   - Option A: Modify libomemo-c's `ratchet.c` to accept configurable HKDF info strings
   - Option B: Add compile-time flag for OMEMO 2 parameters
   - Option C: Wrap the crypto provider to intercept HKDF calls

### Existing Infrastructure
The `_omemo` serialization variants in libomemo-c already handle the wire format differences:
- Bare keys without type prefix
- Separated registration_id
- These are ready for OMEMO 2 protobuf format

---

## 8. Kaidan Implementation Analysis

Kaidan uses **QXmpp** library which provides `QXmppOmemoManager`:
- Enum: `Encryption::Omemo2 = QXmpp::Omemo2` (from `Encryption.h`)
- Controller: `OmemoController` wraps `QXmppOmemoManager`
- Database: `OmemoDb` with tables like `omemoDevicesOwn` (id, label, privateKey, publicKey, latestSignedPreKeyId, latestPreKeyId)
- QXmpp handles the full OMEMO 2 protocol internally — DinoX needs to produce compatible XML and crypto output

---

## 9. File-by-File Implementation Plan

### 9.1 xmpp-vala Layer (New Files)

#### a) `xmpp-vala/src/module/xep/0384_omemo/omemo2_encryptor.vala` (NEW)
- Namespace constants: `NS_URI_V2`, `NODE_DEVICELIST_V2`, `NODE_BUNDLES_V2`
- `Omemo2EncryptionData` class with OMEMO 2 XML structure:
  - `<keys jid="...">` grouping with `add_device_key(jid, device_id, key, is_kex)`
  - `kex` attribute on `<key>`
  - No `<iv>` in header
  - `<payload>` for encrypted SCE envelope
- `get_encrypted_node()` building OMEMO 2 XML

#### b) `xmpp-vala/src/module/xep/0384_omemo/omemo2_decryptor.vala` (NEW)
- `parse_node_v2()` for OMEMO 2 XML structure
- Parse `<keys jid="...">` groups, `kex` attribute
- New `ParsedDataV2` with JID-grouped key map

#### c) `xmpp-vala/src/module/xep/0420_sce/sce.vala` (NEW)
- SCE envelope builder: body → `<envelope>` XML
- SCE envelope parser: `<envelope>` → extracted content elements
- Affix element handling (rpad, from, to, time)

#### d) `xmpp-vala/meson.build` (MODIFY)
- Add new source files to build

### 9.2 OMEMO Plugin — Crypto Primitives

#### a) `plugins/omemo/src/native/helper.c` (MODIFY)
- Add `omemo_hkdf_sha256()` — HKDF-SHA-256 using libgcrypt
- Add `omemo_aes_cbc_encrypt()` — AES-256-CBC with PKCS#7 padding
- Add `omemo_aes_cbc_decrypt()` — AES-256-CBC with PKCS#7 unpadding
- Add `omemo_hmac_sha256()` — HMAC-SHA-256 with optional truncation

#### b) `plugins/omemo/src/native/helper.h` (MODIFY)
- Declare new function signatures

#### c) `plugins/omemo/vapi/` or inline Vala wrappers (NEW/MODIFY)
- Vala bindings for new crypto functions

### 9.3 OMEMO Plugin — Protocol Layer

#### a) `plugins/omemo/src/protocol/bundle_v2.vala` (NEW)
- `BundleV2` class for OMEMO 2 bundle XML:
  - `<spk id="...">` → signed pre key
  - `<spks>` → signature
  - `<ik>` → identity key
  - `<prekeys><pk id="...">` → pre keys

#### b) `plugins/omemo/src/protocol/stream_module_v2.vala` (NEW)
- `StreamModuleV2` for OMEMO 2 PEP:
  - Subscribe to `urn:xmpp:omemo:2:devices`
  - Parse/publish OMEMO 2 device list
  - Fetch bundles from `urn:xmpp:omemo:2:bundles` (single multi-item node)
  - Publish bundles in OMEMO 2 format
  - Configure `pubsub#max_items=max`

### 9.4 OMEMO Plugin — Logic Layer

#### a) `plugins/omemo/src/logic/encrypt_v2.vala` (NEW)
- `Omemo2Encryptor`:
  - SCE envelope wrapping
  - 32-byte key generation
  - HKDF → enc_key + auth_key + IV
  - AES-256-CBC encryption
  - HMAC-SHA-256 computation
  - key||hmac per device via Double Ratchet
  - OMEMO 2 XML with `<keys jid>` grouping

#### b) `plugins/omemo/src/logic/decrypt_v2.vala` (NEW)
- `Omemo2Decryptor`:
  - OMEMO 2 XML parsing (find `<keys jid=ourjid>`, `<key rid=our_device_id>`)
  - Double Ratchet decrypt → key||hmac
  - HKDF → verify HMAC → AES-256-CBC decrypt
  - SCE envelope parsing → body extraction

#### c) `plugins/omemo/src/logic/omemo2_crypto.vala` (NEW)
- High-level Vala wrappers:
  - `omemo2_encrypt_payload(plaintext, sender_jid)` → ciphertext + key + hmac
  - `omemo2_decrypt_payload(ciphertext, key, hmac)` → plaintext
  - `build_sce_envelope(body, sender_jid, recipient_jid?)` → envelope XML string
  - `parse_sce_envelope(envelope_xml)` → body string

### 9.5 Database

#### `plugins/omemo/src/logic/database.vala` (MODIFY)
- Bump version to 6
- Add `protocol_version` column to `identity_meta` or session tables
- Migration: existing rows default to `protocol_version=0` (legacy)
- Possible: separate table for OMEMO 2 session metadata

### 9.6 Plugin Integration

#### `plugins/omemo/src/plugin.vala` (MODIFY)
- Register both legacy and OMEMO 2 encryptors/decryptors
- Handle dual PEP node subscriptions
- Support `Encryption.OMEMO2` alongside `Encryption.OMEMO`

#### `plugins/omemo/meson.build` (MODIFY)
- Add all new source files

### 9.7 UI Changes

#### libdino entity layer (MODIFY)
- Add `Encryption.OMEMO2` enum value

#### main/src/ui/ (MODIFY)
- Add OMEMO 2 as encryption option
- Show "(OMEMO 2)" label when active
- Device details: show protocol version

---

## 10. Implementation Order

| Step | Description | Files | Risk |
|------|------------|-------|------|
| 1 | Add crypto primitives (HKDF, AES-256-CBC, HMAC) | helper.c/h + Vala wrappers | Low |
| 2 | Add SCE envelope builder/parser | sce.vala | Low |
| 3 | Add OMEMO 2 XML builders/parsers (xmpp-vala) | omemo2_encryptor.vala, omemo2_decryptor.vala | Low |
| 4 | Add OMEMO 2 bundle parser | bundle_v2.vala | Low |
| 5 | Add OMEMO 2 stream module (PEP) | stream_module_v2.vala | Medium |
| 6 | Add OMEMO 2 encryption logic | encrypt_v2.vala, omemo2_crypto.vala | Medium |
| 7 | Add OMEMO 2 decryption logic | decrypt_v2.vala | Medium |
| 8 | Database migration | database.vala | Low |
| 9 | Plugin integration + UI | plugin.vala + UI files | Medium |
| 10 | **Build + test against Kaidan** | — | **High** |
| 11 | Fix Double Ratchet params if needed | libomemo-c modification | High |
| 12 | Backward compat testing | — | Medium |

---

## 11. Backward Compatibility Strategy

1. **Receiving:** DinoX subscribes to BOTH `eu.siacs.conversations.axolotl.devicelist` AND `urn:xmpp:omemo:2:devices`. It can decrypt messages in either format by checking the namespace of the `<encrypted>` element.

2. **Sending:** Default to OMEMO 2 when the peer has an OMEMO 2 device list. Fall back to legacy if peer only has legacy devices. If peer has both, prefer OMEMO 2.

3. **Publishing:** Publish own device to BOTH device list nodes. Publish bundles in BOTH formats (legacy per-device nodes + OMEMO 2 multi-item node).

4. **Sessions:** The same Signal Protocol session can potentially be used for both protocols (the Double Ratchet is protocol-agnostic; only the outer XML and payload encryption differ). However, if HKDF info strings differ, separate sessions are needed.

5. **Trust:** Same trust model applies — trust is per identity key, independent of protocol version.

---

## 12. Testing Plan

1. **Unit test:** Encrypt/decrypt with OMEMO 2 format locally (round-trip)
2. **Self-test:** Send OMEMO 2 message between two DinoX accounts
3. **Kaidan interop:** Send OMEMO 2 message DinoX → Kaidan and Kaidan → DinoX
4. **Legacy compat:** Verify legacy OMEMO still works with Conversations/Gajim after changes
5. **Mixed mode:** Test conversation with one OMEMO 2 device and one legacy device simultaneously
6. **MUC test:** OMEMO 2 in group chats with `<to jid>` affix
7. **Edge cases:** Empty OMEMO messages (session management), heartbeat messages, key exchange completion

---

## 13. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| HKDF info string mismatch with QXmpp | Sessions won't interoperate | Test early, patch libomemo-c if needed |
| Protobuf format differences | Key exchange fails | Use `_omemo` variants in libomemo-c |
| SCE parsing issues | Messages garbled | Test with known-good SCE samples |
| PEP multi-item bundle node | Server may not support `max_items=max` | Graceful fallback, test with ejabberd/prosody |
| Database migration breaks existing sessions | Loss of encrypted history | Non-destructive migration, add columns only |
| Performance impact of dual-protocol | Slower message processing | Lazy initialization, check namespace first |

---

## Appendix A: OMEMO 2 Protobuf vs. Signal Protobuf

**Signal (legacy):**
```
PreKeyWhisperMessage: version(1) + registration_id(4) + pre_key_id + signed_pre_key_id + base_key + identity_key + WhisperMessage
WhisperMessage: version(1) + ratchet_key + counter + previous_counter + ciphertext + MAC(8)
```

**OMEMO 2:**
```
OMEMOKeyExchange: pk_id + spk_id + ik + ek + OMEMOAuthenticatedMessage
OMEMOAuthenticatedMessage: mac(16) + OMEMOMessage
OMEMOMessage: n + pn + dh_pub + ciphertext
```

Key differences:
- No version byte in OMEMO 2
- No registration_id in wire format (passed separately via `_omemo` functions)
- MAC truncated to 16 bytes (not 8)
- Identity key in Ed25519 form (not Curve25519)
- No key type prefix byte on public keys

---

## Appendix B: Required libgcrypt Operations

```c
// HKDF-SHA-256
gcry_kdf_derive(ikm, ikm_len, GCRY_KDF_HKDF, GCRY_MAC_HMAC_SHA256, salt, salt_len, info, info_len, okm, okm_len);
// Note: gcry_kdf_derive with GCRY_KDF_HKDF may not be available in older libgcrypt.
// Alternative: manual HKDF implementation using HMAC-SHA-256

// AES-256-CBC
gcry_cipher_open(&handle, GCRY_CIPHER_AES256, GCRY_CIPHER_MODE_CBC, 0);
gcry_cipher_setkey(handle, key, 32);
gcry_cipher_setiv(handle, iv, 16);
gcry_cipher_encrypt(handle, out, out_len, in, in_len);

// HMAC-SHA-256
gcry_mac_open(&handle, GCRY_MAC_HMAC_SHA256, 0, NULL);
gcry_mac_setkey(handle, key, 32);
gcry_mac_write(handle, data, data_len);
gcry_mac_read(handle, mac, &mac_len);

// PKCS#7 padding (manual)
pad_len = 16 - (plaintext_len % 16);
memset(padded + plaintext_len, pad_len, pad_len);
```
