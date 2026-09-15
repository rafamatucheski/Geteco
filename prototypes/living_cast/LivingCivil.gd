extends "res://characters/AnimatedPedestrian3D.gd"

## Opt-in prototype. Inherits current viewport culling and movement contracts.
const BUILDER := preload("res://prototypes/living_cast/CivilRigBuilder.gd")
const NAMES := ["Morador", "Portuario", "Estudante", "Vizinho", "Brigador", "Vigia"]
@export_range(0, 5) var appearance := 0
@export_enum("Flee", "Unarmed self defense", "Armed self defense") var response := 0
@export var roam := true
var punches_landed := 0
var shots_fired := 0
var death_animation_started := false
var _punch_time := -1.0
var _punch_cooldown := 0.0
var _punch_connected := false
var _left_punch := false
var _flinch := 0.0
var _slide := Vector2.ZERO
var _gun_grip: Node3D

func _setup_district_and_archetype() -> void:
	super._setup_district_and_archetype()
	is_gangster = response == 2
	has_handgun = response == 2
	ambient_running_enabled = false
	base_walk_speed = [40.0, 38.0, 44.0, 30.0, 42.0, 40.0][appearance]

func _build_3d_viewport() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(96, 96)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0, 3.2, 1.4)
	camera.fov = 30
	camera.look_at(Vector3(0, 0.65, 0))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, 30, 0)
	light.light_energy = 1.3
	viewport.add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.72, 0.75, 0.8)
	env.environment.ambient_light_energy = 0.65
	viewport.add_child(env)
	model_root = Node3D.new()
	viewport.add_child(model_root)
	var builder := BUILDER.new()
	var bones := builder.make_rig(model_root, appearance)
	torso_node = bones.torso
	head_node = bones.head
	left_upper_arm = bones.left_upper_arm
	left_lower_arm = bones.left_lower_arm
	right_upper_arm = bones.right_upper_arm
	right_lower_arm = bones.right_lower_arm
	left_upper_leg = bones.left_upper_leg
	left_lower_leg = bones.left_lower_leg
	right_upper_leg = bones.right_upper_leg
	right_lower_leg = bones.right_lower_leg
	if response == 2:
		var grip := Node3D.new()
		_gun_grip = grip
		grip.position = Vector3(0, -0.27, 0)
		right_lower_arm.add_child(grip)
		builder.box(grip, Vector3(0, 0, -0.075), Vector3(0.045, 0.045, 0.15), builder.material("gun", "343a3d"))
		muzzle_flash_3d = builder.ell(grip, Vector3(0, 0, -0.17), Vector3(0.06, 0.06, 0.12), builder.material("flash", "ffe5a0"))
		muzzle_flash_3d.visible = false
	sprite_3d_display = Sprite2D.new()
	sprite_3d_display.texture = viewport.get_texture()
	sprite_3d_display.scale = Vector2.ONE * 0.38
	add_child(sprite_3d_display)

func _pick_new_sidewalk_target() -> void:
	if not roam and not is_scared:
		walk_target = global_position
	else:
		super._pick_new_sidewalk_target()

func _clear_line(target: Node2D) -> bool:
	if not is_instance_valid(target): return false
	var query := PhysicsRayQueryParameters2D.create(global_position, target.global_position, 1 | 2 | 4, [get_rid()])
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == target

