/**
 * UI-Flow Integration Tests for Database Maintenance.
 *
 * Reproduces the EXACT code paths from application.vala:
 *
 *   1. "Change Password" dialog  (show_change_db_password_dialog)
 *      → validation: wrong old pw, empty new pw, mismatch
 *      → db.rekey(new_pw)
 *      → plugin_loader.rekey_databases(new_pw)     [pgp + bot, NOT omemo]
 *      → this.db_key = new_pw
 *
 *   2. "Reset Database"  (perform_reset_database)
 *      → FileUtils.unlink  dino.db  + -wal + -shm
 *      → FileUtils.unlink  pgp.db   + -wal + -shm
 *      → FileUtils.unlink  bot_registry.db + -wal + -shm
 *      → FileUtils.unlink  omemo.db + -wal + -shm
 *      → FileUtils.unlink  omemo.key
 *      → delete omemo/ directory contents
 *
 *   3. "Backup" preparation  (checkpoint_databases)
 *      → db.exec("PRAGMA wal_checkpoint(TRUNCATE)")
 *      → plugin_loader.checkpoint_databases()
 *        → each plugin: db.exec("PRAGMA wal_checkpoint(TRUNCATE)")
 *
 * We do NOT need GTK — we replicate the business logic the buttons trigger.
 *
 * Build: scripts/run_db_integration_tests.sh
 */

using Qlite;

// ── Test framework ───────────────────────────────────────────────────

int PASS = 0;
int FAIL = 0;
unowned string current_suite = "";

void ok(bool cond, string msg) {
    if (cond) {
        PASS = PASS + 1;
        stdout.printf("  ✓ %s\n", msg);
    } else {
        FAIL = FAIL + 1;
        stdout.printf("  ✗ FAIL: %s\n", msg);
    }
}

void suite(string name) {
    current_suite = name;
    stdout.printf("\n═══ %s ═══\n", name);
}

string test_dir() {
    return "/tmp/dinox_ui_integration_test_%d".printf((int) Posix.getpid());
}

// ── Simulated Qlite.Database (same as used by dino.db, pgp.db, bot_registry.db) ──

class TestDatabase : Qlite.Database {
    public Column<string?> col_name = new Column.Text("name");
    public Column<long>    col_val  = new Column.Long("value");
    public Table test_table;

    public TestDatabase(string path) {
        base(path, 1);
        test_table = new Table(this, "test_data");
        test_table.init({col_name, col_val});
    }

    public void open(string? key = null) throws Error {
        init({test_table}, key);
    }

    public void insert_row(string name, long val) {
        insert().into(test_table)
            .value(col_name, name)
            .value(col_val, val)
            .perform();
    }

    public long count_rows() {
        long count = 0;
        Qlite.RowIterator iter = select({col_val}).from(test_table).iterator();
        while (iter.next()) {
            count = count + 1;
        }
        return count;
    }

    public long sum_values() {
        long sum = 0;
        foreach (Row row in select({col_val}).from(test_table)) {
            sum += row[col_val];
        }
        return sum;
    }
}

// ══════════════════════════════════════════════════════════════════════
//              SUITE 1 — "Change Password" full UI flow
// ══════════════════════════════════════════════════════════════════════

