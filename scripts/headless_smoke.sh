#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/.build/app/Nicos Slot Dock.app"
BIN="$APP/Contents/MacOS/SlotDock"
REPORT="${SLOT_DOCK_SELFTEST_REPORT:-$ROOT/.build/selftest-report.json}"
CONFIG="${SLOT_DOCK_CONFIG:-$ROOT/.build/smoke-config/slots.json}"
TIMEOUT_SECONDS="${SLOT_DOCK_SMOKE_TIMEOUT_SECONDS:-30}"

mkdir -p "$(dirname "$CONFIG")"
if [[ -z "${SLOT_DOCK_CONFIG:-}" ]]; then
  rm -f "$CONFIG"
fi
rm -f "$REPORT"

if [[ ! -x "$BIN" ]]; then
  echo "missing binary: $BIN" >&2
  exit 1
fi

export SLOT_DOCK_HEADLESS=1
export SLOT_DOCK_SELFTEST=1
export SLOT_DOCK_SELFTEST_REPORT="$REPORT"
export SLOT_DOCK_CONFIG="$CONFIG"

"$BIN" >"$ROOT/.build/smoke-stdout.log" 2>"$ROOT/.build/smoke-stderr.log" &
pid=$!
deadline=$(( $(date +%s) + TIMEOUT_SECONDS ))
code=""
while kill -0 "$pid" 2>/dev/null; do
  if (( $(date +%s) >= deadline )); then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    echo "headless smoke timed out after ${TIMEOUT_SECONDS}s" >&2
    cat "$ROOT/.build/smoke-stderr.log" >&2 || true
    exit 124
  fi
  sleep 0.1
done
wait "$pid" || code=$?
code="${code:-0}"

echo "headless smoke exit=$code"
if [[ ! -f "$REPORT" ]]; then
  echo "no report written" >&2
  cat "$ROOT/.build/smoke-stderr.log" >&2 || true
  exit 1
fi
cat "$REPORT"

if [[ "$code" -ne 0 ]]; then
  cat "$ROOT/.build/smoke-stderr.log" >&2 || true
  exit "$code"
fi

ok=$(/usr/bin/plutil -extract ok raw -expect bool "$REPORT")
settings_valid=$(/usr/bin/plutil -extract settings_valid raw -expect bool "$REPORT")
composition_valid=$(/usr/bin/plutil -extract composition_valid raw -expect bool "$REPORT")
app=$(/usr/bin/plutil -extract app raw -expect string "$REPORT")
reveal_phase=$(/usr/bin/plutil -extract reveal_phase raw -expect string "$REPORT")
[[ "$app" == "nicos-slot-dock" ]]
[[ "$ok" == "true" ]]
[[ "$settings_valid" == "true" ]]
[[ "$composition_valid" == "true" ]]
[[ "$reveal_phase" == "expanded" ]]
echo "headless smoke ok"
