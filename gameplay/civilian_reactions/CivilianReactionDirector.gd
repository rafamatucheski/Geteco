extends Node
## Reação dos civis genéricos (`world.people`) a tiro, explosão, agressão e buzina — porte do V1 (`PedestrianDanger`,
## `AnimatedPedestrian3D.hear_gunfire/panic/hear_traffic_horn`). Separação de responsabilidades:
##   perceber  -> report_gunfire / report_explosion / report_assault / report_horn
##   decidir   -> CivilianDanger (memória de ameaças + escolha de fuga)
##   mover     -> _steer (usa só os ganchos públicos de `Actor`: controlled_automatically/automatic_direction/speed)
##   apresentar-> CivilianReactionPresenter (grito e balão)
##   retomar   -> _release (devolve o controle e reengata a rota no waypoint mais próximo)
## Só reage quem NÃO é controlado por outro sistema no instante do alerta.
## Ligação: `configure(world, gameplay)` conecta os eventos reais de tiro e explosão. Contrato para os donos em
## docs/civilian-reactions-v1.md.
const DANGER := preload("res://gameplay/civilian_reactions/CivilianDanger.gd")
const PRESENTER := preload("res://gameplay/civilian_reactions/CivilianReactionPresenter.gd")
const RESPONSE_LIMIT := 22.0
const MELEE_REACH := 1.7

const HEARING_RADIUS := 40.0        ## m; V1 240 px (WeaponCustomization.gd:55)
const HEARING_RADIUS_SUPPRESSED := 13.0 ## V1 80 px
const SHOT_LENGTH := 30.0
const EXPLOSION_RADIUS := 55.0
const PANIC_TIME := Vector2(9.0, 12.0)   ## V1
const RECOVER_TIME := Vector2(2.0, 4.0)  ## V1
const PANIC_SPEED := 5.0
const RECOVER_SPEED := 3.5               ## V1: 0,75 do pânico
const HORN_STEP_TIME := 4.5              ## V1
const HORN_SPEED := 2.6
const HORN_AHEAD := 9.0
const HORN_HALF_WIDTH := 2.4
## V1 replanejava a 2 Hz sempre. Aqui só replaneja ao chegar, ao travar ou nesta cadência de segurança: cada
## replano custa até 30 raycasts e, com 24 civis em fuga, 2 Hz dava ~1400 raios/s por nada.
const REPLAN_INTERVAL := 1.5
## Rajada de NPC (SMG da polícia) dispara várias vezes por segundo; uma varredura da população por atirador
## neste intervalo basta, porque CivilianDanger já renova a mesma ameaça.
const NPC_SHOT_INTERVAL := 0.4
const STUCK_CHECK := 1.0
const STUCK_DISTANCE := 0.5
const MAX_REACTORS := 24
## Limites provisórios do trabalho de busca, compartilhados por frame desenhado
## (passos físicos de catch-up não ganham outro orçamento). Cada passo é um raio.
const ESCAPE_RAYS_PER_FRAME := 24
const ESCAPE_BUDGET_USEC := 750
const REACTION_LOD_META := &"civilian_reaction_lod"
const SUSPEND_DISTANCE := 110.0          ## além disso o civil é solto (a rotina/streaming cuida dele)
const DAMAGE_POLL := 0.25

var world: Node3D
var gameplay: Node
var presenter: Node
var reactors := {}        ## instance_id -> estado (mantém WeakRef, nunca o objeto)
var seen_health := {}     ## instance_id -> vida vista na última varredura
var horn_playing := {}    ## instance_id do veículo -> buzina tocando na varredura anterior
var poll_clock := 0.0
var clock := 0.0
var npc_heard := {}   ## instance_id do atirador -> clock da última varredura
var escape_queue: Array[int] = []
var escape_budget_frame := -1
var escape_rays_used := 0
var escape_usec_used := 0
var stats := {"alerts": 0, "released": 0, "stuck_replans": 0, "dropped": 0, "escape_rays": 0, "escape_searches": 0}

