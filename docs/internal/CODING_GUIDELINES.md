# DinoX Coding Guidelines

> **Version:** 1.0 — March 1, 2026
> **Based on:** Code audit (164 bugs, 37 audit units) + Performance analysis (24 findings)
> **Language:** Vala 0.56.16, GTK4, libadwaita, Meson

---

## 1. Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Classes / Interfaces | PascalCase | `ConversationManager`, `TextCommand` |
| Methods | snake_case | `get_conversation_for_message()` |
| Async methods | `async` keyword, snake_case | `public async void join(...)` |
| Signals | snake_case, verb-noun | `conversation_activated`, `message_received` |
| Properties | snake_case | `public int id { get; set; }` |
| Constants | UPPER_SNAKE_CASE | `NS_URI`, `DIRECTION_SENT` |
| Local variables | snake_case | `bare_jid`, `is_recent` |
| Private fields | snake_case, no prefix | `private Database db;` |
| Backing fields | underscore prefix only for property backing | `private string? body_;` |
| Enums | PascalCase name, UPPER_CASE values | `enum Marked { NONE, RECEIVED, READ }` |
| Namespaces | PascalCase, dot-separated | `Dino.Ui.ChatInput`, `Xmpp.Xep` |
| Files | snake_case.vala, matching main class | `conversation_manager.vala` |
| Modules | Static `IDENTITY` constant | `public static ModuleIdentity<T> IDENTITY = ...;` |

---

## 2. File Structure

### Organization
- **One primary class per file** (entity files, services)
- **Exception:** Closely related helper classes may reside in the same file (e.g. Table classes in `database.vala`)
- **UI files:** Maximum 2–4 classes when helper widgets are tightly coupled

### File Layout (order)
```vala
// 1. Copyright header
/*
 * Copyright (C) 2025 Ralf Peter <dinox@handwerker.jetzt>
 * GPL-3.0-or-later
 */

// 2. Using statements (sorted alphabetically)
using Gee;
using Gtk;
using Xmpp;

// 3. Namespace
namespace Dino.Ui {

// 4. Class
public class MyWidget : Gtk.Box {
    // 4a. Constants
    // 4b. Signals
    // 4c. Properties
    // 4d. Private fields
    // 4e. Constructor / construct {}
    // 4f. Public methods
    // 4g. Private methods
    // 4h. Signal handlers
}

}
```

### Namespace Mapping

| Directory | Namespace |
|-----------|-----------|
| `libdino/src/service/` | `Dino` |
| `libdino/src/entity/` | `Dino.Entities` |
| `main/src/ui/` | `Dino.Ui` |
| `main/src/ui/chat_input/` | `Dino.Ui.ChatInput` |
| `main/src/view_model/` | `Dino.Ui.ViewModel` |
| `xmpp-vala/src/` | `Xmpp` |
| `xmpp-vala/src/module/xep/` | `Xmpp.Xep` |
| `qlite/src/` | `Qlite` |
| `plugins/*/src/` | `Dino.Plugins.*` |

---

## 3. Code Style

### Formatting
- **Indentation:** 4 spaces (no tabs)
- **Braces:** K&R style (opening brace on same line)
- **Line length:** Soft limit 120 characters
- **Blank lines:** Between methods; within long methods for logical grouping

```vala
// CORRECT: K&R style
public void do_something() {
    if (condition) {
        action();
    } else {
        other_action();
    }
}

// WRONG: Allman style
public void do_something()
{
    ...
}
```

### Strings
```vala
// String templates for interpolation:
string msg = @"Account $account_name connected";

// printf style for logging:
warning("Failed to parse JID: %s", raw_jid);

// DO NOT mix:
// warning(@"Failed: $e.message");  // <-- WRONG, use printf style
```

### Null Handling
```vala
// Always mark nullable types with ?:
public Conversation? get_conversation(Jid jid);

// Null check with != null:
if (conversation != null) { ... }

// Non-null assertion (!) only when invariant is proven:
((!)identity).matches(flag);

// NEVER use (!) on uncontrolled input:
// string name = (!)node.get_attribute("name"); // <-- CRASH risk
```

---

## 4. Methods

### Length
- **Maximum:** 60 lines (excluding comments/blank lines)
- **Recommended:** 5–30 lines
- **When exceeded:** Split into named helper methods
- **Exception:** `construct {}` blocks in UI classes may be longer (widget setup)

### Parameters
- **Maximum:** 5 parameters — beyond that use an options object or builder
- **Nullable parameters** always with default `= null`:
  ```vala
  public void send(Message msg, Jid? override_to = null);
  ```

### Return Conventions
- **Not found:** `return null` (with `Type?` return)
- **Error:** `throws Error` (for I/O / network operations)
- **Bool:** `true` = success, `false` = not possible (GUI actions)

---

## 5. Error Handling

