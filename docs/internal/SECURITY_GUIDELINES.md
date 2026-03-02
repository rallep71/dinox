# DinoX Security Guidelines

> **Version:** 1.0 — March 1, 2026
> **Based on:** Code audit (164 bugs, 15+ security-relevant) + SECURITY_AUDIT.md (plugins)
> **Scope:** Entire DinoX project (libdino, xmpp-vala, qlite, main, plugins)

---

## 1. Core Principles

1. **Defense in Depth** — Never rely on a single security layer
2. **Fail Secure** — On errors, fall into the secure state (encrypt, reject, disconnect)
3. **Least Privilege** — Request only the minimum necessary rights/access
4. **Zero Trust against Server** — Always validate server data, never trust it blindly

---

## 2. Input Validation

### 2.1 XMPP Stanzas (highest priority)

**Rule: Every attribute and subnode can be null, empty, or manipulated.**

```vala
// CORRECT: Defensive processing
StanzaNode? item = stanza.get_subnode("item");
if (item == null) return;

string? jid_str = item.get_attribute("jid");
if (jid_str == null || jid_str == "") return;

Jid? jid;
try {
    jid = new Jid(jid_str);
} catch (InvalidJidError e) {
    warning("Invalid JID in stanza: %s", jid_str);
    return;
}

// WRONG: Blind trust
Jid jid = new Jid(item.get_attribute("jid"));  // NPE + InvalidJidError!
```

### 2.2 Integer Parsing

```vala
// CORRECT: Safe conversion with fallback
string? val = node.get_attribute("count");
int count = (val != null) ? int.parse(val) : 0;
if (count < 0 || count > MAX_REASONABLE_VALUE) count = 0;

// CORRECT: uint for IDs that can exceed INT_MAX (OMEMO device IDs)
uint32 device_id = (uint32) node.get_attribute_uint("rid", 0);

// WRONG: int for uint32 values (Bug #8, #9)
int device_id = node.get_attribute_int("rid");  // -1 when > INT_MAX!
```

### 2.3 String Input

```vala
// Check length:
if (input.length > MAX_INPUT_LENGTH) {
    warning("Input too long: %d bytes", input.length);
    return;
}

// Slash commands: ALWAYS check array length (Bug #111)
string[] token = text.split(" ", 2);
if (token.length < 2) {
    warning("Missing argument for command");
    return;
}
string argument = token[1];

// JID validation: ALWAYS try/catch
try {
    var jid = new Jid(user_input);
} catch (InvalidJidError e) {
    // Show error message, do not proceed
}
```

### 2.4 File Input

```vala
// Check file size BEFORE processing:
FileInfo info = file.query_info("standard::size", FileQueryInfoFlags.NONE);
int64 size = info.get_size();
if (size > MAX_FILE_SIZE || size <= 0) {
    warning("File size out of range: %lld", size);
    return;
}

// Do not derive MIME type solely from server-provided value:
// Always additionally check magic bytes / content sniffing
```

---

## 3. Cryptography

### 3.1 General Rules

| Rule | Description |
|------|------------|
| **No custom crypto** | Only use GnuTLS, libsignal-protocol, libsrtp |
| **Constant-time comparisons** | `GLib.Memory.cmp()` or `Crypto.hmac_verify()` instead of `==` for secrets |
| **Random numbers** | Only `GnuTLS.Rnd.random()` or `/dev/urandom`, never `GLib.Random` for crypto |
| **Key material** | Overwrite after use with `GLib.Memory.set(buf, 0, buf.length)` |
| **Algorithm selection** | Prefer AES-256-GCM, AES-128-CBC only as fallback |

### 3.2 OMEMO-Specific

```vala
// Device ID is uint32, NOT int (Bug #8, #9):
uint32 own_device_id = ...;
uint32 remote_device_id = (uint32) node.get_attribute_uint("rid", 0);

// Session validation:
// Always check whether a session exists BEFORE encrypting
if (!store.contains_session(address)) {
    // Build session, do not encrypt blindly
}

// Trust decisions:
// OMEMO trust must never be granted automatically for unknown devices
// Always require user confirmation for new device keys
```

