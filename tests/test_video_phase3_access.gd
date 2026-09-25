extends SceneTree
## Harbor public walk-up doors. Capture the original geometry with --before.
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const IDS := ["harbor_clothing", "harbor_fuel", "harbor_hospital"]
var world: Node3D
var failures: Array[String] = []
var checks := 0
var captured: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("VIDEO_ACCESS3 PASS " if ok else "VIDEO_ACCESS3 FAIL ") + label)
	if not ok: failures.append(label)

func frames(count: int) -> void:
	for _i in count: await physics_frame

func wait_until(predicate: Callable, count := 240) -> bool:
	for _i in count:
		if predicate.call(): return true
		await physics_frame
	return false

func _run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args() or "--skip-arrival" not in OS.get_cmdline_user_args():
		push_error("Requires --no-save --skip-arrival")
		quit(2)
		return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	root.add_child(world)
	if not await wait_until(func(): return world.session != null and world.session.ready_for_play, 1800):
		check(false, "Main ready")
		quit(1)
		return
	if "--capture" in OS.get_cmdline_user_args():
		check(await wait_until(func():
			for child in world.get_children():
				if child.get_script() == preload("res://runtime/StartupCurtain.gd"): return false
			return true
		, 600), "startup curtain finishes before photographs")
	check(world.production.no_save, "isolated from personal save")
	world.session.weather.time_of_day = .38
	world.session.state.world_state.time = .38
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 99999.0
	world.session.weather._update()
	if "--fire-smoke" in OS.get_cmdline_user_args():
		await _fire_smoke()
	else:
		for id in IDS:
			if "--before" in OS.get_cmdline_user_args(): await _before(id)
			else: await _check_access(id)
	print("VIDEO_ACCESS3 checks=", checks, " failures=", failures.size())
	world.queue_free()
	await frames(6)
	quit(0 if failures.is_empty() else 1)

func door_position(id: String, definition: Dictionary) -> Vector3:
	var z := 120.0 / (18.0 * .76822128) if id == "harbor_hospital" else 180.0 / 32.0 - .72
	return definition.exterior_position + Vector3(0, 0, z)

func _fire_smoke() -> void:
	var id := "harbor_fire_station"
	var session = world.session
	var access = session.weapon_shop_entrance
	var definition := PLACES.get_definition(id)
	var door: Vector3 = definition.exterior_position + PLACES.FIRE_STATION_DOOR_OFFSET
	session.controller.region.set_focus(door)
	world.player.teleport(door + Vector3(0, .08, 12))
	world.camera.heading = 0
	world.camera.initialized = false
	var facade: Node3D
	for _i in 240:
		for node in get_nodes_in_group("v2_walkin_facade"):
			if node.get_meta("place_id", "") == id: facade = node
		if is_instance_valid(facade): break
		await physics_frame
	check(is_instance_valid(facade), "fire facade streamed")
	if not is_instance_valid(facade): return
	await frames(20)
	var sweep := Transform3D(world.player.global_basis, door + Vector3(0, .08, .8))
	check(is_zero_approx(facade.open_amount) and world.player.test_move(sweep, Vector3(0, 0, -1)), "fire closed shutter blocks whole body")
	world.player.teleport(door + Vector3(0, .08, 2))
	await frames(24)
	check(facade.open_amount > .99 and not world.player.test_move(sweep, Vector3(0, 0, -1)), "fire proximity opens physical passage")
	check(session.nearest().get("id", "") != "enter" and session.state.place_id.is_empty(), "fire approach has no E and does not transfer while standing")
	check(await _walk_in(id), "fire walking admits player")
	if session.state.place_id != id: return
	check(world.camera.locked and not world.player.input_locked and session.position_clear(world.player.global_position + Vector3.UP * .04), "fire spawn camera and controls valid")
	var desired: Vector3 = session.return_point
	world.player.teleport(session.room.exit_position + Vector3(0, .08, -.9))
	await frames(3)
	check(session.nearest().get("id", "") != "exit", "fire exit has no E action")
	Input.action_press("move_down")
	var exited := await wait_until(func(): return session.state.place_id.is_empty())
	Input.action_release("move_down")
	check(exited, "fire walking exits automatically")
	if not exited: return
	check(world.camera._store_focus_active, "fire exit zoom begins")
	check(await wait_until(func(): return not access._leaving), "fire exit zoom completes")
	check(not world.player.input_locked and not world.camera._store_focus_active and _returned_to_access(id, desired) and session.position_clear(world.player.global_position + Vector3.UP * .04), "fire safe return and released control")
	await frames(15)
	check(session.state.place_id.is_empty(), "fire no automatic return loop")

