extends SceneTree

const IDS := [
	&"mountain_cabin", &"mountain_cabin_encosta", &"mountain_cabin_forest",
	&"mountain_cabin_village_1", &"mountain_cabin_village_2",
	&"mountain_cabin_village_3", &"mountain_cabin_village_4",
]
var failed: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failed.append(label)

func run() -> void:
	create_timer(180).timeout.connect(func(): quit(2))
	root.size = Vector2i(1280, 720)
	var mountain: Node2D = load("res://world/mountain_pass/MountainPass.tscn").instantiate()
	root.add_child(mountain)
	current_scene = mountain
	while not mountain.region_ready or not mountain.interior_manager.region_ready: await process_frame
	var player: CharacterBody2D = mountain.player_instance
	player.set_physics_process(false)
	var signatures := {}
	for id in IDS:
		var door: BuildingEntrance = find_entrance(mountain, id)
		var room: Node2D = mountain.interior_manager.get_interior(id)
		check(door != null and room != null and room.inline_mode, String(id) + " has one physical facade and room")
		if door == null or room == null: continue
		check(not door.handle_input_locally and not door.show_entrance_marker and room.exit_door == null, String(id) + " has no teleport or E")
		var outside := door.global_position + Vector2(0, 24)
		player.global_position = outside
		for _i in 6: await physics_frame
		var entry_money: int = player.money
		check(await walk_to(player, room.to_global(room.project_floor(Vector2(0, .1)))), String(id) + " has walkable entrance")
		for _i in 4: await process_frame
		check(player.get_meta("mountain_interior_id", &"") == id and root.get_camera_2d() == player.get_node("Camera"), String(id) + " keeps its identity and player camera")
		var bounds: Dictionary = preload("res://systems/interiors/InteriorSolidProjection.gd").mesh_bounds(room.cabin_3d_world)
		var signature := str(bounds)
		check(not signatures.has(signature), String(id) + " has a distinct furniture layout")
		signatures[signature] = true
		check(room.walls_body.get_child_count() >= 7, String(id) + " keeps projected furniture solids")
		if id == &"mountain_cabin":
			for pickup in ["LegendaryRifleStation", "WoodAxeStation", "HuntingKnifeStation"]:
				check(room.get_node_or_null(pickup) != null, String(id) + " retains " + pickup)
		else:
			var cash: Area2D = room.get_node("CabinCash")
			check(await walk_to(player, cash.global_position), String(id) + " reward is reachable")
			for _i in 4: await physics_frame
			check(cash.collected and player.money == entry_money + cash.amount, String(id) + " pays its unique reward once")
			cash._collect(player)
			check(player.money == entry_money + cash.amount, String(id) + " repeat contact cannot duplicate cash")
			if id == &"mountain_cabin_encosta": check(cash.amount == 5000, "Encosta keeps its 5000 reward")
		player.global_position = room.to_global(room.project_floor(Vector2(0, 1.0)))
		check(await walk_to(player, outside), String(id) + " has walkable exit")
		for _i in 4: await process_frame
		check(not player.has_meta("mountain_interior") and room.viewport_3d.render_target_update_mode == SubViewport.UPDATE_DISABLED, String(id) + " restores exterior and sleeps")
	print("DISTINCT_CABINS failed=", failed.size(), " layouts=", signatures.size())
	mountain.queue_free()
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
