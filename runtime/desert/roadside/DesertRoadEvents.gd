extends Node3D
## Eventos de estrada do deserto: uma van de entrega quebrada no acostamento ou um bloqueio de
## bandidos atravessado na pista, ~240 m à frente de quem dirige por um trecho vazio
## (RoadsideLayout.EVENT_STRETCHES). Um evento por vez, o primeiro ~90 s depois de chegar ao
## deserto, sem depender da história. Modelos só do trânsito comum (courier_van, ranch_single):
## já entram no pré-aquecimento da frota, então nada compila shader no meio da estrada.
const LAYOUT := preload("res://runtime/desert/roadside/RoadsideLayout.gd")
const STATE := preload("res://runtime/desert/roadside/RoadsideState.gd")
const BALANCE := preload("res://data/catalogs/EconomyBalance.gd")
const HM := preload("res://world/desert/DesertTerrainMesh.gd")
const G := preload("res://world/desert/DesertGeometry.gd")
const WILDS := preload("res://runtime/desert/wilds/DesertWilds.gd")
const RESIDENT := preload("res://runtime/desert/DesertVillageResident.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const FIRST_DELAY := 90.0
const COOLDOWN := Vector2(150.0, 240.0)
const MIN_SPEED := 8.0
const RELEASE_DISTANCE := 380.0
const RESOLVED_RELEASE := 160.0
const AGGRO_DISTANCE := 32.0
const LEASH_DISTANCE := 90.0
const GUNFIRE_DISTANCE := 70.0
const INTERACT := 2.4
## Acostamento e faixa, em metros a partir do eixo (as estradas do deserto têm 9 a 10 m).
const SHOULDER := 7.5
## Centro da picape atravessada: com ~5,2 m de comprimento ela fecha a faixa inteira e ainda cabe
## no asfalto das estradas de 9 m (borda a 4,5 m do eixo).
const LANE := 1.6
const BREAKDOWN_MODEL := "courier_van"
const ROADBLOCK_MODEL := "ranch_single"
var session
## {"kind": "breakdown"|"roadblock", "point": Vector3, "direction": Vector2, "root": Node3D,
##  "vehicle", "actors": [], "pending": [], "engaged", "helped", "looted", "resolved"}
var event: Dictionary = {}
var _desert_time := 0.0
var _next_at := FIRST_DELAY
var _last_kind := ""
var _clock := 0.0
var _rng := RandomNumberGenerator.new()

func configure(owner_session) -> void:
	session = owner_session
	name = "DesertRoadEvents"
	_rng.randomize()
	_last_kind = "roadblock" if _rng.randf() < .5 else "breakdown"
	if session.world.gameplay.has_signal("weapon_fired"): session.world.gameplay.weapon_fired.connect(_gunfire)

func _outside() -> bool:
	return is_instance_valid(session) and session.ready_for_play and session.state.region_id == "desert" and session.state.place_id.is_empty()

func _process(delta: float) -> void:
	if not is_instance_valid(session) or not session.ready_for_play: return
	if session.state.region_id != "desert":
		if not event.is_empty(): release_all()
		_desert_time = 0.0
		_next_at = FIRST_DELAY
		return
	if not session.state.place_id.is_empty(): return
	_desert_time += delta
	if not event.is_empty() and not event.pending.is_empty():
		_spawn_pending()
		return
	_clock += delta
	if _clock < .3: return
	_clock = 0.0
	if not event.is_empty(): _update_event()
	elif _desert_time >= _next_at: _try_start()

# --- Começo -----------------------------------------------------------------------------------

func _try_start() -> void:
	if session.modal or session.has_position_transition() or session.desert.busy(): return
	var world = session.world
	if not world.driving.occupied or not is_instance_valid(world.driving.car): return
	var car: CharacterBody3D = world.driving.car
	var heading := Vector2(car.velocity.x, car.velocity.z)
	if heading.length() < MIN_SPEED: return
	var at := Vector2(car.global_position.x, car.global_position.z)
	var spot := LAYOUT.event_point(at, heading)
	if spot.is_empty(): return
	var kind := "breakdown" if _last_kind == "roadblock" else "roadblock"
	force_start(kind, spot.point, spot.direction)

## Também usado pelo teste de sessão para montar cada evento num ponto conhecido.
func force_start(kind: String, point: Vector2, direction: Vector2) -> bool:
	var region: Node3D = session.controller.regions.get("desert")
	if not is_instance_valid(region): return false
	var ground := Vector3(point.x, HM.surface_height(point), point.y)
	if not region.prepare_collision_at(ground): return false
	if not event.is_empty(): release_all()
	_last_kind = kind
	var root := Node3D.new()
	root.name = "RoadEvent_" + kind
	add_child(root)
	root.global_position = ground
	root.rotation.y = atan2(-direction.x, -direction.y)
	event = {"kind": kind, "point": ground, "direction": direction.normalized(), "root": root, "vehicle": null,
		"actors": [], "pending": ["vehicle"], "engaged": false, "helped": false, "looted": false, "resolved": false}
	if kind == "breakdown":
		event.pending.append("driver")
		event.pending.append("props")
	else:
		for i in 3: event.pending.append("outlaw")
	return true

## Uma peça por quadro, só com as superfícies prontas: van/picape, motorista e bandidos.
func _spawn_pending() -> void:
	var region: Node3D = session.controller.regions.get("desert")
	if not is_instance_valid(region) or not region.surfaces_idle(): return
	region.yield_dressing_this_frame()
	var piece: String = event.pending.pop_front()
	var trace := STALL_WORK.begin()
	match piece:
		"vehicle": _spawn_vehicle()
		"driver": _spawn_driver()
		"props": _spawn_props()
		"outlaw": _spawn_outlaw(event.actors.size())
	STALL_WORK.finish_slow("desert.road_event." + piece, trace, 2000)

func _right() -> Vector2:
	var d: Vector2 = event.direction
	return Vector2(-d.y, d.x)

func _surface(point: Vector2, lift := 0.0) -> Vector3:
	return Vector3(point.x, HM.surface_height(point) + lift, point.y)

func _spawn_vehicle() -> void:
	var d: Vector2 = event.direction
	var center := Vector2(event.point.x, event.point.z)
	var model := BREAKDOWN_MODEL
	var at := center + _right() * SHOULDER
	var yaw := atan2(-d.x, -d.y)
	if event.kind == "roadblock":
		# Atravessada na faixa de quem vem: dá para desviar pelo acostamento ou pela outra mão.
		model = ROADBLOCK_MODEL
		at = center + _right() * LANE
		yaw += PI * .5
	var car: CharacterBody3D = session.controller.spawn_vehicle(model, _surface(at, .12), yaw)
	if not is_instance_valid(car): return
	# Sem o meta, a limpeza de carros parados (ProductionWorld, 145 m) soltaria o veículo antes
	# de o jogador chegar. Sai quando o evento termina.
	car.set_meta("race_owned", true)
	car.set_meta("desert_road_event", true)
	car.engine_disabled = true
	event.vehicle = car

func _spawn_driver() -> void:
	var d: Vector2 = event.direction
	var center := Vector2(event.point.x, event.point.z) + _right() * SHOULDER
	# Atrás da van, do lado de fora da pista, olhando para quem chega.
	var at := center - d * 4.4 + _right() * 1.2
	var resident := RESIDENT.new()
	var identity := _rng.randi_range(0, 8999)
	resident.specification = {"name": "Entregador", "activity": "read", "appearance": {"variant": 23000 + identity,
		"female": identity % 2 == 1, "coat": ["4f6a8a", "8a6a4c", "6c6a63"][identity % 3], "pants": "3f4644"}}
	_admit(resident, _surface(at, .06))

func _spawn_props() -> void:
	# Triângulo na pista e capô aberto (caixa inclinada): lê como "quebrado" de longe.
	var d: Vector2 = event.direction
	var triangle := Vector2(event.point.x, event.point.z) + _right() * (SHOULDER - 2.5) - d * 18.0
	var mark := G.box(event.root, "WarningTriangle", Vector3.ZERO, Vector3(.55, .5, .06), Color("d9462b"))
	mark.global_position = _surface(triangle, .25)
	mark.rotation.y = atan2(-d.x, -d.y)

func _spawn_outlaw(index: int) -> void:
	var d: Vector2 = event.direction
	var block := Vector2(event.point.x, event.point.z) + _right() * LANE
	var offsets := [Vector2(-3.5, 3.0), Vector2(3.5, 2.5), Vector2(.5, 5.5)]
	var local: Vector2 = offsets[index % offsets.size()]
	var at := block + _right() * local.x + d * local.y
	var actor = WILDS.Outlaw.new()
	actor.coordinator = self
	actor.site_id = "road_event"
	actor.configure(session.world.gameplay, index)
	actor.uniform_tones = [Color(0.45, 0.38, 0.30), Color(0.36, 0.33, 0.29), Color(0.30, 0.28, 0.27)]
	_admit(actor, _surface(at, .06))

## Posição antes de entrar na árvore: com add_child primeiro e global_position depois, o passo de
## física ainda via o corpo na origem do evento (meio da pista, dentro da picape), a picape batia
## nele como numa parede e saía a 80 m/s (teste de sessão, 19/10).
func _admit(actor: Node3D, point: Vector3) -> void:
	actor.position = event.root.to_local(point)
	# A raiz já está virada no sentido de quem dirige; PI vira o ator de frente para quem chega.
	actor.rotation.y = PI
	event.root.add_child(actor)
	event.actors.append(actor)

# --- Andamento --------------------------------------------------------------------------------

func _update_event() -> void:
	var target: Node3D = session.world.gameplay.pursuit_target()
	var point: Vector3 = event.point
	var distance := Vector2(target.global_position.x, target.global_position.z).distance_to(Vector2(point.x, point.z))
	if distance > RELEASE_DISTANCE or (event.resolved and distance > RESOLVED_RELEASE):
		release_all()
		return
	if event.kind != "roadblock": return
	var alive := _alive_outlaws()
	if alive.is_empty():
		event.engaged = false
		return
	if distance > LEASH_DISTANCE: event.engaged = false
	elif not event.engaged:
		for actor in alive:
			if actor.global_position.distance_to(target.global_position) <= AGGRO_DISTANCE and session.world.gameplay.police_can_see(actor):
				event.engaged = true
				break
	for actor in alive:
		actor.engaged = event.engaged
		if event.engaged: actor.alerted = true

func _alive_outlaws() -> Array:
	return event.get("actors", []).filter(func(actor): return is_instance_valid(actor) and not actor.dead)

func _gunfire(_weapon: String, origin: Vector3) -> void:
	if event.is_empty() or event.kind != "roadblock" or not _outside(): return
	if Vector2(event.point.x, event.point.z).distance_to(Vector2(origin.x, origin.z)) < GUNFIRE_DISTANCE: event.engaged = true

func _driver_alive() -> bool:
	for actor in event.get("actors", []):
		if is_instance_valid(actor) and not actor.dead: return true
	return false

# --- Interações -------------------------------------------------------------------------------

func nearest_action() -> Dictionary:
	if event.is_empty() or not event.pending.is_empty() or event.resolved: return {}
	var world = session.world
	if world.driving.occupied or world.player.input_locked or world.driving.is_body_transition_active(): return {}
	var at: Vector3 = world.player.global_position
	var car = event.vehicle
	if event.kind == "breakdown":
		if _driver_alive():
			if not event.helped and at.distance_to(event.actors[0].global_position) <= INTERACT:
				return _action("event_help", _t("Ajudar o entregador · R$ %d") % BALANCE.ROADSIDE_TRUCK_HELP)
		elif not event.looted and is_instance_valid(car) and at.distance_to(car.global_position) <= INTERACT + car.half_length:
			return _action("event_cashbox", "Pegar a caixinha da cabine")
		return {}
	if _alive_outlaws().is_empty() and not event.looted and is_instance_valid(car) and at.distance_to(car.global_position) <= INTERACT + car.half_length:
		return _action("event_loot", "Vasculhar a picape")
	return {}

func _action(target: String, label: String) -> Dictionary:
	return {"id": "desert_roadside", "target": target, "label": label, "provider": get_parent()}

func _t(text: String) -> String:
	return String(TranslationServer.translate(text))

func perform(target: String) -> bool:
	if nearest_action().get("target", "") != target: return false
	var economy = session.state.economy
	match target:
		"event_help":
			if not economy.grant_reward(STATE.next_receipt(session.state.world_state, "breakdown"), BALANCE.ROADSIDE_TRUCK_HELP):
				session.show_message("Carteira cheia.")
				return true
			event.helped = true
			event.resolved = true
			if is_instance_valid(event.vehicle): event.vehicle.engine_disabled = false
			session.show_message(_t("Vocês trocam a correia e a van pega · + R$ %d") % BALANCE.ROADSIDE_TRUCK_HELP)
			session.save_game()
		"event_cashbox":
			var amount := _rng.randi_range(BALANCE.ROADSIDE_TRUCK_CASHBOX.x, BALANCE.ROADSIDE_TRUCK_CASHBOX.y)
			if not economy.collect_loose_cash(amount):
				session.show_message("Carteira cheia.")
				return true
			event.looted = true
			event.resolved = true
			session.show_message(_t("Caixinha da cabine · + R$ %d") % amount)
		"event_loot":
			var amount := _rng.randi_range(BALANCE.ROADSIDE_ROADBLOCK_LOOT.x, BALANCE.ROADSIDE_ROADBLOCK_LOOT.y)
			if not economy.collect_loose_cash(amount):
				session.show_message("Carteira cheia.")
				return true
			event.looted = true
			event.resolved = true
			session.show_message(_t("Dinheiro escondido no porta-luvas · + R$ %d") % amount)
		_: return false
	return true

# --- Sessão ----------------------------------------------------------------------------------

func save_block_reason() -> String:
	if event.is_empty() or event.kind != "roadblock" or not event.engaged: return ""
	return "Afaste-se dos bandidos antes de salvar." if not _alive_outlaws().is_empty() else ""

## Solta tudo do evento atual; a van ou picape que o jogador pegou fica com ele.
func release_all() -> void:
	if event.is_empty(): return
	var car = event.vehicle
	if is_instance_valid(car) and not car.is_queued_for_deletion():
		for meta in ["race_owned", "desert_road_event"]:
			if car.has_meta(meta): car.remove_meta(meta)
		car.engine_disabled = false
		if not (is_instance_valid(session) and session.world.driving.car == car):
			car.set_physics_process(false)
			if is_instance_valid(session): session.controller.vehicles.erase(car)
			car.queue_free()
	for actor in event.actors:
		if is_instance_valid(actor):
			actor.set_physics_process(false)
			actor.collision_layer = 0
			actor.collision_mask = 0
	if is_instance_valid(event.root): event.root.queue_free()
	event = {}
	_next_at = _desert_time + _rng.randf_range(COOLDOWN.x, COOLDOWN.y)

func _exit_tree() -> void:
	release_all()
