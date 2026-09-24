extends SceneTree
const REGION = preload("res://world/regions/NativeRegion.gd")
const HEAT = preload("res://runtime/cold/OriginalHeatSources.gd")
const LAKE = preload("res://world/regions/NativeLake.gd")
var errors: Array[String] = []
var checks := 0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: errors.append(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var region = REGION.build_region("mountain")
	root.add_child(region)
	var pad := HEAT.to_world(Vector2(6335,-2795))
	for entries in region.records.values():
		for record in entries:
			if record.kind == "tree":
				check(record.position.distance_to(pad)>=125.0/16,"helipad canopy reservation")
	var east_vale: Dictionary = region.roads.filter(func(road): return road.id=="mountain_track_1")[0]
	check(east_vale.surface=="earth" and is_equal_approx(east_vale.width,60.0/16),"EastVale original dirt width/type")
	check(east_vale.points[0]==HEAT.to_world(Vector2(6250,340)),"EastVale joins the main pass axis")
	region.set_focus(HEAT.to_world(Vector2(6250,340)))
	var road_surfaces := region.find_children("RoadSurface","MeshInstance3D",true,false)
	check(not road_surfaces.is_empty(),"connected mountain road surface is built")
	if not road_surfaces.is_empty():
		var normals: PackedVector3Array = road_surfaces[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
		check(not normals.is_empty() and normals[0].y > .5,"road surface faces upward")
	var ammu: Dictionary = region.roads.filter(func(road): return road.id=="mountain_track_2")[0]
	check(ammu.points[0]==HEAT.to_world(Vector2(6950,-250)),"Ammu-Nation road joins the main pass axis")
	var alpine = LAKE.new()
	alpine.variant = "alpine"
	alpine.position = HEAT.to_world(Vector2(7000,0))
	root.add_child(alpine)
	check(alpine.contains_water(HEAT.to_world(Vector2(7000,100))),"alpine lake retains walkable water")
	for i in range(ammu.points.size()-1):
		var a: Vector3 = ammu.points[i]
		var b: Vector3 = ammu.points[i+1]
		for step in range(1,12):
			check(not alpine.contains_water(a.lerp(b,float(step)/12.0)),"Ammu-Nation road stays out of water")
	region.set_focus(HEAT.to_world(Vector2(6440,580)))
	for i in 12: await physics_frame
	var yards := region.find_children("OriginalSawmillYard","MeshInstance3D",true,false)
	check(yards.size()==1,"original sawmill yard exists")
	if not yards.is_empty():
		var bounds: AABB = yards[0].global_transform*yards[0].get_aabb()
		var at := HEAT.to_world(Vector2(6440,580))
		check(bounds.position.x<at.x and bounds.end.x>at.x and bounds.position.z<at.z and bounds.end.z>at.z,"original fire lies on authored yard")
	region.set_focus(HEAT.to_world(Vector2(5655,-990)))
	for i in 12: await physics_frame
	var camps := region.find_children("SmugglerCampsite","MeshInstance3D",true,false)
	var water := region.find_children("GlacialShallows","MeshInstance3D",true,false)
	check(camps.size()==1 and water.size()==1,"camp and lake present")
	if not camps.is_empty() and not water.is_empty():
		var camp_y: float = camps[0].global_position.y+camps[0].get_aabb().position.y
		var water_y: float = water[0].global_position.y+water[0].get_aabb().position.y
		check(camp_y>water_y,"dry campsite occludes water")
		var lake = camps[0].get_parent()
		check(not lake.contains_water(HEAT.to_world(Vector2(5655,-990))),"fire site remains classified dry")
	for point in [HEAT.to_world(Vector2(5655,-990)),HEAT.to_world(Vector2(6440,580)),pad]:
		region.set_focus(point)
		for i in 12: await physics_frame
		var ray := PhysicsRayQueryParameters3D.create(point+Vector3.UP*2,point-Vector3.UP,1)
		check(not region.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(),"physical ground at source/pad")
	for source_point in [Vector2(6250,340),Vector2(6290,363),Vector2(6350,398),Vector2(6950,-250),Vector2(7000,-275)]:
		var point: Vector3 = HEAT.to_world(source_point)
		region.set_focus(point)
		await physics_frame
		var ray := PhysicsRayQueryParameters3D.create(point+Vector3.UP*2,point-Vector3.UP,1)
		var hit := region.get_world_3d().direct_space_state.intersect_ray(ray)
		check(not hit.is_empty() and hit.normal.y > .6 and hit.position.y > -.1,"road junction has walkable physical contact")
	check(region.find_children("Sidewalk","MeshInstance3D",true,false).is_empty(),"rural roads have no overlapping generic sidewalks")
	alpine.free()
	region.free()
	print("COLD_TERRAIN checks=",checks," failures=",errors)
	quit(0 if errors.is_empty() else 1)
