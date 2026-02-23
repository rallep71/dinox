#!/bin/bash
# DinoX -- Complete Test Runner
# Runs all automated tests and displays a summary.
#
# Usage:
#   ./scripts/run_all_tests.sh          # run all
#   ./scripts/run_all_tests.sh --meson  # meson only
#   ./scripts/run_all_tests.sh --db     # DB tests only
#
# Exit code: 0 if all pass, 1 if any fail.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

# Counters
TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0
SUITE_RESULTS=()

run_suite() {
    local name="$1"
    local cmd="$2"
    local pass=0
    local fail=0

    echo ""
    echo -e "${BOLD}>>> $name${NC}"
    echo "    Command: $cmd"
    echo ""

    if eval "$cmd"; then
        pass=1
        SUITE_RESULTS+=("${GREEN}PASS${NC}  $name")
    else
        fail=1
        SUITE_RESULTS+=("${RED}FAIL${NC}  $name")
    fi

    TOTAL_PASS=$((TOTAL_PASS + pass))
    TOTAL_FAIL=$((TOTAL_FAIL + fail))
}

run_meson_tests() {
    echo -e "${BOLD}============================================${NC}"
    echo -e "${BOLD} Meson Tests (6 suites, 361 tests)${NC}"
    echo -e "${BOLD}============================================${NC}"

    # Build first
    if ! ninja -C build 2>&1 | tail -5; then
        echo -e "${RED}BUILD FAILED${NC}"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
        SUITE_RESULTS+=("${RED}FAIL${NC}  Meson build")
        return 1
    fi

    run_suite "main-test (16 UI ViewModel tests)" \
        "meson test -C build 'Tests for main' --print-errorlogs"

    run_suite "xmpp-vala-test (67 XMPP protocol tests)" \
        "meson test -C build 'Tests for xmpp-vala' --print-errorlogs"

    run_suite "libdino-test (29 crypto + data structure tests)" \
        "meson test -C build 'Tests for libdino' --print-errorlogs"

    run_suite "omemo-test (10 Signal Protocol tests)" \
        "meson test -C build 'Tests for omemo' --print-errorlogs"

    run_suite "bot-features-test (24 rate limiter + crypto tests)" \
        "meson test -C build 'bot-features-test' --print-errorlogs"
}

run_db_tests() {
    echo ""
    echo -e "${BOLD}============================================${NC}"
    echo -e "${BOLD} DB Maintenance Tests (136 standalone)${NC}"
    echo -e "${BOLD}============================================${NC}"

    if command -v sqlcipher &>/dev/null; then
        if [[ -x "$PROJECT_DIR/scripts/test_db_maintenance.sh" ]]; then
            run_suite "DB CLI tests (71 bash tests)" \
                "$PROJECT_DIR/scripts/test_db_maintenance.sh"
        else
            echo -e "${YELLOW}SKIP${NC}: scripts/test_db_maintenance.sh not found or not executable"
            TOTAL_SKIP=$((TOTAL_SKIP + 1))
        fi
    else
        echo -e "${YELLOW}SKIP${NC}: sqlcipher not in PATH (required for DB CLI tests)"
        TOTAL_SKIP=$((TOTAL_SKIP + 1))
    fi

    if [[ -x "$PROJECT_DIR/scripts/run_db_integration_tests.sh" ]]; then
        run_suite "DB Integration tests (65 Vala tests)" \
            "$PROJECT_DIR/scripts/run_db_integration_tests.sh"
    else
        echo -e "${YELLOW}SKIP${NC}: scripts/run_db_integration_tests.sh not found or not executable"
        TOTAL_SKIP=$((TOTAL_SKIP + 1))
    fi
}

# Parse arguments
RUN_MESON=true
RUN_DB=true

if [[ "${1:-}" == "--meson" ]]; then
    RUN_DB=false
elif [[ "${1:-}" == "--db" ]]; then
    RUN_MESON=false
elif [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [--meson|--db|--help]"
    echo ""
    echo "  --meson   Run only Meson-registered tests (361 tests)"
    echo "  --db      Run only DB maintenance tests (136 tests)"
    echo "  --help    Show this help"
    echo ""
    echo "Without arguments: run all tests (497 total)"
    exit 0
fi

echo -e "${BOLD}==========================================${NC}"
echo -e "${BOLD} DinoX -- Complete Test Run${NC}"
echo -e "${BOLD}==========================================${NC}"
echo "  Date:    $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Branch:  $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
echo "  Commit:  $(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"

if $RUN_MESON; then run_meson_tests; fi
if $RUN_DB; then run_db_tests; fi

# Summary
echo ""
echo -e "${BOLD}==========================================${NC}"
echo -e "${BOLD} Summary${NC}"
echo -e "${BOLD}==========================================${NC}"
for result in "${SUITE_RESULTS[@]}"; do
    echo -e "  $result"
done
echo ""
echo -e "  Pass: ${GREEN}${TOTAL_PASS}${NC}  Fail: ${RED}${TOTAL_FAIL}${NC}  Skip: ${YELLOW}${TOTAL_SKIP}${NC}"

if [[ $TOTAL_FAIL -gt 0 ]]; then
    echo ""
    echo -e "${RED}SOME TESTS FAILED${NC}"
    exit 1
else
    echo ""
    echo -e "${GREEN}ALL TESTS PASSED${NC}"
    exit 0
fi
