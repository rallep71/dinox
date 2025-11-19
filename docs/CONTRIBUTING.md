# 👥 Contributing to Dino Extended

Thank you for your interest in contributing! This document provides guidelines and information for contributors.

---

## 📋 Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Coding Standards](#coding-standards)
- [Commit Guidelines](#commit-guidelines)
- [Pull Request Process](#pull-request-process)
- [Testing Requirements](#testing-requirements)
- [Documentation](#documentation)

---

## 📜 Code of Conduct

### Our Pledge

We are committed to providing a welcoming and inclusive environment for all contributors, regardless of:
- Experience level
- Background
- Identity
- Location

### Expected Behavior

- ✅ Be respectful and constructive
- ✅ Accept feedback gracefully
- ✅ Focus on what's best for the project
- ✅ Help newcomers get started

### Unacceptable Behavior

- ❌ Harassment, discrimination, or personal attacks
- ❌ Trolling or inflammatory comments
- ❌ Publishing others' private information

**Enforcement**: Violations can be reported to maintainers. We reserve the right to remove contributions or ban users who violate these guidelines.

---

## 🚀 Getting Started

### 1. Set Up Development Environment

Follow the [BUILD.md](BUILD.md) guide to compile Dino from source.

**Quick Start**:
```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/dino.git
cd dino

# Add upstream remote
git remote add upstream https://github.com/rallep71/dino.git

# Install dependencies and build
# (see BUILD.md for your distro)
meson setup build
meson compile -C build
```

### 2. Find Something to Work On

**Good First Issues**: Check issues labeled [`good first issue`](https://github.com/rallep71/dino/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)

**Priority Areas**:
- 🐛 Bug fixes (see [DEVELOPMENT_PLAN.md](../DEVELOPMENT_PLAN.md) Phase 1)
- 🌍 Translations (`main/po/*.po` files)
- 📖 Documentation improvements
- 🧪 Test coverage expansion

**Before Starting**:
1. Check if issue is already assigned
2. Comment on the issue expressing interest
3. Wait for maintainer confirmation (to avoid duplicate work)

---

## 🔄 Development Workflow

### Branch Strategy

```
master (stable)
  └─ develop (active development)
       ├─ feature/my-feature
       ├─ bugfix/fix-crash
       └─ refactor/clean-code
```

### Creating a Branch

```bash
# Update your local repository
git checkout develop
git pull upstream develop

# Create feature branch
git checkout -b feature/add-sticker-support

# Or bug fix branch
git checkout -b bugfix/fix-database-crash
```

### Making Changes

```bash
# Make your changes in appropriate files
# Test your changes
meson compile -C build
./build/main/dino

# Run tests
meson test -C build
```

### Keeping Your Branch Updated

```bash
# Fetch upstream changes
git fetch upstream

# Rebase on upstream/develop
git rebase upstream/develop

# If conflicts, resolve them, then:
git add .
git rebase --continue
```

---

## 📝 Coding Standards

### Vala Style Guide

Follow [GNOME Vala conventions](https://wiki.gnome.org/Projects/Vala/Hacking).

#### Naming Conventions

```vala
// Classes: PascalCase
public class MessageProcessor : Object {
    
    // Methods: snake_case
    public void process_message(Message message) {
        // ...
    }
    
    // Properties: snake_case
    public string account_jid { get; set; }
    
    // Private fields: underscore prefix
    private HashMap<Jid, Conversation> _conversations;
    
    // Constants: UPPER_SNAKE_CASE
    public const int MAX_MESSAGE_LENGTH = 65535;
    
    // Signals: snake_case
    public signal void message_received(Message message);
}
```

#### Indentation and Formatting

```vala
// Use 4 spaces (NO TABS)
public class Example {
    
    // Opening brace on same line for methods
    public void my_method() {
        if (condition) {
            do_something();
        } else {
            do_other_thing();
        }
    }
    
    // Line length: max 120 characters
    public void long_method_with_many_parameters(
        string param1,
        int param2,
        bool param3
    ) {
        // Method body
    }
}
```

#### Comments

```vala
/**
 * Brief description of the class.
 *
 * Longer description explaining purpose and usage.
 * Can span multiple lines.
 */
public class MyClass {
    
    /**
     * Brief method description.
     *
     * @param message The message to process
     * @return true if successful, false otherwise
     */
    public bool process(Message message) {
        // Implementation comments use //
        // Explain WHY, not WHAT (code shows what)
        
        // This check prevents null pointer crash in XmppStream
        if (message.stanza == null) {
            return false;
        }
        
        return true;
    }
}
```

### File Organization

```vala
// 1. License header (use existing files as template)
// 2. using statements
using Gee;
using Gtk;

// 3. namespace
namespace Dino {

// 4. Class definition
public class MyClass : Object {
    // Order:
    // - Constants
    // - Public properties
    // - Private fields
    // - Signals
    // - Constructor
    // - Public methods
    // - Private methods
}

} // namespace Dino
```

---

## 📝 Commit Guidelines

### Commit Message Format

```
type(scope): short description (max 72 chars)

Longer explanation if needed. Wrap at 72 characters.
Explain WHY the change was made, not HOW (code shows how).

Can have multiple paragraphs.

Fixes #123
Closes #456
```

### Types

| Type | Usage |
|------|-------|
| `feat` | New feature |
| `fix` | Bug fix |
| `refactor` | Code restructuring (no behavior change) |
| `perf` | Performance improvement |
| `test` | Add or modify tests |
| `docs` | Documentation only |
| `style` | Formatting, whitespace (no code change) |
| `chore` | Build process, dependencies |
| `ci` | CI/CD changes |

### Scopes

Common scopes:
- `database` - Database schema or queries
- `ui` - User interface
- `omemo` - OMEMO encryption
- `openpgp` - OpenPGP encryption
- `rtp` - Voice/video calls
- `xmpp` - XMPP protocol
- `mam` - Message Archive Management
- `muc` - Multi-user chat

### Examples

**Good commits**:
```
feat(omemo): add QR code device verification

Implements XEP-0384 device verification via QR codes.
Users can now scan QR codes to verify OMEMO devices.

Fixes #123

---

fix(database): prevent crash on long messages

Changed message.body column from VARCHAR(65535) to TEXT.
This prevents crashes when messages exceed 65KB.

Migration added: v30 -> v31.

Fixes #1784

---

refactor(notifications): unify dual notification backends

Merged libdino/src/service/notification.vala and
main/src/ui/notifications.vala into single backend
with strategy pattern for GNotifications vs FreeDesktop.

Reduces code duplication by ~300 lines.
```

**Bad commits**:
```
❌ fix bug
❌ update files
❌ WIP
❌ asdf
❌ Fixed the thing that was broken
```

---

## 🔀 Pull Request Process

### Before Submitting

**Checklist**:
- [ ] Code compiles without warnings (`meson compile -C build`)
- [ ] Tests pass (`meson test -C build`)
- [ ] Code follows style guidelines
- [ ] Commit messages follow convention
- [ ] Documentation updated (if needed)
- [ ] No unrelated changes included

### Creating a Pull Request

1. **Push your branch**:
```bash
git push origin feature/my-feature
```

2. **Open PR on GitHub**:
   - Go to https://github.com/rallep71/dino
   - Click "New Pull Request"
   - Select your branch
   - Fill out PR template (see below)

3. **PR Title Format**:
```
feat(scope): brief description
```

4. **PR Description** (template auto-fills):
```markdown
## Description
Brief summary of changes.

## Related Issues
Fixes #123
Closes #456

## Type of Change
- [ ] Bug fix
- [x] New feature
- [ ] Refactoring
- [ ] Documentation

## Testing Done
- Tested manually on Ubuntu 24.04
- Verified calls still work
- Ran full test suite

## Screenshots (if UI changes)
[Attach screenshots]

## Checklist
- [x] Code compiles
- [x] Tests pass
- [x] Documentation updated
```

### Review Process

1. **Automated Checks**: CI runs tests and linters
2. **Maintainer Review**: Maintainer reviews code
3. **Requested Changes**: Address feedback, push updates
4. **Approval**: Once approved, maintainer merges

**Response Time**: Maintainers aim to respond within 48 hours.

### After Merge

```bash
# Update your local repository
git checkout develop
git pull upstream develop

# Delete feature branch
git branch -d feature/my-feature
git push origin --delete feature/my-feature
```

---

## 🧪 Testing Requirements

### Running Tests

```bash
# Run all tests
meson test -C build

# Run specific test
meson test -C build libdino:jid

# Verbose output
meson test -C build --verbose

# Run under valgrind (memory leak check)
meson test -C build --wrap='valgrind --leak-check=full'
```

### Writing Tests

Tests live in `*/tests/` directories:
- `libdino/tests/`
- `xmpp-vala/tests/`

**Example test** (`libdino/tests/jid.vala`):
```vala
using Dino;

class JidTest : Gee.TestCase {
    
    public JidTest() {
        base("Jid");
        add_test("parse_valid", test_parse_valid);
        add_test("parse_invalid", test_parse_invalid);
    }
    
    void test_parse_valid() {
        var jid = new Jid("user@domain.com/resource");
        assert(jid.localpart == "user");
        assert(jid.domainpart == "domain.com");
        assert(jid.resourcepart == "resource");
    }
    
    void test_parse_invalid() {
        try {
            var jid = new Jid("invalid@@jid");
            fail("Should have thrown exception");
        } catch (Error e) {
            // Expected
        }
    }
}
```

### Manual Testing

Before submitting PR, test:
- ✅ Basic messaging (send/receive)
- ✅ File transfers
- ✅ Encryption (if affected)
- ✅ Calls (if RTP/ICE affected)
- ✅ No crashes or errors in logs

**Check logs**:
```bash
DINO_LOG_LEVEL=debug ./build/main/dino 2>&1 | tee dino.log
# Reproduce issue, then check dino.log
```

---

## 📖 Documentation

### Code Documentation

```vala
/**
 * Process incoming XMPP message stanzas.
 *
 * This class handles message routing, deduplication,
 * and storage in the local database.
 *
 * @see XmppStream
 * @see Database
 */
public class MessageProcessor : Object {
    
    /**
     * Process a received message.
     *
     * @param account The account that received the message
     * @param message The message to process
     * @return true if message was handled, false otherwise
     */
    public bool process_message(Account account, Message message) {
        // ...
    }
}
```

### Documentation Files

Update these when relevant:
- `docs/BUILD.md` - Build instructions
- `docs/ARCHITECTURE.md` - Architecture changes
- `docs/XEP_SUPPORT.md` - New XEP implementations
- `docs/DATABASE_SCHEMA.md` - Database changes
- `README.md` - User-facing changes

### Translations

Translations use GNU gettext (`.po` files in `main/po/`).

**Adding translatable strings**:
```vala
// In code
string message = _("Hello, world!");
string formatted = _("Received %d messages").printf(count);

// Update translation template
ninja -C build dino-update-po

// Translators then update *.po files
```

**Don't translate**:
- Log messages
- Debug output
- Internal identifiers
- XMPP protocol strings

---

## 🌍 Translation Contributions

We welcome translations! Dino supports 40+ languages.

### How to Translate

1. **Check existing translations**: `main/po/LINGUAS`
2. **Create/update .po file**:
```bash
cd main/po
# For new language (e.g., Portuguese)
msginit -l pt_BR -o pt_BR.po -i dino.pot

# For existing language
msgmerge -U de.po dino.pot
```

3. **Edit .po file** with translation tool:
   - [Poedit](https://poedit.net/) (GUI)
   - [Lokalize](https://apps.kde.org/lokalize/) (KDE)
   - Or any text editor

4. **Add language to LINGUAS**:
```bash
echo "pt_BR" >> LINGUAS
```

5. **Submit PR** with updated `.po` file

---

## 🎖️ Recognition

Contributors are recognized in:
- Git commit history
- `CONTRIBUTORS.md` (maintainers add after first merged PR)
- Release notes for significant contributions

---

## ❓ Questions?

- **General questions**: [GitHub Discussions](https://github.com/rallep71/dino/discussions)
- **Bug reports**: [GitHub Issues](https://github.com/rallep71/dino/issues)
- **Chat**: XMPP channel `chat@dino.im` (upstream community)

---

**Thank you for contributing to Dino Extended!** 🎉
