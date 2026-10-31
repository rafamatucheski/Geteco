extends RefCounted
## Cruzamentos do trânsito ambiente: semáforo com fases de verdade e PARE.
##
## Histórico: primeiro não havia regra e carros de direções cruzadas entravam juntos,
## formando bolos de 5+ veículos (2026-09-23). A correção seguinte admitia UM carro por
## vez no cruzamento, vindo de qualquer direção. Isso acabou com os bolos, mas travou o
## fluxo: fila nas quatro aproximações, carro parado no meio da via esperando a vez e o
## semáforo piscando amarelo sem significar nada (2026-09-24).
##
## Agora:
## - Cruzamento com semáforo (o CityChunkDressing registra o poste) alterna dois eixos:
##   verde, amarelo, vermelho geral e vez do outro eixo. O deslocamento de fase vem da
##   posição, então cruzamentos vizinhos não abrem todos juntos. Carros do mesmo eixo
##   entram juntos; carro do outro eixo só entra com o miolo livre do eixo anterior.
## - Cruzamento sem semáforo (PARE, ou região sem mobília urbana) é parada obrigatória:
##   o carro para na faixa e entra quando não há ninguém do eixo cruzado dentro.
## - A lente do semáforo mostra o estado real da aproximação que ela encara.
##
## Cruzamento = vértice do grafo ambiente com 3+ vizinhos. A chave é a posição
## arredondada, estável entre reconfigurações do grafo (costura Harbor/Mountain).

## Distância ao longo da rota (do centro) em que o carro passa a respeitar o cruzamento.
const APPROACH := 26.0
## Distância depois do centro em que o carro deixa o miolo.
const EXIT := 7.0
## Faixa de parada padrão (do centro) quando o cruzamento não registrou a própria.
const DEFAULT_STOP_LINE := 7.0
## Reserva abandonada expira; um casco ainda no miolo continua bloqueando o eixo cruzado.
const HOLD_LIMIT_MSEC := 9000
## Vehicle limita a altura do casco do trânsito a 3.6 m; inclui o snap de piso de 0.4 m dele.
## Isso separa a ocupação da via de corpos em outro nível vertical de via.
const OCCUPANCY_HEIGHT := 4.0
const GREEN_SECONDS := 11.0
const AMBER_SECONDS := 3.0
const ALL_RED_SECONDS := 1.6
const CYCLE := (GREEN_SECONDS + AMBER_SECONDS + ALL_RED_SECONDS) * 2.0
## Desaceleração confortável usada para decidir se dá para parar no amarelo.
const COMFORT_BRAKE := 4.0
const SIGNAL_CELL := 6.0

const LENS_GREEN := Color(0.25, 1.0, 0.45)
const LENS_AMBER := Color(1.0, 0.68, 0.1)
const LENS_RED := Color(1.0, 0.12, 0.08)

static var junctions: Dictionary = {}   # chave -> Vector3
static var axes: Dictionary = {}        # chave -> Vector2 (eixo A, unitário no plano XZ)
static var owners: Dictionary = {}      # chave -> {instance_id: [eixo_a, desde_msec]}
## Semáforos registrados pela mobília urbana, em células grossas: sobrevivem ao
## `configure` porque a mobília vem do streaming de chunks, em outra ordem.
static var _signals: Dictionary = {}    # Vector2i -> [{center: Vector3, stop: float}]
static var _lenses: Array = []          # [{mesh: WeakRef, index, center, heading, key, gen}]
static var _generation := 0
static var _approaches: Dictionary = {}
static var _phase_frame := -1
static var _phase_time := 0.0
static var _next_lens_update := -INF

# Drivers and rendered lenses share one phase timestamp per frame, including
# a frame that straddles a phase boundary. Never keep a separate visual clock.
static func _signal_time() -> float:
	var frame := Engine.get_process_frames()
	if frame != _phase_frame:
		_phase_frame = frame
		_phase_time = Time.get_ticks_msec() / 1000.0
	return _phase_time

