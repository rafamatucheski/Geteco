class_name MountainTunnel
extends Node2D

## Túnel da Montanha com Mecânica de Visão Cutaway:
## Quando o jogador cruza os portais do túnel (de carro ou a pé), o teto rochoso
## esvanece suavemente para revelar a pista subterrânea iluminada com luzes âmbar,
## acostamentos e saídas secretas dos contrabandistas.

signal tunnel_entered(body: Node2D)
signal tunnel_exited(body: Node2D)

@export var tunnel_length: float = 900.0
@export var tunnel_width: float = 160.0

var roof_canvas: Node2D
var interior_node: Node2D
var tunnel_area: Area2D
var _inside_bodies: Array[Node2D] = []
var _tween: Tween

func _ready() -> void:
	_build_walls()
	_build_interior()
	_build_roof()
	_build_trigger_area()

func _build_interior() -> void:
	interior_node = Node2D.new()
	interior_node.name = "TunnelInterior"
	interior_node.z_index = 2
	add_child(interior_node)
	
	# Pista de asfalto do túnel
	var road := Polygon2D.new()
	road.name = "TunnelAsphalt"
	road.color = Color(0.13, 0.14, 0.17)
	road.polygon = PackedVector2Array([
		Vector2(-10, -tunnel_width * 0.5),
		Vector2(tunnel_length + 10, -tunnel_width * 0.5),
		Vector2(tunnel_length + 10, tunnel_width * 0.5),
		Vector2(-10, tunnel_width * 0.5)
	])
	interior_node.add_child(road)
	
	# Faixas amarelas e brancas
	var center_line := Line2D.new()
	center_line.width = 3.0
	center_line.default_color = Color(1.0, 0.8, 0.2, 0.9)
	center_line.points = PackedVector2Array([Vector2(0, 0), Vector2(tunnel_length, 0)])
	interior_node.add_child(center_line)
	
	# Calçadas / Sarjetas de concreto do túnel
	var curb_top := Line2D.new()
	curb_top.width = 12.0
	curb_top.default_color = Color(0.35, 0.37, 0.42)
	curb_top.points = PackedVector2Array([Vector2(0, -tunnel_width * 0.5 + 6), Vector2(tunnel_length, -tunnel_width * 0.5 + 6)])
	interior_node.add_child(curb_top)
	
	var curb_bot := Line2D.new()
	curb_bot.width = 12.0
	curb_bot.default_color = Color(0.35, 0.37, 0.42)
	curb_bot.points = PackedVector2Array([Vector2(0, tunnel_width * 0.5 - 6), Vector2(tunnel_length, tunnel_width * 0.5 - 6)])
	interior_node.add_child(curb_bot)
	
	# Iluminação Âmbar de Emergência ao longo do túnel
	var light_spacing: float = 180.0
	var current_x: float = 90.0
	while current_x < tunnel_length:
		var lamp := PointLight2D.new()
		lamp.name = "AmberLamp_%d" % int(current_x)
		lamp.position = Vector2(current_x, 0)
		lamp.color = Color(1.0, 0.72, 0.32, 1.0)
		lamp.energy = 1.25
		lamp.texture_scale = 1.8
		# Textura radial suave para o ponto de luz
		var light_img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for ly in 64:
			for lx in 64:
				var dist: float = Vector2(lx - 31.5, ly - 31.5).length()
				var alpha: float = clampf(1.0 - (dist / 31.5), 0.0, 1.0)
				light_img.set_pixel(lx, ly, Color(1, 1, 1, alpha * alpha))
		lamp.texture = ImageTexture.create_from_image(light_img)
		interior_node.add_child(lamp)
		current_x += light_spacing

