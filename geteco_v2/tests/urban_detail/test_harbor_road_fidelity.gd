extends SceneTree
## Directed Harbor road/streaming validator. Requires --no-save and never
## resolves a save path. Collision is checked independently from rendering.

var failures := 0


func check(value: bool, message: String) -> void:
	if value:
		print("PASS: ",message)
	else:
		failures += 1
		push_error("FAIL: "+message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("Harbor road fidelity validator refuses to run without --no-save")
		quit(2)
		return
	var native_region_script = load("res://world/regions/NativeRegion.gd")
	check(native_region_script != null,"NativeRegion compiles with source-derived road geometry")
	if native_region_script == null:
		quit(1)
		return
	var region: Node3D = native_region_script.build_region("harbor",Vector3(715.0/16.0,0,1800.0/16.0))
	root.add_child(region)
	for frame in 32: await process_frame
	check(region.roads.size()==39,"all 39 productive V1 road definitions are configured")
	check(region.harbor_road_geometry.source_coverage_errors().is_empty(),"source road segments and junctions have complete geometry")
	var detached_crossings:=0
	for records_value in region.records.values():
		for record_value in records_value:
			if String((record_value as Dictionary).get("kind",""))=="harbor_crosswalk": detached_crossings+=1
	check(detached_crossings==0,"no coordinate-authored V2 crosswalk duplicates the productive road contract")
	var authored_crossings := [
		{"road_id":"cobra_approach","t":.78},
		{"road_id":"cobra_court_northwest","t":.90},
	]
	for crossing_index in authored_crossings.size():
		var crossing:=authored_crossings[crossing_index] as Dictionary
		var road:=_road(region.roads,String(crossing.road_id))
		var sample:=_sample_polyline(road.points as PackedVector3Array,float(crossing.t))
		var stripe_count:=_crosswalk_stripes_at(region.harbor_road_geometry._crosswalk_white,sample.position,sample.tangent,float(road.width),26.0/16.0)
		check(stripe_count==5,"productive Ashbend crossing %d is projected once from its road-relative source"%crossing_index)
	for source_point in [Vector2(3750,3600),Vector2(5750,4770),Vector2(1182,2114),Vector2(7700,1400)]:
		check(not _crosswalk_near(region.harbor_road_geometry._crosswalk_white,source_point/16.0,1.0),"no invented zebra remains at V2 coordinate %s"%source_point)
	check(region.chunks.size()==9,"streaming preserves the productive 3x3 active budget")
	var center: Vector2i = region.current_cell
	var complete_ring := true
	for x in range(-1,2):
		for z in range(-1,2):
			complete_ring = complete_ring and region.chunks.has(center+Vector2i(x,z))
	check(complete_ring,"no active neighbour cell is left missing around the player")
	var has_source_asphalt := false
	var has_source_sidewalk := false
	var has_source_crosswalk := false
	var has_source_lot_surface := false
	var has_old_segment_boxes := false
	for chunk in region.chunks.values():
		for child in chunk.get_children():
			has_source_asphalt = has_source_asphalt or child.name=="HarborRoad_202932"
			has_source_sidewalk = has_source_sidewalk or child.name=="HarborRoad_aaa9a1"
			has_source_crosswalk = has_source_crosswalk or child.name=="HarborCrosswalk"
			has_source_lot_surface = has_source_lot_surface or child.name.begins_with("HarborSurface_")
			has_old_segment_boxes = has_old_segment_boxes or child.name=="Road"
	check(has_source_asphalt,"productive V1 asphalt material pass is mounted")
	check(has_source_sidewalk,"productive V1 sidewalk material pass is mounted")
	check(has_source_crosswalk,"productive signalized crosswalk geometry is mounted")
	check(has_source_lot_surface,"productive V1 lot and access paving is mounted")
	check(not has_old_segment_boxes,"independent overlapping road boxes are absent in Harbor")
	for frame in 3: await physics_frame
	var samples := [
		Vector2(400,1250)/16.0,
		Vector2(1300,1250)/16.0,
		Vector2(2200,1250)/16.0,
		Vector2(400,1718)/16.0,
	]
	for index in samples.size():
		var point: Vector2 = samples[index]
		region.set_focus(Vector3(point.x,0.0,point.y))
		for frame in 12: await process_frame
		var query := PhysicsRayQueryParameters3D.create(Vector3(point.x,8,point.y),Vector3(point.x,-2,point.y),1)
		var hit := root.world_3d.direct_space_state.intersect_ray(query)
		check(not hit.is_empty(),"collision ray %d reaches a physical surface"%index)
		if not hit.is_empty():
			var collider := hit.collider as Node
			check(collider.name.begins_with("HarborRoad_202932"),"collision ray %d hits the road mesh before base land"%index)
	var traversable_segments := 0
	var expected_segments := 0
	for road_value in region.roads:
		var road := road_value as Dictionary
		if String(road.get("surface", "asphalt")) != "asphalt": continue
		var points := road.points as PackedVector3Array
		for segment_index in range(points.size() - 1):
			expected_segments += 1
			var midpoint := points[segment_index].lerp(points[segment_index + 1], 0.5)
			region.set_focus(midpoint)
			for frame in 10: await process_frame
			await physics_frame
			var query := PhysicsRayQueryParameters3D.create(midpoint + Vector3.UP * 8.0, midpoint - Vector3.UP * 2.0, 1)
			var hit := root.world_3d.direct_space_state.intersect_ray(query)
			if not hit.is_empty() and (hit.collider as Node).name.begins_with("HarborRoad_202932"):
				traversable_segments += 1
			else:
				push_error("Missing road surface on %s segment %d" % [road.id, segment_index])
	check(traversable_segments == expected_segments, "every productive V1 road segment remains physical while streamed")
	var physical_accesses := 0
	var access_points: PackedVector2Array = region.harbor_urban_surface.source_access_points()
	for access_index in access_points.size():
		var access := access_points[access_index]
		var point := Vector3(access.x, 0.0, access.y)
		region.set_focus(point)
		for frame in 10: await process_frame
		await physics_frame
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 8.0, point - Vector3.UP * 2.0, 1)
		if not root.world_3d.direct_space_state.intersect_ray(query).is_empty():
			physical_accesses += 1
		else:
			push_error("Missing physical floor at V1 access %d" % access_index)
	check(physical_accesses == access_points.size(), "every productive V1 access has a physical traversal surface")
	region.queue_free()
	await process_frame
	print("HARBOR_ROAD_FIDELITY failures=",failures)
	quit(1 if failures else 0)


