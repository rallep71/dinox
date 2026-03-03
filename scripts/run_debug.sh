#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# DinoX runtime debug launcher — shows ALL GTK/GLib warnings
# that would normally only appear in an AppImage CLI session.
#
# Usage:  ./scripts/run_debug.sh [--fatal] [--filter mqtt]
#
#   --fatal        make GTK warnings fatal (app crashes on warning)
#   --filter STR   only show messages containing STR (e.g. "mqtt", "focus")
#   --valgrind     run under valgrind (memory debugging)
#
# This captures runtime output to logs/runtime_warnings.log
# ──────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
DINOX="$BUILD_DIR/main/dinox"
LOG_DIR="$PROJECT_DIR/logs"
LOG_FILE="$LOG_DIR/runtime_warnings.log"

# ANSI colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

FATAL=false
FILTER=""
USE_VALGRIND=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --fatal)    FATAL=true; shift ;;
        --filter)   FILTER="$2"; shift 2 ;;
        --valgrind) USE_VALGRIND=true; shift ;;
        --help|-h)
            echo "Usage: $0 [--fatal] [--filter STR] [--valgrind]"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [ ! -f "$DINOX" ]; then
    echo -e "${RED}ERROR: $DINOX not found. Build first: ./scripts/build.sh${NC}"
    exit 1
fi

mkdir -p "$LOG_DIR"

echo -e "${CYAN}━━━ DinoX Debug Launcher ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Binary:   $DINOX"
echo -e "  Log:      $LOG_FILE"
echo -e "  Fatal:    $FATAL"
[ -n "$FILTER" ] && echo -e "  Filter:   $FILTER"
echo ""

# ── Environment ───────────────────────────────────────────────
# Show ALL debug messages (GLib, GTK, Adw, MQTT plugin, etc.)
export G_MESSAGES_DEBUG=all

# Optional: Make warnings fatal
if $FATAL; then
    export G_DEBUG=fatal-warnings
    echo -e "${RED}⚠  FATAL MODE: GTK/GLib warnings will crash the app!${NC}"
    echo ""
fi

# ── Launch ────────────────────────────────────────────────────
echo -e "${GREEN}▸ Launching DinoX...${NC}"
echo -e "  (Runtime warnings will appear below and in $LOG_FILE)"
echo ""

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
{
    echo "═══════════════════════════════════════════════════════"
    echo "  DinoX Debug Session — $TIMESTAMP"
    echo "  Fatal: $FATAL | Filter: ${FILTER:-none}"
    echo "═══════════════════════════════════════════════════════"
    echo ""
} > "$LOG_FILE"

# Temporarily allow non-zero exits so the post-run analysis always runs.
# DinoX may exit via Ctrl+C (128+SIGINT=130), and grep --filter returns 1
# when no lines match — both would crash the script under set -e.
set +e

# Run DinoX, tee output to log, optionally filter
if [ -n "$FILTER" ]; then
    if $USE_VALGRIND; then
        valgrind --leak-check=full "$DINOX" 2>&1 | tee -a "$LOG_FILE" | grep -i --color=auto "$FILTER"
    else
        "$DINOX" 2>&1 | tee -a "$LOG_FILE" | grep -i --color=auto "$FILTER"
    fi
else
    if $USE_VALGRIND; then
        valgrind --leak-check=full "$DINOX" 2>&1 | tee -a "$LOG_FILE"
    else
        "$DINOX" 2>&1 | tee -a "$LOG_FILE"
    fi
fi

EXIT_CODE=${PIPESTATUS[0]}  # Exit code of DinoX (first command in pipeline)
set -e

echo ""
echo -e "${CYAN}━━━ DinoX exited (code $EXIT_CODE) ━━━━━━━━━━━━━━━━━━━━━${NC}"

# ── Post-run analysis ─────────────────────────────────────────
WARN_COUNT=$(grep -ci "warning\|critical\|error" "$LOG_FILE" 2>/dev/null || echo "0")
if [ "$WARN_COUNT" -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}━━━ Runtime Warnings/Errors Found: $WARN_COUNT ━━━━━━━━━━━${NC}"
    grep -i "warning\|critical\|error" "$LOG_FILE" | sort | uniq -c | sort -rn | head -20
    echo ""
    echo -e "  Full log: $LOG_FILE"
else
    echo -e "  ${GREEN}No runtime warnings — clean run!${NC}"
fi
