@tool
class_name StreetLamp
extends StaticBody2D

@export var is_facing_south: bool = true

var lamp_light: PointLight2D
var light_glow_sprite: Sprite2D
var is_lit: bool = false

func _ready() -> void:
	z_index = 8 # Fica acima das calçadas
	add_to_group("obstacle")
	add_to_group("metal_prop")
	
	# Configura camadas de colisão física sólida indestrutível
	collision_layer = 1 # Camada de Mundo / Obstáculos sólidos
	collision_mask = 0
	
	_build_lamp_post()
	_setup_collision()
	_setup_light()
	
	# Conecta com o gerenciador de Dia/Noite
	var mgr = get_tree().get_first_node_in_group("day_night_manager")
	if mgr:
		mgr.time_changed.connect(set_lit)
		set_lit(mgr.get("is_dark") == true)
	else:
		set_lit(true)

func _setup_collision() -> void:
	# Colisor cilíndrico sólido de ferro fundido na base
	var col := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 5.0
	col.shape = circle
	col.position = Vector2.ZERO
	add_child(col)

func _build_lamp_post() -> void:
	# 1. Base do Poste de Ferro Fundido
	var base = Polygon2D.new()
	base.polygon = PackedVector2Array([
		Vector2(-6, -6), Vector2(6, -6), Vector2(6, 6), Vector2(-6, 6)
	])
	base.color = Color(0.18, 0.20, 0.24)
	add_child(base)
	
	# Anel de reforço da base
	var ring = Polygon2D.new()
	ring.polygon = PackedVector2Array([
		Vector2(-4, -4), Vector2(4, -4), Vector2(4, 4), Vector2(-4, 4)
	])
	ring.color = Color(0.12, 0.14, 0.16)
	add_child(ring)
	
	# 2. Haste do Poste
	var pole = Polygon2D.new()
	var arm_offset = Vector2(0, 24) if is_facing_south else Vector2(0, -24)
	pole.polygon = PackedVector2Array([
		Vector2(-2, 0), Vector2(2, 0),
		arm_offset + Vector2(2, 0), arm_offset + Vector2(-2, 0)
	])
	pole.color = Color(0.28, 0.32, 0.38)
	add_child(pole)
	
	# 3. Cabeçote da Luminária
	var head = Polygon2D.new()
	var h_pos = arm_offset
	head.polygon = PackedVector2Array([
		h_pos + Vector2(-6, -4), h_pos + Vector2(6, -4),
		h_pos + Vector2(6, 4), h_pos + Vector2(-6, 4)
	])
	head.color = Color(0.85, 0.85, 0.90)
	add_child(head)

func _setup_light() -> void:
	var arm_offset = Vector2(0, 24) if is_facing_south else Vector2(0, -24)
	
	# Ponto de Luz Âmbar 2D
	lamp_light = PointLight2D.new()
	lamp_light.name = "LampLight"
	lamp_light.color = Color(1.0, 0.86, 0.60, 1.0)
	lamp_light.energy = 1.1
	lamp_light.position = arm_offset
	
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.95, 0.75, 1.0),
		Color(1.0, 0.85, 0.55, 0.65),
		Color(1.0, 0.80, 0.40, 0.0)
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 240
	tex.height = 240
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	lamp_light.texture = tex
	lamp_light.visible = false
	add_child(lamp_light)

func set_lit(lit: bool) -> void:
	is_lit = lit
	if lamp_light:
		lamp_light.visible = is_lit

# Postes são indestrutíveis: absorvem impacto de balas produzindo faíscas metálicas
func take_damage(_amount: int, _is_player: bool = false) -> void:
	pass
