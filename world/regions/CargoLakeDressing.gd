extends Node3D
## Authored cargo camp, moored rowboat and crash fragments. Static geometry is
## merged by finish; physical bodies stay explicit and independent from art.
## Coordinates are local to the original secret lake. No heat/water policy here.
const PROP_SHADER := preload("res://world/regions/cargo_lake_props.gdshader")
const CAMP_Y := .08
const ISLAND_Y := .085
const CARGO_SIZE := Vector3(1.5, .8, 1.25)
static var _materials: Dictionary = {}
var _builders: Dictionary = {}
var solid_bodies: Array[StaticBody3D] = []
var prop_bounds: Array[Dictionary] = []
var _pose := Transform3D.IDENTITY

func _ready() -> void:
	name = "CargoLakeDressing"
	_cargo_crate(Vector3(7.5,CAMP_Y,13.75))
	_lashed_cargo(Vector3(8.4375,CAMP_Y,14.6875))
	_bench("SouthCampBench",Vector3(12.8,CAMP_Y,12.7),0.0)
	_bench("EastCampBench",Vector3(16,CAMP_Y,10.1),PI*.5)
	_boulder("WestCampBoulder",Vector3(6.8,CAMP_Y,8.0),Vector3(1.35,.78,1.0),.24)
	_boulder("SouthCampBoulder",Vector3(10.5,CAMP_Y,15.3),Vector3(1.15,.68,.90),-.31)
	_boulder("IslandBoulder",Vector3(18,ISLAND_Y,-3.5),Vector3(1.30,.92,1.10),.53)
	for entry in [["SouthSteppingRock",Vector2(45,105)/16.0,0],["MiddleSteppingRock",Vector2(58,75)/16.0,1],["NorthSteppingRock",Vector2(65,50)/16.0,2]]:
		_low_step(str(entry[0]),entry[1],int(entry[2]))
	_rowboat()
	_fragments()
	_finish_batches()
	set_process(false)
	add_to_group("cargo_lake_dressing")

func _tool(finish: String) -> SurfaceTool:
	if not _builders.has(finish):
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tool.set_smooth_group(-1)
		_builders[finish] = tool
	return _builders[finish]

static func _material(finish: String) -> Material:
	if _materials.has(finish): return _materials[finish]
	var material: Material
	if finish in ["wood","stone","cloth","snow","rope"]:
		var texture := ShaderMaterial.new()
		texture.shader = PROP_SHADER
		texture.set_shader_parameter("finish_kind", {"wood":0.0,"stone":1.0,"cloth":2.0,"snow":3.0,"rope":2.0}[finish])
		material = texture
	else:
		var opaque := StandardMaterial3D.new()
		opaque.vertex_color_use_as_albedo = true
		opaque.vertex_color_is_srgb = true
		opaque.roughness = .64 if finish == "metal" else .83
		opaque.metallic = .38 if finish == "metal" else .08
		material = opaque
	_materials[finish] = material
	return material

func _triangle(finish: String, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var tool := _tool(finish)
	tool.set_color(color)
	for point in [a,b,c]:
		tool.set_uv(Vector2(point.x+point.z*.17,point.y+point.z*.83))
		tool.add_vertex(_pose*point)

func _box(at: Vector3, size: Vector3, finish: String, color: Color, box_rotation := Vector3.ZERO) -> void:
	var corners: Array[Vector3] = []
	var box_basis := Basis.from_euler(box_rotation)
	for i in 8:
		var p := Vector3(size.x if i&1 else -size.x,size.y if i&2 else -size.y,size.z if i&4 else -size.z)*.5
		corners.append(at+box_basis*p)
	for face in [[0,1,3,2],[4,6,7,5],[0,4,5,1],[2,3,7,6],[0,2,6,4],[1,5,7,3]]:
		_triangle(finish,corners[face[0]],corners[face[1]],corners[face[2]],color)
		_triangle(finish,corners[face[0]],corners[face[2]],corners[face[3]],color)

func _rod(a: Vector3, b: Vector3, radius: float, finish: String, color: Color, sides := 7) -> void:
	var axis := (b-a).normalized()
	var helper := Vector3.FORWARD if absf(axis.dot(Vector3.UP))>.90 else Vector3.UP
	var across := axis.cross(helper).normalized()
	var along := axis.cross(across).normalized()
	for i in sides:
		var theta := float(i)*TAU/sides
		var next := float(i+1)*TAU/sides
		var p := (across*cos(theta)+along*sin(theta))*radius
		var q := (across*cos(next)+along*sin(next))*radius
		_triangle(finish,a+p,b+p,b+q,color)
		_triangle(finish,a+p,b+q,a+q,color)
		_triangle(finish,a,a+q,a+p,color)
		_triangle(finish,b,b+p,b+q,color)

func _prism(outline: PackedVector2Array, bottom: float, top: float, finish: String, color: Color) -> void:
	var triangles := Geometry2D.triangulate_polygon(outline)
	for i in range(0,triangles.size(),3):
		var a := outline[triangles[i]]
		var b := outline[triangles[i+1]]
		var c := outline[triangles[i+2]]
		_triangle(finish,Vector3(a.x,top,a.y),Vector3(b.x,top,b.y),Vector3(c.x,top,c.y),color)
		_triangle(finish,Vector3(a.x,bottom,a.y),Vector3(c.x,bottom,c.y),Vector3(b.x,bottom,b.y),color)
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i+1)%outline.size()]
		_triangle(finish,Vector3(a.x,bottom,a.y),Vector3(b.x,bottom,b.y),Vector3(b.x,top,b.y),color.darkened(.08))
		_triangle(finish,Vector3(a.x,bottom,a.y),Vector3(b.x,top,b.y),Vector3(a.x,top,a.y),color.darkened(.08))

