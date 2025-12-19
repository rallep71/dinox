using Sqlite;

namespace Qlite {

public class Database {
    private string file_name;
    private Sqlite.Database db;
    private long expected_version;
    private Table[]? tables;

    private static bool logged_plaintext_fallback = false;
    private static bool logged_plaintext_migration = false;

    private Column<string?> meta_name = new Column.Text("name") { primary_key = true };
    private Column<long> meta_int_val = new Column.Long("int_val");
    private Column<string?> meta_text_val = new Column.Text("text_val");
    private Table meta_table;

    public bool debug = false;

    public Database(string file_name, long expected_version) {
        this.file_name = file_name;
        this.expected_version = expected_version;
        meta_table = new Table(this, "_meta");
        meta_table.init({meta_name, meta_int_val, meta_text_val});
    }

    public void init(Table[] tables, string? key = null, bool allow_plaintext_fallback = true) throws Error {
        Sqlite.config(Config.SERIALIZED);
        int ec = Sqlite.Database.open_v2(file_name, out db, OPEN_READWRITE | OPEN_CREATE | 0x00010000);
        if (ec != Sqlite.OK) {
            throw new Error(-1, 0, "SQLite open error for \"%s\": %d - %s", file_name, db.errcode(), db.errmsg());
        }

        if (key != null) {
            // Escape single quotes for SQL string literal.
            string escaped_key = escape_single_quotes((!)key);
            string key_pragma = "PRAGMA key = '%s';".printf(escaped_key);
            db.exec(key_pragma, null, null);
            
            // Verify encryption
            if (db.exec("SELECT count(*) FROM sqlite_master;", null, null) != Sqlite.OK) {
                // If the DB is plaintext, trying to open it with a key will fail.
                // Fall back and, if possible, migrate plaintext -> encrypted automatically.

                // Re-open without a key to see if it's plaintext.
                db = null;
                ec = Sqlite.Database.open_v2(file_name, out db, OPEN_READWRITE | OPEN_CREATE | 0x00010000);
                if (db.exec("SELECT count(*) FROM sqlite_master;", null, null) == Sqlite.OK) {
                    // Plaintext database detected.
                    bool migrated = false;
                    try {
                        migrated = try_migrate_plaintext_to_encrypted(((!)key));
                    } catch (Error e) {
                        migrated = false;
                    }

                    if (migrated) {
                        if (!logged_plaintext_migration) {
                            message("Qlite: Migrated plain text database to encrypted storage.");
                            logged_plaintext_migration = true;
                        }
                        // Re-open encrypted.
                        db = null;
                        ec = Sqlite.Database.open_v2(file_name, out db, OPEN_READWRITE | OPEN_CREATE | 0x00010000);
                        db.exec(key_pragma, null, null);
                        if (db.exec("SELECT count(*) FROM sqlite_master;", null, null) != Sqlite.OK) {
                            throw new Error(-1, 0, "Qlite: Database migration succeeded but encrypted reopen failed for \"%s\" (Invalid key or corrupted).", file_name);
                        }
                    } else {
                        if (!allow_plaintext_fallback) {
                            throw new Error(-1, 0, "Qlite: Plain text database detected for \"%s\" but encryption migration failed; refusing to run without encryption.", file_name);
                        }
                        if (!logged_plaintext_fallback) {
                            // Not a warning: this can happen on upgrades from versions that stored plaintext.
                            message("Qlite: Plain text database detected; running without encryption because migration failed.");
                            logged_plaintext_fallback = true;
                        }
                    }
                } else {
                    // Encrypted DB but wrong key, or corrupted DB.
                    throw new Error(-1, 0, "Qlite: Failed to open database \"%s\" (Invalid key or corrupted).", file_name);
                }
            }
        }

        this.tables = tables;
        if (debug) db.trace((message) => GLib.debug(@"Qlite trace: $message"));
        start_migration();
    }

    public void close() {
    }

    private bool try_migrate_plaintext_to_encrypted(string key) throws Error {
        // We currently have an *opened plaintext* database connection in `db`.
        // Create a new encrypted database file, export everything, then atomically replace.
        string tmp_path = file_name + ".enc-tmp";

        // Best-effort cleanup of old tmp.
        try { FileUtils.remove(tmp_path); } catch (Error e) { }

        // Escape key for SQL literal.
        string escaped_key = escape_single_quotes(key);

        // Attach a fresh encrypted database and export.
        // sqlcipher_export is provided by SQLCipher.
        string attach = "ATTACH DATABASE '%s' AS encrypted KEY '%s';".printf(escape_single_quotes(tmp_path), escaped_key);
        if (db.exec(attach, null, null) != Sqlite.OK) {
            return false;
        }
        if (db.exec("SELECT sqlcipher_export('encrypted');", null, null) != Sqlite.OK) {
            db.exec("DETACH DATABASE encrypted;", null, null);
            return false;
        }
        db.exec("DETACH DATABASE encrypted;", null, null);

        // Replace original database file.
        // Note: keep the original if replacement fails.
        string backup_path = file_name + ".bak";
        try { FileUtils.remove(backup_path); } catch (Error e) { }

        // Release the current handle before replacing on disk (best-effort).
        // In Vala, clearing the reference drops the underlying handle.
        db = null;

        if (FileUtils.test(file_name, FileTest.EXISTS)) {
            // Rename original away, then move tmp into place.
            if (FileUtils.rename(file_name, backup_path) != 0) {
                // Couldn't move original aside.
                return false;
            }
        }
        if (FileUtils.rename(tmp_path, file_name) != 0) {
            // Restore backup.
            try { FileUtils.rename(backup_path, file_name); } catch (Error e) { }
            return false;
        }
        // Remove backup after successful replace.
        try { FileUtils.remove(backup_path); } catch (Error e) { }
        return true;
    }

