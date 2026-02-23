# DinoX — Testing Guide

Complete inventory of all automated tests in the DinoX project.

---

## Quick Start

```bash
# Run all meson-registered tests (xmpp-vala + omemo)
ninja -C build test

# Run DB maintenance bash CLI tests
./scripts/test_db_maintenance.sh

# Run DB maintenance Vala integration tests (UI-flow)
./scripts/run_db_integration_tests.sh
```

---

## 1. Meson-Registered Tests

These are compiled and run via `ninja -C build test` (or `meson test -C build`).

### 1.1 xmpp-vala (`xmpp-vala/tests/`)

**Meson target:** `xmpp-vala-test`  
**Registration:** `xmpp-vala/meson.build` line 186  
**Framework:** GLib.Test via custom `Gee.TestCase` base class  

| Suite        | File              | Tests |
|--------------|-------------------|-------|
| StanzaTest   | `stanza.vala`     | Stanza parsing, building, namespace handling |
| UtilTest     | `util.vala`       | Utility functions |
| JidTest      | `jid.vala`        | JID parsing, components, resource handling |
| ColorTest    | `color.vala`      | XEP-0392 consistent color generation |
| VCard4Test   | `vcard4.vala`     | vCard4 XML parsing |
| Xep0448Test  | `xep_0448.vala`   | XEP-0448 encryption element parsing |

**Files:**
- `common.vala` — main(), registers all 6 suites
- `testcase.vala` — `Gee.TestCase` base class (set_up/tear_down hooks)

**Run individually:**
```bash
./build/xmpp-vala/xmpp-vala-test
```

### 1.2 OMEMO (`plugins/omemo/tests/native/`)

**Meson target:** `omemo-test`  
**Registration:** `plugins/omemo/meson.build` line 96  
**Framework:** GLib.Test via custom `Gee.TestCase` base class  

| Suite              | File                    | Tests |
|--------------------|-------------------------|-------|
| Curve25519         | `curve25519.vala`       | Key agreement, signature verification |
| SessionBuilderTest | `session_builder.vala`  | Double Ratchet session setup and messaging |
| HKDF               | `hkdf.vala`             | HMAC-based key derivation |

**Files:**
- `common.vala` — main(), registers all 3 suites
- `testcase.vala` — `Gee.TestCase` base class

**Run individually:**
```bash
./build/plugins/omemo/omemo-test
```

### 1.3 libdino (`libdino/tests/`)

> **⚠ NOT registered in meson.** These test files exist but `libdino/meson.build`
> does not compile or register them.  They are NOT run by `ninja test`.

| File               | Content |
|--------------------|---------|
| `common.vala`      | main() — only registers `WeakMapTest` |
| `weak_map.vala`    | `WeakMapTest` — 5 tests: set, set2, set3, unset, remove_when_out_of_scope |
| `jid.vala`         | `JidTest` — 3 tests: parse, components, with_res — **not registered** in common.vala |
| `file_manager.vala`| `FileManagerTest` — **not registered** in common.vala |
| `testcase.vala`    | `Gee.TestCase` base class |

These tests would need to be added to `libdino/meson.build` to be compiled and run.

---

## 2. DB Maintenance Tests (DinoX-specific)

### 2.1 Bash CLI Tests (`scripts/test_db_maintenance.sh`)

**Purpose:** Tests sqlcipher database operations via CLI commands.  
**Result:** 71 PASS, 0 FAIL  
**Commit:** `9c8bb799`  

| Suite | Tests |
|-------|-------|
| Suite 1: Basic sqlcipher | DB creation, key setting, table creation, data insertion |
| Suite 2: Rekey | Password change, old key rejection, new key verification |
| Suite 3: Multi-DB rekey | All 4 databases (dino, pgp, bot_registry, omemo) rekeyed |
| Suite 4: WAL checkpoint | PRAGMA wal_checkpoint(TRUNCATE) on all DBs |
| Suite 5: Reset (unlink) | File deletion for all DBs + WAL/SHM + omemo.key + omemo/ dir |

**Prerequisites:** `sqlcipher` command available in PATH.

**Run:**
```bash
./scripts/test_db_maintenance.sh
```

### 2.2 Vala Integration Tests (`tests/test_db_maintenance_integration.vala`)

**Purpose:** Tests the **actual Qlite.Database code paths** that the UI functions in
`application.vala` use.  Proves that Change Password, Reset Database, and
Backup/Checkpoint work correctly at the library level.  
**Result:** 65 PASS, 0 FAIL, 0 warnings  
**Commit:** `ab0550f8`  

