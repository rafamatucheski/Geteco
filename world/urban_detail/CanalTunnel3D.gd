extends RefCounted
## Túnel do canal (Harbor): liga a warehouse_way (x≈141) à east_union_avenue
## (x≈343) em z=63, passando por baixo da quay_boulevard, do canal (sob o Northstar
## atracado) e da island_esplanade. z=63 é o único corredor livre entre a warehouse_way
## e o cais (entre o ColdStorage e a market_street); em z≈105 a casa Quayside (lugar
## com interior) fecha a vala. Na ilha a vala ocupa a exchange_lane (4,5 m, fora do
## grafo de trânsito), que vira o acesso leste do túnel. Trecho autoral FORA do grafo de ruas: não entra em
## `region.roads`, então o trânsito não cria cruzamento falso com as vias de cima (o
## grafo é 2D; ver docs/plano-passarela-tunel-elevado-20260927.md, "Base comum").
## Quem usa: jogador e qualquer veículo guiado fisicamente. Construído por chunk
## (NativeRegion._build_surfaces) só na fatia X do chunk; sem luzes dinâmicas.
##
## Perfil (m, eixo X):
##   140,75–143,5 acesso em nível | 143,5–178 rampa aberta | 178–200 coberto (cais)
##   200–273,75 tubo sob o canal (teto de vidro) | 273,75–296,7 coberto (esplanada)
##   296,7–333,4 rampa aberta | 333,4–343,25 acesso em nível
## Rampa de 12,5 %: entre a warehouse_way e o meio-fio da quay_boulevard há só 40 m;
## a 10 % o vão livre sob o cais ficaria abaixo de 3 m. 12,5 % dá 3,6 m na boca oeste.

const WALL_SHADER := preload("res://world/urban_detail/canal_tunnel_wall.gdshader")
const WATER_DEPTH_SHADER := preload("res://world/urban_detail/canal_tunnel_water_depth.gdshader")
const CITY := preload("res://world/city_look/CityLookMaterials.gd")

const CENTER_Z := 63.0
const HALF := 3.75 # meia largura interna (2 faixas de 3,15 m + passeios de 0,6 m)
const WALL := 0.6
const KERB := 0.6
const W_STUB := 140.75
const W_TOP := 143.5
const W_PORTAL := 178.0
const SHORE_W := 200.0
const SHORE_E := 273.75
const E_PORTAL := 296.7
const E_TOP := 333.4
const E_STUB := 343.25
const DEPTH := 6.0
const GRADE := 0.125
const CURVE := 6.0
const COVER_CEILING := -0.35
const CANAL_CEILING := -1.65 # vidro termina em -1,45: abaixo do casco do Northstar (-1,3)
const GLASS_TOP := -1.45
const PARAPET := 0.95
const WATER_Y := -0.94
## Região em que o mar não é desenhado (alinhada à grade de 4 m do HarborOcean).
# Ao sul vai até z=76: a câmera olha de cima e do sul a 45°, e a linha de visada do
# carro no fundo (-6 m) só sai da água ~5 m ao sul do tubo; o mar opaco o cobria.
const WATER_CUT := Rect2(140.0, 56.0, 196.0, 20.0)
const CANAL_SHEET := Rect2(SHORE_W, 56.0, SHORE_E - SHORE_W, 20.0)

static var _materials: Dictionary = {}

## A lâmina de água e a armação ficam entre a câmera e o veículo no fundo do
## túnel. O corte acompanha a câmera; fora dele a superfície conserva a cor.
static func set_camera_reveal(strength: float) -> void:
	strength = clampf(strength, 0.0, 1.0)
	for entry in [["water", 0.4, 0.025], ["glass", 0.1, 0.015], ["canopy_steel", 1.0, 0.07]]:
		var mat := material(entry[0]) as StandardMaterial3D
		var color := mat.albedo_color
		color.a = lerpf(float(entry[1]), float(entry[2]), strength)
		mat.albedo_color = color
		if entry[0] == "canopy_steel":
			mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED if strength < 0.001 else BaseMaterial3D.TRANSPARENCY_ALPHA

## Rua virtual do túnel para o grafo de rotas (trânsito, polícia, frete), no
## padrão de `WorldConnection3D.traffic_connectors`. Fica fora de `region.roads`
## para não ganhar asfalto, postes, faixas e semáforos no nível da rua. Os pontos
## carregam a altura real do piso: o grafo identifica nós por (x, y, z), então o
## trecho a −6 m sob a quay_boulevard e a island_esplanade cruza em 2D sem virar
## cruzamento. As pontas (y = 0) se ligam às ruas de cada margem, procuradas nas
## ruas carregadas para seguir edições do MUNDO.
const TRAFFIC_ID := "canal_tunnel"
const TRAFFIC_WIDTH := 6.3 # duas faixas de 3,15 m; os passeios de 0,6 m ficam fora
const WEST_ROAD := "warehouse_way"
const EAST_ROAD := "east_union_avenue"

static func traffic_roads(roads: Array) -> Array[Dictionary]:
	var west := _mouth_on(roads, WEST_ROAD, W_STUB)
	var east := _mouth_on(roads, EAST_ROAD, E_STUB)
	if west == Vector3.INF or east == Vector3.INF: return []
	# Só três pontos: boca, meio do fundo, boca. `route_between` escolhe o caminho
	# com MENOS TRECHOS (busca em largura), não o mais curto. Com um ponto por
	# mudança de inclinação o túnel somava 14 trechos contra 5 da volta pela ponte;
	# com quatro pontos empatava (e o empate cai na rua, que vem antes na lista).
	# Com dois trechos (+2 cortes das ruas que passam por cima) são 4. A altura
	# entre pontos é linear: sob a quay_boulevard e a esplanada o nó fica a ~−3 m,
	# longe do nível da rua, então continua sem cruzamento falso. O carro segue o
	# piso pela física, não a altura da curva.
	# Nó do fundo perto da margem oeste, não no meio: parado no meio do túnel o
	# jogador coincidia com o nó, `route_between` descartava os trechos que saem
	# dele e a viatura passava direto. Sob a esplanada o grafo fica a −2,3 m.
	var middle := Vector3(SHORE_W + 5.0, -DEPTH, CENTER_Z)
	var points := PackedVector3Array([west, middle, east])
	return [{"id": TRAFFIC_ID, "width": TRAFFIC_WIDTH, "points": points, "surface": "tunnel", "lanes_per_direction": 1}]

