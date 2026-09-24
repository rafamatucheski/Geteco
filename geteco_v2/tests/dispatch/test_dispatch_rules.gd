extends SceneTree
## Regras portadas da V1 e planejamento de rotas sobre o grafo de ruas.
## Sem física: só aritmética e grafo. Não certifica direção nem desempenho.

const RULES := preload("res://gameplay/dispatch/DispatchRules.gd")
const ROUTER := preload("res://gameplay/dispatch/DispatchRoadRouter.gd")
const KIT := preload("res://tests/dispatch/DispatchTestKit.gd")
const ROUTES := preload("res://gameplay/NativeTrafficRoutes.gd")
var failures: Array[String] = []
var checks := 0
var groups_done: Array[String] = []

func done(group: String) -> void:
	groups_done.append(group)
	print("GROUP_OK " + group)

## Um erro de script aborta a função no meio e o teste seguiria adiante: só
## vale se todos os grupos esperados chegaram ao fim e houve verificações demais.
func report(tag: String, expected: Array, minimum_checks: int) -> void:
	var missing: Array[String] = []
	for group in expected:
		if not groups_done.has(group): missing.append(group)
	if not missing.is_empty(): failures.append("grupos não concluídos: " + str(missing))
	if checks < minimum_checks: failures.append("poucas verificações: %d < %d" % [checks, minimum_checks])
	print("%s groups=%d/%d checks=%d failures=%d" % [tag, expected.size() - missing.size(), expected.size(), checks, failures.size()])
	for failure in failures: print("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _initialize() -> void: call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func run() -> void:
	_rules()
	_router_grid()
	_router_one_way()
	_router_blocked_and_unreachable()
	_router_spawn_and_departure()
	report("DISPATCH_RULES", ["rules", "router_grid", "router_one_way", "router_blocked_and_unreachable", "router_spawn_and_departure"], 35)

func _rules() -> void:
	check(Array(RULES.MAX_ACTIVE) == [0, 2, 3, 4, 5, 5, 5], "limites ativos da V1")
	check(Array(RULES.DEPLOYMENT) == [0, 4, 6, 10, 14, 18, 22], "orçamento de despacho da V1")
	check(Array(RULES.INTERVAL) == [0.0, 10.0, 8.0, 6.0, 5.0, 4.0, 4.0], "intervalos da V1")
	check(is_equal_approx(RULES.SPAWN_MIN, 32.5) and is_equal_approx(RULES.SPAWN_MAX, 112.5), "nascimento 520-1800 px em metros")
	check(is_equal_approx(RULES.RESPONSE_RADIUS, 68.75), "raio de resposta médica 1100 px")
	check(is_equal_approx(RULES.STOP_BASE, 8.75) and is_equal_approx(RULES.stop_radius(2), 13.25), "raio de parada 140 + 36·(serial%3) px")
	check(RULES.pursuit_role(7) == 2 and RULES.pursuit_role(5) == 0, "função na formação = serial % 5")
	check(RULES.variant_for(2, false) == "patrol" and RULES.variant_for(3, false) == "interceptor", "variantes por patamar")
	check(RULES.variant_for(4, true) == "tactical" and RULES.variant_for(5, false) == "patrol", "um único tático por formação")
	check(RULES.speed_cap("interceptor") > RULES.speed_cap("patrol"), "interceptor mais rápido")
	check(RULES.archetype_for("police") == "police_cruiser" and RULES.archetype_for("medic") == "medic_box", "veículos originais do catálogo")
	check(RULES.archetype_for("fire") == "rescue_pumper" and RULES.archetype_for("mortician") == "station_wagon", "veículos de bombeiro e legista")
	var target := Vector3(10, 0, 0)
	var moving := Vector3(10, 0, 0)
	var forward := Vector3.RIGHT
	var chaser := RULES.formation_goal(0, target, moving, forward, 8.75)
	var left := RULES.formation_goal(1, target, moving, forward, 8.75)
	var right := RULES.formation_goal(2, target, moving, forward, 8.75)
	var block := RULES.formation_goal(3, target, moving, forward, 8.75)
	check(chaser.x < target.x + moving.x * RULES.FORMATION_LEAD[0], "perseguidor fica atrás do para-choque")
	check(left.z != right.z and left.z * right.z < 0.0, "flancos em lados opostos")
	check(block.x > target.x, "interceptor ocupa a linha à frente")
	var parked := RULES.formation_goal(3, target, Vector3.ZERO, forward, 8.75)
	check(parked.distance_to(target) <= 8.75 * 0.65 + 0.01, "alvo parado encolhe o espaçamento ao raio de parada")
	done("rules")

func _routes(roads: Array) -> RefCounted:
	var routes := ROUTES.new()
	routes.configure(roads)
	return routes

func _router(roads: Array) -> RefCounted:
	var router := ROUTER.new()
	router.configure(_routes(roads))
	return router

func _near_a_road(point: Vector3, roads: Array, slack: float) -> bool:
	for road in roads:
		var points: PackedVector3Array = road.points
		for index in range(points.size() - 1):
			if Geometry3D.get_closest_point_to_segment(point, points[index], points[index + 1]).distance_to(point) <= float(road.width) * 0.5 + slack: return true
	return false

func _router_grid() -> void:
	var roads := KIT.grid_roads()
	var router := _router(roads)
	check(router.has_graph(), "grafo de ruas montado")
	var plan: Dictionary = router.plan(Vector3(-50, 0, 2), Vector3(34, 0, 14), Vector3.RIGHT)
	check(plan.ok, "rota entre dois pontos da avenida")
	if not plan.ok: return
	var curve: Curve3D = plan.curve
	check(curve.get_baked_length() > 80.0 and curve.get_baked_length() < 130.0, "comprimento coerente com a distância pela via")
	check(plan.end_gap < 16.0, "fim da rota perto do objetivo (%.1f m)" % plan.end_gap)
	check(curve.get_meta("traffic_open", false) == true, "rota aberta: termina em vez de dar a volta")
	var off_road := 0
	var offset := 0.0
	while offset < curve.get_baked_length():
		if not _near_a_road(curve.sample_baked(offset, true), roads, 0.5): off_road += 1
		offset += 1.0
	check(off_road == 0, "toda a rota fica dentro da pista (%d amostras fora)" % off_road)
	check(curve.sample_baked(0.0, true).distance_to(Vector3(-50, 0, 2)) < 2.5, "a rota começa onde a viatura está")
	# Objetivo atrás: a rota dá a volta pelo grafo, sem atalho.
	var behind: Dictionary = router.plan(Vector3(50, 0, 2), Vector3(-20, 0, 14), Vector3.RIGHT)
	check(behind.ok and behind.length > 100.0, "objetivo atrás exige contornar pelas ruas (%.0f m)" % (behind.length if behind.ok else 0.0))
	done("router_grid")

func _router_one_way() -> void:
	# Ponte de mão única "outbound": só há caminho no sentido dela.
	var roads := [
		{"id": "street", "width": 8.0, "points": PackedVector3Array([Vector3(-40, 0, 0), Vector3(0, 0, 0)])},
		{"id": "bridge_outbound", "width": 4.0, "points": PackedVector3Array([Vector3(0, 0, 0), Vector3(40, 0, 0)])},
	]
	var router := _router(roads)
	var forward: Dictionary = router.plan(Vector3(-30, 0, 2), Vector3(35, 0, 0), Vector3.RIGHT)
	check(forward.ok, "mão única: sentido permitido")
	# Na ponte, voltar à rua exigiria andar contra a mão: sem rota.
	var reverse: Dictionary = router.plan(Vector3(35, 0, 0), Vector3(-30, 0, 2), Vector3.RIGHT)
	check(not reverse.ok and reverse.reason == "no_path", "mão única: sentido proibido não gera rota")
	done("router_one_way")

func _router_blocked_and_unreachable() -> void:
	var roads := KIT.grid_roads()
	var router := _router(roads)
	var start := Vector3(-50, 0, 2)
	var goal := Vector3(34, 0, 14)
	var direct: Dictionary = router.plan(start, goal, Vector3.RIGHT)
	var edge: Dictionary = router.nearest_edge(start, false, Vector3.RIGHT)
	router.block_edge(edge.edge.from, edge.edge.to, 20.0)
	check(router.is_blocked(edge.edge.from, edge.edge.to), "aresta bloqueada")
	var detour: Dictionary = router.plan(start, goal, Vector3.RIGHT)
	check(detour.ok and detour.length > direct.length * 1.5, "com a aresta bloqueada a rota contorna pelo anel (%.0f -> %.0f m)" % [direct.length, detour.length if detour.ok else 0.0])
	check(detour.ok and detour.curve.get_point_position(1).x < start.x + 0.5, "a partir da aresta bloqueada o plano nasce na faixa oposta (retorno real, sem atravessar)")
	router.advance(21.0)
	check(not router.is_blocked(edge.edge.from, edge.edge.to), "bloqueio expira com o tempo simulado")
	# Rua única: bloquear a aresta corta o caminho.
	var single := _router(KIT.single_road())
	var forward: Dictionary = single.nearest_edge(Vector3(-50, 0, 2), false, Vector3.RIGHT)
	single.block_edge(forward.edge.from, forward.edge.to, 20.0)
	var none: Dictionary = single.plan(Vector3(-50, 0, 2), Vector3(40, 0, 2), Vector3.RIGHT)
	check(not none.ok, "sem alternativa e com bloqueio, não há rota")
	var empty := ROUTER.new()
	empty.configure(ROUTES.new())
	check(not empty.plan(Vector3.ZERO, Vector3.ONE).ok, "grafo vazio devolve falha explícita")
	done("router_blocked_and_unreachable")

func _router_spawn_and_departure() -> void:
	var roads := KIT.grid_roads()
	var router := _router(roads)
	var anchor := Vector3(30, 0, 10)
	var candidates: Array[Dictionary] = router.spawn_candidates(anchor, RULES.SPAWN_MIN, RULES.SPAWN_MAX)
	check(not candidates.is_empty(), "há candidatos de nascimento em faixa")
	var in_range := true
	var sorted := true
	var previous := 0.0
	for candidate in candidates:
		var flat := Vector2(candidate.point.x - anchor.x, candidate.point.z - anchor.z).length()
		if flat < RULES.SPAWN_MIN - 0.01 or flat > RULES.SPAWN_MAX + 0.01: in_range = false
		if candidate.distance < previous: sorted = false
		previous = candidate.distance
	check(in_range, "candidatos entre 32,5 e 112,5 m")
	check(sorted, "candidatos do mais próximo ao mais distante")
	var lane_ok := true
	for candidate in candidates:
		if absf(absf(candidate.point.z) - 2.0) > 0.1 and absf(absf(candidate.point.x) - 2.0) > 0.1 and absf(absf(candidate.point.x) - 62.0) > 0.1 and absf(absf(candidate.point.z) - 62.0) > 0.1 and absf(absf(candidate.point.x) - 58.0) > 0.1 and absf(absf(candidate.point.z) - 58.0) > 0.1: lane_ok = false
	check(lane_ok, "candidatos sobre o deslocamento de faixa, não no eixo da rua")
	var departure: Dictionary = router.plan_departure(Vector3(34, 0, 2), anchor, 60.0, Vector3.RIGHT)
	check(departure.ok, "rota de saída existe")
	if departure.ok:
		var end: Vector3 = departure.end
		check(Vector2(end.x - anchor.x, end.z - anchor.z).length() >= 60.0 - 0.5, "a saída termina longe do ponto do incidente")
	done("router_spawn_and_departure")

