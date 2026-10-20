extends SceneTree
## Casinhas, foras-da-lei e cavernas do DesertWilds na sessão real (Main + save isolado).
## Uso (com tela): "$GODOT" --path . --script res://tests/test_desert_wilds.gd -- --no-save --no-traffic
## Capturas em evidence/desert-wilds-20261018/ (fora do Git).
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const WILDS := preload("res://runtime/desert/wilds/DesertWilds.gd")
const CAVE := preload("res://runtime/desert/wilds/CaveBuild.gd")
const LETTERS := preload("res://data/catalogs/VicenteLetters.gd")
const DEFINITIONS := preload("res://activities/ActivityDefinitions.gd")
const CONTRACT := preload("res://runtime/desert/DesertSaveContract.gd")
const FOLDER := "res://evidence/desert-wilds-20261018"
var world: Node3D
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	create_timer(720).timeout.connect(func(): failures.append("watchdog 720 s"); finish(3))
	run.call_deferred()

func check(value: bool, label: String) -> bool:
	checks += 1
	print("DESERT_WILDS ", "PASS " if value else "FAIL ", label)
	if not value: failures.append(label)
	return value

func run() -> void:
	if not check("--no-save" in OS.get_cmdline_user_args(), "--no-save obrigatório"): finish(2); return
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	var first: Dictionary = WILDS.SITES[0]
	var arrival := WILDS.ground(first.center) + Vector3(0, .1, 60)
	var output := FIXTURE.output_dir("desert-wilds")
	var data := FIXTURE.full_snapshot(arrival, true)
	data.region_id = "desert"
	data.world.pedestrian = {"region": "desert", "position": [arrival.x, arrival.y, arrival.z]}
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
	if world.session.modal: world.session.close_menu()
	var wilds: Node3D = world.session.desert.frontier.wilds
	if not check(is_instance_valid(wilds), "DesertFrontierRuntime instala DesertWilds"): finish(1); return
	var region: Node3D = world.session.controller.regions.get("desert")
	# Nenhum lugar em cima de estrada, prédio ou reserva de outro sistema.
	WILDS._enabled = 0
	for site in WILDS.SITES:
		check(region._decoration_clear(site.center, WILDS.CAVE_RADIUS if str(site.kind) == "cave" else WILDS.SITE_RADIUS), "%s em chão livre" % site.id)
	WILDS._enabled = 1
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.gameplay.health = 100000.0
	for site in WILDS.SITES:
		var center: Vector3 = WILDS.ground(site.center)
		var stand := center + Vector3(0, .1, 40)
		world.player.teleport(stand)
		world.production.region.set_focus(stand, true)
		deadline = Time.get_ticks_msec() + 25000
		while Time.get_ticks_msec() < deadline and not wilds.sites.has(site.id):
			await physics_frame
		if not check(wilds.sites.has(site.id), "%s monta perto do jogador" % site.id): continue
		var record: Dictionary = wilds.sites[site.id]
		for i in 30: await physics_frame
		match str(site.kind):
			"homestead":
				check(record.actors.size() == 2, "%s tem dois moradores" % site.id)
				for actor in record.actors:
					check(is_instance_valid(actor) and absf(actor.global_position.y - center.y) < .6, "%s morador no chão" % site.id)
			"outlaws":
				check(record.actors.size() == 3 and not record.engaged, "%s: três foras-da-lei calmos de longe" % site.id)
				world.player.teleport(center + Vector3(0, .1, 12))
				deadline = Time.get_ticks_msec() + 6000
				while Time.get_ticks_msec() < deadline and not record.engaged: await physics_frame
				check(record.engaged, "%s atacam quando o jogador chega" % site.id)
				check(not wilds.save_block_reason().is_empty(), "%s: salvar bloqueado em combate" % site.id)
			"cave" when bool(site.get("secret", false)):
				await brother(wilds, site, record)
			"cave":
				var economy = world.session.state.economy
				var balance_before: int = economy.balance
				var inside: Vector3 = record.loot_point
				world.player.teleport(inside + Vector3(0, .1, 0))
				deadline = Time.get_ticks_msec() + 3000
				while Time.get_ticks_msec() < deadline and not WILDS.cave_claimed(economy, site): await physics_frame
				check(WILDS.cave_claimed(economy, site) and record.claimed, "%s entrega o achado com recibo" % site.id)
				if str(site.loot) == "cash": check(economy.balance == balance_before + int(site.amount), "%s paga R$ %d inteiros" % [site.id, int(site.amount)])
				var again: Dictionary = WILDS.claim_cave(economy, site)
				check(again.ok and not again.get("changed", true) and (str(site.loot) != "cash" or economy.balance == balance_before + int(site.amount)), "%s não paga de novo" % site.id)
				var ray := PhysicsRayQueryParameters3D.create(inside + Vector3.UP * 1.0, inside + Vector3.UP * 6.0, 1)
				check(not world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "%s tem teto de verdade" % site.id)
				for i in 3: await process_frame
				check(is_instance_valid(record.get("roofs")) and not record.roofs.visible, "%s: morro some com o jogador dentro" % site.id)
				world.player.teleport(record.root.global_transform * Vector3(0, .1, -1.0))
				world.camera.initialized = false
				for i in 40: await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/%s_dentro.png" % [FOLDER, site.id]))
				world.player.teleport(record.root.global_transform * Vector3(0, .1, 14.0))
				for i in 3: await process_frame
				check(record.roofs.visible, "%s: morro volta com o jogador fora" % site.id)
				# Só na última com achado: a munição das caixas encheria o bolso antes da submetralhadora.
				if site.id == "cave_sun": await ammo_crate(wilds, site, record)
		record = wilds.sites.get(site.id, record)
		# A caverna de 20/10 ocupa ~11 m em volta do centro: a foto é da frente da boca.
		world.player.teleport(record.root.global_transform * Vector3(-5, .1, 17) if str(site.kind) == "cave" else center + Vector3(-4, .1, 9))
		world.camera.initialized = false
		for i in 40: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/%s.png" % [FOLDER, site.id]))
	# Longe de tudo, nada fica montado.
	var far := WILDS.ground(Vector2(-700, -400)) + Vector3(0, .1, 0)
	world.player.teleport(far)
	for i in 30: await physics_frame
	var near_any := false
	for site in WILDS.SITES:
		if (site.center as Vector2).distance_to(Vector2(far.x, far.z)) < WILDS.RELEASE_DISTANCE: near_any = true
	if not near_any: check(wilds.sites.is_empty(), "lugares soltam ao se afastar")
	finish(0 if failures.is_empty() else 1)

