extends Node
## Harbor arrival: a call at home, Maciota at the passenger street exit, then
## a physical ride to his industrial workshop. V1 checkpoints migrate in place.
const DIALOGUE := preload("res://runtime/ArrivalDialogue.gd")
const STORY := preload("res://systems/campaign/HarborStory.gd")
const VERSION := 2
const PARK := Vector3(210, 0, 151)
const ARRIVAL := Vector3(233,.18,194)
const TOUR_CUE_FRACTIONS := [.18,.36,.54,.72]
const FLAGS := ["harbor_arrival_seen", "harbor_arrival_contact_met", "harbor_city_tour_started", "harbor_city_tour_complete", "harbor_maciota_met"]
const PHASES := ["new", "opening", "disembark", "terminal_meeting", "tour_board", "tour_boarding", "city_tour", "meet_maciota", "complete"]
const LEGACY_FLAGS := ["harbor_arrival_seen", "harbor_police_briefed", "harbor_arrival_call_complete", "harbor_city_tour_started", "harbor_city_tour_complete", "harbor_maciota_met"]
const LEGACY_PHASES := ["new", "opening", "disembark", "police_visit", "police_exit", "arrival_wait", "phone", "yard_meeting", "tour_board", "tour_boarding", "city_tour", "meet_maciota", "complete"]
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
var _meeting_started := false
var _legacy_relocated := false
var _narration_hold_started := -1
var _narration_hold_budget := 0.0
var _recovering := false
var _exit_wait := 0.0
var _exit_retry := 0.0
var recovery_reason := ""
var last_exit_plan: Dictionary = {}
var _traffic_crash_pending := false
var crash_resume_count := 0

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
	# A missing take stays captioned. Never synthesize non-verbal tones and
	# present them as the newly written dialogue's dub.
	voice.stream = preload("res://audio/ExpressiveVoice.gd").recorded_line(line.message, "dante" if line.speaker == "DANTE" else "maciota")
	if voice.stream != null: voice.play()
	_dialogue_index += 1
	session.show_dialogue([line], _next_line)

func start_or_resume(loaded: bool = false) -> void:
	if session.state.region_id != "harbor": return
	var story_repaired := opening_completed and STORY.mark_opening(session.state.world_state)
	if flags.get("harbor_maciota_met",false) or (loaded and session.state.intro.stage == "complete"):
		story_repaired = STORY.mark_maciota(session.state.world_state) or story_repaired
	# Existing V2 journeys that predate M00 continue without replaying an opening.
	if loaded and flags.is_empty() and phase in ["new", "complete"]:
		phase = "complete"
		active = false
		if story_repaired: changed.emit()
		return
	active = phase != "complete"
	if not active:
		if story_repaired: changed.emit()
		return
	if flags.get("harbor_city_tour_complete", false): _finish_tour()
	elif flags.get("harbor_arrival_contact_met", false):
		_spawn_encounter()
		if flags.get("harbor_city_tour_started", false):
			session.controller.region.set_focus(PARK)
			for i in 3: await get_tree().physics_frame
			var checkpoint: Vector3 = car.door_point(1)
			if session.position_clear(checkpoint): session.world.player.teleport(checkpoint)
		_set_phase("tour_board", "Entre como passageiro no carro de Maciota.", car.door_point(1))
	elif flags.get("harbor_arrival_seen", false):
		_street_meeting()
		if _legacy_relocated and session.state.place_id.is_empty():
			# A migrated yard checkpoint must resume beside the new public exit,
			# never strand a player at the removed scrapyard meeting.
			session.controller.region.set_focus(PARK)
			for i in 3: await get_tree().physics_frame
			var point: Vector3 = PARK + Vector3(4,.1,2)
			if session.position_clear(point): session.world.player.teleport(point)
			_legacy_relocated = false
	elif opening_completed: _begin_disembark()
	else:
		if not loaded:
			# The playable quay continues the same rainy night as the ferry film.
			# Resuming an existing journey keeps its saved weather and clock.
			session.weather.time_of_day = .94
			session.weather.weather_state = 1
			session.weather.rain_intensity = .25
			session.weather.weather_timer = 180.0
			session.state.world_state.time = .94
			session.state.world_state.weather = 1
			session.state.world_state.rain_intensity = .25
			session.weather._update()
		_begin_opening()
	if story_repaired: changed.emit()

