#!/usr/bin/env python3
"""
Voidborne Command — Meshy 3D hero-asset generator (5 assets).

Pipeline per asset:
  preview -> refine -> remesh -> [rig -> anim(idle) + anim(walk) -> merge]
  -> download GLB -> texture repack (1024^2 JPEG q=88)

Resumable: every stage's task ID is persisted to .meshy_state.json next to
this script, so a re-run skips completed stages. Every stage is also logged
to artifacts/meshy_<name>.log.

CLI:
  tools/meshy_generate.py            # generate all 5
  tools/meshy_generate.py --only 1   # only the player corvette (1..5)
  tools/meshy_generate.py --only 1,5 # corvette + captain
  tools/meshy_generate.py --download-only  # skip API calls, re-download / re-pack
"""
from __future__ import annotations

import argparse
import io
import json
import os
import re
import struct
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

# ---------------------------------------------------------------------------
# Constants & asset table
# ---------------------------------------------------------------------------

API_ROOT = "https://api.meshy.ai"
STATE_FILE = Path(__file__).resolve().parent.parent / ".meshy_state.json"
ASSETS_DIR = Path(__file__).resolve().parent.parent / "assets" / "models" / "meshy_visual_upgrade"
ARTIFACTS = Path(__file__).resolve().parent.parent / "artifacts"
ENV_FILE_CANDIDATES = [
    Path.home() / ".hermes" / "profiles" / "coder" / ".env",
    Path.home() / ".config" / "hermes" / ".env",
]

