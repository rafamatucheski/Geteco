extends RefCounted
## Visible to normal world cameras; omitted only by the house interior camera.
const INTERIOR_OCCLUDING_CANOPY_LAYER := 1 << 19
## Static garden vegetation: shared meshes, spatial batches, no wind/frame loop.
const TREES := [Vector3(-83,0,-38),Vector3(-66,0,-35),Vector3(-58,0,-18),
	Vector3(-86,0,27),Vector3(-61,0,35),Vector3(-32,0,34),Vector3(3,0,33),
	Vector3(37,0,33),Vector3(81,0,33),Vector3(82,0,7),Vector3(81,0,-11),
	Vector3(55,0,-27),Vector3(1,0,-30),Vector3(17,0,-15),Vector3(-6,0,22),
	Vector3(25,0,20),Vector3(-30,0,18),Vector3(59,0,36)]
const WALKS := [[Vector2(-35,3),Vector2(-50,3),Vector2(-54,14),Vector2(-35,14)],
	[Vector2(3,1),Vector2(17,1),Vector2(27,10),Vector2(3,10)],
	[Vector2(44,3),Vector2(49,3),Vector2(49,24),Vector2(44,24)]]
const FOOTPATH := [Vector2(44,-53),Vector2(44,-42),Vector2(40,-26),Vector2(26,-13),Vector2(15,-2),Vector2(-5,4)]
static var _crown: ArrayMesh


static func build(v: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed=280920261
	var leaves := _paint("52713c")
	var wood := _paint("62503a")
	var tree_wood: Array[Transform3D] = []
	var tree_leaves: Array[Transform3D] = []
	for point in TREES:
		var size := rng.randf_range(.83,1.13)
		var turn := Basis(Vector3.UP,rng.randf()*TAU)
		tree_wood.append(Transform3D(turn.scaled(Vector3(6.2,7.0,6.2)*size),point))
		tree_leaves.append(Transform3D(turn.scaled(Vector3(5.5,3.6,5.1)*size),point+Vector3(0,4.8*size,0)))
		v._solid("VillageGardenTree",point+Vector3(0,2.34*size,0),Vector3(.5,4.68,.5)*size)
	_batch(v,"GardenBranches",preload("res://gameplay/urban_v1/FreightOutskirts.gd")._wood_mesh(),wood,tree_wood,true)
	_batch(v,"GardenCanopies",_foliage(),leaves,tree_leaves,true)
	var grass_batches := {}
	var bush_batches := {}
	var grass_points := []
	var noise := FastNoiseLite.new()
	noise.seed=2809
	noise.frequency=.13
	for attempt in 14000:
		var point := Vector2(rng.randf_range(-87,85),rng.randf_range(-40,39))
		if noise.get_noise_2d(point.x,point.y)<-.25 or not _open(v,point,.3): continue
		var cell := Vector2i(floori(point.x/32),floori(point.y/32))
		if not grass_batches.has(cell): grass_batches[cell]=[]
		var h := rng.randf_range(1.0,2.65)
		grass_batches[cell].append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3(1.4,h,1.4)),Vector3(point.x,.026,point.y)))
		grass_points.append(point)
		if grass_points.size()>=4200: break
	for attempt in 400:
		var point := Vector2(rng.randf_range(-86,84),rng.randf_range(-39,38))
		if not _open(v,point,1.0) or noise.get_noise_2d(point.x,point.y)<.02: continue
		var cell := Vector2i(floori(point.x/32),floori(point.y/32))
		if not bush_batches.has(cell): bush_batches[cell]=[]
		var size := rng.randf_range(.48,.95)
		bush_batches[cell].append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3(1.7,1.05,1.5)*size),Vector3(point.x,.58*size,point.y)))
	for cell in grass_batches:
		_batch(v,"WildGrass%s"%cell,preload("res://world/urban_detail/HarborGrassTufts.gd")._tuft_mesh(),_paint("758747"),grass_batches[cell],false)
	for cell in bush_batches:
		_batch(v,"GardenScrub%s"%cell,_foliage(),leaves,bush_batches[cell],false)
	v.set_meta("wild_grass_points",grass_points)