func configure(p_world: Node3D, p_gameplay: Node) -> void:
	world = p_world
	gameplay = p_gameplay
	if presenter == null:
		presenter = PRESENTER.new()
		add_child(presenter)
	if gameplay != null and gameplay.has_signal("weapon_fired") and not gameplay.weapon_fired.is_connected(_on_weapon_fired):
		gameplay.weapon_fired.connect(_on_weapon_fired)
	if gameplay != null and gameplay.has_signal("explosion_occurred") and not gameplay.explosion_occurred.is_connected(_on_explosion):
		gameplay.explosion_occurred.connect(_on_explosion)
	if gameplay != null and gameplay.has_signal("npc_gunfire") and not gameplay.npc_gunfire.is_connected(_on_npc_gunfire):
		gameplay.npc_gunfire.connect(_on_npc_gunfire)

## Descarregamento real da população: devolve o controle e zera memórias. Uma
## simples troca de region_id na continuidade cidade-serra não deve chamar isto.
func reset_population() -> void:
	for id in reactors.keys(): _release(id, false)
	reactors.clear()
	escape_queue.clear()
	seen_health.clear()
	horn_playing.clear()
	if presenter: presenter.clear_all()

## Compatibilidade para validadores e integrações anteriores. O nome antigo não
## autoriza usar este método em toda mudança lógica de região.
func reset_region() -> void: reset_population()

func _exit_tree() -> void:
	for id in reactors.keys(): _release(id, false)
	reactors.clear()
	escape_queue.clear()

# ── Percepção ────────────────────────────────────────────────────────────────

func _on_weapon_fired(weapon_id: String, origin: Vector3) -> void:
	var data: Dictionary = gameplay.weapon_data(weapon_id) if gameplay != null and gameplay.has_method("weapon_data") else {}
	# weapon_fired também acompanha arremessos/chamas no Gameplay atual. Apenas
	# armas de projétil com estampido entram no contrato de tiro ouvido.
	if data.is_empty() or data.get("is_grenade", false) or data.get("is_flame", false): return
	var aim: Vector3 = gameplay._aim_direction() if gameplay.has_method("_aim_direction") else Vector3.ZERO
	aim.y = 0.0
	if aim.length_squared() < 0.01: aim = Vector3.FORWARD
	var suppressed: bool = data.get("suppressed", false) == true
	report_gunfire(origin, origin + aim.normalized() * SHOT_LENGTH, gameplay.get("player"),
		HEARING_RADIUS_SUPPRESSED if suppressed else HEARING_RADIUS)

func _on_npc_gunfire(origin: Vector3, direction: Vector3, shooter: Node3D) -> void:
	var key: int = shooter.get_instance_id() if is_instance_valid(shooter) else 0
	if clock - float(npc_heard.get(key, -99.0)) < NPC_SHOT_INTERVAL: return
	npc_heard[key] = clock
	var aim := direction
	aim.y = 0.0
	if aim.length_squared() < 0.01: aim = Vector3.FORWARD
	report_gunfire(origin, origin + aim.normalized() * SHOT_LENGTH, shooter)

func _on_explosion(origin: Vector3, radius: float, source: Variant) -> void:
	report_explosion(origin, radius, source)

## Tiro ouvido por quem está no raio, com ou sem linha de visão (V1: só o raio; a cobertura entra na fuga).
func report_gunfire(origin: Vector3, end: Vector3, shooter: Variant = null, radius: float = HEARING_RADIUS) -> void:
	var live_shooter: Variant = shooter if is_instance_valid(shooter) else null
	for person in _people():
		if not is_instance_valid(person) or person == live_shooter or not _reactive(person, true): continue
		var flat: Vector3 = person.global_position - origin
		flat.y = 0.0
		if flat.length() > radius: continue
		_alert(person, origin, end, live_shooter)

func report_explosion(origin: Vector3, radius: float = EXPLOSION_RADIUS, source: Variant = null) -> void:
	var live_source: Variant = source if is_instance_valid(source) else null
	for person in _people():
		if not is_instance_valid(person) or person == live_source or not _reactive(person, true): continue
		var flat: Vector3 = person.global_position - origin
		flat.y = 0.0
		if flat.length() > radius: continue
		_alert(person, origin, origin, live_source)

## Agressão só é aceita quando o chamador possui a origem real. O diretor nunca
## transforma uma queda de vida sem metadado em agressão do jogador.
func report_assault(person: Variant, source: Variant) -> bool:
	if not is_instance_valid(person) or not person is Node3D or not is_instance_valid(source) or not source is Node3D or not _reactive(person, true): return false
	var origin: Vector3 = source.global_position
	_alert(person, origin, origin, source)
	return true

