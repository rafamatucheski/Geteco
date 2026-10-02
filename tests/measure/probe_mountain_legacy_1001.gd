extends SceneTree
const REGION := preload("res://world/regions/NativeRegion.gd")
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var region = REGION.build_region("mountain")
	root.add_child(region)
	var main: Dictionary = region.roads.filter(func(road): return road.id=="mountain_pass")[0]
	for id in ["mountain_track_1","mountain_track_2"]:
		var road: Dictionary = region.roads.filter(func(item): return item.id==id)[0]
		var distance := INF
		for i in range(main.points.size()-1):
			distance = minf(distance,road.points[0].distance_to(Geometry3D.get_closest_point_to_segment(road.points[0],main.points[i],main.points[i+1])))
		print("LEGACY_ROAD id=",id," start=",road.points[0]," main_distance=",distance)
	region.set_focus(CATALOG._at(Vector2(6250,340),"mountain"))
	region.set_focus(CATALOG._at(Vector2(6440,580),"mountain"))
	for i in 12: await physics_frame
	var yards := region.find_children("OriginalSawmillYard","MeshInstance3D",true,false)
	print("LEGACY_YARDS after_12_frames=",yards.size()," idle=",region.is_streaming_idle())
	for i in 1200:
		if region.is_streaming_idle(): break
		await process_frame
	yards = region.find_children("OriginalSawmillYard","MeshInstance3D",true,false)
	print("LEGACY_YARDS after_idle=",yards.size()," idle=",region.is_streaming_idle())
	for mesh in yards:
		print("LEGACY_YARD path=",mesh.get_path()," bounds=",mesh.global_transform*mesh.get_aabb()," material=",mesh.material_override.get_class())
	var origin := CATALOG._at(Vector2(6350,560),"mountain")
	for point in [Vector3(7,0,0),Vector3(4.4,0,0),Vector3(4.4,0,-4),Vector3(4.4,0,4),Vector3(10.2,0,0),Vector3(10.2,0,-4),Vector3(10.2,0,4)]:
		var ray := PhysicsRayQueryParameters3D.create(origin+point+Vector3.UP*2,origin+point-Vector3.UP,1)
		var hit := region.get_world_3d().direct_space_state.intersect_ray(ray)
		print("LEGACY_CONTACT local=",point," hit=",hit," path=",hit.collider.get_path() if not hit.is_empty() else "none")
	region.free()
	quit()
