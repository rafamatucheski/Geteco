extends RefCounted
## Intentional natural clusters respect the same public geometry as the actors.
const MODEL := preload("res://world/mountain_pass/transit/MountainWinterDressing3D.gd")
const VIEW := preload("res://world/mountain_pass/MountainStaticModelView.gd")
const LAYOUT := preload("res://world/mountain_pass/transit/MountainTransitVillageLayout.gd")
const POCKET := preload("res://world/mountain_pass/MountainVillageLayout.gd")
const RUNTIME_WORK := preload("res://systems/RuntimeWorkScheduler.gd")

static func install_village(view: Node2D) -> void:
	if view.has_meta("winter_dressing_ready"): return
	view.set_meta("winter_dressing_ready",true)
	var streamed: bool = _is_streamed_region(view)
	if streamed:
		view.viewport_3d.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var entries: Array[Dictionary] = []
	for grove in [Vector2(7323,-1555),Vector2(7607,-1660),Vector2(7934,-1550),Vector2(7420,-1350),Vector2(7825,-1318)]:
		_cluster(entries,grove,entries.size())
	for point in [Vector2(7365,-1660),Vector2(7588,-1702),Vector2(7888,-1710),Vector2(7904,-1400),Vector2(7390,-1370),Vector2(7650,-1325),Vector2(7532,-1555),Vector2(7410,-1568),Vector2(7783,-1530),Vector2(7351,-1480)]:
		_entry(entries,"rock",point,.7+float(entries.size()%3)*.17)
		_entry(entries,"branches",point+Vector2(20,11),.85)
	for point in [Vector2(7395,-1570),Vector2(7570,-1350),Vector2(7900,-1510),Vector2(7690,-1704)]:
		_entry(entries,"log",point,.85)
		_entry(entries,"branches",point+Vector2(17,12),1.0)
	await _install(view,view.model,entries,LAYOUT.ORIGIN,_village_routes(),null,-1,streamed)
	if not is_instance_valid(view) or not view.is_inside_tree(): return
	if not streamed:
		view.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	view.set_meta("winter_dressing_complete",true)

static func install_pockets(settlement: Node2D) -> void:
	if settlement.has_meta("winter_dressing_ready"): return
	settlement.set_meta("winter_dressing_ready",true)
	var streamed: bool = settlement.get("_streamed") == true or _is_streamed_region(settlement)
	for index in POCKET.POCKETS.size():
		var view := VIEW.new()
		view.name = "WinterDressingPocket%d" % index
		view.position = POCKET.POCKETS[index]
		view.z_index = 4
		settlement.add_child(view)
		var view_ticket: Dictionary = {}
		if streamed:
			view_ticket = await RUNTIME_WORK.reserve(
				view,&"mountain_winter",RUNTIME_WORK.PRIORITY_VISIBLE,MODEL.STREAM_BUILD_BUDGET_USEC)
			if view_ticket.is_empty(): return
		var view_started := Time.get_ticks_usec()
		view.build_view(MODEL,26.0,18.0,Vector3(0,1,0),Vector3(0,24,20))
		if streamed:
			RUNTIME_WORK.complete(view_ticket,Time.get_ticks_usec()-view_started)
		settlement.set_meta("winter_dressing_build_view_peak_usec",maxi(
			int(settlement.get_meta("winter_dressing_build_view_peak_usec",0)),
			Time.get_ticks_usec()-view_started))
		if streamed:
			view.viewport_3d.render_target_update_mode = SubViewport.UPDATE_DISABLED
		for child in view.viewport_3d.get_children():
			if child is DirectionalLight3D: child.light_energy=.72
			if child is WorldEnvironment: child.environment.ambient_light_energy=.45
		var entries: Array[Dictionary] = []
		for local in [Vector2(-95,-102),Vector2(173,-15),Vector2(-138,82),Vector2(150,138)]:
			_cluster(entries,view.position+local,index+entries.size())
		for local in [Vector2(-125,-5),Vector2(-58,-115),Vector2(45,-118),Vector2(154,-110),Vector2(168,44),Vector2(-63,78),Vector2(32,104),Vector2(161,105)]:
			_entry(entries,"rock",view.position+local,.60+float(entries.size()%3)*.15)
			_entry(entries,"branches",view.position+local+Vector2(18,13),.8)
		for local in [Vector2(-93,45),Vector2(52,-111),Vector2(154,79)]:
			_entry(entries,"log",view.position+local,.85)
		await _install(view,view.model,entries,view.position,[],settlement,index,streamed)
		if not is_instance_valid(view) or not view.is_inside_tree() or not is_instance_valid(settlement) or not settlement.is_inside_tree(): return
		var visible := VisibleOnScreenNotifier2D.new()
		visible.rect = Rect2(-230,-260,460,440)
		visible.screen_entered.connect(func(): view.viewport_3d.render_target_update_mode=SubViewport.UPDATE_ONCE)
		view.add_child(visible)
	await _install_roadside(settlement,streamed)
	settlement.set_meta("winter_dressing_complete",true)

