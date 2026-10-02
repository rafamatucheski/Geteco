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
## Dono que some ou fica parado além disso sai do miolo (evita trava por carro preso).
const HOLD_LIMIT_MSEC := 9000
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

## Cruzamentos ao longo de uma rota: [{key, offset}] ordenados pelo deslocamento.
static func along(route: Curve3D) -> Array:
	var result: Array = []
	if route == null or junctions.is_empty(): return result
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
		# Signal phases belong to the arrival arm, not to the tangent of a
		# turning curve near its centre (outer lanes may already point across).
		item.heading = Vector3(-approach.x,0,-approach.y)
		var score := .7
		for entry in _approaches.get(key,[]):
			var alignment: float = approach.dot(entry.direction)
			if alignment <= score or not entry.fits: continue
			var stop: Vector2 = entry.stop_position+entry.direction.orthogonal()*entry.width*.25
			var stop_offset := route.get_closest_offset(Vector3(stop.x,center.y,stop.y))
			var distance := fposmod(offset-stop_offset,length) if closed else offset-stop_offset
			# Maximum legal street width/offset/depth can put the stop beyond 30 m.
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

static func _prune(key: Vector3i) -> Dictionary:
	var inside: Dictionary = owners.get(key, {})
	var now := Time.get_ticks_msec()
	for id in inside.keys():
		if not is_instance_id_valid(id) or now - int(inside[id][1]) > HOLD_LIMIT_MSEC: inside.erase(id)
	return inside

static func _cross_traffic_inside(key: Vector3i, id: int, axis_a: bool) -> bool:
	var inside := _prune(key)
	for other in inside:
		if other != id and bool(inside[other][0]) != axis_a: return true
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
			# A signal is a discrete state. Physics interpolation must not blend
			# red and green into an intermediate color after the phase changes.
			mesh.reset_instance_physics_interpolation(int(lens.index))
			lens.state = state
		# Both axes change at the same half-cycle boundaries. Wake on the first
		# frame of a real transition, without rewriting every instance each frame.
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
