class_name MountainPassRoad
extends Node2D
const BRIDGE_SURFACE = preload("res://geodata/roads/BridgeSurfaceStyle.gd")
const RUNTIME_WORK_SCHEDULER = preload("res://systems/RuntimeWorkScheduler.gd")

## Renderizador de Estradas e Curvas da Montanha:
## Utiliza Curve2D com interpolacao suave (spline) para tracado continuo e organico,
## acostamento de cascalho e neve compactada, faixas duplas amarelas com trechos tracejados,
## trilhas de pneu no asfalto, guard-rails metalicos reais nos penhascos com refletores,
## e zona de Black Ice com fisica escorregadia.

signal vehicle_entered_ice(vehicle: Node2D)
signal vehicle_exited_ice(vehicle: Node2D)
signal build_finished

@export var road_width: float = 140.0

var curve: Curve2D
var smooth_points: PackedVector2Array
var ice_trigger_area: Area2D
var guard_rails: StaticBody2D
var winter_pocket_access: Curve2D
var junctions := preload("res://world/mountain_pass/MountainRoadJunctions.gd").new()
var guard_rail_terminals: Array[PackedVector2Array] = []
var cliff_edges: Node2D
var pavement: Array[PackedVector2Array] = []
var summit_rims: Array[PackedVector2Array] = []
const RESORT_ISLAND_CENTER := Vector2(7140, -2545)
const RESORT_ISLAND_RADIUS := 34.0

# Contract for the global runtime scheduler integration. Costs are conservative
# RTX 4060 Forward Mobile observations; actual timings remain in build_stage_usec.
const STREAM_STAGE_CONTRACT := {
	&"curve_and_junctions": {"priority": RUNTIME_WORK_SCHEDULER.PRIORITY_NEAR_COLLISION, "expected_usec": 14500, "synchronous": true},
	&"pavement": {"priority": RUNTIME_WORK_SCHEDULER.PRIORITY_COLLISION, "expected_usec": 15500},
	&"guard_rail_physics": {"priority": RUNTIME_WORK_SCHEDULER.PRIORITY_COLLISION, "expected_usec": 5600},
	&"external_cliff_edges": {"priority": RUNTIME_WORK_SCHEDULER.PRIORITY_VISIBLE, "expected_usec": 145000, "external_indivisible": true},
	&"ice_hazard": {"priority": RUNTIME_WORK_SCHEDULER.PRIORITY_COLLISION, "expected_usec": 500},
	&"draw_shoulders": {"priority": RUNTIME_WORK_SCHEDULER.PRIORITY_VISIBLE, "expected_usec": 2200},
	&"draw_tire_tracks": {"priority": RUNTIME_WORK_SCHEDULER.PRIORITY_VISIBLE, "expected_usec": 2600},
	&"draw_snow_edges_left": {"priority": RUNTIME_WORK_SCHEDULER.PRIORITY_VISIBLE, "expected_usec": 9800},
	&"draw_snow_edges_right": {"priority": RUNTIME_WORK_SCHEDULER.PRIORITY_VISIBLE, "expected_usec": 9800},
	&"draw_edge_lines": {"priority": RUNTIME_WORK_SCHEDULER.PRIORITY_VISIBLE, "expected_usec": 2600},
	&"draw_centerlines": {"priority": RUNTIME_WORK_SCHEDULER.PRIORITY_VISIBLE, "expected_usec": 3200},
	&"draw_rail_visuals": {"priority": RUNTIME_WORK_SCHEDULER.PRIORITY_VISIBLE, "expected_usec": 500},
}

var resort_access_points: PackedVector2Array = [
	Vector2(6850, -2450),
	Vector2(7020, -2500),
	Vector2(7140, -2545)
]
var summit_connector_points: PackedVector2Array = [
	Vector2(6500, -2660),
	Vector2(6820, -2545),
	Vector2(7140, -2545)
]
var resort_curve: Curve2D
var resort_smooth_points: PackedVector2Array
var summit_connector_curve: Curve2D
var summit_connector_smooth_points: PackedVector2Array

var _cached_shoulder_patches_shoulder: Array[PackedVector2Array] = []
var _cached_shoulder_patches_inner: Array[PackedVector2Array] = []
var _cached_snow_edge_patches: Array[PackedVector2Array] = []
var _cached_tire_track_segments: Array[PackedVector2Array] = []
var _cached_edge_line_segments: Array[PackedVector2Array] = []
var _cached_bridge_centerline_dashes := PackedVector2Array()
var _cached_centerlines_low: Array[PackedVector2Array] = []
var _cached_centerlines_up: Array[PackedVector2Array] = []
var _cached_guard_rail_sections: Array[PackedVector2Array] = []
var _cached_full_guard_rail_sections: Array[PackedVector2Array] = []
var _guard_rail_cache_valid := false
var _cached_guard_rail_posts: Array[Dictionary] = []
var _cached_resort_markings: Array[PackedVector2Array] = []
var _cached_pavement_mesh: ArrayMesh = null
var _cached_pavement_rim: PackedVector2Array = PackedVector2Array()
var build_complete := false
var build_stage_usec: Dictionary = {}
var build_peak_usec := 0

