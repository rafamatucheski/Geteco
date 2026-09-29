extends Node
const PROGRESS := preload("res://activities/motocross/MotocrossProgress.gd")
const COURSE := preload("res://activities/motocross/MotocrossCourse.gd")
const BIKE := preload("res://activities/motocross/MotocrossBike.gd")
const MODELS := preload("res://activities/motocross/MotocrossModels.gd")
const GATE := preload("res://activities/motocross/MotocrossStartGate.gd")
const HUD := preload("res://activities/motocross/MotocrossHUD.gd")
## Rival start-gate odds by difficulty: [holeshot, bog, wheelie].
const RIVAL_LAUNCH := [[.18,.28,.06],[.26,.2,.06],[.34,.14,.05],[.42,.08,.04]]
var selected_model := 0
var start_shot := preload("res://activities/motocross/MotocrossStart.gd").new()
var ambient
var session
var progress := PROGRESS.new()
var track := COURSE.new()
var active := false
var mounted := false
var autopilot := false
## Test/benchmark hook for timed practice; `autopilot` only ever drove races.
var practice_autopilot := false
var racers: Array = []
var player_bike: CharacterBody3D
var owned_bike: CharacterBody3D
var rental_bike: CharacterBody3D
var countdown := 0.0
var elapsed := 0.0
var difficulty := 0
var _status
var _clock := 0.0
var _player_layer := 2
var _player_mask := 1
var _camera_size := 28.0
var _camera_far := 180.0
var _marker: Node3D
var wetness := 0.0
var surface_effects: Node3D
var _weather_clock := 0.0
## Start: engine revs held by the rider while the gate is up, 0..1.
var launch_rev := 0.0
var launch_result := ""
var _gate_drop_at := 0.0
var _launch_rng := RandomNumberGenerator.new()
## First time any rider reached each timing-gate count: the leader's splits.
var _leader_splits := PackedFloat32Array()
var _announced_place := 0
var _place_hold := 0.0
var _info_clock := 0.0
var _course_ref: WeakRef
## Practice laps on a rented or owned bike, timed from the start/finish line.
var practice := {}
var _tags := {}

func configure(owner_session) -> void:
	session = owner_session
	var saved: Variant = session.state.world_state.get("motocross",{})
	if not saved is Dictionary or (not saved.is_empty() and not progress.restore_snapshot(saved)):
		session.controller.save_invalid = true
		session.show_message("Dados de motocross inválidos; save preservado.")
	# An interrupted paid attempt is a loss, never a free retry or a refunded fee.
	if int(progress.data.active) >= 0: progress.settle(session.state.economy,false)
	_status = preload("res://activities/motocross/MotocrossHUD.gd").new()
	session.world.hud.add_child(_status)
	_marker = Node3D.new()
	var arrow := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0
	mesh.bottom_radius = .5
	mesh.height = 1.0
	arrow.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("ffc34f")
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arrow.material_override = mat
	arrow.rotation.z = PI
	_marker.add_child(arrow)
	session.world.add_child(_marker)
	_marker.hide()
	surface_effects = load("res://activities/motocross/MotocrossSurfaceEffects.gd").new()
	session.world.add_child(surface_effects)
	surface_effects.configure(track)
	wetness = .85 if int(session.state.world_state.get("weather",0)) in [1,2] else 0.0
	process_physics_priority = -10
	ambient = load("res://activities/motocross/MotocrossAmbient.gd").new()
	ambient.configure(self)

func snapshot() -> Dictionary: return progress.snapshot()

func nearest_action() -> Dictionary:
	if session == null or not session.ready_for_play or session.modal: return {}
	if active: return {"id":"motocross","target":"quit","label":"Desistir da corrida"}
	if mounted: return {"id":"motocross","target":"dismount","label":"Descer da moto"}
	if session.state.region_id != "harbor" or not session.state.place_id.is_empty() or session.world.driving.occupied: return {}
	var p: Vector3 = session.world.player.position
	if is_instance_valid(owned_bike) and p.distance_to(owned_bike.position) < 2.8:
		return {"id":"motocross","target":"ride","label":"Pilotar sua motocross"}
	if p.distance_to(COURSE.ENTRY) < 5.5:
		return {"id":"motocross","target":"enter","label":"Inscrever-se · Motocross"}
	return {}

func perform(target: String) -> bool:
	if nearest_action().get("target","") != target: return false
	match target:
		"quit":
			session._menu("Desistir perde a inscrição de R$ %d"%int(PROGRESS.LEVELS[difficulty].fee))
			session._button("Continuar corrida",session.close_menu)
			session._button("Desistir",func(): session.close_menu(); finish(false,"quit"))
		"dismount": dismount()
		"ride": _mount(owned_bike)
		"enter": _menu()
		_: return false
	return true

