# 🗄️ Database Schema Documentation

Complete reference for Dino's SQLite database structure.

**Current Version**: 30  
**Database File**: `~/.local/share/dino/dino.db`  
**Engine**: SQLite 3.24+

---

## 📋 Core Tables

### 1. `account` - User XMPP Accounts

```sql
CREATE TABLE account (
    id INTEGER PRIMARY KEY,
    bare_jid TEXT NOT NULL UNIQUE,
    resourcepart TEXT,
    password TEXT,
    alias TEXT,
    enabled INTEGER NOT NULL DEFAULT 1,
    color TEXT
);
```

---

### 2. `message` - Message Storage

```sql
CREATE TABLE message (
    id INTEGER PRIMARY KEY,
    account_id INTEGER NOT NULL,
    counterpart_id INTEGER NOT NULL,
    direction INTEGER NOT NULL,
    type_ INTEGER NOT NULL,
    time INTEGER NOT NULL,
    body TEXT,
    encryption INTEGER NOT NULL DEFAULT 0,
    marked INTEGER NOT NULL DEFAULT 0,
    stanza_id TEXT,
    FOREIGN KEY(account_id) REFERENCES account(id) ON DELETE CASCADE
);
```

**Known Issue**: `body` limited to 65KB in v30 → Fixed in v31 with TEXT type

---

### 3. `conversation` - Active Chats

```sql
CREATE TABLE conversation (
    id INTEGER PRIMARY KEY,
    account_id INTEGER NOT NULL,
    jid_id INTEGER NOT NULL,
    type_ INTEGER NOT NULL,
    encryption INTEGER NOT NULL DEFAULT 0,
    read_up_to_item INTEGER,
    notification INTEGER NOT NULL DEFAULT 0,
    pinned INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY(account_id) REFERENCES account(id) ON DELETE CASCADE
);
```

---

### 4. `file_transfer` - File Metadata

```sql
CREATE TABLE file_transfer (
    id INTEGER PRIMARY KEY,
    account_id INTEGER NOT NULL,
    direction INTEGER NOT NULL,
    file_name TEXT NOT NULL,
    path TEXT,
    mime_type TEXT,
    size INTEGER,
    state INTEGER,
    provider INTEGER NOT NULL,
    FOREIGN KEY(account_id) REFERENCES account(id) ON DELETE CASCADE
);
```

---

### 5. `call` - Call History

```sql
CREATE TABLE call (
    id INTEGER PRIMARY KEY,
    account_id INTEGER NOT NULL,
    counterpart_id INTEGER NOT NULL,
    direction INTEGER NOT NULL,
    time INTEGER NOT NULL,
    end_time INTEGER,
    state INTEGER NOT NULL,
    encryption INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY(account_id) REFERENCES account(id) ON DELETE CASCADE
);
```

---

## 🔗 Foreign Keys

All tables cascade on account deletion:
- `ON DELETE CASCADE` ensures data consistency

---

## 🔄 Migrations

Current migration path: v1 → v2 → ... → v30

**Adding Migration**:
```vala
if (old_version < 31) {
    // Perform migration
    exec("ALTER TABLE message ...");
}
```

---

## 💾 Backup

```bash
# Backup database
cp ~/.local/share/dino/dino.db ~/dino-backup.db

# Or use SQLite backup
sqlite3 ~/.local/share/dino/dino.db ".backup backup.db"
```

---

**Last Updated**: November 19, 2025  
**Schema Version**: 30
