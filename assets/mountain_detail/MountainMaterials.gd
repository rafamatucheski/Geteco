extends RefCounted
class_name MountainMaterials

## Centralized shared material palette for mountain architecture, sawmill, and village props.
## Strictly follows Geteco V2 performance standards: single shared cached StandardMaterial3D instances,
## zero dynamic shadow thrashing, no per-instance material allocation.

static var _cache: Dictionary = {}

static func get_mat(key: String, color: Color = Color.WHITE, roughness: float = 0.82, metallic: float = 0.0) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	_cache[key] = mat
	return mat

# --- Wood and Timber ---

static func wood_log() -> StandardMaterial3D:
	return get_mat("wood_log", Color("2b1c12"), 0.92)

static func wood_cut_end() -> StandardMaterial3D:
	return get_mat("wood_cut_end", Color("d2a86a"), 0.72)

static func wood_board() -> StandardMaterial3D:
	return get_mat("wood_board", Color("825d3b"), 0.80)

static func wood_board_aged() -> StandardMaterial3D:
	return get_mat("wood_board_aged", Color("5c4430"), 0.86)

static func wood_beam() -> StandardMaterial3D:
	return get_mat("wood_beam", Color("483321"), 0.88)

static func wood_shingle() -> StandardMaterial3D:
	return get_mat("wood_shingle", Color("38291f"), 0.90)

static func wood_pole() -> StandardMaterial3D:
	return get_mat("wood_pole", Color("533c2a"), 0.85)

static func wood_bench() -> StandardMaterial3D:
	return get_mat("wood_bench", Color("6b4d37"), 0.82)

# --- Snow and Ice ---

static func snow_fresh() -> StandardMaterial3D:
	return get_mat("snow_fresh", Color("f0f4f8"), 0.90)

static func snow_compact() -> StandardMaterial3D:
	return get_mat("snow_compact", Color("9cabb3"), 0.65)

# --- Stone and Ground ---

static func stone_river() -> StandardMaterial3D:
	return get_mat("stone_river", Color("555a5e"), 0.88)

static func stone_moss() -> StandardMaterial3D:
	return get_mat("stone_moss", Color("384534"), 0.92)

static func stone_paving() -> StandardMaterial3D:
	return get_mat("stone_paving", Color("738085"), 0.82)

static func sawdust() -> StandardMaterial3D:
	return get_mat("sawdust", Color("b89255"), 0.95)

static func dirt_earth() -> StandardMaterial3D:
	return get_mat("dirt_earth", Color("382e22"), 0.92)

# --- Metals ---

static func metal_iron() -> StandardMaterial3D:
	return get_mat("metal_iron", Color("222326"), 0.40, 0.85)

static func metal_strap() -> StandardMaterial3D:
	return get_mat("metal_strap", Color("636869"), 0.35, 0.80)

static func metal_blade() -> StandardMaterial3D:
	return get_mat("metal_blade", Color("8d9698"), 0.25, 0.90)

static func metal_brass() -> StandardMaterial3D:
	return get_mat("metal_brass", Color("cfa648"), 0.35, 0.80)

# --- Glass and Glow ---

static func glass_warm() -> StandardMaterial3D:
	if _cache.has("glass_warm"):
		return _cache["glass_warm"]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.65, 0.35, 0.75)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.18
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = true
	mat.emission = Color("e09c3e")
	mat.emission_energy_multiplier = 0.45
	_cache["glass_warm"] = mat
	return mat

static func glass_clear() -> StandardMaterial3D:
	if _cache.has("glass_clear"):
		return _cache["glass_clear"]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.72, 0.78, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.15
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache["glass_clear"] = mat
	return mat

# --- Props and Accents ---

static func tarp_green() -> StandardMaterial3D:
	return get_mat("tarp_green", Color("365445"), 0.85)

static func tarp_brown() -> StandardMaterial3D:
	return get_mat("tarp_brown", Color("4f3d2f"), 0.85)

static func brazier_coals() -> StandardMaterial3D:
	if _cache.has("brazier_coals"):
		return _cache["brazier_coals"]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("2b120c")
	mat.roughness = 0.90
	mat.emission_enabled = true
	mat.emission = Color("e24b22")
	mat.emission_energy_multiplier = 1.2
	_cache["brazier_coals"] = mat
	return mat

static func mannequin_cloth(color: Color) -> StandardMaterial3D:
	var hex := color.to_html(false)
	var key := "cloth_" + hex
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	_cache[key] = mat
	return mat

static func sign_timber() -> StandardMaterial3D:
	return get_mat("sign_timber", Color("3d2c1e"), 0.85)