func _menu() -> void:
	var best := float(progress.data.get("best_lap",0.0))
	session._menu("Vértice · Motocross"+(" · recorde %s"%HUD.clock(best) if best > 0.0 else ""))
	session._button("Alugar moto para treinar · R$ 35",func(): _bike_menu(-1))
	for i in PROGRESS.LEVELS.size():
		var spec: Dictionary = PROGRESS.LEVELS[i]
		session._button("%s · entrada R$ %d · vitória R$ %d"%[spec.name,spec.fee,int(spec.fee)+int(spec.bonus)],func():
			_bike_menu(i))
		var button := session.column.get_child(session.column.get_child_count()-1) as Button
		if button != null: button.disabled = i > int(progress.data.unlocked) or session.state.economy.balance < int(spec.fee)
	if progress.data.owned:
		session._button("Retirar minha moto",func(): session.close_menu(); _park_owned(true))
	session._button("Voltar",session.close_menu)

func _bike_menu(level: int) -> void:
	session._menu("Escolha a moto · %s"%("Treino" if level < 0 else PROGRESS.LEVELS[level].name))
	for index in MODELS.MODELS.size():
		session._button(("✓ " if selected_model==index else "")+MODELS.caption(index),func():
			selected_model = index
			_bike_menu(level))
		var button := session.column.get_child(session.column.get_child_count()-1) as Button
		button.custom_minimum_size.y = 62
		button.toggle_mode = true
		button.button_pressed = selected_model==index
		button.add_theme_color_override("font_color",MODELS.MODELS[index].color.lightened(.45))
		button.add_theme_color_override("font_pressed_color",MODELS.MODELS[index].color.lightened(.45))
		if selected_model==index: button.call_deferred("grab_focus")
	var fee := 35 if level < 0 else int(PROGRESS.LEVELS[level].fee)
	session._button("%s · R$ %d"%["Alugar" if level < 0 else "Correr",fee],func():
		session.close_menu()
		if level < 0: rent_bike()
		else: start_race(level))
	var confirm := session.column.get_child(session.column.get_child_count()-1) as Button
	confirm.disabled = session.state.economy.balance < fee
	session._button("Voltar",_menu)

func rent_bike() -> bool:
	if mounted or active or session.state.region_id != "harbor" or not session.state.place_id.is_empty() or session.world.driving.occupied or session.world.player.position.distance_to(COURSE.ENTRY) > 8: return false
	if not session.save_block_reason().is_empty(): session.show_message(session.save_block_reason()); return false
	var old_wallet: Dictionary = session.state.economy.snapshot()
	var old_progress := progress.snapshot()
	if not progress.rent(session.state.economy): session.show_message("Aluguel custa R$ 35."); return false
	if not session.save_game(true):
		session.state.economy.restore_snapshot(old_wallet)
		progress.restore_snapshot(old_progress)
		return false
	ambient.clear()
	rental_bike = BIKE.new()
	rental_bike.is_player = true
	MODELS.apply(rental_bike,selected_model)
	session.world.add_child(rental_bike)
	rental_bike.reset_to(track.pose(0))
	_mount(rental_bike)
	return true