static func key_of(point: Vector3) -> Vector3i:
	return Vector3i(roundi(point.x * 2.0), 0, roundi(point.z * 2.0))

static func configure(graph, layouts: Array = []) -> void:
	var previous_centers := junctions.duplicate()
	var previous_axes := axes.duplicate()
	var previous_owners := owners.duplicate()
	junctions.clear()
	axes.clear()
	owners.clear()
	_approaches.clear()
	_generation += 1
	_next_lens_update = -INF
	if graph == null: return
	var neighbours: Dictionary = {}
	for from in graph.edges:
		for edge in graph.edges[from]:
			if not neighbours.has(from): neighbours[from] = {}
			if not neighbours.has(edge.to): neighbours[edge.to] = {}
			neighbours[from][edge.to] = true
			neighbours[edge.to][from] = true
	for index in neighbours:
		if neighbours[index].size() < 3: continue
		var point: Vector3 = graph.vertices[index]
		var key := key_of(point)
		junctions[key] = point
		# Eixo A = direção do primeiro braço; o outro eixo é o perpendicular.
		var axis := Vector2.RIGHT
		for other in neighbours[index]:
			var arm: Vector3 = graph.vertices[other] - point
			if Vector2(arm.x, arm.z).length_squared() > .01:
				axis = Vector2(arm.x, arm.z).normalized()
				break
		# Via dupla vira vários vértices no mesmo cruzamento; o eixo A é sempre o mais
		# próximo do X do mundo, para que todos concordem sobre quem está no verde.
		if absf(axis.x) < absf(axis.y): axis = axis.orthogonal()
		axes[key] = axis
	for key in junctions:
		var center: Vector3 = junctions[key]
		var nearest := 4.0
		for layout in layouts:
			var distance := Vector2(center.x,center.z).distance_to(layout.position)
			if distance < nearest:
				nearest = distance
				_approaches[key] = layout.entries
	# Reconstruir o grafo não pode apagar os ocupantes físicos dos cruzamentos que sobrevivem.
	# Mantém só os IDs; níveis de via alterados/removidos não podem herdar a reserva antiga.
	for key in previous_owners:
		if not junctions.has(key) or not previous_centers.has(key): continue
		if (junctions[key] as Vector3).distance_to(previous_centers[key]) > .5: continue
		var old_axis: Vector2 = previous_axes.get(key, Vector2.RIGHT)
		var retained: Dictionary = previous_owners[key]
		for id in retained:
			var direction := old_axis if bool(retained[id][0]) else old_axis.orthogonal()
			retained[id][0] = _axis_a(key, Vector3(direction.x, 0, direction.y))
		owners[key] = retained
		_prune(key)

## Cruzamentos ao longo de uma rota: [{key, offset}] ordenados pelo deslocamento.
## Rotas de NativeTrafficRoutes.route_near são compartilhadas entre carros (cache por aresta e
## faixa) e imutáveis: a lista vale até o próximo configure() (geração). Sem isto cada carro novo
## pagava um get_closest_offset linear na curva inteira para cada cruzamento do mapa.
static func along(route: Curve3D) -> Array:
	if route == null or junctions.is_empty(): return []
	if not route.has_meta("traffic_nodes"): return _along(route)
	var cached: Array = route.get_meta("junctions_along", [])
	if cached.size() == 2 and int(cached[0]) == _generation: return cached[1]
	var result := _along(route)
	route.set_meta("junctions_along", [_generation, result])
	return result