# 37 assets total: 5 original + 7 procedural-elimination + 25 ship interiors.
# Prompt text is verbatim from the task body / creative brief — do NOT rewrite.
ASSETS: list[dict] = [
    # --- Original 5 hero assets (commit 7ed687f) ---
    {
        "id": "player_corvette",
        "klass": "corvette",
        "team": "player",
        "rigged": False,
        "prompt": (
            "low-poly sci-fi corvette gunship, sleek prow, dual side cannons, "
            "glowing blue engine nacelles, hard surface, game asset, clean topology"
        ),
    },
    {
        "id": "capital_ship",
        "klass": "capital",
        "team": "any",
        "rigged": False,
        "prompt": (
            "low-poly sci-fi capital ship, long dreadnought hull, dorsal gun "
            "turrets, lit bridge, hard surface, game asset, clean topology"
        ),
    },
    {
        "id": "friendly_station",
        "klass": "station",
        "team": "friendly",
        "rigged": False,
        "prompt": (
            "low-poly sci-fi trading station, ring-and-spoke design, docking "
            "ports, lit windows, hard surface, game asset, clean topology"
        ),
    },
    {
        "id": "hostile_fighter",
        "klass": "fighter",
        "team": "enemy",
        "rigged": False,
        "prompt": (
            "low-poly sci-fi hostile interceptor fighter, angular red-black "
            "hull, twin weapons, hard surface, game asset, clean topology"
        ),
    },
    {
        "id": "crew_captain",
        "klass": "humanoid",
        "team": "any",
        "rigged": True,
        "prompt": (
            "humanoid space captain, utility flight suit, rank insignia, "
            "standing in T-pose with arms outstretched horizontally, legs slightly "
            "apart, game character, clean topology"
        ),
    },
    # --- 7 new assets for full procedural elimination ---
    {
        "id": "fighter_player",
        "klass": "fighter",
        "team": "player",
        "rigged": False,
        "prompt": (
            "low-poly sci-fi single-seat space fighter, green hull with white accents, "
            "sleek aerodynamic design, twin engine nozzles, wing-mounted cannons, "
            "cockpit canopy, hard surface, game asset, clean topology"
        ),
    },
    {
        "id": "fighter_ally",
        "klass": "fighter",
        "team": "ally",
        "rigged": False,
        "prompt": (
            "low-poly sci-fi single-seat space fighter, blue hull with white accents, "
            "sleek aerodynamic design, twin engine nozzles, wing-mounted cannons, "
            "cockpit canopy, hard surface, game asset, clean topology"
        ),
    },
    {
        "id": "frigate_any",
        "klass": "frigate",
        "team": "any",
        "rigged": False,
        "prompt": (
            "low-poly sci-fi medium warship, grey hull with dark panel lines, "
            "boxy design with forward-swept wings, multiple turret mounts, "
            "large engine section, bridge tower, hard surface, game asset, clean topology"
        ),
    },
    {
        "id": "station_neutral",
        "klass": "station",
        "team": "neutral",
        "rigged": False,
        "prompt": (
            "low-poly sci-fi space station, ring-and-spoke design with central hub, "
            "grey metallic hull, docking ports on the ring, antenna arrays, "
            "solar panels, hard surface, game asset, clean topology"
        ),
    },
    {
        "id": "station_hostile",
        "klass": "station",
        "team": "hostile",
        "rigged": False,
        "prompt": (
            "low-poly sci-fi space station, ring-and-spoke design with central hub, "
            "dark grey and red hull, menacing angular design, weapon emplacements, "
            "docking ports, hard surface, game asset, clean topology"
        ),
    },
    {
        "id": "crew_humanoid",
        "klass": "humanoid",
        "team": "any",
        "rigged": True,
        "prompt": (
            "humanoid sci-fi crew member, wearing a blue utility jumpsuit with tool belt, "
            "boots, gloves, short hair, standing in T-pose with arms outstretched horizontally, "
            "legs slightly apart, game character, clean topology"
        ),
    },
    {
        "id": "marine_humanoid",
        "klass": "humanoid",
        "team": "any",
        "rigged": True,
        "prompt": (
            "humanoid sci-fi marine soldier, wearing orange and red combat armor with helmet, "
            "boots, gloves, weapon holster, standing in T-pose with arms outstretched horizontally, "
            "legs slightly apart, game character, clean topology"
        ),
    },
    # --- 25 ship-type-specific interior rooms (card t_32c3321c) -----------
    # Static walkable interiors swapped into crew_deck.gd per ship class.
    # All non-rigged props: interior=True skips the rig/animation stages.
    # Prompts are verbatim from docs/studio/creative_deltas/ship_interiors.md §3.
    {
        "id": "fighter_cockpit",
        "klass": "fighter",
        "team": "any",
        "rigged": False,
        "interior": True,
        "prompt": (
            "low-poly sci-fi fighter cockpit interior, single pilot seat, wraparound "
            "transparent canopy dome with structural ribbing, holographic HUD projections "
            "floating in air, control panels with glowing blue displays, cramped intimate "
            "space, dark grey panels with cool blue console glow, hard surface, game asset, "
            "clean topology, walkable interior, no exterior hull"
        ),
    },
    {
        "id": "corvette_bridge",
        "klass": "corvette",
        "team": "any",
        "rigged": False,
        "interior": True,
        "prompt": (
            "low-poly sci-fi corvette bridge interior, central captain chair, curved console "
            "panels with glowing blue displays, forward viewport showing stars, cramped "
            "submarine-like space, exposed cable runs, desaturated steel-blue walls, hard "
            "surface, game asset, clean topology, walkable interior, no exterior hull"
        ),
    },
    {
        "id": "corvette_crew_quarters",
        "klass": "corvette",
        "team": "any",
        "rigged": False,
        "interior": True,
        "prompt": (
            "low-poly sci-fi corvette crew quarters interior, two-tier bunk beds against wall, "
            "personal lockers, warm amber bunk lighting, cramped narrow space, desaturated "
            "blue-grey walls, hard surface, game asset, clean topology, walkable interior, "
            "no exterior hull"
        ),
    },
    {
        "id": "corvette_marine_barracks",
        "klass": "corvette",
        "team": "any",
        "rigged": False,
        "interior": True,
        "prompt": (
            "low-poly sci-fi corvette marine barracks interior, fold-down bunks, weapon rack "
            "with rifles, equipment lockers, red instrument glow accent lighting, cramped "
            "military sleeping quarters, hard surface, game asset, clean topology, walkable "
            "interior, no exterior hull"
        ),
    },
    {
        "id": "frigate_bridge",
        "klass": "frigate",
        "team": "any",
        "rigged": False,
        "interior": True,
        "prompt": (
            "low-poly sci-fi frigate bridge interior, elevated captain chair, wide panoramic "
            "console desk with multiple crew stations, holographic tactical display table, cool "
            "white overhead lighting with teal accents, central spine corridor visible through "
            "doorway, hard surface, game asset, clean topology, walkable interior, no exterior hull"
        ),
    },
    {
        "id": "frigate_engineering",
        "klass": "frigate",
        "team": "any",
        "rigged": False,
        "interior": True,
        "prompt": (
            "low-poly sci-fi frigate engineering room interior, wall-mounted reactor coolant "
            "pipes, power junction boxes with amber hazard striping, tool racks, warning lights, "
            "industrial machinery, exposed conduits on ceiling, hard surface, game asset, clean "
            "topology, walkable interior, no exterior hull"
        ),
    },
    {
        "id": "frigate_crew_quarters",
        "klass": "frigate",
        "team": "any",
        "rigged": False,
        "interior": True,
        "prompt": (
            "low-poly sci-fi frigate crew quarters interior, four bunk beds in two rows, personal "
            "reading lights, fold-down desks, warm neutral lighting, spacious military dormitory, "
            "teal floor lighting strips, hard surface, game asset, clean topology, walkable "
            "interior, no exterior hull"
        ),
    },
    {
        "id": "frigate_marine_barracks",
        "klass": "frigate",
        "team": "any",
        "rigged": False,
        "interior": True,
        "prompt": (
            "low-poly sci-fi frigate marine barracks interior, reinforced bunk frames, equipment "
            "staging area, weapon cleaning station, red overhead accent lighting, military "
            "readiness room, hard surface, game asset, clean topology, walkable interior, "
            "no exterior hull"
        ),
    },
    {
        "id": "frigate_armory",
        "klass": "frigate",
        "team": "any",
        "rigged": False,
        "interior": True,
        "prompt": (
            "low-poly sci-fi frigate armory interior, floor-to-ceiling weapon racks with rifles "
            "and sidearms, armour locker cabinets, ammunition crates, red weapon-rack backlight "
            "glow, reinforced door frame, hard surface, game asset, clean topology, walkable "
            "interior, no exterior hull"
        ),
    },
    {
        "id": "capital_bridge",
        "klass": "capital",
        "team": "any",
        "rigged": False,
        "interior": True,
        "prompt": (
            "low-poly sci-fi capital ship bridge interior, central command chair, "
            "curved console panels with glowing displays, simple room with four walls "
            "and a floor, hard surface, game asset, clean topology, walkable interior, "
            "no exterior hull"
        ),
    },
    {
        "id": "capital_cic",
        "klass": "capital",
        "team": "any",
        "rigged": False,
        "interior": True,
        "prompt": (
            "low-poly sci-fi capital ship CIC interior, Combat Information Center with large "
            "central holographic tactical table, surrounding operator stations, multi-tier layout "
            "with catwalk above, blue holographic glow illuminating operators from below, white "
            "and blue paneling, hard surface, game asset, clean topology, walkable interior, "
            "no exterior hull"
        ),
    },
    {
        "id": "capital_engineering",
        "klass": "capital",
        "team": "any",
        "rigged": False,
        "interior": True,
        "prompt": (
            "low-poly sci-fi capital ship engineering interior, massive reactor housing with "
            "glowing coolant pipes, control consoles in a gallery arrangement, amber and blue "
            "status lights, catwalk grating floor, industrial cathedral scale, hard surface, "
            "game asset, clean topology, walkable interior, no exterior hull"
        ),
    },
    {
        "id": "capital_officer_quarters",
        "klass": "capital",
        "team": "any",
        "rigged": False,
        "interior": True,
        "prompt": (
            "low-poly sci-fi capital ship officer quarters interior, private single cabin, "
            "wood-grain composite desk, personal holographic display, warm ambient lighting, "
            "porthole window showing stars, comfortable military accommodation, hard surface, "
            "game asset, clean topology, walkable interior, no exterior hull"
        ),
    },
    {
        "id": "capital_crew_quarters",
        "klass": "capital",
        "team": "any",
        "rigged": False,
        "interior": True,
        "prompt": (
            "low-tier sci-fi capital ship crew quarters interior, eight bunk beds in open bay, "
            "personal storage lockers, soft blue-white overhead lighting, spacious military "
            "dormitory, clean white panels with teal accents, hard surface, game asset, clean "
            "topology, walkable interior, no exterior hull"
        ),
    },
    {
        "id": "capital_marine_barracks",
        "klass": "capital",
        "team": "any",
        "rigged": False,
        "interior": True,
        "prompt": (
            "low-poly sci-fi capital ship marine barracks interior, reinforced bunk frames in "
            "rows, equipment armoury along walls, red accent strip lighting, military staging "
            "area with weapon racks, hard surface, game asset, clean topology, walkable interior, "
            "no exterior hull"
        ),
    },
    {
        "id": "capital_sick_bay",
        "klass": "capital",
        "team": "any",
        "rigged": False,
        "interior": True,
        "prompt": (
            "low-poly sci-fi capital ship sick bay interior, two medical beds with overhead "
            "surgical lights, diagnostic equipment on walls, medicine cabinets with blue "
            "underglow, sterile white panels with soft blue ambient lighting, clean medical bay, "
            "hard surface, game asset, clean topology, walkable interior, no exterior hull"
        ),
    },
    {
        "id": "station_command_center",
        "klass": "station",
        "team": "any",
        "rigged": False,
        "interior": True,
        "prompt": (
            "low-poly sci-fi space station command center interior, circular room with central "
            "command holographic globe, surrounding operator stations, panoramic windows showing "
            "docking ships, neutral grey walls with white structural beams, cool white overhead "
            "lighting, hard surface, game asset, clean topology, walkable interior, no exterior hull"
        ),
    },
    {
        "id": "station_reactor",
        "klass": "station",
        "team": "any",
        "rigged": False,
        "interior": True,
        "prompt": (
            "low-poly sci-fi space station reactor room interior, central reactor core visible "
            "through reinforced glass housing, pulsing blue Cherenkov-style glow, coolant pipe "
            "arrays on walls, radiation warning markings, catwalk around the core, industrial "
            "hazard lighting, hard surface, game asset, clean topology, walkable interior, "
            "no exterior hull"
        ),
    },
    {
        "id": "station_trade_hub",
        "klass": "station",
        "team": "any",
        "rigged": False,
        "interior": True,
        "prompt": (
            "low-poly sci-fi space station trade hub interior, open market stalls with holographic "
            "advertisement displays, colourful neon signs, civilian foot traffic area, neutral "
            "grey floor with coloured lighting from vendor booths, bustling commercial atmosphere, "
            "hard surface, game asset, clean topology, walkable interior, no exterior hull"
        ),
    },
    {
        "id": "station_crew_quarters",
        "klass": "station",
        "team": "any",
        "rigged": False,
        "interior": True,
        "prompt": (
            "low-poly sci-fi space station crew quarters interior, simple row of "
            "four bunk beds along one wall, small storage lockers, rectangular "
            "room with grey walls, hard surface, game asset, clean topology, "
            "walkable interior, no exterior hull"
        ),
    },
    {
        "id": "station_marine_barracks",
        "klass": "station",
        "team": "any",
        "rigged": False,
        "interior": True,
        "prompt": (
            "low-poly sci-fi space station marine barracks interior, military bunk area within "
            "station, weapon lockers, equipment staging, red overhead accent lighting, security "
            "force quarters, hard surface, game asset, clean topology, walkable interior, "
            "no exterior hull"
        ),
    },
    {
        "id": "station_brig",
        "klass": "station",
        "team": "any",
        "rigged": False,
        "interior": True,
        "prompt": (
            "low-poly sci-fi space station brig interior, reinforced cell with energy barrier "
            "across doorway, harsh red overhead lighting, single cot, grey walls with warning "
            "markings, detention cell, hard surface, game asset, clean topology, walkable "
            "interior, no exterior hull"
        ),
    },
    {
        "id": "station_sick_bay",
        "klass": "station",
        "team": "any",
        "rigged": False,
        "interior": True,
        "prompt": (
            "low-poly sci-fi space station sick bay interior, three medical beds with diagnostic "
            "scanners, medicine storage with blue glow, surgical robot arm mounted on ceiling, "
            "sterile white panels with soft blue lighting, station medical facility, hard surface, "
            "game asset, clean topology, walkable interior, no exterior hull"
        ),
    },
    {
        "id": "station_cargo_bay",
        "klass": "station",
        "team": "any",
        "rigged": False,
        "interior": True,
        "prompt": (
            "low-poly sci-fi space station cargo bay interior, large open space with stacked "
            "shipping containers, cargo crane rail on ceiling, yellow hazard floor markings, "
            "industrial lighting, forklift parking area, hard surface, game asset, clean topology, "
            "walkable interior, no exterior hull"
        ),
    },
    {
        "id": "station_docking_control",
        "klass": "station",
        "team": "any",
        "rigged": False,
        "interior": True,
        "prompt": (
            "low-poly sci-fi space station docking control interior, window overlooking docking "
            "bay with small ship attached, control console with status displays, communication "
            "equipment, white and grey paneling with blue status lights, airlock control station, "
            "hard surface, game asset, clean topology, walkable interior, no exterior hull"
        ),
    },
]


# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------


def load_meshy_key() -> str:
    key = os.environ.get("MESHY_KEY") or os.environ.get("MESY_API_KEY")
    if key:
        return key.strip()
    for path in ENV_FILE_CANDIDATES:
        if not path.exists():
            continue
        for line in path.read_text().splitlines():
            m = re.match(r"^\s*(?:MESHY_KEY|MESY_API_KEY)\s*=\s*(.+)\s*$", line)
            if m:
                val = m.group(1).strip().strip('"').strip("'")
                if val:
                    os.environ["MESHY_KEY"] = val
                    return val
    raise SystemExit(
        "ERROR: MESHY_KEY / MESY_API_KEY not set in env or ~/.hermes/profiles/coder/.env"
    )


# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------


def _http_json(method: str, url: str, body: dict | None = None, *, timeout: int = 60) -> dict:
    data = None
    headers = {"Authorization": f"Bearer {load_meshy_key()}"}
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read().decode("utf-8")
    try:
        return json.loads(raw)
    except json.JSONDecodeError as e:
        raise SystemExit(f"ERROR: bad JSON from {url}: {e}\n{raw[:400]}")


def _http_get_bytes(url: str, *, timeout: int = 120) -> bytes:
    # Signed URLs are HTTPS, no auth required. Follow redirects.
    req = urllib.request.Request(url, method="GET")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


