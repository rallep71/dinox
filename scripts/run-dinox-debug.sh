#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT_DIR/logs"
DINOX_BIN="$ROOT_DIR/build/main/dinox"
PID_FILE="$LOG_DIR/dinox.pid"
RUNINFO_FILE="$LOG_DIR/dinox-runinfo-latest.txt"

usage() {
  cat <<'USAGE'
Usage: scripts/run-dinox-debug.sh [--restart]

Starts DinoX in full debug mode and writes:
- logs/dinox.pid (PID of ./build/main/dinox)
- logs/dinox-runinfo-latest.txt (path to the newest log file)

Environment overrides:
- DINO_LOG_LEVEL   (default: debug)
- GST_DEBUG        (default: 3)
- G_MESSAGES_DEBUG (default: all)

Examples:
  scripts/run-dinox-debug.sh
  GST_DEBUG=5 scripts/run-dinox-debug.sh
  scripts/run-dinox-debug.sh --restart
USAGE
}

restart=false
if [[ "${1-}" == "--help" || "${1-}" == "-h" ]]; then
  usage
  exit 0
elif [[ "${1-}" == "--restart" ]]; then
  restart=true
elif [[ -n "${1-}" ]]; then
  echo "Unknown argument: $1" >&2
  usage >&2
  exit 2
fi

mkdir -p "$LOG_DIR"

if [[ ! -x "$DINOX_BIN" ]]; then
  echo "Error: $DINOX_BIN not found or not executable." >&2
  echo "Hint: build first with: meson compile -C build" >&2
  exit 1
fi

if [[ -f "$PID_FILE" ]]; then
  old_pid="$(cat "$PID_FILE" || true)"
  if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
    old_cmd="$(tr '\0' ' ' < "/proc/$old_pid/cmdline" 2>/dev/null || true)"
    if [[ "$old_cmd" == *"$DINOX_BIN"* ]]; then
      if [[ "$restart" == true ]]; then
        "$ROOT_DIR/scripts/stop-dinox.sh" || true
      else
        echo "DinoX already running (pid=$old_pid)." >&2
        echo "Stop it with: scripts/stop-dinox.sh" >&2
        echo "Or restart with: scripts/run-dinox-debug.sh --restart" >&2
        exit 1
      fi
    fi
  fi
fi

# Create a unique log filename (UTC timestamp + mktemp suffix)
ts="$(date -u +%Y%m%d-%H%M%SZ)"
log_file="$(mktemp -p "$LOG_DIR" "dinox-full-debug-${ts}-XXXXXX.log")"

env_DINO_LOG_LEVEL="${DINO_LOG_LEVEL:-debug}"
env_GST_DEBUG="${GST_DEBUG:-3}"
env_G_MESSAGES_DEBUG="${G_MESSAGES_DEBUG:-all}"

(
  export DINO_LOG_LEVEL="$env_DINO_LOG_LEVEL"
  export GST_DEBUG="$env_GST_DEBUG"
  export G_MESSAGES_DEBUG="$env_G_MESSAGES_DEBUG"
  cd "$ROOT_DIR"
  "$DINOX_BIN" >"$log_file" 2>&1
) &

pid=$!

# Sanity check: ensure pid is actually DinoX.
# If not, try to locate the real child dinox process.
cmdline="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"
if [[ "$cmdline" != *"$DINOX_BIN"* ]]; then
  child_pid="$(pgrep -n -P "$pid" -f "^${DINOX_BIN//\//\/}$" 2>/dev/null || true)"
  if [[ -n "$child_pid" ]]; then
    pid="$child_pid"
  fi
fi

echo "$pid" > "$PID_FILE"
echo "$log_file" > "$RUNINFO_FILE"

# Give it a moment to write the first bytes.
sleep 0.2

if [[ -f "$log_file" ]]; then
  size="$(stat -c '%s' "$log_file" 2>/dev/null || echo 0)"
else
  size=0
fi

echo "PID=$pid"
echo "LOG=$log_file"
echo "LOG_BYTES=$size"
