extends Node3D
## Coordenador da beira de estrada do deserto (RoadsideLayout): monta os lugares perto do jogador
## (um por passo, só com o chão pronto) e estaciona em vez de soltar, oferece as interações e
## cuida da entrega do orelhão. Os eventos de estrada ficam em DesertRoadEvents.
const LAYOUT := preload("res://runtime/desert/roadside/RoadsideLayout.gd")
const STATE := preload("res://runtime/desert/roadside/RoadsideState.gd")
const BUILD := preload("res://runtime/desert/roadside/RoadsideBuild.gd")
const SECRETS := preload("res://runtime/desert/roadside/RoadsideSecrets.gd")
const EVENTS := preload("res://runtime/desert/roadside/DesertRoadEvents.gd")
const BALANCE := preload("res://data/catalogs/EconomyBalance.gd")
const HM := preload("res://world/desert/DesertTerrainMesh.gd")
const G := preload("res://world/desert/DesertGeometry.gd")
const RESIDENT := preload("res://runtime/desert/DesertVillageResident.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const GARAGE := preload("res://runtime/GarageRewards.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
const INTERACT := 1.8
const SERVICE_RADIUS := 6.0
const COURIER_ARRIVAL := 12.0
## Além do que o Neco recusa (GarageRewards.PROTECTED_*): carros de corrida, missão e história.
const PROTECTED_META := ["race_owned", "desert_drag_physics", "armored_transport"]
const STORY_IDS := ["jessica_jetta_gli", "digo_gol_1993", "digo_amarok_2014"]
var session
## id → {"root", "actors", "parked", "definition"}
var sites: Dictionary = {}
var events: Node3D
## Entrega ativa: {"route", "left", "receipt"}; vazio quando não há.
var courier: Dictionary = {}
var _clock := 0.0

func configure(owner_session) -> void:
	session = owner_session
	name = "DesertRoadside"
	# Antes do deserto no quadro: no quadro em que um lugar monta, o enfeite cede a vez.
	process_priority = -1
	if not LAYOUT.enabled():
		set_process(false)
		return
	events = EVENTS.new()
	add_child(events)
	events.configure(session)

static func ground(point: Vector2) -> Vector3:
	return Vector3(point.x, HM.surface_height(point), point.y)

func _outside() -> bool:
	return is_instance_valid(session) and session.ready_for_play and session.state.region_id == "desert" and session.state.place_id.is_empty()

func _process(delta: float) -> void:
	if not courier.is_empty(): _tick_courier(delta)
	_walk_in_roofs()
	_clock += delta
	if _clock < .3: return
	_clock = 0.0
	if not _outside():
		_park_all()
		return
	var player: Vector3 = session.world.player.global_position
	var planar := Vector2(player.x, player.z)
	var region: Node3D = session.controller.regions.get("desert")
	if not is_instance_valid(region): return
	var built_one := false
	for definition in LAYOUT.all_sites():
		var id := str(definition.id)
		var distance := planar.distance_to(definition.center)
		var build_at := float(definition.get("build", LAYOUT.BUILD_DISTANCE))
		var park_at := float(definition.get("park", LAYOUT.PARK_DISTANCE))
		if sites.has(id):
			var record: Dictionary = sites[id]
			if distance > park_at and not record.parked: _park(record, true)
			elif distance < build_at and record.parked and region.prepare_collision_at(ground(definition.center)): _park(record, false)
		elif not built_one and distance < build_at and region.surfaces_idle():
			if not region.prepare_collision_at(ground(definition.center)): continue
			region.yield_dressing_this_frame()
			var trace := STALL_WORK.begin()
			sites[id] = _build(definition)
			STALL_WORK.finish_slow("desert.roadside.build", trace, 2000)
			built_one = true
	if not built_one: _park_vehicles(planar)

## Um veículo por passo: estaciona o carro de um lugar montado que esteja faltando (o controlador
## recolhe carro parado a mais de 145 m). Carro levado pelo jogador fica com ele; só volta outro
## quando aquele sumir.
func _park_vehicles(player: Vector2) -> void:
	for record in sites.values():
		if record.parked or not record.has("parked_cars"): continue
		var slots: Array = LAYOUT.PARKED.get(str(record.definition.kind), [])
		for index in slots.size():
			var car: Variant = record.parked_cars.get(index)
			if car != null and is_instance_valid(car) and not car.is_queued_for_deletion(): continue
			var slot: Array = slots[index]
			var at := LAYOUT.at(record.definition, slot[1])
			var distance := player.distance_to(Vector2(at.x, at.z))
			if distance < LAYOUT.PARKED_SPAWN_MIN or distance > LAYOUT.PARKED_SPAWN_MAX: continue
			var trace := STALL_WORK.begin()
			var spawned: CharacterBody3D = session.controller.spawn_vehicle(str(slot[0]), ground(Vector2(at.x, at.z)) + Vector3.UP * .1, float(record.definition.yaw) + float(slot[2]))
			STALL_WORK.finish_slow("desert.roadside.parked_vehicle", trace, 2000)
			if spawned != null: spawned.set_meta("roadside_site", str(record.definition.id))
			record.parked_cars[index] = spawned
			return

## Cômodos de entrar a pé (Estrada do Sal): com o jogador dentro, o telhado some para a câmera de
## cima ver o cômodo. Por quadro, mas só nos lugares montados que têm cômodo (três) e sem alocar.
func _walk_in_roofs() -> void:
	if sites.is_empty() or not is_instance_valid(session) or not session.ready_for_play: return
	var player: Vector3 = session.world.player.global_position
	for record in sites.values():
		if record.parked or not record.has("roofs"): continue
		var roofs: Node3D = record.roofs
		if not is_instance_valid(roofs): continue
		var local := (record.root as Node3D).to_local(player)
		var inside := false
		if local.y < 3.5:
			for rect: Rect2 in roofs.get_meta("walk_in", []):
				if rect.has_point(Vector2(local.x, local.z)):
					inside = true
					break
		if roofs.visible == inside: roofs.visible = not inside

func _build(definition: Dictionary) -> Dictionary:
	var root := Node3D.new()
	root.name = "Roadside_" + str(definition.id)
	root.position = ground(definition.center)
	root.rotation.y = float(definition.yaw)
	add_child(root)
	var record := {"root": root, "actors": [], "parked": false, "definition": definition}
	match str(definition.kind):
		"station":
			BUILD.station(root)
			_admit_resident(root, record, LAYOUT.SOL_MECHANIC, 0.0, "Mecânico", "read", 41)
		"tower": BUILD.tower(root)
		"scrapyard":
			BUILD.scrapyard(root)
			_admit_resident(root, record, LAYOUT.SCRAP_DEALER, 0.0, "Nonato", "read", 57)
		"food_truck":
			BUILD.food_truck(root)
			_admit_resident(root, record, LAYOUT.FOOD_VENDOR, 0.0, "Dona Cida", "cook", 63)
		"salt_works":
			BUILD.salt_works(root)
			_admit_resident(root, record, LAYOUT.SALT_FOREMAN, PI, "Seu Bento", "read", 71)
		"weigh_station":
			BUILD.weigh_station(root)
			_admit_resident(root, record, LAYOUT.WEIGH_INSPECTOR, 0.0, "Fiscal Rosa", "read", 74)
		"motel":
			BUILD.motel(root)
			_admit_resident(root, record, LAYOUT.MOTEL_CLERK, PI, "Dona Lurdes", "read", 77)
		"chapel":
			BUILD.chapel(root)
			_admit_resident(root, record, LAYOUT.CHAPEL_KEEPER, 0.0, "Dona Fátima", "read", 81)
		"town_street", "homes_yards", "village_square", "workshop_yard":
			BUILD.dressing(root, str(definition.kind))
		"grandstand":
			BUILD.grandstand(root)
			_admit_resident(root, record, LAYOUT.TIMEKEEPER, 0.0, "Seu Zé do Cronômetro", "read", 84)
	var roofs := root.get_node_or_null("WalkInRoofs")
	if roofs != null: record["roofs"] = roofs
	record["parked_cars"] = {}
	G.batch_repeated_meshes(root)
	return record

func _admit_resident(root: Node3D, record: Dictionary, local: Vector3, yaw: float, display_name: String, activity: String, identity: int) -> void:
	var world_point := root.global_transform * local
	world_point.y = HM.surface_height(Vector2(world_point.x, world_point.z)) + .06
	var resident := RESIDENT.new()
	resident.specification = {"name": display_name, "activity": activity, "appearance": {"variant": 21000 + identity,
		"female": identity % 2 == 1, "coat": ["8a6a4c", "5f6f5a", "9a5d45", "6c6a63"][identity % 4], "pants": "4a4238"}}
	# Posição e giro locais antes de entrar na árvore (ver DesertRoadEvents._admit).
	resident.position = root.to_local(world_point)
	resident.rotation.y = yaw
	root.add_child(resident)
	record.actors.append(resident)

## Estacionar: some da tela e para de processar, mas fica montado para a próxima visita.
func _park(record: Dictionary, parked: bool) -> void:
	record.parked = parked
	var root: Node3D = record.root
	if not is_instance_valid(root): return
	root.visible = not parked
	for actor in record.actors:
		if not is_instance_valid(actor) or actor.get("dead") == true: continue
		actor.set_physics_process(not parked)
		actor.collision_layer = 0 if parked else 2

func _park_all() -> void:
	for record in sites.values():
		if not record.parked: _park(record, true)

func _record(id: String) -> Dictionary:
	var record: Dictionary = sites.get(id, {})
	return record if not record.is_empty() and not record.parked and is_instance_valid(record.root) else {}

func _near(id: String, local: Vector3, radius: float, position: Vector3) -> bool:
	var record := _record(id)
	if record.is_empty(): return false
	var point := LAYOUT.at(record.definition, local)
	return Vector2(point.x, point.z).distance_to(Vector2(position.x, position.z)) <= radius and absf(position.y - record.root.global_position.y) < 2.5

func _action(target: String, label: String) -> Dictionary:
	return {"id": "desert_roadside", "target": target, "label": label, "provider": self}

func _t(text: String) -> String:
	return String(TranslationServer.translate(text))

# --- Interações -------------------------------------------------------------------------------

func nearest_action() -> Dictionary:
	if not _outside() or not LAYOUT.enabled() or session.modal or session.has_position_transition() or session.desert.busy(): return {}
	var world = session.world
	if world.gameplay.health <= 0 or world.player.dead: return {}
	if is_instance_valid(events):
		var event_action: Dictionary = events.nearest_action()
		if not event_action.is_empty(): return event_action
	if world.driving.occupied:
		var car: CharacterBody3D = world.driving.car
		if is_instance_valid(car) and absf(float(car.speed)) < 1.0 and _needs_repair(car) and _near("sol_poente", LAYOUT.SOL_SERVICE, SERVICE_RADIUS, car.global_position):
			return _action("repair", _t("Consertar o carro · R$ %d") % BALANCE.ROADSIDE_REPAIR)
		return {}
	if world.player.input_locked or world.driving.is_body_transition_active(): return {}
	var at: Vector3 = world.player.global_position
	if courier.is_empty() and _near("sol_poente", LAYOUT.SOL_PAYPHONE, INTERACT, at): return _action("payphone", "Atender o orelhão")
	if _near("radio_tower", LAYOUT.TOWER_LADDER, INTERACT, at): return _action("tower", "Subir na torre")
	if _near("scrapyard", LAYOUT.SCRAP_DEALER, 2.4, at):
		var bay_car := _bay_car()
		if is_instance_valid(bay_car): return _action("scrap", _t("Vender o carro do pátio · R$ %d") % GARAGE.scrap_value(bay_car))
		return _action("scrap_talk", "Falar com o Nonato")
	if _near("food_truck", LAYOUT.FOOD_COUNTER, INTERACT, at):
		return _action("food", _t("Comprar sanduíche · R$ %d") % int(ECONOMY.SUPPLIES.sandwich.price))
	return {}

func perform(action: Dictionary) -> bool:
	if action.get("id", "") != "desert_roadside": return false
	var target := str(action.get("target", ""))
	if target.begins_with("event_"): return is_instance_valid(events) and events.perform(target)
	if nearest_action().get("target", "") != target: return false
	match target:
		"repair": return _repair()
		"payphone": return _start_courier()
		"tower": return _climb_tower()
		"scrap": return _sell_scrap()
		"scrap_talk":
			session.show_message("Traga um carro que não seja seu e deixe parado no pátio. Pago o peso da sucata.")
			return true
		"food": return _buy_food()
	return false

func _needs_repair(car: Node) -> bool:
	return float(car.get("health")) < float(car.get("max_health")) - .5 or int(car.get_meta("punctured_tires", 0)) > 0

func _repair() -> bool:
	var car: CharacterBody3D = session.world.driving.car
	if not is_instance_valid(car): return false
	var economy = session.state.economy
	if not economy.spend(BALANCE.ROADSIDE_REPAIR, STATE.next_receipt(session.state.world_state, "repair")):
		session.show_message("Dinheiro insuficiente para o conserto.")
		return true
	car.repair()
	session.show_message("Carro consertado no Sol Poente.")
	session.save_game()
	return true

func _start_courier() -> bool:
	var routes: Array = LAYOUT.COURIER_ROUTES
	var receipt := STATE.next_receipt(session.state.world_state, "courier")
	var route: Dictionary = routes[int(STATE.data(session.state.world_state).serial) % routes.size()]
	courier = {"route": route, "left": float(route.seconds), "receipt": receipt}
	var pay := int(BALANCE.ROADSIDE_COURIER.get(str(route.id), 0))
	session.show_message(_t("Voz no orelhão: leve o pacote do balcão até o %s em %d s. Pago R$ %d.") % [_t(str(route.name)), int(route.seconds), pay])
	return true

func _tick_courier(delta: float) -> void:
	if session.get_tree().paused: return
	courier.left = float(courier.left) - delta
	var route: Dictionary = courier.route
	var at: Vector3 = session.world.driving.car.global_position if session.world.driving.occupied and is_instance_valid(session.world.driving.car) else session.world.player.global_position
	if session.state.region_id == "desert" and Vector2(at.x, at.z).distance_to(Vector2(route.point.x, route.point.z)) <= COURIER_ARRIVAL:
		var pay := int(BALANCE.ROADSIDE_COURIER.get(str(route.id), 0))
		var receipt := str(courier.receipt)
		courier = {}
		if session.state.economy.grant_reward(receipt, pay):
			session.show_message(_t("Entrega feita · + R$ %d") % pay)
			session.save_game()
		return
	if float(courier.left) <= 0.0:
		courier = {}
		session.show_message("O prazo da entrega acabou.")

func _climb_tower() -> bool:
	var record := _record("radio_tower")
	var origin: Vector3 = record.root.global_position if not record.is_empty() else session.world.player.global_position
	# Cada subida aponta até três achados novos; os já marcados ficam no mapa até serem achados.
	var seen: Array = SECRETS.nearest(session.state.world_state, session.state.economy, origin, 3, STATE.data(session.state.world_state).revealed)
	if seen.is_empty():
		session.show_message("Do alto da torre não sobrou nada novo à vista. O que você já avistou continua no mapa.")
		return true
	STATE.reveal(session.state.world_state, seen.map(func(entry): return entry.id))
	var names: Array[String] = []
	for entry in seen: names.append(_t(str(entry.name)))
	session.show_message(_t("Do alto da torre você avista: %s. Marcado no mapa.") % ", ".join(names))
	session.save_game()
	return true

## Carro parado no pátio do ferro-velho que o jogador pode vender (não é dele nem de missão).
func _bay_car() -> CharacterBody3D:
	var record := _record("scrapyard")
	if record.is_empty(): return null
	var bay := LAYOUT.at(record.definition, LAYOUT.SCRAP_BAY)
	for car in session.controller.vehicles:
		if not is_instance_valid(car) or car.is_queued_for_deletion() or car.health <= 0: continue
		if Vector2(car.global_position.x, car.global_position.z).distance_to(Vector2(bay.x, bay.z)) > 4.5: continue
		if absf(float(car.speed)) > .5 or car.controlled or _owned(car): continue
		return car
	return null

func _owned(car: Node) -> bool:
	var id := str(car.get("vehicle_id"))
	if id in GARAGE.PROTECTED_IDS or id in STORY_IDS: return true
	for meta in GARAGE.PROTECTED_META + PROTECTED_META:
		if car.get_meta(meta, false): return true
	var fleet: Variant = session.state.world_state.get("desert_fleet", {})
	return fleet is Dictionary and fleet.has(id)

## Mesmo contrato da prensa do Neco (GarageRewards._finish_scrap): o valor pelo tamanho do carro e
## o limite diário de entregas na prensa, que o ferro-velho divide com o guincho e o Neco. Sem isso
## o deserto virava uma fonte de dinheiro sem teto (carro da estrada → R$ 600, de novo e de novo).
func _sell_scrap() -> bool:
	var car := _bay_car()
	if not is_instance_valid(car): return false
	if session.world.gameplay.stars > 0:
		session.show_message("Com a polícia atrás de você, o Nonato não compra nada.")
		return true
	if session.activities == null or session.activities.salvage_available() <= 0:
		session.show_message("A prensa já trabalhou demais hoje. Volte amanhã.")
		return true
	var reward := GARAGE.scrap_value(car)
	var wallet: Dictionary = session.state.economy.snapshot()
	if not session.state.economy.grant_reward(session.activities.salvage_receipt("desert_scrap"), reward) or not session.activities.record_external_delivery():
		session.state.economy.restore_snapshot(wallet)
		session.show_message("O Nonato não conseguiu pagar agora. O carro ficou no pátio.")
		return true
	# Remoção deliberada: se era o último carro dirigido, Driving/ProductionWorld soltam a
	# referência e o snapshot do veículo do jogador (como na prensa do Neco).
	car.queue_free()
	session.show_message(_t("O Nonato prensa o carro · + R$ %d") % reward)
	session.save_game()
	return true

func _buy_food() -> bool:
	var result: Dictionary = session.state.economy.purchase("supply", "sandwich", STATE.next_receipt(session.state.world_state, "food"))
	if bool(result.get("ok", false)):
		session.show_message("Sanduíche comprado na Dona Cida.")
		session.save_game()
	elif str(result.get("reason", "")) == "inventory_full": session.show_message("Inventário cheio.")
	else: session.show_message("Dinheiro insuficiente.")
	return true

# --- Sessão ----------------------------------------------------------------------------------

func objective() -> String:
	if courier.is_empty(): return ""
	return _t("Entrega · leve o pacote até o %s · %d s") % [_t(str(courier.route.name)), maxi(0, ceili(float(courier.left)))]

func save_block_reason() -> String:
	if not courier.is_empty(): return "Entregue o pacote ou deixe o prazo acabar para salvar."
	return events.save_block_reason() if is_instance_valid(events) else ""

## Morte, prisão, viagem e carregar: a entrega e o evento em curso acabam; os lugares ficam.
func cancel_attempt() -> void:
	courier = {}
	if is_instance_valid(events): events.release_all()

func _exit_tree() -> void:
	if is_instance_valid(events): events.release_all()
