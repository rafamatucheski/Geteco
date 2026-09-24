extends SceneTree

const IDS := [
	&"lumberjack_shelter", &"lumberjack_shelter_1", &"lumberjack_shelter_2",
	&"ski_lodge", &"mountain_bunker", &"mountain_mystery_cave",
]
var failed: Array[String] = []
var passed := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	print(("PASS " if value else "FAIL ") + label)
	if value: passed += 1
	else: failed.append(label)

func run() -> void:
	create_timer(300).timeout.connect(func(): quit(2))
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var save_dir := OS.get_temp_dir().path_join("geteco-mountain-inline-0922/special-saves-" + str(OS.get_process_id()))
	DirAccess.make_dir_recursive_absolute(save_dir)
	var saves := root.get_node("SaveManager")
	saves._save_dir = save_dir + "/"
	saves._save_directory_ready = false
	saves.clear_pending_save()
	var world: Node2D = load("res://world/mountain_pass/MountainPass.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.region_ready or not world.interior_manager.region_ready: await process_frame
	var player: CharacterBody2D = world.player_instance
	player.set_physics_process(false)
	var first_shelter_reward: Area2D
	for id in IDS:
		var door := find_entrance(world, id)
		var room: Node2D = world.interior_manager.get_interior(id)
		check(door != null and room != null, String(id) + " has facade and physical room")
		if door == null or room == null: continue
		check(room.inline_mode and not world.interior_manager._exterior_doors.has(door), String(id) + " has no teleport")
		check(not door.handle_input_locally and not door.show_entrance_marker and not door.show_interaction_prompt and room.exit_door == null, String(id) + " entry and exit need no E or marker")
		var outside := door.global_position + Vector2(0, 22)
		player.global_position = outside
		player.velocity = Vector2.ZERO
		player.reset_physics_interpolation()
		for _i in 10: await process_frame
		await capture("after-" + String(id) + "-exterior")
		var inside := room.to_global(room.project_floor(inner_floor(id)))
		check(await walk_to(player, inside), String(id) + " enters through doorway on foot")
		for _i in 5: await process_frame
		await capture("after-" + String(id) + "-interior")
		var control: Node = room.get("inline_controller") if id not in [&"lumberjack_shelter", &"lumberjack_shelter_1", &"lumberjack_shelter_2"] else null
		var occupied: bool = bool(control.get("occupied")) if control != null else bool(room.get("_inline_occupied"))
		check(occupied and room.sprite_3d.visible and player.get_meta("mountain_interior_id", &"") == id, String(id) + " opens cutaway in place")
		check(player.get_node("Camera").has_meta("compact_interior"), String(id) + " applies indoor camera")
		check(root.get_camera_2d() == player.get_node("Camera"), String(id) + " keeps the continuous player camera")
		check(not root.get_node("RegionTravel").snapshot_world().has("interior"), String(id) + " saves continuous position")
		if String(id).begins_with("lumberjack"):
			var axe := room.get_node("WoodAxeStation") as Area2D
			check(axe.pickup_id == "lumberjack_shelter_axe" and room.get_node_or_null("FireplaceHeatSource") != null, String(id) + " shares reward and heat")
			if first_shelter_reward == null:
				first_shelter_reward = axe
				check(await walk_to(player, axe.global_position), String(id) + " axe is reachable")
				for _i in 4: await physics_frame
				check(axe.collected, String(id) + " axe collects")
			else:
				check(axe.collected or not axe.visible, String(id) + " does not duplicate collected axe")
		elif id == &"ski_lodge":
			check(room.get_node_or_null("RentalCounter") != null and room.get_node_or_null("EquipmentRack") != null and room.get_node_or_null("SkiClerk") != null, "lodge retains rental, skis and residents")
			check(await walk_to(player, room.to_global(room.project_floor(Vector2(0, -1.75)))), "lodge centre aisle connects both doors")
			check(await walk_to(player, room.get_node("RentalCounter").global_position), "lodge rental counter reachable")
			room.get_node("RentalCounter")._activate(player, true)
			check(player.ski_rental_active, "lodge rental equips ski clothing")
			check(await walk_to(player, room.to_global(room.project_floor(Vector2(0, -1.75)))), "lodge leaves rental counter")
			check(await walk_to(player, room.to_global(room.project_floor(Vector2(0, -1.0)))), "lodge leaves counter through clear aisle")
			check(await walk_to(player, room.get_node("EquipmentRack").global_position), "lodge equipment rack reachable")
			room.get_node("EquipmentRack")._activate(player, true)
			check(player.ski_equipment_ready, "lodge rack equips skis")
			check(await walk_to(player, room.to_global(room.project_floor(Vector2(4.8, .15)))), "lodge rack clears bench to the south")
			check(await walk_to(player, room.to_global(room.project_floor(Vector2(0, .15)))), "lodge crosses to centre aisle")
			check(await walk_to(player, room.to_global(room.project_floor(Vector2(0, -1.75)))), "lodge rear aisle reachable")
			var rear_door := room.inline_facade.slope_entrance as BuildingEntrance
			check(await walk_to(player, rear_door.global_position + Vector2(0, -22)), "lodge rear door leads to pistes on foot")
			for _i in 5: await process_frame
			check(player.is_skiing and not player.has_meta("mountain_interior"), "lodge rear exit starts skiing without teleport")
			player.stop_skiing()
			player.global_position = outside
			for _i in 8: await process_frame
			check(await walk_to(player, inside), "lodge front reentry after pistes")
		elif id == &"mountain_bunker":
			check(room.get_node_or_null("RoomCash") != null and room.get_node_or_null("Boss2Anchor") != null, "bunker keeps reward and boss anchor")
			var money_before: int = player.money
			var previously_collected: bool = player.world_pickups_collected.has("mountain_bunker_cash_01")
			check(await walk_to(player, room.get_node("RoomCash").global_position), "bunker reward reachable")
			for _i in 4: await physics_frame
			check(room.get_node("RoomCash").collected and player.money == money_before + (0 if previously_collected else 1500), "bunker reward collects once")
		elif id == &"mountain_mystery_cave":
			check(room.get_node_or_null("SecretRPG") != null and room.get_node_or_null("ExpeditionJournal") != null and room.get_node_or_null("BrokenCamera") != null, "cave keeps weapon and evidence")
			check(await walk_to(player, room.to_global(room.project_floor(Vector2(-2.1, .3)))), "cave journal approach reachable")
			for _i in 4: await process_frame
			var journal := room.get_node("ExpeditionJournal")
			check(journal._near, "cave journal can be examined from clear floor")
			journal._open_reading(player)
			check("mountain_expedition_journal" in player.collectibles_found, "cave journal still progresses mystery")
			journal._close_reading()
		if DisplayServer.get_name() != "headless" and id in [&"lumberjack_shelter", &"ski_lodge", &"mountain_bunker", &"mountain_mystery_cave"]:
			var actor_helper: Node = room.get("_actor_scale") if id == &"lumberjack_shelter" else room.inline_controller.actor_presentation
			await check_depth(player, actor_helper, room, id, "player")
			var npc: CharacterBody2D = preload("res://characters/AnimatedPedestrian3D.gd").new()
			world.add_child(npc)
			npc.set_physics_process(false)
			npc.global_position = room.to_global(room.project_floor(Vector2(0, .5)))
			var npc_helper := preload("res://systems/interiors/InteriorActorPresentation.gd").new()
			world.add_child(npc_helper)
			npc_helper.configure(npc, room.camera_3d, room.sprite_3d)
			await check_depth(npc, npc_helper, room, id, "npc")
			npc_helper.restore()
			npc_helper.queue_free()
			npc.collision_layer = 0
			npc.collision_mask = 0
			npc.queue_free()
			await physics_frame
		var slot := "inline_" + String(id)
		var save_result: Dictionary = saves.save_game(slot)
		check(save_result.get("success", false), String(id) + " writes a real save")
		if save_result.get("success", false):
			var stored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(saves.get_slot_path(slot)))
			var location: Array = stored.get("player", {}).get("position", [])
			check(not stored.get("world", {}).has("interior") and location.size() >= 2 and Vector2(location[0], location[1]).distance_to(player.global_position) < 1, String(id) + " save stores physical coordinates")
		check(room.walls_body.get_child_count() > 2, String(id) + " keeps physical solids")
		check(hits_room_solid(world, room, room.to_global(room.project_floor(solid_floor(id)))), String(id) + " furniture blocks physical space")
		check(not hits_room_solid(world, room, room.spawn_point.global_position), String(id) + " spawn stays off furniture")
		player.global_position = inside
		check(await walk_to(player, outside), String(id) + " exits on foot")
		for _i in 5: await process_frame
		check(not player.has_meta("mountain_interior") and not player.get_node("Camera").has_meta("compact_interior"), String(id) + " restores exterior")
		check(room.viewport_3d.render_target_update_mode == SubViewport.UPDATE_DISABLED, String(id) + " sleeps empty viewport")
	for id in IDS:
		var legacy_room: Node2D = world.interior_manager.get_interior(id)
		player.global_position = Vector2(0, 0)
		for _i in 4: await process_frame
		check(not player.has_meta("mountain_interior"), String(id) + " previous physical room releases before reload")
		player.global_position = Vector2(40000, 20000)
		world.restore_region_interior(player, {"interior": String(id), "exterior_return": [7350, 730]})
		check(player.global_position.distance_to(legacy_room.spawn_point.global_position) < 2, String(id) + " legacy off-map save recovers at physical spawn")
		for _i in 4: await process_frame
		check(player.get_meta("mountain_interior_id", &"") == id, String(id) + " recovered save activates physical room")
	print("MOUNTAIN_SPECIAL passed=", passed, " failed=", failed.size())
	world.queue_free()
	await process_frame
	quit(0 if failed.is_empty() else 1)

