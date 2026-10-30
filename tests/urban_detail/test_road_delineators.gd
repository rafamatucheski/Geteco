extends SceneTree
const DESERT := preload("res://world/desert/DesertRoadGeometry.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const REGION := preload("res://world/regions/NativeRegion.gd")
const MOUNTAIN := preload("res://world/mountain_detail/MountainRoadside3D.gd")
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ",message)
	else: failures += 1; push_error(message)
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var geometry := DESERT.new()
	var roads := LAYOUT.roads()
	geometry.configure(roads)
	var clear := true
	for pose in geometry._delineators._points:
		var point := Vector2(pose.origin.x,pose.origin.z)
		for road in roads:
			var points: PackedVector3Array = road.points
			for i in range(points.size()-1):
				var a := Vector2(points[i].x,points[i].z)
				var b := Vector2(points[i+1].x,points[i+1].z)
				if point.distance_to(Geometry2D.get_closest_point_to_segment(point,a,b)) < float(road.width)*.5+.3: clear = false
	check(not geometry._delineators._points.is_empty(),"Open desert highways contain delineators")
	check(clear,"Desert delineators remain outside all carriageways")
	var region = REGION.build_region("mountain")
	region.prepare_data()
	var roadside := MOUNTAIN.new()
	roadside._build_delineators(region)
	# Os lotes ficam no nó MountainDelineators (dono do registro de quebráveis desde 29/10).
	var batches := roadside.find_children("*","MultiMeshInstance3D",true,false).size()
	check(batches>0,"Mountain roads contain delineators")
	check(roadside.find_children("*","Light3D",true,false).is_empty(),"Passive mountain markers allocate no extra lights")
	print("ROAD_DELINEATORS failures=",failures," desert_markers=",geometry._delineators._points.size()," mountain_batches=",batches)
	roadside.free()
	region.free()
	quit(0 if failures==0 else 1)
