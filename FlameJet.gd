class_name FlameJet
extends Node2D

@export var damage_per_tick: int = 2
@export var flame_range: float = 175.0
@export var flame_lifetime: float = 0.32
@export var flame_spread_angle: float = 0.30

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
	flame_core.lifetime = flame_lifetime * 0.60
	flame_core.spread = 8.0
	flame_core.initial_velocity_min = 240.0
	flame_core.initial_velocity_max = 360.0
	flame_core.gravity = Vector2.ZERO
	flame_core.scale_amount_min = 0.15
	flame_core.scale_amount_max = 0.35
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
	flame_body.initial_velocity_min = 180.0
	flame_body.initial_velocity_max = 300.0
	flame_body.gravity = Vector2(0, -10)
	flame_body.scale_amount_min = 0.20
	flame_body.scale_amount_max = 0.55
	flame_body.color = Color(1.0, 0.40, 0.08, 0.85)
	add_child(flame_body)

	# 3. Fumaça de Queima de Napalm
	flame_smoke = CPUParticles2D.new()
	flame_smoke.texture = flame_tex
	flame_smoke.emitting = true
	flame_smoke.one_shot = true
	flame_smoke.amount = 6
	flame_smoke.lifetime = flame_lifetime * 1.2
	flame_smoke.spread = 20.0
	flame_smoke.initial_velocity_min = 100.0
	flame_smoke.initial_velocity_max = 200.0
	flame_smoke.gravity = Vector2(0, -25)
	flame_smoke.scale_amount_min = 0.25
	flame_smoke.scale_amount_max = 0.50
	flame_smoke.color = Color(0.20, 0.18, 0.18, 0.45)
	add_child(flame_smoke)

	# 4. Clarão Sutil e Suave na Ponta do Bico
	flame_light = PointLight2D.new()
	flame_light.color = Color(1.0, 0.65, 0.25)
	flame_light.energy = 0.55
	flame_light.position = Vector2(16, 0)
	
	var grad = Gradient.new()
	grad.colors = PackedColorArray([Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	var tex = GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	flame_light.texture = tex
	add_child(flame_light)

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
	if flame_light:
		flame_light.energy = 0.55 * maxf(0.0, 1.0 - (_elapsed / flame_lifetime))

	if _elapsed >= flame_lifetime:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	_apply_fire_damage(body)

func _on_area_entered(area: Area2D) -> void:
	_apply_fire_damage(area)

func _apply_fire_damage(target: Node2D) -> void:
	if not is_instance_valid(target) or target == shooter or _hit_bodies.has(target):
		return
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
		target.take_damage(damage_per_tick, is_player_attacker)
	elif target.is_in_group("vehicle") and "health" in target:
		target.health = maxi(0, int(target.health) - damage_per_tick)

	# Pedestres entram em estado de pânico ao queimar
	if "is_scared" in target:
		target.is_scared = true
		if "panic_timer" in target:
			target.panic_timer = 2.5
