extends RefCounted
## Planejamento de rotas de despacho sobre o grafo dirigido de NativeTrafficRoutes.
## Não altera o grafo: lê vertices/edges e reaproveita `_curve` para os arcos de
## cruzamento e o deslocamento de faixa. Só devolve rotas por ruas conectadas;
## quando não existe caminho o resultado diz por quê, sem atalho pela calçada.

const STEP := 1.0
const DEFAULT_BAKE := 0.5
const SPAWN_INDEX_CELL := 64.0

class MinHeap extends RefCounted:
	var costs := PackedFloat64Array()
	var nodes := PackedInt32Array()
	func is_empty() -> bool: return nodes.is_empty()
	func push(cost: float, node: int) -> void:
		costs.append(cost)
		nodes.append(node)
		var index := nodes.size() - 1
		while index > 0:
			var parent := (index - 1) >> 1
			if costs[parent] <= costs[index]: break
			_swap(parent, index)
			index = parent
	## Devolve o nó de menor custo; o custo (double) fica em `popped_cost`.
	## Vector2 é float32 e não serve para comparar com as distâncias em double.
	var popped_cost := 0.0
	func pop() -> int:
		var top_node := nodes[0]
		popped_cost = costs[0]
		var last := nodes.size() - 1
		costs[0] = costs[last]
		nodes[0] = nodes[last]
		costs.resize(last)
		nodes.resize(last)
		var index := 0
		while true:
			var left := index * 2 + 1
			var right := left + 1
			var smallest := index
			if left < last and costs[left] < costs[smallest]: smallest = left
			if right < last and costs[right] < costs[smallest]: smallest = right
			if smallest == index: break
			_swap(smallest, index)
			index = smallest
		return top_node
	func _swap(a: int, b: int) -> void:
		var cost := costs[a]
		costs[a] = costs[b]
		costs[b] = cost
		var node := nodes[a]
		nodes[a] = nodes[b]
		nodes[b] = node

var routes: RefCounted
## "de>para" -> instante (s do relógio do roteador) em que o bloqueio expira.
var blocked: Dictionary = {}
## Avança com o tempo simulado do controlador, não com o relógio da máquina.
var clock := 0.0

## Espelho em C# do grafo (gameplay/dispatch/RoadGraphSearch.cs): aresta mais próxima com índice
## espacial e Dijkstra com parada no destino. Sem o build .NET (ou sem a classe compilada) tudo
## cai nos caminhos GDScript abaixo, que seguem sendo a referência. HARBOR_NO_CSHARP=1 força o GDScript.
const NATIVE_SCRIPT := "res://gameplay/dispatch/RoadGraphSearch.cs"
var use_native := OS.get_environment("HARBOR_NO_CSHARP").is_empty()
## Intervalo de bake da curva-fonte (só amostrada aqui) e da curva entregue ao motorista. O bake era
## ~90% do custo do plano (medido: 1,1 ms + 0,9 ms em 725 m a 0,25) e cresce com os pontos baked.
## Medido em 118 rotas: 0,5 m desvia no máximo 3,1 cm (fonte) e 3,8 cm (final) e corta ~1,1 ms; 1,0 m
## chega a 9 cm. HARBOR_PLAN_BAKE_SOURCE / HARBOR_PLAN_BAKE_RESULT=0.25 restauram o comportamento antigo.
var source_bake := _env_interval("HARBOR_PLAN_BAKE_SOURCE")
var result_bake := _env_interval("HARBOR_PLAN_BAKE_RESULT")
var _native: RefCounted
var _native_tried := false
var _native_edges: Array = []
var _native_signature: Array = []
var _spawn_edges: Array[Dictionary] = []
var _spawn_cells: Dictionary = {}

static func _env_interval(name: String) -> float:
	var text := OS.get_environment(name)
	return float(text) if text.is_valid_float() and float(text) > 0.0 else DEFAULT_BAKE

func advance(delta: float) -> void:
	clock += delta

