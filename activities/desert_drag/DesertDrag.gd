extends Node3D
## The vehicle bodies remain authoritative for crossings and obstruction.
## The shared powertrain produces acceleration, RPM, shifts, nitro and audio.
const PROGRESS := preload("res://activities/desert_drag/DesertDragProgress.gd")
const HUD := preload("res://activities/desert_drag/DesertDragHUD.gd")
const POWERTRAIN := preload("res://gameplay/desert_cars/DesertDrivetrain.gd")
const CARS := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
const STREET := preload("res://gameplay/desert_cars/StreetPowertrainCatalog.gd")
const AUDIO := preload("res://audio/desert_cars/DesertCarAudio.gd")
const DRIVER := preload("res://activities/desert_drag/DesertDragDriver.gd")
const SIGNALS := preload("res://activities/desert_drag/DesertDragSignals.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const HONOR := preload("res://runtime/TakeshiHonor.gd")
const OPEN_ROSTER := preload("res://activities/desert_drag/DragOpenRoster.gd")
const START_CAMERA_SWEEP_SECONDS := 1.8
const RETURN_COURSE := preload("res://activities/desert_drag/DragReturnCourse.gd")
const TAKESHI := {"name":"Takeshi","car":"supra_a80","distance":800.0,"reaction":.26,"mistake":0.0}
# One authored 800 m strip for every round. Each car keeps its real powertrain;
# rival builds cover progressively faster times along the same course.
# Difficulty comes from the rival/preparation, never a synthetic speed cap.
const RIVALS := {
	"digo":{"name":"Digo","car":"digo_gol_1993","distance":800.0,"reaction":.22,"mistake":.06,"parts":{}},
	"livia":{"name":"Lívia","car":"desert_faisca_rally","distance":800.0,"reaction":.18,"mistake":.045,"parts":{}},
	"raul":{"name":"Raul","car":"desert_coyote_drag","distance":800.0,"reaction":.15,"mistake":.03,"parts":{}},
	"jessica":{"name":"Jessica","car":"jessica_jetta_gli","distance":800.0,"reaction":.13,"mistake":.018,"parts":{}},
	"nadir":{"name":"Nadir","car":"desert_mirage_gt","distance":800.0,"reaction":.11,"mistake":.01,"parts":{}},
	"rauhz":{"name":"Rauhz","car":"rauhz_focus_mk1","distance":800.0,"reaction":.085,"mistake":.005,"parts":{}},
}
signal race_completed(result: Dictionary)
signal return_completed(result: Dictionary)
var return_course: Node3D
var _return_pending := false
var _return_attempt := false
var _preparation_region: Node3D
var _preparation_overlay: Control
var _preparation_ready_frames := 0
var session
var start_point := LAYOUT.drag_start_point()+Vector3.UP*.08
var direction := LAYOUT.drag_direction()
var staging_point := LAYOUT.drag_staging_point()
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
var _entry_pose := Transform3D.IDENTITY
var _feedback := ""
var _feedback_time := 0.0
var _old_camera_lock := false
var _throttle_override := -1.0
var _nitro_override := false
var board_controller: Node
var takeshi_controller: Node
var takeshi_meet: Node3D
var open_meet: Node3D
var night_controller: Node
var _night_pending := false
var _night_distance := 800.0
var _night_attempt := false
var challenge_controller: Node
var _challenge_pending := false
var _challenge_distance := 800.0
var _challenge_attempt := false
var _run_telemetry: RefCounted
var loaner_controller: Node

func configure(owner_session, strip_start: Vector3 = Vector3.INF, forward: Vector3 = Vector3.RIGHT) -> void:
	session = owner_session
	start_point = (LAYOUT.drag_start_point() if strip_start == Vector3.INF else strip_start)+Vector3.UP*.08
	staging_point = LAYOUT.drag_staging_point()
	direction = Vector3(forward.x,0,forward.z).normalized()
	process_physics_priority = -5
	set_physics_process(false)
	set_process(false)
	set_process_input(false)
	night_controller = preload("res://activities/desert_drag/DragNightController.gd").new()
	add_child(night_controller)
	night_controller.configure(self)
	challenge_controller = preload("res://activities/desert_drag/DragRivalChallengeController.gd").new()
	add_child(challenge_controller)
	challenge_controller.configure(self)
	loaner_controller = preload("res://activities/desert_drag/DragLoanerController.gd").new()
	add_child(loaner_controller)
	loaner_controller.configure(self)
	board_controller = preload("res://activities/desert_drag/DesertDragBoardController.gd").new()
	add_child(board_controller)
	board_controller.configure(self)
	takeshi_controller = preload("res://activities/desert_drag/TakeshiDragController.gd").new()
	add_child(takeshi_controller)
	takeshi_controller.configure(self)
	takeshi_meet = preload("res://runtime/desert/drag_meet/DragMeetTakeshi.gd").new()
	add_child(takeshi_meet)
	takeshi_meet.configure(session,self)
	open_meet = preload("res://activities/desert_drag/DragOpenMeet.gd").new()
	add_child(open_meet)
	open_meet.configure(self)
	if not PROGRESS.validate_snapshot(snapshot()):
		session.controller.save_invalid = true
		session.show_message("Progresso do drag inválido; save preservado.")

func snapshot() -> Dictionary:
	return PROGRESS.data(session.state.world_state)

func is_night() -> bool:
	var time: float = session.weather.time_of_day if is_instance_valid(session.weather) else float(session.state.world_state.get("time", .32))
	return time >= 20.0/24.0 or time < 5.0/24.0

func save_block_reason() -> String:
	if is_instance_valid(open_meet) and not open_meet.pending.is_empty(): return "Saia da fila da arrancada para salvar."
	if active: return "Encerre a arrancada para salvar."
	return loaner_controller.save_block_reason() if is_instance_valid(loaner_controller) else ""

func objective() -> String:
	if active and is_instance_valid(player_car): return "%s · %s · %d m"%["Ida e volta" if _return_attempt else "Drag",rival_config(rival_id).name,ceili(maxf(0,distance-_race_progress(racers[0])))]
	return "Arrancadas do deserto · Vá à concentração"

func target_position() -> Vector3:
	if active and _return_attempt: return start_point if int(racers[0].return_gate)==2 else start_point+direction*RETURN_COURSE.TURN_AT
	return start_point+direction*distance if active else staging_point

func nearest_action() -> Dictionary:
	if not is_instance_valid(session): return {}
	if active: return {"id":"desert_drag","target":"cancel","label":"Abandonar arrancada"}
	if not session.ready_for_play or session.controller.save_invalid or session.state.region_id != "desert" or not session.state.place_id.is_empty(): return {}
	if is_instance_valid(takeshi_meet):
		var special: Dictionary = takeshi_meet.nearest_action()
		if not special.is_empty(): return special
	var point: Vector3 = session.world.player.global_position
	if session.world.driving.occupied and is_instance_valid(session.world.driving.car): point = session.world.driving.car.global_position
	if point.distance_to(staging_point)>15 and point.distance_to(start_point)>12: return {}
	return {"id":"desert_drag","target":"board","label":"Ver quadro das arrancadas"}

func start_block_reason() -> String:
	if active: return "A arrancada já começou."
	if session.controller.save_invalid: return "Save inválido preservado; atividade indisponível."
	if not session.ready_for_play or session.modal or session.get_tree().paused or session.is_transition_blocked(): return "Aguarde o fim da atividade atual."
	if session.state.intro.stage != "complete": return "Conclua a chegada antes de correr."
	if session.state.region_id != "desert" or not session.state.place_id.is_empty() or nearest_action().is_empty(): return "Vá à largada do deserto."
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
	if target == "takeshi":
		if nearest_action().get("target","") != "takeshi": return false
		return takeshi_controller.open()
	if target == "board":
		if nearest_action().get("target","") != "board": return false
		return board_controller.open_board()
	if target == "cancel" and active:
		cancel_attempt()
		return true
	if target != "start": return false
	var reason := start_block_reason()
	if not reason.is_empty():
		session.show_message(reason)
		return false
	return start_rival(PROGRESS.current_rival(session.state.world_state))

func grid(index: int) -> Transform3D:
	var right := direction.cross(Vector3.UP).normalized()
	return Transform3D(Basis.looking_at(direction,Vector3.UP),start_point+right*(2.0 if index==0 else -2.0))

func start_rival(identity: String) -> bool:
	if not can_race(identity): return false
	var reason := start_block_reason()
	if not reason.is_empty():
		session.show_message(reason)
		return false
	if is_instance_valid(open_meet) and not open_meet.dispatching:
		if not open_meet.pending.is_empty():
			session.show_message("Você já está inscrito. Consulte sua posição no quadro.")
			return false
		if open_meet.track_busy(): return open_meet.request(identity,false)
	if identity=="takeshi":
		session.show_dialogue([{"speaker":"Takeshi","message":takeshi_controller.INTRO}],func():
			if start_block_reason().is_empty(): _start("takeshi"))
		return true
	return _start(identity)

func start_night_pass(identity: String, metres: float) -> bool:
	if active or _night_pending or _challenge_pending or metres not in [201.0,402.0,800.0]: return false
	_night_pending = true
	_night_distance = metres
	var started := start_rival(identity)
	if not started: cancel_waiting_context("start_blocked")
	return started

func start_return_pass(identity: String) -> bool:
	if active or _night_pending or _challenge_pending or identity not in PROGRESS.RIVALS or not can_race(identity): return false
	var reason := start_block_reason()
	if not reason.is_empty():
		session.show_message(reason)
		return false
	# Do not dispatch a straight-line queue ticket as an out-and-back race.
	if is_instance_valid(open_meet) and (not open_meet.pending.is_empty() or open_meet.track_busy()):
		session.show_message("Aguarde a pista e a fila ficarem livres.")
		return false
	_return_pending=true
	var started := _start(identity)
	_return_pending=false
	return started

func start_challenge_pass(identity: String, metres: float) -> bool:
	if active or _night_pending or _challenge_pending or metres not in [201.0,402.0,800.0]: return false
	if not is_instance_valid(challenge_controller) or not challenge_controller.can_start(identity): return false
	_challenge_pending=true
	_challenge_distance=metres
	var started:=start_rival(identity)
	if not started: cancel_waiting_context("start_blocked")
	return started

func cancel_waiting_context(reason: String = "cancelled") -> void:
	_night_pending = false
	_challenge_pending = false
	if not _night_attempt and is_instance_valid(night_controller): night_controller.cancel_attempt(reason)
	if not _challenge_attempt and is_instance_valid(challenge_controller): challenge_controller.cancel_attempt(reason)

func can_race(identity: String) -> bool:
	if _challenge_pending and is_instance_valid(challenge_controller) and challenge_controller.can_start(identity): return true
	if OPEN_ROSTER.CARS.has(identity): return true
	return HONOR.can_race(session.state.world_state) if identity=="takeshi" else PROGRESS.can_race(session.state.world_state,identity)

static func rival_config(identity: String) -> Dictionary:
	if OPEN_ROSTER.CARS.has(identity): return OPEN_ROSTER.CARS[identity]
	return TAKESHI if identity=="takeshi" else RIVALS.get(identity,{})

func _start(identity: String = "") -> bool:
	if active: return false
	if identity.is_empty(): identity = PROGRESS.current_rival(session.state.world_state)
	if not can_race(identity): return false
	player_car = session.world.driving.car
	var dispatch_reason := ""
	if _challenge_pending: dispatch_reason=challenge_controller.validate_dispatch(player_car)
	elif _night_pending: dispatch_reason=night_controller.validate_dispatch(player_car)
	if not dispatch_reason.is_empty():
		if is_instance_valid(open_meet) and not open_meet.pending.is_empty(): open_meet.cancel_ticket(false,dispatch_reason)
		else: cancel_waiting_context("preparation_changed")
		session.show_message(dispatch_reason)
		return false
	rival_id = identity
	var config: Dictionary = rival_config(rival_id)
	distance = RETURN_COURSE.LENGTH if _return_pending else (_challenge_distance if _challenge_pending else (_night_distance if _night_pending else float(config.distance)))
	var player_pose := grid(0)
	var opponent_pose := grid(1)
	var production = session.world.production
	if not production.vehicle_position_clear(player_car,player_pose.origin,player_pose.basis.get_euler().y):
		session.show_message("Libere as faixas antes de alinhar.")
		return false
	var opponent = open_meet.take_opponent(identity) if is_instance_valid(open_meet) else null
	if is_instance_valid(opponent): opponent.place(opponent_pose.origin,opponent_pose.basis.get_euler().y)
	else: opponent = production.spawn_vehicle(str(config.car),opponent_pose.origin,opponent_pose.basis.get_euler().y)
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
	if not opponent.has_node("DragRivalDriver"): DRIVER.attach(opponent,rival_id)
	OPEN_ROSTER.attach_number(player_car,27)
	if is_instance_valid(open_meet): open_meet.registered_car = player_car
	if OPEN_ROSTER.CARS.has(rival_id):
		OPEN_ROSTER.attach_number(opponent,int(config.number))
	_saved = {"physics":player_car.is_physics_processing(),"locked":player_car.input_locked,"controlled":player_car.controlled,"external":player_car.external_input,"player_locked":session.world.player.input_locked}
	previous_camera = get_viewport().get_camera_3d()
	previous_listener = get_viewport().get_audio_listener_3d()
	_old_camera_lock = session.world.camera.locked
	session.world.camera.locked = true
	_entry_pose = player_car.global_transform
	player_car.place(player_pose.origin,player_pose.basis.get_euler().y)
	session.world.player.input_locked = true
	racers.clear()
	for i in 2:
		var car = player_car if i==0 else opponent
		var drive := POWERTRAIN.new()
		drive.race_mode = true
		drive.configure(powertrain_profile_for_vehicle(car),CARS.parts_for_vehicle(car) if i==0 else _rival_parts())
		drive.reset()
		drive.launch_blend_seconds = .35
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
		sound.set_race_role("player" if i==0 else "rival")
		if not existing_sound: car.add_child(sound)
		var equipment = car.ensure_equipment(session.world)
		var was_lit: bool = equipment.headlights_on if is_instance_valid(equipment) else false
		if is_instance_valid(equipment): equipment.headlights_on = true
		racers.append({"car":car,"drive":drive,"sound":sound,"finish":INF,"was_lit":was_lit,"travel":0.0,"previous_power":previous_power,"existing_sound":existing_sound,"previous_audio":previous_audio})
	_return_attempt=_return_pending
	if _return_attempt:
		return_course=RETURN_COURSE.new()
		add_child(return_course)
		return_course.configure(start_point,direction)
		for index in 2: return_course.prepare(racers[index],index)
	_night_attempt = _night_pending
	_night_pending = false
	_challenge_attempt = _challenge_pending
	_challenge_pending = false
	_run_telemetry=preload("res://activities/desert_drag/DragRunTelemetry.gd").new()
	if _challenge_attempt: challenge_controller.begin_attempt(player_car)
	active = true
	phase = "staging"
	_preparation_region=session.world.production.regions.get("desert")
	if is_instance_valid(_preparation_region) and _preparation_region.has_method("prepare_drag_view"):
		_preparation_region.prepare_drag_view(true)
		if not _preparation_region.drag_view_ready(): phase="preparing"
		else: _preparation_region.prepare_drag_view(false)
	_preparation_ready_frames=0
	countdown = 3.0
	elapsed = 0
	_runoff = 0
	last_result = {}
	_rng.randomize()
	_rival_wait = float(config.reaction)+(0.0 if rival_id=="takeshi" else _rng.randf_range(-.035,.06))
	_rival_target = racers[1].drive.ideal_shift_rpm
	_rival_shift_delay = -1
	_feedback = "Acelere para preparar o giro"
	_feedback_time = 3.0
	race_camera = Camera3D.new()
	race_camera.name = "DesertDragSideCamera"
	race_camera.set_meta("drag_precipitation",true)
	race_camera.fov = 57
	race_camera.far = 2200
	race_camera.near = .2
	add_child(race_camera)
	_update_camera(0)
	race_camera.make_current()
	preload("res://gameplay/lights/LightBudget.gd").refresh(true)
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
	hud.set_style(preload("res://activities/desert_drag/DragInstrumentStyles.gd").selection(session.state.world_state))
	hud.race_distance = distance
	if _return_attempt:
		hud.event_title="IDA E VOLTA"
	elif _night_attempt:
		var event_status: Dictionary = night_controller.status()
		hud.event_title = "NOITE DE ACERTO · %d/3"%int(event_status.get("round",1))
	elif _challenge_attempt:
		hud.event_title="DESAFIO · "+str(config.name).to_upper()
	hud.show_start_lights = true
	hud.racing = false
	# Fill the instruments before entering the tree: the first rendered staging
	# frame must already show the real opponent, distance and launch RPM band.
	hud.update_state(racers[0].drive,distance,0.0,0.0,str(ceili(countdown)),str(config.name))
	hud.feedback = _feedback
	layer.add_child(hud)
	if phase=="preparing":
		_preparation_overlay=preload("res://activities/desert_drag/DragPreparation.gd").new()
		layer.add_child(_preparation_overlay)
	signals = SIGNALS.new()
	add_child(signals)
	signals.configure(start_point,direction,0.0 if _return_attempt else distance)
	set_physics_process(true)
	set_process(true)
	set_process_input(true)
	_refresh_session_hud()
	return true

static func powertrain_profile_for_vehicle(vehicle: Node) -> String:
	# Street cars already have their own engine/gearing. Generic body-class
	# fallback must never turn a V12 or an authored sports car into a stock hatch.
	if is_instance_valid(vehicle):
		var identity := str(vehicle.get("archetype"))
		if STREET.has(identity): return identity
	return CARS.profile_for_vehicle(vehicle)

func _rival_parts() -> Dictionary:
	# Same purchasable catalogue and rules as Dante; no catch-up velocity.
	if (_night_pending or _night_attempt) and is_instance_valid(night_controller): return night_controller.rival_parts(rival_id)
	return rival_parts(rival_id)

static func rival_parts(identity: String) -> Dictionary:
	# Fixed authored builds, all available in the player's tuning catalogue.
	# Replaying a rival never scales their engine to Dante's car or position.
	match identity:
		"digo": return {"engine":"street_cam","turbo":"turbo_mid","tires":"drag_tires","exhaust":"race_exhaust"}
		"livia": return {"ecu":"ecu_1","engine":"race_cam","turbo":"turbo_small","tires":"drag_tires","weight":"lightweight","nitro":"nitro_street"}
		"raul": return {"engine":"race_cam","turbo":"turbo_mid","tires":"drag_tires","weight":"lightweight","nitro":"nitro_street","suspension":"drag_suspension"}
		"jessica": return {"ecu":"ecu_2","engine":"race_cam","turbo":"turbo_large","nitro":"nitro_race","tires":"drag_tires","weight":"lightweight","suspension":"drag_suspension","exhaust":"race_exhaust"}
		"nadir": return {"ecu":"ecu_1","engine":"race_cam","turbo":"turbo_mid","nitro":"nitro_street","tires":"drag_tires","weight":"lightweight","suspension":"drag_suspension"}
		"rauhz": return {"ecu":"ecu_2","engine":"race_cam","turbo":"turbo_large","nitro":"nitro_race","tires":"drag_tires","weight":"lightweight","suspension":"drag_suspension","exhaust":"race_exhaust"}
		"takeshi": return preload("res://data/TakeshiRewardSpec.gd").PARTS.duplicate()
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
	if outcome.is_empty(): return outcome
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
	if phase=="preparing":
		# The preparation screen owns a bounded streaming budget; no race clock,
		# car motion or green light starts while visible course cells are missing.
		var ready: bool=is_instance_valid(_preparation_region) and _preparation_region.drag_view_ready()
		_preparation_ready_frames=_preparation_ready_frames+1 if ready else 0
		if is_instance_valid(_preparation_overlay): _preparation_overlay.progress=_preparation_region.drag_view_progress() if is_instance_valid(_preparation_region) else 0.0
		if _preparation_ready_frames>=2:
			_preparation_region.prepare_drag_view(false)
			if is_instance_valid(_preparation_overlay): _preparation_overlay.queue_free()
			phase="staging"
		_update_camera(delta)
		return
	if phase == "staging":
		racers[0].drive.stage(delta,throttle,_digital_throttle())
		# Rivals feather the throttle toward their own launch band.
		var other = racers[1].drive
		other.stage(delta,1.0 if other.rpm < other.redline*.57 else 0.0)
		countdown = maxf(0,countdown-delta)
		signals.set_countdown(countdown)
		if countdown <= 0:
			phase = "racing"
			_feedback = str(racers[0].drive.launch())
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
			if crossed:
				if _return_attempt: return_course.runoff(entry,delta)
				else: _step_runoff(entry,delta)
			else:
				var brake_value := _brake() if i==0 else 0.0
				if _return_attempt:
					brake_value=maxf(brake_value,return_course.brake(entry))
					entry.return_braking=brake_value>0.0
					if brake_value>0.0: throttle_value=0.0; nitro_value=false
					if drive.rpm<drive.redline*.4: drive.shift_down()
				drive.step(delta,throttle_value,nitro_value,brake_value)
			var before := _race_progress(entry)
			_move_car(entry,delta)
			var after: float=return_course.observe(entry) if _return_attempt else _offset(entry.car.global_position)
			if not crossed:
				if i==0:
					_run_telemetry.observe(drive,before,after,before_elapsed,delta,distance)
					if _challenge_attempt: challenge_controller.observe(drive,after,delta)
				entry.finish = PROGRESS.crossing_time(before,after,distance,before_elapsed,delta)
			if entry.car.global_position.y < start_point.y-3:
				cancel_attempt("unsupported_track")
				return
		if is_finite(float(racers[0].finish)) and is_finite(float(racers[1].finish)):
			phase = "braking"
		# Technical proofs judge the player's run, even when a faster rival has
		# already finished. Keep the absolute timeout and rival-DNF recovery.
		elif elapsed > (120.0 if _return_attempt else 60.0) or ((not _challenge_attempt or is_finite(float(racers[0].finish))) and elapsed > minf(float(racers[0].finish),float(racers[1].finish))+8.0):
			if is_finite(float(racers[0].finish)): phase = "braking"
			else: cancel_attempt("timeout"); return
	elif phase == "braking":
		_runoff += delta
		for entry in racers:
			if _return_attempt: return_course.runoff(entry,delta)
			else: _step_runoff(entry,delta)
			_move_car(entry,delta)
			if _return_attempt: return_course.observe(entry)
		if racers.all(func(e): return e.drive.speed_mps<.15):
			_finish()
			return
	_feedback_time = maxf(0,_feedback_time-delta)
	_update_camera(delta)

var _challenge_status_clock := 0.0

func _process(delta: float) -> void:
	if not active or not is_instance_valid(hud) or racers.size()!=2: return
	layer.visible = not session.modal
	if session.modal: return
	if _challenge_attempt:
		_challenge_status_clock-=delta
		if _challenge_status_clock<=0.0:
			_challenge_status_clock=.1
			hud.challenge_status=challenge_controller.live_status()
	var title := str(ceili(countdown)) if phase in ["preparing","staging"] else ("FREANDO" if phase=="braking" else "")
	if _return_attempt and phase=="racing":
		title=["IDA","CONTORNE O BARRIL","VOLTA"][int(racers[0].return_gate)]
	hud.feedback = _feedback if _feedback_time>0 else ""
	if _return_attempt and phase=="racing":
		if int(racers[0].return_gate)==1: hud.feedback="Virada assistida"
		elif int(racers[0].return_gate)==0 and return_course.brake(racers[0])>0.0: hud.feedback="Freada assistida · prepare a volta"
	hud.show_start_lights = phase in ["preparing","staging"]
	hud.racing = phase=="racing"
	hud.update_state(racers[0].drive,maxf(0,distance-_race_progress(racers[0])),elapsed,_race_progress(racers[0])-_race_progress(racers[1]),title,str(rival_config(rival_id).name))

func set_pause_overlay(paused: bool) -> void:
	if is_instance_valid(layer): layer.visible = active and not paused and not session.modal

func _rival_control(delta: float) -> void:
	var drive = racers[1].drive
	if drive.rpm < _rival_target or elapsed < _rival_wait: return
	if _rival_shift_delay < 0:
		_rival_shift_delay = _rng.randf_range(.015,.07)
		if _rng.randf() < float(rival_config(rival_id).mistake): _rival_shift_delay += _rng.randf_range(.14,.32)
	_rival_shift_delay -= delta
	if _rival_shift_delay <= 0:
		drive.shift_up()
		_rival_target = drive.ideal_shift_rpm+_rng.randf_range(-120,110)
		_rival_shift_delay = -1

func _step_runoff(entry: Dictionary, delta: float, course_distance: float = -1.0) -> void:
	var drive = entry.drive
	var speed: float = drive.speed_mps
	var finish_distance := distance if course_distance<0.0 else course_distance
	var room := maxf(1.0,finish_distance+175.0-_offset(entry.car.global_position))
	# Reserve distance for the pressure ramp and the gentle final release.
	# Fast builds need more braking force, not an instantaneous speed cap.
	var required := speed*speed/(2.0*maxf(1.0,room-speed*.25-8.0))
	var target := maxf(8.0,required)
	if speed<4.0: target = minf(target,maxf(1.2,speed*2.5))
	var deceleration := move_toward(float(entry.get("runoff_deceleration",0.0)),target,delta*60.0)
	entry.runoff_deceleration = deceleration
	# Normal progressive service braking is rolling grip, not a locked wheel.
	var grip: float = 9.81*float(drive.spec.traction)*drive.surface_grip
	entry.car.set_meta("drag_service_brake_slip",clampf((deceleration-grip)/maxf(1.0,grip),0.0,1.0))
	drive.step(delta,0.0,false,0.0)
	drive.speed_mps = minf(drive.speed_mps,maxf(0.0,speed-deceleration*delta))

func _move_car(entry: Dictionary, delta: float) -> void:
	var car = entry.car
	var drive = entry.drive
	var before: Vector3 = car.global_position
	var motion_direction: Vector3=return_course.heading(entry,delta) if _return_attempt else direction
	if _return_attempt:
		var turn: float=(-car.global_basis.z).signed_angle_to(motion_direction,Vector3.UP)
		car.steering=clampf(atan2(turn*2.4,maxf(.001,drive.speed_mps*delta)),-.48,.48)
		car.global_basis=Basis.looking_at(motion_direction,Vector3.UP)
	var incoming_velocity: Vector3 = motion_direction*drive.speed_mps
	# At 200+ km/h, never outrun the next streamed collision cell. The shared
	# persistent-support pass retains these two admitted cars between updates.
	var region: Node3D = session.world.production.regions.get("desert")
	if is_instance_valid(region):
		var next_point: Vector3 = before+motion_direction*(drive.speed_mps*delta+float(car.half_length)+1.0)
		if not region.prepare_collision_at(next_point):
			drive.speed_mps = 0
			car.velocity = Vector3.ZERO
			return
	# Match ordinary Vehicle motion: floor snapping maintains grounded support.
	# Pushing downward after contact can catch a coplanar floor's exposed edge.
	var vertical_speed: float = 0.0 if car.is_on_floor() else car.velocity.y-18*delta
	car.velocity = motion_direction*drive.speed_mps + Vector3.UP*vertical_speed
	car.move_and_slide()
	var moved: Vector3 = car.global_position-before
	var actual := maxf(0,moved.dot(motion_direction)/maxf(.001,delta))
	if actual+1.0 < drive.speed_mps: drive.speed_mps = actual
	car.speed = actual
	car.horizontal_velocity = motion_direction*actual
	car.throttle_input = drive.throttle
	car.brake_input = is_finite(float(entry.finish)) or (_return_attempt and entry.get("return_braking",false))
	car.wheel_spin += moved.dot(motion_direction)/.355
	for wheel in car.wheels: wheel.rotation.x = car.wheel_spin
	if _return_attempt:
		for pivot in car.steer_pivots.values(): pivot.rotation.y=car.steering if pivot.get_meta("front",false) else 0.0
	car.distance_travelled += moved.length()
	entry.travel += moved.dot(motion_direction)
	if is_instance_valid(car.effects): car.effects.physics_tick(delta,incoming_velocity)
	if not entry.has("launch_body"):
		entry.launch_body = preload("res://activities/desert_drag/DragLaunchBody.gd").new()
		entry.launch_body.bind(car)
	entry.launch_body.step(delta,drive)

func _update_camera(_delta: float) -> void:
	if not is_instance_valid(race_camera) or racers.size()!=2: return
	var a: Vector3 = racers[0].car.global_position
	var b: Vector3 = racers[1].car.global_position
	var frame: Dictionary=return_course.camera_frame(racers[0],b) if _return_attempt and phase!="staging" and elapsed>=START_CAMERA_SWEEP_SECONDS else start_camera_frame(a,b)
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
	var setback := clampf(16.5+maxf(0,absf(signed_gap)-12.0)*.28,16.5,25.5)
	return {"target":center,"position":center+side*setback-direction*4.0+Vector3.UP*4.4,"setback":setback}

func start_camera_frame(a: Vector3, b: Vector3) -> Dictionary:
	var side_frame := camera_frame(a,b)
	if phase not in ["preparing","staging"] and (phase != "racing" or elapsed >= START_CAMERA_SWEEP_SECONDS): return side_frame
	# The race clock owns the sweep: pause freezes it, and every start resets it.
	var progress := 0.0 if phase in ["preparing","staging"] else clampf(elapsed/START_CAMERA_SWEEP_SECONDS,0.0,1.0)
	var blend := progress*progress*(3.0-2.0*progress)
	var side := direction.cross(Vector3.UP).normalized()
	var rear_target := (a+b)*.5+direction*2.0+Vector3.UP*.75
	var target := rear_target.lerp(side_frame.target,blend)
	# Orbit at a steady distance instead of cutting across the cars on a chord.
	var angle := lerpf(atan2(4.5,16.0),atan2(float(side_frame.setback),4.0),blend)
	var radius := lerpf(Vector2(4.5,16.0).length(),Vector2(float(side_frame.setback),4.0).length(),blend)
	var offset := (side*sin(angle)-direction*cos(angle))*radius+Vector3.UP*lerpf(10.5,4.4,blend)
	return {"target":target,"position":target+offset,"setback":offset.dot(side)}

func _offset(point: Vector3) -> float:
	return (point-start_point).dot(direction)

func _race_progress(entry: Dictionary) -> float:
	return float(entry.return_progress) if _return_attempt else _offset(entry.car.global_position)

func _throttle() -> float:
	if _throttle_override>=0: return _throttle_override
	var result := 1.0 if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP) else 0.0
	for device in Input.get_connected_joypads(): result = maxf(result,Input.get_joy_axis(device,JOY_AXIS_TRIGGER_RIGHT))
	return clampf(result,0,1)

