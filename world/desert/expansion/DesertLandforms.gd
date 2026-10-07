extends RefCounted
## Authored natural landmarks, entirely owned by the streamed desert chunks.
## Ground detail uses world-anchored vertices and the supplied physical height.
## There are no process callbacks, timers, particle systems or new light sources.
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const SURFACE := preload("res://world/desert/expansion/DesertLandformsSurface.gdshader")
const ARCH := Vector2(-790.0, -690.0)
const SALT := Vector2(-790.0, -1420.0)
const WASH_BOUNDS := Rect2(-774.0, -1202.0, 260.0, 256.0)
const ARCH_BOUNDS := Rect2(-850.0, -746.0, 124.0, 113.0)
const DUNES_BOUNDS := Rect2(-94.0, -646.0, 135.0, 90.0)
const RESOURCE_CELL := 96.0
const MAX_CACHED_PROVIDERS := 2
const MAX_CACHED_CELLS := 32
static var _ground_materials: Dictionary = {}
static var _rock_material: StandardMaterial3D
static var _features: Array[Dictionary] = []
static var _building_guards: Array[Rect2] = []
static var _wash_segments: Array[Dictionary] = []
static var _resource_cells: Array[Vector2i] = []
static var _resource_caches: Array[Dictionary] = []

static func _cache_enabled() -> bool:
	# Only the isolated A/B benchmark uses this flag; it is never saved.
	return not (OS.is_debug_build() and Engine.get_meta("desert_landform_cache_benchmark_disabled",false))

static func prewarm(height_callable: Callable, world_seed: int = 6102026) -> Dictionary:
	# The finite authored resource set is prepared under the existing loading
	# curtain. First visits and revisits both instantiate the same cached assets.
	if not _cache_enabled(): return {"enabled":false,"ready":false,"cached_cells":0}
	_prepare()
	var cache := _cache_for(height_callable,world_seed,true)
	if cache.is_empty(): return {"enabled":true,"cacheable":false,"ready":false,"cached_cells":0}
	for key in _resource_cells: _cache_cell(cache,key,height_callable,world_seed)
	return cache_diagnostics(height_callable,world_seed)

static func resource_cells() -> Array[Vector2i]:
	_prepare()
	return _resource_cells.duplicate()

static func cache_diagnostics(height_callable: Callable, world_seed: int = 6102026) -> Dictionary:
	_prepare()
	var cache := _cache_for(height_callable,world_seed,false)
	var count := 0 if cache.is_empty() else int(cache.chunks.size())
	return {"enabled":_cache_enabled(),"cacheable":not cache.is_empty(),"ready":count==_resource_cells.size(),
		"candidate_cells":_resource_cells.size(),"cached_cells":count,"provider_count":_resource_caches.size(),
		"geometry_builds":0 if cache.is_empty() else int(cache.builds),
		"cached_instantiations":0 if cache.is_empty() else int(cache.instantiations)}

static func _cache_for(height_callable: Callable, world_seed: int, create: bool) -> Dictionary:
	# Custom/bound callables may carry mutable captured data: retain their normal
	# exact generator path. Region methods have explicit object/method identity.
	if not height_callable.is_valid() or height_callable.is_custom(): return {}
	var provider: Object=height_callable.get_object()
	if not is_instance_valid(provider): return {}
	for i in range(_resource_caches.size()-1,-1,-1):
		if not is_instance_valid((_resource_caches[i].provider as WeakRef).get_ref()): _resource_caches.remove_at(i)
	for cache in _resource_caches:
		if (cache.provider as WeakRef).get_ref()==provider and cache.method==height_callable.get_method() and int(cache.seed)==world_seed: return cache
	if not create: return {}
	if _resource_caches.size()>=MAX_CACHED_PROVIDERS: _resource_caches.pop_front()
	var cache := {"provider":weakref(provider),"method":height_callable.get_method(),"seed":world_seed,
		"chunks":{},"builds":0,"instantiations":0}
	_resource_caches.append(cache)
	return cache