# ---------------------------------------------------------------------------
# State persistence
# ---------------------------------------------------------------------------


def load_state() -> dict:
    if STATE_FILE.exists():
        return json.loads(STATE_FILE.read_text())
    return {}


def save_state(state: dict) -> None:
    STATE_FILE.write_text(json.dumps(state, indent=2, sort_keys=True))


def state_get(state: dict, asset_id: str, key: str) -> str | None:
    return state.get(asset_id, {}).get(key)


def state_put(state: dict, asset_id: str, key: str, value) -> None:
    state.setdefault(asset_id, {})[key] = value


# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------


_log_path: Path | None = None


def open_log(asset_id: str) -> None:
    global _log_path
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    _log_path = ARTIFACTS / f"meshy_{asset_id}.log"
    _log_path.write_text("")


def log(msg: str) -> None:
    ts = time.strftime("%H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line, flush=True)
    if _log_path is not None:
        with _log_path.open("a") as f:
            f.write(line + "\n")


# ---------------------------------------------------------------------------
# Meshy polling wrapper — handles transient failures, never dies on a
# 'PENDING' task (queues can be hours long).
# ---------------------------------------------------------------------------


def submit(endpoint: str, body: dict, *, max_attempts: int = 4) -> str:
    """POST a new task. Returns the task id from `result`. Raises on hard error."""
    url = f"{API_ROOT}{endpoint}"
    transient_failures = 0
    last_err = None
    for attempt in range(max_attempts):
        try:
            resp = _http_json("POST", url, body)
            task_id = resp.get("result")
            if not task_id:
                raise SystemExit(f"ERROR: POST {url} returned no 'result': {resp}")
            return task_id
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError) as e:
            last_err = e
            transient_failures += 1
            wait = min(30, 5 * (2 ** (transient_failures - 1)))
            log(f"  WARN submit transient err {e!r}, retry {transient_failures}/{max_attempts} in {wait}s")
            time.sleep(wait)
    raise SystemExit(f"ERROR: submit {url} failed after {max_attempts} attempts: {last_err!r}")


def poll(get_url: str, *, label: str, max_seconds: float = 7200.0,
         hard_failures: int = 3) -> dict:
    """Poll a task until SUCCEEDED / FAILED / CANCELED. Returns the final JSON."""
    deadline = time.monotonic() + max_seconds
    transient_failures = 0
    last_err = None
    while True:
        if time.monotonic() > deadline:
            raise SystemExit(f"ERROR: {label} polling timed out after {max_seconds}s")
        try:
            data = _http_json("GET", get_url, timeout=60)
            transient_failures = 0
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError) as e:
            transient_failures += 1
            last_err = e
            if transient_failures >= hard_failures:
                raise SystemExit(f"ERROR: {label} poll hard-fail after {hard_failures}: {last_err!r}")
            log(f"  WARN poll transient {e!r} ({transient_failures}/{hard_failures})")
            time.sleep(15)
            continue

        status = str(data.get("status", "UNKNOWN"))
        progress = data.get("progress", 0)
        prec = data.get("preceding_tasks", 0)
        if int(time.monotonic()) % 30 < 5:
            log(f"  {label}: {status} {progress}% queue={prec}")
        if status == "SUCCEEDED":
            log(f"  {label}: SUCCEEDED")
            return data
        if status in ("FAILED", "CANCELED"):
            raise SystemExit(f"ERROR: {label} ended with status={status} body={data}")
        # PENDING / IN_PROGRESS — back-off.
        time.sleep(15 if status == "IN_PROGRESS" else 30)


def _task_status(task_id: str) -> str | None:
    """Return Meshy's current status for a task id (SUCCEEDED / FAILED / CANCELED /
    IN_PROGRESS / PENDING / UNKNOWN) or None if the GET itself failed.

    Used by stage_* functions to detect a cached task that's already terminally
    FAILED/CANCELED — in which case we must start a fresh task instead of
    reusing the dead one.
    """
    if not task_id:
        return None
    try:
        # Different endpoints use different paths; the canonical task GET is
        # `/openapi/v2/text-to-3d/<id>` for text-to-3d tasks and
        # `/openapi/v1/<endpoint>/<id>` for remesh/rig/anim. We probe the v2
        # path first (covers preview/refine/remesh in current Meshy API), and
        # fall back to None on error so the caller treats it as "unknown".
        data = _http_json("GET", f"{API_ROOT}/openapi/v2/text-to-3d/{task_id}", timeout=30)
        return str(data.get("status", "UNKNOWN"))
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, ValueError, KeyError):
        return None


# --------------------------------------------------------------------------
# Stage wrappers — resumable.
# --------------------------------------------------------------------------

# Statuses that mean the cached task is dead and must be replaced.
_DEAD_STATUSES = {"FAILED", "CANCELED"}


