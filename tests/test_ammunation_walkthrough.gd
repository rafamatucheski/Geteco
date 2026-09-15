extends "res://tests/test_ammunation_identity_navigation.gd"

func cross_threshold(player: Node2D, room: Node2D, entering: bool) -> void:
	var action := "move_up" if entering else "move_down"
	for i in 150:
		Input.action_press(action)
		await physics_frame
		if room.contains_point(player.global_position) == entering: break
	release_movement()

func run() -> void:
	_tag = "ammunation_walkthrough"
	arm_watchdog(240)
	isolate_saves(_tag)
	skip_onboarding_flags()
	seed(2718)
	var world := await boot_harbor(15)
	while not world.gameplay_ready: await process_frame
	root.size = Vector2i(1280,720)
	var player = world.get_node("Player")
	var room = world.get_node("Interiors").ammunation_interior
	var door = world.get_node("District/NorthFrontage2/AmmunationEntrance")
	var facade = door.get_parent().get_node("AmmunationBranchFacade")
	var baseline := "baseline" in OS.get_cmdline_user_args()
	player.global_position = door.global_position + Vector2(0,65)
	player.velocity = Vector2.ZERO
	player.get_node("Camera").reset_smoothing()
	await create_timer(3).timeout
	var output := "D:/geteco/artifacts/ammunation-walkthrough"
	if not ("functional" in OS.get_cmdline_user_args()):
		var samples: Array[float] = []
		var start := Time.get_ticks_usec()
		var previous := start
		while Time.get_ticks_usec()-start < 30000000:
			await process_frame
			var now := Time.get_ticks_usec()
			samples.append((now-previous)/1000.0)
			previous = now
		var total := (previous-start)/1000000.0
		var raw := samples.duplicate()
		samples.sort()
		var report := {"baseline":baseline,"gpu":RenderingServer.get_video_adapter_name(),"seconds":total,"frames":samples.size(),"fps":samples.size()/total,"p50":samples[int(samples.size()*.50)],"p95":samples[int(samples.size()*.95)],"p99":samples[int(samples.size()*.99)],"max":samples[-1],"over_33":samples.filter(func(v): return v>33.3).size(),"over_66":samples.filter(func(v): return v>66.7).size(),"samples_ms":raw}
		DirAccess.make_dir_recursive_absolute(output)
		FileAccess.open(output+ ("/before.json" if baseline else "/after.json"),FileAccess.WRITE).store_string(JSON.stringify(report))
		report.erase("samples_ms")
		print("PERFORMANCE ",JSON.stringify(report))
	if not baseline:
		if not ("mountain" in OS.get_cmdline_user_args()):
			for cycle in 3:
				check(await walk_to(player,door.global_position+Vector2(0,18),180,4),"Approach without interaction")
				await create_timer(.7).timeout
				check(facade.model.open_amount>.95,"Visible facade opens on approach")
				check(not room.contains_point(player.global_position),"Approach alone does not enter")
				if cycle == 0 and DisplayServer.get_name()!="headless":
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(output+"/open.png")
				await cross_threshold(player,room,true)
				await create_timer(.8).timeout
				check(room.contains_point(player.global_position),"Walking in enters cycle %d"%cycle)
				check(await walk_to(player,room.exit_door.global_position+Vector2(0,-15),180,3),"Reach inside threshold")
				await cross_threshold(player,room,false)
				await create_timer(.8).timeout
				check(player.global_position.distance_to(door.get_node("OutsideReturn").global_position)<10,"Walking out returns cycle %d"%cycle)
				check(not player.is_in_dialogue,"Movement restored")
			check(await walk_to(player,door.global_position+Vector2(0,100),180,5),"Walk away")
			await create_timer(1.5).timeout
			check(facade.model.open_amount<.01,"Visible door closes after departure")
		var mountain = preload("res://world/mountain_pass/MountainInteriorManager.gd").new()
		# This fixture lives outside the authored map. The production perimeter
		# otherwise returns the player to Harbor before they can reach this branch.
		world.get_node("WorldPerimeter").set_physics_process(false)
		mountain.position = Vector2(60000,0)
		world.add_child(mountain)
		while not mountain.region_ready: await process_frame
		var branch = preload("res://world/mountain_pass/MountainGunShopFacade.gd").new()
		branch.position = Vector2(48000,10000)
		world.add_child(branch)
		branch.install_entrance(mountain)
		room = mountain.ammunation_interior
		door = branch.entrance
		player.global_position = branch.to_global(branch.project_floor(Vector2(0,4.5)))
		player.velocity = Vector2.ZERO
		player.reset_physics_interpolation()
		player.get_node("Camera").global_position = player.global_position
		player.get_node("Camera").reset_smoothing()
		await physics_frames(8)
		await cross_threshold(player,room,true)
		await create_timer(.8).timeout
		if not room.contains_point(player.global_position):
			print("MOUNTAIN ENTRY DIAGNOSTIC ",{"player":player.global_position,"door":door.global_position,"velocity":player.velocity,"visible":player.visible,"control_disabled":player.is_control_disabled,"dialogue":player.is_in_dialogue,"busy":door._busy,"enabled":door.enabled,"tracked_actor":room.actor==player})
		check(room.contains_point(player.global_position),"Mountain walking entry")
		check(await walk_to(player,room.to_global(room.merchant_point),240,8),"Walk to merchant")
		await press_key(KEY_E)
		check(room.active and player.is_in_dialogue,"Merchant interaction still opens catalog")
		await press_key(KEY_ESCAPE)
		await walk_to(player,room.exit_door.global_position+Vector2(0,-15),180,3)
		await cross_threshold(player,room,false)
		await create_timer(.8).timeout
		check(player.global_position.distance_to(branch.to_global(branch.project_floor(Vector2(0,4.5))))<10,"Mountain walking exit returns to same branch")
	print("WALKTHROUGH: %d passed, %d failed"%[passed_count,failures.size()])
	world.queue_free()
	await process_frame
	cleanup_isolated_saves()
	quit(0 if failures.is_empty() else 1)


