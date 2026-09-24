class_name VehiclePrewarmManifest
extends RefCounted

## Region-owned vehicle presentation manifests. Runtime traffic lists remain the
## authority: this file reads their constants dynamically, then adds only the
## explicit vehicles authored outside those lists.

const CATALOG := preload("res://cars/VehicleCatalog.gd")

const HARBOR_EXPLICIT_IDS: Array[String] = [
	# HarborSouthPort / port logistics.
	"cargo_flatbed_truck", "dock_delivery_van", "ranch_single", "port_forklift",
	# Garage, gang and persistent player vehicles.
	"porto_rosso", "ranch_pickup", "monaliza",
	# HarborPreview and service recovery.
	"towmaster",
]

const EMERGENCY_IDS: Array[String] = [
	"police_cruiser", "police_suv", "medic_box", "rescue_pumper", "courier_van",
]

const HARBOR_RUNTIME_MODELS: Array[String] = [
	"res://geodata/transit/RegionalIntercityCoachModel.gd",
	"res://police/PoliceMotorcycleModel.gd",
	"res://world/harbor/HarborContainerTruckModel.gd",
	"res://world/harbor/HarborTransitBusModel.gd",
	"res://world/harbor/urban_transit/UrbanBusModel.gd",
	"res://world/harbor/urban_transit/UrbanBusTrailerModel.gd",
]

static func region_ids() -> Array[StringName]:
	return [&"harbor", &"harbor_traffic", &"emergency", &"harbor_mission", &"mountain"]

static func vehicle_ids(region_id: StringName) -> Array[String]:
	var result: Array[String] = []
	match region_id:
		&"harbor":
			_append_unique(result, vehicle_ids(&"harbor_traffic"))
			_append_unique(result, vehicle_ids(&"emergency"))
			_append_unique(result, vehicle_ids(&"harbor_mission"))
		&"harbor_traffic":
			_append_unique(result, _script_array("res://world/harbor/HarborLife.gd", "CAR_TYPES"))
			_append_unique(result, _script_array("res://world/harbor/HarborLife.gd", "MOTORCYCLE_TYPES"))
			_append_unique(result, HARBOR_EXPLICIT_IDS)
		&"emergency":
			_append_unique(result, EMERGENCY_IDS)
		&"harbor_mission":
			# These identities are loaded by the current Harbor save/mission graph.
			_append_unique(result, ["porto_rosso", "monaliza", "ranch_pickup"])
		&"mountain":
			_append_unique(result, _script_array("res://world/mountain_pass/MountainTraffic.gd", "FLEET"))
			for parking in _script_array("res://world/mountain_pass/MountainVillageLayout.gd", "PARKING"):
				if parking is Array and parking.size() > 1:
					_append_unique(result, [String(parking[1])])
	return result

static func model_paths(region_id: StringName) -> Array[String]:
	var result: Array[String] = []
	for vehicle_id in vehicle_ids(region_id):
		var spec: Dictionary = CATALOG.get_vehicle_spec(vehicle_id)
		var path := String(spec.get("model_class", ""))
		if not path.is_empty() and ResourceLoader.exists(path) and not result.has(path):
			result.append(path)
	if region_id == &"harbor":
		_append_unique(result, HARBOR_RUNTIME_MODELS)
	elif region_id == &"emergency":
		_append_unique(result, ["res://police/PoliceMotorcycleModel.gd"])
	result.sort()
	return result

static func _script_array(path: String, constant_name: String) -> Array:
	var script := load(path) as Script
	if script == null:
		return []
	return script.get_script_constant_map().get(constant_name, []) as Array

static func _append_unique(target: Array, values: Array) -> void:
	for value in values:
		if not target.has(value):
			target.append(value)