def _cached_task_id_or_none(state: dict, asset_id: str, key: str) -> str | None:
    """Return the cached task id for (asset_id, key), or None if the cached
    task is terminally FAILED / CANCELED (in which case the cached id is also
    removed from state so a fresh task can be started)."""
    cached = state_get(state, asset_id, key)
    if not cached:
        return None
    status = _task_status(cached)
    if status in _DEAD_STATUSES:
        log(f"  cached {key}={cached} is {status} on Meshy — discarding, will retry fresh")
        # Remove from state so the stage_* function starts a new task.
        state.setdefault(asset_id, {}).pop(key, None)
        save_state(state)
        return None
    return cached


# ---------------------------------------------------------------------------
# Stage wrappers — resumable.
# ---------------------------------------------------------------------------


def stage_preview(state: dict, asset: dict) -> str:
    asset_id = asset["id"]
    cached = _cached_task_id_or_none(state, asset_id, "preview_id")
    if cached:
        log(f"preview reuse {cached}")
        return cached
    body = {
        "mode": "preview",
        "prompt": asset["prompt"],
        "art_style": "realistic",
        "topology": "triangle",
        "target_polycount": 20000,
    }
    log(f"preview POST …")
    tid = submit("/openapi/v2/text-to-3d", body)
    state_put(state, asset_id, "preview_id", tid)
    save_state(state)
    return tid


def stage_refine(state: dict, asset: dict, preview_id: str) -> str:
    asset_id = asset["id"]
    cached = _cached_task_id_or_none(state, asset_id, "refine_id")
    if cached:
        log(f"refine reuse {cached}")
        return cached
    log("refine POST …")
    tid = submit("/openapi/v2/text-to-3d", {"mode": "refine", "preview_task_id": preview_id})
    state_put(state, asset_id, "refine_id", tid)
    save_state(state)
    return tid


def stage_remesh(state: dict, asset: dict, refine_id: str) -> str:
    asset_id = asset["id"]
    cached = _cached_task_id_or_none(state, asset_id, "remesh_id")
    if cached:
        log(f"remesh reuse {cached}")
        return cached
    body = {
        "input_task_id": refine_id,
        "target_formats": ["glb"],
        "topology": "triangle",
        "target_polycount": 20000,
    }
    log("remesh POST …")
    tid = submit("/openapi/v1/remesh", body)
    state_put(state, asset_id, "remesh_id", tid)
    save_state(state)
    return tid


def stage_rig(state: dict, asset: dict, remesh_id: str) -> str:
    asset_id = asset["id"]
    cached = _cached_task_id_or_none(state, asset_id, "rig_id")
    if cached:
        log(f"rig reuse {cached}")
        return cached
    log("rig POST …")
    tid = submit("/openapi/v1/rigging", {"input_task_id": remesh_id, "height_meters": 1.8})
    state_put(state, asset_id, "rig_id", tid)
    save_state(state)
    return tid


def stage_animation(state: dict, asset: dict, rig_id: str, action_id: int, label: str) -> str:
    asset_id = asset["id"]
    cache_key = f"anim_{label}_id"
    cached = _cached_task_id_or_none(state, asset_id, cache_key)
    if cached:
        log(f"anim[{label}] reuse {cached}")
        return cached
    log(f"anim[{label}] POST action_id={action_id} …")
    tid = submit("/openapi/v1/animations", {"rig_task_id": rig_id, "action_id": action_id})
    state_put(state, asset_id, cache_key, tid)
    save_state(state)
    return tid


# ---------------------------------------------------------------------------
# GLB download + texture repack + animation merge.
# ---------------------------------------------------------------------------


def download(url: str, dest: Path, *, label: str) -> None:
    log(f"  download [{label}] -> {dest.name}")
    data = _http_get_bytes(url, timeout=180)
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(data)
    log(f"  wrote {dest.name} ({len(data)/1024:.1f} KB)")


