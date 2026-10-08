extends "res://runtime/railway/RailwayTransit.gd"
## Shares the train's passenger/menu/camera recovery contract. Movement belongs
## to the native road driver, including traffic, signals and swept collision.
const COACH_ROUTES := preload("res://runtime/regional/RegionalCoachRoute.gd")
const COACH := preload("res://runtime/regional/RegionalCoach.gd")
var _road: Curve3D
var _stalled_seconds := 0.0
var _last_road_distance := 0.0
var _travel_notice := false

func _eligible(allow_menu := false) -> bool:
	if not super._eligible(allow_menu): return false
	return session.railway == null or not session.railway.busy()

func _nearby_station() -> Dictionary:
	if session == null: return {}
	for station in COACH_ROUTES.stations():
		if station.region != session.state.region_id: continue
		if session.world.player.global_position.distance_to(station.arrival) < BOARD_RADIUS:
			return station
		# Retain the existing coach boarding points used by older saves/maps.
		var legacy: Vector3 = Vector3(1930,0,1220)/16.0 if station.id == "harbor" else station.road_point
		if station.id != "desert" and session.world.player.global_position.distance_to(legacy) < 3.0:
			return station
	return {}

func station_name(id: String) -> String:
	return str(COACH_ROUTES.station(id).get("label", id))

func nearest_action() -> Dictionary:
	if not can_interact(): return {}
	return {"id":"regional_coach", "target":str(_nearby_station().id), "label":"Viajar de ônibus"}

