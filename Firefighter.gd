class_name Firefighter
extends CharacterBody2D

enum State { DISEMBARK, APPROACH, EXTINGUISH, RETURN, EMBARKING, EMBARKED }

@export var speed: float = 160.0
@export var max_health: int = 60

var target: Node2D = null
var fire_truck: Node2D = null
var state: State = State.APPROACH

var health: int = 60
var is_dead: bool = false
var is_flying: bool = false
var fly_velocity: Vector2 = Vector2.ZERO
var walk_clock: float = 0.0

var collision_shape: CollisionShape2D
var water_hose: CPUParticles2D
var water_audio: AudioStreamPlayer2D
var extinguish_timer: float = 0.0
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
var mat_uniform: StandardMaterial3D

func _ready() -> void:
	add_to_group("firefighter")
	add_to_group("damageable")
	health = max_health
	z_index = 6
	
	_build_3d_viewport()
	preload("res://district/pedestrians/ServiceUniformDetails.gd").apply(self,"fire")
	
	var col := CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = 5.0
	cap.height = 16.0
	col.shape = cap
	collision_shape = col
	add_child(col)
	
	water_hose = CPUParticles2D.new()
	water_hose.emitting = false
	water_hose.amount = 40
	water_hose.lifetime = 0.55
	water_hose.speed_scale = 1.3
	water_hose.spread = 12.0
	water_hose.initial_velocity_min = 140.0
	water_hose.initial_velocity_max = 210.0
	water_hose.gravity = Vector2(0, 80)
	water_hose.scale_amount_min = 2.5
	water_hose.scale_amount_max = 5.5
	water_hose.color = Color(0.4, 0.75, 1.0, 0.88)
	water_hose.position = Vector2(0, -6)
	add_child(water_hose)
	
	water_audio = AudioStreamPlayer2D.new()
	water_audio.stream = ProceduralAudio.get_water_stream()
	water_audio.max_distance = 600.0
	water_audio.volume_db = -6.0
	add_child(water_audio)

