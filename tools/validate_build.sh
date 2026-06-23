#!/usr/bin/env bash
# validate_build.sh — headless import + short smoke run of Voidborne Command.
# Fails (exit 1) if SCRIPT ERROR, Parse Error, or Invalid call appears in engine output.
# Usage: ./tools/validate_build.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GODOT="${GODOT_BIN:-/home/ganomix/tools/godot/Godot_v4.4.1-stable_linux.x86_64}"
DRIVER="${RENDER_DRIVER:-vulkan}"
LOG_DIR="$ROOT/artifacts"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/validate.log"
: > "$LOG"

if [[ ! -x "$GODOT" ]]; then
	echo "FAIL: Godot binary not found/executable at $GODOT" | tee -a "$LOG"
	exit 1
fi

echo "== Voidborne Command :: validate_build ==" | tee -a "$LOG"
echo "godot=$GODOT driver=$DRIVER" | tee -a "$LOG"

run_godot() {
	# Run godot under xvfb with a hard timeout; merge stdout+stderr into the log.
	local secs="$1"; shift
	timeout "$secs" xvfb-run -a "$GODOT" "$@" 2>&1
}

echo "-- Step 1: import --------------------------------------------" | tee -a "$LOG"
run_godot 120 --headless --rendering-driver "$DRIVER" --path . --import | tee -a "$LOG" >/dev/null

echo "-- Step 1b: save/load schema verifier ------------------------" | tee -a "$LOG"
SAVE_VERIFY_LOG="$(mktemp)"
if ! python3 "$ROOT/tools/verify_save_load.py" > "$SAVE_VERIFY_LOG" 2>&1; then
	cat "$SAVE_VERIFY_LOG" | tee -a "$LOG"
	rm -f "$SAVE_VERIFY_LOG"
	echo "FAIL: verify_save_load.py reported a schema policy regression" | tee -a "$LOG"
	exit 1
fi
cat "$SAVE_VERIFY_LOG" | tee -a "$LOG"
if ! grep -F "VOIDBORNE_SAVE_LOAD_VERIFY: PASS" "$SAVE_VERIFY_LOG" >/dev/null 2>&1; then
	rm -f "$SAVE_VERIFY_LOG"
	echo "FAIL: save/load verifier PASS marker missing" | tee -a "$LOG"
	exit 1
fi
rm -f "$SAVE_VERIFY_LOG"

echo "-- Step 2: GDScript tests -------------------------------------" | tee -a "$LOG"
shopt -s nullglob
for TEST in tests/test_*.gd; do
	echo "test=$TEST" | tee -a "$LOG"
	TMP="$(mktemp)"
	run_godot 60 --headless --path . -s "$TEST" > "$TMP" 2>&1
	STATUS=$?
	cat "$TMP" >> "$LOG"
	if [[ "$STATUS" -ne 0 ]] || ! grep -q "TEST_PASS" "$TMP"; then
		echo "FAIL: $TEST exited $STATUS or did not print TEST_PASS" | tee -a "$LOG"
		cat "$TMP"
		rm -f "$TMP"
		exit 1
	fi
	rm -f "$TMP"
done
shopt -u nullglob

echo "-- Step 3: smoke run (10s) -----------------------------------" | tee -a "$LOG"
# VOIDBORNE_CAPTURE makes the autopilot fight so weapons/boarding code paths execute,
# but we point it at a scratch dir we discard; the real capture tool owns screenshots.
SMOKE_DIR="$(mktemp -d)"
VOIDBORNE_CAPTURE="$SMOKE_DIR" run_godot 30 --rendering-driver "$DRIVER" --path . --audio-driver Dummy | tee -a "$LOG" >/dev/null
rm -rf "$SMOKE_DIR"

echo "-- Step 4: scan for fatal errors -----------------------------" | tee -a "$LOG"
# Match the three forbidden classes. Engine "ERROR:" lines (e.g. transient) are not fatal
# unless they are one of these GDScript-level failures.
HITS="$(grep -E "SCRIPT ERROR|Parse Error|Invalid call" "$LOG" || true)"
if [[ -n "$HITS" ]]; then
	echo "FAIL: forbidden errors detected:" | tee -a "$LOG"
	echo "$HITS" | tee -a "$LOG"
	exit 1
fi

echo "PASS: no SCRIPT ERROR / Parse Error / Invalid call. Log: $LOG"
exit 0
