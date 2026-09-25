extends "res://tests/capture/video_review_interiors.gd"
## Follow-up photographs for final transition fixes. No FPS conclusions.

func run() -> void:
	if DisplayServer.get_name() == "headless" or not "--no-save" in OS.get_cmdline_user_args():
		quit(2)
		return
	capture_prefix = "final-"
	report_filename = "final-captures.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-prefix="): capture_prefix = arg.trim_prefix("--capture-prefix=")
		if arg.begins_with("--capture-report="): report_filename = arg.trim_prefix("--capture-report=")
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_dispatch", true)
	root.add_child(world)
	current_scene = world
	for frame in 4800:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		failures.append("Main failed to start")
		await finish()
		return
	await wait_startup_curtain()
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 1
	world.session.weather.weather_timer = 99999.0
	await frames(15)
	# A tighter inspection camera, confined to this capture process.
	var ordinary_size: float = world.camera.target_size
	world.camera.target_size = 8.0
	world.camera.size = 8.0
	await motorcycle_theft()
	world.camera.target_size = ordinary_size
	world.camera.size = ordinary_size
	if world.driving.occupied:
		await finish()
		return
	world.session.state.grant_weapon("pistol")
	world.session.state.equip_weapon("pistol")
	await frames(3)
	if await enter("maciota"):
		await capture("garage-first-render")
		await frames(15)
		await capture("garage-settled")
		if not await leave("maciota"):
			await finish()
			return
	if await enter("harbor_bank"):
		await bank_occlusion_pair()
		if not await leave("harbor_bank"):
			await finish()
			return
	if await enter("harbor_ammunation"):
		world.player.automatic_direction = Vector3(0, 0, -1)
		await frames(125)
		world.player.automatic_direction = Vector3.ZERO
		await capture("ammo-counter-service")
		# Call the actual automatic-exit helper, including the exterior zoom.
		world.player.teleport(world.session.room.exit_position + Vector3.UP * .05)
		await frames(3)
		world.session.weapon_shop_entrance._leave()
		await capture_zoom_sequence()
		if not world.session.state.place_id.is_empty(): failures.append("zoom exit failed")
	await finish()

func bank_occlusion_pair() -> void:
	# Let bank residents complete admission before choosing player clearance.
	await frames(20)
	var counter := world.session.room.model.find_child("CounterTop_-4_5", true, false) as MeshInstance3D
	if counter == null:
		failures.append("bank occlusion counter not found")
		return
	var bounds: AABB = counter.global_transform * counter.get_aabb()
	for side in ["front", "behind"]:
		var admitted := false
		for margin in [.65, .85, 1.05, 1.4, 1.8]:
			var point := Vector3(bounds.get_center().x, world.session.room.global_position.y + .08, bounds.end.z + margin if side == "front" else bounds.position.z - margin)
			if not world.session.position_clear(point): continue
			world.player.teleport(point)
			await frames(10)
			await capture("bank-occlusion-" + side)
			admitted = true
			break
		if not admitted: failures.append("no admitted bank occlusion position: " + side)

func capture_zoom_sequence() -> void:
	var began := Time.get_ticks_usec()
	var times := [0.0, .15, .3, .55, .8]
	var pending: Array[Dictionary] = []
	for index in times.size():
		while float(Time.get_ticks_usec() - began) / 1000000.0 < times[index]: await process_frame
		await RenderingServer.frame_post_draw
		# Encode PNGs only after the animation completes. GPU readback remains
		# instrumentation, so these photographs are not a timing benchmark.
		pending.append({"image": root.get_texture().get_image(), "record": {"label": capture_prefix + "ammo-zoom-%02d" % index, "elapsed_ms": float(Time.get_ticks_usec() - began) / 1000.0, "camera_size": world.camera.size, "camera_position": str(world.camera.global_position), "player_position": str(world.player.global_position), "place": world.session.state.place_id, "prompt": world.session.prompt.text}})
	for item in pending:
		var row: Dictionary = item.record
		if item.image.save_png(OUTPUT + row.label + ".png") != OK: failures.append(row.label)
		records.append(row)
		print("VIDEO_ZOOM ", JSON.stringify(row))
