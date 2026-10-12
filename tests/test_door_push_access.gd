extends "res://tests/test_video_phase3_access.gd"
## Real Main/.NET traversal: approach is inert; walking against the leaf opens it.
var evidence := "res://output/door-push-20261010"

func _run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	world = load("res://Main.tscn").instantiate()
	if world.get_script() == null:
		check(false, "Main script compiled before integration test")
		world.free()
		quit(2)
		return
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	root.add_child(world)
	if not await wait_until(func(): return world.session != null and world.session.ready_for_play, 1800):
		check(false, "Main ready"); quit(1); return
	check(world.production.no_save, "personal save untouched")
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	var access = world.session.weapon_shop_entrance
	access._contact_depth = 0.0
	check(not access._push_requested(Vector3.BACK * 2, Vector3.FORWARD, .5, Vector3.FORWARD), "walking two metres away does not push")
	check(not access._push_requested(Vector3.BACK * .4, Vector3.FORWARD, .5, Vector3.ZERO), "standing at contact does not push")
	check(not access._push_requested(Vector3.BACK * .4, Vector3.FORWARD, .5, Vector3.RIGHT), "walking across contact does not push")
	check(access._push_requested(Vector3.BACK * .4, Vector3.FORWARD, .5, Vector3.FORWARD), "walking into contact pushes")
	check(not access._push_requested(Vector3.BACK * .4 + Vector3.UP * 2, Vector3.FORWARD, .5, Vector3.FORWARD), "another storey cannot push the ground-floor door")
	check(not access._entry_available("quayside_house"), "ownership still blocks admission")
	var rotated := Vector3.FORWARD.rotated(Vector3.UP, .7)
	check(access._push_requested(-rotated * .4, rotated, .5, rotated), "rotated access uses the door direction")
	for id in ["harbor_clothing", "harbor_police", "harbor_supermarket", "harbor_ammunation"]:
		if not await push_access(id): break
	print("DOOR_PUSH_ACCESS checks=", checks, " failures=", failures)
	world.queue_free()
	await frames(6)
	quit(0 if failures.is_empty() else 1)

func photo(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(evidence.path_join(name + ".png"))

func push_access(id: String) -> bool:
	var session = world.session
	var access = session.weapon_shop_entrance
	var definition: Dictionary = access._definition_for(id)
	var door: Vector3 = access._door_position(id, definition)
	var inward: Vector3 = access._inward(id)
	session.controller.region.set_focus(door)
	world.player.teleport(door - inward * 2 + Vector3.UP * .08)
	world.camera.heading = 0.0
	world.camera.initialized = false
	await frames(90)
	var facade: Node3D
	for node in get_nodes_in_group("v2_walkin_facade"):
		if node.get_meta("place_id", "") == id: facade = node
	check(is_instance_valid(facade), id + " actual facade loaded")
	if not is_instance_valid(facade): return false
	check(facade.open_amount < .01, id + " approach leaves door closed")
	await photo(id + "-approach")
	world.player.teleport(door + inward * access._contact_depth - inward * .42 + Vector3.UP * .08)
	await frames(30)
	check(facade.open_amount < .01 and session.state.place_id.is_empty(), id + " contact while idle leaves door closed")
	check(world.player.test_move(Transform3D(Basis.IDENTITY, world.player.global_position), inward), id + " closed leaf blocks full body")
	world.player.teleport(door - inward * 2 + Vector3.UP * .08)
	await frames(3)
	world.player.automatic_direction = inward
	var saw_partial := false
	var saw_gesture := false
	var saw_hand_reach := false
	for tick in 240:
		if facade.open_amount > .01 and facade.open_amount < .85:
			var hand: int = world.player.skeleton.find_bone("LeftHand")
			var hand_world: Vector3 = world.player.skeleton.to_global(world.player.skeleton.get_bone_global_pose(hand).origin)
			saw_hand_reach = saw_hand_reach or (hand_world - world.player.global_position).dot(inward) > .2
			saw_gesture = saw_gesture or access.is_physics_processing()
		if facade.open_amount > .4 and facade.open_amount < .85 and not saw_partial:
			saw_partial = true
			await photo(id + "-push")
		if session.state.place_id == id: break
		await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	check(saw_partial, id + " door animates before admission")
	check(saw_gesture, id + " push gesture starts at contact")
	check(saw_hand_reach, id + " left hand reaches forward during push")
	var entered: bool = session.state.place_id == id
	check(entered, id + " walking pushes and enters without E")
	if not entered:
		print("PUSH_STOP ", id, " player=",world.player.global_position," door=",door," contact_depth=",access._contact_depth," amount=",facade.open_amount)
		return false
	await wait_until(func(): return not access._entering)
	check(session.position_clear(world.player.global_position + Vector3.UP * .04), id + " admitted capsule fits")
	check(not world.player.input_locked, id + " control restored")
	world.player.teleport(session.room.exit_position + Vector3(0, .08, -.9))
	await frames(3)
	world.player.automatic_direction = Vector3.BACK
	var left := await wait_until(func(): return session.state.place_id.is_empty(), 240)
	world.player.automatic_direction = Vector3.ZERO
	check(left, id + " walking exits")
	await wait_until(func(): return not access._leaving)
	await frames(50)
	check(facade.open_amount < .01, id + " door closes after return without reopening nearby")
	return left
