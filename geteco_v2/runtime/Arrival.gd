extends Node
## Physical Harbor M00. Its authored opening proves only the canonical prologue;
## the rest of the nine-beat campaign stays independent from the Harbor arc.
const DIALOGUE := preload("res://runtime/ArrivalDialogue.gd")
const PARK := Vector3(-750, 0, 930) / 16.0
const ARRIVAL := Vector3(1700, 0, 1130) / 16.0
const FLAGS := ["harbor_arrival_seen", "harbor_police_briefed", "harbor_arrival_call_complete", "harbor_city_tour_started", "harbor_city_tour_complete", "harbor_maciota_met"]
const PHASES := ["new", "opening", "disembark", "police_visit", "police_exit", "arrival_wait", "phone", "yard_meeting", "tour_board", "tour_boarding", "city_tour", "meet_maciota", "complete"]
signal changed
signal finished
var session
var phase := "new"
var flags: Dictionary = {}
var active := false
var controls_locked := false
var opening_completed := false
var presentation: CanvasLayer
var objective_text := ""
var target := Vector3.ZERO
var car: CharacterBody3D
var maciota: CharacterBody3D
var bus: CharacterBody3D
var route: Curve3D
var riding := false
var _wait := 0.0
var _caption := -1
var _caption_wait := 4.0
var _generation := 0
var _exit_pending := false
var _player_layer := 2
var _player_mask := 7
var _previous_place := ""
var voice: AudioStreamPlayer
var _dialogue_lines: Array = []
var _dialogue_index := 0
var _dialogue_done := Callable()

func configure(owner_session) -> void:
	session = owner_session
	process_mode = Node.PROCESS_MODE_PAUSABLE
	voice = AudioStreamPlayer.new()
	voice.volume_db = -8
	if AudioServer.get_bus_index("SFX") >= 0: voice.bus = "SFX"
	add_child(voice)

func _dialogue(source: Array, done: Callable) -> void:
	_dialogue_lines = DIALOGUE.lines(source)
	_dialogue_index = 0
	_dialogue_done = done
	_next_line()

func _next_line() -> void:
	voice.stop()
	if _dialogue_index >= _dialogue_lines.size():
		var done := _dialogue_done
		_dialogue_done = Callable()
		if done.is_valid(): done.call()
		return
	var line: Dictionary = _dialogue_lines[_dialogue_index]
	voice.stream = preload("res://audio/ExpressiveVoice.gd").line(line.message, "dante" if line.speaker == "DANTE" else "maciota")
	voice.play()
	_dialogue_index += 1
	session.show_dialogue([line], _next_line)

func start_or_resume(loaded: bool = false) -> void:
	if session.state.region_id != "harbor": return
	var canonical_repaired := opening_completed and _complete_canonical_prologue()
	# Existing V2 journeys that predate M00 continue without replaying an opening.
	if loaded and flags.is_empty():
		phase = "complete"
		active = false
		if canonical_repaired: changed.emit()
		return
	active = phase != "complete"
	if not active:
		if canonical_repaired: changed.emit()
		return
	if flags.get("harbor_city_tour_complete", false): _finish_tour()
	elif flags.get("harbor_arrival_call_complete", false):
		_spawn_encounter()
		if flags.get("harbor_city_tour_started", false):
			session.controller.region.set_focus(PARK)
			for i in 3: await get_tree().physics_frame
			var checkpoint: Vector3 = car.door_point(1)
			if session.position_clear(checkpoint): session.world.player.teleport(checkpoint)
		_set_phase("yard_meeting", "Encontre o contato no ferro-velho do Neko. [E] Conversar", PARK)
	elif flags.get("harbor_police_briefed", false):
		_set_phase("police_exit" if session.state.place_id == "harbor_police" else "arrival_wait", "Saia da delegacia." if session.state.place_id == "harbor_police" else "Preciso entender o que aconteceu...", Vector3.ZERO)
	elif flags.get("harbor_arrival_seen", false): _police_visit()
	elif opening_completed: _begin_disembark()
	else: _begin_opening()
	if canonical_repaired: changed.emit()

