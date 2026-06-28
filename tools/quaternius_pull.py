#!/usr/bin/env python3
"""
Quaternius CC0 asset puller (poly.pizza mirror).

The free-asset counterpart to tools/meshy_generate.py. For each model URL
in the manifest, downloads the GLB, runs the same repack pipeline as Meshy
outputs (1024^2 JPEG q=88, rebuild BIN chunk, 4-byte align), and writes
<id>.repacked.glb under the destination. Idempotent: re-runs skip completed
files. Records every URL + license + final path in SOURCES.md for release
provenance.

Manifest shape (JSON):

    {
      "destination": "res://assets/models/quaternius_modular/",
      "license": "CC0",
      "source_mirror": "https://poly.pizza/",
      "assets": [
        {"id": "scifi_wall_panel_a", "url": "https://static.poly.pizza/<uuid>.glb"},
        {"id": "scifi_chair_01",    "url": "https://static.poly.pizza/<uuid>.glb"}
      ]
    }

CLI:

    python3 quaternius_pull.py                          # uses quaternius_manifest.json next to script
    python3 quaternius_pull.py --manifest <path.json>
    python3 quaternius_pull.py --manifest <path.json> --only <id1,id2,...>   # subset
    python3 quaternius_pull.py --manifest <path.json> --dry-run             # print plan, no download

Pitfalls documented inline:
  - Never use Quaternius's own site Google Drive folders (rate-limit)
  - Always use poly.pizza per-model URLs (https://static.poly.pizza/<uuid>.glb)
  - Quaternius ships in meters; Meshy sometimes ships in centimeters — verify scale in-engine
  - Always write SOURCES.md with URL + license + local path + date (release checklist)
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import re
import struct
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

# Mirror the meshy_generate.repack_glb implementation so this script is
# self-contained and does not require the consuming project to expose the
# function. Pillow is the only non-stdlib dep; everything else is stdlib.

LICENSE_REQUIRED = "CC0"   # public domain; commercial OK, no attribution
LICENSE_OK_FALLBACK = {"CC0", "Public Domain", "CC-0", "PD"}
ALLOWED_HOSTS = ("static.poly.pizza", "poly.pizza", "quaternius.com")


# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------

def _http_get_bytes(url: str, *, timeout: int = 60, max_attempts: int = 3) -> bytes:
    last = None
    for attempt in range(max_attempts):
        try:
            req = urllib.request.Request(url, method="GET",
                                         headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"})
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return resp.read()
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError) as e:
            last = e
            wait = min(30, 3 * (2 ** attempt))
            print(f"  WARN GET {url} -> {e!r}, retry {attempt+1}/{max_attempts} in {wait}s")
            time.sleep(wait)
    raise SystemExit(f"ERROR: GET {url} failed after {max_attempts} attempts: {last!r}")


def _sha256(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()[:16]


# ---------------------------------------------------------------------------
# GLB repack (inlined from meshy_generate.repack_glb; kept identical so the
# output is byte-comparable with Meshy-repacked assets).
# ---------------------------------------------------------------------------

def repack_glb(src: Path, dst: Path, *, target_size: int = 1024, jpeg_quality: int = 88) -> int:
    """JPEG-encode embedded images at <=target_size^2, rewrite BIN with 4-byte align.
    Returns final byte size. Mirrors meshy_generate.repack_glb semantics.
    """
    from PIL import Image as _PILImage  # type: ignore[attr-defined]
    Image = _PILImage
    _LANCZOS = Image.Resampling.LANCZOS if hasattr(Image, "Resampling") else Image.LANCZOS

    raw = src.read_bytes()
    if raw[:4] != b"glTF":
        raise SystemExit(f"ERROR: {src} is not a GLB (magic={raw[:4]!r})")
    version, total_len = struct.unpack_from("<II", raw, 4)
    if version != 2:
        raise SystemExit(f"ERROR: {src} unsupported GLB version {version}")

    pos = 12
    json_chunk = None
    bin_chunk = None
    while pos < total_len:
        clen, ctype = struct.unpack_from("<II", raw, pos)
        cdata = raw[pos + 8 : pos + 8 + clen]
        if ctype == 0x4E4F534A:
            json_chunk = cdata
        elif ctype == 0x004E4942:
            bin_chunk = cdata
        pos += 8 + clen
    if json_chunk is None:
        raise SystemExit(f"ERROR: {src} missing JSON chunk")
    bin_chunk = bin_chunk or b""

    gltf = json.loads(json_chunk.decode("utf-8"))
    buffers = gltf.setdefault("buffers", [])
    if not buffers:
        dst.write_bytes(raw)
        return len(raw)

    buf0 = buffers[0]
    buf0_len = int(buf0.get("byteLength", len(bin_chunk)))
    if buf0_len > len(bin_chunk):
        bin_chunk = bin_chunk + b"\x00" * (buf0_len - len(bin_chunk))

    buffer_views = gltf.setdefault("bufferViews", [])
    images = gltf.setdefault("images", [])

    new_bin = bytearray()
    img_payloads: dict[int, bytes] = {}

    def append_padded(data: bytes) -> int:
        offset = len(new_bin)
        new_bin.extend(data)
        pad = (-len(new_bin)) & 3
        if pad:
            new_bin.extend(b"\x00" * pad)
        return offset

    old_offset = {vi: (int(v.get("byteOffset", 0)), int(v.get("byteLength", 0)))
                  for vi, v in enumerate(buffer_views)}

    images_rewritten = 0
    for ii, img in enumerate(images):
        bv_index = img.get("bufferView")
        if bv_index is None:
            continue
        bv_index = int(bv_index)
        if bv_index not in old_offset:
            continue
        off, ln = old_offset[bv_index]
        old_blob = bin_chunk[off : off + ln]
        try:
            pil = Image.open(io.BytesIO(old_blob))
            has_alpha = pil.mode in ("RGBA", "LA") or (pil.mode == "P" and "transparency" in pil.info)
            if has_alpha:
                pil = pil.convert("RGBA")
            else:
                pil = pil.convert("RGB")
            if max(pil.size) > target_size:
                pil.thumbnail((target_size, target_size), _LANCZOS)
            buf = io.BytesIO()
            save_mode = pil.mode
            if pil.mode == "RGBA":
                bg = Image.new("RGB", pil.size, (32, 32, 32))
                bg.paste(pil, mask=pil.split()[-1])
                pil = bg
                save_mode = "RGB"
            pil.save(buf, format="JPEG", quality=jpeg_quality, optimize=True)
            img["mimeType"] = "image/jpeg"
            img_payloads[ii] = buf.getvalue()
            images_rewritten += 1
        except Exception as e:  # noqa: BLE001
            print(f"  WARN: image[{ii}] decode/encode failed ({e!r}); keeping original")
            continue

    bv_to_image: dict[int, int] = {}
    for ii, img in enumerate(images):
        bv = img.get("bufferView")
        if bv is not None:
            bv_to_image[int(bv)] = ii

    ordered_views = sorted(old_offset.items(), key=lambda kv: kv[1][0])
    for vi, (off, ln) in ordered_views:
        if vi in bv_to_image and bv_to_image[vi] in img_payloads:
            new_off = append_padded(img_payloads[bv_to_image[vi]])
            new_len = len(img_payloads[bv_to_image[vi]])
        else:
            blob = bin_chunk[off : off + ln]
            new_off = append_padded(blob)
            new_len = ln
        buffer_views[vi]["byteOffset"] = new_off
        buffer_views[vi]["byteLength"] = new_len

    for ii, payload in img_payloads.items():
        bv_index = int(images[ii].get("bufferView", -1))
        if bv_index in old_offset:
            off, ln = old_offset[bv_index]
            if ln == len(payload):
                continue
        new_off = append_padded(payload)
        buffer_views.append({"buffer": 0, "byteOffset": new_off, "byteLength": len(payload)})
        images[ii]["bufferView"] = len(buffer_views) - 1

    buf0["byteLength"] = len(new_bin)

    new_json_bytes = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    pad = (-len(new_json_bytes)) & 3
    if pad:
        new_json_bytes += b" " * pad

    new_total = 12 + 8 + len(new_json_bytes) + 8 + len(new_bin)
    out = bytearray()
    out += struct.pack("<4sII", b"glTF", 2, new_total)
    out += struct.pack("<II", len(new_json_bytes), 0x4E4F534A)
    out += new_json_bytes
    out += struct.pack("<II", len(new_bin), 0x004E4942)
    out += new_bin

    dst.write_bytes(bytes(out))
    print(f"  repack: {src.stat().st_size/1024:.1f}KB -> {len(out)/1024:.1f}KB "
          f"({images_rewritten} images re-encoded)")
    return len(out)


# ---------------------------------------------------------------------------
# Manifest validation
# ---------------------------------------------------------------------------

def _validate_url(url: str) -> None:
    """Reject anything that isn't a poly.pizza mirror URL or quaternius.com."""
    m = re.match(r"^https?://([^/]+)/", url)
    if not m:
        raise SystemExit(f"ERROR: bad URL: {url}")
    host = m.group(1).lower()
    if host not in ALLOWED_HOSTS:
        raise SystemExit(
            f"ERROR: URL host {host!r} not in allowed mirrors {ALLOWED_HOSTS}.\n"
            f"  Use poly.pizza per-model GLBs (https://static.poly.pizza/<uuid>.glb).\n"
            f"  Do NOT use Quaternius Google Drive folders (rate-limit)."
        )


