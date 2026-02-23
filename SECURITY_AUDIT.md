# Security Audit

| | |
|---|---|
| **Date** | February 17, 2026 (manual audit), February 23, 2026 (test suite) |
| **Scope** | 39 crypto-related files (OMEMO v1/v2, Signal Protocol, SASL, file transfer, GCrypt wrapper) + OpenPGP plugin (15 files) |
| **Findings** | 6 Critical/High, 11 Medium, 3 Low (manual audit) + 3 Medium OpenPGP + 21 bugs from automated test suite |
| **Status** | All fixed |
| **Test Suite** | [docs/internal/TESTING.md](docs/internal/TESTING.md) — 506 Meson tests + 136 standalone = 642 total, 0 failures |
| **Website** | [dinox.handwerker.jetzt/security-audit.html](https://dinox.handwerker.jetzt/security-audit.html) |

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

**This file originates from the original Dino project** (March 11, 2017), originally at
`plugins/signal-protocol/src/signal_helper.c`. It has been renamed twice:

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

## OpenPGP Implementation Security

DinoX implements **XEP-0027** (legacy PGP), **XEP-0373** (OpenPGP key distribution via PubSub),
and **XEP-0374** (OpenPGP for XMPP Instant Messaging) with automatic protocol selection.
GPG operations are serialized through a single worker thread to prevent race conditions.

### Architecture

- **GPG CLI backend** (`gpg_cli_helper.vala`, 1474 lines): All cryptographic operations
  delegate to the system `gpg` binary via subprocess, avoiding GPGME library issues on Windows.
- **Worker queue**: A single background thread serializes all GPG subprocess calls, preventing
  deadlocks and concurrent process spawning crashes.
- **App-scoped keyring**: DinoX uses its own `$STORAGE/openpgp/gnupg` directory,
  isolating from the user's global `~/.gnupg` keyring. Enables clean Panic Wipe.
- **Dual-protocol encryption**: XEP-0374 (signcrypt) used for contacts that advertise support
  via Service Discovery; XEP-0027 fallback for all other contacts.

### Audited Files (15)

| File | Purpose |
|------|---------|
| `gpg_cli_helper.vala` | GPG subprocess wrapper (encrypt, decrypt, sign, verify, key management) |
| `gpgme_fix.c` / `gpgme_fix.h` | Windows stdio fix, GPGME key ref/unref helpers |
| `stream_module.vala` | XEP-0027/0374 message encryption/decryption, presence signing |
| `manager.vala` | Encryption orchestration, key cache, auto-fetch from keyserver |
| `plugin.vala` | Plugin lifecycle, gpg-agent config, XEP-0373/0374 module registration |
| `database.vala` | Key storage (SQLite), account/contact key mapping |
| `xep0373_key_manager.vala` | XEP-0373 PubSub key publishing and retrieval |
| `file_transfer/file_encryptor.vala` | GPG file encryption for HTTP upload |
| `file_transfer/file_decryptor.vala` | GPG file decryption |
| `0373_openpgp.vala` | XEP-0373 XMPP module (PEP key distribution) |
| `0374_openpgp_content.vala` | XEP-0374 content elements (signcrypt, sign, crypt) |
| `stream_flag.vala` | Per-JID key ID storage |
| `encryption_list_entry.vala` | UI integration for encryption activation |
| `key_management_dialog.vala` | Key generation, import, export, revocation UI |
| `util.vala` | Fingerprint formatting utility |

### OpenPGP Findings (Fixed)

| # | Severity | File(s) | Issue |
|---|----------|---------|-------|
| 21 | Medium | `gpg_cli_helper.vala` (all encrypt/decrypt/sign/import functions) | **Temp files containing plaintext not securely wiped.** All GPG subprocess operations wrote sensitive data (plaintext messages, decrypted content, key material) to files in `/tmp` and deleted them with `FileUtils.remove()` (simple `unlink()`). Deleted data remains on disk until overwritten by chance. Now `secure_delete_file()` overwrites with zeros before unlinking. |
| 22 | Medium | `gpg_cli_helper.vala` + `file_encryptor.vala` | **Temp files created with permissive permissions.** `FileUtils.set_contents()` creates files with default 0644 permissions (umask-dependent), allowing other local users to read sensitive plaintext during the window between creation and deletion. Now `secure_write_file()` uses `FileCreateFlags.PRIVATE` (0600) and atomic creation (fails if file already exists, preventing TOCTOU races). |
| 23 | Low | `0374_openpgp_content.vala` (SigncryptElement, SignElement, CryptElement) | **XEP-0374 rpad uses Mersenne Twister.** `generate_random_padding()` used `GLib.Random.int_range()` (MT19937) for the random padding bytes in signcrypt/sign/crypt elements. An attacker recovering the MT state could predict padding lengths, enabling minor traffic analysis. Now uses `/dev/urandom` (CSPRNG) with GLib.Random fallback for platforms without `/dev/urandom`. Same pattern as OMEMO finding #20. |

### OpenPGP Security Properties (Verified)

| Property | Status |
|----------|--------|
| GPG subprocess serialization (worker queue) | Correct -- single thread, no races |
| App-scoped keyring isolation | Correct -- `$STORAGE/openpgp/gnupg`, 0700 permissions |
| XEP-0373 key import validation | Correct -- ASCII armor check, base64 validation, radix64 reject |
| XEP-0027 signature verification | Correct -- VALIDSIG/GOODSIG/ERRSIG parsing from GPG status |
| MDC enforcement (batch mode) | Correct -- DECRYPTION_OKAY or GOODMDC required |
| Base64url injection prevention | Correct -- `-` and `_` characters rejected before GPG calls |
| Key revocation and unpublish | Correct -- gen-revoke + import + PubSub retract |
| Sensitive debug logging | OK -- no key material leaked to debug output |

---

## Known Limitations (Not Fixed)

| Item | Risk | Rationale |
|------|------|-----------|
| ~~SCRAM-SHA-1-PLUS channel binding~~ | ~~Medium~~ | **Fixed in v1.1.0.6.** SCRAM-SHA-1-PLUS, SCRAM-SHA-256-PLUS, and SCRAM-SHA-512-PLUS implemented with `tls-exporter` (RFC 9266, GLib 2.74+) and `tls-server-end-point` (RFC 5929, GLib 2.66+) channel binding. Per-account downgrade protection toggle refuses login if server strips -PLUS mechanisms (possible MITM). DinoX is the only XMPP client supporting all six SCRAM variants. |
| ~~SCRAM-SHA-256 support~~ | ~~Medium~~ | **Fixed in v1.1.0.6.** SCRAM-SHA-256 and SCRAM-SHA-512 implemented alongside SCRAM-SHA-1. Preference order: SHA-512 > SHA-256 > SHA-1. |
| ~~SCRAM nonce uses GLib.Random~~ | ~~Low~~ | **Fixed in v1.1.0.6.** Nonce generation replaced with `/dev/urandom` CSPRNG (24 bytes, Base64-encoded). Fallback to GLib.Random on systems without `/dev/urandom`. |
| OpenPGP interactive-mode MDC check | Low | In interactive decrypt mode (pinentry), GPG status output cannot be captured, so MDC status is not verified by DinoX. Mitigated by GPG 2.2+ enforcing MDC by default. |
| Vala string zeroization | Info | Vala/GLib strings are garbage-collected, never zeroized in memory. Language limitation, not fixable without C interop. Applies to both OMEMO and OpenPGP. |

---

## SCRAM Channel Binding: Client Comparison

| Client | SCRAM-SHA-1 | SCRAM-SHA-1-PLUS | SCRAM-SHA-256 | SCRAM-SHA-256-PLUS | SCRAM-SHA-512 | SCRAM-SHA-512-PLUS |
|--------|-------------|------------------|---------------|--------------------|--------------|---------|
| Conversations | Yes | Yes | Yes | No | No | No |
| Monal | Yes | Yes | Yes | No | No | No |
| Gajim | Yes | Yes | Yes | No | No | No |
| Profanity | Yes | Yes | Partial | No | No | No |
| Siskin IM | Yes | Yes | Yes | No | No | No |
| **DinoX** | **Yes** | **Yes** | **Yes** | **Yes** | **Yes** | **Yes** |
| Dino (original) | Yes | No | No | No | No | No |
| Kaidan | Yes | Limited | Yes | No | No | No |
| Pidgin / Swift / Psi | Yes | No | No | No | No | No |

---

## Upstream Dino Bugs

The following bugs exist in the [original Dino codebase](https://github.com/dino/dino)
in `plugins/omemo/src/native/helper.c` (formerly `signal_helper.c`) since 2017:

- **#1** -- `free(md)` after `gcry_md_read()`: heap corruption (internal pointer freed)
- **#2** -- Missing `gcry_mac_close()` on `gcry_mac_setkey()` failure path
- **#6** -- `sizeof(gcry_mac_hd_t)` vs `sizeof(gcry_md_hd_t)` type mismatch in SHA-512 init

These bugs are **not introduced by DinoX**. They were discovered during this audit and fixed
in DinoX but remain unfixed in upstream Dino.

---

## Automated Test Suite -- Additional Bugs Found

After the manual audit, a comprehensive **spec-based test suite** (506 Meson tests + 136
standalone = 642 total) was built to verify all fixes and catch further defects.
The test suite found **21 additional bugs** not discovered during the manual audit.

Full test inventory, spec references, and reproduction steps:
**[docs/internal/TESTING.md](docs/internal/TESTING.md)**

### Bugs Found by Test Suite (all fixed)

| Bug | Severity | File | Test that caught it | Issue |
|-----|----------|------|---------------------|-------|
| T-1 | Medium | `jid.vala` | `RFC7622_reject_empty_string` | Empty string `""` accepted as valid JID instead of throwing `InvalidJidError` |
| T-2 | Medium | `jid.vala` | `RFC7622_reject_too_long_localpart` | Localpart > 1023 bytes accepted (RFC 7622 S3.3 limit) |
| T-3 | Low | `jid.vala` | `RFC7622_reject_at_only` | Bare `"@"` accepted as valid JID |
| T-4 | Low | `jid.vala` | `RFC7622_reject_slash_only_resource` | `"domain/"` with empty resource accepted |
| T-5 | Medium | `file_encryption.vala` | `SP800_38D_iv_is_96_bits` | GCM IV was 128 bits (16 bytes) instead of NIST-mandated 96 bits (12 bytes) |
| T-6 | High | `file_encryption.vala` | `SP800_38D_tag_is_128_bits` | GCM authentication tag truncated to 64 bits instead of full 128 bits |
| T-7 | Medium | `file_encryption.vala` | `SP800_132_salt_minimum_128_bits` | PBKDF2 salt was 64 bits (8 bytes) instead of NIST-mandated 128 bits minimum |
| T-8 | Medium | `file_encryption.vala` | `SP800_38D_unique_iv_per_encryption` | Same IV reused across multiple encryptions (GCM IV reuse = catastrophic) |
| T-9 | Low | `file_encryption.vala` | `IND_CPA_ciphertext_indistinguishable` | Identical plaintexts produced identical ciphertexts (no randomization) |
| T-10 | Medium | `stream_management.vala` | `XEP0198_h_counter_overflow_at_2_32` | h-counter overflow at 2³² not handled per XEP-0198 S5 |
| T-11 | Medium | `omemo/manager.vala` | `XEP0384_prekey_update_classifier` | PreKey update classification logic broken for edge cases |
| T-12 | Medium | `omemo/manager.vala` | `XEP0384_encrypt_safety_check` | Missing safety check before encryption allowed encrypt with 0 recipients |
| T-13 | Medium | `omemo/decrypt.vala` | `XEP0384_decrypt_failure_stages` | Decrypt failure stage tracking incorrect |
| T-14 | Low | `constant_time.vala` | `CWE208_constant_time_compare` | Timing-variant comparison in some edge cases |
| T-15 | Low | `json_escape.vala` | `RFC8259_backslash_escape` | JSON string escaping missed backslash character |
| T-16 | Low | `bot_rate_limiter.vala` | `CONTRACT_zero_window_rate_limiter` | Zero-width rate limiter window caused division by zero |
| T-17 | Medium | `stream_module.vala` | `XEP0374_extract_body_bodyguard` | `<bodyguard>` element falsely matched as `<body>` in XEP-0374 extraction |
| T-18 | Medium | `armor_parser.vala` | `XEP0027_signature_armor` | Armor parser boundary detection off-by-one |
| T-19 | Medium | `gpg_keylist_parser.vala` | `GPG_keylist_uid_field` | GPG keylist UID field parsing skipped colon-delimited fields incorrectly |
| T-20 | Medium | `stanza_node.vala` | `XML_encoded_val_decode` | `encoded_val` setter substring indices wrong: `end-start-3` was `start-end-3`, `splice(start, end)` missing `+1` |
| T-21 | Low | `0300_cryptographic_hashes.vala` | `XEP0300_hash_string_md5` | `hash_string_to_type("md5")` returned null -- missing `case "md5"` in switch |

### Test Suite Summary

| Category | Tests | Bugs Found |
|----------|-------|------------|
| XMPP Core (RFC 6120, 7622) | 67 | T-1 to T-4 |
| Crypto (NIST SP 800-38D/132, RFC 5116) | 27 | T-5 to T-9 |
| Stream Management (XEP-0198) | 15 | T-10 |
| OMEMO (XEP-0384) | 102 | T-11 to T-13 |
| Timing/JSON/Rate Limiter | 17 | T-14 to T-16 |
| OpenPGP (XEP-0027/0373/0374) | 48 | T-17 to T-19 |
| XML/Stanza (RFC 6120) | 21 | T-20 |
| Crypto Hashes (XEP-0300) | 15 | T-21 |
| UI Helpers, Data Structures, Misc | 194 | 0 |
| **Total** | **506** | **21** |
