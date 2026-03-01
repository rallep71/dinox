using Gee;

namespace Dino.Plugins.BotFeatures {

public class BotRegistry : Qlite.Database {
    private const int VERSION = 3;

    // Fired after a bot is deleted, with the owner JID, bot ID, and bot details
    public signal void bot_deleted(string owner_jid, int bot_id, string? bot_jid, string? bot_mode);

    // Fired when per-account Botmother is toggled on/off
    public signal void account_toggled(string account_jid, bool enabled);

    // Fired when a bot's status changes (active/disabled)
    public signal void bot_status_changed(int bot_id, string new_status);

    // --- Bot Table ---
    public class BotTable : Qlite.Table {
        public Qlite.Column<int> id = new Qlite.Column.Integer("id") { primary_key = true, auto_increment = true };
        public Qlite.Column<string> name_ = new Qlite.Column.Text("name") { not_null = true };
        public Qlite.Column<string> jid = new Qlite.Column.Text("jid");
        public Qlite.Column<string> token_hash = new Qlite.Column.Text("token_hash") { unique = true };
        public Qlite.Column<string> token_raw = new Qlite.Column.Text("token_raw") { min_version = 2 };
        public Qlite.Column<string> owner_jid = new Qlite.Column.Text("owner_jid") { not_null = true };
        public Qlite.Column<string> description = new Qlite.Column.Text("description");
        public Qlite.Column<string> permissions = new Qlite.Column.Text("permissions") { @default = "'all'" };
        public Qlite.Column<string> status = new Qlite.Column.Text("status") { @default = "'active'" };
        public Qlite.Column<string> mode = new Qlite.Column.Text("mode") { @default = "'personal'" };
        public Qlite.Column<long> created_at = new Qlite.Column.Long("created_at");
        public Qlite.Column<long> last_active = new Qlite.Column.Long("last_active");
        public Qlite.Column<string> webhook_url = new Qlite.Column.Text("webhook_url");
        public Qlite.Column<string> webhook_secret = new Qlite.Column.Text("webhook_secret");
        public Qlite.Column<bool> webhook_enabled = new Qlite.Column.BoolInt("webhook_enabled");
        public Qlite.Column<string> bot_password = new Qlite.Column.Text("bot_password") { min_version = 3 };

        internal BotTable(Qlite.Database db) {
            base(db, "bot");
            init({id, name_, jid, token_hash, token_raw, owner_jid, description, permissions, status, mode,
                  created_at, last_active, webhook_url, webhook_secret, webhook_enabled, bot_password});
        }
    }

    // --- Bot Commands Table ---
    public class BotCommandTable : Qlite.Table {
        public Qlite.Column<int> id = new Qlite.Column.Integer("id") { primary_key = true, auto_increment = true };
        public Qlite.Column<int> bot_id = new Qlite.Column.Integer("bot_id") { not_null = true };
        public Qlite.Column<string> command = new Qlite.Column.Text("command") { not_null = true };
        public Qlite.Column<string> description = new Qlite.Column.Text("description");

        internal BotCommandTable(Qlite.Database db) {
            base(db, "bot_command");
            init({id, bot_id, command, description});
        }
    }

    // --- Update Queue Table (for getUpdates long-poll) ---
    public class UpdateTable : Qlite.Table {
        public Qlite.Column<int> id = new Qlite.Column.Integer("id") { primary_key = true, auto_increment = true };
        public Qlite.Column<int> bot_id = new Qlite.Column.Integer("bot_id") { not_null = true };
        public Qlite.Column<string> update_type = new Qlite.Column.Text("update_type") { not_null = true };
        public Qlite.Column<string> payload = new Qlite.Column.Text("payload") { not_null = true };
        public Qlite.Column<long> created_at = new Qlite.Column.Long("created_at");

        internal UpdateTable(Qlite.Database db) {
            base(db, "update_queue");
            init({id, bot_id, update_type, payload, created_at});
        }
    }

