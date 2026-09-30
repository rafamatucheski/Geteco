extends SceneTree
## Atravessa o mundo (porto -> costura -> montanha) teleportando o foco do jogador a
## ~25 m/s e registra todo quadro acima de 40 ms com a posição e os custos etiquetados
## (`benchmark_trace`). Serve para achar picos de streaming. Renderizado, sem outra
## instância Godot ativa:
##   godot --path . --script res://tests/measure/probe_region_hitches.gd -- --no-save --skip-arrival
const SEAM := preload("res://world/regions/WorldConnection3D.gd").SEAM
var world: Node3D
var spikes: Array[Dictionary] = []
var frames: Array[float] = []

var t_physics := 0
var t_process := 0
var t_pre := 0
var t_post := 0
var t_first_physics := 0
var prev_process := 0
var timed_nodes: Array[Node] = []
var script_ms_by_path := {}
var frame_index := 0
var prev_pre := 0
var prev_post := 0

func _initialize() -> void:
	physics_frame.connect(func():
		if t_first_physics == 0 or t_first_physics < t_post: t_first_physics = Time.get_ticks_usec()
		t_physics = Time.get_ticks_usec())
	process_frame.connect(func(): t_process = Time.get_ticks_usec())
	RenderingServer.frame_pre_draw.connect(func(): t_pre = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func(): t_post = Time.get_ticks_usec())
	run.call_deferred()

## Cada nó com _process passa a ser chamado por aqui, cronometrado (--per-script).
func adopt_processing_nodes() -> void:
	var stack: Array[Node] = [world]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children(): stack.append(child)
		if node.get_script() != null and node.is_processing() and node.has_method("_process") and node not in timed_nodes and node != self:
			timed_nodes.append(node)
			node.set_process(false)

func run_timed_processes(delta: float) -> Dictionary:
	var slow := {}
	for node in timed_nodes:
		if not is_instance_valid(node) or not node.is_inside_tree(): continue
		var began := Time.get_ticks_usec()
		node._process(delta)
		var ms := float(Time.get_ticks_usec() - began) / 1000.0
		if ms >= 3.0:
			var path: String = (node.get_script() as Script).resource_path
			slow[path] = float(slow.get(path, 0.0)) + ms
	return slow

func tally() -> Dictionary:
	var counts := {}
	var stack: Array[Node] = [world]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children(): stack.append(child)
		var script: Script = node.get_script()
		var key: String = script.resource_path.get_file() if script != null else node.get_class()
		var parent_name := str(node.get_parent().name) if node.get_parent() != null else ""
		key += " <" + parent_name.left(24) + ">"
		counts[key] = int(counts.get(key, 0)) + 1
	return counts

func diff_top(before: Dictionary, after: Dictionary) -> String:
	var rows := []
	for key in after: if int(after[key]) - int(before.get(key, 0)) >= 8: rows.append([int(after[key]) - int(before.get(key, 0)), key])
	for key in before: if int(before[key]) - int(after.get(key, 0)) >= 8: rows.append([int(after.get(key, 0)) - int(before[key]), key])
	rows.sort_custom(func(a, b): return absi(a[0]) > absi(b[0]))
	return str(rows.slice(0, 6))