func _road(roads: Array[Dictionary],road_id: String)->Dictionary:
	for road in roads:
		if String(road.id).get_file()==road_id: return road
	return {}


func _sample_polyline(points: PackedVector3Array,t: float)->Dictionary:
	var total:=0.0
	for index in range(points.size()-1): total+=points[index].distance_to(points[index+1])
	var target:=total*clampf(t,0.0,1.0)
	var travelled:=0.0
	for index in range(points.size()-1):
		var length:=points[index].distance_to(points[index+1])
		if target<=travelled+length or index==points.size()-2:
			var local:=clampf((target-travelled)/maxf(length,.0001),0.0,1.0)
			var point:=points[index].lerp(points[index+1],local)
			return {"position":Vector2(point.x,point.z),"tangent":Vector2(points[index+1].x-points[index].x,points[index+1].z-points[index].z).normalized()}
		travelled+=length
	return {}


func _crosswalk_stripes_at(polygons: Array[PackedVector2Array],center: Vector2,tangent: Vector2,width: float,depth: float)->int:
	var count:=0
	var normal:=tangent.orthogonal()
	for polygon in polygons:
		var centroid:=Vector2.ZERO
		for point in polygon: centroid+=point
		centroid/=polygon.size()
		var delta:=centroid-center
		if absf(delta.dot(tangent))<=depth*.5+.01 and absf(delta.dot(normal))<=width*.5+.01: count+=1
	return count


func _crosswalk_near(polygons: Array[PackedVector2Array],point: Vector2,radius: float)->bool:
	for polygon in polygons:
		for vertex in polygon:
			if vertex.distance_to(point)<=radius: return true
	return false
