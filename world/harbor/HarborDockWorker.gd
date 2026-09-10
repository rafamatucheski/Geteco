extends "res://AnimatedPedestrian3D.gd"
## Carga local com estoque conservado; combate e socorro seguem o pedestre comum.
signal crate_handled(point: Vector2)
const PART := preload("res://world/shared/pedestrians/CitizenDetails.gd")
var work_points := PackedVector2Array()
var worker_index := 0
var crate_stock := [3, 0]
var dropped_crates: Array[Vector2] = []
var carrying := false
var deliveries := 0
var phase := "pickup"
var phase_time := 0.0
var source_index := 0
var carried_box: Node3D
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
	carried_box = Node3D.new()
	carried_box.name = "CarriedCrate"
	carried_box.position = Vector3(0,-.04,-.42)
	torso_node.add_child(carried_box)
	PART.piece(carried_box,Vector3(.46,.34,.36),Vector3.ZERO,Color("ab7c49"))
	for x in [-.17,.17]:
		PART.piece(carried_box,Vector3(.05,.35,.38),Vector3(x,0,0),Color("d0a66b"))
	PART.piece(carried_box,Vector3(.15,.11,.008),Vector3(0,.035,-.184),Color("e2d5aa"))
	carried_box.hide()

func _pick_new_sidewalk_target() -> void:
	if work_points.size() == 2:
		walk_target = work_points[1 - source_index if phase in ["carry", "put_down"] else source_index]

func _ambient_walk_paused() -> bool:
	return phase in ["pickup", "put_down", "rest"]

func _navigate_towards(dest: Vector2, move_speed: float, delta: float) -> Vector2:
	# Corredores retos verificados entre os contêineres. move_and_slide preserva sólidos.
	return (dest-global_position).limit_length(move_speed * delta) / maxf(delta,.001)

func _physics_process(delta: float) -> void:
	var disturbed := is_scared or is_dead or is_incapacitated or is_flying
	if disturbed:
		if carrying:
			dropped_crates.append(global_position)
			carrying = false
			crate_handled.emit(global_position)
		_interrupted = true
	elif _interrupted:
		_interrupted = false
		phase = "return"
		phase_time = 0
		_pick_new_sidewalk_target()
	elif phase == "carry" or phase == "return":
		if global_position.distance_to(walk_target) < 5:
			phase = "put_down" if carrying else "pickup"
			phase_time = 0
	else:
		phase_time += delta
		if phase == "pickup" and phase_time >= 1.8:
			if crate_stock[source_index] > 0:
				crate_stock[source_index] -= 1
				carrying = true
				crate_handled.emit(global_position)
				phase = "carry"
				_pick_new_sidewalk_target()
			else:
				phase = "rest"
			phase_time = 0
		elif phase == "put_down" and phase_time >= 1.6:
			crate_stock[1-source_index] += 1
			carrying = false
			deliveries += 1
			crate_handled.emit(global_position)
			phase = "rest"
			phase_time = 0
		elif phase == "rest" and phase_time >= 2.5 + worker_index:
			source_index = 1-source_index
			phase = "return"
			_pick_new_sidewalk_target()
	super._physics_process(delta)
	if is_instance_valid(carried_box):
		carried_box.visible = carrying
	if disturbed or not _viewport_render_active: return
	if carrying or phase in ["pickup", "put_down"]:
		left_upper_arm.rotation.x = -0.85
		right_upper_arm.rotation.x = -0.85
		left_lower_arm.rotation.x = -0.8
		right_lower_arm.rotation.x = -0.8
		if not phase == "carry":
			var bend := sin(clampf(phase_time/1.8,0,1)*PI)
			torso_node.rotation.x = -.22*bend
			carried_box.position.y = -.04 - .18*bend
	else:
		torso_node.rotation.x = 0

func crate_total() -> int:
	return crate_stock[0] + crate_stock[1] + int(carrying) + dropped_crates.size()