func _complete_canonical_prologue() -> bool:
	var canonical: Dictionary = session.state.canonical_campaign.snapshot()
	if canonical.completed_beats.has("prologue_call"): return false
	if canonical.current_stage != "prologue_call": return false
	return session.state.canonical_campaign.complete_beat("prologue_call_completed")

func _begin_opening() -> void:
	if is_instance_valid(presentation): return
	_set_phase("opening", "", Vector3.ZERO)
	_lock(true)
	presentation = preload("res://runtime/OpeningPresentation.gd").new()
	presentation.completed.connect(func(_skipped: bool):
		opening_completed = true
		_complete_canonical_prologue()
		changed.emit()
		_begin_disembark())
	add_child(presentation)

func _set_phase(value: String, description: String, point: Vector3) -> void:
	phase = value
	objective_text = description
	target = point
	changed.emit()

func _milestone(id: String) -> void:
	flags[id] = true
	changed.emit()

func _lock(value: bool) -> void:
	controls_locked = value
	if session != null: session.world.player.input_locked = value or session.modal or session.world.gameplay.health <= 0

func _begin_disembark() -> void:
	_set_phase("disembark", "Desça na rodoviária.", ARRIVAL)
	_lock(true)
	var player: CharacterBody3D = session.world.player
	player.set_physics_process(false)
	player.hide()
	player.teleport(ARRIVAL + Vector3.UP * .06)
	session.controller.region.set_focus(ARRIVAL)
	for i in 3: await get_tree().physics_frame
	if not active: return
	if not is_instance_valid(bus):
		bus = preload("res://scripts/Vehicle.gd").new()
		bus.archetype = "route_city"
		bus.position = Vector3(1700, 1, 1250) / 16.0
		bus.rotation.y = -PI / 2
		session.world.add_child(bus)
		bus.remove_from_group("drivable")
		bus.external_input = true
		bus.brake_input = true
	var door: Vector3 = bus.to_global(Vector3(-(bus.half_width + .55), .05, -2.31))
	if not session.position_clear(door):
		_set_phase("disembark", "Aguarde um espaço livre para descer.", ARRIVAL)
		player.show()
		player.set_physics_process(true)
		_lock(false)
		return
	player.teleport(door)
	player.show()
	player.set_physics_process(true)
	if not await _walk(player, Vector3(door.x, door.y, ARRIVAL.z)) or not await _walk(player, ARRIVAL + Vector3.UP * .06):
		_lock(false)
		return
	_milestone("harbor_arrival_seen")
	_lock(false)
	_police_visit()

func _police_visit() -> void:
	var definition := preload("res://world/places/PlaceCatalog.gd").get_definition("harbor_police")
	_set_phase("police_visit", "Vá à delegacia perguntar pelo seu irmão.", definition.entry_position)

func on_location_changed() -> void:
	if not active: return
	if phase == "police_exit" and session.state.place_id.is_empty():
		_wait = 0
		_set_phase("arrival_wait", "Preciso entender o que aconteceu...", Vector3.ZERO)
	if phase == "meet_maciota" and session.state.place_id == "maciota" and is_instance_valid(maciota): maciota.hide()

func nearest_action() -> Dictionary:
	if not active or controls_locked or session.modal or session.world.gameplay.health <= 0: return {}
	var point: Vector3 = session.world.player.global_position
	if phase == "disembark": return {"id":"arrival_disembark", "label":"Descer"}
	if phase == "police_visit" and session.state.place_id == "harbor_police" and is_instance_valid(session.room):
		if point.distance_to(session.room.interaction_points.service) < 1.5: return {"id":"arrival_police", "label":"Perguntar pelo irmão"}
	if phase == "phone": return {"id":"arrival_phone", "label":"Atender"}
	if phase == "yard_meeting" and is_instance_valid(maciota) and point.distance_to(maciota.global_position) < 5.3:
		return {"id":"arrival_meeting", "label":"Conversar"}
	if phase == "tour_board" and is_instance_valid(car) and point.distance_to(car.door_point(1)) < 4.375:
		return {"id":"arrival_board", "label":"Entrar como passageiro"}
	return {}

