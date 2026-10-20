extends SceneTree
## Capturas da área de esqui da serra (base do teleférico, pista, topo, cadeiras com passageiros) na
## sessão real, com a câmera do jogo e de dia. Usada para revisar esquiadores e trajes (20/10/2026).
## Uso (com tela): "$GODOT" --path . --script res://tests/capture/capture_mountain_ski.gd -- --no-save --no-traffic --label=antes
## Saída em evidence/mountain-ski-20261020/<label>_*.png (fora do Git).
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const FOLDER := "res://evidence/mountain-ski-20261020"
const SHOTS := [
	[Vector3(713, 0, -612), "base_teleferico"],
	[Vector3(735, 0, -585), "pista_baixa"],
	[Vector3(740, 0, -557), "pista_meio"],
	[Vector3(720, 0, -530), "pista_alta"],
	[Vector3(700, 0, -506), "topo_teleferico"],
	[Vector3(706, 0, -560), "cadeiras"],
]
var world: Node3D

func _initialize() -> void:
	create_timer(360).timeout.connect(func(): print("MOUNTAIN_SKI watchdog"); quit(3))
	run.call_deferred()

func stand(point: Vector3) -> void:
	var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 80, point - Vector3.UP * 40, 1)
	world.player.teleport(point + Vector3(0, 2, 0))
	world.production.region.set_focus(point, true)
	for i in 60: await physics_frame
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(ray)
	world.player.teleport((hit.position if not hit.is_empty() else point) + Vector3(0, .1, 0))
	for i in 30: await physics_frame

func run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	var label := "antes"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
	var arrival: Vector3 = SHOTS[0][0] + Vector3(0, .1, 0)
	var data := FIXTURE.full_snapshot(arrival, true)
	data.region_id = "mountain"
	data.world.pedestrian = {"region": "mountain", "position": [arrival.x, arrival.y, arrival.z]}
	var path := FIXTURE.write_fixture(FIXTURE.output_dir("mountain-ski"), "checkpoint.json", data)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("menu_save_path", path)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if world.get("session") != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	var session = world.session
	if session.modal: session.close_menu()
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.gameplay.health = 100000.0
	session.weather.time_of_day = 11.0 / 24.0
	session.weather.time_scale = 0.0
	for entry in SHOTS:
		await stand(entry[0])
		world.camera.initialized = false
		for i in 50: await process_frame
		await RenderingServer.frame_post_draw
		var file := ProjectSettings.globalize_path("%s/%s_%s.png" % [FOLDER, label, entry[1]])
		root.get_texture().get_image().save_png(file)
		print("MOUNTAIN_SKI shot ", file)
	# Segue um esquiador na pista e um no teleférico (o grupo monta um por vez perto da área).
	var skiers: Node = world.find_child("MountainSkiers", true, false)
	if skiers != null:
		for i in 60: await physics_frame
		print("MOUNTAIN_SKI skiers=%d" % skiers.skiers.size())
		for state in ["ski", "lift"]:
			for skier in skiers.skiers:
				if skier.state != state: continue
				var at: Vector3 = skier.root.global_position
				world.player.teleport(Vector3(at.x + 3, at.y if state == "ski" else at.y - 4.0, at.z + 3))
				for i in 3: await physics_frame
				world.camera.initialized = false
				for i in 20: await process_frame
				await RenderingServer.frame_post_draw
				var file := ProjectSettings.globalize_path("%s/%s_segue_%s.png" % [FOLDER, label, state])
				root.get_texture().get_image().save_png(file)
				print("MOUNTAIN_SKI shot ", file)
				break
	quit(0)