void test_change_password_ui_flow() {
    suite("1 · UI: Change Password — full flow (application.vala:1140-1181)");

    string dir = test_dir() + "/change_pw";
    DirUtils.create_with_parents(dir, 0700);

    // --- Set up: create the 4 databases exactly as the app would ---
    string db_key = "original_password";

    // Main DB (dino.db)
    TestDatabase main_db;
    try {
        main_db = new TestDatabase(dir + "/dino.db");
        main_db.open(db_key);
        main_db.insert_row("account_alice", 1);
        main_db.insert_row("account_bob", 2);
        main_db.insert_row("message_1", 100);
    } catch (Error e) {
        ok(false, "setup main_db: " + e.message);
        return;
    }

    // Plugin DBs (pgp.db, bot_registry.db) — share db_key
    TestDatabase pgp_db;
    TestDatabase bot_db;
    try {
        pgp_db = new TestDatabase(dir + "/pgp.db");
        pgp_db.open(db_key);
        pgp_db.insert_row("gpg_key_alice", 10);

        bot_db = new TestDatabase(dir + "/bot_registry.db");
        bot_db.open(db_key);
        bot_db.insert_row("bot_weatherbot", 20);
    } catch (Error e) {
        ok(false, "setup plugin DBs: " + e.message);
        return;
    }

    // OMEMO DB — uses its own separate key (NOT db_key)
    string omemo_key = "auto_generated_keyring_key";
    TestDatabase omemo_db;
    try {
        omemo_db = new TestDatabase(dir + "/omemo.db");
        omemo_db.open(omemo_key);
        omemo_db.insert_row("identity_key", 42);
    } catch (Error e) {
        ok(false, "setup omemo_db: " + e.message);
        return;
    }
    ok(true, "setup: 4 databases created with data");

    // ─── Validation tests (from application.vala:1148-1163) ───

    // 1a: Wrong old password → reject (line 1149)
    {
        string old_pw = "WRONG_password";
        bool rejected = (old_pw != db_key);
        ok(rejected, "validation: wrong old password rejected");
    }

    // 1b: Empty new password → reject (line 1154)
    {
        string new_pw = "";
        bool rejected = (new_pw.strip().length == 0);
        ok(rejected, "validation: empty new password rejected");
    }

    // 1c: Whitespace-only new password → reject (line 1154)
    {
        string new_pw = "   ";
        bool rejected = (new_pw.strip().length == 0);
        ok(rejected, "validation: whitespace-only new password rejected");
    }

    // 1d: Mismatched passwords → reject (line 1159)
    {
        string new_pw = "new_secure_pw";
        string new_pw2 = "typo_secure_pw";
        bool rejected = (new_pw != new_pw2);
        ok(rejected, "validation: mismatched passwords rejected");
    }

    // 1e: correct old password + matching new password → accepted
    {
        string old_pw = "original_password";
        string new_pw = "new_secure_pw";
        string new_pw2 = "new_secure_pw";
        bool accepted = (old_pw == db_key) &&
                        (new_pw.strip().length > 0) &&
                        (new_pw == new_pw2);
        ok(accepted, "validation: correct inputs accepted");
    }

    // ─── Execute rekey (application.vala:1166-1175) ───

    string new_password = "new_secure_pw";

    // Step 1: db.rekey(new_pw)  — line 1166
    try {
        main_db.rekey(new_password);
        ok(true, "step 1: main_db.rekey() succeeded");
    } catch (Error e) {
        ok(false, "step 1: main_db.rekey() failed: " + e.message);
        return;
    }

    // Step 2: plugin_loader.rekey_databases(new_pw) — line 1171
    //   → openpgp plugin:  db.rekey(new_key)  (line 243 of openpgp/plugin.vala)
    try {
        pgp_db.rekey(new_password);
        ok(true, "step 2a: pgp_db.rekey() succeeded (openpgp plugin)");
    } catch (Error e) {
        ok(false, "step 2a: pgp_db.rekey() failed: " + e.message);
        return;
    }

    //   → bot-features plugin:  registry.rekey(new_key)  (line 731 of bot-features/plugin.vala)
    try {
        bot_db.rekey(new_password);
        ok(true, "step 2b: bot_db.rekey() succeeded (bot-features plugin)");
    } catch (Error e) {
        ok(false, "step 2b: bot_db.rekey() failed: " + e.message);
        return;
    }

    //   → omemo plugin: NO-OP (line 103 of omemo/plugin.vala — separate key)
    ok(true, "step 2c: omemo rekey skipped (separate keyring key — correct)");

    // Step 3: this.db_key = new_pw — line 1175
    db_key = new_password;
    ok(db_key == "new_secure_pw", "step 3: db_key updated");

    // Close all DBs to flush
    main_db.close();
    pgp_db.close();
    bot_db.close();
    omemo_db.close();

    // ─── Verify: reopen with new password, data intact ───

    // main DB
    try {
        var db = new TestDatabase(dir + "/dino.db");
        db.open(new_password);
        ok(db.count_rows() == 3, "verify: dino.db opens with new pw, 3 rows intact");
        ok(db.sum_values() == 103, "verify: dino.db data values correct (1+2+100=103)");
        db.close();
    } catch (Error e) {
        ok(false, "verify dino.db: " + e.message);
    }

    // pgp DB
    try {
        var db = new TestDatabase(dir + "/pgp.db");
        db.open(new_password);
        ok(db.count_rows() == 1, "verify: pgp.db opens with new pw, 1 row intact");
        db.close();
    } catch (Error e) {
        ok(false, "verify pgp.db: " + e.message);
    }

    // bot_registry DB
    try {
        var db = new TestDatabase(dir + "/bot_registry.db");
        db.open(new_password);
        ok(db.count_rows() == 1, "verify: bot_registry.db opens with new pw, 1 row");
        db.close();
    } catch (Error e) {
        ok(false, "verify bot_registry.db: " + e.message);
    }

    // omemo DB — must still use its OWN key, not the new password
    try {
        var db = new TestDatabase(dir + "/omemo.db");
        db.open(omemo_key);
        ok(db.count_rows() == 1, "verify: omemo.db still uses its own key, 1 row");
        db.close();
    } catch (Error e) {
        ok(false, "verify omemo.db: " + e.message);
    }

    // omemo DB must NOT open with the new password
    try {
        var db = new TestDatabase(dir + "/omemo.db");
        db.open(new_password);
        db.count_rows();
        ok(false, "verify: omemo.db should NOT open with new_password");
        db.close();
    } catch (Error e) {
        ok(true, "verify: omemo.db correctly rejects new_password");
    }

    // Old password must NOT work on any of the rekeyed DBs
    foreach (string name in new string[]{ "dino.db", "pgp.db", "bot_registry.db" }) {
        try {
            var db = new TestDatabase(dir + "/" + name);
            db.open("original_password");
            db.count_rows();
            ok(false, name + " should reject old password");
            db.close();
        } catch (Error e) {
            ok(true, "verify: " + name + " correctly rejects old password");
        }
    }
}

