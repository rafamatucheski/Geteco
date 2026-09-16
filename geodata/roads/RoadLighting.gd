extends Node2D
## Fill gaps using the actual road graph, then measure both traffic lanes.
## Pole placement respects all road surfaces, authored access corridors and
## static physics, including entrances added by other scene components.
const LAMP := preload("res://geodata/StreetLamp.gd")
const FIXTURE := preload("res://geodata/roads/RoadLuminaire3D.gd")
const SPACING := 170.0
const MIN_WASH := 0.18
const POST_SPACING := preload("res://geodata/roads/RoadPostSpacing.gd")
# Sidewalk strips swept by the tail of route 510 at its two tight outside
# corners. Dynamic infill poles must obey the same clearance as authored ones.
const ARTICULATED_TURN_CLEARANCES: Array[Rect2] = [
	Rect2(500, 2250, 210, 75),
	Rect2(2690, 275, 210, 75),
]
var ready_for_audit := false
var mountain_road: Node2D
var report: Dictionary = {}
var _roads: Array[Dictionary] = []
var _reserved: Array[Rect2] = []
var _pools: Array[PointLight2D] = []
var _pool_grid: Dictionary = {}
var _poles: Array[Vector2] = []
var _created := 0

func _ready() -> void:
	_build.call_deferred()

func _build() -> void:
	# Physics must include authored shop entrances and transport platforms.
	await get_tree().physics_frame
	await get_tree().process_frame
	var loading_batch := preload("res://ui/LoadingWorkBatch.gd").new()
	var world := get_parent()
	# GETECO-PERF-03A: HarborSouthPort agora constrói seus StaticBody2D em
	# etapas (ver o script) em vez de bloquear um quadro inteiro. A colocação
	# de postes abaixo consulta a física real via _safe_pole()/intersect_shape
	# para não sobrepor "física estática... de outros componentes da cena";
	# sem esperar o porto terminar, essa consulta via early e acha vazio onde
	# o porto ainda vai construir, dobrando postes que depois colidem com a
	# geometria real (visto em test_south_port: total_road_posts 146→290).
	var south_port := world.get_node_or_null("SouthPort")
	if south_port != null:
		while not south_port.port_ready: await get_tree().process_frame
	if mountain_road:
		_roads.append({"id":"mountain_road","points":mountain_road.smooth_points,"width":mountain_road.road_width})
		var village := preload("res://world/mountain_pass/MountainVillageLayout.gd")
		for i in village.POCKETS.size():
			var access: Curve2D = village.winter_stop_access_curve(mountain_road.curve,i)
			_roads.append({"id":"winter_stop_%d" % i,"points":access.get_baked_points(),"width":62.0})
	else:
		var network := world.get_node_or_null("RoadNetwork")
		if network == null: return
		_roads.assign(network.get_graph_data().roads)
		# Neko's driveway is authored outside the street graph. Reserve it before
		# planting poles at Memorial North, including during staged yard loading.
		var yard_access := preload("res://cars/salvage/SalvageLocation.gd").access(false)
		for segment in range(1,yard_access.size()):
			_reserved.append(Rect2(yard_access[segment-1],Vector2.ZERO).expand(yard_access[segment]).grow(64))
		var access := preload("res://world/harbor/HarborNorthAccess.gd")
		for i in access.curves().size():
			var route: Curve2D = access.curves()[i]
			_roads.append({"id":"north_works_%d" % i,"points":route.get_baked_points(),"width":access.WIDTH})
			var count := ceili(route.get_baked_length()/125)
			for station in count+1:
				var offset := route.get_baked_length()*float(station)/count
				var point := route.sample_baked(offset)
				var direction := (route.sample_baked(minf(offset+5,route.get_baked_length()))-route.sample_baked(maxf(offset-5,0))).normalized()
				# Narrow embankments already have continuous solid guardrails;
				# attach overhead battens there instead of placing poles in water.
				var strip := FIXTURE.new()
				strip.fixture_kind = "strip"
				strip.position = point+direction.orthogonal()*68
				strip.target_offset = -direction.orthogonal()*68
				strip.tangent = direction
				strip.always_on = access.TUNNEL.has_point(point)
				strip.emits_ground_light = strip.always_on or station%2 == 0 or station == count
				add_child(strip)
				# Adjacent battens share a longer wash along the narrow access.
				strip.pool.scale.x *= 2.0
				strip.pool.range_item_cull_mask = 3
				strip.hardware.z_index = 1
				strip.beam.z_index = 1
	for road in _roads:
		var points: PackedVector2Array = road.points
		var bounds := Rect2(points[0],Vector2.ZERO)
		var curve := Curve2D.new()
		for point in points:
			bounds = bounds.expand(point)
			curve.add_point(point)
		road["bounds"] = bounds.grow(float(road.width)*.5+18)
		road["lighting_curve"] = curve
	for district_name in ["District","EastDistrict","NorthDistrict"]:
		var district := world.get_node_or_null(district_name)
		if district == null: continue
		for site in district.sites: _reserved.append(site.bounds.grow(14))
		for access in district.accesses: _reserved.append(access.bounds.grow(14))
	if mountain_road == null:
		_reserved.append_array(ARTICULATED_TURN_CLEARANCES)
	_clear_authored_poles()
	_collect_sources()
	report["before"] = coverage_audit()
	for road in _roads:
		var curve: Curve2D = road.lighting_curve
		var length := curve.get_baked_length()
		var count := maxi(1,ceili(length/SPACING))
		for index in count+1:
			var offset := length * float(index)/count
			var center := curve.sample_baked(offset)
			if _wash_at(center) >= .42 or _dedicated_span(center,road): continue
			var direction := (curve.sample_baked(minf(offset+8,length))-curve.sample_baked(maxf(offset-8,0))).normalized()
			_place_pole(center,direction,float(road.width),index)
		# During loading, share the established 6 ms work slice instead of paying
		# one complete VSync per road. Runtime streaming keeps one-road-per-frame.
		await loading_batch.checkpoint(get_tree())
	# Repair coverage at BOTH lane edges, including junctions and displaced poles.
	for road in _roads:
		var curve: Curve2D = road.lighting_curve
		var count := maxi(1,ceili(curve.get_baked_length()/85))
		for i in count+1:
			var offset := curve.get_baked_length()*float(i)/count
			var center := curve.sample_baked(offset)
			if _dedicated_span(center,road): continue
			var direction := (curve.sample_baked(minf(offset+8,curve.get_baked_length()))-curve.sample_baked(maxf(offset-8,0))).normalized()
			for side in [-.35,.35]:
				if _wash_at(center+direction.orthogonal()*float(road.width)*side) < MIN_WASH:
					_place_pole(center,direction,float(road.width),i)
		await loading_batch.checkpoint(get_tree())
	report["after"] = coverage_audit()
	report["added_poles"] = _created
	report["roads"] = _roads.size()
	ready_for_audit = true
	print("ROAD_LIGHTING_AUDIT roads=%d added=%d samples=%d underlit_before=%d underlit_after=%d" % [_roads.size(),_created,report.after.samples,report.before.underlit,report.after.underlit])

