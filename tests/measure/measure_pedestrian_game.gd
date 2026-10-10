extends "res://tests/test_maciota_workshop_session.gd"
## Frame time do jogo real (Main.tscn) com pedestres de rua: um processo por condição, alternados por quem chama.
## A condição "sem Meshy" é a variável de ambiente GETECO_NO_MESHY_BODIES=1 (corpo procedural do kit); sem ela os
## pedestres usam o catálogo. Mesmo fixture de save, mesmos pontos, câmera do gameplay parada, 1280x720, VSync e
## limite de FPS desligados só neste processo. Por ponto: 10 s de aquecimento + 30 s de amostra.
## Uso: "$GODOT" --path . --script res://tests/measure/measure_pedestrian_game.gd -- --label=new --out=res://evidence/npc-meshy/perf-game
const POINTS := [["rua_166_111", Vector3(166, .08, 111.8)], ["inicio", Vector3.ZERO], ["vertice", Vector3(-226.7, .13, -39)]]
const WARMUP := 10.0
const WINDOW := 30.0
var label := "new"
var output_dir := "res://evidence/npc-meshy/perf-game"
var results: Array[Dictionary] = []
var frame_ms: Array[float] = []
var draw_calls: Array[float] = []
var recording := false
var stamp := 0

func _initialize() -> void:
	create_timer(600).timeout.connect(func(): push_error("PED_GAME timeout"); quit(3))
	_run.call_deferred()

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if recording and stamp > 0:
		frame_ms.append(float(now - stamp) / 1000.0)
		draw_calls.append(float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))
	stamp = now
	return false

func _counts() -> Dictionary:
	var bodies := 0
	var meshy := 0
	for node in root.find_children("*", "Node3D", true, false):
		var script := node.get_script() as Script
		var is_body := false
		while script != null:
			if script.resource_path.ends_with("/CivilianModel.gd"): is_body = true; break
			script = script.get_base_script()
		if is_body and node.is_visible_in_tree():
			bodies += 1
			if node.get("skeleton") != null: meshy += 1
	return {"visible_bodies": bodies, "visible_meshy": meshy}

func _run() -> void:
	if DisplayServer.get_name() == "headless": _finish(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.substr(8)
		elif arg.begins_with("--out="): output_dir = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	folder = FIXTURE.output_dir("pedestrian-game-" + label)
	path = FIXTURE.write_fixture(folder, "checkpoint.json", _seed())
	var launch := root.get_node_or_null("V2Launch")
	old_launch_path = str(launch.selected_path)
	launch.selected_path = path
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("menu_save_path", path)
	root.add_child(world)
	current_scene = world
	if not await _ready_world(): _finish(1); return
	root.size = Vector2i(1280, 720)
	world.gameplay.god_mode = true
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.set_process(false)
	world.session.weather.time_of_day = .45
	world.session.weather._update()
	var start: Vector3 = world.player.global_position
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for point in POINTS:
		world.player.teleport(start if point[1] == Vector3.ZERO else point[1])
		await create_timer(WARMUP).timeout
		var counts := _counts()
		frame_ms.clear()
		draw_calls.clear()
		stamp = Time.get_ticks_usec()
		recording = true
		await create_timer(WINDOW).timeout
		recording = false
		var sorted := frame_ms.duplicate()
		sorted.sort()
		var total := 0.0
		var over33 := 0
		for value in frame_ms:
			total += value
			if value > 33.3: over33 += 1
		var draw_total := 0.0
		for value in draw_calls: draw_total += value
		var n := sorted.size()
		var entry := {"label": label, "point": point[0], "frames": n, "fps": n * 1000.0 / total, "p50": sorted[int(n * 0.5)], "p95": sorted[int(n * 0.95)],
			"p99": sorted[int(n * 0.99)], "max": sorted.back(), "over33": over33, "draw_calls_mean": draw_total / maxf(float(draw_calls.size()), 1.0),
			"visible_bodies": counts.visible_bodies, "visible_meshy": counts.visible_meshy, "catalog_enabled": OS.get_environment("GETECO_NO_MESHY_BODIES").is_empty()}
		results.append(entry)
		print("PED_GAME ", JSON.stringify(entry))
	var out := FileAccess.open(ProjectSettings.globalize_path("%s/game-%s-%d.json" % [output_dir, label, Time.get_ticks_msec()]), FileAccess.WRITE)
	out.store_string(JSON.stringify({"environment": {"engine": Engine.get_version_info().string, "gpu": RenderingServer.get_video_adapter_name(),
		"renderer": RenderingServer.get_current_rendering_method(), "resolution": [1280, 720], "warmup_s": WARMUP, "window_s": WINDOW}, "results": results}, "\t"))
	_finish(0)
