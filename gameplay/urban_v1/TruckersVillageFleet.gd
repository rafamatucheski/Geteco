extends Node
## Authored parked vehicles, restored by stable id and suspended away from play.
const ORIGIN := Vector3(-330,0,108)
const SPOTS := [
	["ranch_single",Vector3(-55,.12,-29),.28,"867b56"],
	["lumber_pickup_4x4",Vector3(12,.12,-21),-.36,"835745"],
	["desert_jeep_4x4",Vector3(67,.12,13),1.8,"b0a17d"],
	["arctic_jeep",Vector3(-52,.12,21),2.85,"607052"],
	["bike_cruiser",Vector3(-10,.12,-30),.7,"664936"],
	["bike_urban",Vector3(58,.12,7),2.6,"8e5843"],
	["surf_woody_wagon",Vector3(5,.12,20),-1.4,"697c73"]]
const STATE := preload("res://runtime/FleetState.gd")
var session
var cars: Dictionary = {}
var saved: Dictionary = {}
var _scan := 0.0

func configure(owner_session) -> void:
	session=owner_session
	name="TruckersVillageFleet"

func _process(delta: float) -> void:
	if session==null or not session.ready_for_play: return
	_scan-=delta
	if _scan>0: return
	_scan=.5
	var spawned := false
	for i in SPOTS.size():
		var id := "tonico_parked_%d"%i
		var car = cars.get(id)
		if not is_instance_valid(car):
			for existing in session.controller.vehicles:
				if is_instance_valid(existing) and not existing.is_queued_for_deletion() and existing.vehicle_id==id:
					car=existing
					cars[id]=car
					car.set_meta("secret_discovery_vehicle",true)
					break
		if is_instance_valid(car):
			_capture(id,car)
			var occupied: bool = car==session.world.driving.car and session.world.driving.occupied
			var active: bool = occupied or (session.state.region_id==str(car.get_meta("region_id","harbor")) and session.state.place_id.is_empty() and car.global_position.distance_to(session.world.player.global_position)<125)
			if active==not car.get_meta("village_parked_suspended",false): continue
			if active:
				session.controller.region.prepare_collision_at(car.global_position)
				if not session.controller.vehicle_position_clear(car,car.global_position,car.rotation.y): continue
			car.set_meta("village_parked_suspended",not active)
			car.visible=active
			car.collision_layer=4 if active else 0
			car.set_physics_process(active and car.health>0)
			continue
		if spawned or session.state.region_id!="harbor" or not session.state.place_id.is_empty(): continue
		var record: Dictionary = saved.get(id,{})
		if not record.is_empty() and record.health<=0: continue
		var point: Vector3 = ORIGIN+SPOTS[i][1]
		if record.has("position"): point=Vector3(record.position[0],record.position[1],record.position[2])
		if record.get("region","harbor")!="harbor" or point.distance_to(session.world.player.global_position)>95: continue
		session.controller.region.prepare_collision_at(point)
		car=session.controller.spawn_vehicle(SPOTS[i][0],point,float(record.get("yaw",SPOTS[i][2])))
		if not is_instance_valid(car): continue
		spawned=true
		car.vehicle_id=id
		car.traffic=false
		car.brake_input=true
		car.paint_color=Color.html(str(record.get("paint",SPOTS[i][3])))
		car.health=float(record.get("health",car.max_health))
		car.set_meta("secret_discovery_vehicle",true)
		car.equipment_state=record.get("equipment",{}).duplicate(true)
		cars[id]=car
		_capture(id,car)

func _capture(id: String,car: CharacterBody3D) -> void:
	if not car.global_position.is_finite(): return
	saved[id]=STATE.capture(car,str(car.get_meta("region_id","harbor")))

func snapshot() -> Dictionary:
	for id in cars:
		if is_instance_valid(cars[id]): _capture(id,cars[id])
	return saved.duplicate(true)

func restore_snapshot(data: Dictionary) -> bool:
	if not validate_snapshot(data): return false
	saved=data.duplicate(true)
	for id in cars:
		var car = cars[id]
		if not is_instance_valid(car) or not saved.has(id): continue
		# ProductionWorld restores the selected vehicle; never duplicate it.
		if car==session.world.driving.car: continue
		car.queue_free()
	cars.clear()
	_scan=0
	return true

static func validate_snapshot(data: Dictionary) -> bool:
	if data.size()>SPOTS.size(): return false
	for id in data:
		if not id is String or not id.begins_with("tonico_parked_"): return false
		var index: int = id.trim_prefix("tonico_parked_").to_int()
		if index<0 or index>=SPOTS.size() or id!="tonico_parked_%d"%index: return false
		if not data[id] is Dictionary or not STATE.validate(data[id]): return false
		if data[id].get("vehicle_id","")!=id or data[id].archetype!=SPOTS[index][0]: return false
	return true
