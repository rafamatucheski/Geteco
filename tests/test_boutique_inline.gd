extends SceneTree

var failures: Array[String] = []
var passed := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if ok: passed += 1
	else: failures.append(label)

func run() -> void:
	create_timer(140.0).timeout.connect(func(): quit(2))
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var saves := root.get_node("SaveManager")
	var save_dir := OS.get_temp_dir().path_join("geteco-boutique-inline-0922/saves")
	DirAccess.make_dir_recursive_absolute(save_dir)
	saves._save_dir = save_dir + "/"
	saves._save_directory_ready = false
	saves.clear_pending_save()
	var world: Node2D = load("res://world/mountain_pass/MountainPass.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.region_ready or not world.interior_manager.region_ready:
		await process_frame
	var manager: MountainInteriorManager = world.interior_manager
	var facade: ResortShopFacade = world.find_child("ResortShopFacade", true, false)
	var room: Node2D = manager.get_interior(&"mountain_boutique")
	var player: CharacterBody2D = world.player_instance
	check(facade != null and room != null, "Boutique exists in real MountainPass")
	if facade == null or room == null:
		quit(1)
		return
	check(room.inline_mode and room.global_position.distance_to(facade.global_position) < 1, "Room occupies the facade")
	check(not manager._exterior_doors.has(facade.entrance), "Entrance has no teleport registration")
	check(not facade.entrance.handle_input_locally and not facade.entrance.show_entrance_marker, "Door has no E or orange marker")
	check(room.exit_door == null and not room._counter_hint.visible, "No exit portal or floating checkout prompt")
	player.set_physics_process(false)
	player.global_position = facade.to_global(facade.project_floor(Vector2(0, 3.3)))
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	for _i in 15: await physics_frame
	await capture("after-exterior")
	check(await walk_to(player, room.to_global(room.project_floor(Vector2(0, 1.1)))), "Walk through physical door")
	for _i in 8: await process_frame
	check(facade.door_blocker.disabled, "Sliding leaves open near actor")
	check(room._inline_occupied and room.sprite_3d.visible and not facade.sprite_3d.visible, "Roof hides and room appears")
	check(player.has_meta("mountain_interior") and player.has_meta("interior_actor_presentation"), "Shelter and shared depth activate")
	check(player.get_node("Camera").has_meta("compact_interior"), "Camera frames compact room")
	await capture("after-interior")
	var snapshot: Dictionary = root.get_node("RegionTravel").snapshot_world()
	check(not snapshot.has("interior"), "Save keeps physical map position")
	var save_result: Dictionary = saves.save_game("boutique_inline_probe")
	check(save_result.get("success", false), "Physical boutique save writes to disk")
	if save_result.get("success", false):
		var load_result: Dictionary = saves.load_game("boutique_inline_probe")
		var saved_world: Dictionary = load_result.get("data", {}).get("world", {})
		var saved_player: Dictionary = load_result.get("data", {}).get("player", {})
		var saved_position: Array = saved_player.get("position", [])
		check(load_result.get("success", false) and saved_world.get("region") == "mountain" and not saved_world.has("interior") and saved_position.size() == 2 and Vector2(float(saved_position[0]), float(saved_position[1])).distance_to(player.global_position) < 1, "Boutique disk save reloads at physical map position")
		saves.clear_pending_save()
	var cash: Area2D = room.get_node("ShopCash")
	var initial_money: int = player.money
	check(await walk_to(player, cash.global_position), "Cash reward remains reachable")
	for _i in 5: await physics_frame
	print("BOUTIQUE_CASH collected=", cash.collected, " amount=", cash.amount, " before=", initial_money, " after=", player.money, " inside=", room.contains_actor(player))
	check(cash.collected and player.money == initial_money + 1250, "Cash reward grants once")
	cash._collect(player)
	check(player.money == initial_money + 1250, "Collected reward cannot be duplicated")
	check(await walk_to(player, room.to_global(room._counter_point)), "Counter has clear approach")
	var interact := InputEventAction.new()
	interact.action = "interact"
	interact.pressed = true
	room._unhandled_input(interact)
	check(room.shop.is_active, "Interaction opens clothing catalog")
	player.money = 5000
	var owned: bool = player.owned_outfits.get("dante_arctic", false)
	room.shop._select_outfit("dante_arctic")
	room.shop._on_action_pressed()
	check(player.current_outfit_id == "dante_arctic" and player.money == (5000 if owned else 3200), "Winter outfit purchase keeps price")
	room.shop.close_store()
	var bounds: Dictionary = preload("res://systems/interiors/InteriorSolidProjection.gd").mesh_bounds(room.room_model)
	for id in [&"BackWall", &"SideWall-1", &"SideWall1", &"FrontWall-1", &"FrontWall1", &"Checkout", &"WestCollection", &"EastCollection", &"TailoredCoat", &"AlpineCoat", &"VelvetSeat"]:
		check(bounds.has(id), "Physical mesh group " + String(id))
	player.global_position = room.to_global(room.project_floor(Vector2(0, .34)))
	var counter_target: Vector2 = room.to_global(room.project_floor(Vector2(0, -1.15)))
	check(player.move_and_collide(counter_target - player.global_position) != null, "Player cannot cross checkout")
	var npc: CharacterBody2D = preload("res://characters/AnimatedPedestrian3D.gd").new()
	world.add_child(npc)
	npc.set_physics_process(false)
	npc.collision_mask = 1
	npc.global_position = room.to_global(room.project_floor(Vector2(0, .34)))
	var npc_helper := preload("res://systems/interiors/InteriorActorPresentation.gd").new()
	world.add_child(npc_helper)
	npc_helper.configure(npc, room.camera_3d, room.sprite_3d)
	check(npc.move_and_collide(counter_target - npc.global_position) != null, "Real NPC cannot cross checkout")
	player.global_position = room.to_global(room.project_floor(Vector2(1.3, 1.1)))
	npc.global_position = room.to_global(room.project_floor(Vector2(0, 1.25)))
	check(npc.move_and_collide(room.to_global(room.project_floor(Vector2(0, .3))) - npc.global_position) == null, "Real NPC fits central aisle")
	if DisplayServer.get_name() != "headless":
		await check_depth(player, room._actor_scale, room, "player")
		await check_depth(npc, npc_helper, room, "npc")
	check_solid_sweeps(player, npc, room)
	npc_helper.restore()
	npc_helper.queue_free()
	npc.queue_free()
	await process_frame
	player.global_position = room.to_global(room.project_floor(Vector2(0, 1.1)))
	check(await walk_to(player, facade.to_global(facade.project_floor(Vector2(0, 3.3)))), "Walk back out of the same door")
	for _i in 8: await process_frame
	check(not room._inline_occupied and facade.sprite_3d.visible and not player.has_meta("mountain_interior") and not player.get_node("Camera").has_meta("compact_interior"), "Exterior and camera restore")
	check(room.viewport_3d.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Empty interior stops rendering")
	player.global_position = Vector2(74000, 20100)
	world.restore_region_interior(player, {"interior":"mountain_boutique", "temperature":100, "weather_clock":0})
	check(room.contains_point(player.global_position), "Legacy off-map boutique save recovers to real floor")
	print("BOUTIQUE_INLINE passed=", passed, " failed=", failures.size())
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func walk_to(actor: CharacterBody2D, target: Vector2) -> bool:
	for _step in 240:
		var motion := target - actor.global_position
		if motion.length() < 2.0: return true
		var hit := actor.move_and_collide(motion.limit_length(2.5))
		if hit != null:
			print("BOUTIQUE_ROUTE_BLOCK ", hit.get_collider().get_path())
			return false
		await physics_frame
	return false

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	var out := OS.get_temp_dir().path_join("geteco-boutique-inline-0922")
	DirAccess.make_dir_recursive_absolute(out)
	for _i in 12: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(label + ".png"))

func check_depth(actor: CharacterBody2D, helper: Node, room: Node2D, label: String) -> void:
	var old_process := actor.is_processing()
	actor.set_process(false)
	helper.set_process(false)
	actor.global_position = room.to_global(room.project_floor(Vector2(1.4, .8)))
	helper._update_scale()
	var hidden_count := await changed_pixels(helper, room)
	check(hidden_count == 0, "Real front wall occludes " + label)
	actor.global_position = room.to_global(room.project_floor(Vector2(0, .8)))
	helper._update_scale()
	var visible_count := await changed_pixels(helper, room)
	check(visible_count > 100, "Open doorway shows " + label)
	print("BOUTIQUE_DEPTH ", label, " occluded=", hidden_count, " visible=", visible_count)
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

func check_solid_sweeps(player: CharacterBody2D, npc: CharacterBody2D, room: Node2D) -> void:
	room.set_process(false)
	var directions := [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN, Vector2(-1,-1), Vector2(1,-1), Vector2(-1,1), Vector2(1,1)]
	var approaches := 0
	for actor in [player, npc]:
		var other: CharacterBody2D = npc if actor == player else player
		other.global_position = Vector2(99000, 99000)
		for shape in room.walls_body.get_children():
			var rect: Rect2 = shape.get_meta("model_floor_rect")
			var blocked := 0
			for direction in directions:
				actor.global_position = room.to_global(room.project_floor(rect.get_center() + direction * (rect.size * .5 + Vector2.ONE)))
				var target: Vector2 = room.to_global(room.project_floor(rect.get_center()))
				if actor.move_and_collide(target - actor.global_position) != null: blocked += 1
				approaches += 1
			check(blocked == directions.size(), "Swept " + actor.name + " against " + shape.name)
	player.global_position = room.spawn_point.global_position
	npc.global_position = room.to_global(room.project_floor(Vector2(0, .3)))
	room.set_process(true)
	print("BOUTIQUE_SWEPT_APPROACHES ", approaches)
