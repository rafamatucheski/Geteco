extends SceneTree
## Ilha do deserto no jogo de verdade (etapa 2 do mundo orgânico, 26/10/2026): fotos com a câmera normal
## nas bordas sul (praia e canal até Harbor), norte (cordilheira) e oeste da área jogável, com o mar do
## mundo e a faixa nova de praia. Inspeção visual; não mede FPS.
## Uso (com tela): "$GODOT" --path . --script res://tests/capture/capture_desert_coast.gd -- --no-save --no-traffic
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const L := preload("res://world/desert/DesertLayout.gd")
const SPOTS := {"leste": Vector3(408, 0, -700), "sudoeste": Vector3(-1300, 0, -410)}

func _initialize() -> void:
	create_timer(420).timeout.connect(func(): push_error("DESERT_COAST timeout"); quit(3))
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	root.size = Vector2i(1280, 720)
	var folder := FIXTURE.output_dir("desert-coast")
	var start: Vector3 = SPOTS.values()[0] + Vector3(-60, 0, 0)
	var data := FIXTURE.full_snapshot(start, true)
	data.region_id = "desert"
	data.world.pedestrian = {"region": "desert", "position": [start.x, start.y, start.z]}
	var path := FIXTURE.write_fixture(folder, "checkpoint.json", data)
	var world: Node3D = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("menu_save_path", path)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if world.get("session") != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.get("session") == null or not world.session.ready_for_play: push_error("sessão não carregou"); quit(1); return
	if world.session.modal: world.session.close_menu()
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.gameplay.health = 100000.0
	print("DESERT_COAST mar do mundo: ", is_instance_valid(world.production.get("world_sea")))
	for label in SPOTS:
		var at: Vector3 = SPOTS[label]
		world.player.teleport(at + Vector3(0, .2, 0))
		world.production.region.set_focus(at, true)
		deadline = Time.get_ticks_msec() + 20000
		while Time.get_ticks_msec() < deadline and not world.production.region.is_streaming_idle(): await process_frame
		world.camera.initialized = false
		for i in 60: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/%s.png" % [folder, label]))
	print("DESERT_COAST ", folder)
	quit(0)
