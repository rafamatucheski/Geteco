extends Node3D
## The vehicle bodies remain authoritative for crossings and obstruction.
## The shared powertrain produces acceleration, RPM, shifts, nitro and audio.
const PROGRESS := preload("res://activities/desert_drag/DesertDragProgress.gd")
const HUD := preload("res://activities/desert_drag/DesertDragHUD.gd")
const POWERTRAIN := preload("res://gameplay/desert_cars/DesertDrivetrain.gd")
const CARS := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
const AUDIO := preload("res://audio/desert_cars/DesertCarAudio.gd")
const DRIVER := preload("res://activities/desert_drag/DesertDragDriver.gd")
const SIGNALS := preload("res://activities/desert_drag/DesertDragSignals.gd")
# One authored half-mile strip for every round. Mechanical timing tests place
# stock cars at ~20–25 s and the fastest full build above 15 s at 800 m.
# Difficulty comes from the rival/preparation, never a synthetic speed cap.
const RIVALS := {
	"digo":{"name":"Digo","car":"digo_gol_1993","distance":800.0,"reaction":.32,"mistake":.14,"parts":{}},
	"livia":{"name":"Lívia","car":"desert_faisca_rally","distance":800.0,"reaction":.24,"mistake":.10,"parts":{}},
	"raul":{"name":"Raul","car":"desert_coyote_drag","distance":800.0,"reaction":.20,"mistake":.08,"parts":{}},
	"jessica":{"name":"Jessica","car":"jessica_jetta_gli","distance":800.0,"reaction":.14,"mistake":.025,"parts":{}},
	"nadir":{"name":"Nadir","car":"desert_mirage_gt","distance":800.0,"reaction":.18,"mistake":.06,"parts":{}},
}
signal race_completed(result: Dictionary)
var session
var start_point := Vector3(-1140, .08, -1280)
var direction := Vector3.RIGHT
var staging_point := Vector3(-1150, 0, -1264)
var active := false
var phase := ""
var countdown := 0.0
var elapsed := 0.0
var distance := 800.0
var racers: Array[Dictionary] = []
var player_car
var last_result: Dictionary = {}
var rival_id := ""
var race_camera: Camera3D
var previous_camera: Camera3D
var race_listener: AudioListener3D
var previous_listener: AudioListener3D
var hud: Control
var layer: CanvasLayer
var signals: Node3D
var _saved: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _rival_wait := 0.0
var _rival_shift_delay := 0.0
var _rival_target := 0.0
var _runoff := 0.0
var _hud_clock := 0.0
var _feedback := ""
var _feedback_time := 0.0
var _old_camera_lock := false
var _throttle_override := -1.0
var _nitro_override := false

func configure(owner_session, strip_start: Vector3 = Vector3(-1140,0,-1280), forward: Vector3 = Vector3.RIGHT) -> void:
	session = owner_session
	start_point = strip_start+Vector3.UP*.08
	direction = Vector3(forward.x,0,forward.z).normalized()
	process_physics_priority = -5
	set_physics_process(false)
	set_process_input(false)
	if not PROGRESS.validate_snapshot(snapshot()):
		session.controller.save_invalid = true
		session.show_message("Progresso do drag inválido; save preservado.")

func snapshot() -> Dictionary:
	return PROGRESS.data(session.state.world_state)

func is_night() -> bool:
	var time: float = session.weather.time_of_day if is_instance_valid(session.weather) else float(session.state.world_state.get("time", .32))
	return time >= 20.0/24.0 or time < 5.0/24.0

func save_block_reason() -> String:
	return "Encerre a arrancada para salvar." if active else ""

func objective() -> String:
	if active and is_instance_valid(player_car): return "Drag · %s · %d m"%[RIVALS[rival_id].name,ceili(maxf(0,distance-_offset(player_car.global_position)))]
	return "Arrancadas do deserto · 20h–5h"

func target_position() -> Vector3:
	return start_point+direction*distance if active else staging_point

