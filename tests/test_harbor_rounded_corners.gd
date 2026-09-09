extends SceneTree

var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	var scene := load("res://district/harbor_preview/HarborPreview.tscn").instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	for i in 5:
		await physics_frame
	var network := scene.get_node("RoadNetwork")
	var graph: Dictionary = network.get_graph_data()
	var count := 0
	var samples := 0
	for junction in graph.junctions:
		var asphalt: Dictionary = network._build_junction_surface_geometry(junction, 0.0)
		if asphalt.construction != "rounded_street_corner":
			continue
		count += 1
		print("ROUNDED_CORNER ",junction.position," roads=",junction.road_ids)
		check(asphalt.polygon.size() >= 48, "Corner uses curved boundaries, not a four-point bevel")
		var a: Vector2 = asphalt.arms[0].direction
		var b: Vector2 = asphalt.arms[1].direction
		var hx := float(asphalt.arms[1].half_width)
		var hy := float(asphalt.arms[0].half_width)
		var center: Vector2 = junction.position
		for extra in [0.0, 4.0, 10.0, 84.0]:
			var geometry: Dictionary = network._build_junction_surface_geometry(junction,extra)
			check(not Geometry2D.triangulate_polygon(geometry.polygon).is_empty(), "Every corner layer triangulates")
			check(not Geometry2D.is_polygon_clockwise(geometry.polygon), "Consistent corner winding")
		var sidewalk: Dictionary = network._build_junction_surface_geometry(junction,84.0)
		for step in range(1,24):
			var angle := step * PI / 48.0
			var inside := center - a*(hx-2)*cos(angle) - b*(hy-2)*sin(angle)
			check(Geometry2D.is_point_in_polygon(inside,asphalt.polygon), "Outer turn has continuous asphalt, no missing square quadrant")
			var outside := center - a*(hx+3)*cos(angle) - b*(hy+3)*sin(angle)
			check(not Geometry2D.is_point_in_polygon(outside,asphalt.polygon), "Asphalt respects rounded outer boundary")
			check(Geometry2D.is_point_in_polygon(outside,sidewalk.polygon), "Sidewalk surrounds rounded asphalt")
			samples += 1
		# The new pocket is within the reserved corner, never a distant lot.
		for point in asphalt.polygon:
			check(point.distance_to(center)<180, "Fillet remains local to street corner")
	check(count >= 4, "Authored exterior street corners were actually matched")
	check(network.get_validation_errors().is_empty(), "Lane/surface validation remains empty")
	check(graph.lane_connections.size()>0, "Navigable lane connections retained")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless":
		root.size = Vector2i(1280,720)
		var camera := Camera2D.new()
		camera.position = Vector2(6450,2200)
		camera.zoom = Vector2(2.5,2.5)
		scene.add_child(camera)
		camera.make_current()
		for i in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("D:/geteco/harbor-rounded-corner.png")==OK,"Corner capture saved")
	print("HARBOR_ROUNDED_CORNERS corners=%d samples=%d failures=%d" % [count,samples,failures])
	scene.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