| Suite | Tests | Description |
|-------|-------|-------------|
| Suite 1: Change Password (20) | Validation (wrong old pw, empty, whitespace, mismatch), db.rekey(), plugin rekey chain, all 4 DBs verified, old key rejection | Replicates `application.vala` lines 1140-1181 |
| Suite 2: Reset Database (8) | FileUtils.unlink for all DBs/WAL/SHM + omemo.key + omemo/ dir | Replicates `application.vala` lines 1804-1853 |
| Suite 3: Backup Checkpoint (10) | PRAGMA wal_checkpoint(TRUNCATE) on all 4 DBs, WAL shrinkage verified | Replicates `application.vala` lines 2102-2113 |
| Suite 4: E2E Flow (11) | Change PW → Checkpoint → Verify round-trip | Full end-to-end scenario |
| Suite 5: Edge Cases (9) | SQL injection keys, 1000-char passwords, Unicode/emoji, WAL after rekey, rapid rekeys, missing file unlink, same-pw rekey | Robustness tests |
| Suite 6: Plugin Null-Safety (7) | if(db!=null) guards for openpgp, bot-features, omemo; plugin_loader null checks | Plugin safety verification |

**Build & Run:**
```bash
./scripts/run_db_integration_tests.sh
```

**Manual build:**
```bash
valac --pkg gio-2.0 --pkg gee-0.8 --pkg sqlite3 \
      --vapidir=qlite/vapi --pkg qlite \
      -X -I./qlite/src -X -L./build/qlite -X -lqlite \
      -X -w \
      tests/test_db_maintenance_integration.vala \
      -o build/test_db_maintenance_integration

LD_LIBRARY_PATH=build/qlite ./build/test_db_maintenance_integration
```

---

## 3. Ad-Hoc / Development Tests (Root Directory)

These are standalone one-off test scripts, not wired into any test runner.

| File                 | Language | Purpose |
|----------------------|----------|---------|
| `test_cb.vala`       | Vala     | TLS channel binding type test |
| `test_omemo_deser.c` | C        | OMEMO deserialization with Kaidan key-exchange bytes |
| `test_socks.py`      | Python   | SOCKS5 proxy connectivity test |

These are useful for manual debugging but not part of automated CI.

---

## 4. Other Test-Related Scripts

| File | Purpose |
|------|---------|
| `check_translations.py` | Validates translation file completeness |
| `scripts/analyze_translations.py` | Detailed translation analysis |
| `scripts/scan_unicode.py` | Scans for problematic Unicode characters |

---

## 5. Test Architecture Overview

```
ninja test                             meson-registered
  ├── xmpp-vala-test                   6 suites (GLib.Test)
  └── omemo-test                       3 suites (GLib.Test)

./scripts/test_db_maintenance.sh       bash CLI, 71 tests
./scripts/run_db_integration_tests.sh  Vala, 65 tests (Qlite)

libdino/tests/                         ⚠ exists but NOT in meson
root: test_cb.vala, test_omemo_deser.c, test_socks.py   ad-hoc
```

### Databases Covered by DB Maintenance Tests

All four encrypted databases are tested:

| Database         | Key Source          | Rekey | Reset | Checkpoint |
|------------------|---------------------|-------|-------|------------|
| `dino.db`        | User password       | ✅    | ✅    | ✅         |
| `pgp.db`         | User password       | ✅    | ✅    | ✅         |
| `bot_registry.db`| User password       | ✅    | ✅    | ✅         |
| `omemo.db`       | GNOME Keyring key   | ✅    | ✅    | ✅         |

---

## 6. Running All Tests

```bash
#!/bin/bash
echo "=== Meson Tests ==="
ninja -C build test

echo ""
echo "=== DB Maintenance CLI Tests ==="
./scripts/test_db_maintenance.sh

echo ""
echo "=== DB Maintenance Integration Tests ==="
./scripts/run_db_integration_tests.sh
```

---

## 7. Writing New Tests

### GLib.Test / Gee.TestCase (for xmpp-vala, omemo, libdino)

```vala
class MyTest : Gee.TestCase {
    public MyTest() {
        base("MyTest");
        add_test("test_something", test_something);
    }

    void test_something() {
        assert_true(1 + 1 == 2);
    }
}
```

Register in the corresponding `common.vala`:
```vala
GLib.Test.init(ref args);
TestSuite.get_root().add_suite(new MyTest().get_suite());
GLib.Test.run();
```

### DB Maintenance Style (standalone Vala)

```vala
static int PASS = 0;
static int FAIL = 0;

void ok(bool condition, string description) {
    if (condition) { PASS++; stdout.printf("  PASS: %s\n", description); }
    else           { FAIL++; stdout.printf("  FAIL: %s\n", description); }
}
```

---

*Last updated: v1.1.2.6 (commits 9c8bb799, ab0550f8)*
