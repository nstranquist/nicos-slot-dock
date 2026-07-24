#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/.build/release/SlotDock.app"
BIN="$APP/Contents/MacOS/SlotDock"
REPORT="${SLOT_DOCK_SELFTEST_REPORT:-$ROOT/.build/selftest-report.json}"
CONFIG="${SLOT_DOCK_CONFIG:-$ROOT/.build/smoke-config/slots.json}"

mkdir -p "$(dirname "$CONFIG")"
rm -f "$REPORT"

if [[ ! -x "$BIN" ]]; then
  echo "missing binary: $BIN" >&2
  exit 1
fi

export SLOT_DOCK_HEADLESS=1
export SLOT_DOCK_SELFTEST=1
export SLOT_DOCK_SELFTEST_REPORT="$REPORT"
export SLOT_DOCK_CONFIG="$CONFIG"

# Launch and wait for self-test exit
set +e
"$BIN" >"$ROOT/.build/smoke-stdout.log" 2>"$ROOT/.build/smoke-stderr.log"
code=$?
set -e

echo "headless smoke exit=$code"
if [[ -f "$REPORT" ]]; then
  cat "$REPORT"
else
  echo "no report written" >&2
  cat "$ROOT/.build/smoke-stderr.log" >&2 || true
  exit 1
fi

if [[ "$code" -ne 0 ]]; then
  cat "$ROOT/.build/smoke-stderr.log" >&2 || true
  exit "$code"
fi

# Basic JSON ok check without jq dependency
grep -q '"ok" : true' "$REPORT" || grep -q '"ok": true' "$REPORT"
echo "headless smoke ok"
