class_name MountainPineTree
extends StaticBody2D

## Pinheiro Alpino Procedural Low-Poly (Top-Down 2.5D):
## Substitui as antigas estrelas serrilhadas empilhadas por galhos assimétricos naturais,
## tronco e casca visíveis, canteiro de agulhas caídas, sombra direcional
## e massas discretas de neve volumétrica sobre as superfícies superiores dos ramos.
## 100% estático em runtime: sem SubViewports por árvore e sem _process contínuo.

@export var is_snowy: bool = false
@export_range(0.6, 2.0, 0.05) var tree_scale: float = 1.0
@export var variant_seed: int = 0
@export var enable_collision: bool = true

# Estruturas pré-calculadas de desenho (geradas uma única vez no _ready)
var _shadow_poly: PackedVector2Array = PackedVector2Array()
var _needle_bed: PackedVector2Array = PackedVector2Array()
var _trunk_poly: PackedVector2Array = PackedVector2Array()
var _trunk_roots: Array[PackedVector2Array] = []
var _bough_polys: Array[PackedVector2Array] = []
var _bough_colors: Array[Color] = []
var _snow_cushions: Array[PackedVector2Array] = []
var _apex_poly: PackedVector2Array = PackedVector2Array()
var _apex_snow: PackedVector2Array = PackedVector2Array()

func _ready() -> void:
	z_index = 6
	collision_layer = 1 if enable_collision else 0
	collision_mask = 0
	add_to_group("mountain_tree")
	add_to_group("nature_obstacle")

	_generate_geometry()

	if enable_collision:
		var col := CollisionShape2D.new()
		col.name = "TrunkCol"
		var circ := CircleShape2D.new()
		circ.radius = 10.0 * tree_scale
		col.shape = circ
		col.position = Vector2(0, 3) * tree_scale
		add_child(col)

	queue_redraw()

