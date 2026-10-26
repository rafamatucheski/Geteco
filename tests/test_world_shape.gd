extends SceneTree
## Contratos da forma do mundo orgânico (etapa 0 do plano de 26/10/2026): as curvas de
## world/shape/world_shape.json cabem em volta de tudo que é jogável sem mover nada. Monta Harbor, serra
## e deserto só como dados (mesmo caminho da captura do mapa-múndi), sem Main.
## Grava as violações em evidence/world-shape/violations.json para a prévia marcar em vermelho.
## Uso: "$GODOT" --headless --path . --script res://tests/test_world_shape.gd -- --no-save
const SHAPE := preload("res://world/shape/WorldShape.gd")
const DATA := preload("res://ui/hud/WorldMapData.gd")
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const EDITABLE := preload("res://world/editing/EditableRegion.gd")
const STATE := preload("res://runtime/GameState.gd")
const DESERT := preload("res://world/desert/DesertLayout.gd")
const GATE := preload("res://world/north_gateway/NorthGatewayLayout.gd")
const CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
## Folgas mínimas até a costa, em metros.
const ROAD_MARGIN := 3.0
const MARKER_MARGIN := 8.0
const BUILDING_MARGIN := 2.0
const HARBOR_LAND_MARGIN := 2.0
## Desde a etapa 2 a área jogável do deserto inteira é terra, com folga para o selo de pedra da borda
## (ScenarioBoundary3D) e o chão retangular do deserto não ficarem por cima do mar.
const DESERT_SEAL_MARGIN := 6.0
const MIN_STRAIT := 40.0
const MOUNTAIN_CLEAR := 14.0
## Estradas que podem passar sobre a água: as pontes. Ferrovia é elevada e cruza os canais.
const SPAN_SURFACES := ["railway", "cable"]

class Production extends RefCounted:
	var regions := {}
	var _region_cache := {}

class World extends Node3D:
	var production := Production.new()
	var maciota_place: Node3D
	var player: Node3D

var checks := 0
var failures: Array[String] = []
var violations: Array[Dictionary] = []

func _initialize() -> void:
	create_timer(240).timeout.connect(func(): failures.append("watchdog"); finish())
	run.call_deferred()

func check(value: bool, label: String) -> bool:
	checks += 1
	print("WORLD_SHAPE ", "PASS " if value else "FAIL ", label)
	if not value: failures.append(label)
	return value

