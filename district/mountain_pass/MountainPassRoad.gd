class_name MountainPassRoad
extends Node2D
const BRIDGE_SURFACE = preload("res://district/roads/BridgeSurfaceStyle.gd")

## Renderizador de Estradas e Curvas da Montanha:
## Utiliza Curve2D com interpolacao suave (spline) para tracado continuo e organico,
## acostamento de cascalho e neve compactada, faixas duplas amarelas com trechos tracejados,
## trilhas de pneu no asfalto, guard-rails metalicos reais nos penhascos com refletores,
## e zona de Black Ice com fisica escorregadia.

signal vehicle_entered_ice(vehicle: Node2D)
signal vehicle_exited_ice(vehicle: Node2D)

@export var road_width: float = 140.0

var curve: Curve2D
var smooth_points: PackedVector2Array
var ice_trigger_area: Area2D
var guard_rails: StaticBody2D

var control_points: PackedVector2Array = [
	Vector2(3000, 400),     # Aproximacao oeste da ponte
	Vector2(3800, 400),     # Meio da ponte do Porto
	Vector2(4650, 400),     # Saida leste da ponte
	Vector2(4950, 400),     # Entrada do tunel da montanha
	Vector2(5800, 400),     # Saida do tunel no vale da serra
	Vector2(6250, 340),     # Entrada da madeireira
	Vector2(6650, 150),     # Margem do lago da montanha
	Vector2(6950, -250),    # Curva 1 (Hairpin inferior)
	Vector2(6650, -580),    # Rampa de subida
	Vector2(6150, -780),    # Curva 2 (Hairpin oeste)
	Vector2(6500, -1050),   # Subida em direcao ao mirante
	Vector2(7000, -1350),   # Mirante Panoramico (Overlook)
	Vector2(6600, -1700),   # Transicao para a neve
	Vector2(6250, -2050),   # Curva de gelo liso (Black Ice)
	Vector2(6850, -2450),   # Subida final do desfiladeiro
	Vector2(6500, -2660)    # Turning apron below the stronghold, clear of its facade.
]

func _ready() -> void:
	z_index = 2
	_build_curve()
	_build_guard_rails()
	_build_ice_hazard_area()
	queue_redraw()

func _build_curve() -> void:
	curve = Curve2D.new()
	curve.bake_interval = 8.0
	for i in range(control_points.size()):
		var pt := control_points[i]
		var in_vec := Vector2.ZERO
		var out_vec := Vector2.ZERO
		if i > 0 and i < control_points.size() - 1:
			var prev := control_points[i - 1]
			var next := control_points[i + 1]
			var dir := (next - prev).normalized()
			var dist := minf(prev.distance_to(pt), next.distance_to(pt)) * 0.38
			in_vec = -dir * dist
			out_vec = dir * dist
		curve.add_point(pt, in_vec, out_vec)
	
	smooth_points.clear()
	for distance in range(0, int(curve.get_baked_length()), 8):
		smooth_points.append(curve.sample_baked(float(distance), true))
	smooth_points.append(control_points[-1])

func _draw() -> void:
	if smooth_points.size() < 2:
		return
	
	# 1. Base Larga do Leito da Rodovia (Sub-base de Cascalho e Aterro)
	draw_polyline(smooth_points, Color("#2b251e"), road_width + 44.0, true)
	
	# Acostamento superior de neve compactada
	var upper_snow_pts := PackedVector2Array()
	for p in smooth_points:
		if p.y <= -1400.0:
			upper_snow_pts.append(p)
	if upper_snow_pts.size() > 1:
		draw_polyline(upper_snow_pts, BRIDGE_SURFACE.SHOULDER, road_width + 42.0, true)
		draw_polyline(upper_snow_pts, Color("#9cb2c6"), road_width + 24.0, true)

	# 2. Sarjeta / Borda de Concreto
	draw_polyline(smooth_points, BRIDGE_SURFACE.CURB, road_width + 8.0, true)

	# 3. Pista Principal de Asfalto (Continuo, sem quinas)
	draw_polyline(smooth_points, BRIDGE_SURFACE.ASPHALT, road_width, true)
	# A generous turning apron keeps through traffic out of the bunker doorway.
	draw_circle(control_points[-1], 137, Color("8797a3"))
	draw_circle(control_points[-1], 130, Color("1a1e23"))

	# 4. Trilhas de Pneu Desgastadas (Wheel Tracks nos dois sentidos)
	_draw_tire_tracks(smooth_points)

	# 5. Geada / Neve Acumulada nas Bordas (Zona Alta y <= -1400)
	if upper_snow_pts.size() > 1:
		_draw_snowy_road_edges(upper_snow_pts)

	# 6. Linhas Brancas Laterais (Fog Lines)
	_draw_road_edge_lines(smooth_points)

	# 7. Faixas Centrais
	_draw_centerlines(smooth_points)

	# 8. Guard-Rails Metalicos Visiveis com Postes e Refletores
	_draw_all_guard_rails()