static func _is_streamed_region(node: Node) -> bool:
	var cursor := node
	while cursor != null:
		if cursor.get("streamed_region") == true:
			return true
		cursor = cursor.get_parent()
	return false

static func _install_roadside(settlement: Node2D, streamed: bool) -> void:
	var road: Node2D = settlement.get_parent().road
	var targets := [Vector2(6320,-1830),Vector2(6530,-2250),Vector2(6470,-2540)]
	for index in targets.size():
		var offset: float = road.curve.get_closest_offset(targets[index])
		var frame: Transform2D = road.curve.sample_baked_with_rotation(offset,true)
		var center: Vector2 = frame.origin+frame.x.orthogonal()*195.0*(1.0 if index%2==0 else -1.0)
		var view := VIEW.new()
		view.name = "WinterRoadsideDressing%d" % index
		view.position = center
		view.z_index = 4
		settlement.add_child(view)
		var view_ticket: Dictionary = {}
		if streamed:
			view_ticket = await RUNTIME_WORK.reserve(
				view,&"mountain_winter",RUNTIME_WORK.PRIORITY_VISIBLE,MODEL.STREAM_BUILD_BUDGET_USEC)
			if view_ticket.is_empty(): return
		var view_started := Time.get_ticks_usec()
		view.build_view(MODEL,26.0,18.0,Vector3(0,1,0),Vector3(0,24,20))
		if streamed:
			RUNTIME_WORK.complete(view_ticket,Time.get_ticks_usec()-view_started)
		settlement.set_meta("winter_dressing_build_view_peak_usec",maxi(
			int(settlement.get_meta("winter_dressing_build_view_peak_usec",0)),
			Time.get_ticks_usec()-view_started))
		if streamed:
			view.viewport_3d.render_target_update_mode = SubViewport.UPDATE_DISABLED
		for child in view.viewport_3d.get_children():
			if child is DirectionalLight3D: child.light_energy=.72
			if child is WorldEnvironment: child.environment.ambient_light_energy=.45
		var entries: Array[Dictionary] = []
		_cluster(entries,center+Vector2(-33,-5),index+5)
		_cluster(entries,center+Vector2(40,24),index+2)
		_entry(entries,"log",center+Vector2(-5,56),1.2)
		_entry(entries,"rock",center+Vector2(64,-21),1.2)
		_entry(entries,"branches",center+Vector2(4,76),1.1)
		await _install(view,view.model,entries,center,[],settlement,-1,streamed)
		if not is_instance_valid(view) or not view.is_inside_tree() or not is_instance_valid(settlement) or not settlement.is_inside_tree(): return
		var visible := VisibleOnScreenNotifier2D.new()
		visible.rect = Rect2(-220,-230,440,430)
		visible.screen_entered.connect(func(): view.viewport_3d.render_target_update_mode=SubViewport.UPDATE_ONCE)
		view.add_child(visible)

static func _entry(entries: Array[Dictionary], kind: String, point: Vector2, size: float) -> void:
	entries.append({"kind":kind,"point":point,"scale":size,"angle":float(entries.size())*1.73})