func _generate_geometry() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = variant_seed if variant_seed != 0 else int(position.x * 37 + position.y * 59)

	var s: float = tree_scale

	# -------------------------------------------------------------
	# 1. Canteiro Orgânico de Solo / Agulhas Caídas (Needle Bed)
	# -------------------------------------------------------------
	_needle_bed.clear()
	var bed_radius := 33.0 * s
	for i in 14:
		var a: float = TAU * float(i) / 14.0
		var r: float = bed_radius * rng.randf_range(0.80, 1.15)
		_needle_bed.append(Vector2(cos(a) * r, sin(a) * r * 0.85 + 3.0 * s))

	# -------------------------------------------------------------
	# 2. Sombra Suave Direcional Projetada a Sudeste
	# -------------------------------------------------------------
	_shadow_poly.clear()
	var shadow_offset := Vector2(13.0, 15.0) * s
	var shadow_rad := 29.0 * s
	for i in 12:
		var a: float = TAU * float(i) / 12.0
		var r: float = shadow_rad * rng.randf_range(0.82, 1.12)
		_shadow_poly.append(shadow_offset + Vector2(cos(a) * r, sin(a) * r * 0.80))

	# -------------------------------------------------------------
	# 3. Tronco e Raízes Visíveis (Visão 2.5D na Base Sul)
	# -------------------------------------------------------------
	_trunk_poly.clear()
	_trunk_roots.clear()
	var trunk_w: float = 6.5 * s
	var trunk_top_y: float = -4.0 * s
	var trunk_bot_y: float = 8.5 * s
	_trunk_poly = PackedVector2Array([
		Vector2(-trunk_w * 0.75, trunk_top_y),
		Vector2(trunk_w * 0.75, trunk_top_y),
		Vector2(trunk_w * 1.15, trunk_bot_y),
		Vector2(-trunk_w * 1.15, trunk_bot_y)
	])

	# Raízes se espalhando na base
	for r_side in [-1.0, 1.0]:
		var root_pts := PackedVector2Array([
			Vector2(r_side * trunk_w * 0.8, trunk_bot_y - 2.0 * s),
			Vector2(r_side * (trunk_w + 6.0 * s), trunk_bot_y + 3.5 * s),
			Vector2(r_side * (trunk_w + 4.0 * s), trunk_bot_y + 4.5 * s),
			Vector2(r_side * trunk_w * 0.3, trunk_bot_y + 1.0 * s)
		])
		_trunk_roots.append(root_pts)

	# -------------------------------------------------------------
	# 4. Galhos Assimétricos Low-Poly em Camadas Orgânicas
	# -------------------------------------------------------------
	_bough_polys.clear()
	_bough_colors.clear()
	_snow_cushions.clear()

	# Paleta de coníferas com variação natural por profundidade
	var base_green := Color("#1a3424") if is_snowy else Color("#142a1c")
	var mid_green := Color("#264c36") if is_snowy else Color("#22462e")
	var top_green := Color("#35684a") if is_snowy else Color("#326140")
	var highlight_green := Color("#4a825f") if is_snowy else Color("#457a53")

	# 4 Níveis de Galhos (do mais largo/baixo ao mais alto/compacto)
	var tier_specs = [
		{"tier": 0, "count": 6, "min_r": 28.0 * s, "max_r": 37.0 * s, "y_off": 3.0 * s,  "color": base_green},
		{"tier": 1, "count": 6, "min_r": 22.0 * s, "max_r": 29.0 * s, "y_off": 0.0,        "color": mid_green},
		{"tier": 2, "count": 5, "min_r": 15.0 * s, "max_r": 21.0 * s, "y_off": -4.0 * s, "color": top_green},
		{"tier": 3, "count": 4, "min_r": 8.0 * s,  "max_r": 13.0 * s, "y_off": -8.5 * s, "color": highlight_green}
	]

	for spec in tier_specs:
		var count: int = spec["count"]
		var min_r: float = spec["min_r"]
		var max_r: float = spec["max_r"]
		var y_off: float = spec["y_off"]
		var col: Color = spec["color"]
		var tier_idx: int = spec["tier"]

		var angle_offset: float = rng.randf() * TAU
		for b in range(count):
			var base_angle: float = angle_offset + (TAU * float(b) / float(count))
			# Jitter angular assimétrico
			var angle: float = base_angle + rng.randf_range(-0.18, 0.18)
			var reach: float = rng.randf_range(min_r, max_r)
			var spread: float = rng.randf_range(0.38, 0.52) # Abertura da ponta do galho

			# Ponto central e vetores perpendiculares
			var dir := Vector2(cos(angle), sin(angle) * 0.88)
			var perp := Vector2(-dir.y, dir.x).normalized()

			var p_base := Vector2(0, y_off) + dir * (reach * 0.18)
			var p_left := Vector2(0, y_off) + dir * (reach * 0.55) - perp * (reach * spread * 0.55)
			var p_tip_left := Vector2(0, y_off) + dir * (reach * 0.88) - perp * (reach * spread * 0.32)
			var p_tip := Vector2(0, y_off) + dir * reach
			var p_tip_right := Vector2(0, y_off) + dir * (reach * 0.88) + perp * (reach * spread * 0.32)
			var p_right := Vector2(0, y_off) + dir * (reach * 0.55) + perp * (reach * spread * 0.55)

			var bough_poly := PackedVector2Array([
				p_base, p_left, p_tip_left, p_tip, p_tip_right, p_right
			])
			_bough_polys.append(bough_poly)

			# Variação sutil de tom por galho
			var shade_var: float = rng.randf_range(-0.06, 0.06)
			_bough_colors.append(col.lightened(shade_var))

			# ---------------------------------------------------------
			# Neve em Massas Discretas (Apenas nos galhos expostos)
			# ---------------------------------------------------------
			if is_snowy:
				# A neve assenta no dorso superior dos galhos (principalmente voltados ao norte ou topos)
				# Não cobre tudo; forma almofadas convexas orgânicas
				var should_snow: bool = (tier_idx >= 1) or (dir.y < 0.2 and rng.randf() > 0.3)
				if should_snow:
					var snow_reach: float = reach * rng.randf_range(0.68, 0.88)
					var snow_base := p_base + dir * (reach * 0.15)
					var s_mid1 := p_left * 0.82
					var s_mid2 := p_right * 0.82
					var s_tip := Vector2(0, y_off) + dir * snow_reach
					var snow_cushion := PackedVector2Array([
						snow_base,
						snow_base + (s_mid1 - snow_base) * 0.85,
						s_tip - perp * (snow_reach * spread * 0.25),
						s_tip,
						s_tip + perp * (snow_reach * spread * 0.25),
						snow_base + (s_mid2 - snow_base) * 0.85
					])
					_snow_cushions.append(snow_cushion)

	# -------------------------------------------------------------
	# 5. Broto Apical / Cume do Pinheiro
	# -------------------------------------------------------------
	var apex_y: float = -12.0 * s
	var apex_w: float = 4.2 * s
	_apex_poly = PackedVector2Array([
		Vector2(-apex_w, apex_y + 5.0 * s),
		Vector2(0, apex_y - 2.5 * s),
		Vector2(apex_w, apex_y + 5.0 * s)
	])

	if is_snowy:
		_apex_snow = PackedVector2Array([
			Vector2(-apex_w * 0.75, apex_y + 4.0 * s),
			Vector2(0, apex_y - 2.2 * s),
			Vector2(apex_w * 0.75, apex_y + 4.0 * s)
		])

