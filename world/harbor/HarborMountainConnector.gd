@tool
extends Node2D
## Structural second bridge. Asphalt and traffic are supplied by RoadLayout.
const OUTLET := Vector2(7300, -4529)
const INLET := Vector2(7300, -4591)
const SURFACE_STYLE = preload("res://geodata/roads/BridgeSurfaceStyle.gd")

## Meia-largura da faixa (pista + acostamento) que UnifiedRoadNetwork2D pinta
## de verdade para uma pista com bridge_surface=true: (width + SIDEWALK_MARGIN*2)*0.5
## = (62 + 42*2)*0.5 = 73. Usado abaixo pra desenhar o fundo decorativo do
## tabuleiro do tamanho exato da pista de verdade, sem sobra nem falta.
const LANE_HALF_ENVELOPE := 73.0
const DECK_CONCRETE := Color("777f7c")

## A partir daqui o tabuleiro reto (o Rect2 largo em draw_surface) dá lugar
## ao afunilamento real das duas pistas até o encontro em OUTLET/INLET.
const TAPER_START_X := 7100.0

static func road_definitions() -> Array[Dictionary]:
	var outbound := PackedVector2Array()
	for i in range(25):
		outbound.append(Vector2(6400, -4200) + Vector2.from_angle(PI + PI * 0.5 * i / 24.0) * 280.0)
	for i in range(1, 25):
		var t := float(i) / 24.0
		outbound.append(Vector2(lerpf(6400,7300,t), lerpf(-4480,-4529,smoothstep(0,1,t))))
	var inbound := PackedVector2Array()
	for i in range(25):
		var t := float(i) / 24.0
		inbound.append(Vector2(lerpf(7300,6500,t), lerpf(-4591,-4640,smoothstep(0,1,t))))
	inbound.append(Vector2(6240, -4640))
	for i in range(1, 25):
		inbound.append(Vector2(6240, -4280) + Vector2.from_angle(-PI * 0.5 - PI * 0.5 * i / 24.0) * 360.0)
	inbound.append(Vector2(5880, -4200))
	var definitions: Array[Dictionary] = []
	for entry in [{"id": "mountain_bridge_outbound", "points": outbound, "open_end": true, "open_start": false}, {"id": "mountain_bridge_inbound", "points": inbound, "open_end": false, "open_start": true}]:
		entry["width"] = 62.0
		entry["bridge_surface"] = true
		entry["preserve_open_endpoints"] = true
		entry["lanes"] = [{"lane_id": "forward_01", "offset": 0.0, "direction": 1, "direction_name": "forward"}]
		definitions.append(entry)
	return definitions

func _ready() -> void:
	z_index = 1
	_build_lighting()
	var rails := StaticBody2D.new()
	rails.collision_layer = 1
	rails.collision_mask = 0
	for y in [-4725.0, -4395.0]:
		var shape := CollisionShape2D.new()
		shape.shape = RectangleShape2D.new()
		shape.shape.size = Vector2(720, 8)
		shape.position = Vector2(6840, y)
		rails.add_child(shape)
	add_child(rails)
	for edge_points in guardrail_segments():
		var collision := CollisionShape2D.new()
		var edge := SegmentShape2D.new()
		edge.a = edge_points[0]
		edge.b = edge_points[1]
		collision.shape = edge
		rails.add_child(collision)
	# No travel Area2D: the eastern end physically meets MountainRegion.
	for edge_points in transition_guardrail_segments():
		var collision := CollisionShape2D.new()
		var segment := SegmentShape2D.new()
		segment.a = edge_points[0]
		segment.b = edge_points[1]
		collision.shape = segment
		rails.add_child(collision)
	queue_redraw()
	# z_as_relative=false (HarborGateway._ready() faz isso pra este nó) --
	# o z_index daqui não soma com o do pai, ele É o valor final. RoadLayout
	# (RoadNetwork) desenha o asfalto de verdade em z_index=2 absoluto; um
	# overlay próprio, também absoluto e mais alto, fecha somente o vão interno
	# entre as pistas sem cobrir a leitura das duas mãos na bifurcação.
	var gap_fill_overlay := Node2D.new()
	gap_fill_overlay.name = "GapFillOverlay"
	gap_fill_overlay.z_as_relative = false
	gap_fill_overlay.z_index = 5
	gap_fill_overlay.draw.connect(func(): draw_inner_gap_fill(gap_fill_overlay))
	add_child(gap_fill_overlay)
	gap_fill_overlay.queue_redraw()