## Caixa de munição: oferecida perto da pilha de caixotes, repõe as armas de fogo do jogador e
## fica vazia até o próximo dia de jogo.
func ammo_crate(wilds: Node3D, site: Dictionary, record: Dictionary) -> void:
	var economy = world.session.state.economy
	if not economy.snapshot().weapons.has("pistol"): world.session.state.grant_weapon("pistol")
	world.player.teleport(record.root.global_transform * (CAVE.ammo_point(str(site.id)) + Vector3(CAVE.side(str(site.id)) * 1.3, -.2, 0)))
	for i in 4: await physics_frame
	var action: Dictionary = world.session.nearest()
	if not check(str(action.get("target", "")) == "cave_ammo:" + str(site.id), "%s: caixa de munição oferecida (%s)" % [site.id, action.get("target", action.get("id", "nenhuma"))]): return
	var before := int(economy.get_ammo("pistol").get("reserve", 0)) + int(economy.get_ammo("pistol").get("magazine", 0))
	check(await world.session.interact(), "%s: pegar munição executa" % site.id)
	var after := int(economy.get_ammo("pistol").get("reserve", 0)) + int(economy.get_ammo("pistol").get("magazine", 0))
	check(after > before or before >= 99, "%s: caixa repõe a pistola (%d -> %d)" % [site.id, before, after])
	wilds.take_ammo(str(site.id))
	var again := int(economy.get_ammo("pistol").get("reserve", 0)) + int(economy.get_ammo("pistol").get("magazine", 0))
	check(again == after, "%s: caixa vazia no mesmo dia" % site.id)
	check(CONTRACT.valid(world.session.state.world_state, economy._data), "%s: save do deserto válido com a caixa" % site.id)