static var _pavement_cache: Dictionary = {}

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
	set_meta("stream_stage_contract", STREAM_STAGE_CONTRACT.duplicate(true))
	preload("res://world/mountain_pass/MountainGroundMaterials.gd").grain(self)
	var started := Time.get_ticks_usec()
	_build_curve()
	junctions.road_curve = curve
	junctions.half_road = road_width*0.5
	junctions.add_access(winter_pocket_access,31.0,false,"winter_pocket")
	if resort_curve:
		junctions.add_access(resort_curve, 70.0, false, "resort_access")
	if summit_connector_curve: junctions.add_access(summit_connector_curve,64.0,false,"summit_connector")
	_record_build_stage(&"curve_and_junctions", started)
	if _is_streamed_build():
		_finish_streamed_build.call_deferred()
		return
	_finish_synchronous_build()

func _finish_synchronous_build() -> void:
	var started := Time.get_ticks_usec()
	_build_pavement()
	_record_build_stage(&"pavement", started)
	started = Time.get_ticks_usec()
	_build_guard_rail_physics()
	_record_build_stage(&"guard_rail_physics", started)
	started = Time.get_ticks_usec()
	_build_cliff_edges()
	_record_build_stage(&"external_cliff_edges", started)
	started = Time.get_ticks_usec()
	_build_ice_hazard_area()
	_record_build_stage(&"ice_hazard", started)
	started = Time.get_ticks_usec()
	_precompute_road_draw_geometry()
	_record_build_stage(&"draw_geometry", started)
	queue_redraw()
	_complete_build()

func _finish_streamed_build() -> void:
	# The main curve and junctions are available synchronously to scenery and
	# navigation. Expensive immutable presentation/physics is spread over the
	# following globally reserved frames while the player approaches from Harbor.
	if not await _run_scheduled_stream_stage(&"pavement", _build_pavement): return
	if not await _run_scheduled_stream_stage(&"guard_rail_physics", _build_guard_rail_physics): return
	if not await _run_scheduled_stream_stage(&"external_cliff_edges", _build_cliff_edges): return
	if not await _run_scheduled_stream_stage(&"ice_hazard", _build_ice_hazard_area): return
	for stage: StringName in [&"shoulders", &"tire_tracks", &"snow_edges_left", &"snow_edges_right", &"edge_lines", &"centerlines", &"rail_visuals"]:
		var label := StringName("draw_%s" % stage)
		if not await _run_scheduled_stream_stage(label, _precompute_draw_stage.bind(stage)): return
	queue_redraw()
	_complete_build()

func _run_scheduled_stream_stage(label: StringName, task: Callable) -> bool:
	var specification: Dictionary = STREAM_STAGE_CONTRACT.get(label, {})
	if specification.is_empty():
		push_error("MountainPassRoad has no scheduler contract for stage %s" % label)
		return false
	var producer := StringName("mountain_road/%s" % label)
	var ticket: Dictionary = await RUNTIME_WORK_SCHEDULER.reserve(
		self,
		producer,
		int(specification.get("priority", RUNTIME_WORK_SCHEDULER.PRIORITY_VISIBLE)),
		int(specification.get("expected_usec", RUNTIME_WORK_SCHEDULER.FRAME_BUDGET_USEC))
	)
	if ticket.is_empty() or not is_inside_tree():
		return false
	var started := Time.get_ticks_usec()
	task.call()
	var elapsed := Time.get_ticks_usec() - started
	RUNTIME_WORK_SCHEDULER.complete(ticket, elapsed)
	_record_build_stage(label, started)
	return true

func _is_streamed_build() -> bool:
	var parent := get_parent()
	return parent != null and parent.get("streamed_region") == true

func _record_build_stage(label: StringName, started_usec: int) -> void:
	var elapsed := Time.get_ticks_usec() - started_usec
	build_stage_usec[label] = elapsed
	build_peak_usec = maxi(build_peak_usec, elapsed)
	set_meta("build_stage_usec", build_stage_usec.duplicate())
	set_meta("build_peak_usec", build_peak_usec)

func _complete_build() -> void:
	build_complete = true
	set_meta("build_complete", true)
	build_finished.emit()

## Curve2D.sample_baked() a cada 8px, seguido de um append incondicional do
## ponto final, deixa o último par de pontos quase idênticos sempre que
## get_baked_length() não é múltiplo de 8 -- o segmento final some, vira
## comprimento ~0, e o desenho da pista (draw_polyline/draw_colored_polygon
## direto no CanvasItem nativo, sem passar pelo StaticCanvasGeometry
## compartilhado) tenta triangular esse ponto degenerado e o Godot loga
## "Invalid polygon data, triangulation failed." toda vez que a cena
## redesenha (cada zoom/pan no editor). Mesma causa raiz do conserto em
## StaticCanvasGeometry.gd, aplicada aqui na fonte (a amostragem), já que
## esta pista desenha direto sem passar por aquele utilitário.
const MIN_SAMPLED_SEGMENT := 0.05