func _build_lighting() -> void:
	if Engine.is_editor_hint(): return
	const FIXTURE = preload("res://geodata/roads/RoadLuminaire3D.gd")
	var definitions := road_definitions()
	for road_index in definitions.size():
		var definition: Dictionary = definitions[road_index]
		var curve := Curve2D.new()
		for point in definition.points: curve.add_point(point)
		var length := curve.get_baked_length()
		var count := ceili(length/210)
		for i in count+1:
			var offset := length*float(i)/count
			var center := curve.sample_baked(offset)
			var tangent := (curve.sample_baked(minf(offset+5,length))-curve.sample_baked(maxf(offset-5,0))).normalized()
			# Godot's orthogonal() points left in screen coordinates. Negate it
			# to keep both one-way carriageways' shared median clear.
			var normal := -tangent.orthogonal()
			var fixture := FIXTURE.new()
			# Tall projected poles face away from the road only on the north deck.
			fixture.fixture_kind = "flood" if road_index == 1 and i%3 == 1 else "strip"
			fixture.position = center+normal*76
			fixture.target_offset = -normal*76
			fixture.tangent = tangent
			add_child(fixture)
			fixture.pool.scale.x *= 1.4

func _draw() -> void:
	draw_surface(self)


## Antes desta correção o afunilamento final era um trapézio reto de 2
## pontos (345px de largura em x=7200 caindo pra 220px em x=7300), que não
## acompanhava a curva real das duas pistas -- o fundo claro (SHOULDER)
## ficava exposto onde devia estar coberto de asfalto escuro, visível como
## uma mancha/ponta de cor errada perto da água. Este polígono segue ponto a
## ponto o envelope combinado das duas pistas (outbound + inbound, cada uma
## com sua própria meia-largura real) na mesma faixa final, então o fundo
## nunca fica maior nem menor que o que as pistas de verdade cobrem.
static func _east_end_envelope() -> PackedVector2Array:
	var outbound: PackedVector2Array = road_definitions()[0].points
	var inbound: PackedVector2Array = road_definitions()[1].points
	var polygon := PackedVector2Array()
	for point in outbound:
		if point.x >= TAPER_START_X:
			polygon.append(point + Vector2(0, LANE_HALF_ENVELOPE))
	for point in inbound:
		if point.x >= TAPER_START_X:
			polygon.append(point + Vector2(0, -LANE_HALF_ENVELOPE))
	return polygon


## Interpola o Y de uma polilinha (assumida monótona em X) num X arbitrário.
## Usado pra achar, ponto a ponto, o meio do vão entre outbound e inbound
## mesmo com os dois tendo pontos amostrados em X diferentes.
static func _interpolate_y_at_x(points: PackedVector2Array, x: float) -> float:
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		if (x >= a.x and x <= b.x) or (x <= a.x and x >= b.x):
			var t := 0.0 if is_equal_approx(a.x, b.x) else (x - a.x) / (b.x - a.x)
			return lerpf(a.y, b.y, clampf(t, 0.0, 1.0))
	return points[0].y if x <= points[0].x else points[-1].y


## Cobre somente o vão real entre as duas pistas. O pequeno avanço de 3 px
## apaga as linhas brancas internas antes de a faixa central compartilhada
## começar, sem transformar a emenda inteira num retângulo de outra camada.
static func _inner_gap_polygon(marking_clearance := 3.0) -> PackedVector2Array:
	var outbound: PackedVector2Array = road_definitions()[0].points
	var inbound: PackedVector2Array = road_definitions()[1].points
	var upper_inner := PackedVector2Array()
	var lower_inner := PackedVector2Array()
	for i in 13:
		var x := lerpf(TAPER_START_X, 7300.0, float(i) / 12.0)
		upper_inner.append(Vector2(
			x,
			_interpolate_y_at_x(inbound, x) + 31.0 - marking_clearance
		))
		lower_inner.append(Vector2(
			x,
			_interpolate_y_at_x(outbound, x) - 31.0 + marking_clearance
		))
	var polygon := upper_inner
	for index in range(lower_inner.size() - 1, -1, -1):
		polygon.append(lower_inner[index])
	return polygon


