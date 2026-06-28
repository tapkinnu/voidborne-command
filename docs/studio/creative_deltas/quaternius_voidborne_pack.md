# Quaternius Ultimate Space Kit — Voidborne Command Asset Pack

## Summary

Pulled 35 CC0 Quaternius models from the Ultimate Space Kit (poly.pizza) into
`assets/models/quaternius_modular/`. Total size: 6.8 MB. All 35 pass Godot
headless load() verification. These fill the remaining visual gaps in Voidborne
Command: background scenery, mining asteroids, planets, debris, crew variety,
and station buildings.

## Asset Mapping

### Concord Fleet (Player Faction)
| Asset | Use Case |
|-------|----------|
| `concord_fighter_a` | Player primary fighter — emerald-tinted variant |
| `concord_fighter_b` | Squadmate/AI fighter — alternate silhouette |
| `concord_shuttle` | Boarding craft / crew transport |
| `concord_station_module` | Capital ship section / station hub piece |

### Sundered Reach (Hostile Faction)
| Asset | Use Case |
|-------|----------|
| `sundered_scout` | Small hostile drone — early warning / harassment |
| `sundered_flyer` | Flying bomber — orbital threat |
| `sundered_mech_light` | Light mech — standard hostile encounter |
| `sundered_mech_heavy` | Heavy mech — boss / elite encounter |
| `sundered_brute` | Large hostile — capital-class threat |

### Asteroid Field Mining
| Asset | Use Case |
|-------|----------|
| `asteroid_rock_a` | Large mining target (mission objective) |
| `asteroid_rock_b` | Medium rock (draggable salvage) |
| `asteroid_rock_small` | Small debris (collectible) |
| `asteroid_cluster` | Destructible cluster (explosive) |

### System Map Backdrops (10 systems)
| Asset | Use Case |
|-------|----------|
| `planet_gas_giant` | Outer rim gas giant system |
| `planet_terran` | Habitable zone / colony world |
| `planet_lava` | Hazard system (mining risk) |
| `planet_ice` | Outer rim ice world |
| `planet_desert` | Neutral station location |
| `planet_ocean` | Deep space ocean world |
| `planet_toxic` | Sundered Reach home system |
| `planet_ringed` | Naval chokepoint / strategic pass |
| `planet_crystal` | Rare resource extraction site |
| `planet_dead` | Jump-gate ruin / derelict system |

### Mission Debris & Salvage
| Asset | Use Case |
|-------|----------|
| `debris_solar_panel` | Solar panel wreckage (salvage pickup) |
| `debris_structure` | Generic space structure (cover / scenery) |
| `debris_antenna` | Comms relay antenna (objective marker) |
| `debris_rover` | Abandoned rover (scannable lore) |

### Crew & Characters
| Asset | Use Case |
|-------|----------|
| `crew_astronaut_a` | Crew variant A — recolor to emerald for Concord |
| `crew_astronaut_b` | Crew variant B — recolor to grey for neutral |
| `crew_astronaut_c` | Crew variant C — recolor to red for Sundered |

### Station Buildings (Cutscene Backgrounds)
| Asset | Use Case |
|-------|----------|
| `building_house` | Residential zone (station approach) |
| `building_long` | Docking bay corridor |
| `building_l_shape` | Hub intersection |
| `building_dome` | Command center / operations |
| `building_pod` | Crew quarters habitat |

## Surprises & Notes

- **Astronaut scale**: Quaternius humanoids are ~4.6 units tall (meters), which
  is slightly taller than typical game characters. The 1.27 depth suggests a
  T-pose rather than A-pose. These will need minor scale adjustment (~0.85x)
  when placed inside ship interiors to match the Meshy-generated room shells.
- **Asteroid sizes are generous**: `asteroid_rock_a` is 7.67 x 7.33 units —
  large enough to serve as a mission backdrop rather than handheld object.
  This works well for "mining field" scenes where the player approaches them.
- **Planet sizes are consistent**: All planets are in the 4-5 unit diameter
  range, perfect for system map backdrops at distance.
- **Mech silhouettes are distinct**: Light mech (3.29 x 3.78 x 2.35) vs
  heavy mech (larger) have clearly different silhouettes — good for instant
  threat recognition during gameplay.

## Recommended Next Steps

1. **Crew deck wiring**: Place `crew_astronaut_a/b/c` instances in
   `res://scenes/crew_deck.tscn` with per-instance material overrides for
   faction color. Hook into `crew_deck.gd` spawn points.
2. **System map**: Create `res://scenes/system_map.gd` that instantiates
   planet assets as Sprite3D billboards and positions them on a 2D plane.
   Each planet maps to a `SystemData` resource.
3. **Mining encounters**: Wire `asteroid_rock_a/b` into `res://scenes/mining_field.gd`
   as destructible targets with `HealthComponent`. `asteroid_cluster` becomes
   the explosive variant.
4. **Station approach**: Compose a cutscene scene using `building_*` variants
   as backdrop geometry. Position camera at 50m for parallax.
5. **Sundered encounters**: Place `sundered_*` mechs in combat arenas. The
   `sundered_mech_heavy` should have a `BossComponent` and unique loot table.
6. **Debris salvage**: Wire `debris_*` into `res://scenes/salvage_point.tscn`
   with `Interactable` component for the "scan" prompt.

## Technical Notes

- All assets are CC0 (Public Domain) — no attribution required.
- Repacked at 1024² JPEG q=88 (same pipeline as Meshy assets).
- 35/35 pass `load()` in Godot 4.4.1 headless.
- SOURCES.md records full provenance (URL, size, local path).