func start_race(level: int) -> bool:
	if active or mounted or level < 0 or level >= PROGRESS.LEVELS.size(): return false
	if session.state.region_id != "harbor" or not session.state.place_id.is_empty() or session.world.driving.occupied or session.world.player.position.distance_to(COURSE.ENTRY) > 8:
		return false
	if not session.save_block_reason().is_empty():
		session.show_message(session.save_block_reason()); return false
	var old_wallet: Dictionary = session.state.economy.snapshot()
	var old_progress := progress.snapshot()
	if not progress.begin(session.state.economy,level):
		session.show_message("Saldo insuficiente ou dificuldade bloqueada."); return false
	# Persist the debit before enabling motion, including when the game is closed.
	if not session.save_game(true):
		session.state.economy.restore_snapshot(old_wallet)
		progress.restore_snapshot(old_progress)
		return false
	ambient.clear()
	difficulty = level
	countdown = 3
	# The gate falls at an unpredictable moment of the last 0.6 s: riders must
	# hold their revs instead of timing a fixed count.
	_launch_rng.seed = hash(int(progress.data.serial)*7919+level)
	_gate_drop_at = _launch_rng.randf_range(0.0,.6)
	launch_rev = 0.0
	launch_result = ""
	elapsed = 0
	active = true
	_announced_place = 0
	_place_hold = 0.0
	var spec: Dictionary = PROGRESS.LEVELS[level]
	_leader_splits = PackedFloat32Array()
	_leader_splits.resize(int(spec.laps)*track.gates.size())
	_leader_splits.fill(-1.0)
	var colors := [Color("e98029"),Color("ce4140"),Color("3c86bc"),Color("bcbf3f"),Color("994cbd"),Color("3eaf8a")]
	for i in int(spec.rivals)+1:
		var bike := BIKE.new()
		bike.paint_color = colors[i]
		bike.rider_color = colors[i].lightened(.25)
		bike.rider_name = "Dante" if i == 0 else ["Faísca","Lobo","Nina","Ferro","Juca"][i-1]
		bike.is_player = i == 0
		bike.max_speed = 18.0 if i == 0 else (float(spec.speed)+1.0)*(1.0-float(i-1)*.022)
		if i == 0: MODELS.apply(bike,selected_model)
		bike.race_enabled = false
		session.world.add_child(bike)
		# One row behind the drop bars; banked outer lanes get their clay height.
		var lane := float(GATE.LANES[i])
		var grid := track.pose(GATE.GRID_DISTANCE,lane)
		grid.origin.y = track.ribbon_height(GATE.GRID_DISTANCE,lane)+.15
		bike.reset_to(grid)
		racers.append({"bike":bike,"gate":1,"passed":0,"previous":bike.position,"outside":0.0,"stalled":0.0,"lane":lane,"respawns":0,"times":PackedFloat32Array(),"lap_start":0.0,"best":0.0,"route_distance":-1.0})
		if i > 0: _tag(bike)
	_status.hide_results()
	_mount(racers[0].bike)
	start_shot.begin(self)
	_marker.show()
	var gate: Node3D = _course_gate()
	if gate != null: gate.raise_gate()
	return true

func _course() -> Node3D:
	var known: Node3D = _course_ref.get_ref() if _course_ref != null else null
	if is_instance_valid(known) and known.is_inside_tree() and not known.is_queued_for_deletion(): return known
	for candidate in get_tree().get_nodes_in_group("motocross_course"):
		if candidate is Node3D and session.world.is_ancestor_of(candidate) and not candidate.is_queued_for_deletion():
			_course_ref = weakref(candidate)
			return candidate
	return null

func _course_gate() -> Node3D:
	var course := _course()
	return course.start_gate if course != null and is_instance_valid(course.start_gate) else null

func _tag(bike: CharacterBody3D) -> void:
	# Rival name and live position above the helmet, readable from the high camera.
	var label := Label3D.new()
	label.name = "RiderTag"
	label.font = HUD.FONT
	label.font_size = 46
	label.pixel_size = .012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 9
	label.outline_modulate = Color(0,0,0,.8)
	label.modulate = bike.paint_color.lightened(.45)
	label.position = Vector3(0,2.45,0)
	label.text = bike.rider_name
	bike.add_child(label)
	_tags[bike.get_instance_id()] = label

func _mount(bike: CharacterBody3D) -> void:
	if not is_instance_valid(bike): return
	if ambient != null: ambient.clear()
	player_bike = bike
	mounted = true
	var world = session.world
	_player_layer = world.player.collision_layer
	_player_mask = world.player.collision_mask
	_camera_size = world.camera.target_size
	_camera_far = world.camera.far
	world.player.input_locked = true
	world.player.set_physics_process(false)
	world.player.hide()
	world.player.collision_layer = 0
	world.player.collision_mask = 0
	world.camera.target = bike
	world.camera.target_size = 34
	world.camera.far = maxf(_camera_far,220)
	bike.rider.show()
	bike.race_enabled = true
	world.gameplay.aiming = false
	if not bike.landed.is_connected(_on_player_landed): bike.landed.connect(_on_player_landed)
	# Practice timing starts at the first crossing of the start/finish line.
	practice = {} if active else {"bike":bike,"gate":0,"passed":0,"previous":bike.position,"lap_start":-1.0,"clock":0.0,"best":0.0,"laps":0,"pace":15.0}

func _unmount_at(point: Vector3) -> void:
	var world = session.world
	mounted = false
	world.player.teleport(point)
	world.player.collision_layer = _player_layer
	world.player.collision_mask = _player_mask
	world.player.show()
	world.player.set_physics_process(true)
	world.player.input_locked = world.gameplay.health <= 0 or session.is_transition_blocked()
	world.camera.target = world.player
	world.camera.target_size = _camera_size
	world.camera.far = _camera_far
	if is_instance_valid(player_bike):
		player_bike.drive(0,0,true)
		player_bike.race_enabled = false
		player_bike.rider.hide()
		if player_bike.landed.is_connected(_on_player_landed): player_bike.landed.disconnect(_on_player_landed)
	player_bike = null
	practice = {}
	if is_instance_valid(rental_bike):
		rental_bike.queue_free()
		rental_bike = null
	_status.text = ""

