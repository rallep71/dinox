# OMEMO 2 (XEP-0384 v0.9) -- Implementation Documentation for DinoX

**Date:** 2026-02-09 (Plan) / 2026-02-10 (Implementation complete)  
**Status:** IMPLEMENTED AND TESTED -- Dual OMEMO v1 + OMEMO v2 running simultaneously  
**Goal:** Add OMEMO 2 support with backward compatibility to legacy OMEMO, testable against Kaidan

---

## 0. Implementation Status Summary

### Confirmed Working (2026-02-10)

| Feature | Protocol | Tested Against | Status |
|---------|----------|---------------|--------|
| Text messages send | OMEMO v1 | Monocles/Conversations | OK |
| Text messages receive | OMEMO v1 | Monocles/Conversations | OK |
| Text messages send | OMEMO v2 | Kaidan | OK |
| Text messages receive | OMEMO v2 | Kaidan | OK |
| File transfer send (aesgcm://) | OMEMO v1 | Monocles | OK |
| File transfer receive (aesgcm://) | OMEMO v1 | Monocles | OK |
| File transfer send (ESFS/SFS) | OMEMO v2 | Kaidan | OK |
| File transfer receive (ESFS/SFS) | OMEMO v2 | Kaidan | OK |
| Device management UI | Both | -- | OK |
| Dual device list handling | Both | -- | OK |
| Dual bundle publish | Both | -- | OK |

### Key Challenges Solved

1. **v2 device list wiping v1 devices** -- Empty v2 list (from v1-only clients) caused destructive `insert_device_list()` to deactivate all devices. Fixed with additive insert for v2.
2. **GCM tag mismatch** -- ESFS (no tag) vs aesgcm:// (16-byte tag) broke file transfers. Fixed with `esfs_mode` flag and ESFS JID registry.
3. **HTTP 413 slot size mismatch** -- Slot requested with +16 but ESFS upload had no tag. Fixed by setting `esfs_mode` in `prepare_send_file()` before slot request.
4. **Double Ratchet HKDF info strings** -- libomemo-c uses Signal defaults; QXmpp/Kaidan also uses Signal defaults. No modification needed (pragmatic compatibility).
5. **Key format interop** -- v2 uses bare X25519/Ed25519 keys; libomemo-c `_omemo` variants handle this. Used `get_mont()`/`get_ed()` for correct serialization.

---

## 1. Analysis: Current OMEMO Implementation

### 1.1 Protocol Version
- Current implementation uses **legacy namespace** `eu.siacs.conversations.axolotl` (OMEMO 0.3.x / XEP-0384 v0.2)
- Additionally now `urn:xmpp:omemo:2` (XEP-0384 v0.8+)

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
- `xmpp-vala/src/module/xep/0384_omemo/omemo_encryptor.vala` -- Abstract `OmemoEncryptor`, `EncryptionData` class (builds `<encrypted>` XML), `EncryptionResult`, `EncryptState`
- `xmpp-vala/src/module/xep/0384_omemo/omemo_decryptor.vala` -- Abstract `OmemoDecryptor`, `ParsedData` class, `parse_node()` for legacy XML

#### Plugin Protocol Layer
- `plugins/omemo/src/protocol/stream_module.vala` -- PEP handling, bundle publish/fetch, device list management
- `plugins/omemo/src/protocol/bundle.vala` -- Bundle XML parser (legacy format: `<signedPreKeyPublic>`, `<identityKey>`, etc.)
- `plugins/omemo/src/protocol/message_flag.vala` -- Message flag marker

#### Plugin Logic Layer
- `plugins/omemo/src/logic/encrypt.vala` -- `OmemoEncryptor`: AES-128-GCM with 16-byte key + 12-byte IV. For each trusted device: `SessionCipher.encrypt(keytag)` where keytag = key(16) || auth_tag(16) = 32 bytes. Builds `<encrypted>` XML.
- `plugins/omemo/src/logic/decrypt.vala` -- `OmemoDecryptor`: Parses `<encrypted>`, finds `<key rid=our_id>`, `SessionCipher.decrypt_pre_key_message()` or `decrypt_message()`, AES-128-GCM decrypts payload.
- `plugins/omemo/src/logic/manager.vala` -- Message state machine, device management
- `plugins/omemo/src/logic/database.vala` -- Database schema/migration
- `plugins/omemo/src/logic/trust_manager.vala` -- Trust management, blind trust, identity key pinning

#### Native Bridge
- `plugins/omemo/src/native/context.vala` -- NativeContext wrapper for libomemo-c
- `plugins/omemo/src/native/store.vala` -- SessionBuilder/SessionCipher creation
- `plugins/omemo/src/native/helper.c/h` -- libgcrypt crypto provider (AES-GCM/CBC/CTR, HMAC-SHA-256, SHA-512, CSPRNG)

### 1.6 libomemo-c VAPI Key Finding

The `plugins/omemo/vapi/libomemo-c.vapi` contains `_omemo` variant functions:
- `ec_public_key_serialize_omemo()` -- Bare X25519 key **without** 0x05 type prefix byte
- `pre_key_signal_message_deserialize_omemo()` -- registration_id passed separately (not in wire format)
- `signal_message_deserialize_omemo()` -- OMEMO-specific deserialization
- `session_signed_pre_key_get_signature_omemo` -- OMEMO signature handling

These `_omemo` variants are infrastructure used for OMEMO 2 wire format.

---

## 2. Spec Differences: Legacy OMEMO vs. OMEMO 2

| Aspect | Legacy (0.3.x) | OMEMO 2 (v0.8+/v0.9) |
|---|---|---|
| **Namespace** | `eu.siacs.conversations.axolotl` | `urn:xmpp:omemo:2` |
| **Device list node** | `eu.siacs.conversations.axolotl.devicelist` | `urn:xmpp:omemo:2:devices` |
| **Bundles node** | `eu.siacs.conversations.axolotl.bundles:<device_id>` (per-device node) | `urn:xmpp:omemo:2:bundles` (single node, multi-item, `item_id=device_id`) |
| **Message XML** | `<key rid="...">`, flat list under `<header>` | `<keys jid="..."><key rid="..." kex="true/false">`, grouped by JID |
| **IV in XML** | Explicit `<iv>` child of `<header>` | No `<iv>` in XML -- derived via HKDF |
| **Bundle XML elements** | `<signedPreKeyPublic>`, `<signedPreKeySignature>`, `<identityKey>`, `<preKeyPublic>` | `<spk>`, `<spks>`, `<ik>`, `<pk>` |
| **Payload encryption** | AES-128-GCM (16-byte key, 12-byte IV) | AES-256-CBC + HMAC-SHA-256 via HKDF (32-byte key, 16-byte IV, "OMEMO Payload" info) |
| **Key material per device** | 32 bytes (16-byte key + 16-byte GCM auth tag) | 48 bytes (32-byte key + 16-byte HMAC) |
| **Content wrapping** | Direct `<body>` text as plaintext input | SCE envelope: `<envelope xmlns="urn:xmpp:sce:1">` (XEP-0420) |
| **Double Ratchet HKDF info** | Signal defaults ("WhisperRatchet", etc.) | "OMEMO Root Chain", "OMEMO Message Key Material", "OMEMO X3DH" |
| **Protobuf wire format** | WhisperMessage, PreKeyWhisperMessage | OMEMOMessage, OMEMOAuthenticatedMessage, OMEMOKeyExchange |
| **Key serialization** | With 0x05 type prefix byte | Bare X25519 keys (no prefix) -- `_omemo` variants in libomemo-c |
| **DR inner encryption** | AES-CBC-256 + HMAC-SHA-256 (same as OMEMO 2) | AES-256-CBC + HMAC-SHA-256 with specific HKDF info strings |
| **Empty messages** | 0-byte key+tag | 32 zero-bytes encrypted with DR |
| **Heartbeat** | Not specified | MUST send heartbeat on counter >= 53 |
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
1. Generate 32 bytes cryptographically secure random as `key`
2. HKDF-SHA-256: input=`key`, salt=256 zero-bits, info=`"OMEMO Payload"` producing 80 bytes
3. Split: 32-byte `enc_key` + 32-byte `auth_key` + 16-byte `IV`
4. AES-256-CBC with PKCS#7 padding: encrypt SCE envelope XML into `ciphertext`
5. HMAC-SHA-256(`auth_key`, `ciphertext`) truncated to 16 bytes as `hmac`
6. For each device: Double Ratchet encrypt(`key` || `hmac` = 48 bytes) as per-device key element

### 5.2 Message Decryption (Payload)
1. Double Ratchet decrypt yields `key` (32) || `hmac` (16)
2. HKDF-SHA-256: input=`key`, salt=256 zero-bits, info=`"OMEMO Payload"` producing 80 bytes
3. Split: 32-byte `enc_key` + 32-byte `auth_key` + 16-byte `IV`
4. Verify HMAC-SHA-256(`auth_key`, `ciphertext`) == `hmac`
5. AES-256-CBC decrypt with PKCS#7 unpadding yields SCE envelope XML
6. Parse SCE envelope, extract `<body>` from `<content>`

### 5.3 Double Ratchet Inner Encryption (per-device key)
1. From message key `mk`: HKDF-SHA-256, input=`mk`, salt=256 zero-bits, info=`"OMEMO Message Key Material"` producing 80 bytes
2. Split: 32-byte `enc_key` + 32-byte `auth_key` + 16-byte `IV`
3. AES-256-CBC with PKCS#7: encrypt the 48-byte key||hmac into `ciphertext`
4. Build `OMEMOMessage.proto` (without ciphertext), serialize
5. `CONCAT(ad, OMEMOMessage)` = associated_data || serialized_proto
6. Add ciphertext to proto, re-serialize
7. HMAC-SHA-256(`auth_key`, ad || serialized_proto) truncated to 16 bytes
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

## 6. Architecture: Dual-Protocol Support (Implemented)

```
+---------------------------------------------------------------+
|                     Manager (manager.vala)                     |
|  +------------------+          +-----------------------------+ |
|  | encryptors (v1)  |          | encryptors_v2 (v2)          | |
|  | OmemoEncryptor   |          | Omemo2Encrypt               | |
|  +--------+---------+          +-------------+--------------+  |
|           |    v2_jids.contains(recipient)?   |                |
|           +--------------+-------------------+                |
|                          v                                    |
|              on_pre_message_send()                            |
|                                                               |
|  Signal connections:                                          |
|  +----------------------+    +-----------------------------+  |
|  | StreamModule (v1)    |    | StreamModule2 (v2)          |  |
|  | device_list_loaded   |    | device_list_loaded          |  |
|  | -> on_device_list_   |    | -> v2_jids.add()            |  |
|  |    loaded()          |    | -> register_esfs_jid()      |  |
|  | [destructive DB]     |    | -> on_device_list_loaded_v2 |  |
|  |                      |    |    [additive DB]             |  |
|  | bundle_fetched       |    | bundle_fetched(Bundle2)     |  |
|  | -> on_bundle_fetched |    | -> on_bundle_v2_fetched()   |  |
|  +----------------------+    +-----------------------------+  |
+---------------------------------------------------------------+

Encryption (v2):  SCE Envelope -> HKDF -> AES-256-CBC -> HMAC -> DR encrypt(mk||tag)
Decryption (v2):  DR decrypt -> verify HMAC -> AES-256-CBC -> parse SCE -> inject nodes

File Transfer:
  FileTransfer._esfs_jids <-- Manager (v2 device list)
  HttpFileSender ------------> FileTransfer.is_esfs_jid()
                                 |
                     +-----------+------------+
                     | ESFS mode              | Legacy mode
                     | tag_len=0              | tag_len=16
                     | SFS+EncryptionData     | aesgcm:// URL
                     | inside SCE envelope    | in body
                     +------------------------+

PEP Nodes:
  v1: eu.siacs.conversations.axolotl.devicelist
      eu.siacs.conversations.axolotl.bundles:<id>  (per-device node)
  v2: urn:xmpp:omemo:2:devices
      urn:xmpp:omemo:2:bundles  (multi-item, item_id=device_id)

Key Formats:
  v1: 33-byte DJB-serialized (0x05 + 32 bytes)
  v2: IK=Ed25519(32), SPK=X25519(32), PK=X25519(32), Sig=XEdDSA(64)
```

### Design Decisions (Implemented):
1. **Same identity key pair** shared between legacy and OMEMO 2 (same device)
2. **Same device ID** for both protocols
3. **Separate PEP nodes** -- publish to both legacy and OMEMO 2 nodes
4. **Shared sessions** -- same libomemo-c session store; `builder.version = 4` for v2 sessions
5. **Receive both** -- decrypt messages from either protocol by namespace check
6. **Send preference** -- use OMEMO 2 when peer has v2 devices (`v2_jids` HashSet), fall back to legacy
7. **Dual publish** -- device list and bundles published to both namespaces
8. **Additive v2 device lists** -- v2 device list processing never deactivates existing (v1) devices

---

## 7. Critical Technical Challenge: Double Ratchet Parameters (Resolved)

### Problem
libomemo-c uses Signal Protocol's HKDF info strings internally:
- `"WhisperRatchet"` for root chain
- `"WhisperMessageKeys"` for message keys

OMEMO 2 spec mandates:
- `"OMEMO Root Chain"` for root chain (KDF_RK)
- `"OMEMO Message Key Material"` for message keys (ENCRYPT)
- `"OMEMO X3DH"` for X3DH key exchange

### Resolution
Both libomemo-c (DinoX) and QXmpp (Kaidan) use Signal's default HKDF info strings. No modification to libomemo-c was needed. Sessions interoperate correctly with `builder.version = 4` for OMEMO 2 wire format (bare keys, separated registration_id, OMEMO protobuf).

### Key Insight
The `_omemo` serialization variants in libomemo-c handle all wire format differences:
- `ec_public_key_serialize_omemo()` -- bare 32-byte keys without 0x05 prefix
- `pre_key_signal_message_deserialize_omemo()` -- registration_id passed separately
- `signal_message_deserialize_omemo()` -- OMEMO-specific deserialization
- `session_signed_pre_key_get_signature_omemo()` -- XEdDSA signature (64 bytes)

Setting `builder.version = 4` activates these variants for v2 session building.

---

## 8. Kaidan Implementation Analysis

Kaidan uses **QXmpp** library which provides `QXmppOmemoManager`:
- Enum: `Encryption::Omemo2 = QXmpp::Omemo2` (from `Encryption.h`)
- Controller: `OmemoController` wraps `QXmppOmemoManager`
- Database: `OmemoDb` with tables like `omemoDevicesOwn` (id, label, privateKey, publicKey, latestSignedPreKeyId, latestPreKeyId)
- QXmpp handles the full OMEMO 2 protocol internally -- DinoX needs to produce compatible XML and crypto output

---

## 9. Implemented Files -- Actual State

### 9.1 xmpp-vala Layer (New Files)

#### a) `xmpp-vala/src/module/xep/0384_omemo/omemo2_encryptor.vala`
- Namespace constants: `NS_URI_V2 = "urn:xmpp:omemo:2"`, `NODE_DEVICELIST_V2`, `NODE_BUNDLES_V2`
- `Omemo2EncryptionData` class: `<keys jid="...">` grouping, `kex` attribute, `<payload>` element
- `get_encrypted_node()` builds OMEMO 2 `<encrypted xmlns='urn:xmpp:omemo:2'>` XML

#### b) `xmpp-vala/src/module/xep/0384_omemo/omemo2_decryptor.vala`
- `Omemo2Decryptor` abstract class with `parse_node_v2()` 
- Parses `<keys jid="...">` groups, extracts `kex` attribute, finds our device key

#### c) `xmpp-vala/src/module/xep/0420_sce/sce.vala`
- `Envelope` class: `content_nodes`, `from_jid`, `to_jid`, `timestamp`
- `to_xml()`: serializes envelope with `<content>`, `<rpad>` (1-200 random printable chars), `<from>`, `<to>`, `<time>`
- `from_xml()`: async parser via StanzaReader
- `get_body()`: extracts `<body>` text from content nodes
- `build_message_envelope()`: convenience factory  
- Body parameter is **nullable** -- when SFS file transfer nodes are present, body is omitted from SCE content

#### d) `xmpp-vala/meson.build` -- Sources added to build

### 9.2 OMEMO Plugin -- Crypto Primitives

#### a) `plugins/omemo/src/native/helper.c`
- `omemo_hkdf_sha256(key, key_len, salt, salt_len, info, info_len, output, output_len)` -- Full HKDF-SHA-256 (extract + expand)
- `omemo_aes_256_cbc_pkcs7_encrypt(key, iv, plaintext, pt_len, ciphertext, ct_len)` -- AES-256-CBC + PKCS#7 padding
- `omemo_aes_256_cbc_pkcs7_decrypt(key, iv, ciphertext, ct_len, plaintext, pt_len)` -- AES-256-CBC + PKCS#7 unpadding
- `omemo_hmac_sha256(key, key_len, data, data_len, mac, mac_len)` -- HMAC-SHA-256 (full or truncated)
- Uses manual HKDF implementation (HMAC-based extract+expand) for libgcrypt compatibility

#### b) `plugins/omemo/src/native/helper.h` -- Function declarations added

#### c) `plugins/omemo/vapi/omemo-native.vapi` -- Vala bindings:
- `omemo2_hkdf_sha256()`, `omemo2_aes_256_cbc_pkcs7_encrypt()`, `omemo2_aes_256_cbc_pkcs7_decrypt()`, `omemo2_hmac_sha256()`

### 9.3 OMEMO Plugin -- Protocol Layer

#### a) `plugins/omemo/src/protocol/bundle_v2.vala`
- `Bundle2` class parsing OMEMO 2 bundle XML: `<spk>`, `<spks>`, `<ik>`, `<prekeys><pk>`
- Key decoding: SPK/PK via `decode_public_key_mont()` (X25519 Montgomery), IK via `decode_public_key()` (Ed25519 to Curve25519 conversion)
- Signature via `decode_signature()` (raw 64-byte XEdDSA)

#### b) `plugins/omemo/src/protocol/stream_module_v2.vala`
- `StreamModule2`: Full v2 PEP operations
- Subscribes to `urn:xmpp:omemo:2:devices`, fetches bundles from `urn:xmpp:omemo:2:bundles` (multi-item node)
- Publishes v2 device list and bundles in OMEMO 2 format
- Bundle publish uses: IK=Ed25519 (`get_ed()`), SPK=X25519 (`get_mont()`), Sig=XEdDSA (`signature_omemo()`)
- Session builder: `builder.version = 4` for OMEMO 2 wire format
- Signals: `device_list_loaded`, `bundle_fetched` (emits `Bundle2`)
- Proactive session start for v2-only devices (e.g. Kaidan)

### 9.4 OMEMO Plugin -- Logic Layer

#### a) `plugins/omemo/src/logic/encrypt_v2.vala` (245 lines)
- `Omemo2Encrypt` extends `Xep.Omemo.Omemo2Encryptor`
- Encryption algorithm:
  1. Build SCE envelope (body + SFS/OOB/fallback/receipts/chat markers/BOB nodes)
  2. Generate 32-byte message key `mk`
  3. HKDF-SHA-256(`mk`, salt=32 zeros, info="OMEMO Payload") producing 80 bytes: `enc_key[32] | auth_key[32] | iv[16]`
  4. AES-256-CBC-PKCS7(`enc_key`, `iv`, SCE plaintext) into ciphertext
  5. HMAC-SHA-256(`auth_key`, ciphertext)[0:16] as `auth_tag`
  6. Per device: DR encrypt(`mk || auth_tag` = 48 bytes)
- SCE envelope includes: body, SFS metadata, OOB data, fallback indications, receipt requests, chat markers, BOB data
- SFS aesgcm:// URLs are sanitized to https:// inside SCE
- Sets `<store xmlns='urn:xmpp:hints'/>` and explicit encryption tag

#### b) `plugins/omemo/src/logic/decrypt_v2.vala` (369 lines)
- `Omemo2Decrypt` extends `Xep.Omemo.Omemo2Decryptor`
- Decryption algorithm:
  1. Find `<key>` in `<keys jid='our_jid'>` group
  2. DR decrypt yields `mk[32] || auth_tag[16]` = 48 bytes
  3. HKDF-SHA-256 yields `enc_key[32] | auth_key[32] | iv[16]`
  4. Verify HMAC-SHA-256 (constant-time comparison)
  5. AES-256-CBC-PKCS7 decrypt yields SCE envelope XML
  6. Parse SCE envelope, inject content nodes back into stanza
- Content node injection: Decrypted SFS, OOB, fallback elements are injected back into the stanza so downstream handlers (FileProvider, etc.) can process them
- BOB data handling: `<data xmlns='urn:xmpp:bob'>` nodes from SCE are stored as `known_bobs` for thumbnail resolution via `cid:` URIs
- `Omemo2DecryptMessageListener` registered in DECRYPT action group
- Uses `cipher.version = 4` and `deserialize_omemo_pre_key_message(key, sid)`

#### c) Crypto wrappers (integrated into encrypt_v2.vala / decrypt_v2.vala)
- `omemo2_hkdf_sha256()` called directly for HKDF
- `omemo2_aes_256_cbc_pkcs7_encrypt/decrypt()` for payload encryption
- `omemo2_hmac_sha256()` for authentication
- No separate `omemo2_crypto.vala` file -- crypto is inlined in encryptor/decryptor

### 9.5 Database

#### `plugins/omemo/src/logic/database.vala`
- No version bump needed -- same schema works for both protocols
- Added `insert_device_list_additive()` method:
  - Uses `upsert()` per device -- inserts new or updates to active
  - **Never deactivates** existing devices (critical: empty v2 list won't wipe v1 devices)
  - Used exclusively by `on_device_list_loaded_v2()` handler

### 9.6 Plugin Integration

#### `plugins/omemo/src/logic/manager.vala`
- **Dual encryptor maps**: `encryptors` (v1 `OmemoEncryptor`) + `encryptors_v2` (v2 `Omemo2Encrypt`)
- **`v2_jids` HashSet**: Tracks JIDs with OMEMO 2 device lists
- **Encryption routing** in `on_pre_message_send()`: If any recipient is in `v2_jids`, use `Omemo2Encrypt`; otherwise use legacy `OmemoEncryptor`
- **Dual signal connections**:
  - v1: `StreamModule.device_list_loaded` -> `on_device_list_loaded()` (destructive DB insert)
  - v2: `StreamModule2.device_list_loaded` -> `on_device_list_loaded_v2()` (additive DB insert) + `v2_jids.add()` + `FileTransfer.register_esfs_jid()`
- **Dual bundle handling**: `on_bundle_fetched()` (v1) + `on_bundle_v2_fetched()` (v2 with `Bundle2`)
- **Proactive v2 sessions**: `on_bundle_v2_fetched()` always starts sessions for v2 devices

#### `plugins/omemo/src/plugin.vala`
- Registers both v1 and v2 modules, encryptors, decryptors
- Dual PEP subscriptions configured in `on_account_added()`

#### `plugins/omemo/meson.build` -- All new source files added

### 9.7 UI Changes

- **Single encryption mode**: `Encryption.OMEMO` is used for both v1 and v2 -- the manager auto-selects the appropriate encryptor per recipient
- **Device management**: `manage_key_dialog.vala` + `encryption_preferences_entry.vala` show all devices (v1 + v2) with "Remove device" option
- Trust management works identically for both protocols (trust is per identity key)

### 9.8 File Transfer -- Dual Mode

#### `plugins/http-files/src/file_sender.vala`
- `EncryptedHttpFileSendData`: added `bool esfs_mode = false`
- **`prepare_send_file()`**: Checks `FileTransfer.is_esfs_jid()` *before* slot request:
  - ESFS recipient -> `upload_size = file_size` (no GCM tag)
  - Legacy recipient -> `upload_size = file_size + 16` (16-byte GCM tag)
- **`upload()`**: `tag_len = esfs_mode ? 0 : 16` controls `SymmetricCipherEncrypter` tag output
- **`send_file()`**: 
  - ESFS -> builds SFS element with `EncryptionData` (key, IV, cipher `urn:xmpp:ciphers:aes-256-gcm-nopadding:0`), hooks into `build_message_stanza` to inject SFS XML, OMEMO 2 encryptor wraps it in SCE envelope
  - Legacy -> builds `aesgcm://` URL with hex-encoded IV+key in fragment, sent as message body

#### `plugins/omemo/src/file_transfer/file_decryptor.vala`
- **ESFS path**: Key/IV from SFS metadata, supports `aes-256-cbc-pkcs7` (Kaidan) and `aes-256-gcm-nopadding:0` (DinoX) ciphers, `tag_len=0`
- **Legacy path**: Key/IV from aesgcm:// URL fragment, `tag_len=16`

#### `libdino/src/entity/file_transfer.vala` -- ESFS JID Registry
```vala
private static Gee.HashSet<string> _esfs_jids = new Gee.HashSet<string>();
public static void register_esfs_jid(string jid) { _esfs_jids.add(jid); }
public static bool is_esfs_jid(string jid) { return _esfs_jids.contains(jid); }
```
- Populated by OMEMO Manager when v2 device lists arrive (in `StreamModule2.device_list_loaded` handler)
- Consumed by `HttpFileSender.prepare_send_file()` to decide GCM tag handling
- Cross-plugin communication (OMEMO plugin to http-files plugin) without direct dependency

---

## 10. Implementation Milestones (Completed)

| Step | Description | Status | Notes |
|------|------------|--------|-------|
| 1 | Crypto primitives (HKDF, AES-256-CBC, HMAC) | Done | Manual HKDF impl for libgcrypt compat |
| 2 | SCE envelope builder/parser | Done | Nullable body for SFS-only messages |
| 3 | OMEMO 2 XML builders/parsers | Done | `<keys jid>` grouping, `kex` attr |
| 4 | OMEMO 2 bundle parser | Done | Montgomery/Ed25519 key handling |
| 5 | OMEMO 2 stream module (PEP) | Done | Multi-item bundle node, dual publish |
| 6 | OMEMO 2 encryption logic | Done | Full algorithm with SCE wrapping |
| 7 | OMEMO 2 decryption logic | Done | Content node injection, BOB support |
| 8 | Database adaptation | Done | Additive insert, no schema change |
| 9 | Plugin integration + Manager | Done | Dual encryptor routing, v2_jids |
| 10 | File transfer dual mode | Done | ESFS JID registry, tag_len toggle |
| 11 | Kaidan interop testing | Done | Text + files bidirectional |
| 12 | Monocles/Conversations compat | Done | v1 text + files still work |
| 13 | Double Ratchet params | N/A | Signal defaults work with QXmpp |

---

## 11. Backward Compatibility (Verified)

1. **Receiving:** DinoX subscribes to BOTH `eu.siacs.conversations.axolotl.devicelist` AND `urn:xmpp:omemo:2:devices`. Decrypts either format by checking namespace of `<encrypted>` element.

2. **Sending:** Uses `v2_jids` HashSet -- if recipient has v2 devices, sends OMEMO 2. Falls back to legacy otherwise. Transparent to user (single "OMEMO" encryption option).

3. **Publishing:** Own device published to BOTH device list nodes. Bundles published in BOTH formats (v1 per-device nodes + v2 multi-item node).

4. **Sessions:** Same libomemo-c session store. `builder.version = 4` activates OMEMO 2 wire format (bare keys, OMEMO protobuf). Signal HKDF defaults work with QXmpp.

5. **Trust:** Same trust model for both -- trust is per identity key, independent of protocol version.

6. **Device Lists:** v1 handler uses destructive `insert_device_list()` (deactivate-then-reactivate). v2 handler uses additive `insert_device_list_additive()` (never deactivates). This prevents v2 lists from wiping v1-only devices.

7. **File Transfer:** ESFS JID registry bridges OMEMO plugin and http-files plugin. Recipients with v2 devices get ESFS (SFS+encrypted, no GCM tag). v1-only recipients get aesgcm:// (16-byte GCM tag). Both use same AES-256-GCM cipher, only tag handling differs.

---

## 12. Testing Results

| Test | Result |
|------|--------|
| DinoX to Kaidan text (OMEMO 2) | Pass |
| Kaidan to DinoX text (OMEMO 2) | Pass |
| DinoX to Kaidan file (ESFS) | Pass |
| Kaidan to DinoX file (ESFS) | Pass |
| DinoX to Monocles text (OMEMO v1) | Pass |
| Monocles to DinoX text (OMEMO v1) | Pass |
| DinoX to Monocles file (aesgcm://) | Pass |
| Monocles to DinoX file (aesgcm://) | Pass |
| Simultaneous v1+v2 operation | Pass |
| Device list coexistence (v1+v2) | Pass |

---

## 13. Resolved Risks

| Risk | Resolution |
|------|-----------|
| HKDF info string mismatch | Both use Signal defaults -- interop works |
| Protobuf format differences | `_omemo` variants + `builder.version=4` handle everything |
| SCE parsing issues | Robust parser with content node injection |
| PEP multi-item bundle node | Works with ejabberd; `request_item()` for per-device fetch |
| Database migration | No migration needed -- additive method added alongside existing |
| v2 device list wiping v1 | Additive insert prevents this |
| File transfer GCM tag mismatch | ESFS JID registry + tag_len toggle |
| HTTP slot size mismatch | `esfs_mode` set in `prepare_send_file()` before slot request |

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

## Appendix B: libgcrypt Operations (Implemented)

```c
// HKDF-SHA-256 (manual extract+expand for libgcrypt compatibility)
// Implemented in plugins/omemo/src/native/helper.c: omemo_hkdf_sha256()
// Uses HMAC-SHA-256 for both extract and expand phases

// AES-256-CBC with PKCS#7
// Implemented: omemo_aes_256_cbc_pkcs7_encrypt() / _decrypt()
gcry_cipher_open(&handle, GCRY_CIPHER_AES256, GCRY_CIPHER_MODE_CBC, 0);
gcry_cipher_setkey(handle, key, 32);
gcry_cipher_setiv(handle, iv, 16);
gcry_cipher_encrypt(handle, out, out_len, in, in_len);

// HMAC-SHA-256
// Implemented: omemo_hmac_sha256()
gcry_mac_open(&handle, GCRY_MAC_HMAC_SHA256, 0, NULL);
gcry_mac_setkey(handle, key, 32);
gcry_mac_write(handle, data, data_len);
gcry_mac_read(handle, mac, &mac_len);

// PKCS#7 padding (manual, in helper.c)
pad_len = 16 - (plaintext_len % 16);
memset(padded + plaintext_len, pad_len, pad_len);
```

---

## Appendix C: Bugs Fixed During Dual-Protocol Integration

### C.1 v2 Device List Wiping v1 Devices
- **Symptom**: OMEMO v1 messages to Monocles/Conversations failed ("your client doesn't seem to support that")
- **Root Cause**: `on_device_list_loaded()` called destructive `insert_device_list()` for BOTH v1 and v2 lists. Empty v2 device list (from v1-only client) deactivated all devices -> `get_trusted_devices()` returned empty.
- **Fix**: Separate `on_device_list_loaded_v2()` handler using additive `insert_device_list_additive()`. Empty v2 lists are ignored.

### C.2 GCM Auth Tag Mismatch (ESFS vs aesgcm://)
- **Symptom**: Kaidan showed "checksum mismatch" for files from DinoX; Monocles couldn't decrypt files
- **Root Cause**: ESFS (OMEMO 2) expects `aes-256-gcm-nopadding:0` with NO GCM auth tag. Legacy aesgcm:// expects 16-byte GCM auth tag appended. Both were sharing the same upload path.
- **Fix**: `esfs_mode` flag on `EncryptedHttpFileSendData`. `tag_len = esfs_mode ? 0 : 16` in `upload()`.

### C.3 HTTP 413 -- Upload Slot Size Mismatch
- **Symptom**: File uploads to Kaidan (ESFS) failed with HTTP 413 (payload too large)
- **Root Cause**: `prepare_send_file()` always added +16 to slot size (for GCM tag), but ESFS upload used `tag_len=0` -> server rejected Content-Length mismatch.
- **Fix**: Set `esfs_mode` in `prepare_send_file()` *before* slot request. Only add +16 for non-ESFS recipients.

### C.4 esfs_mode Timing Bug
- **Symptom**: All uploads used `esfs_mode=false` (16-byte tag) even for ESFS recipients
- **Root Cause**: `esfs_mode` was set AFTER `upload()` was called
- **Fix**: ESFS JID registry (`FileTransfer._esfs_jids`) populated by OMEMO Manager when v2 device lists arrive. `HttpFileSender` checks registry BEFORE upload.

### C.5 Content-Length / Stream Size Mismatch
- **Symptom**: "broken pipe" / "Das Netzwerk ist nicht erreichbar" during upload
- **Root Cause**: HTTP PUT Content-Length didn't include GCM auth tag bytes
- **Fix**: `upload_size += tag_len` in `upload()` method
