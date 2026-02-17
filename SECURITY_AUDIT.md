# Security Audit

**Date:** February 17, 2026  
**Scope:** 39 crypto-related files (OMEMO v1/v2, Signal Protocol, SASL, file transfer, GCrypt wrapper)  
**Findings:** 6 Critical/High, 11 Medium  
**Status:** All fixed  
**Website:** [dinox.handwerker.jetzt/security-audit.html](https://dinox.handwerker.jetzt/security-audit.html)

---

## Summary

A comprehensive security audit was performed on all cryptographic code in DinoX.
All critical and medium-severity issues have been fixed in commits
[`08c895f6`](https://github.com/rallep71/dinox/commit/08c895f6) (critical) and
[`83fa5046`](https://github.com/rallep71/dinox/commit/83fa5046) (medium).

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