func _draw_tire_tracks(pts: PackedVector2Array) -> void:
	var left_track := PackedVector2Array()
	var right_track := PackedVector2Array()
	var offset: float = road_width * 0.25
	
	for i in range(pts.size()):
		var p := pts[i]
		var tangent := _get_tangent(pts, i)
		var normal := Vector2(-tangent.y, tangent.x)
		left_track.append(p - normal * offset)
		right_track.append(p + normal * offset)
	
	draw_polyline(left_track, BRIDGE_SURFACE.WEAR, 18.0, true)
	draw_polyline(right_track, BRIDGE_SURFACE.WEAR, 18.0, true)

func _draw_snowy_road_edges(pts: PackedVector2Array) -> void:
	var left_snow := PackedVector2Array()
	var right_snow := PackedVector2Array()
	var half_w: float = road_width * 0.5 - 6.0
	
	for i in range(pts.size()):
		var p := pts[i]
		var tangent := _get_tangent(pts, i)
		var normal := Vector2(-tangent.y, tangent.x)
		left_snow.append(p + normal * half_w)
		right_snow.append(p - normal * half_w)
	
	draw_polyline(left_snow, Color(0.88, 0.93, 0.98, 0.45), 16.0, true)
	draw_polyline(right_snow, Color(0.88, 0.93, 0.98, 0.45), 16.0, true)

func _draw_road_edge_lines(pts: PackedVector2Array) -> void:
	var left_edge := PackedVector2Array()
	var right_edge := PackedVector2Array()
	var half_w: float = road_width * 0.5 - 8.0

	for i in range(pts.size()):
		var p := pts[i]
		var tangent := _get_tangent(pts, i)
		var normal := Vector2(-tangent.y, tangent.x)
		left_edge.append(p + normal * half_w)
		right_edge.append(p - normal * half_w)

	draw_polyline(left_edge, BRIDGE_SURFACE.EDGE, 3.0, true)
	draw_polyline(right_edge, BRIDGE_SURFACE.EDGE, 3.0, true)

func _draw_centerlines(pts: PackedVector2Array) -> void:
	var offset: float = 3.8
	var line1 := PackedVector2Array()
	var line2 := PackedVector2Array()

	for i in range(pts.size()):
		var p := pts[i]
		var tangent := _get_tangent(pts, i)
		var normal := Vector2(-tangent.y, tangent.x)
		line1.append(p + normal * offset)
		line2.append(p - normal * offset)

	# Na secao verde: faixas amarelas duplas
	# Na secao polar (y < -1600): transiciona suavemente para amarelo desbotado/branco
	var split_idx := 0
	for i in range(pts.size()):
		if pts[i].y <= -1600.0:
			split_idx = i
			break
	if split_idx == 0:
		split_idx = int(pts.size() * 0.72)

	var l1_low := line1.slice(0, split_idx + 1)
	var l2_low := line2.slice(0, split_idx + 1)
	draw_polyline(l1_low, Color("#f1c40f"), 2.8, true)
	draw_polyline(l2_low, Color("#f1c40f"), 2.8, true)

	var l1_up := line1.slice(split_idx, line1.size())
	var l2_up := line2.slice(split_idx, line2.size())
	draw_polyline(l1_up, Color(0.92, 0.95, 1.0, 0.75), 2.8, true)
	draw_polyline(l2_up, Color(0.92, 0.95, 1.0, 0.75), 2.8, true)

func _draw_all_guard_rails() -> void:
	for points in _guard_rail_sections():
		_draw_guard_rail_section(points)

