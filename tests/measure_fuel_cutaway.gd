extends "res://tests/claude_gameplay_audit/AuditCommon.gd"

const OUTPUT_DIR := "geteco-fuel-cutaway-0922"
const SAMPLE_SECONDS := 30.0

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	_tag = "fuel_cutaway"
	arm_watchdog(150)
	isolate_saves(_tag)
	skip_onboarding_flags()
	var world := await boot_harbor(15)
	while not world.gameplay_ready:
		await process_frame
	root.size = Vector2i(1280, 720)
	var room: Node2D = world.get_node("Interiors/InteriorSpaces/FuelInterior")
	var door: Node2D = room.entrance
	var player: CharacterBody2D = world.get_node("Player")
	var label := "after" if room.get("inline_mode") == true else "before"
	DirAccess.make_dir_recursive_absolute(OS.get_temp_dir().path_join(OUTPUT_DIR))
	player.global_position = door.to_global(Vector2(0, 85))
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	await physics_frames(30)
	await measure(label, "exterior")
	if room.get("inline_mode") == true:
		player.global_position = room.to_global(room.project_floor(Vector2(0, 1)))
	else:
		world.get_node("Interiors")._on_exterior_destination_requested(door, player, door.destination_id, null, &"", room, room.spawn_point)
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	await physics_frames(30)
	await measure(label, "interior")
	world.queue_free()
	await process_frame
	cleanup_isolated_saves()
	quit(0)

func measure(label: String, scenario: String) -> void:
	var samples := PackedFloat64Array()
	var start := Time.get_ticks_usec()
	var previous := start
	while Time.get_ticks_usec() - start < int(SAMPLE_SECONDS * 1000000.0):
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now - previous) / 1000.0)
		previous = now
	var elapsed := float(previous - start) / 1000000.0
	var sorted := Array(samples)
	sorted.sort()
	var result := {
		"scenario": scenario,
		"renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"resolution": root.size,
		"seconds": elapsed,
		"frames": sorted.size(),
		"fps_mean": float(sorted.size()) / elapsed,
		"p50_ms": sorted[int((sorted.size() - 1) * 0.50)],
		"p95_ms": sorted[int((sorted.size() - 1) * 0.95)],
		"p99_ms": sorted[int((sorted.size() - 1) * 0.99)],
		"max_ms": sorted.back(),
		"over_33_ms": sorted.filter(func(v): return v > 33.3).size(),
		"over_66_ms": sorted.filter(func(v): return v > 66.7).size(),
	}
	var file := FileAccess.open(OS.get_temp_dir().path_join(OUTPUT_DIR).path_join("%s-%s.json" % [label, scenario]), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(result, "  "))
		file.close()
	print("FUEL MEASURE ", JSON.stringify(result))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_temp_dir().path_join(OUTPUT_DIR).path_join("%s-%s.png" % [label, scenario]))
