@tool
extends Node2D

enum Archetype {
	SKYSCRAPER,
	MEDIUM_APARTMENT,
	COMMERCIAL_SHOP,
	SUBURBAN_HOUSE,
	WAREHOUSE,
	PARK_PLAZA,
	CUSTOM
}

@export var archetype: Archetype = Archetype.CUSTOM:
	set(a):
		archetype = a
		_apply_archetype()
		queue_redraw()

@export var height: float = 120.0:
	set(h):
		height = h
		queue_redraw()

@export var size: Vector2 = Vector2(250, 250):
	set(s):
		size = s
		queue_redraw()

@export var building_color: Color = Color(0.6, 0.6, 0.6):
	set(c):
		building_color = c
		queue_redraw()

@export_group("Rooftop Details")
@export var has_helipad: bool = false:
	set(v):
		has_helipad = v
		queue_redraw()

@export var has_hvac: bool = true:
	set(v):
		has_hvac = v
		queue_redraw()

@export var has_antenna: bool = false:
	set(v):
		has_antenna = v
		queue_redraw()

@export var has_water_tower: bool = false:
	set(v):
		has_water_tower = v
		queue_redraw()

func _apply_archetype() -> void:
	match archetype:
		Archetype.SKYSCRAPER:
			height = 320.0
			size = Vector2(240, 240)
			building_color = Color("3a506b")
			has_helipad = true
			has_antenna = true
			has_hvac = true
			has_water_tower = false
		Archetype.MEDIUM_APARTMENT:
			height = 140.0
			size = Vector2(180, 180)
			building_color = Color("6c584c")
			has_helipad = false
			has_antenna = false
			has_hvac = true
			has_water_tower = true
		Archetype.COMMERCIAL_SHOP:
			height = 60.0
			size = Vector2(140, 120)
			building_color = Color("c08552")
			has_helipad = false
			has_antenna = false
			has_hvac = true
			has_water_tower = false
		Archetype.SUBURBAN_HOUSE:
			height = 50.0
			size = Vector2(100, 90)
			building_color = Color("a3b18a")
			has_helipad = false
			has_antenna = false
			has_hvac = false
			has_water_tower = false
		Archetype.WAREHOUSE:
			height = 70.0
			size = Vector2(300, 160)
			building_color = Color("4f5d75")
			has_helipad = false
			has_antenna = false
			has_hvac = false
			has_water_tower = false
		Archetype.PARK_PLAZA:
			height = 0.0
			size = Vector2(240, 240)
			building_color = Color("588157")
			has_helipad = false
			has_antenna = false
			has_hvac = false
			has_water_tower = false
		Archetype.CUSTOM:
			pass

func _process(_delta: float) -> void:
	# Força o redesenho constante para atualizar a perspectiva 3D quando a câmera se move
	queue_redraw()

func _draw() -> void:
	var canvas_trans = get_canvas_transform()
	# Corrige a posição da câmera em relação ao centro da tela
	var view_size = get_viewport_rect().size / canvas_trans.get_scale()
	var cam_pos = -canvas_trans.origin / canvas_trans.get_scale() + view_size / 2.0
	
	# Distância do prédio para a câmera (cria a ilusão 3D top-down)
	var dist_to_cam = global_position - cam_pos
	var roof_offset = dist_to_cam * (height / 1000.0) 
	
	var base_pos = -size / 2
	var r_pos = base_pos + roof_offset
	
	# Cantos da base (chão)
	var b = [base_pos, base_pos + Vector2(size.x, 0), base_pos + size, base_pos + Vector2(0, size.y)]
	# Cantos do teto
	var r = [r_pos, r_pos + Vector2(size.x, 0), r_pos + size, r_pos + Vector2(0, size.y)]
	
	var wall_color = building_color.darkened(0.3)
	var wall_color_side = building_color.darkened(0.5)
	
	if height > 0.0:
		# Desenha as paredes dependendo do ângulo de visão
		if roof_offset.y > 0:
			draw_polygon(PackedVector2Array([b[0], b[1], r[1], r[0]]), PackedColorArray([wall_color, wall_color, wall_color, wall_color]))
		elif roof_offset.y < 0:
			draw_polygon(PackedVector2Array([b[3], b[2], r[2], r[3]]), PackedColorArray([wall_color, wall_color, wall_color, wall_color]))
			
		if roof_offset.x > 0:
			draw_polygon(PackedVector2Array([b[0], b[3], r[3], r[0]]), PackedColorArray([wall_color_side, wall_color_side, wall_color_side, wall_color_side]))
		elif roof_offset.x < 0:
			draw_polygon(PackedVector2Array([b[1], b[2], r[2], r[1]]), PackedColorArray([wall_color_side, wall_color_side, wall_color_side, wall_color_side]))

	# Desenha o teto
	draw_rect(Rect2(r_pos, size), building_color)
	draw_rect(Rect2(r_pos + size * 0.03, size * 0.94), building_color.lightened(0.08))

	# Props no teto
	if has_hvac:
		draw_rect(Rect2(r_pos + size * 0.15, size * 0.18), wall_color_side)
		draw_rect(Rect2(r_pos + size * 0.65, size * 0.18), wall_color_side)

	if has_helipad:
		var center = r_pos + size * 0.5
		var radius = minf(size.x, size.y) * 0.22
		draw_circle(center, radius, Color("22272e"))
		draw_arc(center, radius * 0.85, 0, TAU, 32, Color("e5c07b"), 2.0)
		var hs = radius * 0.45
		draw_line(center + Vector2(-hs, -hs), center + Vector2(-hs, hs), Color.WHITE, 2.5)
		draw_line(center + Vector2(hs, -hs), center + Vector2(hs, hs), Color.WHITE, 2.5)
		draw_line(center + Vector2(-hs, 0), center + Vector2(hs, 0), Color.WHITE, 2.5)

	if has_water_tower:
		var wpos = r_pos + size * Vector2(0.8, 0.2)
		draw_circle(wpos, 14.0, Color("8b5a2b"))
		draw_arc(wpos, 14.0, 0, TAU, 24, Color("3b2f2f"), 2.0)

	if has_antenna:
		var apos = r_pos + size * Vector2(0.2, 0.2)
		draw_circle(apos, 3.0, Color("ff3333"))
