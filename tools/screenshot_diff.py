#!/usr/bin/env python3
"""screenshot_diff.py — compare a baseline screenshot dir against a current dir.

Computes a per-pixel luma difference for each matching filename pair and decides
whether the two captures are visually consistent. Intended as a CI regression gate
that can be run after tools/capture_screenshots.sh.

Usage:
    python3 tools/screenshot_diff.py <baseline_dir> <current_dir> [--threshold N] [--max-diff-pct P]

Exit codes:
    0  all matching images pass (or only warnings / no matches)
    1  at least one image exceeds the allowed diff percentage

Only depends on PIL (Pillow), already used by make_contact_sheet.py.
"""
import sys
import os
import glob
import argparse
from PIL import Image, ImageChops


def luma(img: Image.Image) -> Image.Image:
    """Return an 8-bit luma (grayscale) version of an image."""
    return img.convert("L")


def compare_pair(baseline_path: str, current_path: str, threshold: int):
    """Compare two image files. Returns dict with total/diff/diff_pct/mean_diff."""
    base = Image.open(baseline_path)
    cur = Image.open(current_path)

    # Resize both to the smaller common dimension so minor resolution drift between
    # captures does not break the comparison.
    common_w = min(base.width, cur.width)
    common_h = min(base.height, cur.height)
    if common_w <= 0 or common_h <= 0:
        return None

    base_l = luma(base).resize((common_w, common_h))
    cur_l = luma(cur).resize((common_w, common_h))

    diff = ImageChops.difference(base_l, cur_l)
    diff_bytes = diff.tobytes()
    total = len(diff_bytes)
    if total == 0:
        return None

    different = 0
    sum_diff = 0
    for d in diff_bytes:
        sum_diff += d
        if d > threshold:
            different += 1

    diff_pct = (different / total) * 100.0
    mean_diff = sum_diff / total
    return {
        "total": total,
        "different": different,
        "diff_pct": diff_pct,
        "mean_diff": mean_diff,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Compare baseline vs current screenshots.")
    parser.add_argument("baseline_dir")
    parser.add_argument("current_dir")
    parser.add_argument("--threshold", type=int, default=30,
                        help="per-pixel luma diff threshold (default 30)")
    parser.add_argument("--max-diff-pct", type=float, default=5.0,
                        help="max %% of differing pixels allowed before FAIL (default 5.0)")
    args = parser.parse_args()

    baseline_dir = args.baseline_dir
    current_dir = args.current_dir
    threshold = args.threshold
    max_diff_pct = args.max_diff_pct

    base_files = {os.path.basename(p): p for p in glob.glob(os.path.join(baseline_dir, "*.png"))}
    cur_files = {os.path.basename(p): p for p in glob.glob(os.path.join(current_dir, "*.png"))}

    matched = sorted(set(base_files) & set(cur_files))
    only_base = sorted(set(base_files) - set(cur_files))
    only_cur = sorted(set(cur_files) - set(base_files))

    for name in only_base:
        print(f"WARN: {name} present in baseline but not in current")
    for name in only_cur:
        print(f"WARN: {name} present in current but not in baseline")

    if not matched:
        print(f"WARN: no matching filenames between {baseline_dir} and {current_dir}")
        print("SCREENSHOT_DIFF: PASS")
        return 0

    print(f"comparing {len(matched)} image(s) "
          f"(threshold={threshold}, max_diff_pct={max_diff_pct:.2f})")
    print(f"{'filename':28s} {'diff_pct':>9s} {'mean_diff':>9s}  result")

    any_fail = False
    for name in matched:
        result = compare_pair(base_files[name], cur_files[name], threshold)
        if result is None:
            print(f"WARN: {name} could not be compared (empty/zero-size)")
            continue
        passed = result["diff_pct"] <= max_diff_pct
        if not passed:
            any_fail = True
        status = "PASS" if passed else "FAIL"
        print(f"{name:28s} {result['diff_pct']:8.3f}% {result['mean_diff']:9.3f}  {status}")

    if any_fail:
        print("SCREENSHOT_DIFF: FAIL")
        return 1
    print("SCREENSHOT_DIFF: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