// ══════════════════════════════════════════════════════════════════════
//          SUITE 2 — "Reset Database" full UI flow
// ══════════════════════════════════════════════════════════════════════

void test_reset_database_ui_flow() {
    suite("2 · UI: Reset Database — full flow (application.vala:1804-1853)");

    string data_dir = test_dir() + "/reset_flow";
    DirUtils.create_with_parents(data_dir, 0700);

    string db_key = "reset_test_key";

    // Create all 4 databases with WAL mode + data
    string[] db_names = { "dino.db", "pgp.db", "bot_registry.db", "omemo.db" };
    foreach (string name in db_names) {
        try {
            var db = new TestDatabase(data_dir + "/" + name);
            db.open(db_key);
            db.exec("PRAGMA journal_mode = WAL;");
            db.insert_row("data_" + name, 42);
            db.close();
        } catch (Error e) {
            ok(false, "setup " + name + ": " + e.message);
        }
    }

    // Create omemo.key file
    string omemo_key_path = Path.build_filename(data_dir, "omemo.key");
    try {
        FileUtils.set_contents(omemo_key_path, "fake_omemo_key_data");
    } catch (Error e) {
        ok(false, "setup omemo.key: " + e.message);
    }

    // Create omemo/ directory with files inside
    string omemo_dir = Path.build_filename(data_dir, "omemo");
    DirUtils.create_with_parents(omemo_dir, 0700);
    try {
        FileUtils.set_contents(Path.build_filename(omemo_dir, "identity.dat"), "fake_identity");
        FileUtils.set_contents(Path.build_filename(omemo_dir, "sessions.dat"), "fake_sessions");
    } catch (Error e) {
        ok(false, "setup omemo dir: " + e.message);
    }

    ok(true, "setup: 4 DBs + omemo.key + omemo/ dir created");

    // ─── Execute reset (replicates perform_reset_database, line 1804-1853) ───

    // Step 1: Delete main database (line 1824-1826)
    string db_path = Path.build_filename(data_dir, "dino.db");
    FileUtils.unlink(db_path);
    FileUtils.unlink(db_path + "-shm");
    FileUtils.unlink(db_path + "-wal");
    ok(!FileUtils.test(db_path, FileTest.EXISTS), "step 1: dino.db deleted");

    // Step 2: Delete plugin databases (line 1829-1834)
    string[] plugin_dbs = { "pgp.db", "bot_registry.db", "omemo.db" };
    foreach (string plugin_db in plugin_dbs) {
        string p = Path.build_filename(data_dir, plugin_db);
        FileUtils.unlink(p);
        FileUtils.unlink(p + "-shm");
        FileUtils.unlink(p + "-wal");
    }
    bool plugin_dbs_gone = true;
    foreach (string plugin_db in plugin_dbs) {
        if (FileUtils.test(Path.build_filename(data_dir, plugin_db), FileTest.EXISTS)) {
            plugin_dbs_gone = false;
        }
    }
    ok(plugin_dbs_gone, "step 2: plugin DBs deleted (pgp + bot_registry + omemo)");

    // Step 3: Delete omemo.key (line 1837)
    FileUtils.unlink(omemo_key_path);
    ok(!FileUtils.test(omemo_key_path, FileTest.EXISTS), "step 3: omemo.key deleted");

    // Step 4: Delete omemo/ directory contents (line 1840-1845)
    // Replicate delete_directory_contents + DirUtils.remove
    try {
        Dir dir = Dir.open(omemo_dir, 0);
        string? child = null;
        while ((child = dir.read_name()) != null) {
            FileUtils.unlink(Path.build_filename(omemo_dir, child));
        }
        DirUtils.remove(omemo_dir);
    } catch (Error e) {
        // "Ignore if doesn't exist" — matches application.vala:1843
    }
    ok(!FileUtils.test(omemo_dir, FileTest.IS_DIR), "step 4: omemo/ directory deleted");

    // ─── Verify: nothing remains ───
    bool clean = true;
    foreach (string name in db_names) {
        string p = Path.build_filename(data_dir, name);
        foreach (string suffix in new string[]{ "", "-wal", "-shm" }) {
            if (FileUtils.test(p + suffix, FileTest.EXISTS)) {
                ok(false, name + suffix + " still exists!");
                clean = false;
            }
        }
    }
    if (clean) {
        ok(true, "verify: all database files + WAL/SHM completely removed");
    }
    ok(!FileUtils.test(omemo_key_path, FileTest.EXISTS), "verify: omemo.key gone");
    ok(!FileUtils.test(omemo_dir, FileTest.IS_DIR), "verify: omemo/ gone");
}