func _begin_opening() -> void:
	if is_instance_valid(presentation): return
	_set_phase("opening", "", Vector3.ZERO)
	_lock(true)
	presentation = preload("res://runtime/OpeningPresentation.gd").new()
	presentation.completed.connect(func(_skipped: bool):
		opening_completed = true
		STORY.mark_opening(session.state.world_state)
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
	_set_phase("disembark", "Desembarque no cais.", ARRIVAL)
	_lock(true)
	var player: CharacterBody3D = session.world.player
	player.set_physics_process(false)
	player.hide()
	player.teleport(ARRIVAL + Vector3.UP * .06)
	session.controller.region.set_focus(ARRIVAL)
	for i in 3: await get_tree().physics_frame
	if not active: return
	var terminal = session.urban_operations.passenger_terminal
	terminal.prepare_arrival()
	await get_tree().physics_frame
	var door: Vector3 = terminal.ARRIVAL
	if not session.position_clear(door):
		_set_phase("disembark", "Aguarde um espaço livre para descer.", ARRIVAL)
		player.show()
		player.set_physics_process(true)
		_lock(false)
		return
	player.teleport(door)
	player.show()
	player.set_physics_process(true)
	if not await _walk(player, ARRIVAL + Vector3.UP * .06, true):
		_lock(false)
		return
	terminal.finish_arrival()
	_milestone("harbor_arrival_seen")
	_lock(false)
	_street_meeting()

func _street_meeting() -> void:
	_spawn_encounter()
	_set_phase("terminal_meeting", "Encontre Maciota na saída do terminal.", PARK)

func _meet() -> void:
	if _meeting_started or session.modal: return
	_meeting_started = true
	_dialogue(DIALOGUE.MEETING, func():
		_meeting_started = false
		_milestone("harbor_arrival_contact_met")
		_set_phase("tour_board", "Entre como passageiro no carro de Maciota.", car.door_point(1)))

func on_location_changed() -> void:
	if not active: return
	if phase == "meet_maciota" and session.state.place_id == "maciota": _hide_encounter_actor()

func _hide_encounter_actor() -> void:
	if not is_instance_valid(maciota): return
	maciota.hide()
	maciota.collision_layer = 0
	maciota.collision_mask = 0
	maciota.set_physics_process(false)

func nearest_action() -> Dictionary:
	if not active or controls_locked or session.modal or session.world.gameplay.health <= 0: return {}
	var point: Vector3 = session.world.player.global_position
	if phase == "disembark": return {"id":"arrival_disembark", "label":"Descer"}
	if phase == "terminal_meeting" and is_instance_valid(maciota) and point.distance_to(maciota.global_position) < 5.3:
		return {"id":"arrival_meeting", "label":"Conversar"}
	if phase == "tour_board" and is_instance_valid(car) and point.distance_to(car.door_point(1)) < 4.375:
		return {"id":"arrival_board", "label":"Entrar como passageiro"}
	return {}

func perform(id: String) -> bool:
	if nearest_action().get("id", "") != id: return false
	match id:
		"arrival_disembark": _begin_disembark()
		"arrival_meeting": _meet()
		"arrival_board": _board()
		_: return false
	return true

func _spawn_encounter() -> void:
	if is_instance_valid(car): return
	car = preload("res://runtime/ArrivalCar.gd").new()
	car.position = PARK + Vector3.UP * .08
	car.rotation.y = 0
	car.set_meta("vehicle_model", "bmw_m8_competition")
	session.world.add_child(car)
	car.set_physics_process(false)
	maciota = preload("res://runtime/ArrivalActor.gd").new()
	maciota.set_meta("invulnerable",true)
	maciota.position = car.door_point(-1) + Vector3(0, 0, .875)
	session.world.add_child(maciota)
	session.world.maciota_place.maciota.hide()

func _build_route() -> Curve3D:
	var graph := preload("res://gameplay/NativeTrafficRoutes.gd").new()
	graph.configure(session.controller.region.roads, 4.0)
	var yard: Vector3 = session.world.maciota_place.tour_parking
	var approach_z: float = session.world.maciota_place.exterior_origin.z+9.3
	var street_start := Vector3(3000,0,2200)/16.0
	var quay_radius := 5.6
	var street_finish := Vector3(188,0,approach_z+quay_radius)
	for road: Dictionary in session.controller.region.roads:
		if str(road.get("id","")) == "dock_street":
			var dock: PackedVector3Array = road.points
			street_start = dock[0] if dock[0].distance_squared_to(PARK)<dock[-1].distance_squared_to(PARK) else dock[-1]
		if str(road.get("id","")) != "quay_boulevard": continue
		var points: PackedVector3Array = road.points
		for index in range(points.size()-1):
			var closest := Geometry3D.get_closest_point_to_segment(street_finish,points[index],points[index+1])
			if absf(closest.z-street_finish.z)<.1: street_finish = closest; break
	# Dock joins Quay beside the terminal. Arrive in its northbound native lane
	# and turn into the west court; requesting a southbound goal forced a city
	# loop and an unrelated pair of closely spaced intersections.
	var street := graph.route_between(street_start,street_finish,Vector3.FORWARD)
	if street == null: return null
	var result := Curve3D.new()
	result.bake_interval = .25
	# Public terminal service apron joins Dock Street. The graph supplies every
	# city junction; only the two off-street parking accesses are hand authored.
	for point in [PARK, Vector3(PARK.x,0,147.0)]:
		result.add_point(point)
	for i in street.point_count: result.add_point(street.get_point_position(i), street.get_point_in(i), street.get_point_out(i))
	# Leave Quay with a quarter-circle instead of crossing directly through the
	# frontage. Depot is west of x170.94; this turn remains east of x180.
	var lane_end := street.get_point_position(street.point_count-1)
	var quay_handle := quay_radius*.55228475
	result.set_point_in(result.point_count-1,Vector3.BACK*quay_handle)
	result.set_point_out(result.point_count-1,Vector3.FORWARD*quay_handle)
	result.set_meta("court_access_start",lane_end)
	result.add_point(Vector3(lane_end.x-quay_radius,0,approach_z),Vector3.RIGHT*quay_handle,Vector3.LEFT*3.0)
	result.add_point(Vector3(175,0,approach_z),Vector3.RIGHT*3.0,Vector3.LEFT*3.0)
	# A quarter-circle turns the full hull into the west bay. Its outer swept
	# corners fit between the frontage (z109.56) and Depot (z112.5), unlike
	# a sharp waypoint turn. The final tangent is north before the stop point.
	var radius := approach_z-yard.z
	var handle := radius*.55228475
	result.add_point(Vector3(yard.x+radius,0,approach_z),Vector3.RIGHT*handle,Vector3.LEFT*handle)
	result.add_point(yard,Vector3.BACK*handle)
	# The native driver's bypass logic reads lane widths/directions from the
	# route. Preserve that public road metadata when adding the two accesses.
	result.set_meta("lane_sections",street.get_meta("lane_sections",[]))
	result.set_meta("lane_index",street.get_meta("lane_index",0))
	result.set_meta("junction_reach",street.get_meta("junction_reach",4.0))
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
	_traffic_crash_pending = false
	_narration_hold_started = -1
	_narration_hold_budget = 0.0
	car.route = route
	car.traffic = true
	car.controlled = true
	_note_car_mode("board")
	_milestone("harbor_city_tour_started")
	_set_phase("city_tour", "Conheça a cidade com Maciota.", session.world.maciota_place.entry_position)

func _walk(actor: CharacterBody3D, destination: Vector3, direct := false) -> bool:
	var generation := _generation
	var was_physics := actor.is_physics_processing()
	actor.set_physics_process(false)
	var path: PackedVector3Array = PackedVector3Array() if direct else session.world.gameplay.find_path(actor.global_position, destination)
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
			stalled = stalled + delta if before.distance_to(actor.global_position) < .001 else 0.0
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
	if not riding and phase in ["terminal_meeting", "tour_board", "tour_boarding"] and is_instance_valid(car):
		var nearby: bool = session.state.place_id.is_empty() and session.world.player.global_position.distance_to(car.global_position) < 48
		var ground := PhysicsRayQueryParameters3D.create(car.global_position + Vector3.UP, car.global_position - Vector3.UP, 1)
		car.set_physics_process(nearby and not car.get_world_3d().direct_space_state.intersect_ray(ground).is_empty())
	if phase == "terminal_meeting" and not controls_locked and not session.modal and session.state.place_id.is_empty() and not session.world.driving.occupied and is_instance_valid(maciota):
		if session.world.player.global_position.distance_to(maciota.global_position) < 8.0: _meet()
	if riding and not is_instance_valid(car):
		_request_ride_recovery("vehicle_removed")
		return
	if not riding: return
	session.world.player.global_position = car.global_position
	if _exit_pending:
		_exit_wait += delta
		_exit_retry -= delta
		if _exit_wait >= 2.0: _request_ride_recovery("unsafe_exit"); return
		if _exit_retry <= 0: cancel_ride()
		return
	if car.health <= 0 or session.world.gameplay.health <= 0: cancel_ride(); return
	# StreetPhysics suspends traffic while its real impact impulse settles, but
	# restores only cars without a controlled driver. This passenger car owns a
	# cinematic driver, so remember that suspension and resume its same route
	# only after the stun ends. Cancellation/death/recovery never resume it.
	if car.get_meta("crash_was_traffic",false) and not _traffic_crash_pending:
		_traffic_crash_pending = true
		_note_car_mode("street_crash_suspended")
	if _traffic_crash_pending and not car.has_meta("crash_stun"):
		_traffic_crash_pending = false
		if phase == "city_tour" and not car.traffic:
			car.brake_input = false
			car.traffic = true
			crash_resume_count += 1
			_note_car_mode("street_crash_finished")
	_caption_wait -= delta
	var caption_distance := route.get_baked_length() * float(TOUR_CUE_FRACTIONS[clampi(_caption+1,0,3)])
	if _caption < 3 and _caption_wait <= 0 and not voice.playing and car.route_distance >= caption_distance:
		_caption += 1
		_caption_wait = 10
		session.show_message("MACIOTA: " + str(DIALOGUE.lines(DIALOGUE.TOUR)[_caption].message))
		session.notice_time = 10
		voice.stream = preload("res://audio/ExpressiveVoice.gd").recorded_line(str(DIALOGUE.lines(DIALOGUE.TOUR)[_caption].message), "maciota")
		if voice.stream != null: voice.play()
		_caption_wait = maxf(7, voice.stream.get_length() if voice.stream != null else 0.0) + 3
		session.notice_time = _caption_wait
	if voice.playing and voice.stream != null:
		# Audio owns its playback clock. Keep the matching caption visible even
		# when frame/physics timing temporarily advances faster than the mixer.
		session.notice_time = maxf(session.notice_time,maxf(0.0,voice.stream.get_length()-voice.get_playback_position())+.35)
	if _at_tour_end():
		# The court is a safe waiting point. Finish every narrated line and its
		# caption before unlocking the player for the workshop conversation.
		if _narration_pending():
			if _narration_hold_started < 0:
				_narration_hold_started = Time.get_ticks_msec()
				_narration_hold_budget = _narration_remaining_seconds()
			return
		if _leave_car():
			_milestone("harbor_city_tour_complete")
			_finish_tour()

func _at_tour_end() -> bool:
	return riding and is_instance_valid(car) and route != null and car.route_distance >= route.get_baked_length()-1.2 and absf(car.speed)<.4

func _narration_pending() -> bool:
	return _caption < DIALOGUE.TOUR.size()-1 or voice.playing or _caption_wait > 0

func _narration_remaining_seconds() -> float:
	var remaining := maxf(0.0,_caption_wait)
	if voice.playing and voice.stream != null:
		remaining = maxf(remaining,voice.stream.get_length()-voice.get_playback_position()+3.0)
	var lines: Array = DIALOGUE.lines(DIALOGUE.TOUR)
	for index in range(_caption+1,lines.size()):
		var stream := preload("res://audio/ExpressiveVoice.gd").recorded_line(str(lines[index].message),"maciota")
		remaining += maxf(7.0,stream.get_length() if stream != null else 0.0)+3.0
	return remaining+1.0

func narration_hold_info() -> Dictionary:
	var elapsed := maxf(0.0,float(Time.get_ticks_msec()-_narration_hold_started)/1000.0) if _narration_hold_started >= 0 else 0.0
	return {"holding":_at_tour_end() and _narration_pending() and _narration_hold_started>=0 and elapsed<=_narration_hold_budget,
		"elapsed":elapsed,"budget":_narration_hold_budget,"caption":_caption,"caption_wait":_caption_wait,
		"voice_playing":voice.playing,"voice_position":voice.get_playback_position(),"voice_length":voice.stream.get_length() if voice.stream != null else 0.0}

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
	_traffic_crash_pending = false
	# Ending this trip also cancels StreetPhysics' pre-impact traffic intent.
	# Keep damage and settling impulses; an empty parked car must not resume it.
	if car.has_meta("crash_was_traffic"): car.remove_meta("crash_was_traffic")
	car.traffic = false
	car.controlled = false
	car.speed = 0
	car.horizontal_velocity = Vector3.ZERO
	_note_car_mode("leave_attempt")
	var passenger := _exit_point(1)
	var driver := _exit_point(-1, passenger)
	var passenger_side := 1
	var driver_side := -1
	# A frontage can block one door even at a valid physical stop. Both people
	# may use the free side only after independent capsule and swept-path checks.
	if not passenger.is_finite():
		passenger_side = -1
		driver = _exit_point(-1)
		passenger = _exit_point(-1,driver)
	elif not driver.is_finite():
		driver_side = 1
		driver = _exit_point(1,passenger)
	if not passenger.is_finite() or not driver.is_finite():
		session.show_message("Aguarde um espaço livre para descer.")
		return false
	last_exit_plan = {"passenger":passenger,"driver":driver,"passenger_side":passenger_side,"driver_side":driver_side}
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
	car.model.door(_exit_door(passenger,passenger_side),true)
	car.model.door(_exit_door(driver,driver_side),true)
	session.world.camera.target = player
	riding = false
	_lock(false)
	return true

func _exit_door(point: Vector3, side: int) -> int:
	var local_z := car.to_local(point).z
	var best := -1
	var distance := INF
	for index in car.model.doors.size():
		var door: Node3D = car.model.doors[index]
		if int(door.get_meta("door_side",0)) != side: continue
		var separation := absf(door.position.z-local_z)
		if separation < distance: best = index; distance = separation
	return best

func cancel_ride() -> bool:
	if not riding: return false
	_note_car_mode("cancel_requested")
	if voice.playing:
		voice.stop()
		# Continue the interrupted line if the passenger boards again.
		_caption = maxi(-1,_caption-1)
	session.notice_time = 0
	if not is_instance_valid(car): _request_ride_recovery("vehicle_removed"); return false
	if not _leave_car():
		if not _exit_pending: _exit_wait = 0.0
		_exit_pending = true
		_exit_retry = .25
		return false
	_caption_wait = .5
	_exit_pending = false
	_set_phase("tour_board", "[E] Voltar ao passageiro para continuar o passeio", car.door_point(1))
	return true

func _finish_tour() -> void:
	# The parked cinematic car has no free-driving controls. Stop its simulation
	# when finished so unloading the city floor cannot make it fall away.
	if is_instance_valid(car): car.set_physics_process(false)
	session.world.maciota_place.maciota.show()
	_set_phase("meet_maciota", "Entre na garagem e converse com Maciota.", session.world.maciota_place.entry_position)
	if is_instance_valid(maciota) and maciota.visible:
		if await _walk(maciota, session.world.maciota_place.entry_position + Vector3(0,0,2)): _hide_encounter_actor()

func notify_maciota_met() -> void:
	if phase != "meet_maciota" or session.state.place_id != "maciota": return
	_milestone("harbor_maciota_met")
	STORY.mark_maciota(session.state.world_state)
	_set_phase("complete", "", Vector3.ZERO)
	active = false
	finished.emit()

func snapshot() -> Dictionary:
	return {"version":VERSION, "phase":phase, "flags":flags.duplicate(), "caption":_caption, "opening_completed":opening_completed}

static func validate_snapshot(data: Dictionary) -> bool:
	var version: Variant = data.get("version")
	# JSON numbers are floats. Array membership compares Variant types, while
	# the version contract accepts the same integral number read from disk.
	if typeof(version) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(version)) or (version != 1 and version != VERSION): return false
	if not data.get("flags") is Dictionary: return false
	var valid_phases: Array = LEGACY_PHASES if version == 1 else PHASES
	var valid_flags: Array = LEGACY_FLAGS if version == 1 else FLAGS
	if data.get("phase") not in valid_phases: return false
	if not data.get("opening_completed", false) is bool: return false
	var caption: Variant = data.get("caption")
	if typeof(caption) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(caption)) or caption != floorf(caption) or caption < -1 or caption > 3: return false
	var gap := false
	for flag in valid_flags:
		if data.flags.has(flag):
			if data.flags[flag] != true or gap: return false
		else: gap = true
	for flag in data.flags:
		if flag not in valid_flags: return false
	var required := {"terminal_meeting":0,"tour_board":1,"tour_boarding":1,"city_tour":2,"meet_maciota":3,"complete":4}
	if version == 1: required = {"police_visit":0,"police_exit":1,"arrival_wait":1,"phone":1,"yard_meeting":2,"tour_board":2,"tour_boarding":2,"city_tour":3,"meet_maciota":4,"complete":5}
	if required.has(data.phase) and not (data.phase == "complete" and data.flags.is_empty()):
		if not data.flags.get(valid_flags[required[data.phase]], false): return false
	return true

