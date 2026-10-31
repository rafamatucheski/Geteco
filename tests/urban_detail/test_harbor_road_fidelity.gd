extends SceneTree
## Validador dirigido de ruas/streaming do Harbor. Exige --no-save e nunca
## resolve um caminho de save. A colisão é conferida independente da renderização.

const TUNNEL := preload("res://world/urban_detail/CanalTunnel3D.gd")
const SOURCE_PATH := "res://world/regions/OriginalWorldData.json"
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
	# Os vizinhos são construídos em fatias; o número de quadros até completar
	# depende da carga da máquina. Inspecione o anel somente após o streaming.
	for frame in 600:
		await process_frame
		if region.is_streaming_idle(): break
	check(region.is_streaming_idle(),"initial Harbor 3x3 streaming finishes before geometry checks")
	check_source_roads(region.roads)
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
		for frame in 600:
			await process_frame
			if region.is_streaming_idle(): break
		check(region.is_streaming_idle(),"streaming finishes before collision ray %d"%index)
		await physics_frame
		var query := PhysicsRayQueryParameters3D.create(Vector3(point.x,8,point.y),Vector3(point.x,-2,point.y),1)
		var hit := root.world_3d.direct_space_state.intersect_ray(query)
		check(not hit.is_empty(),"collision ray %d reaches a physical surface"%index)
		if not hit.is_empty():
			var asphalt_hit := (hit.collider as Node).name.begins_with("HarborRoad_202932")
			var exclusions: Array[RID] = []
			for attempt in 32:
				if asphalt_hit: break
				exclusions.append((hit.collider as CollisionObject3D).get_rid())
				query.exclude = exclusions
				hit = root.world_3d.direct_space_state.intersect_ray(query)
				if hit.is_empty(): break
				asphalt_hit = (hit.collider as Node).name.begins_with("HarborRoad_202932")
			check(asphalt_hit,"collision ray %d reaches the road collider despite coplanar land"%index)
	var traversable_segments := 0
	var expected_segments := 0
	for road_value in region.roads:
		var road := road_value as Dictionary
		if String(road.get("surface", "asphalt")) != "asphalt": continue
		var points := road.points as PackedVector3Array
		for segment_index in range(points.size() - 1):
			expected_segments += 1
			var midpoint := points[segment_index].lerp(points[segment_index + 1], 0.5)
			var tunnel_sample := _open_tunnel_ramp(midpoint)
			var floor_point := Vector3(midpoint.x, TUNNEL.floor_y(midpoint.x), midpoint.z) if tunnel_sample else midpoint
			region.set_focus(midpoint)
			for frame in 600:
				await process_frame
				if region.is_streaming_idle(): break
			await physics_frame
			# Asfalto e terreno compartilham y=0 para o carro não bater numa borda.
			# Exclui superfícies sobrepostas até verificar o colisor da própria rua.
			var exclusions: Array[RID] = []
			var road_hit := false
			var first_hit := ""
			for attempt in 32:
				var query := PhysicsRayQueryParameters3D.create(floor_point + Vector3.UP * (1.0 if tunnel_sample else 8.0), floor_point - Vector3.UP * (1.0 if tunnel_sample else 2.0), 1)
				query.exclude = exclusions
				var hit := root.world_3d.direct_space_state.intersect_ray(query)
				if hit.is_empty(): break
				var collider := hit.collider as CollisionObject3D
				if attempt == 0: first_hit = collider.name
				if (_correct_tunnel_floor(hit, midpoint) if tunnel_sample else collider.name.begins_with("HarborRoad_202932")):
					road_hit = true
					break
				exclusions.append(collider.get_rid())
			if road_hit:
				traversable_segments += 1
			else:
				push_error("Missing road surface on %s segment %d point=%s first_hit=%s idle=%s" % [road.id, segment_index, midpoint, first_hit, region.is_streaming_idle()])
	check(traversable_segments == expected_segments, "every productive V1 road segment remains physical while streamed")
	var physical_accesses := 0
	var access_points: PackedVector2Array = region.harbor_urban_surface.source_access_points()
	for access_index in access_points.size():
		var access := access_points[access_index]
		var point := Vector3(access.x, 0.0, access.y)
		region.set_focus(point)
		for frame in 600:
			await process_frame
			if region.is_streaming_idle(): break
		await physics_frame
		var tunnel_sample := _open_tunnel_ramp(point)
		var floor_point := Vector3(point.x, TUNNEL.floor_y(point.x), point.z) if tunnel_sample else point
		var query := PhysicsRayQueryParameters3D.create(floor_point + Vector3.UP * (1.0 if tunnel_sample else 8.0), floor_point - Vector3.UP * (1.0 if tunnel_sample else 2.0), 1)
		var hit := root.world_3d.direct_space_state.intersect_ray(query)
		if (_correct_tunnel_floor(hit, point) if tunnel_sample else not hit.is_empty()):
			physical_accesses += 1
		else:
			push_error("Missing physical floor at V1 access %d" % access_index)
	check(physical_accesses == access_points.size(), "every productive V1 access has a physical traversal surface")
	region.queue_free()
	await process_frame
	print("HARBOR_ROAD_FIDELITY failures=",failures)
	quit(1 if failures else 0)


