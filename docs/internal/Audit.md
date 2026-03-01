# DinoX Code Audit Plan

> **Status:** COMPLETED (Phase 9 coding guidelines completed + 3 runtime bugs fixed)
> **Created:** March 1, 2026
> **Completed:** March 1, 2026
> **Goal:** Systematically audit every directory for bugs, security vulnerabilities, clean code, duplicates, and redundant calls.
> **After:** Performance analysis (bottlenecks) ✓ + Coding guidelines ✓ + Runtime bug investigation ✓

---

## Audit Criteria (for each directory)

| # | Category | What to look for |
|---|----------|-----------------|
| 1 | **Bugs** | Null dereference, race conditions, missing error handling, off-by-one, resource leaks (streams, sessions, timers not stopped) |
| 2 | **Security** | Input validation, injection (SQL/XML/shell), crypto misuse, missing TLS checks, hardcoded secrets, path traversal |
| 3 | **Clean Code** | Dead/unreachable lines, unused variables/imports, overly long methods (>80 lines), unclear naming, missing comments on complex logic |
| 4 | **Duplicates** | Copy-paste code, duplicate functionality across files, redundant calls (e.g. double signal connect, double DB query) |
| 5 | **API Misuse** | Wrong GTK/GLib patterns, deprecated API usage, thread unsafety, main loop blocking |
| 6 | **False Positives** | VERIFY every suspicious finding before reporting it as a bug. Read code in context, check callers, respect the type system. No fix without confirming it's a real problem. |
| 7 | **Dead Code** | Unreachable branches, never-called methods, commented-out code, feature flags that are always false |

### Quality Assurance: False Positive Prevention

For every found bug, before applying the fix:
1. **Can the faulty path even be reached?** (caller analysis)
2. **Does the caller already guard against it?** (e.g. null check upstream)
3. **Is the type actually nullable?** (Vala type system, compiler warnings)
4. **Does the fix cause more harm than good?** (performance, readability)

> **False positive rate so far: ~9%** — Of ~70 suspicious cases, ~6 were dismissed (e.g. paths unreachable by caller logic, SVG checks operating on decrypted files).

---

## Why Does the Audit Find So Many Bugs When Tests Are Green?

### Analysis of Test Gaps

| Metric | Value |
|--------|-------|
| Production code | **108,401 lines** (446 .vala files) |
| Test code | **13,932 lines** (62 .vala files) |
| Test ratio | **12.8%** (industry recommendation: 50–100%) |
| Estimated code coverage | **~15–25%** (no coverage tool available for Vala) |

### What Tests Cover (and What They DON'T)

| Area | Tested? | Details |
|------|---------|---------|
| JID parsing | Yes | Valid/invalid JIDs, Unicode, emoji |
| XML stanza roundtrip | Yes | Serialization/deserialization |
| OMEMO crypto primitives | Yes | Curve25519, HKDF, session builder |
| Stream management | Yes | Basic ack, resume |
| MAM (archive) | Yes | Query parsing |
| Color consistency (XEP-0392) | Yes | HSLuv conversion |
| VCard4 | Yes | Parsing |
| **XEP null safety** | **NO** | Not a single test for: "What happens when get_attribute() returns null?" |
| **Malformed server responses** | **NO** | No test for: incomplete stanzas, missing mandatory attributes, empty subnodes |
| **Security edge cases** | **NO** | No test for: IQ spoofing, STARTTLS downgrade, manipulated pubsub events |
| **Duplicates / dead code** | **NO** | Static analysis completely missing |
| **Integration (end-to-end)** | **NO** | No test XMPP server, no message flow test |
| **UI / GTK** | **Minimal** | Only preferences_row_test, no widget tests |

### Why Tests Didn't Catch the 43 Bugs Found

1. **Category "Defensive Null Checks" (30 of 43 bugs)**
   Tests always send **well-formed** stanzas. No test simulates a server sending `<success/>` without a body, or an `<item>` without subnodes. Real-world XMPP servers (ejabberd, prosody, ...) don't always follow spec.