### Hierarchy (by severity)

| Method | When to use | Example |
|--------|------------|---------|
| `error()` | Unrecoverable — app terminates | DB migration failed |
| `critical()` | Severe error, app continues | SQL error in qlite |
| `warning()` | Expected error, handled | Invalid JID from server |
| `debug()` | Diagnostic information | Stanza details |
| `throws` | Caller must decide | I/O operations, network |
| `return null` | "Not found" semantics | Entity lookup |

### Patterns

```vala
// Pattern 1: try/catch with warning (standard)
try {
    var account = new Account.from_row(this, row);
} catch (InvalidJidError e) {
    warning("Ignoring account with invalid JID: %s", e.message);
}

// Pattern 2: propagate throws (I/O / network)
public async void connect() throws IOError {
    yield stream.setup();  // IOError propagated to caller
}

// Pattern 3: Silent catch ONLY for cleanup
try { temp_file.delete(null); } catch (Error e) {}

// Pattern 4: NEVER empty catch for business logic!
// try { process(); } catch (Error e) {}  // <-- FORBIDDEN
```

### Audit Rule: Every `catch` block must at least:
1. Log via `warning()` / `critical()`, OR
2. Re-throw to caller (`throw`), OR
3. Be explicitly commented as cleanup catch (`// cleanup, ignore`)

---

## 6. Signal Handling

### Declaration
```vala
// Signals are always public, snake_case, verb-participle:
public signal void conversation_activated(Conversation conversation);
public signal void message_received(Message message, Conversation conversation);
```

### Connection
```vala
// PREFERRED: Named method (disconnectable)
stream_interactor.account_added.connect(on_account_added);

// OK: Lambda for one-liners
button.clicked.connect(() => { on_action(); });

// AVOID: Complex lambdas (>3 lines) — use a named method
```

### Lifecycle Rules (from audit findings)
1. **Every `connect()` needs a `disconnect()` on destruction**
2. **Store signal handler IDs** when disconnect is needed:
   ```vala
   private ulong handler_id;
   handler_id = obj.signal_name.connect(on_handler);
   // Later:
   obj.disconnect(handler_id);
   ```
