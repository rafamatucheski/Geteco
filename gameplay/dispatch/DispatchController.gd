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
var _prepared_ground_cells: Dictionary = {}
var roadblocks: RefCounted
var investigation_unit: RefCounted
var _investigation_clock := 0.0

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
	_clock += delta
	router.advance(delta)
	for unit in units.duplicate():
		_prepare_unit_ground(unit)
		unit.tick(delta)
		if unit.finished:
			_prepared_ground_cells.erase(unit.get_instance_id())
			units.erase(unit)
	_dispatch_police(delta)
	if roadblocks != null: roadblocks.tick(delta)
	_dispatch_emergency(delta)
	_wreck_clock -= delta
	if _wreck_clock <= 0.0:
		_wreck_clock = 2.0
		_tidy_wrecks()

func _prepare_unit_ground(unit: RefCounted) -> void:
	if unit == null or not is_instance_valid(unit.vehicle): return
	var production: Variant = world.get("production")
	if production == null: return
	var region: Variant = production.get("region")
	if region == null or not region.has_method("prepare_collision_at"): return
	var car: CharacterBody3D = unit.vehicle
	var ahead := car.global_position-car.global_basis.z*12.0
	var cells := Vector4(floorf(car.global_position.x/64.0),floorf(car.global_position.z/64.0),floorf(ahead.x/64.0),floorf(ahead.z/64.0))
	var unit_id := unit.get_instance_id()
	if _prepared_ground_cells.get(unit_id,Vector4(INF,INF,INF,INF)) == cells: return
	_prepared_ground_cells[unit_id] = cells
	region.prepare_collision_at(car.global_position)
	region.prepare_collision_at(ahead)

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
	return units.filter(func(u): return u.is_police() and not u.finished and (u.state != "departing" or (u.stranded and not released.has(u))))

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
func exit_point(car: CharacterBody3D, taken: Array[Vector3], right_only: bool) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var sides: Array[float] = [1.0]
	var longitudinal: Array[float] = [0.0, 0.3, -0.3]
	if not right_only:
		sides.assign([-1.0, 1.0] if taken.size() % 2 == 0 else [1.0, -1.0])
		var door := -clampf(float(car.half_length) * .18, .30, .62)
		longitudinal.assign([door, 0.3, -1.0, 1.4])
		if car.archetype == "police_transport": longitudinal.assign([-1.1, 0.2, 1.5])
	var reach: float = car.half_width + (0.9 if right_only else 0.75)
	var excluded: Array[RID] = [car.get_rid()]
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.72
	for side in sides:
		for shift in longitudinal:
			var point: Vector3 = car.to_global(Vector3(side * reach, 0.0, shift))
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
			var sight := PhysicsRayQueryParameters3D.create(car.global_position + Vector3.UP * 0.9, point + Vector3.UP * 0.9, 1)
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
	world.add_child(car)
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
	var officer := OFFICER.new()
	officer.controller = gameplay
	officer.dispatch_controller = self
	officer.tier = RULES.officer_tier_for(unit.level, unit.variant)
	officer.last_known = gameplay.last_known
	officer.vehicle = unit.vehicle
	officer.door_side = side
	officer.boarded.connect(unit.on_officer_boarded)
	add_child(officer)
	officer.add_collision_exception_with(unit.vehicle)
	officer.global_position = OFFICER.inside_point(unit.vehicle, point, side)
	officer.begin_disembark(unit.vehicle, point, side)
	unit.driver.ignore.append(officer.get_rid())
	return officer

func spawn_responder(unit: RefCounted, point: Vector3) -> CharacterBody3D:
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
		if gameplay.has_method("police_investigation_active") and gameplay.police_investigation_active() and _investigation_clock <= 0.0:
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
	elif stars > _last_stars: _police_clock = minf(_police_clock, RULES.INITIAL_DELAY[stars])
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
	var variant := "patrol" if investigation else RULES.response_variant(level, units.filter(func(u): return u.is_police() and not u.finished))
	var archetype := RULES.response_archetype(level,variant)
	var size := _archetype_size(archetype)
	var checked := 0
	var planned := 0
	var occupied := 0
	var candidates := _depot_candidates("police", anchor)
	candidates.append_array(router.spawn_candidates(anchor, RULES.SPAWN_MIN, RULES.SPAWN_MAX))
	for candidate in candidates:
		if checked >= POLICE_CLEARANCE_CANDIDATES or planned >= SPAWN_CANDIDATES_CHECKED: break
		var point: Vector3 = candidate.point
		if is_visible_to_player(point): continue
		checked += 1
		if not _space_clear(size, point, candidate.yaw, no_exclusions):
			occupied += 1
			continue
		var heading := Vector3(-sin(candidate.yaw), 0.0, -cos(candidate.yaw))
		planned += 1
		var plan: Dictionary = router.plan(point, anchor, heading)
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
		unit.driver.set_route(plan.curve)
		unit.set_route_goal(anchor)
		unit.set_siren_on()
		emit_dispatch_event("dispatched", {"unit": unit, "distance": candidate.distance, "variant": variant})
		return unit
	emit_dispatch_event("spawn_failed", {"service": "police", "checked": checked, "occupied": occupied, "planned": planned, "archetype": archetype})
	return null

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
	for key in emergency.incidents.keys():
		var record: Dictionary = emergency.incidents[key]
		var actor: Variant = record.get("actor")
		if not is_instance_valid(actor) or actor.is_queued_for_deletion():
			emergency.incidents.erase(key)
			if is_instance_valid(bridge): bridge.roles.erase(key)
			emit_dispatch_event("incident_invalid", {"incident": key, "reason": "actor_removed"})
			continue
		if record.assigned or record.role not in ["medic", "mortician", "fire"]: continue
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
		result.append({"point": edge.closest, "yaw": atan2(-direction.x, -direction.z), "distance": depot.distance_to(target)})
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
		var found := _depot_candidates(service, point)
		found.append_array(router.spawn_candidates(point, RULES.SPAWN_MIN, RULES.SPAWN_MAX))
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
		if is_visible_to_player(start): continue
		state.checked += 1
		work += 1
		if not _space_clear(size, start, candidate.yaw, no_exclusions): continue
		var heading := Vector3(-sin(candidate.yaw), 0.0, -cos(candidate.yaw))
		var candidate_plan: Dictionary = router.plan(start, point, heading)
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
		if is_visible_to_player(chosen.point) or not _space_clear(size, chosen.point, chosen.yaw, no_exclusions): best = {}
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
		emit_dispatch_event("dispatched", {"unit": unit, "distance": candidate.distance, "end_gap": plan.end_gap})
		return unit
	emit_dispatch_event("spawn_failed", {"service": service, "checked": state.checked, "incident": key})
	return null