func restore_state(data: Dictionary) -> bool:
	if not validate_snapshot(data): return false
	phase = data.phase
	flags = data.flags.duplicate()
	_caption = int(data.caption)
	opening_completed = data.get("opening_completed", false)
	if data.version == 1: _migrate_legacy_checkpoint()
	return true

func _request_ride_recovery(reason: String) -> void:
	if _recovering: return
	_recovering = true
	recovery_reason = reason
	_recover_ride.call_deferred()

func _recover_ride() -> void:
	var old_car = car
	_traffic_crash_pending = false
	_note_car_mode("recover_requested")
	if is_instance_valid(old_car):
		# Delay cleanup while admitting the passenger, without blocking damage.
		old_car.traffic = false
		old_car.controlled = false
		old_car.set_physics_process(false)
	riding = false
	_exit_pending = false
	_generation += 1
	voice.stop()
	voice.stream = null
	session.notice_time = 0
	_caption = -1
	_caption_wait = 4.0
	_narration_hold_started = -1
	car = null
	if is_instance_valid(maciota):
		_hide_encounter_actor()
		maciota.queue_free()
	maciota = null
	route = null
	flags = {"harbor_arrival_seen":true,"harbor_arrival_contact_met":true}
	phase = "tour_board"
	objective_text = "Volte ao carro de Maciota no terminal para continuar."
	target = PARK
	controls_locked = false
	var player: CharacterBody3D = session.world.player
	session.world.camera.target = player
	# A deleted body can leave a clear, supported spot at its last position.
	# Otherwise reuse the existing capsule-admitted rescue flow and its retry UI.
	if session.world.gameplay.health > 0 and session.position_clear(player.global_position):
		player.collision_layer = _player_layer
		player.collision_mask = _player_mask
		player.set_physics_process(true)
		player.show()
		_lock(false)
	elif not session.rescue_pending and not session.respawn_busy:
		session.rescue_camera_heading = session.world.camera.heading
		session.rescue_camera_size = session.world.camera.target_size
		await session._respawn()
	if not is_inside_tree() or not is_instance_valid(session.world.player): return
	if is_instance_valid(old_car): old_car.queue_free()
	_spawn_encounter()
	_set_phase("tour_board","Volte ao carro de Maciota no terminal para continuar.",car.door_point(1))
	_recovering = false

