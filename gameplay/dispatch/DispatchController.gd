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

func _physics_process(delta: float) -> void:
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

## One approaching crew per rendered frame, shared across all dispatch units.
## The builder advances by whole mesh parts; measure the actual span rather
## than treating its requested budget as a hard deadline. Deployment retains
## the existing immediate fallback if the preparation has not finished.
func _warm_approaching_doors() -> void:
	var frame := Engine.get_process_frames()
	if _door_warm_frame == frame: return
	_door_warm_frame = frame
	if units.is_empty(): return
	for attempt in units.size():
		var unit: RefCounted = units[_door_warm_cursor % units.size()]
		_door_warm_cursor += 1
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
	# Admit the floor before the existing suspension contract checks resumption.
	if unit.suspended and distance_to_player(unit.vehicle.global_position) > RULES.RESUME_DISTANCE: return
	var production: Variant = world.get("production")
	if production == null: return
	var residents_value: Variant = production.get("regions")
	if not residents_value is Dictionary: return
	var residents: Dictionary = residents_value
	var car: CharacterBody3D = unit.vehicle
	var ahead := car.global_position-car.global_basis.z*12.0
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

## Claim before startup restoration, even while the controller is disabled.
## These gates affect dispatch only; wanted decay and incident cleanup continue.
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

## Transfer ownership without replenishing the crew. The interior controller
## adds this same physical agent to Gameplay.police after a collision-safe entry.
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

func _space_clear(size: Vector3, point: Vector3, yaw: float, exclude: Array[RID]) -> bool:
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var orientation := Basis(Vector3.UP, yaw)
	var query := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = size
	query.shape = box
	query.transform = Transform3D(orientation, point + orientation * Vector3(0.0, size.y * 0.5 + 0.1, 0.0))
	query.collision_mask = 7
	query.exclude = exclude
	for x in [-size.x * 0.4, size.x * 0.4]:
		for z in [-size.z * 0.4, size.z * 0.4]:
			var support: Vector3 = point + orientation * Vector3(x, 0.0, z)
			var ray := PhysicsRayQueryParameters3D.create(support + Vector3.UP * 0.6, support - Vector3.UP * 0.8, 1)
			if space.intersect_ray(ray).is_empty(): return false
	var session: Variant = world.get("session")
	if session != null and session.cold != null and not session.cold.prepare_collision_at(point): return false
	return space.intersect_shape(query,1).is_empty()

func capsule_clear(point: Vector3, exclude: Array[RID]) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.72
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * 0.9)
	query.collision_mask = 7
	query.exclude = exclude
	return world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func footprint_clear(car: CharacterBody3D, point: Vector3, yaw: float) -> bool:
	var size: Vector3 = (car.shape.shape as BoxShape3D).size
	var exclude: Array[RID] = [car.get_rid()]
	return _space_clear(size, point, yaw, exclude)

func _archetype_size(archetype: String) -> Vector3:
	var spec: Dictionary = preload("res://runtime/FleetCatalog.gd").spec(archetype)
	if spec.is_empty(): return Vector3(2.08, 1.4, 4.6)
	var bounds: Array = spec.bounds_size
	return Vector3(maxf(0.65, bounds[0]), clampf(bounds[1], 1.1, 3.6), bounds[2])

## Ponto ao lado da porta onde uma pessoa cabe: chão sólido, sem corpo dentro,
## sem parede entre o veículo e o ponto. Vazio quando não há saída segura.
## A equipe policial alterna os lados: o primeiro desce pela porta do motorista (-1), o
## segundo pela do carona (+1). Antes o lado +1 era sempre testado primeiro e, havendo
## espaço, a dupla inteira descia pelo mesmo lado, um atrás do outro.
func exit_point_at(car: CharacterBody3D, point: Vector3, yaw: float) -> Dictionary:
	var taken: Array[Vector3] = []
	return exit_point(car,taken,true,Transform3D(Basis(Vector3.UP,yaw),point))

