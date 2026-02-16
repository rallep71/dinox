# Security Policy

## Supported Versions

| Version   | Supported          |
|-----------|--------------------|
| 1.1.0.x   | Yes                |
| 1.0.x     | Security fixes only |
| < 1.0     | No                 |

## Reporting a Vulnerability

It is highly appreciated to report a vulnerability to the DinoX developers.
We kindly ask you to **not disclose it publicly** until it has been fixed.
This prevents abuse and exploitation in the current published releases.

**Do NOT open a public GitHub issue for security vulnerabilities.**

### How to Report

Please report issues directly via:

- **Email**: dinox@handwerker.jetzt
- **XMPP** (OMEMO encrypted): dinox@chat.handwerker.jetzt

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

DinoX includes comprehensive security hardening across all layers:

### End-to-End Encryption

- **OMEMO (Legacy + OMEMO 2)**: Double-Ratchet-based encryption for 1:1 and group chats (XEP-0384, XEP-0420 Stanza Content Encryption)
- **OpenPGP**: Legacy (XEP-0027) and modern OpenPGP for XMPP (XEP-0373/0374)
- **OMEMO session auto-repair**: Automatic detection and recovery of broken OMEMO sessions
- **Encrypted file transfers**: Files encrypted on-the-fly during upload with AES-256-GCM; keys embedded in OMEMO message (XEP-0448/0454)
- **File hash verification**: Downloaded file integrity verified via SHA-256 checksums (XEP-0300)

### Local Data Protection

- **Mandatory database encryption**: SQLCipher with AES-256 — password required at every startup, no plaintext fallback
- **Change database password**: Users can change the encryption password via Preferences (`PRAGMA rekey`)
- **Automatic plaintext-to-encrypted migration**: Legacy unencrypted databases are auto-migrated when a password is set
- **Encrypted file storage**: All local files (avatars, file transfers, media) encrypted at rest with AES-256-GCM
- **Secure key storage**: OMEMO database encryption keys stored in libsecret (GNOME Keyring / KDE Wallet) with file-based fallback on Windows
- **Isolated OpenPGP keyring**: App-scoped `GNUPGHOME` — completely separate from the system keyring
- **Secure deletion**: `PRAGMA secure_delete = ON` on all databases — SQLite overwrites deleted data with zeros
- **WAL journal mode**: `PRAGMA journal_mode=WAL` with `synchronous=NORMAL` for crash safety

### Data Destruction

- **Panic Wipe**: Instant secure deletion of all local data — database, keys, cache, config (`Ctrl+Shift+Alt+P`)
- **Auto-wipe**: Triggered automatically after 3 failed database unlock attempts
- **Zero-trace cache cleanup**: Decrypted cache files (`~/.cache/dinox`) are wiped on application exit
- **Encrypted backup**: GPG-encrypted or OpenSSL-encrypted database backups; passwords piped via stdin (never exposed in CLI args)

### Network Security

- **Direct TLS**: XMPP connections via direct TLS (XEP-0368) — avoids STARTTLS downgrade attacks
- **TLS certificate pinning**: Trust self-signed certificates for self-hosted servers; pinned in local database
- **Integrated Tor**: Zero-config Tor & obfs4proxy for network anonymity (Linux)
- **Tor firewall mode**: Restricts Tor traffic to ports 80 and 443 only for restrictive network environments
- **obfs4 bridge filtering**: Prioritizes bridges on ports 80/443 for firewall bypass
- **.onion TLS auto-accept**: Self-signed certificates from `.onion` domains are automatically trusted (encryption provided by Tor)
- **SOCKS5 proxy support**: Generic SOCKS5 and Tor proxy types for XMPP connections (XEP-0065/0260)
- **DTLS-SRTP only**: No SDES-SRTP for voice/video calls — DTLS key exchange only (XEP-0320)
- **Stream Management**: XEP-0198 for reliable message delivery with session resume

### Privacy Controls

- **Disappearing messages**: Configurable per-conversation auto-delete (15m, 30m, 1h, 24h, 7d, 30d)
- **Message retraction**: Delete messages for everyone (XEP-0424) with dual-stack compatibility
- **Read receipt control**: Configurable per-conversation and globally — disable outgoing read markers
- **Typing notification control**: Configurable per-conversation and globally — disable outgoing typing indicators
- **Location sharing opt-in**: Disabled by default, requires explicit user action to enable
- **Smart throttling**: Bulk message retraction limited to 5 msgs/sec to prevent server disconnects

### Bot API Security

- **Token authentication**: SHA-256 hashed API tokens with Bearer header validation
- **Rate limiting**: Request throttling to prevent abuse
- **Localhost-only binding**: HTTP API server bound to 127.0.0.1 only — not accessible from the network
- **Webhook HMAC signatures**: HMAC-SHA256 signed webhook payloads for integrity verification

### Build Hardening

- **Stack protector**: `-fstack-protector-strong` enabled
- **FORTIFY_SOURCE**: `-D_FORTIFY_SOURCE=2` for buffer overflow detection
- **Format string protection**: `-Wformat -Werror=format-security`