func _note_car_mode(reason: String) -> void:
	if not is_instance_valid(car): return
	car.set_meta("arrival_mode_event",{"reason":reason,"frame":Engine.get_physics_frames(),"phase":phase,"riding":riding,"traffic":car.traffic,"controlled":car.controlled,"health":car.health,"route_distance":car.route_distance,"crash_resume_count":crash_resume_count})

func exit_candidate_diagnostics(side: int, occupied := Vector3.INF) -> Array:
	var result: Array = []
	if not is_instance_valid(car): return result
	var capsule := CapsuleShape3D.new()
	capsule.radius = .32
	capsule.height = 1.7
	var space := car.get_world_3d().direct_space_state
	for lateral in [0.0,.75,1.5,2.5]:
		for along in [0.0,-1.125,1.125]:
			var point: Vector3 = car.to_global(Vector3(side*(car.half_width+.62+lateral),.06,along))
			var start: Vector3 = car.to_global(Vector3(side*(car.half_width+.04),.06,along))
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = capsule
			query.collision_mask = 7
			query.exclude = [session.world.player.get_rid()]
			query.transform = Transform3D(Basis.IDENTITY,point+Vector3.UP*.9)
			var overlap: Array[String] = []
			for hit in space.intersect_shape(query,8):
				overlap.append(str(hit.collider.get_path()) if hit.collider is Node else str(hit.collider))
			var floor_query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*.3,point-Vector3.UP*.5,1)
			var ground: Dictionary = space.intersect_ray(floor_query)
			var excludes: Array[RID] = [session.world.player.get_rid(),car.get_rid()]
			if is_instance_valid(maciota): excludes.append(maciota.get_rid())
			query.exclude = excludes
			query.transform = Transform3D(Basis.IDENTITY,start+Vector3.UP*.86)
			query.motion = point-start
			var swept: PackedFloat32Array = space.cast_motion(query)
			result.append({"point":point,"overlap":overlap,"floor":not ground.is_empty(),"floor_position":ground.get("position",Vector3.INF),
				"sweep_fraction":swept[0],"other_occupant_gap":point.distance_to(occupied) if occupied.is_finite() else -1.0})
	return result

func _migrate_legacy_checkpoint() -> void:
	var old_flags := flags.duplicate()
	flags.clear()
	if old_flags.get("harbor_arrival_seen", false): flags.harbor_arrival_seen = true
	if old_flags.get("harbor_city_tour_started", false):
		flags.harbor_arrival_contact_met = true
		flags.harbor_city_tour_started = true
	if old_flags.get("harbor_city_tour_complete", false): flags.harbor_city_tour_complete = true
	if old_flags.get("harbor_maciota_met", false): flags.harbor_maciota_met = true
	if phase in ["police_visit", "police_exit", "arrival_wait", "phone", "yard_meeting", "tour_board", "tour_boarding", "city_tour"]:
		phase = "tour_board" if flags.get("harbor_arrival_contact_met",false) else "terminal_meeting"
		_legacy_relocated = true
		_caption = -1

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