func _solid_box(id: String, at: Vector3, size: Vector3, yaw := 0.0) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	_solid(id,at,shape,yaw,size)

func _solid(id: String, at: Vector3, shape: Shape3D, yaw: float, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = id
	body.position = at
	body.rotation.y = yaw
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("cargo_lake_prop",id)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	solid_bodies.append(body)
	prop_bounds.append({"id":id,"center":at,"size":size,"yaw":yaw})

func _cargo_crate(at: Vector3) -> void:
	_pose = Transform3D(Basis.IDENTITY,at)
	for x in [-.60,0.0,.60]: _box(Vector3(x,.045,0),Vector3(.14,.09,1.25),"wood",Color("564630"))
	for i in 7:
		var x := -.64+i*.214
		_box(Vector3(x,.12,0),Vector3(.195,.06,1.25),"wood",Color("897052").darkened(.035*(i%3)))
	for i in 5:
		var y := .205+i*.095
		var color := Color("8a7456").darkened(.045*(i%3))
		for z in [-.59,.59]: _box(Vector3(0,y,z),Vector3(1.39,.078,.055),"wood",color)
		for x in [-.70,.70]: _box(Vector3(x,y,0),Vector3(.055,.078,1.12),"wood",color.darkened(.04))
	for x in [-.62,.62]:
		for z in [-.615,.615]: _box(Vector3(x,.40,z),Vector3(.095,.51,.035),"metal",Color("575d59"))
	for i in 6:
		_box(Vector3(-.585+i*.234,.681,0),Vector3(.215,.055,1.20),"wood",Color("9a805d").darkened(.025*(i%2)))
	for x in [-.44,.44]:
		_box(Vector3(x,.706,0),Vector3(.055,.014,1.23),"metal",Color("767c73"))
		for z in [-.62,.62]:
			_box(Vector3(x,.427,z),Vector3(.055,.55,.015),"metal",Color("6a736e"))
			for y in [.21,.57]: _box(Vector3(x,y,z*1.008),Vector3(.024,.024,.012),"metal",Color("a2aaa4"))
	# Snow clings to the lid and reinforced corners, rather than a white box cap.
	_prism(PackedVector2Array([Vector2(-.68,-.57),Vector2(-.12,-.58),Vector2(.04,-.28),Vector2(-.20,.12),Vector2(-.62,.33)]),.704,.719,"snow",Color("dce7e9"))
	_solid_box("OriginalCargoCrateA",Vector3(at.x,.4,at.z),CARGO_SIZE)

func _lashed_cargo(at: Vector3) -> void:
	_pose = Transform3D(Basis.IDENTITY,at)
	# Legacy cargo footprints overlap at this corner. This L-shaped load joins
	# the first crate without intersecting duplicate coplanar pallet/lid boards.
	var rim := PackedVector2Array([Vector2(-.1875,-.625),Vector2(.75,-.625),Vector2(.75,.625),Vector2(-.75,.625),Vector2(-.75,-.3125),Vector2(-.1875,-.3125)])
	_prism(rim,.025,.14,"wood",Color("796449"))
	_prism(rim,.14,.655,"cloth",Color("526452"))
	for x in [-.56,-.16,.27,.62]:
		var z_start := -.30 if x<-.1875 else -.60
		_box(Vector3(x,.672,(z_start+.60)*.5),Vector3(.05,.025,.60-z_start),"rope",Color("b0a17d"))
		_box(Vector3(x,.40,.63),Vector3(.05,.52,.018),"rope",Color("90876d"))
	for z in [-.58,.58]:
		var x_start := -.17 if z<-.3125 else -.71
		_box(Vector3((x_start+.71)*.5,.667,z),Vector3(.71-x_start,.022,.052),"rope",Color("9c9277"))
	for y in [.26,.46,.59]:
		_box(Vector3(.10,y,.635),Vector3(1.10,.025,.013),"cloth",Color("394c42"))
	_box(Vector3(.16,.45,.653),Vector3(.43,.37,.018),"paint",Color("334b40"))
	_cobra_seal(Vector3(.16,.47,.669))
	_prism(PackedVector2Array([Vector2(-.55,.08),Vector2(-.08,-.03),Vector2(.52,.03),Vector2(.65,.33),Vector2(.39,.51),Vector2(-.61,.46)]),.668,.704,"snow",Color("d7e2e5"))
	_solid_box("OriginalCargoCrateB",Vector3(at.x,.4,at.z),CARGO_SIZE)

func _cobra_seal(at: Vector3) -> void:
	var trace := [Vector2(-.06,-.11),Vector2(.06,-.08),Vector2(.075,-.015),Vector2(-.04,.015),Vector2(-.02,.065),Vector2(.01,.10)]
	for i in range(trace.size()-1):
		_rod(at+Vector3(trace[i].x,trace[i].y,0),at+Vector3(trace[i+1].x,trace[i+1].y,0),.014,"paint",Color("c4b88b"),6)
	for side in [-1.0,1.0]:
		_rod(at+Vector3(.01,.10,0),at+Vector3(side*.065,.135,0),.018,"paint",Color("c4b88b"),6)
		_rod(at+Vector3(side*.065,.135,0),at+Vector3(side*.045,.185,0),.019,"paint",Color("c4b88b"),6)

func _bench(id: String, at: Vector3, yaw: float) -> void:
	_pose = Transform3D(Basis(Vector3.UP,yaw),at)
	for x in [-.68,.68]:
		for z in [-.15,.15]: _box(Vector3(x,.205,z),Vector3(.095,.41,.095),"wood",Color("514834"))
		_box(Vector3(x,.16,0),Vector3(.15,.10,.50),"wood",Color("6a5a42"))
	for z in [-.17,0.0,.17]:
		_box(Vector3(0,.445,z),Vector3(1.80,.075,.145),"wood",Color("927b59").darkened(.06 if z==0 else 0.0))
	_box(Vector3(0,.20,0),Vector3(1.48,.10,.095),"wood",Color("62533c"))
	for x in [-.68,.68]:
		for z in [-.17,.17]: _box(Vector3(x,.485,z),Vector3(.025,.008,.025),"metal",Color("777e74"))
	_prism(PackedVector2Array([Vector2(-.86,-.23),Vector2(-.23,-.24),Vector2(-.10,-.06),Vector2(-.36,.06),Vector2(-.76,.05)]),.484,.502,"snow",Color("d8e4e6"))
	_solid_box(id,at+Vector3.UP*.251,Vector3(1.80,.502,.49),yaw)

func _boulder(id: String, at: Vector3, size: Vector3, yaw: float) -> void:
	_pose = Transform3D(Basis(Vector3.UP,yaw),at)
	var points := PackedVector3Array()
	var rings: Array[PackedVector3Array] = []
	for level in 3:
		var ring := PackedVector3Array()
		for i in 8:
			var angle := TAU*float(i)/8.0
			var radius: float = [.88,1.0,.57][level]
			var variation := .90+.08*sin(float(i*7+level*13))
			var p := Vector3(cos(angle)*radius*variation*.5,[.005,.38,.90][level],sin(angle)*radius*.5)*size
			ring.append(p)
			points.append(p)
		rings.append(ring)
	for level in 2:
		for i in 8:
			var next := (i+1)%8
			var color := Color("778385").darkened(.025*float(i%4))
			_triangle("stone",rings[level][i],rings[level+1][next],rings[level+1][i],color)
			_triangle("stone",rings[level][i],rings[level][next],rings[level+1][next],color)
	var crown := Vector3(-.035,1.0,.02)*size
	points.append(crown)
	for i in 8:
		var next := (i+1)%8
		_triangle("stone",rings[2][i],rings[2][next],crown,Color("8b9695"))
		# The snowy crown follows the rock facets; no separate floating slab.
		if i not in [1,2,3]:
			_triangle("snow",rings[2][i]+Vector3.UP*.006,rings[2][next]+Vector3.UP*.006,crown+Vector3.UP*.012,Color("dce7e9"))
	var convex := ConvexPolygonShape3D.new()
	convex.points = points
	_solid(id,at,convex,yaw,size)

func _rowboat() -> void:
	var at := Vector3(10.2,.018,-1.25)
	_pose = Transform3D(Basis.IDENTITY,at)
	var rim := PackedVector2Array([Vector2(-1.17,-.34),Vector2(-.68,-.52),Vector2(.53,-.50),Vector2(1.0,-.30),Vector2(1.18,0),Vector2(1.0,.30),Vector2(.53,.50),Vector2(-.68,.52),Vector2(-1.17,.34)])
	var hull_points := PackedVector3Array()
	for i in rim.size():
		var next := (i+1)%rim.size()
		var a := rim[i]
		var b := rim[next]
		var low_a := Vector3(a.x*.88,.02,a.y*.58)
		var low_b := Vector3(b.x*.88,.02,b.y*.58)
		var high_a := Vector3(a.x,.40,a.y)
		var high_b := Vector3(b.x,.40,b.y)
		_triangle("paint",low_a,high_b,high_a,Color("456267"))
		_triangle("paint",low_a,low_b,high_b,Color("526b6b"))
		_triangle("wood",low_a+Vector3.UP*.065,high_a-Vector3(high_a.x*.025,0,high_a.z*.06),high_b-Vector3(high_b.x*.025,0,high_b.z*.06),Color("8a7356"))
		_triangle("wood",low_a+Vector3.UP*.065,high_b-Vector3(high_b.x*.025,0,high_b.z*.06),low_b+Vector3.UP*.065,Color("827159"))
		_rod(high_a,high_b,.025,"wood",Color("b19a72"),7)
		hull_points.append_array(PackedVector3Array([low_a,high_a]))
	for z in [-.28,-.14,0.0,.14,.28]: _box(Vector3(0,.095,z),Vector3(1.85,.04,.125),"wood",Color("746249"))
	for x in [-.55,.43]: _box(Vector3(x,.325,0),Vector3(.19,.065,.85),"wood",Color("9e835b"))
	_rod(Vector3(-.91,.29,.29),Vector3(.72,.38,.21),.018,"wood",Color("bea67e"),7)
	_box(Vector3(.73,.38,.21),Vector3(.34,.025,.12),"wood",Color("ae9268"),Vector3(0,.11,0))
	_coil(Vector3(-.78,.132,-.03),.12)
	var hull := ConvexPolygonShape3D.new()
	hull.points = hull_points
	_solid("MooredRowboat",at,hull,0.0,Vector3(2.36,.40,1.04))
	# Short rough mooring platform ends before the original wing obstruction.
	_pose = Transform3D.IDENTITY
	for i in 10:
		_box(Vector3(11.48+i*.19,.100,-1.30),Vector3(.175,.070,.62),"wood",Color("867250").darkened(.04*(i%2)))
	for z in [-1.54,-1.06]: _box(Vector3(12.25,.045,z),Vector3(1.90,.060,.075),"wood",Color("5c503c"))
	_solid_box("MooringPlatform",Vector3(12.335,.0675,-1.30),Vector3(1.885,.135,.62))
	_rod(Vector3(11.38,.40,-1.25),Vector3(13.12,.15,-1.12),.015,"rope",Color("a49a7c"),6)

func _low_step(id: String, point: Vector2, variant: int) -> void:
	_pose = Transform3D(Basis.IDENTITY,Vector3(point.x,0,point.y))
	# Rounded corners stay strictly inside the original dry quadrilateral.
	var footprint := PackedVector2Array([Vector2(-.75,-.5625),Vector2(.6875,-.625),Vector2(.8125,.5625),Vector2(-.625,.625)])
	var rim := PackedVector2Array()
	var trims: Array = [[.23,.30,.36,.26],[.34,.24,.27,.33],[.30,.35,.22,.29]][variant]
	for i in footprint.size():
		var previous := footprint[(i+footprint.size()-1)%footprint.size()]
		var at := footprint[i]
		var next := footprint[(i+1)%footprint.size()]
		rim.append(previous.lerp(at,1.0-float(trims[i])))
		rim.append(at.lerp(next,float(trims[i])))
	var points := PackedVector3Array()
	var crown_offset: Vector2 = [Vector2(.04,-.02),Vector2(-.06,.055),Vector2(.08,.04)][variant]
	var crown := Vector3(crown_offset.x,.12,crown_offset.y)
	var crown_scale: float = [.72,.81,.68][variant]
	var edge_height: float = [.095,.105,.091][variant]
	points.append(crown)
	for i in rim.size():
		var next := (i+1)%rim.size()
		var a := Vector3(rim[i].x,.030,rim[i].y)
		var b := Vector3(rim[next].x,.030,rim[next].y)
		var inner_a := Vector3(rim[i].x*crown_scale+crown_offset.x,edge_height,rim[i].y*crown_scale+crown_offset.y)
		var inner_b := Vector3(rim[next].x*crown_scale+crown_offset.x,edge_height,rim[next].y*crown_scale+crown_offset.y)
		_triangle("stone",Vector3(a.x,0,a.z),Vector3(b.x,0,b.z),b,Color("576e73"))
		_triangle("stone",Vector3(a.x,0,a.z),b,a,Color("61777a"))
		_triangle("stone",a,b,inner_b,Color("859593"))
		_triangle("stone",a,inner_b,inner_a,Color("81918f"))
		_triangle("stone",inner_a,inner_b,crown,Color("9aa6a2"))
		points.append_array(PackedVector3Array([Vector3(a.x,0,a.z),a,inner_a]))
	var convex := ConvexPolygonShape3D.new()
	convex.points = points
	_solid(id,Vector3(point.x,0,point.y),convex,0.0,Vector3(1.5625,.12,1.25))

func _coil(at: Vector3, radius: float) -> void:
	for i in 22:
		var angle := TAU*float(i)/11.0
		var next := TAU*float(i+1)/11.0
		var r := radius*(.55+.45*float(i)/22.0)
		var nr := radius*(.55+.45*float(i+1)/22.0)
		_rod(at+Vector3(cos(angle)*r,.012*float(i)/22.0,sin(angle)*r),at+Vector3(cos(next)*nr,.012*float(i+1)/22.0,sin(next)*nr),.009,"rope",Color("ad9d79"),5)

func _fragments() -> void:
	for entry in [[Vector3(-2.9,.022,7.0),-.32],[Vector3(-3.6,.018,8.6),.55],[Vector3(2.9,.019,8.7),-.81],[Vector3(4.0,.020,6.2),.28]]:
		_pose = Transform3D(Basis(Vector3.UP,float(entry[1])),entry[0])
		var rim := PackedVector2Array([Vector2(-.43,-.34),Vector2(.29,-.26),Vector2(.39,.11),Vector2(.14,.31),Vector2(-.37,.25)])
		_prism(rim,-.012,.035,"metal",Color("7d8b8c"))
		for x in [-.25,0.0,.24]:
			_box(Vector3(x,.049,-.01),Vector3(.018,.027,.44),"metal",Color("a1aaa7"))
		_box(Vector3(-.11,.038,.01),Vector3(.29,.015,.36),"paint",Color("354b51"))
		_prism(PackedVector2Array([Vector2(-.32,-.25),Vector2(-.10,-.21),Vector2(-.08,-.05),Vector2(-.28,.05)]),.040,.052,"snow",Color("d8e2e3"))
	_pose = Transform3D.IDENTITY
	# Ragged metal folds and broken cargo slats, grouped beside the open ramp.
	for entry in [[Vector3(-3.35,.043,6.4),Vector3(.12,.045,.70),.70],[Vector3(3.5,.038,8.0),Vector3(.16,.04,.48),-.32]]:
		_box(entry[0],entry[1],"wood",Color("7f7156"),Vector3(0,entry[2],0))

func _finish_batches() -> void:
	for finish in _builders:
		var tool: SurfaceTool = _builders[finish]
		tool.generate_normals()
		var visual := MeshInstance3D.new()
		visual.name = "CargoLake_"+str(finish)
		visual.mesh = tool.commit()
		visual.material_override = _material(finish)
		visual.set_meta("cargo_lake_static_batch",finish)
		add_child(visual)
	set_meta("cargo_lake_batch_count",_builders.size())
	_builders.clear()
