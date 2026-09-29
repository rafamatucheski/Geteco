extends Node
const PROGRESS := preload("res://activities/motocross/MotocrossProgress.gd")
const COURSE := preload("res://activities/motocross/MotocrossCourse.gd")
const BIKE := preload("res://activities/motocross/MotocrossBike.gd")
const MODELS := preload("res://activities/motocross/MotocrossModels.gd")
var selected_model := 0
var start_shot := preload("res://activities/motocross/MotocrossStart.gd").new()
var ambient
var session
var progress := PROGRESS.new()
var track := COURSE.new()
var active := false
var mounted := false
var autopilot := false
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
			session._button("Desistir",func(): session.close_menu(); finish(false))
		"dismount": dismount()
		"ride": _mount(owned_bike)
		"enter": _menu()
		_: return false
	return true

func _menu() -> void:
	session._menu("Vértice · Motocross")
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
	elapsed = 0
	active = true
	var spec: Dictionary = PROGRESS.LEVELS[level]
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
		bike.reset_to(track.pose(-float(i/2)*3.5, -1.4 if i%2 == 0 else 1.4))
		racers.append({"bike":bike,"gate":1,"passed":0,"previous":bike.position,"outside":0.0,"stalled":0.0,"lane":(-.9 if i%2==0 else .9),"respawns":0})
	_mount(racers[0].bike)
	start_shot.begin(self)
	_marker.show()
	return true

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
	player_bike = null
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
		_status.text = "Largada em %d"%ceili(countdown)
		return
	if autopilot and active: _drive_ai(racers[0],delta)
	else:
		var throttle := maxf(Input.get_action_strength("move_up"),Input.get_action_strength("accelerate"))-maxf(Input.get_action_strength("move_down"),Input.get_action_strength("brake"))
		var steering := Input.get_axis("move_right","move_left")
		var lean := Input.get_axis("move_up","move_down")
		var touch: Vector2 = get_node("/root/GameInput").touch_move
		if not touch.is_zero_approx():
			steering = -touch.x
			lean = touch.y
		player_bike.drive(throttle,steering,Input.is_action_pressed("handbrake"))
		player_bike.air_lean = lean*.45
	if not active:
		if is_instance_valid(rental_bike) and (player_bike.position.distance_to(COURSE.ENTRY) > 180 or player_bike.position.y < -4): player_bike.reset_to(track.pose(0))
		_status.text = ("Treino · %d km/h · E devolver" if is_instance_valid(rental_bike) else "Motocross · %d km/h · E descer")%int(absf(player_bike.speed)*3.6)
		return
	elapsed += delta
	var total := int(PROGRESS.LEVELS[difficulty].laps)*track.gates.size()
	for i in racers.size():
		var row: Dictionary = racers[i]
		var bike = row.bike
		if i > 0: _drive_ai(row,delta)
		var closest := track.nearest(bike.position)
		var outside: bool = float(closest.lateral) > float(PROGRESS.LEVELS[difficulty].width)*.5+2.0 or bike.position.y < float(closest.point.y)-4
		row.outside = float(row.outside)+delta if outside else 0.0
		row.stalled = float(row.stalled)+delta if absf(bike.speed)<.3 and bike.crash_state=="riding" else 0.0
		if float(row.outside) > 1.0 or (i > 0 and float(row.stalled) > 6):
			_reset_racer(row)
			continue
		# Sequential gates plus plausible displacement prevent shortcuts/teleports.
		var target: Vector3 = track.gates[int(row.gate)]
		var previous: Vector3 = row.previous
		var moved: float = previous.distance_to(bike.position)
		var crossing := Geometry3D.get_closest_point_to_segment(target,previous,bike.position)
		var toward := track.sample(float(row.gate)*track.length/track.gates.size()+1)-target
		if not outside and moved <= maxf(3,30*delta) and bike.crash_state == "riding" and crossing.distance_to(target) < 5.6 and (bike.position-previous).dot(toward)>0:
			row.passed += 1
			row.gate = (int(row.gate)+1)%track.gates.size()
			if int(row.passed) >= total:
				finish(i==0)
				return
		row.previous = bike.position
	var placement := 1
	for i in range(1,racers.size()):
		if _race_distance(racers[i]) > _race_distance(racers[0]): placement += 1
	_marker.position = track.gates[int(racers[0].gate)]+Vector3.UP*3
	_status.present(placement,racers.size(),mini(int(PROGRESS.LEVELS[difficulty].laps),int(racers[0].passed)/track.gates.size()+1),PROGRESS.LEVELS[difficulty].laps,elapsed,player_bike)
	if elapsed > 360: finish(false)

func _race_distance(row: Dictionary) -> float:
	var d := float(track.nearest(row.bike.position).distance)
	var previous_gate := posmod(int(row.gate)-1,track.gates.size())
	var spacing := track.length/track.gates.size()
	return float(row.passed)+clampf(fposmod(d-float(previous_gate)*spacing,track.length)/spacing,0,.99)

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

func finish(won: bool) -> void:
	if not active: return
	start_shot.stop()
	active = false
	var was_owned: bool = progress.data.owned
	var prize := progress.settle(session.state.economy,won)
	if not was_owned and progress.data.owned: progress.data.bike_model = player_bike.profile_id
	_unmount_at(COURSE.ENTRY+Vector3(2,0,2))
	for row in racers:
		if is_instance_valid(row.bike): row.bike.queue_free()
	racers.clear()
	_marker.hide()
	if progress.data.owned: _park_owned()
	session.save_game()
	session.show_message(("Vitória! +R$ %d (inscrição + R$ %d de lucro)."%[prize,PROGRESS.LEVELS[difficulty].bonus]) if won else "Derrota · inscrição de R$ %d perdida."%PROGRESS.LEVELS[difficulty].fee)
	if not was_owned and progress.data.owned: session.show_message("Vitória! +R$ %d. A motocross é sua: retire-a na entrada."%prize)

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
