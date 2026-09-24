extends RefCounted
## Reserva de cruzamento do trânsito ambiente. Sem prioridade de via, carros de
## direções cruzadas entravam juntos no cruzamento e formavam bolos de 5+ veículos
## que nunca se desfaziam (2026-09-23). Aqui cada cruzamento admite um carro por vez:
## quem chega perto pede a vez; sem vez, para antes do cruzamento e espera.
##
## Cruzamento = vértice do grafo ambiente com 3+ vizinhos. A chave é a posição
## arredondada, estável entre reconfigurações do grafo (costura Harbor/Mountain).

## Distância (ao longo da rota) em que o carro pede a vez, antes do centro.
const APPROACH := 10.0
## Distância depois do centro em que o carro libera a vez.
const EXIT := 7.0
## Dono que some ou fica parado além disso perde a vez (evita trava por dono preso).
const HOLD_LIMIT_MSEC := 8000

static var junctions: Dictionary = {}   # chave -> Vector3
static var owners: Dictionary = {}      # chave -> [instance_id, desde_msec]

static func key_of(point: Vector3) -> Vector3i:
	return Vector3i(roundi(point.x * 2.0), 0, roundi(point.z * 2.0))

static func configure(graph) -> void:
	junctions.clear()
	owners.clear()
	if graph == null: return
	var neighbours: Dictionary = {}
	for from in graph.edges:
		for edge in graph.edges[from]:
			if not neighbours.has(from): neighbours[from] = {}
			if not neighbours.has(edge.to): neighbours[edge.to] = {}
			neighbours[from][edge.to] = true
			neighbours[edge.to][from] = true
	for index in neighbours:
		if neighbours[index].size() >= 3:
			var point: Vector3 = graph.vertices[index]
			junctions[key_of(point)] = point

## Cruzamentos ao longo de uma rota: [{key, offset}] ordenados pelo deslocamento.
static func along(route: Curve3D) -> Array:
	var result: Array = []
	if route == null or junctions.is_empty(): return result
	for key in junctions:
		var center: Vector3 = junctions[key]
		var offset := route.get_closest_offset(center)
		if route.sample_baked(offset, true).distance_to(center) > 4.0: continue
		result.append({"key": key, "offset": offset})
	result.sort_custom(func(a, b): return a.offset < b.offset)
	return result

static func try_enter(key: Vector3i, id: int) -> bool:
	var now := Time.get_ticks_msec()
	var current: Array = owners.get(key, [])
	if current.is_empty() or current[0] == id or now - int(current[1]) > HOLD_LIMIT_MSEC or not is_instance_id_valid(current[0]):
		if current.is_empty() or current[0] != id: owners[key] = [id, now]
		return true
	return false

static func release(key: Vector3i, id: int) -> void:
	var current: Array = owners.get(key, [])
	if not current.is_empty() and current[0] == id: owners.erase(key)