func nearest_action() -> Dictionary:
	if not is_instance_valid(session): return {}
	if active: return {"id":"desert_drag","target":"cancel","label":"Abandonar arrancada"}
	if not session.ready_for_play or session.controller.save_invalid or session.state.region_id != "desert" or not session.state.place_id.is_empty(): return {}
	var point: Vector3 = session.world.player.global_position
	if session.world.driving.occupied and is_instance_valid(session.world.driving.car): point = session.world.driving.car.global_position
	if point.distance_to(staging_point)>15 and point.distance_to(start_point)>12: return {}
	var current := PROGRESS.current_rival(session.state.world_state)
	return {"id":"desert_drag","target":"start","label":"Drag contra %s · %d m"%[RIVALS[current].name,RIVALS[current].distance] if is_night() else "Drag · aguarde 20h–5h"}

func start_block_reason() -> String:
	if active: return "A arrancada já começou."
	if session.controller.save_invalid: return "Save inválido preservado; atividade indisponível."
	if not session.ready_for_play or session.modal or session.get_tree().paused or session.is_transition_blocked(): return "Aguarde o fim da atividade atual."
	if session.state.intro.stage != "complete": return "Conclua a chegada antes de correr."
	if session.state.region_id != "desert" or not session.state.place_id.is_empty() or nearest_action().is_empty(): return "Vá à largada do deserto."
	if not is_night(): return "As arrancadas acontecem entre 20h e 5h."
	if session.world.gameplay.health <= 0 or session.rescue_pending or session.arrest_pending: return "Aguarde a recuperação."
	if session.world.gameplay.stars > 0: return "Despiste a polícia antes da largada."
	if not session.state.campaign.active_id.is_empty(): return "Conclua a missão atual antes da arrancada."
	if session.activities != null and not session.activities.can_rest(): return "Encerre a atividade atual antes da arrancada."
	var driving = session.world.driving
	if not driving.occupied or not is_instance_valid(driving.car): return "Entre em um carro para correr."
	var car = driving.car
	if car.health <= 0 or car.engine_disabled or car.half_width > 1.45 or car.half_length > 3.1: return "Use um carro em condições de correr."
	if car.input_locked or car.external_input or absf(car.speed)>1.0: return "Pare o carro na concentração."
	return ""

func perform(target: String) -> bool:
	if target == "cancel" and active:
		cancel_attempt()
		return true
	if target != "start": return false
	var reason := start_block_reason()
	if not reason.is_empty():
		session.show_message(reason)
		return false
	return _start()

func grid(index: int) -> Transform3D:
	var right := direction.cross(Vector3.UP).normalized()
	return Transform3D(Basis.looking_at(direction,Vector3.UP),start_point+right*(2.0 if index==0 else -2.0))