func _dedicated_span(point: Vector2, road: Dictionary) -> bool:
	if bool(road.get("bridge_surface",false)): return true
	if Rect2(3200,280,1180,240).has_point(point): return true
	if String(road.id).begins_with("north_works_"): return true
	return mountain_road != null and Rect2(4930,300,890,200).has_point(point)

func _collect_sources() -> void:
	for group in ["street_lamp","road_luminaire","port_floodlight"]:
		for source in get_tree().get_nodes_in_group(group):
			if not get_parent().is_ancestor_of(source): continue
			for child in source.get_children():
				if child is PointLight2D: _register_pool(child)
			if group == "street_lamp": _poles.append(to_local(source.global_position))
	if mountain_road:
		var tunnel := get_parent().get_node_or_null("MountainTunnel")
		if tunnel:
			for light in tunnel.find_children("*","PointLight2D",true,false): _register_pool(light)

func _place_pole(center: Vector2, direction: Vector2, width: float, index: int) -> bool:
	var normal := direction.orthogonal()
	for shift in [0.0,45.0,-45.0,90.0,-90.0,130.0,-130.0]:
		for side in [1.0 if index%2 == 0 else -1.0,-1.0 if index%2 == 0 else 1.0]:
			var pole: Vector2 = center+direction*shift+normal*(width*.5+28)*side
			if not _safe_pole(pole): continue
			var lamp := LAMP.new()
			lamp.name = "RoadPost%03d" % _created
			lamp.position = pole
			lamp.road_target = center+direction*shift-pole
			lamp.is_facing_south = lamp.road_target.y >= 0
			if absf(lamp.road_target.x) > absf(lamp.road_target.y):
				lamp.is_facing_south = true
				lamp.arm_rotation_quarters = 1 if lamp.road_target.x > 0 else -1
			lamp.light_radius = 520
			add_child(lamp)
			if mountain_road and get_tree().get_first_node_in_group("day_night_manager") == null: lamp.set_lit(true)
			_register_pool(lamp.lamp_light)
			_poles.append(pole)
			_created += 1
			return true
	return false