## V1: buzina NÃO gera pânico — só quem está na frente do veículo e à frente da grade dá um passo para o ombro livre.
func report_horn(vehicle: Node3D) -> void:
	if not is_instance_valid(vehicle): return
	var forward := -vehicle.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var side := Vector3.UP.cross(forward).normalized()
	for person in _people():
		if not is_instance_valid(person) or not _reactive(person) or reactors.has(person.get_instance_id()): continue
		var relative: Vector3 = person.global_position - vehicle.global_position
		relative.y = 0.0
		var ahead := relative.dot(forward)
		if ahead < 0.0 or ahead > HORN_AHEAD or absf(relative.dot(side)) > HORN_HALF_WIDTH: continue
		var shoulder := side if relative.dot(side) >= 0.0 else -side
		for direction in [shoulder, -shoulder]:
			var target: Vector3 = person.global_position + direction * (HORN_HALF_WIDTH + 1.0 - relative.dot(direction))
			if _path_clear(person, target):
				_begin(person, "horn").target = target
				break

## A varredura de vida existe apenas para limpar referências. Actor não publica a
## origem do dano; inferi-la pela proximidade do jogador, polícia ou tráfego
## atribuiria agressões ao autor errado. Donos do dano devem usar report_assault.
func _poll_damage() -> void:
	var live := {}
	for person in _people():
		if not is_instance_valid(person): continue
		var id: int = person.get_instance_id()
		live[id] = true
		var health: float = person.get("health")
		seen_health[id] = health
	for id in seen_health.keys():
		if not live.has(id): seen_health.erase(id)

func _poll_horns() -> void:
	var live := {}
	for vehicle in get_tree().get_nodes_in_group("drivable"):
		var equipment = vehicle.get("equipment")
		if equipment == null or not is_instance_valid(equipment.get("horn_audio")): continue
		var id: int = vehicle.get_instance_id()
		var playing: bool = equipment.horn_audio.playing
		live[id] = true
		if playing and not horn_playing.get(id, false): report_horn(vehicle)
		horn_playing[id] = playing
	for id in horn_playing.keys():
		if not live.has(id): horn_playing.erase(id)

# ── Elegibilidade ────────────────────────────────────────────────────────────

func _people() -> Array:
	return world.people if world != null and world.get("people") != null else []

## Civil genérico vivo, sem dono de movimento. Protegidos (Maciota/mecânico) e atores de rotina/polícia/Cobras não entram
## em `people` nem têm papel "civilian"; ainda assim conferimos, porque `people` é público.
func _reactive(person: Variant, allow_ours := false) -> bool:
	# `world.people` pode conter uma referência de Object já liberada entre
	# atualizações. O argumento precisa ser Variant para validar antes de o
	# runtime tentar convertê-lo para Node.
	if not is_instance_valid(person) or not person is CharacterBody3D: return false
	if person.get("dead") == true or person.get("is_player") == true: return false
	if person.get_meta("gameplay_role", "") != "civilian" or person.is_in_group("v1_routine_actor"): return false
	if person.get_meta("interior_actor", false) or person.get_meta("reaction_exempt", false): return false
	if person.get("controlled_automatically") == true and not (allow_ours and reactors.has(person.get_instance_id())): return false
	return true

# ── Decisão ──────────────────────────────────────────────────────────────────

func _response(person: CharacterBody3D, source: Variant) -> String:
	# Apenas uma agressão atribuída ao jogador permite confronto. Identidade estável
	# dá temperamentos diferentes sem sortear outra decisão a cada tiro da rajada.
	if not is_instance_valid(source) or gameplay == null or source != gameplay.get("player"):
		return "panic"
	if gameplay.get("health") <= 0 or not gameplay.attack_allowed(): return "panic"
	var distance := person.global_position.distance_to(source.global_position)
	var temperament := posmod(int(person.get("identity")), 20)
	if temperament >= 18 and distance <= RESPONSE_LIMIT and person.get("health") > 35.0: return "armed"
	if temperament >= 15 and distance <= 8.0 and person.get("health") > 45.0: return "melee"
	if temperament >= 11 and distance <= HEARING_RADIUS: return "call"
	return "panic"

