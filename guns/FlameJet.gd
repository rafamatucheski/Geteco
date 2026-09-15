class_name FlameJet
extends Node2D

@export var damage_per_tick: int = 2
@export var flame_range: float = 140.0
@export var flame_lifetime: float = 0.32
@export var flame_spread_angle: float = 0.30

var falloff_start := 55.0
var min_damage_ratio := 0.25

func configure_range(data: Dictionary) -> void:
	flame_range = float(data.max_range)
	falloff_start = float(data.falloff_start)
	min_damage_ratio = float(data.min_damage_ratio)
	damage_per_tick = int(data.damage)

func damage_at_distance(distance: float) -> int:
	return WeaponCatalog.distance_damage(damage_per_tick, distance, falloff_start, flame_range, min_damage_ratio)

var direction: Vector2 = Vector2.RIGHT
var shooter: Node2D = null
var _elapsed: float = 0.0
var _hit_bodies: Array = []

# Nós visuais do jato de chamas
var flame_core: CPUParticles2D
var flame_body: CPUParticles2D
var flame_smoke: CPUParticles2D
var flame_light: PointLight2D
var damage_area: Area2D

func _ready() -> void:
	z_index = 8
	rotation = direction.angle()

	var flame_tex = _get_smooth_flame_texture()

	# 1. Partículas do Núcleo Incandescente (Jato fino e veloz)
	flame_core = CPUParticles2D.new()
	flame_core.texture = flame_tex
	flame_core.emitting = true
	flame_core.one_shot = true
	flame_core.amount = 8
	flame_core.lifetime = flame_lifetime * 0.85
	flame_core.spread = 8.0
	flame_core.initial_velocity_min = flame_range / flame_core.lifetime * 0.85
	flame_core.initial_velocity_max = flame_range / flame_core.lifetime
	flame_core.gravity = Vector2.ZERO
	flame_core.scale_amount_min = 0.10
	flame_core.scale_amount_max = 0.22
	flame_core.color = Color(1.0, 0.95, 0.70, 0.90)
	add_child(flame_core)

	# 2. Corpo do Jato de Fogo (Chamas em cone controlado)
	flame_body = CPUParticles2D.new()
	flame_body.texture = flame_tex
	flame_body.emitting = true
	flame_body.one_shot = true
	flame_body.amount = 12
	flame_body.lifetime = flame_lifetime
	flame_body.spread = 14.0
	flame_body.initial_velocity_min = flame_range / flame_lifetime * 0.85
	flame_body.initial_velocity_max = flame_range / flame_lifetime
	flame_body.gravity = Vector2(0, -10)
	flame_body.scale_amount_min = 0.18
	flame_body.scale_amount_max = 0.40
	flame_body.color = Color(1.0, 0.40, 0.08, 0.85)
	add_child(flame_body)

	# 3. Fumaça de Queima de Napalm
	flame_smoke = CPUParticles2D.new()
	flame_smoke.texture = flame_tex
	flame_smoke.emitting = true
	flame_smoke.one_shot = true
	flame_smoke.amount = 4
	flame_smoke.lifetime = flame_lifetime * 1.2
	flame_smoke.spread = 20.0
	flame_smoke.initial_velocity_min = flame_range / flame_lifetime * 0.65
	flame_smoke.initial_velocity_max = flame_range / flame_lifetime * 0.80
	flame_smoke.gravity = Vector2(0, -25)
	flame_smoke.scale_amount_min = 0.25
	flame_smoke.scale_amount_max = 0.50
	flame_smoke.color = Color(0.25, 0.22, 0.20, 0.22)
	add_child(flame_smoke)
	for emitter in [flame_core, flame_body, flame_smoke]:
		emitter.local_coords = false
		emitter.explosiveness = 0.90
		emitter.direction = Vector2.RIGHT
		emitter.spread = rad_to_deg(flame_spread_angle) * (0.35 if emitter == flame_core else 0.7)
		emitter.color_ramp = _flame_fade()
		emitter.scale_amount_curve = _flame_expansion()

	# Player owns the sustained nozzle light. Per-packet lights stacked
	# twenty times per second and washed the flame into a yellow blob.

	# 5. Área de Dano em Cone Curto
	damage_area = Area2D.new()
	damage_area.collision_layer = 0
	damage_area.collision_mask = 7 # Veículos, Pedestres, Inimigos
	var col = CollisionPolygon2D.new()
	col.polygon = PackedVector2Array([
		Vector2(12, -8),
		Vector2(flame_range * 0.5, -24),
		Vector2(flame_range, -36),
		Vector2(flame_range + 10, 0),
		Vector2(flame_range, 36),
		Vector2(flame_range * 0.5, 24),
		Vector2(12, 8)
	])
	damage_area.add_child(col)
	add_child(damage_area)

	damage_area.body_entered.connect(_on_body_entered)
	damage_area.area_entered.connect(_on_area_entered)

static var _cached_flame_tex: Texture2D = null
static var _cached_fade: Gradient
static var _cached_expansion: Curve

static func _flame_fade() -> Gradient:
	if _cached_fade == null:
		_cached_fade = Gradient.new()
		_cached_fade.offsets = PackedFloat32Array([0, 0.15, 0.55, 1])
		_cached_fade.colors = PackedColorArray([Color(1,1,1,0), Color.WHITE, Color(1,0.72,0.35,0.85), Color(0.5,0.2,0.1,0)])
	return _cached_fade

