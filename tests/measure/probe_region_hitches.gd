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

func _initialize() -> void: run.call_deferred()

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
		await process_frame
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
			if not new_records.is_empty(): labels.append("registros novos: " + str(new_records))
			spikes.append({"t": snappedf(elapsed, 0.01), "frame_ms": snappedf(frame_ms, 0.1), "x": snappedf(position.x, 1.0), "z": snappedf(position.z, 1.0), "waypoint": stage, "labels": labels})
			print("SPIKE t=%.1fs %.0f ms at (%.0f,%.0f) wp=%d %s" % [elapsed, frame_ms, position.x, position.z, stage, str(labels)])
	frames.sort()
	var summary := {"frames": frames.size(), "p50": frames[frames.size() / 2], "p95": frames[int(frames.size() * 0.95)], "p99": frames[int(frames.size() * 0.99)], "max": frames[-1], "over_40": spikes.size()}
	print("PROBE_SUMMARY ", JSON.stringify(summary))
	print("MOTOCROSS_BUILD ", str(Engine.get_meta("motocross_build_ms", {})))
	print("SLOW_RECORDS ", str(Engine.get_meta("slow_stream_records", [])))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence/region-hitches"))
	var label := "run"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	var file := FileAccess.open("res://evidence/region-hitches/probe-%s.json" % label, FileAccess.WRITE)
	file.store_string(JSON.stringify({"summary": summary, "spikes": spikes, "costs": world.get_meta("perf_costs", [])}, "\t"))
	file.close()
	quit(0)
