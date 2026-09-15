class_name MountainSkier
extends CharacterBody2D

var course_points := PackedVector2Array()
var target_index := 1
var cruise_speed := 175.0
var coat_color := Color("4f7890")
var appearance_variant := 0
var model: Node3D
var viewport_3d: SubViewport
var presentation_sprite: Sprite2D
var wait_time := 0.0
var fallen_time := 0.0
var clock := 0.0
var render_clock := 0.0
var fall_each_lap := false # Legacy configuration, falls now require an impact.
var impact_cooldown := 0.0
var fell_this_lap := false
var health := 80
var is_dead := false
var panic_timer := 0.0
var danger_response := preload("res://PedestrianDanger.gd").new()

func configure(points: PackedVector2Array, speed: float, color: Color, variant: int, falls := false) -> void:
	course_points = points
	cruise_speed = speed
	coat_color = color
	appearance_variant = variant
	fall_each_lap = falls

func _ready() -> void:
	render_clock = float(posmod(appearance_variant,7))/7.0/30.0
	add_to_group("pedestrian")
	add_to_group("damageable")
	add_to_group("mountain_skier")
	collision_layer = 4
	collision_mask = 1 | 4
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	z_index = 9
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 7.0
	collision.shape = shape
	add_child(collision)
	viewport_3d = SubViewport.new()
	viewport_3d.size = Vector2i(128, 128)
	viewport_3d.own_world_3d = true
	viewport_3d.transparent_bg = true
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport_3d)
	preload("res://world/shared/pedestrians/WinterWardrobe.gd").light_viewport(viewport_3d)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-55,-24,0)
	key.light_energy = .8
	viewport_3d.add_child(key)
	model = preload("res://world/mountain_pass/MountainSkierModel.gd").new()
	model.coat_color = coat_color
	model.role = "visitor"
	model.appearance_variant = appearance_variant
	viewport_3d.add_child(model)
	model.set_process(false)
	var camera := Camera3D.new()
	viewport_3d.add_child(camera)
	camera.position = Vector3(0, 4, 3)
	camera.look_at(Vector3(0, 0.85, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.8
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var sprite := Sprite2D.new()
	presentation_sprite = sprite
	sprite.texture = viewport_3d.get_texture()
	sprite.scale = Vector2.ONE * (18.0 * 2.8 / 128.0)
	sprite.position = (Vector2(64, 64) - camera.unproject_position(Vector3.ZERO)) * sprite.scale
	add_child(sprite)
	if course_points.size() > 0:
		global_position = get_parent().to_global(course_points[0])

func _physics_process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null or global_position.distance_to(player.global_position) > 1650.0:
		return
	var schedule_script := preload("res://world/mountain_pass/MountainSkiSchedule.gd")
	if not schedule_script.is_open(self):
		velocity = Vector2.ZERO
		return
	if is_dead: return
	if panic_timer > 0.0:
		panic_timer -= delta
		velocity = danger_response.movement(self, delta, 150.0)
		move_and_slide()
		_refresh_model(delta, 0.0)
		return
	clock += delta
	impact_cooldown = maxf(0.0, impact_cooldown - delta)
	if wait_time > 0.0:
		wait_time = maxf(.01, wait_time - delta)
		velocity = Vector2.ZERO
		# Only recycle outside the camera at BOTH endpoints. No skier dissolves
		# in front of the player and teleports back onto the visible summit.
		if wait_time <= .02 and not _point_visible(global_position) and not _point_visible(get_parent().to_global(course_points[0])):
			_restart_lap()
		_refresh_model(delta, 0.0)
		return
	if fallen_time > 0.0:
		fallen_time -= delta
		velocity = velocity.move_toward(Vector2.ZERO, 230.0 * delta)
		move_and_slide()
		model.fallen = true
		if fallen_time <= 0.0: model.fallen = false
		_refresh_model(delta, 0.0)
		return
	if target_index >= course_points.size():
		wait_time = 2.0 + float(appearance_variant % 4) * 0.35
		velocity = Vector2.ZERO
		return
	var target: Vector2 = get_parent().to_global(course_points[target_index])
	var direction := global_position.direction_to(target)
	var weave := direction.orthogonal() * sin(clock * (0.8 + float(appearance_variant % 5) * 0.09)) * 0.04
	var desired := (direction + weave).normalized()
	velocity = velocity.lerp(desired * cruise_speed, 1.0 - exp(-7.0 * delta))
	var incoming := velocity
	move_and_slide()
	if impact_cooldown <= 0.0:
		for i in get_slide_collision_count():
			if -incoming.dot(get_slide_collision(i).get_normal()) > 110.0:
				_fall()
				break
	if global_position.distance_to(target) < 12.0:
		target_index += 1

	_refresh_model(delta, weave.dot(direction.orthogonal()))

func _fall() -> void:
	if fallen_time > 0.0: return
	impact_cooldown = 3.0
	fallen_time = 1.8
	fell_this_lap = true
	velocity *= 0.3
	model.fallen = true

func _restart_lap() -> void:
	wait_time = 0.0
	target_index = 1
	fell_this_lap = false
	model.fallen = false
	if is_instance_valid(presentation_sprite):
		presentation_sprite.modulate.a = 1.0
	if course_points.size() > 0:
		global_position = get_parent().to_global(course_points[0])
		reset_physics_interpolation()
	velocity = Vector2.ZERO

func _refresh_model(delta: float, carve: float) -> void:
	if velocity.length() > 2.0:
		model.rotation.y = lerp_angle(model.rotation.y, -velocity.angle() + PI * 0.5, minf(1.0, delta * 8.0))
	model.carve = carve
	model.speed_factor = clampf(velocity.length() / 300.0, 0.0, 1.0)
	render_clock += delta
	if render_clock >= 1.0 / 30.0 and _point_visible(global_position):
		model._process(render_clock)
		render_clock = fmod(render_clock,1.0/30.0)
		viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE

func hear_gunfire(origin: Vector2, end: Vector2) -> void:
	if is_dead: return
	danger_response.remember(origin, end)
	panic_timer = 10.0
	wait_time = 0.0

func take_damage(amount: int, _source: Variant = null) -> void:
	if is_dead or amount <= 0: return
	health = maxi(0, health - amount)
	_fall()
	if health == 0:
		is_dead = true
		collision_layer = 0
		velocity = Vector2.ZERO
		preload("res://guns/combat/GroundBlood.gd").spawn(self)
	_refresh_model(0.04, 0.0)

func _point_visible(point: Vector2) -> bool:
	var screen := get_viewport().get_canvas_transform() * point
	return get_viewport_rect().grow(100.0).has_point(screen)