func _start() -> bool:
	player_car = session.world.driving.car
	rival_id = PROGRESS.current_rival(session.state.world_state)
	var config: Dictionary = RIVALS[rival_id]
	distance = float(config.distance)
	var player_pose := grid(0)
	var opponent_pose := grid(1)
	var production = session.world.production
	if not production.vehicle_position_clear(player_car,player_pose.origin,player_pose.basis.get_euler().y):
		session.show_message("Libere as faixas antes de alinhar.")
		return false
	var opponent = production.spawn_vehicle(str(config.car),opponent_pose.origin,opponent_pose.basis.get_euler().y)
	if not is_instance_valid(opponent):
		session.show_message("Aguarde a pista ficar livre.")
		return false
	opponent.set_meta("race_owned",true)
	opponent.set_meta("desert_drag_rival",true)
	opponent.vehicle_id = "desert_drag_"+rival_id+"_"+str(Time.get_ticks_usec())
	if opponent.get_meta("awaiting_ground",false) or not production.vehicle_position_clear(opponent,opponent_pose.origin,opponent_pose.basis.get_euler().y):
		opponent.queue_free()
		session.show_message("Aguarde a pista carregar e tente novamente.")
		return false
	DRIVER.attach(opponent,rival_id)
	_saved = {"physics":player_car.is_physics_processing(),"locked":player_car.input_locked,"controlled":player_car.controlled,"external":player_car.external_input,"player_locked":session.world.player.input_locked}
	previous_camera = get_viewport().get_camera_3d()
	previous_listener = get_viewport().get_audio_listener_3d()
	_old_camera_lock = session.world.camera.locked
	session.world.camera.locked = true
	player_car.place(player_pose.origin,player_pose.basis.get_euler().y)
	session.world.player.input_locked = true
	racers.clear()
	for i in 2:
		var car = player_car if i==0 else opponent
		var drive := POWERTRAIN.new()
		drive.configure(CARS.profile_for_vehicle(car),CARS.parts_for_vehicle(car) if i==0 else _rival_parts())
		drive.reset()
		car.input_locked = true
		car.set_physics_process(false)
		car.set_meta("desert_drag_physics",true)
		car.speed = 0.0
		car.velocity = Vector3.ZERO
		car.horizontal_velocity = Vector3.ZERO
		var previous_power: Variant = car.get_meta("desert_powertrain") if car.has_meta("desert_powertrain") else null
		car.set_meta("desert_powertrain",drive)
		var sound: Node = car.get_node_or_null("DesertCarAudio")
		var existing_sound := is_instance_valid(sound)
		var previous_audio: Variant = sound.drivetrain if existing_sound else null
		if not existing_sound: sound = AUDIO.new()
		sound.bind(car,drive)
		if not existing_sound: car.add_child(sound)
		var equipment = car.ensure_equipment(session.world)
		var was_lit: bool = equipment.headlights_on if is_instance_valid(equipment) else false
		if is_instance_valid(equipment): equipment.headlights_on = true
		racers.append({"car":car,"drive":drive,"sound":sound,"finish":INF,"was_lit":was_lit,"travel":0.0,"previous_power":previous_power,"existing_sound":existing_sound,"previous_audio":previous_audio})
	active = true
	phase = "staging"
	countdown = 3.0
	elapsed = 0
	_runoff = 0
	last_result = {}
	_rng.randomize()
	_rival_wait = float(config.reaction)+_rng.randf_range(-.035,.06)
	_rival_target = racers[1].drive.ideal_shift_rpm
	_rival_shift_delay = -1
	_feedback = "Acelere para preparar o giro"
	_feedback_time = 3.0
	race_camera = Camera3D.new()
	race_camera.name = "DesertDragSideCamera"
	race_camera.fov = 57
	race_camera.far = 2200
	race_camera.near = .2
	add_child(race_camera)
	_update_camera(0)
	race_camera.make_current()
	# Camera framing widens with the lead, but Dante keeps hearing his own
	# engine from the cabin. The opponent retains physical distance/panning.
	race_listener = AudioListener3D.new()
	race_listener.name = "DesertDragListener"
	race_listener.position = Vector3(0,1.0,0)
	player_car.add_child(race_listener)
	race_listener.make_current()
	layer = CanvasLayer.new()
	layer.layer = 35
	add_child(layer)
	hud = HUD.new()
	# Fill the instruments before entering the tree: the first rendered staging
	# frame must already show the real opponent, distance and launch RPM band.
	hud.update_state(racers[0].drive,distance,0.0,0.0,str(ceili(countdown)),str(config.name))
	hud.feedback = _feedback
	layer.add_child(hud)
	signals = SIGNALS.new()
	add_child(signals)
	signals.configure(start_point,direction,distance)
	set_physics_process(true)
	set_process_input(true)
	_refresh_session_hud()
	return true

func _rival_parts() -> Dictionary:
	# Same purchasable catalogue and rules as Dante; no catch-up velocity.
	match rival_id:
		"raul": return {"engine":"street_cam","tires":"drag_tires"}
		"jessica": return {"engine":"race_cam","turbo":"turbo_large","nitro":"nitro_race","tires":"drag_tires","weight":"lightweight"}
		"nadir": return {"engine":"race_cam","turbo":"turbo_small","nitro":"nitro_street","tires":"drag_tires"}
	return {}

func _input(event: InputEvent) -> void:
	if not active or session.modal or get_tree().paused: return
	var shift := false
	var cancel := false
	if event is InputEventKey and event.pressed and not event.echo:
		shift = event.physical_keycode == KEY_SPACE
		cancel = event.physical_keycode == KEY_Q
	elif event is InputEventJoypadButton and event.pressed:
		shift = event.button_index == JOY_BUTTON_RIGHT_SHOULDER
		cancel = event.button_index == JOY_BUTTON_B
	if cancel:
		cancel_attempt()
		get_viewport().set_input_as_handled()
	elif shift:
		request_shift()
		get_viewport().set_input_as_handled()

func request_shift() -> String:
	if not active or session.modal or get_tree().paused: return "blocked"
	if phase == "staging":
		cancel_attempt("false_start")
		return "false_start"
	if phase != "racing": return "blocked"
	var outcome: String = racers[0].drive.shift_up()
	_feedback = {"perfect":"Troca perfeita", "good":"Boa troca", "early":"Troca antecipada", "late":"Troca atrasada", "max":"Última marcha"}.get(outcome,outcome)
	_feedback_time = 1.2
	return outcome

