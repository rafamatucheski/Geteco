extends SceneTree
## Beira de estrada do deserto na sessão real (Main + save isolado): cada lugar monta perto do
## jogador e estaciona longe; conserto, entrega do orelhão, torre, ferro-velho e lanche passam
## pelo interact() da sessão (FullSession → DesertRuntime → fronteira → beira de estrada); os
## dois eventos de estrada são forçados num ponto conhecido.
## Uso (com tela): "$GODOT" --path . --script res://tests/test_desert_roadside_session.gd -- --no-save --no-traffic
## Capturas e checkpoint em uma pasta exclusiva por execução (fora do Git).
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const LAYOUT := preload("res://runtime/desert/roadside/RoadsideLayout.gd")
const STATE := preload("res://runtime/desert/roadside/RoadsideState.gd")
const ROADSIDE := preload("res://runtime/desert/roadside/DesertRoadside.gd")
const BALANCE := preload("res://data/catalogs/EconomyBalance.gd")
const GARAGE := preload("res://runtime/GarageRewards.gd")
const HM := preload("res://world/desert/DesertTerrainMesh.gd")
const AUTOPILOT := preload("res://runtime/BenchmarkAutopilot.gd")
const DESERT_LAYOUT := preload("res://world/desert/DesertLayout.gd")
var FOLDER := ""
## Terreno ocupado por cada lugar em coordenadas locais (x, z), de RoadsideBuild.
const FOOTPRINTS := {"station": Rect2(-12, -8, 24, 20), "tower": Rect2(-8, -7, 16, 14),
	"scrapyard": Rect2(-15, -12, 30, 20), "food_truck": Rect2(-4, -2, 9, 8),
	# Estrada do Sal (20/10): sem a faixa de cascalho até a pista nem o letreiro na beira.
	"salt_works": Rect2(-52, -40, 104, 76), "weigh_station": Rect2(-17, -1, 34, 20), "motel": Rect2(-22, -6, 44, 22),
	"chapel": Rect2(-10, -10, 20, 20), "grandstand": Rect2(-17, -10, 40, 17)}
var world: Node3D
var session
var roadside: Node3D
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	create_timer(480).timeout.connect(func(): failures.append("watchdog 480 s"); finish(3))
	run.call_deferred()

func check(value: bool, label: String) -> bool:
	checks += 1
	print("DESERT_ROADSIDE ", "PASS " if value else "FAIL ", label)
	if not value: failures.append(label)
	return value

func frames(count: int) -> void:
	for i in count: await physics_frame

