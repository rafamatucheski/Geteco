extends SceneTree

const PLACES := preload("res://world/places/PlaceCatalog.gd")
var world: Node3D
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("WEAPON_WALKIN PASS " if ok else "WEAPON_WALKIN FAIL ") + label)
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
	var folder := OS.get_temp_dir().path_join("geteco-v2-weapon-walkin-0923")
	DirAccess.make_dir_recursive_absolute(folder)
	await RenderingServer.frame_post_draw
	var path := folder.path_join(label + ".png")
	check(root.get_texture().get_image().save_png(path) == OK, "capture " + path)

func check_branch(id: String) -> void:
	var session = world.session
	var definition: Dictionary = PLACES.get_definition(id)
	var door_z := 5.8 if id == "harbor_ammunation" else 2.7
	var door: Vector3 = definition.exterior_position + Vector3(0, 0, door_z)
	world.production.region.set_focus(door)
	world.player.teleport(door + Vector3(0, 0.08, 1.12))
	world.camera.heading = 0.0
	world.camera.initialized = false
	await frames(8)
	await capture(id + "-exterior")
	check(session.nearest().get("id", "") != "enter", id + ": no E entrance action")
	var initial_size: float = world.camera.size
	Input.action_press("move_up")
	var zoom_observed := false
	var zoom_captured := false
	for frame in 30:
		await physics_frame
		zoom_observed = zoom_observed or (world.camera._store_focus_active and world.camera.size < initial_size - 0.05)
		if not zoom_captured and "--capture" in OS.get_cmdline_user_args() and world.camera._store_focus_active and world.camera._store_focus_elapsed >= 0.30:
			zoom_captured = true
			await capture(id + "-zoom")
	Input.action_release("move_up")
	if "--capture" in OS.get_cmdline_user_args() and not zoom_captured:
		for frame in 45:
			await physics_frame
			if world.camera._store_focus_active and world.camera._store_focus_elapsed >= 0.30:
				await capture(id + "-zoom")
				break
	check(zoom_observed, id + ": approach zoom begins")
	check(await wait_until(func(): return session.state.place_id == id and is_instance_valid(session.room), 180), id + ": walking enters real shop")
	if session.state.place_id != id: return
	await capture(id + "-interior")
	check(not world.camera._store_focus_active and world.camera.locked, id + ": room camera takes over")
	world.player.teleport(session.room.interaction_points.service + Vector3.UP * 0.08)
	await frames(5)
	check(session.nearest().get("id", "") == "service", id + ": E still serves at counter")
	world.player.teleport(session.room.exit_position + Vector3(0, 0.08, -0.53))
	await frames(5)
	check(session.nearest().get("id", "") != "exit", id + ": no E exit action")
	Input.action_press("move_down")
	await frames(16)
	Input.action_release("move_down")
	check(await wait_until(func(): return session.state.place_id.is_empty() and not is_instance_valid(session.room), 180), id + ": walking exits shop")

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
	await create_timer(1.0).timeout
	if "--capture" in OS.get_cmdline_user_args(): world.hud.hide()
	await check_branch("harbor_ammunation")
	if world.production.travel("mountain"):
		if await wait_until(func(): return world.session.ready_for_play and world.session.state.region_id == "mountain" and not world.production.travel_busy, 600):
			await check_branch("mountain_gunshop")
		else: check(false, "mountain travel ready")
	else: check(false, "mountain travel admitted")
	Input.action_release("move_up")
	Input.action_release("move_down")
	print("WEAPON_WALKIN failures=", failures.size())
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