func _physics_process(delta: float) -> void:
	if not active: return
	var interruption := _interruption()
	if not interruption.is_empty(): cancel_attempt(interruption); return
	player_car.input_locked = true
	session.world.player.input_locked = true
	if session.modal: return
	var throttle := _throttle()
	if phase == "staging":
		racers[0].drive.stage(delta,throttle)
		# Rivals feather the throttle toward their own launch band.
		var other = racers[1].drive
		other.stage(delta,1.0 if other.rpm < other.redline*.57 else 0.0)
		countdown = maxf(0,countdown-delta)
		signals.set_countdown(countdown)
		if countdown <= 0:
			phase = "racing"
			_feedback = "LARGOU · "+str(racers[0].drive.launch())
			_feedback_time = 1.3
			other.launch()
	elif phase == "racing":
		var before_elapsed := elapsed
		elapsed += delta
		_rival_control(delta)
		for i in 2:
			var entry: Dictionary = racers[i]
			var drive = entry.drive
			var throttle_value: float = throttle if i==0 else (1.0 if elapsed>=_rival_wait else 0.0)
			var nitro_value: bool = _nitro() if i==0 else (drive.gear>=3 and elapsed>6.0)
			var crossed := is_finite(float(entry.finish))
			drive.step(delta,0.0 if crossed else throttle_value,not crossed and nitro_value,1.0 if crossed else _brake() if i==0 else 0.0)
			var before := _offset(entry.car.global_position)
			_move_car(entry,delta)
			var after := _offset(entry.car.global_position)
			if not crossed:
				entry.finish = PROGRESS.crossing_time(before,after,distance,before_elapsed,delta)
			if entry.car.global_position.y < start_point.y-3:
				cancel_attempt("unsupported_track")
				return
		if is_finite(float(racers[0].finish)) and is_finite(float(racers[1].finish)):
			phase = "braking"
		elif elapsed > 60 or elapsed > minf(float(racers[0].finish),float(racers[1].finish))+8.0:
			if is_finite(float(racers[0].finish)): phase = "braking"
			else: cancel_attempt("timeout"); return
	elif phase == "braking":
		_runoff += delta
		for entry in racers:
			entry.drive.step(delta,0,false,1)
			_move_car(entry,delta)
		if _runoff>8 or racers.all(func(e): return e.drive.speed_mps<.6):
			_finish()
			return
	_feedback_time = maxf(0,_feedback_time-delta)
	_update_camera(delta)
	_hud_clock -= delta
	if _hud_clock<=0:
		_hud_clock = .05
		var title := str(ceili(countdown)) if phase=="staging" else ("FREANDO" if phase=="braking" else "")
		hud.feedback = _feedback if _feedback_time>0 else ""
		hud.update_state(racers[0].drive,distance-_offset(player_car.global_position),elapsed,_offset(player_car.global_position)-_offset(racers[1].car.global_position),title,str(RIVALS[rival_id].name))

func _rival_control(delta: float) -> void:
	var drive = racers[1].drive
	if drive.rpm < _rival_target or elapsed < _rival_wait: return
	if _rival_shift_delay < 0:
		_rival_shift_delay = _rng.randf_range(.015,.07)
		if _rng.randf() < float(RIVALS[rival_id].mistake): _rival_shift_delay += _rng.randf_range(.14,.32)
	_rival_shift_delay -= delta
	if _rival_shift_delay <= 0:
		drive.shift_up()
		_rival_target = drive.ideal_shift_rpm+_rng.randf_range(-120,110)
		_rival_shift_delay = -1

