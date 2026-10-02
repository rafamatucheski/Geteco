extends SceneTree
## Diagnóstico renderizado na cena produtiva. Setup posiciona carro e jogador uma
## vez; o percurso usa inputs normais, sem fixar velocidade ou destravar por teleporte.
const CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
var world: Node3D
var frames: Array[float] = []
var samples: Array[Dictionary] = []
var path := Curve3D.new()
var output_path := ""

func _initialize() -> void:
	run.call_deferred()

func argument(name: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(name + "="): return arg.trim_prefix(name + "=")
	return fallback

func run() -> void:
	seed(20261001)
	output_path = argument("--out", "")
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args() or not output_path.begins_with("res://evidence/") or FileAccess.file_exists(output_path):
		push_error("Use renderização, --no-save e --out=res://evidence/ com destino novo.")
		quit(2)
		return
	create_timer(300.0).timeout.connect(func(): push_error("STALL_STREAMING timeout"); quit(2))
	root.size = Vector2i(1280, 720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("benchmark_trace", true)
	root.add_child(world)
	current_scene = world
	for i in 6000:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		push_error("Partida não ficou pronta.")
		quit(1)
		return
	world.session.state.intro.stage = "complete"
	var start := Vector3(425.0, 0.0, -282.5)
	world.player.teleport(start)
	world.production._update_physical_residency(start)
	for i in 180: await physics_frame
	for road in world.production.regions.harbor.roads:
		if road.id != "mountain_bridge_outbound": continue
		for point: Vector3 in road.points:
			if point.x >= start.x: path.add_point(point)
	path.add_point(Vector3(CONNECTION.SEAM.x + 12.0, 0.0, CONNECTION.SEAM.z))
	for road in world.production.regions.mountain.roads:
		if road.id != "mountain_pass": continue
		for point: Vector3 in road.points:
			if point.x > CONNECTION.SEAM.x + 12.0: path.add_point(point)
	if path.point_count < 4:
		push_error("Não foi possível montar o percurso produtivo.")
		quit(1)
		return
	var car: CharacterBody3D = world.driving.car
	start = path.sample_baked(0.0, true)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start + Vector3.UP * 400.0, start - Vector3.UP * 100.0, 1))
	if hit.is_empty():
		push_error("Setup sem piso na via.")
		quit(1)
		return
	start.y = float(hit.position.y) + .12
	var tangent := path.sample_baked(2.0, true) - start
	car.place(start, atan2(-tangent.x, -tangent.z))
	for i in 3: await physics_frame
	var entered := false
	for side in [-1, 1]:
		world.player.teleport(car.to_global(Vector3(side * (car.half_width + .65), .04, .15)))
		await physics_frame
		if world.driving.interact():
			entered = true
			break
	for i in 240:
		await physics_frame
		if entered and car.controlled and not car.input_locked and not world.driving.is_body_transition_active(): break
	if not entered or not car.controlled or car.input_locked:
		push_error("Embarque não concluiu.")
		quit(1)
		return
	var requested_stars := clampi(int(argument("--stars", "0")), 0, 6)
	var use_godmode := "--godmode" in OS.get_cmdline_user_args()
	if use_godmode and not world.gameplay.god_mode: world.gameplay.toggle_god_mode()
	if requested_stars > 0:
		world.gameplay.register_crime(world.gameplay.STAR_THRESHOLDS[requested_stars] + 1, world.player.global_position)
	print("STALL_STREAMING_READY car=", car.global_position, " stars=", world.gameplay.stars)
	var previous := Time.get_ticks_usec()
	var measured := 0.0
	var drove := 0.0
	var reached := false
	var stopped := 0.0
	var stuck := 0.0
	var last_point := car.global_position
	var meters := 0.0
	var last_sample := -1
	var target_meters := float(argument("--distance", "180"))
	while measured < 160.0:
		if not is_instance_valid(car) or not world.driving.occupied: break
		var offset := path.get_closest_offset(car.global_position)
		var target := path.sample_baked(minf(offset + 14.0, path.get_baked_length()), true)
		var direction := target - car.global_position
		var desired := atan2(-direction.x, -direction.z)
		var error := wrapf(desired - car.rotation.y, -PI, PI)
		Input.action_release("move_left")
		Input.action_release("move_right")
		if error > .015: Input.action_press("move_left", clampf(error * 2.0, 0.0, 1.0))
		elif error < -.015: Input.action_press("move_right", clampf(-error * 2.0, 0.0, 1.0))
		Input.action_release("accelerate")
		Input.action_release("brake")
		Input.action_release("handbrake")
		if not reached and absf(car.speed) < 12.0: Input.action_press("accelerate", 1.0)
		elif reached: Input.action_press("handbrake", 1.0)
		elif absf(car.speed) > 14.0: Input.action_press("brake", .4)
		await process_frame
		var now := Time.get_ticks_usec()
		var frame_ms := float(now - previous) / 1000.0
		previous = now
		frames.append(frame_ms)
		measured += frame_ms / 1000.0
		var moved := car.global_position.distance_to(last_point)
		meters += moved
		last_point = car.global_position
		if reached:
			stopped += frame_ms / 1000.0
			if stopped >= 30.0: break
		else:
			drove += frame_ms / 1000.0
			stuck = stuck + frame_ms / 1000.0 if moved < .01 else 0.0
			if stuck > 12.0:
				print("STALL_STREAMING_STUCK car=", car.global_position)
				break
			if meters >= target_meters:
				reached = true
				print("STALL_STREAMING_REACHED seconds=", drove, " car=", car.global_position)
		var second := int(measured)
		if second != last_sample:
			last_sample = second
			samples.append({"t": second, "position": str(car.global_position), "speed": car.speed,
				"health": car.health, "engine_disabled": car.engine_disabled, "input_locked": car.input_locked,
				"path_gap": car.global_position.distance_to(path.sample_baked(offset, true)),
				"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
				"regions": world.production.regions.keys(), "stars": world.gameplay.stars})
	for action in ["move_left", "move_right", "accelerate", "brake", "handbrake"]: Input.action_release(action)
	var sorted := frames.duplicate()
	sorted.sort()
	var count := sorted.size()
	var summary := {"scenario": "productive_scene_normal_inputs", "setup_teleport": true, "teleports_during_measurement": 0,
		"reached": reached, "requested_stars": requested_stars, "godmode": use_godmode,
		"seconds": measured, "drive_seconds": drove, "meters": meters, "frames": count,
		"fps": float(count) / maxf(measured, .001), "p50_ms": sorted[int(count * .5)],
		"p95_ms": sorted[mini(count - 1, int(count * .95))], "p99_ms": sorted[mini(count - 1, int(count * .99))], "max_ms": sorted[-1],
		"over_33_ms": sorted.filter(func(ms): return ms > 33.3).size(), "over_66_ms": sorted.filter(func(ms): return ms > 66.7).size(),
		"over_100_ms": sorted.filter(func(ms): return ms > 100.0).size(), "work_trace": OS.get_environment("HARBOR_STALL_WORK") != "0",
		"renderer": RenderingServer.get_current_rendering_method(), "viewport": str(root.size), "max_fps": Engine.max_fps,
		"vsync": DisplayServer.window_get_vsync_mode(), "max_physics_steps": Engine.max_physics_steps_per_frame,
		"gpu": RenderingServer.get_video_adapter_name(), "godot": Engine.get_version_info().string}
	var component := {}
	var comparison: Array[Dictionary] = []
	if reached and "--compare-work" in OS.get_cmdline_user_args():
		# ABBA na mesma partida reduz diferenças de aquecimento e tendência de
		# população. Todos os sistemas continuam ativos; registrar a carga real.
		for mode in [false, true, true, false]:
			preload("res://runtime/StallWorkTrace.gd").enabled = mode
			var block_frames: Array[float] = []
			var block_seconds := 0.0
			var block_previous := Time.get_ticks_usec()
			var block_nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
			while block_seconds < 30.0:
				Input.action_press("handbrake", 1.0)
				await process_frame
				var block_now := Time.get_ticks_usec()
				var block_ms := float(block_now - block_previous) / 1000.0
				block_previous = block_now
				block_seconds += block_ms / 1000.0
				block_frames.append(block_ms)
			var block_sorted := block_frames.duplicate()
			block_sorted.sort()
			var block_count := block_sorted.size()
			var block_result := {"work_trace": mode, "seconds": block_seconds, "frames": block_count,
				"p50_ms": block_sorted[int(block_count * .5)], "p95_ms": block_sorted[int(block_count * .95)],
				"p99_ms": block_sorted[int(block_count * .99)], "max_ms": block_sorted[-1],
				"nodes_before": block_nodes_before, "nodes_after": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
				"position": str(car.global_position), "frames_ms": block_frames}
			comparison.append(block_result)
			print("STALL_WORK_COMPARISON ", JSON.stringify({"work_trace": mode, "p95_ms": block_result.p95_ms, "p99_ms": block_result.p99_ms, "nodes": block_result.nodes_after}))
		Input.action_release("handbrake")
		preload("res://runtime/StallWorkTrace.gd").enabled = OS.get_environment("HARBOR_STALL_WORK") != "0"
	if reached and "--unmount-diagnostic" in OS.get_cmdline_user_args() and world.production.state.region_id == "mountain" and world.production.regions.has("harbor"):
		# Chamada direta separada do percurso: pode violar pedidos de suporte de
		# ônibus/persistentes. Localiza o custo da API; não aprova streaming normal.
		component["kind"] = "direct_unmount_api_diagnostic"
		component["chunks_before"] = world.production.regions.harbor.chunks.size()
		component["nodes_before"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		var unmount_began := Time.get_ticks_usec()
		world.production._unmount_region("harbor")
		component["call_ms"] = float(Time.get_ticks_usec() - unmount_began) / 1000.0
		component["nodes_after"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		component["work"] = preload("res://runtime/StallWorkTrace.gd").events.duplicate(true)
		await process_frame
		world.production._update_physical_residency(car.global_position)
		for i in 3: await process_frame
		print("STALL_UNMOUNT_COMPONENT ", JSON.stringify(component))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path.get_base_dir()))
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("Não foi possível gravar a evidência.")
		quit(2)
		return
	file.store_string(JSON.stringify({"summary": summary, "comparison": comparison, "component_unmount": component, "samples": samples, "frames_ms": frames}, "\t"))
	file.close()
	print("STALL_STREAMING_SUMMARY ", JSON.stringify(summary))
	quit(0 if reached else 1)
