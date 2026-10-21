extends RefCounted
## Caminho provável do alvo pelo grafo de ruas (NativeTrafficRoutes): a partir da aresta em que ele
## está, no sentido em que anda, segue sempre a saída mais alinhada ("em frente"). Serve ao bloqueador
## (cruzamento à frente) e ao bloqueio com pregos (ponto à frente). Não planeja nada: só lê o grafo.

## Máximo de vértices percorridos por previsão (o grafo da cidade tem trechos de 10-60 m).
const MAX_STEPS := 24
## O alvo precisa estar sobre a rua (aresta alinhada a até isto) para haver previsão.
const MAX_EDGE_DISTANCE := 14.0

## Devolve {"points": PackedVector3Array, "distances": PackedFloat32Array, "junctions": Array[int]}
## com os vértices à frente (o primeiro é a posição projetada do alvo, distância 0). `junctions`
## são os índices de `points` com três ou mais saídas. Vazio se o alvo não está numa rua.
static func predict(routes: RefCounted, router: RefCounted, position: Vector3, velocity: Vector3, max_distance: float) -> Dictionary:
	var empty := {"points": PackedVector3Array(), "distances": PackedFloat32Array(), "junctions": []}
	var direction := Vector3(velocity.x, 0.0, velocity.z)
	if routes == null or router == null or direction.length() < 1.0 or not router.has_graph(): return empty
	direction = direction.normalized()
	var hit: Dictionary = router.nearest_edge(position, false, direction)
	if hit.is_empty() or float(hit.distance) > MAX_EDGE_DISTANCE: return empty
	var edge: Dictionary = hit.edge
	var points := PackedVector3Array([hit.closest])
	var distances := PackedFloat32Array([0.0])
	var junctions: Array[int] = []
	var previous: int = int(edge.from)
	var current: int = int(edge.to)
	var travelled: float = (hit.closest as Vector3).distance_to(routes.vertices[current])
	var visited := {previous: true}
	for step in MAX_STEPS:
		points.append(routes.vertices[current])
		distances.append(travelled)
		var exits: Array = routes.edges.get(current, [])
		if exits.size() >= 3: junctions.append(points.size() - 1)
		if travelled >= max_distance or visited.has(current): break
		visited[current] = true
		var incoming: Vector3 = (routes.vertices[current] - routes.vertices[previous])
		incoming.y = 0.0
		incoming = incoming.normalized() if incoming.length_squared() > 0.0001 else direction
		var next := -1
		var best := -INF
		for candidate in exits:
			var to: int = int(candidate.to)
			if to == previous: continue
			var outgoing: Vector3 = routes.vertices[to] - routes.vertices[current]
			outgoing.y = 0.0
			if outgoing.length_squared() < 0.0001: continue
			var score := outgoing.normalized().dot(incoming)
			if score > best:
				best = score
				next = to
		# Só retorno disponível ou curva fechada demais para ser "em frente": a previsão para aí.
		if next < 0 or best < -0.2: break
		travelled += (routes.vertices[next] as Vector3).distance_to(routes.vertices[current])
		previous = current
		current = next
	return {"points": points, "distances": distances, "junctions": junctions}

## Ponto e direção a `distance` metros pelo caminho previsto (interpola entre vértices).
## {"point": Vector3, "heading": Vector3} ou vazio se o caminho é curto demais.
static func sample(prediction: Dictionary, distance: float) -> Dictionary:
	var points: PackedVector3Array = prediction.points
	var distances: PackedFloat32Array = prediction.distances
	for index in range(1, points.size()):
		if distances[index] < distance: continue
		var span := distances[index] - distances[index - 1]
		var t := clampf((distance - distances[index - 1]) / span, 0.0, 1.0) if span > 0.001 else 1.0
		var heading := points[index] - points[index - 1]
		heading.y = 0.0
		if heading.length_squared() < 0.0001: continue
		return {"point": points[index - 1].lerp(points[index], t), "heading": heading.normalized()}
	return {}
