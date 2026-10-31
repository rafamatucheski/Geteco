extends SceneTree
## Dados reais do Harbor, isolados dos saves do jogador. A folga de pista/pedestre
## e a posse em streaming independem da revisão visual.
const REGION := preload("res://world/regions/NativeRegion.gd")
var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
	else: print("PASS: ", message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var region = REGION.build_region("harbor")
	region.prepare_data()
	var geometry = region.harbor_road_geometry
	var signs = geometry._traffic_signs
	var entries := {}
	for junction in geometry.crossing_layout:
		for entry in junction.entries:
			if entry.enabled: entries[entry.key] = entry
	check(not signs.records.is_empty(), "Real Harbor has pedestrian warning signs")
	var road_clear := true
	var walking_clear := true
	var associated := true
	for record in signs.records:
		associated = associated and entries.has(record.crossing_key)
		if entries.has(record.crossing_key):
			var entry: Dictionary = entries[record.crossing_key]
			walking_clear = walking_clear and float(entry.sidewalk) - .78 - .045 >= 1.2
		for road in region.roads:
			var points: PackedVector3Array = road.points
			for i in range(points.size() - 1):
				var at: Vector2 = record.position
				var a := Vector2(points[i].x, points[i].z)
				var b := Vector2(points[i+1].x, points[i+1].z)
				road_clear = road_clear and at.distance_to(Geometry2D.get_closest_point_to_segment(at,a,b)) >= float(road.width)*.5+.3
	check(associated, "Every warning refers to an enabled crossing")
	check(road_clear, "Signposts stay outside every carriageway")
	check(walking_clear, "At least 1.2m of sidewalk remains behind posts")
	var owner := Node3D.new()
	root.add_child(owner)
	var count := 0
	for x in range(-12, 13):
		for z in range(-12, 13):
			var chunk := Node3D.new()
			owner.add_child(chunk)
			signs.build_chunk(chunk, Rect2(x*64,z*64,64,64))
			count += chunk.find_children("*", "CollisionShape3D", true, false).size()
	check(count == signs.records.size(), "Chunk boundaries neither duplicate nor lose signposts")
	for frame in 3: await physics_frame
	if not signs.records.is_empty():
		var at: Vector2 = signs.records[0].position
		var center := Vector3(at.x,1.0,at.y)
		var query := PhysicsRayQueryParameters3D.create(center-Vector3.RIGHT, center+Vector3.RIGHT, 1)
		check(not owner.get_world_3d().direct_space_state.intersect_ray(query).is_empty(), "A signpost is physically solid at its visible position")
	var details := Node3D.new()
	geometry._sidewalk_details.build_chunk(details, Rect2(0,0,256,256))
	check(details.get_child_count() > 0, "Sidewalk finish is generated on real Harbor roads")
	check(details.find_children("*", "CollisionObject3D", true, false).is_empty(), "Flush sidewalk details add no physical obstacle")
	details.free()
	owner.free()
	region.free()
	print("HARBOR_STREET_REALISM failures=", failures, " signs=", count)
	quit(0 if failures == 0 else 1)