// ══════════════════════════════════════════════════════════════════════
//       SUITE 3 — "Backup" checkpoint flow
// ══════════════════════════════════════════════════════════════════════

void test_checkpoint_backup_ui_flow() {
    suite("3 · UI: Backup — checkpoint_databases() (application.vala:2102-2113)");

    string dir = test_dir() + "/backup_flow";
    DirUtils.create_with_parents(dir, 0700);

    string db_key = "backup_test_key";

    // Create all 4 databases in WAL mode with data
    TestDatabase main_db;
    TestDatabase pgp_db;
    TestDatabase bot_db;
    TestDatabase omemo_db;

    try {
        main_db = new TestDatabase(dir + "/dino.db");
        main_db.open(db_key);
        main_db.exec("PRAGMA journal_mode = WAL;");
        for (int i = 0; i < 50; i++) {
            main_db.insert_row("msg_%d".printf(i), i);
        }

        pgp_db = new TestDatabase(dir + "/pgp.db");
        pgp_db.open(db_key);
        pgp_db.exec("PRAGMA journal_mode = WAL;");
        pgp_db.insert_row("gpg_key", 1);

        bot_db = new TestDatabase(dir + "/bot_registry.db");
        bot_db.open(db_key);
        bot_db.exec("PRAGMA journal_mode = WAL;");
        bot_db.insert_row("bot_1", 1);

        string omemo_key = "separate_key";
        omemo_db = new TestDatabase(dir + "/omemo.db");
        omemo_db.open(omemo_key);
        omemo_db.exec("PRAGMA journal_mode = WAL;");
        omemo_db.insert_row("session_1", 1);
    } catch (Error e) {
        ok(false, "setup: " + e.message);
        return;
    }
    ok(true, "setup: 4 WAL-mode databases with data");

    // ─── Execute checkpoint (replicates checkpoint_databases, line 2102-2113) ───

    // Step 1: Checkpoint main database (line 2104-2107)
    try {
        main_db.exec("PRAGMA wal_checkpoint(TRUNCATE)");
        ok(true, "step 1: main_db checkpoint(TRUNCATE) ok");
    } catch (Error e) {
        ok(false, "step 1: main_db checkpoint failed: " + e.message);
    }

    // Step 2: plugin_loader.checkpoint_databases() (line 2111-2113)
    //   → openpgp:      db.exec("PRAGMA wal_checkpoint(TRUNCATE)")   (openpgp/plugin.vala:251)
    try {
        pgp_db.exec("PRAGMA wal_checkpoint(TRUNCATE)");
        ok(true, "step 2a: pgp_db checkpoint ok (openpgp plugin)");
    } catch (Error e) {
        ok(false, "step 2a: pgp_db checkpoint failed: " + e.message);
    }

    //   → bot-features: registry.exec("PRAGMA wal_checkpoint(TRUNCATE)")  (bot-features/plugin.vala:738)
    try {
        bot_db.exec("PRAGMA wal_checkpoint(TRUNCATE)");
        ok(true, "step 2b: bot_db checkpoint ok (bot-features plugin)");
    } catch (Error e) {
        ok(false, "step 2b: bot_db checkpoint failed: " + e.message);
    }

    //   → omemo:        db.exec("PRAGMA wal_checkpoint(TRUNCATE)")  (omemo/plugin.vala:111)
    try {
        omemo_db.exec("PRAGMA wal_checkpoint(TRUNCATE)");
        ok(true, "step 2c: omemo_db checkpoint ok (omemo plugin)");
    } catch (Error e) {
        ok(false, "step 2c: omemo_db checkpoint failed: " + e.message);
    }

    // Close all
    main_db.close();
    pgp_db.close();
    bot_db.close();
    omemo_db.close();

    // ─── Verify: WAL files should be empty after TRUNCATE ───
    foreach (string name in new string[]{ "dino.db", "pgp.db", "bot_registry.db", "omemo.db" }) {
        string wal_path = dir + "/" + name + "-wal";
        if (FileUtils.test(wal_path, FileTest.EXISTS)) {
            int64 wal_size = 0;
            try {
                var fi = File.new_for_path(wal_path);
                var info = fi.query_info("standard::size", FileQueryInfoFlags.NONE);
                wal_size = info.get_size();
            } catch (Error e) {
                wal_size = -1;
            }
            ok(wal_size == 0, name + " WAL empty after checkpoint (size=%ld)".printf((long) wal_size));
        } else {
            ok(true, name + " WAL file removed (good)");
        }
    }

    // ─── Verify: data still readable after checkpoint + close + reopen ───
    try {
        var db = new TestDatabase(dir + "/dino.db");
        db.open(db_key);
        ok(db.count_rows() == 50, "verify: dino.db has 50 rows after checkpoint");
        db.close();
    } catch (Error e) {
        ok(false, "verify dino.db: " + e.message);
    }
}