static func _cache_cell(cache: Dictionary, key: Vector2i, height_callable: Callable, world_seed: int) -> bool:
	if cache.chunks.has(key): return true
	if key not in _resource_cells or cache.chunks.size()>=MAX_CACHED_CELLS: return false
	var prototype := Node3D.new()
	prototype.name="CachedDesertLandforms"
	var count := _build_uncached(prototype,Rect2(Vector2(key)*RESOURCE_CELL,Vector2.ONE*RESOURCE_CELL),world_seed,height_callable)
	var scene: PackedScene = null
	if count>0:
		_own_descendants(prototype,prototype)
		scene=PackedScene.new()
		if scene.pack(prototype)!=OK:
			prototype.free()
			push_error("Could not prepare authored desert landform resources at "+str(key))
			return false
	prototype.free()
	cache.chunks[key]={"scene":scene,"count":count}
	cache.builds=int(cache.builds)+1
	return true

static func _own_descendants(node: Node, owner_root: Node) -> void:
	for child in node.get_children():
		child.owner=owner_root
		_own_descendants(child,owner_root)

static func locations() -> Array[Dictionary]:
	return [
		{"id":"desert_wind_dunes", "kind":"dunes", "position":Vector3(-25, 0, -622), "camera_size":76.0, "collision_probe":Vector3(-25, 0, -622)},
		{"id":"desert_dry_wash", "kind":"dry_wash", "position":Vector3(-650, 0, -1080), "camera_size":83.0, "collision_probe":Vector3(-650, 0, -1080)},
		{"id":"desert_salt_pan", "kind":"salt_flat", "position":Vector3(SALT.x, 0, SALT.y), "camera_size":134.0, "collision_probe":Vector3(SALT.x, 0, SALT.y)},
		{"id":"desert_natural_arch", "kind":"natural_arch", "position":Vector3(ARCH.x, 0, ARCH.y), "camera_size":43.0, "collision_probe":Vector3(ARCH.x, 10.8, ARCH.y)},
		{"id":"desert_hoodoo", "kind":"hoodoo", "position":Vector3(-834, 0, -718), "camera_size":26.0, "collision_probe":Vector3(-834, 8.5, -718)},
		{"id":"desert_basalt_fan", "kind":"basalt", "position":Vector3(-746, 0, -707), "camera_size":26.0, "collision_probe":Vector3(-746, 5.5, -707)},
		{"id":"desert_balanced_rock", "kind":"balanced_rock", "position":Vector3(-827, 0, -654), "camera_size":24.0, "collision_probe":Vector3(-827, 7.8, -654)},
	]

static func manifest() -> Dictionary:
	return {"locations":locations(), "dunes":4, "dry_washes":1, "salt_flats":1,
		"natural_arches":1, "rock_families":["sandstone_arch", "hoodoo", "basalt_columns", "balanced_sandstone"],
		"maximum_dune_height":2.1, "arch_opening_width":16.0, "arch_opening_height":7.4,
		"ground_grid_metres":3.0, "salt_grid_metres":8.0, "per_frame_callbacks":0}

static func walk_paths() -> Array[Dictionary]:
	return [
		{"id":"arch_portal", "points":PackedVector3Array([Vector3(-790,0,-707),Vector3(-790,0,-690),Vector3(-790,0,-673)]), "width":5.0},
		{"id":"dune_ramp", "points":PackedVector3Array([Vector3(-54,0,-622),Vector3(-25,0,-622),Vector3(4,0,-622)]), "width":3.0},
		{"id":"wash_floor", "points":PackedVector3Array([Vector3(-714,0,-1000),Vector3(-676,0,-1043.5),Vector3(-642.5,0,-1075),Vector3(-609,0,-1106.5),Vector3(-562,0,-1150)]), "width":3.0},
	]

