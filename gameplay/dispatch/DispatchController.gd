extends Node3D
## Controlador independente de despacho físico. Não substitui o sistema de
## procurado (Gameplay.gd) nem o de atendimento (EmergencyManager): lê as
## estrelas, a última posição conhecida e o registro de ocorrências que eles já
## mantêm e coloca viaturas reais, dirigidas pelas ruas, para responder.
## Contrato de integração em gameplay/dispatch/README.md.

signal dispatch_event(event_name: String, data: Dictionary)

const RULES := preload("res://gameplay/dispatch/DispatchRules.gd")
const ROUTER := preload("res://gameplay/dispatch/DispatchRoadRouter.gd")
const DRIVER := preload("res://gameplay/dispatch/DispatchDriver.gd")
const UNIT := preload("res://gameplay/dispatch/DispatchUnit.gd")
const OFFICER := preload("res://gameplay/dispatch/DispatchOfficer.gd")
const BRIDGE := preload("res://gameplay/dispatch/DispatchIncidentBridge.gd")
const RESPONDER := preload("res://gameplay/emergency/Responder.gd")
const VEHICLE := preload("res://gameplay/dispatch/DispatchVehicle.gd")
const ROADBLOCKS := preload("res://gameplay/police_response/ground/PoliceRoadblocks.gd")
const TRACE := preload("res://gameplay/dispatch/DispatchTrace.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
## Mesmo interruptor de NativeRegion.request_collision_soon (GETECO_COLLISION_LOOKAHEAD=0 desliga).
static var _collision_lookahead := OS.get_environment("GETECO_COLLISION_LOOKAHEAD") != "0"
const WORLD_CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
const PURSUIT := preload("res://gameplay/dispatch/PursuitRules.gd")
const RADIO := preload("res://gameplay/dispatch/PursuitRadio.gd")
const RADIO_AUDIO := preload("res://gameplay/dispatch/PursuitRadioAudio.gd")
# Cada candidato pode custar um plano de rota (~2,2 ms): 8 geravam picos de 22–53 ms
# no quadro de despacho. Candidatos que falham voltam no próximo intervalo.
const SPAWN_CANDIDATES_CHECKED := 3
## Clearance is cheap; a blocked nearby spawn must not starve a wider tank or
## ambulance forever. Route planning retains the original three-plan budget.
const POLICE_CLEARANCE_CANDIDATES := 8
## Serviço (bombeiro/ambulância) compara mais pontos: a rota curta importa mais que
## o custo de planejar alguns candidatos a mais, e o despacho é raro.
const SPAWN_CANDIDATES_CHECKED_SERVICE := 8
## Candidatos planejados por quadro na busca de ponto de partida da emergência.
const SERVICE_SEARCH_BUDGET := 2
const MAX_WRECKS := 4
const DOOR_WARM_BUDGET_USEC := 1000
## P9 (13/10): o preparo da porta (`warm_doors`) era ~95% de `controller.tick` nos quadros
## lentos da perseguição (19 de 19 quadros com tick >= 20 ms no editor) e cada veículo custa
## ~25-45 chamadas sempre acima do orçamento de 1 ms (logs de 12-13/10 e
## tests/measure/probe_dispatch_door_warm.gd). Ligado, só prepara a porta de quem vai descer
## por ela (ver DispatchUnit.door_warm_wanted). GETECO_DISPATCH_FAST=0 volta ao de antes.
static var fast := OS.get_environment("GETECO_DISPATCH_FAST") != "0"

var world: Node3D
var gameplay: Node3D
var routes: RefCounted
var router: RefCounted
var bridge: Node3D
var enabled := true
var _owns_dispatch := false
## service -> Array[Vector3] de pontos de garagem/pátio sobre uma rua. Sem entrada,
## o nascimento é em faixa fora da vista, como o despacho regional da V1.
var depots: Dictionary = {}
var units: Array = []
var wrecks: Array[CharacterBody3D] = []
var events: Array[Dictionary] = []
var event_limit := 64
var deployed_this_pursuit := 0
## Dentro de interiores a posição do jogador é a do interior (longe do mapa):
## o integrador aponta aqui a porta exterior para que as unidades não sejam
## suspensas por distância. Vector3.INF desliga.
var player_position_override := Vector3.INF

var no_exclusions: Array[RID] = []
var _serial := 0
var _police_clock := 0.0
var _last_stars := 0
var _search_pending := false
var _service_clock := 0.0
var _scan_clock := 0.0
var _wreck_clock := 0.0
var _clock := 0.0
var _door_warm_frame := -1
var _door_warm_cursor := 0
var _prepared_ground_cells: Dictionary = {}
var roadblocks: RefCounted
var investigation_unit: RefCounted
var _investigation_clock := 0.0
var _investigation_seen := false
## Instante (_clock) antes do qual nenhum caminhão novo é despachado: o anterior foi destruído.
var _fire_lockout_until := 0.0

# Perseguição estilo GTA (PursuitRules)
## O último contato foi com o jogador dirigindo: a busca é em leque pela área, sem descer a pé.
var pursuit_in_car := false
## Velocidade do carro no último contato (estimativa de para onde ele foi nos primeiros segundos).
var pursuit_velocity := Vector3.ZERO
## Contadores para testes e depuração (pit, guide_*, block_*, search_point, outrun, spawn_ahead).
var pursuit_stats: Dictionary = {}
var radio := RADIO.new()
## Voz do rádio (criada na primeira fala; PursuitRadioAudio pede os WAVs em segundo plano).
var radio_voice: Node
var _search_points: Array[Vector3] = []
var _search_center := Vector3.INF
var _search_stars := -1
var _search_rng := RandomNumberGenerator.new()
var _had_contact := false
var _radio_stars := 0
## Auxiliares sem estado (01/11, só para este arquivo caber na leitura): o estado continua aqui, e cada
## função antiga virou delegação de uma linha, então DispatchUnit, PoliceHelicopter e os testes que
## chamam `_space_clear`, `_active_police`, `dispatch_police_to` etc. por nome não mudam. Criados na
## declaração, e não em _ready, para valer também num controlador montado fora da árvore.
const SPACE_QUERIES := preload("res://gameplay/dispatch/DispatchSpaceQueries.gd")
const POLICE_ASSIGN := preload("res://gameplay/dispatch/DispatchPoliceAssign.gd")
const EMERGENCY_ASSIGN := preload("res://gameplay/dispatch/DispatchEmergencyAssign.gd")
var _space_queries: SPACE_QUERIES = SPACE_QUERIES.new(self)
var _police_assign: POLICE_ASSIGN = POLICE_ASSIGN.new(self)
var _emergency_assign: EMERGENCY_ASSIGN = EMERGENCY_ASSIGN.new(self)

func configure(p_world: Node3D, p_gameplay: Node3D, p_routes: RefCounted) -> void:
	world = p_world
	gameplay = p_gameplay
	routes = p_routes
	router = ROUTER.new()
	router.configure(routes)
	roadblocks = ROADBLOCKS.new()
	roadblocks.configure(self)
	claim_dispatch()

func _ready() -> void:
	if _owns_dispatch: claim_dispatch()
	# A voz do rádio pede os WAVs em segundo plano já na carga, para a primeira fala não sair muda.
	if PURSUIT.enabled and radio_voice == null:
		radio_voice = RADIO_AUDIO.new()
		add_child(radio_voice)

## Chamar quando o mapa trocar (`traffic_routes.configure(region.roads)`).
func refresh_roads() -> void:
	router.configure(routes)

func set_depots(service: String, points: Array) -> void:
	depots[service] = points

func _exit_tree() -> void:
	# Os carros são filhos de `world`, não deste nó: sem isto ficariam órfãos.
	_restore_legacy()
	dismiss_all("exit")

func _ensure_bridge() -> bool:
	if is_instance_valid(bridge): return true
	bridge = null
	if gameplay == null or gameplay.emergency == null: return false
	bridge = BRIDGE.new()
	bridge.setup(gameplay.emergency)
	bridge.crew_released.connect(_on_crew_released)
	add_child(bridge)
	return true

# --- Eventos -----------------------------------------------------------------

func emit_dispatch_event(event_name: String, data: Dictionary) -> void:
	var entry := {"name": event_name}
	var unit: Variant = data.get("unit")
	if unit != null:
		entry["unit"] = unit.label()
		entry["service"] = unit.service
	for key in data:
		if key != "unit": entry[key] = data[key]
	events.append(entry)
	while events.size() > event_limit: events.pop_front()
	dispatch_event.emit(event_name, data)

func events_named(event_name: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in events:
		if entry.name == event_name: result.append(entry)
	return result

func witness_call(point: Vector3) -> void:
	if not enabled or gameplay == null or gameplay.stars <= 0: return
	_police_clock = minf(_police_clock, 1.5)
	emit_dispatch_event("witness_call", {"point": point})

# --- Laço --------------------------------------------------------------------

const _SYS_SPAN := preload("res://runtime/StallWorkTrace.gd")
## Span do sistema inteiro (22/10): quadros de 30–60 ms com o tempo em _process sem nenhum span.
func _physics_process(delta: float) -> void:
	var span := _SYS_SPAN.begin()
	_physics_process_traced(delta)
	_SYS_SPAN.finish_slow("sys.dispatch.physics", span, 3000)

func _physics_process_traced(delta: float) -> void:
	if not enabled or gameplay == null or world == null or not _ensure_bridge(): return
	TRACE.refresh(world)
	var traced := TRACE.begin()
	_clock += delta
	router.advance(delta)
	_warm_approaching_doors()
	for unit in units.duplicate():
		var unit_began := TRACE.begin()
		var unit_label := "unit.tick:%s:%s" % [unit.service, unit.state] if unit_began != 0 else ""
		_prepare_unit_ground(unit)
		unit.tick(delta)
		if unit_began != 0: TRACE.end(unit_label, unit_began)
		if unit.finished:
			if unit.service == "fire" and unit.wrecked: _fire_lockout_until = _clock + RULES.FIRE_REPLACEMENT_MIN + randf() * RULES.FIRE_REPLACEMENT_SPREAD
			_prepared_ground_cells.erase(unit.get_instance_id())
			units.erase(unit)
	var step := TRACE.begin()
	if PURSUIT.enabled: _tick_pursuit_awareness()
	_dispatch_police(delta)
	TRACE.end("police.dispatch_step", step)
	if roadblocks != null:
		step = TRACE.begin()
		roadblocks.tick(delta)
		TRACE.end("roadblocks.tick", step)
	step = TRACE.begin()
	_dispatch_emergency(delta)
	TRACE.end("emergency.dispatch_step", step)
	_wreck_clock -= delta
	if _wreck_clock <= 0.0:
		_wreck_clock = 2.0
		step = TRACE.begin()
		_tidy_wrecks()
		TRACE.end("wrecks.tidy", step)
	TRACE.end("controller.tick", traced)
	TRACE.flush(self)

## Uma equipe se aproximando por quadro renderizado, compartilhada entre todas as unidades de despacho.
## O builder avança por partes inteiras de malha; mede o tempo real gasto em vez
## de tratar o orçamento pedido como prazo rígido. O envio mantém
## o fallback imediato existente se a preparação não terminou.
func _warm_approaching_doors() -> void:
	var frame := Engine.get_process_frames()
	if _door_warm_frame == frame: return
	_door_warm_frame = frame
	if units.is_empty(): return
	# Viatura já estacionada com a equipe a bordo vem primeiro: a descida espera a porta pronta
	# (DispatchUnit._doors_ready) e o rodízio entre várias viaturas a atrasava.
	var first := -1
	for index in (units.size() if UNIT.quick_exit else 0):
		var parked: RefCounted = units[index]
		if parked.state == "parked" and not parked.finished and not parked.wrecked and parked.crew_remaining > 0 \
				and is_instance_valid(parked.vehicle) and not parked.vehicle.get_meta("dispatch_doors_warmed", false):
			first = index
			break
	for attempt in units.size():
		var unit: RefCounted = units[(first if attempt == 0 and first >= 0 else _door_warm_cursor) % units.size()]
		if attempt > 0 or first < 0: _door_warm_cursor += 1
		if unit.finished or unit.wrecked or unit.suspended or unit.crew_remaining <= 0 or unit.state not in ["enroute", "parked"]: continue
		# Sem o método (dublês de teste), mantém a regra de antes.
		if fast and unit.has_method("door_warm_wanted") and not unit.door_warm_wanted(): continue
		var candidate: Variant = unit.vehicle
		if not is_instance_valid(candidate) or not candidate is CharacterBody3D: continue
		var car := candidate as CharacterBody3D
		if car.is_queued_for_deletion() or not car.is_inside_tree() or car.health <= 0: continue
		if car.get_meta("dispatch_doors_warmed", false): continue
		var began := STALL_WORK.begin()
		var ready: bool = car.warm_doors(DOOR_WARM_BUDGET_USEC)
		STALL_WORK.finish_slow("dispatch.doors.prewarm", began, 1000, car)
		if ready: car.set_meta("dispatch_doors_warmed", true)
		return

func _prepare_unit_ground(unit: RefCounted) -> void:
	var traced := STALL_WORK.begin()
	_stall_prepare_unit_ground(unit)
	if traced == 0: return
	var source: Node = unit.vehicle as Node if unit != null and is_instance_valid(unit.vehicle) else null
	STALL_WORK.finish_slow("dispatch.unit.prepare_ground_total", traced, 5000, source)

func _stall_prepare_unit_ground(unit: RefCounted) -> void:
	if unit == null or unit.finished or not is_instance_valid(unit.vehicle) or not is_instance_valid(world): return
	# Admite o piso antes que o contrato de suspensão existente cheque a retomada.
	if unit.suspended and distance_to_player(unit.vehicle.global_position) > RULES.RESUME_DISTANCE: return
	var production: Variant = world.get("production")
	if production == null: return
	var residents_value: Variant = production.get("regions")
	if not residents_value is Dictionary: return
	var residents: Dictionary = residents_value
	var car: CharacterBody3D = unit.vehicle
	var ahead := car.global_position-car.global_basis.z*12.0
	if _collision_lookahead:
		# Chão bem à frente pela fila fatiada (~2,5 s de estrada, mínimo 36 m): quando os 12 m chegam lá,
		# a célula já está pronta e prepare_collision_at abaixo não monta nada no quadro.
		var lookahead := car.global_position-car.global_basis.z*maxf(36.0,absf(float(car.get("speed")))*2.5)
		var far_region: Node3D = residents.get(WORLD_CONNECTION.logical_region(lookahead)) as Node3D
		if is_instance_valid(far_region) and far_region.has_method("request_collision_soon"): far_region.request_collision_soon(lookahead)
	var unit_id := unit.get_instance_id()
	var previous: Dictionary = _prepared_ground_cells.get(unit_id,{})
	var prepared: Dictionary = {}
	var traced := TRACE.begin()
	var built := 0
	var finished_jobs := 0
	var admitted := 0
	# Corpo e antecipação podem estar em lados distintos da costura, na mesma célula.
	for point: Vector3 in [car.global_position,ahead]:
		var region: Node3D = residents.get(WORLD_CONNECTION.logical_region(point)) as Node3D
		if not is_instance_valid(region) or not region.has_method("prepare_collision_at"): continue
		var cell: Vector2i = region._cell(point)
		var key := "%d:%d:%d" % [region.get_instance_id(),cell.x,cell.y]
		var chunk: Node3D = region.chunks.get(cell) as Node3D
		var chunk_id: int = chunk.get_instance_id() if is_instance_valid(chunk) and not chunk.is_queued_for_deletion() else 0
		# O memo não certifica chunks podados/recriados nem outro proprietário residente.
		if chunk_id != 0 and (previous.get(key,0) == chunk_id or prepared.get(key,0) == chunk_id):
			prepared[key] = chunk_id
			continue
		var chunks_before: int = region.chunks.size() if traced != 0 else 0
		var jobs_before: int = region.build_jobs.size() if traced != 0 else 0
		region.prepare_collision_at(point)
		admitted += 1
		chunk = region.chunks.get(cell) as Node3D
		if is_instance_valid(chunk) and not chunk.is_queued_for_deletion(): prepared[key] = chunk.get_instance_id()
		if traced != 0:
			built += region.chunks.size()-chunks_before
			finished_jobs += jobs_before-region.build_jobs.size()
	_prepared_ground_cells[unit_id] = prepared
	if traced != 0 and admitted > 0:
		TRACE.end("prepare_ground.build" if built > 0 or finished_jobs > 0 else "prepare_ground", traced, {"chunks_built":built,"jobs_finished":finished_jobs,"cell":str(Vector4(floorf(car.global_position.x/64.0),floorf(car.global_position.z/64.0),floorf(ahead.x/64.0),floorf(ahead.z/64.0))),"owners":prepared.keys()})

## Reivindica antes da restauração de inicialização, mesmo com o controlador desligado.
## Esses bloqueios só afetam o despacho; o decaimento de procurado e a limpeza de incidentes continuam.
func claim_dispatch() -> void:
	_owns_dispatch = true
	if not is_instance_valid(gameplay): return
	gameplay.dispatch_owned = true
	if is_instance_valid(gameplay.emergency): gameplay.emergency.dispatch_owned = true

func _restore_legacy() -> void:
	if not _owns_dispatch: return
	_owns_dispatch = false
	if gameplay == null or not is_instance_valid(gameplay): return
	gameplay.dispatch_owned = false
	if is_instance_valid(gameplay.emergency): gameplay.emergency.dispatch_owned = false

func set_enabled(value: bool, release_ownership := true) -> void:
	enabled = value
	if value:
		claim_dispatch()
	else:
		dismiss_all("disabled")
		if release_ownership: _restore_legacy()
		else: claim_dispatch()

## Recolhe todas as viaturas (troca de região, "Leavemealone", desligar o módulo).
## Equipes a pé e viaturas somem sem animação; ocorrências voltam ao gerente real.
## É REMOÇÃO IMEDIATA: `unit.finish` descarta o estado de ultrapassagem sem
## recuperação física (`driver.discard_overtaking`), porque o veículo é liberado.
## Redirecionar/cancelar com o veículo em jogo (`cancel_incident`, fim da procura,
## partida) passa por `driver.cancel_overtaking`, que recupera fisicamente.
func dismiss_all(reason: String) -> void:
	if roadblocks != null: roadblocks.clear()
	investigation_unit = null
	radio.reset()
	if is_instance_valid(radio_voice): radio_voice.stop()
	pursuit_in_car = false
	_had_contact = false
	_radio_stars = 0
	_search_points.clear()
	_search_center = Vector3.INF
	for unit in units.duplicate(): unit.finish(reason)
	units.clear()
	# Corpos já filtrados de uma equipe continuam filhos do controlador durante
	# seu decaimento. Em troca de região/load/desativação eles também precisam sair.
	for child in get_children():
		if child == bridge: continue
		if child.get_meta("gameplay_role", "") in ["police", "emergency"]:
			child.queue_free()
	for wreck in wrecks:
		if is_instance_valid(wreck): wreck.queue_free()
	wrecks.clear()

## Cancela a viatura que atende a ocorrência `key`; a equipe volta e a viatura parte.
func cancel_incident(key: int) -> bool:
	for unit in units:
		if not unit.is_police() and unit.incident_id == key and not unit.finished:
			unit.abort_response()
			return true
	return false

func status() -> Dictionary:
	var result := {"units": units.size(), "police": 0, "medic": 0, "fire": 0, "mortician": 0, "foot_officers": foot_officer_count(), "wrecks": wrecks.size(), "suspended": 0, "stranded": stranded_count(), "released_slots": _released_slots().size()}
	for unit in units:
		result[unit.service] += 1
		if unit.suspended: result.suspended += 1
	return result

# --- Consultas compartilhadas ---------------------------------------------------

func player_position() -> Vector3:
	if player_position_override != Vector3.INF: return player_position_override
	var driving: Variant = world.get("driving")
	if driving != null and driving.occupied and is_instance_valid(driving.car): return driving.car.global_position
	return gameplay.player.global_position

func distance_to_player(point: Vector3) -> float:
	var reference := player_position()
	return Vector2(point.x - reference.x, point.z - reference.z).length()

func is_visible_to_player(point: Vector3) -> bool:
	if not is_inside_tree(): return false
	var camera := get_viewport().get_camera_3d()
	if camera == null: return false
	return camera.is_position_in_frustum(point + Vector3.UP) and camera.global_position.distance_to(point) < 250.0

func is_unseen(point: Vector3) -> bool:
	return not is_visible_to_player(point)

func foot_officer_count() -> int:
	var count := int(gameplay.get_meta("police_air_reserved_slots",0))
	for officer in gameplay.police:
		if is_instance_valid(officer) and not officer.dead: count += 1
	for unit in units:
		for officer in unit.officers:
			if is_instance_valid(officer) and not officer.dead: count += 1
	return count

## Transfere a posse sem repor a equipe. O controlador de interior
## acrescenta este mesmo agente físico a Gameplay.police depois de uma entrada segura contra colisão.
func take_agent_for_interior(officer: CharacterBody3D) -> bool:
	for unit in units:
		if not unit.officers.has(officer): continue
		unit.officers.erase(officer)
		unit.driver.ignore.erase(officer.get_rid())
		if officer.boarded.is_connected(unit.on_officer_boarded): officer.boarded.disconnect(unit.on_officer_boarded)
		officer.dispatch_controller = null
		officer.vehicle = null
		return true
	return false

## Unidades encalhadas (partindo com recuperação física pendente há STRANDED_SLOT_SECONDS)
## cuja vaga de perfil é liberada, as mais antigas primeiro e no máximo
## MAX_STRANDED_RELEASED. É só a vaga de MAX_ACTIVE/MAX_CREWS: o veículo continua contado
## em `units.size()` contra MAX_UNITS, então o total de carros vivos segue limitado.
func _released_slots() -> Array:
	var candidates: Array = units.filter(func(u): return not u.finished and u.state == "departing" and u.stranded)
	candidates.sort_custom(func(a, b): return a.stranded_age > b.stranded_age)
	return candidates.slice(0, RULES.MAX_STRANDED_RELEASED)

## Polícia partindo normalmente não conta em MAX_ACTIVE (já era assim). Partindo
## ENCALHADA por recuperação passa a contar de novo, exceto as até MAX_STRANDED_RELEASED
## mais antigas: sem isso as encalhadas encheriam MAX_UNITS sem que nada as limitasse.
func _active_police() -> Array:
	var released := _released_slots()
	# "recall" é a viatura parada esperando a equipe a pé voltar (o jogador fugiu de carro): ela não
	# persegue ninguém, então não ocupa vaga de MAX_ACTIVE. Contando, com o teto de 5 (antes 8) as
	# recalls enchiam as vagas e nenhuma viatura nova aparecia diante de quem fugia (log de 2026-10-01).
	return units.filter(func(u): return u.is_police() and not u.finished and u.state != "recall" and (u.state != "departing" or (u.stranded and not released.has(u))))

## Serviços contam em MAX_CREWS até sair de cena, exceto as encalhadas com vaga liberada.
func _active_services() -> Array:
	var released := _released_slots()
	return units.filter(func(u): return not u.is_police() and not u.finished and not released.has(u))

## Quantas unidades estão encalhadas (todas, liberadas ou não).
func stranded_count() -> int:
	return units.filter(func(u): return not u.finished and u.state == "departing" and u.stranded).size()

## Consultas de espaço (vaga livre, cápsula, saída pela porta): corpo em DispatchSpaceQueries.gd (delegação de uma linha; mesmo nome e padrões).
func _space_clear(size: Vector3, point: Vector3, yaw: float, exclude: Array[RID]) -> bool: return _space_queries._space_clear(size, point, yaw, exclude)
func capsule_clear(point: Vector3, exclude: Array[RID]) -> bool: return _space_queries.capsule_clear(point, exclude)
func footprint_clear(car: CharacterBody3D, point: Vector3, yaw: float) -> bool: return _space_queries.footprint_clear(car, point, yaw)
func _archetype_size(archetype: String) -> Vector3: return _space_queries._archetype_size(archetype)
func exit_point_at(car: CharacterBody3D, point: Vector3, yaw: float) -> Dictionary: return _space_queries.exit_point_at(car, point, yaw)
func exit_point(car: CharacterBody3D, taken: Array[Vector3], right_only: bool, at := Transform3D.IDENTITY) -> Dictionary: return _space_queries.exit_point(car, taken, right_only, at)

# --- Criação de veículos e equipes ---------------------------------------------

func _create_vehicle(service: String, point: Vector3, yaw: float, archetype := "") -> CharacterBody3D:
	var car := VEHICLE.new()
	car.archetype = archetype if not archetype.is_empty() else RULES.archetype_for(service)
	car.paint_color = Color("202128") if service == "mortician" or car.archetype == "police_transport" else Color.WHITE
	if car.archetype == "army_tank": car.paint_color = Color("64704e")
	car.vehicle_id = "dispatch_%s_%d" % [service, _serial]
	car.set_meta("dispatch_unit", true)
	var traced := TRACE.begin()
	world.add_child(car)
	if traced != 0:
		TRACE.end("vehicle.add_child:" + car.archetype, traced)
		traced = TRACE.begin()
	car.place(point + Vector3.UP * 0.12, yaw)
	# Ambulância, bombeiro e rabecão não são carros que o jogador possa pegar. A viatura
	# policial parada pode ser roubada: `vehicle_stolen` expulsa quem estava a bordo.
	if service != "police": car.remove_from_group("drivable")
	car.destroyed.connect(func():
		if is_instance_valid(car) and is_instance_valid(gameplay):
			gameplay.explode(car.global_position+Vector3.UP*.4,5.0,35.0,car,false)
			if is_instance_valid(gameplay.emergency):
				gameplay.emergency.ignite(car.global_position, car))
	if service != "mortician": car.ensure_equipment(world)
	if traced != 0: TRACE.end("vehicle.place_equipment:" + car.archetype, traced)
	return car

## Chamado por Driving.gd quando o jogador começa a entrar numa viatura em serviço.
func vehicle_stolen(car: CharacterBody3D, _thief_side: int) -> bool:
	for unit in units:
		if unit.vehicle != car or unit.finished: continue
		if not unit.is_police(): return false
		# Reserve uma saída física para cada ocupante antes de transferir o carro.
		# Se faltar espaço, ninguém é criado dentro de um sólido e o roubo não começa.
		var exits: Array[Dictionary] = []
		var reserved: Array[Vector3] = []
		for index in unit.crew_remaining:
			var exit: Dictionary = exit_point(car, reserved, false)
			if exit.is_empty(): return false
			exits.append(exit)
			reserved.append(exit.point)
		unit.surrender_vehicle(exits)
		car.remove_meta("dispatch_unit")
		car.player_damage_attribution = true
		if is_instance_valid(gameplay): gameplay.register_crime(40, car.global_position)
		return true
	return false

func _make_unit(service: String, car: CharacterBody3D, speed_cap: float, stall: float) -> RefCounted:
	var unit := UNIT.new()
	unit.controller = self
	unit.service = service
	unit.vehicle = car
	unit.driver = DRIVER.new()
	unit.driver.setup(car, speed_cap, stall)
	unit.driver.enable_overtaking(routes, true)
	# Eventos de recuperação de ultrapassagem entram no mesmo registro (`events`), sem HUD.
	unit.driver.overtake_unresolved_changed.connect(unit.on_overtake_unresolved)
	unit.driver.overtake_state_changed.connect(unit.on_overtake_state)
	unit.driver.replan_requested.connect(unit.on_replan_requested)
	unit.driver.gave_up.connect(unit.on_gave_up)
	units.append(unit)
	return unit

func spawn_officer(unit: RefCounted, point: Vector3, side: float) -> CharacterBody3D:
	var traced := TRACE.begin()
	var officer := OFFICER.new()
	officer.controller = gameplay
	officer.dispatch_controller = self
	officer.tier = RULES.officer_tier_for(unit.level, unit.variant)
	officer.motorcycle_officer = unit.variant == "motorcycle"
	officer.last_known = gameplay.last_known
	officer.vehicle = unit.vehicle
	officer.door_side = side
	officer.boarded.connect(unit.on_officer_boarded)
	add_child(officer)
	officer.add_collision_exception_with(unit.vehicle)
	officer.global_position = OFFICER.inside_point(unit.vehicle, point, side)
	officer.begin_disembark(unit.vehicle, point, side)
	unit.driver.ignore.append(officer.get_rid())
	if traced != 0: TRACE.end("officer.spawn:tier%d" % officer.tier, traced)
	return officer

func spawn_responder(unit: RefCounted, point: Vector3) -> CharacterBody3D:
	var traced := TRACE.begin()
	var responder := RESPONDER.new()
	responder.manager = bridge
	responder.role = unit.service
	responder.incident_id = unit.incident_id
	responder.destination = unit.actor.global_position
	responder.vehicle = unit.vehicle
	bridge.roles[unit.incident_id] = unit.service
	add_child(responder)
	responder.global_position = point
	unit.driver.ignore.append(responder.get_rid())
	if traced != 0: TRACE.end("responder.spawn:" + unit.service, traced)
	return responder

## A ocorrência passa a apontar para o Responder real (antes apontava para a viatura).
func claim_incident(unit: RefCounted) -> void:
	var emergency: Node3D = gameplay.emergency
	if not emergency.incidents.has(unit.incident_id): return
	var record: Dictionary = emergency.incidents[unit.incident_id]
	record.assigned = true
	record.crew = unit.crew

func _on_crew_released(crew: CharacterBody3D) -> void:
	for unit in units:
		if unit.crew == crew:
			unit.on_crew_released(crew)
			return
	# Equipe sem viatura registrada (viatura já removida): não fica órfã na cena.
	if is_instance_valid(crew): crew.queue_free()

func adopt_wreck(car: CharacterBody3D) -> void:
	car.set_meta("dispatch_wreck_at", _clock)
	wrecks.append(car)

func _tidy_wrecks() -> void:
	wrecks = wrecks.filter(func(car): return is_instance_valid(car))
	var driving: Variant = world.get("driving") if is_instance_valid(world) else null
	for car in wrecks.duplicate():
		if car.controlled or (driving != null and driving.car == car):
			wrecks.erase(car)
			continue
		var old: bool = _clock - float(car.get_meta("dispatch_wreck_at", _clock)) > 30.0
		# Carcaça some em 30 s mesmo à vista, com o fade do Vehicle. Só a viatura
		# inteira abandonada (vida > 0) fica para ser roubada, e a que ainda tem equipe a pé.
		if old and car.health <= 0.0 and car.get_meta("wreck_hold", false) != true and float(car.get("_wreck_fade")) < 0.0:
			car.call("_begin_wreck_fade")
			continue
		if (old or wrecks.size() > MAX_WRECKS) and is_unseen(car.global_position) and distance_to_player(car.global_position) > RULES.RECYCLE_DISTANCE:
			wrecks.erase(car)
			car.queue_free()

# --- Polícia -----------------------------------------------------------------

## Polícia (despacho, reforço à frente, busca em leque, rádio): corpo em DispatchPoliceAssign.gd (delegação de uma linha; mesmo nome e padrões).
func _dispatch_police(delta: float) -> void: _police_assign._dispatch_police(delta)
func _tactical_van_replacement(level: int, active: Array, responding: Array, armor_support := false) -> RefCounted: return _police_assign._tactical_van_replacement(level, active, responding, armor_support)
func dispatch_police_to(anchor: Vector3, investigation: bool = false) -> RefCounted: return _police_assign.dispatch_police_to(anchor, investigation)
func _spawn_ahead_direction(investigation: bool) -> Dictionary: return _police_assign._spawn_ahead_direction(investigation)
func radio_line() -> String: return _police_assign.radio_line()
func count_pursuit(key: String) -> void: _police_assign.count_pursuit(key)
func recycle_outrun(unit: RefCounted) -> void: _police_assign.recycle_outrun(unit)
func search_point_for(unit: RefCounted) -> Vector3: return _police_assign.search_point_for(unit)
func announce(event: String, street := "", heading := "", urgent := false) -> bool: return _police_assign.announce(event, street, heading, urgent)
func _speak(urgent: bool) -> void: _police_assign._speak(urgent)
func _tick_pursuit_awareness() -> void: _police_assign._tick_pursuit_awareness()
func retain_investigator(unit: RefCounted) -> bool: return _police_assign.retain_investigator(unit)

# --- Emergência ----------------------------------------------------------------

## Serviços de emergência (escolha da ocorrência e despacho fatiado): corpo em DispatchEmergencyAssign.gd (delegação de uma linha; mesmo nome e padrões).
func _dispatch_emergency(delta: float) -> void: _emergency_assign._dispatch_emergency(delta)
func _depot_candidates(service: String, target: Vector3) -> Array[Dictionary]: return _emergency_assign._depot_candidates(service, target)
func dispatch_service_to(key: int, budget: int = -1) -> RefCounted: return _emergency_assign.dispatch_service_to(key, budget)
