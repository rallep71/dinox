# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 0.9.9.x | Yes |
| 0.9.8.x | Security fixes only |
| < 0.9.8 | No |

## Reporting a Vulnerability

It is highly appreciated to report a vulnerability to the DinoX developers.
We kindly ask you to **not disclose it publicly** until it has been fixed.
This prevents abuse and exploitation in the current published releases.

**Do NOT open a public GitHub issue for security vulnerabilities.**

### How to Report

Please report issues directly via:

- **Email**: dinox@handwerker.jetzt
- **XMPP** (OMEMO encrypted): dinox@handwerker.jetzt

Please try to report in detail:

- What you are concerned about
- If applicable, how to reproduce the vulnerability
- Affected versions
- Potential impact
- Your contact details, if needed — so we can ask follow-up questions
- You are also invited to suggest a fix

### Response Timeline

- **Acknowledgment**: Within 48 hours
- **Initial assessment**: Within 7 days
- **Fix & disclosure**: Coordinated with reporter

Once a vulnerability has been reported and confirmed, we try our very best to provide
a fix as soon as possible, ideally within days. However, depending on the issue, it can
take longer if many code sections need to be changed. Please keep in mind that this is a
non-commercial open source project maintained by volunteers.

Thank you for considering to report a security vulnerability. This improves the quality
of DinoX significantly.

## Security Features

DinoX includes several security-hardening features:

- **End-to-end encryption**: OMEMO (Legacy + OMEMO 2) and OpenPGP (XEP-0027, XEP-0373/0374)
- **Encrypted local database**: SQLCipher with AES-256
- **Encrypted file storage**: All local files (avatars, transfers) encrypted at rest (AES-256-GCM)
- **Panic Wipe**: Instant secure deletion of all local data (`Ctrl+Shift+Alt+P`)
- **Auto-wipe**: Triggered after 3 failed database unlock attempts
- **Secure deletion**: `PRAGMA secure_delete = ON` — SQLite overwrites deleted data
- **TLS certificate pinning**: Trust self-signed certificates for self-hosted servers
- **Integrated Tor**: Zero-config Tor & obfs4proxy for network anonymity (Linux)
- **Isolated OpenPGP keyring**: App-scoped `GNUPGHOME` — Panic Wipe removes all key material
- **DTLS-SRTP only**: No SDES-SRTP for voice/video calls