func ground(point: Vector3, fallback: float) -> float:
	var query := PhysicsRayQueryParameters3D.create(Vector3(point.x, 400.0, point.z), Vector3(point.x, -50.0, point.z), 1)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	return float(hit.position.y) + 0.3 if not hit.is_empty() else fallback

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or "--no-save" not in args or "--skip-arrival" not in args: quit(2); return
	create_timer(420.0).timeout.connect(func(): push_error("PROBE_TIMEOUT"); quit(2))
	root.size = Vector2i(1280, 720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("benchmark_trace", true)
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for i in 4800:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		push_error("mundo não iniciou"); quit(1); return
	world.session.state.intro.stage = "complete"
	world.player.controlled_automatically = false
	for i in 240: await process_frame
	var start: Vector3 = world.player.position
	var waypoints := [start, Vector3(SEAM.x - 900.0, 0, SEAM.z), Vector3(SEAM.x - 250.0, 0, SEAM.z), SEAM, Vector3(SEAM.x + 300.0, 0, SEAM.z), Vector3(SEAM.x + 900.0, 0, SEAM.z - 200.0), SEAM, Vector3(SEAM.x - 400.0, 0, SEAM.z), start, Vector3(SEAM.x - 900.0, 0, SEAM.z), Vector3(SEAM.x - 250.0, 0, SEAM.z), SEAM, Vector3(SEAM.x + 300.0, 0, SEAM.z), Vector3(SEAM.x + 900.0, 0, SEAM.z - 200.0), SEAM, Vector3(SEAM.x - 400.0, 0, SEAM.z)]
	var position := start
	var y := start.y
	Engine.set_meta("slow_stream_records", [])
	var seen_records := 0
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var last_nodes := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var previous := Time.get_ticks_usec()
	var elapsed := 0.0
	var stage := 1
	while stage < waypoints.size():
		var target: Vector3 = waypoints[stage]
		var flat := Vector3(target.x - position.x, 0, target.z - position.z)
		if flat.length() < 8.0:
			stage += 1
			continue
		position += flat.normalized() * minf(flat.length(), 25.0 / 60.0)
		y = ground(position, y)
		position.y = y
		world.player.teleport(position)
		world.production.region.set_focus(position) if world.production.region != null else null
		frame_index += 1
		var slow_scripts := {}
		if "--per-script" in args:
			if frame_index % 30 == 1: adopt_processing_nodes()
			slow_scripts = run_timed_processes(1.0 / 60.0)
		var tally_before := tally() if ("--diff-nodes" in args and position.x < -60.0 and position.x > -100.0) else {}
		var saved_process := t_process
		await process_frame
		prev_process = saved_process
		prev_pre = t_pre
		prev_post = t_post
		var now := Time.get_ticks_usec()
		var frame_ms := float(now - previous) / 1000.0
		previous = now
		elapsed += frame_ms / 1000.0
		frames.append(frame_ms)
		var slow_now: Array = Engine.get_meta("slow_stream_records", [])
		var new_records: Array = slow_now.slice(seen_records)
		seen_records = slow_now.size()
		if frame_ms <= 40.0: last_nodes = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		if frame_ms > 40.0:
			var labels := []
			for cost in world.get_meta("perf_costs", []):
				if int(cost.start_usec) >= now - int(frame_ms * 1000.0) - 2000 and int(cost.start_usec) <= now:
					labels.append("%s %.1f ms" % [cost.label, float(cost.duration_usec) / 1000.0])
			var rid := root.get_viewport_rid()
			var split := "process=%.1f physics=%.1f render_cpu=%.1f render_gpu=%.1f nodes%+d draw=%d" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, RenderingServer.viewport_get_measured_render_time_cpu(rid), RenderingServer.viewport_get_measured_render_time_gpu(rid), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT) - last_nodes), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))]
			labels.append(split)
			if not tally_before.is_empty(): labels.append("nos: " + diff_top(tally_before, tally()))
			if not slow_scripts.is_empty(): labels.append("scripts lentos: " + str(slow_scripts))
			# Fases do quadro ANTERIOR (o intervalo medido acaba de fechar): scripts, desenho e o resto
			# (física + espera de apresentação/GPU) até este process_frame.
			labels.append("fases: scripts=%.0f desenho=%.0f fisica_e_espera=%.0f" % [float(prev_pre - prev_process) / 1000.0, float(prev_post - prev_pre) / 1000.0, float(t_process - prev_post) / 1000.0])
			if not new_records.is_empty(): labels.append("registros novos: " + str(new_records))
			spikes.append({"t": snappedf(elapsed, 0.01), "frame_ms": snappedf(frame_ms, 0.1), "x": snappedf(position.x, 1.0), "z": snappedf(position.z, 1.0), "waypoint": stage, "labels": labels})
			print("SPIKE t=%.1fs %.0f ms at (%.0f,%.0f) wp=%d %s" % [elapsed, frame_ms, position.x, position.z, stage, str(labels)])
	frames.sort()
	var summary := {"frames": frames.size(), "p50": frames[frames.size() / 2], "p95": frames[int(frames.size() * 0.95)], "p99": frames[int(frames.size() * 0.99)], "max": frames[-1], "over_40": spikes.size()}
	print("PROBE_SUMMARY ", JSON.stringify(summary))
	print("MOTOCROSS_BUILD ", str(Engine.get_meta("motocross_build_ms", {})))
	print("PROCESS_LOG ", str(Engine.get_meta("slow_stream_records", []).filter(func(x): return str(x).begins_with("PROCESS") or str(x).begins_with("ETAPA"))))
	print("SLOW_RECORDS ", str(Engine.get_meta("slow_stream_records", [])))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence/region-hitches"))
	var label := "run"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	var file := FileAccess.open("res://evidence/region-hitches/probe-%s.json" % label, FileAccess.WRITE)
	file.store_string(JSON.stringify({"summary": summary, "spikes": spikes, "costs": world.get_meta("perf_costs", [])}, "\t"))
	file.close()
	quit(0)
