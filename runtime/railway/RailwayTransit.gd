extends Node
## A single train, a single passenger owner, and the production world's streaming.
## Saves occur only on supported station platforms, never over a moving viaduct.
const NETWORK := preload("res://world/railway/RailwayNetwork.gd")
const MODEL := preload("res://world/railway/TrainModel.gd")
const GATE := preload("res://world/north_gateway/NorthGatewayPolicy.gd")
const CRUISE_SPEED := 20.0
const ACCELERATION := 4.0
const BOARD_RADIUS := 4.2
signal station_requested(origin_id: String, stations: Array)
signal station_menu_closed
signal trip_started(state: Dictionary)
signal trip_updated(state: Dictionary)
signal trip_finished(station_id: String)
signal notice(message: String)
var session
var train: Node3D
var riding := false
var landing := false
var menu_open := false
var camera_mode := 1
var origin_id := ""
var destination_id := ""
var route := PackedVector3Array()
var route_length := 0.0
var distance := 0.0
var speed := 0.0
var _cumulative := PackedFloat32Array()
var _saved: Dictionary = {}
var _menu_locked := false
var _menu_mouse := Input.MOUSE_MODE_HIDDEN
var _generation := 0
var _dwell := 0.0
var _ui_clock := 0.0
var _parked_station := ""
var _audio: AudioStreamPlayer3D
var _boarding := false
var _direction_sign := 1.0
var _ambient_from := "harbor_central"
var _ambient_to := "harbor_north"
var _ambient_returning := false
var _ambient_initialized := false
var _next_desert := false
var _arrival_retry := 0.0
var _arrival_notice_sent := false

func configure(owner_session) -> void:
	session = owner_session
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_physics_priority = 10
	if not notice.is_connected(session.show_message): notice.connect(session.show_message)

func busy() -> bool:
	return riding or landing or menu_open

func is_riding() -> bool:
	return riding

func _eligible(allow_menu := false) -> bool:
	if session == null or not session.ready_for_play or riding or landing: return false
	if session.rescue_pending or session.arrest_pending or session.respawn_busy: return false
	if not session.state.place_id.is_empty() or session.world.driving.occupied: return false
	if session.world.gameplay.health <= 0 or session.world.gameplay.stars > 0: return false
	if not session.transition_kind.is_empty() or session.vehicle_transition_busy or session.controller.travel_busy: return false
	if not session.state.campaign.active_id.is_empty(): return false
	if _local_activity_pending(): return false
	if session._arrival_sequence_blocked(): return false
	if session.arrival != null and session.arrival.active: return false
	if session.activities != null and not session.activities.can_rest(): return false
	if session.desert != null and session.desert.busy(): return false
	if session.mountain_activities != null and session.mountain_activities.busy(): return false
	if session.passenger_transport != null and session.passenger_transport.riding: return false
	if session.jessica != null and session.jessica.riding: return false
	if session.motocross != null and session.motocross.mounted: return false
	if session.skate != null and session.skate.controls_locked(): return false
	if is_instance_valid(session.world.player.ski_controller) and session.world.player.ski_controller.skiing: return false
	if (session.modal or session.world.player.input_locked) and not (allow_menu and menu_open): return false
	return true

func _local_activity_pending() -> bool:
	# Read the activity owners, without invoking persistence as a proximity query.
	if session.mining != null and not session.mining.save_block_reason().is_empty(): return true
	if session.armored_transport != null:
		var armored = session.armored_transport
		if armored.pending_truck >= 0 or int(armored.data.get("pending", 0)) > 0: return true
		if is_instance_valid(armored.minigame) and armored.minigame.active: return true
	if session.port_container_loot != null:
		var cargo = session.port_container_loot
		if is_instance_valid(cargo.pending): return true
		if is_instance_valid(cargo.minigame) and cargo.minigame.active: return true
	if session.urban_operations != null:
		if session.urban_operations.freight != null and session.urban_operations.freight.active_bay >= 0: return true
		var quest = session.urban_operations.get("village_quest")
		if is_instance_valid(quest) and quest.data.started and not quest.data.completed: return true
	if session.mountain_progression != null and not session.mountain_progression.race.mode.is_empty(): return true
	if session.garage_rewards != null and is_instance_valid(session.garage_rewards.press_delivery) and session.garage_rewards.press_delivery.active: return true
	return false