func exit_point(car: CharacterBody3D, taken: Array[Vector3], right_only: bool, at := Transform3D.IDENTITY) -> Dictionary:
	var pose: Transform3D = car.global_transform if at==Transform3D.IDENTITY else at
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var sides: Array[float] = [1.0]
	var longitudinal: Array[float] = [0.0, 0.3, -0.3]
	if not right_only:
		sides.assign([-1.0, 1.0] if taken.size() % 2 == 0 else [1.0, -1.0])
		var door := -clampf(float(car.half_length) * .18, .30, .62)
		longitudinal.assign([door, 0.3, -1.0, 1.4])
		# Camburão: porta lateral, meio e as duas portas de trás; com os pontos já usados de fora,
		# os seis agentes saem espalhados.
		if car.archetype == "police_transport": longitudinal.assign([-1.1, 0.2, 1.5, 2.3, -0.4])
	var reach: float = car.half_width + (0.9 if right_only else 0.75)
	var excluded: Array[RID] = [car.get_rid()]
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.72
	for side in sides:
		for shift in longitudinal:
			var point: Vector3 = pose * Vector3(side * reach, 0.0, shift)
			var ground := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.8, point - Vector3.UP * 0.8, 1)
			var ground_hit := space.intersect_ray(ground)
			if ground_hit.is_empty(): continue
			point.y = ground_hit.position.y + 0.04
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = capsule
			query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * 0.9)
			query.collision_mask = 7
			query.exclude = excluded
			# Meio-fio e parede do túnel do canal ficam a menos de 1 m da porta: sem
			# esta exceção a equipe nunca descia lá dentro ("no_exit" e a viatura ia embora).
			var blocked := false
			for hit in space.intersect_shape(query, 4):
				if is_instance_valid(hit.collider) and hit.collider.has_meta("vehicle_ramp_structure"): continue
				blocked = true
				break
			if blocked: continue
			var sight := PhysicsRayQueryParameters3D.create(pose.origin + Vector3.UP * 0.9, point + Vector3.UP * 0.9, 1, excluded)
			if not space.intersect_ray(sight).is_empty(): continue
			var crowded := false
			for other in taken:
				if point.distance_to(other) < 0.9: crowded = true
			if crowded: continue
			return {"point": point, "side": side}
	return {}

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

func _dispatch_police(delta: float) -> void:
	var stars: int = gameplay.stars
	if stars <= 0:
		deployed_this_pursuit = 0
		_last_stars = 0
		_investigation_clock = maxf(0.0, _investigation_clock - delta)
		var investigating: bool = gameplay.has_method("police_investigation_active") and gameplay.police_investigation_active()
		# A viatura de averiguação não pode aparecer no instante do tiro/explosão.
		if investigating and not _investigation_seen: _investigation_clock = RULES.INVESTIGATION_DELAY
		_investigation_seen = investigating
		if investigating and _investigation_clock <= 0.0:
			_investigation_clock = 20.0
			if (investigation_unit == null or investigation_unit.finished) and _active_police().is_empty():
				var responder := dispatch_police_to(gameplay.police_investigation_point(), true)
				if responder != null:
					investigation_unit = responder
					responder._set_siren(false)
					responder._set_state("investigating")
		return
	investigation_unit = null
	if gameplay.has_method("police_surrendering") and gameplay.police_surrendering(): return
	if _last_stars == 0: _police_clock = RULES.INITIAL_DELAY[stars]
	elif stars > _last_stars: _police_clock = maxf(_police_clock, RULES.INITIAL_DELAY[stars])
	_last_stars = stars
	_police_clock -= delta
	if _police_clock > 0.0: return
	# Como em WantedManager._process: o intervalo reinicia mesmo sem despachar.
	_police_clock = RULES.INTERVAL[stars]
	# High-alert reinforcements continue while the pursuit is active. Live-unit
	# and foot-agent caps still apply; clearing the first wave must not empty 6 stars.
	if (stars < 5 and deployed_this_pursuit >= RULES.DEPLOYMENT[stars]) or not gameplay.last_known_valid: return
	if _active_police().size() >= RULES.MAX_ACTIVE[stars] or units.size() >= RULES.MAX_UNITS: return
	var anchor: Vector3 = gameplay.last_known
	if player_position_override != Vector3.INF:
		anchor = player_position_override
	else:
		var target: Variant = gameplay.pursuit_target()
		if is_instance_valid(target) and gameplay.contact_age <= 1.0: anchor = target.global_position
	dispatch_police_to(anchor)