### 3.3 SRTP (Voice/Video)

```vala
// Support all crypto suites (Bug #1):
// AES_CM_128_HMAC_SHA1_80 AND AES_CM_128_HMAC_SHA1_32
// Do NOT hardcode only one suite

// ALWAYS check stream errors (Bug #2):
int ret = policy.add_stream(stream);
if (ret != ErrorStatus.ok) {
    warning("SRTP add_stream failed: %d", ret);
    return;
}
```

---

## 4. TLS / Network

### 4.1 TLS Rules

```vala
// STARTTLS: Rejection MUST cause connection abort (Bug #11):
if (proceed_node.name != "proceed") {
    throw new IOError.CONNECTION_REFUSED("STARTTLS rejected by server");
    // NEVER proceed with TLS upgrade anyway!
}

// Certificate pinning:
// Trust-on-First-Use (TOFU) for XMPP connections
// Warn user on certificate change

// Minimum TLS version: TLS 1.2
// Do NOT accept TLS 1.0/1.1
```

### 4.2 IQ Spoofing Protection

```vala
// Validate sender on EVERY IQ response:
public void handle_iq_response(Iq.Stanza iq) {
    // Check whether the response comes from the expected server/JID:
    if (iq.from != null && !iq.from.equals(expected_from)) {
        warning("IQ spoofing attempt from %s (expected %s)",
            iq.from.to_string(), expected_from.to_string());
        return;
    }
}

// Pubsub events: Validate sender
// Presence: Only accept from known MUC JIDs
```

### 4.3 Proxy / Tor

```vala
// SOCKS5 proxy: ALWAYS forward hostnames, do NOT resolve locally
// (DNS leak protection for Tor)

// Tor bridge: Detect .onion addresses and route correctly
// No clearnet fallbacks for .onion connections
```

---

## 5. SQL / Database

### 5.1 SQL Injection Protection

```vala
// CORRECT: Always use parameterized queries (Qlite query builder):
db.message.select()
    .with(db.message.stanza_id, "=", user_provided_id)  // Parameterized!
    .limit(1);

// WRONG: String concatenation (NEVER!):
// db.exec(@"SELECT * FROM message WHERE stanza_id = '$id'");

// Raw SQL only for PRAGMA and migrations:
db.exec("PRAGMA journal_mode = WAL");
```

### 5.2 Entity ID Integrity

```vala
// After persist() or INSERT, verify that the assigned ID belongs to the
// expected entity. INSERT OR IGNORE + last_insert_rowid() can return a
// STALE rowid from an unrelated row when the insert was silently ignored
// (UNIQUE constraint conflict). This leads to cross-entity data leaks.
//
// ALWAYS: Look up existing row first, only create if not found.
// ALWAYS: Sanity-check id > 0 after persist.
if (entity.id <= 0) {
    warning("Persist returned invalid ID — possible DB conflict");
}
```

### 5.3 Data Integrity

```vala
// Activate WAL mode BEFORE migrations (Bug P1):
db.exec("PRAGMA journal_mode = WAL");
db.exec("PRAGMA synchronous = NORMAL");
start_migration();  // Not the other way around!

// Migrations: error() on failure (not warning):
try {
    exec("ALTER TABLE ...");
} catch (Error e) {
    error("Migration failed: %s", e.message);  // App terminates
}
```

---

## 6. Filesystem

### 6.1 Path Traversal

```vala
// ALWAYS sanitize filenames from server:
string safe_name = sanitize_filename(server_provided_name);

// Do not allow ../:
if (path.contains("..") || path.has_prefix("/")) {
    warning("Path traversal attempt: %s", path);
    return;
}

// Download directory: Always use absolute path with base directory:
string full_path = Path.build_filename(download_dir, safe_name);
if (!full_path.has_prefix(download_dir)) {
    warning("Path traversal detected");
    return;
}
```

