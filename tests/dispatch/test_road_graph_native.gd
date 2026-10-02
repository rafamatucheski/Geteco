extends SceneTree
## Confere se o espelho em C# do DispatchRoadRouter (RoadGraphSearch.cs) devolve o MESMO que o
## GDScript: aresta mais próxima, bloqueios, rota completa e rota de saída. Também imprime o tempo
## médio de cada lado numa grade sintética, mas isso é só indicação: a medição de verdade é o
## rastro `router.plan:*` do despacho com o jogo renderizado.
## Precisa do build .NET do Godot e de `dotnet build Harbor.csproj`; sem isso sai com SKIP (código 0).

const ROUTES := preload("res://gameplay/NativeTrafficRoutes.gd")
const ROUTER := preload("res://gameplay/dispatch/DispatchRoadRouter.gd")

const GRID := 14
const BLOCK := 70.0
const QUERIES := 300

var failures := 0

func _init() -> void:
	if not ClassDB.class_exists(&"CSharpScript"):
		print("SKIP: este Godot não tem suporte a C# (use o build mono)")
		quit(0)
		return
	var script: Script = load("res://gameplay/dispatch/RoadGraphSearch.cs")
	if script == null or not script.can_instantiate():
		print("SKIP: RoadGraphSearch.cs não instancia (rode `dotnet build Harbor.csproj` e reabra)")
		quit(0)
		return
	var routes := ROUTES.new()
	routes.configure(_roads())
	print("grafo: %d vértices, %d vértices com saída" % [routes.vertices.size(), routes.edges.size()])
	var native := ROUTER.new()
	var reference := ROUTER.new()
	reference.use_native = false
	native.configure(routes)
	reference.configure(routes)
	_check(native._native_graph() != null, "o espelho C# foi criado")
	if failures > 0:
		_finish()
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = 20261001
	var extent := float(GRID - 1) * BLOCK
	var points: Array[Vector3] = []
	var headings: Array[Vector3] = []
	for index in QUERIES:
		# Inclui pontos fora do grafo para exercitar a varredura completa.
		var margin := 400.0 if index % 10 == 0 else 20.0
		points.append(Vector3(rng.randf_range(-margin, extent + margin), 0.0, rng.randf_range(-margin, extent + margin)))
		var heading := Vector3.ZERO
		if index % 3 != 0: heading = Vector3.RIGHT.rotated(Vector3.UP, rng.randf() * TAU)
		headings.append(heading)

	# Bloqueios em ambos os lados, com o mesmo relógio.
	for pair in range(0, 12):
		var from := rng.randi_range(0, routes.vertices.size() - 1)
		var edges: Array = routes.edges[from]
		if edges.is_empty(): continue
		var edge: Dictionary = edges[0]
		native.block_edge(edge.from, edge.to, 30.0)
		reference.block_edge(edge.from, edge.to, 30.0)

	var mismatched := 0
	for index in QUERIES:
		for skip in [false, true]:
			var a: Dictionary = reference.nearest_edge(points[index], skip, headings[index])
			var b: Dictionary = native.nearest_edge(points[index], skip, headings[index])
			if not _same_nearest(a, b):
				mismatched += 1
				if mismatched <= 5: print("nearest_edge diferente em ", points[index], " skip=", skip, " GD=", a, " C#=", b)
	_check(mismatched == 0, "nearest_edge igual em %d consultas (%d divergências)" % [QUERIES * 2, mismatched])

	mismatched = 0
	var planned := 0
	var failed_plans := 0
	for index in 120:
		var start := points[index]
		var goal := points[(index * 7 + 11) % QUERIES]
		var heading := headings[index]
		var a: Dictionary = reference.plan(start, goal, heading)
		var b: Dictionary = native.plan(start, goal, heading)
		if a.ok: planned += 1
		else: failed_plans += 1
		if not _same_plan(a, b):
			mismatched += 1
			if mismatched <= 5: print("plan diferente ", start, "->", goal, " GD=", a.get("reason", a.get("nodes")), " C#=", b.get("reason", b.get("nodes")))
	_check(mismatched == 0, "plan igual em 120 rotas (%d ok, %d sem rota, %d divergências)" % [planned, failed_plans, mismatched])
	_check(planned > 20, "a amostra tem rotas válidas suficientes (%d)" % planned)

	mismatched = 0
	for index in 40:
		var a: Dictionary = reference.plan_departure(points[index], points[(index + 5) % QUERIES], 150.0, headings[index])
		var b: Dictionary = native.plan_departure(points[index], points[(index + 5) % QUERIES], 150.0, headings[index])
		if not _same_plan(a, b): mismatched += 1
	_check(mismatched == 0, "plan_departure igual em 40 rotas (%d divergências)" % mismatched)

	# Bloqueio que expira: depois de 31 s o relógio libera a aresta nos dois lados.
	native.advance(31.0)
	reference.advance(31.0)
	mismatched = 0
	for index in 60:
		var a: Dictionary = reference.nearest_edge(points[index], true, headings[index])
		var b: Dictionary = native.nearest_edge(points[index], true, headings[index])
		if not _same_nearest(a, b): mismatched += 1
	_check(mismatched == 0, "bloqueios expirados liberam a aresta nos dois lados (%d divergências)" % mismatched)

	_time_report(reference, native, points, headings)
	_profile_plan(routes, native, points, headings)
	_finish()

