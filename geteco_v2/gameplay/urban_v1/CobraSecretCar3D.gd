extends Node

## The original Ashbend corner parking and its single discoverable copper coupe.
const PARKING := Vector3(7050.0 / 16.0, .12, 2290.0 / 16.0)
const VEHICLE_ID := "ashbend_copper_coupe"
var session
var car: CharacterBody3D
var scan_clock := 0.0

func configure(owner_session) -> void:
	session = owner_session
	name = "CobraSecretCar3D"
	process_mode = Node.PROCESS_MODE_PAUSABLE

func _process(delta: float) -> void:
	if session == null or session.state == null or not is_instance_valid(session.world.player): return
	scan_clock -= delta
	if scan_clock > 0.0: return
	scan_clock = .35
	if is_instance_valid(car):
		if car.health <= 0.0:
			session.state.world_state["ashbend_secret_car_claimed"] = true
			_capture_car(true)
			return
		var player_driving: bool = session.world.driving.occupied and session.world.driving.car == car
		var nearby: bool = session.state.place_id.is_empty() and session.state.region_id == str(car.get_meta("region_id","harbor")) and session.world.player.global_position.distance_to(car.global_position) < 120.0
		if not player_driving and not nearby:
			if not car.get_meta("secret_suspended",false):
				if bool(session.state.world_state.get("ashbend_secret_car_claimed",false)): _capture_car()
				car.set_meta("secret_suspended",true)
				car.visible = false
				car.set_physics_process(false)
			return
		if car.get_meta("secret_suspended",false):
			if not session.controller.vehicle_position_clear(car,car.global_position,car.rotation.y): return
			car.remove_meta("secret_suspended")
			car.visible = true
			car.set_physics_process(true)
		var newly_claimed: bool = not bool(session.state.world_state.get("ashbend_secret_car_claimed",false)) and (car.controlled or car.global_position.distance_to(PARKING) > 7.0)
		if newly_claimed: session.state.world_state["ashbend_secret_car_claimed"] = true
		if bool(session.state.world_state.get("ashbend_secret_car_claimed",false)): _capture_car()
		if newly_claimed and not session.controller.no_save: session.save_game()
		return
	for existing in session.controller.vehicles:
		if is_instance_valid(existing) and existing.vehicle_id == VEHICLE_ID:
			car = existing
			car.set_meta("secret_discovery_vehicle",true)
			return
	var saved: Dictionary = session.state.world_state.get("ashbend_secret_car",{})
	if bool(saved.get("destroyed",false)): return
	if bool(session.state.world_state.get("ashbend_secret_car_claimed",false)) and saved.is_empty(): return
	var point := PARKING
	if saved.has("position"):
		point = Vector3(float(saved.position[0]),float(saved.position[1]),float(saved.position[2]))
	var region: String = str(saved.get("region","harbor"))
	if session.state.region_id != region or not session.state.place_id.is_empty(): return
	if session.world.player.global_position.distance_to(point) > 75.0: return
	car = session.controller.spawn_vehicle("cobra_v8",point,float(saved.get("yaw",PI)))
	if not is_instance_valid(car): return
	car.vehicle_id = VEHICLE_ID
	car.paint_color = Color.html(str(saved.get("paint","9f673f")))
	car.health = float(saved.get("health",car.max_health))
	car.traffic = false
	car.brake_input = true
	car.set_meta("secret_discovery_vehicle",true)
	car.set_meta("region_id",region)
	car.destroyed.connect(func():
		if is_instance_valid(session) and session.state != null:
			session.state.world_state["ashbend_secret_car_claimed"] = true
			_capture_car(true)
	)

func _capture_car(destroyed := false) -> void:
	if not is_instance_valid(car) or session == null or session.state == null: return
	var position := car.global_position
	if not position.is_finite(): return
	session.state.world_state["ashbend_secret_car"] = {
		"position":[position.x,position.y,position.z],
		"yaw":car.rotation.y,
		"paint":car.paint_color.to_html(false),
		"health":0.0 if destroyed else maxf(0.0,car.health),
		"region":str(car.get_meta("region_id","harbor")),
		"destroyed":destroyed,
	}

static func validate_record(data: Dictionary) -> bool:
	if data.is_empty(): return true
	if not data.get("position",[]) is Array or data.position.size() != 3: return false
	for value in data.position:
		if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or absf(float(value)) > 100000.0: return false
	if typeof(data.get("yaw")) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(data.yaw)): return false
	if not data.get("paint") is String or not Color.html_is_valid(data.paint): return false
	if typeof(data.get("health")) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(data.health)) or float(data.health) < 0.0 or float(data.health) > 140.0: return false
	if str(data.get("region","")) not in ["harbor","mountain"]: return false
	return data.get("destroyed") is bool