func configure(p_routes: RefCounted) -> void:
	routes = p_routes
	blocked.clear()
	_native_signature = []
	_native_edges = []
	_rebuild_spawn_index()

## Index lane-segment bounds once per graph rebuild. Sampling remains unchanged,
## including arbitrary spacing, height and the original edge iteration order.
func _rebuild_spawn_index() -> void:
	_spawn_edges.clear()
	_spawn_cells.clear()
	if not has_graph(): return
	for from in routes.edges:
		for edge in routes.edges[from]:
			var a: Vector3 = routes.vertices[edge.from]
			var b: Vector3 = routes.vertices[edge.to]
			var length := a.distance_to(b)
			if length <= 0.0: continue
			var direction := (b - a) / length
			var offset: Vector3 = routes._lane_offset(direction, edge)
			var index := _spawn_edges.size()
			_spawn_edges.append({"edge": edge, "a": a, "length": length, "direction": direction, "offset": offset})
			var low := _spawn_cell(Vector3(minf(a.x, b.x), 0.0, minf(a.z, b.z)) + offset)
			var high := _spawn_cell(Vector3(maxf(a.x, b.x), 0.0, maxf(a.z, b.z)) + offset)
			for x in range(low.x, high.x + 1):
				for z in range(low.y, high.y + 1):
					var key := Vector2i(x, z)
					if not _spawn_cells.has(key): _spawn_cells[key] = []
					_spawn_cells[key].append(index)

func _spawn_cell(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / SPAWN_INDEX_CELL), floori(point.z / SPAWN_INDEX_CELL))

## Espelho atualizado, ou null quando o C# não está disponível. O grafo só muda em
## `NativeTrafficRoutes.configure` (que recria tudo), então tamanho + extremos identificam a troca.
func _native_graph() -> RefCounted:
	if not use_native or not has_graph(): return null
	var signature := [routes.get_instance_id(), routes.vertices.size(), routes.edges.size(), routes.vertices[0], routes.vertices[-1]]
	if _native == null or _native_signature != signature:
		if not _rebuild_native(): return null
		_native_signature = signature
	_native.SetClock(clock)
	return _native

func _rebuild_native() -> bool:
	if _native == null:
		if _native_tried: return false
		_native_tried = true
		if not ClassDB.class_exists(&"CSharpScript") or not ResourceLoader.exists(NATIVE_SCRIPT): return false
		var script: Script = load(NATIVE_SCRIPT)
		if script == null or not script.can_instantiate(): return false
		_native = script.new()
	# Mesma ordem de iteração do nearest_edge GDScript: o índice devolvido aponta para esta lista.
	_native_edges = []
	var edge_from := PackedInt32Array()
	var edge_to := PackedInt32Array()
	var width := PackedFloat64Array()
	var lanes := PackedInt32Array()
	var one_way := PackedInt32Array()
	for node in routes.edges:
		for edge in routes.edges[node]:
			_native_edges.append(edge)
			edge_from.append(int(edge.from))
			edge_to.append(int(edge.to))
			width.append(float(edge.width))
			lanes.append(int(edge.get("lanes", 1)))
			one_way.append(1 if edge.one_way else 0)
	_native.Build(PackedVector3Array(routes.vertices), edge_from, edge_to, width, lanes, one_way)
	for key in blocked:
		var parts := String(key).split(">")
		_native.BlockEdge(int(parts[0]), int(parts[1]), float(blocked[key]))
	return true

func has_graph() -> bool:
	return routes != null and not routes.vertices.is_empty()

func edge_key(from: int, to: int) -> String:
	return str(from) + ">" + str(to)

func is_blocked(from: int, to: int) -> bool:
	var key := edge_key(from, to)
	if not blocked.has(key): return false
	if clock >= float(blocked[key]):
		blocked.erase(key)
		return false
	return true