### 6.2 Temp Folder Security

```vala
// Temporary files: Use GLib.Dir.make_tmp()
// Permissions: 0600 for sensitive files
// Cleanup: ALWAYS in finally block or defer pattern

// Do NOT enumerate /tmp/ searching for own files (Bug D2)
// Instead: Use PID file or lock file
```

---

## 7. UI Security

### 7.1 Message Rendering

```vala
// ALWAYS escape message content before display:
// GTK4 Label escapes by default, BUT:
// With use_markup=true you MUST escape manually:
label.label = Markup.escape_text(message.body);

// URLs: Only open allowed schemes:
// http://, https://, xmpp:
// NOT: file://, javascript:, data:

// SVG/images: Only process after decryption
// Do not render server-provided SVGs directly (XSS via SVG)
```

### 7.2 Notifications

```vala
// Escape notification content:
// No markup in notification body
// Truncate sender JID (do not display resource part)
```

---

## 8. Plugin Security

### 8.1 Plugin Isolation

| Rule | Description |
|------|------------|
| **Own namespace** | `Dino.Plugins.*` — no access to internal APIs |
| **Registration** | Only via `RootInterface.registered()` |
| **No direct DB access** | Own tables via `Database` extension |
| **Network** | Only via `StreamInteractor` |

### 8.2 Bot / API Security (bot-features, mqtt)

```vala
// API tokens: At least 32 bytes of entropy
// Rate limiting: Always enabled (Bug from audit: missing limits)
// Webhook URLs: Allow only https://
// MQTT broker: TLS strongly recommended for non-local connections.
//   When TLS is disabled for a non-local host, the UI MUST show
//   a prominent warning ("Credentials sent in plain text").
//   Local hosts (localhost, 127.*, 192.168.*, 10.*) may use plain
//   MQTT for development/LAN setups.

// Token validation:
if (token == null || token.length < 32) {
    return AuthResult.DENIED;
}
// Constant-time comparison:
if (!Crypto.secure_compare(token, expected_token)) {
    return AuthResult.DENIED;
}
```

---

## 9. Logging Security

### What MUST NOT be logged:
- Passwords / auth tokens
- OMEMO private keys / session keys
- Message content (only at debug level, never in production)
- Full stanzas with body (only header / type)

### Logging Format:
```vala
// CORRECT: No secrets
warning("Auth failed for account %s", account.bare_jid.to_string());

// WRONG: Password in log
// warning("Auth failed: user=%s pass=%s", user, password);

// CORRECT: Log stanza type, not content
debug("Received %s stanza from %s", stanza.name, stanza.from?.to_string() ?? "unknown");
```

---

## 10. Build Hardening

### Compiler Flags (meson.build)

```meson
# C hardening (already set):
add_project_arguments([
    '-Werror=implicit-function-declaration',
    '-fstack-protector-strong',
    '-D_FORTIFY_SOURCE=2',
], language: 'c')

# C++ hardening (Bug #129 — must also apply to .cpp files):
add_project_arguments([
    '-fstack-protector-strong',
    '-D_FORTIFY_SOURCE=2',
], language: 'cpp')
```

### Dependencies
- Regularly check for known CVEs (GnuTLS, libsignal, SQLite)
- Maintain minimum versions in `meson.build`
- No bundled copies of crypto libraries

---

## 11. Security Checklist for New Features

Before merging every new feature:

- [ ] Input validation: All external inputs (server, user, file) validated?
- [ ] Null safety: All `get_attribute()` / `get_subnode()` checked for null?
- [ ] SQL: Only parameterized queries?
- [ ] Crypto: Only established libraries, no custom crypto?
- [ ] TLS: No downgrade possibility?
- [ ] Filesystem: No path traversal possible?
- [ ] Logging: No secrets in logs?
- [ ] Error handling: Fail-secure on errors?
- [ ] Sender validation: IQ / presence / message sender checked?
- [ ] Integer safety: No overflow on uint32 / int conversion?