func destinations(from_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for station in COACH_ROUTES.stations():
		if station.id == from_id: continue
		var available := station_available(station)
		result.append({"id":station.id, "name":station.label, "available":available,
			"locked_reason":"Conclua a última missão da cidade 1.", "duration_seconds":0})
	return result

func travel_to(target: String, instant := false) -> bool:
	if not _eligible(true): return false
	var source := _nearby_station()
	var destination := COACH_ROUTES.station(target)
	if source.is_empty() or destination.is_empty() or str(source.id) == target: return false
	if not station_available(destination):
		notice.emit("Conclua a última missão da cidade 1 para viajar ao deserto.")
		return false
	close_station_menu()
	origin_id = str(source.id)
	destination_id = target
	_snapshot_passenger()
	_generation += 1
	riding = true
	landing = false
	_boarding = true
	camera_mode = 0
	distance = 0.0
	route_length = 0.0
	speed = 0.0
	_stalled_seconds = 0.0
	_last_road_distance = 0.0
	_travel_notice = false
	_arrival_retry = 0.0
	_arrival_notice_sent = false
	var actor = session.world.player
	actor.input_locked = true
	actor.velocity = Vector3.ZERO
	actor.collision_layer = 0
	actor.collision_mask = 0
	actor.set_physics_process(false)
	actor.set_meta("mountain_shelter", true)
	actor.hide()
	session.state.equip_weapon("fists")
	session.world.camera.clear_store_focus()
	_set_passenger_depth(true)
	session.world.camera.locked = true
	session.world.camera.set_process(false)
	if is_instance_valid(session.world.camera.scope_reticle): session.world.camera.scope_reticle.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	trip_started.emit(get_trip_state())
	_board_coach(instant, _generation)
	return true

func _board_coach(instant: bool, generation: int) -> void:
	if is_instance_valid(session.door_transition): await session.door_transition.fade_to(1.0, .23)
	if generation != _generation or not riding: return
	if instant:
		_boarding = false
		await _arrive(destination_id)
		return
	else:
		var plan: Dictionary = COACH_ROUTES.plan(session.controller, origin_id, destination_id)
		if not plan.get("ok", false):
			_abort_boarding("Não há percurso de ônibus disponível entre estas estações.")
			return
		_road = plan.curve
		route_length = _road.get_baked_length()
		var start := _road.sample_baked(0.0, true)
		var region: Node3D = session.controller._mount_region(str(COACH_ROUTES.station(origin_id).region), start)
		if not is_instance_valid(region):
			_abort_boarding("Não foi possível preparar o embarque. Tente novamente.")
			return
		region.set_focus(start)
		region.prepare_collision_at(start)
		for frame in 3:
			await get_tree().physics_frame
			if generation != _generation or not riding: return
		train = COACH.new()
		train.position = start + Vector3.UP * .12
		var tangent := _road.sample_baked(minf(1.0, route_length), true) - start
		train.rotation.y = atan2(-tangent.x, -tangent.z)
		session.world.add_child(train)
		train.set_service_route(_road)
		train.seat_player(session.world.player)
		if train.test_move(train.global_transform, Vector3.UP * .001):
			_abort_boarding("Ponto de embarque ocupado. Aguarde o ônibus liberar a plataforma.")
			return
		_update_train_pose()
		train.reset_physics_interpolation()
	if generation != _generation: return
	if is_instance_valid(session.door_transition): await session.door_transition.fade_to(0.0, .28)
	if generation != _generation or not riding: return
	_boarding = false
	trip_updated.emit(get_trip_state())

func _abort_boarding(message: String) -> void:
	var point: Vector3 = _saved.get("origin_position", session.world.player.global_position)
	cancel_for_transition()
	session.world.player.teleport(point)
	if is_instance_valid(session.door_transition): session.door_transition.clear()
	notice.emit(message)

func _physics_process(delta: float) -> void:
	if session == null or not session.ready_for_play or not riding or landing or _boarding: return
	if session.world.gameplay.health <= 0 or session.rescue_pending or session.arrest_pending:
		cancel_for_transition()
		return
	if _arrival_retry > 0.0:
		_arrival_retry = maxf(0.0, _arrival_retry - delta)
		return
	if not is_instance_valid(train):
		_arrive(destination_id)
		return
	if train.health <= 0:
		session._on_death()
		return
	train.advance(delta)
	distance = train.route_distance
	speed = absf(train.speed)
	_update_train_pose()
	_stalled_seconds = _stalled_seconds + delta if distance - _last_road_distance < .1 * delta else 0.0
	_last_road_distance = distance
	if _stalled_seconds > 25.0 and not _travel_notice:
		_travel_notice = true
		notice.emit("Trânsito parado. Aguarde ou escolha Viagem rápida.")
	_ui_clock += delta
	if _ui_clock >= .1:
		_ui_clock = 0.0
		trip_updated.emit(get_trip_state())
	if train.arrived(): _arrive(destination_id)

func _tick_ambient(_delta: float) -> void:
	pass # Regional coaches exist only for an admitted passenger journey.

func _update_train_pose() -> void:
	if not is_instance_valid(train): return
	train.follow_player(session.world.player)
	_update_camera()

func _update_camera(interpolated := false) -> void:
	if not riding or not is_instance_valid(train) or _saved.is_empty(): return
	var camera = session.world.camera
	var pose: Transform3D = train.get_global_transform_interpolated() if interpolated else train.global_transform
	camera.target = train
	camera.near = .06
	camera.far = 250.0
	if camera_mode == 0:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = 76.0
		camera.global_position = pose * COACH.WINDOW_EYE
		camera.look_at(pose * Vector3(0.0, 1.9, -6.0), Vector3.UP)
	else:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 23.0
		camera.global_position = pose * Vector3(16, 13, 19)
		camera.look_at(pose * Vector3(0, 1.4, 0), Vector3.UP)

func get_trip_state() -> Dictionary:
	return {"origin_id":origin_id, "destination_id":destination_id,
		"origin_name":station_name(origin_id), "destination_name":station_name(destination_id),
		"progress":clampf(distance / maxf(.001, route_length), 0.0, 1.0),
		"remaining_seconds":ceili(maxf(0.0, route_length - distance) / 5.5),
		"camera_mode":camera_mode, "riding":riding, "landing":landing}

func _arrive(target_id: String) -> void:
	if not riding or landing: return
	var destination := COACH_ROUTES.station(target_id)
	if destination.is_empty() or not station_available(destination): return
	landing = true
	var generation := _generation
	if is_instance_valid(session.door_transition): await session.door_transition.fade_to(1.0, .2)
	if generation != _generation or not riding: return
	var region: Node3D = session.controller._mount_region(str(destination.region), destination.arrival)
	if not is_instance_valid(region):
		landing = false
		_arrival_retry = 1.0
		notice.emit("A estação não carregou. Tente concluir a viagem novamente.")
		if is_instance_valid(session.door_transition): await session.door_transition.fade_to(0.0, .2)
		return
	region.set_focus(destination.arrival)
	region.prepare_collision_at(destination.arrival)
	for frame in 3:
		await get_tree().physics_frame
		if generation != _generation or not riding: return
	var arrival := _safe_arrival(destination)
	if not arrival.is_finite():
		landing = false
		_arrival_retry = 1.0
		if not _arrival_notice_sent:
			_arrival_notice_sent = true
			notice.emit("Desembarque ocupado. Aguarde e tente Viagem rápida novamente.")
		if is_instance_valid(session.door_transition): await session.door_transition.fade_to(0.0, .2)
		return
	_restore_passenger()
	session.world.player.teleport(arrival)
	session.controller._commit_logical_region(str(destination.region))
	if session.garage_rewards != null: session.garage_rewards.on_location_changed()
	session.sync_dispatch_location()
	riding = false
	landing = false
	_boarding = false
	_release_coach()
	session.world.camera.initialized = false
	session.world.camera._process(1.0)
	session._sync_location_presentation()
	trip_finished.emit(target_id)
	notice.emit(str(destination.label))
	session.save_game()
	if is_instance_valid(session.door_transition): await session.door_transition.fade_to(0.0, .25)

func cancel_for_transition() -> void:
	var owned_fade := riding or landing or _boarding
	super.cancel_for_transition()
	_release_coach()
	if owned_fade and is_instance_valid(session.door_transition): session.door_transition.clear()

func _restore_passenger() -> void:
	if not _saved.is_empty(): session.world.player.release_seated()
	super._restore_passenger()

func _release_coach() -> void:
	if is_instance_valid(train): train.queue_free()
	train = null
	_road = null

func save_block_reason() -> String:
	return "Desembarque do ônibus para salvar." if riding or landing else ""
