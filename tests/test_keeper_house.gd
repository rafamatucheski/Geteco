extends "res://tests/test_urban_operations.gd"

func run() -> void:
	if not await _initialize_world():
		quit(1)
		return
	check(await session.enter_place("cemetery_keeper", false), "Enter keeper house")
	await settle(20)
	var cemetery = urban.cemetery
	var keeper = cemetery.keeper
	check(is_instance_valid(keeper), "Keeper exists")
	if is_instance_valid(keeper):
		check(session.room.is_floor_clear(session.room.to_local(keeper.global_position), .30), "Keeper capsule clears furniture")
		var displaced: Vector3 = keeper.global_position + Vector3(0, 0, .4)
		keeper.global_position = displaced
		cemetery.refresh_context()
		check(keeper.global_position.distance_to(displaced) < .01, "Context refresh must not teleport keeper back into table")
		await settle(40)
		check(keeper.finished() and keeper.activity == "idle", "House keeper has no stale outdoor route")
		world.player.teleport(keeper.global_position + Vector3(.8, .04, 0))
		await settle()
		check(cemetery.perform("cemetery_keeper"), "Keeper conversation remains reachable")
		session.close_menu()
	check(session.leave_place(), "Exit house")
	await settle(20)
	check(await session.enter_place("cemetery_keeper", false), "Reenter house")
	await settle(20)
	check(actor_count("cemetery_keeper") == 1, "Reentry has one keeper")
	check(session.room.is_floor_clear(session.room.to_local(cemetery.keeper.global_position), .30), "Reentry capsule clears furniture")
	print("KEEPER_HOUSE failures=", failures)
	world.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