func dismount() -> bool:
	if active or not mounted or not is_instance_valid(player_bike): return false
	if absf(player_bike.speed) > 1.2 or player_bike.crash_state != "riding":
		session.show_message("Pare a moto para descer."); return false
	for side in [-1,1]:
		var candidate: Vector3 = player_bike.position+player_bike.global_basis.x*float(side)*1.7+Vector3.UP*1.5
		var ray := PhysicsRayQueryParameters3D.create(candidate,candidate-Vector3.UP*5,1)
		var hit: Dictionary = session.world.get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty(): continue
		candidate = hit.position+Vector3.UP*.08
		if session.position_clear(candidate):
			_unmount_at(candidate)
			session.save_game()
			return true
	session.show_message("Aproxime a moto de um local livre para descer.")
	return false

func _physics_process(delta: float) -> void:
	if session == null or not session.ready_for_play: return
	if ambient != null: ambient.update(delta)
	_update_surface(delta)
	if not mounted:
		_clock += delta
		if _clock > 1:
			_clock = 0
			if progress.data.owned and not is_instance_valid(owned_bike) and session.state.region_id == "harbor" and session.world.player.position.distance_to(COURSE.ENTRY) < 140: _park_owned()
			_idle_board()
		return
	if not is_instance_valid(player_bike):
		if active: finish(false)
		else: _unmount_at(COURSE.ENTRY+Vector3(2,0,2))
		return
	if session.world.gameplay.health <= 0 or session.is_transition_blocked() or session.state.region_id != "harbor":
		if active: finish(false)
		else: _unmount_at(player_bike.position+Vector3(2,0,0))
		return
	if start_shot.active:
		session.world.player.position = player_bike.position
		if not session.modal: start_shot.update(delta)
		_status.text = "Preparando largada · %s"%MODELS.MODELS[player_bike.profile_id].name
		return
	# Pause/menu freezes every racer, including recovery, so opening a menu is fair.
	for row in racers:
		row.bike.race_enabled = not session.modal and countdown <= 0
		row.bike.set_physics_process(not session.modal)
	player_bike.race_enabled = not session.modal and (not active or countdown <= 0)
	player_bike.set_physics_process(not session.modal)
	session.world.player.position = player_bike.position
	session.world.player.input_locked = true
	if session.modal: return
	if active and countdown > 0:
		countdown = maxf(0,countdown-delta)
		_hold_revs(delta)
		if countdown <= _gate_drop_at: _drop_gate()
		else: _status.present_start(launch_rev,"PREPARAR" if countdown > 1.4 else "ATENÇÃO · PLACA DE LADO")
		_update_info(delta)
		return
	if autopilot and active: _drive_ai(racers[0],delta)
	elif practice_autopilot and not practice.is_empty(): _drive_ai(practice,delta)
	else:
		var throttle := maxf(Input.get_action_strength("move_up"),Input.get_action_strength("accelerate"))-maxf(Input.get_action_strength("move_down"),Input.get_action_strength("brake"))
		var steering := Input.get_axis("move_right","move_left")
		var lean := Input.get_axis("move_up","move_down")
		var touch: Vector2 = get_node("/root/GameInput").touch_move
		if not touch.is_zero_approx():
			steering = -touch.x
			lean = touch.y
		player_bike.drive(throttle,steering,Input.is_action_pressed("handbrake"))
		# Strong enough to square a 0.4 s flight to the landing face, and to
		# over-rotate when W stays held from lip to landing.
		player_bike.air_lean = lean*.8
	if not active:
		if is_instance_valid(rental_bike) and (player_bike.position.distance_to(COURSE.ENTRY) > 180 or player_bike.position.y < -4):
			player_bike.reset_to(track.pose(0))
			practice.lap_start = -1.0
			practice.gate = 0
			practice.previous = player_bike.position
		_practice_lap(delta)
		_status.present_practice(player_bike,int(practice.laps),float(practice.clock),float(practice.lap_start) >= 0.0,float(progress.data.get("best_lap",0.0)),float(practice.best),"DEVOLVER A MOTO" if is_instance_valid(rental_bike) else "DESCER DA MOTO")
		_update_info(delta)
		return
	elapsed += delta
	var total := int(PROGRESS.LEVELS[difficulty].laps)*track.gates.size()
	for i in racers.size():
		var row: Dictionary = racers[i]
		var bike = row.bike
		if i > 0: _drive_ai(row,delta)
		var closest := track.nearest(bike.position)
		row.route_distance = float(closest.distance)
		var outside: bool = float(closest.lateral) > float(PROGRESS.LEVELS[difficulty].width)*.5+2.0 or bike.position.y < float(closest.point.y)-4
		row.outside = float(row.outside)+delta if outside else 0.0
		row.stalled = float(row.stalled)+delta if absf(bike.speed)<.3 and bike.crash_state=="riding" else 0.0
		if float(row.outside) > 1.0 or (i > 0 and float(row.stalled) > 6):
			_reset_racer(row)
			if i == 0: _status.callout("FORA DA PISTA","Volta ao último ponto de controle",Color("f08a5d"),2)
			continue
		if _cross_gate(row,bike,delta,outside):
			row.times.append(elapsed)
			var split := int(row.passed)-1
			if split < _leader_splits.size() and _leader_splits[split] < 0.0: _leader_splits[split] = elapsed
			if int(row.passed)%track.gates.size() == 0:
				var lap := elapsed-float(row.lap_start)
				row.lap_start = elapsed
				if float(row.best) <= 0.0 or lap < float(row.best): row.best = lap
				if i == 0 and int(row.passed) < total: _race_lap(lap,int(row.passed)/track.gates.size())
				if i == 0: progress.record_lap(lap)
			if int(row.passed) >= total:
				finish(i==0,"finished")
				return
	var placement := 1
	for i in range(1,racers.size()):
		if _race_distance(racers[i]) > _race_distance(racers[0]): placement += 1
	_announce_place(placement,delta)
	_marker.position = track.gates[int(racers[0].gate)]+Vector3.UP*3
	_status.present(placement,racers.size(),mini(int(PROGRESS.LEVELS[difficulty].laps),int(racers[0].passed)/track.gates.size()+1),PROGRESS.LEVELS[difficulty].laps,elapsed,player_bike,_gap_text())
	_update_info(delta)
	if elapsed > 360: finish(false,"time")

