extends "res://tests/test_video_phase3_access.gd"
## Finite functional smoke only; the user owns visual/FPS validation for this batch.

func _run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args() or "--skip-arrival" not in OS.get_cmdline_user_args():
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
	var access = world.session.weapon_shop_entrance
	var conventional := 0
	for entry in PLACES.access_points():
		if not PLACES.walkup_family(entry.id).is_empty():
			conventional += 1
			if not access.handles_place(entry.id): failures.append("unhandled " + entry.id)
	check(conventional == 19 and failures.is_empty(), "19 conventional access IDs registered")
	check(not access._entry_available("quayside_house"), "unowned residence rejected before camera lock")
	world.session.activities.residence.data.active_home = "westgate_garden"
	# One real traversal per facade family, plus both noncanonical shared-room origins.
	for id in ["westgate_garden", "cemetery_keeper", "mountain_cabin", "mountain_outfitters", "mountain_bunker", "ski_lodge", "lumberjack_shelter_2", "lumberjack_shelter_3"]:
		var only := ""
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--only="): only = arg.trim_prefix("--only=")
		if not only.is_empty() and id != only: continue
		if not await _smoke_access(id): break
	print("CONVENTIONAL_ACCESS checks=", checks, " failures=", failures)
	world.queue_free()
	await frames(6)
	quit(0 if failures.is_empty() else 1)

func _smoke_access(id: String) -> bool:
	var session = world.session
	var access = session.weapon_shop_entrance
	var definition: Dictionary = access._definition_for(id)
	var canonical: String = definition.get("place_id", id)
	if session.state.region_id != definition.region:
		world.production.travel(definition.region)
		if not await wait_until(func(): return session.ready_for_play and session.state.region_id == definition.region, 900):
			check(false, id + " region loads")
			return false
	var door: Vector3 = access._door_position(id, definition)
	session.controller.region.set_focus(door)
	world.player.teleport(door + Vector3(0, .08, 12))
	world.camera.heading = 0.0
	world.camera.initialized = false
	var facade: Node3D
	for _i in 240:
		for node in get_nodes_in_group("v2_walkin_facade"):
			if node.get_meta("place_id", "") == id: facade = node
		if is_instance_valid(facade): break
		await physics_frame
	if not is_instance_valid(facade):
		check(false, id + " real facade streamed")
		return false
	await frames(20)
	var sweep := Transform3D(Basis.IDENTITY, door + Vector3(0, .08, .8))
	check(is_zero_approx(facade.open_amount) and world.player.test_move(sweep, Vector3(0, 0, -1.1)), id + " closed leaf blocks walking body")
	world.player.teleport(door + Vector3(0, .08, 2))
	await frames(24)
	var collision := KinematicCollision3D.new()
	var obstructed: bool = world.player.test_move(sweep, Vector3(0, 0, -1.1), collision)
	if obstructed: print("ACCESS_BLOCKER ", id, " ", collision.get_collider().get_path(), " ", collision.get_position())
	check(facade.open_amount > .99 and not obstructed, id + " proximity opens physical passage")
	check(session.nearest().get("id", "") != "enter" and session.state.place_id.is_empty(), id + " no E or standing transfer")
	Input.action_press("move_up")
	var entered := await wait_until(func(): return session.state.place_id == canonical, 180)
	Input.action_release("move_up")
	check(entered, id + " walking enters canonical room")
	if not entered:
		print("ACCESS_STOP ", world.player.global_position, " door=", door, " notice=", session.notice.text)
		return false
	await wait_until(func(): return not access._entering)
	check(session.access_id == id and world.camera.locked and not world.player.input_locked, id + " origin and interior control preserved")
	var desired: Vector3 = session.return_point
	_print_return_blockers(id, desired)
	world.player.teleport(session.room.exit_position + Vector3(0, .08, -.9))
	await frames(3)
	Input.action_press("move_down")
	var exited := await wait_until(func(): return session.state.place_id.is_empty(), 180)
	Input.action_release("move_down")
	check(exited, id + " walking exits without E")
	if not exited: return false
	var zoom: bool = world.camera._store_focus_active
	await wait_until(func(): return not access._leaving)
	var returned: Vector3 = world.player.global_position
	returned.y = desired.y
	var outward: Vector3 = desired - Vector3(definition.exterior_position)
	outward.y = 0
	outward = outward.normalized()
	var side := Vector3(-outward.z, 0, outward.x)
	var matches := false
	for offset in [Vector3.ZERO, outward * .75, outward * 1.5, side * .8 + outward * .75, -side * .8 + outward * .75]:
		matches = matches or returned.distance_to(desired + offset) < .1
	print("ACCESS_RETURN ", id, " desired=", desired, " actual=", world.player.global_position, " zoom=", zoom)
	check(zoom and matches and not world.player.input_locked and session.position_clear(world.player.global_position + Vector3.UP * .04), id + " zoom and safe original return")
	await frames(12)
	check(session.state.place_id.is_empty(), id + " no return loop")
	return true
