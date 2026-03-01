# DinoX Code Review Checklist

> **Version:** 1.0 — March 1, 2026
> **Based on:** Code audit (164 bugs) + Performance analysis (24 findings)
> **Usage:** Go through this list on every merge request / code review

---

## Quick Check (5 minutes)

Every code review should check AT LEAST these points:

- [ ] **Compiles without errors** (`ninja -C build`, no warnings)
- [ ] **Tests pass** (`meson test -C build`, 8/8 OK)
- [ ] **No new compiler warnings** introduced
- [ ] **Commit message** follows format: `Category: Short description`

---

## 1. Nullability (highest error source — 30+ bugs in audit)

| # | Check | Details |
|---|-------|---------|
| 1.1 | [ ] `get_attribute()` return checked for null? | Every XMPP attribute access can return null |
| 1.2 | [ ] `get_subnode()` return checked for null? | Every subnode may be missing |
| 1.3 | [ ] Nullable `?` types declared correctly? | `Conversation?`, not `Conversation` when null is possible |
| 1.4 | [ ] `(!)` non-null assertion only with proven invariant? | NOT on uncontrolled input |
| 1.5 | [ ] Array access with length check? | `token[1]` only after `token.length >= 2` |
| 1.6 | [ ] HashMap `.get()` return checked for null? | Or `.has_key()` beforehand |

**Typical error sites:**
```vala
// CHECK: Is the return value nullable here?
var item = list.get(index);        // -> can be null?
var attr = node.get_attribute(x);  // -> ALWAYS nullable!
var row = table.row_with(id);      // -> may not exist!
```

---

## 2. Signal Handling (5+ leaks in audit)

| # | Check | Details |
|---|-------|---------|
| 2.1 | [ ] Every `connect()` has a `disconnect()` counterpart? | Especially for dynamic widgets |
| 2.2 | [ ] Signal handler ID stored when disconnect is needed? | `ulong id = obj.signal.connect(...)` |
| 2.3 | [ ] `dispose()` / destructor cleans up handlers? | GTK widgets MUST disconnect in dispose() |
| 2.4 | [ ] `notify[...]` on the correct object? | Bug #116: `button.notify` instead of `this.notify` |
| 2.5 | [ ] No lambdas capturing `this` without lifecycle control? | Leads to invisible reference holding |

---

## 3. Database (6 bugs + 5 performance findings)

| # | Check | Details |
|---|-------|---------|
| 3.1 | [ ] Parameterized queries instead of string concatenation? | Use `.with()`, never `@"... $var ..."` |
| 3.2 | [ ] `LIMIT` on potentially large SELECT results? | Without LIMIT a query can load thousands of rows |
| 3.3 | [ ] Index for every new WHERE / ORDER BY column? | In `Table` constructor: `index("name", {column})` |
| 3.4 | [ ] `changes()` instead of extra `COUNT(*)` when only count matters? | First DELETE, then `db.changes()` |
| 3.5 | [ ] Migration robust? `error()` on failure? | Not `warning()` — DB corruption is fatal |
| 3.6 | [ ] New table with correct column types? | `Column.Integer` vs `Column.Long` vs `Column.BoolInt` |

---

## 4. Error Handling

| # | Check | Details |
|---|-------|---------|
| 4.1 | [ ] No empty `catch` block (except documented cleanup)? | At least `warning()` or `// cleanup, ignore` |
| 4.2 | [ ] `throws` declared and documented correctly? | Callers must know what can be thrown |
| 4.3 | [ ] Error severity appropriate? | `error()` only for fatal, `warning()` for handled |
| 4.4 | [ ] Error message includes context? | `"Failed to parse X: %s"` not just `"%s"` |
| 4.5 | [ ] Return value after failed operation sensible? | `return null` / `return false` / `throw` |

---

## 5. UI / GTK4