func inner_floor(id: StringName) -> Vector2:
	if String(id).begins_with("lumberjack"): return Vector2(0, 1.25)
	if id == &"ski_lodge": return Vector2(0, 3.75)
	if id == &"mountain_bunker": return Vector2(0, 4.1)
	return Vector2(0, 4.0)

func solid_floor(id: StringName) -> Vector2:
	if String(id).begins_with("lumberjack"): return Vector2(1.15, -.72)
	if id == &"ski_lodge": return Vector2(-5.9, 3.15)
	if id == &"mountain_bunker": return Vector2(0, -4.2)
	return Vector2(-4.8, .8)

func hits_room_solid(world: Node2D, room: Node2D, point: Vector2) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = 1
	for hit in world.get_world_2d().direct_space_state.intersect_point(query):
		if hit.collider == room.walls_body: return true
	return false

func find_entrance(parent: Node, id: StringName) -> BuildingEntrance:
	if parent is BuildingEntrance and parent.destination_id == id: return parent
	for child in parent.get_children():
		var found := find_entrance(child, id)
		if found != null: return found
	return null

func walk_to(actor: CharacterBody2D, target: Vector2) -> bool:
	for _step in 360:
		var delta := target - actor.global_position
		if delta.length() < 2.0: return true
		var hit := actor.move_and_collide(delta.limit_length(2.5))
		if hit != null:
			print("MOUNTAIN_SPECIAL_BLOCK ", hit.get_collider().get_path(), " shape=", hit.get_collider_shape(), " target=", target, " at=", actor.global_position)
			return false
		await physics_frame
	return false

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	var dir := OS.get_temp_dir().path_join("geteco-mountain-inline-0922")
	DirAccess.make_dir_recursive_absolute(dir)
	for _i in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(dir.path_join(label + ".png"))

