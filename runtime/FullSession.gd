extends Node
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const WEAPONS := preload("res://gameplay/WeaponCatalog.gd")
const MISSIONS := preload("res://data/campaign/HarborMissions.gd")
const V1_DEATH_AUDIO := preload("res://audio/V1DeathAudio.gd")
const REWARD_AUDIO := preload("res://gameplay/RewardAudio.gd")
const WORKPLACE_REACTION := preload("res://gameplay/civilian_reactions/WorkplaceThreatReaction.gd")
var world
var controller
var weather
var state
var room: Node3D
var room_npc: CharacterBody3D
var room_npcs: Array[CharacterBody3D] = []
var static_service_actor: Node3D
var anchor: Node3D
var objective: Label
var freight_active := false
var freight_target := Vector3.INF
var _restoring_saved_driver := false
var stats: Label
var thermal_status: Label
var prompt: Label
var notice: Label
var marker: Node2D
var arrow: Label
var panel: PanelContainer
var column: VBoxContainer
var modal := false
var _service_menu_open := false
var menu_closed := Callable()
var dialogue_open := false
var lines: Array = []
var dialogue_done := Callable()
var access_id := ""
var return_point := Vector3.ZERO
var saved_heading := 0.0
var saved_size := 28.0
var notice_time := 0.0
var _reward_failures: Dictionary = {}
var _reward_notice_id := ""
var tick := 0.0
var ready_for_play := false
var mission_world
var activities
var motocross
var services
var storefronts
var robberies
var arrival
var garage_rewards
var police_motor_pool
var personal_car
var residence_services
var mountain_progression
var cold
var passenger_transport
var urban_operations
var port_container_loot
var field_inventory
var action_serial := 0
var rebinding_action := ""
var vehicle_transition_busy := false
var rescue_pending := false
var arrest_pending := false
var respawn_busy := false
var transition_generation := 0
var transition_kind := ""
var rescue_camera_heading := 0.0
var rescue_camera_size := 28.0
var death_presentation: CanvasLayer
var sewer_hatch: Node3D
var sewer_entry_origin := Vector3.ZERO
var weapon_shop_entrance: Node
var special_place_entrance: Node
var last_save_error := ""
var _checkpoint_retry: Timer

func _uses_walkup_access(id: String) -> bool:
	return (weapon_shop_entrance != null and weapon_shop_entrance.handles_place(id)) or (special_place_entrance != null and special_place_entrance.handles_place(id))

func _arrival_sequence_blocked() -> bool:
	return arrival != null and (arrival.controls_locked or arrival.phase == "opening")

func is_transition_blocked() -> bool:
	return not transition_kind.is_empty() or vehicle_transition_busy or rescue_pending or arrest_pending or respawn_busy or (controller != null and controller.travel_busy) or _arrival_sequence_blocked()

func blocks_driving_change() -> bool:
	return is_transition_blocked() or not ready_for_play or (motocross != null and motocross.mounted)

func allows_saved_driver_animation() -> bool:
	return _restoring_saved_driver and not ready_for_play and not modal and not is_transition_blocked()

func _begin_transition(kind: String, _vehicle := false) -> int:
	if not transition_kind.is_empty() or (controller != null and controller.travel_busy): return -1
	transition_generation += 1
	transition_kind = kind
	# Legacy consumers already treat this public flag as the session transition
	# gate. Keep it asserted for every generation, not only vehicle transfers.
	vehicle_transition_busy = true
	return transition_generation

func _owns_transition(token: int) -> bool:
	return token > 0 and token == transition_generation and not transition_kind.is_empty()

func _finish_transition(token: int) -> void:
	if not _owns_transition(token): return
	transition_kind = ""
	vehicle_transition_busy = false

func _routine_director():
	return world.get_node_or_null("V1RoutineDirector") if world != null else null

func _refresh_routine_context() -> void:
	var routines = _routine_director()
	if routines != null: routines.refresh_context()
	if urban_operations != null: urban_operations.refresh_context()

func _sync_location_presentation() -> void:
	if is_instance_valid(weather): weather._update()
	prompt.text = ""
	world.gameplay._update_visual()
	var city_look := world.get_node_or_null("CityLook") as Node
	if city_look != null: city_look._refresh_silhouette()
	if world.hud.has_method("refresh_from_state"): world.hud.refresh_from_state()

func _vehicle_transition_snapshot(car: CharacterBody3D) -> Dictionary:
	return {
		"occupied": world.driving.occupied,
		"driving_car": world.driving.car,
		"car_locked": car.input_locked,
		"car_controlled": car.controlled,
		"car_external_input": car.external_input,
		"player_locked": world.player.input_locked,
		"player_visible": world.player.visible,
		"player_physics": world.player.is_physics_processing(),
		"player_layer": world.player.collision_layer,
		"player_mask": world.player.collision_mask,
		"camera_target": world.camera.target,
		"camera_offset": world.camera.offset,
		"camera_heading": world.camera.heading,
		"camera_target_size": world.camera.target_size,
		"camera_size": world.camera.size,
		"camera_locked": world.camera.locked,
	}

func _restore_vehicle_transition_snapshot(snapshot: Dictionary, car: CharacterBody3D) -> void:
	if is_instance_valid(car):
		car.input_locked = bool(snapshot.car_locked)
		car.controlled = bool(snapshot.car_controlled)
		car.external_input = bool(snapshot.car_external_input)
	world.driving.occupied = bool(snapshot.occupied)
	world.driving.car = snapshot.driving_car if is_instance_valid(snapshot.driving_car) else car
	world.player.input_locked = bool(snapshot.player_locked)
	world.player.visible = bool(snapshot.player_visible)
	world.player.set_physics_process(bool(snapshot.player_physics))
	world.player.collision_layer = int(snapshot.player_layer)
	world.player.collision_mask = int(snapshot.player_mask)
	if is_instance_valid(snapshot.camera_target): world.camera.target = snapshot.camera_target
	world.camera.offset = snapshot.camera_offset
	world.camera.heading = float(snapshot.camera_heading)
	world.camera.target_size = float(snapshot.camera_target_size)
	world.camera.size = float(snapshot.camera_size)
	world.camera.locked = bool(snapshot.camera_locked)
	world.camera.initialized = false

func _discard_place_candidate(candidate: Node3D, owned: bool) -> void:
	if not is_instance_valid(candidate): return
	if candidate == world.maciota_place: candidate.set_interior_active(false)
	elif owned: candidate.queue_free()

func _garage_transfer_valid(token: int, car: CharacterBody3D, place_id: String, entering: bool, expected_room: Node3D) -> bool:
	if not _owns_transition(token) or not is_instance_valid(car) or car.health <= 0 or world.gameplay.health <= 0: return false
	if not world.driving.occupied or world.driving.car != car or room != expected_room: return false
	if car.get("engine_disabled") == true: return false
	return state.place_id.is_empty() if entering else state.place_id == place_id

func transfer_garage_vehicle(place_id: String, car: CharacterBody3D, entering: bool) -> bool:
	if is_transition_blocked() or not is_instance_valid(car) or car.health<=0 or absf(car.speed)>.5: return false
	if not world.driving.occupied or world.driving.car != car: return false
	if entering and (not state.place_id.is_empty() or is_instance_valid(room)): return false
	if not entering and state.place_id != place_id: return false
	var definition: Dictionary = PLACES.get_definition(place_id)
	if place_id == "maciota":
		if state.region_id != "harbor": return false
	elif definition.is_empty() or definition.get("region","") != state.region_id or not definition.has("vehicle_spawn"):
		return false
	var token := _begin_transition("garage_vehicle",true)
	if token < 0: return false
	var snapshot := _vehicle_transition_snapshot(car)
	var expected_room: Node3D = room
	car.input_locked = true
	world.player.input_locked = true
	car.speed = 0
	car.horizontal_velocity = Vector3.ZERO
	var destination: Vector3
	var yaw := 0.0
	var next_room: Node3D = null
	var owns_next_room := false
	if entering:
		if place_id == "maciota":
			next_room = world.maciota_place
			next_room.set_interior_active(true)
			destination = next_room.interior_origin+Vector3(0,.1,1)
		else:
			next_room = PLACES.create_place(place_id)
			if next_room == null:
				_restore_vehicle_transition_snapshot(snapshot,car)
				_finish_transition(token)
				return false
			owns_next_room = true
			next_room.position = Vector3(0,0,-2400)
			world.add_child(next_room)
			destination = next_room.to_global(definition.vehicle_spawn)+Vector3.UP*.08
	else:
		destination = world.maciota_place.exterior_return+Vector3(0,.1,2) if place_id == "maciota" else definition.vehicle_return+Vector3.UP*.08
		yaw = 0.0 if place_id == "maciota" else float(definition.get("vehicle_return_yaw",0))
		controller.region.set_focus(destination)
	for i in 3:
		await get_tree().physics_frame
		if not _garage_transfer_valid(token,car,place_id,entering,expected_room):
			_discard_place_candidate(next_room,owns_next_room)
			controller.region.set_focus(car.global_position if is_instance_valid(car) else world.player.global_position)
			_restore_vehicle_transition_snapshot(snapshot,car)
			_finish_transition(token)
			return false
	if not controller.vehicle_position_clear(car,destination,yaw):
		_discard_place_candidate(next_room,owns_next_room)
		controller.region.set_focus(car.global_position)
		_restore_vehicle_transition_snapshot(snapshot,car)
		_finish_transition(token)
		show_message("Passagem do veículo ocupada. Aguarde espaço livre.")
		return false
	if entering:
		saved_heading = world.camera.heading
		saved_size = world.camera.target_size
		room = next_room
		return_point = room.exterior_return if place_id == "maciota" else definition.return_position
		state.set_location(state.region_id,place_id)
		state.checkpoint_id = place_id
		anchor.position = room.camera_target
		world.camera.target = anchor
		world.camera.offset = Vector3(0,18,15)
		world.camera.heading = 0
		world.camera.target_size = room.camera_size
		world.camera.size = room.camera_size
		world.camera.locked = true
	else:
		_clear_service_npcs()
		if room == world.maciota_place: room.set_interior_active(false)
		else: room.queue_free()
		room = null
		state.set_location(state.region_id)
		world.camera.target = car
		world.camera.offset = world.camera.EXTERIOR_OFFSET
		world.camera.heading = saved_heading
		world.camera.target_size = saved_size
		world.camera.locked = false
	car.set_meta("garage_place",place_id if entering else "")
	car.set_meta("region_id",state.region_id)
	car.place(destination,yaw)
	world.player.teleport(destination)
	_sync_location_presentation()
	world.camera.initialized = false
	world.camera._process(1)
	car.input_locked = bool(snapshot.car_locked)
	world.player.input_locked = bool(snapshot.player_locked)
	_finish_transition(token)
	arrival.on_location_changed()
	_refresh_routine_context()
	sync_dispatch_location()
	return true