    // --- Settings Table ---
    public class SettingsTable : Qlite.Table {
        public Qlite.Column<string> key_ = new Qlite.Column.Text("key") { primary_key = true };
        public Qlite.Column<string> value_ = new Qlite.Column.Text("value");

        internal SettingsTable(Qlite.Database db) {
            base(db, "settings");
            init({key_, value_});
        }
    }

    // --- Audit Log Table ---
    public class AuditLogTable : Qlite.Table {
        public Qlite.Column<int> id = new Qlite.Column.Integer("id") { primary_key = true, auto_increment = true };
        public Qlite.Column<int> bot_id = new Qlite.Column.Integer("bot_id");
        public Qlite.Column<string> action = new Qlite.Column.Text("action") { not_null = true };
        public Qlite.Column<string> details = new Qlite.Column.Text("details");
        public Qlite.Column<string> ip_address = new Qlite.Column.Text("ip_address");
        public Qlite.Column<long> timestamp = new Qlite.Column.Long("timestamp");

        internal AuditLogTable(Qlite.Database db) {
            base(db, "audit_log");
            init({id, bot_id, action, details, ip_address, timestamp});
        }
    }

    public BotTable bot;
    public BotCommandTable bot_command;
    public UpdateTable update_queue;
    public SettingsTable settings;
    public AuditLogTable audit_log;

    public BotRegistry(string db_path, string? key = null) throws Error {
        base(db_path, VERSION);
        bot = new BotTable(this);
        bot_command = new BotCommandTable(this);
        update_queue = new UpdateTable(this);
        settings = new SettingsTable(this);
        audit_log = new AuditLogTable(this);
        init({bot, bot_command, update_queue, settings, audit_log}, key);

        try {
            exec("PRAGMA journal_mode = WAL");
            exec("PRAGMA synchronous = NORMAL");
            exec("PRAGMA secure_delete = ON");
        } catch (Error e) {
            warning("BotRegistry: PRAGMA error: %s", e.message);
        }
    }

    // --- Bot CRUD ---

    public int create_bot(string name, string owner_jid, string token_hash, string mode = "personal",
                          string? jid = null, string? description = null) {
        long now = (long) new DateTime.now_utc().to_unix();
        bot.insert()
            .value(bot.name_, name)
            .value(bot.owner_jid, owner_jid)
            .value(bot.token_hash, token_hash)
            .value(bot.mode, mode)
            .value(bot.created_at, now)
            .value(bot.last_active, now)
            .value(bot.status, "active")
            .value(bot.jid, jid)
            .value(bot.description, description)
            .value(bot.webhook_enabled, false)
            .perform();
        // BUG-04 fix: Use last_insert_rowid() instead of SELECT max(id) to avoid race conditions
        int result_id = 0;
        try {
            foreach (Qlite.Row row in bot.select({bot.id}).with(bot.name_, "=", name).with(bot.owner_jid, "=", owner_jid).with(bot.created_at, "=", now).order_by(bot.id, "DESC").limit(1)) {
                result_id = bot.id.get(row);
            }
        } catch (Error e) {
            warning("BotRegistry: Failed to get last insert id: %s", e.message);
        }
        return result_id;
    }

    public BotInfo? get_bot_by_id(int bot_id) {
        Qlite.RowOption row = bot.row_with(bot.id, bot_id);
        if (row.is_present()) {
            return bot_info_from_row(row.inner);
        }
        return null;
    }

    public BotInfo? get_bot_by_token_hash(string hash) {
        Qlite.RowOption row = bot.select().with(bot.token_hash, "=", hash).row();
        if (row.is_present()) {
            return bot_info_from_row(row.inner);
        }
        return null;
    }

    public Gee.List<BotInfo> get_bots_by_owner(string owner_jid) {
        var result = new ArrayList<BotInfo>();
        foreach (Qlite.Row row in bot.select().with(bot.owner_jid, "=", owner_jid)) {
            result.add(bot_info_from_row(row));
        }
        return result;
    }