static func _along(route: Curve3D) -> Array:
	var result: Array = []
	for key in junctions:
		var center: Vector3 = junctions[key]
		var offset := route.get_closest_offset(center)
		var radius := maxf(4.0,float(route.get_meta("junction_reach",4.0)))
		for entry in _approaches.get(key,[]): radius = maxf(radius,float(entry.width)*.5)
		if route.sample_baked(offset, true).distance_to(center) > radius: continue
		var item := {"key": key, "offset": offset}
		var length := route.get_baked_length()
		var closed := route.get_point_position(0).distance_to(route.get_point_position(route.point_count-1)) < .1
		var before := route.sample_baked(fposmod(offset-12.0,length) if closed else maxf(0,offset-12.0),true)
		var approach := Vector2(before.x-center.x,before.z-center.z).normalized()
		# As fases do sinal pertencem ao braço de chegada, não à tangente de uma
		# curva perto do centro (as faixas externas já podem estar apontando de través).
		item.heading = Vector3(-approach.x,0,-approach.y)
		var score := .7
		for entry in _approaches.get(key,[]):
			var alignment: float = approach.dot(entry.direction)
			if alignment <= score or not entry.fits: continue
			var stop: Vector2 = entry.stop_position+entry.direction.orthogonal()*entry.width*.25
			var stop_offset := route.get_closest_offset(Vector3(stop.x,center.y,stop.y))
			var distance := fposmod(offset-stop_offset,length) if closed else offset-stop_offset
			# A largura/offset/profundidade máxima legal da rua pode pôr a parada além de 30 m.
			if distance < .1 or distance > 45.0: continue
			score = alignment
			item.heading = Vector3(-entry.direction.x,0,-entry.direction.y)
			item.stop_offset = stop_offset
			item.approach_distance = maxf(APPROACH,distance+12.0)
		result.append(item)
	result.sort_custom(func(a, b): return a.offset < b.offset)
	return result

# --- Semáforo ------------------------------------------------------------------------

static func _cell(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / SIGNAL_CELL), floori(point.z / SIGNAL_CELL))

## Chamado pela mobília urbana para cada poste de semáforo montado. `stop` é a distância
## do centro até a faixa de parada daquele braço.
static func register_signal(center: Vector3, stop: float) -> void:
	var cell := _cell(center)
	var list: Array = _signals.get(cell, [])
	for entry in list:
		if (entry.center as Vector3).distance_to(center) < 1.0:
			entry.stop = maxf(float(entry.stop), stop)
			return
	list.append({"center": center, "stop": stop})
	_signals[cell] = list

static func _signal_near(center: Vector3) -> Dictionary:
	var cell := _cell(center)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			for entry in _signals.get(cell + Vector2i(dx, dz), []):
				var other: Vector3 = entry.center
				if Vector2(other.x - center.x, other.z - center.z).length() < 5.0: return entry
	return {}

static func is_signalized(key: Vector3i) -> bool:
	return junctions.has(key) and not _signal_near(junctions[key]).is_empty()

static func stop_line(key: Vector3i) -> float:
	if not junctions.has(key): return DEFAULT_STOP_LINE
	var entry := _signal_near(junctions[key])
	return float(entry.stop) if not entry.is_empty() else DEFAULT_STOP_LINE

static func _axis_a(key: Vector3i, heading: Vector3) -> bool:
	var axis: Vector2 = axes.get(key, Vector2.RIGHT)
	var flat := Vector2(heading.x, heading.z)
	if flat.length_squared() < .0001: return true
	return absf(flat.normalized().dot(axis)) >= 0.7071

## Desfasagem estável por posição: cruzamentos vizinhos não abrem em uníssono.
static func _offset(center: Vector3) -> float:
	var h := absi(roundi(center.x) * 73856093 ^ roundi(center.z) * 19349663)
	return float(h % 1000) / 1000.0 * CYCLE

static func _state_at(center: Vector3, axis_a: bool, now: float) -> String:
	var half := GREEN_SECONDS + AMBER_SECONDS + ALL_RED_SECONDS
	var t := fposmod(now + _offset(center), CYCLE)
	if not axis_a: t = fposmod(t - half, CYCLE)
	if t < GREEN_SECONDS: return "green"
	if t < GREEN_SECONDS + AMBER_SECONDS: return "amber"
	return "red"

