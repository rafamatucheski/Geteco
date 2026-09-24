extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var mpr_script = load("res://world/mountain_pass/MountainPassRoad.gd")
	var mpr = mpr_script.new()
	root.add_child(mpr)
	
	print("MountainPassRoad control_points[0]: ", mpr.control_points[0])
	print("smooth_points size: ", mpr.smooth_points.size(), " first: ", mpr.smooth_points[0])
	if not mpr._cached_centerlines_low.is_empty():
		print("centerlines_low[0] size: ", mpr._cached_centerlines_low[0].size(), " first point: ", mpr._cached_centerlines_low[0][0])
	if not mpr._cached_edge_line_segments.is_empty():
		for i in range(mini(4, mpr._cached_edge_line_segments.size())):
			print("edge_line_segments[", i, "] first point: ", mpr._cached_edge_line_segments[i][0])
	
	var hmc = load("res://world/harbor/HarborMountainConnector.gd")
	var defs = hmc.road_definitions()
	print("HMC outbound last point: ", defs[0].points[-1])
	print("HMC inbound first point: ", defs[1].points[0])
	
	quit(0)
