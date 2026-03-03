#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# DinoX build wrapper — captures ALL compiler warnings and
# fails the build if any new warnings appear.
#
# Usage:  ./scripts/build.sh [--clean] [--strict] [--run]
#
#   --clean    full rebuild (ninja clean first)
#   --strict   treat warnings as errors (fail on ANY warning)
#   --run      launch DinoX after successful build
#
# Output:
#   build_log.txt           full build output
#   build_warnings.txt      extracted warnings only
# ──────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
LOG_FILE="$PROJECT_DIR/build_log.txt"
WARN_FILE="$PROJECT_DIR/build_warnings.txt"

# ANSI colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

DO_CLEAN=false
STRICT=false
DO_RUN=false

for arg in "$@"; do
    case "$arg" in
        --clean)  DO_CLEAN=true ;;
        --strict) STRICT=true ;;
        --run)    DO_RUN=true ;;
        --help|-h)
            echo "Usage: $0 [--clean] [--strict] [--run]"
            echo "  --clean    full rebuild"
            echo "  --strict   fail on any warning"
            echo "  --run      launch DinoX after build"
            exit 0
            ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

cd "$BUILD_DIR"

echo -e "${CYAN}━━━ DinoX Build ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Project:  $PROJECT_DIR"
echo -e "  Build:    $BUILD_DIR"
echo -e "  Strict:   $STRICT"
echo ""

# ── Clean ─────────────────────────────────────────────────────
if $DO_CLEAN; then
    echo -e "${YELLOW}▸ Cleaning build artifacts...${NC}"
    ninja clean 2>&1 | tail -1
    echo ""
fi

# ── Build ─────────────────────────────────────────────────────
echo -e "${CYAN}▸ Building...${NC}"
BUILD_START=$(date +%s)

# Capture full output, show progress, save to log
# Temporarily disable -e so a build failure reaches the error handler below
set +e
ninja 2>&1 | tee "$LOG_FILE"
BUILD_EXIT=${PIPESTATUS[0]}
set -e

BUILD_END=$(date +%s)
BUILD_TIME=$((BUILD_END - BUILD_START))

echo ""

if [ $BUILD_EXIT -ne 0 ]; then
    echo -e "${RED}━━━ BUILD FAILED ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  Full log: $LOG_FILE"
    exit 1
fi

# ── Extract warnings ──────────────────────────────────────────
# Vala warnings: "file.vala:line: warning: ..."
# C warnings:    "file.c:line: warning: ..."
grep -iE "\.vala:[0-9].*warning:|\.c:[0-9]+:[0-9]+: warning:" "$LOG_FILE" \
    | grep -v "^$" \
    > "$WARN_FILE" 2>/dev/null || true

WARN_COUNT=$(wc -l < "$WARN_FILE" | tr -d ' ')

echo -e "${GREEN}━━━ BUILD SUCCEEDED ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Time:     ${BUILD_TIME}s"
echo -e "  Log:      $LOG_FILE"

# ── Warning report ────────────────────────────────────────────
if [ "$WARN_COUNT" -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}━━━ ⚠  $WARN_COUNT COMPILER WARNING(S) ━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    cat "$WARN_FILE" | while IFS= read -r line; do
        echo -e "  ${YELLOW}⚠${NC}  $line"
    done
    echo ""
    echo -e "  Saved to: $WARN_FILE"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if $STRICT; then
        echo ""
        echo -e "${RED}  STRICT MODE: Failing build due to $WARN_COUNT warning(s).${NC}"
        echo -e "${RED}  Fix warnings or build without --strict.${NC}"
        exit 1
    fi
else
    echo -e "  Warnings: ${GREEN}0 — clean build!${NC}"
fi

echo ""

# ── Run ───────────────────────────────────────────────────────
if $DO_RUN; then
    echo -e "${CYAN}▸ Launching DinoX with G_MESSAGES_DEBUG...${NC}"
    echo ""
    # Enable ALL debug output so GTK warnings are visible
    export G_MESSAGES_DEBUG=all
    # Make GTK warnings fatal so they crash instead of hiding
    # Uncomment the next line to make warnings fatal:
    # export G_DEBUG=fatal-warnings
    exec "$BUILD_DIR/main/dinox"
fi