static func surface_height(point: Vector2, base_callable: Callable) -> float:
	# Barycentric evaluation of the same clipped triangles, for exact support
	# queries in validation or placement. No renderer/physics approximation here.
	if not base_callable.is_valid(): return 0.0
	_prepare()
	var result := float(base_callable.call(point))
	for feature in _features:
		if int(feature.kind)==2 or not (feature.bounds as Rect2).has_point(point): continue
		var polygon: PackedVector2Array = feature.polygon
		if not Geometry2D.is_point_in_polygon(point,polygon): continue
		var start := (point/3.0).floor()*3.0
		var clip := PackedVector2Array([start,start+Vector2(3,0),start+Vector2(3,3),start+Vector2(0,3)])
		for part: PackedVector2Array in Geometry2D.intersect_polygons(polygon,clip):
			if Geometry2D.is_polygon_clockwise(part): part.reverse()
			var indices := Geometry2D.triangulate_polygon(part)
			for i in range(0,indices.size(),3):
				var a := part[indices[i]]
				var b := part[indices[i+1]]
				var c := part[indices[i+2]]
				var denominator := (b-a).cross(c-a)
				if absf(denominator)<.000001: continue
				var wb := (point-a).cross(c-a)/denominator
				var wc := (b-a).cross(point-a)/denominator
				var wa := 1.0-wb-wc
				if minf(wa,minf(wb,wc))<-.00001: continue
				var va := _ground_vertex(a,feature,base_callable)
				var vb := _ground_vertex(b,feature,base_callable)
				var vc := _ground_vertex(c,feature,base_callable)
				result=maxf(result,wa*float(va.position.y)+wb*float(vb.position.y)+wc*float(vc.position.y))
	return result

static func reservation_clear(point: Vector2, radius: float = 0.0) -> bool:
	# Reserves protect raised support and the open arch portal from legacy scatter.
	if WASH_BOUNDS.grow(radius).has_point(point): return false
	if ARCH_BOUNDS.grow(radius).has_point(point): return false
	if DUNES_BOUNDS.grow(radius).has_point(point): return false
	if Rect2(SALT-Vector2(102, 59), Vector2(204, 118)).grow(radius).has_point(point): return false
	return true

static func placement_clear(point: Vector2, radius: float = 0.0) -> bool:
	_prepare()
	if point.y-radius < -1558.0 or not LAYOUT.BOUNDS.grow(-radius).has_point(point): return false
	if not LAYOUT.road_clear(point, radius+1.0): return false
	if Rect2(210, -797, 125, 92).grow(radius).has_point(point): return false
	if not LAYOUT.drag_reservation_clear(point,radius+3.0): return false
	for bounds in _building_guards:
		if bounds.grow(radius).has_point(point): return false
	return true

static func build_chunk(parent: Node3D, rect: Rect2, world_seed: int, height_callable: Callable) -> int:
	if not height_callable.is_valid() or not rect.intersects(LAYOUT.BOUNDS): return 0
	if not _cache_enabled(): return _build_uncached(parent,rect,world_seed,height_callable)
	_prepare()
	var key := Vector2i((rect.position/RESOURCE_CELL).floor())
	var canonical := Rect2(Vector2(key)*RESOURCE_CELL,Vector2.ONE*RESOURCE_CELL)
	# Other rectangle sizes keep the general API's clipping and ownership contract.
	if not rect.is_equal_approx(canonical): return _build_uncached(parent,rect,world_seed,height_callable)
	if key not in _resource_cells: return 0
	var cache := _cache_for(height_callable,world_seed,true)
	if cache.is_empty() or not _cache_cell(cache,key,height_callable,world_seed): return _build_uncached(parent,rect,world_seed,height_callable)
	var resource: Dictionary=cache.chunks[key]
	if resource.scene!=null:
		parent.add_child((resource.scene as PackedScene).instantiate())
		cache.instantiations=int(cache.instantiations)+1
	return int(resource.count)