func perform(id: String) -> bool:
	if nearest_action().get("id", "") != id: return false
	match id:
		"arrival_disembark": _begin_disembark()
		"arrival_police":
			_dialogue(DIALOGUE.POLICE, func():
				_milestone("harbor_police_briefed")
				_set_phase("police_exit", "Saia da delegacia.", session.room.exit_position))
		"arrival_phone":
			_dialogue(DIALOGUE.PHONE, func():
				_milestone("harbor_arrival_call_complete")
				_spawn_encounter()
				_set_phase("yard_meeting", "Encontre o contato no ferro-velho do Neko. [E] Conversar", PARK))
		"arrival_meeting":
			_dialogue(DIALOGUE.MEETING, func():
				_set_phase("tour_board", "[E] Aproxime-se da porta do passageiro para entrar.", car.door_point(1)))
		"arrival_board": _board()
		_: return false
	return true

func _spawn_encounter() -> void:
	if is_instance_valid(car): return
	car = preload("res://runtime/ArrivalCar.gd").new()
	car.position = PARK + Vector3.UP * .08
	car.rotation.y = PI
	session.world.add_child(car)
	car.set_physics_process(false)
	maciota = preload("res://runtime/ArrivalActor.gd").new()
	maciota.position = car.door_point(-1) + Vector3(0, 0, .875)
	session.world.add_child(maciota)
	session.world.maciota_place.maciota.hide()

func _build_route() -> Curve3D:
	var graph := preload("res://gameplay/NativeTrafficRoutes.gd").new()
	graph.configure(session.controller.region.roads, 4.0)
	var entry: Vector3 = session.world.maciota_place.entry_position
	var street := graph.route_between(Vector3(-1180, 0, 1225) / 16.0, entry + Vector3(-250, 0, 120) / 16.0, Vector3.RIGHT)
	if street == null: return null
	var result := Curve3D.new()
	result.bake_interval = .25
	for point in [PARK, Vector3(-750, 0, 1000) / 16.0, Vector3(-1250, 0, 1000) / 16.0, Vector3(-1250, 0, 1225) / 16.0]:
		result.add_point(point)
	for i in street.point_count: result.add_point(street.get_point_position(i), street.get_point_in(i), street.get_point_out(i))
	# Original shallow lane change ends parallel to the frontage, never a U-turn.
	result.set_point_out(result.point_count - 1, Vector3.RIGHT * 5.5)
	result.add_point(entry + Vector3(-70, 0, 45) / 16.0, Vector3.LEFT * 5.5)
	result.set_meta("traffic_open", true)
	result.set_meta("traffic_endpoint", result.get_point_position(result.point_count - 1))
	return result

func _board() -> void:
	if controls_locked or riding or not is_instance_valid(car) or car.health <= 0: return
	if route == null: route = _build_route()
	if route == null:
		session.show_message("Aguarde a rua liberar. [E] Tentar a volta")
		return
	_set_phase("tour_boarding", "", car.door_point(1))
	_lock(true)
	var player: CharacterBody3D = session.world.player
	if not await _walk(player, car.door_point(1)) or not await _walk(maciota, car.door_point(-1)):
		_lock(false)
		_set_phase("tour_board", "[E] Aproxime-se da porta do passageiro para entrar.", car.door_point(1))
		return
	car.model.door(0, true)
	car.model.door(1, true)
	await get_tree().create_timer(.55).timeout
	_player_layer = player.collision_layer
	_player_mask = player.collision_mask
	player.collision_layer = 0
	player.collision_mask = 0
	player.set_physics_process(false)
	player.hide()
	maciota.collision_layer = 0
	maciota.collision_mask = 0
	maciota.hide()
	car.show_occupants(true)
	car.model.door(0, false)
	car.model.door(1, false)
	session.world.camera.target = car
	riding = true
	car.route = route
	car.traffic = true
	car.controlled = true
	_milestone("harbor_city_tour_started")
	_set_phase("city_tour", "Conheça a cidade com Maciota.", session.world.maciota_place.entry_position)