## Cartas do deserto achadas a pé, depois a caverna do Vicente: lona sem as dez; com elas, o Coyote,
## que vira carro do jogador ao entrar nele.
func brother(wilds: Node3D, site: Dictionary, record: Dictionary) -> void:
	var economy = world.session.state.economy
	check(is_instance_valid(record.get("tarp")) and not is_instance_valid(record.get("car")), "cave_brother: lona e nenhum carro sem as cartas")
	for entry in DEFINITIONS.vicente_letters():
		if str(entry.region) != "desert": continue
		var point: Vector3 = entry.point
		world.player.teleport(point + Vector3(0, .1, 0))
		world.production.region.set_focus(point, true)
		var deadline := Time.get_ticks_msec() + 8000
		while Time.get_ticks_msec() < deadline and not economy.snapshot().collectibles.has(entry.id): await physics_frame
		check(economy.snapshot().collectibles.has(entry.id), "%s achada a pé" % entry.id)
		await close_dialogue()
	for id in LETTERS.IDS:
		if not economy.snapshot().collectibles.has(id): economy.collect(id)
	check(LETTERS.complete(economy.snapshot().collectibles), "dez cartas achadas")
	# A volta pelas cartas soltou a caverna: espera montar de novo.
	var center := WILDS.ground(site.center)
	world.player.teleport(center + Vector3(0, .1, 40))
	world.production.region.set_focus(center, true)
	var deadline := Time.get_ticks_msec() + 25000
	while Time.get_ticks_msec() < deadline and not wilds.sites.has(site.id): await physics_frame
	if not check(wilds.sites.has(site.id), "cave_brother monta de novo"): return
	record = wilds.sites[site.id]
	var spot: Vector3 = record.root.global_transform * CAVE.CAR_POINT
	world.player.teleport(record.root.global_transform * Vector3(0, .1, 6.5))
	deadline = Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline and not is_instance_valid(record.get("car")): await physics_frame
	var car: Variant = record.get("car")
	if not check(is_instance_valid(car) and not is_instance_valid(record.get("tarp")), "com as dez cartas a lona sai e o Coyote aparece"): return
	for i in 30: await physics_frame
	world.player.teleport(record.root.global_transform * Vector3(0, .1, -1.0))
	world.camera.initialized = false
	for i in 40: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/cave_brother_dentro.png" % FOLDER))
	var entered := false
	for side in [-1, 1]:
		world.player.teleport(car.to_global(Vector3(side * (car.half_width + .65), .04, .15)))
		for i in 4: await physics_frame
		if world.driving.interact():
			deadline = Time.get_ticks_msec() + 8000
			while Time.get_ticks_msec() < deadline and not (world.driving.occupied and not world.driving.is_body_transition_active()): await physics_frame
			entered = world.driving.occupied
			if entered: break
	if not check(entered, "jogador entra no Coyote do Vicente"): return
	deadline = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline and not record.get("claimed", false): await physics_frame
	var state: Dictionary = world.session.state.world_state
	check(record.get("claimed", false) and WILDS.cave_claimed(economy, site), "Coyote vira achado com recibo")
	check(state.get("desert_fleet", {}).has(LETTERS.CAR_ID) and car.vehicle_id == LETTERS.CAR_ID, "Coyote entra na frota do deserto")
	check(state.get("desert_garage", {}).get("vehicles", {}).get(LETTERS.CAR_ID, {}).get("vicente_gift", false), "peças do Vicente na garagem")
	check(CONTRACT.valid(state, economy._data), "save do deserto válido com o Coyote")
	check(world.gameplay.stars == 0, "pegar o Coyote não chama a polícia")
	await close_dialogue()
	world.driving.leave()
	deadline = Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline and (world.driving.occupied or world.driving.is_body_transition_active()): await physics_frame

func close_dialogue() -> void:
	for i in 12:
		if not world.session.dialogue_open: break
		world.session._advance_dialogue()
	for i in 2: await process_frame

func finish(code: int) -> void:
	print("DESERT_WILDS checks=%d failures=%s" % [checks, failures])
	quit(code if failures.is_empty() or code != 0 else 1)