| # | Check | Details |
|---|-------|---------|
| 5.1 | [ ] `[GtkChild]` declared as `unowned`? | Template owns the reference |
| 5.2 | [ ] No blocking operations on main thread? | File I/O, crypto, network must be async |
| 5.3 | [ ] Division by zero protected? | `if (size > 0)` before division |
| 5.4 | [ ] Integer division considered? | `150/100 == 1` in Vala! Multiply instead of divide |
| 5.5 | [ ] Widget cleanup on removal? | `container.remove(widget)` when no longer needed |
| 5.6 | [ ] Loop optimization? | `break` after find, don't keep iterating (Bug P6) |
| 5.7 | [ ] User-visible strings translatable? | Use `_("text")` macro |

---

## 6. XMPP Protocol

| # | Check | Details |
|---|-------|---------|
| 6.1 | [ ] Sender validation on IQ responses? | Check against expected sender |
| 6.2 | [ ] uint32 for OMEMO device IDs? | Not int (overflow when > INT_MAX) |
| 6.3 | [ ] Namespace constant instead of hardcoded string? | Use `NS_URI` |
| 6.4 | [ ] Robust against missing mandatory attributes? | Spec-MANDATORY != implementation-GUARANTEED |
| 6.5 | [ ] `write_async()` instead of `write()` for stanza sending? | `write()` is deprecated and swallows errors |
| 6.6 | [ ] STARTTLS rejection leads to connection abort? | Never proceed with TLS upgrade anyway |

---

## 7. Security

| # | Check | Details |
|---|-------|---------|
| 7.1 | [ ] No secrets in logs? | Passwords, tokens, keys must not be logged |
| 7.2 | [ ] No string concatenation in SQL? | Always parameterized |
| 7.3 | [ ] No path traversal possible? | Check for `..` and absolute paths |
| 7.4 | [ ] URL scheme whitelisted? | Only open http(s), xmpp: |
| 7.5 | [ ] File size checked before processing? | Against DoS via huge files |
| 7.6 | [ ] Crypto: Only established libraries? | No custom crypto |
| 7.7 | [ ] Constant-time comparisons for secrets? | Not `==` for tokens/keys |

---

## 8. Performance

| # | Check | Details |
|---|-------|---------|
| 8.1 | [ ] No N+1 query pattern? | Don't load individually in a loop |
| 8.2 | [ ] Cache lookup O(1) instead of O(n)? | HashMap instead of linear search |
| 8.3 | [ ] Cache has eviction strategy? | LRU, time-based, or purge call |
| 8.4 | [ ] No unnecessary object creation in hot path? | Especially in render loops |
| 8.5 | [ ] DB index for new query? | Test with `explain query plan` if in doubt |
| 8.6 | [ ] Async for I/O > 16 ms? | File, network, crypto |

---

## 9. Tests

| # | Check | Details |
|---|-------|---------|
| 9.1 | [ ] New code has tests? | At least for happy path + one edge case |
| 9.2 | [ ] Every test has at least one assertion? | Test without assertion always passes (Bug #132) |
| 9.3 | [ ] Correct variables in assertions? | Not `alice_message` when `bob_message` is meant (Bug #131) |
| 9.4 | [ ] Tests are locale-independent? | No parsing of localized output (Bug #128) |
| 9.5 | [ ] Edge cases tested? | null, empty string, 0, MAX_VALUE, negative |

---

## 10. Code Quality

| # | Check | Details |
|---|-------|---------|
| 10.1 | [ ] Method under 60 lines? | Otherwise split |
| 10.2 | [ ] Maximum 5 parameters? | Otherwise use an object |
| 10.3 | [ ] No copy-paste duplicates? | Extract common logic |
| 10.4 | [ ] Naming consistent? | PascalCase classes, snake_case methods |
| 10.5 | [ ] Dead code removed? | Commented-out code, unreachable branches |
| 10.6 | [ ] 4-space indentation? | No tabs |

---

## Review Result

| Result | Meaning |
|--------|---------|
| **Approved** | All checks passed, ready to merge |
| **Changes Requested** | Specific defects identified, must be fixed before merge |
| **Needs Discussion** | Architecture / design questions that need team discussion |

### Comment Template for Found Issues:
```
**[Severity: Critical/High/Medium/Low]**
File: `path/file.vala:Line`
Category: (Nullability / Signal / DB / Security / Performance / ...)
Problem: (What is wrong)
Fix: (Suggested solution)
```