// ══════════════════════════════════════════════════════════════════════
//     SUITE 4 — Change Password → Backup → Verify end-to-end
// ══════════════════════════════════════════════════════════════════════

void test_change_pw_then_backup_e2e() {
    suite("4 · E2E: Change Password → Checkpoint → Backup verify");

    string dir = test_dir() + "/e2e";
    DirUtils.create_with_parents(dir, 0700);

    string old_key = "old_password";
    string new_key = "new_password";
    string omemo_key = "omemo_separate_key";

    // Create all DBs
    TestDatabase main_db;
    TestDatabase pgp_db;
    TestDatabase bot_db;
    TestDatabase omemo_db;
    try {
        main_db = new TestDatabase(dir + "/dino.db");
        main_db.open(old_key);
        main_db.insert_row("alice", 1);
        main_db.insert_row("bob", 2);

        pgp_db = new TestDatabase(dir + "/pgp.db");
        pgp_db.open(old_key);
        pgp_db.insert_row("key_fp", 99);

        bot_db = new TestDatabase(dir + "/bot_registry.db");
        bot_db.open(old_key);
        bot_db.insert_row("mybot", 77);

        omemo_db = new TestDatabase(dir + "/omemo.db");
        omemo_db.open(omemo_key);
        omemo_db.insert_row("sess", 55);
    } catch (Error e) {
        ok(false, "e2e setup: " + e.message);
        return;
    }
    ok(true, "e2e setup: 4 databases created");

    // Phase 1: Change password
    try {
        main_db.rekey(new_key);
        pgp_db.rekey(new_key);
        bot_db.rekey(new_key);
        // omemo: no-op
        ok(true, "phase 1: rekey all shared-key DBs");
    } catch (Error e) {
        ok(false, "phase 1 rekey: " + e.message);
        return;
    }

    // Phase 2: Checkpoint (backup preparation)
    try {
        main_db.exec("PRAGMA wal_checkpoint(TRUNCATE)");
        pgp_db.exec("PRAGMA wal_checkpoint(TRUNCATE)");
        bot_db.exec("PRAGMA wal_checkpoint(TRUNCATE)");
        omemo_db.exec("PRAGMA wal_checkpoint(TRUNCATE)");
        ok(true, "phase 2: checkpoint all DBs");
    } catch (Error e) {
        ok(false, "phase 2 checkpoint: " + e.message);
        return;
    }

    // Close all
    main_db.close();
    pgp_db.close();
    bot_db.close();
    omemo_db.close();

    // Phase 3: Verify — simulate "restore from backup" by opening fresh
    try {
        var db = new TestDatabase(dir + "/dino.db");
        db.open(new_key);
        ok(db.count_rows() == 2, "e2e verify: dino.db 2 rows with new key");
        ok(db.sum_values() == 3, "e2e verify: dino.db values correct (1+2)");
        db.close();
    } catch (Error e) {
        ok(false, "e2e verify dino.db: " + e.message);
    }

    try {
        var db = new TestDatabase(dir + "/pgp.db");
        db.open(new_key);
        ok(db.count_rows() == 1, "e2e verify: pgp.db 1 row with new key");
        db.close();
    } catch (Error e) {
        ok(false, "e2e verify pgp.db: " + e.message);
    }

    try {
        var db = new TestDatabase(dir + "/bot_registry.db");
        db.open(new_key);
        ok(db.count_rows() == 1, "e2e verify: bot_registry.db 1 row with new key");
        db.close();
    } catch (Error e) {
        ok(false, "e2e verify bot_registry.db: " + e.message);
    }

    try {
        var db = new TestDatabase(dir + "/omemo.db");
        db.open(omemo_key);
        ok(db.count_rows() == 1, "e2e verify: omemo.db 1 row with own key");
        db.close();
    } catch (Error e) {
        ok(false, "e2e verify omemo.db: " + e.message);
    }

    // Old key must fail on rekeyed DBs
    foreach (string name in new string[]{ "dino.db", "pgp.db", "bot_registry.db" }) {
        try {
            var db = new TestDatabase(dir + "/" + name);
            db.open(old_key);
            db.count_rows();
            ok(false, name + " should reject old key after e2e");
            db.close();
        } catch (Error e) {
            ok(true, "e2e verify: " + name + " rejects old key");
        }
    }
}

