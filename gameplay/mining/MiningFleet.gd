extends RefCounted
## Industrial vehicles use the production Vehicle/Driving/save path.
const IDS := ["mining_backhoe", "mining_tractor", "mining_haul_truck"]
const DATA := {
	"mining_backhoe": {"label":"Retroescavadeira", "bounds_size":[2.8,3.0,4.8], "mass":8.0, "max_speed":150.0, "acceleration":950.0, "turn_speed":1.7, "colors":["d3a238ff"], "durability":950.0},
	"mining_tractor": {"label":"Trator carregador", "bounds_size":[2.7,2.9,4.4], "mass":6.0, "max_speed":170.0, "acceleration":1000.0, "turn_speed":1.9, "colors":["698051ff"], "durability":850.0},
	"mining_haul_truck": {"label":"Caminhão de mineração", "bounds_size":[4.6,3.6,8.0], "mass":28.0, "max_speed":200.0, "acceleration":1400.0, "turn_speed":1.05, "colors":["d1a24aff"], "durability":1600.0}
}
static func spec(id: String) -> Dictionary:
	if not DATA.has(id): return {}
	var s: Dictionary = DATA[id].duplicate(true)
	s.merge({"id":id,"bounds_center":[0,float(s.bounds_size[1])*.5,0],"braking":1800.0,"drift_factor":.74,"drivetrain":"4x4","engine_family":"diesel","engine_pitch":.72,"roof_prop":"none","vehicle_kind":"truck","damage_resistance":.55},true)
	return s

static func create_model(id: String) -> Node3D:
	return preload("res://world/mining/operation/MiningMachineModel.gd").create(id)

static func door_spec(id: String) -> Dictionary:
	if id not in IDS: return {}
	if id == "mining_haul_truck": return {"class":"truck","zf":-3.40,"zr":-1.90,"sill":1.18,"belt":1.90,"top":3.55,"x":.94,"stand_z_min":-1.48}
	return {"class":"truck","zf":-.65,"zr":.85,"sill":.98,"belt":1.70,"top":2.88,"x":.94}

static func attach(car: CharacterBody3D) -> void:
	if car.archetype not in IDS or car.has_node("MiningMachine"): return
	var controller: Node = load("res://gameplay/mining/MiningMachine.gd").new()
	controller.name = "MiningMachine"
	controller.vehicle = car
	car.add_child(controller)