func restore_garage_driver(car: CharacterBody3D) -> bool:
	if is_transition_blocked() or not is_instance_valid(car) or car.health<=0 or world.driving.occupied: return false
	var place: String = state.place_id
	if place not in ["","maciota","port_boss_garage"] or car.get_meta("garage_place","") != place: return false
	if car.get_meta("region_id",state.region_id) != state.region_id or car.get("engine_disabled") == true: return false
	if place == "maciota" and state.region_id != "harbor": return false
	var definition := PLACES.get_definition(place)
	if not place.is_empty() and place != "maciota" and (definition.is_empty() or definition.get("region","") != state.region_id): return false
	var token := _begin_transition("restore_garage_driver",true)
	if token < 0: return false
	var snapshot := _vehicle_transition_snapshot(car)
	var expected_room: Node3D = room
	car.input_locked = true
	for i in 3:
		await get_tree().physics_frame
		if not _owns_transition(token) or not is_instance_valid(car) or state.place_id != place or room != expected_room or world.driving.occupied or modal or world.gameplay.health <= 0:
			_restore_vehicle_transition_snapshot(snapshot,car)
			_finish_transition(token)
			return false
	if car.health<=0 or not car.is_visible_in_tree() or car.collision_layer == 0 or not controller.vehicle_position_clear(car,car.position,car.rotation.y):
		_restore_vehicle_transition_snapshot(snapshot,car)
		_finish_transition(token)
		return false
	var checkpoint: Vector3 = world.player.position
	var previous_car: CharacterBody3D = world.driving.car
	var capsule := CapsuleShape3D.new()
	capsule.radius = .32
	capsule.height = 1.7
	for side in [-1,1]:
		var point := car.to_global(Vector3(side*(car.half_width+.65),.05,.15))
		# Long cabins sit beyond the reach of the generic car-side anchor.
		if car.boarding_class() in ["truck", "bus"]:
			point = car.driver_door_anchor(side) + car.global_basis.x * float(side) * .11 + Vector3.UP * .01
		if not position_clear(point): continue
		# Restoring a seated save may relocate the actor to a door only through
		# a continuous clear walking corridor, never across a car or furniture.
		var paths: Array[PackedVector3Array] = [PackedVector3Array([point])]
		var routed: PackedVector3Array = world.gameplay.find_path(checkpoint,point)
		if not routed.is_empty():
			routed.append(point)
			paths.append(routed)
		var reachable := false
		for path in paths:
			var from := checkpoint
			var clear := true
			for destination in path:
				if not position_clear(destination): clear = false; break
				var query := PhysicsShapeQueryParameters3D.new()
				query.shape = capsule
				query.collision_mask = 7
				query.exclude = [world.player.get_rid()]
				query.transform = Transform3D(Basis.IDENTITY,from+Vector3.UP*.9)
				query.motion = destination-from
				var sweep: PackedFloat32Array = world.get_world_3d().direct_space_state.cast_motion(query)
				if sweep[0] < 1.0: clear = false; break
				var steps := maxi(1,ceili(from.distance_to(destination)/.5))
				for step in range(1,steps):
					if not position_clear(from.lerp(destination,float(step)/steps)): clear = false; break
				if not clear: break
				from = destination
			if clear: reachable = true; break
		if not reachable: continue
		world.player.teleport(point)
		var entry: Dictionary = world.driving._entry_option(true)
		# Driving.car still names the previous controlled vehicle until the entry
		# actually begins. Validate the physically selected candidate instead.
		if entry.get("car") == car and world.driving.interact(true):
			world.camera.target = car if place.is_empty() else anchor
			world.camera.locked = not place.is_empty()
			state.set_location(state.region_id,place)
			_sync_location_presentation()
			# Release only the session gate while the existing body/door presentation
			# owns input. Otherwise Driving sees our gate as an interruption and aborts
			# the entry on its first frame.
			_finish_transition(token)
			for frame in 180:
				if not world.driving.is_body_transition_active(): break
				await get_tree().physics_frame
				if not is_instance_valid(car) or car.health <= 0 or state.place_id != place or room != expected_room or world.gameplay.health <= 0:
					world.driving.cancel_transition("garage_restore_invalidated")
					_restore_vehicle_transition_snapshot(snapshot,car if is_instance_valid(car) else null)
					return false
			if world.driving.is_body_transition_active():
				world.driving.cancel_transition("garage_restore_timeout")
				_restore_vehicle_transition_snapshot(snapshot,car)
				return false
			if not world.driving.occupied or world.driving.car != car:
				_restore_vehicle_transition_snapshot(snapshot,car)
				return false
			car.input_locked = bool(snapshot.car_locked)
			return true
		world.player.teleport(checkpoint)
	world.player.teleport(checkpoint)
	world.driving.car = previous_car
	_restore_vehicle_transition_snapshot(snapshot,car)
	_finish_transition(token)
	return false

func _garage_restore_spawn(place: String, preferred: Vector3, candidate_room: Node3D = null) -> Vector3:
	if place not in ["maciota","port_boss_garage"] or garage_rewards == null: return preferred
	if candidate_room == null: candidate_room = room
	if not is_instance_valid(candidate_room): return Vector3.INF
	var records: Dictionary = garage_rewards.data.get("vehicles",{})
	if records.is_empty(): return preferred
	var origin: Vector3 = candidate_room.to_global(candidate_room.interior_origin) if place == "maciota" else candidate_room.global_position
	var reservations: Array[Dictionary] = []
	for record in records.values():
		if record.get("place_id","") != place or record.get("region_id","") != state.region_id: continue
		var specification: Dictionary = preload("res://runtime/FleetCatalog.gd").spec(str(record.archetype))
		if specification.is_empty(): continue
		var size: Array = specification.bounds_size
		var point := origin+Vector3(record.position[0],record.position[1],record.position[2])
		reservations.append({"point":point,"inverse":Basis(Vector3.UP,float(record.yaw)).inverse(),"half":Vector2(maxf(.65,size[0])*.5+.4,float(size[2])*.5+.4),"height":clampf(size[1],1.1,3.6)})
	if reservations.is_empty(): return preferred
	var candidates: Array[Vector3] = [preferred,candidate_room.exit_position]
	for center: Vector3 in [candidate_room.exit_position,preferred]:
		for radius in [1.2,2.4,3.6]:
			for offset in [Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3.BACK]: candidates.append(center+offset*radius)
	var bounds: Rect2
	if place == "maciota":
		bounds = Rect2(candidate_room.room_bounds.position.x,candidate_room.room_bounds.position.z,candidate_room.room_bounds.size.x,candidate_room.room_bounds.size.z)
	else:
		var size: Vector2 = candidate_room.definition.size
		bounds = Rect2(-size*.5,size)
	for candidate in candidates:
		var local := candidate-origin
		if not bounds.grow(-.34).has_point(Vector2(local.x,local.z)): continue
		if not position_clear(candidate+Vector3.UP*.04): continue
		var reserved := false
		for reservation in reservations:
			var relative: Vector3 = reservation.inverse*(candidate-reservation.point)
			if absf(relative.x) <= reservation.half.x and absf(relative.z) <= reservation.half.y and relative.y < reservation.height and relative.y+1.8 > 0:
				reserved = true
				break
		if not reserved: return candidate
	return Vector3.INF

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	state = controller.state
	weapon_shop_entrance = preload("res://runtime/WeaponShopEntrance.gd").new()
	weapon_shop_entrance.session = self
	add_child(weapon_shop_entrance)
	special_place_entrance = preload("res://runtime/SpecialPlaceEntrance.gd").new()
	special_place_entrance.session = self
	add_child(special_place_entrance)
	anchor = Node3D.new()
	world.add_child(anchor)
	objective = _label(Vector2(530,24),20)
	objective.custom_minimum_size.x = 700
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats = _label(Vector2(26,64),18)
	thermal_status = _label(Vector2(26,112),16)
	thermal_status.hide()
	prompt = _label(Vector2(26,590),20)
	notice = _label(Vector2(26,550),18)
	marker = preload("res://ui/DoorAccessMarker.gd").new()
	world.hud.add_child(marker)
	arrow = _label(Vector2.ZERO,30)
	arrow.text = "▲"
	arrow.modulate = Color("f39a38")
	arrow.pivot_offset = Vector2(12,20)
	# World-anchored HUD must follow the final camera every rendered frame,
	# not the 10 Hz text refresh (which made the orange marker jump).
	marker.update_position = _update_world_indicator
	panel = PanelContainer.new()
	panel.position = Vector2(330,110)
	panel.custom_minimum_size = Vector2(620,440)
	world.hud.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["top","left","right","bottom"]: margin.add_theme_constant_override("margin_"+side,20)
	panel.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(580,400)
	margin.add_child(scroll)
	column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",10)
	scroll.add_child(column)
	panel.hide()
	world.gameplay.message.connect(show_message)
	world.gameplay.player_died.connect(_on_death)
	world.gameplay.player_arrested.connect(_on_arrest)
	world.gameplay.police_warning_issued.connect(func(): show_message("POLÍCIA: Pare e fique imóvel para se render!"))
	mission_world = preload("res://runtime/MissionWorld.gd").new()
	mission_world.session = self
	world.add_child(mission_world)
	activities = preload("res://activities/Activities.gd").new()
	world.add_child(activities)
	activities.configure(self)
	motocross = preload("res://activities/motocross/Motocross.gd").new()
	world.add_child(motocross)
	motocross.configure(self)
	residence_services = preload("res://runtime/ResidenceServices.gd").new()
	residence_services.configure(self)
	mountain_progression = preload("res://activities/MountainProgression.gd").new()
	world.add_child(mountain_progression)
	mountain_progression.configure(self)
	world.player.ski_controller = mountain_progression
	services = preload("res://runtime/Services.gd").new()
	world.add_child(services)
	services.configure(self)
	if state.world_state.has("services") and not services.restore_snapshot(state.world_state.services): controller.save_invalid = true
	storefronts = preload("res://runtime/HarborStorefronts.gd").new()
	world.hud.add_child(storefronts)
	storefronts.configure(self)
	robberies = preload("res://runtime/Robberies.gd").new()
	if state.world_state.has("robberies") and not robberies.restore_snapshot(state.world_state.robberies): controller.save_invalid = true
	world.add_child(robberies)
	robberies.configure(self)
	arrival = preload("res://runtime/Arrival.gd").new()
	arrival.configure(self)
	if state.world_state.has("arrival") and not arrival.restore_state(state.world_state.arrival): controller.save_invalid = true
	world.add_child(arrival)
	arrival.changed.connect(save_game)
	garage_rewards = preload("res://runtime/GarageRewards.gd").new()
	if state.world_state.has("garage_rewards") and not garage_rewards.restore_snapshot(state.world_state.garage_rewards): controller.save_invalid = true
	world.add_child(garage_rewards)
	garage_rewards.configure(self)
	police_motor_pool = preload("res://runtime/PoliceMotorPool.gd").new()
	world.add_child(police_motor_pool)
	police_motor_pool.configure(self)
	personal_car = preload("res://runtime/PersonalCar.gd").new()
	world.add_child(personal_car)
	personal_car.configure(self)
	passenger_transport = preload("res://runtime/PassengerTransport.gd").new()
	passenger_transport.configure(self)
	world.add_child(passenger_transport)
	urban_operations = preload("res://gameplay/urban_v1/UrbanOperations.gd").new()
	urban_operations.configure(self)
	world.add_child(urban_operations)
	if state.world_state.has("urban_operations") and not urban_operations.restore_snapshot(state.world_state.urban_operations): controller.save_invalid = true
	port_container_loot = preload("res://gameplay/urban_v1/PortContainerLoot.gd").new()
	port_container_loot.configure(self)
	world.add_child(port_container_loot)
	field_inventory = preload("res://systems/inventory/FieldInventoryRuntime.gd").new()
	world.add_child(field_inventory)
	field_inventory.configure(self)
	if not world.get_meta("skip_cold",false):
		cold = preload("res://runtime/ColdSurvival.gd").new()
		cold.configure(self)
		if state.world_state.has("cold") and not cold.restore(state.world_state.cold): controller.save_invalid = true
		world.add_child(cold)