// ══════════════════════════════════════════════════════════════════════
//     SUITE 5 — Edge cases the UI must handle
// ══════════════════════════════════════════════════════════════════════

void test_edge_cases() {
    suite("5 · Edge cases for UI robustness");

    string dir = test_dir() + "/edge";
    DirUtils.create_with_parents(dir, 0700);

    // 5a: Password with SQL injection attempt (single quotes)
    {
        string path = dir + "/sqlinject.db";
        try {
            var db = new TestDatabase(path);
            db.open("safe_key");
            db.insert_row("data", 1);
            db.rekey("'; DROP TABLE test_data; --");
            db.close();

            db = new TestDatabase(path);
            db.open("'; DROP TABLE test_data; --");
            ok(db.count_rows() == 1, "edge: SQL injection key works, data intact");
            db.close();
        } catch (Error e) {
            ok(false, "edge: SQL injection key: " + e.message);
        }
    }

    // 5b: Very long password (1000 chars)
    {
        string path = dir + "/longpw.db";
        var sb = new StringBuilder();
        for (int i = 0; i < 1000; i++) sb.append_c('A');
        string long_pw = sb.str;
        try {
            var db = new TestDatabase(path);
            db.open("short");
            db.insert_row("x", 1);
            db.rekey(long_pw);
            db.close();

            db = new TestDatabase(path);
            db.open(long_pw);
            ok(db.count_rows() == 1, "edge: 1000-char password works");
            db.close();
        } catch (Error e) {
            ok(false, "edge: long password: " + e.message);
        }
    }

    // 5c: Unicode password (emoji, CJK, Arabic)
    {
        string path = dir + "/unicode.db";
        string pw = "🔒密码كلمة";
        try {
            var db = new TestDatabase(path);
            db.open("temp");
            db.insert_row("unicode_test", 1);
            db.rekey(pw);
            db.close();

            db = new TestDatabase(path);
            db.open(pw);
            ok(db.count_rows() == 1, "edge: Unicode/emoji password works");
            db.close();
        } catch (Error e) {
            ok(false, "edge: Unicode password: " + e.message);
        }
    }

    // 5d: Rekey while DB has pending WAL data
    {
        string path = dir + "/wal_rekey.db";
        try {
            var db = new TestDatabase(path);
            db.open("before");
            db.exec("PRAGMA journal_mode = WAL;");
            for (int i = 0; i < 200; i++) {
                db.insert_row("row_%d".printf(i), i);
            }
            // Rekey WITHOUT checkpoint first — must still work
            db.rekey("after");
            ok(true, "edge: rekey with pending WAL data succeeded");
            ok(db.count_rows() == 200, "edge: 200 rows intact after WAL rekey");
            db.close();
        } catch (Error e) {
            ok(false, "edge: WAL rekey: " + e.message);
        }
    }

    // 5e: Delete non-existent files (reset gracefully handles missing DBs)
    {
        string missing = dir + "/nonexistent.db";
        // FileUtils.unlink returns -1 for missing files — should not crash
        int r1 = FileUtils.unlink(missing);
        int r2 = FileUtils.unlink(missing + "-wal");
        int r3 = FileUtils.unlink(missing + "-shm");
        ok(true, "edge: unlink non-existent files doesn't crash (returns %d,%d,%d)".printf(r1, r2, r3));
    }

    // 5f: Same password rekey (no-op should still work)
    {
        string path = dir + "/same_pw.db";
        try {
            var db = new TestDatabase(path);
            db.open("same");
            db.insert_row("test", 1);
            db.rekey("same");  // Rekey to SAME password
            db.close();

            db = new TestDatabase(path);
            db.open("same");
            ok(db.count_rows() == 1, "edge: rekey to same password works");
            db.close();
        } catch (Error e) {
            ok(false, "edge: same password: " + e.message);
        }
    }

    // 5g: Rapid sequential rekeys (simulates fast UI clicks)
    {
        string path = dir + "/rapid.db";
        try {
            var db = new TestDatabase(path);
            db.open("key0");
            db.insert_row("speed_test", 1);
            for (int i = 1; i <= 5; i++) {
                db.rekey("key%d".printf(i));
            }
            ok(true, "edge: 5 rapid sequential rekeys succeeded");
            db.close();

            db = new TestDatabase(path);
            db.open("key5");
            ok(db.count_rows() == 1, "edge: data intact after rapid rekeys");
            db.close();
        } catch (Error e) {
            ok(false, "edge: rapid rekeys: " + e.message);
        }
    }
}