func _same_nearest(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty(): return a.is_empty() and b.is_empty()
	return a.edge.from == b.edge.from and a.edge.to == b.edge.to \
		and (a.closest as Vector3).is_equal_approx(b.closest) and absf(float(a.distance) - float(b.distance)) < 0.0001

func _same_plan(a: Dictionary, b: Dictionary) -> bool:
	if bool(a.ok) != bool(b.ok): return false
	if not a.ok: return a.reason == b.reason
	if a.nodes != b.nodes or absf(float(a.length) - float(b.length)) > 0.001: return false
	# A curva refeita pelo C# tem de ter os mesmos pontos que a do GDScript.
	var curve_a: Curve3D = a.curve
	var curve_b: Curve3D = b.curve
	if curve_a.point_count != curve_b.point_count: return false
	for index in curve_a.point_count:
		if not curve_a.get_point_position(index).is_equal_approx(curve_b.get_point_position(index)): return false
	return true

func _time_report(reference: RefCounted, native: RefCounted, points: Array[Vector3], headings: Array[Vector3]) -> void:
	for router in [reference, native]:
		var label := "C#     " if router == native else "GDScript"
		var began := Time.get_ticks_usec()
		for index in QUERIES: router.nearest_edge(points[index], false, headings[index])
		var nearest_us := float(Time.get_ticks_usec() - began) / QUERIES
		began = Time.get_ticks_usec()
		for index in 80: router.plan(points[index], points[(index * 7 + 11) % QUERIES], headings[index])
		var plan_us := float(Time.get_ticks_usec() - began) / 80.0
		print("%s: nearest_edge %.1f µs/consulta, plan %.1f µs/rota (grade sintética, indicação apenas)" % [label, nearest_us, plan_us])

## Onde o `plan` em C# ainda gasta tempo: cada etapa cronometrada por separado nas mesmas rotas.
func _profile_plan(routes: RefCounted, router: RefCounted, points: Array[Vector3], headings: Array[Vector3]) -> void:
	var graph: RefCounted = router._native_graph()
	var totals := {"start_edge": 0, "goal_edge": 0, "search": 0, "curve": 0, "bake_source": 0, "closest": 0, "build_path": 0, "bake_result": 0,
		"fonte@0.5 bake": 0, "fonte@0.5 desvio": 0.0, "fonte@0.5 rotas c/ pontos diferentes": 0,
		"fonte@1.0 bake": 0, "fonte@1.0 desvio": 0.0, "fonte@1.0 rotas c/ pontos diferentes": 0,
		"final@0.25 closest": 0, "final@0.5 bake": 0, "final@0.5 desvio": 0.0, "final@0.5 closest": 0,
		"final@1.0 bake": 0, "final@1.0 desvio": 0.0, "final@1.0 closest": 0,
		"ambos@0.5 bake total": 0, "ambos@0.5 desvio": 0.0}
	var samples := 0
	var curve_points := 0
	var curve_length := 0.0
	for index in 120:
		var start := points[index]
		var goal := points[(index * 7 + 11) % QUERIES]
		var heading := headings[index]
		var began := Time.get_ticks_usec()
		var first: Dictionary = router._start_edge(start, heading)
		totals.start_edge += Time.get_ticks_usec() - began
		began = Time.get_ticks_usec()
		var last: Dictionary = router.nearest_edge(goal, true)
		totals.goal_edge += Time.get_ticks_usec() - began
		if first.is_empty() or last.is_empty(): continue
		began = Time.get_ticks_usec()
		var found: Dictionary = graph.Plan(first.edge.to, last.edge.from)
		totals.search += Time.get_ticks_usec() - began
		if not found.found: continue
		var nodes: Array[int] = [first.edge.from]
		nodes.append_array(found.chain)
		nodes.append(last.edge.to)
		began = Time.get_ticks_usec()
		var source: Curve3D = routes._curve(nodes, false)
		totals.curve += Time.get_ticks_usec() - began
		began = Time.get_ticks_usec()
		var length := source.get_baked_length()
		totals.bake_source += Time.get_ticks_usec() - began
		began = Time.get_ticks_usec()
		var begin := clampf(source.get_closest_offset(first.closest), 0.0, length)
		totals.closest += Time.get_ticks_usec() - began
		var window := maxf(0.0, length - ((routes.vertices[nodes[-1]] as Vector3).distance_to(routes.vertices[nodes[-2]]) + 14.0))
		began = Time.get_ticks_usec()
		var result: Curve3D = graph.BuildPath(source, begin, window, last.closest, router.STEP, 0.25)
		totals.build_path += Time.get_ticks_usec() - began
		began = Time.get_ticks_usec()
		var result_length := result.get_baked_length()
		totals.bake_result += Time.get_ticks_usec() - began
		# Variantes de intervalo de bake: custo e desvio contra a curva padrão (0,25 / 0,25).
		for source_interval in [0.5, 1.0]:
			var coarse_source: Curve3D = routes._curve(nodes, false)
			coarse_source.bake_interval = source_interval
			began = Time.get_ticks_usec()
			var coarse_length := coarse_source.get_baked_length()
			totals["fonte@%.1f bake" % source_interval] += Time.get_ticks_usec() - began
			var coarse_begin := clampf(coarse_source.get_closest_offset(first.closest), 0.0, coarse_length)
			var coarse_window := maxf(0.0, coarse_length - ((routes.vertices[nodes[-1]] as Vector3).distance_to(routes.vertices[nodes[-2]]) + 14.0))
			var coarse_result: Curve3D = graph.BuildPath(coarse_source, coarse_begin, coarse_window, last.closest, router.STEP, 0.25)
			totals["fonte@%.1f desvio" % source_interval] = maxf(float(totals["fonte@%.1f desvio" % source_interval]), _max_gap(result, coarse_result))
			if absi(coarse_result.point_count - result.point_count) > 0: totals["fonte@%.1f rotas c/ pontos diferentes" % source_interval] += 1
		for result_interval in [0.5, 1.0]:
			var copy := Curve3D.new()
			copy.bake_interval = result_interval
			for point_index in result.point_count: copy.add_point(result.get_point_position(point_index))
			began = Time.get_ticks_usec()
			copy.get_baked_length()
			totals["final@%.1f bake" % result_interval] += Time.get_ticks_usec() - began
			totals["final@%.1f desvio" % result_interval] = maxf(float(totals["final@%.1f desvio" % result_interval]), _max_gap(result, copy))
			began = Time.get_ticks_usec()
			for repeat in 20: copy.get_closest_offset(first.closest)
			totals["final@%.1f closest" % result_interval] += (Time.get_ticks_usec() - began) / 20.0
		# Os dois em 0,5 m juntos (o novo padrão do roteador): o desvio pode somar.
		var both_source: Curve3D = routes._curve(nodes, false)
		both_source.bake_interval = 0.5
		began = Time.get_ticks_usec()
		var both_length := both_source.get_baked_length()
		var both_begin := clampf(both_source.get_closest_offset(first.closest), 0.0, both_length)
		var both_window := maxf(0.0, both_length - ((routes.vertices[nodes[-1]] as Vector3).distance_to(routes.vertices[nodes[-2]]) + 14.0))
		var both_result: Curve3D = graph.BuildPath(both_source, both_begin, both_window, last.closest, router.STEP, 0.5)
		both_result.get_baked_length()
		totals["ambos@0.5 bake total"] += Time.get_ticks_usec() - began
		totals["ambos@0.5 desvio"] = maxf(float(totals["ambos@0.5 desvio"]), _max_gap(result, both_result))
		began = Time.get_ticks_usec()
		for repeat in 20: result.get_closest_offset(first.closest)
		totals["final@0.25 closest"] += (Time.get_ticks_usec() - began) / 20.0
		samples += 1
		curve_points += result.point_count
		curve_length += result_length
	if samples == 0: return
	print("--- onde o plan em C# gasta tempo (média de %d rotas, %.0f pontos e %.0f m por rota) ---" % [samples, float(curve_points) / samples, curve_length / samples])
	for key in totals:
		if str(key).ends_with("desvio"): print("  %-36s %7.2f cm (pior rota)" % [key, float(totals[key]) * 100.0])
		elif str(key).ends_with("diferentes"): print("  %-36s %d de %d" % [key, int(totals[key]), samples])
		else: print("  %-36s %7.1f µs" % [key, float(totals[key]) / samples])

## Maior distância entre as duas curvas, amostrando a primeira a cada 0,5 m e projetando na outra.
func _max_gap(reference: Curve3D, other: Curve3D) -> float:
	var worst := 0.0
	var length := reference.get_baked_length()
	var distance := 0.0
	while distance <= length:
		var point := reference.sample_baked(distance, true)
		worst = maxf(worst, point.distance_to(other.sample_baked(other.get_closest_offset(point), true)))
		distance += 0.5
	return worst

func _check(ok: bool, message: String) -> void:
	print(("OK    " if ok else "FALHA ") + message)
	if not ok: failures += 1

func _finish() -> void:
	print("resultado: ", "falhou" if failures > 0 else "passou")
	quit(1 if failures > 0 else 0)

## Grade de GRID x GRID ruas, com mão única, duas faixas e larguras diferentes.
func _roads() -> Array:
	var roads: Array = []
	for line in GRID:
		var width := 12.0 if line % 4 == 0 else 7.5
		var lanes := 2 if line % 4 == 0 else 1
		var span := float(GRID - 1) * BLOCK
		var horizontal_id := "street_h%d" % line
		var vertical_id := "street_v%d" % line
		if line % 5 == 3:
			horizontal_id = "street_inbound_h%d" % line
			vertical_id = "street_outbound_v%d" % line
		roads.append({"id": horizontal_id, "width": width, "lanes_per_direction": lanes,
			"points": PackedVector3Array([Vector3(0, 0, line * BLOCK), Vector3(span, 0, line * BLOCK)])})
		roads.append({"id": vertical_id, "width": width, "lanes_per_direction": lanes,
			"points": PackedVector3Array([Vector3(line * BLOCK, 0, 0), Vector3(line * BLOCK, 0, span)])})
	return roads
