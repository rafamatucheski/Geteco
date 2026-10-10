extends "res://tests/test_maciota_workshop_session.gd"
## A/B de frame time do mecânico: corpo antigo (cópia congelada em evidence/) × corpo único do Meshy.
## As duas condições alternam na MESMA sessão (antigo, novo, antigo, novo) para diluir ruído da máquina.
## Renderizado, 1280x720, VSync e limite de FPS desligados só neste processo; 5 s de aquecimento por rodada.
## Modos: --mode=garage (Main.tscn real, garagem do Maciota, 1 mecânico)
##        --mode=crowd  (palco isolado, 40 mecânicos andando de um lado ao outro)
## Uso: "$GODOT" --path . --script res://tests/measure/measure_meshy_body.gd -- --mode=crowd --out=res://evidence/npc-meshy/perf
const OLD := "res://evidence/npc-meshy/before/MechanicModelBefore.gd"
const NEW := "res://assets/maciota/MechanicModel.gd"
const WARMUP := 5.0
const WINDOW := 30.0
const CROWD := 40

var mode := "crowd"
## "new_nosync" = corpo novo com a cópia juntas→ossos desligada: isola o custo do esqueleto do custo da cópia.
var kinds: Array = ["old", "new", "old", "new"]
var output_dir := "res://evidence/npc-meshy/perf"
var rounds: Array[Dictionary] = []
var keep_raw := false
var frame_ms: Array[float] = []
var process_ms: Array[float] = []
var draw_calls: Array[float] = []
var recording := false
var stamp := 0
var walkers: Array[Node3D] = []
var walk_time := 0.0

func _initialize() -> void:
	create_timer(420).timeout.connect(func(): push_error("MESHY_AB timeout"); quit(3))
	_run.call_deferred()

func _process(delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if recording and stamp > 0:
		frame_ms.append(float(now - stamp) / 1000.0)
		process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		draw_calls.append(float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))
	stamp = now
	walk_time += delta
	for k in walkers.size():
		var walker := walkers[k]
		# Amplitude 2,5 m e 0,56 rad/s: velocidade máxima de 1,4 m/s, passo de caminhada.
		walker.position.z = float(walker.get_meta("base_z")) + 2.5 * sin(walk_time * 0.56 + float(k))
	return false

func _run() -> void:
	if DisplayServer.get_name() == "headless": _finish(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="): mode = arg.substr(7)
		elif arg.begins_with("--out="): output_dir = arg.substr(6)
		elif arg.begins_with("--kinds="): kinds = arg.substr(8).split(",")
		elif arg == "--raw": keep_raw = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	root.size = Vector2i(1280, 720)
	if mode == "garage": await _garage()
	else: await _crowd()
	_write()
	_finish(0)

# --- Cenários --------------------------------------------------------------------

func _crowd() -> void:
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
	plane.size = Vector2(80, 80)
	ground.mesh = plane
	stage.add_child(ground)
	var camera := Camera3D.new()
	camera.fov = 55.0
	stage.add_child(camera)
	camera.position = Vector3(0, 7.5, 15.0)
	camera.look_at(Vector3(0, 0.8, 0), Vector3.UP)
	camera.current = true
	_prepare_runtime()
	for kind in kinds:
		var holder := Node3D.new()
		stage.add_child(holder)
		walkers.clear()
		for k in CROWD:
			var walker := Node3D.new()
			walker.set_meta("base_z", -3.0 + float(k / 8) * 0.0)
			walker.position = Vector3(-7.0 + float(k % 8) * 2.0, 0, -3.0 + float(k / 8) * 1.6)
			walker.set_meta("base_z", walker.position.z)
			holder.add_child(walker)
			var model := _make(kind)
			walker.add_child(model)
			_after_enter(model, kind)
			walkers.append(walker)
		await _sample("crowd_%s_%d" % [kind, CROWD], kind)
		walkers.clear()
		holder.queue_free()
		await process_frame
		await process_frame

func _garage() -> void:
	folder = FIXTURE.output_dir("meshy-body-garage")
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
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	world.gameplay.god_mode = true
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.set_process(false)
	world.session.weather.time_of_day = .45
	world.session.weather._update()
	world.session.state.campaign.cancel("test_fixture")
	if not await world.session.enter_place("maciota", false): _finish(1); return
	await _frames(12)
	var point: Vector3 = world.session.room.interaction_points["mechanic"]
	world.player.teleport(point)
	await _frames(30)
	_prepare_runtime()
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for kind in kinds:
		_swap_mechanic(kind)
		await create_timer(1.0).timeout
		await _capture("garage_%s_%d" % [kind, rounds.size()])
		await _sample("garage_%s" % kind, kind)
	Engine.max_fps = 60
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)

