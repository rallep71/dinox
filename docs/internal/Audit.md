# Security Audit - Internal Notes

**Public page:** [security-audit.html](../security-audit.html)

## helper.c Origin

The file `plugins/omemo/src/native/helper.c` originates from the **original Dino project**,
authored by **Marvin W** (core Dino developer) on 2017-03-11, as
`plugins/signal-protocol/src/signal_helper.c`. Renamed twice:

- 2023: `plugins/omemo/src/signal/signal_helper.c` (merge signal-protocol into omemo plugin)
- 2025: `plugins/omemo/src/native/helper.c` (switch from libsignal-protocol-c to libomemo-c)

**Why C instead of Vala?** libomemo-c (formerly libsignal-protocol-c) is a C library that
requires a `signal_crypto_provider` struct with C function pointers for callbacks (HMAC-SHA256,
SHA-512, AES encrypt/decrypt, random). These must be registered as real C functions, which
cannot be done directly in Vala. This is standard practice -- every XMPP client using
libsignal has equivalent glue code.

The OMEMO v2 functions (`omemo2_hkdf_sha256`, `omemo2_aes_256_cbc_pkcs7_encrypt/decrypt`)
were added in the DinoX fork.

## Bugs present in upstream Dino

The following bugs found in helper.c also exist in the original Dino codebase:
- `free(md)` after `gcry_md_read()` internal pointer (heap corruption)
- Missing `gcry_mac_close()` before `free()` on setkey failure
- `sizeof(gcry_mac_hd_t)` instead of `sizeof(gcry_md_hd_t)` in SHA-512 init

## SCRAM-SHA-1-PLUS Analysis

| Client | SCRAM-SHA-1-PLUS | SCRAM-SHA-256 |
|---|---|---|
| Conversations | Yes | Yes |
| Monal | Yes | Yes |
| Gajim | Yes | Yes |
| Profanity | Yes | Partial |
| Siskin IM | Yes | Yes |
| Dino/DinoX | No | No |
| Kaidan | Limited | Yes |
| Pidgin/Swift/Psi | No | No |

Channel binding protects against MITM attacks with forged TLS certificates (compromised CA,
state-level actors). TLS alone is sufficient for most users, but leading clients all support it.
Implementation requires extracting TLS binding data from GnuTLS
(`gnutls_session_channel_binding()`). Worth doing later, not a blocker.

## SCRAM Nonce CSPRNG

GLib.Random uses Mersenne Twister, seeded from `/dev/urandom`. Theoretically predictable
after ~624 outputs, but:
- Attacker would need to observe prior random outputs from the same process
- Even with predicted nonce, attacker still needs the password
- SCRAM security relies on PBKDF2 + HMAC, not nonce entropy
- **Not practically exploitable**

## Fix Commits

- `08c895f6` - Critical fixes (helper.c, simple_iks.vala, sasl.vala)
- `83fa5046` - Medium fixes (11 issues across 8 files)
