extends Node3D
## White 2014 double cab, black multi-spoke rims and black side steps from Digo's photo.
## Shared baked batches; wheel and headlight sides stay independent for animation/lights.
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
		if "@" in str(entry.name):
			var bits := str(entry.name).split("@")
			part.set_meta("wheel_center",Vector3(float(bits[1]),.405,float(bits[2])))
		add_child(part)
	_batches.clear()
	_materials.clear()
	set_meta("model_identity","Amarok 2014 Stage 2")
	set_meta("body_doors",4)
func _build() -> void:
	for row in [["paint","f0f1ef",.32,.25],["rubber","111518",.0,.93],["trim","20262a",.20,.50],["glass","172c34",.35,.17],["alloy","151a1e",.60,.27],["chrome","b8c0c3",.9,.19],["headlight","8298a9",.5,.14],["tail","a52a22",.18,.27],["plate","dce0df",.1,.5]]:
		var material := StandardMaterial3D.new()
		material.resource_name = row[0]
		material.albedo_color = Color(row[1])
		material.metallic = row[2]
		material.roughness = row[3]
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[row[0]] = material
	_box("rubber",Vector3(0,.43,0),Vector3(1.72,.17,4.92))
	_box("paint",Vector3(0,1.055,-.83),Vector3(1.70,.20,3.10))
	_bonnet()
	_quad("paint",Vector3(-.775,1.86,-.52),Vector3(.775,1.86,-.52),Vector3(.80,1.85,.96),Vector3(-.80,1.85,.96))
	_quad("paint",Vector3(-.775,1.86,-.52),Vector3(.775,1.86,-.52),Vector3(.731,1.808,-.507),Vector3(-.731,1.808,-.507))
	_quad("glass",Vector3(-.845,1.27,-1.015),Vector3(.845,1.27,-1.015),Vector3(.731,1.808,-.507),Vector3(-.731,1.808,-.507))
	_box("paint",Vector3(0,1.505,1.01),Vector3(1.70,.68,.07))
	_box("glass",Vector3(0,1.61,1.052),Vector3(1.40,.34,.012))
	_box("rubber",Vector3(0,1.19,1.73),Vector3(1.82,.055,1.47))
	_box("paint",Vector3(0,.95,2.51),Vector3(1.96,.55,.10))
	_box("rubber",Vector3(0,1.25,2.50),Vector3(1.91,.035,.13))
	_box("rubber",Vector3(0,.77,1.75),Vector3(1.74,.10,1.46))
	for side in [-1.0,1.0]:
		var x: float = side*.965
		for z in [-1.53,1.56]: _wheel(side,z)
		var zs: Array[float] = [-2.49,-2.28,-2.00,-1.95,-1.87,-1.74,-1.53,-1.32,-1.19,-1.11,-1.06,-.98,.98,1.08,1.14,1.22,1.36,1.56,1.76,1.90,1.98,2.04,2.49]
		for i in zs.size()-1:
			var za := zs[i]
			var zb := zs[i+1]
			var ya := _arch(za)
			var yb := _arch(zb)
			var xa: float = side*lerpf(.915,.965,clampf((za+2.49)/.21,0.0,1.0))
			var xb: float = side*lerpf(.915,.965,clampf((zb+2.49)/.21,0.0,1.0))
			_quad("paint",Vector3(xa,ya,za),Vector3(xb,yb,zb),Vector3(xb,lerpf(1.157,1.20,clampf((zb+2.49)/.21,0,1)),zb),Vector3(xa,lerpf(1.157,1.20,clampf((za+2.49)/.21,0,1)),za))
			if ya>.49 or yb>.49: _beam("paint",Vector3(x*1.022,ya+.025,za),Vector3(x*1.022,yb+.025,zb),.075)
		# White A/B/C pillars and black weather seals around four passenger windows.
		var a := Vector3(side*.914,1.245,-1.025)
		var b := Vector3(side*.777,1.82,-.508)
		var c := Vector3(side*.799,1.812,.12)
		var d := Vector3(side*.930,1.245,.12)
		var e := Vector3(side*.799,1.812,.22)
		var f := Vector3(side*.808,1.805,.885)
		var g := Vector3(side*.933,1.245,.905)
		var h := Vector3(side*.930,1.245,.22)
		_quad("glass",a,b,c,d)
		_quad("glass",e,f,g,h)
		_quad("paint",Vector3(x,1.20,-1.025),Vector3(x,1.20,.905),g,a)
		for line in [[a,b],[b,c],[c,d],[d,a],[e,f],[f,g],[g,h],[h,e]]: _beam("rubber",line[0],line[1],.022)
		_beam("paint",Vector3(side*.925,1.22,-1.07),Vector3(side*.772,1.833,-.54),.072)
		_beam("paint",Vector3(side*.80,1.824,.95),Vector3(side*.96,1.20,1.03),.09)
		_quad("paint",Vector3(side*.775,1.86,-.52),Vector3(side*.80,1.85,.96),Vector3(side*.808,1.805,.885),Vector3(side*.777,1.82,-.508))
		_quad("trim",c,e,h,d)
		_box("trim",Vector3(side*.971,.39,-.03),Vector3(.17,.09,2.32))
		_box("chrome",Vector3(side*.974,.415,-.03),Vector3(.11,.018,2.29))
		for z in [-1.03,.17,.99]: _beam("trim",Vector3(x+.006*side,.52,z),Vector3(x+.006*side,1.22,z),.008)
		for z in [-.05,.77]: _box("paint",Vector3(side*.985,1.17,z),Vector3(.040,.050,.18))
		_box("trim",Vector3(side*.967,1.30,-.68),Vector3(.12,.075,.09))
		_box("paint",Vector3(side*1.058,1.36,-.67),Vector3(.20,.17,.245))
		_box("glass",Vector3(side*1.058,1.36,-.543),Vector3(.16,.125,.01))
		_box("rubber",Vector3(side*.939,1.238,1.76),Vector3(.075,.038,1.49))
		_headlight(side)
		_box("tail",Vector3(side*.878,1.03,2.577),Vector3(.173,.364,.025))
	_front_bumper()
	_quad("rubber",Vector3(-.50,1.171,-2.534),Vector3(.50,1.171,-2.534),Vector3(.465,.934,-2.551),Vector3(-.465,.934,-2.551))
	for y in [1.002,1.117]: _box("chrome",Vector3(0,y,-2.558),Vector3(.976,.031,.025))
	for y in [.969,1.067]: _box("trim",Vector3(0,y,-2.553),Vector3(.944,.017,.012))
	_ring_z("chrome",Vector3(0,1.058,-2.575),.109,.090)
	for line in [[Vector2(-.059,.060),Vector2(0,-.009)],[Vector2(0,-.009),Vector2(.059,.060)],[Vector2(-.075,.002),Vector2(-.038,-.064)],[Vector2(-.038,-.064),Vector2(0,-.017)],[Vector2(0,-.017),Vector2(.038,-.064)],[Vector2(.038,-.064),Vector2(.075,.002)]]:
		_beam("chrome",Vector3(line[0].x,1.058+line[0].y,-2.583),Vector3(line[1].x,1.058+line[1].y,-2.583),.012)
	_box("plate",Vector3(0,.811,-2.603),Vector3(.46,.14,.02))
	_box("trim",Vector3(0,.551,2.531),Vector3(1.98,.14,.16))
	_box("plate",Vector3(0,.805,2.574),Vector3(.46,.14,.014))
	_box("trim",Vector3(0,1.151,2.577),Vector3(.26,.060,.021))
	_cylinder("chrome",Vector3(.77,.355,2.47),.057,.31,Vector3(PI*.5,0,0),20)
	_cylinder("rubber",Vector3(.77,.355,2.628),.046,.009,Vector3(PI*.5,0,0),20)

