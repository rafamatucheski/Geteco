extends SceneTree
## Casinhas, foras-da-lei e cavernas do DesertWilds na sessão real (Main + save isolado).
## Uso (com tela): "$GODOT" --path . --script res://tests/test_desert_wilds.gd -- --no-save --no-traffic
## Capturas em evidence/desert-wilds-20261018/ (fora do Git).
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const WILDS := preload("res://runtime/desert/wilds/DesertWilds.gd")
const FOLDER := "res://evidence/desert-wilds-20261018"
var world: Node3D
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	create_timer(420).timeout.connect(func(): failures.append("watchdog 420 s"); finish(3))
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
		check(region._decoration_clear(site.center, WILDS.SITE_RADIUS), "%s em chão livre" % site.id)
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
			"cave":
				var before: int = world.gameplay._loot.size()
				var inside: Vector3 = record.loot_point
				world.player.teleport(inside + Vector3(0, .1, 0))
				deadline = Time.get_ticks_msec() + 3000
				while Time.get_ticks_msec() < deadline and world.gameplay._loot.size() == before: await physics_frame
				check(WILDS._claimed.has(site.id), "%s entrega o achado" % site.id)
				var ray := PhysicsRayQueryParameters3D.create(inside + Vector3.UP * 1.0, inside + Vector3.UP * 6.0, 1)
				check(not world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "%s tem teto de verdade" % site.id)
		world.player.teleport(center + Vector3(-4, .1, 9))
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

func finish(code: int) -> void:
	print("DESERT_WILDS checks=%d failures=%s" % [checks, failures])
	quit(code if failures.is_empty() or code != 0 else 1)
