extends Node3D
## Modern white GLI sedan: four doors, thin lamps, red grille stripe and alloys.
## Native triangles batch by finish; immutable meshes are cached once.
static var _cached: Array[Dictionary] = []
var _batches: Dictionary = {}
var _materials: Dictionary = {}

func _init() -> void:
	if _cached.is_empty():
		_build()
		for key: String in _batches:
			var material_key := key.get_slice("@",0).get_slice("#",0)
			_cached.append({"name":key,"mesh":_batches[key].commit(),"material":_materials[material_key],"key":material_key})
	for entry in _cached:
		var part := MeshInstance3D.new()
		part.name = entry.name
		part.mesh = entry.mesh
		part.material_override = entry.material
		part.set_meta("coupe_damage_material_key",entry.key)
		if "#fixed" in str(entry.name): part.set_meta("door_cut_exempt",true)
		if "@" in str(entry.name):
			var bits := str(entry.name).split("@")
			part.set_meta("wheel_center",Vector3(float(bits[1]),.33,float(bits[2])))
		add_child(part)
	_batches.clear()
	_materials.clear()
	set_meta("model_identity","Jetta GLI")
	set_meta("body_doors",4)
	set_meta("rim_inches",18)

func _build() -> void:
	for row in [["paint","f1f0ea",.48,.24],["rubber","131619",0.0,.92],["trim","20262a",.12,.46],
		["glass","263f4c",.3,.12],["smoked_lens","263f4c",.3,.12],["alloy","bfc4c8",.88,.19],["headlight","e6f1f3",.2,.16],
		["tail","b92827",.15,.28],["red","b61f2b",.12,.32]]:
		var material := StandardMaterial3D.new()
		material.resource_name = row[0]
		material.albedo_color = Color(row[1])
		material.metallic = row[2]
		material.roughness = row[3]
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[row[0]] = material
	# Passenger cabin is hollow: no belt-height slab crosses the seats.
	_box("rubber#fixed",Vector3(0,.22,0),Vector3(1.65,.12,4.28))
	_quad("paint#fixed",Vector3(-.86,.84,-2.20),Vector3(.86,.84,-2.20),Vector3(.91,.99,-.90),Vector3(-.91,.99,-.90))
	_quad("paint#fixed",Vector3(-.70,1.46,-.30),Vector3(.70,1.46,-.30),Vector3(.71,1.44,.79),Vector3(-.71,1.44,.79))
	_quad("paint#fixed",Vector3(-.88,.99,1.27),Vector3(.88,.99,1.27),Vector3(.87,.89,2.22),Vector3(-.87,.89,2.22))
	_quad("glass",Vector3(-.865,1.01,-.865),Vector3(.865,1.01,-.865),Vector3(.673,1.438,-.302),Vector3(-.673,1.438,-.302))
	_quad("glass",Vector3(-.681,1.416,.823),Vector3(.681,1.416,.823),Vector3(.836,1.012,1.254),Vector3(-.836,1.012,1.254))
	# Solid roof lips and pillars close the seams without overlapping glass.
	_quad("paint#fixed",Vector3(-.70,1.46,-.30),Vector3(.70,1.46,-.30),Vector3(.673,1.438,-.302),Vector3(-.673,1.438,-.302))
	_quad("paint#fixed",Vector3(-.71,1.44,.79),Vector3(.71,1.44,.79),Vector3(.681,1.416,.823),Vector3(-.681,1.416,.823))
	for side in [-1.0,1.0]:
		for z in [-1.38,1.40]: _wheel(side,z)
		var x: float = side*.91
		var samples: Array[float] = [-2.22,-1.79,-1.73,-1.61,-1.49,-1.38,-1.27,-1.15,-1.03,-.97,-.89,.91,1.00,1.12,1.24,1.40,1.56,1.68,1.80,2.22]
		for i in samples.size()-1:
			var za := samples[i]
			var zb := samples[i+1]
			var ya := _arch(za)
			var yb := _arch(zb)
			_quad("paint",Vector3(x,ya,za),Vector3(x,yb,zb),Vector3(x,.99,zb),Vector3(x,.99,za))
			if ya>.34 or yb>.34: _beam("paint",Vector3(x*1.012,ya+.01,za),Vector3(x*1.012,yb+.01,zb),.022)
		var front_a := Vector3(side*.887,1.010,-.827)
		var front_b := Vector3(side*.698,1.435,-.279)
		var front_c := Vector3(side*.704,1.428,.181)
		var front_d := Vector3(side*.908,1.010,.185)
		_quad("glass",front_a,front_b,front_c,front_d)
		var rear_a := Vector3(side*.908,1.010,.267)
		var rear_b := Vector3(side*.704,1.424,.269)
		var rear_c := Vector3(side*.713,1.408,.794)
		var rear_d := Vector3(side*.862,1.010,1.20)
		_quad("glass",rear_a,rear_b,rear_c,rear_d)
		for span in [[front_a,front_b],[front_b,front_c],[front_c,front_d],[front_d,front_a],
			[rear_a,rear_b],[rear_b,rear_c],[rear_c,rear_d],[rear_d,rear_a]]: _beam("rubber",span[0],span[1],.018)
		_beam("paint#fixed",Vector3(side*.91,.99,-.90),Vector3(side*.70,1.46,-.30),.055)
		_beam("paint#fixed",Vector3(side*.71,1.44,.79),Vector3(side*.88,.99,1.27),.060)
		_beam("trim#fixed",Vector3(side*.91,.99,.225),Vector3(side*.71,1.44,.225),.060)
		_beam("paint#fixed",Vector3(side*.70,1.46,-.30),Vector3(side*.71,1.44,.79),.026)
		_quad("paint#fixed",Vector3(side*.70,1.46,-.30),Vector3(side*.71,1.44,.79),rear_c,front_b)
		for z in [-.85,.22,1.16]: _beam("trim",Vector3(x+side*.003,.34,z),Vector3(x+side*.003,.984,z),.008)
		for z in [.05,.98]: _box("trim",Vector3(side*.93,.884,z),Vector3(.025,.030,.140))
		_box("trim#fixed",Vector3(side*.972,1.045,-.57),Vector3(.09,.026,.15))
		_box("paint#fixed",Vector3(side*1.027,1.075,-.56),Vector3(.156,.093,.192))
		_box("smoked_lens#fixed",Vector3(side*1.027,1.072,-.455),Vector3(.130,.072,.008))
		_box("trim",Vector3(side*.92,.315,.18),Vector3(.047,.047,1.91))
	# Wide grille, sharp headlamps and the red GLI line distinguish the sedan.
	_box("paint#fixed",Vector3(0,.66,-2.27),Vector3(1.83,.43,.13))
	_box("rubber#fixed",Vector3(0,.775,-2.343),Vector3(.97,.187,.025))
	for i in 4: _box("trim#fixed",Vector3(0,.710+i*.042,-2.36),Vector3(.96,.013,.015))
	_box("red#fixed",Vector3(0,.839,-2.372),Vector3(.97,.018,.010))
	_box("rubber#fixed",Vector3(0,.44,-2.345),Vector3(1.26,.16,.025))
	_box("alloy#fixed",Vector3(0,.436,-2.362),Vector3(.78,.09,.010))
	for side in [-1.0,1.0]:
		_box("trim#fixed",Vector3(side*.701,.804,-2.349),Vector3(.411,.151,.037))
		_box("headlight#fixed",Vector3(side*.701,.817,-2.370),Vector3(.379,.092,.027))
		_box("headlight#fixed",Vector3(side*.695,.774,-2.385),Vector3(.376,.020,.011))
		_box("rubber#fixed",Vector3(side*.743,.463,-2.347),Vector3(.198,.143,.030))
		_box("trim#fixed",Vector3(side*.693,.357,-2.355),Vector3(.315,.022,.024))
	_box("trim#fixed",Vector3(0,.327,-2.355),Vector3(1.82,.040,.100))
	# Rear diffuser, slim tail lamps and two polished exhaust outlets.
	_box("paint#fixed",Vector3(0,.660,2.275),Vector3(1.82,.430,.135))
	_box("trim#fixed",Vector3(0,.332,2.285),Vector3(1.77,.122,.100))
	_box("trim#fixed",Vector3(0,.529,2.350),Vector3(.452,.151,.017))
	for side in [-1.0,1.0]:
		_box("tail#fixed",Vector3(side*.665,.801,2.354),Vector3(.443,.116,.026))
		_box("tail#fixed",Vector3(side*.536,.824,2.373),Vector3(.643,.022,.012))
		_cylinder("alloy#fixed",Vector3(side*.625,.301,2.300),.052,.210,Vector3(PI*.5,0,0),16)
		_cylinder("rubber#fixed",Vector3(side*.625,.301,2.408),.042,.009,Vector3(PI*.5,0,0),16)
	_box("trim#fixed",Vector3(0,.901,2.20),Vector3(1.72,.026,.048))

