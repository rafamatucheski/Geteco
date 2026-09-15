extends Node
## Owns a driven vehicle while its source scene is unloaded. Disk saves use
## an allowlisted snapshot; live travel retains the actual instance.
const HARBOR := "res://world/harbor/HarborGame.tscn"
const MOUNTAIN := "res://world/mountain_pass/MountainPass.tscn"
const VEHICLE_SCRIPTS := [
	"res://PlayerCar.gd", "res://prototypes/living_cast/HarborCoupe.gd",
	"res://world/mountain_pass/MountainSUV.gd",
	"res://world/mountain_pass/ArcticJeep.gd",
	"res://world/mountain_pass/MountainPickup.gd",
	"res://world/shared/traffic/TrafficVehicle.gd",
	"res://world/harbor/monaliza/MonalizaCar.gd",
]
const CAR_FIELDS := ["health", "max_health", "max_speed", "acceleration", "braking", "friction", "turn_speed", "drift_factor", "has_nitro", "nitro_amount", "nitro_max", "has_puncture_proof_tires", "has_punctured_tires", "is_broken", "radio_index"]
var destination := ""
var passenger: Dictionary = {}
var carried_car: Node2D
var arrival_speed := 0.0
var pending_world: Dictionary = {}
var cooldown := 0.0

func _process(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)

func is_arriving() -> bool:
	return not destination.is_empty()

func controlled_car() -> Node2D:
	for vehicle in get_tree().get_nodes_in_group("vehicle"):
		if is_instance_valid(vehicle) and vehicle.get("is_driven_by_player") == true:
			return vehicle as Node2D
	return null

func request(region: String, actor: Node2D) -> bool:
	# Production borders are continuous geography. Legacy standalone previews
	# retain their travel helper, but never replace a running continuous world.
	if get_tree().get_first_node_in_group("continuous_world") != null:
		return false
	if is_arriving() or cooldown > 0 or region not in ["harbor", "mountain"]:
		return false
	var player := get_tree().get_first_node_in_group("player")
	var car := controlled_car()
	if player == null or actor != player and actor != car:
		return false
	if player.is_dead or player.is_arrested:
		return false
	destination = region
	passenger = player.serialize()
	carried_car = car
	arrival_speed = minf(car.velocity.length(), 200.0) if car else 0.0
	call_deferred("_depart")
	return true

func _depart() -> void:
	if is_instance_valid(carried_car):
		carried_car.force_exit_vehicle()
		carried_car.reparent(self, true)
		carried_car.process_mode = Node.PROCESS_MODE_DISABLED
		carried_car.hide()
	var error := get_tree().change_scene_to_file(MOUNTAIN if destination == "mountain" else HARBOR)
	if error != OK:
		if is_instance_valid(carried_car):
			carried_car.reparent(get_tree().current_scene, true)
			carried_car.process_mode = Node.PROCESS_MODE_INHERIT
			carried_car.show()
			carried_car.enter_vehicle(get_tree().get_first_node_in_group("player"))
		carried_car = null
		destination = ""
		passenger.clear()
		push_error("Region travel failed: " + error_string(error))

func finish_arrival(scene: Node) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	if pending_world.has("north_access_lower"):
		player.set_meta("north_access_lower",bool(pending_world.north_access_lower))
	var stream := get_tree().get_first_node_in_group("continuous_world")
	if stream != null and pending_world.get("region", "") == "mountain":
		if not stream.ready_for_crossing:
			stream.ensure_mountain()
			return
		if int(pending_world.get("coordinates_version", 1)) < 2:
			player.global_position += stream.MOUNTAIN_OFFSET
			var saved_car: Dictionary = pending_world.get("vehicle", {})
			if not saved_car.is_empty():
				saved_car.x = float(saved_car.get("x", 0)) + stream.MOUNTAIN_OFFSET.x
				saved_car.y = float(saved_car.get("y", 0)) + stream.MOUNTAIN_OFFSET.y
			var old_return: Array = pending_world.get("exterior_return", [7350, 730])
			pending_world.exterior_return = [old_return[0] + stream.MOUNTAIN_OFFSET.x, old_return[1] + stream.MOUNTAIN_OFFSET.y]
			pending_world.coordinates_version = 2
		_restore_saved_vehicle(scene, player)
		stream.mountain.restore_region_interior(player, pending_world)
		pending_world.clear()
		stream._update_region()
		var restored_camera := get_viewport().get_camera_2d()
		if restored_camera: restored_camera.reset_smoothing()
	if not pending_world.is_empty():
		_restore_saved_vehicle(scene, player)
		if scene.has_method("restore_region_interior"):
			scene.restore_region_interior(player, pending_world)
		pending_world.clear()
	if not is_arriving():
		return
	player.restore(passenger)
	var point := Vector2(3240, 430) if destination == "mountain" else Vector2(7530, -4640)
	var heading := 0.0 if destination == "mountain" else PI
	player.global_position = point
	player.velocity = Vector2.ZERO
	player.rotation = heading
	# Chegada em outra regiao: descarta o transform da regiao de origem.
	player.reset_physics_interpolation()
	if is_instance_valid(carried_car):
		carried_car.reparent(scene, true)
		carried_car.global_position = point
		carried_car.rotation = heading
		carried_car.reset_physics_interpolation()
		carried_car.show()
		carried_car.process_mode = Node.PROCESS_MODE_INHERIT
		carried_car.enter_vehicle(player)
		carried_car.velocity = Vector2.from_angle(heading) * arrival_speed
	player._refresh_weapon_ui()
	var camera := get_viewport().get_camera_2d()
	if camera:
		camera.reset_smoothing()
	carried_car = null
	destination = ""
	passenger.clear()
	cooldown = 2.0

