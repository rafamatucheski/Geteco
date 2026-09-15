extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)

func run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	create_timer(120.0).timeout.connect(func():
		printerr("FAIL: mountain ski integration timed out")
		quit(2)
	)
	var packed := load("res://world/mountain_pass/MountainPass.tscn") as PackedScene
	expect(packed != null, "MountainPass scene loads")
	if packed == null:
		quit(1)
		return
	var mountain := packed.instantiate()
	root.add_child(mountain)
	current_scene = mountain
	while not mountain.region_ready:
		await process_frame

	var ski_area := mountain.get_node_or_null("MountainSkiArea")
	expect(ski_area != null, "ski area is part of the existing MountainPass")
	if ski_area:
		expect(ski_area.get_tree().get_nodes_in_group("ski_race").size() == 3, "three ski trials are registered")
		expect(ski_area.find_children("AmbientSkier*", "CharacterBody2D", true, false).size() >= 6, "ambient skiers populate the slopes")
		expect(ski_area.find_children("Gate_*", "Node2D", true, false).size() >= 12, "3D course gates cover every route")
		var trees := get_nodes_in_group("ski_boundary_tree")
		expect(trees.size() >= 20, "snowy treeline gives the slopes a forest setting")
		for tree in trees:
			for course in preload("res://world/mountain_pass/MountainSkiLayout.gd").COURSES:
				var points := preload("res://world/mountain_pass/MountainSkiLayout.gd").all_course_points(course)
				for i in range(points.size() - 1):
					var center := Geometry2D.get_closest_point_to_segment(tree.position, points[i], points[i + 1])
					expect(center.distance_to(tree.position) >= 145.0, "trees preserve ski routes and their recovery margins")

	var settlement := mountain.get_node_or_null("MountainSettlement")
	var lodge := settlement.find_child("SummitSkiLodge", true, false) if settlement else null
	expect(lodge != null, "summit pocket contains the ski lodge")
	if lodge:
		expect(lodge.get("model") is Node3D, "ski lodge exterior is rendered from a Node3D model")
		expect(lodge.get_node_or_null("SkiLodgeEntrance") != null, "ski lodge entrance is interactive")

	var manager: Node = mountain.interior_manager
	expect(manager._interiors.has(&"ski_lodge"), "ski lodge interior is registered")
	expect(manager._interiors.has(&"mountain_mystery_cave"), "waterfall cave interior is registered")
	var lodge_room: Node = manager._interiors.get(&"ski_lodge")
	if lodge_room:
		expect(lodge_room.get("room_view").get("model") is Node3D, "lodge interior is rendered from a Node3D model")
		expect(lodge_room.get_node_or_null("RentalCounter") != null, "rental counter exists")
		expect(lodge_room.get_node_or_null("EquipmentRack") != null, "equipment rack exists")
		expect(lodge_room.get_node_or_null("SlopeExit") != null, "rear slope exit exists")

	var cave_cache := mountain.find_child("CaveCache", true, false)
	var waterfall := cave_cache.find_child("WaterfallCaveExterior", true, false) if cave_cache else null
	expect(waterfall != null, "the original CaveCache was adapted into the waterfall cave")
	if waterfall:
		expect(waterfall.get("model") is Node3D, "waterfall location is rendered from a Node3D model")
	expect(cave_cache.find_child("AbandonedExpeditionPack", true, false) != null if cave_cache else false, "explorer pack clue is placed by the waterfall")

	for id in ["mountain_expedition_pack", "mountain_expedition_journal", "mountain_expedition_camera"]:
		expect(CollectibleCatalog.has_entry(id), "collectible catalog contains " + id)

	var player: Node = mountain.player_instance
	expect(player != null, "MountainPass player exists")
	if player:
		player.money = 1000
		var money_before: int = player.money
		expect(player.begin_ski_rental(250), "player can rent the ski outfit")
		expect(player.money == money_before - 250 and player.current_outfit_id == "dante_ski", "rental charges once and equips the ski suit")
		var slope_exit: BuildingEntrance = lodge_room.get_node("SlopeExit")
		player.set_meta("mountain_interior", true)
		player.set_meta("mountain_interior_id", &"ski_lodge")
		manager._actor_returns[player] = player.global_position
		var blocked_position: Vector2 = player.global_position
		manager._on_exit_requested(slope_exit, player, &"", null, &"", &"ski_lodge")
		expect(player.global_position == blocked_position and player.has_meta("mountain_interior"), "rear exit stays locked until skis are collected")
		player.take_ski_equipment()
		expect(player.ski_equipment_ready, "rack grants skis and poles")
		manager._on_exit_requested(slope_exit, player, &"", null, &"", &"ski_lodge")
		expect(player.is_skiing and not player.has_meta("mountain_interior"), "rear exit places the player on skis on the far side")
		player.global_position = mountain.to_global(Vector2(6600, -3100))
		var skis: Node = player.ski_controller
		skis._update_trails(0.06)
		player.global_position += Vector2(0, -20)
		skis._update_trails(0.06)
		expect(skis.trail_left.get_point_count() == 2 and skis.trail_right.get_point_count() == 2, "continuous skiing leaves two parallel tracks")
		player.global_position += Vector2(0, -1200)
		skis._update_trails(0.06)
		expect(skis.trail_left.get_point_count() == 1 and skis.trail_right.get_point_count() == 1, "teleport does not draw a track across the mountain")
		var health_before: int = player.health
		player.ski_controller.crash(10, Vector2(0, -120))
		expect(player.ski_controller.falling and player.health == health_before - 10, "ski falls trigger recovery and health damage")
		player.stop_skiing()
		expect(skis.trail_left.get_point_count() == 0 and skis.trail_right.get_point_count() == 0, "removing skis clears tracks before lift travel or entering a room")
		for id in ["mountain_expedition_pack", "mountain_expedition_journal", "mountain_expedition_camera"]:
			player.add_collectible(id, id)
		await process_frame
		await process_frame
		var monster := mountain.find_child("MountainShadow", true, false)
		expect(monster != null and monster.get("active") == true, "all explorer clues reveal the 3D mountain creature")
		expect("mountain_legend" in player.unlocked_achievements, "the complete mystery unlocks its achievement")
		player.return_ski_rental()
		expect(not player.ski_rental_active and not player.ski_equipment_ready and player.current_outfit_id == "dante_classic", "returning the rental restores the previous outfit")

	if failures.is_empty():
		print("PASS: mountain ski lodge, far-side slopes, races, waterfall cave and monster mystery")
	quit(0 if failures.is_empty() else 1)
