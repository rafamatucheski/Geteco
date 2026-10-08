extends SceneTree
## Finite contracts for the real region/room nodes. Rendered depth and frame-time need separate capture.
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const REGION := preload("res://world/desert/DesertRegion.gd")
const PLACE := preload("res://world/places/NativePlace.gd")
const SURFACE_PROBE := preload("res://gameplay/vehicle_effects/VehicleSurfaceProbe.gd")
var failures: Array[String]=[]
var checks := 0
func _initialize() -> void: _run.call_deferred()
func check(value: bool, label: String) -> void:
	checks+=1
	if not value: failures.append(label)
func _run() -> void:
	var gateway := preload("res://world/north_gateway/NorthGatewayLayout.gd")
	check(LAYOUT.BRIDGE_END.is_equal_approx(Vector3(gateway.TERMINAL.x,gateway.DECK_HEIGHT,gateway.END_Z)),"Arrival meets existing bridge exactly")
	check(is_equal_approx(LAYOUT.surface_height(Vector2(342.5,-373.5)),2.4),"Bridge shore has continuous support height")
	check(is_zero_approx(LAYOUT.surface_height(Vector2(342.5,-445))),"Ramp descends smoothly to basin")
	var road_data := LAYOUT.roads()
	var longest := 0.0
	for road in road_data:
		for i in range(1,road.points.size()): longest=maxf(longest,road.points[i-1].distance_to(road.points[i]))
	check(longest>1400,"Desert has an uninterrupted highway straight over 1.4km")
	# Safety property: traffic must never cross an authored building, regardless of coordinates.
	for building in LAYOUT.buildings():
		var footprint := Rect2(Vector2(building.position.x,building.position.z)-Vector2(building.size.x,building.size.z)*.5,Vector2(building.size.x,building.size.z))
		var conflicts: Array[String]=[]
		for road in road_data:
			for i in range(1,road.points.size()):
				var a := Vector2(road.points[i-1].x,road.points[i-1].z)
				var b := Vector2(road.points[i].x,road.points[i].z)
				var pavement := Rect2(Vector2(minf(a.x,b.x),minf(a.y,b.y)),Vector2(absf(a.x-b.x),absf(a.y-b.y)))
				if absf(a.x-b.x)>absf(a.y-b.y): pavement=pavement.grow_individual(0,float(road.width)*.5,0,float(road.width)*.5)
				else: pavement=pavement.grow_individual(float(road.width)*.5,0,float(road.width)*.5,0)
				if footprint.intersects(pavement): conflicts.append(str(road.id))
		check(conflicts.is_empty(),"Carriageways clear building %s: %s"%[building.id,conflicts])
	for road in road_data:
		if str(road.id).begins_with("desert_drag"): check(not road.traffic,"Drag is excluded from ambient traffic")
	var graph := preload("res://gameplay/NativeTrafficRoutes.gd").new()
	graph.configure(road_data.filter(func(road: Dictionary): return road.get("traffic",true)))
	for endpoints in [[LAYOUT.BRIDGE_END,Vector3(-210,0,-907)],[Vector3(-210,0,-907),LAYOUT.BRIDGE_END],[Vector3(290,0,-750),Vector3(-140,0,-980)],[Vector3(-140,0,-980),Vector3(290,0,-750)]]:
		var route: Curve3D=graph.route_between(endpoints[0],endpoints[1])
		check(route!=null and route.point_count>2,"Directed route joins bridge, town, bank, workshop and truck stop")
	var separated := true
	for segment in graph.segments:
		if str(segment.id).begins_with("desert_drag"): separated=false
	check(separated,"Real ambient graph excludes racing strip")
	var warm_region := REGION.new()
	warm_region.initial_prewarm_only=true
	root.add_child(warm_region)
	warm_region.prewarm()
	check(not warm_region.buildings.is_empty() and warm_region.buildings.all(func(building: Dictionary): return building.size is Vector2 and building.size.x>0 and building.size.y>0),"Public building geography exposes planar Vector2 footprints to minimap")
	var art_sizes_preserved := true
	for cell_records in warm_region.records.values():
		for record in cell_records:
			if record.kind=="building" and not record.data.size is Vector3: art_sizes_preserved=false
	check(art_sizes_preserved,"Architectural records retain native Vector3 dimensions")
	check(warm_region.chunks.is_empty() and warm_region.is_streaming_idle(),"Distant prewarm without focus never builds spawn neighbourhood")
	warm_region.set_focus(warm_region.spawn_position)
	check(warm_region.chunks.has(warm_region._cell(warm_region.spawn_position)),"Explicit focus admits initial bridge spawn after prewarm")
	for i in 180:
		if warm_region.is_streaming_idle(): break
		await process_frame
	await physics_frame
	await physics_frame
	_ramp_layers(warm_region)
	warm_region.free()
	var region := REGION.new()
	region.initial_focus=LAYOUT.TRUCK_STOP
	root.add_child(region)
	for i in 180:
		if region.is_streaming_idle(): break
		await process_frame
	check(region.is_streaming_idle(),"Truck stop streaming settles finitely")
	await physics_frame
	check(_floor(Vector3(342.5,0,-750)),"Highway has physical road support")
	check(_floor(Vector3(270,0,-758)),"Truck-stop NPC position has floor")
	var probe_car := CharacterBody3D.new()
	probe_car.collision_layer=0
	root.add_child(probe_car)
	var asphalt_contact := SURFACE_PROBE.sample(probe_car,Vector3(342.5,.2,-750))
	var sand_contact := SURFACE_PROBE.sample(probe_car,Vector3(352,.2,-770))
	check(not asphalt_contact.is_empty() and asphalt_contact.kind=="hard","Real wheel ray classifies weathered asphalt as hard")
	check(not sand_contact.is_empty() and sand_contact.kind=="dirt","Real wheel ray classifies desert sand as dirt")
	probe_car.free()
	var parked := 0
	for node in region.find_children("*","Node3D",true,false):
		if node.get_meta("vehicle_kind","")=="bitrem":
			parked+=1
			check(node.get_meta("trailer_count")==2,"Parked road train has two trailers")
	check(parked==4,"Four large bitrems are actually instantiated at stop")
	region.set_focus(LAYOUT.TOWN)
	for i in 180:
		if region.is_streaming_idle(): break
		await process_frame
	await physics_frame
	for definition in LAYOUT.place_definitions():
		check(_floor(definition.entry_position),"Exterior entry supported: "+definition.id)
		check(_clear(definition.entry_position),"Exterior entry clear: "+definition.id)
		var room := PLACE.new()
		room.definition=definition
		room.position=Vector3(0,0,-3000)
		root.add_child(room)
		await physics_frame
		await physics_frame
		check(room.is_floor_clear(definition.spawn,.34),"Spawn clear: "+definition.id)
		check(room.is_floor_clear(definition.exit,.34),"Exit clear: "+definition.id)
		check(_clear(room.spawn_position),"Real physics admits actor capsule: "+definition.id)
		check(_floor(room.spawn_position),"Real room floor supports actor: "+definition.id)
		var target := Vector3(0,0,-2.6) if definition.id=="desert_bank" else Vector3(8.4,0,0)
		check(not room.is_floor_clear(target,.34),"Furniture blocks full footprint: "+definition.id)
		var service := Vector3(-1.5,0,-1.35) if definition.id=="desert_bank" else Vector3(8.4,0,1.65)
		check(room.is_floor_clear(service,.34),"Service is on accessible customer side: "+definition.id)
		check(_clear(room.to_global(service)),"Physics confirms service capsule: "+definition.id)
		var clerk := Vector3(-1.5,0,-3.45) if definition.id=="desert_bank" else Vector3(8.4,0,-1.2)
		check(room.is_floor_clear(clerk,.34),"Resident fits behind desk: "+definition.id)
		room.free()
	var count := region.chunks.size()
	region.set_focus(LAYOUT.drag_start_point())
	for i in 180:
		if region.is_streaming_idle(): break
		await process_frame
	check(region.chunks.size()<=25 and count<=25,"Streaming residency bounded independently of map area")
	await physics_frame
	check(_floor(LAYOUT.drag_start_point()+Vector3(0,0,2)),"Drag start lane supported")
	check(_clear(LAYOUT.drag_staging_point()),"Race staging is clear of props")
	var rival_finish := LAYOUT.drag_start_point()+Vector3.RIGHT*800
	region.set_vehicle_support([{"position":rival_finish,"radius":3.0}])
	region.set_retention_radius(1)
	check(region.chunks.has(region._cell(rival_finish)),"Rival support beyond player retention remains resident")
	await physics_frame
	check(_floor(rival_finish),"Distant rival has actual physical finish support")
	region.set_vehicle_support([])
	check(not region.chunks.has(region._cell(rival_finish)),"Removing race support releases distant finish cells")
	check(region.prepare_collision_at(rival_finish),"Late physical preparation can admit a distant desert cell")
	check(region.chunks.has(region._cell(rival_finish)),"Prepared desert cell is resident before support update")
	region.set_vehicle_support([])
	check(not region.chunks.has(region._cell(rival_finish)),"Unchanged empty support still consumes pending desert trim")
	region.release_chunks()
	check(region.chunks.is_empty() and region.build_jobs.is_empty(),"Region release removes owned geometry jobs")
	region.free()
	for failure in failures: push_error(failure)
	print("DESERT_WORLD_CONTRACT checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
func _space() -> PhysicsDirectSpaceState3D: return root.world_3d.direct_space_state
func _ramp_layers(region: Node3D) -> void:
	var observed: Dictionary={}
	var unsupported := 0
	var worst_separation := 0.0
	for node in region.find_children("*","MeshInstance3D",true,false):
		var kind := ""
		for prefix in ["WeatheredAsphalt","GravelShoulder","WornEdge","LaneDash"]:
			if str(node.name).begins_with(prefix): kind=prefix
		if kind.is_empty(): continue
		var vertices: PackedVector3Array=node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for i in range(0,vertices.size(),3):
			# Triangle interiors catch a long floating quad even when all four corners touch ground.
			var point: Vector3=node.to_global((vertices[i]+vertices[i+1]+vertices[i+2])/3.0)
			if point.z<=-445 or point.z>=LAYOUT.BRIDGE_END.z: continue
			observed[kind]=true
			var hit := _space().intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*3,point-Vector3.UP*4,1))
			if hit.is_empty(): unsupported+=1
			else: worst_separation=maxf(worst_separation,absf(point.y-float(hit.position.y)))
	check(observed.size()==4,"Ramp comparison covers rendered asphalt, shoulder, edge and lane paint")
	check(unsupported==0,"Every sampled ramp layer has real physical support")
	check(worst_separation<=.04,"Ramp layers stay within 4cm of actual collidable pavement/ground (worst %.4fm)"%worst_separation)
func _floor(point: Vector3) -> bool:
	return not _space().intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*.6,point-Vector3.UP*.35,1)).is_empty()
func _clear(point: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius=.32
	capsule.height=1.75
	query.shape=capsule
	query.transform=Transform3D(Basis.IDENTITY,point+Vector3.UP*.94)
	query.collision_mask=1
	return _space().intersect_shape(query,8).is_empty()