func _before(id: String) -> void:
	var session = world.session
	var definition: Dictionary = PLACES.get_definition(id)
	var door := door_position(id, definition)
	session.controller.region.set_focus(door)
	world.player.teleport(door + Vector3(0, .08, 2))
	world.camera.heading = 0.0
	world.camera.initialized = false
	await frames(40)
	await capture(id + "-approach")
	check(await session.enter_place(id, false, id), id + " original interior opens")
	await frames(10)
	await capture(id + "-inside")
	check(await session.leave_place(), id + " original exterior return")
	await frames(10)

func _check_access(id: String) -> void:
	var session = world.session
	var access = session.weapon_shop_entrance
	var definition: Dictionary = PLACES.get_definition(id)
	var door := door_position(id, definition)
	var start := door + Vector3(0, .08, 2)
	session.controller.region.set_focus(door)
	world.player.teleport(door + Vector3(0, .08, 9.5))
	world.camera.heading = 0.0
	world.camera.initialized = false
	await frames(35)
	var facade: Node3D
	for node in get_nodes_in_group("v2_walkin_facade"):
		if node.get_meta("place_id", "") == id: facade = node
	check(is_instance_valid(facade), id + " facade streamed")
	if not is_instance_valid(facade): return
	check(is_zero_approx(facade.open_amount), id + " leaf starts closed")
	check(not session.position_clear(door + Vector3.UP * .08), id + " closed leaf blocks full actor")
	var sweep := Transform3D(world.player.global_basis, door + Vector3(0, .08, .8))
	check(world.player.test_move(sweep, Vector3(0, 0, -1)), id + " closed leaf blocks swept walking body")
	await capture(id + "-door-closed")
	if "--closed-only" in OS.get_cmdline_user_args(): return
	world.player.teleport(start)
	await frames(24)
	check(facade.open_amount > .99, id + " proximity opens real leaf")
	check(session.position_clear(door + Vector3.UP * .08), id + " open portal admits full actor")
	check(not world.player.test_move(sweep, Vector3(0, 0, -1)), id + " open vestibule admits swept walking body")
	check(session.nearest().get("id", "") != "enter", id + " entry has no E action")
	check(session.state.place_id.is_empty(), id + " proximity alone never transfers")
	await capture(id + "-approach")
	if id == "harbor_hospital":
		check(is_equal_approx(facade.door_amount, 1.0), "ambulance door stays independent and open")
	# Exercise the actual helper while an unrelated UI owns movement.
	world.player.teleport(door + Vector3(0, .08, .4))
	world.player.velocity = Vector3.FORWARD * 2
	session.modal = true
	access.update(.016)
	check(not access._entering, id + " modal blocks admission")
	session.modal = false
	world.player.velocity = Vector3.RIGHT * 2
	access.update(.016)
	check(not access._entering, id + " lateral movement never transfers")
	world.player.teleport(start)
	await frames(2)
	var entered := await _walk_in(id)
	check(entered, id + " walking enters without E")
	if not entered:
		print("VIDEO_ACCESS3 entry blocked at ", world.player.global_position, " door=", door, " notice=", session.notice.text)
		return
	await frames(4)
	check(world.camera.locked and not world.player.input_locked, id + " interior camera and controls restored")
	check(session.position_clear(world.player.global_position + Vector3.UP * .04), id + " spawn fits full actor")
	check(not session.marker.visible, id + " automatic exit has no door marker")
	await capture(id + "-inside")
	await _check_service(id)
	var expected_return: Vector3 = session.return_point
	world.player.teleport(session.room.exit_position + Vector3(0, .08, -.9))
	await frames(3)
	check(session.nearest().get("id", "") != "exit", id + " exit has no E action")
	_print_return_blockers(id, expected_return)
	Input.action_press("move_down")
	var exited := await wait_until(func(): return session.state.place_id.is_empty())
	Input.action_release("move_down")
	check(exited, id + " walking exits without E")
	if not exited:
		print("VIDEO_ACCESS3 exit blocked at ", world.player.global_position, " exit=", session.room.exit_position)
		return
	check(world.camera._store_focus_active and world.player.input_locked, id + " exit starts close before first render")
	await capture(id + "-exit-zoom")
	check(await wait_until(func(): return not access._leaving), id + " exit zoom completes")
	check(not world.player.input_locked and not world.camera._store_focus_active, id + " exit releases control and camera")
	check(_returned_to_access(id, expected_return), id + " returns to original access or its authored clear offsets")
	check(session.position_clear(world.player.global_position + Vector3.UP * .04), id + " returned body remains clear of exterior solids")
	await capture(id + "-returned")
	await frames(12)
	check(session.state.place_id.is_empty(), id + " no entry exit ping-pong")
	world.player.teleport(start)
	await frames(3)
	check(await _walk_in(id), id + " deliberate re-entry after retreat")
	if session.state.place_id == id:
		await session.leave_place()
		await frames(4)
	await _check_cancel(id, door)

