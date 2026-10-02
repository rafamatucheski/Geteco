extends Node3D
## Rural extension in Harbor world coordinates. OriginalWorldData owns its
## streamed physical ground and road; this node adds static, spatially batched
## woodland without another overlapping floor collider or a per-frame loop.
const LAND := Rect2(-430, -160, 350, 318)
const SECRET_CELLAR_OPENING := Rect2(-413.25,85.35,6.10,3.30)
const SITE_CLEARANCE := Rect2(-394, -118, 111, 125)
const ROAD := [Vector2(-55,137.5), Vector2(-65,144), Vector2(-105,144),
	Vector2(-120,118),Vector2(-120,70),Vector2(-145,34),
	Vector2(-200,34), Vector2(-250,10), Vector2(-290,10), Vector2(-320,18),
	Vector2(-340,18), Vector2(-340,-2)]
const CELL := 64.0
const VILLAGE_ROAD := [Vector2(-290,10),Vector2(-290,32),Vector2(-285,48),
	Vector2(-286,66),Vector2(-290,82),Vector2(-304,95)]
var tree_positions: Array[Vector3] = []
var _batches: Dictionary = {}
var _meshes: Dictionary = {}
var _materials: Dictionary = {}
var _trunks: StaticBody3D

func _ready() -> void:
	name = "FreightOutskirts"
	_build_resources()
	_ground_finish()
	_trunks = StaticBody3D.new()
	_trunks.name = "WoodlandTrunks"
	add_child(_trunks)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9282026
	# A loose, irregular lattice prevents intersecting trunks and keeps all
	# canopy meshes away from the truck corridor and the company's fence.
	for x in range(-422, -99, 12):
		for z in range(-150, 151, 12):
			var point := Vector2(float(x)+rng.randf_range(-3.5,3.5),float(z)+rng.randf_range(-3.5,3.5))
			if not _available(point,11.0) or rng.randf()<0.12: continue
			_tree(point,rng)
	for index in 580:
		var point := Vector2(rng.randf_range(-422,-101),rng.randf_range(-153,150))
		if not _available(point,8.1): continue
		var scale_value := rng.randf_range(0.5,1.25)
		var tint := Color(0.83,0.96,0.76).lerp(Color(1.03,0.93,0.70),rng.randf())
		_put("shrub",Vector3(point.x,0.36*scale_value,point.y),Vector3(1.2,0.65,1.0)*scale_value,rng.randf()*TAU,tint)
	for index in 72:
		var point := Vector2(rng.randf_range(-422,-101),rng.randf_range(-153,150))
		if not _available(point,8.6): continue
		# Low stones are below a normal walking step, not false solid boulders.
		_put("stone",Vector3(point.x,0.055,point.y),Vector3(rng.randf_range(.25,.65),.11,rng.randf_range(.3,.8)),rng.randf()*TAU,Color.WHITE)
	for index in 12000:
		var point := Vector2(rng.randf_range(-422,-101),rng.randf_range(-153,150))
		if not _available(point,5.0): continue
		var size_value := rng.randf_range(.85,1.75)
		_put("grass",Vector3(point.x,-.02,point.y),Vector3.ONE*size_value,rng.randf()*TAU,Color(.9,1,.85))
	_flush()

static func _available(point: Vector2, road_clearance: float) -> bool:
	# Reserve the marked motocross park and its access; trunks must not pierce ramps.
	if preload("res://activities/motocross/MotocrossCourse.gd").BOUNDS.grow(4).has_point(point): return false
	if Rect2(-229,-40,9,75).has_point(point): return false
	# Keep the rental porch, picnic seats and parked motorcycle bays free.
	if Rect2(-240,-41,30,18).grow(2).has_point(point): return false
	if SITE_CLEARANCE.grow(5.0).has_point(point): return false
	# Keep the village, its back-yard paths and the truck approach free of trunks.
	if Rect2(-418,62,176,88).grow(5.0).has_point(point): return false
	for index in VILLAGE_ROAD.size()-1:
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point,VILLAGE_ROAD[index],VILLAGE_ROAD[index+1])) < 10.0: return false
	for index in ROAD.size()-1:
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point,ROAD[index],ROAD[index+1]))<road_clearance: return false
	return true