def _validate_license(license_str: str) -> None:
    """Refuse to pull assets whose license is not CC0/Public Domain."""
    norm = license_str.strip()
    if norm not in LICENSE_OK_FALLBACK:
        raise SystemExit(
            f"ERROR: license {license_str!r} is not CC0/Public Domain.\n"
            f"  Quaternius pulls must be CC0. CC-BY and CC-BY-SA require attribution —\n"
            f"  you may pull them only if you accept the attribution requirement and\n"
            f"  record it explicitly in SOURCES.md."
        )


# ---------------------------------------------------------------------------
# SOURCES.md provenance writer
# ---------------------------------------------------------------------------

SOURCES_HEADER = """# SOURCES.md — Quaternius CC0 asset provenance

Auto-generated by `ludo-style-game-asset-studio/scripts/quaternius_pull.py`.
Do not edit by hand; re-run the script to update.

Mirror: https://poly.pizza/
License: CC0 (Public Domain — commercial use OK, no attribution required)
Generated: {ts}

| ID | poly.pizza URL | Source size | Repacked size | Local path |
|----|----------------|-------------|---------------|------------|
"""


def _update_sources_md(dest: Path, rows: list[dict]) -> None:
    sources_path = dest / "SOURCES.md"
    lines = [SOURCES_HEADER.format(ts=time.strftime("%Y-%m-%dT%H:%M:%S"))]
    for r in sorted(rows, key=lambda x: x["id"]):
        lines.append(
            f"| `{r['id']}` | {r['url']} | {r['raw_kb']:.1f} KB | "
            f"{r['packed_kb']:.1f} KB | `res://{r['local']}` |"
        )
    sources_path.write_text("\n".join(lines) + "\n")
    print(f"  wrote {sources_path.relative_to(dest.parent)}")