func _physics_process(delta: float) -> void:
	_flinch = maxf(0, _flinch - delta)
	_punch_cooldown = maxf(0, _punch_cooldown - delta)
	if is_dead:
		_update_viewport_render_state(delta)
		if _slide.length() > 1:
			velocity = _slide
			move_and_slide()
			_slide = _slide.move_toward(Vector2.ZERO, delta * 350)
		else:
			velocity = Vector2.ZERO
		return
	if response == 1 and is_instance_valid(combat_target):
		if combat_target.get("is_dead") == true or global_position.distance_to(combat_target.global_position) > 450:
			combat_target = null
			_punch_time = -1
		else:
			_update_viewport_render_state(delta)
			var direction := global_position.direction_to(combat_target.global_position)
			var distance := global_position.distance_to(combat_target.global_position)
			velocity = direction * base_walk_speed * 1.25 if distance > 30 else Vector2.ZERO
			if _punch_time >= 0: velocity *= 0.25
			move_and_slide()
			model_root.rotation.y = lerp_angle(model_root.rotation.y, -direction.angle() - PI / 2, 1 - exp(-12 * delta))
			walk_timer += delta * velocity.length() / maxf(1, base_walk_speed)
			left_upper_leg.rotation.x = sin(walk_timer * 7.5) * 0.35 if velocity.length() > 1 else 0
			right_upper_leg.rotation.x = -left_upper_leg.rotation.x
			if distance < 39 and _punch_cooldown <= 0 and _clear_line(combat_target):
				_punch_time = 0
				_punch_cooldown = 0.9
				_punch_connected = false
				_left_punch = not _left_punch
			left_upper_arm.rotation = Vector3(0.95, 0, -0.12)
			right_upper_arm.rotation = Vector3(0.95, 0, 0.12)
			left_lower_arm.rotation.x = 0.9
			right_lower_arm.rotation.x = 0.9
			if _punch_time >= 0:
				_punch_time += delta
				var reach := sin(clampf(_punch_time / 0.5, 0, 1) * PI)
				var arm := left_upper_arm if _left_punch else right_upper_arm
				var forearm := left_lower_arm if _left_punch else right_lower_arm
				arm.rotation.x += reach * 0.55
				forearm.rotation.x -= reach * 0.8
				if _punch_time >= 0.22 and not _punch_connected:
					_punch_connected = true
					if distance < 42 and _clear_line(combat_target) and combat_target.has_method("take_damage"):
						combat_target.take_damage(7)
						punches_landed += 1
				if _punch_time >= 0.5: _punch_time = -1
			return
	super._physics_process(delta)
	if not is_dead:
		torso_node.rotation.z = sin(_flinch / 0.23 * PI) * 0.10
		if _gun_grip:
			# Keep the muzzle forward rather than inheriting the lifted forearm.
			_gun_grip.basis = (right_upper_arm.basis * right_lower_arm.basis).inverse()

func _gangster_shoot_target(target_pos: Vector2) -> void:
	if not _clear_line(combat_target): return
	shots_fired += 1
	super._gangster_shoot_target(target_pos)

func take_damage(amount: int, is_player_attacker: bool = false) -> void:
	if is_dead or amount <= 0: return
	_flinch = 0.23
	super.take_damage(amount, is_player_attacker)
	if not is_dead and response == 1 and is_player_attacker:
		combat_target = get_tree().get_first_node_in_group("player")
		is_scared = false
		if _panic_bubble: _panic_bubble.hide()

func _die(is_player_attacker: bool = false) -> void:
	if is_dead: return
	var original := model_root.rotation
	super._die(is_player_attacker)
	death_animation_started = true
	model_root.rotation = original
	var fall := create_tween().set_parallel(true)
	fall.tween_property(model_root, "rotation:x", PI * 0.47, 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.tween_property(left_upper_leg, "rotation:x", -0.6, 0.28)
	fall.tween_property(right_upper_arm, "rotation:z", 0.7, 0.4)
	fall.tween_property(left_upper_arm, "rotation:z", -0.45, 0.4)
	# A horizontal body occupies more screen space than an upright one. Reframe
	# its local render gently so the head/feet are not clipped by the viewport.
	var render_camera := viewport.get_child(0) as Camera3D
	if render_camera:
		if render_camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
			fall.tween_property(render_camera, "size", 2.5, 0.65)
		else:
			fall.tween_property(render_camera, "fov", 40.0, 0.65)
		fall.tween_method(func(target: Vector3): render_camera.look_at(target), Vector3(0,0.65,0), Vector3(0,0.20,0.50), 0.65)

func get_run_over(impact_velocity: Vector2, _is_player_driver: bool = false) -> void:
	if is_dead: return
	_slide = impact_velocity.limit_length(240) * 0.65
	health = 0
	_die()