func _alert(person: CharacterBody3D, origin: Vector3, end: Vector3, source: Variant) -> void:
	var id := person.get_instance_id()
	var state: Dictionary = reactors.get(id, {})
	if state.is_empty():
		var response := _response(person, source)
		state = _begin(person, response)
		if state.is_empty(): return
		match response:
			"armed":
				presenter.bubble(person, "LARGA A ARMA!")
			"melee":
				presenter.bubble(person, "PARA COM ISSO!")
			"call":
				presenter.bubble(person, "VOU LIGAR PARA A POLÍCIA!")
				presenter.show_phone(person)
			_:
				presenter.scream(person) # sem balão: o grito e a corrida já dizem o que houve
	var was_panicking: bool = state.phase == "panic"
	if state.phase == "horn": state.phase = "panic"; presenter.scream(person)
	elif state.phase == "recover": state.phase = "panic"
	if is_instance_valid(source) and source is Node3D: state.source = weakref(source)
	stats.alerts += 1
	state.danger.remember(origin, end)
	if state.phase == "panic":
		state.timer = randf_range(PANIC_TIME.x, PANIC_TIME.y)
		# Renew danger during an active panic without bypassing a failed-search retry.
		# Entering panic from another phase still reacts immediately.
		if not was_panicking:
			state.replan = 0.0
			state.target = Vector3.ZERO

func _begin(person: CharacterBody3D, phase: String) -> Dictionary:
	if reactors.size() >= MAX_REACTORS and not reactors.has(person.get_instance_id()): return {}
	var id := person.get_instance_id()
	if reactors.has(id): return reactors[id]
	var state := {"ref": weakref(person), "danger": DANGER.new(), "phase": phase, "timer": HORN_STEP_TIME if phase == "horn" else randf_range(PANIC_TIME.x, PANIC_TIME.y),
		"replan": 0.0, "target": Vector3.ZERO, "saved_speed": person.get("speed"), "last_position": person.global_position,
		"stuck_clock": 0.0, "blocked": [] as Array[Vector3], "source": null,
		"action_time": 0.0, "attack_clock": 0.0, "reported": false, "escape_search": {}}
	reactors[id] = state
	person.set("controlled_automatically", true)
	person.set_meta(REACTION_LOD_META, phase == "panic" or phase == "recover")
	person.set("automatic_direction", Vector3.ZERO)
	person.set("speed", HORN_SPEED if phase == "horn" else (PANIC_SPEED if phase == "panic" else 0.0))
	return state

# ── Movimento ────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	clock += delta
	poll_clock += delta
	if poll_clock >= DAMAGE_POLL:
		poll_clock = 0.0
		_poll_damage()
		_poll_horns()
		if npc_heard.size() > 32:
			for key in npc_heard.keys():
				if clock - float(npc_heard[key]) > NPC_SHOT_INTERVAL: npc_heard.erase(key)
	var player = gameplay.get("player") if gameplay else null
	for id in reactors.keys():
		var state: Dictionary = reactors[id]
		var person = state.ref.get_ref()
		if not is_instance_valid(person) or person.get("dead") == true or not _world_owns(person):
			_release(id, false) # alvo removido/morto: nada a restaurar, só soltar o estado
			stats.dropped += 1
			continue
		if person.get("controlled_automatically") != true:
			_release(id, false) # outro sistema assumiu ou soltou: não brigar pelo controle
			stats.dropped += 1
			continue
		if is_instance_valid(player) and player is Node3D and person.global_position.distance_to(player.global_position) > SUSPEND_DISTANCE:
			_release(id, true)
			continue
		state.timer -= delta
		state.danger.tick(delta)
		var allow_lod: bool = state.phase == "panic" or state.phase == "recover"
		if person.get_meta(REACTION_LOD_META, false) != allow_lod: person.set_meta(REACTION_LOD_META, allow_lod)
		match state.phase:
			"panic":
				if state.timer <= 0.0 or state.danger.is_empty():
					state.phase = "recover"
					state.timer = randf_range(RECOVER_TIME.x, RECOVER_TIME.y)
					state.target = Vector3.ZERO
					_cancel_escape(id, state)
				else: _steer_panic(person, state, delta)
			"recover":
				if state.timer <= 0.0: _release(id, true)
				else: _steer_recover(person, state)
			"horn":
				if state.timer <= 0.0 or person.global_position.distance_to(state.target) < 0.5: _release(id, true)
				else: _move(person, state.target, HORN_SPEED)
			"call": _update_call(person, state, delta)
			"armed", "melee": _update_resistance(person, state, delta)
	_process_escape_queue()

func _source(state: Dictionary) -> Node3D:
	var reference: Variant = state.get("source")
	var actor: Variant = reference.get_ref() if reference is WeakRef else null
	return actor as Node3D if is_instance_valid(actor) and actor is Node3D else null

