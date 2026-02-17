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

echo "== SASL / Authentication =="
grep -nE "SASL:|SCRAM:|channel.bind|downgrade" "$log_file" | head -n 50 || true

echo

echo "== Certificate Pinning =="
grep -nEi "certificate.*pinned|fingerprint.*changed|onion.*unknown CA" "$log_file" | head -n 50 || true

echo

echo "== OMEMO =="
grep -nEi "omemo.*fail|omemo.*error|decrypt.*fail|bundle.*fail|session.*error" "$log_file" | head -n 50 || true

echo

echo "== OpenPGP =="
grep -nE "XEP-0373:.*FAIL|XEP-0373:.*error|XEP-0373:.*Self-test" "$log_file" | head -n 50 || true

echo

echo "== Botmother =="
grep -nEi "Botmother:|BotOmemo:|BotRouter:|SessionPool:.*REJECTED|SessionPool:.*IGNORED|Telegram:.*fail|Telegram:.*error" "$log_file" | head -n 100 || true

echo

echo "== Tor =="
grep -nEi "\[TOR\]|TorController|obfs4|bridge.*fail" "$log_file" | head -n 50 || true

echo

echo "== Audio underflow / discontinuities =="
grep -nEi "underflow|skipping segment|audioringbuffer|too late|discont" "$log_file" | head -n 200 || true

echo

echo "== ICE / DTLS startup buffering =="
grep -nE "DTLS not ready, buffering packet|DTLS-SRTP: buffering pre-ready" "$log_file" | head -n 200 || true

echo

echo "== libnice TURN refresh warnings =="
grep -nE "alive TURN refreshes" "$log_file" | head -n 50 || true
