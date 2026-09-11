class_name Paramedic
extends CharacterBody2D

enum State { DISEMBARK, APPROACH, TREAT_LOAD, RETURN_AMBULANCE, EMBARKING, EMBARKED }

@export var speed: float = 160.0
@export var max_health: int = 60
@export var is_stretcher_bearer: bool = false

var target: Node2D = null
var ambulance: Node2D = null
var state: State = State.APPROACH

var health: int = 60
var is_dead: bool = false
var fall_presentation := preload("res://CharacterFallPresentation.gd").new()
var is_flying: bool = false
var fly_velocity: Vector2 = Vector2.ZERO
var walk_clock: float = 0.0

var collision_shape: CollisionShape2D
var treat_timer: float = 0.0
var crew_side := 1.0
var crew_longitudinal := 8.0
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
var mat_uniform: StandardMaterial3D
var stretcher_mesh: MeshInstance3D = null

func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	platform_floor_layers = 0
	platform_wall_layers = 0
	if is_instance_valid(ambulance): add_collision_exception_with(ambulance)
	add_to_group("paramedic")
	add_to_group("damageable")
	health = max_health
	z_index = 6
	
	_build_3d_viewport()
	preload("res://world/shared/pedestrians/ServiceUniformDetails.gd").apply(self,"medic")
	
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
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(viewport_3d)

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 3.2, 1.4)
	cam.fov = 30.0
	viewport_3d.add_child(cam)
	cam.look_at(Vector3(0.0, 0.65, 0.0), Vector3.UP)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-60.0, 35.0, 0.0)
	light.light_energy = 1.35
	viewport_3d.add_child(light)

	var env := WorldEnvironment.new()
	var env_res := Environment.new()
	env_res.background_mode = Environment.BG_COLOR
	env_res.background_color = Color(0, 0, 0, 0)
	env_res.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env_res.ambient_light_color = Color(0.70, 0.72, 0.82)
	env.environment = env_res
	viewport_3d.add_child(env)

	model_root = Node3D.new()
	viewport_3d.add_child(model_root)

	var shadow_mat := StandardMaterial3D.new()
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mat.albedo_color = Color(0.02, 0.02, 0.05, 0.50)
	shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var shadow_mesh := MeshInstance3D.new()
	var cyl_shadow := CylinderMesh.new()
	cyl_shadow.top_radius = 0.28
	cyl_shadow.bottom_radius = 0.28
	cyl_shadow.height = 0.01
	shadow_mesh.mesh = cyl_shadow
	shadow_mesh.material_override = shadow_mat
	shadow_mesh.position = Vector3(0.0, 0.01, 0.0)
	shadow_mesh.name = "GroundShadow"
	shadow_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	viewport_3d.add_child(shadow_mesh)

	# Jaleco / Uniforme Médico Branco com detalhes
	mat_uniform = _make_mat(Color(0.92, 0.95, 0.96), 0.5)
	var mat_pants := _make_mat(Color(0.20, 0.35, 0.55), 0.6)
	var mat_skin := _make_mat(Color(0.85, 0.68, 0.52), 0.5)
	var mat_red := _make_mat(Color(0.88, 0.15, 0.15), 0.3)
	var mat_black := _make_mat(Color(0.08, 0.08, 0.10), 0.4)
	var mat_kit := _make_mat(Color(0.90, 0.20, 0.20), 0.3)

	# Torso 3D
	torso_node = Node3D.new()
	torso_node.position = Vector3(0.0, 0.85, 0.0)
	model_root.add_child(torso_node)

	var torso_mesh := MeshInstance3D.new()
	var cap_t := CapsuleMesh.new()
	cap_t.radius = 0.17
	cap_t.height = 0.48
	torso_mesh.mesh = cap_t
	torso_mesh.material_override = mat_uniform
	torso_node.add_child(torso_mesh)

	# Cruz Vermelha no Peito
	var cross_v := MeshInstance3D.new()
	var box_cv := BoxMesh.new()
	box_cv.size = Vector3(0.03, 0.09, 0.02)
	cross_v.mesh = box_cv
	cross_v.material_override = mat_red
	cross_v.position = Vector3(0.0, 0.10, -0.165)
	torso_node.add_child(cross_v)

	var cross_h := MeshInstance3D.new()
	var box_ch := BoxMesh.new()
	box_ch.size = Vector3(0.09, 0.03, 0.02)
	cross_h.mesh = box_ch
	cross_h.material_override = mat_red
	cross_h.position = Vector3(0.0, 0.10, -0.165)
	torso_node.add_child(cross_h)

	# Estetoscópio no Pescoço
	var steth := MeshInstance3D.new()
	var box_st := BoxMesh.new()
	box_st.size = Vector3(0.22, 0.12, 0.03)
	steth.mesh = box_st
	steth.material_override = mat_black
	steth.position = Vector3(0.0, 0.18, -0.15)
	torso_node.add_child(steth)

	# Cabeça 3D
	head_node = Node3D.new()
	head_node.position = Vector3(0.0, 1.25, 0.0)
	model_root.add_child(head_node)

	var head_mesh := MeshInstance3D.new()
	var sph_h := SphereMesh.new()
	sph_h.radius = 0.17
	sph_h.height = 0.34
	head_mesh.mesh = sph_h
	head_mesh.material_override = mat_skin
	head_node.add_child(head_mesh)

	# Braços 3D
	left_upper_arm = Node3D.new()
	left_upper_arm.position = Vector3(-0.24, 1.05, 0.0)
	model_root.add_child(left_upper_arm)
	left_upper_arm.add_child(_create_limb(0.050, 0.22, mat_uniform, Vector3(0, -0.11, 0)))

	left_lower_arm = Node3D.new()
	left_lower_arm.position = Vector3(0, -0.22, 0)
	left_upper_arm.add_child(left_lower_arm)
	left_lower_arm.add_child(_create_limb(0.042, 0.18, mat_skin, Vector3(0, -0.09, 0)))

	right_upper_arm = Node3D.new()
	right_upper_arm.position = Vector3(0.24, 1.05, 0.0)
	model_root.add_child(right_upper_arm)
	right_upper_arm.add_child(_create_limb(0.050, 0.22, mat_uniform, Vector3(0, -0.11, 0)))

	right_lower_arm = Node3D.new()
	right_lower_arm.position = Vector3(0, -0.22, 0)
	right_upper_arm.add_child(right_lower_arm)
	right_lower_arm.add_child(_create_limb(0.042, 0.18, mat_skin, Vector3(0, -0.09, 0)))

	# Maleta de Primeiros Socorros 3D na Mão Direita
	var med_kit := MeshInstance3D.new()
	var box_mk := BoxMesh.new()
	box_mk.size = Vector3(0.08, 0.16, 0.22)
	med_kit.mesh = box_mk
	med_kit.material_override = mat_kit
	med_kit.position = Vector3(0.05, -0.22, 0.0)
	right_lower_arm.add_child(med_kit)

	# Pernas 3D
	left_upper_leg = Node3D.new()
	left_upper_leg.position = Vector3(-0.11, 0.65, 0.0)
	model_root.add_child(left_upper_leg)
	left_upper_leg.add_child(_create_limb(0.068, 0.28, mat_pants, Vector3(0, -0.14, 0)))

	left_lower_leg = Node3D.new()
	left_lower_leg.position = Vector3(0, -0.28, 0)
	left_upper_leg.add_child(left_lower_leg)
	left_lower_leg.add_child(_create_limb(0.058, 0.26, mat_pants, Vector3(0, -0.13, 0)))
	left_lower_leg.add_child(_create_shoe(mat_black, Vector3(0, -0.26, -0.02)))

	right_upper_leg = Node3D.new()
	right_upper_leg.position = Vector3(0.11, 0.65, 0.0)
	model_root.add_child(right_upper_leg)
	right_upper_leg.add_child(_create_limb(0.068, 0.28, mat_pants, Vector3(0, -0.14, 0)))

	right_lower_leg = Node3D.new()
	right_lower_leg.position = Vector3(0, -0.28, 0)
	right_upper_leg.add_child(right_lower_leg)
	right_lower_leg.add_child(_create_limb(0.058, 0.26, mat_pants, Vector3(0, -0.13, 0)))
	right_lower_leg.add_child(_create_shoe(mat_black, Vector3(0, -0.26, -0.02)))

	# Maca retrátil (se for o paramédico carregador) -- mesmo padrão de
	# Mortician.gd._build_stretcher(), lençol claro em vez de saco preto.
	if is_stretcher_bearer:
		_build_stretcher()

	# Exibição 2D
	sprite_3d_display = Sprite2D.new()
	sprite_3d_display.texture = viewport_3d.get_texture()
	sprite_3d_display.scale = Vector2(0.38, 0.38)
	add_child(sprite_3d_display)