func _safe_pole(point: Vector2, existing: StreetLamp = null) -> bool:
	if not POST_SPACING.is_clear(existing if existing != null else self, to_global(point)): return false
	for pole in _poles:
		if pole.distance_squared_to(point) < 95*95: return false
	for bounds in _reserved:
		if bounds.has_point(point): return false
	for road in _roads:
		if not road.bounds.has_point(point): continue
		var curve: Curve2D = road.lighting_curve
		if point.distance_to(curve.get_closest_point(point)) < float(road.width)*.5+16: return false
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 12
	query.shape = circle
	query.transform = Transform2D(0,to_global(point))
	query.collision_mask = 1
	query.collide_with_areas = false
	if existing != null: query.exclude = [existing.get_rid()]
	for hit in get_world_2d().direct_space_state.intersect_shape(query,32):
		if hit.collider is StaticBody2D: return false
	return true

func _clear_authored_poles() -> void:
	for lamp in get_tree().get_nodes_in_group("street_lamp"):
		if not get_parent().is_ancestor_of(lamp): continue
		var original := to_local(lamp.global_position)
		if _safe_pole(original, lamp): continue
		var found := false
		for radius in range(8, 161, 8):
			for step in 32:
				var candidate := original + Vector2.from_angle(TAU * step / 32.0) * radius
				if not _safe_pole(candidate, lamp): continue
				lamp.global_position = to_global(candidate)
				lamp.reset_physics_interpolation()
				# Renewal must use the cleared foundation, not the original overlap.
				var renewal := get_node_or_null("/root/WorldRenewal")
				if renewal: renewal._register_id(lamp.get_instance_id())
				found = true
				break
			if found: break
		if not found: push_warning("No clear roadside position for %s at %s" % [lamp.get_path(), original])

func _register_pool(pool: PointLight2D) -> void:
	if _pools.has(pool) or not pool.enabled: return
	_pools.append(pool)
	# Static fixtures: index their footprint once, not every lane sample/frame.
	var radius := (pool.texture.get_size()*pool.texture_scale*.5*pool.global_scale.abs()).length()
	var center := to_local(pool.global_position)
	var first := Vector2i(((center-Vector2.ONE*radius)/300).floor())
	var last := Vector2i(((center+Vector2.ONE*radius)/300).floor())
	for x in range(first.x,last.x+1):
		for y in range(first.y,last.y+1):
			var cell := Vector2i(x,y)
			if not _pool_grid.has(cell): _pool_grid[cell] = []
			_pool_grid[cell].append(pool)

func _wash_at(point: Vector2) -> float:
	var total := 0.0
	var global_point := to_global(point)
	for pool: PointLight2D in _pool_grid.get(Vector2i((point/300).floor()),[]):
		if not is_instance_valid(pool) or pool.texture == null: continue
		var local_point: Vector2 = pool.to_local(global_point)-pool.offset
		var dimensions := pool.texture.get_size()*pool.texture_scale*.5
		var radius := (local_point/dimensions).length()
		if radius >= 1: continue
		if pool.texture is GradientTexture2D:
			total += pool.texture.gradient.sample(radius).a*pool.energy
		else:
			total += pow(1-radius,2)*pool.energy
	return total

func coverage_audit() -> Dictionary:
	var samples := 0
	var gaps: Array[Dictionary] = []
	var minimum := INF
	for road in _roads:
		var curve: Curve2D = road.lighting_curve
		var count := maxi(1,ceili(curve.get_baked_length()/85))
		for i in count+1:
			var offset := curve.get_baked_length()*float(i)/count
			var center := curve.sample_baked(offset)
			var direction := (curve.sample_baked(minf(offset+8,curve.get_baked_length()))-curve.sample_baked(maxf(offset-8,0))).normalized()
			for side in [-.35,0.0,.35]:
				var point: Vector2 = center+direction.orthogonal()*float(road.width)*side
				var wash := _wash_at(point)
				minimum = minf(minimum,wash)
				samples += 1
				if wash < MIN_WASH: gaps.append({"road":road.id,"point":point,"wash":snappedf(wash,.001)})
	return {"samples":samples,"underlit":gaps.size(),"minimum":snappedf(minimum,.001),"gaps":gaps}