## Abaixo do nível da rua dentro do túnel (rampas e tubo).
static func below_grade(point: Vector3) -> bool:
	return in_roadway(point) and point.y < -1.0

## Caminho a pé entre rua e túnel. A busca em grade de `Gameplay.find_path` roda
## numa altura fixa: com o alvo a −6 m ela levava a polícia até o cais, EM CIMA
## dele. Aqui o trecho do túnel segue o eixo pela rampa e a busca em grade cuida
## só da parte de superfície até a boca. Vazio = não envolve o túnel.
static func walking_path(start: Vector3, finish: Vector3, surface: Callable) -> PackedVector3Array:
	var start_below := below_grade(start)
	var finish_below := below_grade(finish)
	if not start_below and not finish_below: return PackedVector3Array()
	if start_below and finish_below: return _axis_walk(start.x, finish.x)
	var inside := finish if finish_below else start
	var outside := start if finish_below else finish
	# Boca mais curta para quem está fora + trecho dentro até o alvo.
	var west := Vector3(W_TOP - 2.0, 0.0, CENTER_Z)
	var east := Vector3(E_TOP + 2.0, 0.0, CENTER_Z)
	var mouth := west
	if outside.distance_to(east) + absf(E_TOP - inside.x) < outside.distance_to(west) + absf(inside.x - W_TOP): mouth = east
	var result := PackedVector3Array()
	if finish_below:
		result.append_array(surface.call(outside, mouth))
		result.append(mouth)
		result.append_array(_axis_walk(mouth.x, inside.x))
	else:
		result.append_array(_axis_walk(inside.x, mouth.x))
		result.append(mouth)
		result.append_array(surface.call(mouth, outside))
	return result

static func _axis_walk(from_x: float, to_x: float) -> PackedVector3Array:
	var result := PackedVector3Array()
	var steps := maxi(1, int(absf(to_x - from_x) / 3.0))
	for step in range(1, steps + 1):
		var x := lerpf(from_x, to_x, float(step) / steps)
		result.append(Vector3(x, floor_y(x), CENTER_Z))
	return result

## Ponto (x, z) dentro da faixa de rolamento do túnel, entre as bocas.
static func in_roadway(point: Vector3) -> bool:
	return point.x > W_STUB and point.x < E_STUB and point.z > inner_north() - .5 and point.z < inner_south() + .5

## A curva de rota que o grafo monta corta a rampa em linha reta (o túnel tem só
## dois trechos no grafo, ver `traffic_roads`). Entre pontos consecutivos dentro do
## túnel insere pontos a cada 2,5 m na altura do piso, e corrige os existentes:
## reposicionamento de trânsito e sondagens de faixa usam a altura da curva.
static func follow_floor(curve: Curve3D) -> void:
	var inside := false
	for i in curve.point_count:
		if in_roadway(curve.get_point_position(i)): inside = true
	if not inside: return
	var rebuilt := Curve3D.new()
	rebuilt.bake_interval = curve.bake_interval
	for i in curve.point_count:
		var at := curve.get_point_position(i)
		if in_roadway(at): at.y = floor_y(at.x)
		rebuilt.add_point(at, curve.get_point_in(i), curve.get_point_out(i))
		if i + 1 >= curve.point_count: break
		var next := curve.get_point_position(i + 1)
		if not (in_roadway(at) and in_roadway(next)): continue
		var steps := int(absf(next.x - at.x) / 2.5)
		for step in range(1, steps):
			var point := at.lerp(next, float(step) / steps)
			point.y = floor_y(point.x)
			rebuilt.add_point(point)
	curve.clear_points()
	for i in rebuilt.point_count:
		curve.add_point(rebuilt.get_point_position(i), rebuilt.get_point_in(i), rebuilt.get_point_out(i))

## Ponto da rua `id` na linha do túnel (z = CENTER_Z), na altura dela.
static func _mouth_on(roads: Array, id: String, near_x: float) -> Vector3:
	var best := Vector3.INF
	for road in roads:
		if not road is Dictionary or str(road.get("id", "")) != id: continue
		var points: PackedVector3Array = road.points
		for i in range(points.size() - 1):
			var a := points[i]
			var b := points[i + 1]
			if (a.z - CENTER_Z) * (b.z - CENTER_Z) > 0.0 or is_equal_approx(a.z, b.z): continue
			var hit := a.lerp(b, (CENTER_Z - a.z) / (b.z - a.z))
			if best == Vector3.INF or absf(hit.x - near_x) < absf(best.x - near_x): best = hit
	return best

static func inner_north() -> float: return CENTER_Z - HALF
static func inner_south() -> float: return CENTER_Z + HALF
static func outer_north() -> float: return CENTER_Z - HALF - WALL
static func outer_south() -> float: return CENTER_Z + HALF + WALL

static func ramp_length() -> float:
	return DEPTH / GRADE + CURVE

## Profundidade descida a `u` metros do topo da rampa (curvas verticais parabólicas).
static func _drop(u: float) -> float:
	var total := ramp_length()
	if u <= 0.0: return 0.0
	if u >= total: return DEPTH
	if u < CURVE: return GRADE * u * u / (2.0 * CURVE)
	if u < total - CURVE: return GRADE * CURVE * 0.5 + GRADE * (u - CURVE)
	var v := total - u
	return DEPTH - GRADE * v * v / (2.0 * CURVE)

## Altura do piso do túnel (colisão) em x. Zero fora das rampas.
static func floor_y(x: float) -> float:
	if x <= W_TOP or x >= E_TOP: return 0.0
	return -_drop(minf(x - W_TOP, E_TOP - x))

## "stub", "open", "covered", "canal" ou "" (fora do túnel).
static func section_at(x: float) -> String:
	if x < W_STUB or x > E_STUB: return ""
	if x < W_TOP or x > E_TOP: return "stub"
	if x < W_PORTAL or x > E_PORTAL: return "open"
	if x < SHORE_W or x > SHORE_E: return "covered"
	return "canal"

