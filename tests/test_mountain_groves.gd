extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	seed(912)
	var world := Node2D.new()
	root.add_child(world)
	var road = preload("res://world/mountain_pass/MountainPassRoad.gd").new()
	world.add_child(road)
	var builder = preload("res://world/mountain_pass/MountainSceneryBuilder.gd")
	builder._init_dirt_roads()
	await builder.build_dense_pine_forest(world, road)
	await physics_frame
	var count := 0
	var rocks := 0
	var snow := 0
	var species := {}
	var failures := 0
	for prop in world.get_node("DensePineForest").get_children():
		if not prop.has_meta("mountain_grove"): continue
		count += 1
		if road.is_point_on_road(prop.position,130.0) or builder._is_point_on_dirt_road(prop.position,42.0): failures += 1
		if prop is StaticBody2D and prop.collision_layer != 1: failures += 1
		if prop.has_node("RockCollision"): rocks += 1
		else:
			if not prop.has_node("TrunkCol"): failures += 1
			species[prop.get_meta("forest_species")] = true
			if prop.is_snowy: snow += 1
	if count < 90 or rocks < 15 or snow < 25 or species.size() < 6: failures += 1
	print("GROVES count=%d rocks=%d snowy=%d species=%d failures=%d" % [count,rocks,snow,species.size(),failures])
	quit(1 if failures else 0)