static func _build_uncached(parent: Node3D, rect: Rect2, world_seed: int, height_callable: Callable) -> int:
	if not height_callable.is_valid() or not rect.intersects(LAYOUT.BOUNDS): return 0
	_prepare()
	var count := 0
	var ground_batches: Dictionary = {}
	for feature in _features:
		if not rect.intersects(feature.bounds): continue
		var kind: int = feature.kind
		if not ground_batches.has(kind): ground_batches[kind]=_data()
		if _ground_patch(ground_batches[kind], feature, rect, height_callable): count+=1
	for kind in ground_batches:
		var data: Dictionary = ground_batches[kind]
		if data.vertices.is_empty(): continue
		var mesh := _mesh(parent, ["WindSculptedDunes", "ErodedDryWash", "CrackedSaltPan"][int(kind)], data, _ground_material(int(kind)))
		mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.set_meta("desert_expansion_ground", true)
		mesh.set_meta("vehicle_surface", "dirt")
		# Every raised face is also a physical face, including the gentle dune edge.
		# Salt lies only 16mm over the existing ground and needs no duplicate collider.
		if int(kind)<2: _ground_collision(mesh, data.vertices)
	var tracks := _data()
	_build_tracks(tracks, rect, height_callable)
	if not tracks.vertices.is_empty():
		var tracks_mesh := _mesh(parent, "OldOffroadWheelTracks", tracks, _ground_material(3))
		tracks_mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		count+=1
	for record in locations():
		if record.kind in ["dunes", "dry_wash", "salt_flat"]: continue
		var p := Vector2(record.position.x, record.position.z)
		# Half-open Rect2 ownership means one landmark even on a chunk boundary.
		if not rect.has_point(p): continue
		var radius := 18.0 if record.kind=="natural_arch" else 8.0
		if not placement_clear(p, radius): continue
		var landmark := Node3D.new()
		landmark.name=record.id
		landmark.position=Vector3(p.x, float(height_callable.call(p)), p.y)
		landmark.set_meta("desert_landform_id", record.id)
		landmark.set_meta("footprint_radius", radius)
		parent.add_child(landmark)
		var data := _data()
		var body := StaticBody3D.new()
		body.name="MatchedRockCollision"
		body.collision_layer=1
		body.collision_mask=0
		body.set_meta("vehicle_surface", "hard")
		landmark.add_child(body)
		match record.kind:
			"natural_arch": _arch(data, body)
			"hoodoo": _hoodoo(data, body, world_seed)
			"basalt": _basalt(data, body, world_seed)
			"balanced_rock": _balanced_rock(data, body, world_seed)
		_mesh(landmark, "WeatheredStone", data, _stone_material())
		count+=1
	return count

static func _prepare() -> void:
	if not _features.is_empty(): return
	for building in LAYOUT.buildings():
		var size := Vector2(building.size.x, building.size.z)
		var position := Vector2(building.position.x, building.position.z)
		_building_guards.append(Rect2(position-size*.5, size).grow(9.0))
	for row in [
		[Vector2(-72,-614), Vector2(20,11), 1.8, -.18],
		[Vector2(-25,-622), Vector2(24,14), 2.1, -.20],
		[Vector2(14,-594), Vector2(18,11), 1.65, -.28],
		[Vector2(-30,-568), Vector2(22,11), 1.4, -.16],
	]:
		var polygon := _oval(row[0], row[1], float(row[3]), false)
		_features.append({"kind":0, "center":row[0], "radius":row[1], "height":row[2], "yaw":row[3], "polygon":polygon, "bounds":_bounds(polygon)})
	var wash_polygon := PackedVector2Array()
	var right_bank := PackedVector2Array()
	for i in 45:
		var t := float(i)/44.0
		var center := wash_point(t)
		var tangent := (wash_point(minf(t+.002, 1.0))-wash_point(maxf(t-.002, 0.0))).normalized()
		var side := Vector2(-tangent.y, tangent.x)
		var width := _wash_width(t)
		wash_polygon.append(center+side*width)
		right_bank.append(center-side*width)
		if i>0: _wash_segments.append({"a":wash_point(float(i-1)/44.0), "b":center, "t":float(i-1)/44.0})
	right_bank.reverse()
	wash_polygon.append_array(right_bank)
	_features.append({"kind":1, "polygon":wash_polygon, "bounds":_bounds(wash_polygon)})
	var salt_polygon := _oval(SALT, Vector2(94,52), .12, true)
	_features.append({"kind":2, "center":SALT, "radius":Vector2(94,52), "polygon":salt_polygon, "bounds":_bounds(salt_polygon)})
	var cells: Dictionary = {}
	for feature in _features: _include_cells(cells,feature.bounds)
	_include_cells(cells,WASH_BOUNDS)
	for location in locations():
		if location.kind in ["dunes","dry_wash","salt_flat"]: continue
		cells[Vector2i(floori(location.position.x/RESOURCE_CELL),floori(location.position.z/RESOURCE_CELL))]=true
	for key: Vector2i in cells: _resource_cells.append(key)
	_resource_cells.sort_custom(func(a: Vector2i,b: Vector2i): return a.y<b.y or (a.y==b.y and a.x<b.x))
	assert(_resource_cells.size()<=MAX_CACHED_CELLS,"Authored landform warm-up must stay bounded")

