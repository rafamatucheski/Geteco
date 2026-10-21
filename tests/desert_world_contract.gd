extends SceneTree
## Finite contracts for the real region/room nodes. Rendered depth and frame-time need separate capture.
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const REGION := preload("res://world/desert/DesertRegion.gd")
const MINING_LAYOUT := preload("res://world/mining/MiningLayout.gd")
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
	check(LAYOUT.BOUNDS.get_area()<=1940.0*1576.5*.5,"Compact desert occupies at most half its previous area")
	check(is_equal_approx(LAYOUT.DRAG_LENGTH,800.0),"Compact geography preserves the full 800m drag competition")
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
	for endpoints in [[LAYOUT.BRIDGE_END,LAYOUT.BANK+Vector3(0,0,13)],[LAYOUT.BANK+Vector3(0,0,13),LAYOUT.BRIDGE_END],[LAYOUT.TRUCK_STOP+Vector3(5,0,0),LAYOUT.WORKSHOP+Vector3(0,0,-25)],[LAYOUT.WORKSHOP+Vector3(0,0,-25),LAYOUT.TRUCK_STOP+Vector3(5,0,0)]]:
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
	check(await _settle(warm_region,"bridge"),"Bridge streaming completes with continuous progress")
	await physics_frame
	await physics_frame
	_ramp_layers(warm_region)
	# Explicit preparation must acquire the complete panorama even when the
	# ordinary focus is still at the remote bridge, then release its request.
	warm_region.prepare_drag_view(true)
	check(warm_region._drag_preparing and warm_region.drag_view_cells.size()==42,"Explicit race preparation acquires the full42-cell camera band from outside course proximity")
	warm_region.prepare_drag_view(false)
	warm_region.set_focus(warm_region.spawn_position)
	check(not warm_region._drag_preparing and warm_region.drag_view_cells.is_empty() and warm_region.drag_view_pending.is_empty(),"Ending explicit preparation outside the course releases camera requests")
	warm_region.free()
	var region := REGION.new()
	region.initial_focus=LAYOUT.TRUCK_STOP
	root.add_child(region)
	# Idle includes thousands of decorations per cell under the production 1 ms
	# budget. Check natural progress and completion, rather than 180 arbitrary frames.
	check(await _settle(region,"truck stop"),"Truck stop streaming settles finitely")
	check(region.chunks.size()==9 and _residency_owned(region),"Truck stop keeps only its nine requested neighbouring cells")
	await physics_frame
	await physics_frame
	check(_floor(LAYOUT.TRUCK_STOP+Vector3(57.5,0,0)),"Highway has physical road support")
	check(_floor(LAYOUT.TRUCK_STOP+Vector3(-15,0,-8)),"Truck-stop NPC position has floor")
	var probe_car := CharacterBody3D.new()
	probe_car.collision_layer=0
	root.add_child(probe_car)
	var asphalt_contact := SURFACE_PROBE.sample(probe_car,LAYOUT.TRUCK_STOP+Vector3(57.5,.2,0))
	var sand_contact := SURFACE_PROBE.sample(probe_car,LAYOUT.TRUCK_STOP+Vector3(67,.2,-20))
	check(not asphalt_contact.is_empty() and asphalt_contact.kind=="hard","Real wheel ray classifies weathered asphalt as hard")
	check(not sand_contact.is_empty() and sand_contact.kind=="dirt","Real wheel ray classifies desert sand as dirt")
	probe_car.free()
	var parked := 0
	for node in region.find_children("*","Node3D",true,false):
		if node.get_meta("vehicle_kind","")=="bitrem":
			parked+=1
			check(node.get_meta("trailer_count")==2,"Parked road train has two trailers")
	check(parked==4,"Four large bitrems are actually instantiated at stop")
	region.set_focus(MINING_LAYOUT.GATE+Vector3(0,0,20))
	check(region.drag_view_cells.is_empty() and region.drag_view_pending.is_empty(),"Ordinary mining gate focus never requests the racing panorama")
	check(await _settle(region,"mining gate without race panorama"),"Mining gate streaming completes under the ordinary local window")
	check(region.drag_view_cells.is_empty() and _residency_owned(region),"Settled mining residency remains local and does not activate race-camera owners")
	region.set_focus(LAYOUT.TOWN)
	check(await _settle(region,"town"),"Town streaming completes with continuous progress")
	check(region.drag_view_cells.is_empty() and region.drag_view_pending.is_empty(),"Ordinary town focus never requests the racing panorama")
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
	var town_owner_limit := (region.retention_radius*2+1)*(region.retention_radius*2+1)+region.drag_view_cells.size()+region.vehicle_support_cells.size()+region.developer_view_cells.size()
	check(count<=town_owner_limit and _residency_owned(region),"Compact town residency belongs only to its local window and explicit camera/support owners")
	region.set_focus(LAYOUT.drag_staging_point())
	check(not region._drag_preparing and region.drag_view_cells.size()==42,"Staging proximity admits the complete camera band without explicit preparation")
	check(await _settle(region,"drag course"),"Drag scenery completes with continuous progress")
	# Grid alignment changes after relocation; coverage and ownership, rather
	# than the previous coordinate-dependent 26-cell count, remain mandatory.
	var view_bounds: Rect2=region.DRAG_VIEW_BOUNDS
	check(view_bounds.encloses(LAYOUT.DRAG_STRIP_BOUNDS),"Race camera residency covers the complete relocated strip and braking pavement")
	var expected_view_cells := 0
	for x in range(floori(view_bounds.position.x/region.CELL),ceili(view_bounds.end.x/region.CELL)):
		for z in range(floori(view_bounds.position.y/region.CELL),ceili(view_bounds.end.y/region.CELL)):
			expected_view_cells+=1
			check(region.drag_view_cells.has(Vector2i(x,z)),"Race camera retains authored scenery cell %d,%d"%[x,z])
	check(expected_view_cells==42 and region.drag_view_cells.size()==expected_view_cells,"Race camera retains its complete42-cell scenery band after preparation")
	var race_owner_limit := (region.retention_radius*2+1)*(region.retention_radius*2+1)+expected_view_cells+region.vehicle_support_cells.size()+region.developer_view_cells.size()
	check(region.chunks.size()<=race_owner_limit and _residency_owned(region),"Streaming residency bounded independently of map area")
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
	check(region.vehicle_support_cells.is_empty() and region.drag_view_cells.has(region._cell(rival_finish)) and region.chunks.has(region._cell(rival_finish)),"Removing rival support preserves finish scenery still owned by race camera")
	# Leave the camera's hysteresis region before requiring the same finish cell
	# to disappear. Removing one owner must not destroy another owner's scenery.
	region.set_focus(LAYOUT.BRIDGE_END)
	check(region.drag_view_cells.is_empty() and not region.chunks.has(region._cell(rival_finish)),"Leaving race camera releases distant finish cells")
	check(region.prepare_collision_at(rival_finish),"Late physical preparation can admit a distant desert cell")
	check(region.chunks.has(region._cell(rival_finish)),"Prepared desert cell is resident before support update")
	region.set_vehicle_support([])
	check(not region.chunks.has(region._cell(rival_finish)),"Unchanged empty support still consumes pending desert trim")
	region.release_chunks()
	check(region.chunks.is_empty() and region.build_jobs.is_empty() and region._surface_jobs.is_empty() and region.pending.is_empty() and region.drag_view_pending.is_empty(),"Region release removes owned geometry jobs")
	region.free()
	for failure in failures: push_error(failure)
	print("DESERT_WORLD_CONTRACT checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _residency_owned(region: Node) -> bool:
	for key: Vector2i in region.chunks:
		if region.vehicle_support_cells.has(key) or region.developer_view_cells.has(key) or region.drag_view_cells.has(key): continue
		if absi(key.x-region.current_cell.x)>region.retention_radius or absi(key.y-region.current_cell.y)>region.retention_radius: return false
	return true

func _stream_state(region: Node) -> Array:
	var state: Array=[region.pending.duplicate(),region.drag_view_pending.duplicate()]
	for key: Vector2i in region._surface_jobs:
		state.append([key,region._surface_jobs[key].stage])
	for job: Dictionary in region.build_jobs:
		var phase: Array=[job.key,job.index,job.get("dress_stage",0),job.get("dressed",false),job.get("ground_cover_done",false),job.get("expansion_stage",0),job.get("mining_built",false)]
		if job.has("ground_cover"):
			var cover: RefCounted=job.ground_cover
			phase.append([cover.next,cover.next_contact,cover.next_part,cover.committed])
			for part: RefCounted in cover.parts: phase.append([part.next_contact,part.committed])
		state.append(phase)
	return state

func _settle(region: Node, label: String) -> bool:
	var began := Time.get_ticks_msec()
	var last_progress := began
	var previous := _stream_state(region)
	var frames := 0
	# Finite functional watchdogs, not FPS/loading acceptance criteria. They
	# catch a stalled phase or endless producer while retaining the real scheduler.
	while not region.is_streaming_idle():
		await process_frame
		frames+=1
		var now := Time.get_ticks_msec()
		var state := _stream_state(region)
		if state!=previous:
			previous=state
			last_progress=now
		if now-began>45000 or now-last_progress>3000:
			push_error("DESERT_STREAM stalled %s frames=%d state=%s"%[label,frames,str(state)])
			return false
	print("DESERT_STREAM completed %s frames=%d wall_ms=%d"%[label,frames,Time.get_ticks_msec()-began])
	return true
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