func _arch(z: float) -> float:
	for center in [-1.38,1.40]:
		var offset := absf(z-center)
		if offset < .40: return .33+sqrt(maxf(0.0,.40*.40-offset*offset))
	return .33

func _wheel(side: float,z: float) -> void:
	var center := Vector3(side*.86,.33,z)
	var suffix := "@%s@%s" % [str(center.x),str(z)]
	_cylinder("rubber"+suffix,center,.327,.218,Vector3(0,0,PI*.5),24)
	_cylinder("alloy"+suffix,center+Vector3(side*.116,0,0),.229,.018,Vector3(0,0,PI*.5),24)
	_cylinder("trim"+suffix,center+Vector3(side*.129,0,0),.204,.010,Vector3(0,0,PI*.5),24)
	for i in 5:
		var angle := TAU*i/5.0
		_box("alloy"+suffix,center+Vector3(side*.142,sin(angle)*.123,cos(angle)*.123),Vector3(.020,.078,.190),Vector3(-angle,0,0))
	_cylinder("alloy"+suffix,center+Vector3(side*.148,0,0),.065,.017,Vector3(0,0,PI*.5),16)
	_box("red#fixed",center+Vector3(side*.104,0,.151),Vector3(.051,.115,.079))

func _tool(key: String) -> SurfaceTool:
	if not _batches.has(key):
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[key] = tool
	return _batches[key]

func _box(key: String,point: Vector3,size: Vector3,angles := Vector3.ZERO) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_tool(key).append_from(mesh,0,Transform3D(Basis.from_euler(angles),point))

func _cylinder(key: String,point: Vector3,radius: float,height: float,angles: Vector3,segments: int) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	_tool(key).append_from(mesh,0,Transform3D(Basis.from_euler(angles),point))

func _beam(key: String,a: Vector3,b: Vector3,width: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = width*.5
	mesh.bottom_radius = width*.5
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 6
	_tool(key).append_from(mesh,0,Transform3D(Basis(Quaternion(Vector3.UP,(b-a).normalized())),(a+b)*.5))

func _quad(key: String,a: Vector3,b: Vector3,c: Vector3,d: Vector3) -> void:
	var normal := (c-a).cross(b-a).normalized()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([a,b,c,d])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([normal,normal,normal,normal])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2,0,2,3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	_tool(key).append_from(mesh,0,Transform3D.IDENTITY)
