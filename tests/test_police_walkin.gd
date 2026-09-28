extends SceneTree

const PLACES := preload("res://world/places/PlaceCatalog.gd")
var world: Node3D
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("POLICE_WALKIN PASS " if ok else "POLICE_WALKIN FAIL ") + label)
	if not ok:
		failures.append(label)
		push_error(label)

func frames(count: int) -> void:
	for i in count: await physics_frame

func wait_until(predicate: Callable, count: int) -> bool:
	for i in count:
		if predicate.call(): return true
		await physics_frame
	return false

func capture(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": return
	var folder := OS.get_temp_dir().path_join("geteco-police-walkin-0924")
	DirAccess.make_dir_recursive_absolute(folder)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder.path_join(label + ".png")) == OK, "capture " + label)

func find_facade() -> Node3D:
	for candidate in get_nodes_in_group("v2_walkin_facade"):
		if candidate.get_meta("place_id", "") == "harbor_police": return candidate
	return null

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args() or "--skip-arrival" not in OS.get_cmdline_user_args():
		push_error("Run with --no-save --skip-arrival")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	world.set_meta("skip_traffic_yield", true)
	root.add_child(world)
	if not await wait_until(func(): return world.session != null and world.session.ready_for_play and world.production.ready_for_play, 1800):
		check(false, "world ready")
		quit(1)
		return
	var session = world.session
	var definition: Dictionary = PLACES.get_definition("harbor_police")
	var door: Vector3 = session.weapon_shop_entrance._door_position("harbor_police", definition)
	world.production.region.set_focus(door)
	world.player.teleport(door + Vector3(0, .08, 12.2))
	world.camera.heading = 0.0
	world.camera.initialized = false
	await wait_until(func(): return is_instance_valid(find_facade()), 180)
	var facade: Node3D = find_facade()
	check(is_instance_valid(facade), "real precinct facade streamed")
	if not is_instance_valid(facade):
		quit(1)
		return
	# Streaming mounts the facade before PhysicsServer registers its shapes.
	await frames(2)
	check(is_zero_approx(facade.open_amount), "police doors start closed")
	var vestibule_point := door - Vector3(0, 0, .35) + Vector3.UP * .14
	check(not session.position_clear(vestibule_point), "closed doors block the full actor")
	world.player.teleport(door + Vector3(0, .08, 2.0))
	await frames(28)
	check(facade.open_amount > .9, "proximity opens both physical doors")
	check(session.position_clear(vestibule_point), "open vestibule admits the full actor")
	check(session.nearest().get("id", "") != "enter", "entry requires no E action")
	await capture("exterior")
	var exterior_size: float = world.camera.size
	Input.action_press("move_up")
	var zoom_in := false
	var zoom_frame := false
	for i in 48:
		await physics_frame
		zoom_in = zoom_in or (world.camera._store_focus_active and world.camera.size < exterior_size - .05)
		if not zoom_frame and world.camera._store_focus_active and world.camera._store_focus_elapsed > .28:
			zoom_frame = true
			await capture("zoom-in")
		if session.state.place_id == "harbor_police": break
	Input.action_release("move_up")
	check(zoom_in, "exterior camera zooms toward precinct door")
	check(await wait_until(func(): return session.state.place_id == "harbor_police" and is_instance_valid(session.room), 180), "walking crosses into precinct")
	if session.state.place_id == "harbor_police":
		await frames(4)
		check(absf(world.camera.size - 16.0) < .01 and world.camera.locked, "interior has closer stable framing")
		check(session.room_npcs.size() == session.room.definition.npcs.size(), "resident officers remain installed")
		check(session.position_clear(session.room.spawn_position + Vector3.UP * .04), "interior spawn is clear")
		await capture("interior")
		world.player.teleport(session.room.exit_position + Vector3(0, .08, -.53))
		await frames(5)
		check(session.nearest().get("id", "") != "exit", "exit requires no E action")
		Input.action_press("move_down")
		await frames(16)
		Input.action_release("move_down")
		check(await wait_until(func(): return session.state.place_id.is_empty() and not is_instance_valid(session.room), 180), "walking exits at the same door")
		check(world.player.global_position.distance_to(definition.return_position) < 1.0, "player returns beside precinct door")
		var zoom_out := false
		for i in 40:
			await physics_frame
			zoom_out = zoom_out or (world.camera._store_focus_active and world.camera.size > 11.05)
			if i == 16: await capture("zoom-out")
		check(zoom_out and not world.camera._store_focus_active, "exterior camera zooms back out")
		check(not world.player.input_locked, "movement returns after zoom-out")
		await capture("returned")
	Input.action_release("move_up")
	Input.action_release("move_down")
	print("POLICE_WALKIN failures=", failures.size())
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
