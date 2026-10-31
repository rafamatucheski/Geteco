extends Node
## Trânsito ambiente cedendo passagem a viaturas com sirene. Módulo
## independente: não edita Vehicle, NativeTrafficRoutes, ProductionWorld nem o
## despacho; só lê seus contratos públicos e troca `Vehicle.route` dos carros
## ambiente. Pontos de conexão e limitações em README.md.

signal yield_event(event_name: String, data: Dictionary)

const RULES := preload("res://gameplay/traffic_yield/YieldRules.gd")
const MODEL := preload("res://gameplay/traffic_yield/YieldRoadModel.gd")
const AGENT := preload("res://gameplay/traffic_yield/YieldAgent.gd")

var world: Node
var enabled := true
var model: RefCounted
## Callable() -> Array de veículos ambiente. Padrão: `world.production.vehicles`.
var ambient_provider := Callable()
## Callable() -> Array de veículos com sirene candidatos. Padrão: viaturas de
## `world.dispatch.units` e o carro do jogador.
var emergency_provider := Callable()
var agents: Dictionary = {}
var events: Array[Dictionary] = []
var event_limit := 64

var _clock := 0.0
var _scan := 0.0
## instance_id -> instante (tempo simulado) em que o veículo pode voltar a ceder
var _cooldown: Dictionary = {}

func configure(p_world: Node, routes: RefCounted, p_ambient: Callable = Callable(), p_emergency: Callable = Callable()) -> void:
	world = p_world
	model = MODEL.new()
	model.configure(routes)
	ambient_provider = p_ambient
	emergency_provider = p_emergency

## Depois de `traffic_routes.configure(region.roads)`: o grafo mudou.
func refresh_roads(routes: RefCounted) -> void:
	release_all("roads_changed")
	model.configure(routes)

func set_enabled(value: bool) -> void:
	enabled = value
	if not value: release_all("disabled")

## Devolve a rota original a todos (troca de região, desligar, sair da árvore).
func release_all(reason: String) -> void:
	for agent in agents.values(): agent.release()
	agents.clear()
	_emit("released_all", {"reason": reason})

func release_vehicle(vehicle: CharacterBody3D, reason: String) -> void:
	var id:=vehicle.get_instance_id()
	if not agents.has(id): return
	agents[id].release()
	agents.erase(id)
	_cooldown[id]=_clock+RULES.COOLDOWN
	_emit("finished",{"vehicle":vehicle,"reason":reason})

func _exit_tree() -> void:
	release_all("exit")

func status() -> Dictionary:
	var result := {"yielding": agents.size(), "pulling": 0, "held": 0, "merging": 0, "slow": 0}
	for agent in agents.values(): result[agent.mode] += 1
	return result

func _emit(event_name: String, data: Dictionary) -> void:
	var entry := {"name": event_name}
	for key in data: entry[key] = data[key]
	events.append(entry)
	while events.size() > event_limit: events.pop_front()
	yield_event.emit(event_name, data)

# --- Fontes ------------------------------------------------------------------

## Sirene ligada e viatura de emergência de verdade (tem barra de luzes) e
## em serviço: conduzida pelo despacho ou pelo jogador.
func is_siren_vehicle(vehicle: Variant) -> bool:
	if not is_instance_valid(vehicle) or vehicle.health <= 0.0: return false
	var equipment: Variant = vehicle.equipment
	if not is_instance_valid(equipment) or equipment.siren_on != true or equipment.beacons.is_empty(): return false
	return vehicle.controlled or vehicle.get_meta("dispatch_unit", false)

func _candidates() -> Array:
	if emergency_provider.is_valid(): return emergency_provider.call()
	var result: Array = []
	var dispatch: Variant = world.get("dispatch")
	if dispatch != null:
		for unit in dispatch.units:
			if is_instance_valid(unit.vehicle) and not unit.suspended: result.append(unit.vehicle)
	var driving: Variant = world.get("driving")
	if driving != null and driving.occupied and is_instance_valid(driving.car): result.append(driving.car)
	return result

func _ambient() -> Array:
	if ambient_provider.is_valid(): return ambient_provider.call()
	var production: Variant = world.get("production")
	if production != null: return production.vehicles
	return []