2. **Category "Copy-Paste Bugs" (5 of 43)**
   Tests check whether the function works with correct input. That `generation` is read instead of `id` (Bug #18) only shows up when a candidate has a different generation than id — an extremely rare edge case.

3. **Category "Security" (4 of 43)**
   No test simulates a malicious peer. STARTTLS rejection, IQ spoofing, sender validation — that would require a fuzzer or explicit adversarial tests.

4. **Category "Logic / API" (4 of 43)**
   int vs int64, wrong log message, missing listener cleanup — these are errors only found through manual code inspection.

### Recommendation: Expand Test Suite (Phase 10)

| # | Test Category | Description | Priority |
|---|--------------|-------------|----------|
| 1 | **Malformed stanza tests** | For each XEP: Send stanzas with missing attributes, empty nodes, null content | Critical |
| 2 | **Adversarial tests** | IQ spoofing, STARTTLS downgrade, invalid senders | High |
| 3 | **Null safety tests** | Systematically test `get_attribute()` / `get_subnode()` returns for null | High |
| 4 | **Duplicate detection** | Script to find similar code blocks (simhash etc.) | Medium |
| 5 | **Dead code detection** | Build call graph, find never-referenced public methods | Medium |
| 6 | **Integration tests** | Mock XMPP server with prosody-in-docker, end-to-end message flow | Low (expensive) |

---

## Overview: Directories & Progress

### Legend
- [ ] = Not yet audited
- [~] = In progress
- [x] = Audited, bugs fixed
- [o] = Audited, no issues found

| # | Directory | Files | Priority | Status | Bugs Found |
|---|-----------|-------|----------|--------|------------|
| -- | **Plugins (already done)** | | | | |
| P1 | `plugins/bot-features/` | 19 .vala | High | [x] | See SECURITY_AUDIT.md |
| P2 | `plugins/http-files/` | 7 .vala | High | [x] | See SECURITY_AUDIT.md |
| P3 | `plugins/omemo/` | 39 .vala | Critical | [x] | See SECURITY_AUDIT.md |
| P4 | `plugins/openpgp/` | 15 .vala | High | [x] | See SECURITY_AUDIT.md |
| P5 | `plugins/ice/` | 6 .vala | Medium | [x] | See SECURITY_AUDIT.md |
| P6 | `plugins/rtp/` | 13 .vala | Medium | [x] | See SECURITY_AUDIT.md |
| P7 | `plugins/mqtt/` | 18 .vala | High | [x] | See SECURITY_AUDIT.md |
| P8 | `plugins/notification-sound/` | 2 .vala | Low | [x] | See SECURITY_AUDIT.md |
| P9 | `plugins/tor-manager/` | 7 .vala | Low | [x] | See SECURITY_AUDIT.md |
| -- | **Core Libraries** | | | | |
| 1 | `crypto-vala/src/` | 5 .vala | Critical | [x] | 4 bugs fixed (628ad222) |
| 2 | `qlite/src/` | 10 .vala | Critical | [x] | 3 bugs fixed (3678fa82) |
| 3 | `libdino/src/entity/` | 7 .vala | High | [x] | 4 bugs fixed (c18ac2f2) |
| 4 | `libdino/src/service/` | 41 .vala | Critical | [x] | 21 bugs fixed (575361a6) |
| 5 | `libdino/src/plugin/` | 3 .vala | Medium | [o] | No issues |
| 6 | `libdino/src/dbus/` | 3 .vala | Medium | [o] | No issues |
| 7 | `libdino/src/security/` | 2 .vala | High | [o] | No issues (clean crypto code) |
| 8 | `libdino/src/util/` | 7 .vala | Medium | [x] | 3 bugs fixed (7382210d) |
| -- | **XMPP Protocol** | | | | |
| 9 | `xmpp-vala/src/core/` | 13 .vala | Critical | [x] | 3 bugs fixed |
| 10 | `xmpp-vala/src/module/` (root) | 10 .vala | High | [x] | 2 bugs fixed |
| 11 | `xmpp-vala/src/module/xep/` (root) | 64 .vala | Critical | [x] | 6 bugs fixed + ~20 documented |
| 12 | `xmpp-vala/src/module/xep/0166_jingle/` | 12 .vala | High | [x] | 1 bug fixed (reason_element) |
| 13 | `xmpp-vala/src/module/xep/0167_jingle_rtp/` | 6 .vala | Medium | [o] | No issues |
| 14 | `xmpp-vala/src/module/xep/0176_jingle_ice_udp/` | 3 .vala | Medium | [o] | No issues |
| 15 | `xmpp-vala/src/module/xep/0384_omemo/` | 4 .vala | Critical | [x] | 3 bugs fixed (1c0667e4) |
| 16 | `xmpp-vala/src/module/xep/` (remaining subdirs) | 13 .vala | Medium | [x] | Co-audited in step 11 |
| 17 | `xmpp-vala/src/module/presence/` | 3 .vala | Medium | [o] | No issues |
| 18 | `xmpp-vala/src/module/iq/` | 2 .vala | Medium | [x] | 1 bug fixed (97001888) |
| 19 | `xmpp-vala/src/module/message/` | 2 .vala | Medium | [o] | No issues |
| 20 | `xmpp-vala/src/module/roster/` | 4 .vala | Medium | [x] | 4 bugs fixed (97001888) |
| -- | **UI / Frontend** | | | | |
| 21 | `main/src/ui/` (root) | 18 .vala | High | [x] | 20 bugs fixed (994c5dce) |
| 22 | `main/src/ui/conversation_content_view/` | 21 .vala | High | [x] | 14 bugs fixed (48e7e867) |
| 23 | `main/src/ui/chat_input/` | 11 .vala | High | [x] | 6 bugs fixed (1cb9c6b0) |
| 24 | `main/src/ui/add_conversation/` | 12 .vala | Medium | [o] | No fixable issues |
| 25 | `main/src/ui/call_window/` | 10 .vala | Medium | [x] | 2 bugs fixed (1cb9c6b0) |
| 26 | `main/src/ui/conversation_titlebar/` | 4 .vala | Medium | [x] | 1 bug fixed (1cb9c6b0) |
| 27 | `main/src/ui/conversation_selector/` | 2 .vala | Medium | [x] | 2 bugs fixed (1cb9c6b0) |
| 28 | `main/src/ui/contact_details/` | 2 .vala | Low | [o] | No issues |
| 29 | `main/src/ui/occupant_menu/` | 3 .vala | Low | [x] | 1 bug fixed (1cb9c6b0) |
| 30 | `main/src/ui/widgets/` | 4 .vala | Low | [x] | 1 bug fixed (1cb9c6b0) |
| 31 | `main/src/ui/util/` | 10 .vala | Medium | [o] | No issues |
| 32 | `main/src/windows/preferences_window/` | 9 .vala | Medium | [x] | 1 bug fixed (1cb9c6b0) |
| 33 | `main/src/view_model/` | 4 .vala | Medium | [x] | 1 bug fixed (1cb9c6b0) |
| -- | **Build / Infrastructure** | | | | |
| 34 | `scripts/` | 16 files | Medium | [x] | 3 bugs fixed (b152a44d) |
| 35 | `meson.build` (all) | 8 files | Low | [x] | 2 bugs fixed (b152a44d) |
| 36 | Root files (check_translations.py, etc.) | ~5 files | Low | [x] | 1 bug fixed (b152a44d) |
| -- | **Tests** | | | | |
| 37 | `tests/` + `*/tests/` | ~15 .vala | Medium | [x] | 3 bugs fixed (b152a44d) |

**Total: 37 audit units — ALL COMPLETED** (133 bugs in tracker + 26 plugin + 5 systray = **164 bugs found and fixed**)

**Post-Audit Runtime Investigation:** 3 additional bugs found via debug log analysis (#134–#136), total **167 bugs**.

---

## Recommended Order

The order is prioritized by **risk × impact**:

### Phase 1: Cryptography & Data Storage (Critical)
> Errors here = data loss or security vulnerability

| Step | Directory | Why first |
|------|-----------|----------|
| 1 | `crypto-vala/src/` (5 files) | Crypto primitives, one mistake = everything insecure |
| 2 | `qlite/src/` (10 files) | SQL abstraction layer, injection risk, data loss |
| 3 | `xmpp-vala/src/module/xep/0384_omemo/` (4 files) | OMEMO protocol at XMPP level |

### Phase 2: XMPP Core (Critical)
> Errors here = connection problems, authentication vulnerabilities

| Step | Directory | Why |
|------|-----------|-----|
| 4 | `xmpp-vala/src/core/` (13 files) | XML parser, stanza handling, TLS/SASL |
| 5 | `xmpp-vala/src/module/` root (10 files) | Base modules |
| 6 | `xmpp-vala/src/module/xep/` root (64 files) | All XEP implementations — largest block |

### Phase 3: Core Services (Critical/High)
> Errors here = business logic bugs, data corruption

| Step | Directory | Why |
|------|-----------|-----|
| 7 | `libdino/src/entity/` (7 files) | Data model (Account, Message, Conversation) |
| 8 | `libdino/src/service/` (41 files) | Main logic — largest single directory! |
| 9 | `libdino/src/security/` (2 files) | TLS pinning, certificate validation |

### Phase 4: UI / Frontend (High)
> Errors here = crashes, rendering bugs, XSS in message display

| Step | Directory | Why |
|------|-----------|-----|
| 10 | `main/src/ui/` root (18 files) | Application, main window, routing |
| 11 | `main/src/ui/conversation_content_view/` (21 files) | Message display — XSS/injection risk |
| 12 | `main/src/ui/chat_input/` (11 files) | Input handling, markup, encryption selection |
| 13 | `main/src/ui/add_conversation/` (12 files) | JID validation, MUC joining |
| 14 | `main/src/ui/call_window/` (10 files) | VoIP UI, media controls |

### Phase 5: Remaining UI & ViewModels (Medium)

| Step | Directory |
|------|-----------|
| 15 | `main/src/ui/util/` (10 files) |
| 16 | `main/src/windows/preferences_window/` (9 files) |
| 17 | `main/src/view_model/` (4 files) |
| 18 | `main/src/ui/conversation_titlebar/` (4 files) |
| 19 | `main/src/ui/conversation_selector/` (2 files) |
| 20 | `main/src/ui/contact_details/` + `occupant_menu/` + `widgets/` (9 files) |

### Phase 6: Remaining XMPP Modules (Medium)

| Step | Directory |
|------|-----------|
| 21 | `xmpp-vala/src/module/xep/0166_jingle/` (12 files) |
| 22 | `xmpp-vala/src/module/xep/0167_jingle_rtp/` (6 files) |
| 23 | `xmpp-vala/src/module/xep/` remaining subdirs (13 files) |
| 24 | `xmpp-vala/src/module/presence/` + `iq/` + `message/` + `roster/` (11 files) |

### Phase 7: Infrastructure & Helper Code (Medium/Low)

| Step | Directory |
|------|-----------|
| 25 | `libdino/src/plugin/` (3 files) |
| 26 | `libdino/src/dbus/` (3 files) |
| 27 | `libdino/src/util/` (7 files) |
| 28 | `scripts/` (16 files) |
| 29 | `meson.build` files (all 8) |
| 30 | Root files + `tests/` |

---

## Phase 8: Performance Analysis (after the code audit)

> **Status:** COMPLETED (4edd36dc)
> **Result:** 24 performance findings identified, 7 safe high-impact fixes applied

| # | Task | Description |
|---|------|-------------|
| 1 | **Startup profiling** | Measure app start, identify slow modules |
| 2 | **DB query analysis** | Slow/frequent SQL queries, missing indexes |
| 3 | **Memory usage** | Leaks, unnecessary caches, large object trees |
| 4 | **Network efficiency** | Redundant XMPP stanzas, polling vs. push |
| 5 | **UI rendering** | Frame drops, unnecessary redraws, widget recycling |
| 6 | **Filesystem I/O** | Unnecessary read/write cycles, cache strategy |

### Applied Fixes (Commit 4edd36dc)

| # | File | Severity | Description | Fix |
|---|------|----------|-------------|-----|
| P1 | qlite/src/database.vala | **High** | WAL journal_mode set after migration — first migration without WAL | PRAGMA WAL + synchronous=NORMAL BEFORE start_migration() |
| P2 | libdino/src/service/database.vala | **High** | body_meta.message_id without index — every message lookup full table scan | `index("body_meta_message_id_idx", {message_id})` |
| P3 | libdino/src/service/database.vala | **Medium** | file_transfer.info without index | `index("file_transfer_info_idx", {info})` |
| P4 | libdino/src/service/database.vala | **Low** | undecrypted.message_id without index | `index("undecrypted_message_id_idx", {message_id})` |
| P5 | libdino/src/service/database.vala | **Medium** | purge_caches: 9× COUNT(*) before/after DELETE — double query | `changes()` after DELETE instead of separate COUNT |
| P6 | main/src/ui/.../conversation_view.vala | **High** | update_highlight scans all items on mouse movement instead of breaking after match | `break` after match in second foreach |
| P7 | libdino/src/service/conversation_manager.vala | **High** | get_conversation_by_id: O(n) triple-nested loop | HashMap lookup O(1) with conversations_by_id |

### Identified but Deferred (too invasive for this phase)

| # | Area | Severity | Description | Recommended Fix |
|---|------|----------|-------------|----------------|
| D1 | Startup | Medium | GStreamer init blocks main thread 200–500 ms | Idle.add() or background thread |
| D2 | Startup | Medium | /tmp enumeration on every start | Lazy/targeted cleanup |
| D3 | DB | **High** | Sidebar N+1: Last message per conversation loaded individually | JOIN refactor in one query |
| D4 | DB | **High** | content_item N+1: Each message fetched individually | JOIN refactor |
| D5 | DB | **High** | get_items_older_than without LIMIT — unbounded result set | Introduce LIMIT parameter |
| D6 | Memory | **High** | Tile model signal handlers never disconnected — gradual leak | dispose() with handler IDs |
| D7 | Memory | Medium | Conversation view widgets accumulate without limit | Eviction/recycling |
| D8 | Memory | Medium | mam_times HashMap grows unbounded | Cleanup on disconnect |
| D9 | Memory | Low | entity_caps unbounded | LRU cache |
| D10 | I/O | **High** | Avatar loading: synchronous file I/O on main thread | async I/O |
| D11 | I/O | **High** | Video decryption blocks main thread | Background thread |
| D12 | I/O | Medium | Thumbnail parsing synchronous | async |
| D13 | UI | Medium | Builder XML re-parsed per message skeleton | Template/composite widget |
| D14 | UI | Low | Selector row signal leak | disconnect in dispose() |
| D15 | I/O | Low | Avatar preload N+1 | JOIN or lazy loading |

## Phase 9: Coding Guidelines

> **Status:** COMPLETED
> **Result:** 3 documents created based on all 164 audit findings + 24 performance findings

| # | Document | Content | Status |
|---|----------|---------|--------|
| 1 | **CODING_GUIDELINES.md** | Naming conventions, file structure, max method length, error handling, DB patterns, GTK4 rules, async/threading, top 10 mistakes from audit | [x] |
| 2 | **SECURITY_GUIDELINES.md** | Input validation, crypto do's & don'ts, TLS rules, SQL parameters, path traversal, logging security, build hardening, plugin isolation | [x] |
| 3 | **REVIEW_CHECKLIST.md** | 50+ check items: nullability, signals, dispose, DB, error handling, UI, XMPP, security, performance, tests, code quality | [x] |

All documents are in `docs/internal/` (in .gitignore).

## Post-Audit: Runtime Bug Investigation

> **Status:** COMPLETED (2da94da3)
> **Trigger:** SIGSEGV crash when right-clicking a contact in the sidebar
> **Method:** Debug log capture with `G_MESSAGES_DEBUG=all`, analysis of 25,000+ lines of runtime output
> **Result:** 3 real bugs found and fixed, 3 expected behaviors documented

| Finding | Severity | Description | Disposition |
|---------|----------|-------------|-------------|
| Popover crash | **Critical** | PopoverMenu parented to row; row removed while popover open → `gdk_surface_request_motion` SIGSEGV | Fixed (#134) |
| libsoup session | **Medium** | New `Soup.Session` per HTTP request → GC'd with active connections → warning | Fixed (#135) |
| Tooltip spam | **Low** | `generate_groupchat_tooltip()` rebuilds entire widget tree on every mouse pixel | Fixed (#136) |
| OpenPGP signed_status NULL | Info | Expected async key setup timing | No action needed |
| OMEMO SG_ERR_DUPLICATE | Info | Expected MAM duplicate + session repair | No action needed |
| DTLS peer nulls | Info | Expected for outgoing calls before transport-accept | No action needed |

---

## Bug Tracker (populated during each directory audit)

| # | Directory | File:Line | Severity | Description | Fix | Status |
|---|-----------|-----------|----------|-------------|-----|--------|
| 1 | crypto-vala | srtp.vala:89 | Medium | create_policy() only AES_CM_128_HMAC_SHA1_80, AES_CM_128_HMAC_SHA1_32 missing | Added + default fallback | [x] |
| 2 | crypto-vala | srtp.vala:137 | Medium | set_decryption_key() ignores add_stream() error | Check return value + warning | [x] |
| 3 | crypto-vala | srtp.vala:44,72 | Low | decrypt_rtp/rtcp unnecessary double copy | buf.length = buf_use instead of new buffer | [x] |
| 4 | crypto-vala | cipher.vala:37 | Low | mode_from_string() missing CCM (present in mode_to_string) | Added CCM case | [x] |
| 5 | qlite | row.vala:104 | High | RowIterator() binds SQL text instead of args[i], index 0-based instead of 1-based | args[i] + i+1 | [x] |
| 6 | qlite | database.vala:156 | Medium | close() was empty no-op, DB handle never released | Set db = null | [x] |
| 7 | qlite | database.vala:349 | Low | is_known_column() ignores table parameter | Check t.name == table | [x] |
| 8 | xmpp-vala/omemo | omemo_decryptor.vala:44 | Medium | get_attribute_int("rid") for uint32 device ID; values > INT_MAX → -1 → own key never found | get_attribute_uint("rid") | [x] |
| 9 | xmpp-vala/omemo | omemo2_decryptor.vala:71,76 | Medium | Same int/uint32 mismatch + explicit (int) cast would overflow for IDs > INT_MAX | get_attribute_uint + removed cast | [x] |
| 10 | xmpp-vala/omemo | omemo_encryptor.vala:111 | Low | EncryptState.to_string() bracket error: other=( never closed, own=( appears embedded | Fixed brackets | [x] |
| -- | **Phase 2: XMPP Core** | | | | | |
| 11 | xmpp-vala/core | starttls_xmpp_stream.vala:64 | Medium (Security) | STARTTLS rejection not enforced: server doesn't respond with `<proceed/>`, code still does TLS upgrade | throw IOError instead of just warning | [x] |
| 12 | xmpp-vala/core | starttls_xmpp_stream.vala:62 | Low | Deprecated fire-and-forget `write()` for STARTTLS request, write errors swallowed | `yield write_async()` | [x] |
| 13 | xmpp-vala/core | stanza_node.vala:28-38 | Low | Empty XML character references (`&#;`, `&#x;`) produce invalid unichar (-1 = 0xFFFFFFFF) | U+FFFD default + `num.validate()` | [x] |
| 14 | xmpp-vala/module | sasl.vala:280 | Medium | SCRAM `<success/>` without text content: `get_string_content()` null → `Base64.decode(null)` → crash | Null check before Base64 | [x] |
| 15 | xmpp-vala/module | sasl.vala:309 | Low | No null check on `get_subnode("mechanisms")`: Features without `<mechanisms>` → crash | `if (mechanisms == null) return` | [x] |
| 16 | xmpp-vala/xep | 0249:43 (detach) | Medium | `detach()` calls `.connect()` instead of `.disconnect()` → signal handler leak, double execution | `.disconnect()` | [x] |
| 17 | xmpp-vala/xep | 0166/reason_element:11-12 | Medium | `failed_application`/`failed_transport` with underscore instead of hyphen → XEP-0166 mismatch | Dashes instead of underscores | [x] |
| 18 | xmpp-vala/xep | 0177:72 (raw_udp) | Medium | Copy-paste bug: `candidate.id = get_attribute("generation")` instead of `"id"` | `"id"` | [x] |
| 19 | xmpp-vala/xep | 0045/flag:17 | Medium | HashMap hash/equals violation: `hash_func` (full) with `equals_bare_func` → MUC occupant lookup unreliable | `equals_func` (full) | [x] |
| 20 | xmpp-vala/xep | 0198:123 (require) | Low | Copy-paste: `require()` creates `PrivateXmlStorage.Module()` instead of SM module | `new Module()` | [x] |
| 21 | xmpp-vala/xep | 0198:167 (resumed) | Medium | Null deref: `get_attribute("h")` null on broken `<resumed/>` → `uint64.parse(null)` crash | Null check like "failed" | [x] |
| -- | **Phase 2 Backlog (XEP)** | | | | | |
| 22 | xmpp-vala/xep | 0198:83 | **Critical** | `cancellable.set_error_if_cancelled()` on nullable Cancellable → NPE on default call | `if (cancellable != null)` guard | [x] |
| 23 | xmpp-vala/xep | 0191:69 | Medium (Security) | `on_iq_set` doesn't validate IQ sender → remote can spoof block/unblock push | Check sender == own bare JID | [x] |
| 24 | xmpp-vala/xep | 0060:42 | Low | `remove_filtered_notification()` forgets `delete_listeners.unset(node)` → leak | Added `.unset()` | [x] |
| 25 | xmpp-vala/xep | 0060:110,277 | Medium | `sub_nodes[0]` without empty check → IndexError on empty item node | `sub_nodes.size > 0` guard | [x] |
| 26 | xmpp-vala/xep | 0030/info_result:11,27 | Medium | `get_subnode("query")` null → NPE in features/identities getters | Null check + return empty list | [x] |
| 27 | xmpp-vala/xep | 0048:15 | Medium | `get_subnode("storage").get_subnodes()` chain NPE | Null check on storage_node | [x] |
| 28 | xmpp-vala/xep | 0048:51,57,68 | Medium | `get_conferences()` nullable return without check → NPE in add/replace/remove | Null guard + empty set fallback | [x] |
| 29 | xmpp-vala/xep | 0004:89 | Medium | `get_subnode("value").get_string_content()` NPE in `get_options()` | Null check + continue | [x] |
| 30 | xmpp-vala/xep | 0084:67 | Medium | `node.get_subnodes()` on nullable StanzaNode without check | `if (node == null) return` | [x] |
| 31 | xmpp-vala/xep | 0184:42 | Medium | `get_attribute("id", NS_URI)` null passed to receipt_received signal | Null check + guard | [x] |
| 32 | xmpp-vala/xep | 0402:24 | Medium | `item_node.sub_nodes[0]` without empty check → IndexError | `sub_nodes.size == 0` guard | [x] |
| 33 | xmpp-vala/xep | 0402:80 | Medium | `parse_item_node(node, id)` on nullable node + non-nullable assignment | Added null checks | [x] |
| 34 | xmpp-vala/xep | 0353:71,82,87,90 | Medium | `get_attribute("id")` null passed to JMI signal emissions | Null check per case branch | [x] |
| 35 | xmpp-vala/xep | 0363:192 | Medium | `get_subnode("value")` null → NPE in extract_max_file_size | `if (value_node != null)` guard | [x] |
| 36 | xmpp-vala/xep | 0272:248 | Medium | `calls[muc_jid].our_nick` NPE when call not registered | `GroupCall? call` + null check | [x] |
| 37 | xmpp-vala/xep | 0421:39 | Medium | `int.parse(get_attribute("code"))` NPE on missing code attribute | Null check on code | [x] |
| 38 | xmpp-vala/xep | 0231:40,63 | Medium | `Base64.decode(get_string_content())` with null content → undefined | Null check on content | [x] |
| 39 | xmpp-vala/xep | 0264:44 | Medium | `get_data_for_uri()` nullable return → NPE downstream | `if (data == null) return null` | [x] |
| 40 | xmpp-vala/xep | 0298:49 | Medium | `substring(4)` without "xmpp:" prefix check → JID truncation | `has_prefix("xmpp:") ? substring(5) : jid_string` | [x] |
| 41 | xmpp-vala/xep | 0234:111 | Low | Log message "not null" instead of "is null" (inverted) | Corrected text | [x] |
| 42 | xmpp-vala/xep | 0373:302 | Medium | `(string) key_bytes` without NUL terminator → buffer over-read | `key_bytes += 0` before cast | [x] |
| 43 | xmpp-vala/xep | 0446:101 | Low | `int.parse()` for int64 length field → truncation > 2 GB | `int64.parse()` | [x] |
| -- | **Phase 3: Core Services** | | | | | |
| 44 | libdino/entity | file_transfer.vala:247 | Low (Duplicate) | `path` set twice in `persist()` (copy-paste) | Removed duplicate statement | [x] |
| 45 | libdino/entity | file_transfer.vala:175 | Medium | `get_data_for_uri()` nullable return directly to non-nullable `thumbnail.data` → NPE | Null check + continue | [x] |
| 46 | libdino/entity | file_transfer.vala:268 | Medium | `thumbnail.data.get_data()` in persist() NPE when thumbnail.data null | `if (thumbnail.data == null) continue` | [x] |
| 47 | libdino/entity | message.vala:338 | Medium | `real_jid.to_string()` in on_update NPE when real_jid set to null | `&& real_jid != null` guard | [x] |
| -- | **Phase 3 Step 8: libdino/src/service/** | | | | | |
| 48 | libdino/service | history_sync.vala:357 | **Critical** | `\|\|` short-circuit: `query_params.start.to_unix()` NPE when start==null | `\|\|` → `(start != null &&)` bracket | [x] |
| 49 | libdino/service | blocking_manager.vala:52,59 | **Critical** | `block()`/`unblock()` null deref on `get_stream()` (no check like `is_blocked`) | `if (stream == null) return` | [x] |
| 50 | libdino/service | occupant_id_store.vala:78 | **Critical** | `muc_jid.resourcepart` (always null for bare JID) instead of `last_nick` in INSERT | Use `last_nick` | [x] |
| 51 | libdino/service | counterpart_interaction_manager.vala:42 | Medium | `add_seconds(-1)` instead of `-60` → typing timeout 1 s instead of 1 min | `add_seconds(-60)` | [x] |
| 52 | libdino/service | jingle_file_transfers.vala:152 | Medium | `get_flag(Presence.Flag.IDENTITY)` null deref in is_upload_available | Null check before `.get_resources()` | [x] |
| 53 | libdino/service | jingle_file_transfers.vala:200-201 | Medium | `get_flag()` null deref in send_file (Presence + Bind) | Null checks + empty list fallback | [x] |
| 54 | libdino/service | chat_interaction.vala:157,165 | Medium | MapIterator pattern: `has_next()+next()` in for loop skips last element | `for (iter.next(); )` pattern | [x] |
| 55 | libdino/service | file_manager.vala:480 | Medium | `file_transfer.direction` read before set → wrong counterpart | Counterpart assignment after direction | [x] |
| 56 | libdino/service | reactions.vala:251 | Medium | Null JID inserted into reaction user list (when occupant ID/JID missing) | `if (jid != null)` guard | [x] |
| 57 | libdino/service | database.vala:884-885 | Medium | Before pagination with id<=0: `message.id < 0` → empty results | `message.time < before` instead of id filter | [x] |
| 58 | libdino/service | database.vala:893+896 | Medium | After pagination: redundant `message.id > id` filter collides with OR condition | Removed redundant filter | [x] |
| 59 | libdino/service | file_transfer_storage.vala:62 | Medium | Non-nullable return `FileTransfer` but returns `null` | → `FileTransfer?` | [x] |
| 60 | libdino/service | stateless_file_sharing.vala:172 | Medium | `return true` inside foreach → only first source_attachment processed | Return moved after foreach | [x] |
| 61 | libdino/service | module_manager.vala:37 | Medium | `module_map[account]` iterated outside lock (race condition) | Iterate local `modules` copy | [x] |
| 62 | libdino/service | message_correction.vala:240 | Low | `i > 0` off-by-one: first message (index 0) never checked | `i >= 0` | [x] |
| 63 | libdino/service | message_storage.vala:81,88 | Low | Nullable `Conversation?` dereferenced without null check | Early return on null | [x] |
| 64 | libdino/service | entity_capabilities_storage.vala:19-28 | Low | `store_features()` doesn't fill cache → duplicate DB inserts possible | `features_cache[entity] = features` | [x] |
| 65 | libdino/service | util.vala:46 | Low | Case-sensitive MIME comparison after case-insensitive SVG check | Additionally compare lowercase | [x] |
| 66 | libdino/service | content_item_store.vala:390 | Low | `compare_func` never returns 0 → TreeSet contract violated | `a.id == b.id ? 0 : ...` | [x] |
| 67 | libdino/service | call_peer_state.vala:453 | Low (Dead Code) | `!call.equals(call)` tautologically false → dead guard | Removed | [x] |
| 68 | libdino/service | conversation_manager.vala:38 | Low (Duplicate) | Double `add_module(this)` in constructor + `start()` | Removed from constructor | [x] |
| -- | **Phase 7: libdino plugin/dbus/util** | | | | | |
| 69 | libdino/util | weak_map.vala:22 | Medium | `key_equal_func` checked twice instead of `key_hash_func` → custom hashes ignored | Check `key_hash_func` | [x] |
| 70 | libdino/util | display_name.vala:93 | Medium | `get_real_jid()` return value discarded → real_jid always null in private MUC rooms | Assignment `real_jid =` | [x] |
| 71 | libdino/util | send_message.vala:39 | Medium | Markup offset per `fallback.length` (bytes) instead of `char_count()` → corruption on non-ASCII | Use `char_count()` | [x] |
| -- | **Phase 6: XMPP Modules (presence/iq/message/roster)** | | | | | |
| 72 | xmpp-vala/iq | module.vala:28 | **Critical** | Nullable `Cancellable?` without null check in `send_iq_async` → NPE | `if (cancellable != null)` guard | [x] |
| 73 | xmpp-vala/roster | module.vala:53 | Medium | `iq.from.equals()` NPE on server roster pushes (no from attribute, RFC 6121 §2.1.6) | `iq.from != null &&` guard | [x] |
| 74 | xmpp-vala/roster | versioning_module.vala:24 | Medium | `detach()` disconnects only 1 of 4 signals → 3 handler leaks | Disconnect all 4 | [x] |
| 75 | xmpp-vala/roster | flag.vala:9 | Medium | `HashMap<Jid, Item>` without hash/equals → roster lookups by identity instead of JID value | `Jid.hash_bare_func, Jid.equals_bare_func` | [x] |
| 76 | xmpp-vala/roster | module.vala:71 | Low | `mutual_subscription` signal on already existing BOTH (inverted condition) | `!= SUBSCRIPTION_BOTH` | [x] |
| 77 | main/src/ui | notifier_gnotifications.vala:196 | **Critical** | `send/withdraw_notification_safe` calls itself → infinite recursion / stack overflow | `GLib.Application.get_default().send/withdraw_notification()` | [x] |
| 78 | main/src/ui | notifier_freedesktop.vala:259 | Medium | `Markup.escape_text(body)` return value discarded → markup injection in voice request | `body = Markup.escape_text(body)` | [x] |
| 79 | main/src/ui | notifier_freedesktop.vala:244 | Medium | Action listener `"deny"` vs button key `"reject"` → MUC invite reject button non-functional | `"reject"` | [x] |
| 80 | main/src/ui | application.vala:738 | Medium | `Uri.unescape_string` returns null on malformed encoding → NPE | Null check + return | [x] |
| 81 | main/src/ui | application.vala:1105,1117 | Medium | Nullable `Call?` as HashMap key without null guard (accept/reject call) | `if (call == null) return` | [x] |
| 82 | main/src/ui | application.vala:1888 | Medium | `perform_reset_database` missing `db.close()` → silent failure on Windows | Added `db.close()` | [x] |
| 83 | main/src/ui | application.vala:2002 | Medium | `perform_factory_reset` missing `db.close()` → data survives reset | Added `db.close()` | [x] |
| 84 | main/src/ui | application.vala:2355 | Medium | Unencrypted temp backup remains in /tmp if OpenSSL throws | `FileUtils.unlink(temp_tar_path)` in catch | [x] |
| 85 | main/src/ui | conversation_view_controller.vala:146 | Medium | Null deref on `conversation` with Ctrl+W without active conversation | `if (conversation == null) return` | [x] |
| 86 | main/src/ui | main_window_controller.vala:34 | Medium | Null deref on `this.conversation` on jump-to-message | `this.conversation == null` check | [x] |
| 87 | main/src/ui | main_window_controller.vala:164 | Medium | Null deref on nullable `conversation` in `select_conversation` | `if (conversation == null) return` | [x] |
| 88 | main/src/ui | global_search.vala:236 | Medium | `substring` length parameter is absolute offset instead of relative → over-read | `mid_end - mid_start` | [x] |
| 89 | main/src/ui | sticker_pack_import_dialog.vala:201 | Medium | `copy_share_uri` uses `account.bare_jid` instead of `source_jid` → broken share link | `source_jid.to_string()` | [x] |
| 90 | main/src/ui | conversation_details.vala:682 | Medium | `scale_simple` dimension can round to 0 with extreme aspect ratios | `int.max(1, ...)` | [x] |
| 91 | main/src/ui | bot_manager_dialog.vala:141 | Medium | JSON injection via unescaped `account_jid` in `set_account_enabled` | `Json.Builder` instead of string interpolation | [x] |
| 92 | main/src/ui | bot_manager_dialog.vala:610 | Medium | Predictable temp file leaks API token in world-readable /tmp | stdin pipe instead of temp file | [x] |
| 93 | main/src/ui | global_search.vala:92,103 | Low | `get_selected_row()` can be null on Tab/Return | Null check | [x] |
| 94 | main/src/ui | main_window.vala:160 | Low | `get_monitor_at_surface` null not checked → crash when headless | `if (monitor == null) return` | [x] |
| 95 | main/src/ui | conversation_details.vala:317 | Low | `GLib.Application` cast null not checked in fallback | `if (app != null)` | [x] |
| 96 | main/src/ui | sticker_pack_import_dialog.vala:195 | Low | `finally spinner.spinning` after `close()/destroy()` → GTK critical | Stop spinner before close | [x] |
| 97 | conversation_content_view | conversation_view.vala:447 | Medium | `populator.close()` passes new instead of old conversation → populators never properly deinitialized | `this.conversation` instead of `conversation` | [x] |
| 98 | conversation_content_view | video_player_widget.vala:870 | **Critical** | Path traversal: unsanitized `file_name` in `Path.build_filename` → attacker writes outside temp | `Path.get_basename()` + sanitization | [x] |
| 99 | conversation_content_view | video_player_widget.vala:873 | **Critical** | Command injection Windows: `file_name` interpolated in cmd.exe | `AppInfo.launch_default_for_uri()` | [x] |
| 100 | conversation_content_view | audio_player_widget.vala:235 | Medium | `scan_waveform` always creates new temp file, loses the one from `setup_pipeline` | Reuse when `temp_play_file != null` | [x] |
| 101 | conversation_content_view | audio_player_widget.vala:425 | Medium | `saved_position` seek blocked by `duration > 0` guard (duration not yet known) | Removed guard | [x] |
| 103 | conversation_content_view | quote_widget.vala:63 | Low | `base.dispose()` called before child cleanup (wrong order) | Swapped order | [x] |
| 104 | conversation_content_view | file_widget.vala:205 | **Critical** | Same cmd.exe command injection on Windows as #99 | `AppInfo.launch_default_for_uri()` | [x] |
| 105 | conversation_content_view | url_preview_widget.vala:103 | Medium | Empty HTTP body (204) → `bytes.get_data()` null → crash at `.make_valid()` | Size check before access | [x] |
| 106 | conversation_content_view | url_preview_widget.vala:222 | Medium | Byte-length truncation splits multi-byte UTF-8 codepoints | `char_count()` / `index_of_nth_char()` | [x] |
| 107 | conversation_content_view | url_preview_widget.vala:149 | Medium | `scale_simple` dimension can round to 0 → null crash | `int.max(1, ...)` + null check | [x] |
| 108 | conversation_content_view | call_widget.vala:76 | Medium | Nullable `call_manager` without null check on accept/reject buttons | `if (call_manager == null) return` | [x] |
| 109 | conversation_content_view | file_default_widget.vala:82 | Medium | Division by zero on upload with `size==0` | `if (size > 0)` guard | [x] |
| 110 | conversation_content_view | content_populator.vala:51 | Medium | Null items added to list in `populate_latest/before` | Null check like `populate_after` | [x] |
| -- | **Phase 4+5: Remaining UI Directories (Units 23–33)** | | | | | |
| 111 | chat_input | chat_input_controller.vala:231-254 | **Critical** | `/kick`, `/nick`, `/ping`, `/topic` crash on missing argument — `token[1]` without length check | `if (token.length < 2) return` | [x] |
| 112 | chat_input | chat_text_view.vala:167 | Medium | Ctrl+S strikethrough dead — `Key.s` missing from gate array `{Key.i, Key.b}` | Added `Key.s` | [x] |
| 113 | chat_input | occupants_tab_completer.vala:41 | Medium | Tab complete crash on null `conversation` before initialization | `if (conversation == null) return false` | [x] |
| 114 | chat_input | occupants_tab_completer.vala:94 | Medium | Off-by-one `i > 0` skips last content item (index 0) | `i >= 0` | [x] |
| 115 | chat_input | chat_input_controller.vala:261 | Medium | Plugin text command `token[1]` without length check on `/unknown_cmd` | `token.length > 1 ? token[1] : ""` | [x] |
| 116 | call_window | call_encryption_button.vala:18 | Medium | `button.notify["controls-active"]` connects on wrong object — encryption button permanently invisible | `this.notify[...]` | [x] |
| 117 | call_window | call_window.vala:204 | Medium | Integer division `150/100==1` → own video exceeds 150 px at 16:9 | `width * 100 > height * 150` | [x] |
| 118 | conversation_selector | conversation_selector_row.vala:311-313 | Medium | `update_read_pending_force` deleted before read → forced updates lost | Save value before reset | [x] |
| 119 | conversation_selector | conversation_selector.vala:174 | Medium | `loop_conversations` NPE when no row selected | `if (selected == null) return` | [x] |
| 120 | occupant_menu | list.vala:157 | Medium | Filter returns on first word, ignores rest → multi-word search broken | Check all words | [x] |
| 121 | widgets | avatar_picture.vala:337 | Medium | `get_item(-1)` with 0 tiles → null deref when drawing | Null guard + default color | [x] |
| 122 | view_model | conversation_details.vala:67-70 | Medium | MucMemberSorter `index_of(NONE)==-1` sorts before Owner(0) | Fallback to `size` on -1 | [x] |
| 123 | view_model | preferences_dialog.vala:24,30 | **Critical** | `account_details` (HashMap, never null) instead of `account_detail` (lookup result) in null check → NPE | Check `account_detail` | [x] |
| 124 | conversation_titlebar | menu_entry.vala:33 | Low | `conversation.id` in details action without null check on conversation | `if (conversation == null) return` | [x] |
| -- | **Phase 7: Build/Scripts/Tests (Units 34–37)** | | | | | |
| 125 | scripts | ci-build-deps.sh:94-98 | Medium | `set -e` makes Unicode scan error message unreachable (dead code) | `if !` instead of `$?` | [x] |
| 126 | scripts | release_helper.sh:21 | Medium | No version format validation — `sed` breaks on `/` or `&` in `$VERSION` | Regex validation like release.sh | [x] |
| 127 | scripts | release_helper.sh:35 | Medium | Regex error: `(\d+)?` instead of `(\.\d+)?` — 4-part versions not recognized | Added dot | [x] |
| 128 | root | check_translations.py:32-38 | Medium | Locale-dependent: only German `msgfmt` output parsed — always 0 on English | `LC_ALL=C` + English strings + `--output=/dev/null` | [x] |
| 129 | meson | meson.build:4-9 | Medium | C++ hardening flags missing — 2 .cpp files without stack protector/FORTIFY | Added `language: 'cpp'` block | [x] |
| 130 | meson | plugins/tor-manager/meson.build:28 | Medium | Hardcoded install path `'dino'/'plugins'` instead of `get_option('plugindir')` | Like all other plugins | [x] |
| 131 | tests | session_builder.vala:475 | Medium | Copy-paste: `alice_message.type` checked instead of `bob_message.type` | `bob_message.type` | [x] |
| 132 | tests | session_version_guard.vala:148 | Medium | Test has no assertion — always passes regardless of result | `GLib.Test.fail()` in non-throw path | [x] |
| 133 | tests | common.vala:98 (xmpp-vala + libdino) | Low | `nullcheck` expression is tautological contradiction — always false | XOR: `(left == null) != (right == null)` | [x] |
| -- | **Post-Audit: Runtime Bug Investigation** | | | | | |
| 134 | conversation_selector | conversation_selector_row.vala:~640 | **Critical** | PopoverMenu `set_parent(this)` → row removed while popover open → `gdk_surface_request_motion` SIGSEGV. Context menu right-click on contact then "Close Conversation" crashes app. | `dismiss_popover()` before row removal in `colapse()`; track `active_popover` and check identity in `closed` handler (2da94da3) | [x] |
| 135 | conversation_content_view | url_preview_widget.vala:~69,~135 | Medium | New `Soup.Session` created per HTTP request in `UrlPreviewCache.fetch_async()` and `fetch_image()` → session GC'd with active connections → libsoup WARNING on every URL preview fetch | Shared `Soup.Session` field in singleton, initialized in private constructor (2da94da3) | [x] |
| 136 | conversation_selector | conversation_selector_row.vala:~98 | Low | `generate_groupchat_tooltip()` rebuilds entire widget tree on every `query_tooltip` signal (fires per mouse pixel) → 36× redundant calls in a single session | Cache tooltip widget in `cached_groupchat_tooltip`, invalidate only on `subject_set` signal (2da94da3) | [x] |