## Sequential gates plus plausible displacement prevent shortcuts/teleports.
func _cross_gate(row: Dictionary, bike: CharacterBody3D, delta: float, outside: bool) -> bool:
	var target: Vector3 = track.gates[int(row.gate)]
	var previous: Vector3 = row.previous
	row.previous = bike.position
	var moved: float = previous.distance_to(bike.position)
	var crossing := Geometry3D.get_closest_point_to_segment(target,previous,bike.position)
	var toward := track.sample(float(row.gate)*track.length/track.gates.size()+1)-target
	if outside or moved > maxf(3,30*delta) or bike.crash_state != "riding" or crossing.distance_to(target) >= 5.6 or (bike.position-previous).dot(toward) <= 0: return false
	row.passed += 1
	row.gate = (int(row.gate)+1)%track.gates.size()
	return true

func _hold_revs(delta: float) -> void:
	# Keyboard throttle is on/off, so holding the zone means feathering it;
	# analogue triggers and the touch pedal can simply hold a partial value.
	var throttle := maxf(Input.get_action_strength("move_up"),Input.get_action_strength("accelerate"))
	if autopilot: throttle = .7
	var goal := clampf(throttle,0.0,1.0)
	launch_rev = move_toward(launch_rev,goal,delta*(1.05 if goal > launch_rev else .9))

static func launch_quality(rev: float) -> String:
	if rev >= HUD.REV_ZONE.x and rev <= HUD.REV_ZONE.y: return "holeshot"
	if rev > .93: return "wheelie"
	if rev < .3: return "bog"
	return "good"

func _drop_gate() -> void:
	countdown = 0
	var gate: Node3D = _course_gate()
	if gate != null: gate.drop_gate()
	launch_result = launch_quality(launch_rev)
	racers[0].bike.launch(launch_result)
	var odds: Array = RIVAL_LAUNCH[difficulty]
	for i in range(1,racers.size()):
		var roll := _launch_rng.randf()
		var quality := "holeshot" if roll < float(odds[0]) else ("bog" if roll < float(odds[0])+float(odds[1]) else ("wheelie" if roll < float(odds[0])+float(odds[1])+float(odds[2]) else "good"))
		racers[i].bike.launch(quality)
	match launch_result:
		"holeshot": _status.callout("HOLESHOT!","Largada perfeita",Color("8ee29f"),3)
		"wheelie": _status.callout("EMPINOU","Giro alto demais na largada",Color("f08a5d"),3)
		"bog": _status.callout("LARGADA LENTA","Motor sem giro quando a grade caiu",Color("f3b96c"),3)
		_: _status.callout("LARGOU!","",Color("f0f3f4"),3)

