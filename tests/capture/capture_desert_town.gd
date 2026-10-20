extends SceneTree
## Capturas da cidade do deserto (rua principal, banco, oficina do Digo) e da vila Santa Lua na sessão
## real, com a câmera do jogo, de dia e de noite. Usada para comparar o antes e o depois do acabamento.
## Uso (com tela): "$GODOT" --path . --script res://tests/capture/capture_desert_town.gd -- --no-save --no-traffic --label=antes
## Saída em evidence/desert-town-20261020/<label>_*.png (fora do Git).
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const HM := preload("res://world/desert/DesertTerrainMesh.gd")
const FOLDER := "res://evidence/desert-town-20261020"
const SHOTS := [
	[Vector3(-180, 0, -893), "rua_centro"],
	[Vector3(-300, 0, -893), "rua_oeste"],
	[Vector3(-60, 0, -893), "rua_leste"],
	[Vector3(-210, 0, -905), "banco"],
	[Vector3(-140, 0, -940), "oficina"],
	[Vector3(-528, 0, -829), "vila_centro"],
	[Vector3(-528, 0, -800), "vila_norte"],
	[Vector3(-242, 0, -948), "aproximacao_casas"],
	[Vector3(-271, 0, -1018), "casas_frente"],
	[Vector3(-242, 0, -1043), "casas_quintal"],
	[Vector3(-245, 0, -872), "lanchonete"],
	[Vector3(-180, 0, -872), "mercado"],
	[Vector3(-156, 0, -951), "oficina_oeste"],
	[Vector3(-124, 0, -953), "oficina_leste"],
	[Vector3(-336, 0, -911), "motel_horizonte"],
	[Vector3(-166, 0, -858), "mercado_lado"],
]
var world: Node3D

func _initialize() -> void:
	create_timer(420).timeout.connect(func(): print("DESERT_TOWN watchdog"); quit(3))
	run.call_deferred()

func stand(point: Vector3) -> void:
	var at := Vector3(point.x, HM.surface_height(Vector2(point.x, point.z)) + .1, point.z)
	world.player.teleport(at)
	world.production.region.set_focus(at, true)
	for i in 90: await physics_frame

func run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	var label := "antes"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
	var arrival := Vector3(-180, 0, -893)
	var data := FIXTURE.full_snapshot(arrival, true)
	data.region_id = "desert"
	data.world.pedestrian = {"region": "desert", "position": [arrival.x, 0.1, arrival.z]}
	var path := FIXTURE.write_fixture(FIXTURE.output_dir("desert-town"), "checkpoint.json", data)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("menu_save_path", path)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if world.get("session") != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	var session = world.session
	if session.modal: session.close_menu()
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.gameplay.health = 100000.0
	var weather = session.weather
	for hour in [13.0, 21.5]:
		weather.time_of_day = hour / 24.0
		weather.time_scale = 0.0
		for entry in SHOTS:
			await stand(entry[0])
			world.camera.initialized = false
			for i in 50: await process_frame
			await RenderingServer.frame_post_draw
			var file := ProjectSettings.globalize_path("%s/%s_%s_%s.png" % [FOLDER, label, entry[1], "dia" if hour < 18.0 else "noite"])
			root.get_texture().get_image().save_png(file)
			print("DESERT_TOWN shot ", file)
	quit(0)
