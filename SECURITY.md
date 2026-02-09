# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 0.9.9.x | Yes |
| 0.9.8.x | Security fixes only |
| < 0.9.8 | No |

## Reporting a Vulnerability

If you discover a security vulnerability in DinoX, please report it responsibly.

**Do NOT open a public GitHub issue for security vulnerabilities.**

### How to Report

- **Email**: dinox@handwerker.jetzt
- **XMPP** (OMEMO encrypted): dinox@handwerker.jetzt

Please include:
- Description of the vulnerability
- Steps to reproduce
- Affected versions
- Potential impact

### Response Timeline

- **Acknowledgment**: Within 48 hours
- **Initial assessment**: Within 7 days
- **Fix & disclosure**: Coordinated with reporter

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
