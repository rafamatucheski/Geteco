extends "res://tests/claude_gameplay_audit/AuditCommon.gd"

const OUTPUT_DIR := "geteco-inline-homes-0922"
const SAMPLE_SECONDS := 30.0

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	_tag = "home_cutaway"
	arm_watchdog(280)
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
	player.money = 200000
	player.set_physics_process(false)
	var manager: ResidenceManager = world.get_node("ResidencePrototype")
	var user_args := OS.get_cmdline_user_args()
	var photos_only: bool = user_args.has("--photos-only")
	var measure_remaining: bool = user_args.has("--measure-remaining")
	var ablate_room: bool = user_args.has("--ablate-room")
	var selected_home := ""
	for arg in user_args:
		if arg.begins_with("--only="): selected_home = arg.trim_prefix("--only=")
	var first := true
	for id in ["westgate_garden","quayside_house","canal_north"]:
		if not selected_home.is_empty() and id!=selected_home: continue
		if measure_remaining and id=="westgate_garden": continue
		manager.purchase_home(id)
		var property: ResidenceProperty = manager.properties[id]
		var room: ResidenceInterior = manager.residence_interiors[id]
		var label := "after" if room.get("inline_mode")==true else "before"
		player.global_position = property.entrance_position()+Vector2(0,52)
		player.velocity = Vector2.ZERO
		player.reset_physics_interpolation()
		player.get_node("Camera").reset_smoothing()
		await physics_frames(45)
		await wait_exterior(property)
		if photos_only: await create_timer(4.2).timeout
		if not measure_remaining: await shot(("retake" if photos_only else label)+"-exterior-"+id)
		if measure_remaining and not ablate_room:
			await measure("confirm" if not selected_home.is_empty() else label,id+"-exterior")
		elif not measure_remaining and first and not photos_only and not user_args.has("--keeper-only"): await measure(label,"residence-exterior")
		if room.get("inline_mode")==true:
			player.global_position = room.spawn_point.global_position
		else:
			manager.enter_home(id)
			while world.get_node("Interiors").is_transitioning(): await process_frame
		player.get_node("Camera").reset_smoothing()
		await physics_frames(45)
		if ablate_room:
			for frame in 120:
				if room._inline_occupied and not room._presentation_compacted: break
				await physics_frame
			await physics_frames(60)
			room.set_process(false)
			room.viewport_3d.size = Vector2i(2,2)
			await physics_frames(5)
			print("HOME_ABLATE_VIEW ",id," size=",room.viewport_3d.size," mode=",room.viewport_3d.render_target_update_mode)
			if room.viewport_3d.size != Vector2i(2,2):
				cleanup_isolated_saves()
				quit(2)
				return
		if not measure_remaining: await shot(("retake" if photos_only else label)+"-interior-"+id)
		if measure_remaining:
			await measure("ablate" if ablate_room else "confirm" if not selected_home.is_empty() else label,id+"-interior")
		elif not measure_remaining and first and not photos_only and not user_args.has("--keeper-only"): await measure(label,"residence-interior")
		first = false
	if measure_remaining:
		world.queue_free()
		await process_frame
		cleanup_isolated_saves()
		quit(0)
		return
	var home: Node2D = world.get_node("Cemetery/KeeperHouse")
	var keeper_room: Node2D = home.room
	var keeper_label := "after" if keeper_room.get("inline_mode")==true else "before"
	player.global_position = home.entrance.global_position+Vector2(0,48)
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	player.get_node("Camera").reset_smoothing()
	await physics_frames(45)
	await wait_exterior(home)
	if photos_only: await create_timer(4.2).timeout
	await shot(("retake" if photos_only else keeper_label)+"-exterior-keeper")
	if not OS.get_cmdline_user_args().has("--photos-only"): await measure(keeper_label,"keeper-exterior")
	if keeper_room.get("inline_mode")==true:
		player.global_position = keeper_room.spawn_point.global_position
	else:
		world.get_node("Interiors")._on_exterior_destination_requested(home.entrance,player,home.entrance.destination_id,null,&"",keeper_room,keeper_room.spawn_point)
	player.get_node("Camera").reset_smoothing()
	await physics_frames(45)
	await shot(("retake" if photos_only else keeper_label)+"-interior-keeper")
	if not OS.get_cmdline_user_args().has("--photos-only") and not OS.get_cmdline_user_args().has("--keeper-only"): await measure(keeper_label,"keeper-interior")
	world.queue_free()
	await process_frame
	cleanup_isolated_saves()
	quit(0)

func wait_exterior(building: Node2D) -> void:
	for frame in 300:
		if building.sprite_3d.visible: return
		await process_frame
	print("HOME EXTERIOR NOT READY ",building.get_path()," profile=",building.get_render_profile())

func shot(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	var path := OS.get_temp_dir().path_join(OUTPUT_DIR).path_join(name+".png")
	root.get_texture().get_image().save_png(path)
	print("HOME SHOT ",path)

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
	var result := {"scenario":scenario,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":root.size,"seconds":float(previous-start)/1000000.0,"fps":float(samples.size())/(float(previous-start)/1000000.0),"p95_ms":sorted[int((sorted.size()-1)*.95)],"p99_ms":sorted[int((sorted.size()-1)*.99)],"over_33_ms":sorted.filter(func(v):return v>33.3).size()}
	var file := FileAccess.open(OS.get_temp_dir().path_join(OUTPUT_DIR).path_join(label+"-"+scenario+".json"),FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(result,"  "))
		file.close()
	print("HOME MEASURE ",JSON.stringify(result))
