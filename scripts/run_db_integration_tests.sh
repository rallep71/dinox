#!/usr/bin/env bash
# =============================================================================
# run_db_integration_tests.sh
# =============================================================================
# Compiles and runs the Vala integration test for Database Maintenance.
# Tests the ACTUAL Qlite.Database code paths (rekey, checkpoint, init, exec).
#
# Only depends on libqlite.so — no plugin VAPIs needed.
# The plugin rekey/checkpoint code is just  db.rekey(key)  and
# db.exec("PRAGMA wal_checkpoint(TRUNCATE)"), so proving Qlite works
# proves the plugins work.
#
# Usage: ./scripts/run_db_integration_tests.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
TEST_SRC="$PROJECT_DIR/tests/test_db_maintenance_integration.vala"
TEST_BIN="$BUILD_DIR/test_db_maintenance_integration"

echo "╔══════════════════════════════════════════════════╗"
echo "║  Building DB Maintenance Integration Test        ║"
echo "╚══════════════════════════════════════════════════╝"

# Check prerequisites
if ! command -v valac &>/dev/null; then
    echo "ERROR: valac not found. Install with: sudo apt install valac"
    exit 1
fi

QLITE_SO="$BUILD_DIR/qlite/libqlite.so"
QLITE_VAPI="$BUILD_DIR/qlite/qlite.vapi"

for f in "$QLITE_SO" "$QLITE_VAPI"; do
    if [[ ! -f "$f" ]]; then
        echo "ERROR: Missing: $f"
        echo "Run 'ninja -C build' first."
        exit 1
    fi
done

echo "Compiling: $TEST_SRC"

valac \
    --vapidir="$BUILD_DIR/qlite" \
    --vapidir="$PROJECT_DIR/qlite/vapi" \
    --pkg=qlite \
    --pkg=gio-2.0 \
    --pkg=gee-0.8 \
    --pkg=posix \
    -X -I"$BUILD_DIR/qlite" \
    -X -L"$BUILD_DIR/qlite" \
    -X -lqlite \
    -X "$(pkg-config --cflags sqlcipher 2>/dev/null || echo '')" \
    -o "$TEST_BIN" \
    "$TEST_SRC" \
    2>&1

echo ""
echo "Compilation successful."
echo ""
echo "Running: $TEST_BIN"
echo "──────────────────────────────────────────────────"

export LD_LIBRARY_PATH="$BUILD_DIR/qlite:${LD_LIBRARY_PATH:-}"

exec "$TEST_BIN"