func _build_3d_viewport() -> void:
	viewport_3d = SubViewport.new()
	viewport_3d.size = Vector2i(96, 96)
	viewport_3d.transparent_bg = true
	viewport_3d.own_world_3d = true
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
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
	model_root.add_child(shadow_mesh)

	# Uniforme Amarelo Mostarda de Resgate
	mat_uniform = _make_mat(Color(0.85, 0.68, 0.10), 0.6)
	var mat_helmet := _make_mat(Color(0.88, 0.15, 0.15), 0.3)
	var mat_skin := _make_mat(Color(0.85, 0.68, 0.52), 0.5)
	var mat_black := _make_mat(Color(0.08, 0.08, 0.10), 0.4)
	var mat_silver := _make_mat(Color(0.85, 0.88, 0.92), 0.2)

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

	var stripe := MeshInstance3D.new()
	var box_st := BoxMesh.new()
	box_st.size = Vector3(0.36, 0.06, 0.35)
	stripe.mesh = box_st
	stripe.material_override = mat_silver
	stripe.position = Vector3(0.0, 0.04, 0.0)
	torso_node.add_child(stripe)

	# Cabeça com Capacete de Bombeiro com Aba
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

	var helm := MeshInstance3D.new()
	var sph_hl := SphereMesh.new()
	sph_hl.radius = 0.19
	sph_hl.height = 0.28
	helm.mesh = sph_hl
	helm.material_override = mat_helmet
	helm.position = Vector3(0.0, 0.06, 0.0)
	head_node.add_child(helm)

	var brim := MeshInstance3D.new()
	var cyl_br := CylinderMesh.new()
	cyl_br.top_radius = 0.23
	cyl_br.bottom_radius = 0.23
	cyl_br.height = 0.02
	brim.mesh = cyl_br
	brim.material_override = mat_helmet
	brim.position = Vector3(0.0, -0.02, 0.0)
	head_node.add_child(brim)

	# Braços 3D
	left_upper_arm = Node3D.new()
	left_upper_arm.position = Vector3(-0.24, 1.05, 0.0)
	model_root.add_child(left_upper_arm)
	left_upper_arm.add_child(_create_limb(0.050, 0.22, mat_uniform, Vector3(0, -0.11, 0)))

	left_lower_arm = Node3D.new()
	left_lower_arm.position = Vector3(0, -0.22, 0)
	left_upper_arm.add_child(left_lower_arm)
	left_lower_arm.add_child(_create_limb(0.042, 0.18, mat_black, Vector3(0, -0.09, 0)))

	right_upper_arm = Node3D.new()
	right_upper_arm.position = Vector3(0.24, 1.05, 0.0)
	model_root.add_child(right_upper_arm)
	right_upper_arm.add_child(_create_limb(0.050, 0.22, mat_uniform, Vector3(0, -0.11, 0)))

	right_lower_arm = Node3D.new()
	right_lower_arm.position = Vector3(0, -0.22, 0)
	right_upper_arm.add_child(right_lower_arm)
	right_lower_arm.add_child(_create_limb(0.042, 0.18, mat_black, Vector3(0, -0.09, 0)))

	# Bico de Mangueira 3D nas Mãos
	var hose_nozzle := MeshInstance3D.new()
	var cyl_noz := CylinderMesh.new()
	cyl_noz.top_radius = 0.022
	cyl_noz.bottom_radius = 0.035
	cyl_noz.height = 0.20
	hose_nozzle.mesh = cyl_noz
	hose_nozzle.material_override = mat_silver
	hose_nozzle.rotation_degrees = Vector3(90, 0, 0)
	hose_nozzle.position = Vector3(0.0, -0.18, -0.12)
	right_lower_arm.add_child(hose_nozzle)

	# Pernas 3D
	left_upper_leg = Node3D.new()
	left_upper_leg.position = Vector3(-0.11, 0.65, 0.0)
	model_root.add_child(left_upper_leg)
	left_upper_leg.add_child(_create_limb(0.068, 0.28, mat_uniform, Vector3(0, -0.14, 0)))

	left_lower_leg = Node3D.new()
	left_lower_leg.position = Vector3(0, -0.28, 0)
	left_upper_leg.add_child(left_lower_leg)
	left_lower_leg.add_child(_create_limb(0.058, 0.26, mat_uniform, Vector3(0, -0.13, 0)))
	left_lower_leg.add_child(_create_shoe(mat_black, Vector3(0, -0.26, -0.02)))

	right_upper_leg = Node3D.new()
	right_upper_leg.position = Vector3(0.11, 0.65, 0.0)
	model_root.add_child(right_upper_leg)
	right_upper_leg.add_child(_create_limb(0.068, 0.28, mat_uniform, Vector3(0, -0.14, 0)))

	right_lower_leg = Node3D.new()
	right_lower_leg.position = Vector3(0, -0.28, 0)
	right_upper_leg.add_child(right_lower_leg)
	right_lower_leg.add_child(_create_limb(0.058, 0.26, mat_uniform, Vector3(0, -0.13, 0)))
	right_lower_leg.add_child(_create_shoe(mat_black, Vector3(0, -0.26, -0.02)))

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

func get_run_over(impact_velocity: Vector2, _is_player_driver: bool = false) -> void:
	if is_dead: return
	is_dead = true
	is_flying = true
	fly_velocity = impact_velocity.limit_length(600.0) * 0.85
	health = 0
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	if water_hose: water_hose.emitting = false
	if water_audio: water_audio.stop()
	
	_spawn_blood_burst(impact_velocity.normalized())
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
		tween.tween_property(mat_uniform, "albedo_color", Color(0.85, 0.68, 0.10), 0.2)
	_play_audio(ProceduralAudio.get_squish_stream(), -6.0)
	
	if health <= 0:
		_die()

