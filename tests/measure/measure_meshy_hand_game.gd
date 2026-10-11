extends "res://tests/measure/measure_meshy_palm_game.gd"
## A/B intercalado na mesma Main viva: IA, física, tráfego e streaming continuam.
## ABBA/BAAB distribui cada condição pelo mesmo intervalo e população, sem trocar GLBs.
const MODEL := preload("res://gameplay/PoliceModel.gd")
const PATTERN := [false, true, true, false, true, false, false, true]
var bins: Array = [[], []]
var draws: Array = [[], []]
var cpu: Array = [[], []]
var gpu: Array = [[], []]
var durations := Vector2.ZERO
var active_variant := 0
var frame_index := 0

func _initialize() -> void:
	create_timer(600).timeout.connect(func(): push_error("HANDS_GAME timeout"); quit(3))
	_run.call_deferred()

func _measurement_output() -> String:
	return "res://evidence/npc-meshy/hands-perf-20261011/pose-main"

func _ready_world() -> bool:
	if not await super._ready_world(): return false
	return _check(world.dispatch.router._native_graph() != null, "roteador C# compilado ativo na Main")

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if recording and stamp > 0:
		var elapsed := float(now - stamp) / 1000.0
		bins[active_variant].append(elapsed)
		durations[active_variant] += elapsed
		draws[active_variant].append(float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))
		cpu[active_variant].append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
		gpu[active_variant].append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		active_variant = 1 if PATTERN[frame_index % PATTERN.size()] else 0
		MODEL.optimize_weapon_targets = active_variant == 1
		RIG.optimize_pose_chain = active_variant == 1
		frame_index += 1
	stamp = now
	return false

func _summary(values: Array) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var sum := 0.0
	var over33 := 0
	var over66 := 0
	for value in values:
		sum += value
		if value > 33.3: over33 += 1
		if value > 66.7: over66 += 1
	var n := values.size()
	return {"frames": n, "duration_s": sum / 1000.0, "fps": n * 1000.0 / sum,
		"p50": sorted[int(n * .50)], "p95": sorted[int(n * .95)], "p99": sorted[int(n * .99)],
		"max": sorted.back(), "over33": over33, "over66": over66}

func _mean(values: Array) -> float:
	var sum := 0.0
	for value in values: sum += value
	return sum / maxf(values.size(), 1)

func _fixture_in_view() -> int:
	var count := 0
	var camera := root.get_camera_3d()
	for officer in fixture_officers:
		if not is_instance_valid(officer) or officer.dead: continue
		var body: Node3D = officer.visual.body
		if not is_instance_valid(body) or not body.palm_grip_enabled: continue
		if camera != null and camera.is_position_in_frustum(body.to_global(Vector3(0, 1.0, 0))): count += 1
	return count

func _measure_variants() -> void:
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	for round_index in 3:
		MODEL.optimize_weapon_targets = true
		RIG.optimize_pose_chain = true
		await create_timer(5.0).timeout
		var before := _counts()
		var officers_before := _police_counts()
		var minimum_fixture_in_view := _fixture_in_view()
		bins = [[], []]
		draws = [[], []]
		cpu = [[], []]
		gpu = [[], []]
		durations = Vector2.ZERO
		frame_index = round_index * 4
		active_variant = 1
		stamp = Time.get_ticks_usec()
		recording = true
		while minf(durations.x, durations.y) < 30000.0:
			await create_timer(.5).timeout
			minimum_fixture_in_view = mini(minimum_fixture_in_view, _fixture_in_view())
		recording = false
		var after := _counts()
		var officers_after := _police_counts()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/main-%d.png" % [output_dir, round_index]))
		for variant in 2:
			var row := _summary(bins[variant])
			row.merge({"pair": round_index, "kind": "optimized" if variant == 1 else "original",
				"draw_calls_mean": _mean(draws[variant]), "render_cpu_mean_ms": _mean(cpu[variant]), "render_gpu_mean_ms": _mean(gpu[variant]),
				"bodies_pair_before": before, "bodies_pair_after": after,
				"officers_pair_before": officers_before, "officers_pair_after": officers_after,
				"minimum_fixture_in_view": minimum_fixture_in_view,
				"invalid_round": minimum_fixture_in_view < 2})
			results.append(row)
			FileAccess.open("%s/raw-%d-%d.json" % [output_dir, round_index, variant], FileAccess.WRITE).store_string(JSON.stringify({"frame_ms": bins[variant], "draw_calls": draws[variant], "render_cpu_ms": cpu[variant], "render_gpu_ms": gpu[variant]}))
			print("HANDS_GAME_AB ", JSON.stringify(row))
	FileAccess.open(output_dir + "/ab-game.json", FileAccess.WRITE).store_string(JSON.stringify({"environment": {
		"engine": Engine.get_version_info().string, "gpu": RenderingServer.get_video_adapter_name(),
		"renderer": RenderingServer.get_current_rendering_method(), "resolution": [1280, 720], "vsync": false,
		"max_fps": 0, "warmup_s": 5, "minimum_sample_s_per_condition": 30,
		"method": "three paired ABBA/BAAB interleaved windows; elapsed assigned to preceding flag; render timings may lag GPU submission",
		"scope": "same V11 geometry, two native PoliceAgent in live Main; exact weapon-target shortcuts, current transform reuse and sparse bone-origin propagation"}, "rounds": results}, "\t"))
	MODEL.optimize_weapon_targets = true
	RIG.optimize_pose_chain = true
