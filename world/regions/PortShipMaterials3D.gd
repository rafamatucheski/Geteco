extends RefCounted
## Shared, world-tiled maritime paint for both native harbor ships.
const HULL := preload("res://world/regions/ship_hull_weathered.png")
const DECK := preload("res://world/regions/ship_deck_nonslip.png")
const CRANE := preload("res://world/regions/crane_yellow_weathered.png")
static var _cache: Dictionary = {}

static func material(kind: String) -> StandardMaterial3D:
	if _cache.has(kind): return _cache[kind]
	var result := StandardMaterial3D.new()
	result.uv1_triplanar = true
	result.uv1_world_triplanar = true
	match kind:
		"hull":
			result.albedo_texture = HULL
			result.uv1_scale = Vector3.ONE/4.0
			result.roughness = .76
			result.metallic = .17
		"deck":
			result.albedo_texture = DECK
			result.uv1_scale = Vector3.ONE/7.5
			result.roughness = .88
			result.metallic = .11
		"crane":
			result.albedo_texture = CRANE
			result.uv1_scale = Vector3.ONE/2.0
			result.roughness = .69
			result.metallic = .21
	_cache[kind] = result
	return result