    public Gee.List<BotInfo> get_all_active_bots() {
        var result = new ArrayList<BotInfo>();
        foreach (Qlite.Row row in bot.select().with(bot.status, "=", "active")) {
            result.add(bot_info_from_row(row));
        }
        return result;
    }

    public Gee.List<BotInfo> get_all_bots() {
        var result = new ArrayList<BotInfo>();
        foreach (Qlite.Row row in bot.select()) {
            result.add(bot_info_from_row(row));
        }
        return result;
    }

    public void update_bot_token_hash(int bot_id, string new_hash) {
        bot.update().with(bot.id, "=", bot_id).set(bot.token_hash, new_hash).perform();
    }

    public void update_bot_token_raw(int bot_id, string raw_token) {
        bot.update().with(bot.id, "=", bot_id).set(bot.token_raw, raw_token).perform();
    }

    public void update_bot_status(int bot_id, string status) {
        bot.update().with(bot.id, "=", bot_id).set(bot.status, status).perform();
    }

    public void update_bot_password(int bot_id, string password) {
        bot.update().with(bot.id, "=", bot_id).set(bot.bot_password, password).perform();
    }

    public void update_bot_last_active(int bot_id) {
        long now = (long) new DateTime.now_utc().to_unix();
        bot.update().with(bot.id, "=", bot_id).set(bot.last_active, now).perform();
    }

    public void set_webhook(int bot_id, string? url, string? secret, bool enabled) {
        bot.update().with(bot.id, "=", bot_id)
            .set(bot.webhook_url, url)
            .set(bot.webhook_secret, secret)
            .set(bot.webhook_enabled, enabled)
            .perform();
    }

    public void delete_bot(int bot_id) {
        // Look up owner and bot details before deleting
        string? owner = null;
        string? jid = null;
        string? mode = null;
        BotInfo? info = get_bot_by_id(bot_id);
        if (info != null) {
            owner = info.owner_jid;
            jid = info.jid;
            mode = info.mode;
        }

        bot_command.delete().with(bot_command.bot_id, "=", bot_id).perform();
        update_queue.delete().with(update_queue.bot_id, "=", bot_id).perform();
        bot.delete().with(bot.id, "=", bot_id).perform();

        if (owner != null) {
            bot_deleted(owner, bot_id, jid, mode);
        }
    }

    // --- Bot Commands CRUD ---

    public void set_bot_commands(int bot_id, Gee.List<CommandInfo> commands) {
        bot_command.delete().with(bot_command.bot_id, "=", bot_id).perform();
        foreach (CommandInfo cmd in commands) {
            bot_command.insert()
                .value(bot_command.bot_id, bot_id)
                .value(bot_command.command, cmd.command)
                .value(bot_command.description, cmd.description)
                .perform();
        }
    }

    public Gee.List<CommandInfo> get_bot_commands(int bot_id) {
        var result = new ArrayList<CommandInfo>();
        foreach (Qlite.Row row in bot_command.select().with(bot_command.bot_id, "=", bot_id)) {
            result.add(new CommandInfo(
                bot_command.command.get(row),
                bot_command.description.get(row)
            ));
        }
        return result;
    }

    // --- Update Queue ---

    public int enqueue_update(int bot_id, string update_type, string payload) {
        long now = (long) new DateTime.now_utc().to_unix();
        update_queue.insert()
            .value(update_queue.bot_id, bot_id)
            .value(update_queue.update_type, update_type)
            .value(update_queue.payload, payload)
            .value(update_queue.created_at, now)
            .perform();
        // Get the last inserted update ID
        int result_id = 0;
        foreach (Qlite.Row row in update_queue.select({update_queue.id}).order_by(update_queue.id, "DESC").limit(1)) {
            result_id = update_queue.id.get(row);
        }
        return result_id;
    }

