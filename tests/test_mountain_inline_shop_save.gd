extends SceneTree

var failed := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failed += 1

func run() -> void:
	create_timer(90.0).timeout.connect(func(): quit(2))
	var saves := root.get_node("SaveManager")
	var original_dir: String = saves._save_dir
	var directory := OS.get_temp_dir().path_join("geteco-mountain-shop-save-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(directory)
	saves._save_dir = directory + "/"
	saves._save_directory_ready = false
	saves.clear_pending_save()
	change_scene_to_file("res://world/mountain_pass/MountainPass.tscn")
	await process_frame
	while current_scene == null or not current_scene.region_ready or not current_scene.interior_manager.region_ready:
		await process_frame
	var world: Node2D = current_scene
	var actor: CharacterBody2D = world.player_instance
	actor.set_physics_process(false)
	var room: Node2D = world.interior_manager.get_interior(&"mountain_outfitters")
	actor.global_position = room.to_global(room.project_floor(Vector2(0, 0.1)))
	for _i in 10: await physics_frame
	check(room._inline_occupied, "shop occupies its physical facade before save")
	check(saves.save_game("inline_shop").success, "shop writes a real save file")
	var loaded: Dictionary = saves.load_game("inline_shop")
	check(loaded.success and loaded.data.world.region == "mountain" and not loaded.data.world.has("interior"), "save keeps mountain region and continuous coordinates")
	var snapshot: Dictionary = loaded.data.duplicate(true)
	var saved_position: Vector2 = actor.global_position
	saves.clear_pending_save()
	change_scene_to_file("res://world/mountain_pass/MountainPass.tscn")
	await process_frame
	while current_scene == null or not current_scene.region_ready or not current_scene.interior_manager.region_ready:
		await process_frame
	world = current_scene
	actor = world.player_instance
	actor.set_physics_process(false)
	room = world.interior_manager.get_interior(&"mountain_outfitters")
	actor.restore(snapshot.player)
	world.restore_region_interior(actor, snapshot.world)
	for _i in 10: await physics_frame
	check(actor.global_position.distance_to(saved_position) < 2.0 and room._inline_occupied, "disk reload reopens the same physical shop")
	var camera := actor.get_node("Camera") as Camera2D
	var framing: Rect2 = camera.get_meta("compact_interior", Rect2())
	check(root.get_camera_2d() == camera and framing.size == Vector2(140, 104), "reload restores the tight indoor camera")
	actor.global_position = room.to_global(room._counter_point)
	var key := InputEventAction.new()
	key.action = "interact"
	key.pressed = true
	room._unhandled_input(key)
	check(room.shop.is_active, "counter still opens the shop after reload")
	room.shop.close_store()
	actor.global_position = Vector2(33000, 20000)
	world.restore_region_interior(actor, {"interior": "mountain_outfitters", "exterior_return": [5980, 600]})
	for _i in 8: await physics_frame
	check(actor.global_position.distance_to(room.spawn_point.global_position) < 2.0 and room.contains_point(actor.global_position) and room._inline_occupied, "legacy off-map shop save lands inside the physical floor")
	DirAccess.remove_absolute(saves.get_slot_path("inline_shop"))
	DirAccess.remove_absolute(directory)
	saves._save_dir = original_dir
	world.queue_free()
	await process_frame
	print("MOUNTAIN_SHOP_SAVE failed=", failed)
	quit(0 if failed == 0 else 1)
