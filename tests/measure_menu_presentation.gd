extends SceneTree

const SAMPLE_SECONDS := 30.0
const WARMUP_SECONDS := 2.0

func _initialize() -> void:
	run.call_deferred()

func percentile(sorted_values: Array[float], fraction: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var index := clampi(ceili(float(sorted_values.size()) * fraction) - 1, 0, sorted_values.size() - 1)
	return sorted_values[index]

func measure(label: String, presentation: Control, animate_legacy: bool) -> Dictionary:
	var warmup_end := Time.get_ticks_usec() + int(WARMUP_SECONDS * 1000000.0)
	while Time.get_ticks_usec() < warmup_end:
		if animate_legacy:
			presentation.atmosphere.advance(1.0 / 60.0, false)
			presentation.background.material.set_shader_parameter("atmosphere_time", presentation.atmosphere.elapsed)
		await process_frame
	var samples: Array[float] = []
	var above_33 := 0
	var above_66 := 0
	var started := Time.get_ticks_usec()
	var previous := started
	while Time.get_ticks_usec() - started < int(SAMPLE_SECONDS * 1000000.0):
		if animate_legacy:
			presentation.atmosphere.advance(1.0 / 60.0, false)
			presentation.background.material.set_shader_parameter("atmosphere_time", presentation.atmosphere.elapsed)
		await process_frame
		var now := Time.get_ticks_usec()
		var frame_ms := float(now - previous) / 1000.0
		previous = now
		samples.append(frame_ms)
		if frame_ms > 33.3:
			above_33 += 1
		if frame_ms > 66.7:
			above_66 += 1
	var elapsed_seconds := float(Time.get_ticks_usec() - started) / 1000000.0
	samples.sort()
	var result := {
		"label": label,
		"frames": samples.size(),
		"seconds": elapsed_seconds,
		"fps": float(samples.size()) / elapsed_seconds,
		"p50_ms": percentile(samples, 0.50),
		"p95_ms": percentile(samples, 0.95),
		"p99_ms": percentile(samples, 0.99),
		"max_ms": samples[-1] if not samples.is_empty() else 0.0,
		"above_33_3_ms": above_33,
		"above_66_7_ms": above_66,
	}
	print("MENU_PRESENTATION_PERF ", JSON.stringify(result))
	return result

func run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	change_scene_to_file("res://ui/MainMenu.tscn")
	await create_timer(1.0).timeout
	var presentation = current_scene.get_node("SunsetPresentation")
	var refreshed_texture: Texture2D = presentation.background.texture
	var refreshed_cover_material: Material = presentation.cover.material
	presentation.background.texture = load("res://prototypes/menu_concept/dante_sunset_preview.png")
	var legacy_material := ShaderMaterial.new()
	legacy_material.shader = load("res://ui/SunsetAtmosphere.gdshader")
	presentation.background.material = legacy_material
	presentation.cover.material = null
	presentation.cover.color = Color(0.04, 0.05, 0.08, 0.65)
	presentation.atmosphere = preload("res://ui/SunsetAtmosphere.gd").new()
	presentation.add_child(presentation.atmosphere)
	presentation.atmosphere.size = presentation.background.size
	presentation.atmosphere.position = presentation.background.position
	var legacy := await measure("legacy_animated", presentation, true)
	presentation.atmosphere.queue_free()
	presentation.atmosphere = null
	presentation.background.texture = refreshed_texture
	presentation.background.material = null
	presentation.cover.material = refreshed_cover_material
	presentation.cover.color = Color.WHITE
	presentation.arrange()
	var refreshed := await measure("refreshed_static", presentation, false)
	print("MENU_PRESENTATION_PERF_COMPARISON baseline_p95_ms=", legacy.p95_ms,
		" refreshed_p95_ms=", refreshed.p95_ms,
		" delta_percent=", ((refreshed.p95_ms / legacy.p95_ms) - 1.0) * 100.0)
	quit()