func violate(point: Vector2, what: String) -> void:
	if violations.size() < 400: violations.append({"x": point.x, "z": point.y, "what": what})

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): check(false, "--no-save obrigatório"); finish(); return
	var islands := SHAPE.islands()
	var ids: Array = islands.map(func(island): return island.id)
	check(ids.has("harbor") and ids.has("desert") and ids.has("mountain"), "três ilhas: Harbor, deserto e serra (%s)" % [ids])
	for island in islands:
		var polygon: PackedVector2Array = island.polygon
		check(not Geometry2D.triangulate_polygon(polygon).is_empty(), "%s é um polígono simples (%d vértices)" % [island.id, polygon.size()])
		var kinds_ok := true
		for run_ in island.coast: kinds_ok = kinds_ok and str(run_[1]) in SHAPE.KINDS
		check(kinds_ok and not island.coast.is_empty() and int(island.coast[0][0]) == 0, "%s: todo trecho de costa tem tipo" % island.id)
	# Canais: nenhuma ilha encosta na outra.
	for a in islands.size():
		for b in range(a + 1, islands.size()):
			var gap := _polygon_gap(islands[a].polygon, islands[b].polygon)
			check(gap >= MIN_STRAIT, "canal entre %s e %s tem %.0f m (mínimo %.0f)" % [islands[a].id, islands[b].id, gap, MIN_STRAIT])

	var world := World.new()
	root.add_child(world)
	world.player = Node3D.new()
	world.add_child(world.player)
	var state := STATE.new()
	state.restore_snapshot(FIXTURE.full_snapshot(Vector3(80, .12, 80), true))
	for id: String in ["harbor", "mountain", "desert"]:
		var region = EDITABLE.build_region(id)
		region.prepare_data()
		world.production._region_cache[id] = region
	var atlas := DATA.new()
	atlas.collect({"state": state, "world": world, "region": world.production._region_cache.harbor}, false)

	# Terra de Harbor de hoje (retângulos da V1 e terra extra): toda dentro, para a etapa 3 não perder chão.
	var harbor = world.production._region_cache.harbor
	var lost := 0
	for row in harbor.source_data.harbor_land:
		var rect := Rect2(row[0] / 16.0, row[1] / 16.0, row[2] / 16.0, row[3] / 16.0)
		for corner in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
			if SHAPE.signed_distance(corner) < HARBOR_LAND_MARGIN: lost += 1; violate(corner, "terra de Harbor")
	for polygon in harbor.extra_land:
		for point in polygon:
			if SHAPE.signed_distance(point) < HARBOR_LAND_MARGIN: lost += 1; violate(point, "terra extra de Harbor")
	check(lost == 0, "toda a terra de Harbor de hoje fica em terra (%d cantos fora)" % lost)

	# Deserto: a borda inteira da área jogável fica em terra, com folga para o selo.
	var inner: Rect2 = DESERT.BOUNDS
	var desert_wet := 0
	var x := inner.position.x
	while x <= inner.end.x:
		for z in [inner.position.y, inner.end.y]:
			if SHAPE.island_at(Vector2(x, z)) != "desert" or SHAPE.signed_distance(Vector2(x, z)) < DESERT_SEAL_MARGIN: desert_wet += 1; violate(Vector2(x, z), "área jogável do deserto")
		x += 40.0
	var z2 := inner.position.y
	while z2 <= inner.end.y:
		for x2 in [inner.position.x, inner.end.x]:
			if SHAPE.island_at(Vector2(x2, z2)) != "desert" or SHAPE.signed_distance(Vector2(x2, z2)) < DESERT_SEAL_MARGIN: desert_wet += 1; violate(Vector2(x2, z2), "área jogável do deserto")
		z2 += 40.0
	check(desert_wet == 0, "borda da área jogável do deserto a %.0f m da costa (%d pontos fora)" % [DESERT_SEAL_MARGIN, desert_wet])

	# Estradas: em terra com folga, a não ser as pontes, que precisam mesmo passar sobre a água.
	var wet_roads := {}
	var tight := 0
	for road in atlas.roads:
		if str(road.surface) in SPAN_SURFACES: continue
		var points: PackedVector2Array = road.points
		var wet := 0
		for i in points.size() - 1:
			var length := points[i].distance_to(points[i + 1])
			var steps := maxi(1, ceili(length / 4.0))
			for s in steps:
				var p := points[i].lerp(points[i + 1], float(s) / steps)
				var d := SHAPE.signed_distance(p)
				if d < 0.0: wet += 1
				elif d < ROAD_MARGIN and not _is_bridge(road): tight += 1; violate(p, "estrada colada na costa")
		if wet > 0: wet_roads[str(road.id) if not str(road.id).is_empty() else "%s:%s" % [road.region, road.surface]] = wet
	print("WORLD_SHAPE estradas sobre a água: ", wet_roads)
	check(tight == 0, "estradas em terra ficam a %.0f m da costa (%d pontos colados)" % [ROAD_MARGIN, tight])
	var bridge_ids := _bridge_ids()
	var unexpected := wet_roads.keys().filter(func(id): return id not in bridge_ids)
	for road in atlas.roads:
		var key := str(road.id) if not str(road.id).is_empty() else "%s:%s" % [road.region, road.surface]
		if key in unexpected:
			for p in road.points: if not SHAPE.is_land(p): violate(p, "estrada no mar: " + key)
	check(unexpected.is_empty(), "só as pontes passam sobre a água (fora da lista: %s)" % [unexpected])

	# Pontes de verdade: a do norte (Harbor → deserto) e a do leste (Harbor → serra) cruzam água.
	var gate_wet := false
	for p in GATE.centerline(): gate_wet = gate_wet or not SHAPE.is_land(Vector2(p.x, p.z))
	check(gate_wet, "ponte norte cruza o canal")
	var east := Vector2((CONNECTION.HARBOR_CONNECTOR_X + CONNECTION.SEAM.x) * .5, CONNECTION.CENTER_Z)
	check(not SHAPE.is_land(east), "ponte leste cruza o canal em %s" % east)

	# Serra (etapa 4): o muro de pedra acompanha a costa 5 m para dentro, com 10 m de largura; trilhas,
	# estradas e lugares da serra (fora a ponte) ficam a MOUNTAIN_CLEAR m da costa para ele caber.
	var close_mountain := 0
	for road in atlas.roads:
		if str(road.region) != "mountain" or _is_bridge(road): continue
		for p in road.points:
			if SHAPE.signed_distance(p) < MOUNTAIN_CLEAR: close_mountain += 1; violate(p, "serra: trilha perto do muro")
	for marker in atlas.markers:
		if str(marker.region) == "mountain" and SHAPE.signed_distance(marker.point) < MOUNTAIN_CLEAR: close_mountain += 1; violate(marker.point, "serra: lugar perto do muro")
	check(close_mountain == 0, "trilhas, estradas e lugares da serra a %.0f m da costa (%d pontos perto)" % [MOUNTAIN_CLEAR, close_mountain])
	# Grade de distância da serra (lida pelo terreno em trabalhador) bate com a distância exata.
	var worst_field := 0.0
	for p in [Vector2(650, -500), Vector2(700, -800), Vector2(500, -400), Vector2(800, -300), Vector2(600, -200)]:
		worst_field = maxf(worst_field, absf(SHAPE.field_distance("mountain", p) - clampf(SHAPE.signed_distance(p), -80.0, 80.0)))
	check(worst_field < 3.0, "grade de distância da serra bate com a distância exata (erro máximo %.2f m)" % worst_field)

	# Lugares e prédios em terra com folga.
	var bad_markers: Array = []
	for marker in atlas.markers:
		if SHAPE.signed_distance(marker.point) < MARKER_MARGIN: bad_markers.append(marker.title); violate(marker.point, "marcador: " + str(marker.title))
	check(bad_markers.is_empty(), "%d marcadores a %.0f m da costa (fora: %s)" % [atlas.markers.size(), MARKER_MARGIN, bad_markers])
	var bad_buildings := 0
	for building in atlas.buildings:
		for corner in building:
			if SHAPE.signed_distance(corner) < BUILDING_MARGIN: bad_buildings += 1; violate(corner, "prédio")
	check(bad_buildings == 0, "%d prédios em terra (%d cantos fora)" % [atlas.buildings.size(), bad_buildings])
	finish()