static func _include_cells(cells: Dictionary, bounds: Rect2) -> void:
	for x in range(floori(bounds.position.x/RESOURCE_CELL),ceili(bounds.end.x/RESOURCE_CELL)):
		for z in range(floori(bounds.position.y/RESOURCE_CELL),ceili(bounds.end.y/RESOURCE_CELL)):
			cells[Vector2i(x,z)]=true

static func wash_point(t: float) -> Vector2:
	return Vector2(-750.0+215.0*t+sin(t*TAU)*16.0, -970.0-210.0*t)

static func _wash_width(t: float) -> float:
	return (12.5+sin(t*TAU*1.6)*2.2)*(.12+.88*sin(t*PI))

static func _oval(center: Vector2, radius: Vector2, yaw: float, irregular: bool) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 48:
		var angle := float(i)*TAU/48.0
		var variation := 1.0
		if irregular: variation+=sin(angle*3.0+.7)*.044+sin(angle*7.0)*.021
		var offset := Vector2(cos(angle)*radius.x, sin(angle)*radius.y)*variation
		points.append(center+offset.rotated(yaw))
	return points

static func _bounds(polygon: PackedVector2Array) -> Rect2:
	var result := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon: result=result.expand(point)
	return result

static func _ground_patch(data: Dictionary, feature: Dictionary, rect: Rect2, height_callable: Callable) -> bool:
	var area: Rect2 = rect.intersection(feature.bounds)
	if not area.has_area(): return false
	var before: int = data.vertices.size()
	var step := 8.0 if int(feature.kind)==2 else 3.0
	var polygon: PackedVector2Array = feature.polygon
	var vertex_cache: Dictionary = {}
	for z in range(floori(area.position.y/step), ceili(area.end.y/step)):
		for x in range(floori(area.position.x/step), ceili(area.end.x/step)):
			var tile := Rect2(float(x)*step, float(z)*step, step, step).intersection(area)
			if not placement_clear(tile.get_center(), step*.75): continue
			var clip := PackedVector2Array([tile.position, Vector2(tile.end.x,tile.position.y), tile.end, Vector2(tile.position.x,tile.end.y)])
			for part: PackedVector2Array in Geometry2D.intersect_polygons(polygon, clip):
				if Geometry2D.is_polygon_clockwise(part): part.reverse()
				var indices := Geometry2D.triangulate_polygon(part)
				for i in range(0, indices.size(), 3):
					var a := part[indices[i]]
					var b := part[indices[i+1]]
					var c := part[indices[i+2]]
					var va := _cached_vertex(a, feature, height_callable, vertex_cache)
					var vb := _cached_vertex(b, feature, height_callable, vertex_cache)
					var vc := _cached_vertex(c, feature, height_callable, vertex_cache)
					_triangle(data, va.position, vb.position, vc.position, va.color, vb.color, vc.color, Vector3.UP)
	return data.vertices.size()>before

static func _cached_vertex(point: Vector2, feature: Dictionary, height_callable: Callable, cache: Dictionary) -> Dictionary:
	if not cache.has(point): cache[point]=_ground_vertex(point,feature,height_callable)
	return cache[point]

