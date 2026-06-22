#!/usr/bin/env bash
# capture_screenshots.sh — render the live battle headlessly and write PNGs to
# artifacts/screenshots/. The in-engine Capture autoload (scripts/capture.gd) grabs the
# frames and quits itself; the shell timeout here is only a safety net. Falls back from
# vulkan to opengl3 if the first run produces no images.
# Usage: ./tools/capture_screenshots.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GODOT="${GODOT_BIN:-/home/ganomix/tools/godot/Godot_v4.4.1-stable_linux.x86_64}"
OUT="$ROOT/artifacts/screenshots"
mkdir -p "$OUT"
rm -f "$OUT"/*.png

if [[ ! -x "$GODOT" ]]; then
	echo "FAIL: Godot binary not found at $GODOT"
	exit 1
fi

attempt() {
	local driver="$1"
	echo "== capture attempt: driver=$driver =="
	VOIDBORNE_CAPTURE="$OUT" timeout 90 xvfb-run -a "$GODOT" \
		--rendering-driver "$driver" --path . --audio-driver Dummy 2>&1 \
		| grep -E "capture|ERROR|SCRIPT" || true
}

attempt "${RENDER_DRIVER:-vulkan}"
COUNT=$(find "$OUT" -name '*.png' | wc -l | tr -d ' ')
if [[ "$COUNT" -eq 0 ]]; then
	echo "Vulkan produced no PNGs; falling back to opengl3."
	attempt "opengl3"
	COUNT=$(find "$OUT" -name '*.png' | wc -l | tr -d ' ')
fi

if [[ "$COUNT" -eq 0 ]]; then
	echo "FAIL: no screenshots were produced."
	exit 1
fi

echo "PASS: wrote $COUNT screenshot(s) to $OUT"
ls -la "$OUT"/*.png
exit 0
