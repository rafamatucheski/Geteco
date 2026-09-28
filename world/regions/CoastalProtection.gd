extends RefCounted
## Exposed edges of the actual dry footprint, split at intersections and chunk lines.
## All geometry/collision is static and owned by the streamed chunk.
const CELL := 64.0
const HEIGHT := 1.15
var polygons: Array[PackedVector2Array] = []
var boundaries: Array[Dictionary] = []
var cells: Dictionary = {}
var materials: Dictionary = {}
var box_mesh := BoxMesh.new()
var bridge_walks: Array[PackedVector2Array] = []
var existing_perimeters: Array[PackedVector2Array] = []

func configure(data: Dictionary, extra: Array[PackedVector2Array], road_surfaces: Array) -> void:
	polygons.clear()
	boundaries.clear()
	cells.clear()
	bridge_walks.clear()
	existing_perimeters.clear()
	for row in data.harbor_land:
		polygons.append(_rect(Rect2(float(row[0])/16,float(row[1])/16,float(row[2])/16,float(row[3])/16)))
	polygons.append_array(extra)
	# The public passenger quay supplies its own deck and guards. Union its
	# footprint before extracting edges so the old walkway rail has a real opening.
	polygons.append(_rect(Rect2(218,191.5,20,11)))
	var ship := PackedVector2Array()
	for p in data.ship_deck: ship.append(Vector2(p[0],p[1])/16.0)
	polygons.append(ship)
	existing_perimeters.append(ship)
	var south_hull := preload("res://world/regions/OriginalSouthPortLayout.gd").ship_hull()
	for i in south_hull.size(): south_hull[i] /= 16.0
	existing_perimeters.append(south_hull)
	polygons.append(_rect(Rect2(3130.0/16,1742.0/16,288.0/16,40.0/16)))
	for polygon: PackedVector2Array in road_surfaces:
		var exposed := false
		for i in polygon.size():
			var a := polygon[i]
			var b := polygon[(i+1)%polygon.size()]
			var steps := maxi(1,ceili(a.distance_to(b)/4.0))
			for step in range(steps+1):
				if not on_land(a.lerp(b,float(step)/steps)): exposed = true; break
			if exposed: break
		if exposed: bridge_walks.append(polygon)
	# Test against original dry land before adding any road footprints.
	for polygon in road_surfaces: polygons.append(polygon)
	# FoundryBridge3D owns its outer rails; avoid a second guard in its sidewalk.
	var foundry_deck := _rect(Rect2(200,18.125,73.75,13.75))
	polygons.append(foundry_deck)
	bridge_walks.append(foundry_deck)
	# Existing bridge/tunnel structure owns its guards, including the eastern exit.
	polygons.append(_rect(Rect2(393.75,-296.5,11.25,23)))
	polygons.append(PackedVector2Array([Vector2(405,-296),Vector2(456.25,-292.15),Vector2(456.25,-277.85),Vector2(405,-274.5)]))
	polygons.append(_rect(Rect2(456.25,-292.2,122.0,14.4)))
	_extract()

static func _rect(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])

func on_land(point: Vector2) -> bool:
	for polygon in polygons:
		if Geometry2D.is_point_in_polygon(point,polygon): return true
	return false