func snapshot_world() -> Dictionary:
	var scene := get_tree().current_scene
	var region := "mountain" if scene != null and scene.scene_file_path == MOUNTAIN else "harbor" if scene != null and scene.scene_file_path == HARBOR else "legacy"
	var result := {"region": region}
	var stream := get_tree().get_first_node_in_group("continuous_world")
	if stream != null:
		region = stream.current_region
		result = {"region": region, "coordinates_version": 2}
		if region == "mountain": scene = stream.mountain
	if region == "mountain":
		result["temperature"] = scene.cold_controller.current_temperature
		result["weather_clock"] = scene.storm_manager.weather_clock
	var player := get_tree().get_first_node_in_group("player")
	result["north_access_lower"] = bool(player.get_meta("north_access_lower",false))
	if region == "mountain" and player.get_meta("mountain_interior",false):
		result["interior"] = String(player.get_meta("mountain_interior_id",""))
		var point: Vector2 = scene.interior_manager._actor_returns.get(player,Vector2(7350,730))
		result["exterior_return"] = [point.x,point.y]
	var car := controlled_car()
	if car:
		var script: String = car.get_script().resource_path
		var values := {}
		for key in CAR_FIELDS:
			if key in car:
				values[key] = car.get(key)
		var color := Color.WHITE
		if "paint_color" in car:
			color = car.paint_color
		elif "body_model" in car and is_instance_valid(car.body_model):
			color = car.body_model.paint.albedo_color
		elif "visual" in car and car.visual:
			color = car.visual.modulate
		elif "sprite" in car and car.sprite:
			color = car.sprite.modulate
		result["vehicle"] = {"script": script, "name": String(car.name), "archetype": car.get("active_archetype_id") if "active_archetype_id" in car else car.get("vehicle_id"), "paint": color.to_html(), "x": car.global_position.x, "y": car.global_position.y, "rotation": car.rotation, "values": values}
		result.vehicle["north_access_lower"] = bool(car.get_meta("north_access_lower",false))
		if car.has_meta("salvage_token"): result.vehicle["salvage_token"] = String(car.get_meta("salvage_token"))
		if car.get_meta("residence_stored_vehicle",false): result.vehicle["residence_stored_vehicle"] = true
		if car.has_meta("service_safe_position"):
			var safe: Vector2 = car.get_meta("service_safe_position")
			result.vehicle.x = safe.x
			result.vehicle.y = safe.y
			result.vehicle.rotation = car.get_meta("service_safe_rotation",car.rotation)
	var repair_data := {"world": result}
	for warning in sanitize_saved_coordinates(repair_data): push_warning(warning)
	return result

func _restore_saved_vehicle(scene: Node, player: Node) -> void:
	var restore_copy := {"world": pending_world}
	for warning in sanitize_saved_coordinates(restore_copy): push_warning(warning)
	var data: Dictionary = pending_world.get("vehicle", {})
	if data.is_empty():
		return
	var script := String(data.get("script", ""))
	if script not in VEHICLE_SCRIPTS:
		push_warning("Unrecognized saved vehicle; restoring player on foot.")
		return
	var car: Node2D
	var personal := script == "res://world/harbor/monaliza/MonalizaCar.gd"
	if personal:
		car = get_tree().get_first_node_in_group("personal_vehicle")
		if car == null: return
		car.unlocked = get_node("/root/CampaignState").has_campaign_flag(&"harbor_delivery_complete")
	elif script == "res://world/shared/traffic/TrafficVehicle.gd":
		car = load("res://world/shared/traffic/TrafficVehicle.tscn").instantiate()
	elif script.contains("mountain_pass"):
		car = load(script).new()
	else:
		# Both allowlisted player-car scripts require their physical/camera nodes
		# before _ready. A bare script cannot restore a drivable car.
		var car_script := load(script) as Script
		if car_script == null:
			push_warning("Saved vehicle script could not be loaded; restoring player on foot.")
			return
		car = load("res://world/shared/traffic/SavedPlayerCar.tscn").instantiate()
		car.set_script(car_script)
	car.name = String(data.get("name", "TravelVehicle"))
	car.set_meta("north_access_lower",bool(data.get("north_access_lower",false)))
	if data.has("salvage_token"): car.set_meta("salvage_token",String(data.salvage_token))
	if data.get("residence_stored_vehicle",false): car.set_meta("residence_stored_vehicle",true)
	car.position = Vector2(float(data.get("x", player.global_position.x)), float(data.get("y", player.global_position.y)))
	car.rotation = float(data.get("rotation", 0.0))
	if not personal: scene.add_child(car)
	if car.has_method("configure_as_parked"):
		car.configure_as_parked()
	var color := Color(String(data.get("paint", "ffffff")))
	if car.has_method("apply_archetype") and not script.contains("mountain_pass") and not personal:
		car.apply_archetype(String(data.get("archetype", "sport_coupe")), color)
	if car.has_method("repaint_vehicle"):
		car.repaint_vehicle(color)
	for key in CAR_FIELDS:
		if key in car and data.get("values", {}).has(key):
			car.set(key, data.values[key])
	car.enter_vehicle(player)