func _digital_throttle() -> bool:
	if _throttle_override>=0: return false
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): return true
	for device in Input.get_connected_joypads():
		if Input.get_joy_axis(device,JOY_AXIS_TRIGGER_RIGHT)>.02: return false
	return true

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
	if not active or phase != "braking" or racers.size()!=2: return
	var player_time: float = racers[0].finish
	var other_time: float = racers[1].finish
	var casual := OPEN_ROSTER.CARS.has(rival_id)
	var result: Dictionary
	var night := _night_attempt
	var challenge := _challenge_attempt
	var returning := _return_attempt
	if returning:
		result=RETURN_COURSE.record_finish(session.state.world_state,rival_id,player_time,other_time)
	elif challenge:
		result=challenge_controller.record_finish(player_time,other_time,player_car)
	elif night:
		result = night_controller.record_finish(player_time,other_time,player_car)
	elif casual:
		result = {"finished":true,"casual":true,"first_win":false,"rival_id":rival_id,"won":player_time<other_time,"seconds":player_time,"number":27}
	else:
		result = HONOR.record_finish(session.state.world_state,player_time<other_time,player_time) if rival_id=="takeshi" else PROGRESS.record_finish(session.state.world_state,rival_id,player_time<other_time,player_time)
	if result.is_empty():
		_cleanup()
		return
	result["rival_seconds"] = other_time if is_finite(other_time) else -1.0
	if not night and not challenge and not returning:
		result["best_seconds"] = float(HONOR.data(session.state.world_state).best_seconds) if rival_id=="takeshi" else float(snapshot().best.get(rival_id,player_time))
	if is_instance_valid(_run_telemetry) and not returning: result["telemetry"]=_run_telemetry.snapshot()
	last_result = result
	_cleanup()
	if not result.get("finished",false): return
	if returning:
		return_completed.emit(result)
		session.save_game()
		return
	race_completed.emit(result)
	if night or challenge or not casual: session.save_game()

