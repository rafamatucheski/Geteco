extends SceneTree
## Cartas de Vicente (20/10/2026) na sessão real: as seis de Harbor e da serra são achadas a pé (as
## quatro do deserto ficam em test_desert_wilds, junto da caverna do Coyote). Confere o catálogo, o
## texto de cada carta, a leitura no achado e que as dez liberam a mala do Maciota sem a Prova de rua.
## Uso (com tela): "$GODOT" --path . --script res://tests/test_vicente_letters.gd -- --no-save --no-traffic
## Capturas em evidence/vicente-letters-20261020/ (fora do Git).
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const LETTERS := preload("res://data/catalogs/VicenteLetters.gd")
const CATALOG := preload("res://data/catalogs/CollectibleCatalog.gd")
const DEFINITIONS := preload("res://activities/ActivityDefinitions.gd")
const FOLDER := "res://evidence/vicente-letters-20261020"
var world: Node3D
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	create_timer(600).timeout.connect(func(): failures.append("watchdog 600 s"); finish(3))
	run.call_deferred()

func check(value: bool, label: String) -> bool:
	checks += 1
	print("VICENTE_LETTERS ", "PASS " if value else "FAIL ", label)
	if not value: failures.append(label)
	return value

func run() -> void:
	if not check("--no-save" in OS.get_cmdline_user_args(), "--no-save obrigatório"): finish(2); return
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	var entries := DEFINITIONS.vicente_letters()
	check(entries.size() == 10 and LETTERS.IDS.size() == 10, "dez cartas com ponto")
	for id in LETTERS.IDS:
		check(CATALOG.ENTRIES.has(id) and LETTERS.TEXTS.has(id) and LETTERS.PLACES.has(id), "%s no catálogo, com texto e lugar" % id)
	for region in ["harbor", "mountain"]:
		var points := entries.filter(func(entry): return str(entry.region) == region)
		if not await session_at(region, points[0].point): continue
		for entry in points: await pick(entry)
		if region == "harbor":
			# As quatro do deserto e as da serra: o resto pela carteira, para conferir a mala aqui.
			var economy = world.session.state.economy
			var car = world.session.personal_car
			var race_done: bool = "cobra_race" in world.session.state.campaign._data.completed
			if car != null and not race_done: check(not car.travel_bag_available(), "mala presa antes das dez cartas")
			for id in LETTERS.IDS:
				if not economy.snapshot().collectibles.has(id): economy.collect(id)
			if car != null: check(car.travel_bag_available() or "monaliza_travel_bag" in economy._data.grid_inventory.claimed or not economy.grid_enabled(), "dez cartas liberam a mala do Maciota")
		world.queue_free()
		for i in 10: await process_frame
	finish(0 if failures.is_empty() else 1)

func session_at(region: String, point: Vector3) -> bool:
	var arrival := point + Vector3(0, .1, 12)
	var data := FIXTURE.full_snapshot(arrival, false)
	data.region_id = region
	data.world.pedestrian = {"region": region, "position": [arrival.x, arrival.y, arrival.z]}
	var path := FIXTURE.write_fixture(FIXTURE.output_dir("vicente-letters-" + region), "checkpoint.json", data)
	if not check(not path.is_empty(), "%s: save isolado válido" % region): return false
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("menu_save_path", path)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if world.get("session") != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if not check(world.get("session") != null and world.session.ready_for_play and world.session.state.region_id == region, "%s: sessão real carregou" % region): return false
	if world.session.modal: world.session.close_menu()
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.gameplay.health = 100000.0
	return true

## Chega perto (o pickup só se prende ao chão e liga a 55 m), depois pisa no ponto.
func pick(entry: Dictionary) -> void:
	var economy = world.session.state.economy
	var point: Vector3 = entry.point
	world.player.teleport(point + Vector3(0, 2, 20))
	world.production.region.set_focus(point, true)
	for i in 60: await physics_frame
	var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 30, point - Vector3.UP * 10, 1)
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(ray)
	var ground: Vector3 = hit.position if not hit.is_empty() else point
	world.player.teleport(ground + Vector3(0, .1, 0))
	var deadline := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < deadline and not economy.snapshot().collectibles.has(entry.id): await physics_frame
	check(economy.snapshot().collectibles.has(entry.id), "%s achada a pé (chão a %.1f m)" % [entry.id, ground.y])
	if not economy.snapshot().collectibles.has(entry.id):
		var acts = world.session.activities
		print("VICENTE_DEBUG region=%s place=%s player=%s act_region=%s" % [world.session.state.region_id, world.session.state.place_id, world.player.global_position, acts.get("_region")])
		for id in acts._pickups:
			var area: Area3D = acts._pickups[id]
			if is_instance_valid(area): print("VICENTE_DEBUG pickup %s at %s mon=%s vis=%s grounded=%s" % [id, area.global_position, area.monitoring, area.visible, area.has_meta("grounded")])
	check(world.session.get("dialogue_open") == true, "%s: a carta é lida ao achar" % entry.id)
	world.camera.initialized = false
	for i in 30: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/%s.png" % [FOLDER, entry.id]))
	for i in 12:
		if not world.session.dialogue_open: break
		world.session._advance_dialogue()
	for i in 2: await process_frame

func finish(code: int) -> void:
	print("VICENTE_LETTERS checks=%d failures=%s" % [checks, failures])
	quit(code if failures.is_empty() or code != 0 else 1)
