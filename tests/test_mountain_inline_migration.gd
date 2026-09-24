extends SceneTree

const IDS := [
	&"mountain_outfitters", &"mountain_village_outfitters",
	&"mountain_cabin", &"mountain_cabin_encosta", &"mountain_cabin_forest",
	&"mountain_cabin_village_1", &"mountain_cabin_village_2",
	&"mountain_cabin_village_3", &"mountain_cabin_village_4",
]
var failures: Array[String] = []
var passed := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if ok: passed += 1
	else: failures.append(label)

func run() -> void:
	create_timer(300.0).timeout.connect(func(): quit(2))
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var saves := root.get_node("SaveManager")
	var save_dir := OS.get_temp_dir().path_join("geteco-mountain-inline-0922/saves")
	DirAccess.make_dir_recursive_absolute(save_dir)
	saves._save_dir = save_dir + "/"
	saves._save_directory_ready = false
	saves.clear_pending_save()
	var world: Node2D = load("res://world/mountain_pass/MountainPass.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.region_ready or not world.interior_manager.region_ready:
		await process_frame
	var player: CharacterBody2D = world.player_instance
	player.set_physics_process(false)
	for id in IDS:
		var entrance: BuildingEntrance = find_entrance(world, id)
		var room: Node2D = world.interior_manager.get_interior(id)
		check(entrance != null and room != null, String(id) + " exists in real scene")
		if entrance == null or room == null: continue
		check(room.inline_mode and not world.interior_manager._exterior_doors.has(entrance), String(id) + " is physical and has no teleport")
		check(not entrance.handle_input_locally and not entrance.show_entrance_marker and not entrance.show_interaction_prompt, String(id) + " has no E or entry marker")
		check(room.exit_door == null, String(id) + " has no offmap exit")
		check(room.global_position.distance_to(entrance.global_position) < 90, String(id) + " room is under its facade")
		var outside := entrance.global_position + Vector2(0, 18)
		player.global_position = outside
		player.velocity = Vector2.ZERO
		player.reset_physics_interpolation()
		for _i in 20: await physics_frame
		var entry_money: int = player.money
		await capture("after-" + String(id) + "-exterior")
		var inside := room.to_global(room.project_floor(Vector2(0, .1)))
		check(await walk_to(player, inside), String(id) + " walk-in crosses real door")
		for _i in 6: await process_frame
		await capture("after-" + String(id) + "-interior")
		check(room._inline_occupied and room.sprite_3d.visible and player.get_meta("mountain_interior_id", &"") == id, String(id) + " roof, shelter and room activate")
		check(player.get_node("Camera").has_meta("compact_interior"), String(id) + " zoom follows presence")
		check(root.get_camera_2d() == player.get_node("Camera"), String(id) + " keeps the continuous player camera")
		var snapshot: Dictionary = root.get_node("RegionTravel").snapshot_world()
		check(not snapshot.has("interior"), String(id) + " saves physical position")
		if id in [&"mountain_outfitters", &"mountain_village_outfitters"]:
			await check_clothes(player, room, id, entry_money)
		else:
			await check_cabin_content(player, room, id, entry_money)
		if DisplayServer.get_name() != "headless":
			await check_depth(player, room.get("_actor_scale"), room, id, "player")
			var npc: CharacterBody2D = preload("res://characters/AnimatedPedestrian3D.gd").new()
			world.add_child(npc)
			npc.set_physics_process(false)
			npc.global_position = room.to_global(room.project_floor(Vector2(0, 1.1)))
			var npc_helper := preload("res://systems/interiors/InteriorActorPresentation.gd").new()
			world.add_child(npc_helper)
			npc_helper.configure(npc, room.camera_3d, room.sprite_3d)
			await check_depth(npc, npc_helper, room, id, "npc")
			npc_helper.restore()
			npc_helper.queue_free()
			npc.queue_free()
			await process_frame
		check(room.walls_body.get_child_count() >= 7, String(id) + " has projected room solids")
		if room.walls_body.get_child_count() > 0:
			var wall_point: Vector2 = room.to_global(room.project_floor(Vector2(0, -2.2)))
			player.global_position = room.to_global(room.project_floor(Vector2(0, -.8)))
			check(player.move_and_collide(wall_point - player.global_position) != null, String(id) + " rear wall blocks player")
		player.global_position = room.to_global(room.project_floor(Vector2(0, 1.0)))
		check(await walk_to(player, outside), String(id) + " walks back out")
		for _i in 7: await process_frame
		check(not room._inline_occupied and not player.has_meta("mountain_interior") and not player.get_node("Camera").has_meta("compact_interior"), String(id) + " exterior restores")
		check(room.viewport_3d.render_target_update_mode == SubViewport.UPDATE_DISABLED, String(id) + " empty viewport sleeps")
	print("MOUNTAIN_INLINE passed=", passed, " failed=", failures.size())
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func check_clothes(player: CharacterBody2D, room: Node2D, id: StringName, entry_money: int) -> void:
	var cash: Area2D = room.get_node("ShopCash")
	check(await walk_to(player, cash.global_position), String(id) + " reward reachable")
	for _i in 4: await physics_frame
	print("MOUNTAIN_REWARD ", id, " collected=", cash.collected, " entry=", entry_money, " current=", player.money, " amount=", cash.amount)
	check(cash.collected and player.money == entry_money + cash.amount, String(id) + " reward collected once")
	check(await walk_to(player, room.to_global(room._counter_point)), String(id) + " counter reachable")
	var interact := InputEventAction.new()
	interact.action = "interact"
	interact.pressed = true
	room._unhandled_input(interact)
	check(room.shop.is_active, String(id) + " catalog opens at counter")
	room.shop.close_store()

func check_cabin_content(player: CharacterBody2D, room: Node2D, id: StringName, entry_money: int) -> void:
	check(room.get_node_or_null("FireplaceHeatSource") != null, String(id) + " heat source retained")
	if id == &"mountain_cabin":
		for pickup in ["LegendaryRifleStation", "WoodAxeStation", "HuntingKnifeStation"]:
			check(room.get_node_or_null(pickup) != null, String(id) + " retained " + pickup)
	else:
		var cash: Area2D = room.get_node("CabinCash")
		check(await walk_to(player, cash.global_position), String(id) + " reward reachable")
		for _i in 4: await physics_frame
		print("MOUNTAIN_REWARD ", id, " collected=", cash.collected, " entry=", entry_money, " current=", player.money, " amount=", cash.amount)
		check(cash.collected and player.money == entry_money + cash.amount, String(id) + " reward collected once")

func find_entrance(parent: Node, id: StringName) -> BuildingEntrance:
	if parent is BuildingEntrance and parent.destination_id == id: return parent
	for child in parent.get_children():
		var found := find_entrance(child, id)
		if found != null: return found
	return null

func walk_to(actor: CharacterBody2D, target: Vector2) -> bool:
	for _step in 260:
		var motion := target - actor.global_position
		if motion.length() < 2.0: return true
		var hit := actor.move_and_collide(motion.limit_length(2.5))
		if hit != null:
			print("MOUNTAIN_ROUTE_BLOCK ", hit.get_collider().get_path(), " target=", target, " position=", actor.global_position)
			return false
		await physics_frame
	return false

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	var folder := OS.get_temp_dir().path_join("geteco-mountain-inline-0922")
	DirAccess.make_dir_recursive_absolute(folder)
	for _i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label + ".png"))

