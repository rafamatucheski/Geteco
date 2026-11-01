extends RefCounted
## Caminho do embarque: rota até o ponto de espera da porta fechada (arrombamento), canto por onde o
## corpo contorna a lataria, rota pela porta com o grafo de visibilidade que desvia do casco e da
## folha aberta, e leitura do caminho (ponto, rumo). Separado do VehicleBoardingPresentation em 01/11
## (Onda 2 do plano de divisão). Estado (_path, _path_length, _layout, _approach...) continua na
## apresentação, que mantém cada função antiga como delegação de uma linha (testes leem _approach,
## _path_length e _stand_world lá). `g` fica como Node, sem preload cíclico, e até as chamadas entre
## funções passam por `g.`.

const BREAK_IN := preload("res://gameplay/VehicleBreakIn.gd")

var g: Node

func _init(host: Node) -> void:
	g = host

func _prepare_locked_path() -> void:
	g._break_layout = BREAK_IN.closed_layout(g.vehicle, g.side)
	var from: Vector3 = g.vehicle.to_local(g._start)
	var destination: Vector3 = g._break_layout.stand
	g._planning_closed = true
	var route: Array[Vector2] = g._plan(Vector2(from.x, from.z), Vector2(destination.x, destination.z))
	g._planning_closed = false
	g._path.assign([g._start])
	for index in range(1, route.size()):
		g._path.append(g.vehicle.to_global(Vector3(route[index].x, .04, route[index].y)))
	g._path_length = 0.0
	for index in range(1, g._path.size()): g._path_length += g._path[index - 1].distance_to(g._path[index])
	g._walk_seconds = clampf(g._path_length / 2.3, .3, 3.2)
	g._approach_seconds = g._walk_seconds
	var body: float = g.BODY_SECONDS.get(g._kind, 1.5)
	g.duration = g._approach_seconds + body + g.CLOSE_SECONDS
	g._approach = g._approach_seconds / (g._approach_seconds + body)
	g._retreat_seconds = maxf(g.vehicle.to_global(destination).distance_to(g._stand_world) / 2.0, .25)

## Ponto de fora da lataria alinhado à porta. Quem está na frente ou atrás do veículo
## vai primeiro até a lateral e depois acompanha a lataria, em vez de atravessá-la.
func _outside_corner(from: Vector3) -> Vector3:
	var local: Vector3 = g.vehicle.to_local(from)
	var door_local: Vector3 = g.vehicle.to_local(g._door)
	var lateral := absf(door_local.x)
	if signf(local.x) == float(g.side) and absf(local.x) >= float(g.vehicle.half_width) + .10: return g._door.lerp(from, .5)
	var margin := float(g.vehicle.half_length) + .45
	var z := clampf(local.z, -margin, margin)
	if absf(local.z) < margin:
		# Do lado errado e ao lado da lataria: contorna pela ponta mais próxima da porta.
		z = -margin if door_local.z < 0 else margin
	var corner: Vector3 = g.vehicle.to_global(Vector3(float(g.side) * lateral, door_local.y, z))
	corner.y = g._door.y
	return corner

## Caminho em dois trechos (início → canto → porta), com velocidade constante.
func _walk_along(k: float) -> Vector3:
	var first: float = g._start.distance_to(g._corner)
	var total: float = first + g._corner.distance_to(g._door)
	if total < .001:
		g.actor.global_position = g._door
		return Vector3.ZERO
	var travelled := k * total
	if travelled <= first:
		g.actor.global_position = g._start.lerp(g._corner, travelled / maxf(first, .001))
		return g._corner - g._start
	g.actor.global_position = g._corner.lerp(g._door, (travelled - first) / maxf(total - first, .001))
	return g._door - g._corner

func _prepare_door_path(outside: Vector3, entering: bool) -> void:
	g._layout = {}
	g._path.clear()
	if not g.vehicle.has_method("door_layout") or not (g._kind in ["car", "tall", "truck"]): return
	var found: Dictionary = g.vehicle.door_layout(g.side)
	if found.is_empty(): return
	g._layout = found
	g._stand_world = g.vehicle.to_global(g._flat(g._layout.stand, .04))
	g._reach_world = g.vehicle.to_global(g._flat(g._layout.reach, .04))
	g._gate_world = g.vehicle.to_global(g._flat(g._layout.gate, .04))
	g._grip_side = "Right" if g.side < 0 else "Left"
	var ground: float = g.vehicle.global_position.y + .04
	var outside_local: Vector3 = g.vehicle.to_local(outside)
	# Aproxima-se de uma porta fechada antes de abri-la. Planejar contra a folha aberta
	# mandava pedestres próximos contornarem o casco inteiro para chegar ao ponto de espera.
	g._planning_closed = entering
	var route: Array[Vector2] = g._plan(Vector2(outside_local.x, outside_local.z), Vector2(g._layout.stand.x, g._layout.stand.z))
	g._planning_closed = false
	g._path.append(outside)
	for index in range(1, route.size()):
		var point: Vector3 = g.vehicle.to_global(Vector3(route[index].x, 0.0, route[index].y))
		point.y = ground if index == route.size() - 1 else lerpf(outside.y, ground, float(index) / float(route.size() - 1))
		g._path.append(point)
	g._path_length = 0.0
	for index in range(1, g._path.size()): g._path_length += g._path[index - 1].distance_to(g._path[index])
	g._walk_seconds = clampf(g._path_length / 2.3, .3, 3.2)
	# Quem aperta o F colado na porta dá um passo para trás e só então a porta abre; o corpo
	# espera a folha terminar de abrir antes de se aproximar do vão.
	var wait := .32 if entering else 0.0
	g._approach_seconds = g._walk_seconds + wait
	var body: float = g.BODY_SECONDS.get(g._kind, 1.5)
	g.duration = g._approach_seconds + body + g.CLOSE_SECONDS
	g._approach = g._approach_seconds / (g._approach_seconds + body)

