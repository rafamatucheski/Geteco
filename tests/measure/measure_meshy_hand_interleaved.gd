extends "res://tests/measure/measure_meshy_hand_optimization.gd"
## Quatro combinações no mesmo grupo de atores, distribuídas pelo mesmo intervalo.
## Distingue custo de arma/cadeia sem confundir a condição com tendências longas de carga.
const ORDER := [0, 1, 3, 2, 1, 2, 0, 3, 2, 3, 1, 0, 3, 0, 2, 1]
const LABELS := ["original", "weapon_only", "chain_only", "optimized"]
var paired_recording := false
var bins: Array = [[], [], [], []]
var draw_bins: Array = [[], [], [], []]
var durations := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var active_variant := 0
var sequence_index := 0
var paired_stamp := 0

func _initialize() -> void:
	super._initialize()
	kinds = ["original", "original"]

func _process(delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if paired_recording:
		var elapsed := float(now - paired_stamp) / 1000.0
		bins[active_variant].append(elapsed)
		durations[active_variant] += elapsed
		draw_bins[active_variant].append(float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))
		active_variant = ORDER[sequence_index % ORDER.size()]
		MODEL.optimize_weapon_targets = (active_variant & 1) != 0
		RIG.optimize_pose_chain = (active_variant & 2) != 0
		sequence_index += 1
	paired_stamp = now
	return super._process(delta)

func _sample(_round_name: String, _kind: String) -> void:
	await process_frame
	for officer in officers:
		assert(officer.body.palm_grip_enabled and officer.body.mesh_node.get_blend_shape_count() == 2)
	await create_timer(WARMUP).timeout
	bins = [[], [], [], []]
	draw_bins = [[], [], [], []]
	durations.fill(0.0)
	active_variant = 0
	MODEL.optimize_weapon_targets = false
	RIG.optimize_pose_chain = false
	sequence_index = sample_index * 8
	paired_stamp = Time.get_ticks_usec()
	paired_recording = true
	while minf(minf(durations[0], durations[1]), minf(durations[2], durations[3])) < 30000.0:
		await create_timer(.5).timeout
	paired_recording = false
	for variant in 4:
		var values: Array = bins[variant]
		var sorted := values.duplicate()
		sorted.sort()
		var over33 := 0
		var over66 := 0
		var draw_sum := 0.0
		for value in values:
			if value > 33.3: over33 += 1
			if value > 66.7: over66 += 1
		for value in draw_bins[variant]: draw_sum += value
		var n := values.size()
		var row := {"pair": sample_index, "kind": LABELS[variant], "frames": n,
			"duration_s": durations[variant] / 1000.0, "fps": n * 1000.0 / durations[variant],
			"p50": sorted[int(n * .50)], "p95": sorted[int(n * .95)], "p99": sorted[int(n * .99)],
			"max": sorted.back(), "over33": over33, "over66": over66,
			"draw_calls_mean": draw_sum / n, "method": "four interleaved flags; preceding interval; same V11 geometry"}
		rounds.append(row)
		FileAccess.open("%s/raw-pair%d-%s.json" % [output_dir, sample_index, LABELS[variant]], FileAccess.WRITE).store_string(JSON.stringify({"frame_ms": values, "draw_calls": draw_bins[variant]}))
		print("HANDS_INTERLEAVED ", JSON.stringify(row))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/pair-%d.png" % [output_dir, sample_index]))
	sample_index += 1
