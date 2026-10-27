extends SceneTree
## Encontro de lowriders no mundo de verdade (Main.tscn, sem save): de noite, perto da Vila Cobra,
## os cinco lowriders e a turma aparecem, o som toca, a hidráulica dança e um carro pula; os carros
## dos Cobras no trânsito saem da garagem nova. Fotos em evidence/muscle-lowrider-20261027/meet.
## Uso (com janela): tools/run_godot_locked.sh --path . --script res://tests/capture/capture_lowrider_meet.gd -- --no-save
const MEET := preload("res://gameplay/lowrider/LowriderMeet.gd")
const FLEET := preload("res://runtime/MuscleFleet.gd")
var world
var failures: Array[String] = []
var folder := ""
var camera: Camera3D

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func photo(label: String) -> void:
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label + ".png"))

func look(from: Vector3, at: Vector3) -> void:
	camera.global_position = from
	camera.look_at(at)
	camera.make_current()

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	if DisplayServer.get_name() == "headless": quit(2); return
	folder = ProjectSettings.globalize_path("res://evidence/muscle-lowrider-20261027/meet")
	DirAccess.make_dir_recursive_absolute(folder)
	create_timer(330).timeout.connect(func(): quit(3))
	seed(27102026)
	root.size = Vector2i(1280, 720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for i in 7000:
		await physics_frame
		if world.session != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	check(world.session != null and world.session.ready_for_play, "sessão pronta")
	if world.session == null or not world.session.ready_for_play:
		finish()
		return
	if world.session.modal: world.session.close_menu()
	world.session.weather.weather_timer = 3600
	world.session.weather.time_of_day = 20.5 / 24.0
	world.session.weather.weather_state = 0
	world.session.weather._update()
	world.gameplay.health = 5000
	world.player.teleport(Vector3(428.0, .1, 96.0))
	var meet: Node = root.find_child("LowriderMeet", true, false)
	check(meet != null, "encontro existe na sessão")
	if meet == null:
		finish()
		return
	for i in 60:
		await create_timer(.25).timeout
		if meet.cars.size() == MEET.CAR_SPOTS.size() and meet.guests.size() == MEET.GUEST_SPOTS.size(): break
	check(meet.active and meet.event_active, "encontro ativo à noite")
	check(meet.cars.size() == MEET.CAR_SPOTS.size(), "cinco lowriders estacionados (%d)" % meet.cars.size())
	check(meet.guests.size() == MEET.GUEST_SPOTS.size(), "turma na calçada (%d)" % meet.guests.size())
	camera = Camera3D.new()
	camera.fov = 52
	world.add_child(camera)
	var spawn_worst := 0.0
	var spawn_last := Time.get_ticks_usec()
	for i in 120:
		await process_frame
		var now := Time.get_ticks_usec()
		spawn_worst = maxf(spawn_worst, (now - spawn_last) / 1000.0)
		spawn_last = now
	print("MEET_IDLE_WORST_FRAME_MS %.1f" % spawn_worst)
	check(is_instance_valid(meet._music) and meet._music.playing, "som tocando perto do encontro")
	look(Vector3(404.0, 4.2, 110.0), Vector3(428.0, .8, 100.5))
	await photo("01-encontro")
	# Força um show em cada carro e fotografa no meio do movimento.
	var hop_car = meet.cars.get(0)
	var peak := 0.0
	for index in meet.cars:
		var car = meet.cars[index]
		if index == 0: car.hydraulics.hop(1.0)
		else: car.hydraulics.play(["side", "three_wheel", "front", "wave"][index % 4], 3)
	var worst := 0.0
	var last := Time.get_ticks_usec()
	for i in 30:
		await physics_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
		peak = maxf(peak, float(hop_car.hydraulics.hop_y))
	print("SHOW_WORST_FRAME_MS %.1f" % worst)
	look(Vector3(406.0, 2.4, 107.0), Vector3(413.0, 1.0, 101.5))
	await photo("02-pulo")
	for i in 40:
		await physics_frame
		peak = maxf(peak, float(hop_car.hydraulics.hop_y))
	check(peak > .6, "carro do pulo sobe (%.2f m)" % peak)
	look(Vector3(431.0, 2.0, 107.5), Vector3(425.3, .9, 101.5))
	await photo("03-tres-rodas")
	look(Vector3(421.0, 1.7, 95.5), Vector3(424.5, 1.2, 98.6))
	await photo("04-turma")
	# Carros dos Cobras no trânsito: espera a patrulha aparecer na vila e confere o modelo.
	world.player.teleport(Vector3(470.0, .1, 135.0))
	var models := {}
	for i in 80:
		await create_timer(.25).timeout
		for patrol in get_nodes_in_group("cobra_patrol"):
			if is_instance_valid(patrol.car): models[str(patrol.car.archetype)] = true
		if models.size() >= 1 and i > 20: break
	print("COBRA_MODELS ", models.keys())
	check(not models.is_empty() and models.keys().all(func(id): return id in FLEET.IDS), "Cobras rodam com a garagem nova " + str(models.keys()))
	for patrol in get_nodes_in_group("cobra_patrol"):
		if is_instance_valid(patrol.car):
			var car: Node3D = patrol.car
			look(car.global_position + car.global_basis * Vector3(4.5, 2.2, -5.5), car.global_position + Vector3.UP * .7)
			await photo("05-cobra-" + str(car.archetype))
			break
	finish()

func finish() -> void:
	print("LOWRIDER_MEET_CAPTURE ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)