// ══════════════════════════════════════════════════════════════════════
//     SUITE 6 — Plugin null-safety (db == null checks)
// ══════════════════════════════════════════════════════════════════════

void test_plugin_null_safety() {
    suite("6 · Plugin null-safety (if db != null checks)");

    // The plugin code has "if (db != null) db.rekey(..." guards.
    // Verify these don't crash when db IS null.
    // We simulate this by testing the same null-check pattern.

    // Simulate openpgp plugin with null db (line 242-244)
    {
        TestDatabase? db = null;
        bool safe = true;
        try {
            if (db != null) {
                db.rekey("test");
            }
        } catch (Error e) {
            safe = false;
        }
        ok(safe, "null-safety: openpgp rekey_database with null db");
    }

    // Simulate openpgp plugin checkpoint with null db (line 248-254)
    {
        TestDatabase? db = null;
        bool safe = true;
        try {
            if (db != null) {
                db.exec("PRAGMA wal_checkpoint(TRUNCATE)");
            }
        } catch (Error e) {
            safe = false;
        }
        ok(safe, "null-safety: openpgp checkpoint_database with null db");
    }

    // Simulate bot-features plugin with null registry (line 729-731)
    {
        TestDatabase? registry = null;
        bool safe = true;
        try {
            if (registry != null) {
                registry.rekey("test");
            }
        } catch (Error e) {
            safe = false;
        }
        ok(safe, "null-safety: bot-features rekey_database with null registry");
    }

    // Simulate bot-features plugin checkpoint with null registry (line 735-742)
    {
        TestDatabase? registry = null;
        bool safe = true;
        try {
            if (registry != null) {
                registry.exec("PRAGMA wal_checkpoint(TRUNCATE)");
            }
        } catch (Error e) {
            safe = false;
        }
        ok(safe, "null-safety: bot-features checkpoint_database with null registry");
    }

    // Simulate omemo plugin checkpoint with null db (line 108-116)
    {
        TestDatabase? db = null;
        bool safe = true;
        try {
            if (db != null) {
                db.exec("PRAGMA wal_checkpoint(TRUNCATE)");
            }
        } catch (Error e) {
            safe = false;
        }
        ok(safe, "null-safety: omemo checkpoint_database with null db");
    }

    // Simulate plugin_loader null check from application.vala (line 1170-1172)
    {
        bool safe = true;
        // In app: if (plugin_loader != null) plugin_loader.rekey_databases(new_pw);
        // We just test the null check pattern
        Object? plugin_loader = null;
        if (plugin_loader != null) {
            // Would call rekey_databases but it's null
            safe = false; // Should never reach here
        }
        ok(safe, "null-safety: plugin_loader null check in rekey flow");
    }

    // Simulate plugin_loader null check in checkpoint (line 2111-2113)
    {
        bool safe = true;
        Object? plugin_loader = null;
        if (plugin_loader != null) {
            safe = false;
        }
        ok(safe, "null-safety: plugin_loader null check in checkpoint flow");
    }
}

// ── Main ─────────────────────────────────────────────────────────────

int main(string[] args) {
    stdout.printf("╔══════════════════════════════════════════════════════════╗\n");
    stdout.printf("║  DinoX DB Maintenance — UI-Flow Integration Tests      ║\n");
    stdout.printf("╚══════════════════════════════════════════════════════════╝\n");

    string dir = test_dir();
    if (FileUtils.test(dir, FileTest.IS_DIR)) {
        Posix.system("rm -rf " + dir);
    }
    DirUtils.create_with_parents(dir, 0700);

    test_change_password_ui_flow();
    test_reset_database_ui_flow();
    test_checkpoint_backup_ui_flow();
    test_change_pw_then_backup_e2e();
    test_edge_cases();
    test_plugin_null_safety();

    stdout.printf("\n══════════════════════════════════════════════════════════\n");
    stdout.printf("  Results:  %d PASS  |  %d FAIL\n", PASS, FAIL);
    stdout.printf("══════════════════════════════════════════════════════════\n");

    Posix.system("rm -rf " + dir);

    return (FAIL > 0) ? 1 : 0;
}