func _build_resources() -> void:
	# One shared wood mesh includes the tapered trunk and four forked branches.
	# Their dark/light faces read as long bark furrows without texture sampling.
	_meshes["trunk"] = _wood_mesh()
	for variant in 3: _meshes["crown_%d"%variant] = _canopy_mesh(variant)
	var crown := SphereMesh.new()
	crown.radius = 0.5
	crown.height = 1.0
	crown.radial_segments = 9
	crown.rings = 5
	_meshes["shrub"] = crown
	_meshes["stone"] = crown
	_meshes["grass"] = preload("res://world/urban_detail/HarborGrassTufts.gd")._tuft_mesh()
	_materials["grass"] = preload("res://activities/motocross/MotocrossGroundDetail.gd").grass_material()
	for entry in [["trunk",Color("65503b")],["crown_0",Color("425d36")],["crown_1",Color("66784a")],
		["crown_2",Color("526d43")],["shrub",Color("5e7545")],["stone",Color("8e9280")]]:
		var material := StandardMaterial3D.new()
		material.albedo_color = entry[1]
		material.vertex_color_use_as_albedo = true
		material.roughness = 0.94
		_materials[entry[0]] = material

static func _face(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, tint: Color) -> void:
	var normal := (b-a).cross(c-a).normalized()
	# Godot front faces are clockwise. Keep outward normals and expose the bark.
	for point in [a,c,b]:
		surface.set_normal(normal)
		surface.set_color(tint)
		surface.add_vertex(point)

static func _limb(surface: SurfaceTool, start: Vector3, finish: Vector3, radius: float, taper: float, sides: int) -> void:
	var axis := finish-start
	var local_basis := Basis(Quaternion(Vector3.UP,axis.normalized()))
	for side in sides:
		var a := TAU*float(side)/float(sides)
		var b := TAU*float(side+1)/float(sides)
		var bottom_a := start+local_basis*Vector3(cos(a)*radius,0,sin(a)*radius)
		var bottom_b := start+local_basis*Vector3(cos(b)*radius,0,sin(b)*radius)
		var top_a := finish+local_basis*Vector3(cos(a)*radius*taper,0,sin(a)*radius*taper)
		var top_b := finish+local_basis*Vector3(cos(b)*radius*taper,0,sin(b)*radius*taper)
		var shade := .68 + .11*float(side%4)
		var tint := Color(shade,shade*.98,shade*.93)
		_face(surface,bottom_a,top_a,top_b,tint)
		_face(surface,bottom_a,top_b,bottom_b,tint)
		_face(surface,finish,top_b,top_a,tint)

static func _wood_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_limb(surface,Vector3(0,-.008,0),Vector3(0,.67,0),.04,.72,8)
	for root_index in 5:
		var angle := root_index*TAU/5
		_limb(surface,Vector3(0,.02,0),Vector3(cos(angle)*.11,-.003,sin(angle)*.11),.012,.15,5)
	# Keep branch cross sections in normalized tree-height units, then scale
	# X/Z by radius/.04 and Y by total height (avoids flattened giant limbs).
	for index in 4:
		var angle := float(index)*2.39+.3
		var start := Vector3(0,.35+float(index)*.045,0)
		var finish := Vector3(cos(angle)*(.16+index*.014),.60+index*.038,sin(angle)*(.16+index*.014))
		_limb(surface,start,finish,.0172,.14,6)
	return surface.commit()

static func _canopy_mesh(variant: int) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centers := [Vector3(-.05,.03,0),Vector3(.28,-.12,.12),Vector3(-.27,-.05,-.10),Vector3(.08,.29,-.07),Vector3(-.05,-.07,.31)]
	var sizes := [Vector3(.38,.40,.34),Vector3(.28,.29,.25),Vector3(.29,.33,.26),Vector3(.27,.29,.26),Vector3(.29,.26,.25)]
	for mass in centers.size():
		var center: Vector3 = centers[mass]
		center.x *= 1.0 + float(variant)*.08
		center.z += sin(float(mass+variant)*1.7)*.065
		var size: Vector3 = sizes[mass]
		size.y *= 1.0 + sin(float(variant*3+mass))*.16
		var tint := Color.WHITE.darkened(.055*float((mass+variant)%3))
		for ring in 4:
			for side in 7:
				var points: Array[Vector3] = []
				for corner in [Vector2i(side,ring),Vector2i(side+1,ring),Vector2i(side+1,ring+1),Vector2i(side,ring+1)]:
					var angle := TAU*float(corner.x)/7.0
					var latitude := PI*float(corner.y)/4.0
					var wobble := 1.0 + sin(angle*3.0+float(mass+variant)*1.7+latitude)*.11
					points.append(center+Vector3(cos(angle)*sin(latitude)*wobble,cos(latitude),sin(angle)*sin(latitude)*wobble)*size)
				if ring > 0: _face(surface,points[0],points[1],points[2],tint)
				if ring < 3: _face(surface,points[0],points[2],points[3],tint)
	return surface.commit()