static func _cluster(entries: Array[Dictionary], center: Vector2, seed_value: int) -> void:
	_entry(entries,"pine",center,.88+float(seed_value%3)*.09)
	_entry(entries,"pine",center+Vector2(28,24),.58)
	_entry(entries,"rock",center+Vector2(-19,17),.8)
	_entry(entries,"rock",center+Vector2(-30,25),.46)
	_entry(entries,"branches",center+Vector2(11,33),.9)
	_entry(entries,"branches",center+Vector2(-9,39),.67)

static func _install(view: Node2D, stage: Node3D, entries: Array[Dictionary], origin: Vector2, routes: Array, settlement: Node2D, pocket_index: int, streamed: bool) -> void:
	var group := MODEL.new()
	group.name = "WinterNaturalDressing3D"
	stage.add_child(group)
	var local_entries: Array[Dictionary] = []
	for entry in entries:
		var local: Dictionary = entry.duplicate()
		local.point -= origin
		local_entries.append(local)
	if streamed:
		await group.build_streamed(local_entries)
	else:
		group.build(local_entries)
	var installed := 0
	var ticket: Dictionary = {}
	if streamed:
		ticket = await RUNTIME_WORK.reserve(
			view,&"mountain_winter",RUNTIME_WORK.PRIORITY_COLLISION,MODEL.STREAM_BUILD_BUDGET_USEC)
		if ticket.is_empty(): return
	var slice_started := Time.get_ticks_usec()
	var peak_feature_usec := 0
	for feature in group.features:
		var feature_started := Time.get_ticks_usec()
		var points := PackedVector2Array()
		_mesh_points(feature.root,view,points)
		var polygon := Geometry2D.convex_hull(points)
		var absolute := PackedVector2Array()
		for point in polygon: absolute.append(point+origin)
		var clear := _clear_routes(absolute,routes)
		if clear: clear = _clear_solids(view,polygon)
		if clear and settlement != null:
			clear = _clear_region(absolute,settlement) if pocket_index<0 else _clear_pocket(absolute,settlement,pocket_index)
		if not clear:
			feature.root.queue_free()
			peak_feature_usec = maxi(peak_feature_usec,Time.get_ticks_usec()-feature_started)
			if streamed and Time.get_ticks_usec()-slice_started >= MODEL.STREAM_BUILD_BUDGET_USEC:
				RUNTIME_WORK.complete(ticket,Time.get_ticks_usec()-slice_started)
				ticket = await RUNTIME_WORK.reserve(
					view,&"mountain_winter",RUNTIME_WORK.PRIORITY_COLLISION,MODEL.STREAM_BUILD_BUDGET_USEC)
				if ticket.is_empty(): return
				slice_started = Time.get_ticks_usec()
			continue
		group.dress_base(feature,installed)
		var body := StaticBody2D.new()
		body.name = "Dressing%s%02d" % [String(feature.kind).capitalize(),installed]
		body.collision_layer = 1 if feature.solid else 0
		body.collision_mask = 0
		body.add_to_group("mountain_dressing")
		body.set_meta("dressing_kind",feature.kind)
		body.set_meta("walkable",not feature.solid)
		body.set_meta("dressing_model",feature.root)
		body.set_meta("dressing_polygon",polygon)
		body.set_meta("geometry_contract","projected_mesh_volume" if feature.solid else "walkable_ground_detail")
		if feature.solid:
			body.add_to_group("mountain_geodata")
			var shape := CollisionPolygon2D.new()
			shape.polygon = polygon
			body.add_child(shape)
		view.add_child(body)
		installed+=1
		peak_feature_usec = maxi(peak_feature_usec,Time.get_ticks_usec()-feature_started)
		if streamed and Time.get_ticks_usec()-slice_started >= MODEL.STREAM_BUILD_BUDGET_USEC:
			RUNTIME_WORK.complete(ticket,Time.get_ticks_usec()-slice_started)
			ticket = await RUNTIME_WORK.reserve(
				view,&"mountain_winter",RUNTIME_WORK.PRIORITY_COLLISION,MODEL.STREAM_BUILD_BUDGET_USEC)
			if ticket.is_empty(): return
			slice_started = Time.get_ticks_usec()
	if streamed:
		RUNTIME_WORK.complete(ticket,Time.get_ticks_usec()-slice_started)
	view.set_meta("winter_dressing_count",installed)
	view.set_meta("winter_dressing_peak_filter_usec",peak_feature_usec)