# ---------------------------------------------------------------------------
# Per-asset pull
# ---------------------------------------------------------------------------

def pull_one(asset: dict, dest: Path, *, dry_run: bool) -> dict | None:
    aid = asset["id"]
    url = asset["url"]
    _validate_url(url)

    raw_path = dest / f"{aid}.glb"
    packed_path = dest / f"{aid}.repacked.glb"

    if packed_path.exists() and packed_path.stat().st_size > 0:
        print(f"[skip] {aid}: {packed_path.name} already exists")
        return None

    if dry_run:
        print(f"[dry-run] would pull {aid} <- {url}")
        return None

    print(f"==== {aid} ====")
    raw_bytes = _http_get_bytes(url, timeout=120)
    raw_path.parent.mkdir(parents=True, exist_ok=True)
    raw_path.write_bytes(raw_bytes)
    print(f"  download -> {raw_path.name} ({len(raw_bytes)/1024:.1f} KB, sha256={_sha256(raw_bytes)})")

    packed_size = repack_glb(raw_path, packed_path)
    return {
        "id": aid,
        "url": url,
        "raw_kb": len(raw_bytes) / 1024.0,
        "packed_kb": packed_size / 1024.0,
        "local": str(packed_path.relative_to(dest.parent.parent.parent)) if False else str(packed_path),
    }


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1] if __doc__ else "")
    ap.add_argument("--manifest", type=Path,
                    default=Path(__file__).resolve().parent / "quaternius_manifest.json",
                    help="JSON manifest of assets to pull")
    ap.add_argument("--only", type=str, default="",
                    help="comma-separated ids to subset (default: all in manifest)")
    ap.add_argument("--dry-run", action="store_true",
                    help="print plan, do not download")
    args = ap.parse_args()

    if not args.manifest.exists():
        raise SystemExit(
            f"ERROR: manifest not found: {args.manifest}\n"
            f"Create a JSON manifest with destination + assets[]. See script docstring."
        )

    manifest = json.loads(args.manifest.read_text())
    _validate_license(manifest.get("license", ""))
    dest = Path(manifest.get("destination", "res://assets/models/quaternius_modular/"))
    dest.mkdir(parents=True, exist_ok=True)

    only_set = {s.strip() for s in args.only.split(",") if s.strip()}
    assets = manifest.get("assets", [])
    if only_set:
        assets = [a for a in assets if a["id"] in only_set]

    print(f"Pulling {len(assets)} Quaternius assets -> {dest}")
    rows = []
    for asset in assets:
        row = pull_one(asset, dest, dry_run=args.dry_run)
        if row:
            rows.append(row)

    if rows and not args.dry_run:
        _update_sources_md(dest, rows)
    print(f"DONE: {len(rows)} new assets pulled, {len(assets) - len(rows)} skipped.")


if __name__ == "__main__":
    main()