    private static string escape_single_quotes(string s) {
        if (s.index_of("'") < 0) return s;

        var b = new GLib.StringBuilder();
        for (int i = 0; i < s.length; i++) {
            char c = s[i];
            if (c == '\'') {
                b.append("''");
            } else {
                b.append_c(c);
            }
        }
        return b.str;
    }

    public void ensure_init() {
        if (tables == null) error(@"Database $file_name was not initialized, call init()");
    }

    private void start_migration() {
        try {
            exec("BEGIN TRANSACTION");
        } catch (Error e) {
            error("SQLite error: %d - %s", db.errcode(), db.errmsg());
        }
        meta_table.create_table_at_version(expected_version);
        long old_version = 0;
        old_version = meta_table.row_with(meta_name, "version")[meta_int_val, -1];
        if (old_version == -1) {
            foreach (Table t in tables) {
                t.create_table_at_version(expected_version);
            }
            meta_table.insert().value(meta_name, "version").value(meta_int_val, expected_version).perform();
        } else if (expected_version != old_version) {
            foreach (Table t in tables) {
                if (t.has_any_column_for_version(old_version)) {
                    t.create_table_at_version(old_version);
                } else {
                    // Table introduced after old_version; create it directly at the new schema version.
                    t.create_table_at_version(expected_version);
                }
            }
            foreach (Table t in tables) {
                if (t.has_any_column_for_version(old_version)) {
                    t.add_columns_for_version(old_version, expected_version);
                }
            }
            migrate(old_version);
            foreach (Table t in tables) {
                if (t.has_any_column_for_version(old_version)) {
                    t.delete_columns_for_version(old_version, expected_version);
                }
            }
            if (old_version == -1) {
                meta_table.insert().value(meta_name, "version").value(meta_int_val, expected_version).perform();
            } else {
                meta_table.update().with(meta_name, "=", "version").set(meta_int_val, expected_version).perform();
            }
        }
        foreach (Table t in tables) {
            t.post();
        }
        try {
            exec("END TRANSACTION");
        } catch (Error e) {
            error("SQLite error: %d - %s", db.errcode(), db.errmsg());
        }
    }

    internal int errcode() {
        return db.errcode();
    }

    internal string errmsg() {
        return db.errmsg();
    }

    internal int64 last_insert_rowid() {
        return db.last_insert_rowid();
    }

    // To be implemented by actual implementation if required
    // new table columns are added, outdated columns are still present and will be removed afterwards
    public virtual void migrate(long old_version) {
    }

    public QueryBuilder select(Column[]? columns = null) {
        ensure_init();
        return new QueryBuilder(this).select(columns);
    }

    internal MatchQueryBuilder match_query(Table table) {
        ensure_init();
        return new MatchQueryBuilder(this, table);
    }

    public InsertBuilder insert() {
        ensure_init();
        return new InsertBuilder(this);
    }

    public UpdateBuilder update(Table table) {
        ensure_init();
        return new UpdateBuilder(this, table);
    }

    public UpsertBuilder upsert(Table table) {
        ensure_init();
        return new UpsertBuilder(this, table);
    }

    public UpdateBuilder update_named(string table) {
        ensure_init();
        return new UpdateBuilder.for_name(this, table);
    }

    public DeleteBuilder delete() {
        ensure_init();
        return new DeleteBuilder(this);
    }

    public RowIterator query_sql(string sql, string[]? args = null) {
        ensure_init();
        return new RowIterator(this, sql, args);
    }

    internal Statement prepare(string sql) {
        ensure_init();
        Sqlite.Statement statement;
        if (db.prepare_v2(sql, sql.length, out statement) != OK) {
            error("SQLite error: %d - %s: %s", db.errcode(), db.errmsg(), sql);
        }
        return statement;
    }

    public void exec(string sql) throws Error {
        ensure_init();
        if (db.exec(sql) != OK) {
            throw new Error(-1, 0, "SQLite error: %d - %s", db.errcode(), db.errmsg());
        }
    }

    public void rekey(string new_key) throws Error {
        ensure_init();
        if (new_key.strip().length == 0) {
            throw new Error(-1, 0, "New database key must not be empty.");
        }

        // SQLCipher: PRAGMA rekey changes the encryption key for the entire database.
        // Escape single quotes for SQL string literal.
        string escaped_key = escape_single_quotes(new_key);
        exec("PRAGMA rekey = '%s';".printf(escaped_key));

        // Verify DB is still readable.
        if (db.exec("SELECT count(*) FROM sqlite_master;", null, null) != Sqlite.OK) {
            throw new Error(-1, 0, "Database rekey failed (Invalid key or corrupted).");
        }
    }

    public bool is_known_column(string table, string field) {
        ensure_init();
        foreach (Table t in tables) {
            if (t.is_known_column(field)) return true;
        }
        return false;
    }
}

}
