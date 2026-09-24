extends SceneTree

var failed: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failed.append(label)

func run() -> void:
	var travel := root.get_node("RegionTravel")
	var offset: Vector2 = preload("res://world/harbor/ContinuousWorld.gd").MOUNTAIN_OFFSET
	for id in [
		&"mountain_cabin", &"mountain_cabin_encosta", &"mountain_cabin_forest",
		&"mountain_cabin_village_1", &"mountain_cabin_village_2",
		&"mountain_cabin_village_3", &"mountain_cabin_village_4",
		&"lumberjack_shelter", &"mountain_outfitters", &"mountain_village_outfitters",
		&"ski_lodge", &"mountain_bunker", &"mountain_mystery_cave",
	]:
		for version in [1, 2]:
			var shift: Vector2 = offset if version == 2 else Vector2.ZERO
			var old: Vector2 = Vector2(25000, 20000) + shift
			var safe: Vector2 = Vector2(6350, 600) + shift
			var data := {
				"world": {"region":"mountain", "coordinates_version":version, "interior":String(id), "exterior_return":[safe.x,safe.y]},
				"player": {"position":[old.x,old.y], "money":7511, "world_pickups_collected":["unique_reward"]},
			}
			travel.sanitize_saved_coordinates(data)
			var position: Array = data.player.position
			check(Vector2(position[0],position[1]).distance_to(safe) < 1 and data.world.interior == String(id), String(id) + " v" + str(version) + " keeps room ID at safe physical point")
			check(data.player.money == 7511 and data.player.world_pickups_collected == ["unique_reward"], String(id) + " v" + str(version) + " preserves inventory")
	var orphan := {"world":{"region":"mountain"}, "player":{"position":[40000,20000]}}
	travel.sanitize_saved_coordinates(orphan)
	check(Vector2(orphan.player.position[0],orphan.player.position[1]) == Vector2(3240,430) and not orphan.world.has("interior"), "orphaned off-map save returns to safe mountain arrival")
	var physical := {"world":{"region":"mountain", "coordinates_version":2}, "player":{"position":[10500.0,-4400.0]}}
	travel.sanitize_saved_coordinates(physical)
	check(Vector2(physical.player.position[0],physical.player.position[1]) == Vector2(10500,-4400), "physical mountain coordinates remain intact")
	print("MOUNTAIN_LEGACY failed=", failed.size())
	quit(0 if failed.is_empty() else 1)