## Despacha uma viatura que nasce em faixa, fora da vista, a 32,5–112,5 m de `anchor`.
func dispatch_police_to(anchor: Vector3, investigation: bool = false) -> RefCounted:
	var level: int = 1 if investigation else gameplay.stars
	if level <= 0 or units.size() >= RULES.MAX_UNITS or _active_police().size() >= RULES.MAX_ACTIVE[clampi(level,0,6)]: return null
	var dispatch_began := TRACE.begin()
	var variant := "patrol" if investigation else RULES.response_variant(level, units.filter(func(u): return u.is_police() and not u.finished))
	var archetype := RULES.response_archetype(level,variant)
	var size := _archetype_size(archetype)
	var checked := 0
	var planned := 0
	var occupied := 0
	var step := TRACE.begin()
	var candidates := _depot_candidates("police", anchor)
	var ahead := _spawn_ahead_direction(investigation)
	if ahead.is_empty():
		candidates.append_array(router.spawn_candidates(anchor, RULES.SPAWN_MIN, RULES.SPAWN_MAX))
	else:
		# Alvo fugindo de carro: o reforço nasce à frente, onde ele estará em ~2,5 s, de preferência
		# virado para ele. Do mais próximo ao mais distante, quase sempre nascia atrás e nunca alcançava.
		var speed: float = ahead.speed
		var reach := clampf(RULES.SPAWN_MAX + speed, RULES.SPAWN_MAX, PURSUIT.SPAWN_AHEAD_MAX)
		var found: Array[Dictionary] = router.spawn_candidates(anchor, RULES.SPAWN_MIN, reach)
		var direction: Vector3 = ahead.direction
		for candidate in found: candidate["score"] = PURSUIT.spawn_score(candidate.point, candidate.yaw, anchor, direction, speed)
		found.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.score < y.score)
		candidates.append_array(found)
	TRACE.end("police.candidates", step, {"count": candidates.size(), "ahead": not ahead.is_empty()})
	for candidate in candidates:
		if checked >= POLICE_CLEARANCE_CANDIDATES or planned >= SPAWN_CANDIDATES_CHECKED: break
		var point: Vector3 = candidate.point
		if is_visible_to_player(point): continue
		checked += 1
		step = TRACE.begin()
		var clear := _space_clear(size, point, candidate.yaw, no_exclusions)
		TRACE.end("police.clearance", step)
		if not clear:
			occupied += 1
			continue
		var heading := Vector3(-sin(candidate.yaw), 0.0, -cos(candidate.yaw))
		planned += 1
		step = TRACE.begin()
		var plan: Dictionary = router.plan(point, anchor, heading)
		TRACE.end("police.plan", step)
		if not plan.ok: continue
		_serial += 1
		deployed_this_pursuit += 1
		var car := _create_vehicle("police", point, candidate.yaw, archetype)
		var unit := _make_unit("police", car, RULES.speed_cap(variant), RULES.STUCK_POLICE)
		unit.crew_capacity = RULES.crew_size(archetype)
		unit.crew_remaining = unit.crew_capacity
		unit.serial = _serial
		unit.level = level
		unit.variant = variant
		unit.role = RULES.pursuit_role(_serial)
		if PURSUIT.enabled and not investigation:
			# Papéis por prioridade: a primeira viatura ativa persegue (PIT), depois flanco, bloqueio...
			var roles: Array = []
			for other in _active_police():
				if other != unit: roles.append(other.role)
			unit.role = PURSUIT.next_role(roles)
		unit.driver.set_route(plan.curve)
		unit.set_route_goal(anchor)
		unit.set_siren_on()
		if not ahead.is_empty(): count_pursuit("spawn_ahead")
		emit_dispatch_event("dispatched", {"unit": unit, "distance": candidate.distance, "variant": variant})
		TRACE.end("police.dispatch_to", dispatch_began, {"outcome": "dispatched", "archetype": archetype})
		return unit
	emit_dispatch_event("spawn_failed", {"service": "police", "checked": checked, "occupied": occupied, "planned": planned, "archetype": archetype})
	TRACE.end("police.dispatch_to", dispatch_began, {"outcome": "spawn_failed", "archetype": archetype})
	return null

## Direção e velocidade do alvo para o nascimento à frente, ou vazio (alvo a pé, parado, sem
## contato, averiguação ou perseguição GTA desligada).
func _spawn_ahead_direction(investigation: bool) -> Dictionary:
	if not PURSUIT.enabled or investigation or player_position_override != Vector3.INF or gameplay.contact_age > 1.0: return {}
	var target: Variant = gameplay.pursuit_target()
	if not is_instance_valid(target) or not "horizontal_velocity" in target: return {}
	var velocity: Vector3 = target.horizontal_velocity
	velocity.y = 0.0
	if velocity.length() < PURSUIT.SPAWN_MOVING_SPEED: return {}
	return {"direction": velocity.normalized(), "speed": velocity.length()}

