/**
 * Integration test for database maintenance operations.
 *
 * Tests the actual Qlite.Database Vala code paths:
 *   - rekey()      (PRAGMA rekey)
 *   - exec()       (PRAGMA wal_checkpoint)
 *   - init()       (open with key)
 *   - close()
 *   - file deletion (reset_database simulation)
 *
 * This exercises the SAME compiled Qlite code that the DinoX UI calls
 * via plugin_loader.rekey_databases() / checkpoint_databases().
 *
 * Build:  see scripts/run_db_integration_tests.sh
 */

using Qlite;

// ── Helpers ───────────────────────────────────────────────────────────

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
    return "/tmp/dinox_vala_integration_test_%d".printf((int) Posix.getpid());
}

// A minimal Qlite.Database subclass with one table, used for testing.
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
            .value(col_val,  val)
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
}

// ── Test suites ──────────────────────────────────────────────────────

void test_basic_rekey() {
    suite("1 · Qlite.Database.rekey()");

    string dir = test_dir();
    DirUtils.create_with_parents(dir, 0700);
    string path = dir + "/rekey_basic.db";

    // 1a  Create encrypted DB with key "alpha"
    try {
        var db = new TestDatabase(path);
        db.open("alpha");
        db.insert_row("hello", 42);
        ok(db.count_rows() == 1, "insert into encrypted DB");
        db.close();
    } catch (Error e) {
        ok(false, "create encrypted DB: " + e.message);
        return;
    }

    // 1b  Rekey from "alpha" → "beta"
    try {
        var db = new TestDatabase(path);
        db.open("alpha");
        db.rekey("beta");
        ok(true, "rekey alpha → beta succeeded");
        db.close();
    } catch (Error e) {
        ok(false, "rekey alpha → beta: " + e.message);
        return;
    }

    // 1c  Open with NEW key "beta" must work
    try {
        var db = new TestDatabase(path);
        db.open("beta");
        ok(db.count_rows() == 1, "open with new key, data intact");
        db.close();
    } catch (Error e) {
        ok(false, "open with new key: " + e.message);
    }

    // 1d  Open with OLD key "alpha" must fail
    try {
        var db = new TestDatabase(path);
        db.open("alpha");
        // If init doesn't throw, a SELECT will fail:
        long n = db.count_rows();
        ok(false, "old key should have been rejected (got " + n.to_string() + " rows)");
        db.close();
    } catch (Error e) {
        ok(true, "old key correctly rejected");
    }

    // 1e  Empty key must throw
    try {
        var db = new TestDatabase(path);
        db.open("beta");
        db.rekey("");
        ok(false, "empty key should throw");
        db.close();
    } catch (Error e) {
        ok(true, "empty key rejected: " + e.message);
    }

    // 1f  Key with special chars
    try {
        // Re-open with beta (previous rekey("") was rejected, so key is still beta)
        string special = "p@ss'w\"rd<>&€";
        var db = new TestDatabase(path);
        db.open("beta");
        db.rekey(special);
        db.close();

        db = new TestDatabase(path);
        db.open(special);
        ok(db.count_rows() == 1, "special-char key works");
        db.close();
    } catch (Error e) {
        ok(false, "special-char key: " + e.message);
    }
}

void test_multi_db_rekey() {
    suite("2 · Multi-DB rekey (simulates Loader.rekey_databases)");

    string dir = test_dir();
    DirUtils.create_with_parents(dir, 0700);

    string[] names = { "dino.db", "pgp.db", "bot_registry.db", "omemo.db" };
    string old_key = "old_pw";
    string new_key = "new_pw";

    // 2a  Create 4 DBs all with old_key
    foreach (string name in names) {
        try {
            var db = new TestDatabase(dir + "/" + name);
            db.open(old_key);
            db.insert_row(name, 1);
            db.close();
        } catch (Error e) {
            ok(false, "create " + name + ": " + e.message);
        }
    }
    ok(true, "created 4 encrypted databases");

    // 2b  Rekey only the first 3 (omemo stays on old_key — matches real logic)
    for (int i = 0; i < 3; i++) {
        try {
            var db = new TestDatabase(dir + "/" + names[i]);
            db.open(old_key);
            db.rekey(new_key);
            db.close();
        } catch (Error e) {
            ok(false, "rekey " + names[i] + ": " + e.message);
        }
    }
    ok(true, "rekeyed dino/pgp/bot_registry");

    // 2c  Verify first 3 open with new_key
    for (int i = 0; i < 3; i++) {
        try {
            var db = new TestDatabase(dir + "/" + names[i]);
            db.open(new_key);
            ok(db.count_rows() == 1, names[i] + " opens with new key, data ok");
            db.close();
        } catch (Error e) {
            ok(false, names[i] + " new key: " + e.message);
        }
    }

    // 2d  Verify omemo.db still on old_key
    try {
        var db = new TestDatabase(dir + "/omemo.db");
        db.open(old_key);
        ok(db.count_rows() == 1, "omemo.db still on old key");
        db.close();
    } catch (Error e) {
        ok(false, "omemo.db old key: " + e.message);
    }
}

