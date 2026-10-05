extends SceneTree
## Isola o custo do PRIMEIRO plano de rota do despacho (span `dispatch.service.plan`) no
## jogo renderizado, com o C# ativo. Origem: f2124 de sdl-bt-off-02 (472 ms de quadro,
## 462,951 ms no plano, ~13 ms de CPU da thread principal — quase tudo espera).
## Uma medição por processo (fria). Modos:
##   --mode=whole  primeiro router.plan como o jogo faz (inclui montar o espelho C#)
##   --mode=split  separa: load do .cs | _native_graph() (new+laço+Build) | 1º plan | seguintes
## --wait-frames=N espera N quadros depois do ready_for_play (padrão 600, ~10 s como a captura).
## Grava JSON em --out=<arquivo> (dentro do projeto). Exige --no-save e janela real.
## --fixture=mountain restaura um save isolado longe do terminal antes do loading.
## --sample-seconds=30 retém intervalos reais antes/depois do primeiro plano.
const ROUTER_SCRIPT := "res://gameplay/dispatch/RoadGraphSearch.cs"
const RULES := preload("res://gameplay/dispatch/DispatchRules.gd")
var world: Node3D
var probe: RefCounted
var result := {}

func _initialize() -> void: run.call_deferred()

func _arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + name + "="): return a.trim_prefix("--" + name + "=")
	return fallback

func _sample() -> Array:
	return Array(probe.Sample()) if probe != null else []