## Fala atual do rádio da central para o HUD ("" sem fala recente).
func radio_line() -> String:
	return radio.current(_clock) if PURSUIT.enabled else ""

func count_pursuit(key: String) -> void:
	pursuit_stats[key] = int(pursuit_stats.get(key, 0)) + 1

## Viatura deixada para trás numa perseguição (DispatchUnit._outrun): some fora da vista, devolve a
## vaga e o orçamento de despacho (ela não falhou, só ficou para trás) e adianta o próximo reforço,
## que nasce à frente.
func recycle_outrun(unit: RefCounted) -> void:
	count_pursuit("outrun")
	deployed_this_pursuit = maxi(0, deployed_this_pursuit - 1)
	_police_clock = minf(_police_clock, 1.0)
	emit_dispatch_event("outrun", {"unit": unit})
	unit.finish("outrun")

## Ponto de rua para a viatura vasculhar na busca em leque: dentro do raio de busca em volta da
## última posição conhecida, longe da própria viatura e dos pontos das outras. INF sem candidatos.
func search_point_for(unit: RefCounted) -> Vector3:
	var center: Vector3 = gameplay.last_known
	var stars: int = gameplay.stars
	if _search_center == Vector3.INF or _search_center.distance_to(center) > 10.0 or _search_stars != stars:
		var traced := TRACE.begin()
		var spanned := STALL_WORK.begin()
		_search_center = center
		_search_stars = stars
		_search_points.clear()
		var radius := PURSUIT.search_radius(stars)
		for candidate in router.spawn_candidates(center, 0.0, radius, PURSUIT.SEARCH_POINT_SPACING):
			_search_points.append(candidate.point)
		_search_rng.seed = hash(Vector3i(roundi(center.x), roundi(center.z), stars))
		STALL_WORK.finish_slow("dispatch.search_points", spanned, 3000, self)
		TRACE.end("pursuit.search_points", traced, {"count": _search_points.size()})
	if _search_points.is_empty(): return Vector3.INF
	var taken: Array[Vector3] = []
	for other in units:
		if other != unit and other.is_police() and other.search_point != Vector3.INF: taken.append(other.search_point)
	var fallback: Vector3 = _search_points[_search_rng.randi_range(0, _search_points.size() - 1)]
	for attempt in 8:
		var candidate: Vector3 = _search_points[_search_rng.randi_range(0, _search_points.size() - 1)]
		if candidate.distance_to(unit.vehicle.global_position) < 25.0: continue
		var crowded := false
		for point in taken:
			if point.distance_to(candidate) < 20.0: crowded = true
		if not crowded: return candidate
	return fallback

## Fala do rádio: linha no HUD e a mesma fala em voz (pedaços gravados, PursuitRadioAudio).
func announce(event: String, street := "", heading := "", urgent := false) -> bool:
	var settings := get_node_or_null("/root/V2Settings")
	radio.english = settings != null and str(settings.get("text_language")).begins_with("en")
	if not radio.announce(event, _clock, street, heading, urgent): return false
	_speak(urgent)
	return true

func _speak(urgent: bool) -> void:
	if radio.clips.is_empty(): return
	if radio_voice == null:
		radio_voice = RADIO_AUDIO.new()
		add_child(radio_voice)
	radio_voice.say(radio.clips, urgent)

## Rádio da central e o lado (carro/a pé) do último contato. Só lê o estado; não despacha nada.
func _tick_pursuit_awareness() -> void:
	var stars: int = gameplay.stars
	if stars <= 0:
		if _radio_stars > 0: announce("evaded", "", "", true)
		_radio_stars = 0
		_had_contact = false
		return
	var target: Variant = gameplay.pursuit_target()
	var contact: bool = gameplay.contact_age <= 1.0 and is_instance_valid(target)
	if contact:
		pursuit_in_car = "horizontal_velocity" in target
		pursuit_velocity = target.horizontal_velocity if pursuit_in_car else Vector3.ZERO
	if stars > _radio_stars:
		announce("wanted" if _radio_stars == 0 else "escalated", "", "", true)
	_radio_stars = stars
	if contact and not _had_contact:
		var street := RADIO.place(router, target.global_position)
		if not street.is_empty(): announce("spotted", street)
	elif not contact and _had_contact:
		announce("lost", RADIO.place(router, gameplay.last_known))
	elif contact and pursuit_in_car:
		if radio.fleeing(router, target.global_position, target.horizontal_velocity, _clock): _speak(false)
	_had_contact = contact