func cancel_attempt(reason: String = "cancelled") -> void:
	if not active: return
	if _night_attempt and is_instance_valid(night_controller): night_controller.cancel_attempt(reason)
	if _challenge_attempt and is_instance_valid(challenge_controller): challenge_controller.cancel_attempt(reason)
	last_result = {"finished":false,"reason":reason}
	_cleanup()
	if reason == "false_start" and is_instance_valid(session): session.show_message("Queimou a largada. Espere o sinal verde para trocar a marcha.")
	elif reason in ["cancelled","timeout","unsupported_track"] and is_instance_valid(session): session.show_message("Arrancada interrompida. Volte à concentração para tentar novamente.")

func _cleanup() -> void:
	if is_instance_valid(_preparation_region): _preparation_region.prepare_drag_view(false)
	if is_instance_valid(_preparation_overlay): _preparation_overlay.queue_free()
	if _challenge_attempt and is_instance_valid(challenge_controller): challenge_controller.cancel_attempt("cleanup")
	active = false
	_return_attempt=false
	_return_pending=false
	if is_instance_valid(return_course): return_course.queue_free()
	_night_attempt = false
	_challenge_attempt = false
	_run_telemetry=null
	phase = ""
	set_process(false)
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
			entry.sound.set_race_role("")
			if entry.existing_sound and is_instance_valid(entry.car): entry.sound.bind(entry.car,entry.previous_audio)
			else: entry.sound.queue_free()
		if not is_instance_valid(entry.car): continue
		var car = entry.car
		car.remove_meta("desert_drag_physics")
		if entry.has("launch_body"): entry.launch_body.reset()
		car.remove_meta("drag_service_brake_slip")
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
			if is_instance_valid(open_meet) and car.get_meta("open_drag_owned",false) and open_meet.reclaim_opponent(car):
				pass
			elif is_instance_valid(session) and session.world.driving.occupied and session.world.driving.car==car:
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

