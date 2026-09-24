extends SceneTree

var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	print(("PASS " if value else "FAIL ") + label)
	if not value: failures += 1

func run() -> void:
	create_timer(120).timeout.connect(func(): quit(2))
	var saves := root.get_node("SaveManager")
	saves._save_dir = "user://distinct-cabin-save-validation/"
	saves._save_directory_ready = false
	saves.clear_pending_save()
	var mountain = load("res://world/mountain_pass/MountainPass.tscn").instantiate()
	root.add_child(mountain)
	current_scene = mountain
	while not mountain.region_ready or not mountain.interior_manager.region_ready: await process_frame
	var actor = mountain.player_instance
	actor.set_physics_process(false)
	var manager = mountain.interior_manager
	var expected_total := 0
	for id in manager.DISTINCT_CABINS:
		var room = manager.get_interior(id)
		actor.set_meta("mountain_interior", true)
		actor.set_meta("mountain_interior_id", id)
		manager.set_active_interior(room)
		actor.global_position = room.get_node("CabinCash").global_position
		var before: int = actor.money
		for frame in 4: await physics_frame
		var cash = room.get_node("CabinCash")
		check(cash.collected and actor.money == before + cash.amount, "Unique reward " + String(id))
		expected_total += cash.amount
	check(expected_total == 9950, "Six independent cash rewards total 9950")
	check(saves.save_game("unique_cabins").success, "Unique cabin rewards saved to disk")
	var loaded: Dictionary = saves.load_game("unique_cabins")
	check(loaded.success, "Unique cabin save loads")
	actor.world_pickups_collected.clear()
	actor.restore(loaded.data.player)
	var preserved_money: int = actor.money
	for id in manager.DISTINCT_CABINS:
		var old = manager._interiors[id]
		manager._interiors.erase(id)
		old.queue_free()
		await process_frame
		var room = manager.get_interior(id)
		actor.global_position = room.spawn_point.global_position
		mountain.restore_region_interior(actor, {"interior": String(id), "exterior_return": [7350, 730]})
		for frame in 3: await physics_frame
		var reward = room.get_node("CabinCash")
		check(reward.collected and not reward.model.visible, "Reconstructed room honors saved reward " + String(id))
		check(room.visible and actor.model_root.get_viewport() == room.viewport_3d, "Save restores unique room and actor depth " + String(id))
		manager._on_exit_requested(room.exit_door, actor, &"", null, &"", id)
		check(actor.global_position.distance_to(Vector2(7350, 730)) < 1 and not actor.has_meta("mountain_interior"), "Saved exterior return " + String(id))
	check(actor.money == preserved_money, "Reload and revisits cannot duplicate money")
	print("DISTINCT_CABIN_SAVE failures=", failures)
	mountain.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