static func _ground_vertex(point: Vector2, feature: Dictionary, height_callable: Callable) -> Dictionary:
	var mask := 0.0
	var elevation := 0.0
	var cracks := 0.0
	var border_distance := _border_distance(point,feature.polygon)
	match int(feature.kind):
		0:
			var offset: Vector2 = (point-Vector2(feature.center)).rotated(-float(feature.yaw))/Vector2(feature.radius)
			var radial := offset.length()
			mask=1.0-smoothstep(.55, 1.0, radial)
			# Broad smooth shoulders remain comfortably walkable and driveable.
			var belly := pow(maxf(0.0, 1.0-radial*radial), 2.0)
			elevation=float(feature.height)*belly*(.9+.1*sin(offset.y*2.5))
		1:
			var sample := _wash_sample(point)
			var t: float = sample.x
			var cross: float = sample.y
			var end_mask := smoothstep(0.0, .15, t)*(1.0-smoothstep(.85,1.0,t))
			mask=(1.0-smoothstep(.68,1.0,cross))*end_mask
			# A dry stream bed over the existing terrain, with shallow eroded banks.
			elevation=(smoothstep(.32,.66,cross)*(1.0-smoothstep(.70,1.0,cross)))*.64*end_mask
			cracks=(1.0-smoothstep(.34,.65,cross))*end_mask
		2:
			mask=smoothstep(0.0, 10.0, border_distance)
			cracks=mask
	var ground_offset := .016
	if int(feature.kind)<2:
		# An upright vehicle hull cannot step over even a16mm exposed mesh edge.
		# Both visual mesh and collider merge into the existing floor at the exact
		# polygon perimeter; the interior retains its full authored sand volume.
		# The1mm band also absorbs clipping roundoff at large world coordinates.
		elevation*=smoothstep(.001,.75,border_distance)
		ground_offset*=smoothstep(.001,2.4,border_distance)
	return {"position":Vector3(point.x, float(height_callable.call(point))+ground_offset+elevation, point.y), "color":Color(mask,cracks,0,1)}

static func _border_distance(point: Vector2, polygon: PackedVector2Array) -> float:
	var distance := INF
	for i in polygon.size():
		distance=minf(distance,point.distance_to(Geometry2D.get_closest_point_to_segment(point,polygon[i],polygon[(i+1)%polygon.size()])))
	return distance

static func _wash_sample(point: Vector2) -> Vector2:
	var approximate := clampi(floori((-point.y-970.0)/210.0*44.0),0,43)
	var nearest := INF
	var sample_t := 0.0
	for i in range(maxi(0,approximate-5),mini(44,approximate+6)):
		var segment: Dictionary = _wash_segments[i]
		var delta: Vector2 = segment.b-segment.a
		var weight := clampf((point-Vector2(segment.a)).dot(delta)/delta.length_squared(),0.0,1.0)
		var closest: Vector2 = segment.a+delta*weight
		var distance := point.distance_to(closest)
		if distance>=nearest: continue
		nearest=distance
		sample_t=float(segment.t)+weight/44.0
	return Vector2(sample_t,nearest/maxf(_wash_width(sample_t),.1))

static func _build_tracks(data: Dictionary, rect: Rect2, height_callable: Callable) -> void:
	if not rect.intersects(WASH_BOUNDS): return
	# Paired old tire impressions remain on the flat centre of the dry stream bed.
	# Each small segment has exactly one owner and follows the supplied ground.
	for i in 174:
		var t := .075+float(i)*.85/174.0
		var next := minf(t+.0038, .925)
		var a := wash_point(t)
		var b := wash_point(next)
		if not rect.has_point((a+b)*.5): continue
		var side := Vector2(-(b-a).y, (b-a).x).normalized()
		for lane in [-.88, .88]:
			var points: Array[Vector3] = []
			for point in [a+side*(lane-.12), a+side*(lane+.12), b+side*(lane+.12), b+side*(lane-.12)]:
				points.append(Vector3(point.x, float(height_callable.call(point))+.025, point.y))
			var fade := smoothstep(.075,.13,t)*(1.0-smoothstep(.85,.925,t))*.72
			_quad(data, points[0], points[1], points[2], points[3], Color(fade,0,0,1), Vector3.UP)