func _append_sampled_point(points: PackedVector2Array, point: Vector2) -> void:
	if points.is_empty() or points[-1].distance_to(point) >= MIN_SAMPLED_SEGMENT:
		points.append(point)

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
		_append_sampled_point(smooth_points, curve.sample_baked(float(distance), true))
	_append_sampled_point(smooth_points, control_points[-1])
	winter_pocket_access = preload("res://world/mountain_pass/MountainVillageLayout.gd").winter_stop_access_curve(curve,1)

	# Acesso Asfaltado do Resort Cume Branco
	resort_curve = Curve2D.new()
	resort_curve.bake_interval = 8.0
	resort_curve.add_point(resort_access_points[0], Vector2.ZERO, Vector2(60, -50))
	resort_curve.add_point(resort_access_points[1], Vector2(-50, 45), Vector2(60, -45))
	resort_curve.add_point(resort_access_points[2], Vector2(-50, 0), Vector2.ZERO)
	resort_smooth_points.clear()
	for distance in range(0, int(resort_curve.get_baked_length()), 8):
		_append_sampled_point(resort_smooth_points, resort_curve.sample_baked(float(distance), true))
	_append_sampled_point(resort_smooth_points, resort_access_points[-1])

	# Conector Pavimentado do Platô (Bunker <-> Resort)
	summit_connector_curve = Curve2D.new()
	summit_connector_curve.bake_interval = 8.0
	summit_connector_curve.add_point(summit_connector_points[0], Vector2.ZERO, Vector2(100, 0))
	summit_connector_curve.add_point(summit_connector_points[1], Vector2(-80, 0), Vector2(80, 0))
	summit_connector_curve.add_point(summit_connector_points[2], Vector2(-80, 0), Vector2.ZERO)
	summit_connector_smooth_points.clear()
	for distance in range(0, int(summit_connector_curve.get_baked_length()), 8):
		_append_sampled_point(summit_connector_smooth_points, summit_connector_curve.sample_baked(float(distance), true))
	_append_sampled_point(summit_connector_smooth_points, summit_connector_points[-1])

func _draw() -> void:
	if smooth_points.size() < 2:
		return
	
	# Gravel belongs on land. Across the harbor bridge it formed a dark strip
	# behind the paved deck and a square cap at the west seam.
	var land_start := 0
	while land_start < smooth_points.size() - 1 and smooth_points[land_start].x < 4650.0:
		land_start += 1
	draw_polyline(smooth_points.slice(land_start), Color("#2b251e"), road_width + 44.0, true)
	
	# Acostamento superior de neve compactada
	for patch in _cached_shoulder_patches_shoulder:
		draw_colored_polygon(patch, BRIDGE_SURFACE.SHOULDER)
	for patch in _cached_shoulder_patches_inner:
		draw_colored_polygon(patch, Color("#9cb2c6"))

	# The summit shoulder follows the same outside contour as the asphalt.
	for edge in summit_rims:
		draw_polyline(edge, Color("d6e5e9"), 50.0, true)
		draw_polyline(edge, Color("b8c9d2"), 30.0, true)
		draw_polyline(edge, Color("91a5b2"), 15.0, true)
	if _cached_pavement_mesh != null:
		draw_mesh(_cached_pavement_mesh, null)
	# The outside curb must remain visible above the asphalt. Junction mouths
	# are drawn afterwards so the curb never closes an access road.
	if not _cached_pavement_rim.is_empty():
		_draw_pavement_rim_without_bridge_cap()
	junctions.draw_surfaces(self, ["resort_access", "summit_connector"])

	# 4. Trilhas de Pneu Desgastadas (Wheel Tracks nos dois sentidos)
	for segment in _cached_tire_track_segments:
		draw_polyline(segment, BRIDGE_SURFACE.WEAR, 18.0, true)

	# 5. Geada / Neve Acumulada nas Bordas (Zona Alta y <= -1400)
	for patch in _cached_snow_edge_patches:
		draw_colored_polygon(patch, Color(0.88, 0.93, 0.98, 0.45))

	# 6. Linhas Brancas Laterais (Fog Lines)
	for segment in _cached_edge_line_segments:
		draw_polyline(segment, BRIDGE_SURFACE.EDGE, 3.0, true)

	# 7. Faixas Centrais
	if not _cached_bridge_centerline_dashes.is_empty():
		draw_multiline(_cached_bridge_centerline_dashes, BRIDGE_SURFACE.LANE, BRIDGE_SURFACE.MARKING_WIDTH, true)
	for segment in _cached_centerlines_low:
		draw_polyline(segment, BRIDGE_SURFACE.LANE, BRIDGE_SURFACE.MARKING_WIDTH, true)
	for segment in _cached_centerlines_up:
		draw_polyline(segment, Color(0.92, 0.95, 1.0, 0.75), 2.8, true)

	# 8. Guard-Rails Metalicos Visiveis com Postes e Refletores
	for points in _cached_guard_rail_sections:
		_draw_guard_rail_section(points)
	for terminal in guard_rail_terminals:
		var end := terminal[-1]
		var tangent := terminal[-2].direction_to(end)
		var across := tangent.orthogonal()
		draw_circle(end+Vector2(2,3),5.0,Color(0.03,0.04,0.05,.4))
		draw_line(end+Vector2(0,5),end,Color("596a78"),5.0,true)
		draw_line(end-across*4.0,end+across*4.0,Color("d2dfe7"),6.0,true)
		draw_line(end-across*2.5,end+across*2.5,Color("f4bb50"),3.3,true)
		draw_circle(end+Vector2(-1,-1),.9,Color("fff4c9"))

	# Resort network
	for marking in _cached_resort_markings:
		draw_polyline(marking, BRIDGE_SURFACE.EDGE, 2.8, true)
	var center := RESORT_ISLAND_CENTER
	draw_circle(center, RESORT_ISLAND_RADIUS, Color("8c9aa6"))
	draw_circle(center, 30.0, Color("d6e0e6"))

