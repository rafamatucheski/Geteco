extends SceneTree
## Cache de rotas de NativeTrafficRoutes.route_near (15/10): mesma aresta e faixa devolvem a
## mesma curva (bake, veredito do porto e cruzamentos pagos uma vez), e o cache some quando o
## grafo muda por configure() ou pela troca de dicionários de ProductionWorld._graph_restore.
## A curva compartilhada tem de ser idêntica à montada do zero.
const REGION := preload("res://world/editing/EditableRegion.gd")
const GRAPH := preload("res://gameplay/NativeTrafficRoutes.gd")
const POLICY := preload("res://gameplay/urban_v1/HarborPortPolicy.gd")
const JUNCTIONS := preload("res://gameplay/traffic_junctions/TrafficJunctions.gd")
const PRODUCTION := preload("res://runtime/ProductionWorld.gd")
var failures := 0
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _same_geometry(a: Curve3D, b: Curve3D) -> bool:
	if a.point_count != b.point_count or not is_equal_approx(a.get_baked_length(), b.get_baked_length()): return false
	for i in a.point_count:
		if not a.get_point_position(i).is_equal_approx(b.get_point_position(i)): return false
	return a.get_meta("traffic_nodes") == b.get_meta("traffic_nodes") and a.get_meta("traffic_open") == b.get_meta("traffic_open")

## Varredura original de HarborPortPolicy.route_is_ambient_safe (antes de 15/10), como referência.
func _legacy_safe(route: Curve3D) -> bool:
	var previous := route.sample_baked(0.0, true)
	if POLICY.contains_private_area(previous): return false
	var steps := maxi(1, ceili(route.get_baked_length() / 1.0))
	for index in range(1, steps + 1):
		var point := route.sample_baked(route.get_baked_length() * float(index) / float(steps), true)
		if POLICY.segment_enters_private_area(previous, point): return false
		previous = point
	return true

## Escolha original de route_near (varredura de todas as arestas), como referência.
func _legacy_selected(graph, point: Vector3, lane_index: int, heading: Vector3) -> Dictionary:
	var selected: Dictionary = {}
	var distance := INF
	for from in graph.edges:
		for edge in graph.edges[from]:
			var direction: Vector3 = (graph.vertices[edge.to] - graph.vertices[from]).normalized()
			if heading.length_squared() > .01 and direction.dot(heading.normalized()) < .5: continue
			var offset: Vector3 = graph._lane_offset(direction, edge, lane_index)
			var closest := Geometry3D.get_closest_point_to_segment(point, graph.vertices[from] + offset, graph.vertices[edge.to] + offset)
			var separation := closest.distance_squared_to(point)
			if separation < distance:
				distance = separation
				selected = edge
	return selected

