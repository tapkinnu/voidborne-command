extends Node
# GameConstants: single source of truth for gameplay/economy balance knobs.
#
# These values used to live as bare consts in main.gd with some literals duplicated
# inline in other scripts (e.g. the 0.22 disable threshold appeared in both main.gd and
# ship.gd, and the 70.0 service range appeared as raw proximity checks). Centralising them
# here makes the game tunable from one place and prevents the duplicates from drifting.
#
# Registered as the "GameConstants" autoload so runtime scripts can read e.g.
# GameConstants.DISABLE_FRAC, and preloaded (const GC = preload(...)) where a value is
# needed in const context (main.gd re-exports these under its existing public names so
# external callers/tests that read main.SERVICE_RANGE etc. keep working).
#
# No class_name (avoids circular-import pitfalls); values are plain consts.

# --- Recruiting costs (credits) ------------------------------------------------
const COST_CREW: int = 120              # hire one crew member at a station
const COST_MARINE: int = 180            # hire one marine at a station

# --- Combat / capture ----------------------------------------------------------
const DISABLE_FRAC: float = 0.22        # hull fraction at/below which a ship is "disabled"
const CAPTURE_BOUNTY_RATE: float = 0.18 # credits awarded for a capture, as a fraction of value
const DESTROY_SALVAGE_RATE: float = 0.08 # credits salvaged from a kill, as a fraction of value
const MIN_CAPTURE_BOUNTY: int = 100     # floor on capture payout
const MIN_DESTROY_SALVAGE: int = 40     # floor on salvage payout

# --- Interaction ranges (world units) ------------------------------------------
const SERVICE_RANGE: float = 70.0       # station refit/recruit/dock proximity
const GARRISON_ASSIGN_RANGE: float = 120.0 # range for assigning reserve marines to owned prizes
const FLEET_DOCK_RANGE: float = 500.0   # max distance a station can be for a dock order to hold