## Mede `callable` em wall e em ciclos da thread principal (ciclos não são tempo; a razão
## ciclos/µs do mesmo processo em trabalho normal serve de régua para estimar CPU).
func _timed(label: String, callable: Callable) -> Variant:
	var a := _sample()
	var began := Time.get_ticks_usec()
	var value: Variant = callable.call()
	var wall := Time.get_ticks_usec() - began
	var b := _sample()
	var entry := {"label": label, "ms": wall / 1000.0, "began_usec": began,
		"finished_usec": began + wall, "finished_utc": Time.get_datetime_string_from_system(true)}
	if a.size() == 7 and b.size() == 7:
		entry.cycles = b[4] - a[4]
		entry.cpu_filetime_ms = (b[2] + b[3] - a[2] - a[3]) / 1000.0
		entry.processor = [a[6], b[6]]
	result.steps.append(entry)
	print("PROBE_STEP ", JSON.stringify(entry))
	return value

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		push_error("probe_first_dispatch_plan: exige janela real e --no-save")
		quit(2); return
	var mode := _arg("mode", "whole")
	var wait_frames := _arg("wait-frames", "600").to_int()
	var out := _arg("out", "")
	var fixture := _arg("fixture", "")
	var sample_seconds := _arg("sample-seconds", "0").to_float()
	result = {"mode": mode, "wait_frames": wait_frames, "steps": [], "env_no_csharp": not OS.get_environment("HARBOR_NO_CSHARP").is_empty(),
		"args": OS.get_cmdline_user_args(), "jit_prewarm": OS.get_environment("HARBOR_ROUTER_JIT_PREWARM") != "0"}
	seed(21092026)
	var probe_script := load("res://tests/measure/ThreadCpuProbe.cs") as Script
	if probe_script != null and probe_script.can_instantiate(): probe = probe_script.new()
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_move_to_foreground()
	if mode == "cold_class":
		_cold_class()
		result.cold_class_second = true
		_cold_class()
		_save(out)
		quit(0); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	if not fixture.is_empty():
		if not _prepare_fixture(fixture, out):
			world.free()
			quit(4); return
	root.add_child(world)
	var loading_deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < loading_deadline:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		push_error("probe_first_dispatch_plan: loading não concluiu em 90 s")
		quit(5); return
	var terminal: Node = world.production.urban_transit.terminal_operations
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	var d: Node = world.dispatch
	var router: RefCounted = d.router
	result.ready = {"router_native": router._native != null, "native_tried": router._native_tried,
		"script_cached": ResourceLoader.has_cached(ROUTER_SCRIPT), "prepared_meta": router.get("startup_prepared"),
		"loaded_save": world.production.loaded_save, "position": str(world.player.global_position),
		"terminal_road_prepared": terminal._road_prepared,
		"terminal_distance": world.player.global_position.distance_to(preload("res://runtime/terminal/TerminalRoutes.gd").point(0, 0))}
	if not fixture.is_empty(): result.ready.restore_distance = world.player.global_position.distance_to(result.fixture.position)
	if not fixture.is_empty() and (not world.production.loaded_save or result.ready.terminal_distance < 100.0 or terminal._road_prepared or result.ready.restore_distance > .5):
		push_error("probe_first_dispatch_plan: save distante não foi restaurado sem preparar o terminal")
		_save(out); quit(6); return
	result.environment = {"engine": Engine.get_version_info().string, "renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(), "resolution": str(root.size), "vsync": DisplayServer.window_get_vsync_mode(),
		"max_fps": Engine.max_fps, "msaa": root.msaa_3d, "requested_population": world.production.requested_population, "seed": 21092026}
	print("PROBE_READY ", JSON.stringify(result.ready))
	# Ritmo normal de jogo (o despacho segue ligado; sem estrelas não há polícia).
	var worst := 0.0
	var last := Time.get_ticks_usec()
	for i in wait_frames:
		await process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
	# Ciclos/µs de referência: 120 quadros de jogo normal.
	var ref_a := _sample()
	for i in 120: await process_frame
	var ref_b := _sample()
	if ref_a.size() == 7 and ref_b.size() == 7:
		result.reference_cycles_per_usec = float(ref_b[4] - ref_a[4]) / float(maxi(1, ref_b[0] - ref_a[0]))
	result.before = {"router_native": router._native != null, "native_tried": router._native_tried,
		"script_cached": ResourceLoader.has_cached(ROUTER_SCRIPT), "worst_wait_frame_ms": worst,
		"vertices": router.routes.vertices.size(), "edge_lists": router.routes.edges.size()}
	print("PROBE_BEFORE ", JSON.stringify(result.before))
	if sample_seconds > 0.0: result.frames_before = await _sample_frames(sample_seconds)
	result.plan_entry_native = router._native != null
	# Mesmo formato do serviço: alvo perto do jogador, candidatos de faixa do roteador.
	var point: Vector3 = world.player.global_position + Vector3(18, 0, 0)
	var candidates: Array = router.spawn_candidates(point, RULES.SPAWN_MIN, RULES.SPAWN_MAX)
	var picked: Array = []
	for c in candidates:
		if d.is_visible_to_player(c.point): continue
		picked.append(c)
		if picked.size() >= 8: break
	if picked.is_empty():
		push_error("probe_first_dispatch_plan: sem candidatos")
		quit(3); return
	if mode == "split":
		_timed("load_script", func(): return load(ROUTER_SCRIPT))
		_timed("native_graph_build", func(): return router._native_graph())
	var plans: Array = []
	for i in picked.size():
		var c: Dictionary = picked[i]
		var heading := Vector3(-sin(c.yaw), 0.0, -cos(c.yaw))
		var plan: Dictionary = _timed("plan_%d" % i, func(): return router.plan(c.point, point, heading))
		plans.append({"ok": plan.get("ok", false), "reason": plan.get("reason", ""), "nodes": plan.get("nodes", []).size(),
			"length": plan.get("length", 0.0)})
	result.plans = plans
	result.after = {"router_native": router._native != null}
	# Quadros seguintes: o custo não pode só ter mudado de lugar dentro do teste.
	var after_worst := 0.0
	last = Time.get_ticks_usec()
	for i in 120:
		await process_frame
		var now := Time.get_ticks_usec()
		after_worst = maxf(after_worst, (now - last) / 1000.0)
		last = now
	result.after.worst_frame_next120_ms = after_worst
	if sample_seconds > 0.0: result.frames_after = await _sample_frames(sample_seconds)
	_save(out)
	quit(0 if router._native != null and plans.all(func(p): return p.ok) else 7)

func _prepare_fixture(fixture: String, out: String) -> bool:
	if fixture != "mountain" or out.is_empty():
		push_error("probe_first_dispatch_plan: fixture exige mountain e --out")
		return false
	var path := ProjectSettings.globalize_path(out).replace("\\", "/").get_base_dir().path_join("fixture-save.json").simplify_path()
	var project := ProjectSettings.globalize_path("res://").replace("\\", "/").simplify_path().trim_suffix("/")
	if not path.to_lower().begins_with(project.to_lower() + "/") or FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak") or FileAccess.file_exists(path + ".tmp"):
		push_error("probe_first_dispatch_plan: save isolado exige caminho novo dentro do projeto")
		return false
	var state := preload("res://runtime/GameState.gd").new()
	state.region_id = "mountain"
	state.checkpoint_id = ""
	state.intro.stage = "complete"
	var region := preload("res://world/regions/NativeRegion.gd").new()
	region.region_id = "mountain"
	var point: Vector3 = region.spawn_position + Vector3.UP * .08
	region.free()
	state.world_state.pedestrian = {"region": "mountain", "position": [point.x, point.y, point.z]}
	var store := preload("res://runtime/SaveStore.gd").new()
	store.path = path
	if store.save(state) != OK:
		push_error("probe_first_dispatch_plan: falha ao gravar fixture")
		return false
	world.set_meta("menu_save_path", path)
	result.fixture = {"kind": fixture, "path": path, "requested_position": str(point), "position": point}
	return true