func _die() -> void:
	is_dead = true
	velocity = Vector2.ZERO
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	if water_hose: water_hose.emitting = false
	if water_audio: water_audio.stop()
	if model_root:
		model_root.rotation.x = PI * 0.45
	_create_3d_blood_puddle()
	_play_audio(ProceduralAudio.get_scream_stream(), -5.0)
	_start_decay()

func _physics_process(delta: float) -> void:
	if is_flying:
		position += fly_velocity * delta
		fly_velocity = fly_velocity.move_toward(Vector2.ZERO, 950.0 * delta)
		if model_root:
			model_root.rotation.y += 12.0 * delta
		if fly_velocity.length() < 12.0:
			is_flying = false
			if model_root:
				model_root.rotation.x = PI * 0.45
		return
		
	if is_dead or state == State.EMBARKED:
		return
		
	var is_moving: bool = false
	var dir_to_look: Vector2 = Vector2.ZERO

	match state:
		State.DISEMBARK:
			if not is_instance_valid(fire_truck):
				state = State.APPROACH
			else:
				var exit_point: Vector2 = fire_truck.get_crew_exit_point(crew_side, crew_longitudinal) if fire_truck.has_method("get_crew_exit_point") else fire_truck.global_position
				dir_to_look = global_position.direction_to(exit_point)
				if global_position.distance_to(exit_point) > 5.0:
					velocity = _navigate_towards(exit_point, speed * 0.72, delta)
					is_moving = true
				else:
					velocity = Vector2.ZERO
					state = State.APPROACH
		State.APPROACH:
			if not is_instance_valid(target):
				_start_return_to_truck()
				return
			var dist: float = global_position.distance_to(target.global_position)
			var dir: Vector2 = global_position.direction_to(target.global_position)
			dir_to_look = dir
			
			if dist > 60.0 and stuck_timer < 2.0:
				velocity = _navigate_towards(target.global_position, speed, delta)
				is_moving = true
			else:
				velocity = Vector2.ZERO
				state = State.EXTINGUISH
				extinguish_timer = 2.6
				water_hose.emitting = true
				water_hose.direction = dir
				water_audio.play()
				
		State.EXTINGUISH:
			velocity = Vector2.ZERO
			if is_instance_valid(target):
				dir_to_look = global_position.direction_to(target.global_position)
				water_hose.direction = dir_to_look
			extinguish_timer -= delta
			if extinguish_timer <= 0.0:
				water_hose.emitting = false
				water_audio.stop()
				if is_instance_valid(target):
					if target.has_method("extinguish_fire"):
						target.extinguish_fire()
					elif target.has_method("repair_vehicle"):
						target.repair_vehicle()
				_start_return_to_truck()
				
		State.RETURN:
			if not is_instance_valid(fire_truck):
				_disperse_on_foot()
				return
			var door_point: Vector2 = fire_truck.get_crew_door_point(crew_side, crew_longitudinal) if fire_truck.has_method("get_crew_door_point") else fire_truck.global_position
			var dist_truck: float = global_position.distance_to(door_point)
			dir_to_look = global_position.direction_to(door_point)
			if dist_truck > 7.0:
				velocity = _navigate_towards(door_point, speed, delta)
				is_moving = true
			else:
				velocity = Vector2.ZERO
				_board_fire_truck()

	move_and_slide()

	# Animação e Rotação 3D
	if model_root and dir_to_look.length_squared() > 0.01:
		var target_angle_3d: float = -atan2(dir_to_look.y, dir_to_look.x) - PI * 0.5
		model_root.rotation.y = lerp_angle(model_root.rotation.y, target_angle_3d, 14.0 * delta)

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
		if state == State.EXTINGUISH:
			right_upper_arm.rotation = Vector3(1.35, -0.08, 0.0)
			right_lower_arm.rotation = Vector3(0.05, 0.0, 0.0)
			left_upper_arm.rotation = Vector3(1.30, 0.22, 0.0)
			left_lower_arm.rotation = Vector3(0.15, 0.28, 0.0)
		else:
			right_upper_arm.rotation = Vector3(-step_angle * 0.6, 0.0, 0.0)
			left_upper_arm.rotation = Vector3(step_angle * 0.6, 0.0, 0.0)

