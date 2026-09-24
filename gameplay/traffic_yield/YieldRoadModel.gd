extends RefCounted
## Espaço lateral permitido, lido do mesmo grafo dirigido que o tráfego usa
## (NativeTrafficRoutes: `vertices`, `edges`, `width`, `_lane_offset`). O limite
## da pista é a largura do eixo cadastrado: não existe outra fonte de "onde
## começa a calçada" na V2, então nunca se ultrapassa `largura/2 - margem`.

const RULES := preload("res://gameplay/traffic_yield/YieldRules.gd")
var routes: RefCounted
## Cruzamentos: vértices com 3 ou mais saídas. [{"point": Vector3, "radius": float}]
var junctions: Array[Dictionary] = []

func configure(p_routes: RefCounted) -> void:
	routes = p_routes
	junctions.clear()
	_signature = ""
	if routes == null: return
	_signature = str(routes.vertices.size()) + ":" + str(routes.edges.size())
	if not routes.vertices.is_empty(): _signature += str(routes.vertices[0]) + str(routes.vertices[routes.vertices.size() - 1])
	for vertex in routes.edges:
		var outgoing: Array = routes.edges[vertex]
		if outgoing.size() < 3: continue
		var widest := 0.0
		for edge in outgoing: widest = maxf(widest, float(edge.width))
		junctions.append({"point": routes.vertices[vertex], "radius": widest * 0.5 + RULES.JUNCTION_MARGIN})

## O grafo é o mesmo objeto reconfigurado na troca de região: reconstrói as
## zonas de cruzamento se ele mudou desde `configure`.
func refresh_if_changed() -> void:
	if routes == null: return
	var signature := str(routes.vertices.size()) + ":" + str(routes.edges.size())
	if not routes.vertices.is_empty(): signature += str(routes.vertices[0]) + str(routes.vertices[routes.vertices.size() - 1])
	if signature == _signature: return
	configure(routes)

var _signature := ""

func has_graph() -> bool:
	return routes != null and not routes.vertices.is_empty()

func in_junction(point: Vector3, extra: float = 0.0) -> bool:
	for junction in junctions:
		var center: Vector3 = junction.point
		if Vector2(point.x - center.x, point.z - center.z).length() < float(junction.radius) + extra: return true
	return false

## Onde `point` está em relação ao eixo da pista de mesmo sentido que `heading`.
## `room` = quanto ainda cabe deslocar para a direita; `left` = folga até o limite esquerdo.
## `valid` é falso fora de qualquer pista (não há calçada aqui: sem pista, sem manobra).
func lateral(point: Vector3, heading: Vector3, half_width: float) -> Dictionary:
	var result := {"valid": false, "room": 0.0, "left": 0.0, "width": 0.0, "right": Vector3.ZERO}
	if not has_graph(): return result
	var flat_heading := Vector3(heading.x, 0.0, heading.z).normalized()
	var best := INF
	for from in routes.edges:
		for edge in routes.edges[from]:
			var a: Vector3 = routes.vertices[edge.from]
			var b: Vector3 = routes.vertices[edge.to]
			var direction := (b - a).normalized()
			if direction.dot(flat_heading) < 0.5: continue
			var closest := Geometry3D.get_closest_point_to_segment(point, a, b)
			var off := Vector3(point.x - closest.x, 0.0, point.z - closest.z)
			var separation := off.length()
			if separation >= best: continue
			var width := float(edge.width)
			if separation > width * 0.5 + 0.5: continue
			best = separation
			var right := direction.cross(Vector3.UP)
			var signed := off.dot(right)
			result = {
				"valid": true,
				"room": maxf(0.0, width * 0.5 - RULES.EDGE_MARGIN - half_width - signed),
				"left": maxf(0.0, width * 0.5 - RULES.EDGE_MARGIN - half_width + signed),
				# Sem corte em zero: negativo = o casco já passa do limite da pista.
				"room_raw": width * 0.5 - RULES.EDGE_MARGIN - half_width - signed,
				"left_raw": width * 0.5 - RULES.EDGE_MARGIN - half_width + signed,
				# Coordenada do centro do veículo à direita do eixo cadastrado da rua.
				"signed": signed,
				"one_way": bool(edge.one_way),
				"width": width,
				"right": right,
			}
	return result