func _draw_pavement_rim_without_bridge_cap() -> void:
	# The closed pavement outline includes a crosswise curb at its west end.
	# That cap sat directly across the live harbor-to-mountain traffic seam.
	for i in range(_cached_pavement_rim.size() - 1):
		var a := _cached_pavement_rim[i]
		var b := _cached_pavement_rim[i + 1]
		if absf(a.x - 3000.0) > 12.0 or absf(b.x - 3000.0) > 12.0:
			continue
		if absf(a.y - b.y) < 80.0:
			continue
		if i > 0:
			draw_polyline(_cached_pavement_rim.slice(0, i + 1), BRIDGE_SURFACE.CURB, 8.0, true)
		if i + 2 < _cached_pavement_rim.size():
			draw_polyline(_cached_pavement_rim.slice(i + 1), BRIDGE_SURFACE.CURB, 8.0, true)
		return
	draw_polyline(_cached_pavement_rim, BRIDGE_SURFACE.CURB, 8.0, true)

func _circle_polygon(center: Vector2, radius: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in 96: result.append(center + Vector2.from_angle(TAU * i / 96.0) * radius)
	return result

func _simplify_open_polyline(points: PackedVector2Array, epsilon: float) -> PackedVector2Array:
	if points.size() <= 2:
		return points.duplicate()
	var keep := PackedByteArray()
	keep.resize(points.size())
	keep[0] = 1
	keep[points.size() - 1] = 1
	var ranges: Array[Vector2i] = [Vector2i(0, points.size() - 1)]
	while not ranges.is_empty():
		var span: Vector2i = ranges.pop_back()
		var furthest := -1
		var maximum := epsilon
		for index in range(span.x + 1, span.y):
			var closest := Geometry2D.get_closest_point_to_segment(points[index], points[span.x], points[span.y])
			var distance := points[index].distance_to(closest)
			if distance > maximum:
				maximum = distance
				furthest = index
		if furthest >= 0:
			keep[furthest] = 1
			ranges.append(Vector2i(span.x, furthest))
			ranges.append(Vector2i(furthest, span.y))
	var result := PackedVector2Array()
	for index in points.size():
		if keep[index] != 0:
			result.append(points[index])
	return result

func _simplify_closed_polygon(points: PackedVector2Array, epsilon: float) -> PackedVector2Array:
	if points.size() <= 4:
		return points.duplicate()
	# Splitting at the farthest vertex turns the ring into two stable open
	# chains. Douglas-Peucker then removes only sub-pixel collinear detail;
	# junction corners and the connected outside contour remain explicit.
	var split := 1
	var greatest := 0.0
	for index in range(1, points.size()):
		var distance := points[0].distance_squared_to(points[index])
		if distance > greatest:
			greatest = distance
			split = index
	var first := _simplify_open_polyline(points.slice(0, split + 1), epsilon)
	var second_source := points.slice(split, points.size())
	second_source.append(points[0])
	var second := _simplify_open_polyline(second_source, epsilon)
	first.resize(first.size() - 1)
	second.resize(second.size() - 1)
	first.append_array(second)
	return first

func _pavement_cache_key() -> String:
	return "%.3f:%d" % [road_width, hash(control_points)]

func _duplicate_polygon_array(source: Array) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for polygon in source:
		result.append((polygon as PackedVector2Array).duplicate())
	return result

func _install_resort_island() -> void:
	if has_node("ResortIsland"):
		return
	var island := StaticBody2D.new()
	island.name = "ResortIsland"
	island.collision_layer = 1
	island.collision_mask = 0
	island.position = RESORT_ISLAND_CENTER
	var solid := CollisionShape2D.new()
	solid.shape = CircleShape2D.new()
	solid.shape.radius = RESORT_ISLAND_RADIUS
	island.add_child(solid)
	add_child(island)

func _build_pavement() -> void:
	# Boolean geometry is built once, never in the render/frame loop.
	# END_BUTT (não END_ROUND): a ponta oeste (control_points[0], x=3000) é a
	# emenda com o tabuleiro da ponte de HarborMountainConnector.gd, não uma
	# extremidade de verdade -- uma tampa arredondada ali sobrava como um
	# semicírculo cravado sobre a água, com cor errada (reportado pelo
	# usuário). A ponta leste continua arredondada de verdade: ganha seu
	# próprio círculo explícito (_circle_polygon(control_points[-1], 80.0)
	# logo abaixo), fundido por cima, então trocar o cap da polilinha base
	# não muda a aparência dela.
	var cache_key := _pavement_cache_key()
	var cached: Dictionary = _pavement_cache.get(cache_key, {})
	if not cached.is_empty():
		pavement = _duplicate_polygon_array(cached.pavement)
		_cached_pavement_rim = (cached.rim as PackedVector2Array).duplicate()
		summit_rims = _duplicate_polygon_array(cached.summit_rims)
		_cached_pavement_mesh = cached.mesh as ArrayMesh
		_install_resort_island()
		set_meta("pavement_cache_hit", true)
		return
	set_meta("pavement_cache_hit", false)
	var pavement_stage_usec := {}
	var started := Time.get_ticks_usec()
	var parts: Array[PackedVector2Array] = []
	parts.append_array(Geometry2D.offset_polyline(smooth_points, road_width * 0.5, Geometry2D.JOIN_ROUND, Geometry2D.END_BUTT))
	for route in [resort_smooth_points, summit_connector_smooth_points]:
		var strips := Geometry2D.offset_polyline(route, 70.0 if route == resort_smooth_points else 64.0, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND)
		parts.append_array(strips)
	parts.append(_circle_polygon(control_points[-1], 80.0))
	parts.append(_circle_polygon(Vector2(7140, -2545), 108.0))
	parts.append(PackedVector2Array([Vector2(6918,-2662),Vector2(7062,-2662),Vector2(7062,-2485),Vector2(6918,-2485)]))
	var outline := parts.pop_front() as PackedVector2Array
	for part in parts:
		var merged := Geometry2D.merge_polygons(outline, part)
		for polygon in merged:
			if not Geometry2D.is_polygon_clockwise(polygon): outline = polygon
	pavement_stage_usec[&"merge"] = Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	# One small close operation softens boolean cusps. The former 36 px close
	# inflated this contour from 2.691 to 9.907 vertices before triangulation.
	var inset := Geometry2D.offset_polygon(outline, -14.0, Geometry2D.JOIN_ROUND)
	if inset.size() == 1:
		var rounded := Geometry2D.offset_polygon(inset[0], 14.0, Geometry2D.JOIN_ROUND)
		if rounded.size() == 1: outline = rounded[0]
	outline = _simplify_closed_polygon(outline, 0.75)
	pavement_stage_usec[&"round_and_simplify"] = Time.get_ticks_usec() - started
	pavement = [outline]
	_cached_pavement_rim = outline.duplicate()
	_cached_pavement_rim.append(outline[0])
	summit_rims = Geometry2D.intersect_polyline_with_polygon(_cached_pavement_rim, PackedVector2Array([
		Vector2(6000,-3200), Vector2(7500,-3200), Vector2(7500,-2250), Vector2(6000,-2250)
	]))
	started = Time.get_ticks_usec()
	var triangles := Geometry2D.triangulate_polygon(outline)
	pavement_stage_usec[&"triangulate"] = Time.get_ticks_usec() - started
	if not triangles.is_empty():
		started = Time.get_ticks_usec()
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		var vertices := PackedVector3Array()
		vertices.resize(outline.size())
		for i in outline.size():
			vertices[i] = Vector3(outline[i].x, outline[i].y, 0.0)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_INDEX] = triangles
		var colors := PackedColorArray()
		colors.resize(outline.size())
		var poly_color := Color("d6e0e6") if Geometry2D.is_polygon_clockwise(outline) else BRIDGE_SURFACE.ASPHALT
		colors.fill(poly_color)
		arrays[Mesh.ARRAY_COLOR] = colors
		_cached_pavement_mesh = ArrayMesh.new()
		_cached_pavement_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		pavement_stage_usec[&"mesh"] = Time.get_ticks_usec() - started
	_install_resort_island()
	_pavement_cache[cache_key] = {
		"pavement": _duplicate_polygon_array(pavement),
		"rim": _cached_pavement_rim.duplicate(),
		"summit_rims": _duplicate_polygon_array(summit_rims),
		"mesh": _cached_pavement_mesh,
	}
	set_meta("pavement_stage_usec", pavement_stage_usec)