func block_edge(from: int, to: int, seconds: float) -> void:
	blocked[edge_key(from, to)] = clock + seconds
	if _native != null: _native.BlockEdge(from, to, clock + seconds)

## Bloqueia (e devolve) a aresta em que `point` está: usado quando uma viatura
## fica presa e o próximo plano precisa evitar o mesmo trecho.
func block_edge_near(point: Vector3, seconds: float, heading: Vector3 = Vector3.ZERO) -> Dictionary:
	var found := nearest_edge(point, false, heading)
	if not found.is_empty(): block_edge(found.edge.from, found.edge.to, seconds)
	return found

func _xz(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z)

## Aresta dirigida mais próxima (com o deslocamento de faixa usado pelo tráfego).
## `heading` opcional descarta arestas contra a direção atual do veículo.
func nearest_edge(point: Vector3, skip_blocked: bool = false, heading: Vector3 = Vector3.ZERO) -> Dictionary:
	if not has_graph(): return {}
	var native := _native_graph()
	if native != null:
		var hit: Dictionary = native.NearestEdge(point, skip_blocked, heading)
		if hit.is_empty(): return {}
		return {"edge": _native_edges[int(hit.index)], "closest": hit.closest, "distance": hit.distance}
	var best: Dictionary = {}
	var best_distance := INF
	for from in routes.edges:
		for edge in routes.edges[from]:
			if skip_blocked and is_blocked(edge.from, edge.to): continue
			var a: Vector3 = routes.vertices[edge.from]
			var b: Vector3 = routes.vertices[edge.to]
			var direction := (b - a).normalized()
			if heading.length_squared() > 0.01 and direction.dot(heading.normalized()) < 0.0: continue
			var offset: Vector3 = routes._lane_offset(direction, edge)
			var closest := Geometry3D.get_closest_point_to_segment(point, a + offset, b + offset)
			var distance := closest.distance_squared_to(point)
			if distance < best_distance:
				best_distance = distance
				best = {"edge": edge, "closest": closest, "distance": sqrt(distance)}
	return best

## Aresta em que o veículo está saindo. Uma aresta bloqueada não serve de
## partida: o plano nasce na faixa oposta e o veículo faz o retorno de verdade.
func _start_edge(start: Vector3, heading: Vector3) -> Dictionary:
	var aligned := nearest_edge(start, false, heading)
	if not aligned.is_empty() and not is_blocked(aligned.edge.from, aligned.edge.to) and aligned.distance <= 10.0: return aligned
	var any := nearest_edge(start, true)
	if not any.is_empty(): return any
	return aligned if not aligned.is_empty() else nearest_edge(start)

## Dijkstra por comprimento a partir de `source`, respeitando mão única e bloqueios.
func _search(source: int, cost_limit: float = INF) -> Dictionary:
	var native := _native_graph()
	if native != null:
		var found: Dictionary = native.Search(source, cost_limit)
		if not found.is_empty(): return found
	var count: int = routes.vertices.size()
	var distance := PackedFloat64Array()
	distance.resize(count)
	distance.fill(INF)
	var previous := PackedInt32Array()
	previous.resize(count)
	previous.fill(-1)
	var heap := MinHeap.new()
	distance[source] = 0.0
	heap.push(0.0, source)
	while not heap.is_empty():
		var node := heap.pop()
		var settled := heap.popped_cost
		if settled > distance[node] or settled > cost_limit: continue
		for edge in routes.edges[node]:
			if is_blocked(node, edge.to): continue
			var cost: float = settled + (routes.vertices[edge.to] as Vector3).distance_to(routes.vertices[node])
			if cost < distance[edge.to]:
				distance[edge.to] = cost
				previous[edge.to] = node
				heap.push(cost, edge.to)
	return {"distance": distance, "previous": previous}

func _chain(previous: PackedInt32Array, source: int, target: int) -> Array[int]:
	var reverse: Array[int] = [target]
	var guard := 0
	while reverse[-1] != source and guard < 100000:
		var back := previous[reverse[-1]]
		if back < 0: return []
		reverse.append(back)
		guard += 1
	reverse.reverse()
	return reverse

