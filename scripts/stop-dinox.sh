#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT_DIR/logs"
DINOX_BIN="$ROOT_DIR/build/main/dinox"
PID_FILE="$LOG_DIR/dinox.pid"
RUNINFO_FILE="$LOG_DIR/dinox-runinfo-latest.txt"

usage() {
  cat <<'USAGE'
Usage: scripts/stop-dinox.sh

Stops a running DinoX instance that was started via scripts/run-dinox-debug.sh.
- Sends SIGINT, waits briefly, then SIGTERM if needed.
- Verifies the PID looks like ./build/main/dinox before killing.

Outputs:
- Prints PID and (if present) the latest log path.

USAGE
}

if [[ "${1-}" == "--help" || "${1-}" == "-h" ]]; then
  usage
  exit 0
elif [[ -n "${1-}" ]]; then
  echo "Unknown argument: $1" >&2
  usage >&2
  exit 2
fi

pid=""
if [[ -f "$PID_FILE" ]]; then
  pid="$(cat "$PID_FILE" || true)"
fi

if [[ -z "$pid" ]]; then
  # Fallback: find most recent dinox process.
  pid="$(pgrep -n -f "^${DINOX_BIN//\//\/}$" 2>/dev/null || pgrep -n -f "$DINOX_BIN" 2>/dev/null || true)"
fi

if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
  echo "DinoX not running."
  exit 0
fi

cmdline="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"
if [[ "$cmdline" != *"$DINOX_BIN"* ]]; then
  echo "Refusing to stop PID=$pid; cmdline does not look like dinox:" >&2
  echo "  $cmdline" >&2
  echo "If this is a stale pidfile, delete: $PID_FILE" >&2
  exit 1
fi

echo "Stopping PID=$pid"
if [[ -f "$RUNINFO_FILE" ]]; then
  echo "LOG=$(cat "$RUNINFO_FILE" || true)"
fi

kill -INT "$pid" 2>/dev/null || true

# Wait up to ~2 seconds.
for _ in {1..20}; do
  if ! kill -0 "$pid" 2>/dev/null; then
    exit 0
  fi
  sleep 0.1
done

kill -TERM "$pid" 2>/dev/null || true

# Wait a bit more.
for _ in {1..20}; do
  if ! kill -0 "$pid" 2>/dev/null; then
    exit 0
  fi
  sleep 0.1
done

echo "Warning: PID=$pid still running after SIGTERM." >&2
exit 1