func retain_investigator(unit: RefCounted) -> bool:
	if not gameplay.has_method("police_investigation_active") or not gameplay.police_investigation_active(): return false
	if unit.variant in ["tank","motorcycle"] or unit.wrecked or unit.finished: return false
	if unit.crew_remaining <= 0 and unit.officers.all(func(o): return not is_instance_valid(o) or o.dead): return false
	if investigation_unit == null or investigation_unit.finished: investigation_unit = unit
	return investigation_unit == unit

func _has_active_tactical() -> bool:
	for unit in _active_police():
		if unit.variant == "tactical": return true
	return false

# --- Emergência ----------------------------------------------------------------

func _dispatch_emergency(delta: float) -> void:
	_service_clock = maxf(0.0, _service_clock - delta)
	_scan_clock -= delta
	if _scan_clock > 0.0: return
	_scan_clock = 0.5
	var legacy_crews: int = gameplay.emergency.crews.filter(func(crew): return is_instance_valid(crew) and not crew.dead).size()
	if _service_clock > 0.0 or _active_services().size()+legacy_crews >= RULES.MAX_CREWS or units.size() >= RULES.MAX_UNITS: return
	var emergency: Node3D = gameplay.emergency
	var best_key := -1
	var best_age := -1.0
	var fire_trucks: int = units.filter(func(u): return u.service == "fire" and not u.finished).size()
	for key in emergency.incidents.keys():
		var record: Dictionary = emergency.incidents[key]
		var actor: Variant = record.get("actor")
		if not is_instance_valid(actor) or actor.is_queued_for_deletion():
			emergency.incidents.erase(key)
			if is_instance_valid(bridge): bridge.roles.erase(key)
			emit_dispatch_event("incident_invalid", {"incident": key, "reason": "actor_removed"})
			continue
		if record.assigned or record.role not in ["medic", "mortician", "fire"]: continue
		if record.role == "mortician" and not emergency.mortician_dispatch_allowed(key):
			# Se as estrelas subirem durante a busca, abandonamos os candidatos.
			# A ocorrência permanece disponível para quando a situação acalmar.
			record.erase("search")
			continue
		if record.role == "medic" and float(record.age) < RULES.medic_response_delay(int(key)): continue
		# Um caminhão de bombeiros por vez, só depois de 10-15 s de fogo, e 30-45 s de pausa se o anterior foi destruído.
		if record.role == "fire":
			if fire_trucks >= RULES.MAX_FIRE_TRUCKS or _clock < _fire_lockout_until: continue
			if float(record.age) < RULES.fire_response_delay(int(key)): continue
		if distance_to_player(actor.global_position) > RULES.RESPONSE_RADIUS: continue
		# Uma busca já em andamento tem prioridade, para não trocar de ocorrência no meio.
		var priority: float = record.age + (100000.0 if record.has("search") else 0.0)
		if priority > best_age:
			best_age = priority
			best_key = key
	if best_key < 0: return
	if dispatch_service_to(best_key, SERVICE_SEARCH_BUDGET) != null: _service_clock = RULES.DISPATCH_COOLDOWN
	elif _search_pending: _scan_clock = 0.0
	else: _service_clock = 3.0

## Garagens registradas com set_depots, projetadas na faixa mais próxima.
func _depot_candidates(service: String, target: Vector3) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for depot in depots.get(service, []):
		var edge: Dictionary = router.nearest_edge(depot)
		if edge.is_empty(): continue
		var direction: Vector3 = (routes.vertices[edge.edge.to] - routes.vertices[edge.edge.from]).normalized()
		result.append({"point": edge.closest, "yaw": atan2(-direction.x, -direction.z), "distance": depot.distance_to(target), "depot": true})
	return result

