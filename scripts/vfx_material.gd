extends RefCounted
# VfxMaterial: factory helpers for the unshaded emissive StandardMaterial3D resources
# used throughout combat VFX (projectiles, beams, explosions, muzzle flashes, shield
# impacts, debris, decals, demo effects).
#
# Extracted from main.gd / ship.gd to eliminate ~15 near-identical material-creation
# blocks scattered across the codebase. Every function is pure and stateless.
#
# No class_name (avoids circular-import pitfalls); called via preload from main.gd.

# Unshaded emissive material — the workhorse of every combat/VFX effect.
#   color            : albedo + emission colour
#   energy           : emission_energy_multiplier
#   transparent      : enable TRANSPARENCY_ALPHA
#   cull_disabled    : disable back-face culling (shield bubbles, decals)
#   no_depth_test    : render on top of geometry (hit decals)
static func make_emissive(
	color: Color,
	energy: float = 5.0,
	transparent: bool = false,
	cull_disabled: bool = false,
	no_depth_test: bool = false,
) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b)
	mat.emission_energy_multiplier = energy
	if transparent:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if cull_disabled:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if no_depth_test:
		mat.no_depth_test = true
	return mat

# Faction-tinted projectile colour (green for player, orange-red for hostile).
static func projectile_color(faction: String) -> Color:
	return Color(0.5, 1.0, 0.6) if faction == "player" else Color(1.0, 0.5, 0.35)

# Faction-tinted beam colour (teal for player, red-pink for hostile).
static func beam_color(faction: String) -> Color:
	return Color(0.6, 1.0, 0.8) if faction == "player" else Color(1.0, 0.4, 0.5)