func _hazards() -> Array:
	var result: Array = []
	for vehicle in _candidates():
		var needs_room: bool = vehicle.get_meta("dispatch_needs_room",false)
		if not is_siren_vehicle(vehicle) and not needs_room: continue
		var forward: Vector3 = -vehicle.global_basis.z
		if vehicle.speed < 0.0: forward = -forward
		# A intenção de despacho continua significativa enquanto parado. Mantém inalterada
		# a semântica da sirene estacionada do jogador e reserva folga traseira na recuperação.
		var speed: float = absf(vehicle.speed)
		if vehicle.get_meta("dispatch_unit",false): speed = maxf(speed,RULES.MIN_EMERGENCY_SPEED)
		result.append({"vehicle": vehicle, "position": vehicle.global_position, "forward": forward, "speed":speed,"rear":needs_room})
	return result

## Só carros do tráfego ambiente, em rota, inteiros e em jogo.
func _yieldable(vehicle: Variant) -> bool:
	if not is_instance_valid(vehicle) or not vehicle.traffic or vehicle.controlled or vehicle.route == null: return false
	if vehicle.traffic_escape!=null and (vehicle.traffic_escape.active or vehicle.traffic_escape.retiring): return false
	# Comboios usam a física de trânsito mas continuam donos da rota privada deles.
	if vehicle.get_meta("armored_transport", false): return false
	if vehicle.health <= 0.0 or not vehicle.visible or not vehicle.is_physics_processing(): return false
	if vehicle.has_meta("awaiting_ground") or vehicle.get_meta("dispatch_unit", false) or vehicle.get_meta("residence_vehicle", false): return false
	return true

# --- Laço --------------------------------------------------------------------

const _SYS_SPAN := preload("res://runtime/StallWorkTrace.gd")
## Span do sistema inteiro (22/10): quadros de 30–60 ms com o tempo em _process sem nenhum span.
func _physics_process(delta: float) -> void:
	var span := _SYS_SPAN.begin()
	_physics_process_traced(delta)
	_SYS_SPAN.finish_slow("sys.traffic_yield.physics", span, 3000)

func _physics_process_traced(delta: float) -> void:
	if not enabled or world == null or not model.has_graph(): return
	_clock += delta
	var hazards := _hazards()
	for id in agents.keys():
		var agent: RefCounted = agents[id]
		var tick_span := _SYS_SPAN.begin()
		agent.tick(delta, hazards)
		_SYS_SPAN.finish_slow("traffic_yield.tick", tick_span, 2000)
		if agent.finished:
			_cooldown[id] = _clock + RULES.COOLDOWN
			agents.erase(id)
			_emit("finished", {"vehicle": agent.vehicle, "reason": agent.end_reason})
	_scan -= delta
	if _scan > 0.0: return
	_scan = RULES.SCAN_INTERVAL
	if hazards.is_empty():
		# Sem sirene em campo, nenhum carro nasce cedendo; limpa validades antigas.
		_prune_cooldowns()
		return
	var started := 0
	for vehicle in _ambient():
		# Montar a curva varre o grafo e faz consultas físicas: poucas por varredura.
		if agents.size() >= RULES.MAX_YIELDERS or started >= RULES.MAX_STARTS_PER_SCAN: return
		if not _yieldable(vehicle): continue
		var id: int = vehicle.get_instance_id()
		if agents.has(id) or _clock < float(_cooldown.get(id, 0.0)): continue
		for hazard in hazards:
			if hazard.vehicle == vehicle: continue
			var threatened: bool = RULES.threatens(hazard.position,hazard.forward,hazard.speed,vehicle.global_position,-vehicle.global_basis.z,vehicle.half_width)
			var relative: Vector2 = RULES.relative(hazard.position,hazard.forward,vehicle.global_position)
			if hazard.rear and relative.x > -18 and relative.x < 0 and relative.y < RULES.CORRIDOR: threatened = true
			if not threatened: continue
			if hazard.rear and relative.x < 0 and vehicle.speed<.6 and vehicle.traffic_rear_clear(3.0):
				# Primeiro cria espaço longitudinal, depois encosta numa curva validada.
				if not model.in_junction(vehicle.global_position):
					vehicle.backoff_time = maxf(vehicle.backoff_time,1.6)
			var agent := AGENT.new()
			# Span (22/10): o controlador chegou a 10 ms num quadro de física no estresse do porto.
			var begin_span := _SYS_SPAN.begin()
			var began_ok: bool = agent.begin(vehicle, model)
			_SYS_SPAN.finish_slow("traffic_yield.begin", begin_span, 2000)
			if began_ok:
				agents[id] = agent
				started += 1
				_emit("started", {"vehicle": vehicle, "mode": agent.mode, "emergency": hazard.vehicle})
			break

func _prune_cooldowns() -> void:
	for id in _cooldown.keys():
		if _clock >= float(_cooldown[id]) or not is_instance_id_valid(id): _cooldown.erase(id)
