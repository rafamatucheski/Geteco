extends "res://AnimatedPedestrian3D.gd"
## Carga local com estoque conservado; combate e socorro seguem o pedestre comum.
signal crate_handled(point: Vector2)
const PART := preload("res://world/shared/pedestrians/CitizenDetails.gd")
var work_points := PackedVector2Array()
var work_route := PackedVector2Array()
var station_points := PackedVector2Array()
var worker_index := 0
var crate_stock := [3, 0]
var dropped_crates: Array[Vector2] = []
var carrying := false
var deliveries := 0
var phase := "pickup"
var phase_time := 0.0
var source_index := 0
var carried_box: Node3D
var left_crate_grip: Marker3D
var right_crate_grip: Marker3D
var route_cursor := 0
var completed_circuits := 0
var _transferred := false
var _turning := false
var _interrupted := false

func _ready() -> void:
	district_theme = DistrictTheme.CITY_DOWNTOWN
	archetype_override = 1
	appearance_seed = 180 + worker_index * 4
	body_type_override = worker_index % 3
	ambient_running_enabled = false
	base_walk_speed = 32.0 + worker_index * 2
	phase_time = worker_index * 0.45
	global_position = work_points[0]
	super._ready()
	add_to_group("harbor_dock_worker")

func _setup_district_and_archetype() -> void:
	super._setup_district_and_archetype()
	shirt_color = Color("344958")
	pants_color = Color("283848")
	shoe_color = Color("342b24")
	has_cap = false
	has_beanie = false
	has_coffee_cup = false
	has_backpack = false

func _build_3d_viewport() -> void:
	super._build_3d_viewport()
	for name in ["BaseHair", "HairStyle"]:
		var hair := head_node.get_node_or_null(name) as Node3D
		if hair: hair.hide()
	var hat := Node3D.new()
	hat.name = "SafetyHelmet"
	head_node.add_child(hat)
	var yellow := Color("f4cc40") if worker_index != 2 else Color("f1e9ca")
	PART.piece(hat, Vector3(.46,.045,.44), Vector3(0,.11,-.025), yellow, true)
	PART.piece(hat, Vector3(.39,.25,.36), Vector3(0,.16,0), yellow, true)
	PART.piece(hat, Vector3(.045,.035,.31), Vector3(0,.28,0), yellow.lightened(.15))
	var vest := Node3D.new()
	vest.name = "ReflectiveVest"
	torso_node.add_child(vest)
	PART.piece(vest, Vector3(.405,.43,.34), Vector3(0,.015,0), Color("ec792b") if worker_index != 1 else Color("d7d84d"))
	for z in [-.178,.178]:
		for x in [-.115,.115]:
			PART.piece(vest, Vector3(.045,.37,.016), Vector3(x,.02,z), Color("e6eac9"))
		PART.piece(vest, Vector3(.41,.05,.018), Vector3(0,-.09,z), Color("e6eac9"))
	for arm in [left_lower_arm,right_lower_arm]:
		PART.piece(arm, Vector3(.11,.10,.12), Vector3(0,-.19,0), Color("c6b596"), true)
	left_crate_grip = Marker3D.new()
	left_crate_grip.position = Vector3(0,-.19,0)
	left_lower_arm.add_child(left_crate_grip)
	right_crate_grip = Marker3D.new()
	right_crate_grip.position = Vector3(0,-.19,0)
	right_lower_arm.add_child(right_crate_grip)
	carried_box = Node3D.new()
	carried_box.name = "CarriedCrate"
	# O peito balança separadamente dos braços: a carga acompanha os apoios.
	model_root.add_child(carried_box)
	PART.piece(carried_box,Vector3(.46,.34,.36),Vector3.ZERO,Color("ab7c49"))
	for x in [-.17,.17]:
		PART.piece(carried_box,Vector3(.05,.35,.38),Vector3(x,0,0),Color("d0a66b"))
	PART.piece(carried_box,Vector3(.15,.11,.008),Vector3(0,.035,-.184),Color("e2d5aa"))
	carried_box.hide()

func _pick_new_sidewalk_target() -> void:
	if not work_route.is_empty(): walk_target = work_route[route_cursor]

func _ambient_walk_paused() -> bool:
	return _turning or phase in ["pickup", "put_down", "rest"]

func _navigate_towards(dest: Vector2, move_speed: float, delta: float) -> Vector2:
	# Corredores retos verificados entre os contêineres. move_and_slide preserva sólidos.
	return (dest-global_position).limit_length(move_speed * delta) / maxf(delta,.001)

