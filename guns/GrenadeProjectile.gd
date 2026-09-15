class_name GrenadeProjectile
extends CharacterBody2D

@export var fuse_time: float = 2.0
@export var damage: int = 180
@export var blast_radius: float = 140.0
@export var bounce_friction: float = 0.28

var max_throw_range := 320.0
var distance_travelled := 0.0

var throw_velocity: Vector2 = Vector2.ZERO
var owner_body: Node = null
var current_fuse: float = 0.0
var z_height: float = 12.0
var z_velocity: float = 180.0
var gravity_z: float = -620.0
var blink_timer: float = 0.0
var is_exploded: bool = false
var grenade_rotation: float = 0.0
var rot_speed: float = 8.0

func setup(origin: Vector2, target_dir: Vector2, throw_speed: float, thrower: Node) -> void:
	global_position = origin
	throw_velocity = target_dir * throw_speed
	velocity = throw_velocity
	owner_body = thrower
	if thrower is PhysicsBody2D:
		add_collision_exception_with(thrower)
		# The hand offset must not place the grenade behind a nearby wall/car.
		if is_inside_tree():
			var release := PhysicsRayQueryParameters2D.create(thrower.global_position, origin, 1 | 2)
			release.exclude = [get_rid(), thrower.get_rid()]
			var obstacle := get_world_2d().direct_space_state.intersect_ray(release)
			if not obstacle.is_empty(): global_position = obstacle.position + obstacle.normal * 7.0
	current_fuse = fuse_time
	z_height = 16.0
	z_velocity = 190.0
	grenade_rotation = randf() * TAU
	rot_speed = randf_range(8.0, 16.0)

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 | 2 | 4 | 8 # World, vehicles, people and props.
	z_as_relative = false
	z_index = 12
	add_to_group("explosives")
	queue_redraw()

func _physics_process(delta: float) -> void:
	if is_exploded:
		return
	
	current_fuse -= delta
	blink_timer += delta * 12.0
	
	# Simulação de altura Z (arco parabólico 3D e quique no chão)
	z_velocity += gravity_z * delta
	z_height += z_velocity * delta
	grenade_rotation += rot_speed * delta
	
	if z_height <= 0.0:
		z_height = 0.0
		z_velocity = -z_velocity * 0.32 if z_velocity < -45.0 else 0.0
		velocity = velocity * 0.72
		rot_speed *= 0.65
		if abs(z_velocity) > 25.0:
			_play_bounce_sound()
	
	# Movimento e colisão 2D com paredes e obstáculos
	var before := global_position
	var movement := velocity * delta
	movement = movement.limit_length(maxf(0.0, max_throw_range - distance_travelled))
	var collision = move_and_collide(movement)
	distance_travelled += before.distance_to(global_position)
	if distance_travelled >= max_throw_range: velocity = Vector2.ZERO
	if collision:
		velocity = velocity.bounce(collision.get_normal()) * bounce_friction
		# Contact removes forward energy and starts the fall beside the obstacle.
		z_velocity = minf(z_velocity, -45.0)
		rot_speed = -rot_speed * 0.8
		_play_bounce_sound()
	
	# Atrito no chão
	if z_height <= 0.5:
		velocity = velocity.move_toward(Vector2.ZERO, 380.0 * delta)
		rot_speed = move_toward(rot_speed, 0.0, 12.0 * delta)
	
	queue_redraw()
	
	if current_fuse <= 0.0:
		explode()

func _play_bounce_sound() -> void:
	var audio := AudioStreamPlayer2D.new()
	audio.stream = ProceduralAudio.get_ricochet_stream()
	audio.volume_db = -12.0
	audio.pitch_scale = randf_range(1.6, 2.2)
	get_parent().add_child(audio)
	audio.global_position = global_position
	audio.play()
	audio.finished.connect(audio.queue_free)