func _move_car(entry: Dictionary, delta: float) -> void:
	var car = entry.car
	var drive = entry.drive
	var offset := _offset(car.global_position)
	# A bounded deceleration zone prevents an already finished vehicle leaving
	# the authored strip. This is braking force, never a position teleport.
	if is_finite(float(entry.finish)):
		var room := maxf(0,distance+175-offset)
		drive.speed_mps = minf(drive.speed_mps,sqrt(2.0*15.0*room))
	var before: Vector3 = car.global_position
	var incoming_velocity: Vector3 = direction*drive.speed_mps
	# At 200+ km/h, never outrun the next streamed collision cell. The shared
	# persistent-support pass retains these two admitted cars between updates.
	var region: Node3D = session.world.production.regions.get("desert")
	if is_instance_valid(region):
		var next_point: Vector3 = before+direction*(drive.speed_mps*delta+float(car.half_length)+1.0)
		if not region.prepare_collision_at(next_point):
			drive.speed_mps = 0
			car.velocity = Vector3.ZERO
			return
	car.velocity = direction*drive.speed_mps + Vector3.UP*(car.velocity.y-18*delta)
	car.move_and_slide()
	var moved: Vector3 = car.global_position-before
	var actual := maxf(0,moved.dot(direction)/maxf(.001,delta))
	if actual+1.0 < drive.speed_mps: drive.speed_mps = actual
	car.speed = actual
	car.horizontal_velocity = direction*actual
	car.throttle_input = drive.throttle
	car.brake_input = is_finite(float(entry.finish))
	car.wheel_spin += moved.dot(direction)/.355
	for wheel in car.wheels: wheel.rotation.x = car.wheel_spin
	car.distance_travelled += moved.length()
	entry.travel += moved.dot(direction)
	if is_instance_valid(car.effects): car.effects.physics_tick(delta,incoming_velocity)

func _update_camera(_delta: float) -> void:
	if not is_instance_valid(race_camera) or racers.size()!=2: return
	var a: Vector3 = racers[0].car.global_position
	var b: Vector3 = racers[1].car.global_position
	var frame := camera_frame(a,b)
	race_camera.global_position = frame.position
	race_camera.look_at(frame.target,Vector3.UP)
	if is_instance_valid(hud):
		var screen := race_camera.unproject_position(b+Vector3.UP*.7)
		var width := get_viewport().get_visible_rect().size.x
		hud.rival_offscreen = -1 if screen.x<65 else (1 if screen.x>width-65 else 0)
		if race_camera.is_position_behind(b): hud.rival_offscreen = -1 if (a-b).dot(direction)>0 else 1

func camera_frame(a: Vector3, b: Vector3) -> Dictionary:
	var signed_gap := (b-a).dot(direction)
	var side := direction.cross(Vector3.UP).normalized()
	# Midpoint framing while close; bounded look-back keeps Dante readable when a
	# legitimate lead grows. No car pose, drivetrain, result or rival pace is changed.
	var center := a+direction*clampf(signed_gap*.5,-10.0,10.0)+side*((b-a).dot(side)*.5)+Vector3.UP*.75
	var setback := clampf(18.0+maxf(0,absf(signed_gap)-12.0)*.28,18.0,27.0)
	return {"target":center,"position":center+side*setback-direction*4.0+Vector3.UP*3.2,"setback":setback}

func _offset(point: Vector3) -> float:
	return (point-start_point).dot(direction)

func _throttle() -> float:
	if _throttle_override>=0: return _throttle_override
	var result := 1.0 if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP) else 0.0
	for device in Input.get_connected_joypads(): result = maxf(result,Input.get_joy_axis(device,JOY_AXIS_TRIGGER_RIGHT))
	return clampf(result,0,1)

func _nitro() -> bool:
	if _throttle_override>=0: return _nitro_override
	if Input.is_physical_key_pressed(KEY_SHIFT): return true
	for device in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(device,JOY_BUTTON_A): return true
	return false

func _brake() -> float:
	return 1.0 if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN) else 0.0

func _interruption() -> String:
	if session.world.gameplay.health<=0 or session.rescue_pending: return "player_death"
	if session.arrest_pending: return "player_arrest"
	if not session.ready_for_play or session.is_transition_blocked(): return "world_transition"
	if session.state.region_id!="desert" or not session.state.place_id.is_empty(): return "region_changed"
	if not is_instance_valid(player_car) or player_car.health<=0 or player_car.engine_disabled: return "vehicle_broken"
	if not session.world.driving.occupied or session.world.driving.car!=player_car: return "vehicle_left"
	if racers.size()!=2 or not is_instance_valid(racers[1].car) or racers[1].car.health<=0: return "rival_interrupted"
	return ""

func _finish() -> void:
	var player_time: float = racers[0].finish
	var other_time: float = racers[1].finish
	var result := PROGRESS.record_finish(session.state.world_state,rival_id,player_time<other_time,player_time)
	result["rival_seconds"] = other_time if is_finite(other_time) else -1.0
	last_result = result
	_cleanup()
	if not result.get("finished",false): return
	race_completed.emit(result)
	session.show_message("%s · %.3f s · %s"%["Vitória" if result.won else "Derrota",player_time,RIVALS[rival_id].name])
	session.save_game()