func _update_call(person: CharacterBody3D, state: Dictionary, delta: float) -> void:
	person.set("automatic_direction", Vector3.ZERO)
	state.action_time += delta
	if not state.reported and state.action_time >= 2.5:
		state.reported = true
		var source := _source(state)
		if is_instance_valid(source) and gameplay != null and gameplay.has_method("report_civilian_call"):
			gameplay.report_civilian_call(person.global_position, source.global_position)
	if state.action_time >= 4.0:
		presenter.hide_prop(person)
		state.phase = "panic"
		state.timer = randf_range(PANIC_TIME.x, PANIC_TIME.y)

func _update_resistance(person: CharacterBody3D, state: Dictionary, delta: float) -> void:
	var source := _source(state)
	if not is_instance_valid(source) or gameplay == null or source != gameplay.get("player") or gameplay.get("health") <= 0 or not gameplay.attack_allowed():
		presenter.hide_prop(person)
		state.phase = "panic"
		state.timer = randf_range(PANIC_TIME.x, PANIC_TIME.y)
		return
	var direction: Vector3 = source.global_position - person.global_position
	direction.y = 0.0
	var distance := direction.length()
	if distance > RESPONSE_LIMIT * 1.5:
		_release(person.get_instance_id(), true)
		return
	state.action_time += delta
	state.attack_clock = maxf(0.0, state.attack_clock - delta)
	if state.action_time > 12.0 or person.get("health") < 25.0:
		presenter.hide_prop(person)
		state.phase = "panic"
		state.timer = randf_range(PANIC_TIME.x, PANIC_TIME.y)
		return
	person.visual.rotation.y = atan2(-direction.x, -direction.z)
	if state.phase == "armed":
		if state.action_time < 0.9:
			person.set("automatic_direction", Vector3.ZERO)
			return
		presenter.show_pistol(person)
		_move(person, source.global_position, 2.3 if distance > 12.0 else 0.0)
		if distance <= RESPONSE_LIMIT and state.attack_clock <= 0.0 and _line_of_sight(person, source):
			var muzzle: Vector3 = person.global_position + Vector3.UP * 1.2 + direction.normalized() * 0.5
			if gameplay.has_method("civilian_shoot") and gameplay.civilian_shoot(person, muzzle, 7.0):
				state.attack_clock = randf_range(1.2, 1.8)
	else:
		_move(person, source.global_position, 3.4 if distance > MELEE_REACH else 0.0)
		if distance <= MELEE_REACH and state.attack_clock <= 0.0 and _line_of_sight(person, source):
			if source.has_method("receive_damage"): source.call("receive_damage", 5.0, person)
			state.attack_clock = randf_range(1.1, 1.5)
			presenter.bubble(person, "SAI DAQUI!")

func _line_of_sight(person: CharacterBody3D, target: Node3D) -> bool:
	var from := person.global_position + Vector3.UP * 1.2
	var to := target.global_position + Vector3.UP
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 2 | 4, [person.get_rid()])
	var hit := person.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == target

func _world_owns(person: Node) -> bool: return world != null and world.people.has(person) and person.is_inside_tree()

func _steer_panic(person: CharacterBody3D, state: Dictionary, delta: float) -> void:
	state.replan -= delta
	state.stuck_clock += delta
	if state.stuck_clock >= STUCK_CHECK:
		var moved: float = person.global_position.distance_to(state.last_position)
		state.last_position = person.global_position
		state.stuck_clock = 0.0
		if moved < STUCK_DISTANCE and state.target != Vector3.ZERO:
			# Encostou (parede, veículo, outro civil): descarta esta direção e replaneja já.
			var bad: Vector3 = state.target - person.global_position
			bad.y = 0.0
			if bad.length_squared() > 0.01: state.blocked.append(bad.normalized())
			while state.blocked.size() > 3: state.blocked.pop_front()
			state.replan = 0.0
			state.target = Vector3.ZERO
			_cancel_escape(person.get_instance_id(), state)
			stats.stuck_replans += 1
	# ZERO means the previous search found no escape, not a reached waypoint.
	# Retry it on the same bounded cadence; actual arrivals still replan at once.
	var arrived: bool = state.target != Vector3.ZERO and person.global_position.distance_to(state.target) < 0.8
	if arrived: state.target = Vector3.ZERO
	if state.escape_search.is_empty() and (state.replan <= 0.0 or arrived):
		state.escape_search = state.danger.begin_escape(person, state.blocked)
		escape_queue.append(person.get_instance_id())
		stats.escape_searches += 1
	if state.target == Vector3.ZERO:
		# O susto e o início da fuga não esperam a fila. A física normal do Actor
		# continua conferindo piso/colisão e fazendo o desvio local a cada passo.
		person.set("automatic_direction", state.danger.away_from_threats(person.global_position) if not state.escape_search.is_empty() else Vector3.ZERO)
		person.set("speed", PANIC_SPEED)
	else: _move(person, state.target, PANIC_SPEED)

