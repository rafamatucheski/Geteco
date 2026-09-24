extends SceneTree

var failures: Array[String] = []
var passed := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("[%s] %s" % ["PASS" if ok else "FAIL", label])
	if ok: passed += 1
	else: failures.append(label)

func run() -> void:
	create_timer(240).timeout.connect(func(): quit(2))
	root.size = Vector2i(1280,720)
	var world: Node2D = load("res://world/mountain_pass/MountainPass.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.region_ready or not world.interior_manager.region_ready:
		await process_frame
	var player: CharacterBody2D = world.player_instance
	var room: Node2D = world.interior_manager.ammunation_interior
	var shop: Node2D = world.find_child("MountainAmmuNation", true, false)
	check(shop != null and room.inline_mode, "Real mountain shop has inline floor")
	if shop == null:
		quit(1)
		return
	check(room.global_position.distance_to(shop.global_position) < 1, "Floor and facade share map coordinates")
	player.set_physics_process(false)
	player.global_position = shop.to_global(shop.project_floor(Vector2(0,3.6)))
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	for _i in 60: await process_frame
	await _shot("mountain-world-before")
	check(await walk_to(player, room.to_global(room.project_floor(Vector2(0,1.55)))), "Walk through real mountain doorway")
	for _i in 10: await process_frame
	check(room._occupied and room.room_sprite.visible and not shop.sprite_3d.visible, "Roof and camera switch at real shop")
	check(player.has_meta("interior_actor_presentation") and player.has_meta("mountain_interior"), "Shared actor depth and shelter activate")
	await _shot("mountain-world-inside")
	var snapshot: Dictionary = root.get_node("RegionTravel").snapshot_world()
	check(not snapshot.has("interior"), "Inline shop save stores physical map position")
	check(await walk_to(player, room.to_global(room.merchant_point)), "Reach Vance in compact aisle")
	room.open_catalog()
	check(room.active, "Catalog opens in real mountain shop")
	player.money = 1000
	player.armor = 0
	room.selection = room.stock.find("armor")
	room.change_selection(0)
	room.purchase()
	check(player.armor == 100, "Armor purchase still works")
	room.close_catalog()
	check(room.get_node_or_null("MountainStove") is StaticBody2D, "Mountain stove has collision")
	player.global_position = room.to_global(room.project_floor(Vector2(-2.9,1.53)))
	var stove_hit := player.move_and_collide(room.to_global(room.project_floor(Vector2(-3.9,1.53))) - player.global_position)
	check(stove_hit != null, "Player cannot cross mountain stove")
	player.global_position = room.spawn_point.global_position
	for _i in 5: await process_frame
	check(await walk_to(player, room.to_global(room.project_floor(Vector2(0,3.6)))), "Walk out through real mountain doorway")
	for _i in 8: await process_frame
	check(not room._occupied and shop.sprite_3d.visible and not player.has_meta("mountain_interior"), "Exterior restores after leaving")
	world.restore_region_interior(player, {"interior":"ammunation","temperature":100,"weather_clock":0})
	check(room.contains_point(player.global_position), "Legacy off-map shop save migrates to in-building spawn")
	print("MOUNTAIN AMMUNATION: %d passed, %d failed" % [passed, failures.size()])
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func walk_to(actor: CharacterBody2D, target: Vector2) -> bool:
	for _i in 220:
		var motion := target - actor.global_position
		if motion.length() < 9: return true
		var hit := actor.move_and_collide(motion.limit_length(3))
		if hit != null:
			print("MOUNTAIN ROUTE BLOCK ", hit.get_collider().get_path())
			return false
		await physics_frame
	return false

func _shot(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	var dir := OS.get_temp_dir().path_join("geteco-ammunation-cutaway-0922")
	DirAccess.make_dir_recursive_absolute(dir)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(dir.path_join(label + ".png"))
