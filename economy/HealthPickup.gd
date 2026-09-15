class_name HealthPickup
extends Area2D

## Ícone de Cruz Médica / Primeiros Socorros (GTA Style Health Pick-up)
## Localizado na entrada do Hospital. Recupera 100% da vida e renasce a cada 3 minutos (180s).

@export var heal_amount: int = 100
@export var respawn_seconds: float = 180.0
@export var auto_respawn: bool = true

var _clock: float = 0.0
var _is_collected: bool = false
var _respawn_timer: float = 0.0

var visual_root: Node2D
var cross_root: Node2D
var cross_h: Polygon2D
var cross_v: Polygon2D
var glow_circle: Polygon2D
var label: Label
var col_shape: CollisionShape2D

func _ready() -> void:
	z_index = 8
	collision_layer = 0
	collision_mask = 1 # Detecta o Player
	
	col_shape = CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 18.0
	col_shape.shape = circle
	add_child(col_shape)
	
	visual_root = Node2D.new()
	add_child(visual_root)
	
	# Halo Luminoso Rosa/Vermelho Médico
	glow_circle = Polygon2D.new()
	glow_circle.polygon = _create_circle_polygon(14.0, 16)
	glow_circle.color = Color(0.95, 0.20, 0.35, 0.28)
	visual_root.add_child(glow_circle)
	
	cross_root = Node2D.new()
	visual_root.add_child(cross_root)
	
	# Base Circular Branca
	var base_disc := Polygon2D.new()
	base_disc.polygon = _create_circle_polygon(10.0, 16)
	base_disc.color = Color(0.96, 0.96, 0.98, 0.95)
	cross_root.add_child(base_disc)
	
	# Barra Horizontal Vermelha
	cross_h = Polygon2D.new()
	cross_h.color = Color("#e74c3c")
	cross_h.polygon = PackedVector2Array([
		Vector2(-7, -2.5), Vector2(7, -2.5), Vector2(7, 2.5), Vector2(-7, 2.5)
	])
	cross_root.add_child(cross_h)
	
	# Barra Vertical Vermelha
	cross_v = Polygon2D.new()
	cross_v.color = Color("#e74c3c")
	cross_v.polygon = PackedVector2Array([
		Vector2(-2.5, -7), Vector2(2.5, -7), Vector2(2.5, 7), Vector2(-2.5, 7)
	])
	cross_root.add_child(cross_v)
	
	# Texto Flutuante de Vida
	label = Label.new()
	label.text = "+VIDA 100%"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-36, -24)
	label.size = Vector2(72, 16)
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color("#2ecc71"))
	label.visible = false
	add_child(label)
	
	body_entered.connect(_on_body_entered)

func _create_circle_polygon(radius: float, points: int) -> PackedVector2Array:
	var arr := PackedVector2Array()
	for i in range(points):
		var ang = (float(i) / float(points)) * TAU
		arr.append(Vector2(cos(ang), sin(ang)) * radius)
	return arr

func _process(delta: float) -> void:
	if _is_collected:
		if auto_respawn:
			_respawn_timer -= delta
			if _respawn_timer <= 0.0:
				_respawn_pickup()
		return
		
	_clock += delta * 2.8
	if cross_root:
		cross_root.scale.x = cos(_clock * 1.5)
		cross_root.position.y = -3.0 + sin(_clock * 2.0) * 2.5
	if glow_circle:
		var pulse = 0.22 + sin(_clock * 2.5) * 0.10
		glow_circle.color.a = pulse

func _on_body_entered(body: Node2D) -> void:
	if _is_collected: return
	if body.is_in_group("player"):
		_is_collected = true
		_respawn_timer = respawn_seconds
		col_shape.set_deferred("disabled", true)
		
		# Cura o Player
		if "max_health" in body:
			body.health = body.max_health
		elif "health" in body:
			body.health = 100
			
		if body.has_method("_refresh_weapon_ui"):
			body._refresh_weapon_ui()
			
		# Áudio de cura médica (Powerup)
		preload("res://audio/rewards/RewardAudioBank.gd").play(self, "pickup")
		
		# Efeito flutuante de coleta
		if visual_root: visual_root.visible = false
		label.visible = true
		label.modulate.a = 1.0
		label.position = Vector2(-36, -20)
		
		var tw := create_tween().set_parallel(true)
		tw.tween_property(label, "position:y", -46.0, 0.70)
		tw.tween_property(label, "modulate:a", 0.0, 0.70)

func _respawn_pickup() -> void:
	_is_collected = false
	col_shape.set_deferred("disabled", false)
	if visual_root:
		visual_root.visible = true
		visual_root.scale = Vector2.ONE
		visual_root.modulate.a = 1.0