func _race_lap(lap: float, completed: int) -> void:
	var laps := int(PROGRESS.LEVELS[difficulty].laps)
	var best := float(progress.data.get("best_lap",0.0))
	var record := lap >= PROGRESS.MIN_LAP and (best <= 0.0 or lap < best)
	var detail := "Volta %d · %s%s"%[completed,HUD.clock(lap)," · RECORDE DA PISTA" if record else ""]
	if completed == laps-1: _status.callout("ÚLTIMA VOLTA",detail,Color("ffc34f"),4)
	else: _status.callout("VOLTA %d/%d"%[completed+1,laps],detail,Color("ffc34f") if record else Color("f0f3f4"),4)

func _practice_lap(delta: float) -> void:
	if practice.is_empty() or not is_instance_valid(player_bike): return
	var timing := float(practice.lap_start) >= 0.0
	if timing: practice.clock = float(practice.clock)+delta
	var closest := track.nearest(player_bike.position)
	var outside := float(closest.lateral) > track.HALF_WIDTH+2.5
	if not _cross_gate(practice,player_bike,delta,outside): return
	if int(practice.gate) != 1: return
	# Crossing the start/finish line either opens the first timed lap or closes one.
	if timing and int(practice.passed) > track.gates.size():
		var lap := float(practice.clock)
		var record := progress.record_lap(lap)
		if float(practice.best) <= 0.0 or lap < float(practice.best): practice.best = lap
		practice.laps = int(practice.laps)+1
		_status.callout(HUD.clock(lap),"RECORDE DA PISTA" if record else ("melhor do treino %s"%HUD.clock(float(practice.best))),Color("ffc34f") if record else Color("f0f3f4"),4)
	practice.passed = 1
	practice.lap_start = 0.0
	practice.clock = 0.0

func _on_player_landed(quality: String, air_time: float) -> void:
	if quality == "perfect": _status.callout("POUSO PERFEITO","%.1f s no ar · impulso"%air_time,Color("8ee29f"),1)
	elif quality == "rough": _status.callout("POUSO DURO","Incline a moto para acompanhar a rampa",Color("f08a5d"),1)

func _announce_place(placement: int, delta: float) -> void:
	# Side-by-side riders swap order for a few frames; only a held change counts.
	if _announced_place == 0 or elapsed < 2.0:
		_announced_place = placement
		return
	if placement == _announced_place:
		_place_hold = 0.0
		return
	_place_hold += delta
	if _place_hold < .7: return
	var mine := _race_distance(racers[0])
	var other := ""
	var nearest_gap := INF
	for i in range(1,racers.size()):
		var gap := _race_distance(racers[i])-mine
		# Improved: the rival just behind. Lost ground: the rival just ahead.
		if (placement < _announced_place and gap < 0.0 and -gap < nearest_gap) or (placement > _announced_place and gap > 0.0 and gap < nearest_gap):
			nearest_gap = absf(gap)
			other = racers[i].bike.rider_name
	if placement < _announced_place: _status.callout("%dº LUGAR"%placement,"Você passou %s"%other if not other.is_empty() else "",Color("8ee29f"),2)
	else: _status.callout("%dº LUGAR"%placement,"%s passou você"%other if not other.is_empty() else "",Color("f08a5d"),2)
	_announced_place = placement
	_place_hold = 0.0

func _gap_text() -> String:
	var me: Dictionary = racers[0]
	var mine := _race_distance(me)
	var ahead: Dictionary = {}
	var behind: Dictionary = {}
	for i in range(1,racers.size()):
		var gap := _race_distance(racers[i])-mine
		if gap > 0.0 and (ahead.is_empty() or gap < _race_distance(ahead)-mine): ahead = racers[i]
		elif gap <= 0.0 and (behind.is_empty() or gap > _race_distance(behind)-mine): behind = racers[i]
	if not ahead.is_empty():
		var count := int(me.passed)
		if count <= 0 or ahead.times.size() < count: return "À FRENTE · %s"%ahead.bike.rider_name
		return "À FRENTE · %s +%s s"%[ahead.bike.rider_name,("%.1f"%(float(me.times[count-1])-float(ahead.times[count-1]))).replace(".",",")]
	if not behind.is_empty():
		var count := int(behind.passed)
		if count <= 0 or me.times.size() < count: return "LIDERANDO"
		return "LIDERANDO · %s s sobre %s"%[("%.1f"%(float(behind.times[count-1])-float(me.times[count-1]))).replace(".",","),behind.bike.rider_name]
	return ""

