extends "res://tests/claude_gameplay_audit/AuditCommon.gd"

const OUTPUT_DIR := "geteco-inline-complexes-0922"
const SAMPLE_SECONDS := 30.0

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	_tag = "harbor_complexes_cutaway"
	arm_watchdog(500)
	isolate_saves(_tag)
	skip_onboarding_flags()
	var world := await boot_harbor(15)
	while not world.gameplay_ready: await process_frame
	root.size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(OS.get_temp_dir().path_join(OUTPUT_DIR))
	var player: CharacterBody2D = world.get_node("Player")
	player.set_physics_process(false)
	var manager: HarborInteriorManager = world.get_node("Interiors")
	var selected := ""
	var boss_retake := OS.get_cmdline_user_args().has("--boss-retake")
	var boss_ablate := OS.get_cmdline_user_args().has("--boss-ablate")
	var fire_ablate := OS.get_cmdline_user_args().has("--fire-ablate")
	var fire_district_ablate := OS.get_cmdline_user_args().has("--fire-district-ablate")
	var fire_exterior_control := OS.get_cmdline_user_args().has("--fire-exterior-control")
	var maciota_exterior_retake := OS.get_cmdline_user_args().has("--maciota-exterior-retake")
	var fire_interior_retake := OS.get_cmdline_user_args().has("--fire-interior-retake")
	var measure_fire_final := OS.get_cmdline_user_args().has("--fire-final")
	var measure_fire_confirm := OS.get_cmdline_user_args().has("--fire-confirm")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="): selected = arg.trim_prefix("--only=")
	for spec in [
		{"id":"maciota","door":"District/Garage/Entrance","room":manager.garage_interior},
		{"id":"fire","door":"NorthDistrict/NorthFireStation/Entrance1","room":manager.fire_station_interior},
		{"id":"boss","door":"","room":world.get_node("Interiors/InteriorSpaces/PortBossGarage")},
	]:
		var id: String = spec.id
		if not selected.is_empty() and selected != id: continue
		if fire_interior_retake and id!="fire": continue
		if boss_ablate and id!="boss": continue
		if fire_ablate and id!="fire": continue
		if fire_district_ablate and id!="fire": continue
		if fire_exterior_control and id!="fire": continue
		if maciota_exterior_retake and id!="maciota": continue
		var room = spec.room
		var label := "retake" if (boss_retake or fire_interior_retake) else ("after" if room.get("inline_mode")==true else "before")
		world.weather.is_dynamic_time = false
		world.weather.time_of_day = .08 if id=="boss" else .46
		world.weather._update_lighting()
		manager.set_active_interior(null)
		var door: BuildingEntrance = null
		if id!="boss": door = world.get_node(spec.door) as BuildingEntrance
		var outside: Vector2 = door.to_global(Vector2(0,80)) if door else Vector2(5570,5870) if boss_retake else Vector2(5515,5870)
		player.global_position = outside
		player.velocity = Vector2.ZERO
		player.reset_physics_interpolation()
		player.get_node("Camera").remove_meta("compact_interior")
		player.get_node("Camera").reset_smoothing()
		await physics_frames(60)
		if maciota_exterior_retake:
			var photo_camera := player.get_node("Camera") as Camera2D
			photo_camera.set_process(false)
			photo_camera.set_physics_process(false)
			photo_camera.position_smoothing_enabled = false
			photo_camera.global_position = door.global_position+Vector2(0,-75)
			print("MACIOTA_RETAKE door=",door.global_position," camera=",photo_camera.global_position," garage=",world.get_node("District/Garage").global_position," business=",world.get_node("District/Garage").business_name)
			await create_timer(4.2).timeout
			await physics_frames(5)
			await shot("retake-exterior-maciota")
			continue
		if boss_retake: await create_timer(4.2).timeout
		if not fire_interior_retake and not boss_ablate and not fire_ablate and not fire_district_ablate and not fire_exterior_control:
			await shot(label+"-exterior-"+id)
			await measure(label,id+"-exterior")
		if id=="boss":
			room.build_interior()
			player.global_position = room.spawn_point.global_position
			room.set_npc_rendering_active(true)
			if room.get("inline_mode")!=true: manager._frame_interior_camera(player,room.get_camera_rect())
		elif room.get("inline_mode")==true:
			player.global_position = room.spawn_point.global_position
		else:
			manager._on_exterior_destination_requested(door,player,door.destination_id,null,&"",room,room.spawn_point)
		player.velocity = Vector2.ZERO
		player.reset_physics_interpolation()
		player.get_node("Camera").reset_smoothing()
		await physics_frames(90 if fire_interior_retake else 60)
		if OS.get_cmdline_user_args().has("--warm-interior"):
			await create_timer(25.0).timeout
		if boss_ablate:
			var boss_view: SubViewport = room.showroom.viewport_3d
			var original_size: Vector2i = boss_view.size
			boss_view.size = Vector2i(2,2)
			await physics_frames(8)
			print("BOSS_ABLATE_VIEW size=",boss_view.size," mode=",boss_view.render_target_update_mode)
			await measure("ablate",id+"-interior")
			boss_view.size = original_size
			await physics_frames(60)
			print("BOSS_RECOVER_VIEW size=",boss_view.size," mode=",boss_view.render_target_update_mode)
			await measure("recover",id+"-interior")
			continue
		if fire_ablate:
			var fire_view: SubViewport = room.viewport_3d
			var fire_original_size: Vector2i = fire_view.size
			fire_view.size = Vector2i(2,2)
			await physics_frames(8)
			print("FIRE_ABLATE_VIEW size=",fire_view.size," mode=",fire_view.render_target_update_mode)
			await measure("ablate",id+"-interior")
			fire_view.size = fire_original_size
			await physics_frames(60)
			print("FIRE_RECOVER_VIEW size=",fire_view.size," mode=",fire_view.render_target_update_mode)
			await measure("recover",id+"-interior")
			continue
		if fire_district_ablate:
			var north_district: CanvasItem = world.get_node("NorthDistrict")
			north_district.hide()
			await physics_frames(60)
			print("FIRE_DISTRICT_ABLATE visible=",north_district.visible)
			await measure("ablate-district",id+"-interior")
			north_district.show()
			await physics_frames(60)
			print("FIRE_DISTRICT_RECOVER visible=",north_district.visible)
			await measure("recover-district",id+"-interior")
			continue
		if fire_exterior_control:
			await measure("paired",id+"-interior")
			player.global_position = outside
			player.velocity = Vector2.ZERO
			player.reset_physics_interpolation()
			player.get_node("Camera").reset_smoothing()
			await physics_frames(90)
			print("FIRE_PAIRED_EXTERIOR room=",room.sprite_3d.visible," facade=",room.inline_facade.inline_cutaway," player=",player.global_position)
			await measure("paired",id+"-exterior")
			continue
		if fire_interior_retake:
			print("FIRE_RETAKE_GATE ",room._gate_amounts," door=",room.inline_entrances[1]._door_open," player=",player.global_position)
			print("FIRE_RETAKE_FACADES ",room.inline_entrances[0].get_node("Facade").visible," ",room.inline_entrances[1].get_node("Facade").visible," ",room.inline_entrances[2].get_node("Facade").visible)
			await create_timer(4.2).timeout
		await shot(label+"-interior-"+id)
		if fire_interior_retake:
			if measure_fire_final or measure_fire_confirm: await measure("confirm" if measure_fire_confirm else "final",id+"-interior")
		if not fire_interior_retake: await measure(label,id+"-interior")
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
	print("COMPLEX SHOT ",path)

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
	var elapsed := float(previous-start)/1000000.0
	var result := {"scenario":scenario,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":root.size,"seconds":elapsed,"fps":float(samples.size())/elapsed,"p95_ms":sorted[int((sorted.size()-1)*.95)],"p99_ms":sorted[int((sorted.size()-1)*.99)],"over_33_ms":sorted.filter(func(v): return v>33.3).size(),"over_66_ms":sorted.filter(func(v): return v>66.7).size()}
	var file := FileAccess.open(OS.get_temp_dir().path_join(OUTPUT_DIR).path_join(label+"-"+scenario+".json"),FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(result,"  "))
		file.close()
	print("COMPLEX MEASURE ",JSON.stringify(result))