static func _open(v: Node3D,point: Vector2,margin: float) -> bool:
	for spot in preload("res://gameplay/urban_v1/TruckersVillageFleet.gd").SPOTS:
		var at: Vector3 = spot[1]
		if point.distance_to(Vector2(at.x,at.z))<4.0+margin: return false
	if Rect2(-50,-28,43,31).grow(margin).has_point(point): return false
	if Rect2(52.5,-10,17,15).grow(margin).has_point(point): return false
	for polygon in v.get_meta("earth_plots",[]):
		if Geometry2D.is_point_in_polygon(point,polygon): return false
		for i in polygon.size():
			if point.distance_to(Geometry2D.get_closest_point_to_segment(point,polygon[i],polygon[(i+1)%polygon.size()]))<margin: return false
	for i in FOOTPATH.size()-1:
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point,FOOTPATH[i],FOOTPATH[i+1]))<2.0+margin: return false
	for walk in WALKS:
		for i in walk.size():
			if point.distance_to(Geometry2D.get_closest_point_to_segment(point,walk[i],walk[(i+1)%walk.size()]))<.8+margin: return false
	for solid in v.placements:
		if solid.id=="VillageGardenTree": continue
		var local: Vector3 = solid.basis.inverse()*(Vector3(point.x,0,point.y)-solid.center)
		if absf(local.x)<solid.size.x*.5+margin and absf(local.z)<solid.size.z*.5+margin: return false
	return true

static func _paint(hex: String) -> StandardMaterial3D:
	var paint := StandardMaterial3D.new()
	paint.albedo_color=Color(hex)
	paint.vertex_color_use_as_albedo=true
	paint.roughness=1.0
	return paint

static func _batch(v: Node3D,label: String,mesh: Mesh,paint: Material,transforms: Array,shadows: bool) -> void:
	if transforms.is_empty(): return
	var multi := MultiMesh.new()
	multi.transform_format=MultiMesh.TRANSFORM_3D
	multi.mesh=mesh
	multi.instance_count=transforms.size()
	for i in transforms.size(): multi.set_instance_transform(i,transforms[i])
	var display := MultiMeshInstance3D.new()
	display.name=label.validate_node_name()
	display.multimesh=multi
	display.material_override=paint
	if label=="GardenCanopies": display.layers=INTERIOR_OCCLUDING_CANOPY_LAYER
	display.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Fine grass is not serialized into the map's static overview catalog.
	if shadows:
		display.set_meta("editor_transforms",transforms)
		display.set_meta("editor_colors",Array(transforms.map(func(_t): return paint.albedo_color)))
	v.add_child(display)

static func _foliage() -> ArrayMesh:
	if _crown != null: return _crown
	var source := SphereMesh.new()
	source.radius=1.0
	source.height=2.0
	source.radial_segments=10
	source.rings=4
	var arrays := source.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var clumps := [[Vector3(0,.22,0),Vector3(.55,.68,.53)],
		[Vector3(-.4,0,.13),Vector3(.48,.5,.44)],[Vector3(.39,-.07,.08),Vector3(.47,.55,.49)],
		[Vector3(.08,-.19,-.38),Vector3(.52,.45,.45)],[Vector3(-.08,-.14,.4),Vector3(.51,.43,.47)],
		[Vector3(-.28,.34,-.24),Vector3(.38,.47,.4)],[Vector3(.3,.32,.22),Vector3(.36,.48,.4)],
		[Vector3(.31,.13,-.33),Vector3(.44,.52,.38)]]
	for clump in clumps:
		for i in range(0,indices.size(),3):
			var a: Vector3 = clump[0]+vertices[indices[i]]*clump[1]
			var b: Vector3 = clump[0]+vertices[indices[i+1]]*clump[1]
			var c: Vector3 = clump[0]+vertices[indices[i+2]]*clump[1]
			var normal := (c-a).cross(b-a).normalized()
			# Whole-number grouping/index; preserve integer truncation and precision.
			@warning_ignore("integer_division")
			var shade := .79+float((i/3)%7)*.038
			for point in [a,b,c]:
				tool.set_normal(normal)
				tool.set_color(Color(shade,shade,shade*.94))
				tool.add_vertex(point)
	_crown=tool.commit()
	return _crown
