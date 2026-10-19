extends SceneTree
## Beira de estrada do deserto na sessão real (Main + save isolado): cada lugar monta perto do
## jogador e estaciona longe; conserto, entrega do orelhão, torre, ferro-velho e lanche passam
## pelo interact() da sessão (FullSession → DesertRuntime → fronteira → beira de estrada); os
## dois eventos de estrada são forçados num ponto conhecido.
## Uso (com tela): "$GODOT" --path . --script res://tests/test_desert_roadside_session.gd -- --no-save --no-traffic
## Capturas em evidence/desert-roadside-20261019/ (fora do Git).
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const LAYOUT := preload("res://runtime/desert/roadside/RoadsideLayout.gd")
const STATE := preload("res://runtime/desert/roadside/RoadsideState.gd")
const ROADSIDE := preload("res://runtime/desert/roadside/DesertRoadside.gd")
const BALANCE := preload("res://data/catalogs/EconomyBalance.gd")
const GARAGE := preload("res://runtime/GarageRewards.gd")
const HM := preload("res://world/desert/DesertTerrainMesh.gd")
const AUTOPILOT := preload("res://runtime/BenchmarkAutopilot.gd")
const FOLDER := "res://evidence/desert-roadside-20261019"
## Terreno ocupado por cada lugar em coordenadas locais (x, z), de RoadsideBuild.
const FOOTPRINTS := {"station": Rect2(-12, -8, 24, 20), "tower": Rect2(-8, -7, 16, 14),
	"scrapyard": Rect2(-15, -12, 30, 20), "food_truck": Rect2(-4, -2, 9, 8)}
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

func act(target: String, label: String) -> bool:
	var action: Dictionary = session.nearest()
	if not check(str(action.get("id", "")) == "desert_roadside" and str(action.get("target", "")) == target, "%s: ação oferecida (%s)" % [label, action.get("target", action.get("id", "nenhuma"))]): return false
	return check(await session.interact(), "%s: interact() executa" % label)

func run() -> void:
	if not check("--no-save" in OS.get_cmdline_user_args(), "--no-save obrigatório"): finish(2); return
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	var start: Dictionary = LAYOUT.site("sol_poente")
	var arrival := Vector3(start.center.x - 60, 0, start.center.y + 30)
	arrival.y = HM.surface_height(Vector2(arrival.x, arrival.z)) + .1
	var output := FIXTURE.output_dir("desert-roadside")
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

func parking() -> void:
	# Longe de todos os lugares: estacionam (escondidos, sem física) em vez de soltar.
	await stand(Vector3(-200, 0, -1700))
	check(await until(func(): return roadside.sites.values().all(func(record): return record.parked and not record.root.visible), 3.0), "lugares estacionam longe do jogador")
	check(roadside.sites.size() == LAYOUT.SITES.size(), "nenhum lugar foi solto")
	await stand(local_point("food_truck", Vector3(0, 0, 40)))
	check(await until(func(): return not roadside.sites.food_truck.parked and roadside.sites.food_truck.root.visible, 10.0), "lugar volta ao chegar perto")

func breakdown_event() -> void:
	var events: Node3D = roadside.events
	var economy = session.state.economy
	events._try_start()
	check(events.event.is_empty(), "a pé não nasce evento")
	await stand(Vector3(330, 0, -950))
	if not check(events.force_start("breakdown", Vector2(342.5, -1000), Vector2(0, -1)), "van quebrada nasce no trecho da Route 66"): return
	check(await until(func(): return not events.event.is_empty() and events.event.pending.is_empty(), 10.0), "van, motorista e triângulo montam em quadros separados")
	var van = events.event.vehicle
	await frames(60)
	check(is_instance_valid(van) and absf(van.global_position.x - 350.0) < .5 and absf(van.global_position.z - -1000.0) < .5 and absf(van.speed) < .5, "van parada no acostamento (%s)" % (van.global_position if is_instance_valid(van) else Vector3.INF))
	check(is_instance_valid(van) and van.engine_disabled and van.get_meta("race_owned", false), "van parada e protegida da limpeza de 145 m")
	var driver: Node3D = events.event.actors[0]
	await stand(driver.global_position + Vector3(1.2, 0, 0))
	var before: int = economy.balance
	if await act("event_help", "ajudar o entregador"):
		check(economy.balance == before + BALANCE.ROADSIDE_TRUCK_HELP and events.event.resolved and not van.engine_disabled, "ajuda paga R$ %d e a van pega" % BALANCE.ROADSIDE_TRUCK_HELP)
	await stand(Vector3(342.5, 0, -1200))
	check(await until(func(): return events.event.is_empty(), 3.0), "evento resolvido solta ao se afastar")
	await frames(2)
	check(not is_instance_valid(van) or van.is_queued_for_deletion(), "van some junto")

func roadblock_event() -> void:
	var events: Node3D = roadside.events
	var economy = session.state.economy
	await stand(Vector3(40, 0, -1565))
	if not check(events.force_start("roadblock", Vector2(100, -1540), Vector2(1, 0)), "bloqueio nasce na rodovia do sal"): return
	check(await until(func(): return not events.event.is_empty() and events.event.pending.is_empty(), 10.0), "picape e três bandidos montam")
	var outlaws: Array = events.event.actors
	check(outlaws.size() == 3 and not events.event.engaged, "três bandidos calmos de longe")
	var pickup = events.event.vehicle
	await frames(60)
	check(absf(pickup.global_position.z - (-1540.0 + events.LANE)) < .5 and absf(pickup.global_position.x - 100.0) < .5 and absf(pickup.speed) < .5, "picape parada atravessada na faixa (%s, %.1f m/s)" % [pickup.global_position, pickup.speed])
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
	var start := Vector3(347, 0, -700)
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
	var autopilot = AUTOPILOT.new(world, car, [start, Vector3(347, start.y, -1150)], 14.0)
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
	check(absf(point.x - 342.5) < .5 and point.z < driven_to.z - 150.0 and point.z > -1080.0, "evento nasce à frente, no trecho route66_north (%s, carro em %s)" % [point, driven_to])
	check(await until(func(): return events.event.is_empty() or events.event.pending.is_empty(), 10.0), "peças do evento natural montam")

func finish(code: int) -> void:
	print("DESERT_ROADSIDE checks=%d failures=%s" % [checks, failures])
	quit(code if failures.is_empty() or code != 0 else 1)