## Estado do sinal para quem chega com `heading`: green, amber, red; "stop" sem semáforo.
static func signal_state(key: Vector3i, heading: Vector3) -> String:
	if not junctions.has(key): return "stop"
	var entry := _signal_near(junctions[key])
	if entry.is_empty(): return "stop"
	# A fase vem do centro do semáforo (um por cruzamento real), não do vértice do grafo.
	return _state_at(entry.center, _axis_a(key, heading), _signal_time())

# --- Ocupação do miolo ---------------------------------------------------------------

## Um token só é válido enquanto o registro ainda é dono dele. Checar um token
## evita varrer donos sem relação a cada tick de física de Vehicle.
static func has_reservation(key: Vector3i, id: int) -> bool:
	var inside: Dictionary = owners.get(key, {})
	if not inside.has(id): return false
	if _reservation_alive(key, id, inside[id], Time.get_ticks_msec()): return true
	inside.erase(id)
	return false

static func _reservation_alive(key: Vector3i, id: int, entry: Array, now: int) -> bool:
	if not is_instance_id_valid(id): return false
	if now - int(entry[1]) <= HOLD_LIMIT_MSEC: return true
	if not occupies(key, id): return false
	# Renova só depois de observar ocupação física, nunca só porque um heartbeat
	# de IA está vivo. Isso limita o trabalho geométrico num engarrafamento parado.
	entry[1] = now
	return true

static func _prune(key: Vector3i) -> Dictionary:
	var inside: Dictionary = owners.get(key, {})
	var now := Time.get_ticks_msec()
	for id in inside.keys():
		if not _reservation_alive(key, id, inside[id], now): inside.erase(id)
	return inside

## Só a expiração da reserva e a partida precisam de geometria. Sem consulta ao mundo de física, leitura
## do renderizador, referências persistentes a Node, visibilidade ou heurística de vida do motorista.
static func occupies(key: Vector3i, id: int) -> bool:
	if not junctions.has(key) or not is_instance_id_valid(id): return false
	var owner := instance_from_id(id) as Node3D
	if owner == null or not owner.is_inside_tree(): return false
	if not owner.has_method("junction_collision_bodies"): return false
	var center: Vector3 = junctions[key]
	var axis: Vector2 = axes.get(key, Vector2.RIGHT)
	var radius := EXIT
	for entry in _approaches.get(key, []): radius = maxf(radius, float(entry.width) * .5)
	for body: CollisionObject3D in owner.call("junction_collision_bodies"):
		if not is_instance_valid(body) or not body.is_inside_tree(): continue
		# Os outros veículos varrem a camada 4. A máscara do próprio dono pode ser zero e ele
		# continua sendo obstáculo para eles. Callbacks pausados não removem a colisão.
		if (body.collision_layer & 4) == 0 or _removed_from_physics(body): continue
		for shape_owner in body.get_shape_owners():
			if body.is_shape_owner_disabled(shape_owner): continue
			var pose := body.global_transform * body.shape_owner_get_transform(shape_owner)
			for index in body.shape_owner_get_shape_count(shape_owner):
				var hull := body.shape_owner_get_shape(shape_owner, index) as BoxShape3D
				if hull != null and _box_in_crossing(hull.size * .5, pose, center, axis, radius): return true
	return false

static func _removed_from_physics(body: CollisionObject3D) -> bool:
	if body.disable_mode != CollisionObject3D.DISABLE_MODE_REMOVE: return false
	# Resolve o process mode herdado, não can_process() (que também enxerga a pausa).
	var node: Node = body
	while node != null and node.process_mode == Node.PROCESS_MODE_INHERIT: node = node.get_parent()
	return node != null and node.process_mode == Node.PROCESS_MODE_DISABLED

