extends Node3D
## Exactly three roaming neighbours; all animation and physics suspend outside
## the settlement. Tonico can be registered without adding a fourth wanderer.
signal attacked(actor,source)
const ORIGIN := Vector3(-330,0,108)
const ROUTES := [
	[Vector3(-35,0,3),Vector3(-50,0,3),Vector3(-54,0,14),Vector3(-35,0,14)],
	[Vector3(3,0,1),Vector3(17,0,1),Vector3(27,0,10),Vector3(3,0,10)],
	[Vector3(44,0,3),Vector3(49,0,3),Vector3(49,0,24),Vector3(44,0,24)]]
var session
var residents: Array[CharacterBody3D] = []
var region_active := true
var hostile := false
var target: Node3D
var _near := false
var _scan := 0.0
var house_guards

func bind_homes(homes, quest) -> void:
	if is_instance_valid(house_guards): return
	house_guards=preload("res://gameplay/urban_v1/TruckersVillageHouseGuards.gd").new()
	house_guards.configure(self,homes,quest)
	add_child(house_guards)
	quest.bind_house_guards(house_guards)

func house_entered(index: int, point: Vector3) -> bool:
	return is_instance_valid(house_guards) and house_guards.house_entered(index,point)

func configure(owner_session) -> void:
	session = owner_session
	name = "TruckersVillageResidents"

func _ready() -> void:
	for index in ROUTES.size():
		var points: Array = []
		for p in ROUTES[index]: points.append(p+ORIGIN)
		var resident := preload("res://gameplay/urban_v1/TruckersVillageResident.gd").new()
		resident.configure({"id":"village_neighbour_%d"%index,"variant":index,"position":points[0],"route":points},session.world.gameplay if session!=null else null)
		add_child(resident)
		register_resident(resident)
	_update_activity()

func register_resident(resident: CharacterBody3D) -> void:
	if residents.has(resident): return
	residents.append(resident)
	resident.attacked.connect(_on_attacked)
	resident.set_hostile(hostile,target)
	resident.set_active(region_active and _near)

func _on_attacked(actor,source) -> void:
	attacked.emit(actor,source)

func set_hostile(value: bool,source: Node3D = null) -> void:
	hostile = value
	target = source if value else null
	for resident in residents:
		if is_instance_valid(resident): resident.set_hostile(value,target)
	if is_instance_valid(house_guards): house_guards.set_hostile(value,target)

func provoke(source: Node3D) -> void:
	set_hostile(true,source)

func set_region_active(value: bool) -> void:
	region_active = value
	_update_activity(true)

func _process(delta: float) -> void:
	_scan -= delta
	if _scan>0: return
	_scan = .3
	_update_activity()

func _update_activity(force := false) -> void:
	var nearby := region_active
	if session!=null and is_instance_valid(session.world.player):
		nearby = nearby and session.world.player.global_position.distance_to(ORIGIN)<135
	if nearby==_near and not force: return
	_near = nearby
	for resident in residents:
		if is_instance_valid(resident): resident.set_active(nearby)