func station_available(station: Dictionary) -> bool:
	if station.is_empty(): return false
	return not station.get("requires_act1", false) or GATE.campaign_completed(session.state.campaign.snapshot())

func _nearby_station() -> Dictionary:
	var position: Vector3 = session.world.player.global_position
	var result: Dictionary = {}
	var best := BOARD_RADIUS
	for station in NETWORK.stations():
		var gap := position.distance_to(station.arrival)
		if gap < best:
			best = gap
			result = station
	return result

func can_interact() -> bool:
	return session != null and not _nearby_station().is_empty() and _eligible()

func nearest_action() -> Dictionary:
	if not can_interact(): return {}
	return {"id": "railway", "label": "Viajar de trem", "target": str(_nearby_station().id)}

func perform(target: String) -> bool:
	if not can_interact() or str(_nearby_station().id) != target: return false
	return try_interact()

func try_interact() -> bool:
	if not can_interact(): return false
	origin_id = str(_nearby_station().id)
	_menu_locked = session.world.player.input_locked
	_menu_mouse = Input.mouse_mode
	menu_open = true
	session.modal = true
	session.world.player.input_locked = true
	session.menu_closed = _on_session_menu_closed
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	station_requested.emit(origin_id, destinations(origin_id))
	return true

func destinations(from_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for station in NETWORK.stations():
		if str(station.id) == from_id: continue
		var points := NETWORK.get_route(from_id, str(station.id))
		var total := 0.0
		for index in range(1, points.size()): total += points[index - 1].distance_to(points[index])
		var available := station_available(station) and points.size() >= 2
		result.append({"id": str(station.id), "name": str(station.label), "label": str(station.label),
			"available": available, "locked_reason": "Conclua a última missão da cidade 1." if not available else "",
			"duration_seconds": ceili(total / CRUISE_SPEED + CRUISE_SPEED / ACCELERATION + 2.0)})
	return result

func close_station_menu() -> void:
	if not menu_open: return
	menu_open = false
	session.menu_closed = Callable()
	session.modal = false
	if not riding and not landing and session.world.gameplay.health > 0 and not session.rescue_pending and not session.arrest_pending:
		session.world.player.input_locked = _menu_locked
	Input.mouse_mode = _menu_mouse
	station_menu_closed.emit()

func _on_session_menu_closed() -> void:
	# FullSession.close_menu may be called by rescue or another owning interface.
	close_station_menu()

func travel_to(target: String, instant := false) -> bool:
	if not _eligible(true): return false
	var source := _nearby_station()
	var destination := NETWORK.get_station(target)
	if source.is_empty() or destination.is_empty() or str(source.id) == target: return false
	if not station_available(destination):
		notice.emit("Conclua a última missão da cidade 1 para viajar ao deserto.")
		return false
	var points := NETWORK.get_route(str(source.id), target)
	if points.size() < 2: return false
	close_station_menu()
	origin_id = str(source.id)
	destination_id = target
	_build_route(points)
	_ensure_train()
	_align_direction()
	_snapshot_passenger()
	_generation += 1
	riding = true
	landing = false
	# Signal listeners may select a camera before the boarding fade has started.
	# Record that choice without exposing the train's previous service position.
	_boarding = true
	distance = 0.0
	speed = 0.0
	_dwell = 1.2
	_ui_clock = 0.0
	_arrival_retry = 0.0
	_arrival_notice_sent = false
	camera_mode = 1
	_parked_station = ""
	var actor = session.world.player
	actor.input_locked = true
	actor.velocity = Vector3.ZERO
	actor.collision_layer = 0
	actor.collision_mask = 0
	actor.set_physics_process(false)
	actor.set_meta("mountain_shelter", true)
	session.state.equip_weapon("fists")
	session.world.camera.clear_store_focus()
	_set_passenger_depth(true)
	session.world.camera.locked = true
	session.world.camera.set_process(false)
	if is_instance_valid(session.world.camera.scope_reticle): session.world.camera.scope_reticle.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	train.show()
	train.set_doors_open(false)
	trip_started.emit(get_trip_state())
	if instant:
		_update_train_pose()
		_boarding = false
		_arrive(target)
	else: _board_with_fade(_generation)
	return true

func _board_with_fade(generation: int) -> void:
	_boarding = true
	if is_instance_valid(session.door_transition): await session.door_transition.fade_to(1.0, .23)
	if generation != _generation or not riding: return
	_update_train_pose()
	train.reset_physics_interpolation()
	session.world.player.reset_physics_interpolation()
	if is_instance_valid(session.door_transition): await session.door_transition.fade_to(0.0, .28)
	if generation != _generation or not riding: return
	_boarding = false

func _snapshot_passenger() -> void:
	var actor = session.world.player
	var camera = session.world.camera
	_saved = {"layer": actor.collision_layer, "mask": actor.collision_mask, "physics": actor.is_physics_processing(),
		"visible": actor.visible, "locked": actor.input_locked, "origin_position": actor.global_position,
		"weapon": session.state.equipped_weapon, "mouse": Input.mouse_mode,
		"shelter_had": actor.has_meta("mountain_shelter"), "shelter": actor.get_meta("mountain_shelter", false),
		"camera_process": camera.is_processing(), "camera_target": camera.target, "camera_offset": camera.offset,
		"camera_heading": camera.heading, "camera_target_size": camera.target_size, "camera_size": camera.size,
		"camera_locked": camera.locked, "camera_projection": camera.projection, "camera_fov": camera.fov,
		"camera_near": camera.near, "camera_far": camera.far, "camera_transform": camera.global_transform,
		"camera_depth_had": camera.has_meta("uses_interior_depth"), "camera_depth": camera.get_meta("uses_interior_depth", false)}

func _set_passenger_depth(active: bool) -> void:
	var camera = session.world.camera
	if active:
		camera.set_meta("uses_interior_depth", true)
	elif bool(_saved.get("camera_depth_had", false)):
		camera.set_meta("uses_interior_depth", _saved.camera_depth)
	else:
		camera.remove_meta("uses_interior_depth")
	# Reuse the existing interior-depth contract: only CityLook's own x-ray
	# overlay yields. The real actor remains visible through coach windows.
	var city_look: Node = session.world.get_node_or_null("CityLook")
	if city_look != null: city_look._refresh_silhouette()

func _build_route(points: PackedVector3Array) -> void:
	route = points
	_cumulative = PackedFloat32Array([0.0])
	route_length = 0.0
	for index in range(1, route.size()):
		route_length += route[index - 1].distance_to(route[index])
		_cumulative.append(route_length)

func sample_route(at_distance: float) -> Vector3:
	if route.is_empty(): return Vector3.ZERO
	if route.size() == 1: return route[0]
	if at_distance <= 0: return route[0] + (route[1] - route[0]).normalized() * at_distance
	if at_distance >= route_length:
		return route[-1] + (route[-1] - route[-2]).normalized() * (at_distance - route_length)
	# Binary search keeps per-frame work bounded even for long authored lines.
	var low := 0
	var high := _cumulative.size() - 1
	while high - low > 1:
		var middle := floori(float(low + high) / 2.0)
		if _cumulative[middle] <= at_distance: low = middle
		else: high = middle
	var fraction := (at_distance - _cumulative[low]) / maxf(.001, _cumulative[high] - _cumulative[low])
	return route[low].lerp(route[high], fraction)

func _pose_at(at_distance: float) -> Transform3D:
	var point := sample_route(at_distance)
	var tangent := (sample_route(at_distance + .8) - sample_route(at_distance - .8)).normalized() * _direction_sign
	return Transform3D(Basis.looking_at(tangent, Vector3.UP), point)

func _align_direction() -> void:
	_direction_sign = 1.0
	if not is_instance_valid(train) or route.size() < 2: return
	if train.global_position.distance_to(route[0]) > 3.0: return
	var tangent := (route[1] - route[0]).normalized()
	if (-train.global_basis.z).dot(tangent) < 0: _direction_sign = -1.0

func _physics_process(delta: float) -> void:
	if session == null or not session.ready_for_play: return
	if not riding:
		if not menu_open: _tick_ambient(delta)
		return
	if landing or _boarding: return
	if _arrival_retry > 0.0:
		_arrival_retry = maxf(0.0, _arrival_retry - delta)
		return
	if session.world.gameplay.health <= 0 or session.rescue_pending or session.arrest_pending:
		cancel_for_transition()
		return
	if not is_instance_valid(train):
		_ensure_train()
		_arrive(origin_id)
		return
	if _dwell > 0.0:
		_dwell = maxf(0.0, _dwell - delta)
		_update_train_pose()
		return
	var remaining := route_length - distance
	var target_speed := minf(CRUISE_SPEED, sqrt(maxf(0.0, 2.0 * ACCELERATION * remaining)))
	speed = move_toward(speed, target_speed, ACCELERATION * delta)
	var step := minf(remaining, speed * delta)
	distance += step
	train.advance_wheels(step * _direction_sign)
	_update_train_pose()
	if is_instance_valid(_audio):
		if not _audio.playing: _audio.play()
		_audio.pitch_scale = .74 + .45 * speed / CRUISE_SPEED
		_audio.volume_db = -21.0 + 7.0 * speed / CRUISE_SPEED
	_ui_clock += delta
	if _ui_clock >= .1:
		_ui_clock = 0.0
		trip_updated.emit(get_trip_state())
	if remaining <= .12: _arrive(destination_id)

func _process(_delta: float) -> void:
	if session == null or not session.ready_for_play: return
	if riding:
		if Input.mouse_mode in [Input.MOUSE_MODE_HIDDEN, Input.MOUSE_MODE_CONFINED_HIDDEN]: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if not _boarding: _update_camera(true)
		return

func _tick_ambient(delta: float) -> void:
	if not _ambient_initialized:
		_ensure_train()
		_start_ambient_leg("harbor_central", "harbor_north")
		_ambient_initialized = true
	if not is_instance_valid(train) or route.size() < 2: return
	if _dwell > 0.0:
		_dwell = maxf(0.0, _dwell - delta)
		if _dwell > 0.0: return
		train.set_doors_open(false)
	var remaining := route_length - distance
	var target_speed := minf(CRUISE_SPEED * .78, sqrt(maxf(0.0, 2.0 * ACCELERATION * remaining)))
	speed = move_toward(speed, target_speed, ACCELERATION * delta)
	var step := minf(remaining, speed * delta)
	distance += step
	train.advance_wheels(step * _direction_sign)
	_place_train()
	if is_instance_valid(_audio):
		var audible := train.global_position.distance_squared_to(session.world.player.global_position) < 10000.0
		if audible and not _audio.playing: _audio.play()
		elif not audible and _audio.playing: _audio.stop()
		_audio.pitch_scale = .74 + .45 * speed / CRUISE_SPEED
	if remaining > .12: return
	var arrived := _ambient_to
	var next := "harbor_north"
	if arrived == "harbor_central":
		_ambient_returning = false
	elif arrived == "mountain_pines":
		_ambient_returning = true
		_next_desert = true
	elif arrived == "desert_copper":
		_ambient_returning = true
		_next_desert = false
	elif arrived == "harbor_north":
		if _ambient_returning:
			next = "harbor_central"
		else:
			# Alternate the northern branches after the same campaign gate as roads.
			var desert := NETWORK.get_station("desert_copper")
			next = "desert_copper" if station_available(desert) and _next_desert else "mountain_pines"
	_start_ambient_leg(arrived, next)

func _start_ambient_leg(from_id: String, to_id: String) -> void:
	_ambient_from = from_id
	_ambient_to = to_id
	_build_route(NETWORK.get_route(from_id, to_id))
	_align_direction()
	distance = 0.0
	speed = 0.0
	_dwell = 12.0
	_parked_station = from_id
	_place_train()
	train.reset_physics_interpolation()
	# Boarding is admitted by the station interaction, so an unattended train
	# cannot depart with a walking actor that never entered the passenger state.
	train.set_doors_open(false)

func _place_train() -> void:
	train.global_transform = _pose_at(distance)
	train.set_engine_transform(_pose_at(distance + MODEL.ENGINE_LEAD * _direction_sign))

func _update_train_pose() -> void:
	_place_train()
	var actor = session.world.player
	actor.global_position = train.to_global(MODEL.PASSENGER_FOOT)
	actor.last_position = actor.global_position
	actor.velocity = Vector3.ZERO
	if is_instance_valid(actor.visual): actor.visual.global_rotation.y = train.global_rotation.y
	if actor.has_method("_pose_locomotion"): actor._pose_locomotion(Vector3.ZERO, 0.0, Vector3.ZERO, 0.0)
	_update_camera()

func _update_camera(interpolated := false) -> void:
	if not riding or not is_instance_valid(train) or _saved.is_empty(): return
	var camera = session.world.camera
	var pose: Transform3D = train.get_global_transform_interpolated() if interpolated else train.global_transform
	camera.target = train
	camera.near = .06
	camera.far = 280.0
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 36.0
	camera.global_position = pose * Vector3(21, 19, 27)
	camera.look_at(pose * Vector3(0, 1.1, -4.0), Vector3.UP)
	# The real actor remains present for external cameras and through the windows.
	session.world.player.visible = bool(_saved.visible)

func set_camera_mode(_mode: Variant) -> void:
	if not riding: return
	# Older callers may still request an interior view; the ride now has one view.
	camera_mode = 1
	if not _boarding: _update_camera()
	trip_updated.emit(get_trip_state())

func get_trip_state() -> Dictionary:
	var source := NETWORK.get_station(origin_id)
	var destination := NETWORK.get_station(destination_id)
	return {"origin_id": origin_id, "destination_id": destination_id,
		"origin_name": str(source.get("label", "")), "destination_name": str(destination.get("label", "")),
		"progress": clampf(distance / maxf(.001, route_length), 0.0, 1.0),
		"remaining_seconds": ceili(maxf(0.0, route_length - distance) / CRUISE_SPEED + _dwell),
		"camera_mode": camera_mode, "mode": "exterior",
		"riding": riding, "landing": landing}

func handle_input(event: InputEvent) -> bool:
	if not busy(): return false
	if menu_open:
		if event.is_action_pressed("pause_game") or event.is_action_pressed("ui_cancel"):
			close_station_menu()
			return true
		# UI receives pointer, navigation and accept; the session modal owns gameplay.
		return false
	if event.is_action_pressed("pause_game") or (get_tree().paused and event.is_action_pressed("ui_cancel")): return false
	if get_tree().paused: return false
	if event is InputEventJoypadMotion:
		# Direction/aim sticks are owned by this ride, never by the actor.
		return true
	# Buttons remain interactive; consume only gameplay events before other systems.
	if event is InputEventMouseButton or event is InputEventMouseMotion or event is InputEventScreenTouch or event is InputEventScreenDrag: return false
	if not landing:
		if event.is_action_pressed("interact"): skip_trip()
	return not event.is_action("ui_accept") and not event.is_action("ui_left") and not event.is_action("ui_right") and not event.is_action("ui_up") and not event.is_action("ui_down")

func skip_trip() -> void:
	if riding and not landing and not _boarding: _arrive(destination_id)

func cancel_trip() -> void:
	if riding and not landing and not _boarding: _arrive(origin_id)

func _arrive(target_id: String) -> void:
	if not riding or landing: return
	var destination := NETWORK.get_station(target_id)
	if destination.is_empty(): return
	landing = true
	speed = 0.0
	if is_instance_valid(_audio): _audio.stop()
	var generation := _generation
	trip_updated.emit(get_trip_state())
	# The production controller's focus is held by FullSession.has_position_transition
	# during admission, so it cannot unload the destination under this capsule probe.
	var region: Node3D = session.controller._mount_region(str(destination.region), destination.arrival)
	if region == null:
		landing = false
		_arrival_retry = 1.0
		notice.emit("A estação não carregou. A viagem continua disponível.")
		return
	region.set_focus(destination.arrival)
	if is_instance_valid(session.get("railway_world")):
		session.railway_world.set_focus(destination.arrival)
		session.railway_world.ensure_station(target_id)
	for frame in 3:
		await get_tree().physics_frame
		if generation != _generation or not riding: return
	var arrival := _safe_arrival(destination)
	if not arrival.is_finite():
		landing = false
		_arrival_retry = 1.0
		if not _arrival_notice_sent:
			_arrival_notice_sent = true
			notice.emit("Plataforma ocupada. Aguarde e tente chegar novamente.")
		return
	distance = 0.0 if target_id == origin_id else route_length
	_update_train_pose()
	train.set_doors_open(true)
	_parked_station = target_id
	_restore_passenger()
	session.world.player.teleport(arrival)
	session.controller._commit_logical_region(str(destination.region))
	if session.garage_rewards != null: session.garage_rewards.on_location_changed()
	session.sync_dispatch_location()
	riding = false
	landing = false
	_boarding = false
	_ambient_initialized = true
	_start_ambient_leg(target_id, "harbor_north" if target_id != "harbor_north" else "harbor_central")
	session.world.camera.initialized = false
	session.world.camera._process(1.0)
	session._sync_location_presentation()
	trip_finished.emit(target_id)
	notice.emit(str(destination.label))
	session.save_game()

func _safe_arrival(station: Dictionary) -> Vector3:
	var arrival: Vector3 = station.arrival
	# All candidates stay on the authored platform, away from the track and stairs.
	for offset in [Vector3.ZERO, Vector3(0, 0, 1.5), Vector3(0, 0, -1.5), Vector3(0, 0, 3), Vector3(0, 0, -3)]:
		var candidate: Vector3 = arrival + offset
		if session.position_clear(candidate): return candidate
	return Vector3.INF

func _restore_passenger() -> void:
	if _saved.is_empty() or session == null: return
	var actor = session.world.player
	var camera = session.world.camera
	actor.collision_layer = int(_saved.layer)
	actor.collision_mask = int(_saved.mask)
	actor.set_physics_process(bool(_saved.physics))
	actor.visible = bool(_saved.visible)
	actor.input_locked = bool(_saved.locked)
	actor.velocity = Vector3.ZERO
	if bool(_saved.shelter_had): actor.set_meta("mountain_shelter", _saved.shelter)
	else: actor.remove_meta("mountain_shelter")
	camera.target = _saved.camera_target if is_instance_valid(_saved.camera_target) else actor
	camera.offset = _saved.camera_offset
	camera.heading = float(_saved.camera_heading)
	camera.target_size = float(_saved.camera_target_size)
	camera.size = float(_saved.camera_size)
	camera.locked = bool(_saved.camera_locked)
	camera.projection = int(_saved.camera_projection)
	camera.fov = float(_saved.camera_fov)
	camera.near = float(_saved.camera_near)
	camera.far = float(_saved.camera_far)
	camera.global_transform = _saved.camera_transform
	camera.initialized = false
	camera.set_process(bool(_saved.camera_process))
	_set_passenger_depth(false)
	Input.mouse_mode = int(_saved.mouse) as Input.MouseMode
	if session.world.gameplay.health > 0: session.state.equip_weapon(str(_saved.weapon))
	_saved.clear()

func cancel_for_transition() -> void:
	# Death/arrest calls this for every transition, including unrelated doors.
	# Only release state and the fade actually owned by an active railway flow.
	if not busy() and _saved.is_empty(): return
	var owns_fade := _boarding
	_generation += 1
	close_station_menu()
	var was_riding := riding
	_restore_passenger()
	riding = false
	landing = false
	_boarding = false
	_ambient_initialized = false
	if owns_fade and is_instance_valid(session.door_transition): session.door_transition.clear()
	if is_instance_valid(_audio): _audio.stop()
	if was_riding: trip_finished.emit("")

func save_block_reason() -> String:
	return "Desembarque na estação para salvar." if riding or landing else ""

func _ensure_train() -> void:
	if is_instance_valid(train): return
	train = MODEL.new()
	session.world.add_child(train)
	_audio = AudioStreamPlayer3D.new()
	_audio.name = "TrainRollingAudio"
	_audio.stream = _rolling_audio()
	_audio.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	_audio.unit_size = 18.0
	_audio.max_distance = 100.0
	_audio.volume_db = -20.0
	train.add_child(_audio)

func _rolling_audio() -> AudioStreamWAV:
	const RATE := 16000
	const SAMPLES := 16000
	var data := PackedByteArray()
	data.resize(SAMPLES * 2)
	# Deterministic one-second loop, generated once; no DSP loop on the game frame.
	for index in SAMPLES:
		var t := float(index) / RATE
		var motor := sin(TAU * 64.0 * t) * .30 + sin(TAU * 128.0 * t) * .12
		var clack := exp(-fmod(t, .25) * 70.0) * sin(TAU * 760.0 * t) * .28
		var rail := sin(TAU * 347.0 * t) * sin(TAU * 28.0 * t) * .07
		data.encode_s16(index * 2, int((motor + clack + rail) * 23000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = SAMPLES
	stream.data = data
	return stream

func _exit_tree() -> void:
	_generation += 1
	if is_instance_valid(session) and is_instance_valid(session.world) and is_instance_valid(session.world.player) and is_instance_valid(session.world.camera):
		cancel_for_transition()
	if is_instance_valid(train): train.queue_free()
