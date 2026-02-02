using Qlite;

using Dino.Entities;
using Xmpp;

namespace Dino.Plugins.OpenPgp {

public class Database : Qlite.Database {
    private const int VERSION = 1;

    public class AccountSetting : Table {
        public Column<int> account_id = new Column.Integer("account_id") { primary_key = true };
        public Column<string> key = new Column.Text("key") { not_null = true };

        internal AccountSetting(Database db) {
            base(db, "account_setting");
            init({account_id, key});
        }
    }

    public class ContactKey : Table {
        public Column<string> jid = new Column.Text("jid") { primary_key = true };
        public Column<string> key = new Column.Text("key") { not_null = true };

        internal ContactKey(Database db) {
            base(db, "contact_key");
            init({jid, key});
        }
    }

    // Tracks which keys have been published to a keyserver
    public class PublishedKey : Table {
        public Column<string> fingerprint = new Column.Text("fingerprint") { primary_key = true };
        public Column<string> keyserver = new Column.Text("keyserver") { not_null = true };
        public Column<int64?> published_at = new Column.Long("published_at") { not_null = true };

        internal PublishedKey(Database db) {
            base(db, "published_key");
            init({fingerprint, keyserver, published_at});
        }
    }

    public AccountSetting account_setting_table { get; private set; }
    public ContactKey contact_key_table { get; private set; }
    public PublishedKey published_key_table { get; private set; }

    public Database(string filename, string? key) throws Error {
        base(filename, VERSION);
        this.account_setting_table = new AccountSetting(this);
        this.contact_key_table = new ContactKey(this);
        this.published_key_table = new PublishedKey(this);
        init({account_setting_table, contact_key_table, published_key_table}, key);

        try {
            exec("PRAGMA journal_mode = WAL");
            exec("PRAGMA synchronous = NORMAL");
            exec("PRAGMA secure_delete = ON");
        } catch (Error e) {
            error("Failed to set OpenPGP database properties: %s", e.message);
        }
    }

    public void set_contact_key(Jid jid, string key) {
        contact_key_table.upsert()
                .value(contact_key_table.jid, jid.to_string(), true)
                .value(contact_key_table.key, key)
                .perform();
    }

    public string? get_contact_key(Jid jid) {
        return contact_key_table.select({contact_key_table.key})
            .with(contact_key_table.jid, "=", jid.to_string())[contact_key_table.key];
    }

    public void set_account_key(Account account, string key) {
        account_setting_table.upsert()
                .value(account_setting_table.account_id, account.id, true)
                .value(account_setting_table.key, key)
                .perform();
    }

    public string? get_account_key(Account account) {
        return account_setting_table.select({account_setting_table.key})
            .with(account_setting_table.account_id, "=", account.id)[account_setting_table.key];
    }

    public void remove_account_key(Account account) {
        account_setting_table.delete()
            .with(account_setting_table.account_id, "=", account.id)
            .perform();
    }

    // Mark a key as published to keyserver
    public void set_key_published(string fingerprint, string keyserver = "hkps://keys.openpgp.org") {
        published_key_table.upsert()
                .value(published_key_table.fingerprint, fingerprint, true)
                .value(published_key_table.keyserver, keyserver)
                .value(published_key_table.published_at, new DateTime.now_utc().to_unix())
                .perform();
    }

    // Check if a key has been published to keyserver
    public bool is_key_published(string fingerprint) {
        var row = published_key_table.select()
            .with(published_key_table.fingerprint, "=", fingerprint)
            .row();
        return row != null;
    }

    // Get keyserver URL where key was published
    public string? get_key_keyserver(string fingerprint) {
        return published_key_table.select({published_key_table.keyserver})
            .with(published_key_table.fingerprint, "=", fingerprint)[published_key_table.keyserver];
    }

    public override void migrate(long oldVersion) {
        if (oldVersion < 1) {
            // Version 1: Added published_key table (auto-created by init)
        }
    }
}

}