func _build_roof() -> void:
	roof_canvas = Node2D.new()
	roof_canvas.name = "TunnelRoof"
	roof_canvas.z_index = 8 # Cobre o carro ate o cutaway
	add_child(roof_canvas)
	
	# Sombra projetada do macico rochoso
	var shadow := Polygon2D.new()
	shadow.color = Color(0.03, 0.04, 0.05, 0.45)
	shadow.polygon = PackedVector2Array([
		Vector2(10, -tunnel_width * 0.52 + 10),
		Vector2(tunnel_length + 15, -tunnel_width * 0.52 + 10),
		Vector2(tunnel_length + 15, tunnel_width * 0.52 + 12),
		Vector2(10, tunnel_width * 0.52 + 12)
	])
	roof_canvas.add_child(shadow)

	# Macico rochoso central com camadas de relevo
	var rock_roof := Polygon2D.new()
	rock_roof.name = "MountainRockMass"
	rock_roof.color = Color("#2e2722")
	rock_roof.polygon = PackedVector2Array([
		Vector2(-5, -tunnel_width * 0.52),
		Vector2(tunnel_length + 5, -tunnel_width * 0.52),
		Vector2(tunnel_length + 5, tunnel_width * 0.52),
		Vector2(-5, tunnel_width * 0.52)
	])
	roof_canvas.add_child(rock_roof)

	var ridge1 := Polygon2D.new()
	ridge1.color = Color("#3b322b")
	ridge1.polygon = PackedVector2Array([
		Vector2(80, -tunnel_width * 0.45),
		Vector2(tunnel_length - 80, -tunnel_width * 0.45),
		Vector2(tunnel_length - 120, 0),
		Vector2(120, 0)
	])
	roof_canvas.add_child(ridge1)

	var ridge2 := Polygon2D.new()
	ridge2.color = Color("#4a3f36")
	ridge2.polygon = PackedVector2Array([
		Vector2(140, -tunnel_width * 0.35),
		Vector2(tunnel_length - 140, -tunnel_width * 0.35),
		Vector2(tunnel_length - 180, -10),
		Vector2(180, -10)
	])
	roof_canvas.add_child(ridge2)
	
	# Portais de concreto armado com sinalizacao viaria nos dois lados
	for px in [0.0, tunnel_length]:
		var portal := Polygon2D.new()
		portal.color = Color("#7f8c8d")
		portal.polygon = PackedVector2Array([
			Vector2(px - 14, -tunnel_width * 0.58),
			Vector2(px + 14, -tunnel_width * 0.58),
			Vector2(px + 14, tunnel_width * 0.58),
			Vector2(px - 14, tunnel_width * 0.58)
		])
		roof_canvas.add_child(portal)

		var beam := Line2D.new()
		beam.width = 5.0
		beam.default_color = Color("#95a5a6")
		beam.points = PackedVector2Array([
			Vector2(px, -tunnel_width * 0.58),
			Vector2(px, tunnel_width * 0.58)
		])
		roof_canvas.add_child(beam)

		# Faixas zebradas refletivas no topo do portal
		for y_off in [-tunnel_width * 0.45, tunnel_width * 0.45]:
			var sign_box := Polygon2D.new()
			sign_box.color = Color("#f39c12")
			sign_box.polygon = PackedVector2Array([
				Vector2(px - 12, y_off - 12), Vector2(px + 12, y_off - 12),
				Vector2(px + 12, y_off + 12), Vector2(px - 12, y_off + 12)
			])
			roof_canvas.add_child(sign_box)

func _build_trigger_area() -> void:
	tunnel_area = Area2D.new()
	tunnel_area.name = "CutawayTriggerArea"
	tunnel_area.collision_layer = 0
	tunnel_area.collision_mask = 1 | 2 | 4 | 8 # Detecta jogador, pedestre e carros
	add_child(tunnel_area)
	
	var col := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(tunnel_length, tunnel_width)
	col.shape = box
	col.position = Vector2(tunnel_length * 0.5, 0)
	tunnel_area.add_child(col)
	
	tunnel_area.body_entered.connect(_on_body_entered)
	tunnel_area.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	if body is StaticBody2D:
		return
	if not _inside_bodies.has(body):
		_inside_bodies.append(body)
	_update_cutaway()
	tunnel_entered.emit(body)

func _on_body_exited(body: Node2D) -> void:
	_inside_bodies.erase(body)
	_update_cutaway()
	tunnel_exited.emit(body)

func _update_cutaway() -> void:
	_inside_bodies = _inside_bodies.filter(func(b): return is_instance_valid(b))
	var should_reveal: bool = _inside_bodies.any(func(body): return body.is_in_group("player") or body.get("is_driven_by_player") == true)
	if should_reveal == _last_revealed: return
	_last_revealed = should_reveal
	var target_alpha: float = 0.0 if should_reveal else 1.0
	
	if _tween and _tween.is_valid():
		_tween.kill()
	
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(roof_canvas, "modulate:a", target_alpha, 0.28)

func is_revealed() -> bool:
	return roof_canvas != null and roof_canvas.modulate.a < 0.5

func _build_walls() -> void:
	for side in [-1.0, 1.0]:
		var wall := StaticBody2D.new()
		wall.name = "TunnelWallNorth" if side < 0 else "TunnelWallSouth"
		wall.collision_layer = 1
		wall.collision_mask = 0
		wall.position = Vector2(tunnel_length * 0.5, side * (tunnel_width * 0.5 + 16.0))
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(tunnel_length + 32.0, 32.0)
		shape.shape = box
		wall.add_child(shape)
		add_child(wall)

func contains_actor(actor: Node2D) -> bool:
	return is_instance_valid(actor) and Rect2(0, -tunnel_width * 0.5, tunnel_length, tunnel_width).has_point(to_local(actor.global_position))

var _last_revealed := false
func _process(_delta: float) -> void:
	_update_cutaway()