func _bonnet() -> void:
	# Crown, pressed shoulder lines and falling outer wings: no flat cuboid nose.
	var rings := [Vector4(-2.52,.900,1.192,1.157),Vector4(-2.28,.958,1.235,1.205),Vector4(-1.42,.944,1.295,1.225),Vector4(-1.065,.909,1.273,1.244)]
	var across := [-1.0,-.84,-.62,0.0,.62,.84,1.0]
	for i in rings.size()-1:
		for j in across.size()-1:
			_quad("paint",_hood_point(rings[i],across[j]),_hood_point(rings[i],across[j+1]),_hood_point(rings[i+1],across[j+1]),_hood_point(rings[i+1],across[j]))
	for side in [-1.0,1.0]:
		for i in rings.size()-1:
			var a := _hood_point(rings[i],side*.84)
			var b := _hood_point(rings[i+1],side*.84)
			_beam("paint",a+Vector3.UP*.002,b+Vector3.UP*.002,.009)
func _hood_point(ring: Vector4,ratio: float) -> Vector3:
	return Vector3(ring.y*ratio,lerpf(ring.z,ring.w,pow(absf(ratio),3.4)),ring.x+(pow(absf(ratio),4.0)*.07 if ring.x<-2.5 else 0.0))

func _headlight(side: float) -> void:
	# Outer end wraps back into the wing instead of sitting on a rectangular block.
	var key := "headlight#%s" % str(side)
	var a := Vector3(side*.515,1.139,-2.550)
	var b := Vector3(side*.902,1.148,-2.470)
	var c := Vector3(side*.923,.976,-2.461)
	var d := Vector3(side*.492,.955,-2.561)
	_quad(key,a,b,c,d)
	for line in [[a,b],[b,c],[c,d],[d,a]]: _beam("trim",line[0],line[1],.024)
	_beam("chrome",a+Vector3(0,-.018,-.008),b+Vector3(0,-.018,-.008),.010)
	for lens in [Vector3(side*.753,1.055,-2.517),Vector3(side*.563,1.048,-2.557)]:
		_cylinder("trim",lens,.081,.014,Vector3(PI*.5,0,0),20)
		_cylinder("chrome",lens+Vector3(0,0,-.008),.072,.014,Vector3(PI*.5,0,0),20)
		_cylinder(key,lens+Vector3(0,0,-.019),.050,.014,Vector3(PI*.5,0,0),20)
	for i in 6:
		var x: float = .535+i*.054
		_beam("chrome",Vector3(side*x,.979,-2.572+(x-.49)*.23),Vector3(side*x,.994,-2.572+(x-.49)*.23),.007)
	var fog := Vector3(side*.772,.654,_bumper_z(.772)-.012)
	_ring_z("chrome",fog,.064,.053)
	_cylinder(key,fog+Vector3(0,0,-.011),.048,.012,Vector3(PI*.5,0,0),20)