## Despacha a viatura da ocorrência `key` do EmergencyManager, sem teleporte:
## nasce em garagem (`depots`) ou faixa fora da vista e chega dirigindo.
func dispatch_service_to(key: int, budget: int = -1) -> RefCounted:
	# `budget` >= 0 reparte a busca de ponto de partida em vários quadros: no máx. `budget`
	# candidatos planejados por chamada, com o estado guardado em `record.search`.
	# Tudo num quadro só custava 40-80 ms na 1ª ocorrência (varredura do grafo de ruas +
	# até 8 planos de rota; tests/measure/probe_first_emergency.gd). Sem orçamento (-1)
	# roda até o fim na hora, como antes.
	_search_pending = false
	var emergency: Node3D = gameplay.emergency
	if not emergency.incidents.has(key): return null
	var record: Dictionary = emergency.incidents[key]
	var actor: Variant = record.get("actor")
	if record.assigned or not is_instance_valid(actor) or actor.is_queued_for_deletion():
		record.erase("search")
		if not is_instance_valid(actor) or actor.is_queued_for_deletion():
			emergency.incidents.erase(key)
			if is_instance_valid(bridge): bridge.roles.erase(key)
			emit_dispatch_event("incident_invalid", {"incident": key, "reason": "actor_removed"})
		return null
	var service: String = record.role
	var point: Vector3 = actor.global_position
	var size := _archetype_size(RULES.archetype_for(service))
	var state: Dictionary = record.get("search", {})
	if state.is_empty():
		var sweep := TRACE.begin()
		var found := _depot_candidates(service, point)
		found.append_array(router.spawn_candidates(point, RULES.SERVICE_SPAWN_MIN, RULES.SERVICE_SPAWN_MAX))
		TRACE.end("service.candidates", sweep, {"count": found.size()})
		state = {"candidates": found, "index": 0, "checked": 0, "best": {}, "best_length": INF}
		if budget >= 0:
			# A coleta de candidatos já é o trabalho deste quadro.
			record.search = state
			_search_pending = true
			return null
	var candidates: Array = state.candidates
	var work := 0
	# Escolhe a rota mais curta entre os candidatos checados. O primeiro válido às
	# vezes nascia numa faixa apontada para longe e o caminhão dava a volta no
	# quarteirão: 50 a 140 s para um incêndio a 33 m (sonda de 2026-09-24).
	while state.index < candidates.size() and state.checked < SPAWN_CANDIDATES_CHECKED_SERVICE:
		if budget >= 0 and work >= budget:
			record.search = state
			_search_pending = true
			return null
		var candidate: Dictionary = candidates[state.index]
		state.index += 1
		var start: Vector3 = candidate.point
		# Sair da garagem é crível mesmo perto; surgir no meio da rua, não.
		if is_visible_to_player(start) or (not candidate.get("depot", false) and distance_to_player(start) < RULES.SERVICE_SPAWN_PLAYER_CLEARANCE): continue
		state.checked += 1
		work += 1
		var probe := TRACE.begin()
		var start_clear := _space_clear(size, start, candidate.yaw, no_exclusions)
		TRACE.end("service.clearance", probe)
		if not start_clear: continue
		var heading := Vector3(-sin(candidate.yaw), 0.0, -cos(candidate.yaw))
		probe = TRACE.begin()
		var candidate_plan: Dictionary = router.plan(start, point, heading)
		TRACE.end("service.plan", probe)
		if not candidate_plan.ok or candidate_plan.end_gap > RULES.FOOT_RANGE: continue
		var length: float = candidate_plan.curve.get_baked_length()
		if length < state.best_length:
			state.best_length = length
			state.best = {"candidate": candidate, "plan": candidate_plan}
	record.erase("search")
	var best: Dictionary = state.best
	if not best.is_empty() and budget >= 0:
		# O ponto foi escolhido quadros atrás: confirma que ainda está livre e fora da vista.
		var chosen: Dictionary = best.candidate
		if is_visible_to_player(chosen.point) or (not chosen.get("depot", false) and distance_to_player(chosen.point) < RULES.SERVICE_SPAWN_PLAYER_CLEARANCE) or not _space_clear(size, chosen.point, chosen.yaw, no_exclusions): best = {}
	if not best.is_empty():
		var candidate: Dictionary = best.candidate
		var plan: Dictionary = best.plan
		var start: Vector3 = candidate.point
		_serial += 1
		var car := _create_vehicle(service, start, candidate.yaw)
		var unit := _make_unit(service, car, RULES.SPEED_PATROL, RULES.STUCK_SERVICE)
		unit.serial = _serial
		unit.incident_id = key
		unit.actor = actor
		unit.driver.set_route(plan.curve)
		unit.set_route_goal(point)
		unit.set_siren_on()
		record.assigned = true
		record.crew = car
		if service == "mortician": emergency.mortician_clock = RULES.MORTICIAN_COOLDOWN
		emit_dispatch_event("dispatched", {"unit": unit, "distance": candidate.distance, "end_gap": plan.end_gap})
		return unit
	emit_dispatch_event("spawn_failed", {"service": service, "checked": state.checked, "incident": key})
	return null