static func _arch(data: Dictionary, body: StaticBody3D) -> void:
	# Separate convex wedges preserve the traversable opening; no bounding-box wall.
	for i in 14:
		var points := PackedVector3Array()
		for angle in [float(i)*PI/14.0, float(i+1)*PI/14.0]:
			for inner in [false, true]:
				var radius := 8.0 if inner else 14.0
				var height := 7.4 if inner else 11.8
				var x := cos(angle)*radius
				var y := sin(angle)*height-.24
				var depth := 2.5+sin(angle)*.7
				for side in [-1.0, 1.0]: points.append(Vector3(x,y,side*depth))
		_prism(data, body, points, Color("b08a65"), i)
	# A low talus fan visually anchors the feet while leaving the portal clear.
	for row in [[Vector3(-14.2,-.18,1.5),Vector3(6.4,1.6,6.1)], [Vector3(13.5,-.18,-.8),Vector3(5.2,1.5,6.5)]]:
		_boulder(data, body, row[0], row[1], 810+int(row[0].x), Color("a77f59"))

static func _hoodoo(data: Dictionary, body: StaticBody3D, world_seed: int) -> void:
	_layered_column(data, body, Vector3(0,-.15,0), [0.0,1.1,3.9,6.4,7.4], [3.2,2.3,1.55,1.1,1.45], Color("a77b55"), world_seed+2301, 8)
	_boulder(data, body, Vector3(0,6.95,0), Vector3(6.3,2.2,4.9), world_seed+2302, Color("ceb28a"))
	_boulder(data, body, Vector3(3.3,-.12,1.1), Vector3(3.1,1.3,2.4), world_seed+2303, Color("ac845f"))

static func _basalt(data: Dictionary, body: StaticBody3D, world_seed: int) -> void:
	for i in 7:
		var angle := float(i)*TAU/6.0
		var center := Vector3(cos(angle)*2.1,-.18,sin(angle)*2.1) if i<6 else Vector3(0,-.18,0)
		var height := 3.3+float((i*3)%5)*.52
		_layered_column(data, body, center, [0.0,height*.47,height], [1.24,1.2,1.03], Color("72706a"), world_seed+i*17+2410, 6)
	for i in 3:
		_boulder(data, body, Vector3(-3.4+float(i)*2.7,-.15,4.2), Vector3(2.0,1.1,2.3), world_seed+i+2500, Color("77756b"))

static func _balanced_rock(data: Dictionary, body: StaticBody3D, world_seed: int) -> void:
	_layered_column(data, body, Vector3(0,-.1,0), [0.0,1.0,4.3,5.4], [2.9,2.15,1.05,1.3], Color("977753"), world_seed+2600, 9)
	_boulder(data, body, Vector3(.48,4.86,.1), Vector3(7.4,3.7,4.8), world_seed+2601, Color("c1a07b"))

