# Security Audit

**Date:** February 17, 2026  
**Scope:** 39 crypto-related files (OMEMO v1/v2, Signal Protocol, SASL, file transfer, GCrypt wrapper)  
**Findings:** 6 Critical/High, 11 Medium, 3 Low  
**Status:** All fixed  
**Website:** [dinox.handwerker.jetzt/security-audit.html](https://dinox.handwerker.jetzt/security-audit.html)

---

## Summary

A comprehensive security audit was performed on all cryptographic code in DinoX.
All critical, medium, and low-severity issues have been fixed in commits
[`08c895f6`](https://github.com/rallep71/dinox/commit/08c895f6) (critical),
[`83fa5046`](https://github.com/rallep71/dinox/commit/83fa5046) (medium), and
[`525115d9`](https://github.com/rallep71/dinox/commit/525115d9) (low).

---

## About helper.c

The file `plugins/omemo/src/native/helper.c` provides GCrypt-based cryptographic callbacks
(HMAC-SHA256, SHA-512, AES encrypt/decrypt, random) registered as the Signal Protocol crypto
provider for libomemo-c (formerly libsignal-protocol-c).

**This file originates from the original Dino project**, authored by **Marvin W** (core Dino
developer) on March 11, 2017, as `plugins/signal-protocol/src/signal_helper.c`. It has been
renamed twice:

- 2023: `plugins/omemo/src/signal/signal_helper.c`
- 2025: `plugins/omemo/src/native/helper.c`

The file is written in C because libomemo-c requires a `signal_crypto_provider` struct with
C function pointers. This is standard practice -- every XMPP client using libsignal has
equivalent glue code.

**Note:** Several critical bugs found in this file (#1, #2, #6 below) are also present in
the [original upstream Dino codebase](https://github.com/dino/dino) and have not been fixed
there as of the audit date. These bugs have existed since 2017.

---

## Critical & High Severity (Fixed)

| # | Severity | File | Issue |
|---|----------|------|-------|
| 1 | **CRITICAL** | `helper.c:159` | **Heap corruption:** `free(md)` called on `gcry_md_read()` internal pointer. `gcry_md_read()` returns a pointer to an internal buffer that must not be freed. *Also in upstream Dino.* |
| 2 | **CRITICAL** | `helper.c:86-89` | **Resource leak:** Missing `gcry_mac_close()` before `free()` when `gcry_mac_setkey()` fails. GCrypt internal state leaked. *Also in upstream Dino.* |
| 3 | **CRITICAL** | `helper.c:343-345` | **Incomplete PKCS#5 padding validation.** Only the last byte checked. Fixed with constant-time XOR-accumulator verifying all padding bytes. |
| 4 | **HIGH** | `simple_iks.vala:33-36` | **Timing attack:** Non-constant-time identity key comparison with early return. Fixed with XOR-OR accumulator. |
| 5 | **HIGH** | `sasl.vala:110-113` | **Timing attack:** Non-constant-time SCRAM-SHA-1 server signature verification. Fixed with XOR-OR accumulator. |
| 6 | **HIGH** | `helper.c:128` | **Type mismatch:** `sizeof(gcry_mac_hd_t)` instead of `sizeof(gcry_md_hd_t)` in SHA-512 digest init. *Also in upstream Dino.* |

---

## Medium Severity (Fixed)

| # | File | Issue |
|---|------|-------|
| 7 | `file_decryptor.vala` | **Empty cipher URI defaulted to unauthenticated GCM.** Unknown/empty ESFS cipher strings now rejected. |
| 8 | `decrypt.vala` | **Loose key length validation.** Accepted any key >= 32 bytes. Now enforces exactly 16 or 32 bytes per OMEMO spec. |
| 9 | `encrypt.vala` | **Key material not zeroized (OMEMO v1).** AES key and IV remained in heap. Now zeroed with `Memory.set()`. |
| 10 | `encrypt_v2.vala` | **Key material not zeroized (OMEMO v2).** Message key, HKDF output, enc_key, auth_key now zeroed after use. |
| 11 | `helper.c` (HKDF) | **HKDF intermediate keys not zeroized.** Stack-allocated `prk` and `t_prev` now cleared on all exit paths via `goto cleanup`. |
| 12 | `helper.c` (omemo2 CBC) | **Non-constant-time PKCS#7 padding check** in OMEMO v2 decrypt. Early-exit loop replaced with constant-time XOR-accumulator. |
| 13 | `cipher.vala` | **ECB mode available in cipher API.** ECB provides no semantic security. Now logs a warning when requested. |
| 14 | `sasl.vala` | **PLAIN auth sent without TLS check.** Cleartext password could be sent unencrypted. Now refuses PLAIN auth without TLS. |
| 15 | `sasl.vala` | **No minimum PBKDF2 iteration count.** Malicious server could specify 1 iteration. Now enforces minimum 4096 per RFC 5802. |
| 16 | `file_decryptor.vala` | **GCM without auth tag verification.** ESFS GCM used tag length 0 for Kaidan/QXmpp interop. Now logs a warning. |
| 17 | `decrypt.vala` | **Incomplete session finalization.** `TODO` comment clarified: Signal sessions auto-transition after pre-key decryption. |

---

## Low Severity (Fixed)

| # | File | Issue |
|---|------|-------|
| 18 | `helper.c` (omemo2 CBC decrypt) | **Decrypted plaintext not zeroized before free.** After copying the unpadded result, the full decrypted buffer (including padding) was freed with `g_free()` without clearing. Now `memset(decrypted, 0, ciphertext_len)` on all exit paths. |
| 19 | `helper.c` (omemo2 HMAC) | **Full HMAC not zeroized on stack.** `omemo2_hmac_sha256()` computed a full 32-byte MAC into a stack buffer, copied the truncated result, but did not clear the full MAC before return. Now `memset(full_mac, 0, sizeof(full_mac))` after truncation. |
| 20 | `sce.vala` (SCE rpad) | **Random padding used Mersenne Twister.** `generate_rpad()` used `GLib.Random` (MT19937) which is not a CSPRNG. An attacker recovering the MT state could predict padding lengths, leaking minor traffic analysis information. Now uses `/dev/urandom` directly, with GLib.Random as fallback. |

---

## OMEMO v2 Implementation Security

DinoX is one of the first desktop XMPP clients to implement **OMEMO v2** (XEP-0384 v0.8+)
alongside the legacy OMEMO protocol (v0.3.x). The implementation was developed and debugged
through interoperability testing with **Kaidan** (which uses the QXmpp library), as well as
Conversations and Monocles for legacy OMEMO backward compatibility.

### Crypto Architecture

OMEMO v2 uses a fundamentally different encryption scheme than legacy OMEMO:

| Aspect | Legacy OMEMO | OMEMO v2 |
|--------|-------------|----------|
| Payload cipher | AES-128-GCM (16-byte key, 12-byte IV) | AES-256-CBC + HMAC-SHA-256 via HKDF |
| Key derivation | Direct key use | HKDF-SHA-256 (salt=256 zero-bits, info=`"OMEMO Payload"`) producing 80 bytes |
| Per-device key material | 32 bytes (key + GCM auth tag) | 48 bytes (32-byte key + 16-byte HMAC) |
| Content wrapping | Plaintext body | SCE envelope (XEP-0420) with random padding |
| Wire format | DJB-serialized keys (0x05 prefix) | Bare X25519/Ed25519 keys |
| Protobuf format | WhisperMessage / PreKeyWhisperMessage | OMEMOMessage / OMEMOAuthenticatedMessage / OMEMOKeyExchange |
| Identity key format | Curve25519 (Montgomery) | Ed25519 (with Montgomery conversion for DH) |

All OMEMO v2 cryptographic primitives were implemented in `helper.c` using libgcrypt:
`omemo2_hkdf_sha256()`, `omemo2_aes_256_cbc_pkcs7_encrypt/decrypt()`, `omemo2_hmac_sha256()`.

### Kaidan Interoperability: Issues Found and Fixed

The following interop issues were discovered and resolved during testing with Kaidan:

**1. Ed25519 Identity Key Decoding** (`bundle_v2.vala`, commit `620b0e24`)

OMEMO v2 bundles carry the identity key in **Ed25519 format** (via `ec_public_key_get_ed()`),
not Montgomery/X25519. Initially DinoX decoded the identity key with `decode_public_key_mont()`,
which silently produced wrong key material. Sessions appeared to establish but messages were
undecryptable. Fixed by switching to `decode_public_key()` which correctly handles the
Ed25519-to-Montgomery conversion for ECDH while preserving Ed25519 data for XEdDSA signature
verification.

**2. OMEMO v1/v2 Session Conflict** (`manager.vala`, commit `40bcb7db`)

Both protocol versions share the same libomemo-c session store. When a v2 bundle arrived first,
it created a `builder.version = 4` session. The v1 encryptor then used this v4 session without
setting `cipher.version`, producing messages with a broken version byte that receivers rejected
as `SG_ERR_LEGACY_MESSAGE`. Fixed by:
- Preventing v2 session creation for JIDs that have v1 devices
- Replacing existing v4 sessions with v3 in v1 `start_session()`
- Using v2 encryptor only when all recipients have v2 devices
- Adding `SG_ERR_LEGACY_MESSAGE` to session repair triggers

**3. v2 Device List Wiping v1 Devices** (`manager.vala`, `database.vala`)

The v1 device list handler used destructive `insert_device_list()` which deactivates all devices
before re-inserting the active ones. When applied to an empty v2 device list (from a v1-only
client like Conversations), all devices were deactivated and `get_trusted_devices()` returned
empty. Fixed with an additive `insert_device_list_additive()` that only adds or reactivates
devices, never deactivates. The v2 handler uses this exclusively.

**4. GCM Auth Tag Mismatch for File Transfers** (`file_sender.vala`, `file_decryptor.vala`)

ESFS file transfers (OMEMO v2) use `aes-256-gcm-nopadding:0` with no GCM auth tag in the
ciphertext stream. Legacy `aesgcm://` transfers append a 16-byte GCM auth tag. Both paths
shared the same upload code, causing Kaidan to report "checksum mismatch" and Monocles to fail
decryption. Fixed with an `esfs_mode` flag controlling `tag_len` (0 for ESFS, 16 for legacy)
and an ESFS JID registry for cross-plugin communication.

**5. HTTP 413 on ESFS File Uploads** (`file_sender.vala`)

The upload slot was always requested with `file_size + 16` for the GCM tag, but ESFS uploads
had `tag_len = 0`. The server rejected the Content-Length mismatch with HTTP 413. Fixed by
checking the ESFS JID registry before requesting the slot.

**6. Bundle Retry for Broken Bundles** (`manager.vala`, commit `cc0abe1b`)

Kaidan sometimes publishes bundles with empty `<ik/>` elements (no identity key content). These
broken bundles were silently accepted, creating devices with `identity_key = null` that blocked
all encryption. Fixed with a retry mechanism (up to 5 attempts, 10-minute intervals) and by
marking devices with broken bundles as "lost" so messages still flow to other devices.

**7. Undecryptable Message Storage** (`decrypt.vala`, `decrypt_v2.vala`, commit `65530687`)

When OMEMO decryption fails (missing session, ratchet mismatch), the sender's fallback body
`[This message is OMEMO encrypted]` was stored as a normal plaintext message, creating ghost
messages that could never be decrypted. Fixed by clearing `message.body` when an OMEMO element
is present but decryption fails, allowing the message filter to drop it.

**8. Session Auto-Repair** (`decrypt.vala`, `decrypt_v2.vala`, commit `de3de171`)

`SG_ERR_INVALID_MESSAGE` errors (ratchet desync) caused permanent message loss. Fixed with
automatic session repair: broken session is deleted and the peer's bundle is re-fetched to
establish a new session. A per-device HashSet guard prevents thrashing (one repair per device
per runtime).

### OMEMO v2 Security Hardening (from this audit)

During the February 2026 audit, the following OMEMO v2-specific issues were addressed:

- **Key zeroization** (#10): Message key, HKDF output, encryption key, and auth key in
  `encrypt_v2.vala` are now explicitly zeroed after use
- **HKDF intermediate key zeroization** (#11): `prk` and `t_prev` in `helper.c` HKDF
  implementation cleared on all exit paths
- **Constant-time PKCS#7 validation** (#12): Padding check in `omemo2_aes_256_cbc_pkcs7_decrypt()`
  replaced with constant-time XOR-accumulator to prevent padding oracle attacks
- **Strict key length validation** (#8): Decryptor rejects key material that is not exactly
  16 or 32 bytes
- **Unknown cipher rejection** (#7): ESFS file transfers with empty or unrecognized cipher URIs
  are now rejected instead of silently defaulting to unauthenticated GCM
- **CBC decrypt buffer zeroization** (#18): Decrypted plaintext buffer in
  `omemo2_aes_256_cbc_pkcs7_decrypt()` now zeroized before `g_free()` on all exit paths
- **HMAC stack buffer zeroization** (#19): Full 32-byte MAC in `omemo2_hmac_sha256()` cleared
  after truncation to prevent stack recovery
- **SCE rpad CSPRNG** (#20): Random padding generation in `sce.vala` now uses `/dev/urandom`
  instead of Mersenne Twister to prevent padding length prediction

### Dual-Protocol Design

DinoX runs both OMEMO v1 and v2 simultaneously with shared infrastructure:
- Same identity key pair and device ID for both protocols
- Same libomemo-c session store (`builder.version = 4` for v2 sessions)
- Separate PEP nodes for device lists and bundles
- Automatic protocol selection: v2 when all recipients support it, v1 otherwise
- Trust is per identity key, independent of protocol version

### Testing Matrix

| Test | Protocol | Tested Against | Result |
|------|----------|---------------|--------|
| Text send/receive | OMEMO v2 | Kaidan | Pass |
| File send/receive (ESFS/SFS) | OMEMO v2 | Kaidan | Pass |
| Text send/receive | OMEMO v1 | Monocles/Conversations | Pass |
| File send/receive (aesgcm://) | OMEMO v1 | Monocles | Pass |
| Simultaneous v1+v2 operation | Both | Mixed | Pass |
| Device list coexistence | Both | Mixed | Pass |
| MUC OMEMO (v1+v2 version selection) | Both | Mixed | Pass |

---

## Known Limitations (Not Fixed)

| Item | Risk | Rationale |
|------|------|-----------|
| SCRAM-SHA-1-PLUS channel binding | Medium | Requires extracting TLS binding data from GnuTLS. Major clients (Conversations, Monal, Gajim) support this. Planned for future release. |
| SCRAM-SHA-256 support | Medium | Only SCRAM-SHA-1 currently implemented. Low incremental effort once channel binding is added. |
| SCRAM nonce uses GLib.Random | Low | Mersenne Twister seeded from `/dev/urandom`. Not a CSPRNG, but SCRAM nonce only needs replay prevention. Not practically exploitable. |

---

## SCRAM Channel Binding: Client Comparison

| Client | SCRAM-SHA-1 | SCRAM-SHA-1-PLUS | SCRAM-SHA-256 |
|--------|-------------|------------------|---------------|
| Conversations | Yes | Yes | Yes |
| Monal | Yes | Yes | Yes |
| Gajim | Yes | Yes | Yes |
| Profanity | Yes | Yes | Partial |
| Siskin IM | Yes | Yes | Yes |
| **DinoX** | **Yes** | **No (planned)** | **No (planned)** |
| Dino (original) | Yes | No | No |
| Kaidan | Yes | Limited | Yes |
| Pidgin / Swift / Psi | Yes | No | No |

---

## Upstream Dino Bugs

The following bugs exist in the [original Dino codebase](https://github.com/dino/dino)
in `plugins/omemo/src/native/helper.c` (formerly `signal_helper.c`) since 2017:

- **#1** -- `free(md)` after `gcry_md_read()`: heap corruption (internal pointer freed)
- **#2** -- Missing `gcry_mac_close()` on `gcry_mac_setkey()` failure path
- **#6** -- `sizeof(gcry_mac_hd_t)` vs `sizeof(gcry_md_hd_t)` type mismatch in SHA-512 init

These bugs are **not introduced by DinoX**. They were discovered during this audit and fixed
in DinoX but remain unfixed in upstream Dino.