func _prepare_runtime() -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

func _make(kind: String) -> Node3D:
	return (load(OLD if kind == "old" else NEW) as GDScript).new()

## Variantes de diagnóstico do corpo novo, uma variável por vez:
## new_nosync = sem cópia juntas→ossos; new_hidden = malha oculta (esqueleto e IK continuam);
## new_noshadow = malha sem projetar sombra.
func _after_enter(model: Node3D, kind: String) -> void:
	if model.get("body") == null: return
	if kind == "new_nosync" and model.body.get("_driver") != null: model.body._driver.set_process(false)
	elif kind == "new_hidden": model.body.mesh_node.visible = false
	elif kind == "new_noshadow": model.body.mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Troca o mecânico da garagem preservando posição, giro e metadados de invulnerabilidade.
func _swap_mechanic(kind: String) -> void:
	var room = world.session.room
	var current: Node3D = room.mechanic
	var replacement := _make(kind)
	replacement.name = "Mechanic"
	replacement.position = current.position
	replacement.rotation = current.rotation
	for key in current.get_meta_list(): replacement.set_meta(key, current.get_meta(key))
	var resident_body := current.get_node_or_null("ResidentBody")
	if resident_body != null:
		current.remove_child(resident_body)
		replacement.add_child(resident_body)
	var parent := current.get_parent()
	parent.remove_child(current)
	current.free()
	parent.add_child(replacement)
	_after_enter(replacement, kind)
	room.mechanic = replacement

# --- Amostragem ---------------------------------------------------------------------

func _capture(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/%s.png" % [output_dir, shot_name]))

func _sample(round_name: String, kind: String) -> void:
	await create_timer(WARMUP).timeout
	frame_ms.clear()
	process_ms.clear()
	draw_calls.clear()
	stamp = Time.get_ticks_usec()
	recording = true
	await create_timer(WINDOW).timeout
	recording = false
	var sorted := frame_ms.duplicate()
	sorted.sort()
	var total := 0.0
	var over33 := 0
	var over66 := 0
	for value in frame_ms:
		total += value
		if value > 33.3: over33 += 1
		if value > 66.7: over66 += 1
	var process_total := 0.0
	for value in process_ms: process_total += value
	var draw_total := 0.0
	for value in draw_calls: draw_total += value
	var count := sorted.size()
	var entry := {"round": round_name, "kind": kind, "frames": count, "seconds": total / 1000.0, "fps": count * 1000.0 / total,
		"p50": sorted[int(count * 0.5)], "p95": sorted[int(count * 0.95)], "p99": sorted[int(count * 0.99)], "max": sorted.back(),
		"over33": over33, "over66": over66, "process_ms_mean": process_total / maxf(float(process_ms.size()), 1.0),
		"draw_calls_mean": draw_total / maxf(float(draw_calls.size()), 1.0)}
	if keep_raw: entry["raw_ms"] = frame_ms.duplicate()
	rounds.append(entry)
	print("MESHY_AB ", JSON.stringify({"round": round_name, "kind": kind, "fps": entry.fps, "p50": entry.p50, "p95": entry.p95, "p99": entry.p99, "max": entry.max, "over33": over33, "draw_calls_mean": entry.draw_calls_mean}))

func _write() -> void:
	var info := {"engine": Engine.get_version_info().string, "gpu": RenderingServer.get_video_adapter_name(),
		"renderer": RenderingServer.get_current_rendering_method(), "resolution": [1280, 720], "mode": mode,
		"crowd": CROWD if mode == "crowd" else 1, "warmup_s": WARMUP, "window_s": WINDOW, "vsync": "desligado só neste processo", "max_fps": 0}
	var out := FileAccess.open(ProjectSettings.globalize_path("%s/ab-%s.json" % [output_dir, mode]), FileAccess.WRITE)
	out.store_string(JSON.stringify({"environment": info, "rounds": rounds}, "\t"))
	print("MESHY_AB_OUTPUT ", output_dir)