## Rota de `start` até o trecho de rua mais próximo de `goal`. `end_gap` é a
## distância restante, em planta, entre o fim da rota e o objetivo: quem chama
## decide se a equipe ainda alcança o local a pé.
func plan(start: Vector3, goal: Vector3, heading: Vector3 = Vector3.ZERO) -> Dictionary:
	if not has_graph(): return _fail("no_graph")
	var first := _start_edge(start, heading)
	var last := nearest_edge(goal, true)
	if first.is_empty() or last.is_empty(): return _fail("no_edge")
	var e_start: Dictionary = first.edge
	var e_goal: Dictionary = last.edge
	var nodes: Array[int] = []
	var direction: Vector3 = (routes.vertices[e_start.to] - routes.vertices[e_start.from]).normalized()
	var same_edge: bool = e_start.from == e_goal.from and e_start.to == e_goal.to
	var ahead: bool = (last.closest - first.closest).dot(direction) > 0.5
	if same_edge and ahead:
		nodes.assign([e_start.from, e_start.to])
	else:
		var chain: Array[int] = []
		var native := _native_graph()
		if native != null:
			# Para ao assentar o destino: o grafo inteiro não precisa ser percorrido.
			var found: Dictionary = native.Plan(e_start.to, e_goal.from)
			if not found.found: return _fail("no_path")
			chain.assign(found.chain)
		else:
			var searched := _search(e_start.to)
			chain = _chain(searched.previous, e_start.to, e_goal.from)
			if chain.is_empty() or is_inf(searched.distance[e_goal.from]): return _fail("no_path")
		nodes.append(e_start.from)
		nodes.append_array(chain)
		nodes.append(e_goal.to)
	return _build(nodes, start, last.closest, goal, first.closest)

## Rota de saída: vai ao vértice alcançável mais próximo que fique a pelo menos
## `min_distance` de `away_from` (fora da vista), sem teleporte nem marcha ré infinita.
func plan_departure(start: Vector3, away_from: Vector3, min_distance: float, heading: Vector3 = Vector3.ZERO) -> Dictionary:
	if not has_graph(): return _fail("no_graph")
	var first := _start_edge(start, heading)
	if first.is_empty(): return _fail("no_edge")
	var e_start: Dictionary = first.edge
	var searched := _search(e_start.to, 600.0)
	var pick := -1
	var pick_cost := INF
	var far_pick := -1
	var far_distance := -INF
	for index in routes.vertices.size():
		if is_inf(searched.distance[index]): continue
		var separation := _xz(routes.vertices[index]).distance_to(_xz(away_from))
		if separation >= min_distance and searched.distance[index] < pick_cost:
			pick = index
			pick_cost = searched.distance[index]
		if separation > far_distance:
			far_distance = separation
			far_pick = index
	if pick < 0: pick = far_pick
	if pick < 0: return _fail("no_path")
	var chain := _chain(searched.previous, e_start.to, pick)
	if chain.is_empty(): return _fail("no_path")
	var nodes: Array[int] = []
	nodes.append(e_start.from)
	nodes.append_array(chain)
	if nodes.size() < 2 or nodes[0] == nodes[1]: return _fail("no_path")
	var end_point: Vector3 = routes.vertices[pick]
	return _build(nodes, start, end_point, end_point, first.closest)

func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

