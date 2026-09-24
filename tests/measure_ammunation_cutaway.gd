extends "res://tests/claude_gameplay_audit/AuditCommon.gd"

const SAMPLE_SECONDS := 30.0
const OUTPUT_DIR := "geteco-ammunation-cutaway-0922"

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	_tag = "ammunation_cutaway"
	arm_watchdog(150)
	isolate_saves(_tag)
	skip_onboarding_flags()
	var world := await boot_harbor(15)
	while not world.gameplay_ready:
		await process_frame
	root.size = Vector2i(1280, 720)
	var player: CharacterBody2D = world.get_node("Player")
	var door: Node2D = world.get_node("District/NorthFrontage2/AmmunationEntrance")
	var room: Node2D = world.get_node("Interiors").ammunation_interior
	DirAccess.make_dir_recursive_absolute(OS.get_temp_dir().path_join(OUTPUT_DIR))
	player.global_position = door.to_global(Vector2(0, 85))
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	await physics_frames(30)
	await _measure("exterior")
	if room.get("inline_mode") == true:
		player.global_position = room.to_global(room.floor_point(Vector2(0, 0.8)))
	else:
		world.get_node("Interiors")._on_exterior_destination_requested(door, player, door.destination_id, null, &"", room, room.spawn_point)
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	await physics_frames(30)
	await _measure("interior")
	world.queue_free()
	await process_frame
	cleanup_isolated_saves()
	quit(0)

func _measure(label: String) -> void:
	var samples := PackedFloat64Array()
	var start := Time.get_ticks_usec()
	var previous := start
	while Time.get_ticks_usec() - start < int(SAMPLE_SECONDS * 1000000.0):
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now - previous) / 1000.0)
		previous = now
	var elapsed := float(previous - start) / 1000000.0
	var values := Array(samples)
	values.sort()
	var result := {
		"scenario": label,
		"renderer": RenderingServer.get_current_rendering_method(),
		"resolution": root.size,
		"seconds": elapsed,
		"frames": values.size(),
		"fps_mean": float(values.size()) / elapsed,
		"p50_ms": values[int((values.size() - 1) * 0.50)],
		"p95_ms": values[int((values.size() - 1) * 0.95)],
		"p99_ms": values[int((values.size() - 1) * 0.99)],
		"max_ms": values.back(),
		"over_33_ms": values.filter(func(v): return v > 33.3).size(),
		"over_66_ms": values.filter(func(v): return v > 66.7).size(),
	}
	var suffix := "after" if room_has_inline() else "before"
	var path := OS.get_temp_dir().path_join(OUTPUT_DIR).path_join("%s-%s.json" % [suffix, label])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Measurement write failed: %s (%s)" % [path, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print("AMMUNATION MEASURE %s %s" % [path, JSON.stringify(result)])
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_temp_dir().path_join(OUTPUT_DIR).path_join("%s-%s.png" % [suffix, label]))

func room_has_inline() -> bool:
	var world := current_scene
	return world != null and world.get_node("Interiors").ammunation_interior.get("inline_mode") == true