func _set_phase(next_phase: String) -> void:
	phase = next_phase
	phase_time = 0.0
	_transferred = false

func _next_corner() -> void:
	route_cursor = (route_cursor + 1) % work_route.size()
	_pick_new_sidewalk_target()

func _physics_process(delta: float) -> void:
	var disturbed := is_scared or is_dead or is_incapacitated or is_flying
	_turning = false
	if disturbed:
		if carrying:
			dropped_crates.append(global_position)
			carrying = false
			crate_handled.emit(global_position)
		_interrupted = true
	elif _interrupted:
		_interrupted = false
		_set_phase("return")
		_pick_new_sidewalk_target()
	elif phase in ["carry", "return"]:
		if global_position.distance_to(walk_target) < 2:
			if carrying and route_cursor == (1-source_index)*2:
				_set_phase("put_down")
			elif not carrying and route_cursor == source_index*2:
				completed_circuits += 1
				_set_phase("pickup")
			else:
				_next_corner()
	else:
		phase_time += delta
		if phase == "pickup":
			if not _transferred and phase_time >= .9:
				_transferred = true
				if crate_stock[source_index] > 0:
					crate_stock[source_index] -= 1
					carrying = true
					crate_handled.emit(station_points[source_index])
			if phase_time >= 1.8:
				_set_phase("carry" if carrying else "rest")
				if carrying: _next_corner()
		elif phase == "put_down":
			if not _transferred and phase_time >= .9:
				_transferred = true
				crate_stock[1-source_index] += 1
				carrying = false
				deliveries += 1
				crate_handled.emit(station_points[1-source_index])
			if phase_time >= 1.6: _set_phase("rest")
		elif phase == "rest" and phase_time >= 1.0 + worker_index*.2:
			# Transporta o lote inteiro antes de inverter os postos, preservando
			# as três caixas. Entre entregas, completa a outra metade sem carga.
			if crate_stock[source_index] == 0 and crate_stock[1-source_index] > 0:
				source_index = 1-source_index
			if crate_stock[source_index] > 0:
				_set_phase("pickup" if route_cursor == source_index*2 else "return")
				if phase == "return": _next_corner()
	if not disturbed:
		var destination := walk_target
		if phase == "pickup": destination = station_points[source_index]
		elif phase == "put_down": destination = station_points[1-source_index]
		var direction := global_position.direction_to(destination)
		if not direction.is_zero_approx():
			walk_dir = direction
			if _viewport_render_active:
				var target_yaw := -atan2(direction.y, direction.x) - PI*.5
				_turning = absf(angle_difference(model_root.rotation.y, target_yaw)) > .18
	super._physics_process(delta)
	if is_instance_valid(carried_box): carried_box.visible = carrying
	if disturbed or not _viewport_render_active: return
	_update_carry_pose()

func _update_carry_pose() -> void:
	if get_meta("port_guiding",false) and not carrying and phase not in ["pickup","put_down"]:
		# Banksman gives a visible hand signal from outside the truck's swept path.
		right_upper_arm.rotation = Vector3(2.35,0,.22*sin(phase_time*4))
		right_lower_arm.rotation = Vector3(.3,0,0)
		return
	if not carrying and phase not in ["pickup", "put_down"]: return
	var reach := 1.0
	if phase == "pickup": reach = smoothstep(0.0, 1.8, phase_time)
	elif phase == "put_down": reach = 1.0 - smoothstep(0.0, 1.6, phase_time)
	# O rosto aponta para -Z. Rotações positivas levam as mãos à frente;
	# os sinais negativos anteriores dobravam os braços para as costas.
	for upper in [left_upper_arm, right_upper_arm]:
		upper.rotation = Vector3(lerpf(.28, .70, reach), 0, 0)
	for lower in [left_lower_arm, right_lower_arm]:
		lower.rotation = Vector3(lerpf(.20, .85, reach), 0, 0)
	var left := model_root.to_local(left_crate_grip.global_position)
	var right := model_root.to_local(right_crate_grip.global_position)
	carried_box.position = (left + right)*.5 + Vector3(0,.035,-.025)
	carried_box.scale.x = absf(right.x-left.x)/.46
	if phase in ["pickup", "put_down"]:
		torso_node.rotation.x = -.18*sin(clampf(phase_time/1.8,0,1)*PI)

func crate_total() -> int:
	return crate_stock[0] + crate_stock[1] + int(carrying) + dropped_crates.size()