func _ground_finish() -> void:
	var pieces := _rect_outside(LAND,SECRET_CELLAR_OPENING)
	for index in pieces.size():
		var piece: Rect2 = pieces[index]
		var ground := MeshInstance3D.new()
		ground.name = "WoodlandFloorFinish%d"%index
		var plane := PlaneMesh.new()
		plane.size = piece.size
		ground.mesh = plane
		ground.position = Vector3(piece.get_center().x,0.001,piece.get_center().y)
		ground.material_override = preload("res://activities/motocross/MotocrossGroundDetail.gd").ground_material()
		ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ground)

func _rect_outside(surface: Rect2,hole: Rect2) -> Array[Rect2]:
	var overlap := surface.intersection(hole)
	if not overlap.has_area(): return [surface]
	var pieces: Array[Rect2] = []
	if overlap.position.y>surface.position.y: pieces.append(Rect2(surface.position,Vector2(surface.size.x,overlap.position.y-surface.position.y)))
	if overlap.end.y<surface.end.y: pieces.append(Rect2(Vector2(surface.position.x,overlap.end.y),Vector2(surface.size.x,surface.end.y-overlap.end.y)))
	if overlap.position.x>surface.position.x: pieces.append(Rect2(Vector2(surface.position.x,overlap.position.y),Vector2(overlap.position.x-surface.position.x,overlap.size.y)))
	if overlap.end.x<surface.end.x: pieces.append(Rect2(Vector2(overlap.end.x,overlap.position.y),Vector2(surface.end.x-overlap.end.x,overlap.size.y)))
	return pieces

func _tree(point: Vector2, rng: RandomNumberGenerator) -> void:
	var height := rng.randf_range(7.0,12.0)
	var radius := rng.randf_range(0.24,0.39)
	var trunk_height := height*0.67
	var trunk_center := Vector3(point.x,trunk_height*0.5,point.y)
	_put("trunk",Vector3(point.x,0,point.y),Vector3(radius/.04,height,radius/.04),rng.randf()*TAU,Color.WHITE)
	var crown_size := rng.randf_range(4.3,6.4)
	_put("crown_%d"%rng.randi_range(0,2),Vector3(point.x,height*0.70,point.y),Vector3(crown_size,height*.54,crown_size*.94),rng.randf()*TAU,Color.WHITE)
	var collider := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = trunk_height
	collider.shape = shape
	collider.position = trunk_center
	_trunks.add_child(collider)
	tree_positions.append(Vector3(point.x,0,point.y))

func _put(kind: String, point: Vector3, scale_value: Vector3, yaw: float, tint: Color) -> void:
	var cell := Vector2i(floori(point.x/CELL),floori(point.z/CELL))
	var key := "%s_%d_%d" % [kind,cell.x,cell.y]
	if not _batches.has(key): _batches[key] = {"kind":kind,"cell":cell,"transforms":[],"colors":[]}
	var local := point-Vector3(cell.x*CELL,0,cell.y*CELL)
	_batches[key].transforms.append(Transform3D(Basis(Vector3.UP,yaw).scaled(scale_value),local))
	_batches[key].colors.append(tint)

func _flush() -> void:
	for key in _batches:
		var batch: Dictionary = _batches[key]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = _meshes[batch.kind]
		multimesh.instance_count = batch.transforms.size()
		for index in batch.transforms.size():
			multimesh.set_instance_transform(index,batch.transforms[index])
			multimesh.set_instance_color(index,batch.colors[index])
		var display := MultiMeshInstance3D.new()
		display.name = key
		display.position = Vector3(batch.cell.x*CELL,0,batch.cell.y*CELL)
		display.multimesh = multimesh
		display.material_override = _materials[batch.kind]
		if batch.kind in ["shrub","stone","grass"]: display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if batch.kind=="grass":
			display.visibility_range_end = 100
			display.visibility_range_end_margin = 15
		add_child(display)
	_batches.clear()