static func ceiling_y(x: float) -> float:
	match section_at(x):
		"covered": return COVER_CEILING
		"canal": return CANAL_CEILING
	return INF

## Recortes do chão da ilha/cidade (caixas "Land"): rampas abertas e trechos cobertos.
static func land_cuts() -> Array[Rect2]:
	var depth := outer_south() - outer_north()
	return [Rect2(W_TOP, outer_north(), SHORE_W - W_TOP, depth), Rect2(SHORE_E, outer_north(), E_TOP - SHORE_E, depth)]

## Rampas a céu aberto: nada de calçada, pintura ou mobiliário flutuando por cima.
static func open_cuts() -> Array[Rect2]:
	var depth := outer_south() - outer_north()
	return [Rect2(W_TOP, outer_north(), W_PORTAL - W_TOP, depth), Rect2(E_PORTAL, outer_north(), E_TOP - E_PORTAL, depth)]

## Área que o mobiliário automático e os objetos do mapa não podem ocupar: rampas
## abertas, acessos em nível e os pórticos.
static func reserves(point: Vector2, margin := 0.0) -> bool:
	var band := Rect2(W_STUB, outer_north() - 1.2, E_STUB - W_STUB, outer_south() - outer_north() + 2.4).grow(margin)
	if not band.has_point(point): return false
	var covered := Rect2(W_PORTAL + 1.0, band.position.y, E_PORTAL - W_PORTAL - 2.0, band.size.y)
	return not covered.has_point(point)

## Pedaços de `surface` fora dos recortes de chão.
static func outside_land(surface: Rect2) -> Array[Rect2]:
	var pieces: Array[Rect2] = [surface]
	for cut in land_cuts():
		var next: Array[Rect2] = []
		for piece in pieces: next.append_array(_rect_outside(piece, cut))
		pieces = next
	return pieces

static func _rect_outside(surface: Rect2, hole: Rect2) -> Array[Rect2]:
	if not surface.has_area(): return []
	var overlap := surface.intersection(hole)
	if not overlap.has_area(): return [surface]
	var pieces: Array[Rect2] = []
	if overlap.position.y > surface.position.y:
		pieces.append(Rect2(surface.position, Vector2(surface.size.x, overlap.position.y - surface.position.y)))
	if overlap.end.y < surface.end.y:
		pieces.append(Rect2(Vector2(surface.position.x, overlap.end.y), Vector2(surface.size.x, surface.end.y - overlap.end.y)))
	if overlap.position.x > surface.position.x:
		pieces.append(Rect2(Vector2(surface.position.x, overlap.position.y), Vector2(overlap.position.x - surface.position.x, overlap.size.y)))
	if overlap.end.x < surface.end.x:
		pieces.append(Rect2(Vector2(overlap.end.x, overlap.position.y), Vector2(surface.end.x - overlap.end.x, overlap.size.y)))
	return pieces

# --- recorte do acabamento de chão -------------------------------------------------

## Tira das rampas abertas tudo o que é chapa de chão (asfalto, calçada, pintura,
## pisos do editor, cópias "_Lit") e as colisões planas em y≈0 que as acompanham.
## Genérico de propósito: essas camadas vêm de vários geradores (HarborRoadGeometry,
## HarborUrbanSurface, WorldGroundFactory, CityLook) e só o túnel sabe onde abriu a vala.
static func carve_chunk(chunk: Node3D, rect: Rect2) -> void:
	var cuts: Array[Rect2] = []
	for cut in open_cuts():
		if cut.intersects(rect): cuts.append(cut)
	if cuts.is_empty(): return
	var done := {}
	for node in chunk.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or str(mesh.get_path()).contains("CanalTunnel"): continue
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		if box.position.y < -0.12 or box.end.y > 0.12: continue
		if not _touches(box, cuts): continue
		var key := mesh.mesh.get_rid()
		if not done.has(key): done[key] = _carved_mesh(mesh.mesh, mesh.global_transform, cuts)
		mesh.mesh = done[key]
	for node in chunk.find_children("*", "CollisionShape3D", true, false):
		var collider := node as CollisionShape3D
		if not collider.shape is ConcavePolygonShape3D or str(collider.get_path()).contains("CanalTunnel"): continue
		var faces: PackedVector3Array = (collider.shape as ConcavePolygonShape3D).get_faces()
		if faces.is_empty(): continue
		var to_global := collider.global_transform
		var flat := true
		var bounds := AABB(to_global * faces[0], Vector3.ZERO)
		for face in faces:
			var point := to_global * face
			bounds = bounds.expand(point)
			if absf(point.y) > 0.12:
				flat = false
				break
		if not flat or not _touches(bounds, cuts): continue
		var carved := _carve_triangles({Mesh.ARRAY_VERTEX: faces}, to_global, cuts)
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = (collider.shape as ConcavePolygonShape3D).backface_collision
		shape.set_faces(carved[Mesh.ARRAY_VERTEX])
		collider.shape = shape

static func _touches(box: AABB, cuts: Array[Rect2]) -> bool:
	var area := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
	for cut in cuts:
		if area.intersects(cut): return true
	return false