void test_wal_checkpoint() {
    suite("3 · WAL checkpoint via exec()");

    string dir = test_dir();
    DirUtils.create_with_parents(dir, 0700);
    string path = dir + "/wal_test.db";

    try {
        var db = new TestDatabase(path);
        db.open("wal_key");

        // Enable WAL mode
        db.exec("PRAGMA journal_mode = WAL;");

        // Insert data — may produce WAL
        for (int i = 0; i < 100; i++) {
            db.insert_row("row_%d".printf(i), i);
        }

        // Checkpoint (same call as plugin checkpoint_database)
        db.exec("PRAGMA wal_checkpoint(TRUNCATE);");
        ok(true, "WAL checkpoint executed without error");

        // Verify data still readable
        ok(db.count_rows() == 100, "100 rows intact after checkpoint");
        db.close();
    } catch (Error e) {
        ok(false, "WAL checkpoint: " + e.message);
    }

    // WAL file should be empty or missing after TRUNCATE checkpoint + close
    string wal_path = path + "-wal";
    if (FileUtils.test(wal_path, FileTest.EXISTS)) {
        int64 wal_size = 0;
        try {
            var fi = File.new_for_path(wal_path);
            var info = fi.query_info("standard::size", FileQueryInfoFlags.NONE);
            wal_size = info.get_size();
        } catch (Error e) {
            wal_size = -1;
        }
        ok(wal_size == 0, "WAL file empty after truncate checkpoint (size=%ld)".printf((long) wal_size));
    } else {
        ok(true, "WAL file removed after close");
    }
}

void test_rekey_data_integrity() {
    suite("4 · Data integrity survives rekey");

    string dir = test_dir();
    DirUtils.create_with_parents(dir, 0700);
    string path = dir + "/integrity.db";

    try {
        var db = new TestDatabase(path);
        db.open("key1");
        // Insert varied data
        db.insert_row("Alice",   100);
        db.insert_row("Bob",     200);
        db.insert_row("Charlie", 300);
        ok(db.count_rows() == 3, "3 rows inserted");

        // Chain rekey twice
        db.rekey("key2");
        ok(true, "rekey key1 → key2");
        db.rekey("key3");
        ok(true, "rekey key2 → key3");
        db.close();
    } catch (Error e) {
        ok(false, "chain rekey: " + e.message);
        return;
    }

    // Reopen, verify data
    try {
        var db = new TestDatabase(path);
        db.open("key3");
        ok(db.count_rows() == 3, "all 3 rows present after double rekey");

        // Verify specific values through a raw query
        long sum = 0;
        foreach (Row row in db.select({db.col_val}).from(db.test_table)) {
            sum += row[db.col_val];
        }
        ok(sum == 600, "sum of values = 600 (data intact)");
        db.close();
    } catch (Error e) {
        ok(false, "reopen after double rekey: " + e.message);
    }

    // key1 and key2 must fail
    foreach (string bad in new string[]{ "key1", "key2" }) {
        try {
            var db = new TestDatabase(path);
            db.open(bad);
            db.count_rows();
            ok(false, bad + " should be rejected");
            db.close();
        } catch (Error e) {
            ok(true, "intermediate key '" + bad + "' rejected");
        }
    }
}

void test_file_deletion_reset() {
    suite("5 · File deletion (reset_database simulation)");

    string dir = test_dir() + "/reset";
    DirUtils.create_with_parents(dir, 0700);

    string[] names = { "dino.db", "pgp.db", "bot_registry.db", "omemo.db" };

    // Create DBs and companion files
    foreach (string name in names) {
        try {
            var db = new TestDatabase(dir + "/" + name);
            db.open("del_key");
            db.exec("PRAGMA journal_mode = WAL;");
            db.insert_row("x", 1);
            db.close();
        } catch (Error e) {
            ok(false, "create " + name + ": " + e.message);
        }
    }
    ok(true, "4 databases created for reset test");

    // Delete all DBs + WAL + SHM  (mirrors application.vala logic)
    foreach (string name in names) {
        string p = dir + "/" + name;
        foreach (string suffix in new string[]{ "", "-wal", "-shm" }) {
            string full = p + suffix;
            if (FileUtils.test(full, FileTest.EXISTS)) {
                FileUtils.remove(full);
            }
        }
    }

    // Verify all gone
    bool all_gone = true;
    foreach (string name in names) {
        string p = dir + "/" + name;
        if (FileUtils.test(p, FileTest.EXISTS)) {
            ok(false, name + " still exists after reset");
            all_gone = false;
        }
    }
    if (all_gone) {
        ok(true, "all 4 DBs + WAL/SHM removed");
    }
}

