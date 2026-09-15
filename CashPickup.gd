class_name CashPickup
extends Area2D

## Maço de Dinheiro Compacto Estilo Retrô Arcade (GTA 1/2)
## Tamanho reduzido, animação de flutuação suave e áudio de caixa registradora ao coletar.

@export var amount: int = 50
var _clock: float = 0.0
var _is_collected: bool = false

var visual_root: Node2D
var bundle_poly: Polygon2D
var strap_poly: Polygon2D
var glow_circle: Polygon2D
var label: Label

func _ready() -> void:
	z_index = 8
	collision_layer = 0
	collision_mask = 4 # Player/pedestrians; group check below accepts only Player.
	
	var col := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 16.0
	col.shape = circle
	add_child(col)
	
	visual_root = Node2D.new()
	add_child(visual_root)
	
	# Halo suave verde de chão
	glow_circle = Polygon2D.new()
	glow_circle.polygon = _create_circle_polygon(10.0, 12)
	glow_circle.color = Color(0.18, 0.85, 0.45, 0.22)
	visual_root.add_child(glow_circle)
	
	# Maço compacto de cédulas verdes (14x8 px)
	bundle_poly = Polygon2D.new()
	bundle_poly.color = Color("#2ed573")
	bundle_poly.polygon = PackedVector2Array([
		Vector2(-7, -4), Vector2(7, -4), Vector2(7, 4), Vector2(-7, 4)
	])
	visual_root.add_child(bundle_poly)
	
	# Faixa/Cinta branca central do maço de dinheiro
	strap_poly = Polygon2D.new()
	strap_poly.color = Color(0.96, 0.96, 0.96, 0.95)
	strap_poly.polygon = PackedVector2Array([
		Vector2(-2, -4), Vector2(2, -4), Vector2(2, 4), Vector2(-2, 4)
	])
	bundle_poly.add_child(strap_poly)
	
	# Label de valor flutuante (invisível até ser coletado)
	label = Label.new()
	label.text = "+$%d" % amount
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-24, -18)
	label.size = Vector2(48, 14)
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color("#2ecc71"))
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.visible = false
	add_child(label)
	
	body_entered.connect(_on_body_entered)
	
	# Desaparece suavemente após 25 segundos se não for coletado
	var lifetime_tween := create_tween()
	lifetime_tween.tween_interval(18.0)
	lifetime_tween.tween_property(self, "modulate:a", 0.0, 7.0)
	lifetime_tween.tween_callback(queue_free)

func _create_circle_polygon(radius: float, points: int) -> PackedVector2Array:
	var arr := PackedVector2Array()
	for i in range(points):
		var ang = (float(i) / float(points)) * TAU
		arr.append(Vector2(cos(ang), sin(ang)) * radius)
	return arr

func _process(delta: float) -> void:
	if _is_collected: return
	_clock += delta * 3.5
	if visual_root:
		visual_root.position.y = sin(_clock) * 2.0
		bundle_poly.scale.x = cos(_clock * 0.8) * 0.15 + 0.90
		if glow_circle:
			glow_circle.scale = Vector2.ONE * (1.0 + sin(_clock * 2.0) * 0.12)

func _on_body_entered(body: Node2D) -> void:
	if _is_collected:
		return
	if body.is_in_group("player"):
		_is_collected = true
		if "money" in body:
			body.money += amount
			if body.has_method("_refresh_weapon_ui"):
				body._refresh_weapon_ui()
		
		# Som satisfatório de caixa registradora (Cha-Ching!)
		preload("res://audio/rewards/RewardAudioBank.gd").play(self, "cash")
		
		# Efeito flutuante de coleta
		if bundle_poly: bundle_poly.visible = false
		if glow_circle: glow_circle.visible = false
		label.visible = true
		
		var tw := create_tween().set_parallel(true)
		tw.tween_property(label, "position:y", label.position.y - 22.0, 0.45)
		tw.tween_property(label, "modulate:a", 0.0, 0.45)
		tw.chain().tween_callback(queue_free)