func _update_info(delta: float) -> void:
	# Rival tags and the race-control board refresh at 4 Hz, not every tick.
	_info_clock += delta
	if _info_clock < .25: return
	_info_clock = 0.0
	var course := _course()
	if active:
		var order := racers.duplicate()
		order.sort_custom(func(a,b): return _race_distance(a) > _race_distance(b))
		for place in order.size():
			var tag: Label3D = _tags.get(order[place].bike.get_instance_id())
			if is_instance_valid(tag): tag.text = "%d · %s"%[place+1,order[place].bike.rider_name]
		if course == null: return
		if countdown > 0: course.set_board("LARGADA","%s · %d VOLTAS"%[str(PROGRESS.LEVELS[difficulty].name).to_upper(),int(PROGRESS.LEVELS[difficulty].laps)])
		else:
			var laps := int(PROGRESS.LEVELS[difficulty].laps)
			var lap := mini(laps,int(order[0].passed)/track.gates.size()+1)
			course.set_board("VOLTA %d/%d"%[lap,laps],"1º %s · 2º %s"%[order[0].bike.rider_name,order[1].bike.rider_name] if order.size() > 1 else "")
	elif course != null and mounted and not practice.is_empty():
		course.set_board("TREINO",HUD.clock(float(practice.clock)) if float(practice.lap_start) >= 0.0 else "PISTA LIVRE")

func _idle_board() -> void:
	var course := _course()
	if course == null: return
	var best := float(progress.data.get("best_lap",0.0))
	course.set_board("VÉRTICE MX","RECORDE %s"%HUD.clock(best) if best > 0.0 else "PISTA ABERTA")

func _race_distance(row: Dictionary) -> float:
	# The race loop caches each rider's route distance once per tick.
	var d := float(row.get("route_distance",-1.0))
	if d < 0.0: d = float(track.nearest(row.bike.position).distance)
	var previous_gate := posmod(int(row.gate)-1,track.gates.size())
	var spacing := track.length/track.gates.size()
	# Signed: riders still behind the line on the grid rank by how far back they are.
	return float(row.passed)+clampf(wrapf(d-float(previous_gate)*spacing,-track.length*.5,track.length*.5)/spacing,-3.0,.99)

func _update_surface(delta: float) -> void:
	var rain := 0.0
	if session.weather != null:
		if session.weather.weather_state == 1: rain = .8
		elif session.weather.weather_state == 2: rain = 1.0
	wetness = move_toward(wetness,rain,delta*(.12 if rain > wetness else .006))
	_weather_clock += delta
	if _weather_clock > .2:
		_weather_clock = 0
		for course in get_tree().get_nodes_in_group("motocross_course"): course.set_wetness(wetness)
		for venue in get_tree().get_nodes_in_group("motocross_paddock"): venue.configure(session.world.player)
		for spectator in get_tree().get_nodes_in_group("motocross_spectator"): spectator.bind_combat(session.world.gameplay)
		for bike in get_tree().get_nodes_in_group("motocross_bikes"): bike.bind_combat(session.world.gameplay)
		for venue in get_tree().get_nodes_in_group("motocross_scenery"):
			var daylight: float = session.weather.atmosphere.daylight_at(session.weather.time_of_day) if session.weather != null else 1.0
			venue.set_lighting(1.0-smoothstep(.25,.70,daylight),session.world.player.position)
	for row in racers: row.bike.wetness = wetness
	if ambient != null:
		for row in ambient.rows: row.bike.wetness = wetness
	if is_instance_valid(owned_bike): owned_bike.wetness = wetness
	if is_instance_valid(rental_bike): rental_bike.wetness = wetness
	if surface_effects != null:
		var riders: Array = racers.duplicate()
		if ambient != null: riders.append_array(ambient.rows)
		if not active and mounted and is_instance_valid(player_bike): riders.append(player_bike)
		surface_effects.update_riders(riders,wetness)

func _drive_ai(row: Dictionary,delta: float = 1.0/60.0) -> void:
	var nearby: Array = ambient.rows if bool(row.bike.get_meta("motocross_ambient",false)) and ambient!=null else racers
	preload("res://activities/motocross/MotocrossPilot.gd").drive(row,track,nearby,float(row.get("pace",float(PROGRESS.LEVELS[difficulty].speed)+1.0)),delta)

func _reset_racer(row: Dictionary) -> void:
	var checkpoint := posmod(int(row.gate)-1,track.gates.size())
	var pose := track.pose(float(checkpoint)*track.length/track.gates.size(),float(row.lane))
	row.bike.reset_to(pose)
	row.previous = pose.origin
	row.outside = 0.0
	row.stalled = 0.0
	row.respawns += 1
	# Recovery costs actual race time; rivals keep moving.
	row.bike.crash(.25)

