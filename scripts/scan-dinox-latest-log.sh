#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT_DIR/logs"
RUNINFO_FILE="$LOG_DIR/dinox-runinfo-latest.txt"

if [[ ! -f "$RUNINFO_FILE" ]]; then
  echo "No $RUNINFO_FILE found." >&2
  exit 1
fi

log_file="$(cat "$RUNINFO_FILE")"
if [[ -z "$log_file" || ! -f "$log_file" ]]; then
  echo "Log file not found: $log_file" >&2
  exit 1
fi

echo "LOG=$log_file"
echo

echo "== High-signal warnings/errors =="
grep -nE "WARN|WARNING|ERROR|CRITICAL" "$log_file" | head -n 200 || true

echo

echo "== Audio underflow / discontinuities =="
grep -nEi "underflow|skipping segment|audioringbuffer|too late|discont" "$log_file" | head -n 200 || true

echo

echo "== ICE / DTLS startup buffering =="
grep -nE "DTLS not ready, buffering packet|DTLS-SRTP: buffering pre-ready" "$log_file" | head -n 200 || true

echo

echo "== libnice TURN refresh warnings =="
grep -nE "alive TURN refreshes" "$log_file" | head -n 50 || true