func until(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call(): return true
		await physics_frame
	return condition.call()

func stand(point: Vector3) -> void:
	var at := Vector3(point.x, HM.surface_height(Vector2(point.x, point.z)) + .1, point.z)
	world.player.teleport(at)
	world.production.region.set_focus(at, true)
	await frames(4)

func local_point(id: String, local: Vector3) -> Vector3:
	return LAYOUT.at(LAYOUT.site(id), local)

func event_stretch(id: String) -> Dictionary:
	for stretch in LAYOUT.EVENT_STRETCHES:
		if str(stretch.id) == id: return stretch
	return {}

func act(target: String, label: String) -> bool:
	var action: Dictionary = session.nearest()
	if not check(str(action.get("id", "")) == "desert_roadside" and str(action.get("target", "")) == target, "%s: ação oferecida (%s)" % [label, action.get("target", action.get("id", "nenhuma"))]): return false
	return check(await session.interact(), "%s: interact() executa" % label)

func run() -> void:
	if not check("--no-save" in OS.get_cmdline_user_args(), "--no-save obrigatório"): finish(2); return
	root.size = Vector2i(1280, 720)
	FOLDER = FIXTURE.output_dir("desert-roadside-compact")
	if not check(not FOLDER.is_empty(), "pasta exclusiva de evidências criada"): finish(2); return
	var start: Dictionary = LAYOUT.site("sol_poente")
	var arrival := Vector3(start.center.x - 60, 0, start.center.y + 30)
	arrival.y = HM.surface_height(Vector2(arrival.x, arrival.z)) + .1
	var output := FOLDER
	var data := FIXTURE.full_snapshot(arrival, true)
	data.region_id = "desert"
	data.world.pedestrian = {"region": "desert", "position": [arrival.x, arrival.y, arrival.z]}
	data.economy.balance = 5000
	var path := FIXTURE.write_fixture(output, "checkpoint.json", data)
	if not check(not path.is_empty(), "save isolado do deserto válido"): finish(1); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("menu_save_path", path)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if world.get("session") != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if not check(world.get("session") != null and world.session.ready_for_play, "sessão real carregou"): finish(1); return
	session = world.session
	if session.modal: session.close_menu()
	roadside = session.desert.frontier.roadside
	if not check(is_instance_valid(roadside) and is_instance_valid(roadside.events), "DesertFrontierRuntime instala a beira de estrada e os eventos"): finish(1); return
	var region: Node3D = session.controller.regions.get("desert")
	# Nenhum lugar em cima de prédio, ladeira, trilha ou reserva de outro sistema: amostra o terreno
	# de cada lugar (retângulo local) a cada 2 m com a mesma regra do enfeite do deserto.
	LAYOUT._enabled = 0
	for definition in LAYOUT.SITES:
		var footprint: Rect2 = FOOTPRINTS[str(definition.kind)]
		var blocked := []
		var sampled := 0
		for x in range(int(footprint.position.x), int(footprint.end.x) + 1, 2):
			for z in range(int(footprint.position.y), int(footprint.end.y) + 1, 2):
				var point := LAYOUT.at(definition, Vector3(x, 0, z))
				sampled += 1
				if not region._decoration_clear(Vector2(point.x, point.z), .5): blocked.append(Vector2(x, z))
		check(blocked.is_empty(), "%s em chão livre (%d pontos, bloqueados %s)" % [definition.id, sampled, blocked])
	LAYOUT._enabled = 1
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.gameplay.health = 100000.0
	# Sem evento automático no meio das checagens dos lugares.
	roadside.events._next_at = INF
	for definition in LAYOUT.SITES:
		var id := str(definition.id)
		await stand(local_point(id, Vector3(0, 0, 40)))
		if not check(await until(func(): return roadside.sites.has(id), 25.0), "%s monta perto do jogador" % id): continue
		var record: Dictionary = roadside.sites[id]
		await frames(30)
		var expected := 0 if id == "radio_tower" else 1
		check(record.actors.size() == expected, "%s tem %d morador(es)" % [id, expected])
		for actor in record.actors:
			var ground := HM.surface_height(Vector2(actor.global_position.x, actor.global_position.z))
			check(is_instance_valid(actor) and absf(actor.global_position.y - ground) < .6, "%s: morador no chão" % id)
		match id:
			"sol_poente": await sol_poente()
			"radio_tower": await radio_tower()
			"scrapyard": await scrapyard()
			"food_truck": await food_truck()
			"salt_works": await salt_works()
			"weigh_station": await weigh_station()
			"motel": await motel()
			"chapel": await chapel()
			"grandstand": await grandstand()
		await stand(local_point(id, Vector3(0, 0, 7.0 if id == "food_truck" else 9.5)))
		world.camera.initialized = false
		for i in 40: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/%s.png" % [FOLDER, id]))
	await parking()
	await breakdown_event()
	await roadblock_event()
	await natural_event()
	finish(0 if failures.is_empty() else 1)

func sol_poente() -> void:
	var economy = session.state.economy
	# Orelhão: entrega cronometrada até o destino sorteado pela sequência de recibos.
	await stand(local_point("sol_poente", LAYOUT.SOL_PAYPHONE))
	if await act("payphone", "orelhão"):
		check(not roadside.courier.is_empty() and not roadside.objective().is_empty(), "entrega ativa com objetivo na tela (%s)" % roadside.objective())
		check(not session.desert.save_block_reason().is_empty(), "salvar bloqueado durante a entrega")
		var route: Dictionary = roadside.courier.route
		var pay := int(BALANCE.ROADSIDE_COURIER[str(route.id)])
		var before: int = economy.balance
		await stand(route.point)
		check(await until(func(): return roadside.courier.is_empty(), 3.0) and economy.balance == before + pay, "entrega no %s paga R$ %d (saldo %d → %d)" % [route.id, pay, before, economy.balance])
		check(session.desert.save_block_reason().is_empty(), "salvar volta depois da entrega")
		await stand(local_point("sol_poente", Vector3(0, 0, 40)))
		await until(func(): return not roadside.sites.sol_poente.parked, 10.0)
	# Conserto: carro batido parado na frente da oficina, com o jogador ao volante.
	var service := local_point("sol_poente", LAYOUT.SOL_SERVICE)
	service.y = HM.surface_height(Vector2(service.x, service.z)) + .12
	var car: CharacterBody3D = session.controller.spawn_vehicle("union_sedan", service, float(LAYOUT.site("sol_poente").yaw))
	if not check(is_instance_valid(car), "carro de teste na frente da oficina"): return
	await frames(10)
	var entered := false
	for side in [-1, 1]:
		await stand(car.to_global(Vector3(side * (car.half_width + .65), .04, .15)))
		if world.driving.interact():
			entered = await until(func(): return world.driving.occupied and not world.driving.is_body_transition_active(), 8.0)
			if entered: break
	if not check(entered, "jogador entra no carro de teste"): return
	car.health = car.max_health * .4
	await until(func(): return absf(car.speed) < .5, 5.0)
	var before: int = economy.balance
	if await act("repair", "conserto no posto"):
		check(car.health >= car.max_health - .01 and economy.balance == before - BALANCE.ROADSIDE_REPAIR, "conserto cobra R$ %d e deixa o carro inteiro" % BALANCE.ROADSIDE_REPAIR)
	check(session.nearest().get("target", "") != "repair", "carro inteiro não oferece conserto")
	world.driving.leave()
	await until(func(): return not world.driving.occupied and not world.driving.is_body_transition_active(), 8.0)

func radio_tower() -> void:
	await stand(local_point("radio_tower", LAYOUT.TOWER_LADDER))
	if await act("tower", "torre de rádio"):
		var revealed: Array = STATE.data(session.state.world_state).revealed
		check(revealed.size() == 3, "torre marca três achados (%s)" % [revealed])
		var markers := preload("res://ui/hud/WorldMapData.gd").new()
		markers.collect(session.controller)
		var seen := markers.markers.filter(func(entry): return str(entry.id).begins_with("roadside_seen_"))
		check(seen.size() == 3, "mapa mostra os três avistados")
		check(markers.markers.filter(func(entry): return str(entry.id).begins_with("roadside_") and not str(entry.id).begins_with("roadside_seen_")).size() == LAYOUT.SITES.size(), "mapa mostra os quatro lugares")
	if await act("tower", "segunda subida"):
		check(STATE.data(session.state.world_state).revealed.size() == 6, "segunda subida marca outros três")

func scrapyard() -> void:
	var economy = session.state.economy
	var bay := local_point("scrapyard", LAYOUT.SCRAP_BAY)
	bay.y = HM.surface_height(Vector2(bay.x, bay.z)) + .12
	var car: CharacterBody3D = session.controller.spawn_vehicle("union_sedan", bay, float(LAYOUT.site("scrapyard").yaw))
	if not check(is_instance_valid(car), "carro de teste no pátio do ferro-velho"): return
	await frames(20)
	await stand(local_point("scrapyard", LAYOUT.SCRAP_DEALER + Vector3(0, 0, 1.4)))
	# Carro do jogador (garagem) não é sucata.
	car.set_meta("garage_reward", true)
	await act("scrap_talk", "carro protegido só conversa")
	car.remove_meta("garage_reward")
	var value := GARAGE.scrap_value(car)
	var before: int = economy.balance
	var used: int = session.activities.salvage_available()
	if await act("scrap", "venda no ferro-velho"):
		check(economy.balance == before + value and car.is_queued_for_deletion(), "Nonato paga R$ %d e prensa o carro" % value)
		check(session.activities.salvage_available() == used - 1, "venda conta no limite diário da prensa")

func food_truck() -> void:
	var economy = session.state.economy
	await stand(local_point("food_truck", LAYOUT.FOOD_COUNTER))
	var before: int = economy.balance
	if await act("food", "lanche da reta"):
		check(economy.balance == before - int(preload("res://systems/economy/Economy.gd").SUPPLIES.sandwich.price), "sanduíche custa o preço da loja")

## Ao lado do morador (não em cima dele, que tem corpo): todos ficam a menos de 2,4 m.
func beside(id: String, local: Vector3) -> void:
	await stand(local_point(id, local + Vector3(.9, 0, 0)))
	await frames(6)

func salt_works() -> void:
	var economy = session.state.economy
	await beside("salt_works", LAYOUT.SALT_FOREMAN)
	if not await act("salt_run", "frete de sal"): return
	check(str(roadside.courier.get("route", {}).get("id", "")) == "sal", "frete de sal vira a entrega em curso")
	check(session.nearest().get("target", "") != "salt_run", "um frete por vez")
	var before: int = economy.balance
	await stand(LAYOUT.SALT_ROUTE.point)
	check(await until(func(): return roadside.courier.is_empty(), 6.0), "chegar ao mercado encerra o frete")
	check(economy.balance == before + int(BALANCE.ROADSIDE_COURIER.sal), "frete de sal paga R$ %d" % int(BALANCE.ROADSIDE_COURIER.sal))
	await stand(local_point("salt_works", Vector3(0, 0, 40)))
	await until(func(): return not roadside.sites.salt_works.parked, 10.0)

func weigh_station() -> void:
	await beside("weigh_station", LAYOUT.WEIGH_INSPECTOR)
	await act("weigh_talk", "conversa com a fiscal")
	var spot := local_point("weigh_station", LAYOUT.WEIGH_PLATFORM + Vector3(3.5, 0, 0))
	spot.y = HM.surface_height(Vector2(spot.x, spot.z)) + .3
	var car: CharacterBody3D = session.controller.spawn_vehicle("union_sedan", spot, float(LAYOUT.site("weigh_station").yaw) + PI * .5)
	if not check(is_instance_valid(car), "carro de teste na balança"): return
	await frames(10)
	var entered := false
	for side in [-1, 1]:
		await stand(car.to_global(Vector3(side * (car.half_width + .65), .04, .15)))
		if world.driving.interact():
			entered = await until(func(): return world.driving.occupied and not world.driving.is_body_transition_active(), 8.0)
			if entered: break
	if not check(entered, "jogador entra no carro na balança"): return
	await until(func(): return absf(car.speed) < .5, 5.0)
	await act("weigh", "pesagem na balança")
	world.driving.leave()
	await until(func(): return not world.driving.occupied and not world.driving.is_body_transition_active(), 8.0)
	car.queue_free()

func motel() -> void:
	var economy = session.state.economy
	await beside("motel", LAYOUT.MOTEL_CLERK)
	session.weather.time_of_day = 22.0 / 24.0
	var before: int = economy.balance
	if await act("motel_room", "quarto no Motel Oásis"):
		check(economy.balance == before - BALANCE.ROADSIDE_MOTEL_ROOM, "quarto custa R$ %d" % BALANCE.ROADSIDE_MOTEL_ROOM)
		check(absf(session.weather.time_of_day - 7.0 / 24.0) < .001, "acorda às 7h")
	session.weather.time_of_day = 13.0 / 24.0

func chapel() -> void:
	var economy = session.state.economy
	await beside("chapel", LAYOUT.CHAPEL_KEEPER)
	var before: int = economy.balance
	if await act("candle", "vela na capela"):
		check(economy.balance == before - BALANCE.ROADSIDE_CANDLE, "vela custa R$ %d" % BALANCE.ROADSIDE_CANDLE)

func grandstand() -> void:
	await beside("grandstand", LAYOUT.TIMEKEEPER)
	await act("timekeeper", "cronometrista da arquibancada")

func parking() -> void:
	# Mantém as identidades de todo lugar admitido, incluindo acabamentos autorais próximos.
	var admitted: Dictionary = {}
	var authored: Dictionary = {}
	for definition in LAYOUT.all_sites(): authored[str(definition.id)] = true
	for id in roadside.sites:
		admitted[id] = roadside.sites[id].root.get_instance_id()
	var all_places_present := true
	for definition in LAYOUT.SITES:
		all_places_present = all_places_present and admitted.has(str(definition.id))
	check(all_places_present, "all authored places admitted before parking")
	var far: Vector2 = DESERT_LAYOUT.BOUNDS.position+Vector2(24,24)
	await stand(Vector3(far.x, 0, far.y))
	check(await until(func(): return roadside.sites.values().all(func(record): return record.parked and not record.root.visible), 3.0), "lugares estacionam longe do jogador")
	var retained := true
	for id in admitted:
		retained = retained and roadside.sites.has(id)
		if not roadside.sites.has(id): continue
		var site_root: Node3D = roadside.sites[id].root
		retained = retained and is_instance_valid(site_root) and not site_root.is_queued_for_deletion() and site_root.get_instance_id() == admitted[id]
	for id in roadside.sites: retained = retained and authored.has(id)
	check(retained, "all admitted place IDs and instances retained, with legitimate dressings")
	await stand(local_point("food_truck", Vector3(0, 0, 40)))
	check(await until(func(): return not roadside.sites.food_truck.parked and roadside.sites.food_truck.root.visible, 10.0), "lugar volta ao chegar perto")

func breakdown_event() -> void:
	var events: Node3D = roadside.events
	var economy = session.state.economy
	events._try_start()
	check(events.event.is_empty(), "a pé não nasce evento")
	var stretch: Dictionary = event_stretch("route66_south")
	var event_point: Vector2 = (stretch.a as Vector2).lerp(stretch.b,.5)
	await stand(Vector3(event_point.x-12.5, 0, event_point.y+50))
	if not check(events.force_start("breakdown", event_point, Vector2(0, -1)), "van quebrada nasce no trecho da Route 66"): return
	check(await until(func(): return not events.event.is_empty() and events.event.pending.is_empty(), 10.0), "van, motorista e triângulo montam em quadros separados")
	var van = events.event.vehicle
	await frames(60)
	check(is_instance_valid(van) and absf(van.global_position.x - (event_point.x+events.SHOULDER)) < .5 and absf(van.global_position.z - event_point.y) < .5 and absf(van.speed) < .5, "van parada no acostamento (%s)" % (van.global_position if is_instance_valid(van) else Vector3.INF))
	check(is_instance_valid(van) and van.engine_disabled and van.get_meta("race_owned", false), "van parada e protegida da limpeza de 145 m")
	var driver: Node3D = events.event.actors[0]
	await stand(driver.global_position + Vector3(1.2, 0, 0))
	var before: int = economy.balance
	if await act("event_help", "ajudar o entregador"):
		check(economy.balance == before + BALANCE.ROADSIDE_TRUCK_HELP and events.event.resolved and not van.engine_disabled, "ajuda paga R$ %d e a van pega" % BALANCE.ROADSIDE_TRUCK_HELP)
	await stand(DESERT_LAYOUT.BRIDGE_END+Vector3(0,0,-12))
	check(await until(func(): return events.event.is_empty(), 3.0), "evento resolvido solta ao se afastar")
	await frames(2)
	check(not is_instance_valid(van) or van.is_queued_for_deletion(), "van some junto")

func roadblock_event() -> void:
	var events: Node3D = roadside.events
	var economy = session.state.economy
	var stretch: Dictionary = event_stretch("salt_east")
	var event_point: Vector2 = (stretch.a as Vector2).lerp(stretch.b,.5)
	await stand(Vector3(event_point.x-60, 0, event_point.y-25))
	if not check(events.force_start("roadblock", event_point, Vector2(1, 0)), "bloqueio nasce na rodovia do sal"): return
	check(await until(func(): return not events.event.is_empty() and events.event.pending.is_empty(), 10.0), "picape e três bandidos montam")
	var outlaws: Array = events.event.actors
	check(outlaws.size() == 3 and not events.event.engaged, "três bandidos calmos de longe")
	var pickup = events.event.vehicle
	await frames(60)
	check(absf(pickup.global_position.z - (event_point.y+events.LANE)) < .5 and absf(pickup.global_position.x - event_point.x) < .5 and absf(pickup.speed) < .5, "picape parada atravessada na faixa (%s, %.1f m/s)" % [pickup.global_position, pickup.speed])
	await stand(pickup.global_position - Vector3(16, 0, 0))
	check(await until(func(): return events.event.engaged, 6.0), "bandidos atacam quando o jogador chega")
	check(not session.desert.save_block_reason().is_empty(), "salvar bloqueado no tiroteio")
	for actor in outlaws:
		if is_instance_valid(actor): actor.receive_damage(100000.0)
	await frames(20)
	check(session.desert.save_block_reason().is_empty(), "salvar volta com os bandidos no chão")
	# A picape está atravessada (comprimento ao longo de z); o lado de quem chega é o -x.
	await stand(pickup.global_position - Vector3(pickup.half_width + 1.2, 0, 0))
	var before: int = economy.balance
	if await act("event_loot", "vasculhar a picape"):
		var gained: int = economy.balance - before
		check(gained >= BALANCE.ROADSIDE_ROADBLOCK_LOOT.x and gained <= BALANCE.ROADSIDE_ROADBLOCK_LOOT.y, "picape tinha R$ %d" % gained)
	check(session.nearest().get("target", "") != "event_loot", "picape só paga uma vez")
	world.camera.initialized = false
	for i in 30: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/roadblock.png" % FOLDER))

## Sem forçar nada: jogador ao volante na Route 66, o piloto do benchmark aperta as mesmas ações de
## acelerar e virar do jogador, e o evento tem de nascer sozinho à frente quando o relógio deixa.
func natural_event() -> void:
	var events: Node3D = roadside.events
	events.release_all()
	var stretch: Dictionary = event_stretch("route66_north")
	# Dá espaço de aceleração ao sedã comum antes da janela de evento de 55m;
	# isto ainda fica na estrada plana depois que a rampa da ponte termina em z=-445.
	var start := Vector3(float(stretch.a.x)+4.5, 0, float(stretch.a.y)+120)
	start.y = HM.surface_height(Vector2(start.x, start.z)) + .12
	await stand(start + Vector3(9, 0, 0))
	await frames(30)
	var car: CharacterBody3D = session.controller.spawn_vehicle("union_sedan", start, 0.0)
	if not check(is_instance_valid(car), "carro na Route 66 para dirigir"): return
	await frames(10)
	var entered := false
	for side in [-1, 1]:
		await stand(car.to_global(Vector3(side * (car.half_width + .65), .04, .15)))
		if world.driving.interact():
			entered = await until(func(): return world.driving.occupied and not world.driving.is_body_transition_active(), 8.0)
			if entered: break
	if not check(entered, "jogador ao volante na Route 66"): return
	# Só o relógio de "pode nascer" vencido; o resto (velocidade, trecho, ponto à frente) é o do jogo.
	events._next_at = events._desert_time
	var autopilot = AUTOPILOT.new(world, car, [start, Vector3(start.x, start.y, float(stretch.b.y)-100)], 14.0)
	autopilot.begin()
	var started := false
	var fastest := 0.0
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline and not started:
		await physics_frame
		autopilot.drive(1.0 / Engine.physics_ticks_per_second)
		fastest = maxf(fastest, Vector2(car.velocity.x, car.velocity.z).length())
		started = not events.event.is_empty()
	var driven_to: Vector3 = car.global_position
	autopilot.finish()
	if not check(started, "evento nasce sozinho dirigindo (até %.1f m/s, carro em %s)" % [fastest, driven_to]): return
	var point: Vector3 = events.event.point
	# As estradas compactas agora usam antecipação de 100m. Preserva os requisitos de
	# frente do carro e de trecho autoral sem manter a expectativa antiga de 240m.
	check(absf(point.x - float(stretch.a.x)) < .5 and absf(point.z-(driven_to.z-100.0)) < 20.0 and point.z > minf(stretch.a.y,stretch.b.y) and point.z < maxf(stretch.a.y,stretch.b.y), "evento nasce 100m à frente, no trecho route66_north (%s, carro em %s)" % [point, driven_to])
	check(await until(func(): return events.event.is_empty() or events.event.pending.is_empty(), 10.0), "peças do evento natural montam")

func finish(code: int) -> void:
	print("DESERT_ROADSIDE checks=%d failures=%s output=%s" % [checks, failures, FOLDER])
	quit(code if failures.is_empty() or code != 0 else 1)