    public Gee.List<UpdateInfo> get_updates(int bot_id, int offset = 0, int limit = 100) {
        var result = new ArrayList<UpdateInfo>();
        foreach (Qlite.Row row in update_queue.select()
                    .with(update_queue.bot_id, "=", bot_id)
                    .with(update_queue.id, ">", offset)
                    .order_by(update_queue.id, "ASC")
                    .limit(limit)) {
            result.add(new UpdateInfo(
                update_queue.id.get(row),
                update_queue.bot_id.get(row),
                update_queue.update_type.get(row),
                update_queue.payload.get(row),
                update_queue.created_at.get(row)
            ));
        }
        return result;
    }

    public void delete_updates_up_to(int bot_id, int update_id) {
        update_queue.delete()
            .with(update_queue.bot_id, "=", bot_id)
            .with(update_queue.id, "<=", update_id)
            .perform();
    }

    // Cleanup old updates (older than 24h)
    public void cleanup_old_updates() {
        long cutoff = (long) new DateTime.now_utc().to_unix() - 86400;
        update_queue.delete().with(update_queue.created_at, "<", cutoff).perform();
    }

    // --- Settings ---

    public string? get_setting(string key) {
        Qlite.RowOption row = settings.row_with(settings.key_, key);
        if (row.is_present()) {
            return settings.value_.get(row.inner);
        }
        return null;
    }

    public void set_setting(string key, string value) {
        settings.upsert()
            .value(settings.key_, key, true)
            .value(settings.value_, value)
            .perform();
    }

    public void delete_setting(string key) {
        settings.delete().with(settings.key_, "=", key).perform();
    }

    // --- Audit Log ---

    public void log_action(int bot_id, string action, string? details = null, string? ip = null) {
        long now = (long) new DateTime.now_utc().to_unix();
        audit_log.insert()
            .value(audit_log.bot_id, bot_id)
            .value(audit_log.action, action)
            .value(audit_log.details, details)
            .value(audit_log.ip_address, ip)
            .value(audit_log.timestamp, now)
            .perform();
    }

    // --- Helper ---

    private BotInfo bot_info_from_row(Qlite.Row row) {
        var info = new BotInfo();
        info.id = bot.id.get(row);
        info.name = bot.name_.get(row);
        info.jid = bot.jid.get(row);
        info.token_hash = bot.token_hash.get(row);
        info.token_raw = bot.token_raw.get(row);
        info.owner_jid = bot.owner_jid.get(row);
        info.description = bot.description.get(row);
        info.permissions = bot.permissions.get(row);
        info.status = bot.status.get(row);
        info.mode = bot.mode.get(row);
        info.created_at = bot.created_at.get(row);
        info.last_active = bot.last_active.get(row);
        info.webhook_url = bot.webhook_url.get(row);
        info.webhook_secret = bot.webhook_secret.get(row);
        info.webhook_enabled = bot.webhook_enabled.get(row);
        info.bot_password = bot.bot_password.get(row);
        return info;
    }
}

// --- Data Classes ---

public class BotInfo : Object {
    public int id { get; set; }
    public string? name { get; set; }
    public string? jid { get; set; }
    public string? token_hash { get; set; }
    public string? token_raw { get; set; }
    public string? owner_jid { get; set; }
    public string? description { get; set; }
    public string? permissions { get; set; }
    public string? status { get; set; }
    public string? mode { get; set; }
    public long created_at { get; set; }
    public long last_active { get; set; }
    public string? webhook_url { get; set; }
    public string? webhook_secret { get; set; }
    public bool webhook_enabled { get; set; }
    public string? bot_password { get; set; }
}

public class CommandInfo : Object {
    public string command { get; set; }
    public string? description { get; set; }

    public CommandInfo(string command, string? description) {
        this.command = command;
        this.description = description;
    }
}

public class UpdateInfo : Object {
    public int id { get; set; }
    public int bot_id { get; set; }
    public string update_type { get; set; }
    public string payload { get; set; }
    public long created_at { get; set; }

    public UpdateInfo(int id, int bot_id, string update_type, string payload, long created_at) {
        this.id = id;
        this.bot_id = bot_id;
        this.update_type = update_type;
        this.payload = payload;
        this.created_at = created_at;
    }
}

}
