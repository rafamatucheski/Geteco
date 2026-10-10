extends SceneTree
## A/B de frame time da multidão de pedestres: corpo procedural do kit × catálogo do Meshy, alternados na MESMA
## sessão, em palco renderizado isolado (1280x720, VSync e limite de FPS desligados só neste processo).
## Cada pedestre é um CivilianModel com a mesma identidade nos dois lados e anda de um lado ao outro a ~1,4 m/s
## (pose por IK ativa, como no jogo). 5 s de aquecimento + 30 s por rodada.
## Uso: "$GODOT" --path . --script res://tests/measure/measure_pedestrian_crowd.gd -- --count=80 --kinds=old,new,old,new --out=res://evidence/npc-meshy/perf-peds
const CATALOG := preload("res://assets/civilians/CivilianBodyCatalog.gd")
const CIVILIAN := preload("res://assets/CivilianModel.gd")
const WARMUP := 5.0
const WINDOW := 30.0
var count := 80
var kinds: Array = ["old", "new", "old", "new"]
var output_dir := "res://evidence/npc-meshy/perf-peds"
var rounds: Array[Dictionary] = []
var frame_ms: Array[float] = []
var draw_calls: Array[float] = []
var recording := false
var stamp := 0
var walkers: Array[Node3D] = []
var walk_time := 0.0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--count="): count = int(arg.substr(8))
		elif arg.begins_with("--kinds="): kinds = arg.substr(8).split(",")
		elif arg.begins_with("--out="): output_dir = arg.substr(6)
	create_timer(900).timeout.connect(func(): push_error("PED_AB timeout"); quit(3))
	_run.call_deferred()

func _process(delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if recording and stamp > 0:
		frame_ms.append(float(now - stamp) / 1000.0)
		draw_calls.append(float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))
	stamp = now
	walk_time += delta
	for k in walkers.size():
		var walker := walkers[k]
		walker.position.z = float(walker.get_meta("base_z")) + 2.5 * sin(walk_time * 0.56 + float(k))
	return false

func _run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	root.size = Vector2i(1280, 720)
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("8fa3ad")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("b9c4cc")
	env.environment.ambient_light_energy = 0.7
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	stage.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120, 120)
	ground.mesh = plane
	stage.add_child(ground)
	var camera := Camera3D.new()
	camera.fov = 60.0
	stage.add_child(camera)
	camera.position = Vector3(0, 9.0, 17.0)
	camera.look_at(Vector3(0, 0.8, 0), Vector3.UP)
	camera.current = true
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for kind in kinds:
		CATALOG.enabled = (kind == "new")
		var holder := Node3D.new()
		stage.add_child(holder)
		walkers.clear()
		var columns := 10
		for k in count:
			var walker := Node3D.new()
			walker.position = Vector3((k % columns - (columns - 1) * 0.5) * 1.5, 0, -4.0 + float(k / columns) * 1.6)
			walker.set_meta("base_z", walker.position.z)
			holder.add_child(walker)
			var model := CIVILIAN.new() as Node3D
			model.appearance_locked = true
			model.appearance_variant = k
			model.coat_color = [Color("426c70"), Color("a35d42"), Color("d3c3a1"), Color("42556f"), Color("8e5362"), Color("70835d")][k % 6]
			model.pants_color = [Color("293849"), Color("484644"), Color("615342")][k % 3]
			CATALOG.apply(model, k)
			walker.add_child(model)
			walkers.append(walker)
		await _sample("peds_%s_%d" % [kind, count], kind)
		walkers.clear()
		holder.queue_free()
		await process_frame
		await process_frame
	var info := {"engine": Engine.get_version_info().string, "gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"resolution": [1280, 720], "pedestrians": count, "warmup_s": WARMUP, "window_s": WINDOW, "vsync": "desligado só neste processo", "max_fps": 0}
	var out := FileAccess.open(ProjectSettings.globalize_path("%s/ab-peds-%d.json" % [output_dir, count]), FileAccess.WRITE)
	out.store_string(JSON.stringify({"environment": info, "rounds": rounds}, "\t"))
	quit(0)

func _sample(round_name: String, kind: String) -> void:
	await create_timer(WARMUP).timeout
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
	var entry := {"round": round_name, "kind": kind, "frames": n, "fps": n * 1000.0 / total, "p50": sorted[int(n * 0.5)], "p95": sorted[int(n * 0.95)],
		"p99": sorted[int(n * 0.99)], "max": sorted.back(), "over33": over33, "draw_calls_mean": draw_total / maxf(float(draw_calls.size()), 1.0)}
	rounds.append(entry)
	print("PED_AB ", JSON.stringify(entry))
