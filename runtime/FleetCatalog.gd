extends RefCounted
static var _data: Dictionary = {}
static var _last_paint_index: Dictionary = {}
# Civilian models whose exported catalog only contains the showroom color.
const SPAWN_PALETTES := {
	"dune_buggy": ["ffffffff", "dba638ff", "c45638ff", "3d827fff", "405948ff"],
	"monaliza": ["183b91ff", "722e30ff", "e6e4dfff", "171b20ff", "92979cff"],
	"muscle_classic": ["ffffffff", "963b32ff", "284d79ff", "d09b37ff", "294d43ff", "171b20ff"],
	"porto_rosso": ["e01824ff", "e6e4dfff", "171b20ff", "dba638ff", "284d79ff"],
	"ranch_pickup": ["ffffffff", "8b5941ff", "526b4eff", "315b6bff", "7b3035ff"],
	"sport_coupe": ["ffffffff", "b63b32ff", "31577aff", "d5a544ff", "171b20ff", "92979cff"],
	"station_wagon": ["ffffffff", "456354ff", "843c35ff", "456877ff", "b69b66ff"],
}
static func all() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/fleet/catalog.json"))
		if parsed is Dictionary:
			_data = parsed.vehicles
			var transport: Dictionary = _data.courier_van.duplicate(true)
			transport.merge({"id":"police_transport", "label":"Camburão tático", "colors":["202128ff"], "durability":380, "mass":2.6, "roof_prop":"none"}, true)
			_data["police_transport"] = transport
			var motorcycle: Dictionary = _data.bike_urban.duplicate(true)
			motorcycle.merge({"id":"bike_police", "label":"Moto policial", "colors":["e4e7e4ff"], "durability":145, "max_speed":345.0, "roof_prop":"none"}, true)
			_data["bike_police"] = motorcycle
			var tank: Dictionary = _data.police_cruiser.duplicate(true)
			tank.merge({"id":"army_tank", "label":"Blindado do Exército", "colors":["64704eff"], "bounds_size":[3.18,2.85,5.3], "bounds_center":[0,1.425,0], "durability":3000, "damage_resistance":0.4, "mass":30.0, "max_speed":208.0, "acceleration":650.0, "braking":1100.0, "turn_speed":1.1, "drivetrain":"4x4", "engine_family":"tank", "roof_prop":"none"}, true)
			_data["army_tank"] = tank
	return _data
static func spec(id: String) -> Dictionary:
	return all().get(id,preload("res://runtime/GarageRewardFleet.gd").spec(id))
static func create(id: String) -> Node3D:
	var definition := spec(id)
	if definition.is_empty(): return null
	if id == "army_tank": return preload("res://gameplay/police_response/ground/PoliceGroundModels.gd").tank()
	if id == "nordic_estate": return preload("res://assets/fleet/nordic_estate_detail.scn").instantiate() as Node3D
	var packed := load(definition.scene) as PackedScene
	if packed == null: return null
	var model := packed.instantiate() as Node3D
	if id == "police_transport": preload("res://gameplay/dispatch/PoliceTransportModel.gd").decorate(model)
	if id == "bike_police": preload("res://gameplay/police_response/ground/PoliceGroundModels.gd").motorcycle(model)
	preload("res://runtime/HeavyVehicleDetail.gd").decorate(id, model)
	preload("res://runtime/VehicleFinish.gd").decorate(id, model)
	preload("res://runtime/VehicleTwoTone.gd").decorate(id, model)
	if id == "taxi_yellow": preload("res://runtime/TaxiLivery.gd").decorate(model)
	if id == "aurora_executive": preload("res://runtime/AuroraExecutiveDetail.gd").decorate(model)
	else: preload("res://runtime/FleetSpeedPass.gd").decorate(id, model)
	return model
static func default_paint(id: String, fallback := Color.WHITE) -> Color:
	var colors: Array = SPAWN_PALETTES.get(id, spec(id).get("colors", []))
	if id in preload("res://runtime/VehicleTwoTone.gd").MODELS:
		colors = preload("res://runtime/VehicleTwoTone.gd").PALETTES
	if colors.is_empty(): return fallback
	# One bounded draw per spawn; skip the last choice without retry loops.
	var previous: int = int(_last_paint_index.get(id, -1))
	var index := 0
	if colors.size() > 1:
		if previous >= 0 and previous < colors.size():
			index = randi_range(0, colors.size() - 2)
			if index >= previous: index += 1
		else:
			index = randi_range(0, colors.size() - 1)
	_last_paint_index[id] = index
	return Color.html(str(colors[index]))
