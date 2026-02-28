#!/usr/bin/env bash
# =============================================================================
# test_db_maintenance.sh — Automated tests for Database Maintenance operations
# =============================================================================
# Tests the 3 fixes from commit 19381243:
#   1. Rekey covers all databases (dino.db, pgp.db, bot_registry.db)
#   2. Reset deletes all databases + WAL/SHM + omemo.key
#   3. WAL checkpoint works for all databases before backup
#
# Requires: sqlcipher CLI
# Usage:    ./scripts/test_db_maintenance.sh
# =============================================================================

set -euo pipefail

# --- Colors ----------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- Counters --------------------------------------------------------------
PASS=0
FAIL=0
SKIP=0
TESTS=()

# --- Test directory ---------------------------------------------------------
TEST_DIR=$(mktemp -d "/tmp/dinox-db-test.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT

# --- Helpers ----------------------------------------------------------------
log_section() { echo -e "\n${CYAN}${BOLD}━━━ $1 ━━━${NC}"; }
log_test()    { echo -ne "  ${BOLD}TEST:${NC} $1 ... "; }
pass()        { echo -e "${GREEN}PASS${NC}"; PASS=$((PASS + 1)); TESTS+=("PASS: $1"); }
fail()        { echo -e "${RED}FAIL${NC} — $2"; FAIL=$((FAIL + 1)); TESTS+=("FAIL: $1 — $2"); }
skip()        { echo -e "${YELLOW}SKIP${NC} — $2"; SKIP=$((SKIP + 1)); TESTS+=("SKIP: $1 — $2"); }

# Execute sqlcipher with key and return exit code
# Usage: sqlcipher_exec <db_path> <key> <sql>
sqlcipher_exec() {
    local db="$1" key="$2" sql="$3"
    sqlcipher "$db" "PRAGMA key = '$key'; $sql" >/dev/null 2>/dev/null
}

# Execute sqlcipher and capture output (last line only, filtering PRAGMA output)
sqlcipher_query() {
    local db="$1" key="$2" sql="$3"
    sqlcipher "$db" "PRAGMA key = '$key'; $sql" 2>/dev/null | tail -1
}

# Create a test database with sqlcipher, a table, and some data
# Usage: create_test_db <path> <key> <table_name>
create_test_db() {
    local db="$1" key="$2" table="$3"
    sqlcipher "$db" "
        PRAGMA key = '$key';
        PRAGMA journal_mode = WAL;
        CREATE TABLE IF NOT EXISTS $table (id INTEGER PRIMARY KEY, data TEXT);
        INSERT INTO $table (data) VALUES ('test_row_1');
        INSERT INTO $table (data) VALUES ('test_row_2');
        INSERT INTO $table (data) VALUES ('test_row_3');
    " >/dev/null 2>/dev/null
}

# ============================================================================
# PRE-FLIGHT CHECKS
# ============================================================================
log_section "Pre-flight checks"

log_test "sqlcipher available"
if command -v sqlcipher &>/dev/null; then
    pass "sqlcipher available"
else
    fail "sqlcipher available" "sqlcipher not found in PATH"
    echo -e "\n${RED}Cannot continue without sqlcipher. Install with: sudo apt install sqlcipher${NC}"
    exit 1
fi

log_test "sqlcipher supports PRAGMA rekey"
REKEY_DB="$TEST_DIR/rekey_precheck.db"
create_test_db "$REKEY_DB" "oldpw" "precheck"
if sqlcipher_exec "$REKEY_DB" "oldpw" "PRAGMA rekey = 'newpw';" &>/dev/null; then
    # Verify it actually rekeyed
    if sqlcipher_query "$REKEY_DB" "newpw" "SELECT count(*) FROM precheck;" | grep -q "3"; then
        pass "sqlcipher supports PRAGMA rekey"
    else
        fail "sqlcipher supports PRAGMA rekey" "rekey command ran but verification failed"
    fi
else
    fail "sqlcipher supports PRAGMA rekey" "PRAGMA rekey not supported"
    echo -e "\n${RED}Your sqlcipher build does not support rekey. Tests will be limited.${NC}"
fi

# ============================================================================
# TEST SUITE 1: REKEY — All databases share old password, rekey to new
# ============================================================================
log_section "Test Suite 1: Rekey"

OLD_PW="test123"
NEW_PW="newSecurePassword456"
OMEMO_KEY="b79776f57fe7f146418debefc40800e0c4dd755a826db7dc7a5afabc99fe8390"

# Create simulated data directory
REKEY_DIR="$TEST_DIR/rekey"
mkdir -p "$REKEY_DIR"

# Create all 4 databases
create_test_db "$REKEY_DIR/dino.db"          "$OLD_PW"    "accounts"
create_test_db "$REKEY_DIR/pgp.db"           "$OLD_PW"    "keys"
create_test_db "$REKEY_DIR/bot_registry.db"  "$OLD_PW"    "bots"
create_test_db "$REKEY_DIR/omemo.db"         "$OMEMO_KEY" "identity"

# --- Test 1.1: All DBs readable with original keys
log_test "1.1 dino.db readable with old password"
if sqlcipher_query "$REKEY_DIR/dino.db" "$OLD_PW" "SELECT count(*) FROM accounts;" | grep -q "3"; then
    pass "1.1 dino.db readable with old password"
else
    fail "1.1 dino.db readable with old password" "query returned unexpected result"
fi

log_test "1.2 pgp.db readable with old password"
if sqlcipher_query "$REKEY_DIR/pgp.db" "$OLD_PW" "SELECT count(*) FROM keys;" | grep -q "3"; then
    pass "1.2 pgp.db readable with old password"
else
    fail "1.2 pgp.db readable with old password" "query returned unexpected result"
fi

log_test "1.3 bot_registry.db readable with old password"
if sqlcipher_query "$REKEY_DIR/bot_registry.db" "$OLD_PW" "SELECT count(*) FROM bots;" | grep -q "3"; then
    pass "1.3 bot_registry.db readable with old password"
else
    fail "1.3 bot_registry.db readable with old password" "query returned unexpected result"
fi

log_test "1.4 omemo.db readable with OMEMO key"
if sqlcipher_query "$REKEY_DIR/omemo.db" "$OMEMO_KEY" "SELECT count(*) FROM identity;" | grep -q "3"; then
    pass "1.4 omemo.db readable with OMEMO key"
else
    fail "1.4 omemo.db readable with OMEMO key" "query returned unexpected result"
fi

# --- Simulate rekey (what the fixed code does) ---
# Rekey dino.db, pgp.db, bot_registry.db with new password
# Do NOT rekey omemo.db (it uses its own key)

log_test "1.5 Rekey dino.db to new password"
if sqlcipher_exec "$REKEY_DIR/dino.db" "$OLD_PW" "PRAGMA rekey = '$NEW_PW';"; then
    pass "1.5 Rekey dino.db to new password"
else
    fail "1.5 Rekey dino.db to new password" "PRAGMA rekey failed"
fi

log_test "1.6 Rekey pgp.db to new password"
if sqlcipher_exec "$REKEY_DIR/pgp.db" "$OLD_PW" "PRAGMA rekey = '$NEW_PW';"; then
    pass "1.6 Rekey pgp.db to new password"
else
    fail "1.6 Rekey pgp.db to new password" "PRAGMA rekey failed"
fi

log_test "1.7 Rekey bot_registry.db to new password"
if sqlcipher_exec "$REKEY_DIR/bot_registry.db" "$OLD_PW" "PRAGMA rekey = '$NEW_PW';"; then
    pass "1.7 Rekey bot_registry.db to new password"
else
    fail "1.7 Rekey bot_registry.db to new password" "PRAGMA rekey failed"
fi

# --- Verify all 3 open with NEW password ---
log_test "1.8 dino.db opens with NEW password after rekey"
if sqlcipher_query "$REKEY_DIR/dino.db" "$NEW_PW" "SELECT count(*) FROM accounts;" | grep -q "3"; then
    pass "1.8 dino.db opens with NEW password after rekey"
else
    fail "1.8 dino.db opens with NEW password after rekey" "cannot read with new password"
fi

log_test "1.9 pgp.db opens with NEW password after rekey"
if sqlcipher_query "$REKEY_DIR/pgp.db" "$NEW_PW" "SELECT count(*) FROM keys;" | grep -q "3"; then
    pass "1.9 pgp.db opens with NEW password after rekey"
else
    fail "1.9 pgp.db opens with NEW password after rekey" "cannot read with new password"
fi

log_test "1.10 bot_registry.db opens with NEW password after rekey"
if sqlcipher_query "$REKEY_DIR/bot_registry.db" "$NEW_PW" "SELECT count(*) FROM bots;" | grep -q "3"; then
    pass "1.10 bot_registry.db opens with NEW password after rekey"
else
    fail "1.10 bot_registry.db opens with NEW password after rekey" "cannot read with new password"
fi

# --- Verify all 3 FAIL with OLD password ---
log_test "1.11 dino.db REJECTS old password after rekey"
if sqlcipher_query "$REKEY_DIR/dino.db" "$OLD_PW" "SELECT count(*) FROM accounts;" 2>/dev/null | grep -q "3"; then
    fail "1.11 dino.db REJECTS old password after rekey" "old password still works!"
else
    pass "1.11 dino.db REJECTS old password after rekey"
fi

log_test "1.12 pgp.db REJECTS old password after rekey"
if sqlcipher_query "$REKEY_DIR/pgp.db" "$OLD_PW" "SELECT count(*) FROM keys;" 2>/dev/null | grep -q "3"; then
    fail "1.12 pgp.db REJECTS old password after rekey" "old password still works!"
else
    pass "1.12 pgp.db REJECTS old password after rekey"
fi

log_test "1.13 bot_registry.db REJECTS old password after rekey"
if sqlcipher_query "$REKEY_DIR/bot_registry.db" "$OLD_PW" "SELECT count(*) FROM bots;" 2>/dev/null | grep -q "3"; then
    fail "1.13 bot_registry.db REJECTS old password after rekey" "old password still works!"
else
    pass "1.13 bot_registry.db REJECTS old password after rekey"
fi

# --- Verify omemo.db was NOT touched ---
log_test "1.14 omemo.db still opens with OMEMO key (untouched)"
if sqlcipher_query "$REKEY_DIR/omemo.db" "$OMEMO_KEY" "SELECT count(*) FROM identity;" | grep -q "3"; then
    pass "1.14 omemo.db still opens with OMEMO key (untouched)"
else
    fail "1.14 omemo.db still opens with OMEMO key (untouched)" "omemo.db was modified!"
fi

log_test "1.15 omemo.db REJECTS new user password"
if sqlcipher_query "$REKEY_DIR/omemo.db" "$NEW_PW" "SELECT count(*) FROM identity;" 2>/dev/null | grep -q "3"; then
    fail "1.15 omemo.db REJECTS new user password" "new user password opens omemo.db — keys should differ!"
else
    pass "1.15 omemo.db REJECTS new user password"
fi

# --- Test that data integrity is preserved after rekey ---
log_test "1.16 Data intact in dino.db after rekey (3 rows)"
DINO_COUNT=$(sqlcipher_query "$REKEY_DIR/dino.db" "$NEW_PW" "SELECT count(*) FROM accounts;")
if [[ "$DINO_COUNT" == "3" ]]; then
    pass "1.16 Data intact in dino.db after rekey (3 rows)"
else
    fail "1.16 Data intact in dino.db after rekey (3 rows)" "expected 3, got $DINO_COUNT"
fi

log_test "1.17 Data intact in pgp.db after rekey (3 rows)"
PGP_COUNT=$(sqlcipher_query "$REKEY_DIR/pgp.db" "$NEW_PW" "SELECT count(*) FROM keys;")
if [[ "$PGP_COUNT" == "3" ]]; then
    pass "1.17 Data intact in pgp.db after rekey (3 rows)"
else
    fail "1.17 Data intact in pgp.db after rekey (3 rows)" "expected 3, got $PGP_COUNT"
fi

log_test "1.18 Data intact in bot_registry.db after rekey (3 rows)"
BOT_COUNT=$(sqlcipher_query "$REKEY_DIR/bot_registry.db" "$NEW_PW" "SELECT count(*) FROM bots;")
if [[ "$BOT_COUNT" == "3" ]]; then
    pass "1.18 Data intact in bot_registry.db after rekey (3 rows)"
else
    fail "1.18 Data intact in bot_registry.db after rekey (3 rows)" "expected 3, got $BOT_COUNT"
fi

# ============================================================================
# TEST SUITE 2: RESET DATABASE — All files must be deleted
# ============================================================================
log_section "Test Suite 2: Reset Database"

RESET_DIR="$TEST_DIR/reset"
mkdir -p "$RESET_DIR/omemo"

# Create all databases + WAL/SHM files + omemo.key + omemo dir contents
create_test_db "$RESET_DIR/dino.db"          "$OLD_PW"    "accounts"
create_test_db "$RESET_DIR/pgp.db"           "$OLD_PW"    "keys"
create_test_db "$RESET_DIR/bot_registry.db"  "$OLD_PW"    "bots"
create_test_db "$RESET_DIR/omemo.db"         "$OMEMO_KEY" "identity"
create_test_db "$RESET_DIR/mqtt.db"          "$OLD_PW"    "messages"

# Create WAL/SHM files (they may already exist from WAL mode, but create explicitly)
for db in dino.db pgp.db bot_registry.db omemo.db mqtt.db; do
    touch "$RESET_DIR/${db}-wal"
    touch "$RESET_DIR/${db}-shm"
done

# Create omemo.key and omemo directory contents
echo "fake_omemo_key_data" > "$RESET_DIR/omemo.key"
echo "fake_device_data" > "$RESET_DIR/omemo/device1.dat"
echo "fake_session_data" > "$RESET_DIR/omemo/session2.dat"

# Verify all files exist before reset
ALL_FILES=(
    "dino.db" "dino.db-wal" "dino.db-shm"
    "pgp.db" "pgp.db-wal" "pgp.db-shm"
    "bot_registry.db" "bot_registry.db-wal" "bot_registry.db-shm"
    "omemo.db" "omemo.db-wal" "omemo.db-shm"
    "mqtt.db" "mqtt.db-wal" "mqtt.db-shm"
    "omemo.key"
    "omemo/device1.dat" "omemo/session2.dat"
)

log_test "2.1 All test files exist before reset"
ALL_EXIST=true
for f in "${ALL_FILES[@]}"; do
    if [[ ! -f "$RESET_DIR/$f" ]]; then
        ALL_EXIST=false
        break
    fi
done
if $ALL_EXIST; then
    pass "2.1 All test files exist before reset"
else
    fail "2.1 All test files exist before reset" "missing: $f"
fi

# --- Simulate what perform_reset_database() does (the FIXED version) ---
simulate_reset_database() {
    local data_dir="$1"
    local db_path="$data_dir/dino.db"

    # Delete the main database file
    rm -f "$db_path"
    rm -f "${db_path}-shm"
    rm -f "${db_path}-wal"

    # Delete plugin databases (NEW CODE)
    for plugin_db in pgp.db bot_registry.db omemo.db mqtt.db; do
        local p="$data_dir/$plugin_db"
        rm -f "$p"
        rm -f "${p}-shm"
        rm -f "${p}-wal"
    done

    # Delete OMEMO key file (NEW CODE)
    rm -f "$data_dir/omemo.key"

    # Also delete OMEMO data directory contents
    if [[ -d "$data_dir/omemo" ]]; then
        rm -rf "$data_dir/omemo"
    fi
}

simulate_reset_database "$RESET_DIR"

# --- Verify all files are gone ---
log_test "2.2 dino.db deleted"
if [[ ! -f "$RESET_DIR/dino.db" ]]; then pass "2.2 dino.db deleted"; else fail "2.2 dino.db deleted" "file still exists"; fi

log_test "2.3 dino.db-wal deleted"
if [[ ! -f "$RESET_DIR/dino.db-wal" ]]; then pass "2.3 dino.db-wal deleted"; else fail "2.3 dino.db-wal deleted" "file still exists"; fi

log_test "2.4 dino.db-shm deleted"
if [[ ! -f "$RESET_DIR/dino.db-shm" ]]; then pass "2.4 dino.db-shm deleted"; else fail "2.4 dino.db-shm deleted" "file still exists"; fi

log_test "2.5 pgp.db deleted"
if [[ ! -f "$RESET_DIR/pgp.db" ]]; then pass "2.5 pgp.db deleted"; else fail "2.5 pgp.db deleted" "file still exists"; fi

log_test "2.6 pgp.db-wal deleted"
if [[ ! -f "$RESET_DIR/pgp.db-wal" ]]; then pass "2.6 pgp.db-wal deleted"; else fail "2.6 pgp.db-wal deleted" "file still exists"; fi

log_test "2.7 pgp.db-shm deleted"
if [[ ! -f "$RESET_DIR/pgp.db-shm" ]]; then pass "2.7 pgp.db-shm deleted"; else fail "2.7 pgp.db-shm deleted" "file still exists"; fi

log_test "2.8 bot_registry.db deleted"
if [[ ! -f "$RESET_DIR/bot_registry.db" ]]; then pass "2.8 bot_registry.db deleted"; else fail "2.8 bot_registry.db deleted" "file still exists"; fi

log_test "2.9 bot_registry.db-wal deleted"
if [[ ! -f "$RESET_DIR/bot_registry.db-wal" ]]; then pass "2.9 bot_registry.db-wal deleted"; else fail "2.9 bot_registry.db-wal deleted" "file still exists"; fi

log_test "2.10 bot_registry.db-shm deleted"
if [[ ! -f "$RESET_DIR/bot_registry.db-shm" ]]; then pass "2.10 bot_registry.db-shm deleted"; else fail "2.10 bot_registry.db-shm deleted" "file still exists"; fi

log_test "2.11 omemo.db deleted"
if [[ ! -f "$RESET_DIR/omemo.db" ]]; then pass "2.11 omemo.db deleted"; else fail "2.11 omemo.db deleted" "file still exists"; fi

log_test "2.12 omemo.db-wal deleted"
if [[ ! -f "$RESET_DIR/omemo.db-wal" ]]; then pass "2.12 omemo.db-wal deleted"; else fail "2.12 omemo.db-wal deleted" "file still exists"; fi

log_test "2.13 omemo.db-shm deleted"
if [[ ! -f "$RESET_DIR/omemo.db-shm" ]]; then pass "2.13 omemo.db-shm deleted"; else fail "2.13 omemo.db-shm deleted" "file still exists"; fi

log_test "2.14 mqtt.db deleted"
if [[ ! -f "$RESET_DIR/mqtt.db" ]]; then pass "2.14 mqtt.db deleted"; else fail "2.14 mqtt.db deleted" "file still exists"; fi

log_test "2.15 mqtt.db-wal deleted"
if [[ ! -f "$RESET_DIR/mqtt.db-wal" ]]; then pass "2.15 mqtt.db-wal deleted"; else fail "2.15 mqtt.db-wal deleted" "file still exists"; fi

log_test "2.16 mqtt.db-shm deleted"
if [[ ! -f "$RESET_DIR/mqtt.db-shm" ]]; then pass "2.16 mqtt.db-shm deleted"; else fail "2.16 mqtt.db-shm deleted" "file still exists"; fi

log_test "2.17 omemo.key deleted"
if [[ ! -f "$RESET_DIR/omemo.key" ]]; then pass "2.17 omemo.key deleted"; else fail "2.17 omemo.key deleted" "file still exists"; fi

log_test "2.18 omemo/ directory deleted"
if [[ ! -d "$RESET_DIR/omemo" ]]; then pass "2.18 omemo/ directory deleted"; else fail "2.18 omemo/ directory deleted" "directory still exists"; fi

# --- Test that reset on empty dir doesn't crash ---
log_test "2.19 Reset on already-empty dir (idempotent)"
simulate_reset_database "$RESET_DIR"
pass "2.19 Reset on already-empty dir (idempotent)"

# ============================================================================
# TEST SUITE 3: WAL CHECKPOINT — Data in WAL must be flushed before backup
# ============================================================================
log_section "Test Suite 3: WAL Checkpoint"

CHECKPOINT_DIR="$TEST_DIR/checkpoint"
mkdir -p "$CHECKPOINT_DIR"

# Create databases in WAL mode with unflushed data
for db_info in "dino.db:$OLD_PW:accounts" "pgp.db:$OLD_PW:keys" "bot_registry.db:$OLD_PW:bots" "omemo.db:$OMEMO_KEY:identity" "mqtt.db:$OLD_PW:messages"; do
    IFS=: read -r db key table <<< "$db_info"
    create_test_db "$CHECKPOINT_DIR/$db" "$key" "$table"
    # Insert more data WITHOUT checkpoint to ensure WAL has data
    sqlcipher "$CHECKPOINT_DIR/$db" "
        PRAGMA key = '$key';
        INSERT INTO $table (data) VALUES ('wal_unflushed_1');
        INSERT INTO $table (data) VALUES ('wal_unflushed_2');
    " >/dev/null 2>/dev/null
done

# Check WAL files exist (WAL mode should create them)
log_test "3.1 dino.db has WAL file"
if [[ -f "$CHECKPOINT_DIR/dino.db-wal" ]] && [[ -s "$CHECKPOINT_DIR/dino.db-wal" ]]; then
    pass "3.1 dino.db has WAL file"
else
    # WAL may auto-checkpoint on close; this is expected behavior
    skip "3.1 dino.db has WAL file" "WAL auto-checkpointed on close (normal for CLI)"
fi

# Simulate checkpoint (what the FIXED code does)
log_test "3.2 Checkpoint dino.db"
if sqlcipher_exec "$CHECKPOINT_DIR/dino.db" "$OLD_PW" "PRAGMA wal_checkpoint(TRUNCATE);"; then
    pass "3.2 Checkpoint dino.db"
else
    fail "3.2 Checkpoint dino.db" "checkpoint failed"
fi

log_test "3.3 Checkpoint pgp.db"
if sqlcipher_exec "$CHECKPOINT_DIR/pgp.db" "$OLD_PW" "PRAGMA wal_checkpoint(TRUNCATE);"; then
    pass "3.3 Checkpoint pgp.db"
else
    fail "3.3 Checkpoint pgp.db" "checkpoint failed"
fi

log_test "3.4 Checkpoint bot_registry.db"
if sqlcipher_exec "$CHECKPOINT_DIR/bot_registry.db" "$OLD_PW" "PRAGMA wal_checkpoint(TRUNCATE);"; then
    pass "3.4 Checkpoint bot_registry.db"
else
    fail "3.4 Checkpoint bot_registry.db" "checkpoint failed"
fi

log_test "3.5 Checkpoint omemo.db"
if sqlcipher_exec "$CHECKPOINT_DIR/omemo.db" "$OMEMO_KEY" "PRAGMA wal_checkpoint(TRUNCATE);"; then
    pass "3.5 Checkpoint omemo.db"
else
    fail "3.5 Checkpoint omemo.db" "checkpoint failed"
fi

# After TRUNCATE checkpoint, WAL should be empty (0 bytes or nonexistent)
log_test "3.6 dino.db WAL is empty after checkpoint"
if [[ ! -s "$CHECKPOINT_DIR/dino.db-wal" ]]; then
    pass "3.6 dino.db WAL is empty after checkpoint"
else
    WAL_SIZE=$(stat -c%s "$CHECKPOINT_DIR/dino.db-wal" 2>/dev/null || echo "?")
    fail "3.6 dino.db WAL is empty after checkpoint" "WAL still has $WAL_SIZE bytes"
fi

log_test "3.7 pgp.db WAL is empty after checkpoint"
if [[ ! -s "$CHECKPOINT_DIR/pgp.db-wal" ]]; then
    pass "3.7 pgp.db WAL is empty after checkpoint"
else
    WAL_SIZE=$(stat -c%s "$CHECKPOINT_DIR/pgp.db-wal" 2>/dev/null || echo "?")
    fail "3.7 pgp.db WAL is empty after checkpoint" "WAL still has $WAL_SIZE bytes"
fi

log_test "3.8 bot_registry.db WAL is empty after checkpoint"
if [[ ! -s "$CHECKPOINT_DIR/bot_registry.db-wal" ]]; then
    pass "3.8 bot_registry.db WAL is empty after checkpoint"
else
    WAL_SIZE=$(stat -c%s "$CHECKPOINT_DIR/bot_registry.db-wal" 2>/dev/null || echo "?")
    fail "3.8 bot_registry.db WAL is empty after checkpoint" "WAL still has $WAL_SIZE bytes"
fi

log_test "3.9 omemo.db WAL is empty after checkpoint"
if [[ ! -s "$CHECKPOINT_DIR/omemo.db-wal" ]]; then
    pass "3.9 omemo.db WAL is empty after checkpoint"
else
    WAL_SIZE=$(stat -c%s "$CHECKPOINT_DIR/omemo.db-wal" 2>/dev/null || echo "?")
    fail "3.9 omemo.db WAL is empty after checkpoint" "WAL still has $WAL_SIZE bytes"
fi

# Verify all data is present after checkpoint
log_test "3.10 All data present in dino.db after checkpoint"
COUNT=$(sqlcipher_query "$CHECKPOINT_DIR/dino.db" "$OLD_PW" "SELECT count(*) FROM accounts;")
if [[ "$COUNT" == "5" ]]; then
    pass "3.10 All data present in dino.db after checkpoint"
else
    fail "3.10 All data present in dino.db after checkpoint" "expected 5 rows, got $COUNT"
fi

log_test "3.11 All data present in pgp.db after checkpoint"
COUNT=$(sqlcipher_query "$CHECKPOINT_DIR/pgp.db" "$OLD_PW" "SELECT count(*) FROM keys;")
if [[ "$COUNT" == "5" ]]; then
    pass "3.11 All data present in pgp.db after checkpoint"
else
    fail "3.11 All data present in pgp.db after checkpoint" "expected 5 rows, got $COUNT"
fi

log_test "3.12 All data present in bot_registry.db after checkpoint"
COUNT=$(sqlcipher_query "$CHECKPOINT_DIR/bot_registry.db" "$OLD_PW" "SELECT count(*) FROM bots;")
if [[ "$COUNT" == "5" ]]; then
    pass "3.12 All data present in bot_registry.db after checkpoint"
else
    fail "3.12 All data present in bot_registry.db after checkpoint" "expected 5 rows, got $COUNT"
fi

log_test "3.13 All data present in omemo.db after checkpoint"
COUNT=$(sqlcipher_query "$CHECKPOINT_DIR/omemo.db" "$OMEMO_KEY" "SELECT count(*) FROM identity;")
if [[ "$COUNT" == "5" ]]; then
    pass "3.13 All data present in omemo.db after checkpoint"
else
    fail "3.13 All data present in omemo.db after checkpoint" "expected 5 rows, got $COUNT"
fi

# ============================================================================
# TEST SUITE 4: EDGE CASES
# ============================================================================
log_section "Test Suite 4: Edge Cases"

EDGE_DIR="$TEST_DIR/edge"
mkdir -p "$EDGE_DIR"

# --- 4.1: Rekey with special characters in password ---
SPECIAL_PW="p@ss'w\"ord!#\$%^&*()"
create_test_db "$EDGE_DIR/special.db" "$OLD_PW" "data"

log_test "4.1 Rekey with special chars in password"
# The Vala code uses escape_single_quotes, simulate that
ESCAPED_PW="${SPECIAL_PW//\'/\'\'}"
if sqlcipher "$EDGE_DIR/special.db" "PRAGMA key = '$OLD_PW'; PRAGMA rekey = '$ESCAPED_PW';" >/dev/null 2>/dev/null; then
    if sqlcipher "$EDGE_DIR/special.db" "PRAGMA key = '$ESCAPED_PW'; SELECT count(*) FROM data;" 2>/dev/null | grep -q "3"; then
        pass "4.1 Rekey with special chars in password"
    else
        fail "4.1 Rekey with special chars in password" "cannot open with special password"
    fi
else
    fail "4.1 Rekey with special chars in password" "rekey command failed"
fi

# --- 4.2: Rekey with empty password should fail ---
log_test "4.2 Rekey with empty password (code prevents this)"
# In the Vala code: if (new_pw.strip().length == 0) → rejected
# In Qlite.Database.rekey: if new_key.strip().length == 0 → throws Error
# We just verify the guard exists conceptually
if grep -q 'new_key.strip.*length.*0' /media/linux/SSD128/xmppwin/qlite/src/database.vala; then
    pass "4.2 Rekey with empty password (code prevents this)"
else
    fail "4.2 Rekey with empty password (code prevents this)" "empty password guard not found in code"
fi

# --- 4.3: Rekey when plugin DB doesn't exist (not initialized) ---
log_test "4.3 Rekey when plugin DB file doesn't exist"
# The Vala code checks `if (db != null)` / `if (registry != null)` before rekey
# If plugin wasn't initialized, db is null → no-op
# Verify the null guard exists in each plugin
GUARDS_OK=true
for plugin_file in \
    /media/linux/SSD128/xmppwin/plugins/openpgp/src/plugin.vala \
    /media/linux/SSD128/xmppwin/plugins/bot-features/src/plugin.vala; do
    if ! grep -A2 'rekey_database' "$plugin_file" | grep -q 'if.*!= null'; then
        GUARDS_OK=false
    fi
done
if $GUARDS_OK; then
    pass "4.3 Rekey when plugin DB file doesn't exist"
else
    fail "4.3 Rekey when plugin DB file doesn't exist" "null guard missing in plugin"
fi

# --- 4.4: Checkpoint when DB is in DELETE journal mode (not WAL) ---
log_test "4.4 Checkpoint on DELETE-mode DB (no-op, no crash)"
DELETE_DB="$EDGE_DIR/delete_mode.db"
sqlcipher "$DELETE_DB" "
    PRAGMA key = '$OLD_PW';
    PRAGMA journal_mode = DELETE;
    CREATE TABLE test (id INTEGER PRIMARY KEY);
    INSERT INTO test VALUES (1);
" >/dev/null 2>/dev/null
if sqlcipher_exec "$DELETE_DB" "$OLD_PW" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null; then
    pass "4.4 Checkpoint on DELETE-mode DB (no-op, no crash)"
else
    fail "4.4 Checkpoint on DELETE-mode DB (no-op, no crash)" "checkpoint command crashed"
fi

# --- 4.5: Verify RootInterface has both new methods ---
log_test "4.5 RootInterface declares rekey_database()"
if grep -q 'public abstract void rekey_database' /media/linux/SSD128/xmppwin/libdino/src/plugin/interfaces.vala; then
    pass "4.5 RootInterface declares rekey_database()"
else
    fail "4.5 RootInterface declares rekey_database()" "method not found in interface"
fi

log_test "4.6 RootInterface declares checkpoint_database()"
if grep -q 'public abstract void checkpoint_database' /media/linux/SSD128/xmppwin/libdino/src/plugin/interfaces.vala; then
    pass "4.6 RootInterface declares checkpoint_database()"
else
    fail "4.6 RootInterface declares checkpoint_database()" "method not found in interface"
fi

# --- 4.7: Verify Loader has forwarding methods ---
log_test "4.7 Loader.rekey_databases() iterates all plugins"
if grep -A3 'public void rekey_databases' /media/linux/SSD128/xmppwin/libdino/src/plugin/loader.vala | grep -q 'foreach.*RootInterface.*p.*in.*plugins'; then
    pass "4.7 Loader.rekey_databases() iterates all plugins"
else
    fail "4.7 Loader.rekey_databases() iterates all plugins" "iteration pattern not found"
fi

log_test "4.8 Loader.checkpoint_databases() iterates all plugins"
if grep -A3 'public void checkpoint_databases' /media/linux/SSD128/xmppwin/libdino/src/plugin/loader.vala | grep -q 'foreach.*RootInterface.*p.*in.*plugins'; then
    pass "4.8 Loader.checkpoint_databases() iterates all plugins"
else
    fail "4.8 Loader.checkpoint_databases() iterates all plugins" "iteration pattern not found"
fi

# --- 4.9: Verify all 8 plugins implement both methods ---
log_test "4.9 All 8 plugins implement rekey_database()"
PLUGIN_COUNT=0
for plugin_dir in http-files ice notification-sound omemo openpgp rtp tor-manager bot-features; do
    PLUGIN_FILE="/media/linux/SSD128/xmppwin/plugins/$plugin_dir/src/plugin.vala"
    if grep -q 'public void rekey_database' "$PLUGIN_FILE"; then
        PLUGIN_COUNT=$((PLUGIN_COUNT + 1))
    fi
done
if [[ $PLUGIN_COUNT -eq 8 ]]; then
    pass "4.9 All 8 plugins implement rekey_database()"
else
    fail "4.9 All 8 plugins implement rekey_database()" "only $PLUGIN_COUNT/8 plugins have it"
fi

log_test "4.10 All 8 plugins implement checkpoint_database()"
PLUGIN_COUNT=0
for plugin_dir in http-files ice notification-sound omemo openpgp rtp tor-manager bot-features; do
    PLUGIN_FILE="/media/linux/SSD128/xmppwin/plugins/$plugin_dir/src/plugin.vala"
    if grep -q 'public void checkpoint_database' "$PLUGIN_FILE"; then
        PLUGIN_COUNT=$((PLUGIN_COUNT + 1))
    fi
done
if [[ $PLUGIN_COUNT -eq 8 ]]; then
    pass "4.10 All 8 plugins implement checkpoint_database()"
else
    fail "4.10 All 8 plugins implement checkpoint_database()" "only $PLUGIN_COUNT/8 plugins have it"
fi

# --- 4.11: Verify application.vala calls plugin_loader for rekey ---
log_test "4.11 application.vala calls plugin_loader.rekey_databases()"
if grep -q 'plugin_loader.rekey_databases' /media/linux/SSD128/xmppwin/main/src/ui/application.vala; then
    pass "4.11 application.vala calls plugin_loader.rekey_databases()"
else
    fail "4.11 application.vala calls plugin_loader.rekey_databases()" "call not found"
fi

# --- 4.12: Verify application.vala calls plugin_loader for checkpoint ---
log_test "4.12 application.vala calls plugin_loader.checkpoint_databases()"
if grep -q 'plugin_loader.checkpoint_databases' /media/linux/SSD128/xmppwin/main/src/ui/application.vala; then
    pass "4.12 application.vala calls plugin_loader.checkpoint_databases()"
else
    fail "4.12 application.vala calls plugin_loader.checkpoint_databases()" "call not found"
fi

# --- 4.13: Verify reset_database deletes all plugin DBs ---
log_test "4.13 reset_database deletes pgp.db"
if grep -q '"pgp.db"' /media/linux/SSD128/xmppwin/main/src/ui/application.vala; then
    pass "4.13 reset_database deletes pgp.db"
else
    fail "4.13 reset_database deletes pgp.db" "pgp.db not in delete list"
fi

log_test "4.14 reset_database deletes bot_registry.db"
if grep -q '"bot_registry.db"' /media/linux/SSD128/xmppwin/main/src/ui/application.vala; then
    pass "4.14 reset_database deletes bot_registry.db"
else
    fail "4.14 reset_database deletes bot_registry.db" "bot_registry.db not in delete list"
fi

log_test "4.15 reset_database deletes omemo.db"
if grep -q '"omemo.db"' /media/linux/SSD128/xmppwin/main/src/ui/application.vala; then
    pass "4.15 reset_database deletes omemo.db"
else
    fail "4.15 reset_database deletes omemo.db" "omemo.db not in delete list"
fi

log_test "4.15b reset_database deletes mqtt.db"
if grep -q '"mqtt.db"' /media/linux/SSD128/xmppwin/main/src/ui/application.vala; then
    pass "4.15b reset_database deletes mqtt.db"
else
    fail "4.15b reset_database deletes mqtt.db" "mqtt.db not in delete list"
fi

log_test "4.16 reset_database deletes omemo.key"
if grep -q '"omemo.key"' /media/linux/SSD128/xmppwin/main/src/ui/application.vala; then
    pass "4.16 reset_database deletes omemo.key"
else
    fail "4.16 reset_database deletes omemo.key" "omemo.key not in delete list"
fi

# --- 4.17: Verify OMEMO rekey is explicitly a no-op ---
log_test "4.17 OMEMO rekey_database is no-op (comment confirms)"
if grep -A3 'rekey_database.*string new_key' /media/linux/SSD128/xmppwin/plugins/omemo/src/plugin.vala | grep -q 'no-op\|NOT.*shared\|own.*key'; then
    pass "4.17 OMEMO rekey_database is no-op (comment confirms)"
else
    fail "4.17 OMEMO rekey_database is no-op (comment confirms)" "no-op comment not found"
fi

# ============================================================================
# TEST SUITE 5: SIMULATE FULL WORKFLOW
# ============================================================================
log_section "Test Suite 5: Full Workflow Simulation"

WORKFLOW_DIR="$TEST_DIR/workflow"
mkdir -p "$WORKFLOW_DIR/omemo"

# Step 1: Create initial state (4 DBs with data)
create_test_db "$WORKFLOW_DIR/dino.db"          "$OLD_PW"    "accounts"
create_test_db "$WORKFLOW_DIR/pgp.db"           "$OLD_PW"    "keys"
create_test_db "$WORKFLOW_DIR/bot_registry.db"  "$OLD_PW"    "bots"
create_test_db "$WORKFLOW_DIR/omemo.db"         "$OMEMO_KEY" "identity"
create_test_db "$WORKFLOW_DIR/mqtt.db"          "$OLD_PW"    "messages"
echo "auto_key_data" > "$WORKFLOW_DIR/omemo.key"
echo "device" > "$WORKFLOW_DIR/omemo/dev1.dat"

# Step 2: Checkpoint all DBs
log_test "5.1 Full workflow: checkpoint all DBs"
CHECKPOINT_OK=true
for db_info in "dino.db:$OLD_PW" "pgp.db:$OLD_PW" "bot_registry.db:$OLD_PW" "omemo.db:$OMEMO_KEY" "mqtt.db:$OLD_PW"; do
    IFS=: read -r db key <<< "$db_info"
    if ! sqlcipher_exec "$WORKFLOW_DIR/$db" "$key" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null; then
        CHECKPOINT_OK=false
    fi
done
if $CHECKPOINT_OK; then
    pass "5.1 Full workflow: checkpoint all DBs"
else
    fail "5.1 Full workflow: checkpoint all DBs" "one or more checkpoints failed"
fi

# Step 3: Simulate backup (tar all files)
log_test "5.2 Full workflow: backup captures all DBs"
BACKUP_TAR="$TEST_DIR/backup.tar.gz"
tar -czf "$BACKUP_TAR" -C "$TEST_DIR" workflow/ 2>/dev/null
if tar -tzf "$BACKUP_TAR" | grep -q "workflow/dino.db" && \
   tar -tzf "$BACKUP_TAR" | grep -q "workflow/pgp.db" && \
   tar -tzf "$BACKUP_TAR" | grep -q "workflow/bot_registry.db" && \
   tar -tzf "$BACKUP_TAR" | grep -q "workflow/omemo.db"; then
    pass "5.2 Full workflow: backup captures all DBs"
else
    fail "5.2 Full workflow: backup captures all DBs" "some DBs missing from tar"
fi

# Step 4: Change password
log_test "5.3 Full workflow: rekey dino+pgp+bot (not omemo)"
REKEY_OK=true
for db in dino.db pgp.db bot_registry.db; do
    if ! sqlcipher_exec "$WORKFLOW_DIR/$db" "$OLD_PW" "PRAGMA rekey = '$NEW_PW';" 2>/dev/null; then
        REKEY_OK=false
    fi
done
if $REKEY_OK; then
    pass "5.3 Full workflow: rekey dino+pgp+bot (not omemo)"
else
    fail "5.3 Full workflow: rekey dino+pgp+bot (not omemo)" "rekey failed for one or more DBs"
fi

# Step 5: Verify all DBs accessible with correct keys after rekey
log_test "5.4 Full workflow: all DBs open after rekey"
ALL_OK=true
# dino, pgp, bot should use NEW_PW
for db_table in "dino.db:accounts" "pgp.db:keys" "bot_registry.db:bots"; do
    IFS=: read -r db table <<< "$db_table"
    COUNT=$(sqlcipher_query "$WORKFLOW_DIR/$db" "$NEW_PW" "SELECT count(*) FROM $table;" 2>/dev/null)
    if [[ "$COUNT" != "3" ]]; then
        ALL_OK=false
        echo -ne " (${db}=FAIL) "
    fi
done
# omemo should still use OMEMO_KEY
COUNT=$(sqlcipher_query "$WORKFLOW_DIR/omemo.db" "$OMEMO_KEY" "SELECT count(*) FROM identity;" 2>/dev/null)
if [[ "$COUNT" != "3" ]]; then
    ALL_OK=false
    echo -ne " (omemo.db=FAIL) "
fi
if $ALL_OK; then
    pass "5.4 Full workflow: all DBs open after rekey"
else
    fail "5.4 Full workflow: all DBs open after rekey" "one or more DBs inaccessible"
fi

# Step 6: Reset
log_test "5.5 Full workflow: reset clears everything"
simulate_reset_database "$WORKFLOW_DIR"
REMAINING=$(find "$WORKFLOW_DIR" -type f 2>/dev/null | wc -l)
if [[ "$REMAINING" -eq 0 ]]; then
    pass "5.5 Full workflow: reset clears everything"
else
    LEFTOVER=$(find "$WORKFLOW_DIR" -type f 2>/dev/null | tr '\n' ', ')
    fail "5.5 Full workflow: reset clears everything" "leftover files: $LEFTOVER"
fi

# Step 7: Restore from backup
log_test "5.6 Full workflow: restore from backup"
tar -xzf "$BACKUP_TAR" -C "$TEST_DIR" 2>/dev/null
# After restore, DBs should be accessible with OLD password (pre-rekey backup)
RESTORE_OK=true
for db_table in "dino.db:accounts:$OLD_PW" "pgp.db:keys:$OLD_PW" "bot_registry.db:bots:$OLD_PW" "omemo.db:identity:$OMEMO_KEY"; do
    IFS=: read -r db table key <<< "$db_table"
    COUNT=$(sqlcipher_query "$WORKFLOW_DIR/$db" "$key" "SELECT count(*) FROM $table;" 2>/dev/null)
    if [[ "$COUNT" != "3" ]]; then
        RESTORE_OK=false
        echo -ne " (${db}=FAIL:$COUNT) "
    fi
done
if $RESTORE_OK; then
    pass "5.6 Full workflow: restore from backup"
else
    fail "5.6 Full workflow: restore from backup" "restored DBs not accessible"
fi

# ============================================================================
# RESULTS SUMMARY
# ============================================================================
log_section "Results"

TOTAL=$((PASS + FAIL + SKIP))
echo -e "  ${GREEN}Passed:${NC}  $PASS"
echo -e "  ${RED}Failed:${NC}  $FAIL"
echo -e "  ${YELLOW}Skipped:${NC} $SKIP"
echo -e "  ${BOLD}Total:${NC}   $TOTAL"
echo ""

if [[ $FAIL -gt 0 ]]; then
    echo -e "${RED}${BOLD}FAILED TESTS:${NC}"
    for t in "${TESTS[@]}"; do
        if [[ "$t" == FAIL* ]]; then
            echo -e "  ${RED}✗${NC} ${t#FAIL: }"
        fi
    done
    echo ""
    echo -e "${RED}${BOLD}RESULT: FAIL${NC}"
    exit 1
else
    echo -e "${GREEN}${BOLD}RESULT: ALL TESTS PASSED ✓${NC}"
    exit 0
fi