static func _box_in_crossing(half: Vector3, pose: Transform3D, center: Vector3, axis: Vector2, radius: float) -> bool:
	var x := pose.basis.x * half.x
	var y := pose.basis.y * half.y
	var z := pose.basis.z * half.z
	var vertical := absf(x.y) + absf(y.y) + absf(z.y)
	if pose.origin.y - vertical > center.y + OCCUPANCY_HEIGHT or pose.origin.y + vertical < center.y - .4: return false
	var offset := Vector2(pose.origin.x - center.x, pose.origin.z - center.z)
	var px := Vector2(x.x, x.z)
	var py := Vector2(y.x, y.z)
	var pz := Vector2(z.x, z.z)
	var across := axis.orthogonal()
	# SAT da área projetada da caixa contra o quadrado protegido do cruzamento.
	# Inclui a projeção da base vertical quando o veículo está inclinado.
	for normal: Vector2 in [axis, across, px.orthogonal(), py.orthogonal(), pz.orthogonal()]:
		if normal.length_squared() < .000001: continue
		var hull_radius := absf(px.dot(normal)) + absf(py.dot(normal)) + absf(pz.dot(normal))
		var road_radius := radius * (absf(axis.dot(normal)) + absf(across.dot(normal)))
		if absf(offset.dot(normal)) > hull_radius + road_radius: return false
	return true

static func _completed_exit_axis(key: Vector3i, id: int, entry_axis: bool) -> bool:
	# Cruzamentos próximos podem se sobrepor à traseira de um carro depois que a curva dele terminou.
	# Mantém a reserva física, mas classifica esse movimento concluído pela saída dele.
	# Senão duas curvas opostas seguram N/S enquanto esperam para entrar em E/W.
	if not junctions.has(key) or not is_instance_id_valid(id): return entry_axis
	var car := instance_from_id(id) as Node3D
	if car == null or not car.is_inside_tree() or not car.has_method("junction_collision_bodies") or not car.has_method("_route_ahead"): return entry_axis
	if car.get("traffic") != true or car.get("controlled") == true or car.get("external_input") == true: return entry_axis
	if float(car.get("speed")) < -.1 or float(car.get("bypass_side")) != 0.0 or float(car.get("bypass_blend")) > .01 or car.get("_merging_back") == true: return entry_axis
	var route := car.get("route") as Curve3D
	if route == null: return entry_axis
	var bodies: Array = car.call("junction_collision_bodies")
	# Articulated tails need their own complete-turn proof; preserve their entry.
	if bodies.size() != 1 or bodies[0] != car: return entry_axis
	var heading := -car.global_basis.z
	heading.y = 0.0
	heading = heading.normalized()
	var exit_axis := _axis_a(key, heading)
	if exit_axis == entry_axis: return entry_axis
	var axis: Vector2 = axes.get(key, Vector2.RIGHT)
	if not exit_axis: axis = axis.orthogonal()
	if absf(Vector2(heading.x, heading.z).dot(axis)) < .985: return entry_axis
	var length := route.get_baked_length()
	var span := float(car.get("half_length")) + .5
	if length <= span * 2.0: return entry_axis
	var at := route.get_closest_offset(car.global_position)
	var crossed := route.get_closest_offset(junctions[key])
	var open: bool = route.get_meta("traffic_open", false)
	var progress := at - crossed if open else fposmod(at - crossed + length * .5, length) - length * .5
	if progress <= span: return entry_axis
	var center := route.sample_baked(at, true)
	if center.distance_to(car.global_position) > .8: return entry_axis
	var rear := route.sample_baked(maxf(0.0, at - span) if open else fposmod(at - span, length), true)
	var front := route.sample_baked(minf(length, at + span) if open else fposmod(at + span, length), true)
	# As duas metades do casco inteiro precisam ficar no segmento reto de saída.
	if rear.direction_to(center).dot(heading) < .985 or center.direction_to(front).dot(heading) < .985: return entry_axis
	if not occupies(key, id): return entry_axis
	return exit_axis

