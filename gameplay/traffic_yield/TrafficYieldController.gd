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
		if not is_siren_vehicle(vehicle): continue
		var forward: Vector3 = -vehicle.global_basis.z
		if vehicle.speed < 0.0: forward = -forward
		result.append({"vehicle": vehicle, "position": vehicle.global_position, "forward": forward, "speed": absf(vehicle.speed)})
	return result

## Só carros do tráfego ambiente, em rota, inteiros e em jogo.
func _yieldable(vehicle: Variant) -> bool:
	if not is_instance_valid(vehicle) or not vehicle.traffic or vehicle.controlled or vehicle.route == null: return false
	if vehicle.health <= 0.0 or not vehicle.visible or not vehicle.is_physics_processing(): return false
	if vehicle.has_meta("awaiting_ground") or vehicle.get_meta("dispatch_unit", false) or vehicle.get_meta("residence_vehicle", false): return false
	return true

# --- Laço --------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not enabled or world == null or not model.has_graph(): return
	_clock += delta
	var hazards := _hazards()
	for id in agents.keys():
		var agent: RefCounted = agents[id]
		agent.tick(delta, hazards)
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
			if not RULES.threatens(hazard.position, hazard.forward, hazard.speed, vehicle.global_position, -vehicle.global_basis.z, vehicle.half_width): continue
			var agent := AGENT.new()
			if agent.begin(vehicle, model):
				agents[id] = agent
				started += 1
				_emit("started", {"vehicle": vehicle, "mode": agent.mode, "emergency": hazard.vehicle})
			break

func _prune_cooldowns() -> void:
	for id in _cooldown.keys():
		if _clock >= float(_cooldown[id]) or not is_instance_id_valid(id): _cooldown.erase(id)
