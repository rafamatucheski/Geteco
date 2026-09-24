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
	var bunker: Node2D = world.interior_manager.get_interior(&"mountain_bunker")
	var actor: CharacterBody2D = world.player_instance
	actor.set_physics_process(false)
	var entrance: BuildingEntrance = find_entrance(world, &"mountain_bunker")
	check(bunker.inline_mode and bunker.exit_door == null, "Station Zero uses a physical room and exit")
	check(not entrance.handle_input_locally and not entrance.show_entrance_marker, "door opens without E or marker")
	check(bunker.model.get_child_count() > 150 and bunker.walls_body.get_child_count() >= 20, "authored room keeps projected solids")
	actor.global_position = entrance.global_position + Vector2(0, 24)
	for _i in 8: await physics_frame
	check(await walk_to(actor, bunker.to_global(bunker.project_floor(Vector2(0, 4.3)))), "front door crosses on foot")
	for _i in 4: await process_frame
	check(actor.get_meta("mountain_interior_id", &"") == &"mountain_bunker", "interior identity follows physical position")
	check(bunker.active and bunker.sprite_3d.visible and root.get_camera_2d() == actor.get_node("Camera"), "cutaway and player camera activate")
	check(world.storm_manager.sheltered and not world.storm_manager.visible, "snow stops inside")
	var query := PhysicsPointQueryParameters2D.new()
	query.position = bunker.to_global(bunker.project_floor(Vector2(0, -4.2)))
	query.collision_mask = 1
	query.exclude = [actor.get_rid()]
	check(not world.get_world_2d().direct_space_state.intersect_point(query).is_empty(), "command desk blocks actor")
	query.position = bunker.to_global(bunker.project_floor(Vector2(0, 0)))
	check(world.get_world_2d().direct_space_state.intersect_point(query).is_empty(), "central floor stays clear")
	actor.global_position = bunker.to_global(bunker.console_position)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F
	key.pressed = true
	bunker._unhandled_key_input(key)
	check(bunker.note_open and bunker.note_text.text.contains("CANAL 07"), "radio note remains readable")
	bunker._unhandled_key_input(key)
	actor.global_position = bunker.to_global(bunker.route_position)
	bunker._unhandled_key_input(key)
	check(bunker.note_open and bunker.note_text.text.contains("MAPA"), "route map remains readable")
	bunker._unhandled_key_input(key)
	check(bunker.get_node_or_null("Boss2Anchor") != null and bunker.get_node_or_null("RoomCash") != null, "boss and reward remain")
	actor.global_position = bunker.to_global(bunker.project_floor(Vector2(0, 4.3)))
	check(await walk_to(actor, entrance.global_position + Vector2(0, 24)), "front door exits on foot")
	for _i in 5: await process_frame
	check(not bunker.active and not actor.has_meta("mountain_interior") and root.get_camera_2d() == actor.get_node("Camera"), "exterior presentation restores")
	check(world.storm_manager.visible, "snow resumes outside")
	actor.global_position = Vector2(40000, 20000)
	world.restore_region_interior(actor, {"interior":"mountain_bunker", "exterior_return":[6500, -2790]})
	check(actor.global_position.distance_to(bunker.spawn_point.global_position) < 2, "legacy off-map save recovers on clear floor")
	print("BUNKER failed=", failed.size())
	world.queue_free()
	await process_frame
	quit(0 if failed.is_empty() else 1)

func find_entrance(parent: Node, id: StringName) -> BuildingEntrance:
	if parent is BuildingEntrance and parent.destination_id == id: return parent
	for child in parent.get_children():
		var found := find_entrance(child, id)
		if found != null: return found
	return null

func walk_to(actor: CharacterBody2D, target: Vector2) -> bool:
	for _step in 360:
		var delta := target - actor.global_position
		if delta.length() < 2: return true
		if actor.move_and_collide(delta.limit_length(2.5)) != null: return false
		await physics_frame
	return false