def repack_glb(src: Path, dst: Path, *, target_size: int = 1024, jpeg_quality: int = 88) -> int:
    """Parse a GLB, JPEG-encode its embedded images at <=1024^2, rewrite the BIN
    chunk with 4-byte alignment, save to `dst`. Returns final byte size."""
    from PIL import Image as _PILImage  # type: ignore[attr-defined]
    Image = _PILImage
    _LANCZOS = Image.Resampling.LANCZOS if hasattr(Image, "Resampling") else Image.LANCZOS  # type: ignore[attr-defined]

    raw = src.read_bytes()
    if raw[:4] != b"glTF":
        raise SystemExit(f"ERROR: {src} is not a GLB (magic={raw[:4]!r})")
    version, total_len = struct.unpack_from("<II", raw, 4)
    if version != 2:
        raise SystemExit(f"ERROR: {src} unsupported GLB version {version}")

    # Parse chunks: JSON first, then BIN.
    pos = 12
    json_chunk = None
    bin_chunk = None
    while pos < total_len:
        clen, ctype = struct.unpack_from("<II", raw, pos)
        cdata = raw[pos + 8 : pos + 8 + clen]
        if ctype == 0x4E4F534A:  # "JSON"
            json_chunk = cdata
        elif ctype == 0x004E4942:  # "BIN\0"
            bin_chunk = cdata
        pos += 8 + clen
    if json_chunk is None:
        raise SystemExit(f"ERROR: {src} missing JSON chunk")
    bin_chunk = bin_chunk or b""

    gltf = json.loads(json_chunk.decode("utf-8"))
    buffers = gltf.setdefault("buffers", [])
    if not buffers:
        log(f"  WARN: {src.name} has no buffers — nothing to repack")
        dst.write_bytes(raw)
        return len(raw)

    buf0 = buffers[0]
    buf0_len = int(buf0.get("byteLength", len(bin_chunk)))
    if buf0_len > len(bin_chunk):
        # Pad bin chunk up to declared length (shouldn't normally happen).
        bin_chunk = bin_chunk + b"\x00" * (buf0_len - len(bin_chunk))

    buffer_views = gltf.setdefault("bufferViews", [])
    images = gltf.setdefault("images", [])

    new_bin = bytearray()
    new_views_meta: list[tuple[int, int, int]] = []  # (offset, length, view_index)

    def align4(n: int) -> int:
        return (n + 3) & ~3

    def append_padded(data: bytes) -> tuple[int, int]:
        offset = len(new_bin)
        new_bin.extend(data)
        # Pad to 4-byte boundary (GLB spec requirement).
        pad = (-len(new_bin)) & 3
        if pad:
            new_bin.extend(b"\x00" * pad)
        return offset, len(data)

    # Build a map from old bufferView index to new byte offset/length.
    old_offset = {}
    for vi, v in enumerate(buffer_views):
        old_offset[vi] = (int(v.get("byteOffset", 0)), int(v.get("byteLength", 0)))

    # Walk bufferViews in index order. Rebuild any whose referenced image gets
    # re-encoded. We must rewrite the BIN chunk contiguously because images
    # change length unpredictably.
    images_rewritten = 0

    # Pass 1: figure out which images get re-encoded and how big each new image is.
    img_payloads: dict[int, bytes] = {}  # image_index -> new jpeg bytes
    for ii, img in enumerate(images):
        bv_index = img.get("bufferView")
        if bv_index is None:
            continue
        bv_index = int(bv_index)
        if bv_index not in old_offset:
            continue
        off, ln = old_offset[bv_index]
        # Find the blob in old bin
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
            # Flatten RGBA onto a neutral dark grey before JPEG. PBR base-color
            # alpha is rarely meaningful for these Meshy outputs; saving as PNG
            # would balloon the file (1024^2 PNG = ~1.7 MB) and defeat the
            # repack. The normal map is already opaque RGB so it stays JPEG.
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
            log(f"  WARN: image[{ii}] decode/encode failed ({e!r}); keeping original")
            continue

    # Pass 2: rebuild BIN chunk. For each bufferView, either replace its
    # payload (if it served an image we re-encoded) or copy the original bytes.
    # We need to map bv_index -> image_index for replacement.
    bv_to_image: dict[int, int] = {}
    for ii, img in enumerate(images):
        bv = img.get("bufferView")
        if bv is not None:
            bv_to_image[int(bv)] = ii

    # Sort bufferViews by their old offset so we copy non-image bytes in the
    # order they appeared (cosmetic — GLB doesn't care).
    ordered_views = sorted(old_offset.items(), key=lambda kv: kv[1][0])
    for vi, (off, ln) in ordered_views:
        if vi in bv_to_image and bv_to_image[vi] in img_payloads:
            new_off, _ = append_padded(img_payloads[bv_to_image[vi]])
            new_len = len(img_payloads[bv_to_image[vi]])
        else:
            blob = bin_chunk[off : off + ln]
            new_off, _ = append_padded(blob)
            new_len = ln
        buffer_views[vi]["byteOffset"] = new_off
        buffer_views[vi]["byteLength"] = new_len

    # Add new bufferViews for any image re-encodes that need their OWN view
    # (this only happens if the source image shared a bufferView with other
    # data, which is unusual for Meshy outputs — guard anyway).
    for ii, payload in img_payloads.items():
        bv_index = int(images[ii].get("bufferView", -1))
        if bv_index in old_offset:
            off, ln = old_offset[bv_index]
            if ln == len(payload):
                continue  # we already replaced this view in-place above
        # Append a brand-new view.
        new_off, new_len = append_padded(payload)
        buffer_views.append({"buffer": 0, "byteOffset": new_off, "byteLength": new_len})
        images[ii]["bufferView"] = len(buffer_views) - 1

    # Update buffer byteLength
    buf0["byteLength"] = len(new_bin)

    # Re-serialize JSON and rebuild the GLB. JSON must be padded with spaces
    # to a 4-byte boundary per the GLB spec.
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
    log(f"  repack: {src.stat().st_size/1024:.1f}KB -> {len(out)/1024:.1f}KB "
        f"({images_rewritten} images re-encoded)")
    return len(out)


