extends SceneTree
## Real walking through the three newly automatic doors; no personal save writes.
var world: Node3D
var failures: Array[String] = []
var checks := 0
var zoom_seen := false
var captured: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("VIDEO_ACCESS PASS " if ok else "VIDEO_ACCESS FAIL ") + label)
	if not ok: failures.append(label)

func frames(count: int) -> void:
	for _i in count: await physics_frame

func wait_until(predicate: Callable, count := 180) -> bool:
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
	var session = world.session
	check(world.production.no_save, "isolated from personal save")
	var places := ["port_boss_garage"] if "--access-remaining" in OS.get_cmdline_user_args() else ["harbor_bank", "maciota", "port_boss_garage"]
	for id in places:
		await _walk_place(id)
		if not session.state.place_id.is_empty(): break
	await _check_bank_closed()
	if "--access-remaining" not in OS.get_cmdline_user_args(): await _check_cancelled_zoom()
	print("VIDEO_ACCESS checks=", checks, " failures=", failures.size())
	world.queue_free()
	await frames(6)
	quit(0 if failures.is_empty() else 1)

func _walk_place(id: String) -> void:
	var session = world.session
	var access = session.weapon_shop_entrance
	var definition: Dictionary = access._definition_for(id)
	var door: Vector3 = access._door_position(id, definition)
	var inward: Vector3 = access._inward(id)
	var start := door - inward * 2.0 + Vector3.UP * .08
	var action := "move_left" if id == "port_boss_garage" else "move_up"
	session.controller.region.set_focus(door)
	world.player.teleport(door - inward * 12.0 + Vector3.UP * .08)
	world.camera.heading = 0.0
	world.camera.initialized = false
	await frames(35)
	if id == "harbor_bank":
		var facade: Node3D
		for node in get_nodes_in_group("v2_walkin_facade"):
			if node.get_meta("place_id", "") == id: facade = node
		check(is_instance_valid(facade), "bank real facade streamed")
		if is_instance_valid(facade):
			check(is_zero_approx(facade.open_amount), "bank door starts closed")
			check(not session.position_clear(door + Vector3.UP * .08), "closed bank door blocks full actor")
			await capture("bank-door-closed")
			world.player.teleport(start)
			await frames(24)
			check(facade.open_amount > .99, "bank proximity opens physical leaf")
			check(session.position_clear(door + Vector3.UP * .08), "open bank door leaves full actor clearance")
	else:
		world.player.teleport(start)
		await frames(12)
	check(session.nearest().get("id", "") != "enter", id + " has no E entry")
	check(session.state.place_id.is_empty(), id + " standing near door does not enter")
	await capture(id + "-approach")
	# Moving across the doorway must not transfer, even at the exact threshold.
	world.player.teleport(door - inward * .4 + Vector3.UP * .08)
	world.player.velocity = Vector3(-inward.z, 0, inward.x) * 3.0
	access.update(.016)
	check(not access._entering, id + " lateral motion does not enter")
	world.player.teleport(start)
	await frames(2)
	if id == "port_boss_garage":
		session.weather.time_of_day = 12.0 / 24.0
		session.state.world_state.time = 12.0 / 24.0
		Input.action_press(action)
		await frames(28)
		Input.action_release(action)
		check(session.state.place_id.is_empty() and not access._entering, "boss garage respects closed hours before zoom")
		check(session.nearest().get("id", "") != "enter", "closed garage never offers E entry")
		world.player.teleport(start)
		await frames(3)
		session.weather.time_of_day = 2.0 / 24.0
		session.state.world_state.time = 2.0 / 24.0
	await _walk_in(action, id)
	check(session.state.place_id == id, id + " real walking enters without E")
	if session.state.place_id != id:
		print("VIDEO_ACCESS failed entry position=", world.player.global_position, " door=", door, " velocity=", world.player.velocity, " notice=", session.notice.text)
		return
	check(zoom_seen, id + " entry zoom active before transfer")
	await frames(4)
	check(not world.player.input_locked and world.camera.locked, id + " interior control and camera restored")
	check(session.position_clear(world.player.global_position + Vector3.UP * .04), id + " interior spawn admits full actor")
	await capture(id + "-inside")
	if id == "maciota":
		check(not session.state.weapons_allowed() and not session.state.can_attack(), "Maciota remains weapon-free")
		check(session.room.maciota.get_meta("invulnerable", false) and session.room.mechanic.get_meta("invulnerable", false), "Maciota residents remain invulnerable")
		var prior_stage: String = session.state.intro.stage
		session.state.intro.stage = "meet_maciota"
		world.player.teleport(session.room.interaction_points.maciota + Vector3.UP * .08)
		await frames(3)
		check(session.nearest().get("id", "") == "maciota", "Maciota NPC still uses E conversation")
		check(session.marker.visible, "Maciota NPC objective marker stays visible")
		session.state.intro.stage = prior_stage
	var expected_return: Vector3 = session.return_point
	world.player.teleport(session.room.exit_position + Vector3(0, .08, -.9))
	await frames(3)
	check(session.nearest().get("id", "") != "exit", id + " has no E exit")
	Input.action_press("move_down")
	var exited := await wait_until(func(): return session.state.place_id.is_empty())
	Input.action_release("move_down")
	check(exited, id + " real walking exits without E")
	if not exited: return
	check(world.camera._store_focus_active and world.player.input_locked, id + " exit starts zoom with controlled movement")
	await capture(id + "-exit-zoom")
	check(await wait_until(func(): return not access._leaving), id + " exit zoom completes")
	check(not world.player.input_locked and not world.camera._store_focus_active, id + " exit releases camera and player")
	check(world.player.global_position.distance_to(expected_return) < .5, id + " returns to its original access")
	await capture(id + "-returned")
	await frames(12)
	check(session.state.place_id.is_empty(), id + " no automatic ping-pong")
	world.player.teleport(start)
	await frames(4)
	await _walk_in(action, id)
	check(session.state.place_id == id, id + " intentional re-entry works after retreat")
	if session.state.place_id == id:
		await session.leave_place()
		await frames(4)