func _build(nodes: Array[int], _start: Vector3, end_point: Vector3, goal: Vector3, start_projection: Vector3) -> Dictionary:
	if nodes.size() < 2: return _fail("no_path")
	# A streamed seam can expose two graph vertices at the same position.  Such
	# an edge has no heading and Curve3D cannot bake/sample it safely.
	for index in range(nodes.size() - 1):
		if (routes.vertices[nodes[index]] as Vector3).distance_squared_to(routes.vertices[nodes[index + 1]]) < 0.0001:
			return _fail("degenerate_path")
	var source: Curve3D = routes._curve(nodes, false)
	source.bake_interval = source_bake
	var length := source.get_baked_length()
	if length < 1.0: return _fail("no_path")
	var begin := clampf(source.get_closest_offset(start_projection), 0.0, length)
	if length - begin < 0.25: return _fail("no_path")
	var window := maxf(0.0, length - ((routes.vertices[nodes[-1]] as Vector3).distance_to(routes.vertices[nodes[-2]]) + 14.0))
	# O reamostrado (uma consulta nativa por metro) é o que sobra do custo do plano depois da busca;
	# em C# o laço não passa pelo interpretador e as amostras são as mesmas chamadas ao Curve3D.
	var curve: Curve3D
	var native := _native_graph()
	if native != null:
		curve = native.BuildPath(source, begin, window, end_point, STEP, result_bake)
	else:
		var finish := length
		var finish_distance := INF
		var offset := window
		while offset <= length:
			var separation := source.sample_baked(offset, true).distance_squared_to(end_point)
			if separation < finish_distance:
				finish_distance = separation
				finish = offset
			offset += 0.5
		finish = minf(length, maxf(finish, begin + 1.0))
		curve = Curve3D.new()
		curve.bake_interval = result_bake
		var cursor := begin
		while cursor < finish:
			var sampled := source.sample_baked(cursor, true)
			if curve.point_count == 0 or curve.get_point_position(curve.point_count - 1).distance_squared_to(sampled) >= 0.0001:
				curve.add_point(sampled)
			cursor += STEP
		var final_point := source.sample_baked(finish, true)
		if curve.point_count == 0 or curve.get_point_position(curve.point_count - 1).distance_squared_to(final_point) >= 0.0001:
			curve.add_point(final_point)
	if curve.point_count < 2 or curve.get_baked_length() < 0.25: return _fail("degenerate_path")
	var end: Vector3 = curve.get_point_position(curve.point_count - 1)
	curve.set_meta("traffic_open", true)
	curve.set_meta("traffic_endpoint", end)
	return {"ok": true, "curve": curve, "length": curve.get_baked_length(), "end": end, "end_gap": _xz(end).distance_to(_xz(goal)), "nodes": nodes, "reason": ""}

## Pontos de faixa candidatos a nascimento, do mais próximo ao mais distante,
## entre `min_distance` e `max_distance` de `target`. O chamador valida
## visibilidade, colisão e alcance.
func spawn_candidates(target: Vector3, min_distance: float, max_distance: float, spacing: float = 8.0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not has_graph() or spacing <= 0.0 or max_distance < 0.0: return result
	var extent := Vector3(max_distance, 0.0, max_distance)
	var low := _spawn_cell(target - extent)
	var high := _spawn_cell(target + extent)
	var nearby: Dictionary = {}
	for x in range(low.x, high.x + 1):
		for z in range(low.y, high.y + 1):
			for index in _spawn_cells.get(Vector2i(x, z), []): nearby[index] = true
	# Restore the exact pre-index order before the original distance sort; even
	# equal-distance candidates keep the same input order for that sort.
	var indices: Array = nearby.keys()
	indices.sort()
	for index in indices:
		var entry: Dictionary = _spawn_edges[index]
		var edge: Dictionary = entry.edge
		if is_blocked(edge.from, edge.to): continue
		var length: float = entry.length
		if length < spacing: continue
		var a: Vector3 = entry.a
		var direction: Vector3 = entry.direction
		var offset: Vector3 = entry.offset
		var along := spacing * 0.5
		while along < length - spacing * 0.5:
			var point := a + direction * along + offset
			var separation := _xz(point).distance_to(_xz(target))
			if separation >= min_distance and separation <= max_distance:
				result.append({"point": point, "yaw": atan2(-direction.x, -direction.z), "distance": separation, "edge": edge})
			along += spacing
	result.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.distance < y.distance)
	return result