func _guard_rail_sections() -> Array[PackedVector2Array]:
	var sections: Array[PackedVector2Array] = []
	# Localiza trechos de curvas fechadas (hairpins) e penhascos para desenhar guard-rail metalico
	var hairpin_ranges: Array[Dictionary] = [
		{"min_y": -480.0, "max_y": -50.0, "side": 1.0, "min_x": 6750.0},     # Hairpin 1 (Leste)
		{"min_y": -950.0, "max_y": -650.0, "side": -1.0, "max_x": 6350.0},    # Hairpin 2 (Oeste)
		{"min_y": -1520.0, "max_y": -1200.0, "side": 1.0, "min_x": 6800.0},   # Hairpin 3 (Mirante)
		{"min_y": -2200.0, "max_y": -1900.0, "side": -1.0, "max_x": 6450.0},  # Hairpin 4 (Black Ice)
		{"min_y": -2620.0, "max_y": -2320.0, "side": 1.0, "min_x": 6700.0}    # Hairpin 5 (Subida Cume)
	]

	for hp in hairpin_ranges:
		var rail_pts := PackedVector2Array()
		var side: float = hp["side"]
		var rail_offset: float = (road_width * 0.5 + 4.0) * side

		for i in range(smooth_points.size()):
			var p := smooth_points[i]
			if p.y >= hp["min_y"] and p.y <= hp["max_y"]:
				if hp.has("min_x") and p.x < hp["min_x"]:
					continue
				if hp.has("max_x") and p.x > hp["max_x"]:
					continue
				var tangent := _get_tangent(smooth_points, i)
				var normal := Vector2(-tangent.y, tangent.x)
				rail_pts.append(p + normal * rail_offset)

		if rail_pts.size() > 2:
			sections.append(rail_pts)
	return sections

func _draw_guard_rail_section(pts: PackedVector2Array) -> void:
	# Postes verticais de sustentacao de aco a cada ~35 unidades
	var dist_accum: float = 0.0
	for i in range(pts.size() - 1):
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var seg_len := p1.distance_to(p2)
		dist_accum += seg_len
		if dist_accum >= 32.0 or i == 0:
			dist_accum = 0.0
			draw_circle(p1 + Vector2(2, 2), 4.5, Color(0.04, 0.05, 0.06, 0.45))
			draw_circle(p1, 3.8, Color("#576574"))
			draw_circle(p1, 2.0, Color("#8395a7"))
			# Refletor na cabeca do poste
			var ref_col := Color("#ee5253") if (i % 2 == 0) else Color("#feca57")
			draw_circle(p1, 1.4, ref_col)

	# Lamina continua W-Beam (Sombra, Face e Destaque)
	draw_polyline(pts, Color(0.05, 0.06, 0.08, 0.4), 6.0, true)
	draw_polyline(pts, Color("#576574"), 4.8, true)
	draw_polyline(pts, Color("#c8d6e5"), 3.2, true)
	draw_polyline(pts, Color("#ffffff"), 1.2, true)

func _get_tangent(pts: PackedVector2Array, idx: int) -> Vector2:
	if pts.size() < 2:
		return Vector2.RIGHT
	if idx < pts.size() - 1:
		return (pts[idx + 1] - pts[idx]).normalized()
	elif idx > 0:
		return (pts[idx] - pts[idx - 1]).normalized()
	return Vector2.RIGHT

func _build_guard_rails() -> void:
	guard_rails = StaticBody2D.new()
	guard_rails.name = "CliffGuardRails"
	guard_rails.collision_layer = 1
	guard_rails.collision_mask = 0
	add_child(guard_rails)

	# The drawn W-beam and physical barrier use exactly the same curve.
	for points in _guard_rail_sections():
		for i in range(0, points.size()-1, 3):
			var col := CollisionShape2D.new()
			var segment := SegmentShape2D.new()
			segment.a = points[i]
			segment.b = points[mini(i+3,points.size()-1)]
			col.shape = segment
			guard_rails.add_child(col)

func _build_ice_hazard_area() -> void:
	ice_trigger_area = Area2D.new()
	ice_trigger_area.name = "BlackIceHazardArea"
	ice_trigger_area.collision_layer = 0
	ice_trigger_area.collision_mask = 1 | 2 | 4 | 8
	add_child(ice_trigger_area)

	var col := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(1100.0, 1400.0)
	col.shape = box
	col.position = Vector2(6500.0, -2100.0)
	ice_trigger_area.add_child(col)

	ice_trigger_area.body_entered.connect(_on_ice_entered)
	ice_trigger_area.body_exited.connect(_on_ice_exited)

func _on_ice_entered(body: Node2D) -> void:
	if body.has_method("set_ice_physics"):
		body.set_ice_physics(true)
	elif "wheel_friction" in body:
		body.wheel_friction = 0.35
	elif "friction" in body:
		body.friction = 0.25
	vehicle_entered_ice.emit(body)

func _on_ice_exited(body: Node2D) -> void:
	if body.has_method("set_ice_physics"):
		body.set_ice_physics(false)
	elif "wheel_friction" in body:
		body.wheel_friction = 1.0
	elif "friction" in body:
		body.friction = 1.0
	vehicle_exited_ice.emit(body)

func is_point_on_road(pos: Vector2, tolerance: float = 120.0) -> bool:
	if curve == null:
		return false
	var closest := curve.get_closest_point(pos)
	return pos.distance_to(closest) < tolerance