## reason: "finished" (someone crossed the line), "quit", "time" or "" (external).
func finish(won: bool, reason := "") -> void:
	if not active: return
	start_shot.stop()
	var placement := _classify(won, reason)
	active = false
	var gate: Node3D = _course_gate()
	if gate != null and gate.raised: gate.drop_gate()
	var was_owned: bool = progress.data.owned
	var prize := progress.settle(session.state.economy,won)
	if not was_owned and progress.data.owned: progress.data.bike_model = player_bike.profile_id
	_unmount_at(COURSE.ENTRY+Vector3(2,0,2))
	for row in racers:
		if is_instance_valid(row.bike): row.bike.queue_free()
	racers.clear()
	_tags.clear()
	_marker.hide()
	if progress.data.owned: _park_owned()
	session.save_game()
	_idle_board()
	session.show_message(("Vitória! +R$ %d (inscrição + R$ %d de lucro)."%[prize,PROGRESS.LEVELS[difficulty].bonus]) if won else ("%dº lugar · inscrição de R$ %d perdida."%[placement,PROGRESS.LEVELS[difficulty].fee] if reason == "finished" else "Derrota · inscrição de R$ %d perdida."%PROGRESS.LEVELS[difficulty].fee))
	if not was_owned and progress.data.owned: session.show_message("Vitória! +R$ %d. A motocross é sua: retire-a na entrada."%prize)

## Builds the results card from the live timing and returns the player's place.
func _classify(won: bool, reason: String) -> int:
	if racers.is_empty(): return 0
	var order := racers.duplicate()
	order.sort_custom(func(a,b): return _race_distance(a) > _race_distance(b))
	var leader: Dictionary = order[0]
	var rows: Array = []
	var placement := 0
	for index in order.size():
		var row: Dictionary = order[index]
		var detail := ""
		var count := int(row.passed)
		if index == 0: detail = HUD.clock(elapsed) if reason == "finished" else "líder"
		elif count > 0 and leader.times.size() >= count:
			var laps_down := (int(leader.passed)-count)/track.gates.size()
			# Gap at the last timing gate both riders crossed, as on a timing loop.
			var gap := float(row.times[count-1])-float(leader.times[count-1])
			detail = "+%d volta%s"%[laps_down,"s" if laps_down > 1 else ""] if laps_down > 0 else "+%s s"%("%.1f"%gap).replace(".",",")
		else: detail = "—"
		if row == racers[0]: placement = index+1
		rows.append({"place":index+1,"name":row.bike.rider_name,"detail":detail,"player":row == racers[0]})
	var title := "VITÓRIA" if won else ("DESISTÊNCIA" if reason == "quit" else ("TEMPO ESGOTADO" if reason == "time" else "%dº LUGAR"%placement))
	var me: Dictionary = racers[0]
	var best := float(progress.data.get("best_lap",0.0))
	var footer := "%s · %d volta%s"%[str(PROGRESS.LEVELS[difficulty].name),int(PROGRESS.LEVELS[difficulty].laps),"s" if int(PROGRESS.LEVELS[difficulty].laps) > 1 else ""]
	if float(me.best) > 0.0: footer += " · sua melhor volta %s"%HUD.clock(float(me.best))
	if best > 0.0: footer += " · recorde %s"%HUD.clock(best)
	if launch_result == "holeshot": footer += " · holeshot"
	footer += " · pousos perfeitos: %d"%int(me.bike.perfect_landings)
	_status.show_results(title,rows,footer)
	return placement

func _park_owned(recall := false) -> void:
	if not progress.data.owned or mounted: return
	if not is_instance_valid(owned_bike):
		owned_bike = BIKE.new()
		owned_bike.is_player = true
		MODELS.apply(owned_bike,int(progress.data.get("bike_model",0)))
		owned_bike.rider_name = "Dante"
		session.world.add_child(owned_bike)
	elif not recall: return
	owned_bike.reset_to(Transform3D(Basis.IDENTITY,COURSE.ENTRY+Vector3(4,.15,-3)))
	owned_bike.race_enabled = false
	owned_bike.rider.hide()

func _exit_tree() -> void:
	start_shot.stop()
	if ambient != null: ambient.clear()
	track.free()
	if is_instance_valid(surface_effects): surface_effects.queue_free()
	if is_instance_valid(_status): _status.queue_free()
	if is_instance_valid(_marker): _marker.queue_free()
