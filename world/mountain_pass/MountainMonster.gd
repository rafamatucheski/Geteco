class_name MountainMonster
extends CharacterBody2D

var home := Vector2.ZERO
var patrol_points := PackedVector2Array()
var patrol_index := 0
var active := false
var attack_cooldown := 0.0
var retreat_time := 0.0
var viewport_3d: SubViewport
var model: Node3D
var render_clock := 0.0

func _ready() -> void:
	add_to_group("mountain_monster")
	collision_layer = 4
	collision_mask = 1
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	z_index = 11
	home = global_position
	patrol_points = PackedVector2Array([home, home + Vector2(-260, -230), home + Vector2(180, -470), home + Vector2(360, -160)])
	var collision := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = 13.0
	capsule.height = 36.0
	collision.shape = capsule
	add_child(collision)
	_build_view()
	visible = false
	set_physics_process(false)

func reveal() -> void:
	if active:
		return
	active = true
	visible = true
	set_physics_process(true)
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE

func _physics_process(delta: float) -> void:
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	retreat_time = maxf(0.0, retreat_time - delta)
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var target := patrol_points[patrol_index]
	var speed := 82.0
	var charging := false
	if is_instance_valid(player) and player.is_visible_in_tree() and not player.get_meta("mountain_interior", false):
		var distance := global_position.distance_to(player.global_position)
		if distance < 430.0 and retreat_time <= 0.0:
			target = player.global_position
			speed = 265.0 if player.get("is_skiing") == true else 155.0
			charging = distance < 250.0
		if distance < 34.0 and attack_cooldown <= 0.0:
			var impulse := global_position.direction_to(player.global_position) * 185.0
			if player.get("is_skiing") == true and is_instance_valid(player.get("ski_controller")):
				player.ski_controller.crash(24, impulse)
			elif player.has_method("take_damage"):
				player.take_damage(24)
			attack_cooldown = 5.0
			retreat_time = 2.2
			target = home
	if global_position.distance_to(target) < 28.0:
		patrol_index = (patrol_index + 1) % patrol_points.size()
		target = patrol_points[patrol_index]
	velocity = global_position.direction_to(target) * speed
	move_and_slide()
	if velocity.length_squared() > 1.0:
		model.rotation.y = lerp_angle(model.rotation.y, -velocity.angle() + PI * 0.5, minf(1.0, delta * 8.0))
	model.walking = velocity.length_squared() > 1.0
	model.charging = charging
	render_clock += delta
	if render_clock >= 0.05:
		model.animate(render_clock)
		render_clock = 0.0
		viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE

func take_damage(_amount: int, _source: Variant = null) -> void:
	# The sighting retreats into the storm; defeating it is deliberately left
	# unresolved so the diary remains an ongoing mountain legend.
	retreat_time = 4.0
	patrol_index = 0

func _build_view() -> void:
	viewport_3d = SubViewport.new()
	viewport_3d.size = Vector2i(192, 192)
	viewport_3d.transparent_bg = true
	viewport_3d.own_world_3d = true
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport_3d)
	model = preload("res://world/mountain_pass/MountainMonsterModel.gd").new()
	viewport_3d.add_child(model)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.4
	camera.position = Vector3(0, 5.0, 4.2)
	viewport_3d.add_child(camera)
	camera.look_at(Vector3(0, 1.35, 0))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -28, 0)
	sun.light_energy = 1.25
	viewport_3d.add_child(sun)
	var sprite := Sprite2D.new()
	sprite.texture = viewport_3d.get_texture()
	sprite.scale = Vector2.ONE * (24.0 * camera.size / float(viewport_3d.size.x))
	sprite.position = (Vector2(viewport_3d.size) * 0.5 - camera.unproject_position(Vector3.ZERO)) * sprite.scale
	add_child(sprite)
