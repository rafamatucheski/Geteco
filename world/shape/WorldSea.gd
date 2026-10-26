extends Node3D
## Mar do mundo orgânico (plano de 26/10/2026, etapa 1): um mar persistente em volta de todas as ilhas e
## um chão-base dentro delas, montados uma vez sob a cortina a partir da forma do mundo (WorldShape).
##
## - A água fica 0,2 m abaixo da água de Harbor e do mar do mirante (mesmo shader, sem onda nos
##   vértices), então perto do jogador quem aparece é a água de sempre; longe, onde nenhuma região montou
##   nada, aparece esta. A faixa rasa perto da costa usa a mesma distância até a margem (COLOR.r).
## - O deserto e a serra usam as curvas da forma. Harbor continua com a terra de hoje (retângulos da V1 e
##   terra extra) até a etapa 3: com a curva, longe veria praia onde perto ainda é água.
## - O chão-base (a −0,3 m) cobre as ilhas para a vista de longe. Onde alguma região tem chão próprio
##   (o retângulo jogável do deserto, a terra de Harbor, a serra) ele se esconde nas células que a região
##   já montou em volta do jogador, para não aparecer piso falso em bueiro, túnel ou cava. A faixa nova
##   entre o retângulo do deserto e a costa não tem chão de região: fica sempre à vista (etapa 2).
## GETECO_WORLD_SEA=0 desliga (A/B no mesmo export).
const SHAPE := preload("res://world/shape/WorldShape.gd")
const OCEAN := preload("res://world/regions/HarborOcean.gd")
const GROUND_CUT := preload("res://world/urban_detail/GroundCut.gd")
const CANAL := preload("res://world/urban_detail/CanalTunnel3D.gd")
const SKATE := preload("res://activities/skate/SkateParkLayout.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const MINING := preload("res://world/mining/MiningExterior.gd")
const SMUGGLER := preload("res://world/desert/canyon/DesertSmugglerLayout.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const DESERT_LAYOUT := preload("res://world/desert/DesertLayout.gd")
## Mesmo alcance do mar do mirante: passa do plano de corte em todas as direções.
const EXTENT := 8192.0
## Células do chão-base (escondidas por residência) e blocos da água.
const BLOCK := 128.0
const WATER_BLOCK := 1024.0
## Perto da costa a célula vira 16 m (até 4 m nos recortes) para a faixa rasa e o contorno.
const FINE := 16.0
const MIN_CUT := 4.0
const COAST_REACH := 48.0
const WATER_DROP := 0.2
const BASE_Y := -0.3
const COAST_BAND := 20.0
const COAST_COLORS := {"quay": Color("8c8d88"), "beach": Color("d9c49a"), "cliff": Color("8f6b4c"), "rock": Color("7a8382")}
const INTERIOR := {"harbor": Color("6e746f"), "woodland": Color("52683f"), "desert": Color("c9a26a"), "mountain": Color("b9c3c6")}
const BUDGET_USEC := 5000
static var _enabled := -1

static func enabled() -> bool:
	if _enabled < 0: _enabled = 0 if OS.get_environment("GETECO_WORLD_SEA") == "0" else 1
	return _enabled == 1

## {id, polygon, kind}: terra seca para a água (ilhas da forma, terra de Harbor de hoje e recortes).
var dry: Array[Dictionary] = []
## {id, polygon, interior}: terra com chão-base.
var lands: Array[Dictionary] = []
## Trechos rebaixados do chão-base: {polygon, bounds, y, color}. Em vez de buraco (que de longe aparecia
## como retângulo preto), a cava e o cânion viram fundo escuro, os lagos e o canal viram água parada.
## Ficam nos blocos do chão-base, que se escondem perto do jogador, onde a geometria de verdade existe.
var sunk: Array[Dictionary] = []
## Bordas de costa com tipo, para a cor do chão-base: [a, b, tipo].
var coast_edges: Array = []
## Chave Vector2i (BLOCK) -> MeshInstance3D do chão-base.
var base_tiles: Dictionary = {}
var water_material: ShaderMaterial
var base_material: StandardMaterial3D
var production: Node
var _dry_bounds := Rect2()
var _clock := 0.0
var build_usec := 0

func configure(owner_production: Node) -> void:
	production = owner_production
	name = "WorldSea"

## Monta tudo em fatias de ~5 ms (chamar sob a cortina) e devolve quando terminar.
func build_sliced(tree: SceneTree) -> void:
	var began := Time.get_ticks_usec()
	_collect_geography()
	water_material = ShaderMaterial.new()
	water_material.shader = preload("res://world/regions/harbor_ocean.gdshader")
	base_material = StandardMaterial3D.new()
	base_material.vertex_color_use_as_albedo = true
	base_material.vertex_color_is_srgb = true
	base_material.roughness = 1.0
	var slice := Time.get_ticks_usec()
	var water: Dictionary = {}
	var cells := int(EXTENT * 2.0 / BLOCK)
	for bz in cells:
		for bx in cells:
			var rect := Rect2(Vector2(bx, bz) * BLOCK - Vector2.ONE * EXTENT, Vector2.ONE * BLOCK)
			var key := Vector2i(floori(rect.position.x / WATER_BLOCK), floori(rect.position.y / WATER_BLOCK))
			if not water.has(key): water[key] = _buffer()
			_block(rect, water[key])
			if Time.get_ticks_usec() - slice > BUDGET_USEC:
				await tree.process_frame
				slice = Time.get_ticks_usec()
	var t := STALL_WORK.begin()
	for key in water:
		var mesh := _commit(water[key], water_material, "Water_%d_%d" % [key.x, key.y])
		if mesh != null: add_child(mesh)
	STALL_WORK.finish("world_sea.commit", t)
	build_usec = Time.get_ticks_usec() - began

## Sob a cortina: desenha por alguns quadros um pedaço da água e do chão-base na frente da câmera, para
## o material do chão-base (cor por vértice) não compilar no jogo na primeira vista de longe. Mesma
## receita do ForgePrewarm.
func prewarm(host: Node3D, curtain: CanvasLayer) -> void:
	const GUARDS := preload("res://gameplay/emergency/EffectsPrewarm.gd")
	if DisplayServer.get_name() == "headless" or "--no-prewarm" in OS.get_cmdline_user_args(): return
	if not GUARDS._covered_loading(host, curtain): return
	var camera := host.get("camera") as Camera3D
	if not GUARDS._current_camera(host, camera): return
	var stage := Node3D.new()
	stage.name = "WorldSeaPrewarm"
	host.add_child(stage)
	for i in 2:
		var buffer := _buffer()
		_polygon(buffer, GROUND_CUT.rect_polygon(Rect2(Vector2(i * 1.2, 0), Vector2.ONE)), i == 0, [], "desert", OCEAN.DEPTH_RANGE if i == 0 else -1.0)
		var piece := _commit(buffer, water_material if i == 0 else base_material, "Piece")
		if piece != null: stage.add_child(piece)
	var draws: Array[int] = [0]
	var count_draw := func() -> void: draws[0] += 1
	RenderingServer.frame_post_draw.connect(count_draw)
	for frame in 24:
		stage.global_transform = Transform3D(camera.global_basis, camera.global_position - camera.global_basis.z * 6.0)
		await host.get_tree().process_frame
		if not GUARDS._covered_loading(host, curtain) or not is_instance_valid(stage) or draws[0] >= 3: break
	if RenderingServer.frame_post_draw.is_connected(count_draw): RenderingServer.frame_post_draw.disconnect(count_draw)
	if is_instance_valid(stage): stage.free()

func _process(delta: float) -> void:
	_clock += delta
	if _clock < .25: return
	_clock = 0.0
	refresh_residency()

## Esconde o chão-base onde a região montada já tem chão: o quadrado de 3 × 3 células em volta do foco.
func refresh_residency() -> void:
	var squares: Array[Rect2] = []
	if is_instance_valid(production):
		for region in production.get("regions").values():
			if not is_instance_valid(region) or not region.is_inside_tree(): continue
			var cell_size: float = region.CELL if region.has_method("set_focus") else 64.0
			var focus: Vector3 = region.get("focus") if region.get("focus") is Vector3 else Vector3.INF
			if not focus.is_finite(): continue
			var cell := Vector2(floorf(focus.x / cell_size), floorf(focus.z / cell_size))
			squares.append(Rect2((cell - Vector2.ONE) * cell_size, Vector2.ONE * cell_size * 3.0))
	for key: Vector2i in base_tiles:
		var tile: MeshInstance3D = base_tiles[key]
		var rect := Rect2(Vector2(key) * BLOCK, Vector2.ONE * BLOCK)
		var covered := squares.any(func(square: Rect2) -> bool: return square.encloses(rect))
		if tile.visible == covered: tile.visible = not covered

# --- Geografia ----------------------------------------------------------------------------------

func _collect_geography() -> void:
	for island in SHAPE.islands():
		if str(island.id).begins_with("harbor"): continue
		var region := "desert" if str(island.id).begins_with("desert") else "mountain"
		dry.append({"id": island.id, "polygon": island.polygon, "bounds": island.bounds})
		lands.append({"id": island.id, "polygon": island.polygon, "bounds": island.bounds, "interior": region})
		var polygon: PackedVector2Array = island.polygon
		for i in polygon.size(): coast_edges.append([polygon[i], polygon[(i + 1) % polygon.size()], SHAPE.kind_at(island, i)])
	for polygon in _harbor_land():
		var woodland: bool = polygon == preload("res://world/places/fishing/FishingRuralLayout.gd").outline()
		var bounds := GROUND_CUT.bounds(polygon)
		dry.append({"id": "harbor", "polygon": polygon, "bounds": bounds})
		lands.append({"id": "harbor", "polygon": polygon, "bounds": bounds, "interior": "woodland" if woodland else "harbor"})
		for i in polygon.size(): coast_edges.append([polygon[i], polygon[(i + 1) % polygon.size()], "quay"])
	# Mesmos recortes do mar de Harbor e do mar do mirante: nenhuma água por cima do túnel, da pista de
	# skate, do porão secreto ou das bocas de bueiro.
	var cuts: Array[Rect2] = [CANAL.WATER_CUT, Rect2(-413.25, 85.35, 6.10, 3.30)]
	if SKATE.enabled(): cuts.append(SKATE.FOOTPRINT)
	for opening in PLACES.sewer_openings(): cuts.append(Rect2(opening.position / 16.0, opening.size / 16.0))
	for cut in cuts: dry.append({"id": "cut", "polygon": GROUND_CUT.rect_polygon(cut), "bounds": cut})
	# Logo abaixo do fundo de verdade (cava 28 m, cânion 21,6 m): sem paredes, um fundo mais fundo deixava
	# uma fresta preta na borda com a câmera inclinada.
	_sink(GROUND_CUT.rect_polygon(MINING.OWNED_GROUND), -preload("res://world/mining/MiningLayout.gd").PIT_DEPTH - .3, Color("5e4632"))
	if SMUGGLER.enabled(): _sink(GROUND_CUT.rect_polygon(SMUGGLER.BOUNDS), -SMUGGLER.DEPTH - .3, Color("5e4632"))
	for cut in cuts: _sink(GROUND_CUT.rect_polygon(cut), -1.3, Color("1e4f5c"))
	for lake in _lakes(): _sink(lake, -1.3, Color("2c6a74"))
	_dry_bounds = dry[0].bounds
	for d in dry: _dry_bounds = _dry_bounds.merge(d.bounds)
	_dry_bounds = _dry_bounds.grow(COAST_REACH)

func _sink(polygon: PackedVector2Array, y: float, color: Color) -> void:
	sunk.append({"polygon": polygon, "bounds": GROUND_CUT.bounds(polygon), "y": y, "color": color})

## Terra de Harbor de hoje, igual à do HarborOcean: retângulos da V1 e terra extra (porto sul e mata).
static func _harbor_land() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://world/regions/OriginalWorldData.json"))
	if not data is Dictionary: return result
	for row in data.harbor_land:
		result.append(GROUND_CUT.rect_polygon(Rect2(float(row[0]) / 16.0, float(row[1]) / 16.0, float(row[2]) / 16.0, float(row[3]) / 16.0)))
	for polygon in preload("res://world/regions/OriginalSouthPort.gd").extra_surfaces(data.harbor_land):
		var metric := PackedVector2Array()
		for point in polygon: metric.append(point / 16.0)
		result.append(metric)
	result.append_array(preload("res://world/places/fishing/FishingRuralLayout.gd").extra_surfaces())
	return result

## Margens dos lagos da serra (mesma leitura do WorldMapData).
static func _lakes() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var lakes: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://world/regions/OriginalLakeData.json"))
	if not lakes is Dictionary: return result
	for key in lakes:
		var polygon := PackedVector2Array()
		for p in lakes[key].get("lake_shore", lakes[key].get("shallow", [])):
			var point := Vector2(p[0], p[1])
			if key == "secret": point += Vector2(5450, -1150)
			var world: Vector3 = PLACES._at(point, "mountain")
			polygon.append(Vector2(world.x, world.z))
		if polygon.size() > 2: result.append(polygon)
	return result

# --- Malha ----------------------------------------------------------------------------------------

func _block(rect: Rect2, water: Dictionary) -> void:
	if not _dry_bounds.intersects(rect):
		_quad(water, rect, OCEAN.DEPTH_RANGE, true)
		return
	var near_dry: Array[Dictionary] = dry.filter(func(d: Dictionary) -> bool: return (d.bounds as Rect2).grow(COAST_REACH).intersects(rect))
	if near_dry.is_empty():
		_quad(water, rect, OCEAN.DEPTH_RANGE, true)
		return
	var near_lands: Array[Dictionary] = lands.filter(func(l: Dictionary) -> bool: return (l.bounds as Rect2).intersects(rect))
	var near_sunk: Array[Dictionary] = sunk.filter(func(k: Dictionary) -> bool: return (k.bounds as Rect2).intersects(rect))
	var edges := _edges_near(rect.grow(OCEAN.DEPTH_RANGE + COAST_BAND))
	var crossing := _edges_near(rect)
	var base := _buffer()
	var ring := _buffer()
	var steps := int(BLOCK / FINE)
	for z in steps:
		for x in steps:
			var cell := Rect2(rect.position + Vector2(x, z) * FINE, Vector2.ONE * FINE)
			var crossed := crossing.any(func(e: Array) -> bool: return cell.intersects(Rect2(e[0], Vector2.ZERO).expand(e[1]), true))
			_water_cell(cell, near_dry, edges, crossed, water)
			var cell_sunk: Array[Dictionary] = near_sunk.filter(func(k: Dictionary) -> bool: return (k.bounds as Rect2).intersects(cell))
			for land in near_lands:
				if (land.bounds as Rect2).intersects(cell): _base_cell(cell, land, edges, crossed, cell_sunk, base, ring)
			for k in cell_sunk:
				for piece in Geometry2D.intersect_polygons(GROUND_CUT.rect_polygon(cell), k.polygon):
					if not Geometry2D.is_polygon_clockwise(piece): _flat(base, piece, k.y, k.color)
	var key := Vector2i(floori(rect.position.x / BLOCK), floori(rect.position.y / BLOCK))
	var ring_mesh := _commit(ring, base_material, "Ring_%d_%d" % [key.x, key.y])
	if ring_mesh != null: add_child(ring_mesh)
	if not base.indices.is_empty():
		var mesh := _commit(base, base_material, "Base_%d_%d" % [key.x, key.y])
		if mesh != null:
			add_child(mesh)
			base_tiles[key] = mesh

## Célula sem costa atravessando é toda terra ou toda mar: basta o centro. Só a beira passa pelo recorte.
func _water_cell(cell: Rect2, near_dry: Array[Dictionary], edges: Array, crossed: bool, water: Dictionary) -> void:
	var cover: Array[PackedVector2Array] = []
	var cut := false
	for d in near_dry:
		if not (d.bounds as Rect2).intersects(cell): continue
		cover.append(d.polygon)
		if d.id == "cut": cut = true
	if cover.is_empty():
		_quad(water, cell, -1.0, true, edges)
		return
	if not crossed and not cut:
		var center := cell.get_center()
		if cover.any(func(polygon: PackedVector2Array) -> bool: return Geometry2D.is_point_in_polygon(center, polygon)): return
		_quad(water, cell, -1.0, true, edges)
		return
	for piece in _subtract(GROUND_CUT.rect_polygon(cell), cover, cell.size.x):
		_polygon(water, piece, true, edges, "")

func _base_cell(cell: Rect2, land: Dictionary, edges: Array, crossed: bool, cell_sunk: Array[Dictionary], base: Dictionary, ring: Dictionary) -> void:
	var cuts: Array[PackedVector2Array] = []
	for k in cell_sunk: cuts.append(k.polygon)
	var pieces: Array[PackedVector2Array] = []
	if not crossed:
		if not Geometry2D.is_point_in_polygon(cell.get_center(), land.polygon): return
		pieces.append(GROUND_CUT.rect_polygon(cell))
	else:
		for piece in Geometry2D.intersect_polygons(GROUND_CUT.rect_polygon(cell), land.polygon):
			if not Geometry2D.is_polygon_clockwise(piece): pieces.append(piece)
	for piece in pieces:
		var parts: Array[PackedVector2Array] = []
		if cuts.is_empty(): parts.append(piece)
		else: parts = _subtract(piece, cuts, cell.size.x)
		for part in parts:
			if str(land.interior) != "desert":
				_polygon(base, part, false, edges, str(land.interior))
				continue
			# Deserto: dentro do retângulo jogável há chão de região (esconde por residência); fora, não.
			var play := GROUND_CUT.rect_polygon(DESERT_LAYOUT.BOUNDS)
			for inside in Geometry2D.intersect_polygons(part, play):
				if not Geometry2D.is_polygon_clockwise(inside): _polygon(base, inside, false, edges, "desert")
			for outside in Geometry2D.clip_polygons(part, play):
				if not Geometry2D.is_polygon_clockwise(outside): _polygon(ring, outside, false, edges, "desert")

## Peça plana de cor única (trechos rebaixados).
func _flat(buffer: Dictionary, polygon: PackedVector2Array, y: float, color: Color) -> void:
	var triangles := Geometry2D.triangulate_polygon(polygon)
	if triangles.is_empty(): return
	var offset: int = buffer.vertices.size()
	for point in polygon:
		buffer.vertices.append(Vector3(point.x, y, point.y))
		buffer.colors.append(color)
		buffer.uvs.append(point)
		buffer.normals.append(Vector3.UP)
	for index in triangles: buffer.indices.append(offset + index)

## Subtrai as coberturas; se o resultado tiver buraco (a cobertura caiu inteira dentro), divide a peça
## em quatro e tenta de novo, até MIN_CUT. Geometry2D.triangulate_polygon não aceita buraco.
func _subtract(piece: PackedVector2Array, cover: Array[PackedVector2Array], size: float) -> Array[PackedVector2Array]:
	var pieces: Array[PackedVector2Array] = [piece]
	for polygon in cover:
		var next: Array[PackedVector2Array] = []
		for current in pieces:
			var result := Geometry2D.clip_polygons(current, polygon)
			var hole := result.any(func(p: PackedVector2Array) -> bool: return Geometry2D.is_polygon_clockwise(p))
			if hole and size > MIN_CUT:
				var bounds := GROUND_CUT.bounds(current)
				var half := bounds.size * .5
				for q in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
					for quarter in Geometry2D.intersect_polygons(current, GROUND_CUT.rect_polygon(Rect2(bounds.position + half * q, half))):
						var single: Array[PackedVector2Array] = [polygon]
						if not Geometry2D.is_polygon_clockwise(quarter): next.append_array(_subtract(quarter, single, size * .5))
				continue
			for part in result:
				if not Geometry2D.is_polygon_clockwise(part): next.append(part)
		pieces = next
	return pieces

func _edges_near(area: Rect2) -> Array:
	return coast_edges.filter(func(e: Array) -> bool: return area.intersects(Rect2(e[0], Vector2.ZERO).expand(e[1]), true))

static func _nearest(point: Vector2, edges: Array) -> Array:
	var best := INF
	var kind := ""
	for e in edges:
		var d := point.distance_to(Geometry2D.get_closest_point_to_segment(point, e[0], e[1]))
		if d < best:
			best = d
			kind = e[2]
	return [best, kind]

func _vertex(buffer: Dictionary, point: Vector2, is_water: bool, edges: Array, interior: String, origin: Vector2) -> void:
	var nearest := _nearest(point, edges) if not edges.is_empty() else [INF, ""]
	var shore := minf(float(nearest[0]), OCEAN.DEPTH_RANGE)
	if is_water:
		buffer.vertices.append(Vector3(point.x, OCEAN.surface_y(point, shore) - WATER_DROP, point.y))
		buffer.colors.append(Color(shore / OCEAN.DEPTH_RANGE, 0, 0, 1))
	else:
		var inner: Color = INTERIOR.get(interior, INTERIOR.harbor)
		var edge: Color = COAST_COLORS.get(str(nearest[1]), inner)
		buffer.vertices.append(Vector3(point.x, BASE_Y, point.y))
		buffer.colors.append(edge.lerp(inner, smoothstep(0.0, COAST_BAND, float(nearest[0]))))
	buffer.uvs.append(point - origin)
	buffer.normals.append(Vector3.UP)

func _quad(buffer: Dictionary, rect: Rect2, shore: float, is_water: bool, edges: Array = []) -> void:
	_polygon(buffer, GROUND_CUT.rect_polygon(rect), is_water, edges, "", shore)

## UV local ao bloco de 256 m (PERIOD) que contém o polígono, como no HarborOcean: as ondas casam.
func _polygon(buffer: Dictionary, polygon: PackedVector2Array, is_water: bool, edges: Array, interior: String, fixed_shore := -1.0) -> void:
	var triangles := Geometry2D.triangulate_polygon(polygon)
	if triangles.is_empty(): return
	var origin := (GROUND_CUT.bounds(polygon).get_center() / OCEAN.PERIOD).floor() * OCEAN.PERIOD
	var offset: int = buffer.vertices.size()
	for point in polygon:
		if fixed_shore >= 0.0:
			buffer.vertices.append(Vector3(point.x, OCEAN.surface_y(point, fixed_shore) - WATER_DROP, point.y))
			buffer.colors.append(Color(fixed_shore / OCEAN.DEPTH_RANGE, 0, 0, 1))
			buffer.uvs.append(point - origin)
			buffer.normals.append(Vector3.UP)
		else: _vertex(buffer, point, is_water, edges, interior, origin)
	for index in triangles: buffer.indices.append(offset + index)

static func _buffer() -> Dictionary:
	return {"vertices": PackedVector3Array(), "normals": PackedVector3Array(), "colors": PackedColorArray(), "uvs": PackedVector2Array(), "indices": PackedInt32Array()}

static func _commit(buffer: Dictionary, material: Material, id: String) -> MeshInstance3D:
	if buffer.indices.is_empty(): return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = buffer.vertices
	arrays[Mesh.ARRAY_NORMAL] = buffer.normals
	arrays[Mesh.ARRAY_COLOR] = buffer.colors
	arrays[Mesh.ARRAY_TEX_UV] = buffer.uvs
	arrays[Mesh.ARRAY_INDEX] = buffer.indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance3D.new()
	node.name = id
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node