func return_to_entry() -> bool:
	# Keep the result modal/input lock until support and the destination are safe.
	if active or not is_instance_valid(player_car) or not session.world.driving.occupied or session.world.driving.car!=player_car: return false
	if player_car.health<=0 or session.world.gameplay.health<=0 or session.rescue_pending or session.arrest_pending: return false
	if session.state.region_id!="desert" or not session.state.place_id.is_empty(): return false
	var region: Node3D = session.world.production.regions.get("desert")
	if not is_instance_valid(region): return false
	# Replay can restart on the next frame, before ordinary streaming revisits
	# the neighbouring grid cell. Admit both lanes before the physics query.
	if not region.prepare_collision_at(grid(0).origin) or not region.prepare_collision_at(grid(1).origin): return false
	var destinations: Array[Transform3D] = []
	# A cancelled attempt can leave the car on the launch grid. "Entrada" means
	# the meet parking, even after a chain of cancellations and rematches.
	if _entry_pose.origin.distance_to(staging_point)<=15.0: destinations.append(_entry_pose)
	for offset in [-6.0,-10.0,-2.0]:
		destinations.append(Transform3D(_entry_pose.basis,staging_point+Vector3(0,.1,offset)))
	for pose in destinations:
		if not region.prepare_collision_at(pose.origin): continue
		await get_tree().physics_frame
		if not is_instance_valid(player_car) or not session.modal or session.world.driving.car!=player_car: return false
		if not session.world.production.vehicle_position_clear(player_car,pose.origin,pose.basis.get_euler().y): continue
		player_car.place(pose.origin,pose.basis.get_euler().y)
		session.world.player.global_position = pose.origin
		session.world.player.reset_physics_interpolation()
		region.set_focus(pose.origin)
		session.world.camera.initialized = false
		return true
	return false

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
