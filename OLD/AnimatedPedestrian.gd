class_name AnimatedPedestrian
extends CharacterBody2D

const ATLAS_PATH = "res://city_demo/art/pedestrian-directional-safe-v3.png"

@export var walk_speed: float = 48.0

var walk_target: Vector2 = Vector2.ZERO
var walk_timer: float = 0.0
var walk_dir: Vector2 = Vector2.RIGHT
var is_scared: bool = false
var panic_timer: float = 0.0
var health: int = 40
var is_dead: bool = false

var identity_col: int = 0
var facing_row: int = 0

var body_sprite: Sprite2D
var shadow: Polygon2D
var left_foot: Polygon2D
var right_foot: Polygon2D
var atlas_texture: AtlasTexture

func _ready() -> void:
	add_to_group("pedestrian")
	add_to_group("damageable")
	z_index = 6
	identity_col = randi() % 8
	
	_build_animated_rig()
	_pick_new_sidewalk_target()

func _build_animated_rig() -> void:
	# Sombra dinâmica
	shadow = Polygon2D.new()
	shadow.polygon = PackedVector2Array([
		Vector2(-7, -3), Vector2(0, -5), Vector2(7, -3),
		Vector2(7, 3), Vector2(0, 5), Vector2(-7, 3)
	])
	shadow.color = Color(0, 0, 0, 0.35)
	add_child(shadow)
	
	# Pés animados (Passos)
	left_foot = Polygon2D.new()
	left_foot.polygon = PackedVector2Array([Vector2(-2, -2), Vector2(2, -2), Vector2(2, 4), Vector2(-2, 4)])
	left_foot.color = Color(0.15, 0.12, 0.10)
	left_foot.position = Vector2(-3, 6)
	add_child(left_foot)
	
	right_foot = Polygon2D.new()
	right_foot.polygon = PackedVector2Array([Vector2(-2, -2), Vector2(2, -2), Vector2(2, 4), Vector2(-2, 4)])
	right_foot.color = Color(0.15, 0.12, 0.10)
	right_foot.position = Vector2(3, 6)
	add_child(right_foot)
	
	# Corpo com atlas direcional
	body_sprite = Sprite2D.new()
	var base_tex = load(ATLAS_PATH) as Texture2D
	if base_tex:
		atlas_texture = AtlasTexture.new()
		atlas_texture.atlas = base_tex
		atlas_texture.filter_clip = true
		_update_atlas_rect()
		body_sprite.texture = atlas_texture
		body_sprite.scale = Vector2(0.11, 0.11)
	body_sprite.position = Vector2(0, -6)
	add_child(body_sprite)
	
	# Colisão
	var col = CollisionShape2D.new()
	var cap = CapsuleShape2D.new()
	cap.radius = 6.0
	cap.height = 18.0
	col.shape = cap
	add_child(col)

func _update_atlas_rect() -> void:
	if atlas_texture:
		atlas_texture.region = Rect2(float(identity_col * 192), float(facing_row * 256), 192.0, 256.0)

func _physics_process(delta: float) -> void:
	if is_dead:
		velocity = velocity.move_toward(Vector2.ZERO, 400.0 * delta)
		move_and_slide()
		return
		
	walk_timer += delta
	
	if is_scared:
		panic_timer -= delta
		if panic_timer <= 0.0:
			is_scared = false
	
	var cur_speed = walk_speed * (2.2 if is_scared else 1.0)
	var dist = global_position.distance_to(walk_target)
	
	if dist < 16.0 or dist > 1200.0:
		_pick_new_sidewalk_target()
	
	walk_dir = global_position.direction_to(walk_target)
	velocity = walk_dir * cur_speed
	
	# Determina a linha direcional (0: Sul, 1: Leste, 2: Norte, 3: Oeste)
	var new_row = 0
	if absf(walk_dir.x) > absf(walk_dir.y):
		new_row = 1 if walk_dir.x > 0 else 3
	else:
		new_row = 0 if walk_dir.y > 0 else 2
		
	if new_row != facing_row:
		facing_row = new_row
		_update_atlas_rect()
	
	# Animação Procedural de Passos e Balanço de Corpo
	var step_cycle = sin(walk_timer * (14.0 if is_scared else 8.0))
	var bob_cycle = absf(cos(walk_timer * (14.0 if is_scared else 8.0)))
	
	if left_foot and right_foot:
		left_foot.position.y = 6.0 + step_cycle * 3.5
		right_foot.position.y = 6.0 - step_cycle * 3.5
		left_foot.position.x = -3.0 + walk_dir.x * 2.0
		right_foot.position.x = 3.0 + walk_dir.x * 2.0
		
	if body_sprite:
		body_sprite.position.y = -6.0 - bob_cycle * 2.5
		body_sprite.rotation = step_cycle * 0.07
			
	move_and_slide()

func _pick_new_sidewalk_target() -> void:
	var sidewalk_lanes = [
		Vector2(randf_range(-1400, 1400), -75),
		Vector2(randf_range(-1400, 1400), 75),
		Vector2(-75, randf_range(-600, 600)),
		Vector2(75, randf_range(-600, 600)),
		Vector2(randf_range(-1400, 1400), 475),
		Vector2(randf_range(-1400, 1400), -475)
	]
	walk_target = sidewalk_lanes[randi() % sidewalk_lanes.size()]

func get_run_over(impact_velocity: Vector2, _is_player_driver: bool = false) -> void:
	if is_dead: return
	is_dead = true
	health = 0
	velocity = impact_velocity.limit_length(500.0) * 0.8
	
	if body_sprite:
		body_sprite.rotation = PI * 0.5
		body_sprite.modulate = Color(0.6, 0.2, 0.2)
	if left_foot: left_foot.hide()
	if right_foot: right_foot.hide()
	
	var blood := CPUParticles2D.new()
	blood.emitting = true
	blood.one_shot = true
	blood.amount = 20
	blood.lifetime = 0.6
	blood.color = Color(0.75, 0.05, 0.05)
	add_child(blood)
	
	var p = AudioStreamPlayer2D.new()
	p.stream = ProceduralAudio.get_squish_stream()
	p.volume_db = -6.0
	add_child(p)
	p.play()
	
	var wm = get_node_or_null("/root/WantedManager")
	if _is_player_driver and wm:
		wm.report_crime(25)
	
	var t = create_tween()
	t.tween_interval(12.0)
	t.tween_property(self, "modulate:a", 0.0, 2.0)
	t.tween_callback(queue_free)

func take_damage(amount: int, _is_player_attacker: bool = false) -> void:
	if is_dead: return
	health = maxi(0, health - amount)
	is_scared = true
	panic_timer = 5.0
	walk_target = global_position + Vector2(randf_range(-300, 300), randf_range(-300, 300))
	if _is_player_attacker:
		var wm = get_node_or_null("/root/WantedManager")
		if wm: wm.report_crime(15)
	
	if health <= 0:
		get_run_over(Vector2(randf_range(-100, 100), randf_range(-100, 100)), _is_player_attacker)