func _extract() -> void:
	var edges: Array[Dictionary] = []
	for polygon in polygons:
		for i in polygon.size():
			var a := polygon[i]
			var b := polygon[(i+1)%polygon.size()]
			if a.distance_to(b)<0.01: continue
			edges.append({"a":a,"b":b,"bounds":Rect2(a,Vector2.ZERO).expand(b).grow(0.02)})
	var seen := {}
	for edge in edges:
		var a: Vector2 = edge.a
		var b: Vector2 = edge.b
		var delta := b-a
		var cuts: Array[float] = [0.0,1.0]
		for other in edges:
			if not edge.bounds.intersects(other.bounds): continue
			var hit = Geometry2D.segment_intersects_segment(a,b,other.a,other.b)
			if hit is Vector2: cuts.append(clampf((hit-a).dot(delta)/delta.length_squared(),0,1))
			# Coincident boundaries need their endpoints too.
			for point: Vector2 in [other.a,other.b]:
				if point.distance_to(Geometry2D.get_closest_point_to_segment(point,a,b))<0.005:
					cuts.append(clampf((point-a).dot(delta)/delta.length_squared(),0,1))
		cuts.sort()
		for i in range(cuts.size()-1):
			var start := a+delta*cuts[i]
			var end := a+delta*cuts[i+1]
			if start.distance_to(end)<0.025: continue
			var midpoint := (start+end)*0.5
			var normal := Vector2(-delta.y,delta.x).normalized()
			var left := on_land(midpoint+normal*0.02)
			var right := on_land(midpoint-normal*0.02)
			if left == right: continue
			if left: normal = -normal
			# Ships and bridge already have authored rails. Keep their boarding gaps.
			if _existing_guard(midpoint): continue
			var key := str(midpoint.snapped(Vector2.ONE*0.01))
			if seen.has(key): continue
			seen[key] = true
			var record := {"a":start,"b":end,"outward":normal,"style":_style(midpoint)}
			boundaries.append(record)
			_index(record)

func _existing_guard(point: Vector2) -> bool:
	if Rect2(217.9,191.4,20.2,11.2).has_point(point): return true
	if point.x>=200 and point.x<=273.75 and point.y>=18.1 and point.y<=31.9: return true
	if point.x>=405 and point.y < -270: return true
	for polygon in existing_perimeters:
		for i in polygon.size():
			if point.distance_to(Geometry2D.get_closest_point_to_segment(point,polygon[i],polygon[(i+1)%polygon.size()]))<0.1: return true
	if Rect2(3128.0/16,1736.0/16,295.0/16,48.0/16).has_point(point): return true
	if Rect2(4210.0/16,3118.0/16,76.0/16,134.0/16).has_point(point): return true
	return false

func _style(point: Vector2) -> String:
	if point.y < -150: return "highway"
	if point.x < -8 or point.x > 410: return "stone"
	if point.y > 156 or (point.x > 195 and point.x < 275): return "industrial"
	return "urban"

func _index(record: Dictionary) -> void:
	var a: Vector2 = record.a
	var b: Vector2 = record.b
	var delta := b-a
	var cuts: Array[float] = [0,1]
	for axis in 2:
		if absf(delta[axis])<0.0001: continue
		for cell in range(floori(minf(a[axis],b[axis])/CELL)+1,ceili(maxf(a[axis],b[axis])/CELL)):
			cuts.append((cell*CELL-a[axis])/delta[axis])
	cuts.sort()
	for i in range(cuts.size()-1):
		var start := a+delta*cuts[i]
		var end := a+delta*cuts[i+1]
		if start.distance_to(end)<0.01: continue
		# Put the guard on dry ground. Ownership follows that same inset.
		var inset: Vector2 = record.outward*0.24
		var center := (start+end)*0.5-inset
		var key := Vector2i(floori(center.x/CELL),floori(center.y/CELL))
		if not cells.has(key): cells[key] = []
		cells[key].append({"a":start-inset,"b":end-inset,"style":record.style})

