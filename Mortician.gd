class_name Mortician
extends CharacterBody2D

## Agente Funerário do IML / Necrotério
## Responsável por recolher corpos mortos em sacos de cadáver (body bag) e transportá-los ao Rabecão.

enum State { DISEMBARK, APPROACH, BAG_AND_LIFT, RETURN_HEARSE, EMBARKING, EMBARKED }

@export var speed: float = 110.0
@export var max_health: int = 60
@export var is_stretcher_bearer: bool = false

var target: Node2D = null
var hearse: Node2D = null
var state: State = State.APPROACH
## Second leg of a coroner run: the body was already picked up (target is
## gone), this legist just needs to walk to burial_position and place a
## marker there. See EmergencyVehicle.gd's _deploy_morticians_for_burial().
var is_burial_trip: bool = false
var burial_position: Vector2 = Vector2.ZERO

var health: int = 60
var is_dead: bool = false
var is_flying: bool = false
var fly_velocity: Vector2 = Vector2.ZERO
var walk_clock: float = 0.0

var collision_shape: CollisionShape2D
var bag_timer: float = 0.0
var crew_side := 1.0
var crew_longitudinal := 22.0
var boarding_started := false

# 3D SubViewport Rig
var viewport_3d: SubViewport
var sprite_3d_display: Sprite2D
var model_root: Node3D
var torso_node: Node3D
var head_node: Node3D
var left_upper_arm: Node3D
var left_lower_arm: Node3D
var right_upper_arm: Node3D
var right_lower_arm: Node3D
var left_upper_leg: Node3D
var left_lower_leg: Node3D
var right_upper_leg: Node3D
var right_lower_leg: Node3D
var stretcher_mesh: MeshInstance3D = null
var body_bag_mesh: MeshInstance3D = null

func _ready() -> void:
	add_to_group("mortician")
	add_to_group("damageable")
	health = max_health
	z_index = 6
	
	_build_3d_viewport()
	
	var col := CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = 5.0
	cap.height = 16.0
	col.shape = cap
	collision_shape = col
	add_child(col)

func _build_3d_viewport() -> void:
	viewport_3d = SubViewport.new()
	viewport_3d.size = Vector2i(96, 96)
	viewport_3d.transparent_bg = true
	viewport_3d.own_world_3d = true
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_3d.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(viewport_3d)

	var world_3d := World3D.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 1.0, 1.0)
	env.ambient_light_energy = 1.15
	world_3d.environment = env
	viewport_3d.world_3d = world_3d

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.45
	cam.position = Vector3(0.0, 10.0, 0.01)
	cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	cam.current = true
	viewport_3d.add_child(cam)

	var key_light := DirectionalLight3D.new()
	key_light.position = Vector3(5.0, 12.0, 5.0)
	key_light.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	key_light.light_color = Color(1.0, 0.98, 0.94)
	key_light.light_energy = 1.35
	viewport_3d.add_child(key_light)

	_build_mortician_rig()

	sprite_3d_display = Sprite2D.new()
	sprite_3d_display.name = "Sprite3DDisplay"
	sprite_3d_display.texture = viewport_3d.get_texture()
	sprite_3d_display.position = Vector2.ZERO
	add_child(sprite_3d_display)