func explode() -> void:
	if is_exploded:
		return
	is_exploded = true
	
	# Som de explosão massiva com sub-bass
	var audio := AudioStreamPlayer2D.new()
	audio.stream = ProceduralAudio.get_explosion_stream()
	audio.volume_db = 4.0
	audio.pitch_scale = randf_range(0.9, 1.1)
	get_parent().add_child(audio)
	audio.global_position = global_position
	audio.play()
	audio.finished.connect(audio.queue_free)
	
	# Screen shake na câmera do jogador
	var player = get_tree().get_first_node_in_group("player")
	if preload("res://guns/combat/CombatWorld.gd").shares_world(self, player):
		var dist: float = global_position.distance_to(player.global_position)
		if dist < 650.0:
			var shake_intensity := clampf(1.0 - (dist / 650.0), 0.15, 1.0)
			if player.has_method("apply_screen_shake"):
				player.apply_screen_shake(shake_intensity * 14.0)
	
	# Dano em área (Pedestres, Carros, Inimigos)
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var circle = CircleShape2D.new()
	circle.radius = blast_radius
	query.shape = circle
	query.transform = Transform2D(0, global_position)
	query.collision_mask = 1 | 2 | 4 | 8
	
	var results = space_state.intersect_shape(query, 128)
	var damaged := {}
	for res in results:
		var collider = res.get("collider")
		if is_instance_valid(collider) and collider.has_meta("combat_actor"):
			collider = collider.get_meta("combat_actor")
		if is_instance_valid(collider) and collider != self:
			if damaged.has(collider.get_instance_id()): continue
			damaged[collider.get_instance_id()] = true
			var cover := PhysicsRayQueryParameters2D.create(global_position, collider.global_position, 1 | 2)
			cover.exclude = [get_rid(), collider.get_rid()]
			if not space_state.intersect_ray(cover).is_empty(): continue
			var hit_dist: float = global_position.distance_to(collider.global_position)
			var falloff: float = clampf(1.0 - (hit_dist / blast_radius), 0.0, 1.0)
			var total_dmg: int = int(damage * falloff)
			if total_dmg <= 0: continue
			
			if collider.has_method("take_damage"):
				preload("res://guns/combat/WeaponBlastDamage.gd").apply(collider, total_dmg, global_position, self, owner_body as Node2D)
			elif collider.has_method("damage_vehicle"):
				collider.damage_vehicle(total_dmg, global_position.direction_to(collider.global_position))
			elif collider.has_method("explode") and collider != owner_body:
				collider.explode()
	
	# Efeito visual procedural de detonação
	_spawn_explosion_visual()
	queue_free()

func _spawn_explosion_visual() -> void:
	preload("res://guns/combat/ExplosionVisual.gd").spawn(get_parent(), global_position, blast_radius)

func _draw() -> void:
	if is_exploded:
		return
	
	# 1. Sombra projetada no chão
	var shadow_scale := clampf(1.0 - (z_height / 80.0), 0.3, 1.0)
	draw_circle(Vector2(0, 0), 4.5 * shadow_scale, Color(0.02, 0.02, 0.05, 0.45 * shadow_scale))
	
	# 2. Corpo da Granada 2.5D com elevação Z
	var draw_pos := Vector2(0, -z_height)
	
	# Corpo verde-oliva com ranhuras de fragmentação
	draw_circle(draw_pos, 5.0, Color("3b5e2b")) # Verde oliva militar
	draw_circle(draw_pos, 4.0, Color("4d7c38"))
	
	# Pino e detonador prateado
	var pin_dir := Vector2.UP.rotated(grenade_rotation)
	draw_line(draw_pos, draw_pos + pin_dir * 4.5, Color("dcdde1"), 2.0)
	
	# LED vermelho indicador de fusível piscando
	var is_blinking: bool = fmod(blink_timer, 2.0) < 1.0 or current_fuse < 0.6
	var led_col := Color("ff3838") if is_blinking else Color("400000")
	draw_circle(draw_pos + Vector2(1, -1), 1.6, led_col)