func check_depth(actor: CharacterBody2D, helper: Node, room: Node2D, id: StringName, kind: String) -> void:
	var old_process := actor.is_processing()
	actor.set_process(false)
	helper.set_process(false)
	var shop := id in [&"mountain_outfitters", &"mountain_village_outfitters"]
	var hidden_pose := Vector2(1.5, .55) if id == &"mountain_outfitters" else Vector2(2.5, 1.45) if shop else Vector2(1.07, 1.08)
	var visible_pose := Vector2(0, .45) if id == &"mountain_outfitters" else Vector2(0, 1.35) if shop else Vector2(0, 1.08)
	actor.global_position = room.to_global(room.project_floor(hidden_pose))
	helper._update_scale()
	var hidden_count := await changed_pixels(helper, room)
	check(hidden_count == 0, String(id) + " front wall occludes " + kind)
	actor.global_position = room.to_global(room.project_floor(visible_pose))
	helper._update_scale()
	var visible_count := await changed_pixels(helper, room)
	check(visible_count > 100, String(id) + " doorway reveals " + kind)
	print("MOUNTAIN_DEPTH ", id, " ", kind, " hidden=", hidden_count, " visible=", visible_count)
	helper.set_process(true)
	actor.set_process(old_process)

func changed_pixels(helper: Node, room: Node2D) -> int:
	helper.anchor.show()
	for _i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var with_actor: Image = room.viewport_3d.get_texture().get_image()
	helper.anchor.hide()
	for _i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var without_actor: Image = room.viewport_3d.get_texture().get_image()
	var pixel: Vector2 = room.camera_3d.unproject_position(helper.anchor.position + Vector3.UP * .9)
	var changed := 0
	for y in range(maxi(0, int(pixel.y) - 30), mini(with_actor.get_height(), int(pixel.y) + 30)):
		for x in range(maxi(0, int(pixel.x) - 24), mini(with_actor.get_width(), int(pixel.x) + 24)):
			if with_actor.get_pixel(x, y) != without_actor.get_pixel(x, y): changed += 1
	helper.anchor.show()
	return changed