static func _carved_mesh(source: Mesh, to_global: Transform3D, cuts: Array[Rect2]) -> Mesh:
	var result := ArrayMesh.new()
	for surface in source.get_surface_count():
		if source is ArrayMesh and (source as ArrayMesh).surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES: return source
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var channels := {}
		var indices := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null: indices = arrays[Mesh.ARRAY_INDEX]
		for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
			if arrays[channel] == null: continue
			var values: Variant = arrays[channel]
			if not indices.is_empty():
				# Desindexa: cada triângulo recortado ganha vértices próprios.
				var expanded: Variant = values.duplicate()
				expanded.resize(0)
				var stride := 4 if channel == Mesh.ARRAY_TANGENT else 1
				for index in indices:
					for k in stride: expanded.append(values[index * stride + k])
				values = expanded
			channels[channel] = values
		var carved := _carve_triangles(channels, to_global, cuts)
		if (carved[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty(): continue
		var out := []
		out.resize(Mesh.ARRAY_MAX)
		for channel in carved: out[channel] = carved[channel]
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
		result.surface_set_material(result.get_surface_count() - 1, source.surface_get_material(surface))
	return result

## Triângulos (não indexados) menos os retângulos, em XZ do mundo. O exterior de um
## retângulo é a união de quatro faixas convexas: cada pedaço sai convexo, sem furo.
static func _carve_triangles(channels: Dictionary, to_global: Transform3D, cuts: Array[Rect2]) -> Dictionary:
	var vertices: PackedVector3Array = channels[Mesh.ARRAY_VERTEX]
	var out := {}
	for channel in channels:
		var empty: Variant = channels[channel].duplicate()
		empty.resize(0)
		out[channel] = empty
	for t in range(0, vertices.size() - 2, 3):
		var a := to_global * vertices[t]
		var b := to_global * vertices[t + 1]
		var c := to_global * vertices[t + 2]
		var tri := PackedVector2Array([Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)])
		var bounds := Rect2(tri[0], Vector2.ZERO).expand(tri[1]).expand(tri[2])
		var hit := false
		for cut in cuts:
			if bounds.intersects(cut): hit = true
		var area := (tri[1] - tri[0]).cross(tri[2] - tri[0])
		if not hit or absf(area) < 0.000001:
			for k in 3: _copy_vertex(channels, out, t + k)
			continue
		var pieces: Array[PackedVector2Array] = [tri]
		for cut in cuts:
			var next: Array[PackedVector2Array] = []
			var slabs := [
				Rect2(-1e6, -1e6, cut.position.x + 1e6, 2e6),
				Rect2(cut.end.x, -1e6, 1e6, 2e6),
				Rect2(cut.position.x, -1e6, cut.size.x, cut.position.y + 1e6),
				Rect2(cut.position.x, cut.end.y, cut.size.x, 1e6)]
			for piece in pieces:
				for slab in slabs:
					var slab_polygon := PackedVector2Array([slab.position, Vector2(slab.end.x, slab.position.y), slab.end, Vector2(slab.position.x, slab.end.y)])
					for part in Geometry2D.intersect_polygons(piece, slab_polygon):
						if part.size() >= 3: next.append(part)
			pieces = next
		for piece in pieces:
			for i in range(1, piece.size() - 1):
				var fan := [piece[0], piece[i], piece[i + 1]]
				if signf((fan[1] - fan[0]).cross(fan[2] - fan[0])) != signf(area): fan = [fan[0], fan[2], fan[1]]
				for p in fan: _blend_vertex(channels, out, t, tri, area, p)
	return out

static func _copy_vertex(channels: Dictionary, out: Dictionary, index: int) -> void:
	for channel in channels:
		if channel == Mesh.ARRAY_TANGENT:
			for k in 4: out[channel].append(channels[channel][index * 4 + k])
		else: out[channel].append(channels[channel][index])

static func _blend_vertex(channels: Dictionary, out: Dictionary, t: int, tri: PackedVector2Array, area: float, p: Vector2) -> void:
	var w0 := (tri[1] - p).cross(tri[2] - p) / area
	var w1 := (tri[2] - p).cross(tri[0] - p) / area
	var w2 := 1.0 - w0 - w1
	for channel in channels:
		var values: Variant = channels[channel]
		if channel == Mesh.ARRAY_TANGENT:
			for k in 4: out[channel].append(values[t * 4 + k] * w0 + values[(t + 1) * 4 + k] * w1 + values[(t + 2) * 4 + k] * w2)
		else:
			out[channel].append(values[t] * w0 + values[t + 1] * w1 + values[t + 2] * w2)

# --- construção -----------------------------------------------------------------

var _surfaces: Dictionary = {} # material id -> {tool, material}
var _batches: Dictionary = {} # material id -> Array[Transform3D]
var _x0 := 0.0
var _x1 := 0.0
var _wall_faces := PackedVector3Array()
var _body: StaticBody3D
var _root: Node3D

static func build_chunk(parent: Node3D, rect: Rect2) -> Node3D:
	# A vala cruza a divisa z=64 das células: tudo fica no chunk que contém o eixo.
	if CENTER_Z < rect.position.y or CENTER_Z >= rect.end.y: return null
	var x0 := maxf(rect.position.x, W_STUB)
	var x1 := minf(rect.end.x, E_STUB)
	if x1 <= x0: return null
	var builder = load("res://world/urban_detail/CanalTunnel3D.gd").new()
	return builder._build(parent, x0, x1)

func _build(parent: Node3D, x0: float, x1: float) -> Node3D:
	_x0 = x0
	_x1 = x1
	_root = Node3D.new()
	_root.name = "CanalTunnel"
	_root.add_to_group("canal_tunnel")
	parent.add_child(_root)
	_body = StaticBody3D.new()
	_body.name = "CanalTunnelSolid"
	# Piso e paredes da rampa: o sensor frontal dos carros ignora (ver Vehicle.obstacle_ahead).
	_body.set_meta("vehicle_ramp_structure", true)
	_body.collision_layer = 1
	_body.collision_mask = 0
	_root.add_child(_body)
	var cuts: Array[float] = [x0, x1]
	for mark in [W_TOP, W_PORTAL, SHORE_W, SHORE_E, E_PORTAL, E_TOP]:
		if mark > x0 and mark < x1: cuts.append(mark)
	var x := ceilf(x0)
	while x < x1:
		if x > x0: cuts.append(x)
		x += 1.0
	cuts.sort()
	for i in cuts.size() - 1:
		if cuts[i + 1] - cuts[i] > 0.001: _segment(cuts[i], cuts[i + 1])
	_sections_boxes(x0, x1)
	_repeating(x0, x1)
	for portal in [[W_PORTAL, -1.0], [E_PORTAL, 1.0]]:
		if portal[0] >= x0 and portal[0] < x1: _portal(float(portal[0]), float(portal[1]))
	_flush()
	return _root

## Uma fatia de ≤1 m: piso, passeios, marcações e paredes seguindo o perfil.
func _segment(xa: float, xb: float) -> void:
	var section := section_at((xa + xb) * 0.5)
	var zn := inner_north()
	var zs := inner_south()
	if section == "stub":
		# Acesso em nível sobre o chão existente: só pintura de asfalto, sem colisão.
		_quad_flat("asphalt", xa, xb, zn, zs, 0.03, 0.03)
		_markings(xa, xb, 0.035, 0.035)
		return
	var ya := floor_y(xa)
	var yb := floor_y(xb)
	_quad_flat("asphalt", xa, xb, zn + KERB, zs - KERB, ya + 0.03, yb + 0.03)
	_markings(xa, xb, ya + 0.035, yb + 0.035)
	for side in [[zn, zn + KERB, 1.0], [zs - KERB, zs, -1.0]]:
		_quad_flat("walkway", xa, xb, side[0], side[1], ya + 0.18, yb + 0.18)
		var face_z: float = side[1] if side[2] > 0.0 else side[0]
		_quad_vertical("kerb", xa, xb, face_z, ya, yb, ya + 0.18, yb + 0.18, Vector3(0, 0, side[2]))
	var top_a := _wall_top(xa, section)
	var top_b := _wall_top(xb, section)
	# Parede norte (face vista pela câmera, olhando para o norte).
	_quad_vertical("wall_north", xa, xb, zn, ya, yb, top_a, top_b, Vector3(0, 0, 1), true)
	# Parede sul: no canal é vidro (a câmera enxerga o tubo pelo lado de cima/sul).
	var south_material := "glass" if section == "canal" else "wall_south"
	_quad_vertical(south_material, xa, xb, zs, ya, yb, top_a, top_b, Vector3(0, 0, -1), south_material != "glass")
	if section == "canal":
		_quad_vertical("glass", xa, xb, outer_south(), ya - 0.5, yb - 0.5, GLASS_TOP, GLASS_TOP, Vector3(0, 0, 1))
	for wall_z in [zn, zs]:
		# Até o teto (ou o chão, nas rampas: o parapeito tem caixa própria). Nada acima
		# de y=0 no trecho coberto: a parede furava 20 cm o asfalto do cais.
		_collision_wall(xa, xb, wall_z, ya, yb, top_a, top_b)

func _wall_top(_x: float, section: String) -> float:
	match section:
		"covered": return COVER_CEILING
		"canal": return CANAL_CEILING
	return 0.0 # rampa aberta: a parede vai até o chão; acima dela, o parapeito

## Peças em caixa por trecho: tetos, tampas de parede, parapeitos, fundo do canal.
func _sections_boxes(x0: float, x1: float) -> void:
	var outer_n := outer_north()
	var outer_s := outer_south()
	var width := outer_s - outer_n
	for span in [[W_TOP, W_PORTAL, "open"], [W_PORTAL, SHORE_W, "covered"], [SHORE_W, SHORE_E, "canal"], [SHORE_E, E_PORTAL, "covered"], [E_PORTAL, E_TOP, "open"]]:
		var a := maxf(x0, float(span[0]))
		var b := minf(x1, float(span[1]))
		if b <= a: continue
		var mid := (a + b) * 0.5
		var length := b - a
		match span[2]:
			"covered":
				# Laje sob o cais/esplanada: substitui o chão recortado e sustenta quem passa em cima.
				_box("roof_top", Vector3(mid, -0.005, CENTER_Z), Vector3(length, 0.01, width))
				_box("ceiling", Vector3(mid, (COVER_CEILING - 0.01) * 0.5, CENTER_Z), Vector3(length, -COVER_CEILING - 0.02, width))
				_solid(Vector3(mid, COVER_CEILING * 0.5, CENTER_Z), Vector3(length, -COVER_CEILING, width))
			"canal":
				_box("glass", Vector3(mid, (GLASS_TOP + CANAL_CEILING) * 0.5, CENTER_Z), Vector3(length, GLASS_TOP - CANAL_CEILING, width))
				_solid(Vector3(mid, (GLASS_TOP + CANAL_CEILING) * 0.5, CENTER_Z), Vector3(length, GLASS_TOP - CANAL_CEILING, width))
				_box("concrete_dark", Vector3(mid, CANAL_CEILING + 0.5 * (GLASS_TOP - CANAL_CEILING) - 0.0, outer_n + WALL * 0.5), Vector3(length, GLASS_TOP - CANAL_CEILING, WALL))
				# Lâmina de água translúcida no lugar do mar recortado, fundo e laje de base.
				_box("water", Vector3(mid, WATER_Y, CANAL_SHEET.get_center().y), Vector3(length, 0.004, CANAL_SHEET.size.y))
				_box("seabed", Vector3(mid, -7.3, CANAL_SHEET.get_center().y), Vector3(length, 0.3, CANAL_SHEET.size.y))
				# Água submersa do lado externo do vidro sul, sem ocupar a pista.
				var water_bottom := -7.15
				var water_top := WATER_Y - 0.02
				var water_near := outer_s + 0.05
				var water_far := CANAL_SHEET.end.y
				_box("water_depth", Vector3(mid, (water_bottom + water_top) * 0.5, (water_near + water_far) * 0.5), Vector3(length, water_top - water_bottom, water_far - water_near))
				_box("concrete_dark", Vector3(mid, -DEPTH - 0.3, CENTER_Z), Vector3(length, 0.6, width))
				# Folga atrás do azulejo: faces coplanares disputavam profundidade.
				_box("concrete_dark", Vector3(mid, (-DEPTH + CANAL_CEILING) * 0.5, outer_n + (WALL - 0.04) * 0.5), Vector3(length, CANAL_CEILING + DEPTH, WALL - 0.04))
			"open":
				for side in [[outer_n + WALL * 0.5, false], [outer_s - WALL * 0.5, true]]:
					var z: float = side[0]
					_box("cap", Vector3(mid, 0.02, z), Vector3(length, 0.04, WALL + 0.1))
					if side[1]:
						# Sul: gradil fino de aço (não esconde o carro da câmera), sólido na colisão.
						_box("rail", Vector3(mid, PARAPET, z), Vector3(length, 0.09, 0.09))
						_box("rail_paint", Vector3(mid, PARAPET * 0.55, z), Vector3(length, 0.05, 0.05))
					else:
						_box("parapet", Vector3(mid, PARAPET * 0.5, z), Vector3(length, PARAPET, WALL * 0.7))
						_box("neon_teal", Vector3(mid, PARAPET + 0.03, z + WALL * 0.35), Vector3(length, 0.05, 0.05))
					_solid(Vector3(mid, PARAPET * 0.5, z), Vector3(length, PARAPET, WALL))

## Peças que se repetem ao longo do eixo: luminárias de teto, costelas do tubo,
## tachões, postes do parapeito e montantes do gradil.
func _repeating(x0: float, x1: float) -> void:
	var start := ceilf(x0 / 2.0) * 2.0
	var x := start
	while x < x1:
		var section := section_at(x)
		var index := int(round(x / 2.0))
		if section in ["covered", "canal"] and index % 2 == 0:
			var ceiling := ceiling_y(x)
			# Uma fileira na borda do teto identifica as luminárias sem projetar
			# três séries de traços brancos sobre as faixas da estrada.
			_box("ceiling_lamp", Vector3(x, ceiling - 0.06, inner_north() + 0.9), Vector3(1.4, 0.06, 0.18))
		if section == "canal" and index % 2 == 0:
			# Costela de aço: arco do teto de vidro e montante do vidro sul.
			_box("canopy_steel", Vector3(x, GLASS_TOP + 0.04, CENTER_Z), Vector3(0.22, 0.12, outer_south() - outer_north()))
			_box("canopy_steel", Vector3(x, (floor_y(x) + GLASS_TOP) * 0.5, outer_south() - 0.05), Vector3(0.2, GLASS_TOP - floor_y(x), 0.14))
		if section in ["open", "covered", "canal"] and index % 2 == 0:
			var y := floor_y(x)
			for z in [CENTER_Z - 0.18, CENTER_Z + 0.18]:
				_box("cat_eye", Vector3(x, y + 0.06, z), Vector3(0.14, 0.04, 0.1))
		if section == "open":
			if index % 6 == 0 and absf(x - (W_PORTAL - 19.0)) > 4.5 and absf(x - (E_PORTAL + 19.0)) > 4.5:
				_box("lamp_pole", Vector3(x, PARAPET + 1.6, outer_north() + WALL * 0.5), Vector3(0.14, 3.2, 0.14))
				_box("lamp_pole", Vector3(x, PARAPET + 3.15, outer_north() + WALL * 0.5 + 0.7), Vector3(0.1, 0.1, 1.4))
				_box("lamp_head", Vector3(x, PARAPET + 3.05, outer_north() + WALL * 0.5 + 1.3), Vector3(0.5, 0.16, 0.34))
			_box("rail", Vector3(x, PARAPET * 0.5, outer_south() - WALL * 0.5), Vector3(0.07, PARAPET, 0.07))
		x += 2.0

## Pórtico: cabeceira com listras de alerta, três quadros escalonados com neon,
## luminárias e o totem com o nome, virado para a câmera (sul).
func _portal(x: float, outward: float) -> void:
	var zn := outer_north()
	var zs := outer_south()
	var width := zs - zn
	# Cabeceira sobre a boca (da laje até 1,2 m acima do chão).
	var head_x := x + outward * 0.35
	_box("concrete", Vector3(head_x, (COVER_CEILING + 1.2) * 0.5, CENTER_Z), Vector3(0.7, 1.2 - COVER_CEILING, width))
	_solid(Vector3(head_x, (COVER_CEILING + 1.2) * 0.5, CENTER_Z), Vector3(0.7, 1.2 - COVER_CEILING, width))
	_box("hazard", Vector3(head_x, 1.21, CENTER_Z), Vector3(0.7, 0.02, width))
	_box("neon_teal", Vector3(head_x - outward * 0.33, 1.24, CENTER_Z), Vector3(0.06, 0.06, width))
	# Quadros escalonados avançando sobre a rampa aberta: leem como arco de cima.
	for step in 3:
		var fx := x + outward * (1.2 + step * 3.2)
		var height := 5.2 - step * 0.8
		for z in [zn + WALL * 0.5, zs - WALL * 0.5]:
			_box("portal_paint", Vector3(fx, height * 0.5, z), Vector3(0.7, height, WALL))
			_solid(Vector3(fx, height * 0.5, z), Vector3(0.7, height, WALL))
		_box("portal_paint", Vector3(fx, height - 0.3, CENTER_Z), Vector3(0.7, 0.6, width))
		_box("neon_orange" if step % 2 == 0 else "neon_teal", Vector3(fx, height + 0.03, CENTER_Z), Vector3(0.12, 0.06, width - 0.2))
		# Faixa de neon na face sul do pilar sul (a que a câmera vê de frente).
		_box("neon_teal", Vector3(fx, height * 0.5, zs + 0.02), Vector3(0.14, height - 0.4, 0.05))
		if step == 0:
			for z in [CENTER_Z - 2.2, CENTER_Z + 2.2]:
				_box("lamp_head", Vector3(fx, height - 0.66, z), Vector3(0.5, 0.12, 0.5))
	# Placa com o nome, na borda norte (fica atrás da rampa, não tapa o carro).
	# Longe dos quadros do pórtico, que a escondiam na câmera diagonal do jogo.
	var sign_center := Vector3(x + outward * 19.0, PARAPET + 1.9, zn + 0.08)
	_box("sign_board", sign_center, Vector3(6.6, 1.5, 0.12))
	_box("neon_orange", sign_center + Vector3(0, 0.8, 0.06), Vector3(6.6, 0.07, 0.06))
	_box("neon_orange", sign_center + Vector3(0, -0.8, 0.06), Vector3(6.6, 0.07, 0.06))
	for dx in [-3.1, 3.1]:
		_box("lamp_pole", Vector3(sign_center.x + dx, (PARAPET + 1.9) * 0.5, zn + 0.08), Vector3(0.16, PARAPET + 1.9, 0.16))
	var label := Label3D.new()
	label.name = "CanalTunnelSign"
	label.text = "TÚNEL DO CANAL"
	label.font_size = 96
	label.outline_size = 18
	label.pixel_size = 0.0075
	label.modulate = Color(1.0, 0.96, 0.86)
	label.outline_modulate = Color(0.02, 0.1, 0.12)
	label.position = sign_center + Vector3(0, 0.12, 0.08)
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(label)
	var sub := Label3D.new()
	sub.name = "CanalTunnelClearance"
	sub.text = ("CIDADE" if outward < 0.0 else "ILHA") + "  ·  ALTURA MÁX 3,5 m"
	sub.font_size = 48
	sub.outline_size = 10
	sub.pixel_size = 0.0075
	sub.modulate = Color(1.0, 0.78, 0.35)
	sub.outline_modulate = Color(0.02, 0.1, 0.12)
	sub.position = sign_center + Vector3(0, -0.46, 0.08)
	sub.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(sub)

# --- primitivas -------------------------------------------------------------------

func _markings(xa: float, xb: float, ya: float, yb: float) -> void:
	# Linha dupla amarela contínua no eixo, bordas brancas.
	for z in [CENTER_Z - 0.12, CENTER_Z + 0.12]:
		_quad_flat("paint_yellow", xa, xb, z - 0.05, z + 0.05, ya, yb)
	for z in [inner_north() + KERB + 0.2, inner_south() - KERB - 0.2]:
		_quad_flat("paint_white", xa, xb, z - 0.06, z + 0.06, ya, yb)

func _quad_flat(id: String, xa: float, xb: float, za: float, zb: float, ya: float, yb: float) -> void:
	_quad(id, [Vector3(xa, ya, za), Vector3(xb, yb, za), Vector3(xb, yb, zb), Vector3(xa, ya, zb)], Vector3.UP, [Vector2(xa, za) / 4.0, Vector2(xb, za) / 4.0, Vector2(xb, zb) / 4.0, Vector2(xa, zb) / 4.0])

## Face vertical em z entre o piso (ya/yb) e o topo (ta/tb). UV = (x, altura acima do piso).
func _quad_vertical(id: String, xa: float, xb: float, z: float, ya: float, yb: float, ta: float, tb: float, normal: Vector3, floor_uv := false) -> void:
	if ta <= ya and tb <= yb: return
	var base_a := ya if floor_uv else 0.0
	var base_b := yb if floor_uv else 0.0
	_quad(id, [Vector3(xa, ya, z), Vector3(xb, yb, z), Vector3(xb, tb, z), Vector3(xa, ta, z)], normal, [Vector2(xa, ya - base_a), Vector2(xb, yb - base_b), Vector2(xb, tb - base_b), Vector2(xa, ta - base_a)])

func _quad(id: String, points: Array, normal: Vector3, uvs: Array) -> void:
	if not _surfaces.has(id):
		var branch_tool := SurfaceTool.new()
		branch_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		_surfaces[id] = branch_tool
	var tool: SurfaceTool = _surfaces[id]
	for tri in [[0, 1, 2], [0, 2, 3]]:
		var order: Array = tri.duplicate()
		var a: Vector3 = points[order[0]]
		var b: Vector3 = points[order[1]]
		var c: Vector3 = points[order[2]]
		# Godot: face da frente em sentido horário, (b-a)x(c-a) aponta contra a normal.
		if (b - a).cross(c - a).dot(normal) > 0.0: order = [order[0], order[2], order[1]]
		for index in order:
			tool.set_normal(normal)
			tool.set_uv(uvs[index])
			tool.add_vertex(points[index])

## Trechos do piso com inclinação constante, do túnel inteiro: [xa, ya, xb, yb].
static func floor_runs() -> Array:
	var runs: Array = []
	var marks: Array[float] = [W_TOP, W_TOP + CURVE, W_TOP + ramp_length() - CURVE, W_TOP + ramp_length(), E_TOP - ramp_length(), E_TOP - ramp_length() + CURVE, E_TOP - CURVE, E_TOP]
	var x := W_TOP
	while x < E_TOP - 0.001:
		var next := E_TOP
		for mark in marks:
			if mark > x + 0.001: next = minf(next, mark); break
		# Curvas verticais em fatias de 1 m; retas e fundo plano numa peça só.
		var in_curve := (x < W_TOP + CURVE) or (x >= W_TOP + ramp_length() - CURVE - 0.001 and x < W_TOP + ramp_length()) or (x >= E_TOP - ramp_length() - 0.001 and x < E_TOP - ramp_length() + CURVE) or (x >= E_TOP - CURVE - 0.001)
		if in_curve: next = minf(next, x + 1.0)
		runs.append([x, floor_y(x), next, floor_y(next)])
		x = next
	return runs

## Colisão do piso. Cada chunk põe as peças INTEIRAS que tocam a sua fatia (vizinhos
## repetem a mesma caixa, coincidente): emenda de caixa no meio de um trecho reto é
## "aresta fantasma" para a caixa do carro (GodotPhysics) — travava em x=256, divisa
## de chunk, e no trimesh travava em x=322,7 (aresta interna).
func _flush_floor(x0: float, x1: float) -> void:
	var depth := 0.5
	var width := inner_south() - inner_north()
	var runs := floor_runs()
	for index in runs.size():
		var run: Array = runs[index]
		if float(run[2]) < x0 or float(run[0]) > x1: continue
		var a := Vector2(float(run[0]), float(run[1]))
		var b := Vector2(float(run[2]), float(run[3]))
		# Emenda CÔNCAVA (fundo das rampas: a inclinação aumenta no sentido +x):
		# as caixas avançam 25 cm uma sob a outra, e as faces se cruzam em vez de
		# se encontrarem numa aresta exposta. A quina da caixa do carro enroscava
		# nessa aresta (normal (−1, 0,08) no pé da rampa leste, x≈279) e o trânsito
		# parava ali às vezes. Na emenda convexa avançar criaria um calombo.
		var slope := (b.y - a.y) / (b.x - a.x)
		if index > 0:
			var previous: Array = runs[index - 1]
			if slope > (float(previous[3]) - float(previous[1])) / (float(previous[2]) - float(previous[0])) + 0.001:
				a -= (b - a).normalized() * 0.25
		if index + 1 < runs.size():
			var following: Array = runs[index + 1]
			if (float(following[3]) - float(following[1])) / (float(following[2]) - float(following[0])) > slope + 0.001:
				b += (b - a).normalized() * 0.25
		var along := (b - a).normalized()
		var normal := Vector2(-along.y, along.x)
		if normal.y < 0.0: normal = -normal
		var middle := (a + b) * 0.5 - normal * depth * 0.5
		var shape := BoxShape3D.new()
		shape.size = Vector3(a.distance_to(b), depth, width)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.transform = Transform3D(Basis(Vector3.BACK, atan2(along.y, along.x)), Vector3(middle.x, middle.y, CENTER_Z))
		_body.add_child(collider)

func _collision_wall(xa: float, xb: float, z: float, ya: float, yb: float, ta: float, tb: float) -> void:
	var a := Vector3(xa, ya - 0.5, z)
	var b := Vector3(xb, yb - 0.5, z)
	var c := Vector3(xb, tb, z)
	var d := Vector3(xa, ta, z)
	_wall_faces.append_array(PackedVector3Array([a, b, c, a, c, d]))

func _box(id: String, center: Vector3, size: Vector3) -> void:
	if not _batches.has(id): _batches[id] = []
	_batches[id].append(Transform3D(Basis.from_scale(size), center))

func _solid(center: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = center
	_body.add_child(collider)

func _flush() -> void:
	for id in _surfaces:
		var tool: SurfaceTool = _surfaces[id]
		var mesh := MeshInstance3D.new()
		mesh.name = "CanalTunnel_" + id
		mesh.mesh = tool.commit()
		mesh.material_override = material(id)
		if id in ["glass", "paint_white", "paint_yellow", "asphalt", "walkway", "kerb"]:
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root.add_child(mesh)
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	for id in _batches:
		var transforms: Array = _batches[id]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = cube
		multimesh.instance_count = transforms.size()
		for index in transforms.size(): multimesh.set_instance_transform(index, transforms[index])
		var instance := MultiMeshInstance3D.new()
		instance.name = "CanalTunnelBatch_" + id
		instance.multimesh = multimesh
		instance.material_override = material(id)
		if id in ["glass", "water", "water_depth", "seabed", "ceiling_lamp", "cat_eye", "neon_teal", "neon_orange", "roof_top", "hazard"]:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root.add_child(instance)
	_flush_floor(_x0, _x1)
	for faces in [_wall_faces]:
		if faces.is_empty(): continue
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		_body.add_child(collider)
	_surfaces.clear()
	_batches.clear()

static func material(id: String) -> Material:
	if _materials.has(id): return _materials[id]
	var result: Material
	match id:
		"water_depth":
			var water_shader := ShaderMaterial.new()
			water_shader.shader = WATER_DEPTH_SHADER
			result = water_shader
		"wall_north", "wall_south":
			var shader := ShaderMaterial.new()
			shader.shader = WALL_SHADER
			# Mão direita: faixa norte vai para oeste, faixa sul para leste.
			shader.set_shader_parameter("direction", -1.0 if id == "wall_north" else 1.0)
			result = shader
		"lamp_head": result = CITY.lamp_head()
		"neon_teal": result = CITY.neon(Color(0.2, 0.95, 1.0))
		"neon_orange": result = CITY.neon(Color(1.0, 0.55, 0.12))
		_:
			var mat := StandardMaterial3D.new()
			match id:
				"asphalt": mat.albedo_color = Color("2c2e30"); mat.roughness = 0.9
				"walkway": mat.albedo_color = Color("8d8b82")
				"kerb": mat.albedo_color = Color("c9b63c")
				"paint_white": mat.albedo_color = Color("e8e6dc"); mat.roughness = 0.6
				"paint_yellow": mat.albedo_color = Color("f0b72a"); mat.roughness = 0.6
				"roof_top": mat.albedo_color = Color("737b69")
				"ceiling": mat.albedo_color = Color("3b4043")
				"concrete": mat.albedo_color = Color("a9a59a")
				"concrete_dark": mat.albedo_color = Color("59605f")
				"cap": mat.albedo_color = Color("b9b4a7")
				"parapet": mat.albedo_color = Color("a8a397")
				"portal_paint": mat.albedo_color = Color("1f5d66"); mat.roughness = 0.55
				"steel", "canopy_steel", "lamp_pole": mat.albedo_color = Color("5b6468"); mat.metallic = 0.5; mat.roughness = 0.45
				"rail": mat.albedo_color = Color("7d8488"); mat.metallic = 0.4; mat.roughness = 0.5
				"rail_paint": mat.albedo_color = Color("d7a02c")
				"sign_board": mat.albedo_color = Color("0f2a33"); mat.roughness = 0.5
				"seabed": mat.albedo_color = Color("1d3334"); mat.roughness = 1.0
				"hazard":
					mat.albedo_texture = _hazard_texture()
					mat.uv1_triplanar = true
					mat.uv1_world_triplanar = true
					mat.uv1_scale = Vector3(0.6, 0.6, 0.6)
				"ceiling_lamp":
					mat.albedo_color = Color(0.95, 0.97, 1.0)
					mat.emission_enabled = true
					mat.emission = Color(0.9, 0.96, 1.0)
					mat.emission_energy_multiplier = 3.0
				"cat_eye":
					mat.albedo_color = Color(1.0, 0.7, 0.2)
					mat.emission_enabled = true
					mat.emission = Color(1.0, 0.62, 0.15)
					mat.emission_energy_multiplier = 2.2
				"glass":
					mat.albedo_color = Color(0.62, 0.9, 0.95, 0.1)
					mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					mat.cull_mode = BaseMaterial3D.CULL_DISABLED
					# Sem luz: o farol do próprio carro acendia o vidro e o apagava na câmera.
					mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				"water":
					# Janela de água limpa sobre o tubo: o mar opaco fica recortado aqui.
					# Fosca e sem especular: o farol do carro (e o sol) viravam um clarão que
					# escondia o carro; sem luz nenhuma ela brilhava turquesa à noite.
					mat.albedo_color = Color(0.03, 0.24, 0.28, 0.4)
					mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					mat.roughness = 1.0
					mat.metallic_specular = 0.0
			result = mat
	_materials[id] = result
	return result

static func _hazard_texture() -> ImageTexture:
	var image := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			# Whole-number grouping/index; preserve integer truncation and precision.
			@warning_ignore("integer_division")
			image.set_pixel(x, y, Color("e8b21e") if ((x + y) / 16) % 2 == 0 else Color("1b1b1b"))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