func build_chunk(parent: Node3D, rect: Rect2) -> void:
	_build_walk_support(parent,rect)
	var key := Vector2i(floori(rect.position.x/CELL),floori(rect.position.y/CELL))
	if not cells.has(key): return
	var root := Node3D.new()
	root.name = "CoastalProtection"
	parent.add_child(root)
	var body := StaticBody3D.new()
	body.name = "CoastalBarrierSolid"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	var batches := {}
	for record in cells[key]:
		var a: Vector2 = record.a
		var b: Vector2 = record.b
		var delta := b-a
		var center := Vector3((a.x+b.x)*0.5,0,(a.y+b.y)*0.5)
		var basis := Basis(Vector3.UP,atan2(delta.x,delta.y))
		var length := delta.length()+0.16
		var style: String = record.style
		var width := 0.46 if style != "stone" else 0.65
		var shape := BoxShape3D.new()
		shape.size = Vector3(width,HEIGHT,length)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.transform = Transform3D(basis,center+Vector3.UP*HEIGHT*0.5)
		body.add_child(collider)
		if style == "industrial":
			_part(batches,"concrete",basis,center+Vector3.UP*0.10,Vector3(width,0.20,length))
			for y in [0.55,1.10]: _part(batches,"steel",basis,center+Vector3.UP*y,Vector3(0.12,0.10,length))
		elif style == "urban":
			_part(batches,"masonry",basis,center+Vector3.UP*0.40,Vector3(width,0.8,length))
			_part(batches,"cap",basis,center+Vector3.UP*0.83,Vector3(width+0.06,0.12,length))
			_part(batches,"dark_steel",basis,center+Vector3.UP*1.10,Vector3(0.09,0.10,length))
		elif style == "highway":
			_part(batches,"concrete",basis,center+Vector3.UP*0.47,Vector3(width,0.94,length))
			_part(batches,"steel",basis,center+Vector3.UP*1.08,Vector3(0.18,0.14,length))
		else:
			_part(batches,"stone",basis,center+Vector3.UP*0.54,Vector3(width,1.08,length))
			var blocks := maxi(1,ceili(length/1.15))
			for i in blocks:
				var point := a.lerp(b,(float(i)+0.5)/blocks)
				var height := 1.12+0.14*sin(point.x*2.7+point.y*1.3)
				_part(batches,"stone_cap",basis,Vector3(point.x,height-0.07,point.y),Vector3(width+0.12,0.22,length/blocks+0.04))
		if style in ["urban","industrial"]:
			var posts := maxi(1,ceili(delta.length()/2.5))
			for i in range(posts+1):
				var point := a.lerp(b,float(i)/posts)
				_part(batches,"steel" if style=="industrial" else "dark_steel",basis,Vector3(point.x,0.58,point.y),Vector3(0.14,1.16,0.14))
	for id in batches:
		var instance := MultiMeshInstance3D.new()
		instance.name = id
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = box_mesh
		mm.instance_count = batches[id].size()
		for i in mm.instance_count: mm.set_instance_transform(i,batches[id][i])
		instance.multimesh = mm
		instance.material_override = _material(id)
		root.add_child(instance)

func _build_walk_support(parent: Node3D, rect: Rect2) -> void:
	# The original road collider covered asphalt only; over water its visible
	# sidewalks need support before a pedestrian can reach the new guard.
	var faces := PackedVector3Array()
	for polygon in bridge_walks:
		for piece in Geometry2D.intersect_polygons(polygon,_rect(rect)):
			var triangles := Geometry2D.triangulate_polygon(piece)
			for i in range(0,triangles.size(),3):
				var a: Vector2 = piece[triangles[i]]
				var b: Vector2 = piece[triangles[i+1]]
				var c: Vector2 = piece[triangles[i+2]]
				var va := Vector3(a.x,0,a.y)
				var vb := Vector3(b.x,0,b.y)
				var vc := Vector3(c.x,0,c.y)
				faces.append(va)
				if (vb-va).cross(vc-va).y>0: faces.append(vc); faces.append(vb)
				else: faces.append(vb); faces.append(vc)
	if faces.is_empty(): return
	var body := StaticBody3D.new()
	body.name = "CoastalWalkSupport"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	parent.add_child(body)

func _part(batches: Dictionary, id: String, basis: Basis, center: Vector3, size: Vector3) -> void:
	if not batches.has(id): batches[id] = []
	batches[id].append(Transform3D(basis.scaled_local(size),center))

func _material(id: String) -> StandardMaterial3D:
	if materials.has(id): return materials[id]
	var palette := {"concrete":"727b78","steel":"9aaca8","dark_steel":"354946","masonry":"848477","cap":"b1b2a3","stone":"686c5e","stone_cap":"8b8978"}
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(palette[id])
	mat.roughness = 0.88
	materials[id] = mat
	return mat