func check_source_roads(roads: Array[Dictionary]) -> void:
	# Entrada de origem independente: compara cada ID, ponto e largura, em vez de
	# congelar uma contagem que ficou obsoleta quando a lista autoral de ruas mudou.
	var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
	check(decoded is Dictionary, "productive road source is a readable dictionary")
	if not decoded is Dictionary: return
	var rows: Array = (decoded as Dictionary).get("harbor_roads", [])
	var actual: Dictionary = {}
	for road: Dictionary in roads: actual[String(road.id)] = road
	check(not rows.is_empty() and roads.size() == rows.size() and actual.size() == rows.size(), "all source road definitions are configured once")
	var source_ids: Dictionary = {}
	for row: Dictionary in rows:
		var id := String(row.id)
		check(not source_ids.has(id), "source road ID is unique: " + id)
		source_ids[id] = true
		var match_source := actual.has(id)
		if match_source:
			var road: Dictionary = actual[id]
			var points: PackedVector3Array = road.points
			var original: Array = row.points
			match_source = points.size() == original.size() and absf(float(road.width) - float(row.width) / 16.0) < .000001
			if match_source:
				for index in original.size():
					var point: Array = original[index]
					var expected := Vector3(float(point[0]) / 16.0, 0.0, float(point[1]) / 16.0)
					if points[index].distance_to(expected) > .000001:
						match_source = false
						break
		check(match_source, "road matches independent source ID/coordinates/width: " + id)


func _open_tunnel_ramp(point: Vector3) -> bool:
	if not TUNNEL.in_roadway(point): return false
	for cut: Rect2 in TUNNEL.open_cuts():
		if cut.has_point(Vector2(point.x, point.z)): return true
	return false


func _tunnel_normal(x: float) -> Vector3:
	# Derivada analítica do perfil autoral parabólico/linear do piso.
	var west := x - TUNNEL.W_TOP
	var east := TUNNEL.E_TOP - x
	var u := minf(west, east)
	var gradient := 0.0
	var length := TUNNEL.ramp_length()
	if u > 0.0 and u < length:
		if u < TUNNEL.CURVE: gradient = TUNNEL.GRADE * u / TUNNEL.CURVE
		elif u < length - TUNNEL.CURVE: gradient = TUNNEL.GRADE
		else: gradient = TUNNEL.GRADE * (length - u) / TUNNEL.CURVE
	var slope := -gradient if west <= east else gradient
	return Vector3(-slope, 1.0, 0.0).normalized()


func _correct_tunnel_floor(hit: Dictionary, point: Vector3) -> bool:
	if hit.is_empty(): return false
	var owner: Node = hit.collider as Node
	while owner != null and not owner.is_in_group("canal_tunnel"): owner = owner.get_parent()
	var height_error := absf(float(hit.position.y) - TUNNEL.floor_y(point.x))
	var normal_error := (hit.normal as Vector3).distance_to(_tunnel_normal(point.x))
	# Trechos curvos são tesselados fisicamente em vãos <=1 m: a tangente analítica
	# pode diferir em <=0.01042; rampas lineares (os dois pontos que falhavam antes)
	# são exatas. Um sólido na altura antiga da rua ou uma parede não satisfaz isto.
	var ok := owner != null and height_error < .01 and normal_error < .012
	print("TUNNEL_FLOOR point=%s hit=%s normal=%s expected_y=%.7f expected_normal=%s owner=%s valid=%s" % [
		point, hit.position, hit.normal, TUNNEL.floor_y(point.x), _tunnel_normal(point.x),
		str(owner.get_path()) if owner != null else "none", ok])
	return ok


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