var last_pos: Vector2 = Vector2.ZERO
var stuck_timer: float = 0.0
var unstuck_dir_sign: float = 1.0

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
			if tangent.dot(dir) < 0:
				tangent = -tangent
			slide_dir = tangent
			break
			
	if stuck_timer > 0.35:
		if stuck_timer > 1.8 and randf() < 0.04:
			unstuck_dir_sign = -unstuck_dir_sign
		var side_step: Vector2 = dir.rotated(PI * 0.45 * unstuck_dir_sign)
		return (side_step * 0.85 + slide_dir * 0.15).normalized() * move_speed
		
	return slide_dir.normalized() * move_speed

func _start_return_to_truck() -> void:
	state = State.RETURN
	if not is_instance_valid(fire_truck):
		_disperse_on_foot()


func begin_service_disembark(vehicle: Node2D, side: float, longitudinal: float) -> void:
	fire_truck = vehicle
	crew_side = side
	crew_longitudinal = longitudinal
	state = State.DISEMBARK

func _board_fire_truck() -> void:
	if boarding_started:
		return
	boarding_started = true
	state = State.EMBARKING
	if is_instance_valid(fire_truck) and fire_truck.has_method("play_crew_door"):
		fire_truck.play_crew_door(crew_side, crew_longitudinal)
	await get_tree().create_timer(0.42).timeout
	if not is_instance_valid(self):
		return
	state = State.EMBARKED
	hide()
	set_physics_process(false)
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	if is_instance_valid(fire_truck) and fire_truck.has_method("on_firefighter_embarked"):
		fire_truck.on_firefighter_embarked(self)
	queue_free()

func _disperse_on_foot() -> void:
	var t := create_tween()
	t.tween_interval(5.0)
	t.tween_property(self, "modulate:a", 0.0, 2.0)
	t.tween_callback(queue_free)

func _spawn_blood_burst(dir: Vector2) -> void:
	var blood_particles := CPUParticles2D.new()
	blood_particles.emitting = true
	blood_particles.one_shot = true
	blood_particles.explosiveness = 0.9
	blood_particles.amount = 25
	blood_particles.lifetime = 0.6
	blood_particles.spread = 45.0
	blood_particles.direction = dir
	blood_particles.initial_velocity_min = 70.0
	blood_particles.initial_velocity_max = 190.0
	blood_particles.gravity = Vector2(0, 160)
	blood_particles.scale_amount_min = 2.0
	blood_particles.scale_amount_max = 4.0
	blood_particles.color = Color(0.75, 0.05, 0.05, 0.95)
	add_child(blood_particles)

func _create_3d_blood_puddle() -> void:
	var puddle_root := Node2D.new()
	puddle_root.name = "3DBloodPuddle"
	puddle_root.global_position = global_position
	puddle_root.z_index = -1
	
	var base_poly := Polygon2D.new()
	base_poly.polygon = PackedVector2Array([
		Vector2(-12, -3), Vector2(-8, -9), Vector2(0, -11),
		Vector2(8, -8), Vector2(13, -1), Vector2(11, 7),
		Vector2(4, 10), Vector2(-5, 9), Vector2(-11, 4)
	])
	base_poly.color = Color(0.24, 0.01, 0.015, 0.92)
	puddle_root.add_child(base_poly)
	
	var core_poly := Polygon2D.new()
	core_poly.polygon = PackedVector2Array([
		Vector2(-9, -2), Vector2(-6, -7), Vector2(0, -8),
		Vector2(6, -6), Vector2(10, -1), Vector2(8, 5),
		Vector2(3, 7), Vector2(-4, 6), Vector2(-8, 3)
	])
	core_poly.color = Color(0.68, 0.04, 0.04, 0.95)
	puddle_root.add_child(core_poly)
	
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