func _in_resort_surface(point: Vector2, margin := 0.0) -> bool:
	for route in [resort_curve, summit_connector_curve]:
		if point.distance_to(route.get_closest_point(point)) < 76.0 + margin: return true
	return point.distance_to(control_points[-1]) < 86.0 + margin

func _snow_weight(y: float) -> float:
	return smoothstep(0.0,1.0,clampf((-y-1260.0)/240.0,0.0,1.0))

func _generate_tapered_snow_shoulder_patches(extra_width: float) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for i in range(smooth_points.size() - 1):
		var a := smooth_points[i]
		var b := smooth_points[i+1]
		if a.y < -2250.0 and b.y < -2250.0: continue
		var wa := _snow_weight(a.y)
		var wb := _snow_weight(b.y)
		if wa + wb < 0.002: continue
		var na := _get_tangent(smooth_points, i).orthogonal()
		var nb := _get_tangent(smooth_points, i+1).orthogonal()
		var ha := (road_width + 8.0 + extra_width * wa) * 0.5
		var hb := (road_width + 8.0 + extra_width * wb) * 0.5
		var patch := Geometry2D.convex_hull(PackedVector2Array([a - na * ha, b - nb * hb, b + nb * hb, a + na * ha]))
		if patch.size() > 3:
			patch.remove_at(patch.size() - 1)
			result.append(patch)
	return result

func _precompute_road_draw_geometry() -> void:
	if smooth_points.size() < 2:
		return
	for stage: StringName in [&"shoulders", &"tire_tracks", &"snow_edges_left", &"snow_edges_right", &"edge_lines", &"centerlines", &"rail_visuals"]:
		_precompute_draw_stage(stage)

func _precompute_draw_stage(stage: StringName) -> void:
	match stage:
		&"shoulders": _precompute_shoulders()
		&"tire_tracks": _precompute_tire_tracks()
		&"snow_edges_left": _precompute_snow_edge_side(0)
		&"snow_edges_right": _precompute_snow_edge_side(1)
		&"edge_lines": _precompute_edge_lines()
		&"centerlines": _precompute_centerlines()
		&"rail_visuals": _precompute_rail_visuals()