func _walk(actor: CharacterBody3D, destination: Vector3) -> bool:
	var generation := _generation
	var was_physics := actor.is_physics_processing()
	actor.set_physics_process(false)
	var path: PackedVector3Array = session.world.gameplay.find_path(actor.global_position, destination)
	if path.is_empty() or path[-1].distance_to(destination) > .05: path.append(destination)
	var elapsed := 0.0
	var stalled := 0.0
	var limit := actor.global_position.distance_to(destination) / 2.0 + 5
	for point in path:
		while Vector2(actor.global_position.x - point.x, actor.global_position.z - point.z).length() > .12:
			await get_tree().physics_frame
			if generation != _generation or not is_instance_valid(actor): return false
			var delta := get_physics_process_delta_time()
			var before := actor.global_position
			if actor.has_method("walk_step"): actor.walk_step(point, delta)
			else:
				var offset: Vector3 = point - actor.global_position
				offset.y = 0
				actor.velocity = offset.normalized() * minf(3.625, offset.length() / maxf(delta, .001))
				actor.velocity.y = -1
				actor.move_and_slide()
				actor.visual.rotation.y = atan2(-offset.x, -offset.z)
				if actor.animation:
					var animation: Animation = actor.animation.get_animation("Walking")
					actor.phase = fposmod(actor.phase + actor.global_position.distance_to(before) / 1.8, 1)
					actor.animation.play("Walking")
					actor.animation.seek(.067 + actor.phase * maxf(.01, animation.length - .067), true)
					if actor.hips >= 0:
						var hip: Vector3 = actor.skeleton.get_bone_pose_position(actor.hips)
						hip.x = actor.hip_rest.x
						hip.z = actor.hip_rest.z
						actor.skeleton.set_bone_pose_position(actor.hips, hip)
			elapsed += delta
			stalled = stalled + delta if before.distance_to(actor.global_position) < .001 else 0
			if stalled > 2 or elapsed > limit:
				actor.velocity = Vector3.ZERO
				actor.set_physics_process(was_physics)
				return false
	actor.velocity = Vector3.ZERO
	actor.set_physics_process(was_physics)
	return true

func _physics_process(delta: float) -> void:
	if not active or session == null or not session.ready_for_play: return
	if _previous_place != session.state.place_id:
		_previous_place = session.state.place_id
		on_location_changed()
	if not riding and is_instance_valid(car):
		var nearby: bool = session.state.place_id.is_empty() and session.world.player.global_position.distance_to(car.global_position) < 48
		var ground := PhysicsRayQueryParameters3D.create(car.global_position + Vector3.UP, car.global_position - Vector3.UP, 1)
		car.set_physics_process(nearby and not car.get_world_3d().direct_space_state.intersect_ray(ground).is_empty())
	if phase == "arrival_wait" and not session.modal and not session.world.driving.occupied:
		_wait += delta
		if _wait >= 4:
			_set_phase("phone", "Ligação recebida. [E] Atender", Vector3.ZERO)
			voice.stream = DIALOGUE.phone_ring()
			voice.play()
	if not riding or not is_instance_valid(car): return
	session.world.player.global_position = car.global_position
	_caption_wait -= delta
	if _caption < 3 and _caption_wait <= 0 and not voice.playing and car.distance_travelled >= (_caption + 1) * 37.5:
		_caption += 1
		_caption_wait = 10
		session.show_message("MACIOTA: " + str(DIALOGUE.lines(DIALOGUE.TOUR)[_caption].message))
		session.notice_time = 10
		voice.stream = preload("res://audio/ExpressiveVoice.gd").line(str(DIALOGUE.lines(DIALOGUE.TOUR)[_caption].message), "maciota")
		voice.play()
		_caption_wait = maxf(7, voice.stream.get_length()) + 3
		session.notice_time = _caption_wait
	if _exit_pending: cancel_ride(); return
	if car.health <= 0 or session.world.gameplay.health <= 0: cancel_ride(); return
	if car.route_distance >= route.get_baked_length() - 1.2 and absf(car.speed) < .4:
		if _leave_car():
			_milestone("harbor_city_tour_complete")
			_finish_tour()