func _cancel_escape(id: int, state: Dictionary) -> void:
	state.escape_search = {}
	escape_queue.erase(id)

## Round robin por consulta, não por busca: um civil encurralado nunca monopoliza
## os 30 raios. A fila só guarda IDs e o plano vive no estado fraco do reator.
func _process_escape_queue() -> void:
	var frame := Engine.get_process_frames()
	if escape_budget_frame != frame:
		escape_budget_frame = frame
		escape_rays_used = 0
		escape_usec_used = 0
	var began := Time.get_ticks_usec()
	while not escape_queue.is_empty() and escape_rays_used < ESCAPE_RAYS_PER_FRAME:
		if escape_usec_used + Time.get_ticks_usec() - began >= ESCAPE_BUDGET_USEC: break
		var id: int = escape_queue.pop_front()
		var state: Dictionary = reactors.get(id, {})
		if state.is_empty(): continue
		var person = state.ref.get_ref()
		if not is_instance_valid(person) or not person.is_inside_tree() or state.phase != "panic" or person.get("dead") == true or person.get("controlled_automatically") != true:
			state.escape_search = {}
			continue
		var search: Dictionary = state.escape_search
		if search.is_empty(): continue
		var rays: int = state.danger.step_escape(person, search)
		escape_rays_used += rays
		stats.escape_rays += rays
		if search.done:
			state.target = search.target
			state.escape_search = {}
			state.replan = REPLAN_INTERVAL
			if state.target == Vector3.ZERO: person.set("automatic_direction", Vector3.ZERO)
			else: _move(person, state.target, PANIC_SPEED)
		else: escape_queue.append(id)
	escape_usec_used += Time.get_ticks_usec() - began

func _steer_recover(person: CharacterBody3D, _state: Dictionary) -> void:
	var route: PackedVector3Array = person.get("route")
	if route.size() > 1: _move(person, route[_nearest_waypoint(person, route)], RECOVER_SPEED)
	else: person.set("automatic_direction", Vector3.ZERO)

func _move(person: CharacterBody3D, target: Vector3, speed: float) -> void:
	var direction := target - person.global_position
	direction.y = 0.0
	person.set("automatic_direction", direction.normalized() if direction.length() > 0.2 else Vector3.ZERO)
	person.set("speed", speed)

func _path_clear(person: Node3D, target: Vector3) -> bool:
	var from := person.global_position + Vector3.UP * 0.9
	var query := PhysicsRayQueryParameters3D.create(from, Vector3(target.x, from.y, target.z), 1 | 4)
	query.exclude = [person.get_rid()]
	return person.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

# ── Retomada ─────────────────────────────────────────────────────────────────

func _nearest_waypoint(person: Node3D, route: PackedVector3Array) -> int:
	var best := 0
	var best_distance := INF
	for index in route.size():
		var flat := route[index] - person.global_position
		flat.y = 0.0
		if flat.length_squared() < best_distance:
			best_distance = flat.length_squared()
			best = index
	return best

func _release(id: int, restore: bool) -> void:
	var state: Dictionary = reactors.get(id, {})
	reactors.erase(id)
	escape_queue.erase(id)
	if presenter: presenter.clear_actor(id)
	if state.is_empty(): return
	state.escape_search = {}
	stats.released += 1
	var person = state.ref.get_ref()
	if not is_instance_valid(person): return
	person.remove_meta(REACTION_LOD_META)
	if person.get("controlled_automatically") == true:
		person.set("controlled_automatically", false)
		person.set("automatic_direction", Vector3.ZERO)
	person.set("speed", state.saved_speed)
	if restore:
		var route: PackedVector3Array = person.get("route")
		if route.size() > 1: person.set("waypoint", _nearest_waypoint(person, route)) # rota reengatada no ponto mais próximo