func _precompute_shoulders() -> void:
	_cached_shoulder_patches_shoulder = _generate_tapered_snow_shoulder_patches(34.0)
	_cached_shoulder_patches_inner = _generate_tapered_snow_shoulder_patches(16.0)

func _precompute_tire_tracks() -> void:
	_cached_tire_track_segments.clear()
	var left_track := PackedVector2Array()
	var right_track := PackedVector2Array()
	var track_offset: float = road_width * 0.25
	for i in range(smooth_points.size()):
		var p := smooth_points[i]
		var tangent := _get_tangent(smooth_points, i)
		var normal := Vector2(-tangent.y, tangent.x)
		left_track.append(p - normal * track_offset)
		right_track.append(p + normal * track_offset)
	for track in [left_track, right_track]:
		for segment in _marking_segments(track):
			if segment.size() > 1:
				_cached_tire_track_segments.append(segment)

func _precompute_snow_edges() -> void:
	_precompute_snow_edge_side(0)
	_precompute_snow_edge_side(1)

func _precompute_snow_edge_side(side_index: int) -> void:
	if side_index == 0:
		_cached_snow_edge_patches.clear()
	var edge := PackedVector2Array()
	var half_w: float = road_width * 0.5 - 6.0
	for i in range(smooth_points.size()):
		var p := smooth_points[i]
		var tangent := _get_tangent(smooth_points, i)
		var normal := Vector2(-tangent.y, tangent.x)
		edge.append(p + normal * half_w * (1.0 if side_index == 0 else -1.0))
	for i in range(edge.size() - 1):
		if junctions.contains(edge[i]) or junctions.contains(edge[i+1]) or _in_resort_surface(edge[i], 10.0) or _in_resort_surface(edge[i+1], 10.0):
			continue
		var half_a := 8.0 * _snow_weight(smooth_points[i].y)
		var half_b := 8.0 * _snow_weight(smooth_points[i+1].y)
		if half_a + half_b < 0.02:
			continue
		var normal_a := _get_tangent(smooth_points, i).orthogonal()
		var normal_b := _get_tangent(smooth_points, i+1).orthogonal()
		var patch := Geometry2D.convex_hull(PackedVector2Array([
			edge[i] - normal_a * half_a,
			edge[i+1] - normal_b * half_b,
			edge[i+1] + normal_b * half_b,
			edge[i] + normal_a * half_a
		]))
		if patch.size() > 3:
			patch.remove_at(patch.size() - 1)
			if not Geometry2D.triangulate_polygon(patch).is_empty():
				_cached_snow_edge_patches.append(patch)

func _precompute_edge_lines() -> void:
	_cached_edge_line_segments.clear()
	var left_edge := PackedVector2Array()
	var right_edge := PackedVector2Array()
	var half_edge_w: float = road_width * 0.5 - 8.0
	for i in range(smooth_points.size()):
		var p := smooth_points[i]
		var tangent := _get_tangent(smooth_points, i)
		var normal := Vector2(-tangent.y, tangent.x)
		left_edge.append(p + normal * half_edge_w)
		right_edge.append(p - normal * half_edge_w)
	for edge in [left_edge, right_edge]:
		for segment in _marking_segments(edge):
			if segment.size() > 1:
				_cached_edge_line_segments.append(segment)

func _precompute_centerlines() -> void:
	_cached_bridge_centerline_dashes.clear()
	_cached_centerlines_low.clear()
	_cached_centerlines_up.clear()
	var bridge_end_idx := 0
	var bridge_end_distance := INF
	for i in smooth_points.size():
		var distance := smooth_points[i].distance_squared_to(Vector2(4650, 400))
		if distance < bridge_end_distance:
			bridge_end_distance = distance
			bridge_end_idx = i
	var bridge_centerline := smooth_points.slice(0, bridge_end_idx + 1)
	var bridge_world_start_x := 7300.0
	var bridge_phase := fposmod(bridge_world_start_x, BRIDGE_SURFACE.DASH_LENGTH + BRIDGE_SURFACE.DASH_GAP)
	_cached_bridge_centerline_dashes = BRIDGE_SURFACE.dashed_multiline(bridge_centerline, bridge_phase)
	var center_offset: float = 3.8
	var line1 := PackedVector2Array()
	var line2 := PackedVector2Array()
	for i in range(smooth_points.size()):
		var p := smooth_points[i]
		var tangent := _get_tangent(smooth_points, i)
		var normal := Vector2(-tangent.y, tangent.x)
		line1.append(p + normal * center_offset)
		line2.append(p - normal * center_offset)
	var split_idx := smooth_points.size() - 1
	for i in range(smooth_points.size()):
		if smooth_points[i].y <= -1600.0:
			split_idx = i
			break
	var low_start_idx := mini(bridge_end_idx, split_idx)
	var l1_low := line1.slice(low_start_idx, split_idx + 1)
	var l2_low := line2.slice(low_start_idx, split_idx + 1)
	for segment in _marking_segments(l1_low):
		if segment.size() > 1: _cached_centerlines_low.append(segment)
	for segment in _marking_segments(l2_low):
		if segment.size() > 1: _cached_centerlines_low.append(segment)
	var l1_up := line1.slice(split_idx, line1.size())
	var l2_up := line2.slice(split_idx, line2.size())
	for segment in _marking_segments(l1_up):
		if segment.size() > 1: _cached_centerlines_up.append(segment)
	for segment in _marking_segments(l2_up):
		if segment.size() > 1: _cached_centerlines_up.append(segment)