static func _flame_expansion() -> Curve:
	if _cached_expansion == null:
		_cached_expansion = Curve.new()
		_cached_expansion.max_value = 1.5
		_cached_expansion.add_point(Vector2(0, 0.35))
		_cached_expansion.add_point(Vector2(0.45, 0.8))
		_cached_expansion.add_point(Vector2(1, 1.5))
	return _cached_expansion

static func _get_smooth_flame_texture() -> Texture2D:
	if _cached_flame_tex != null:
		return _cached_flame_tex
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var gradient_texture := GradientTexture2D.new()
	gradient_texture.gradient = gradient
	gradient_texture.fill = GradientTexture2D.FILL_RADIAL
	gradient_texture.fill_from = Vector2(0.5, 0.5)
	gradient_texture.fill_to = Vector2(0.5, 0.0)
	gradient_texture.width = 64
	gradient_texture.height = 64
	_cached_flame_tex = gradient_texture
	return _cached_flame_tex

func setup(origin: Vector2, dir: Vector2, owner_node: Node2D) -> void:
	global_position = origin
	direction = dir.normalized()
	rotation = direction.angle()
	shooter = owner_node

func _physics_process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()
	if flame_light:
		flame_light.energy = 0.55 * maxf(0.0, 1.0 - (_elapsed / flame_lifetime))

	if _elapsed >= flame_lifetime:
		damage_area.set_deferred("monitoring", false)
	# Let smoke and the last emitted particles finish rather than cutting
	# off the jet while it is still travelling toward the end of its range.
	if _elapsed >= flame_lifetime * 1.4:
		queue_free()

func _draw() -> void:
	# Overlapping moving tongues keep the stream connected at 20 Hz.
	# Particles supply the frayed edge; they are not isolated fireballs.
	var progress := _elapsed / flame_lifetime
	if progress >= 1.0: return
	var front := minf(flame_range, progress * flame_range + 32.0)
	var back := maxf(0.0, progress * flame_range - 18.0)
	var span := front - back
	var width := lerpf(2.2, 13.0, progress)
	var flutter := sin(progress * 43.0) * width * 0.2
	var alpha := 1.0 - smoothstep(0.72, 1.0, progress)
	for layer in 3:
		var radius: float = width * [1.0, 0.63, 0.26][layer]
		var color: Color = [Color(1,0.28,0.025,0.66), Color(1,0.68,0.06,0.8), Color(1,0.94,0.52,0.9)][layer]
		color.a *= alpha
		var points := PackedVector2Array([
			Vector2(back, 0), Vector2(back + span * 0.22, -radius * 0.6),
			Vector2(back + span * 0.50, -radius + flutter), Vector2(back + span * 0.77, -radius * 0.45),
			Vector2(front, flutter), Vector2(back + span * 0.66, radius * 0.7 + flutter),
			Vector2(back + span * 0.40, radius), Vector2(back + span * 0.15, radius * 0.4)
		])
		var uvs := PackedVector2Array()
		for point in points:
			uvs.append(Vector2((point.x - back) / span, (point.y / (radius * 1.3) + 1.0) * 0.5))
		draw_colored_polygon(points, color, uvs, _get_smooth_flame_texture())

func _on_body_entered(body: Node2D) -> void:
	_apply_fire_damage(body)

func _on_area_entered(area: Area2D) -> void:
	_apply_fire_damage(area)

func _apply_fire_damage(target: Node2D) -> void:
	if is_instance_valid(target) and target.has_meta("combat_actor"):
		target = target.get_meta("combat_actor")
	if not is_instance_valid(target) or target == shooter or _hit_bodies.has(target):
		return
	if _elapsed >= flame_lifetime: return
	var effective_damage := damage_at_distance(global_position.distance_to(target.global_position))
	if effective_damage <= 0: return
	if not preload("res://guns/combat/WeaponBlastDamage.gd").exposed(self, target, global_position): return
	_hit_bodies.append(target)

	# Cooldown de dano de fogo para evitar dano instantâneo infinito por sobreposição de partículas
	var now := Time.get_ticks_msec()
	if target.has_meta("_last_flame_hit"):
		if now - int(target.get_meta("_last_flame_hit")) < 120:
			return
	target.set_meta("_last_flame_hit", now)

	var is_player_attacker: bool = shooter != null and shooter.is_in_group("player")

	# Dano equilibrado (2-3 HP por tick de chama sustentada)
	if target.has_method("take_damage"):
		var previous_health: Variant = target.get("health")
		target.set_meta("combat_attacker", shooter)
		target.take_damage(effective_damage, is_player_attacker)
		if previous_health != null and target.get("health") < previous_health:
			preload("res://guns/combat/PersonBurning.gd").ignite(target, shooter)
	elif target.is_in_group("vehicle") and "health" in target:
		target.health = maxi(0, int(target.health) - effective_damage)

	# Pedestres entram em estado de pânico ao queimar
	if "is_scared" in target:
		target.is_scared = true
		if "panic_timer" in target:
			target.panic_timer = 2.5
