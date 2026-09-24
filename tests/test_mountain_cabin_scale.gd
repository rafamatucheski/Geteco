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
	var actor: CharacterBody2D = world.player_instance
	actor.set_physics_process(false)
	var cabin: Node2D = world.interior_manager.cabin_interior
	var entrance: BuildingEntrance = find_entrance(world, &"mountain_cabin")
	check(cabin.inline_mode and entrance != null and cabin.exit_door == null, "cabin occupies its real facade")
	actor.global_position = entrance.global_position + Vector2(0, 24)
	for _i in 6: await physics_frame
	check(await walk_to(actor, cabin.to_global(cabin.project_floor(Vector2(0, .1)))), "actor enters through physical door")
	for _i in 4: await process_frame
	check(cabin._inline_occupied and actor.get_meta("mountain_interior_id", &"") == &"mountain_cabin", "cabin shelters player in place")
	check(root.get_camera_2d() == actor.get_node("Camera") and actor.get_node("Camera").has_meta("compact_interior"), "player camera zooms inside")
	var presentation: Node = actor.get_meta("interior_actor_presentation", null)
	check(is_instance_valid(presentation) and presentation.rig.get_parent() == presentation.anchor and is_equal_approx(presentation.anchor.scale.x * presentation.standing_rig_height, 1.8), "human rig keeps its 1.8 m scale beside compact furnishings")
	for pickup in cabin._active_weapon_stations:
		var floor_point := Vector2(pickup.model.position.x, pickup.model.position.z)
		check(pickup.position.distance_to(cabin.project_floor(floor_point)) < 1, "weapon pickup matches visible floor: " + pickup.weapon_id)
	var query := PhysicsPointQueryParameters2D.new()
	query.collision_mask = 1
	query.position = cabin.to_global(cabin.project_floor(Vector2(-1.16, -.54)))
	query.exclude = [actor.get_rid()]
	var bed_solid := false
	for hit in world.get_world_2d().direct_space_state.intersect_point(query):
		if hit.collider == cabin.walls_body: bed_solid = true
	check(bed_solid, "bed physically blocks walking through furniture")
	actor.global_position = cabin.to_global(cabin.project_floor(Vector2(0, .5)))
	check(await walk_to(actor, entrance.global_position + Vector2(0, 24)), "cabin exits on foot")
	for _i in 5: await process_frame
	check(not actor.has_meta("mountain_interior") and cabin.viewport_3d.render_target_update_mode == SubViewport.UPDATE_DISABLED, "exterior presentation and idle renderer restore")
	actor.global_position = Vector2(40000, 20000)
	world.restore_region_interior(actor, {"interior":"mountain_cabin", "exterior_return":[7350, 730]})
	check(actor.global_position.distance_to(cabin.spawn_point.global_position) < 2, "legacy off-map save recovers at clear spawn")
	for _i in 4: await process_frame
	check(actor.get_meta("mountain_interior_id", &"") == &"mountain_cabin", "legacy save activates physical room")
	actor._respawn_at_hospital()
	actor.set_physics_process(false)
	for _i in 4: await process_frame
	check(not actor.has_meta("mountain_interior") and actor.model_root.get_viewport() == actor.viewport_3d, "respawn restores exterior rig")
	print("CABIN_SCALE failed=", failed.size())
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
	for _step in 300:
		var delta := target - actor.global_position
		if delta.length() < 2: return true
		if actor.move_and_collide(delta.limit_length(2.5)) != null: return false
		await physics_frame
	return false