func _precompute_rail_visuals() -> void:
	_ensure_guard_rail_sections()
	_cached_resort_markings.clear()
	for side in [-1.0, 1.0]:
		var marking := PackedVector2Array()
		for i in summit_connector_smooth_points.size():
			var point := summit_connector_smooth_points[i]
			if point.x > 6660.0 and point.x < 6810.0:
				marking.append(point + _get_tangent(summit_connector_smooth_points, i).orthogonal() * 3.8 * side)
		if marking.size() > 1:
			_cached_resort_markings.append(marking)

func _is_winter_stop_opening(point: Vector2) -> bool:
	return junctions.contains(point,true)

func register_coach_access(access: Curve2D) -> void:
	junctions.add_access(access,44.0,false,"coach_entry")
	junctions.add_access(access,44.0,true,"coach_exit")
	_guard_rail_cache_valid = false
	_cached_guard_rail_sections.clear()
	_cached_full_guard_rail_sections.clear()
	_build_guard_rails()
	_precompute_road_draw_geometry()
	queue_redraw()

func _guard_rail_sections(full_edge := false) -> Array[PackedVector2Array]:
	_ensure_guard_rail_sections()
	return _cached_full_guard_rail_sections if full_edge else _cached_guard_rail_sections

func _ensure_guard_rail_sections() -> void:
	if _guard_rail_cache_valid:
		return
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
				var rail_point := p + normal * rail_offset
				if preload("res://world/mountain_pass/transit/MountainTransitVillageLayout.gd").is_reserved(rail_point) or _is_winter_stop_opening(rail_point) or _in_resort_surface(rail_point, 12.0):
					if rail_pts.size() > 2: sections.append(rail_pts)
					rail_pts = PackedVector2Array()
					continue
				rail_pts.append(rail_point)

		if rail_pts.size() > 2:
			sections.append(rail_pts)
	_cached_full_guard_rail_sections = _duplicate_polygon_array(sections)
	# Protect the apex, leave the approaches open to the visible drop.
	for i in sections.size():
		var points := sections[i]
		var near_access := false
		for point in points:
			if junctions.contains(point + Vector2(32,0),true) or junctions.contains(point - Vector2(32,0),true):
				near_access = true
		if not near_access and points.size() > 18:
			sections[i] = points.slice(int(points.size()*0.28),int(points.size()*0.72))
	guard_rail_terminals = _coach_entry_terminal(sections)
	sections.append_array(guard_rail_terminals)
	_cached_guard_rail_sections = sections
	_guard_rail_cache_valid = true