func _sample_frames(seconds: float) -> Dictionary:
	var frames: Array[float] = []
	var focused := 0
	var previous := Time.get_ticks_usec()
	var began := previous
	var began_utc := Time.get_datetime_string_from_system(true)
	while Time.get_ticks_usec() - began < seconds * 1000000.0:
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - previous) / 1000.0)
		previous = now
		if DisplayServer.window_is_focused(): focused += 1
	var sorted := frames.duplicate()
	sorted.sort()
	return {"intervals_ms": frames, "seconds": (previous - began) / 1000000.0, "frames": frames.size(), "began_usec": began,
		"finished_usec": previous, "began_utc": began_utc, "finished_utc": Time.get_datetime_string_from_system(true),
		"focused_frames": focused, "fps": frames.size() * 1000000.0 / (previous - began),
		"p50_ms": sorted[int((sorted.size() - 1) * .5)], "p95_ms": sorted[int((sorted.size() - 1) * .95)],
		"p99_ms": sorted[int((sorted.size() - 1) * .99)], "max_ms": sorted[-1],
		"over_33_3": frames.filter(func(ms): return ms > 33.3).size(), "over_66_7": frames.filter(func(ms): return ms > 66.7).size()}

func _save(out: String) -> void:
	# Os intervalos brutos ficam no JSON; imprimi-los cria trabalho extra no console.
	var summary := result.duplicate()
	for phase in ["frames_before", "frames_after"]:
		if not result.has(phase): continue
		summary[phase] = result[phase].duplicate()
		summary[phase].erase("intervals_ms")
	print("PROBE_RESULT ", JSON.stringify(summary))
	if out.is_empty(): return
	var path := out if out.is_absolute_path() else ProjectSettings.globalize_path(out)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null: f.store_string(JSON.stringify(result, "\t"))

## Custo de inicialização/JIT da classe C# isolado do mundo: o mesmo processo ainda não
## executou nenhum método de RoadGraphSearch. Grade sintética 12x12 de mão dupla; a 1ª
## rodada inclui load do .cs + JIT, a 2ª (instância nova) mostra o custo quente.
func _cold_class() -> void:
	var tag := "warm_" if result.has("cold_class_second") else "cold_"
	var vertices := PackedVector3Array()
	var from := PackedInt32Array()
	var to := PackedInt32Array()
	var width := PackedFloat64Array()
	var lanes := PackedInt32Array()
	var one_way := PackedInt32Array()
	var n := 12
	for z in n:
		for x in n: vertices.append(Vector3(x * 60.0, 0.0, z * 60.0))
	for z in n:
		for x in n:
			var v := z * n + x
			for w in [v + 1 if x + 1 < n else -1, v + n if z + 1 < n else -1]:
				if w < 0: continue
				for pair in [[v, w], [w, v]]:
					from.append(pair[0]); to.append(pair[1]); width.append(8.0); lanes.append(1); one_way.append(0)
	var script: Script = _timed(tag + "load_script", func(): return load(ROUTER_SCRIPT))
	var native: RefCounted = _timed(tag + "new", func(): return script.new())
	_timed(tag + "Build", func(): return native.Build(vertices, from, to, width, lanes, one_way))
	_timed(tag + "NearestEdge", func(): return native.NearestEdge(Vector3(130, 0, 70), true, Vector3.RIGHT))
	_timed(tag + "Plan", func(): return native.Plan(0, n * n - 1))
	var curve := Curve3D.new()
	for i in 20: curve.add_point(Vector3(i * 10.0, 0.0, sin(i) * 3.0))
	curve.bake_interval = 0.5
	_timed(tag + "BuildPath", func(): return native.BuildPath(curve, 0.0, 120.0, Vector3(190, 0, 0), 1.0, 0.5))
	_timed(tag + "NearestEdge_2", func(): return native.NearestEdge(Vector3(400, 0, 300), false, Vector3.ZERO))
	_timed(tag + "Plan_2", func(): return native.Plan(5, 77))
