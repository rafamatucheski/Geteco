extends "res://tests/claude_gameplay_audit/AuditCommon.gd"

const SAMPLE_SECONDS := 20.0

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	_tag = "fuel_passes"
	arm_watchdog(180)
	isolate_saves(_tag)
	skip_onboarding_flags()
	var world := await boot_harbor(15)
	while not world.gameplay_ready: await process_frame
	root.size = Vector2i(1280,720)
	var player: CharacterBody2D = world.get_node("Player")
	var room: Node2D = world.get_node("Interiors/InteriorSpaces/FuelInterior")
	player.global_position = room.to_global(room.project_floor(Vector2(0,1)))
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	await physics_frames(45)
	await sample("full",room,world)
	room.set_process(false)
	var force_off: Callable = func(): room.view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	RenderingServer.frame_pre_draw.connect(force_off)
	room.view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	await physics_frames(45)
	await sample("no_fuel_view",room,world)
	RenderingServer.frame_pre_draw.disconnect(force_off)
	room.set_process(true)
	room.view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await physics_frames(45)
	await sample("full_again",room,world)
	world.get_node("District").hide()
	await physics_frames(45)
	await sample("no_district_draw",room,world)
	world.get_node("District").show()
	await physics_frames(5)
	print("FUEL PASSES restored=",room.is_processing(),"/",world.get_node("District").visible,"/",room.view.render_target_update_mode)
	world.queue_free()
	await process_frame
	cleanup_isolated_saves()
	quit(0)

func sample(label: String, room: Node2D, world: Node2D) -> void:
	var times := PackedFloat64Array()
	var cpu := PackedFloat64Array()
	var physics := PackedFloat64Array()
	var draws := PackedFloat64Array()
	var start := Time.get_ticks_usec()
	var previous := start
	while Time.get_ticks_usec()-start < int(SAMPLE_SECONDS*1000000):
		await process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now-previous)/1000.0)
		previous = now
		cpu.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var sorted := Array(times)
	sorted.sort()
	var result := {
		"label":label,
		"seconds":float(previous-start)/1000000.0,
		"fps":float(times.size())/(float(previous-start)/1000000.0),
		"p50_ms":sorted[int((sorted.size()-1)*.50)],
		"p95_ms":sorted[int((sorted.size()-1)*.95)],
		"p99_ms":sorted[int((sorted.size()-1)*.99)],
		"cpu_process_mean_ms":mean(cpu),
		"cpu_physics_mean_ms":mean(physics),
		"draw_calls_mean":mean(draws),
		"room_view_update":room.view.render_target_update_mode,
		"district_visible":world.get_node("District").visible,
	}
	print("FUEL PASS ",JSON.stringify(result))

func mean(values: PackedFloat64Array) -> float:
	var total := 0.0
	for value in values: total += value
	return total/maxf(1.0,values.size())
