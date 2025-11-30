# DinoX - Development Plan

> **Last Updated**: November 30, 2025  
> **Version**: 0.7.7

---

## Current Status

| Metric | Status |
|--------|--------|
| **Version** | v0.7.7 |
| **XEPs Implemented** | 67 |
| **Languages** | 47 (100% translated) |
| **Build Status** | Clean (0 warnings) |
| **GTK/libadwaita** | GTK4 4.14, libadwaita 1.5 |

---

## Completed Features (v0.6.0 - v0.7.7)

### Core Features
- System Tray with background mode toggle
- Custom server settings (host, port, resource)
- Delete conversation history
- Contact management (block, mute, remove)
- Dark mode toggle (light/dark/system)
- Volume controls for calls (microphone & speaker)

### Database & Backup (NEW in v0.7.7)
- **Encrypted Backup**: Password-protected backups with GPG encryption
- **Encrypted Restore**: Restore backups with password decryption
- **Unencrypted Backup**: Quick backup without encryption
- **Unencrypted Restore**: Restore unencrypted backups
- **Database Maintenance**: VACUUM, REINDEX, integrity check
- **Data Location Info**: View where user data is stored
- **Progress Dialogs**: Visual feedback during backup/restore operations

### Messaging
- Voice messages (AAC/m4a format)
- Inline video player (H.264/HEVC)
- Message retraction (XEP-0424)
- Message moderation (XEP-0425)
- Message reactions (XEP-0444)
- Message replies (XEP-0461)

### Group Chats (MUC)
- MUJI multi-party video calls (XEP-0272)
- Room privacy control
- Affiliation management (admin, owner, ban)
- MUC invitations
- Room destruction
- Browse rooms with member count

### Security
- OMEMO encryption for messages and files
- OMEMO encrypted calls (XEP-0396)

---

## Roadmap

### Phase 9: MUJI Group Calls Phase 2 (Q1 2026)

| Feature | Status |
|---------|--------|
| Volume controls | DONE |
| Individual volume per participant | DONE |
| Call quality indicators | TODO |
| Speaking indicator | DEFERRED |

**Note**: MUJI needs testing with 3+ participants

---

### Phase 10: Bug Fixes (Q1 2026)

| Issue | Description | Status |
|-------|-------------|--------|
| OMEMO Call Sessions | Auto-refresh stale OMEMO sessions for calls | PARTIAL |
| Echo Cancellation | Fine-tuning WebRTC AEC | PARTIAL |
| Self-signed Certs | Accept/pin dialog | PARTIAL |
| Spell Checking | Waiting for GTK4 support | BLOCKED |

---

### Phase 11: Modern XEPs (Q2 2026)

| XEP | Feature | Status |
|-----|---------|--------|
| XEP-0388 | SASL2/FAST Auth | TODO |
| XEP-0386 | Bind 2 | TODO |
| XEP-0357 | Push Notifications | TODO |
| XEP-0449 | Stickers | TODO |

---

### Phase 12: 1.0 Release (Q4 2026)

**Requirements**:
- Zero P1 crash bugs
- Memory usage <200MB for 7-day sessions
- All Phase 9-11 features complete
- 3+ months beta testing

---

## Quick Build

```bash
# Ubuntu/Debian
sudo apt install -y meson ninja-build valac libgtk-4-dev libadwaita-1-dev \
  libglib2.0-dev libgee-0.8-dev libsqlite3-dev libgcrypt20-dev \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libnice-dev \
  libsrtp2-dev libgnutls28-dev libgpgme-dev libqrencode-dev \
  libsoup-3.0-dev libicu-dev libcanberra-dev libwebrtc-audio-processing-dev \
  libdbusmenu-glib-dev

meson setup build && meson compile -C build && ./build/main/dinox
```

See [docs/BUILD.md](docs/BUILD.md) for Flatpak and other distros.

---

## Contributing

```bash
git checkout -b feature/my-feature
# Make changes
meson test -C build
git commit -m "feat: add feature"
git push origin feature/my-feature
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

## License

GPL-3.0 - See [LICENSE](LICENSE)

---

**Maintainer**: @rallep71