## Repairs only invalid legacy coordinates in a COPY supplied by SaveManager.
## Existing mission, inventory, health and paint data are left intact.
func sanitize_saved_coordinates(data: Dictionary) -> Array[String]:
	var warnings: Array[String] = []
	var world: Dictionary = data.get("world", {}) if data.get("world", {}) is Dictionary else {}
	var region := String(world.get("region", "legacy"))
	var fallback := Vector2.INF
	if region == "harbor": fallback = Vector2(1700,1130) # HarborGame/ArrivalSpawn
	elif region == "mountain":
		fallback = Vector2(3240,430) # Same authored entry as finish_arrival.
		if int(world.get("coordinates_version",1)) >= 2:
			fallback += preload("res://world/harbor/ContinuousWorld.gd").MOUNTAIN_OFFSET
	var player_data: Dictionary = data.get("player", {}) if data.get("player", {}) is Dictionary else {}
	if region in ["legacy", "harbor"]:
		const YARD_LOCATION = preload("res://world/shared/salvage/SalvageLocation.gd")
		if valid_saved_point(player_data.get("position", [])):
			var old_point := Vector2(float(player_data.position[0]),float(player_data.position[1]))
			var safe_point := YARD_LOCATION.safe_load_position(old_point,region=="legacy")
			player_data.position = [safe_point.x,safe_point.y]
		var saved_car: Dictionary = world.get("vehicle", {}) if world.get("vehicle", {}) is Dictionary else {}
		if valid_saved_point([saved_car.get("x"),saved_car.get("y")]):
			var car_point := Vector2(float(saved_car.x),float(saved_car.y))
			var safe_car := YARD_LOCATION.safe_load_position(car_point,region=="legacy")
			saved_car.x=safe_car.x
			saved_car.y=safe_car.y
	if player_data.has("position") and not valid_saved_point(player_data.position):
		if fallback.is_finite(): player_data.position = [fallback.x,fallback.y]
		else: player_data.erase("position") # Unknown scenes retain their own spawn.
		world.erase("interior")
		world.erase("exterior_return")
		warnings.append("Posição antiga inválida: personagem recuperado na entrada da região.")
	var personal: Dictionary = player_data.get("personal_car_state", {}) if player_data.get("personal_car_state", {}) is Dictionary else {}
	if personal.has("position") and not valid_saved_point(personal.position):
		personal.erase("position") # PersonalCarManager already defaults to its own garage bay.
		warnings.append("Posição antiga da Monaliza inválida: carro recuperado na oficina.")
	if personal.has("rotation") and not _valid_saved_number(personal.rotation): personal.rotation = PI/2
	var vehicle: Dictionary = world.get("vehicle", {}) if world.get("vehicle", {}) is Dictionary else {}
	if not vehicle.is_empty():
		if not valid_saved_point([vehicle.get("x"),vehicle.get("y")]):
			world.erase("vehicle") # Never instantiate a broken transform or duplicate the personal car.
			warnings.append("Posição antiga do veículo inválida: retomada a pé em segurança.")
		else:
			if not _valid_saved_number(vehicle.get("rotation",0)): vehicle.rotation = 0.0
			var values: Dictionary = vehicle.get("values",{}) if vehicle.get("values",{}) is Dictionary else {}
			for field in values.keys():
				if values[field] is float and not is_finite(values[field]): values.erase(field)
	if world.has("exterior_return") and not valid_saved_point(world.exterior_return):
		if fallback.is_finite(): world.exterior_return = [fallback.x,fallback.y]
		else: world.erase("exterior_return")
		warnings.append("Retorno externo antigo inválido: saída recuperada na entrada da região.")
	return warnings

static func _valid_saved_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func valid_saved_point(value: Variant) -> bool:
	if not value is Array or value.size() < 2: return false
	if not _valid_saved_number(value[0]) or not _valid_saved_number(value[1]): return false
	return preload("res://VehicleMotionSafety.gd").valid_position(Vector2(float(value[0]),float(value[1])))