static func _tight_turn(car: Node3D, key: Vector3i) -> Dictionary:
	if car == null or not car.is_inside_tree() or not car.has_method("_route_ahead"): return {}
	if car.get("traffic") != true or car.get("controlled") == true or car.get("external_input") == true: return {}
	var route := car.get("route") as Curve3D
	if route == null or car.get("_junction_route") != route: return {}
	var rows: Array = car.get("_junction_list")
	for index in rows.size():
		var row: Dictionary = rows[index]
		if row.key != key: continue
		var next_index := index + 1
		if next_index >= rows.size():
			if bool(route.get_meta("traffic_open", false)): return {}
			next_index = 0
		var next: Dictionary = rows[next_index]
		if next.key == key or not junctions.has(next.key): return {}
		var distance := float(next.offset) - float(row.offset)
		if distance <= 0: distance += route.get_baked_length()
		if distance > EXIT * 2.0 + float(car.get("half_length")) * 2.0: return {}
		var delta: Vector3 = junctions[next.key] - junctions[key]
		if absf(delta.y) > .5: return {}
		delta.y = 0
		var heading: Vector3 = row.get("heading", Vector3.ZERO)
		if heading.length_squared() < .01 or delta.length_squared() < .01: return {}
		if absf(heading.normalized().dot(delta.normalized())) >= .7071: return {}
		return {"next":next.key,"heading":heading.normalized()}
	return {}

static func _turn_queue_blocked(key: Vector3i, car: Node3D, gap: float) -> bool:
	var turn := _tight_turn(car,key)
	if turn.is_empty(): return false
	# Os motoristas mantêm um token admitido até a partida. Nesta ligação curta de curva,
	# reservas antecipadas poderiam admitir uma fila inteira antes que o líder chegasse ao
	# cruzamento. Decide na linha de parada, onde a ocupação física da fila é conhecida.
	if gap > 1.6: return true
	for other in _prune(key):
		if other == car.get_instance_id(): continue
		var predecessor := instance_from_id(other) as Node3D
		if predecessor == null or not predecessor.is_inside_tree() or predecessor.get_world_3d() != car.get_world_3d(): continue
		if not occupies(key,other): continue
		var previous := _tight_turn(predecessor,key)
		if previous.is_empty() or previous.next != turn.next: continue
		if (previous.heading as Vector3).dot(turn.heading) > .95: return true
	return false

static func _cross_traffic_inside(key: Vector3i, id: int, axis_a: bool) -> bool:
	var inside := _prune(key)
	var requester := instance_from_id(id) as Node3D
	var world: World3D = requester.get_world_3d() if requester != null and requester.is_inside_tree() else null
	for other in inside:
		if other == id: continue
		# Uma reconstrução do grafo pode sobrepor dois ciclos de vida de cena. Corpos em mundos
		# de física independentes não podem obstruir este solicitante, mesmo em XYZ idêntico.
		if world != null:
			var body := instance_from_id(other) as Node3D
			if body != null and body.is_inside_tree() and body.get_world_3d() != world: continue
		inside[other][0] = _completed_exit_axis(key, other, bool(inside[other][0]))
		if bool(inside[other][0]) == axis_a: continue
		return true
	return false