func _walk_in(action: String, id: String) -> void:
	zoom_seen = false
	Input.action_press(action)
	for _i in 180:
		await physics_frame
		zoom_seen = zoom_seen or world.camera._store_focus_active
		if world.camera._store_focus_active and world.camera._store_focus_elapsed > .2:
			await capture(id + "-entry-zoom")
		if world.session.state.place_id == id: break
	Input.action_release(action)

func capture(label: String) -> void:
	if captured.has(label) or "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": return
	captured[label] = true
	var folder := OS.get_temp_dir().path_join("geteco-video-phase2-access")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): folder = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(folder)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder.path_join("phase2-access-" + label + ".png")) == OK, "capture " + label)

func _check_bank_closed() -> void:
	var session = world.session
	var access = session.weapon_shop_entrance
	var definition: Dictionary = access._definition_for("harbor_bank")
	var door: Vector3 = access._door_position("harbor_bank", definition)
	var previous: String = session.robberies.data.aftermath
	var previous_days: float = session.robberies.data.elapsed_days
	session.robberies.data.aftermath = "closed"
	session.robberies.data.elapsed_days = 0.0
	world.player.teleport(door + Vector3(0, .08, .4))
	world.player.velocity = Vector3.FORWARD * 2.0
	access._blocked_entry_id = ""
	access._reentry_remaining = 0.0
	access.update(.016)
	check(not access._entering and session.state.place_id.is_empty(), "investigation blocks bank before entry zoom")
	check(session.nearest().get("id", "") != "enter", "closed bank has no E entry")
	check(session.notice.text == "O banco está fechado para investigação.", "closed bank gives functional feedback")
	session.notice_time = 1.25
	access.update(.016)
	access.update(.016)
	check(is_equal_approx(session.notice_time, 1.25), "closed bank does not repeat feedback every frame")
	session.robberies.data.aftermath = previous
	session.robberies.data.elapsed_days = previous_days
	world.player.teleport(door + Vector3(0, .08, 2))
	access.update(.016)

func _check_cancelled_zoom() -> void:
	var session = world.session
	var access = session.weapon_shop_entrance
	var definition: Dictionary = access._definition_for("harbor_bank")
	var door: Vector3 = access._door_position("harbor_bank", definition)
	for reason in ["modal", "arrest", "death"]:
		world.player.teleport(door + Vector3(0, .08, .4))
		world.player.velocity = Vector3.FORWARD * 2.0
		access._blocked_entry_id = ""
		access._reentry_remaining = 0.0
		access.update(.016)
		check(access._entering, reason + " fixture begins real entry zoom")
		if reason == "modal": session.modal = true
		elif reason == "arrest": session.arrest_pending = true
		else: world.gameplay.health = 0
		access.update(.016)
		check(not world.camera._store_focus_active, reason + " cancels entry focus immediately")
		# Model the external owner completing before the zoom timer: the old
		# request must remain cancelled, even once gameplay is available again.
		session.modal = false
		session.arrest_pending = false
		world.gameplay.health = 100
		check(await wait_until(func(): return not access._entering), reason + " cancelled zoom resolves")
		check(session.state.place_id.is_empty() and not world.player.input_locked, reason + " cannot resume old entry or strand movement")
		check(not world.camera._store_focus_active, reason + " leaves no camera focus")
