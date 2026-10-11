extends SceneTree
## A/B de frame time de policiais: corpo procedural do kit × catálogo do Meshy (`PoliceBodyCatalog.enabled`),
## alternados na MESMA sessão, em palco renderizado isolado (1280x720, VSync e limite de FPS desligados só neste
## processo). Cada policial é um `PoliceModel` com o mesmo escalão/aparência/arma nos dois lados, parado em
## formação, alternando repouso e mira (pose por IK ativa, como em uma resposta policial). 5 s de aquecimento +
## 30 s por rodada.
## Uso: "$GODOT" --path . --script res://tests/measure/measure_police_crowd.gd -- --count=24 --kinds=old,new,old,new --out=res://evidence/npc-meshy/perf-police
const MODEL := preload("res://gameplay/PoliceModel.gd")
const CATALOG := preload("res://gameplay/PoliceBodyCatalog.gd")
const TIERS := [0, 0, 0, 1, 2, 2, 3, 4]
const WEAPONS := {0: "pistol", 1: "pistol", 2: "smg", 3: "smg", 4: "m4a1"}
const WARMUP := 5.0
const WINDOW := 30.0
var count := 24
var kinds: Array = ["old", "new", "old", "new"]
var output_dir := "res://evidence/npc-meshy/perf-police"
var rounds: Array[Dictionary] = []
var frame_ms: Array[float] = []
var draw_calls: Array[float] = []
var recording := false
var stamp := 0
var officers: Array = []
var clock := 0.0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--count="): count = int(arg.substr(8))
		elif arg.begins_with("--kinds="): kinds = arg.substr(8).split(",")
		elif arg.begins_with("--out="): output_dir = arg.substr(6)
	create_timer(900).timeout.connect(func(): push_error("POLICE_AB timeout"); quit(3))
	_run.call_deferred()

func _process(delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if recording and stamp > 0:
		frame_ms.append(float(now - stamp) / 1000.0)
		draw_calls.append(float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))
	stamp = now
	clock += delta
	for k in officers.size():
		var police: Node3D = officers[k]
		if is_instance_valid(police) and police.has_method("update_pose"):
			police.update_pose(delta, sin(clock * 0.5 + float(k)) > 0.0, false, 0.0, 0.0)
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
	camera.position = Vector3(0, 7.0, 14.0)
	camera.look_at(Vector3(0, 0.9, 0), Vector3.UP)
	camera.current = true
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for kind in kinds:
		CATALOG.enabled = (kind == "new")
		var holder := Node3D.new()
		stage.add_child(holder)
		officers.clear()
		var columns := 8
		for k in count:
			var tier: int = TIERS[k % TIERS.size()]
			var police := MODEL.new()
			police.tier = tier
			police.appearance_index = k
			police.position = Vector3((k % columns - (columns - 1) * 0.5) * 1.6, 0, -3.0 + float(k / columns) * 1.8)
			holder.add_child(police)
			police.equip(WEAPONS[tier])
			officers.append(police)
		await _sample("police_%s_%d" % [kind, count], kind)
		officers.clear()
		holder.queue_free()
		await process_frame
		await process_frame
	var info := {"engine": Engine.get_version_info().string, "gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"resolution": [1280, 720], "officers": count, "warmup_s": WARMUP, "window_s": WINDOW, "vsync": "desligado só neste processo", "max_fps": 0}
	var out := FileAccess.open(ProjectSettings.globalize_path("%s/ab-police-%d.json" % [output_dir, count]), FileAccess.WRITE)
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
	print("POLICE_AB ", JSON.stringify(entry))