## Pede entrada. `gap` = distância da frente do carro até a faixa de parada (negativa
## depois dela); `speed` em m/s. true = pode entrar, e o carro passa a ocupar o miolo.
static func request(key: Vector3i, id: int, heading: Vector3, gap: float, speed: float) -> bool:
	var axis_a := _axis_a(key, heading)
	var inside := _prune(key)
	if inside.has(id): return true
	var state := signal_state(key, heading)
	var allowed := false
	match state:
		"green": allowed = true
		# Amarelo: segue só quem não consegue mais parar antes da faixa.
		"amber": allowed = gap < speed * speed / (2.0 * COMFORT_BRAKE) + .5
		"red": allowed = false
		# PARE: para de fato na faixa antes de seguir.
		_: allowed = gap < 1.6 and absf(speed) < .8
	# Quem já passou da faixa (nasceu ali, foi empurrado) não fica parado no meio da via.
	if gap < -1.5: allowed = true
	elif allowed and _cross_traffic_inside(key, id, axis_a): allowed = false
	elif allowed and _turn_queue_blocked(key, instance_from_id(id) as Node3D, gap): allowed = false
	if allowed:
		inside[id] = [axis_a, Time.get_ticks_msec()]
		owners[key] = inside
	return allowed

static func release(key: Vector3i, id: int) -> void:
	var inside: Dictionary = owners.get(key, {})
	inside.erase(id)
	if inside.is_empty(): owners.erase(key)

## Compatibilidade: entrada sem sinal nem distância (usada por quem só quer o miolo).
static func try_enter(key: Vector3i, id: int) -> bool:
	return request(key, id, Vector3.ZERO, -2.0, 0.0)

# --- Lentes --------------------------------------------------------------------------

## A lente `index` de `mesh` encara quem chega ao cruzamento `center` andando em `heading`.
static func register_lens(mesh: MultiMesh, index: int, center: Vector3, heading: Vector3) -> void:
	_lenses.append({"mesh": weakref(mesh), "index": index, "center": center, "heading": heading})
	_next_lens_update = -INF

static func update_lenses() -> void:
	var now := _signal_time()
	if now < _next_lens_update: return
	_next_lens_update = INF
	for i in range(_lenses.size() - 1, -1, -1):
		var lens: Dictionary = _lenses[i]
		var mesh: MultiMesh = lens.mesh.get_ref()
		if mesh == null or int(lens.index) >= mesh.instance_count:
			_lenses.remove_at(i)
			continue
		var center: Vector3 = lens.center
		# O cruzamento do grafo de cada lente é resolvido uma vez por configuração.
		if int(lens.get("gen", -1)) != _generation:
			lens.key = _nearest_junction(center)
			lens.gen = _generation
		var key: Vector3i = lens.key
		var axis_a := true
		# Sem cruzamento no grafo (região sem trânsito ambiente) usa o eixo X do mundo.
		if axes.has(key): axis_a = _axis_a(key, lens.heading)
		else: axis_a = absf((lens.heading as Vector3).normalized().x) >= 0.7071
		var state := _state_at(center, axis_a, now)
		if lens.get("state", "") != state:
			mesh.set_instance_color(int(lens.index), LENS_GREEN if state == "green" else (LENS_AMBER if state == "amber" else LENS_RED))
			# Um sinal é um estado discreto. A interpolação de física não pode misturar
			# vermelho e verde numa cor intermediária depois que a fase muda.
			mesh.reset_instance_physics_interpolation(int(lens.index))
			lens.state = state
		# Os dois eixos mudam nas mesmas fronteiras de meio ciclo. Acorda no primeiro
		# quadro de uma transição real, sem reescrever todas as instâncias a cada quadro.
		var half := CYCLE * .5
		var phase := fposmod(now + _offset(center), half)
		var boundary := GREEN_SECONDS if phase < GREEN_SECONDS else (GREEN_SECONDS + AMBER_SECONDS if phase < GREEN_SECONDS + AMBER_SECONDS else half)
		_next_lens_update = minf(_next_lens_update, now + boundary - phase)

static func _nearest_junction(center: Vector3) -> Vector3i:
	var key := key_of(center)
	if junctions.has(key): return key
	var best := Vector3i.MAX
	var distance := 5.0
	for other in junctions:
		var d := Vector2(junctions[other].x - center.x, junctions[other].z - center.z).length()
		if d < distance:
			distance = d
			best = other
	return best
