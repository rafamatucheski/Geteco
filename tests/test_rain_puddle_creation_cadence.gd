extends SceneTree

const RAIN := preload("res://world/harbor/HarborRainPuddles.gd")
const MAX_TEST_FRAMES := 180
const FRAME_DELTA := 1.0 / 60.0

var failures := 0


class Weather extends CanvasModulate:
	var intensity := 0.0

	func get_rain_intensity() -> float:
		return intensity


class Roads extends Node2D:
	var _roads: Array[Dictionary] = [
		{"points": PackedVector2Array([Vector2(-800, 140), Vector2(24000, 140)]), "width": 96.0},
		{"points": PackedVector2Array([Vector2(-800, 320), Vector2(24000, 320)]), "width": 72.0},
		{"points": PackedVector2Array([Vector2(-800, 520), Vector2(24000, 520)]), "width": 120.0},
	]


func _initialize() -> void:
	run.call_deferred()


func check(value: bool, label: String) -> void:
	print(("PASS " if value else "FAIL ") + label)
	if not value:
		failures += 1


func _count_particles(node: Node) -> int:
	var count := 1 if node is CPUParticles2D else 0
	for child in node.get_children():
		count += _count_particles(child)
	return count


func _count_puddles(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		if child is Puddle:
			count += 1
	return count


func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world

	var weather := Weather.new()
	world.add_child(weather)

	var roads := Roads.new()
	roads.name = "RoadNetwork"
	world.add_child(roads)

	var camera := Camera2D.new()
	world.add_child(camera)
	camera.position = Vector2(200, 300)
	camera.make_current()

	var rain := RAIN.new()
	world.add_child(rain)
	rain.set_process(false)
	rain._rng.seed = 24680
	await process_frame
	# Keep this focused fixture out of the production manager group: autoloaded
	# medical/weather observers expect the complete DayNightWeatherManager API.
	rain._weather = weather

	weather.intensity = 1.0
	var previous_puddles := _count_puddles(rain)
	var previous_particles := _count_particles(rain)
	var max_frame_usec := 0
	var max_puddles_added := 0
	var max_particles_added := 0
	var completed_frame := -1
	var total_usec := 0
	for frame in MAX_TEST_FRAMES:
		var started := Time.get_ticks_usec()
		rain._process(FRAME_DELTA)
		var elapsed := Time.get_ticks_usec() - started
		total_usec += elapsed
		max_frame_usec = maxi(max_frame_usec, elapsed)
		var puddle_count := _count_puddles(rain)
		var particle_count := _count_particles(rain)
		max_puddles_added = maxi(max_puddles_added, puddle_count - previous_puddles)
		max_particles_added = maxi(max_particles_added, particle_count - previous_particles)
		previous_puddles = puddle_count
		previous_particles = particle_count
		if puddle_count >= 96 and completed_frame < 0:
			completed_frame = frame + 1
		await process_frame

	var telemetry: Dictionary = rain.get_build_telemetry() if rain.has_method("get_build_telemetry") else {}
	print("RAIN_PUDDLE_CADENCE ", JSON.stringify({
		"pool_size": _count_puddles(rain),
		"particles": _count_particles(rain),
		"max_frame_usec": max_frame_usec,
		"total_usec": total_usec,
		"max_puddles_added_per_frame": max_puddles_added,
		"max_particles_added_per_frame": max_particles_added,
		"materialization_frames": completed_frame,
		"materialization_seconds_at_60hz": completed_frame * FRAME_DELTA if completed_frame >= 0 else -1.0,
		"telemetry": telemetry,
	}))

	check(_count_puddles(rain) == 96, "The complete bounded puddle population materializes")
	check(max_puddles_added <= 2, "Puddle construction is limited to two instances per frame")
	check(max_particles_added <= 1, "Shared splash emitters are prewarmed at no more than one per frame")
	check(completed_frame > 0 and completed_frame <= 60, "The complete pool is ready within one second at 60 Hz")
	check(max_frame_usec < 12000, "No controlled construction frame consumes most of the 16.67 ms budget")
	check(int(telemetry.get("planning_peak_usec", 999999)) < 4000, "Surface planning is split below a quarter of the 16.67 ms budget")
	check(rain.get_splash_pool_size() == 8, "A bounded shared splash pool is ready before puddles become interactive")

	# Advance the same natural 45-second accumulation curve. Construction must
	# finish long before the authored water reaches its final visual state.
	for step in 180:
		rain._process(0.25)
	var visible_puddles := 0
	var per_puddle_particles := 0
	var nearby: Node
	for puddle in rain.get_children():
		if puddle is Puddle:
			if puddle.visible:
				visible_puddles += 1
				if nearby == null:
					nearby = puddle
			per_puddle_particles += _count_particles(puddle)
	check(is_equal_approx(rain.wetness, 1.0), "Water reaches the unchanged final wetness after 45 simulated seconds")
	check(visible_puddles > 0, "Mature nearby puddles retain their final visible presentation")
	check(per_puddle_particles == 0, "Puddles do not retain one particle system per instance")

	if nearby != null:
		nearby._splash(120.0)
		check(rain.get_active_splash_count() == 1, "A mature puddle still emits a visible pooled splash on impact")

	world.queue_free()
	await process_frame
	print("RAIN PUDDLE CREATION CADENCE failures=", failures)
	quit(0 if failures == 0 else 1)