func _build_mortician_rig() -> void:
	model_root = Node3D.new()
	model_root.name = "MorticianRig"
	viewport_3d.add_child(model_root)

	var mat_suit := _make_mat(Color(0.14, 0.15, 0.18), 0.5) # Terno Chumbo/Preto IML
	var mat_shirt := _make_mat(Color(0.92, 0.94, 0.96), 0.3) # Camisa Social Branca
	var mat_tie := _make_mat(Color(0.05, 0.05, 0.06), 0.7) # Gravata Preta
	var mat_skin := _make_mat(Color(0.88, 0.74, 0.62), 0.4) # Pele
	var mat_gloves := _make_mat(Color(0.22, 0.48, 0.88), 0.2) # Luvas Cirúrgicas Azuis
	var mat_shoes := _make_mat(Color(0.06, 0.06, 0.08), 0.8) # Sapatos Pretos

	# Tronco (Paletó Preto)
	torso_node = Node3D.new()
	torso_node.position = Vector3(0.0, 0.75, 0.0)
	model_root.add_child(torso_node)

	var torso_mesh := MeshInstance3D.new()
	var box_t := BoxMesh.new()
	box_t.size = Vector3(0.38, 0.52, 0.22)
	torso_mesh.mesh = box_t
	torso_mesh.material_override = mat_suit
	torso_node.add_child(torso_mesh)

	# Gravata & Colarinho
	var tie_mesh := MeshInstance3D.new()
	var box_tie := BoxMesh.new()
	box_tie.size = Vector3(0.08, 0.28, 0.03)
	tie_mesh.mesh = box_tie
	tie_mesh.material_override = mat_tie
	tie_mesh.position = Vector3(0.0, 0.08, -0.12)
	torso_node.add_child(tie_mesh)

	# Cabeça
	head_node = Node3D.new()
	head_node.position = Vector3(0.0, 1.22, 0.0)
	model_root.add_child(head_node)

	var head_mesh := MeshInstance3D.new()
	var sph_h := SphereMesh.new()
	sph_h.radius = 0.16
	sph_h.height = 0.32
	head_mesh.mesh = sph_h
	head_mesh.material_override = mat_skin
	head_node.add_child(head_mesh)

	# Óculos / Máscara Protetora
	var mask_mesh := MeshInstance3D.new()
	var box_m := BoxMesh.new()
	box_m.size = Vector3(0.18, 0.09, 0.06)
	mask_mesh.mesh = box_m
	mask_mesh.material_override = _make_mat(Color(0.85, 0.90, 0.95), 0.1)
	mask_mesh.position = Vector3(0.0, -0.04, -0.14)
	head_node.add_child(mask_mesh)

	# Braços (com luvas cirúrgicas)
	left_upper_arm = Node3D.new()
	left_upper_arm.position = Vector3(-0.24, 1.02, 0.0)
	model_root.add_child(left_upper_arm)
	left_upper_arm.add_child(_create_limb(0.050, 0.22, mat_suit, Vector3(0, -0.11, 0)))

	left_lower_arm = Node3D.new()
	left_lower_arm.position = Vector3(0, -0.22, 0)
	left_upper_arm.add_child(left_lower_arm)
	left_lower_arm.add_child(_create_limb(0.044, 0.18, mat_gloves, Vector3(0, -0.09, 0)))

	right_upper_arm = Node3D.new()
	right_upper_arm.position = Vector3(0.24, 1.02, 0.0)
	model_root.add_child(right_upper_arm)
	right_upper_arm.add_child(_create_limb(0.050, 0.22, mat_suit, Vector3(0, -0.11, 0)))

	right_lower_arm = Node3D.new()
	right_lower_arm.position = Vector3(0, -0.22, 0)
	right_upper_arm.add_child(right_lower_arm)
	right_lower_arm.add_child(_create_limb(0.044, 0.18, mat_gloves, Vector3(0, -0.09, 0)))

	# Pernas & Calça Social
	left_upper_leg = Node3D.new()
	left_upper_leg.position = Vector3(-0.11, 0.50, 0.0)
	model_root.add_child(left_upper_leg)
	left_upper_leg.add_child(_create_limb(0.058, 0.24, mat_suit, Vector3(0, -0.12, 0)))

	left_lower_leg = Node3D.new()
	left_lower_leg.position = Vector3(0, -0.24, 0)
	left_upper_leg.add_child(left_lower_leg)
	left_lower_leg.add_child(_create_limb(0.050, 0.24, mat_shoes, Vector3(0, -0.12, 0)))

	right_upper_leg = Node3D.new()
	right_upper_leg.position = Vector3(0.11, 0.50, 0.0)
	model_root.add_child(right_upper_leg)
	right_upper_leg.add_child(_create_limb(0.058, 0.24, mat_suit, Vector3(0, -0.12, 0)))

	right_lower_leg = Node3D.new()
	right_lower_leg.position = Vector3(0, -0.24, 0)
	right_upper_leg.add_child(right_lower_leg)
	right_lower_leg.add_child(_create_limb(0.050, 0.24, mat_shoes, Vector3(0, -0.12, 0)))

	# Maca Retrátil com Saco de Cadáver (se for carregador)
	if is_stretcher_bearer:
		_build_stretcher()

func _build_stretcher() -> void:
	var mat_metal := _make_mat(Color(0.65, 0.68, 0.72), 0.8)
	stretcher_mesh = MeshInstance3D.new()
	var box_s := BoxMesh.new()
	box_s.size = Vector3(0.42, 0.06, 0.85)
	stretcher_mesh.mesh = box_s
	stretcher_mesh.material_override = mat_metal
	stretcher_mesh.position = Vector3(0.0, 0.55, -0.55)
	model_root.add_child(stretcher_mesh)

	# Saco preto de cadáver (inicialmente invisível, aparece após ensacar)
	var mat_bag := _make_mat(Color(0.06, 0.06, 0.08), 0.9)
	body_bag_mesh = MeshInstance3D.new()
	var box_b := BoxMesh.new()
	box_b.size = Vector3(0.36, 0.16, 0.78)
	body_bag_mesh.mesh = box_b
	body_bag_mesh.material_override = mat_bag
	body_bag_mesh.position = Vector3(0.0, 0.10, 0.0)
	body_bag_mesh.visible = false
	stretcher_mesh.add_child(body_bag_mesh)

