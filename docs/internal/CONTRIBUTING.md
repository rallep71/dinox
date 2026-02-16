# Contributing to DinoX

Thank you for your interest in contributing to DinoX!

## How to Contribute

### Reporting Bugs

- Check if the issue already exists in [GitHub Issues](https://github.com/rallep71/dinox/issues)
- Create a new issue using the **Bug Report** template
- Include steps to reproduce, expected behavior, and actual behavior
- Add system information (OS, DinoX version, installation method)
- Attach debug logs — see [DEBUG.md](DEBUG.md) for instructions

### Feature Requests

- Open a new issue using the **Feature Request** template
- Describe the feature and why it would be useful
- If it relates to an XMPP Extension Protocol (XEP), include the XEP number and link
- If possible, include mockups or examples

### Code Contributions

1. **Fork the repository**
   ```bash
   git clone https://github.com/YOUR_USERNAME/dinox.git
   cd dinox
   ```

2. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Install dependencies and build** — see [BUILD.md](BUILD.md)
   ```bash
   meson setup build
   ninja -C build
   ./build/main/dinox
   ```

4. **Make your changes**
   - Follow existing code conventions (see below)
   - Test on at least one platform (Linux build, Flatpak, or Windows)

5. **Commit your changes**
   - Use clear, descriptive commit messages
   - Reference issues if applicable: `Fix #123: Description`
   - Keep commits focused — one logical change per commit

6. **Submit a Pull Request**
   - Fill out the PR template
   - Describe what your PR does and link related issues
   - Add before/after screenshots for UI changes

### Translations

DinoX supports 47 languages via gettext (~85% translated). We welcome translation contributions!

**The easiest way to translate is via [Weblate](https://hosted.weblate.org/engage/dinox/)** — no local setup needed, just translate in the browser.

[![Translation status](https://hosted.weblate.org/widget/dinox/translations/multi-auto.svg)](https://hosted.weblate.org/engage/dinox/)

**Alternatively, contribute via Pull Request:**

1. Browse the existing `.po` files in `main/po/` — pick your language or create a new one
2. Use a PO editor like [Poedit](https://poedit.net/), [Lokalize](https://apps.kde.org/lokalize/), or any text editor
3. Focus on untranslated (`msgstr ""`) and fuzzy entries first
4. Test your translations locally by building and running DinoX
5. Submit a Pull Request with your updated `.po` file

**Quick start for a new language:**

```bash
# Create a new .po file from the template
cd main/po
msginit -l <LANG_CODE> -i dinox.pot -o <LANG_CODE>.po
# Edit <LANG_CODE>.po with your translations
```

**Translation helper script** (checks coverage across all languages):

```bash
python3 scripts/translate_all.py
```

## Project Architecture

DinoX follows a modular plugin architecture:

| Directory | Purpose |
|-----------|---------|
| `xmpp-vala/` | XMPP protocol library — XEP implementations, stream management |
| `libdino/` | Core application library — services, database, business logic |
| `main/` | GTK4/libadwaita UI — windows, widgets, controllers |
| `qlite/` | SQLite/SQLCipher ORM wrapper |
| `crypto-vala/` | Cryptographic abstractions |
| `plugins/omemo/` | OMEMO encryption (Legacy + OMEMO 2) |
| `plugins/openpgp/` | OpenPGP encryption (XEP-0027, XEP-0373/0374) |
| `plugins/rtp/` | Audio/video calls (Jingle RTP, MUJI) |
| `plugins/ice/` | ICE/DTLS-SRTP transport for calls |
| `plugins/tor-manager/` | Integrated Tor & obfs4proxy |
| `plugins/http-files/` | HTTP file upload/download (XEP-0363) |
| `plugins/notification-sound/` | Notification sounds |
| `plugins/bot-features/` | Local HTTP API server, bot management, AI integration |

### Key Patterns

- **Plugin system**: Plugins implement the `RootInterface` and register via `ModuleManager`
- **Async operations**: Use GLib `async`/`yield` pattern throughout
- **Database access**: All queries go through `qlite` — never raw SQL in UI code
- **Signal-based communication**: GLib signals for loose coupling between components

## Code Style

- **Language**: Vala (GTK4 + libadwaita)
- Follow existing code conventions in the file you're editing
- Use meaningful variable and function names
- Comment complex logic, especially protocol-level decisions
- Keep functions focused and small
- Use `debug()`, `warning()`, `critical()` for logging — never `print()`

## Platforms

DinoX runs on Linux and Windows. When contributing:

- **Linux-specific code**: Guarded by `#if !WINDOWS` or runtime checks
- **Windows-specific code**: Guarded by `#if WINDOWS` — see `main/src/ui/application.vala`
- **Cross-platform**: Most code should work on both platforms. Test when possible.

## Communication

- **XMPP Chat** (OMEMO encrypted): [dinox@chat.handwerker.jetzt](xmpp:dinox@chat.handwerker.jetzt?join)
- **Email**: dinox@handwerker.jetzt
- **GitHub Issues**: For bugs and feature requests
- **Security vulnerabilities**: See [SECURITY.md](SECURITY.md) — do NOT open public issues

## License

By contributing, you agree that your contributions will be licensed under the [GPLv3](LICENSE).
