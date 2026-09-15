extends SceneTree
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var region := Node2D.new()
	region.position = Vector2(14000,-8000)
	root.add_child(region)
	var builder := preload("res://world/mountain_pass/MountainSceneryBuilder.gd")
	builder._init_dirt_roads()
	builder.build_backcountry_dirt_roads(region)
	var cave := Node2D.new()
	region.add_child(cave)
	builder.build_detailed_cave_cache(cave)
	var minimap := preload("res://ui/HarborMinimap.gd").new()
	minimap._cache_dirt_paths(region)
	var ok: bool = minimap._dirt_paths.size() == 5
	ok = ok and minimap._dirt_paths[0].points[0].is_equal_approx(region.to_global(Vector2(6350,560)))
	var cave_path: Dictionary = minimap._dirt_paths.back()
	ok = ok and cave_path.points[0].is_equal_approx(region.to_global(Vector2(6200,-320)))
	minimap._cache_dirt_paths(region)
	ok = ok and minimap._dirt_paths.size() == 5
	print("PASS dirt roads and cave approach mapped with world offset, without duplicates" if ok else "FAIL minimap dirt paths")
	minimap.free()
	region.queue_free()
	await process_frame
	quit(0 if ok else 1)