## O ponto (mundo) está dentro do círculo que a ponta da folha varre, com uma folga?
func _inside_swing(point: Vector3, margin := .30) -> bool:
	if g._layout.is_empty(): return false
	var local: Vector3 = g.vehicle.to_local(point)
	var hinge: Vector3 = g._layout.hinge
	return Vector2(local.x - hinge.x, local.z - hinge.z).length() < float(g._layout.length) + margin

func _flat(local: Vector3, height: float) -> Vector3:
	return Vector3(local.x, height, local.z)

## Menor caminho (grafo de visibilidade) entre dois pontos do plano do veículo, desviando do
## casco e da folha aberta. Nós: origem, destino, quatro cantos folgados do casco e dois
## pontos além da ponta da folha. Poucos nós: custo desprezível, roda só ao iniciar.
func _plan(from2: Vector2, to2: Vector2) -> Array[Vector2]:
	var nodes: Array[Vector2] = [from2, to2]
	var ring_x: float = g.vehicle.half_width + .55
	var ring_z: float = g.vehicle.half_length + .55
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]: nodes.append(Vector2(sx * ring_x, sz * ring_z))
	if not g._layout.is_empty():
		var tip: Vector3 = g._layout.tip
		var hinge: Vector3 = g._layout.hinge
		nodes.append(Vector2(tip.x + float(g.side) * .55, tip.z + .1))
		nodes.append(Vector2(tip.x + float(g.side) * .55, hinge.z - .55))
	var count := nodes.size()
	var cost: Array[float] = []
	var previous: Array[int] = []
	var done: Array[bool] = []
	for i in count:
		cost.append(INF)
		previous.append(-1)
		done.append(false)
	cost[0] = 0.0
	for round_index in count:
		var current := -1
		for i in count:
			if not done[i] and (current < 0 or cost[i] < cost[current]): current = i
		if current < 0 or cost[current] == INF: break
		done[current] = true
		if current == 1: break
		for other in count:
			if done[other] or not g._clear(nodes[current], nodes[other]): continue
			var through := cost[current] + nodes[current].distance_to(nodes[other])
			if through < cost[other]:
				cost[other] = through
				previous[other] = current
	var route: Array[Vector2] = []
	if cost[1] == INF:
		route.append(from2)
		route.append(to2)
		return route
	var cursor := 1
	while cursor >= 0:
		route.push_front(nodes[cursor])
		cursor = previous[cursor]
	return route

## O segmento passa livre do casco (com folga) e da folha aberta? Amostragem a cada 10 cm,
## ignorando os primeiros e últimos 25 cm (quem começa colado no carro não fica preso).
func _clear(a: Vector2, b: Vector2) -> bool:
	var length := a.distance_to(b)
	if length < .001: return true
	var hull_x: float = g.vehicle.half_width + .12
	var hull_z: float = g.vehicle.half_length + .12
	var leaf: bool = not g._planning_closed and not g._layout.is_empty()
	var hinge2 := Vector2(g._layout.hinge.x, g._layout.hinge.z) if leaf else Vector2.ZERO
	var tip2 := Vector2(g._layout.tip.x, g._layout.tip.z) if leaf else Vector2.ZERO
	var steps := int(ceil(length / .1))
	for i in range(steps + 1):
		var travelled := length * float(i) / float(steps)
		if travelled < .25 or length - travelled < .25: continue
		var point := a.lerp(b, float(i) / float(steps))
		if absf(point.x) < hull_x and absf(point.y) < hull_z: return false
		if leaf and g._distance_to_segment(point, hinge2, tip2) < .44: return false
	return true

static func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((point - a).dot(ab) / maxf(ab.length_squared(), .0001), 0.0, 1.0)
	return point.distance_to(a + ab * t)

func _path_at(k: float) -> Vector3:
	if g._path.size() < 2 or g._path_length < .001: return g._stand_world
	var target: float = clampf(k, 0.0, 1.0) * g._path_length
	for index in range(1, g._path.size()):
		var segment: float = g._path[index - 1].distance_to(g._path[index])
		if target <= segment or index == g._path.size() - 1:
			return g._path[index - 1].lerp(g._path[index], clampf(target / maxf(segment, .001), 0.0, 1.0))
		target -= segment
	return g._path[g._path.size() - 1]

func _path_heading(k: float) -> Vector3:
	var direction: Vector3 = g._path_at(minf(k + .04, 1.0)) - g._path_at(maxf(k - .04, 0.0))
	direction.y = 0.0
	# Saindo, o corpo percorre o caminho de volta: ele anda de frente para onde vai.
	return -direction if g.exiting else direction

func _yaw_toward(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)
