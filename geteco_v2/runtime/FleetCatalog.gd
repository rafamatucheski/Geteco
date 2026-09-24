extends RefCounted
static var _data: Dictionary = {}
static func all() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/fleet/catalog.json"))
		if parsed is Dictionary: _data = parsed.vehicles
	return _data
static func spec(id: String) -> Dictionary:
	return all().get(id,preload("res://runtime/GarageRewardFleet.gd").spec(id))
static func create(id: String) -> Node3D:
	var definition := spec(id)
	if definition.is_empty(): return null
	var packed := load(definition.scene) as PackedScene
	return packed.instantiate() if packed else null
static func default_paint(id: String, fallback := Color.WHITE) -> Color:
	var colors: Array = spec(id).get("colors",[])
	return Color.html(str(colors.pick_random())) if not colors.is_empty() else fallback