func run() -> void:
	var region = REGION.build_region("harbor")
	region.prepare_data()
	var roads: Array = POLICY.ambient_roads(region.roads)
	var graph = GRAPH.new()
	graph.configure(roads)
	var probes := [Vector3(193.25, 0, 100), Vector3(110, 0, 143), Vector3(64, 0, 82), Vector3(150, 0, 82), Vector3(250, 0, 30)]
	var cached: Array[Curve3D] = []
	for point: Vector3 in probes:
		for lane in [0, 1]:
			var first: Curve3D = graph.route_near(point, lane)
			var second: Curve3D = graph.route_near(point, lane)
			check(first != null, "Rota existe perto de %s" % point)
			if first == null: continue
			check(first == second, "Mesma aresta/faixa devolve a mesma curva em %s faixa %d" % [point, lane])
			cached.append(first)
			# Referência sem cache: grafo novo, montado do zero.
			var fresh_graph = GRAPH.new()
			fresh_graph.configure(roads)
			var fresh: Curve3D = fresh_graph.route_near(point, lane)
			check(fresh != null and _same_geometry(first, fresh), "Curva do cache igual à montada do zero em %s" % point)
			# Veredito memorizado igual à varredura completa.
			var verdict: bool = POLICY.route_is_ambient_safe(first)
			check(first.has_meta("ambient_safe_verdict"), "Veredito do porto memorizado na rota compartilhada")
			check(verdict == _legacy_safe(first), "Veredito memorizado igual à varredura antiga")
	# Escolha de aresta indexada igual à varredura antiga, com e sem rumo, em todo o mapa;
	# e o veredito do porto igual nas rotas que passam perto do porto (envoltório não poda).
	var rng_pick := RandomNumberGenerator.new()
	rng_pick.seed = 77
	var pick_mismatch := 0
	var near_port := 0
	for sample in 400:
		var point := Vector3(rng_pick.randf_range(-350, 650), 0, rng_pick.randf_range(-350, 400))
		var lane := rng_pick.randi_range(0, 1)
		var heading := Vector3.ZERO if sample % 2 == 0 else Vector3(rng_pick.randf_range(-1, 1), 0, rng_pick.randf_range(-1, 1))
		var expected := _legacy_selected(graph, point, lane, heading)
		var curve: Curve3D = graph.route_near(point, lane, heading)
		var nodes: Array = curve.get_meta("traffic_nodes", []) if curve != null else []
		if expected.is_empty() != (curve == null): pick_mismatch += 1
		elif curve != null and (nodes.size() < 2 or int(nodes[0]) != int(expected.from) or int(nodes[1]) != int(expected.to)): pick_mismatch += 1
		if curve != null and POLICY._route_bounds(curve).intersects(POLICY._private_bounds()): near_port += 1
		if curve != null and POLICY.route_is_ambient_safe(curve) != _legacy_safe(curve): pick_mismatch += 1
	check(pick_mismatch == 0, "Aresta escolhida e veredito iguais aos antigos (%d divergências, %d rotas perto do porto)" % [pick_mismatch, near_port])
	# Grafo com as ruas do porto (não ambiente): o veredito tem de recusar as que entram nele.
	var full_graph = GRAPH.new()
	full_graph.configure(region.roads)
	var unsafe := 0
	var verdict_mismatch := 0
	for sample in 60:
		var point := Vector3(rng_pick.randf_range(150, 400), 0, rng_pick.randf_range(120, 400))
		var curve: Curve3D = full_graph.route_near(point, 0)
		if curve == null: continue
		var legacy := _legacy_safe(curve)
		if not legacy: unsafe += 1
		if POLICY.route_is_ambient_safe(curve) != legacy: verdict_mismatch += 1
	check(verdict_mismatch == 0 and unsafe > 0, "Veredito igual ao antigo também em rotas do porto (%d recusadas, %d divergências)" % [unsafe, verdict_mismatch])
	# Rota de fora do cache (sem traffic_nodes) nunca guarda veredito: pode ser alterada.
	var loose := Curve3D.new()
	loose.add_point(Vector3(80, 0, 80))
	loose.add_point(Vector3(120, 0, 80))
	check(POLICY.route_is_ambient_safe(loose) and not loose.has_meta("ambient_safe_verdict"), "Curva avulsa não memoriza veredito")
	# O porto continua barrado com casco/limites em cache.
	check(POLICY.contains_private_area(Vector3(4500, 0, 2900) / 16.0), "Casco do navio continua área privada")
	check(not POLICY.contains_private_area(Vector3(100, 0, 80)), "Rua pública continua livre")
	# configure() limpa o cache (o dicionário de arestas é reaproveitado no lugar).
	if not cached.is_empty():
		var before: Curve3D = graph.route_near(probes[0], 0)
		graph.configure(roads)
		var after: Curve3D = graph.route_near(probes[0], 0)
		check(before != after and _same_geometry(before, after), "configure() descarta curvas antigas")
		# Troca de dicionários (ProductionWorld._graph_restore) também descarta.
		var snapshot: Array = PRODUCTION._graph_snapshot(graph)
		PRODUCTION._graph_restore(graph, snapshot)
		var restored: Curve3D = graph.route_near(probes[0], 0)
		check(restored != after and _same_geometry(restored, after), "_graph_restore descarta curvas antigas")
	# Limite do cache.
	var many := 0
	for x in range(-300, 600, 20):
		for z in range(-300, 300, 20):
			if graph.route_near(Vector3(x, 0, z), 0) != null: many += 1
	check(graph._route_cache.size() <= GRAPH.ROUTE_CACHE_LIMIT and graph._route_cache.size() == graph._route_cache_order.size(), "Cache respeita o limite (%d consultas)" % many)
	# Cruzamentos ao longo da rota: memorizados por geração, iguais ao cálculo direto.
	var geometry = preload("res://world/urban_detail/HarborRoadGeometry3D.gd").new()
	geometry.configure(region.roads, false)
	JUNCTIONS.configure(graph, geometry.crossing_layout)
	var route: Curve3D = graph.route_near(Vector3(193.25, 0, 100), 1)
	if route != null:
		var listed: Array = JUNCTIONS.along(route)
		check(JUNCTIONS.along(route) == listed and listed == JUNCTIONS._along(route), "Cruzamentos memorizados iguais ao cálculo direto")
		check(not listed.is_empty(), "Rota de teste cruza ao menos um cruzamento")
		JUNCTIONS.configure(graph, geometry.crossing_layout)
		var regenerated: Array = JUNCTIONS.along(route)
		check(not is_same(regenerated, listed) and regenerated == listed, "Nova geração recalcula os cruzamentos")
	# Grade de _on_carriageway: mesmo resultado da varredura de todos os trechos.
	var grid: Dictionary = PRODUCTION.carriageway_grid(region.roads)
	var mismatches := 0
	var inside := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 1510
	for sample in 20000:
		var point := Vector3(rng.randf_range(-350, 650), 0, rng.randf_range(-350, 350))
		var brute := false
		for road in region.roads:
			var points: PackedVector3Array = road.points
			var half := float(road.width) * .5 + .3
			for i in range(points.size() - 1):
				var nearest := Geometry2D.get_closest_point_to_segment(Vector2(point.x, point.z), Vector2(points[i].x, points[i].z), Vector2(points[i + 1].x, points[i + 1].z))
				if Vector2(point.x, point.z).distance_to(nearest) < half: brute = true
		if brute: inside += 1
		if brute != PRODUCTION.grid_on_carriageway(grid, point): mismatches += 1
	check(mismatches == 0 and inside > 100, "Grade de pista igual à varredura completa (%d na pista, %d divergências)" % [inside, mismatches])
	print("TRAFFIC_ROUTE_CACHE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