func _coach_entry_terminal(sections: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var mouth: Dictionary = {}
	for candidate in junctions.mouths:
		if candidate.label=="coach_entry": mouth=candidate
	if mouth.is_empty(): return result
	# Choose the already-built W-beam nearest the east rim of this entrance.
	# The extension follows its real highway shoulder before curling outward.
	var anchor := Vector2.ZERO
	var target := Vector2.ZERO
	var best := INF
	for rim in mouth.rims:
		if rim.size()<2: continue
		for section in sections:
			for endpoint in [section[0],section[-1]]:
				var distance: float = endpoint.distance_to(rim[0])
				if distance<best:
					best=distance
					anchor=endpoint
					target=rim[0]
	if best>140.0: return result
	var offset := curve.get_closest_offset(anchor)
	var target_offset := curve.get_closest_offset(target)
	var direction := signf(target_offset-offset)
	var pose := curve.sample_baked_with_rotation(offset,true)
	var normal := Vector2(-pose.x.y,pose.x.x)
	var side := signf((anchor-pose.origin).dot(normal))
	var extension := PackedVector2Array([anchor])
	for distance in range(2,142,2):
		pose=curve.sample_baked_with_rotation(offset+direction*float(distance),true)
		normal=Vector2(-pose.x.y,pose.x.x)
		# The coach's rear corner swings beyond the lane at the first steering
		# step, so this short lead-in flares onto the outer shoulder as well.
		var rail_distance := road_width*.5+4.0+12.0*smoothstep(0.0,20.0,float(distance))
		var point := pose.origin+normal*rail_distance*side
		if not _terminal_clear(point): break
		extension.append(point)
		if absf(offset+direction*float(distance)-target_offset)<3.0: break
	if extension.size()<12: return result
	# A flared quarter-circle turns the blunt end away from traffic. Search a
	# few upstream positions so every centimetre, including its terminal post,
	# stays outside the mouth's published clearance polygon.
	for retreat in range(8,mini(extension.size()-2,34)):
		var index := extension.size()-1-retreat
		var start := extension[index]
		var forward := extension[index-1].direction_to(start)
		var outside := (start-curve.get_closest_point(start)).normalized()
		var radius := 16.0
		var center := start+outside*radius
		var arc := PackedVector2Array()
		var clear := true
		for step in range(1,17):
			var angle := float(step)*PI/32.0
			var point := center-outside*cos(angle)*radius+forward*sin(angle)*radius
			if not _terminal_clear(point):
				clear=false
				break
			arc.append(point)
		if clear:
			var terminal := extension.slice(0,index+1)
			terminal.append_array(arc)
			result.append(terminal)
			break
	return result

func _terminal_clear(point: Vector2) -> bool:
	if point.distance_to(curve.get_closest_point(point))<road_width*.5+2.0: return false
	for offset in [Vector2.ZERO,Vector2(6,0),Vector2(-6,0),Vector2(0,6),Vector2(0,-6)]:
		if junctions.contains(point+offset,true): return false
	return true

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
	# Rounded end caps close the metal profile without extending into the lane.
	if pts[0].y < -2250.0:
		for endpoint in [pts[0], pts[-1]]:
			draw_circle(endpoint, 2.4, Color("8395a7"))
			draw_circle(endpoint, 1.5, Color("dce6ec"))

func _get_tangent(pts: PackedVector2Array, idx: int) -> Vector2:
	if pts.size() < 2:
		return Vector2.RIGHT
	if idx < pts.size() - 1:
		return (pts[idx + 1] - pts[idx]).normalized()
	elif idx > 0:
		return (pts[idx] - pts[idx - 1]).normalized()
	return Vector2.RIGHT

func _build_guard_rails() -> void:
	_build_guard_rail_physics()
	_build_cliff_edges()

func _build_guard_rail_physics() -> void:
	var guard_stage_usec := {}
	var started := Time.get_ticks_usec()
	_ensure_guard_rail_sections()
	guard_stage_usec[&"sections"] = Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	if is_instance_valid(guard_rails):
		remove_child(guard_rails)
		guard_rails.free()
	guard_rails = StaticBody2D.new()
	guard_rails.name = "CliffGuardRails"
	guard_rails.collision_layer = 1
	guard_rails.collision_mask = 0
	add_child(guard_rails)

	# The drawn W-beam and physical barrier use exactly the same curve. A
	# single static concave shape represents every segment; the former layout
	# created one scene node and one physics object per 8 px sample.
	var rail_segments := PackedVector2Array()
	for points in _cached_guard_rail_sections:
		for i in range(points.size()-1):
			rail_segments.append(points[i])
			rail_segments.append(points[i+1])
	if not rail_segments.is_empty():
		var rail_collision := CollisionShape2D.new()
		rail_collision.name = "GuardRailSegments"
		var rail_shape := ConcavePolygonShape2D.new()
		rail_shape.segments = rail_segments
		rail_collision.shape = rail_shape
		guard_rails.add_child(rail_collision)
	for terminal in guard_rail_terminals:
		var cap := CollisionShape2D.new()
		cap.name = "CoachEntryTerminalPost"
		cap.shape = CircleShape2D.new()
		cap.shape.radius = 4.0
		cap.position = terminal[-1]
		guard_rails.add_child(cap)
	guard_rails.set_meta("terminal_curves",guard_rail_terminals)
	guard_rails.set_meta("segment_count", rail_segments.size() / 2)
	guard_stage_usec[&"physics"] = Time.get_ticks_usec() - started
	set_meta("guard_stage_usec", guard_stage_usec)

func _build_cliff_edges() -> void:
	var guard_stage_usec: Dictionary = get_meta("guard_stage_usec", {}).duplicate()
	var started := Time.get_ticks_usec()
	if is_instance_valid(cliff_edges):
		remove_child(cliff_edges)
		cliff_edges.queue_free()
	cliff_edges = preload("res://world/mountain_pass/MountainCliffEdges.gd").new()
	cliff_edges.name = "MountainCliffEdges"
	cliff_edges.road = self
	add_child(cliff_edges)
	cliff_edges.build(_cached_full_guard_rail_sections)
	guard_stage_usec[&"external_cliff_edges"] = Time.get_ticks_usec() - started
	set_meta("guard_stage_usec", guard_stage_usec)

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
	if curve != null and pos.distance_to(curve.get_closest_point(pos)) < tolerance:
		return true
	if resort_curve != null and pos.distance_to(resort_curve.get_closest_point(pos)) < tolerance:
		return true
	if summit_connector_curve != null and pos.distance_to(summit_connector_curve.get_closest_point(pos)) < tolerance:
		return true
	if pos.distance_to(Vector2(7140, -2545)) < 118.0:
		return true
	if Rect2(6918,-2662,144,177).has_point(pos):
		return true
	return false

func _marking_segments(points: PackedVector2Array) -> Array[PackedVector2Array]:
	var segments: Array[PackedVector2Array] = junctions.clip_marking(points)
	var roundabout := PackedVector2Array()
	for i in 32: roundabout.append(Vector2(7140,-2545)+Vector2.from_angle(TAU*i/32.0)*122.0)
	var parking := PackedVector2Array([Vector2(6908,-2672),Vector2(7072,-2672),Vector2(7072,-2475),Vector2(6908,-2475)])
	var exclusions: Array[PackedVector2Array] = [roundabout, parking, _circle_polygon(control_points[-1], 94.0)]
	for route in [resort_smooth_points, summit_connector_smooth_points]:
		exclusions.append_array(Geometry2D.offset_polyline(route, 90.0, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND))
	for apron in exclusions:
		var outside: Array[PackedVector2Array] = []
		for segment in segments:
			if segment.size()>1: outside.append_array(Geometry2D.clip_polyline_with_polygon(segment,apron))
		segments = outside
	return segments.filter(func(segment: PackedVector2Array):
		var length := 0.0
		for i in range(1, segment.size()): length += segment[i-1].distance_to(segment[i])
		return length >= 24.0
	)