func cancel_attempt(reason: String = "cancelled") -> void:
	if not active: return
	last_result = {"finished":false,"reason":reason}
	_cleanup()
	if reason == "false_start" and is_instance_valid(session): session.show_message("Queimou a largada. Espere o sinal verde para trocar a marcha.")
	elif reason in ["cancelled","timeout","unsupported_track"] and is_instance_valid(session): session.show_message("Arrancada interrompida. Volte à concentração para tentar novamente.")

func _cleanup() -> void:
	active = false
	phase = ""
	set_physics_process(false)
	set_process_input(false)
	if is_instance_valid(race_listener):
		if race_listener.is_current():
			race_listener.clear_current()
			if is_instance_valid(previous_listener): previous_listener.make_current()
		race_listener.queue_free()
	elif is_instance_valid(previous_listener) and get_viewport().get_audio_listener_3d()==null:
		previous_listener.make_current()
	for entry in racers:
		if is_instance_valid(entry.sound):
			if entry.existing_sound and is_instance_valid(entry.car): entry.sound.bind(entry.car,entry.previous_audio)
			else: entry.sound.queue_free()
		if not is_instance_valid(entry.car): continue
		var car = entry.car
		car.remove_meta("desert_drag_physics")
		if entry.previous_power != null: car.set_meta("desert_powertrain",entry.previous_power)
		else: car.remove_meta("desert_powertrain")
		car.velocity = Vector3.ZERO
		car.horizontal_velocity = Vector3.ZERO
		car.speed = 0
		car.throttle_input = 0
		car.brake_input = false
		if is_instance_valid(car.equipment): car.equipment.headlights_on = entry.was_lit
		if car == player_car:
			car.set_physics_process(bool(_saved.get("physics",true)))
			car.input_locked = bool(_saved.get("locked",false)) or (is_instance_valid(session) and session.modal)
			if car.health>0 and is_instance_valid(session) and session.world.gameplay.health>0 and not session.rescue_pending and not session.arrest_pending:
				car.controlled = bool(_saved.get("controlled",true)) and session.world.driving.occupied and session.world.driving.car==car
				car.external_input = bool(_saved.get("external",false))
		else:
			# A concurrent takeover must not delete the car beneath its occupant.
			if is_instance_valid(session) and session.world.driving.occupied and session.world.driving.car==car:
				car.remove_meta("race_owned")
				car.remove_meta("desert_drag_rival")
				car.set_physics_process(true)
				car.set_external_driver(false)
				car.controlled = car.health>0
				car.input_locked = session.modal
				var driver: Node = car.get_node_or_null("DragRivalDriver")
				if is_instance_valid(driver): driver.queue_free()
			else: car.queue_free()
	racers.clear()
	if is_instance_valid(session):
		if session.world.gameplay.health>0 and not session.rescue_pending and not session.arrest_pending:
			session.world.player.input_locked = bool(_saved.get("player_locked",false)) or session.modal
		if is_instance_valid(race_camera) and race_camera.is_current():
			if is_instance_valid(previous_camera): previous_camera.make_current()
			session.world.camera.locked = _old_camera_lock
			session.world.camera.initialized = false
	if is_instance_valid(race_camera): race_camera.queue_free()
	if is_instance_valid(layer): layer.queue_free()
	if is_instance_valid(signals): signals.queue_free()
	_throttle_override = -1
	_nitro_override = false
	_refresh_session_hud()

func _refresh_session_hud() -> void:
	# Contextual HUD normally polls at80ms. Ownership changes need one immediate
	# projection so its minimap/weapon channels never overlap the race instruments.
	if not is_instance_valid(session) or not is_instance_valid(session.world) or not session.world.is_inside_tree(): return
	var normal_hud = session.world.hud
	if is_instance_valid(normal_hud) and normal_hud.is_inside_tree() and normal_hud.has_method("refresh_from_state"):
		normal_hud.refresh_from_state()
	if is_instance_valid(session.world.camera) and session.world.camera.is_inside_tree() and session.has_method("_update_world_indicator"):
		session._update_world_indicator()

func _exit_tree() -> void:
	if active: _cleanup()