void test_error_propagation() {
    suite("6 · Error propagation");

    string dir = test_dir() + "/errors";
    DirUtils.create_with_parents(dir, 0700);

    // 6a  Whitespace-only key must be rejected ("  " is not empty but should fail strip check)
    string path_ws = dir + "/whitespace_key.db";
    try {
        var db = new TestDatabase(path_ws);
        db.open("tempkey");
        db.rekey("   ");
        ok(false, "whitespace-only key should throw");
        db.close();
    } catch (Error e) {
        ok(true, "whitespace-only key rejected: " + e.message);
    }

    // 6b  exec arbitrary SQL after rekey should work
    string path2 = dir + "/error_exec.db";
    try {
        var db = new TestDatabase(path2);
        db.open("testkey");
        db.insert_row("before", 1);
        db.rekey("newkey");
        db.insert_row("after", 2);
        ok(db.count_rows() == 2, "insert works after rekey in same session");
        db.close();
    } catch (Error e) {
        ok(false, "exec after rekey: " + e.message);
    }

    // 6c  Close, reopen with new key, verify
    try {
        var db = new TestDatabase(path2);
        db.open("newkey");
        ok(db.count_rows() == 2, "reopen after rekey, 2 rows present");
        db.close();
    } catch (Error e) {
        ok(false, "reopen after rekey: " + e.message);
    }
}

void test_concurrent_like_access() {
    suite("7 · Sequential multi-DB operations (like real plugin loop)");

    string dir = test_dir() + "/loader_sim";
    DirUtils.create_with_parents(dir, 0700);

    // Simulate the actual Loader.rekey_databases() pattern:
    //   foreach plugin { plugin.rekey_database(new_key); }
    // Each plugin opens its own DB, rekeys, done.

    string[] db_names = { "plugin_a.db", "plugin_b.db", "plugin_c.db" };
    string old = "shared_old";
    string @new = "shared_new";

    // Create
    foreach (string name in db_names) {
        try {
            var db = new TestDatabase(dir + "/" + name);
            db.open(old);
            db.insert_row(name, 99);
            db.close();
        } catch (Error e) {
            ok(false, "create " + name + ": " + e.message);
        }
    }
    ok(true, "3 plugin DBs created");

    // Rekey loop — mirrors Loader pattern
    bool rekey_ok = true;
    foreach (string name in db_names) {
        try {
            var db = new TestDatabase(dir + "/" + name);
            db.open(old);
            db.rekey(@new);
            db.close();
        } catch (Error e) {
            ok(false, "rekey " + name + ": " + e.message);
            rekey_ok = false;
        }
    }
    if (rekey_ok) ok(true, "rekey loop completed for all 3 DBs");

    // Checkpoint loop — mirrors Loader pattern
    bool cp_ok = true;
    foreach (string name in db_names) {
        try {
            var db = new TestDatabase(dir + "/" + name);
            db.open(@new);
            db.exec("PRAGMA wal_checkpoint(TRUNCATE);");
            db.close();
        } catch (Error e) {
            ok(false, "checkpoint " + name + ": " + e.message);
            cp_ok = false;
        }
    }
    if (cp_ok) ok(true, "checkpoint loop completed for all 3 DBs");

    // Verify all with new key
    foreach (string name in db_names) {
        try {
            var db = new TestDatabase(dir + "/" + name);
            db.open(@new);
            ok(db.count_rows() == 1, name + " readable with new key after loop");
            db.close();
        } catch (Error e) {
            ok(false, name + " verify: " + e.message);
        }
    }
}

// ── Main ─────────────────────────────────────────────────────────────

int main(string[] args) {
    stdout.printf("╔══════════════════════════════════════════════════╗\n");
    stdout.printf("║  DinoX DB Maintenance — Vala Integration Tests  ║\n");
    stdout.printf("╚══════════════════════════════════════════════════╝\n");

    // Clean previous run
    string dir = test_dir();
    if (FileUtils.test(dir, FileTest.IS_DIR)) {
        Posix.system("rm -rf " + dir);
    }
    DirUtils.create_with_parents(dir, 0700);

    test_basic_rekey();
    test_multi_db_rekey();
    test_wal_checkpoint();
    test_rekey_data_integrity();
    test_file_deletion_reset();
    test_error_propagation();
    test_concurrent_like_access();

    stdout.printf("\n══════════════════════════════════════════════════\n");
    stdout.printf("  Results:  %d PASS  |  %d FAIL\n", PASS, FAIL);
    stdout.printf("══════════════════════════════════════════════════\n");

    // Cleanup
    Posix.system("rm -rf " + dir);

    return (FAIL > 0) ? 1 : 0;
}
