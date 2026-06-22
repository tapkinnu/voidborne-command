#!/usr/bin/env python3
"""make_contact_sheet.py — tile the captured PNGs into a single contact-sheet JPG.

Also performs a "not black" sanity check: it fails if every source image is effectively
black (mean luma below a threshold), since a black frame means the capture is broken.

Usage:
    python3 tools/make_contact_sheet.py <screenshots_dir> <output.jpg>
"""
import sys
import os
import glob
from PIL import Image

BLACK_LUMA_THRESHOLD = 8.0   # mean 0-255 luma below this == effectively black
COLS = 2
THUMB_W = 640


def mean_luma(img: Image.Image) -> float:
    g = img.convert("L").resize((64, 64))
    px = g.tobytes()
    return sum(px) / len(px)


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: make_contact_sheet.py <screenshots_dir> <output.jpg>")
        return 2
    src_dir = sys.argv[1]
    out_path = sys.argv[2]

    paths = sorted(glob.glob(os.path.join(src_dir, "*.png")))
    if not paths:
        print(f"FAIL: no PNG screenshots found in {src_dir}")
        return 1

    thumbs = []
    lumas = []
    for p in paths:
        try:
            im = Image.open(p).convert("RGB")
        except Exception as e:  # noqa: BLE001
            print(f"WARN: could not open {p}: {e}")
            continue
        lum = mean_luma(im)
        lumas.append((os.path.basename(p), lum))
        ratio = THUMB_W / im.width
        thumb = im.resize((THUMB_W, int(im.height * ratio)))
        thumbs.append(thumb)

    print("per-image mean luma (0-255):")
    for name, lum in lumas:
        flag = "  <-- BLACK" if lum < BLACK_LUMA_THRESHOLD else ""
        print(f"  {name:28s} {lum:6.2f}{flag}")

    if not thumbs:
        print("FAIL: no readable images.")
        return 1

    if all(lum < BLACK_LUMA_THRESHOLD for _, lum in lumas):
        print("FAIL: all screenshots are effectively black.")
        return 1

    cols = min(COLS, len(thumbs))
    rows = (len(thumbs) + cols - 1) // cols
    cw = max(t.width for t in thumbs)
    ch = max(t.height for t in thumbs)
    pad = 8
    sheet = Image.new("RGB", (cols * cw + pad * (cols + 1), rows * ch + pad * (rows + 1)), (10, 12, 20))
    for i, t in enumerate(thumbs):
        r, c = divmod(i, cols)
        x = pad + c * (cw + pad)
        y = pad + r * (ch + pad)
        sheet.paste(t, (x, y))

    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    sheet.save(out_path, "JPEG", quality=88)
    print(f"PASS: contact sheet written to {out_path} ({sheet.width}x{sheet.height}, {len(thumbs)} tiles)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
