extends RefCounted
## Shared material families; metal, stone, cloth and glass retain distinct response.
const TILES := preload("res://world/places/ShopInteriorMaterials.gd")
static var _cache: Dictionary = {}

static func material(kind: String, color: Color) -> StandardMaterial3D:
	var key := kind + color.to_html()
	if _cache.has(key): return _cache[key]
	var value := StandardMaterial3D.new()
	value.albedo_color = color
	value.roughness = .86
	if kind in ["wood", "cloth", "stone"]:
		value.albedo_texture = TILES.texture(kind)
		value.uv1_triplanar = true
		value.uv1_scale = Vector3(1.4, 1.4, 1.4) if kind == "wood" else Vector3.ONE * 2.0
		value.roughness = .96 if kind == "cloth" else .77
	elif kind == "metal":
		value.metallic = .65
		value.roughness = .36
	elif kind == "ceramic": value.roughness = .28
	elif kind == "glass":
		# Opaque dark glazing avoids transparent sorting on cupboard panes/screens.
		value.metallic = .20
		value.roughness = .16
	elif kind == "tank_glass":
		value.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		value.albedo_color.a = .16
		value.roughness = .12
	elif kind == "paper": value.roughness = .97
	elif kind == "light":
		value.emission_enabled = true
		value.emission = color
		value.emission_energy_multiplier = .65
	_cache[key] = value
	return value