func _returned_to_access(id: String, desired: Vector3) -> bool:
	# The session can step around a pedestrian blocking the authored return.
	# Accept only its documented candidates, not an arbitrary radius.
	var outward := desired - Vector3(PLACES.get_definition(id).exterior_position)
	outward.y = 0
	outward = outward.normalized()
	var side := Vector3(-outward.z, 0, outward.x)
	for offset in [Vector3.ZERO, outward * .75, outward * 1.5, side * .8 + outward * .75, -side * .8 + outward * .75]:
		if world.player.global_position.distance_to(desired + offset) < .2:
			print("VIDEO_ACCESS3 return ", id, " offset=", offset, " actual=", world.player.global_position)
			return true
	print("VIDEO_ACCESS3 unexpected return ", id, " expected=", desired, " actual=", world.player.global_position)
	return false

func _print_return_blockers(id: String, desired: Vector3) -> void:
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = .32
	shape.height = 1.7
	query.shape = shape
	query.collision_mask = 7
	query.transform = Transform3D(Basis.IDENTITY, desired + Vector3.UP * .98)
	query.exclude = [world.player.get_rid()]
	for hit in world.get_world_3d().direct_space_state.intersect_shape(query):
		print("VIDEO_ACCESS3 return blocker ", id, " ", hit.collider.get_path())

func _walk_in(id: String) -> bool:
	Input.action_press("move_up")
	var zoom := false
	for _i in 180:
		await physics_frame
		zoom = zoom or world.camera._store_focus_active
		if world.camera._store_focus_active and world.camera._store_focus_elapsed > .2: await capture(id + "-entry-zoom")
		if world.session.state.place_id == id: break
	Input.action_release("move_up")
	check(zoom, id + " entry camera zooms toward actual door")
	return world.session.state.place_id == id

func _check_service(id: String) -> void:
	var session = world.session
	if id == "harbor_clothing":
		world.player.teleport(session.room.interaction_points.service + Vector3.UP * .08)
		await frames(3)
		check(session.nearest().get("id", "") == "service", "Union keeps functional counter interaction")
		check(session.interact() and session.modal, "Union E opens clothing service")
		session.close_menu()
	elif id == "harbor_hospital":
		world.player.teleport(session.room.to_global(Vector3(2, .08, -3.5)))
		await frames(3)
		check(session.nearest().get("target", "") == "hospital_triage", "hospital keeps triage interaction")
		check(session.interact() and session.dialogue_open, "hospital E opens triage dialogue")
		session.close_menu()
		world.gameplay.health = 75
		world.player.teleport(session.room.to_global(Vector3(2, .08, -1)))
		await frames(3)
		check(world.gameplay.health == 100 and session.services.hospital_cooldown > 0, "hospital walking pickup still heals")
	else:
		check(session.robberies._actors.size() == 1 and session.robberies._actors[0].health > 0, "convenience retains living interactive cashier")
		world.player.teleport(session.room.to_global(Vector3(4.6, .08, -1.8)))
		await frames(3)
		check(session.nearest().get("id", "") != "service", "convenience does not invent an unused service prompt")

func _check_cancel(id: String, door: Vector3) -> void:
	var session = world.session
	var access = session.weapon_shop_entrance
	world.player.teleport(door + Vector3(0, .08, .4))
	world.player.velocity = Vector3.FORWARD * 2
	access._blocked_entry_id = ""
	access._reentry_remaining = 0.0
	access.update(.016)
	check(access._entering, id + " cancellation starts real zoom")
	# Each newly added ID exercises a different owner that can interrupt zoom.
	if id == "harbor_clothing": session.modal = true
	elif id == "harbor_fuel": session.arrest_pending = true
	else: world.gameplay.health = 0
	access.update(.016)
	check(not world.camera._store_focus_active, id + " interrupt cancels focus immediately")
	session.modal = false
	session.arrest_pending = false
	world.gameplay.health = 100
	check(await wait_until(func(): return not access._entering), id + " cancelled request resolves")
	check(session.state.place_id.is_empty() and not world.player.input_locked, id + " cancelled request cannot restart or strand controls")

func capture(label: String) -> void:
	if captured.has(label) or "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": return
	captured[label] = true
	var folder := OS.get_temp_dir().path_join("geteco-video-phase3-access")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): folder = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(folder)
	await RenderingServer.frame_post_draw
	var phase := "before" if "--before" in OS.get_cmdline_user_args() else "after"
	check(root.get_texture().get_image().save_png(folder.path_join("phase3-access-" + phase + "-" + label + ".png")) == OK, "capture " + phase + " " + label)