func _exit_point(side: int, occupied := Vector3.INF) -> Vector3:
	for lateral in [0.0, .75, 1.5, 2.5]:
		for along in [0.0, -1.125, 1.125]:
			var point: Vector3 = car.to_global(Vector3(side * (car.half_width + .62 + lateral), .06, along))
			if occupied.is_finite() and occupied.distance_to(point) < 1: continue
			if not session.position_clear(point): continue
			var capsule := CapsuleShape3D.new()
			capsule.radius = .32
			capsule.height = 1.7
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = capsule
			query.collision_mask = 7
			query.exclude = [car.get_rid(), session.world.player.get_rid(), maciota.get_rid()]
			var start: Vector3 = car.to_global(Vector3(side * (car.half_width + .04), .06, along))
			query.transform = Transform3D(Basis.IDENTITY, start + Vector3.UP * .86)
			query.motion = point - start
			var sweep: PackedFloat32Array = car.get_world_3d().direct_space_state.cast_motion(query)
			if sweep[0] >= 1: return point
	return Vector3.INF

func _leave_car() -> bool:
	car.traffic = false
	car.controlled = false
	car.speed = 0
	car.horizontal_velocity = Vector3.ZERO
	var passenger := _exit_point(1)
	var driver := _exit_point(-1, passenger)
	if not passenger.is_finite() or not driver.is_finite():
		session.show_message("Aguarde um espaço livre para descer.")
		return false
	var player: CharacterBody3D = session.world.player
	player.teleport(passenger)
	player.collision_layer = _player_layer
	player.collision_mask = _player_mask
	player.set_physics_process(true)
	player.show()
	maciota.global_position = driver
	maciota.collision_layer = 2
	maciota.collision_mask = 7
	maciota.show()
	car.show_occupants(false)
	car.model.door(0, true)
	car.model.door(1, true)
	session.world.camera.target = player
	riding = false
	_lock(false)
	return true

func cancel_ride() -> bool:
	if not riding: return false
	if not _leave_car(): _exit_pending = true; return false
	_exit_pending = false
	_set_phase("tour_board", "[E] Voltar ao passageiro para continuar o passeio", car.door_point(1))
	return true

func _finish_tour() -> void:
	session.world.maciota_place.maciota.show()
	_set_phase("meet_maciota", "Entre na garagem e converse com Maciota.", session.world.maciota_place.entry_position)
	if is_instance_valid(maciota) and maciota.visible:
		if await _walk(maciota, session.world.maciota_place.entry_position + Vector3(0,0,2)): maciota.hide()

func notify_maciota_met() -> void:
	if phase != "meet_maciota" or session.state.place_id != "maciota": return
	_milestone("harbor_maciota_met")
	_set_phase("complete", "", Vector3.ZERO)
	active = false
	finished.emit()

func snapshot() -> Dictionary:
	return {"version":1, "phase":phase, "flags":flags.duplicate(), "caption":_caption, "opening_completed":opening_completed}

static func validate_snapshot(data: Dictionary) -> bool:
	if data.get("version") != 1 or data.get("phase") not in PHASES or not data.get("flags") is Dictionary: return false
	if not data.get("opening_completed", false) is bool: return false
	var caption: Variant = data.get("caption")
	if typeof(caption) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(caption)) or caption != floorf(caption) or caption < -1 or caption > 3: return false
	var gap := false
	for flag in FLAGS:
		if data.flags.has(flag):
			if data.flags[flag] != true or gap: return false
		else: gap = true
	for flag in data.flags:
		if flag not in FLAGS: return false
	var required := {"police_visit":0,"police_exit":1,"arrival_wait":1,"phone":1,"yard_meeting":2,"tour_board":2,"tour_boarding":2,"city_tour":3,"meet_maciota":4,"complete":5}
	if required.has(data.phase) and not (data.phase == "complete" and data.flags.is_empty()):
		if not data.flags.get(FLAGS[required[data.phase]], false): return false
	return true

func restore_state(data: Dictionary) -> bool:
	if not validate_snapshot(data): return false
	phase = data.phase
	flags = data.flags.duplicate()
	_caption = int(data.caption)
	opening_completed = data.get("opening_completed", false)
	return true

func _exit_tree() -> void:
	_generation += 1
	_dialogue_done = Callable()
	if is_instance_valid(voice): voice.stop(); voice.stream = null
	if riding and session != null and is_instance_valid(session.world.player):
		var player: CharacterBody3D = session.world.player
		player.collision_layer = _player_layer
		player.collision_mask = _player_mask
		player.show()
		player.set_physics_process(true)
		_lock(false)
	for actor in [car, maciota, bus]:
		if is_instance_valid(actor): actor.queue_free()