func _label(point: Vector2,size_value: int) -> Label:
	var result := Label.new()
	result.position = point
	result.add_theme_font_size_override("font_size",size_value)
	result.add_theme_color_override("font_shadow_color",Color.BLACK)
	result.add_theme_constant_override("shadow_offset_y",2)
	world.hud.add_child(result)
	return result

func show_message(text: String) -> void:
	if not is_instance_valid(notice): return
	_reward_notice_id = ""
	notice.text = text
	notice_time = 5.0
	notice.show()
	notice.move_to_front()

func position_clear(point: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = .32
	shape.height = 1.7
	query.shape = shape
	query.collision_mask = 7
	query.transform = Transform3D(Basis.IDENTITY,point+Vector3.UP*.9)
	query.exclude = [world.player.get_rid()]
	if not world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return false
	var ground := PhysicsRayQueryParameters3D.create(point+Vector3.UP*.3,point-Vector3.UP*.5,1)
	return not world.get_world_3d().direct_space_state.intersect_ray(ground).is_empty()

func restore_location() -> void:
	var restore_blocked := false
	var place: String = state.place_id
	state.place_id = ""
	var definition := PLACES.get_definition(place)
	var place_matches_region: bool = place == "maciota" and state.region_id == "harbor"
	if not definition.is_empty(): place_matches_region = definition.get("region","") == state.region_id
	if place_matches_region:
		if not await enter_place(place,false): restore_blocked = true
	else:
		if not place.is_empty():
			controller.save_invalid = true
			show_message("Local salvo incompatível com a região; arquivo original preservado.")
		var point: Vector3 = world.maciota_place.exterior_return if state.region_id == "harbor" else controller.region.spawn_position
		for entry in controller.region.entries:
			if entry.id == state.checkpoint_id: point = entry.return_position
		var fallback: Vector3 = point
		var pedestrian: Dictionary = state.world_state.get("pedestrian",{})
		if pedestrian.get("region","") == state.region_id:
			var coordinates: Array = pedestrian.position
			point = Vector3(coordinates[0],coordinates[1],coordinates[2])-Vector3.UP*.08
		var seated: Dictionary = _saved_garage_driver()
		if not seated.is_empty():
			var size: Array = preload("res://runtime/FleetCatalog.gd").spec(seated.archetype).bounds_size
			var parked := Vector3(seated.position[0],seated.position[1],seated.position[2])
			point = parked+Basis(Vector3.UP,float(seated.yaw))*Vector3(maxf(.65,float(size[0]))*.5+.65,0,.15)
		controller.region.set_focus(point)
		if cold != null: cold.prepare_collision_at(point)
		for i in 3: await get_tree().physics_frame
		if position_clear(point+Vector3.UP*.08): world.player.teleport(point+Vector3.UP*.08)
		else:
			controller.region.set_focus(fallback)
			if cold != null: cold.prepare_collision_at(fallback)
			for i in 3: await get_tree().physics_frame
			if position_clear(fallback+Vector3.UP*.08):
				world.player.teleport(fallback+Vector3.UP*.08)
				show_message("Local salvo ocupado. Retomada pelo ponto de retorno.")
			else: restore_blocked = true
	if not state.combat_state.is_empty(): world.gameplay.restore_state(state.combat_state)
	if state.world_state.has("mission_world"):
		if not mission_world.restore_snapshot(state.world_state.mission_world):
			controller.save_invalid = true
			show_message("Não foi possível restaurar o guincho; save preservado.")
	elif state.campaign.active_id == "cobra_contact":
		mission_world.begin_tow_job({"story":true,"kind":"local"})
	await _restore_outdoor_driver()
	ready_for_play = true
	if personal_car != null: personal_car.refresh()
	if activities != null: activities.refresh_achievements()
	garage_rewards.on_location_changed()
	apply_outfit()
	_refresh_routine_context()
	if world.gameplay.health <= 0 or restore_blocked: _on_death()

func _saved_garage_driver() -> Dictionary:
	if garage_rewards == null or not state.place_id.is_empty(): return {}
	for record in garage_rewards.data.get("vehicles",{}).values():
		if record.get("was_driven",false) and record.region_id == state.region_id and record.place_id.is_empty(): return record
	return {}

func _restore_outdoor_driver() -> void:
	# A seated save resumes at the saved car, not at a remote pedestrian checkpoint.
	if not state.place_id.is_empty() or world.gameplay.health <= 0: return
	var saved: Dictionary = controller.starting_vehicle()
	if saved.is_empty() or not saved.get("was_driven",false) or saved.region != state.region_id: return
	var car: CharacterBody3D = world.driving.car
	var destination := Vector3(saved.position[0],saved.position[1],saved.position[2])
	var checkpoint: Vector3 = world.player.position
	controller.region.set_focus(destination)
	if cold != null: cold.prepare_collision_at(destination)
	for i in 3: await get_tree().physics_frame
	if not controller.vehicle_position_clear(car,destination,float(saved.yaw)):
		controller.region.set_focus(checkpoint)
		return
	car.place(destination,float(saved.yaw))
	car.remove_meta("awaiting_ground")
	car.set_physics_process(true)
	for side in [-1,1]:
		var door := car.to_global(Vector3(side*(car.half_width+.65),.05,.15))
		if car.boarding_class() in ["truck", "bus"]:
			door = car.driver_door_anchor(side) + car.global_basis.x * float(side) * .11 + Vector3.UP * .01
		if not position_clear(door): continue
		world.player.teleport(door)
		# The saved driver is admitted before ready_for_play. Keep normal input
		# gated, but allow its already-owned body animation to finish under the curtain.
		_restoring_saved_driver = true
		var restored := await restore_garage_driver(car)
		_restoring_saved_driver = false
		if restored: return
	world.player.teleport(checkpoint)
	controller.region.set_focus(checkpoint)

func enter_place(id: String, autosave := true, requested_access_id := "") -> bool:
	if is_transition_blocked() or world.driving.occupied or not state.place_id.is_empty() or is_instance_valid(room) or world.player.input_locked: return false
	var definition := PLACES.get_definition(id)
	if id == "maciota":
		if state.region_id != "harbor": return false
	elif definition.is_empty() or (definition.get("region","") != state.region_id and not definition.get("any_region",false)):
		show_message("Este acesso não pertence à região atual.")
		return false
	if autosave and garage_rewards != null and not garage_rewards.can_enter(id):
		show_message("A garagem abre entre 1h e 5h.")
		return false
	if id == "harbor_bank" and not robberies.can_enter_bank():
		show_message("O banco está fechado para investigação.")
		return false
	if activities != null and not activities.can_enter_home(id):
		show_message("Esta casa ainda não é sua.")
		return false
	var token := _begin_transition("enter_place")
	if token < 0: return false
	var origin_region: String = state.region_id
	var origin_room: Node3D = room
	var was_player_locked: bool = world.player.input_locked
	var local_access_id: String = requested_access_id
	world.player.input_locked = true
	var destination: Vector3
	var candidate_room: Node3D
	var owns_candidate := false
	var candidate_return := Vector3.ZERO
	if id == "harbor_sewer":
		sewer_hatch = _find_sewer_hatch()
		sewer_entry_origin = world.player.global_position
	if id == "maciota":
		candidate_room = world.maciota_place
		candidate_return = candidate_room.exterior_return
		destination = candidate_room.interior_spawn
		candidate_room.set_interior_active(true)
	else:
		candidate_room = PLACES.create_place(id)
		if candidate_room == null:
			if id == "harbor_sewer" and sewer_entry_origin.is_finite():
				world.player.teleport(sewer_entry_origin)
				await _animate_sewer_hatch(0.0, token)
				sewer_entry_origin = Vector3.ZERO
			world.player.input_locked = was_player_locked
			_finish_transition(token)
			return false
		owns_candidate = true
		candidate_room.position = Vector3(0,0,-2400)
		world.add_child(candidate_room)
		candidate_return = candidate_room.definition.return_position
		for entry in controller.region.entries:
			if entry.id == local_access_id: candidate_return = entry.return_position
		destination = candidate_room.spawn_position
	controller.region.set_focus(candidate_return)
	for i in 2:
		await get_tree().physics_frame
		if not _owns_transition(token) or state.region_id != origin_region or not state.place_id.is_empty() or room != origin_room or world.driving.occupied or world.gameplay.health <= 0 or not is_instance_valid(candidate_room):
			_discard_place_candidate(candidate_room,owns_candidate)
			controller.region.set_focus(world.player.global_position)
			if id == "harbor_sewer" and sewer_entry_origin.is_finite():
				world.player.teleport(sewer_entry_origin)
				await _animate_sewer_hatch(0.0, token)
				sewer_entry_origin = Vector3.ZERO
			world.player.input_locked = was_player_locked
			_finish_transition(token)
			return false
	destination = _garage_restore_spawn(id,destination,candidate_room)
	if not destination.is_finite() or not position_clear(destination+Vector3.UP*.04):
		_discard_place_candidate(candidate_room,owns_candidate)
		controller.region.set_focus(world.player.global_position)
		if id == "harbor_sewer" and sewer_entry_origin.is_finite():
			world.player.teleport(sewer_entry_origin)
			await _animate_sewer_hatch(0.0, token)
		world.player.input_locked = was_player_locked
		_finish_transition(token)
		show_message("Entrada bloqueada.")
		return false
	saved_heading = world.camera.heading
	saved_size = world.camera.target_size
	room = candidate_room
	return_point = candidate_return
	access_id = local_access_id
	state.set_location(state.region_id,id)
	state.checkpoint_id = local_access_id if not local_access_id.is_empty() else id
	world.player.teleport(destination+Vector3.UP*.04)
	_sync_location_presentation()
	anchor.position = room.camera_target
	if _uses_walkup_access(id): world.camera.clear_store_focus()
	world.camera.target = anchor
	world.camera.offset = Vector3(0,18,15)
	world.camera.heading = 0
	world.camera.target_size = room.camera_size
	world.camera.size = room.camera_size
	world.camera.locked = true
	world.camera.initialized = false
	world.camera._process(1)
	if id == "harbor_sewer" and is_instance_valid(sewer_hatch):
		await _animate_sewer_hatch(0.0, token)
		sewer_hatch = null
		sewer_entry_origin = Vector3.ZERO
	world.player.input_locked = was_player_locked
	if id != "maciota":
		_install_service_npc()
		_update_reward()
	if room.has_method("on_session_entered"): room.on_session_entered(self)
	_finish_transition(token)
	arrival.on_location_changed()
	garage_rewards.on_location_changed()
	_refresh_routine_context()
	sync_dispatch_location()
	if autosave: save_game()
	return true

func leave_place() -> bool:
	if is_transition_blocked() or state.place_id.is_empty() or not is_instance_valid(room): return false
	var token := _begin_transition("leave_place")
	if token < 0: return false
	var leaving_room: Node3D = room
	var was_player_locked: bool = world.player.input_locked
	if state.place_id == "harbor_sewer":
		sewer_hatch = _find_sewer_hatch()
		if is_instance_valid(sewer_hatch):
			world.player.input_locked = true
			sewer_hatch.set_open_amount(0.0)
	var leaving_return := _clear_return_point(state.place_id, return_point)
	world.player.input_locked = true
	if not leaving_return.is_finite():
		if is_instance_valid(sewer_hatch):
			sewer_hatch.set_open_amount(0.0)
			sewer_hatch = null
		world.player.input_locked = was_player_locked
		_finish_transition(token)
		show_message("Passagem ocupada. Aguarde.")
		return false
	controller.region.set_focus(leaving_return)
	if leaving_room == world.maciota_place: leaving_room.set_interior_active(false)
	else: leaving_room.queue_free()
	_clear_service_npcs()
	room = null
	state.set_location(state.region_id)
	world.player.teleport(leaving_return+Vector3.UP*.08)
	_sync_location_presentation()
	if state.place_id.is_empty() and is_instance_valid(sewer_hatch):
		_close_sewer_hatch_after_exit(sewer_hatch)
		sewer_hatch = null
	world.camera.target = world.player
	world.camera.offset = world.camera.EXTERIOR_OFFSET
	world.camera.heading = saved_heading
	world.camera.target_size = saved_size
	world.camera.locked = false
	world.camera.initialized = false
	world.camera._process(1)
	world.player.input_locked = was_player_locked
	_finish_transition(token)
	close_menu()
	arrival.on_location_changed()
	garage_rewards.on_location_changed()
	_refresh_routine_context()
	sync_dispatch_location()
	save_game()
	return true

func _find_sewer_hatch() -> Node3D:
	if controller == null or controller.region == null: return null
	var target := Vector2(1182.0, 2114.0) / 16.0
	var best: Node3D
	var best_distance := 2.0
	for chunk in controller.region.get_children():
		for node in chunk.find_children("harbor_sewer", "Node3D", true, false):
			var distance := Vector2(node.global_position.x, node.global_position.z).distance_to(target)
			if distance < best_distance:
				best_distance = distance
				best = node
	return best

func _animate_sewer_hatch(amount: float, token: int) -> void:
	if not is_instance_valid(sewer_hatch) or not sewer_hatch.has_method("set_open_amount"): return
	if _owns_transition(token): sewer_hatch.set_open_amount(0.0)

func _close_sewer_hatch_after_exit(hatch: Node3D) -> void:
	if is_instance_valid(hatch): hatch.set_open_amount(0.0)


func _clear_return_point(place_id: String, desired: Vector3) -> Vector3:
	# Keep the authored V1 return first. A streamed pedestrian or a facade edge
	# must not trap the player inside forever, so test a few small points farther
	# along the same exterior approach before refusing the transition.
	if position_clear(desired + Vector3.UP * .08): return desired
	var outward := Vector3.FORWARD
	if place_id == "maciota":
		outward = desired - world.maciota_place.entry_position
	else:
		var definition: Dictionary = PLACES.get_definition(place_id)
		if weapon_shop_entrance != null and weapon_shop_entrance.handles_place(access_id):
			definition = weapon_shop_entrance._definition_for(access_id)
		if not definition.is_empty(): outward = desired - definition.exterior_position
	outward.y = 0
	if outward.length_squared() < .01: outward = Vector3.FORWARD
	outward = outward.normalized()
	var side := Vector3(-outward.z, 0, outward.x)
	for offset in [outward * .75, outward * 1.5, side * .8 + outward * .75, -side * .8 + outward * .75]:
		var candidate: Vector3 = desired + offset
		if position_clear(candidate + Vector3.UP * .08): return candidate
	return Vector3.INF

func sync_dispatch_location() -> void:
	if is_instance_valid(world.dispatch):
		world.dispatch.player_position_override = return_point if not state.place_id.is_empty() else Vector3.INF

func _install_service_npc() -> void:
	# Vance is authored into the room's 3D art, rather than the NPC catalog.
	static_service_actor = room.find_child("VanceMilitaryGunsmith", true, false) as Node3D
	if is_instance_valid(static_service_actor): _install_workplace_reaction(static_service_actor, static_service_actor)
	var residents: Array = room.definition.get("npcs",[])
	if not residents.is_empty():
		for definition in residents:
			var point: Vector3 = room.to_global(definition.local_position)+Vector3.UP*.04
			if not position_clear(point):
				push_error("Interior NPC position blocked: "+str(definition.id))
				continue
			var actor = preload("res://scripts/Actor.gd").new()
			actor.controlled_automatically = true
			actor.position = point
			actor.set_meta("interior_npc_id",definition.id)
			# Story and service residents must survive every combat damage path.
			if state.place_id == "harbor_police": actor.set_meta("invulnerable",true)
			world.add_child(actor)
			var original: Node = actor.visual.get_child(0)
			actor.visual.remove_child(original)
			original.queue_free()
			var model: Node3D = preload("res://world/places/OriginalResidents.gd").create_model(definition)
			actor.visual.add_child(model)
			room_npcs.append(actor)
			_install_workplace_reaction(actor, model)
		room_npc = room_npcs[0] if not room_npcs.is_empty() else null
		return
	if str(room.definition.get("npc_model","")).is_empty(): return
	var model_resource = load(room.definition.npc_model)
	if model_resource == null: return
	room_npc = preload("res://scripts/Actor.gd").new()
	room_npc.controlled_automatically = true
	room_npc.position = room.to_global(room.definition.get("npc_point",Vector3(0,0,-2)))
	world.add_child(room_npc)
	var old_model: Node = room_npc.visual.get_child(0)
	room_npc.visual.remove_child(old_model)
	old_model.queue_free()
	var model: Node3D = model_resource.instantiate() if model_resource is PackedScene else model_resource.new()
	room_npc.visual.add_child(model)
	room_npc.visual.rotation.y = PI
	room_npcs.append(room_npc)
	_install_workplace_reaction(room_npc, model)

func _install_workplace_reaction(actor: Node3D, model: Node3D) -> void:
	var reaction: Node = WORKPLACE_REACTION.install(actor, model, world.gameplay)
	if reaction != null and not reaction.threat_started.is_connected(_on_workplace_threat_started):
		reaction.threat_started.connect(_on_workplace_threat_started)

func _service_threatened(npc_id := "") -> bool:
	if npc_id.is_empty() and is_instance_valid(static_service_actor) and static_service_actor.get_meta("workplace_threatened", false): return true
	for actor in room_npcs:
		if not is_instance_valid(actor) or not actor.is_visible_in_tree(): continue
		if not npc_id.is_empty() and str(actor.get_meta("interior_npc_id", "")) != npc_id: continue
		if actor.get_meta("workplace_threatened", false): return true
	# Robberies replace the generic bank/fuel resident with their physical actors.
	if npc_id.is_empty() and robberies != null:
		for actor in robberies._actors:
			if is_instance_valid(actor) and not actor.guard and actor.get_meta("workplace_threatened", false): return true
	return false

func _on_workplace_threat_started(actor: Node3D) -> void:
	var local_staff: bool = actor == static_service_actor or room_npcs.has(actor) or (robberies != null and robberies._actors.has(actor))
	if not local_staff: return
	if _service_menu_open or (storefronts != null and storefronts.is_open()):
		lines.clear()
		dialogue_done = Callable()
		close_menu()
	prompt.text = ""

func _clear_service_npcs() -> void:
	static_service_actor = null
	for actor in room_npcs:
		if is_instance_valid(actor): actor.queue_free()
	room_npcs.clear()
	room_npc = null

func nearest() -> Dictionary:
	if rescue_pending or arrest_pending or world.gameplay.health <= 0: return {}
	if field_inventory != null:
		var supply_action: Dictionary = field_inventory.nearest_action()
		if not supply_action.is_empty(): return supply_action
	if motocross != null:
		var mx_action: Dictionary = motocross.nearest_action()
		if not mx_action.is_empty(): return mx_action
	if port_container_loot != null:
		var cargo_action: Dictionary = port_container_loot.nearest_action()
		if not cargo_action.is_empty(): return cargo_action
	if passenger_transport != null and passenger_transport.riding: return passenger_transport.nearest_action()
	var arrival_action: Dictionary = arrival.nearest_action()
	if not arrival_action.is_empty(): return arrival_action
	if not world.driving.occupied and not state.place_id.is_empty() and is_instance_valid(room):
		if not _uses_walkup_access(state.place_id) and world.player.position.distance_to(room.exit_position) < 1.45: return {"id":"exit","label":"Sair"}
	var personal_action: Dictionary = personal_car.nearest_action()
	if not personal_action.is_empty(): return personal_action
	var residence_action: Dictionary = residence_services.nearest_action()
	if not residence_action.is_empty(): return residence_action
	var mountain_action: Dictionary = mountain_progression.nearest_action()
	if not mountain_action.is_empty(): return mountain_action
	var garage_action: Dictionary = garage_rewards.nearest_action()
	if not garage_action.is_empty(): return garage_action
	if world.driving.occupied:
		var vehicle_action: Dictionary = mission_world.nearest_vehicle_action()
		return vehicle_action if not vehicle_action.is_empty() else activities.nearest_action()
	var point: Vector3 = world.player.position
	if not state.place_id.is_empty():
		if not _uses_walkup_access(state.place_id) and point.distance_to(room.exit_position) < 1.45: return {"id":"exit","label":"Sair"}
		var robbery_action: Dictionary = robberies.nearest_action()
		if not robbery_action.is_empty(): return robbery_action
		var original_action: Dictionary = services.nearest_action()
		if not original_action.is_empty() and not _service_threatened(str(original_action.get("target", ""))): return original_action
		var urban_action: Dictionary = urban_operations.nearest_action() if urban_operations != null else {}
		if not urban_action.is_empty(): return urban_action
		var interior_routine_action: Dictionary = _routine_director().nearest_action() if _routine_director() != null else {}
		if not interior_routine_action.is_empty(): return interior_routine_action
		if state.place_id == "maciota":
			for id in ["maciota","mechanic","part"]:
				if id == "part" and state.intro.stage != "collect_part": continue
				if point.distance_to(room.interaction_points[id]) < 1.3: return {"id":id,"label":"Pegar peça" if id == "part" else "Conversar"}
		else:
			var service_point: Vector3 = room.interaction_points.service
			var service: String = str(room.definition.get("service",""))
			# Police, hospital and fire station publish their terminal/NPC/healing
			# actions through Services.nearest_action(). A second generic counter
			# produced a visible "Atender" prompt with no consumer or result.
			var primary_available := service in ["weapons","clothing"]
			if state.place_id == "harbor_bank": primary_available = state.campaign.target_id() == "helena"
			# A conveniência não tinha balcão de compras no V1: sua operação é o
			# caixa do assalto. Não exponha um "Atender" que não produz resultado.
			if primary_available and not _service_threatened() and point.distance_to(service_point) < 1.5:
				return {"id":"service","label":"Falar com Vance" if state.place_id in ["harbor_ammunation", "mountain_gunshop"] else "Atender"}
		return {}
	var activity_action: Dictionary = activities.nearest_action()
	if not activity_action.is_empty(): return activity_action
	var urban_action: Dictionary = urban_operations.nearest_action() if urban_operations != null else {}
	if not urban_action.is_empty(): return urban_action
	var outdoor_routine_action: Dictionary = _routine_director().nearest_action() if _routine_director() != null else {}
	if not outdoor_routine_action.is_empty(): return outdoor_routine_action
	if state.region_id == "harbor" and not _uses_walkup_access("maciota") and point.distance_to(world.maciota_place.entry_position) < 1.5: return {"id":"enter","place":"maciota","access":"maciota","label":"Entrar"}
	for entry in controller.region.entries:
		if entry.place_id == "harbor_sewer" and point.distance_to(entry.position) < 1.5:
			return {"id":"enter","place":entry.place_id,"access":entry.id,"label":"","silent":true}
		if _uses_walkup_access(entry.place_id): continue
		if point.distance_to(entry.position) < 1.5: return {"id":"enter","place":entry.place_id,"access":entry.id,"label":"Entrar"}
	var mission_action: Dictionary = mission_world.nearest_action()
	if not mission_action.is_empty(): return mission_action
	return passenger_transport.nearest_action()

func interact() -> bool:
	if modal or not ready_for_play: return false
	var action := nearest()
	if action.get("id","") == "motocross": return motocross.perform(str(action.target))
	if str(action.get("id","")).begins_with("ski_"): return mountain_progression.perform(action.target)
	if str(action.get("id","")).begins_with("arrival_"): return arrival.perform(action.id)
	match str(action.get("id","")):
		"field_inventory": return field_inventory.perform(str(action.target))
		"port_container": return port_container_loot.perform(str(action.target))
		"passenger_transport": return passenger_transport.perform(action.target)
		"residence_services": return residence_services.perform("residence_services")
		"personal_car": return personal_car.perform(action.target)
		"garage_reward": return garage_rewards.perform(action.target)
		"robbery": return robberies.perform(action.target)
		"original_service":
			if _service_threatened(str(action.target)): return false
			var performed: bool = services.perform(action.target)
			_service_menu_open = performed and modal and str(action.target) not in ["hospital_triage", "police_terminal", "fire_alarm"]
			return performed
		"urban_v1": return _perform_urban_action(str(action.target))
		"v1_routine":
			var routines = _routine_director()
			return routines != null and routines.perform(str(action.target))
		"exit": return leave_place()
		"enter":
			enter_place(action.place,true,str(action.access))
			return true
		"maciota":
			if state.intro.stage != "complete": return _intro_interact("maciota")
			if mission_world.perform("maciota"): return true
			show_journal()
			return true
		"mechanic":
			if state.intro.stage != "complete": return _intro_interact("mechanic")
			show_services("garage")
			return true
		"part": return _intro_interact("workbench")
		"service":
			if state.place_id == "harbor_bank" and mission_world.perform("helena"):
				_service_menu_open = modal
				return true
			show_services(room.definition.service)
			return true
	if activities.perform(str(action.get("target",""))): return true
	return mission_world.perform(str(action.get("target","")))

func _perform_urban_action(target: String) -> bool:
	if urban_operations == null: return false
	var quest = urban_operations.get("village_quest")
	if target == "truckers_village_tonico" and is_instance_valid(quest) and not quest.data.started:
		if not save_game(true): return false
	return urban_operations.perform(target)

func _intro_interact(id: String) -> bool:
	if id == "maciota" and state.intro.stage == "meet_maciota" and not save_game(true): return false
	state.intro.set_location("harbor_garage")
	var reply: Dictionary = state.intro.interact(id)
	if not reply.ok: return false
	if id == "maciota": arrival.notify_maciota_met()
	show_dialogue([{ "speaker":reply.speaker,"message":reply.message }])
	world.maciota_place.set_part_available(state.intro.part_available)
	if reply.changed: save_game()
	return true

func _input(event: InputEvent) -> void:
	if port_container_loot != null and is_instance_valid(port_container_loot.minigame) and port_container_loot.minigame.active: return
	if controller.travel_busy or not transition_kind.is_empty() or vehicle_transition_busy:
		get_viewport().set_input_as_handled()
		return
	if not ready_for_play: return
	if arrival.riding and (event.is_action_pressed("pause_game") or event.is_action_pressed("exit_vehicle")):
		arrival.cancel_ride()
		get_viewport().set_input_as_handled()
		return
	if _arrival_sequence_blocked():
		if event.is_action_pressed("pause_game") or event.is_action_pressed("ui_cancel"):
			show_message("Aguarde a conclusão desta chegada.")
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(robberies.lockpick) and robberies.lockpick.active: return
	if police_motor_pool != null and police_motor_pool.blocks_input(): return
	if not rebinding_action.is_empty():
		if event is InputEventKey and event.pressed and not event.echo:
			var controls = get_node("/root/GameInput")
			if event.keycode != KEY_ESCAPE:
				var error: String = controls.rebind(rebinding_action,event)
				if not error.is_empty(): show_message(error); get_viewport().set_input_as_handled(); return
				get_node("/root/V2Settings").save_settings()
			rebinding_action = ""
			controls.remapping = false
			show_controls()
			get_viewport().set_input_as_handled()
		return
	if modal:
		if field_inventory != null and field_inventory.ui.visible and event.is_action_pressed("inventory"):
			close_menu()
			get_viewport().set_input_as_handled()
			return
		if storefronts != null and storefronts.is_open() and storefronts.handle_input(event):
			get_viewport().set_input_as_handled()
			return
		# Focused Buttons own ui_accept. Consuming it here prevented Enter and the
		# controller accept button from reaching shops, journals and death rescue.
		if dialogue_open and (event.is_action_pressed("interact") or event.is_action_pressed("ui_accept")):
			_advance_dialogue()
			get_viewport().set_input_as_handled()
		elif (event.is_action_pressed("pause_game") or event.is_action_pressed("ui_cancel")) and not rescue_pending:
			close_menu()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("interact"):
			get_viewport().set_input_as_handled()
		return
	if get_tree().paused: return
	if passenger_transport != null and passenger_transport.riding:
		if event.is_action_pressed("interact") or event.is_action_pressed("exit_vehicle") or event.is_action_pressed("vehicle_interact"):
			passenger_transport.request_exit()
		# Leave pause available, but consume gameplay/menu/quick-save input in transit.
		if not event.is_action_pressed("pause_game"): get_viewport().set_input_as_handled()
		return
	if motocross != null and motocross.mounted:
		if event.is_action_pressed("interact") or event.is_action_pressed("exit_vehicle"):
			motocross.perform("quit" if motocross.active else "dismount")
		if not event.is_action_pressed("pause_game"): get_viewport().set_input_as_handled()
		return
	if world.driving.occupied and is_instance_valid(world.driving.car.equipment):
		if world.driving.car.equipment.handle_input(event,true):
			get_viewport().set_input_as_handled()
			return
	var wants_interact := event.is_action_pressed("interact")
	if world.gameplay.handle_arsenal_input(event):
		get_viewport().set_input_as_handled()
		return
	var wants_reload: bool = event.is_action_pressed("reload") and not world.driving.occupied
	if wants_interact and (not wants_reload or not nearest().is_empty()):
		interact()
		get_viewport().set_input_as_handled()
	elif wants_reload:
		world.gameplay.reload_weapon()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("journal"): show_journal()
	elif event.is_action_pressed("inventory"): show_inventory()
	elif event.is_action_pressed("trunk"):
		var personal_action: Dictionary = personal_car.nearest_action()
		if personal_action.get("target","") == "trunk":
			personal_car.perform(personal_action.target)
		elif event.is_action_pressed("unarmed") and not world.driving.occupied:
			state.equip_weapon("fists")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("world_map"): show_map()
	elif event.is_action_pressed("unarmed"): state.equip_weapon("fists")
	elif event.is_action_pressed("weapon_next") and not world.driving.occupied: world.gameplay.cycle_weapon(1)
	elif event.is_action_pressed("weapon_flashlight"): _toggle_weapon_flashlight()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F5: save_game(true)
		elif event.physical_keycode == KEY_F9: load_game()

## V1 `WeaponFlashlight._unhandled_input`: sem lanterna instalada na arma em mãos,
## a tecla explica onde comprá-la em vez de falhar em silêncio.
func _toggle_weapon_flashlight() -> void:
	if world.gameplay.toggle_flashlight(): return
	var id: String = world.gameplay.equipped()
	if not state.can_attack() or id in ["", "fists"]: return
	if not preload("res://gameplay/WeaponCustomization.gd").installed(world.gameplay.customization, id):
		show_message("Instale uma lanterna nesta arma na Ammu-Nation.")

func _process(delta: float) -> void:
	notice_time = maxf(0.0,notice_time-delta)
	notice.visible = notice_time > 0
	if not ready_for_play or get_tree().paused: return
	weapon_shop_entrance.update(delta)
	special_place_entrance.update(delta)
	if is_instance_valid(world.driving.car) and is_instance_valid(world.driving.car.equipment): world.driving.car.equipment.set_input_enabled(not modal)
	if not modal and not world.driving.occupied and not get_tree().paused:
		var aim: Vector3 = world.gameplay.aim_from_screen(get_viewport().get_mouse_position())
		var controls = get_node("/root/GameInput")
		if controls.using_gamepad or controls.get_meta("touch_controls_active", false) or not controls.touch_aim.is_zero_approx():
			aim = controls.aim_target_3d(world.player,world.camera,delta)
			# Robbery intimidation and every non-shot aim consumer read the same
			# authoritative world point as firearm presentation. Previously only the
			# local fire target followed a controller/touch stick, so the fuel clerk
			# could be aimed at visually but never surrender without a mouse cursor.
			world.gameplay.aim_point = aim
		var data: Dictionary = WEAPONS.WEAPONS.get(state.equipped_weapon,{})
		if Input.is_action_pressed("fire") and (data.get("automatic",false) or Input.is_action_just_pressed("fire")): world.gameplay.fire_at(aim)
	if world.player.position.y < -12 and not modal: _on_death()
	tick += delta
	if tick < .1: return
	tick = 0
	_refresh_reward_feedback()
	if not modal and not world.driving.occupied:
		if not state.place_id.is_empty() and state.place_id != "maciota": _collect_reward(room)
		elif state.place_id.is_empty():
			for source in get_tree().get_nodes_in_group("native_world_rewards"): _collect_reward(source)
	var ammo: Dictionary = state.get_ammo(state.equipped_weapon)
	if cold != null:
		var thermal: Dictionary = cold.status()
		thermal_status.visible = thermal.visible and not modal
		thermal_status.text = "Calor corporal %d%% · %s"%[roundi(thermal.temperature),thermal.text]
	stats.text = "R$ %d   Vida %d   Colete %d\n%s   %s   %s" % [state.economy.balance,roundi(world.gameplay.health),roundi(world.gameplay.armor),str(WEAPONS.WEAPONS.get(state.equipped_weapon,{}).get("label",state.equipped_weapon)),"—" if int(ammo.magazine)<0 else "%d / %d"%[ammo.magazine,ammo.reserve],"★".repeat(world.gameplay.stars)]
	objective.text = state.campaign.objective() if state.campaign.active_id != "" else (state.intro.objective() if state.intro.stage != "complete" else "J  Missões · M  Mapa")
	if arrival.active: objective.text = arrival.objective_text
	var freight: Dictionary = urban_operations.freight_status() if urban_operations != null else {}
	freight_active = bool(freight.get("active", false)) and state.region_id == "harbor" and state.campaign.active_id.is_empty() and state.intro.stage == "complete" and not arrival.active
	freight_target = freight.get("target", Vector3.INF) if freight_active else Vector3.INF
	if freight_active: objective.text = str(freight.get("objective", ""))
	if urban_operations != null and is_instance_valid(urban_operations.village_quest) and state.campaign.active_id.is_empty() and state.intro.stage == "complete" and not arrival.active and not freight_active:
		var village_objective: String = urban_operations.village_quest.objective()
		if not village_objective.is_empty(): objective.text = village_objective
	var action := nearest()
	var silent_exit: bool = action.get("id","") == "exit" and state.place_id == "vertice_undercroft"
	prompt.text = "" if modal or action.is_empty() or action.get("silent",false) or silent_exit else "E  "+str(action.label)
	if not modal and action.get("id","") == "port_container":
		prompt.text = get_node("/root/GameInput").hint("interact")+"  "+str(action.label)

func _update_world_indicator() -> void:
	if not ready_for_play or not is_instance_valid(marker) or not is_instance_valid(arrow): return
	var target: Vector3 = mission_world.target_position()
	if state.intro.stage != "complete": target = world.maciota_place.entry_position
	if arrival.active: target = arrival.target
	if freight_active: target = freight_target
	if not state.place_id.is_empty() and is_instance_valid(room):
		target = room.exit_position
		if state.place_id == "maciota":
			var phase: String = state.intro.stage
			if phase in ["meet_maciota","return_maciota"] or state.campaign.target_id()=="maciota": target = room.interaction_points.maciota
			elif phase == "talk_mechanic": target = room.interaction_points.mechanic
			elif phase == "collect_part": target = room.interaction_points.part
		elif state.place_id == "harbor_bank" and state.campaign.target_id()=="helena": target = robberies.helena_position()
	var maciota_exterior_marker: bool = state.place_id.is_empty() and target.is_equal_approx(world.maciota_place.entry_position)
	var automatic_shop_exit: bool = _uses_walkup_access(state.place_id) and is_instance_valid(room) and target.is_equal_approx(room.exit_position)
	marker.visible = target.is_finite() and not maciota_exterior_marker and not automatic_shop_exit and not world.camera.is_position_behind(target)
	if marker.visible: marker.position = world.camera.unproject_position(target+Vector3.UP*.06)
	var screen: Vector2 = world.camera.unproject_position(target) if target.is_finite() else Vector2(640,360)
	arrow.visible = state.place_id.is_empty() and not Rect2(40,90,1200,520).has_point(screen)
	arrow.position = Vector2(clampf(screen.x,40,1220),clampf(screen.y,90,610))
	arrow.rotation = (screen-Vector2(640,360)).angle()+PI/2

func _menu(title: String) -> void:
	if panel.has_meta("modal_preferred_size"): panel.remove_meta("modal_preferred_size")
	var previous_map: Node = world.hud.get_node_or_null("MapUI")
	if is_instance_valid(previous_map):
		previous_map.queue_free()
		menu_closed = Callable()
	if field_inventory != null and field_inventory.ui.visible:
		field_inventory.dismiss()
		menu_closed = Callable()
	_service_menu_open = false
	if storefronts != null and storefronts.is_open(): storefronts.dismiss()
	for child in column.get_children():
		column.remove_child(child)
		child.queue_free()
	modal = true
	dialogue_open = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	world.player.input_locked = true
	if world.driving.occupied: world.driving.car.input_locked = true
	panel.show()
	panel.custom_minimum_size = Vector2(620,440)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size",26)
	column.add_child(label)
func _button(text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 36
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(action)
	var previous: Button = null
	for child in column.get_children():
		if child is Button: previous = child
	column.add_child(button)
	if previous != null:
		previous.focus_neighbor_bottom = previous.get_path_to(button)
		previous.focus_next = previous.get_path_to(button)
		button.focus_neighbor_top = button.get_path_to(previous)
		button.focus_previous = button.get_path_to(previous)
	else:
		_focus_menu_button.call_deferred(weakref(button))
func _focus_menu_button(reference: WeakRef) -> void:
	var button := reference.get_ref() as Control
	if not is_instance_valid(button) or button.is_queued_for_deletion(): return
	if modal and button.is_inside_tree() and button.get_parent() == column and button.is_visible_in_tree():
		button.grab_focus()
func close_menu() -> void:
	_service_menu_open = false
	if storefronts != null and storefronts.is_open(): storefronts.dismiss()
	if menu_closed.is_valid(): menu_closed.call()
	menu_closed = Callable()
	modal = false
	dialogue_open = false
	panel.hide()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	world.player.input_locked = world.gameplay.health <= 0 or is_transition_blocked() or (passenger_transport != null and passenger_transport.riding) or (motocross != null and motocross.mounted)
	if is_instance_valid(world.driving.car): world.driving.car.input_locked = is_transition_blocked()
func show_dialogue(dialogue_lines: Array, on_done := Callable()) -> void:
	lines = dialogue_lines.duplicate(true)
	dialogue_done = on_done
	_advance_dialogue()
func _advance_dialogue() -> void:
	if lines.is_empty():
		close_menu()
		if dialogue_done.is_valid(): dialogue_done.call()
		return
	var line: Dictionary = lines.pop_front()
	var continuing_service := _service_menu_open
	_menu(str(line.get("speaker","")))
	_service_menu_open = continuing_service
	dialogue_open = true
	var text := Label.new()
	text.text = str(line.get("message",""))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = 560
	text.add_theme_font_size_override("font_size",21)
	column.add_child(text)
	_button("Continuar",_advance_dialogue)

func cancel_mission() -> bool:
	if state.campaign.active_id.is_empty(): return false
	if not mission_world.cancel_attempt():
		show_message("Libere uma área para descarregar o guincho antes de cancelar.")
		save_game()
		return false
	close_menu()
	save_game()
	return true

func show_journal() -> void:
	_menu("Missões")
	if state.campaign.active_id != "":
		_button(state.campaign.objective(),close_menu)
		_button("Cancelar missão",cancel_mission)
	else:
		for id in state.campaign.available_missions():
			_button(str(MISSIONS.MISSIONS[id].title),func():
				if state.intro.stage != "complete": show_message("Converse primeiro com Maciota."); close_menu(); return
				if not mission_world.begin(id):
					close_menu()
					return
				if not dialogue_open: close_menu())
	var secret_file: Variant = urban_operations.get("secret_file") if urban_operations != null else null
	if is_instance_valid(secret_file) and secret_file.available():
		_button("Arquivo de Vicente",secret_file.open_from_journal)
	_button("Voltar",close_menu)
func show_inventory() -> void:
	if field_inventory != null:
		field_inventory.open()
		return
	_menu("Inventário · R$ %d"%state.economy.balance)
	for id in WEAPONS.ORDER:
		if state.owns_weapon(id):
			var stored: bool = not state.economy.can_carry_weapon(id)
			_button(str(WEAPONS.WEAPONS[id].label)+(" · No porta-malas" if stored else ""),func():
				if not state.economy.can_carry_weapon(id):
					close_menu()
					show_message("Selecione esta arma no porta-malas da Monaliza.")
					return
				close_menu()
				state.equip_weapon(id))
	if state.economy.inventory.get("first_aid",0)>0:
		_button("Usar primeiros socorros",func():
			if world.gameplay.heal(40): state.economy.consume_item("first_aid")
			close_menu(); save_game())
	_button("Configurações",show_settings)
	_button("Voltar",close_menu)
func show_services(service: String) -> void:
	if _service_threatened(): return
	_show_services_available(service)
	_service_menu_open = modal

func _show_services_available(service: String) -> void:
	if service == "ski_rental":
		mountain_progression.show_services()
		return
	if services.perform(service): return
	if service in ["weapons","ammunation","gunshop"]:
		if state.place_id == "harbor_ammunation" and storefronts.open_weapons(): return
		_show_shop("weapon")
		return
	if service == "clothing":
		if state.place_id == "harbor_clothing" and storefronts.open_clothing(): return
		_show_shop("outfit")
		return
	# Vehicle repair belongs to its physical service. Maciota is handled above
	# by Services.perform(); Northgate admits the occupied car in its exterior
	# bay. This fallback must never charge or clear wanted state remotely.
	if service == "garage":
		show_message("Use a bancada da garagem para cuidar da Monaliza.")
		return
	if service == "auto_service":
		show_message("Leve o veículo até a baia externa da Northgate.")
		return
func _show_shop(category: String) -> void:
	_menu("R$ %d"%state.economy.balance)
	for item in state.economy.storefront(category):
		var label := str(item.get("name",item.get("label",item.id)))
		_button(label+(" · Equipar" if item.owned else " · R$ %d"%item.price),func():
			if not item.owned:
				var result: Dictionary = state.economy.purchase(category,item.id,_transaction())
				if not result.ok: show_message("Compra indisponível: "+str(result.reason)); close_menu(); return
			if category == "weapon": state.equip_weapon(item.id)
			else: state.economy.equip_outfit(item.id); apply_outfit()
			close_menu(); save_game())
	if category == "weapon":
		_button("Personalizar arma equipada",_show_customization)
		_button("Munição para arma equipada",func():
			var purchased: bool = state.economy.buy_ammo(state.equipped_weapon,30,_transaction())
			show_message("Munição comprada." if purchased else "Compra indisponível.")
			close_menu(); save_game())
		if world.gameplay.armor >= 100:
			_button("Proteção completa",func():
				show_message("O colete já está completo.")
				close_menu())
		else:
			_button("Colete · R$ 500",func():
				var result: Dictionary = state.economy.purchase_body_armor(world.gameplay.armor,100,_transaction())
				if result.ok:
					world.gameplay.armor = int(result.armor)
					show_message("Colete equipado.")
				else:
					show_message("Proteção completa." if result.reason == "protection_full" else "Compra indisponível.")
				close_menu()
				if result.ok: save_game())
	_button("Voltar",close_menu)
func _show_customization() -> void:
	var catalog = preload("res://gameplay/WeaponCustomization.gd")
	var id: String = state.equipped_weapon
	_menu("Personalizar · "+str(WEAPONS.WEAPONS[id].label))
	for part in catalog.PARTS:
		if not catalog.supports(id,part): continue
		var data: Dictionary = catalog.PARTS[part]
		var owned: bool = catalog.owns(world.gameplay.customization,id,part)
		var selected: bool = catalog.selected(world.gameplay.customization,id,data.slot) == part
		var suffix := " · Remover" if selected else (" · Instalar" if owned else " · R$ %d"%data.price)
		_button(str(data.label)+suffix,func():
			var ok: bool = world.gameplay.install_attachment(id,part,false) if selected else world.gameplay.buy_attachment(id,part)
			if not ok: show_message("Personalização indisponível.")
			save_game()
			_show_customization())
	_button("Voltar",func(): _show_shop("weapon"))
func _transaction() -> String:
	action_serial += 1
	return "%d_%d_%d"%[Time.get_unix_time_from_system(),Time.get_ticks_usec(),action_serial]
func apply_outfit() -> void:
	# Palette integration is applied by the original Dante outfit shader adapter.
	var outfit: String = state.economy.outfit
	if mountain_progression != null and mountain_progression.data.rental: outfit = "dante_ski"
	if world.player.has_method("set_outfit"): world.player.set_outfit(outfit)

func advance_residence_time(target: float) -> bool:
	if target not in [.36,.84] or controller.save_invalid or weather == null: return false
	if state.region_id != "harbor" or not activities.residence.can_enter(state.place_id) or state.place_id.is_empty(): return false
	if not is_instance_valid(room) or world.driving.occupied or world.gameplay.health <= 0 or world.gameplay.stars > 0: return false
	if world.player.position.distance_to(room.interaction_points.service) >= 1.5: return false
	if not state.campaign.active_id.is_empty() or not activities.can_rest() or arrival.active: return false
	var elapsed := fposmod(target-float(weather.time_of_day),1.0)*600.0
	activities.advance_time(elapsed)
	weather.time_of_day = target
	state.world_state.time = target
	weather._update()
	return true
func show_settings() -> void:
	close_menu()
	world.pause_panel.pause_game()
	world.pause_panel.open_settings()
func show_controls() -> void:
	show_settings()
	world.pause_panel.settings._select_tab(2)
func show_map() -> void:
	_menu("Mapa")
	var map = preload("res://ui/v2/WorldMap.gd").new()
	map.controller = controller
	world.hud.add_child(map)
	panel.hide()
	menu_closed = map.queue_free
func _update_reward() -> void:
	if room == null or room == world.maciota_place: return
	for point in room.reward_points:
		var data: Dictionary = point.get("reward",{})
		if not data.is_empty(): room.set_reward_available(not state.world_state.rewards.has(data.id),data.id)
func _collect_reward(source: Node3D) -> void:
	if not is_instance_valid(source) or not source.is_visible_in_tree() or world.gameplay.health <= 0: return
	for reward in source.reward_points:
		var data: Dictionary = reward.get("reward",{})
		if data.is_empty(): continue
		if state.world_state.rewards.has(data.id):
			source.set_reward_available(false,data.id)
			continue
		var point: Vector3 = reward.get("position",Vector3.ZERO)
		if world.player.global_position.distance_to(point) > .8: continue
		if _reward_failures.has(data.id): continue
		var result: Dictionary = state.economy.grant_world_reward(data)
		if not result.ok:
			var reason := str(result.get("reason","grant_failed"))
			var item_name := str(WEAPONS.WEAPONS.get(str(data.get("item", "")), {}).get("label", "Item")) if data.get("kind", "") == "weapon" else "Recompensa"
			var explanation: String = {"already_owned":"Você já possui esta arma.", "wallet_full":"Carteira cheia.", "inventory_full":"Inventário cheio.", "ammo_full":"Munição no limite.", "invalid_reward":"Não foi possível coletar este item: dados inválidos.", "transaction_conflict":"Coleta bloqueada por conflito no registro da recompensa."}.get(reason, "Não foi possível concluir a coleta.")
			show_message("%s: %s" % [item_name, explanation])
			_reward_notice_id = str(data.id)
			_reward_failures[data.id] = {"source":weakref(source), "position":point, "region":state.region_id, "place":state.place_id}
			continue
		if not state.world_state.rewards.has(data.id): state.world_state.rewards.append(data.id)
		if result.get("changed",true):
			REWARD_AUDIO.play(self,REWARD_AUDIO.kind_for_reward(str(data.get("kind",""))))
		source.set_reward_available(false,data.id,true)
		# Coleta sem aviso na tela (como os drops de combate); só a falha avisa.
		save_game()
func _refresh_reward_feedback() -> void:
	# Uma falha por aproximação; não renove o aviso a cada tick nem após sair.
	for id in _reward_failures.keys():
		var failure: Dictionary = _reward_failures[id]
		var source = failure.source.get_ref()
		if is_instance_valid(source) and source.is_visible_in_tree() and failure.region == state.region_id and failure.place == state.place_id and not world.driving.occupied and world.player.global_position.distance_to(failure.position) <= .8: continue
		_reward_failures.erase(id)
		if _reward_notice_id == id:
			_reward_notice_id = ""
			notice_time = 0.0
			notice.text = ""
			notice.hide()
func save_block_reason() -> String:
	if controller.save_invalid: return "Save inválido preservado; salvamento bloqueado."
	if motocross != null and motocross.mounted: return "Termine a corrida ou desça da moto para salvar."
	if world.gameplay.health <= 0: return "Salvar indisponível enquanto o jogador estiver morto."
	if world.gameplay.stars > 0: return "Perca todas as estrelas da polícia para salvar."
	if not state.campaign.active_id.is_empty() or state.intro.stage not in ["meet_maciota", "complete"]:
		return "Conclua ou encerre a missão para salvar um checkpoint."
	if activities != null and not activities.can_rest(): return "Encerre a corrida ou o contrato de guincho para salvar."
	if mountain_progression != null and not mountain_progression.race.mode.is_empty(): return "Encerre a prova de esqui para salvar."
	if urban_operations != null:
		var quest = urban_operations.get("village_quest")
		if is_instance_valid(quest) and quest.data.started and not quest.data.completed:
			return "Conclua a missão de Tonico para salvar um checkpoint."
	if urban_operations != null and urban_operations.freight != null and urban_operations.freight.active_bay >= 0:
		return "Encerre a entrega de carga para salvar."
	if is_transition_blocked(): return "Conclua a chegada, o resgate ou a transição para salvar."
	if passenger_transport != null and passenger_transport.riding: return "Aguarde o desembarque para salvar."
	return ""

func _queue_checkpoint() -> void:
	if controller.no_save or controller.save_invalid: return
	if _checkpoint_retry == null:
		_checkpoint_retry = Timer.new()
		_checkpoint_retry.process_mode = Node.PROCESS_MODE_PAUSABLE
		_checkpoint_retry.wait_time = 1.0
		_checkpoint_retry.one_shot = true
		add_child(_checkpoint_retry)
		_checkpoint_retry.timeout.connect(func(): save_game())
	# Only one pending request; capture fresh state once saving becomes safe.
	if _checkpoint_retry.is_stopped(): _checkpoint_retry.start()

func _save_indicator() -> Control:
	var indicator := get_node_or_null("SaveFeedback/Indicator")
	if indicator == null:
		var feedback := CanvasLayer.new()
		feedback.name = "SaveFeedback"
		feedback.layer = 125
		add_child(feedback)
		indicator = preload("res://ui/SaveIndicator.gd").new()
		indicator.name = "Indicator"
		feedback.add_child(indicator)
	return indicator

func save_game(manual := false) -> bool:
	var blocked := save_block_reason()
	if not blocked.is_empty():
		if manual: _save_indicator().reject(blocked)
		else: _queue_checkpoint()
		return false
	state.world_state.erase("pedestrian")
	if state.place_id.is_empty() and not world.driving.occupied and not world.player.input_locked and position_clear(world.player.position):
		var point: Vector3 = world.player.position
		state.world_state.pedestrian = {"region":state.region_id,"position":[point.x,point.y,point.z]}
	if personal_car != null: personal_car.refresh()
	if activities != null: activities.refresh_achievements()
	controller.capture_player_vehicle()
	if cold != null: state.world_state.cold = cold.snapshot()
	if garage_rewards != null: state.world_state.garage_rewards = garage_rewards.snapshot()
	if arrival != null: state.world_state.arrival = arrival.snapshot()
	if robberies != null: state.world_state.robberies = robberies.snapshot()
	if services != null: state.world_state.services = services.snapshot()
	if activities != null: state.world_state.activities = activities.snapshot()
	if motocross != null: state.world_state.motocross = motocross.snapshot()
	if mountain_progression != null: state.world_state.mountain_progression = mountain_progression.snapshot()
	if mission_world != null: state.world_state.mission_world = mission_world.snapshot()
	if urban_operations != null:
		var urban_snapshot: Dictionary = urban_operations.snapshot()
		if not preload("res://gameplay/urban_v1/UrbanOperations.gd").validate_snapshot(urban_snapshot):
			controller.save_invalid = true
			last_save_error = "Estado urbano incompleto; salvamento bloqueado."
			_save_indicator().reject(last_save_error)
			return false
		state.world_state.urban_operations = urban_snapshot
	if controller.no_save: return true
	state.combat_state = world.gameplay.snapshot()
	var result: Error = controller.store.save(state)
	if _checkpoint_retry != null: _checkpoint_retry.stop()
	if result != OK:
		last_save_error = "Não foi possível salvar (%d)." % result
		_save_indicator().reject(last_save_error)
		return false
	last_save_error = ""
	_save_indicator().acknowledge()
	return true
func load_game() -> void:
	if is_transition_blocked():
		show_message("Aguarde a conclusão da transição para carregar."); return
	if passenger_transport != null and passenger_transport.riding:
		show_message("Aguarde o desembarque para carregar."); return
	if world.driving.occupied: show_message("Saia do veículo para carregar."); return
	garage_rewards.cancel_press_delivery()
	if is_instance_valid(world.traffic_yield): world.traffic_yield.release_all("load")
	if is_instance_valid(world.dispatch): world.dispatch.dismiss_all("load")
	var result := get_tree().reload_current_scene()
	if result != OK: show_message("Não foi possível carregar o jogo (%d)." % result)
func return_to_main_menu() -> void:
	if is_transition_blocked() or (passenger_transport != null and passenger_transport.riding):
		show_message("Aguarde a conclusão da chegada, do resgate ou da transição.")
		return
	garage_rewards.cancel_press_delivery()
	if is_instance_valid(world.traffic_yield): world.traffic_yield.release_all("main_menu")
	if is_instance_valid(world.dispatch): world.dispatch.dismiss_all("main_menu")
	var launch = get_node_or_null("/root/V2Launch")
	if launch != null: launch.direct_start_consumed = true
	var was_paused := get_tree().paused
	get_tree().paused = false
	var result := get_tree().change_scene_to_file("res://ui/MainMenu.tscn")
	if result != OK:
		get_tree().paused = was_paused
		show_message("Não foi possível abrir o menu principal.")

func _show_v1_death_presentation() -> void:
	if is_instance_valid(death_presentation): death_presentation.queue_free()
	death_presentation = CanvasLayer.new()
	death_presentation.name = "WastedPresentation"
	death_presentation.layer = 120
	var audio := AudioStreamPlayer.new()
	audio.name = "WastedAudio"
	audio.stream = V1_DEATH_AUDIO.stream()
	audio.volume_db = 0.0
	death_presentation.add_child(audio)
	var tint := ColorRect.new()
	tint.name = "DeathTint"
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tint.color = Color(0.8,0.1,0.1,0.0)
	tint.mouse_filter = Control.MOUSE_FILTER_STOP
	death_presentation.add_child(tint)
	var label := Label.new()
	label.name = "WastedLabel"
	label.text = "SE FODEU"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_size_override("font_size",42)
	label.add_theme_color_override("font_color",Color(1.0,0.1,0.1))
	label.add_theme_color_override("font_shadow_color",Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x",3)
	label.add_theme_constant_override("shadow_offset_y",3)
	label.modulate.a = 0.0
	death_presentation.add_child(label)
	get_tree().root.add_child(death_presentation)
	audio.play()
	label.pivot_offset = get_viewport().get_visible_rect().size*.5
	label.scale = Vector2(1.35,1.35)
	var intro := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	intro.tween_property(tint,"color:a",.45,.35)
	intro.tween_property(label,"modulate:a",1.0,.35)
	intro.tween_property(label,"scale",Vector2.ONE,.35)
	await get_tree().create_timer(2.2).timeout
	if is_instance_valid(death_presentation): death_presentation.queue_free()
	death_presentation = null

func _show_v1_arrest_presentation() -> void:
	if is_instance_valid(death_presentation): death_presentation.queue_free()
	death_presentation = CanvasLayer.new()
	death_presentation.name = "ArrestPresentation"
	death_presentation.layer = 120
	var tint := ColorRect.new()
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tint.color = Color(0.1,0.2,0.8,0.45)
	tint.mouse_filter = Control.MOUSE_FILTER_STOP
	death_presentation.add_child(tint)
	var label := Label.new()
	label.name = "ArrestLabel"
	label.text = "PRESO"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_size_override("font_size",46)
	label.add_theme_color_override("font_color",Color(0.2,0.6,1.0))
	label.add_theme_color_override("font_shadow_color",Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x",3)
	label.add_theme_constant_override("shadow_offset_y",3)
	death_presentation.add_child(label)
	get_tree().root.add_child(death_presentation)
	await get_tree().create_timer(2.2).timeout
	if is_instance_valid(death_presentation): death_presentation.queue_free()
	death_presentation = null

func _on_arrest() -> void:
	if arrest_pending or rescue_pending: return
	arrest_pending = true
	prompt.text = ""
	if services != null and services.has_method("cancel_auto_service"): services.cancel_auto_service("player_arrest")
	if is_instance_valid(world.driving) and world.driving.has_method("cancel_transition"): world.driving.cancel_transition("player_arrest")
	if passenger_transport != null and passenger_transport.riding: passenger_transport._brake()
	garage_rewards.cancel_press_delivery()
	activities.cancel_attempt()
	mountain_progression.cancel_attempt()
	mission_world.cancel_attempt("player_arrest")
	await _show_v1_arrest_presentation()
	if not arrest_pending or not is_inside_tree(): return
	await _respawn()

func _on_death() -> void:
	if rescue_pending: return
	# Falling out of the world and an invalid restored position reach this path
	# directly, without damage_player. Establish the same dead state before any
	# boarding cleanup or death presentation reads it.
	world.gameplay.health = 0
	if services != null and services.has_method("cancel_auto_service"): services.cancel_auto_service("player_death")
	if is_instance_valid(world.driving) and world.driving.has_method("cancel_transition"): world.driving.cancel_transition("player_death")
	world.player.input_locked = true
	world.player.on_player_death()
	# Damage may have posed death before Driving restored the on-foot capsule.
	# Reassert the dead body's collision after cancelling that presentation.
	world.player.collision_layer = 0
	world.player.collision_mask = 0
	world.player.set_physics_process(false)
	world.gameplay.changed.emit()
	var from_interior: bool = not state.place_id.is_empty() or is_instance_valid(room)
	rescue_camera_heading = saved_heading if from_interior else world.camera.heading
	rescue_camera_size = saved_size if from_interior else world.camera.target_size
	rescue_pending = true
	prompt.text = ""
	world.hud.refresh_from_state()
	if passenger_transport != null and passenger_transport.riding: passenger_transport._brake()
	lines.clear()
	dialogue_done = Callable()
	garage_rewards.cancel_press_delivery()
	activities.cancel_attempt()
	mountain_progression.cancel_attempt()
	mission_world.cancel_attempt("player_death")
	await _show_v1_death_presentation()
	if not rescue_pending or not is_inside_tree(): return
	await _respawn()

func _respawn() -> void:
	if respawn_busy: return
	var token := _begin_transition("rescue")
	if token < 0:
		show_message("Aguarde a transição atual e tente novamente.")
		return
	respawn_busy = true
	var destination: Vector3 = controller.region.spawn_position+Vector3.UP*.1
	if arrest_pending and state.region_id == "harbor":
		var police: Dictionary = PLACES.get_definition("harbor_police")
		if not police.is_empty(): destination = police.return_position+Vector3.UP*.1
	controller.region.set_focus(destination)
	if cold != null: cold.prepare_collision_at(destination)
	for i in 3:
		await get_tree().physics_frame
		if not _owns_transition(token): return
	if not position_clear(destination):
		respawn_busy = false
		_finish_transition(token)
		_menu("Local de custódia ocupado. Aguarde e tente novamente." if arrest_pending else "Local de resgate ocupado. Aguarde e tente novamente.")
		_button("Tentar novamente",_respawn)
		return
	if world.driving.occupied:
		world.driving.occupied = false
		if is_instance_valid(world.driving.car):
			world.driving.car.controlled = false
			world.driving.car.external_input = false
			world.driving.car.throttle_input = 0
	if passenger_transport != null: passenger_transport.cancel_for_transition()
	if is_instance_valid(room):
		if room == world.maciota_place: room.set_interior_active(false)
		else: room.queue_free()
	_clear_service_npcs()
	room = null
	state.set_location(state.region_id)
	world.gameplay.respawn()
	world.player.respawn_player()
	if is_instance_valid(world.traffic_yield): world.traffic_yield.release_all("rescue")
	if is_instance_valid(world.dispatch): world.dispatch.dismiss_all("rescue")
	sync_dispatch_location()
	if cold != null: cold.recover_after_rescue()
	world.player.teleport(destination)
	_sync_location_presentation()
	world.player.collision_layer = 2
	world.player.collision_mask = 7
	world.player.show()
	world.player.set_physics_process(true)
	world.camera.target = world.player
	world.camera.offset = world.camera.EXTERIOR_OFFSET
	world.camera.heading = rescue_camera_heading
	world.camera.target_size = rescue_camera_size
	world.camera.size = rescue_camera_size
	world.camera.locked = false
	world.camera.initialized = false
	world.camera._process(1)
	_refresh_routine_context()
	rescue_pending = false
	arrest_pending = false
	respawn_busy = false
	_finish_transition(token)
	close_menu()
	save_game()