func check_depth(actor: CharacterBody2D, helper: Node, room: Node2D, id: StringName, kind: String) -> void:
	var poses := depth_poses(id)
	var hearth: Node = room.room_view.model.get_node_or_null("LivingHearth") if id == &"ski_lodge" else null
	if hearth != null: hearth.set_process(false)
	var old_process := actor.is_processing()
	actor.set_process(false)
	helper.set_process(false)
	actor.global_position = room.to_global(room.project_floor(poses[0]))
	helper._update_scale()
	var hidden := await changed_pixels(helper, room)
	actor.global_position = room.to_global(room.project_floor(poses[1]))
	helper._update_scale()
	var visible := await changed_pixels(helper, room)
	print("MOUNTAIN_SPECIAL_DEPTH ", id, " ", kind, " hidden=", hidden, " visible=", visible)
	check(visible > 100 and hidden < visible * .25, String(id) + " furniture occludes " + kind + " at real depth")
	helper.set_process(true)
	actor.set_process(old_process)
	if hearth != null: hearth.set_process(true)

func depth_poses(id: StringName) -> Array[Vector2]:
	if id == &"lumberjack_shelter": return [Vector2(1.15, 1.1), Vector2(0, 1.1)]
	if id == &"ski_lodge": return [Vector2(-5.9, 2.4), Vector2(-3.5, 2.4)]
	if id == &"mountain_bunker": return [Vector2(0, -4.6), Vector2(0, -2.8)]
	return [Vector2(-6.1, 1.6), Vector2(-2.4, .1)]

func changed_pixels(helper: Node, room: Node2D) -> int:
	helper.anchor.show()
	for _i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var with_actor: Image = room.viewport_3d.get_texture().get_image()
	helper.anchor.hide()
	for _i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var without_actor: Image = room.viewport_3d.get_texture().get_image()
	var pixel: Vector2 = room.camera_3d.unproject_position(helper.anchor.position + Vector3.UP * .45)
	var changed := 0
	for y in range(maxi(0, int(pixel.y) - 20), mini(with_actor.get_height(), int(pixel.y) + 20)):
		for x in range(maxi(0, int(pixel.x) - 18), mini(with_actor.get_width(), int(pixel.x) + 18)):
			if with_actor.get_pixel(x, y) != without_actor.get_pixel(x, y): changed += 1
	helper.anchor.show()
	return changed