func _bumper_z(x: float) -> float:
	return -2.579+.205*pow(absf(x)/.99,5.0)
func _front_bumper() -> void:
	var widths := [-.99,-.93,-.85,-.72,-.59,-.46,0.0,.46,.59,.72,.85,.93,.99]
	for i in widths.size()-1:
		var xa: float = widths[i]
		var xb: float = widths[i+1]
		var za := _bumper_z(xa)
		var zb := _bumper_z(xb)
		# Crown belt above the intakes and a rolled lower lip share curved corners.
		for band in [Vector2(.773,.934),Vector2(.463,.539)]:
			var setback := .020 if band.x<.5 else 0.0
			_quad("paint",Vector3(xa,band.x,za+setback),Vector3(xb,band.x,zb+setback),Vector3(xb,band.y,zb),Vector3(xa,band.y,za))
			_quad("paint",Vector3(xa,band.y,za),Vector3(xb,band.y,zb),Vector3(xb,band.y,zb+.105),Vector3(xa,band.y,za+.105))
		# Recessed black inner face remains below the actual painted openings.
		_quad("rubber",Vector3(xa,.537,za+.020),Vector3(xb,.537,zb+.020),Vector3(xb,.774,zb+.020),Vector3(xa,.774,za+.020))
		if absf((xa+xb)*.5)>.89:
			_quad("paint",Vector3(xa,.526,za),Vector3(xb,.526,zb),Vector3(xb,.785,zb),Vector3(xa,.785,za))
	for side in [-1.0,1.0]:
		# Sculpted dividers slope into each round fog-lamp recess.
		var a := Vector3(side*.587,.775,_bumper_z(.587))
		var b := Vector3(side*.669,.775,_bumper_z(.669))
		var c := Vector3(side*.638,.532,_bumper_z(.638))
		var d := Vector3(side*.528,.532,_bumper_z(.528))
		_quad("paint",a,b,c,d)
		_beam("chrome",Vector3(side*.58,.546,_bumper_z(.58)-.006),Vector3(side*.855,.549,_bumper_z(.855)-.006),.014)
	for i in 4: _box("trim",Vector3(0,.565+i*.050,-2.576),Vector3(1.072,.009,.012))
func _arch(z: float) -> float:
	for center in [-1.53,1.56]:
		var offset := absf(z-center)
		if offset<.49: return .405+sqrt(maxf(0.0,.49*.49-offset*offset))
	return .49
func _wheel(side: float,z: float) -> void:
	var center := Vector3(side*.94,.405,z)
	var suffix := "@%s@%s" % [str(center.x),str(z)]
	_cylinder("rubber"+suffix,center,.397,.255,Vector3(0,0,PI*.5),32)
	_cylinder("alloy"+suffix,center+Vector3(side*.135,0,0),.280,.017,Vector3(0,0,PI*.5),32)
	_cylinder("trim"+suffix,center+Vector3(side*.145,0,0),.245,.010,Vector3(0,0,PI*.5),32)
	for i in 10:
		var a := TAU*i/10.0
		_box("alloy"+suffix,center+Vector3(side*.16,sin(a)*.17,cos(a)*.17),Vector3(.021,.036,.195),Vector3(-a,0,0))
	_cylinder("alloy"+suffix,center+Vector3(side*.173,0,0),.071,.025,Vector3(0,0,PI*.5),20)

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
	var axis := (b-a).normalized()
	_tool(key).append_from(mesh,0,Transform3D(Basis(Quaternion(Vector3.UP,axis)),(a+b)*.5))
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
func _ring_z(key: String,center: Vector3,outer: float,inner: float) -> void:
	for i in 32:
		var a := TAU*i/32.0
		var b := TAU*(i+1)/32.0
		_quad(key,center+Vector3(cos(a)*outer,sin(a)*outer,0),center+Vector3(cos(b)*outer,sin(b)*outer,0),center+Vector3(cos(b)*inner,sin(b)*inner,0),center+Vector3(cos(a)*inner,sin(a)*inner,0))
