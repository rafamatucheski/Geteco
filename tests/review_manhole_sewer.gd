extends SceneTree

const SEWER_SCRIPT := preload("res://world/harbor/sewer/HarborManholeSewer.gd")
const MANHOLE_POSITION := SEWER_SCRIPT.STREET_POSITION
const OUTPUT := "D:/geteco/artifacts/manhole-sewer/isolated"

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	print(("PASS " if condition else "FAIL ") + message)
	if not condition:
		failures.append(message)

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(OUTPUT.path_join(name + ".png"))
	check(error == OK, name + " capture saved")

func wait_for_state(sewer: Node, expected: int) -> bool:
	var deadline := Time.get_ticks_msec() + 8000
	var first_tick := Time.get_ticks_msec()
	var frames := 0
	var max_frame := 0
	var previous_tick := first_tick
	while sewer.state != expected and Time.get_ticks_msec() < deadline:
		await process_frame
		frames += 1
		max_frame = maxi(max_frame, Time.get_ticks_msec() - previous_tick)
		previous_tick = Time.get_ticks_msec()
	print("SEWER_WAIT frames=", frames, " ms=", Time.get_ticks_msec() - first_tick, " max_frame_ms=", max_frame)
	if sewer.state != expected and OS.get_cmdline_user_args().has("--diagnose-return"):
		# Diagnostic observation only; the original 8-second assertion stays failed.
		var diagnostic_end := Time.get_ticks_msec() + 12000
		while sewer.state != expected and Time.get_ticks_msec() < diagnostic_end:
			await process_frame
		print("SEWER_DIAG_FINAL ", sewer.get_runtime_stats())
		return false
	return sewer.state == expected

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("MANHOLE_REVIEW requires a real renderer")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.get_node("SaveManager").clear_pending_save()
	var campaign := OS.get_cmdline_user_args().has("--campaign")
	root.get_node("SaveManager").set("_save_dir", OUTPUT.path_join("test-saves") + "/")
	root.get_node("SaveManager").set("_save_directory_ready", false)
	if campaign:
		root.get_node("CampaignState").set_campaign_flag(&"harbor_arrival_seen", true)
	var scene_path := "res://world/harbor/HarborGame.tscn" if campaign else "res://world/harbor/HarborPreview.tscn"
	var world: Node2D = load(scene_path).instantiate()
	print("SEWER_REVIEW_SCENE ", scene_path, " script=", world.get_script().resource_path)
	world.review_mode = false
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 60000
	while not world.world_build_ready and Time.get_ticks_msec() < deadline:
		await process_frame
	check(world.world_build_ready, "real harbor review scene is ready")
	if not world.world_build_ready:
		quit(1)
		return
	if campaign:
		while not world.gameplay_ready and Time.get_ticks_msec() < deadline:
			await process_frame
		check(world.gameplay_ready, "production HarborGame gameplay initialization finished")
		if not world.gameplay_ready:
			quit(1)
			return
	world.call("_walk")
	var player := world.get_node("Player") as CharacterBody2D
	var sewer: Node2D = world.get_node_or_null("Interiors/InteriorSpaces/PoliceManholeSewer")
	if sewer == null:
		sewer = SEWER_SCRIPT.new()
		sewer.name = "PoliceManholeSewer"
		sewer.position = MANHOLE_POSITION
		world.get_node("Interiors/InteriorSpaces").add_child(sewer)
	var query := PhysicsShapeQueryParameters2D.new()
	var clearance := CircleShape2D.new()
	clearance.radius = 22.0
	query.shape = clearance
	query.transform.origin = MANHOLE_POSITION
	query.collision_mask = 1
	await physics_frame
	var obstructions := player.get_world_2d().direct_space_state.intersect_shape(query)
	check(obstructions.is_empty(), "cover footprint is clear of exterior solids")
	for hit in obstructions:
		print("MANHOLE_OBSTRUCTION ", hit.collider.get_path())
	clearance.radius = 13.0
	for step in range(5):
		query.transform.origin = MANHOLE_POSITION + SEWER_SCRIPT.COVER_SLIDE * float(step) / 4.0
		check(player.get_world_2d().direct_space_state.intersect_shape(query).is_empty(), "sliding cover clears street solids at step " + str(step))
		query.transform.origin += SEWER_SCRIPT.COVER_GRIP
		check(player.get_world_2d().direct_space_state.intersect_shape(query).is_empty(), "Dante drag path clears street solids at step " + str(step))
	player.global_position = MANHOLE_POSITION
	await physics_frame
	var police_door := world.get_node("District/Police/Entrance")
	check(not police_door.is_actor_in_range(player), "cover interaction does not compete with the police entrance")
	player.global_position = MANHOLE_POSITION + Vector2(-22.0, 2.0)
	player.velocity = Vector2.ZERO
	var camera := player.get_node("Camera") as Camera2D
	camera.make_current()
	camera.reset_smoothing()
	await create_timer(0.8).timeout
	check(player.global_position.distance_to(MANHOLE_POSITION) < 70.0, "cover is reachable beside Harbor Patrol")
	await capture("surface-near-police")
	check(sewer.request_interaction(player), "review starts the authored entry")
	await create_timer(0.8).timeout
	await capture("cover-dragging")
	await create_timer(2.15).timeout
	await capture("ladder-first-step")
	await create_timer(0.55).timeout
	await capture("ladder-mid-descent")
	await create_timer(0.55).timeout
	await capture("ladder-last-step")
	check(await wait_for_state(sewer, SEWER_SCRIPT.State.INSIDE), "rendered entry reaches the sewer")
	camera.reset_smoothing()
	await create_timer(0.6).timeout
	await capture("sewer-entry")
	player.equip_weapon("pistol")
	player.weapon_ammo["pistol"] = {"clip": 10, "reserve": 30}
	var crime_before: int = root.get_node("WantedManager").crime_points
	var mouse := InputEventMouseMotion.new()
	var aim_at := player.global_position + Vector2(85, 0)
	mouse.position = player.get_viewport().get_canvas_transform() * aim_at
	mouse.global_position = mouse.position
	Input.parse_input_event(mouse)
	await physics_frame
	var fire := InputEventMouseButton.new()
	fire.button_index = MOUSE_BUTTON_LEFT
	fire.position = mouse.position
	fire.pressed = true
	Input.parse_input_event(fire)
	await create_timer(0.18).timeout
	fire.pressed = false
	Input.parse_input_event(fire)
	check(player.weapon_ammo["pistol"].clip == 9, "native mouse input fires underground")
	check(root.get_node("WantedManager").crime_points == crime_before, "rendered underground shot does not alert street police")
	check(player.get_world_2d() != world.get_world_2d(), "rendered gameplay uses a separate physics world")
	player.global_position = sewer.to_global(SEWER_SCRIPT.SECRET_POSITION + Vector2(-72.0, 10.0))
	player.velocity = Vector2.ZERO
	camera.reset_smoothing()
	await create_timer(0.8).timeout
	await capture("sewer-secret-chamber")
	player.global_position = sewer.global_position
	player.velocity = Vector2.ZERO
	camera.reset_smoothing()
	await process_frame
	var interact := InputEventKey.new()
	interact.physical_keycode = KEY_E
	interact.pressed = true
	Input.parse_input_event(interact)
	check(await wait_for_state(sewer, SEWER_SCRIPT.State.SURFACE), "rendered exit closes the cover")
	print("SEWER_RETURN_DIAGNOSTIC ", sewer.get_runtime_stats(), " player=", player.global_position, " mode=", sewer.process_mode, " paused=", paused, " scale=", Engine.time_scale)
	await create_timer(0.4).timeout
	await capture("surface-after-return")
	world.queue_free()
	await process_frame
	await process_frame
	print("MANHOLE_REVIEW failures=", failures)
	quit(1 if not failures.is_empty() else 0)
