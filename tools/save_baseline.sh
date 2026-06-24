#!/usr/bin/env bash
# save_baseline.sh — snapshot the current screenshots as the regression baseline.
# Copies artifacts/screenshots/*.png to artifacts/baseline/ for screenshot_diff.py.
# Usage: ./tools/save_baseline.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/artifacts/screenshots"
DST="$ROOT/artifacts/baseline"

shopt -s nullglob
PNGS=("$SRC"/*.png)
shopt -u nullglob

if [[ ${#PNGS[@]} -eq 0 ]]; then
	echo "FAIL: no screenshots found in $SRC. Run tools/capture_screenshots.sh first."
	exit 1
fi

mkdir -p "$DST"
for p in "${PNGS[@]}"; do
	cp "$p" "$DST/"
done

echo "BASELINE_SAVED: ${#PNGS[@]} files"
exit 0