## Ids das estradas que são ponte. Ponte leste: as duas pistas de Harbor e a metade da serra
## (mountain_pass sai da cabeceira sobre o mar). Ponte norte: entra no mapa sem id (WorldMapData.collect).
func _bridge_ids() -> Array:
	var ids: Array = ["mountain_bridge_outbound", "mountain_bridge_inbound", "mountain_pass", "harbor:asphalt"]
	for source in CONNECTION.traffic_connectors(): ids.append(str(source.id))
	return ids

func _is_bridge(road: Dictionary) -> bool:
	var key := str(road.id) if not str(road.id).is_empty() else "%s:%s" % [road.region, road.surface]
	return key in _bridge_ids()

static func _polygon_gap(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var best := INF
	for p in a:
		for i in b.size(): best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, b[i], b[(i + 1) % b.size()])))
	for p in b:
		for i in a.size(): best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a[i], a[(i + 1) % a.size()])))
	return best

func finish() -> void:
	var folder := ProjectSettings.globalize_path("res://evidence/world-shape")
	DirAccess.make_dir_recursive_absolute(folder)
	var file := FileAccess.open(folder.path_join("violations.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(violations))
		file.close()
	print("WORLD_SHAPE checks=%d failures=%s violações=%d" % [checks, failures, violations.size()])
	quit(0 if failures.is_empty() else 1)