func _create_limb(radius: float, height: float, mat: Material, offset: Vector3) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	mesh_inst.mesh = cyl
	mesh_inst.material_override = mat
	mesh_inst.position = offset
	return mesh_inst

func _make_mat(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.shading_mode = StandardMaterial3D.SHADING_MODE_PER_PIXEL
	return m

func _physics_process(delta: float) -> void:
	if is_dead or state == State.EMBARKED:
		return
		
	var is_moving := false
	var dir_to_look := Vector2.ZERO

	match state:
		State.DISEMBARK:
			if not is_instance_valid(hearse):
				state = State.APPROACH
			else:
				var exit_point: Vector2 = hearse.get_crew_exit_point(crew_side, crew_longitudinal) if hearse.has_method("get_crew_exit_point") else hearse.global_position
				dir_to_look = global_position.direction_to(exit_point)
				if global_position.distance_to(exit_point) > 5.0:
					velocity = _navigate_towards(exit_point, speed * 0.72, delta)
					is_moving = true
				else:
					velocity = Vector2.ZERO
					state = State.APPROACH
		State.APPROACH:
			if is_burial_trip:
				var dist_b: float = global_position.distance_to(burial_position)
				dir_to_look = global_position.direction_to(burial_position)
				if dist_b > 20.0:
					velocity = _navigate_towards(burial_position, speed, delta)
					is_moving = true
				else:
					velocity = Vector2.ZERO
					state = State.BAG_AND_LIFT
					bag_timer = 1.5
			elif not is_instance_valid(target):
				_start_return_to_hearse()
				return
			else:
				var dist: float = global_position.distance_to(target.global_position)
				dir_to_look = global_position.direction_to(target.global_position)
				if dist > 26.0:
					velocity = _navigate_towards(target.global_position, speed, delta)
					is_moving = true
				else:
					velocity = Vector2.ZERO
					state = State.BAG_AND_LIFT
					bag_timer = 2.0

		State.BAG_AND_LIFT:
			velocity = Vector2.ZERO
			if is_burial_trip:
				dir_to_look = global_position.direction_to(burial_position)
			elif is_instance_valid(target):
				dir_to_look = global_position.direction_to(target.global_position)
			bag_timer -= delta
			if bag_timer <= 0.0:
				if is_burial_trip:
					_place_grave_marker()
				elif is_instance_valid(target):
					# Desaparece com o corpo e poça de sangue
					target.queue_free()
				if body_bag_mesh:
					body_bag_mesh.visible = true # Saco de cadáver preto fechado na maca
				_start_return_to_hearse()

		State.RETURN_HEARSE:
			if not is_instance_valid(hearse):
				queue_free()
				return
			var door_point: Vector2 = hearse.get_crew_door_point(crew_side, crew_longitudinal) if hearse.has_method("get_crew_door_point") else hearse.global_position
			var dist_h: float = global_position.distance_to(door_point)
			dir_to_look = global_position.direction_to(door_point)
			if dist_h > 7.0:
				velocity = _navigate_towards(door_point, speed, delta)
				is_moving = true
			else:
				velocity = Vector2.ZERO
				_board_hearse()

	move_and_slide()

	# Animação e Rotação 3D
	if model_root and dir_to_look.length_squared() > 0.01:
		var target_angle_3d: float = -atan2(dir_to_look.y, dir_to_look.x) - PI * 0.5
		model_root.rotation.y = lerp_angle(model_root.rotation.y, target_angle_3d, 12.0 * delta)

	if is_moving:
		walk_clock += delta * 5.0
	else:
		walk_clock += delta * 1.5

	var step_angle: float = sin(walk_clock) * 0.35 if is_moving else 0.0
	if left_upper_leg and right_upper_leg:
		left_upper_leg.rotation.x = step_angle
		right_upper_leg.rotation.x = -step_angle
		if left_lower_leg and right_lower_leg:
			left_lower_leg.rotation.x = maxf(0.0, -step_angle * 0.65)
			right_lower_leg.rotation.x = maxf(0.0, step_angle * 0.65)

	if right_upper_arm and left_upper_arm:
		if is_stretcher_bearer:
			# Segura a maca com as duas mãos à frente
			right_upper_arm.rotation = Vector3(1.20, -0.15, 0.0)
			left_upper_arm.rotation = Vector3(1.20, 0.15, 0.0)
		else:
			right_upper_arm.rotation.x = -step_angle * 0.5
			left_upper_arm.rotation.x = step_angle * 0.5

var last_pos: Vector2 = Vector2.ZERO
var stuck_timer: float = 0.0

func _navigate_towards(dest: Vector2, move_speed: float, delta: float) -> Vector2:
	var dir: Vector2 = global_position.direction_to(dest)
	if dir.length_squared() < 0.001:
		return Vector2.ZERO
	if global_position.distance_to(last_pos) < 2.0:
		stuck_timer += delta
	else:
		stuck_timer = maxf(0.0, stuck_timer - delta * 1.5)
		last_pos = global_position
		
	var slide_dir: Vector2 = dir
	for i in get_slide_collision_count():
		var col = get_slide_collision(i)
		var n: Vector2 = col.get_normal()
		if n.dot(dir) < -0.2:
			var tangent := Vector2(-n.y, n.x)
			if tangent.dot(dir) < 0: tangent = -tangent
			slide_dir = tangent
			break
			
	if stuck_timer > 0.4:
		var side_step: Vector2 = dir.rotated(PI * 0.45)
		return (side_step * 0.8 + slide_dir * 0.2).normalized() * move_speed
		
	return slide_dir.normalized() * move_speed

func _start_return_to_hearse() -> void:
	state = State.RETURN_HEARSE
	if not is_instance_valid(hearse):
		queue_free()

## Leaves a permanent grave marker at burial_position -- a simple cross on
## a small dirt mound, same low-poly Polygon2D style used by the other
## props in this file. Registers with the HarborCemetery node if present.
func _place_grave_marker() -> void:
	var grave := Node2D.new()
	grave.name = "GraveMarker"
	grave.global_position = burial_position
	grave.z_index = -1

	var mound := Polygon2D.new()
	mound.polygon = PackedVector2Array([
		Vector2(-11, 6), Vector2(-7, 2), Vector2(0, 0),
		Vector2(7, 2), Vector2(11, 6), Vector2(0, 9)
	])
	mound.color = Color(0.32, 0.24, 0.16, 0.95)
	grave.add_child(mound)

	var upright := Polygon2D.new()
	upright.polygon = PackedVector2Array([Vector2(-2, -14), Vector2(2, -14), Vector2(2, 6), Vector2(-2, 6)])
	upright.color = Color(0.55, 0.52, 0.47)
	grave.add_child(upright)

	var crossbar := Polygon2D.new()
	crossbar.polygon = PackedVector2Array([Vector2(-8, -8), Vector2(8, -8), Vector2(8, -4), Vector2(-8, -4)])
	crossbar.color = Color(0.55, 0.52, 0.47)
	grave.add_child(crossbar)

	var parent := get_parent() if get_parent() != null else get_tree().current_scene
	if parent:
		parent.add_child(grave)

	var cemetery := get_tree().get_first_node_in_group("cemetery")
	if cemetery and cemetery.has_method("register_grave"):
		cemetery.register_grave(grave, burial_position)


func begin_service_disembark(vehicle: Node2D, side: float, longitudinal: float) -> void:
	hearse = vehicle
	crew_side = side
	crew_longitudinal = longitudinal
	state = State.DISEMBARK

func _board_hearse() -> void:
	if boarding_started:
		return
	boarding_started = true
	state = State.EMBARKING
	if is_instance_valid(hearse) and hearse.has_method("play_crew_door"):
		hearse.play_crew_door(crew_side, crew_longitudinal)
	await get_tree().create_timer(0.42).timeout
	if not is_instance_valid(self):
		return
	state = State.EMBARKED
	hide()
	set_physics_process(false)
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	if is_instance_valid(hearse) and hearse.has_method("on_mortician_embarked"):
		hearse.on_mortician_embarked(self)
	queue_free()

func take_damage(amount: int, _is_player_attacker: bool = false) -> void:
	health = maxi(0, health - amount)
	if health <= 0 and not is_dead:
		is_dead = true
		velocity = Vector2.ZERO
		if collision_shape: collision_shape.set_deferred("disabled", true)
		if model_root: model_root.rotation.x = PI * 0.45
		create_tween().tween_interval(10.0).finished.connect(queue_free)