def merge_animation_into_base(base_glb: Path, anim_glb: Path, dst: Path) -> int:
    """Merge the animations + their accessors/bufferViews from `anim_glb` into
    `base_glb`, asserting identical node trees. Saves to `dst`."""
    base_raw = base_glb.read_bytes()
    anim_raw = anim_glb.read_bytes()

    def parse_glb(raw: bytes) -> tuple[dict, bytes]:
        if raw[:4] != b"glTF":
            raise SystemExit("merge_animation_into_base: bad GLB magic")
        _v, total = struct.unpack_from("<II", raw, 4)
        p = 12
        j = None
        b = b""
        while p < total:
            clen, ctype = struct.unpack_from("<II", raw, p)
            d = raw[p + 8 : p + 8 + clen]
            if ctype == 0x4E4F534A:
                j = d
            elif ctype == 0x004E4942:
                b = d
            p += 8 + clen
        if j is None:
            raise SystemExit("merge_animation_into_base: GLB has no JSON chunk")
        return json.loads(j.decode("utf-8")), b

    base_gltf, base_bin = parse_glb(base_raw)
    anim_gltf, anim_bin = parse_glb(anim_raw)

    # Assert identical node trees (names only — bone order must match for
    # channel.target.node indices to stay valid).
    def node_names(gltf: dict) -> list[str]:
        return [n.get("name", "") for n in gltf.get("nodes", [])]

    if node_names(base_gltf) != node_names(anim_gltf):
        raise SystemExit(
            f"ERROR: animation GLB node tree mismatch with rigged base.\n"
            f"  base={node_names(base_gltf)}\n  anim={node_names(anim_gltf)}"
        )

    # Append anim accessors + bufferViews + their bin bytes. We must re-index
    # the anim samplers' accessor and bufferView references by the delta.
    base_n_acc = len(base_gltf.get("accessors", []))
    base_n_bv = len(base_gltf.get("bufferViews", []))

    anim_accessors = anim_gltf.get("accessors", [])
    anim_views = anim_gltf.get("bufferViews", [])

    # Collect the accessor indices actually used by anim samplers (we don't
    # need to bring in unused ones).
    used_acc: set[int] = set()
    used_bv: set[int] = set()
    for anim in anim_gltf.get("animations", []):
        for ch in anim.get("channels", []):
            sampler_idx = ch.get("sampler")
            if sampler_idx is None:
                continue
            sampler = anim["samplers"][sampler_idx]
            for k in ("input", "output"):
                if k in sampler and sampler[k] is not None:
                    used_acc.add(int(sampler[k]))
        for sampler in anim.get("samplers", []):
            for k in ("input", "output"):
                if k in sampler and sampler[k] is not None:
                    used_acc.add(int(sampler[k]))
    for ai in used_acc:
        if ai < len(anim_accessors):
            bv = anim_accessors[ai].get("bufferView")
            if bv is not None:
                used_bv.add(int(bv))

    # Append bufferViews (in original order so byte offsets stay monotonic).
    bv_old_to_new: dict[int, int] = {}
    new_views = base_gltf.setdefault("bufferViews", [])
    new_bin = bytearray(base_bin)

    def append_padded(data: bytes) -> tuple[int, int]:
        offset = len(new_bin)
        new_bin.extend(data)
        pad = (-len(new_bin)) & 3
        if pad:
            new_bin.extend(b"\x00" * pad)
        return offset, len(data)

    for old_vi, view in enumerate(anim_views):
        if old_vi not in used_bv:
            continue
        off = int(view.get("byteOffset", 0))
        ln = int(view.get("byteLength", 0))
        blob = anim_bin[off : off + ln]
        new_off, new_len = append_padded(blob)
        new_view = dict(view)
        new_view["byteOffset"] = new_off
        new_view["byteLength"] = new_len
        new_view["buffer"] = 0
        new_views.append(new_view)
        bv_old_to_new[old_vi] = len(new_views) - 1

    # Append accessors and remap.
    new_accessors = base_gltf.setdefault("accessors", [])
    acc_old_to_new: dict[int, int] = {}
    for old_ai in sorted(used_acc):
        if old_ai >= len(anim_accessors):
            continue
        acc = dict(anim_accessors[old_ai])
        if "bufferView" in acc and acc["bufferView"] is not None:
            bv_idx = int(acc["bufferView"])
            acc["bufferView"] = bv_old_to_new.get(bv_idx, bv_idx)
        new_accessors.append(acc)
        acc_old_to_new[old_ai] = len(new_accessors) - 1

    # Append the animation object itself with remapped samplers.
    new_anim = json.loads(json.dumps(anim_gltf.get("animations", [])))
    for anim in new_anim:
        for sampler in anim.get("samplers", []):
            for k in ("input", "output"):
                if k in sampler and sampler[k] is not None:
                    sampler[k] = acc_old_to_new.get(int(sampler[k]), int(sampler[k]))

    base_gltf.setdefault("animations", []).extend(new_anim)

    # Update buffer[0].byteLength.
    if base_gltf.get("buffers"):
        base_gltf["buffers"][0]["byteLength"] = len(new_bin)

    # Serialize.
    new_json = json.dumps(base_gltf, separators=(",", ":")).encode("utf-8")
    pad = (-len(new_json)) & 3
    if pad:
        new_json += b" " * pad

    total = 12 + 8 + len(new_json) + 8 + len(new_bin)
    out = bytearray()
    out += struct.pack("<4sII", b"glTF", 2, total)
    out += struct.pack("<II", len(new_json), 0x4E4F534A)
    out += new_json
    out += struct.pack("<II", len(new_bin), 0x004E4942)
    out += bytes(new_bin)

    dst.write_bytes(bytes(out))
    log(f"  merge: {base_glb.stat().st_size/1024:.1f}KB + {anim_glb.stat().st_size/1024:.1f}KB "
        f"-> {len(out)/1024:.1f}KB")
    return len(out)


# ---------------------------------------------------------------------------
# Per-asset orchestration
# ---------------------------------------------------------------------------


