extends "res://tests/claude_gameplay_audit/AuditCommon.gd"

const OUTPUT_DIR := "geteco-inline-services-0922"
const SAMPLE_SECONDS := 30.0

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	_tag = "harbor_services_cutaway"
	arm_watchdog(420)
	isolate_saves(_tag)
	skip_onboarding_flags()
	var world := await boot_harbor(15)
	while not world.gameplay_ready: await process_frame
	root.size = Vector2i(1280,720)
	world.weather.is_dynamic_time = false
	world.weather.time_of_day = .46
	world.weather._update_lighting()
	DirAccess.make_dir_recursive_absolute(OS.get_temp_dir().path_join(OUTPUT_DIR))
	var player: CharacterBody2D = world.get_node("Player")
	player.set_physics_process(false)
	var manager: HarborInteriorManager = world.get_node("Interiors")
	var debug_police: bool = OS.get_cmdline_user_args().has("--police-only-debug")
	var police_interior_only: bool = OS.get_cmdline_user_args().has("--police-interior-only")
	var clinic_exterior_retake: bool = OS.get_cmdline_user_args().has("--clinic-exterior-retake")
	for spec in [
		{"id":"police","door":"District/Police/Entrance","room":"PoliceInterior"},
		{"id":"clinic","door":"District/Clinic/Entrance","room":"ClinicInterior"},
	]:
		var id: String = spec.id
		if (debug_police or police_interior_only) and id != "police": continue
		if clinic_exterior_retake and id != "clinic": continue
		var door: BuildingEntrance = world.get_node(spec.door)
		var room: Node2D = manager.get_node("InteriorSpaces/"+String(spec.room))
		var label := "after" if room.get("inline_mode")==true else "before"
		manager.set_active_interior(null)
		var outside: Vector2 = door.to_global(Vector2(0,60))
		player.global_position = outside
		player.velocity = Vector2.ZERO
		player.reset_physics_interpolation()
		player.get_node("Camera").remove_meta("compact_interior")
		player.get_node("Camera").reset_smoothing()
		await physics_frames(45)
		if id == "clinic":
			var facade: Node2D = world.get_node("District/Clinic").hospital_view
			for frame in 300:
				if facade.sprite_3d.visible: break
				await process_frame
			if clinic_exterior_retake: await create_timer(4.2).timeout
		if not police_interior_only:
			await shot(("retake" if clinic_exterior_retake else label)+"-exterior-"+id)
			if not debug_police and not clinic_exterior_retake: await measure(label,id+"-exterior")
		if room.get("inline_mode")==true:
			player.global_position = room.spawn_point.global_position
		else:
			manager._on_exterior_destination_requested(door,player,door.destination_id,null,&"",room,room.spawn_point)
		player.velocity = Vector2.ZERO
		player.reset_physics_interpolation()
		player.get_node("Camera").reset_smoothing()
		await physics_frames(45)
		if debug_police:
			var cam: Camera2D = player.get_node("Camera")
			print("POLICE INTERIOR DIAG player=",player.global_position," room=",room.global_position," spawn=",room.spawn_point.global_position," contains=",room.contains_point(player.global_position)," visible=",room.visible," sprite=",room.room_display.visible," camera=",cam.global_position," screen=",cam.get_screen_center_position()," rect=",room.get_camera_rect()," current=",cam.is_current())
		await shot(("retake" if clinic_exterior_retake else label)+"-interior-"+id)
		if not debug_police and not clinic_exterior_retake: await measure(label,id+"-interior")
		if room.get("inline_mode")!=true: room.set_npc_rendering_active(false)
	manager.set_active_interior(null)
	world.queue_free()
	await process_frame
	cleanup_isolated_saves()
	quit(0)

func shot(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	var path := OS.get_temp_dir().path_join(OUTPUT_DIR).path_join(name+".png")
	root.get_texture().get_image().save_png(path)
	print("SERVICE SHOT ",path)

func measure(label: String, scenario: String) -> void:
	var samples := PackedFloat64Array()
	var start := Time.get_ticks_usec()
	var previous := start
	while Time.get_ticks_usec()-start < int(SAMPLE_SECONDS*1000000.0):
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now-previous)/1000.0)
		previous = now
	var sorted := Array(samples)
	sorted.sort()
	var result := {"scenario":scenario,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":root.size,"seconds":float(previous-start)/1000000.0,"fps":float(samples.size())/(float(previous-start)/1000000.0),"p95_ms":sorted[int((sorted.size()-1)*.95)],"p99_ms":sorted[int((sorted.size()-1)*.99)],"over_33_ms":sorted.filter(func(v):return v>33.3).size(),"over_66_ms":sorted.filter(func(v):return v>66.7).size()}
	var file := FileAccess.open(OS.get_temp_dir().path_join(OUTPUT_DIR).path_join(label+"-"+scenario+".json"),FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(result,"  "))
		file.close()
	print("SERVICE MEASURE ",JSON.stringify(result))