static func _layered_column(data: Dictionary, body: StaticBody3D, at: Vector3, heights: Array, radii: Array, color: Color, seed_value: int, sides: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed=absi(seed_value)
	var outline := PackedVector2Array()
	for i in sides:
		var angle := float(i)*TAU/float(sides)+.13
		outline.append(Vector2(cos(angle),sin(angle))*rng.randf_range(.92,1.0))
	for level in heights.size()-1:
		var bottom := PackedVector3Array()
		var top := PackedVector3Array()
		for p in outline:
			bottom.append(at+Vector3(p.x*float(radii[level]),float(heights[level]),p.y*float(radii[level])))
			top.append(at+Vector3(p.x*float(radii[level+1]),float(heights[level+1]),p.y*float(radii[level+1])))
		var points := PackedVector3Array()
		points.append_array(bottom)
		points.append_array(top)
		_hull(body, points)
		for i in sides:
			var j := (i+1)%sides
			var shade := color.lightened(.035*float(level%2))
			_quad(data,bottom[i],bottom[j],top[j],top[i],shade,(bottom[i]-at)*Vector3(1,0,1))
			if level==heights.size()-2: _triangle(data,top[i],top[j],at+Vector3.UP*float(heights[-1]),color.lightened(.1),color.lightened(.1),color.lightened(.1),Vector3.UP)

static func _boulder(data: Dictionary, body: StaticBody3D, foot: Vector3, size: Vector3, seed_value: int, color: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed=absi(seed_value)
	var rings: Array[PackedVector3Array] = []
	for level in 4:
		var ring := PackedVector3Array()
		for i in 8:
			var angle := float(i)*TAU/8.0
			var radius: float = [0.64,1.0,.83,.38][level]
			var y: float = [0.0,.27,.74,1.0][level]
			var variation := rng.randf_range(.87,1.0)
			ring.append(foot+Vector3(cos(angle)*size.x*.5*radius*variation,y*size.y,sin(angle)*size.z*.5*radius*variation))
		rings.append(ring)
	for level in 3:
		var hull := PackedVector3Array()
		hull.append_array(rings[level])
		hull.append_array(rings[level+1])
		_hull(body,hull)
		for i in 8:
			var j := (i+1)%8
			var shade := color.darkened(.09-float(level)*.035)
			_quad(data,rings[level][i],rings[level][j],rings[level+1][j],rings[level+1][i],shade,(rings[level][i]-foot)*Vector3(1,0,1))
	for i in 8: _triangle(data,rings[3][i],rings[3][(i+1)%8],foot+Vector3.UP*size.y,color.lightened(.09),color.lightened(.09),color.lightened(.09),Vector3.UP)

static func _prism(data: Dictionary, body: StaticBody3D, points: PackedVector3Array, color: Color, index: int) -> void:
	_hull(body, points)
	var center := Vector3.ZERO
	for p in points: center+=p/float(points.size())
	for face in [[0,1,3,2],[4,6,7,5],[0,4,5,1],[2,3,7,6],[0,2,6,4],[1,5,7,3]]:
		var a := points[face[0]]
		var b := points[face[1]]
		var c := points[face[2]]
		var d := points[face[3]]
		var shade := color.lightened(.022*float(index%3))
		_quad(data,a,b,c,d,shade,(a+b+c+d)*.25-center)

static func _hull(body: StaticBody3D, points: PackedVector3Array) -> void:
	var shape := ConvexPolygonShape3D.new()
	shape.points=points
	var collider := CollisionShape3D.new()
	collider.shape=shape
	body.add_child(collider)

static func _ground_collision(node: MeshInstance3D, vertices: PackedVector3Array) -> void:
	var body := StaticBody3D.new()
	body.name="MatchingGroundFaces"
	body.collision_layer=1
	body.collision_mask=0
	body.set_meta("vehicle_surface", "dirt")
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(vertices)
	var collider := CollisionShape3D.new()
	collider.shape=shape
	body.add_child(collider)
	node.add_child(body)

static func _data() -> Dictionary:
	return {"vertices":PackedVector3Array(), "normals":PackedVector3Array(), "colors":PackedColorArray()}

static func _quad(data: Dictionary, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, outward: Vector3) -> void:
	_triangle(data,a,b,c,color,color,color,outward)
	_triangle(data,a,c,d,color,color,color,outward)

static func _triangle(data: Dictionary, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, outward: Vector3) -> void:
	var normal := (c-a).cross(b-a).normalized()
	if normal.dot(outward)<0:
		var swap := b
		b=c
		c=swap
		var swap_color := cb
		cb=cc
		cc=swap_color
		normal=-normal
	data.vertices.append_array(PackedVector3Array([a,b,c]))
	data.normals.append_array(PackedVector3Array([normal,normal,normal]))
	data.colors.append_array(PackedColorArray([ca,cb,cc]))

static func _mesh(parent: Node3D, label: String, data: Dictionary, material: Material) -> MeshInstance3D:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=data.vertices
	arrays[Mesh.ARRAY_NORMAL]=data.normals
	arrays[Mesh.ARRAY_COLOR]=data.colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node := MeshInstance3D.new()
	node.name=label
	node.mesh=mesh
	node.material_override=material
	parent.add_child(node)
	return node

static func _ground_material(kind: int) -> ShaderMaterial:
	if not _ground_materials.has(kind):
		var material := ShaderMaterial.new()
		material.shader=SURFACE
		material.set_shader_parameter("landform_kind",kind)
		_ground_materials[kind]=material
	return _ground_materials[kind]

static func _stone_material() -> StandardMaterial3D:
	if _rock_material==null:
		_rock_material=StandardMaterial3D.new()
		_rock_material.vertex_color_use_as_albedo=true
		_rock_material.vertex_color_is_srgb=true
		_rock_material.roughness=.98
	return _rock_material
