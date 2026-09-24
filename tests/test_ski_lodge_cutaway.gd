extends SceneTree

var failed: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failed.append(label)

func run() -> void:
	create_timer(120).timeout.connect(func(): quit(2))
	root.size = Vector2i(1280, 720)
	var world: Node2D = load("res://world/mountain_pass/MountainPass.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.region_ready or not world.interior_manager.region_ready: await process_frame
	var room: Node2D = world.interior_manager.get_interior(&"ski_lodge")
	var actor: CharacterBody2D = world.player_instance
	actor.set_physics_process(false)
	var facade: Node2D = room.inline_facade
	var front := facade.get_node_or_null("SkiLodgeEntrance") as BuildingEntrance
	var rear := facade.get_node_or_null("SkiLodgeSlopeEntrance") as BuildingEntrance
	check(front != null and rear != null, "both physical lodge doorways exist")
	if front == null or rear == null:
		world.queue_free()
		await process_frame
		quit(1)
		return
	check(room.inline_mode and room.exit_door == null, "lodge uses its physical floor")
	check(not front.handle_input_locally and not rear.handle_input_locally and not front.show_entrance_marker, "both doors open without E or marker")
	actor.global_position = front.global_position + Vector2(0, 24)
	for _i in 8: await physics_frame
	check(await walk_to(actor, room.to_global(room.project_floor(Vector2(0, 3.75)))), "front entrance is walkable")
	for _i in 4: await process_frame
	check(room.sprite_3d.visible and actor.get_node("Camera").has_meta("compact_interior"), "cutaway and camera activate in place")
	check(room.get_node_or_null("LodgeFireplaceHeat") != null and room.get_node_or_null("SkiClerk") != null, "heat and clerk remain")
	check(room.walls_body.get_child_count() > 7, "furniture keeps physical solids")
	check(await walk_to(actor, room.to_global(room.project_floor(Vector2(0, -1.75)))), "centre aisle reaches the rear")
	check(await walk_to(actor, room.get_node("RentalCounter").global_position), "rental counter is reachable")
	room.get_node("RentalCounter")._activate(actor, true)
	check(actor.ski_rental_active, "rental equips clothing")
	check(await walk_to(actor, room.to_global(room.project_floor(Vector2(0, -1.75)))), "rental returns to aisle")
	check(await walk_to(actor, room.to_global(room.project_floor(Vector2(0, -1)))), "cross aisle stays clear")
	check(await walk_to(actor, room.get_node("EquipmentRack").global_position), "ski rack is reachable")
	room.get_node("EquipmentRack")._activate(actor, true)
	check(actor.ski_equipment_ready, "rack equips skis")
	check(await walk_to(actor, room.to_global(room.project_floor(Vector2(4.8, .15)))), "rack clears bench")
	check(await walk_to(actor, room.to_global(room.project_floor(Vector2(0, .15)))), "cross aisle reaches centre")
	check(await walk_to(actor, room.to_global(room.project_floor(Vector2(0, -1.75)))), "rear aisle stays clear")
	check(await walk_to(actor, rear.global_position + Vector2(0, -22)), "rear door leads to pistes on foot")
	for _i in 5: await process_frame
	check(actor.is_skiing and not actor.has_meta("mountain_interior"), "rear exit starts skiing without teleport")
	actor.stop_skiing()
	actor.global_position = front.global_position + Vector2(0, 24)
	for _i in 8: await process_frame
	check(await walk_to(actor, room.to_global(room.project_floor(Vector2(0, 3.75)))), "front door accepts reentry")
	check(await walk_to(actor, front.global_position + Vector2(0, 24)), "front door exits on foot")
	for _i in 5: await process_frame
	check(not actor.has_meta("mountain_interior") and room.viewport_3d.render_target_update_mode == SubViewport.UPDATE_DISABLED, "vacant lodge restores exterior and sleeps")
	actor.global_position = Vector2(40000, 20000)
	world.restore_region_interior(actor, {"interior":"ski_lodge", "exterior_return":[6350, 600]})
	check(actor.global_position.distance_to(room.spawn_point.global_position) < 2, "legacy off-map save recovers at physical spawn")
	print("LODGE_CUTAWAY failed=", failed.size())
	world.queue_free()
	await process_frame
	quit(0 if failed.is_empty() else 1)

func walk_to(actor: CharacterBody2D, target: Vector2) -> bool:
	for _step in 360:
		var delta := target - actor.global_position
		if delta.length() < 2: return true
		if actor.move_and_collide(delta.limit_length(2.5)) != null: return false
		await physics_frame
	return false