static func _mesh_points(node: Node3D, view: Node2D, points: PackedVector2Array) -> void:
	if node is MeshInstance3D:
		var transform: Transform3D = view.model.global_transform.affine_inverse()*node.global_transform
		for endpoint in 8: points.append(view.project_point(transform*node.mesh.get_aabb().get_endpoint(endpoint)))
	for child in node.get_children():
		if child is Node3D: _mesh_points(child,view,points)

static func _village_routes() -> Array:
	var routes: Array = [LAYOUT.BUS_TO_PLAZA,LAYOUT.PLAZA_TO_SHOP,LAYOUT.PLAZA_TO_WAIT]
	for index in 4: routes.append(LAYOUT.cabin_route(index))
	for point in LAYOUT.BENCH_CENTERS:
		for side in [-8.0,8.0]:
			var seat: Vector2 = point+Vector2(side,0)
			var route := LAYOUT.bench_access_route(seat)
			route.append(seat)
			routes.append(route)
	return routes

static func _clear_routes(polygon: PackedVector2Array, routes: Array, clearance := 19.0) -> bool:
	for route in routes:
		for index in range(route.size()-1):
			var a: Vector2 = route[index]
			var b: Vector2 = route[index+1]
			if Geometry2D.is_point_in_polygon(a,polygon) or Geometry2D.is_point_in_polygon(b,polygon): return false
			for vertex in polygon.size():
				var point := polygon[vertex]
				if point.distance_to(Geometry2D.get_closest_point_to_segment(point,a,b)) < clearance: return false
				if Geometry2D.segment_intersects_segment(a,b,point,polygon[(vertex+1)%polygon.size()]) != null: return false
	# Bus clearances use full physical envelope, not only the marked centerline.
	var berth := Rect2(LAYOUT.BERTH-Vector2(86,41),Vector2(172,82))
	for point in polygon:
		if berth.has_point(point): return false
		for route in LAYOUT.ACCESS_CORRIDORS:
			for index in range(route.size()-1):
				if point.distance_to(Geometry2D.get_closest_point_to_segment(point,route[index],route[index+1]))<78: return false
	return true

static func _clear_solids(view: Node2D, polygon: PackedVector2Array) -> bool:
	for body in view.get_children():
		if not body is StaticBody2D or body.collision_layer==0: continue
		for shape in body.get_children():
			if shape is CollisionPolygon2D and not Geometry2D.intersect_polygons(polygon,shape.polygon).is_empty(): return false
	return true

static func _clear_pocket(polygon: PackedVector2Array, settlement: Node2D, index: int) -> bool:
	var road: Node2D = settlement.get_parent().road
	var access := POCKET.winter_stop_access_curve(road.curve,index)
	var parking := POCKET.parking_bay(index).grow(19)
	var shelter := Rect2(POCKET.POCKETS[index]-Vector2(52,100),Vector2(104,148))
	var bench := Rect2(POCKET.POCKETS[index]+Vector2(56,-5),Vector2(75,90))
	var overlook := Rect2(7185,-1487,110,80)
	for point in polygon:
		if parking.has_point(point) or shelter.has_point(point) or bench.has_point(point): return false
		if index==1 and overlook.has_point(point): return false
		if road.is_point_on_road(point,road.road_width*.5+35): return false
		if index==2 and Rect2(6960,-2860,550,240).has_point(point): return false
		if point.distance_to(access.get_closest_point(point))<57: return false
		for resident in POCKET.RESIDENTS:
			if point.distance_to(resident[0])<34: return false
	return true

static func _clear_region(polygon: PackedVector2Array, settlement: Node2D) -> bool:
	var road: Node2D = settlement.get_parent().road
	var railway := preload("res://geodata/rail/HarborMountainRailRoute.gd").new()
	for point in polygon:
		if road.is_point_on_road(point,road.road_width*.5+35): return false
		if POCKET.is_reserved(point) or railway.is_mountain_reserved(point): return false
	return true