static func draw_inner_gap_fill(canvas: Node2D) -> void:
	# The two one-way lanes keep a visible, dark median until the merge. The
	# shared road renderer otherwise paints a bright sidewalk wedge between them.
	var median := PackedVector2Array()
	var median_colors := PackedColorArray()
	var median_bottom := PackedVector2Array()
	var bottom_colors := PackedColorArray()
	var inbound: PackedVector2Array = road_definitions()[1].points
	var outbound: PackedVector2Array = road_definitions()[0].points
	for i in 32:
		var x := lerpf(6400.0, TAPER_START_X, float(i) / 31.0)
		var tint := Color(0.345, 0.392, 0.412, smoothstep(6400.0, 6620.0, x))
		median.append(Vector2(x, _interpolate_y_at_x(inbound, x) + 36.0))
		median_colors.append(tint)
		median_bottom.append(Vector2(x, _interpolate_y_at_x(outbound, x) - 36.0))
		bottom_colors.append(tint)
	for i in range(median_bottom.size() - 1, -1, -1):
		median.append(median_bottom[i])
		median_colors.append(bottom_colors[i])
	canvas.draw_polygon(median, median_colors)
	var gap := _inner_gap_polygon()
	if gap.size() >= 3:
		canvas.draw_colored_polygon(gap, SURFACE_STYLE.ASPHALT)
	# A one-pixel endpoint edge from the two independent road meshes otherwise
	# remains across the driving surface at the streaming seam.
	canvas.draw_rect(Rect2(7298.5, -4620.0, 3.0, 120.0), SURFACE_STYLE.ASPHALT)
	canvas.draw_line(Vector2(7298.5, -4560), Vector2(7301.5, -4560), SURFACE_STYLE.LANE, SURFACE_STYLE.MARKING_WIDTH, true)


static func draw_surface(canvas: Node2D) -> void:
	for edge_points in guardrail_segments():
		canvas.draw_line(edge_points[0],edge_points[1],Color("a4b5ba"),5,true)
	canvas.draw_rect(Rect2(6480, -4732, TAPER_START_X - 6480, 345), DECK_CONCRETE)
	canvas.draw_colored_polygon(_east_end_envelope(), DECK_CONCRETE)
	for y in [-4725.0, -4395.0]:
		canvas.draw_line(Vector2(6480, y), Vector2(TAPER_START_X, y), Color("c3c6b7"), 7)
		for x in range(6500, int(TAPER_START_X), 45):
			canvas.draw_circle(Vector2(x, y), 3, Color("efbf66"))
	for edge_points in transition_guardrail_segments():
		canvas.draw_line(edge_points[0], edge_points[1], Color("a4b5ba"), 5, true)
	for x in [6700.0, 7040.0]:
		for y in [-4740.0, -4380.0]:
			canvas.draw_rect(Rect2(x-14, y-18, 28, 36), Color("a4afa8"))
			for anchor_x in [x-190, x+190]:
				canvas.draw_line(Vector2(x, y), Vector2(anchor_x, y), Color("d2d0bd"), 2)


static func guardrail_segments() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var roads := road_definitions()
	for road_index in roads.size():
		var points: PackedVector2Array = roads[road_index].points
		for side in [-1.0,1.0]:
			for i in range(points.size()-1):
				var junction_end: Vector2 = points[0] if road_index == 0 else points[-1]
				if points[i].distance_to(junction_end) < 150 or points[i+1].distance_to(junction_end) < 150: continue
				var normal := (points[i+1]-points[i]).normalized().orthogonal()
				var a: Vector2 = points[i]+normal*82*side
				var b: Vector2 = points[i+1]+normal*82*side
				var midpoint: Vector2 = (a+b)*0.5
				var internal_edge := false
				# When decks merge at the mountain, never put a rail across the other lane.
				var other: PackedVector2Array = roads[1-road_index].points
				for j in range(other.size()-1):
					if midpoint.distance_to(Geometry2D.get_closest_point_to_segment(midpoint,other[j],other[j+1])) < 84:
						internal_edge = true
						break
				if not internal_edge: result.append(PackedVector2Array([a,b]))
	return result


static func transition_guardrail_segments() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for side in [-1.0, 1.0]:
		result.append(PackedVector2Array([
			Vector2(TAPER_START_X, -4560 + side * 165),
			Vector2(7300, -4560 + side * 110),
		]))
	return result