def process_asset(asset: dict, state: dict) -> dict:
    asset_id = asset["id"]
    open_log(asset_id)
    log(f"==== {asset_id} (rigged={asset['rigged']}) ====")
    log(f"prompt: {asset['prompt']}")

    preview_id = stage_preview(state, asset)
    poll(f"{API_ROOT}/openapi/v2/text-to-3d/{preview_id}", label=f"{asset_id}/preview")

    refine_id = stage_refine(state, asset, preview_id)
    poll(f"{API_ROOT}/openapi/v2/text-to-3d/{refine_id}", label=f"{asset_id}/refine")

    remesh_id = stage_remesh(state, asset, refine_id)
    remesh_result = poll(
        f"{API_ROOT}/openapi/v1/remesh/{remesh_id}", label=f"{asset_id}/remesh"
    )
    # poll() returns the full task JSON; the URL lives under "result".
    remesh_inner = remesh_result.get("result", remesh_result)
    model_url = remesh_inner.get("model_urls", {}).get("glb")
    if not model_url:
        raise SystemExit(f"ERROR: remesh for {asset_id} returned no model_urls.glb: {remesh_result}")
    state_put(state, asset_id, "remesh_url", model_url)
    save_state(state)

    raw_path = ASSETS_DIR / f"{asset_id}.glb"
    if not raw_path.exists():
        download(model_url, raw_path, label="remesh-glb")
    else:
        log(f"  remesh-glb already present, skipping download")

    if not asset["rigged"]:
        repacked_path = ASSETS_DIR / f"{asset_id}.repacked.glb"
        if not repacked_path.exists():
            log("  repack:")
            repack_glb(raw_path, repacked_path)
        else:
            log(f"  repacked already present, skipping")

    # Interior props are static — never rig/animate them even if a future
    # entry sets rigged by mistake.
    if asset["rigged"] and not asset.get("interior"):
        rig_id = stage_rig(state, asset, remesh_id)
        rig_result = poll(f"{API_ROOT}/openapi/v1/rigging/{rig_id}", label=f"{asset_id}/rig")
        # poll() returns the full task JSON; the URL lives under "result".
        rig_result_inner = rig_result.get("result", rig_result)
        rig_model_url = (
            rig_result_inner.get("rigged_character_glb_url")
            or rig_result_inner.get("model_urls", {}).get("glb")
        )
        if not rig_model_url:
            raise SystemExit(f"ERROR: rig for {asset_id} returned no rigged_character_glb_url: {rig_result}")
        state_put(state, asset_id, "rig_url", rig_model_url)
        save_state(state)

        rigged_raw = ASSETS_DIR / f"{asset_id}.rigged.glb"
        if not rigged_raw.exists():
            download(rig_model_url, rigged_raw, label="rigged-glb")
        else:
            log("  rigged-glb already present, skipping download")

        # Two animations: idle (0) and walk (1). Merge into the rigged GLB.
        idle_id = stage_animation(state, asset, rig_id, 0, "idle")
        walk_id = stage_animation(state, asset, rig_id, 1, "walk")

        idle_result = poll(
            f"{API_ROOT}/openapi/v1/animations/{idle_id}", label=f"{asset_id}/anim_idle"
        )
        walk_result = poll(
            f"{API_ROOT}/openapi/v1/animations/{walk_id}", label=f"{asset_id}/anim_walk"
        )

        # IMPORTANT: animation results use animation_glb_url, not model_urls.
        # poll() returns the full task JSON; the URL lives under "result".
        idle_inner = idle_result.get("result", idle_result)
        walk_inner = walk_result.get("result", walk_result)
        idle_anim_url = idle_inner.get("animation_glb_url") or idle_inner.get("model_urls", {}).get("glb")
        walk_anim_url = walk_inner.get("animation_glb_url") or walk_inner.get("model_urls", {}).get("glb")
        if not idle_anim_url or not walk_anim_url:
            raise SystemExit(
                f"ERROR: animation results missing animation_glb_url:\n"
                f"  idle={idle_result}\n  walk={walk_result}"
            )

        idle_glb = ASSETS_DIR / f"{asset_id}.anim_idle.glb"
        walk_glb = ASSETS_DIR / f"{asset_id}.anim_walk.glb"
        if not idle_glb.exists():
            download(idle_anim_url, idle_glb, label="anim_idle-glb")
        if not walk_glb.exists():
            download(walk_anim_url, walk_glb, label="anim_walk-glb")

        # Merge: start from the rigged base, then add idle, then add walk.
        staged = ASSETS_DIR / f"{asset_id}.stage1.glb"
        if not staged.exists():
            merge_animation_into_base(rigged_raw, idle_glb, staged)
        else:
            log("  stage1 (rig+idle) already present, skipping")
        staged2 = ASSETS_DIR / f"{asset_id}.stage2.glb"
        if not staged2.exists():
            merge_animation_into_base(staged, walk_glb, staged2)
        else:
            log("  stage2 (rig+idle+walk) already present, skipping")

        # Repack the merged file.
        final = ASSETS_DIR / f"{asset_id}.repacked.glb"
        if not final.exists():
            repack_glb(staged2, final)
        else:
            log(f"  final repacked already present ({final.stat().st_size/1024:.1f}KB), skipping")

    return {
        "asset_id": asset_id,
        "preview_id": state_get(state, asset_id, "preview_id"),
        "refine_id": state_get(state, asset_id, "refine_id"),
        "remesh_id": state_get(state, asset_id, "remesh_id"),
        "rig_id": state_get(state, asset_id, "rig_id"),
        "anim_idle_id": state_get(state, asset_id, "anim_idle_id"),
        "anim_walk_id": state_get(state, asset_id, "anim_walk_id"),
        "repacked_path": str(ASSETS_DIR / f"{asset_id}.repacked.glb"),
        "size_bytes": (ASSETS_DIR / f"{asset_id}.repacked.glb").stat().st_size,
    }


def parse_only(spec: str | None) -> list | None:
    """Parse --only into a selector list. Each token is either a 1-based integer
    index (or 'a-b' range) into ASSETS, or an asset id string. Returns a mixed
    list of 0-based ints and id strings, or None for "all"."""
    if not spec:
        return None
    out: list = []
    for tok in spec.split(","):
        tok = tok.strip()
        if not tok:
            continue
        # Numeric index or range -> 0-based ints.
        if re.fullmatch(r"\d+(-\d+)?", tok):
            if "-" in tok:
                a, b = tok.split("-", 1)
                out.extend(range(int(a) - 1, int(b)))
            else:
                out.append(int(tok) - 1)
        else:
            out.append(tok)  # asset id string
    return out


def _asset_selected(idx: int, asset: dict, selected: list | None) -> bool:
    if selected is None:
        return True
    return idx in selected or asset["id"] in selected


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--only", help="Comma-separated asset indices (1-based) or asset ids. "
                                  "E.g. '1,5', '13-37', or 'fighter_cockpit,corvette_bridge'.")
    p.add_argument("--download-only", action="store_true",
                   help="Skip Meshy API calls; only re-download / re-pack from state file.")
    args = p.parse_args()

    load_meshy_key()
    state = load_state()
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    ASSETS_DIR.mkdir(parents=True, exist_ok=True)

    selected = parse_only(args.only)
    selected_assets = [a for i, a in enumerate(ASSETS) if _asset_selected(i, a, selected)]

    summary = []
    for asset in selected_assets:
        try:
            r = process_asset(asset, state)
            summary.append(r)
        except SystemExit as e:
            log(f"FAILED {asset['id']}: {e}")
            summary.append({"asset_id": asset["id"], "error": str(e)})

    print()
    print(json.dumps({"summary": summary, "state": state}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())