3. **UI widgets:** Signal disconnect in `dispose()` or during widget rebuild
4. **notify signals:** Pay special attention to correct property reference (Bug #116: wrong object)

---

## 7. Database (Qlite)

### Table Definition
```vala
public class MyTable : Table {
    public Column<int> id = new Column.Integer("id") { primary_key = true, auto_increment = true };
    public Column<string> name = new Column.Text("name") { not_null = true };
    public Column<long> time = new Column.Long("time");
    
    internal MyTable(Database db) {
        base(db, "my_table");
        init({id, name, time});
        // Indexes for frequently queried columns:
        index("my_table_name_idx", {name});
    }
}
```

### Query Builder (Fluent API)
```vala
// SELECT
var rows = db.message.select()
    .with(db.message.account_id, "=", account.id)
    .with(db.message.time, ">", cutoff)
    .order_by(db.message.time, "DESC")
    .limit(50);  // <-- ALWAYS LIMIT on potentially large result sets!

// INSERT
db.content_item.insert()
    .value(db.content_item.conversation_id, conv.id)
    .value(db.content_item.time, (long) time.to_unix())
    .perform();

// DELETE with result check
db.message.delete()
    .with(db.message.id, "=", id)
    .perform();
int deleted = db.changes();
```

### Audit Rules for DB
1. **Always LIMIT** on `select()` that may return unbounded rows (Bug D5)
2. **Index** for every column used in `with()` or `order_by()` (Bugs P2–P4)
3. **`changes()` instead of `COUNT(*)`** when you only need whether/how many rows were affected (Bug P5)
4. **No string concatenation** in queries — always use `.with()` parameters (SQL injection!)
5. **Raw SQL (`exec()`)** only for PRAGMA and migrations

---

## 8. GTK4 / UI Widgets

### Composite Templates (preferred)
```vala
[GtkTemplate (ui = "/im/github/rallep71/DinoX/my_widget.ui")]
public class MyWidget : Adw.Bin {
    [GtkChild] public unowned Label title_label;
    [GtkChild] private unowned Button action_button;
    
    construct {
        action_button.clicked.connect(on_action);
    }
}
```

### Programmatic Construction (for dynamic widgets)
```vala
var button = new Button() { name = "action" };
button.clicked.connect(() => { handle_click(); });
container.append(button);
```

### Audit Rules for UI
1. **`[GtkChild]` always `unowned`** — template owns the reference
2. **No blocking operations** on the main thread (file I/O, crypto, network)
3. **Avoid widget accumulation** — remove old widgets before adding new ones
4. **Mouse handlers:** Return early when result found (Bug P6: `break` after match)
5. **Check for division by zero** with dynamic sizes (Bug #109: `size==0`)
6. **Watch out for integer division** in size calculations (Bug #117: `150/100==1`)

---

## 9. Async / Threading

### Main-Thread Rule
**Everything that takes longer than 16 ms MUST run asynchronously:**
- File I/O → `yield` with `async` methods
- Network → GLib.SocketClient with async
- Crypto → Background thread with `new Thread<void>`
- GStreamer init → `Idle.add()`

### Async Pattern
```vala
public async Bytes? load_data() throws IOError {
    var file = File.new_for_path(path);
    var stream = yield file.read_async();
    var bytes = yield stream.read_bytes_async(MAX_SIZE);
    return bytes;
}
```

### Thread Safety
- **Vala signals are NOT thread-safe** — always use `Idle.add()` for UI updates from threads
- **HashMap / ArrayList not thread-safe** — use a mutex or only access on the main thread

---

## 10. Caching

### HashMap Caches
```vala
// Cache with ID lookup (O(1) instead of O(n)):
private HashMap<int, Entity> cache = new HashMap<int, Entity>();

// Always update cache when adding:
public void add(Entity entity) {
    list.add(entity);
    cache[entity.id] = entity;  // <-- DON'T FORGET (Bug P7)
}
```

### Audit Rules for Caches
1. **Every cache needs an eviction strategy** (LRU, time-based, or explicit purge)
2. **Clear cache on disconnect / logout** (Bug D8: mam_times grows unbounded)
3. **Avoid N+1:** Instead of a loop with individual lookups, use a JOIN or batch query

---

## 11. XMPP Protocol Specifics

### Stanza Processing
```vala
// ALWAYS access attributes / subnodes null-safely:
string? type = node.get_attribute("type");
if (type == null) return;

StanzaNode? query = stanza.get_subnode("query", NS_URI);
if (query == null) return;

// NEVER:
// string type = node.get_attribute("type");  // <-- can be null!
```

### Integer Parsing
```vala
// int for values that can be negative:
int priority = int.parse(node.get_attribute("priority") ?? "0");

// uint for IDs and counts (OMEMO device IDs etc.):
// Caution: get_attribute_int() returns -1 on overflow!
// Use get_attribute_uint() for uint32 values (Bug #8, #9)
```

### Sender Validation
```vala
// ALWAYS validate IQ response sender:
if (iq.from != null && !iq.from.equals(expected_from)) {
    warning("IQ response from unexpected sender: %s", iq.from.to_string());
    return;
}
```

---

## 12. Tests

### Test File Convention
- Test files in `*/tests/` next to the source code
- Filename: `*_test.vala` or `test_*.vala`
- Namespace: `*.Test` (e.g. `Dino.Test`, `Xmpp.Test`)

### Test Rules (from audit findings)
1. **Every test needs at least one assertion** (Bug #132: test without assertion always passes)
2. **Avoid misleading variable names** (Bug #131: `alice_message` instead of `bob_message`)
3. **Test locale-independently** — no assumptions about `msgfmt` output language (Bug #128)
4. **Test edge cases:** Null input, empty strings, integer boundaries
5. **Test adversarial input:** Missing attributes, unexpected types, manipulated stanzas

---

## 13. Commit Conventions

### Format
```
Category: Short description (max 72 characters)

- Detail 1
- Detail 2
```

### Categories
| Prefix | When |
|--------|------|
| `Fix:` | Bug fix |
| `Feature:` | New functionality |
| `Refactor:` | Code restructuring without behavior change |
| `Security:` | Security-relevant change |
| `Performance:` | Performance optimization |
| `Test:` | Test-only changes |
| `Build:` | Build system, dependencies |
| `Docs:` | Documentation only |

---

## 14. Common Mistakes (Top 10 from the Audit)

| # | Error Type | Frequency | Prevention |
|---|-----------|-----------|------------|
| 1 | Missing null check on `get_attribute()` | 30+ sites | Always use `?` type and `!= null` check |
| 2 | Copy-paste with wrong variable | 5 bugs | Name variables by context, not `a`, `b` |
| 3 | `token[1]` without length check | 6 bugs | `if (token.length < 2) return` |
| 4 | Signal handler never disconnected | 5+ sites | Store handler ID, disconnect in dispose() |
| 5 | Integer division instead of float | 2 bugs | `width * 100 > height * 150` instead of `width/height > 1.5` |
| 6 | int instead of uint for IDs > INT_MAX | 3 bugs | `get_attribute_uint()` for device IDs |
| 7 | DB query without LIMIT | 3+ sites | Always `.limit()` on potentially large sets |
| 8 | DB column without index | 3 bugs | Index for every WHERE / ORDER BY column |
| 9 | Blocking I/O on main thread | 4+ sites | `async` / `yield` or background thread |
| 10 | Empty catch block | 5+ sites | At least `warning()` or cleanup comment |