func _make_mat(col: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = roughness
	return mat

func _create_limb(radius: float, height: float, mat: Material, offset: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius * 0.85
	cyl.height = height
	m.mesh = cyl
	m.material_override = mat
	m.position = offset
	return m

func _create_shoe(mat: Material, offset: Vector3) -> MeshInstance3D:
	var shoe := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.09, 0.065, 0.16)
	shoe.mesh = box
	shoe.material_override = mat
	shoe.position = offset
	return shoe

func _build_stretcher() -> void:
	var mat_metal := _make_mat(Color(0.65, 0.68, 0.72), 0.8)
	stretcher_mesh = MeshInstance3D.new()
	var box_s := BoxMesh.new()
	box_s.size = Vector3(0.42, 0.06, 0.85)
	stretcher_mesh.mesh = box_s
	stretcher_mesh.material_override = mat_metal
	stretcher_mesh.position = Vector3(0.0, 0.55, -0.55)
	model_root.add_child(stretcher_mesh)

	# Lençol/cobertor claro sobre a maca -- a mesma peça que em Mortician.gd
	# aparece como saco de cadáver preto, aqui é o paciente sendo salvo.
	var mat_blanket := _make_mat(Color(0.88, 0.90, 0.94), 0.6)
	var blanket := MeshInstance3D.new()
	var box_b := BoxMesh.new()
	box_b.size = Vector3(0.36, 0.10, 0.78)
	blanket.mesh = box_b
	blanket.material_override = mat_blanket
	blanket.position = Vector3(0.0, 0.08, 0.0)
	stretcher_mesh.add_child(blanket)

func get_run_over(impact_velocity: Vector2, _is_player_driver: bool = false) -> void:
	if is_dead: return
	is_dead = true
	is_flying = true
	fly_velocity = impact_velocity.limit_length(600.0) * 0.85
	_start_fall(impact_velocity)
	health = 0
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	_create_3d_blood_puddle()
	_play_audio(ProceduralAudio.get_squish_stream(), -3.0)
	_play_audio(ProceduralAudio.get_scream_stream(), -4.0)
	_start_decay()

func take_damage(amount: int, _is_player_attacker: bool = false) -> void:
	if is_dead: return
	health = maxi(0, health - amount)
	if mat_uniform:
		mat_uniform.albedo_color = Color(1.0, 0.4, 0.4)
		var tween := create_tween()
		tween.tween_property(mat_uniform, "albedo_color", Color(0.92, 0.95, 0.96), 0.2)
	_play_audio(ProceduralAudio.get_squish_stream(), -6.0)
	if health <= 0:
		_die()

func _die() -> void:
	is_dead = true
	velocity = Vector2.ZERO
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	_start_fall()
	_create_3d_blood_puddle()
	_play_audio(ProceduralAudio.get_scream_stream(), -5.0)
	_start_decay()

func _physics_process(delta: float) -> void:
	if is_flying:
		position += fly_velocity * delta
		fly_velocity = fly_velocity.move_toward(Vector2.ZERO, 950.0 * delta)
		if fly_velocity.length() < 12.0: is_flying = false
		
	if is_dead:
		fall_presentation.update(delta)
		return
	if state == State.EMBARKED: return
		
	var is_moving: bool = false
	var dir_to_look: Vector2 = Vector2.ZERO

	match state:
		State.DISEMBARK:
			if not is_instance_valid(ambulance):
				state = State.APPROACH
			else:
				var exit_point: Vector2 = ambulance.get_crew_exit_point(crew_side, crew_longitudinal) if ambulance.has_method("get_crew_exit_point") else ambulance.global_position
				dir_to_look = global_position.direction_to(exit_point)
				if global_position.distance_to(exit_point) > 5.0:
					velocity = _navigate_towards(exit_point, speed * 0.72, delta)
					is_moving = true
				else:
					velocity = Vector2.ZERO
					state = State.APPROACH
					remove_collision_exception_with(ambulance)
		State.APPROACH:
			if not is_instance_valid(target):
				_start_return_to_ambulance()
				return
			var dist: float = global_position.distance_to(target.global_position)
			var dir: Vector2 = global_position.direction_to(target.global_position)
			dir_to_look = dir
			
			if dist > 42.0 or not _can_reach_patient():
				velocity = _navigate_towards(movement_navigation.service_position(self, target, 32.0, delta), speed, delta)
				is_moving = true
			else:
				velocity = Vector2.ZERO
				state = State.TREAT_LOAD
				treat_timer = 2.0
				_play_audio(ProceduralAudio.get_powerup_stream(), -8.0)
				
		State.TREAT_LOAD:
			velocity = Vector2.ZERO
			if not is_instance_valid(target):
				_start_return_to_ambulance()
				return
			if global_position.distance_to(target.global_position) > 42.0 or not _can_reach_patient():
				state = State.APPROACH
				return
			if is_instance_valid(target):
				dir_to_look = global_position.direction_to(target.global_position)
			treat_timer -= delta
			if treat_timer <= 0.0:
				if is_instance_valid(target):
					if target.has_method("rescue_from_emergency"):
						target.rescue_from_emergency(ambulance)
					else:
						target.queue_free()
				_start_return_to_ambulance()
				
		State.RETURN_AMBULANCE:
			if not is_instance_valid(ambulance):
				_disperse_on_foot()
				return
			var door_point: Vector2 = ambulance.get_crew_door_point(crew_side, crew_longitudinal) if ambulance.has_method("get_crew_door_point") else ambulance.global_position
			var dist_amb: float = global_position.distance_to(door_point)
			dir_to_look = global_position.direction_to(door_point)
			if dist_amb > 7.0:
				velocity = _navigate_towards(door_point, speed, delta)
				is_moving = true
			else:
				velocity = Vector2.ZERO
				_board_ambulance()

	move_and_slide()
	is_moving = velocity.length_squared() > 1.0

	# Animação e Rotação 3D
	if model_root and dir_to_look.length_squared() > 0.01:
		var target_angle_3d: float = -atan2(dir_to_look.y, dir_to_look.x) - PI * 0.5
		model_root.rotation.y = lerp_angle(model_root.rotation.y, target_angle_3d, minf(1.0, 14.0 * delta))

	if is_moving:
		walk_clock += delta * 6.0
	else:
		walk_clock += delta * 1.5

	var step_angle: float = sin(walk_clock) * 0.40 if is_moving else 0.0
	if left_upper_leg and right_upper_leg:
		left_upper_leg.rotation.x = step_angle
		right_upper_leg.rotation.x = -step_angle
		if left_lower_leg and right_lower_leg:
			left_lower_leg.rotation.x = maxf(0.0, -step_angle * 0.70)
			right_lower_leg.rotation.x = maxf(0.0, step_angle * 0.70)

	if right_upper_arm and left_upper_arm:
		right_upper_arm.rotation.x = -step_angle * 0.6
		left_upper_arm.rotation.x = step_angle * 0.6

var last_pos: Vector2 = Vector2.ZERO
var stuck_timer: float = 0.0
var unstuck_dir_sign: float = 1.0

var movement_navigation := preload("res://ResponderNavigation.gd").new()

func _navigate_towards(dest: Vector2, move_speed: float, delta: float) -> Vector2:
	var result: Vector2 = movement_navigation.movement(self, dest, move_speed, delta)
	stuck_timer = movement_navigation.stuck_time
	return result


func _start_return_to_ambulance() -> void:
	if boarding_started: return
	if is_instance_valid(ambulance): add_collision_exception_with(ambulance)
	state = State.RETURN_AMBULANCE
	if not is_instance_valid(ambulance):
		_disperse_on_foot()

func _can_reach_patient() -> bool:
	if not is_instance_valid(target): return false
	var query := PhysicsRayQueryParameters2D.create(global_position, target.global_position, 3, [get_rid()])
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == target


func begin_service_disembark(vehicle: Node2D, side: float, longitudinal: float) -> void:
	ambulance = vehicle
	crew_side = side
	crew_longitudinal = longitudinal
	state = State.DISEMBARK

func _board_ambulance() -> void:
	if boarding_started:
		return
	boarding_started = true
	state = State.EMBARKING
	if is_instance_valid(ambulance) and ambulance.has_method("play_crew_door"):
		ambulance.play_crew_door(crew_side, crew_longitudinal)
	await get_tree().create_timer(0.42).timeout
	if not is_instance_valid(self):
		return
	state = State.EMBARKED
	hide()
	set_physics_process(false)
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	if is_instance_valid(ambulance) and ambulance.has_method("on_paramedic_embarked"):
		ambulance.on_paramedic_embarked(self)
	queue_free()

func _disperse_on_foot() -> void:
	velocity = Vector2.ZERO
	set_physics_process(false)
	var t := create_tween()
	t.tween_interval(5.0)
	t.tween_property(self, "modulate:a", 0.0, 2.0)
	t.tween_callback(queue_free)

func _create_3d_blood_puddle() -> void:
	var puddle_root := Node2D.new()
	puddle_root.name = "3DBloodPuddle"
	puddle_root.global_position = global_position
	puddle_root.z_index = -1
	
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(-10, -2), Vector2(-7, -7), Vector2(0, -9),
		Vector2(7, -7), Vector2(11, -1), Vector2(9, 6),
		Vector2(3, 8), Vector2(-4, 7), Vector2(-9, 3)
	])
	poly.color = Color(0.65, 0.03, 0.03, 0.95)
	puddle_root.add_child(poly)
	
	if get_parent():
		get_parent().add_child(puddle_root)
	else:
		get_tree().current_scene.add_child(puddle_root)
		
	puddle_root.scale = Vector2(0.1, 0.1)
	var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(puddle_root, "scale", Vector2(0.65, 0.65), 0.55)
	
	var fade_tween := puddle_root.create_tween()
	fade_tween.tween_interval(6.0)
	fade_tween.tween_property(puddle_root, "modulate:a", 0.0, 2.5)
	fade_tween.tween_callback(puddle_root.queue_free)

func _start_decay() -> void:
	var t := create_tween()
	t.tween_interval(8.0)
	t.tween_property(self, "modulate:a", 0.0, 3.0)
	t.tween_callback(queue_free)

func _play_audio(stream: AudioStream, volume_db: float = -6.0) -> void:
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.max_distance = 600.0
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)

func _start_fall(impact := Vector2.ZERO) -> void:
	fall_presentation.start(self, model_root, viewport_3d, impact)