func _draw() -> void:
	var s: float = tree_scale

	# 1. Sombra projetada
	if _shadow_poly.size() > 2:
		draw_colored_polygon(_shadow_poly, Color(0.02, 0.04, 0.06, 0.38))

	# 2. Canteiro de solo / agulhas caídas
	if _needle_bed.size() > 2:
		if is_snowy:
			draw_colored_polygon(_needle_bed, Color("#d0dbe5"))
			draw_polyline(_needle_bed, Color("#b5c5d4"), 1.4 * s, true)
		else:
			draw_colored_polygon(_needle_bed, Color("#261c14"))
			draw_polyline(_needle_bed, Color("#1b130e"), 1.4 * s, true)

	# 3. Tronco e Raízes Visíveis
	for r in _trunk_roots:
		draw_colored_polygon(r, Color("#362316"))
	if _trunk_poly.size() > 2:
		draw_colored_polygon(_trunk_poly, Color("#422b1b"))
		draw_polyline(_trunk_poly, Color("#2b1b11"), 1.2 * s, true)
		# Ranhura vertical de casca
		draw_line(Vector2(-1.0 * s, -1.0 * s), Vector2(-0.5 * s, 7.5 * s), Color("#2b1b11"), 1.2 * s)

	# 4. Galhos Coníferos Assimétricos
	for i in range(_bough_polys.size()):
		var poly: PackedVector2Array = _bough_polys[i]
		var col: Color = _bough_colors[i]
		draw_colored_polygon(poly, col)
		draw_polyline(poly, col.darkened(0.28), 1.1 * s, true)

	# 5. Massas Discretas de Neve (Almofadas volumétricas sobrepostas)
	if is_snowy:
		var snow_base_col := Color("#d6e4f0")
		var snow_top_col := Color("#f7fbff")
		for cushion in _snow_cushions:
			if cushion.size() > 2:
				# Base sombreada da neve
				draw_colored_polygon(cushion, snow_base_col)
				# Borda/miolo iluminado de neve fresca
				draw_polyline(cushion, snow_top_col, 1.6 * s, true)

	# 6. Broto Apical
	if _apex_poly.size() > 2:
		draw_colored_polygon(_apex_poly, Color("#48825c"))
		if is_snowy and _apex_snow.size() > 2:
			draw_colored_polygon(_apex_snow, Color("#f7fbff"))
