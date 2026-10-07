extends RefCounted
## Parked seven-axle road trains. Shared baked meshes, no per-frame detail nodes.
const G := preload("res://world/desert/DesertGeometry.gd")
const BATCH := preload("res://world/desert/DesertTownMaterials.gd")
static var _finishes: Dictionary = {}
static var _models: Dictionary = {}
const AXLES := [-11.15, -7.75, -6.45, .35, 1.65, 10.65, 11.95]

static func build(paint: Color) -> Node3D:
	var root := Node3D.new()
	root.name="ParkedBitrem"
	root.set_meta("vehicle_kind","bitrem")
	root.set_meta("trailer_count",2)
	root.set_meta("axle_count",7)
	var key := paint.to_html()
	if not _models.has(key):
		var art := Node3D.new()
		var variant := 0 if paint.r>.55 and paint.g<.4 else (2 if paint.r>.7 else (1 if paint.b>.45 else 3))
		_tractor(art,paint)
		for i in 2: _trailer(art,-2.3+float(i)*10.5,variant,i)
		for axle in AXLES:
			_pipe(art,Vector3(-1.02,.57,axle),Vector3(1.02,.57,axle),.10,"chassis")
			for side in [-1.0,1.0]:
				_wheel(art,Vector3(side*1.13,.57,axle),side)
				if axle!=AXLES[0]:
					var inner := Vector3(side*.77,.57,axle)
					_tire(art,inner)
					_pipe(art,inner-Vector3(.16,0,0),inner+Vector3(.16,0,0),.34,"recess")
		BATCH.batch_visuals(art)
		var meshes: Array[Dictionary]=[]
		for part: MeshInstance3D in art.get_children():
			meshes.append({"mesh":part.mesh,"material":part.material_override,"transform":part.transform})
		_models[key]=meshes
		art.free()
	for part: Dictionary in _models[key]:
		var mesh := MeshInstance3D.new()
		mesh.mesh=part.mesh
		mesh.material_override=part.material
		mesh.transform=part.transform
		root.add_child(mesh)
	# Coarse solid envelopes are independent of the baked visual mesh and never discarded by batching.
	_solid(root,"CabSolid",Vector3(0,1.94,-10.73),Vector3(2.46,3.22,3.42))
	_solid(root,"TractorSolid",Vector3(0,.77,-7.55),Vector3(2.46,1.28,3.1))
	for z in [-2.3,8.2]: _solid(root,"TrailerSolid",Vector3(0,2.04,z),Vector3(2.58,3.05,9.48))
	return root

static func _material(kind: String, tint := Color.WHITE) -> StandardMaterial3D:
	var key := kind+tint.to_html()
	if _finishes.has(key): return _finishes[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color={"chassis":Color("272d2e"),"rubber":Color("242628"),"tread":Color("343637"),"alloy":Color("a8adb0"),"recess":Color("3b454a"),"glass":Color("24414c"),"seal":Color("151f24"),"ivory":Color("d5d3c6"),"red":Color("9a302b"),"amber":Color("cd8b33"),"lens":Color("c7d6db"),"canvas":tint,"paint":tint}.get(kind,tint)
	mat.roughness={"paint":.4,"alloy":.36,"glass":.2,"canvas":.97}.get(kind,.8)
	mat.metallic=.65 if kind=="alloy" else (.2 if kind=="paint" else 0.0)
	_finishes[key]=mat
	return mat

static func _box(root: Node3D, at: Vector3, size: Vector3, kind: String, tint := Color.WHITE) -> MeshInstance3D:
	var node := G.box(root,"TruckDetail",at,size,Color.WHITE)
	node.material_override=_material(kind,tint)
	return node

static func _pipe(root: Node3D, a: Vector3, b: Vector3, radius: float, kind: String) -> void:
	var node := G.cylinder(root,"TruckTube",(a+b)*.5,radius,a.distance_to(b),Color.WHITE)
	(node.mesh as CylinderMesh).radial_segments=24 if radius>=.2 else 12
	node.basis=Basis(Quaternion(Vector3.UP,(b-a).normalized()))
	node.material_override=_material(kind)

static func _surface(root: Node3D, faces: Array, kind: String, tint := Color.WHITE) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face: PackedVector3Array in faces:
		# Author faces with outward right-hand normals; reverse indices for Godot winding.
		var normal := (face[1]-face[0]).cross(face[2]-face[0]).normalized()
		for i in [0,2,1,0,3,2]:
			st.set_normal(normal)
			st.set_uv(Vector2(face[i].x+face[i].z,face[i].y))
			st.add_vertex(face[i])
	var node := MeshInstance3D.new()
	node.mesh=st.commit()
	node.material_override=_material(kind,tint)
	root.add_child(node)

static func _ring(width: float, front: float, back: float, y: float) -> PackedVector3Array:
	var bevel := .18
	return PackedVector3Array([Vector3(-width+bevel,y,front),Vector3(width-bevel,y,front),Vector3(width,y,front+bevel),Vector3(width,y,back-bevel),Vector3(width-bevel,y,back),Vector3(-width+bevel,y,back),Vector3(-width,y,back-bevel),Vector3(-width,y,front+bevel)])

static func _tractor(root: Node3D, paint: Color) -> void:
	var rings := [_ring(1.22,-12.48,-9.05,1.14),_ring(1.24,-12.48,-9.05,2.25),_ring(1.20,-12.24,-9.12,3.28),_ring(1.10,-12.02,-9.28,3.64)]
	var faces: Array=[]
	for level in 3:
		for i in 8:
			var j := (i+1)%8
			faces.append(PackedVector3Array([rings[level][i],rings[level+1][i],rings[level+1][j],rings[level][j]]))
	# The chamfered top closes the silhouette without a floating sleeper box.
	for i in range(1,7): faces.append(PackedVector3Array([rings[3][0],rings[3][i+1],rings[3][i],rings[3][0]]))
	_surface(root,faces,"paint",paint)
	_box(root,Vector3(0,3.65,-10.5),Vector3(1.25,.065,1.05),"paint",paint.darkened(.16))
	_box(root,Vector3(0,3.695,-10.5),Vector3(.72,.03,.55),"recess")
	# Raked glazing is laid over the actual sloping cab face, with a visible rubber perimeter.
	for layer in 2:
		var w := 1.06 if layer==0 else .98
		var low := 2.32 if layer==0 else 2.40
		var high := 3.25 if layer==0 else 3.17
		var low_z := -12.49+(low-2.25)*.233-float(layer)*.013
		var high_z := -12.49+(high-2.25)*.233-float(layer)*.013
		_surface(root,[PackedVector3Array([Vector3(-w,low,low_z),Vector3(-w,high,high_z),Vector3(w,high,high_z),Vector3(w,low,low_z)])],"seal" if layer==0 else "glass")
	_box(root,Vector3(0,3.28,-12.33),Vector3(2.22,.095,.34),"paint",paint.darkened(.18))
	for x in [-.53,.53]:
		_pipe(root,Vector3(x-.3,2.4,-12.50),Vector3(x+.24,2.49,-12.48),.022,"seal")
		_pipe(root,Vector3(x-.30,2.4,-12.50),Vector3(x-.15,2.32,-12.50),.023,"seal")
	_box(root,Vector3(0,1.68,-12.515),Vector3(1.78,.88,.08),"seal")
	for i in 6: _box(root,Vector3(0,1.30+float(i)*.135,-12.57),Vector3(1.65,.035,.035),"recess")
	_box(root,Vector3(0,2.12,-12.54),Vector3(.32,.13,.035),"alloy")
	_box(root,Vector3(0,.92,-12.48),Vector3(2.46,.36,.29),"paint",paint.darkened(.23))
	_box(root,Vector3(0,.69,-12.54),Vector3(2.38,.1,.22),"chassis")
	_box(root,Vector3(0,.88,-12.64),Vector3(.42,.13,.025),"ivory")
	for side in [-1.0,1.0]:
		_box(root,Vector3(side*.94,1.07,-12.65),Vector3(.49,.25,.055),"seal")
		for x in [.81,1.04]: _box(root,Vector3(side*x,1.08,-12.685),Vector3(.18,.16,.022),"lens")
		_box(root,Vector3(side*1.18,1.12,-12.62),Vector3(.10,.16,.04),"amber")
		# Door glazing with an angled A pillar, door seam, recessed handle and low stripe.
		var x: float = side*1.244
		var window := PackedVector3Array([Vector3(x,2.35,-12.13),Vector3(side*1.21,3.17,-11.96),Vector3(side*1.21,3.17,-10.44),Vector3(x,2.35,-10.44)])
		if side<0: window.reverse()
		_surface(root,[window],"seal")
		var glass := PackedVector3Array([Vector3(x+side*.012,2.44,-12.01),Vector3(side*1.223,3.09,-11.87),Vector3(side*1.223,3.09,-10.53),Vector3(x+side*.012,2.44,-10.53)])
		if side<0: glass.reverse()
		_surface(root,[glass],"glass")
		_box(root,Vector3(side*1.255,1.8,-10.37),Vector3(.022,1.08,.026),"recess")
		_box(root,Vector3(side*1.26,2.13,-10.63),Vector3(.04,.12,.30),"seal")
		_box(root,Vector3(side*1.287,2.15,-10.63),Vector3(.025,.035,.22),"alloy")
		_box(root,Vector3(side*1.251,1.49,-10.63),Vector3(.028,.12,1.2),"ivory")
		_box(root,Vector3(side*1.235,2.66,-9.64),Vector3(.045,.63,.65),"seal")
		_box(root,Vector3(side*1.262,2.67,-9.64),Vector3(.02,.50,.52),"glass")
		for i in 4: _box(root,Vector3(side*1.253,1.81+float(i)*.1,-9.62),Vector3(.025,.028,.48),"recess")
		for y in [.56,.86,1.16]:
			_box(root,Vector3(side*1.20,y,-10.02),Vector3(.37,.10,.72),"chassis")
			_box(root,Vector3(side*1.25,y+.056,-10.02),Vector3(.32,.025,.61),"alloy")
		_pipe(root,Vector3(side*1.14,2.84,-12.09),Vector3(side*1.57,2.84,-12.15),.035,"chassis")
		_pipe(root,Vector3(side*1.17,2.35,-12.1),Vector3(side*1.57,2.40,-12.15),.03,"chassis")
		_box(root,Vector3(side*1.59,2.60,-12.15),Vector3(.19,.59,.25),"seal")
		_box(root,Vector3(side*1.59,2.60,-12.01),Vector3(.15,.48,.02),"alloy")
		_pipe(root,Vector3(side*.95,.89,-9.0),Vector3(side*.95,.89,-8.30),.34,"alloy")
		for z in [-8.87,-8.43]: _box(root,Vector3(side*1.275,.87,z),Vector3(.045,.54,.075),"chassis")
		_box(root,Vector3(side*.60,.9,-7.55),Vector3(.17,.32,3.45),"chassis")
		_box(root,Vector3(side*1.09,1.21,-7.13),Vector3(.67,.10,2.60),"chassis")
		_box(root,Vector3(side*1.12,.55,-5.85),Vector3(.63,.84,.065),"rubber")
		var arch_faces: Array=[]
		for i in 12:
			var a := float(i)*PI/12.0
			var b := float(i+1)*PI/12.0
			var face := PackedVector3Array([Vector3(side*1.34,.57+sin(a)*.64,-11.15+cos(a)*.64),Vector3(side*1.34,.57+sin(a)*.76,-11.15+cos(a)*.76),Vector3(side*1.34,.57+sin(b)*.76,-11.15+cos(b)*.76),Vector3(side*1.34,.57+sin(b)*.64,-11.15+cos(b)*.64)])
			if side>0: face.reverse()
			arch_faces.append(face)
		_surface(root,arch_faces,"paint",paint.darkened(.25))
	_box(root,Vector3(0,1.09,-8.58),Vector3(1.57,.05,.65),"alloy")
	_pipe(root,Vector3(0,1.18,-7.01),Vector3(0,1.30,-7.01),.63,"chassis")
	for x in [-.2,.2]:
		for i in 10:
			var a := Vector3(x+sin(float(i)*1.8)*.10,1.4+float(i)*.08,-8.92+float(i)*.12)
			var b := Vector3(x+sin(float(i+1)*1.8)*.10,1.4+float(i+1)*.08,-8.92+float(i+1)*.12)
			_pipe(root,a,b,.025,"red" if x<0 else "chassis")

static func _trailer(root: Node3D, z: float, variant: int, index: int) -> void:
	var body := [Color("aaaba2"),Color("c2c5bd"),Color("c5b58c"),Color("889b9e")][variant] as Color
	var tarp := [Color("3d4945"),Color("697478"),Color("715b43"),Color("3c5364")][variant] as Color
	var is_box := variant==1
	var bottom := 1.28
	var top := 3.77 if is_box else 3.13
	_box(root,Vector3(0,1.16,z),Vector3(2.58,.18,9.52),"chassis")
	_box(root,Vector3(0,(top+bottom)*.5,z),Vector3(2.53,top-bottom,9.42),"paint",body)
	if is_box:
		for x in [-1.15,-.58,0.0,.58,1.15]: _box(root,Vector3(x,top+.015,z),Vector3(.035,.03,9.39),"paint",body.darkened(.08))
	for side in [-1.0,1.0]:
		_box(root,Vector3(side*.77,.96,z),Vector3(.17,.30,9.6),"chassis")
		for height in [bottom+.09,top-.02]: _box(root,Vector3(side*1.29,height,z),Vector3(.07,.095,9.5),"alloy")
		var ribs := 31 if is_box else 10
		for rib in ribs:
			var at := z-4.5+float(rib)*9.0/float(ribs-1)
			_box(root,Vector3(side*1.288,(top+bottom)*.5,at),Vector3(.055,top-bottom-.16,.04 if is_box else .085),"paint",body.lightened(.1))
		if not is_box:
			for y in [1.87,2.47]: _box(root,Vector3(side*1.29,y,z),Vector3(.045,.046,9.38),"paint",body.darkened(.18))
		for i in 10:
			var at := z-4.25+float(i)*.94
			_box(root,Vector3(side*1.335,1.28,at),Vector3(.025,.075,.25),"red" if i%2==0 else "ivory")
			if not is_box:
				_pipe(root,Vector3(side*1.32,2.95,at),Vector3(side*1.35,2.54,at+.12),.017,"chassis")
		for at in [-3.6,-2.0,-.4]:
			_box(root,Vector3(side*1.16,.85,z+at),Vector3(.07,.1,1.65),"alloy")
		for at in [-4.15,0.0,4.15]: _box(root,Vector3(side*1.335,1.46,z+at),Vector3(.045,.095,.14),"amber")
		_box(root,Vector3(side*.85,.86,z-3.15),Vector3(.13,.67,.15),"chassis")
		_box(root,Vector3(side*.85,.51,z-3.15),Vector3(.31,.065,.34),"chassis")
		_box(root,Vector3(side*1.10,1.18,z+3.3),Vector3(.69,.07,2.75),"rubber")
		_box(root,Vector3(side*1.10,.55,z+4.18),Vector3(.69,.86,.065),"rubber")
	# Crown and small folds in the canvas break up the former perfectly flat boxes.
	if not is_box:
		var rings: Array[PackedVector3Array]=[]
		for segment in 25:
			var zz := z-4.76+float(segment)*9.52/24.0
			var fold := sin(float(segment)*2.2)*.032
			var ring := PackedVector3Array()
			for xy in [Vector2(-1.32,2.96),Vector2(-1.32,3.19),Vector2(-1.06,3.51),Vector2(0,3.67),Vector2(1.06,3.51),Vector2(1.32,3.19),Vector2(1.32,2.96)]:
				ring.append(Vector3(xy.x,xy.y+fold,zz))
			rings.append(ring)
		var faces: Array=[]
		for i in 24:
			for j in 6: faces.append(PackedVector3Array([rings[i][j],rings[i+1][j],rings[i+1][j+1],rings[i][j+1]]))
		for end in [0,24]:
			for j in range(1,6):
				var face := PackedVector3Array([rings[end][0],rings[end][j],rings[end][j+1],rings[end][0]])
				if end==24: face.reverse()
				faces.append(face)
		_surface(root,faces,"canvas",tarp)
		for offset in [-3.7,-1.85,0.0,1.85,3.7]:
			var path := [Vector3(-1.335,3.16,z+offset),Vector3(-1.07,3.54,z+offset),Vector3(0,3.705,z+offset),Vector3(1.07,3.54,z+offset),Vector3(1.335,3.16,z+offset)]
			for i in 4: _pipe(root,path[i],path[i+1],.02,"chassis")
	var rear := z+4.73
	_box(root,Vector3(0,(top+bottom)*.5,rear+.025),Vector3(.037,top-bottom,.04),"recess")
	for side in [-1.0,1.0]:
		_pipe(root,Vector3(side*.72,1.44,rear+.06),Vector3(side*.72,top-.13,rear+.06),.024,"alloy")
		_box(root,Vector3(side*.65,1.72,rear+.105),Vector3(.26,.055,.04),"chassis")
		for y in [1.6,2.3,top-.2]: _box(root,Vector3(side*1.16,y,rear+.06),Vector3(.18,.085,.07),"alloy")
		_box(root,Vector3(side*.95,.94,rear+.08),Vector3(.53,.23,.13),"seal")
		for x in [.79,.96,1.13]: _box(root,Vector3(side*x,.94,rear+.155),Vector3(.13,.14,.035),"amber" if x==1.13 else "red")
	_box(root,Vector3(0,.52,rear+.16),Vector3(2.43,.14,.16),"alloy")
	for i in 10: _box(root,Vector3(-1.08+float(i)*.24,.52,rear+.25),Vector3(.19,.10,.025),"red" if i%2==0 else "ivory")
	for x in [-.85,.85]: _box(root,Vector3(x,.77,rear+.1),Vector3(.08,.51,.12),"chassis")
	if index==0:
		_box(root,Vector3(0,1.06,rear+.58),Vector3(1.08,.22,1.18),"chassis")
		_pipe(root,Vector3(0,1.19,rear+.86),Vector3(0,1.28,rear+.86),.47,"chassis")

static func _tire(root: Node3D, at: Vector3) -> void:
	# Rounded shoulders, recessed sidewalls, separate tread shoulders; axle is along X.
	var profile := [Vector2(-.185,.34),Vector2(-.18,.46),Vector2(-.13,.55),Vector2(-.09,.57),Vector2(.09,.57),Vector2(.13,.55),Vector2(.18,.46),Vector2(.185,.34)]
	var faces: Array=[]
	for i in 24:
		var a := float(i)*TAU/24.0
		var b := float(i+1)*TAU/24.0
		for j in profile.size()-1:
			var p: Vector2=profile[j]
			var q: Vector2=profile[j+1]
			faces.append(PackedVector3Array([at+Vector3(p.x,cos(b)*p.y,sin(b)*p.y),at+Vector3(q.x,cos(b)*q.y,sin(b)*q.y),at+Vector3(q.x,cos(a)*q.y,sin(a)*q.y),at+Vector3(p.x,cos(a)*p.y,sin(a)*p.y)]))
	_surface(root,faces,"rubber")

static func _wheel(root: Node3D, at: Vector3, side: float) -> void:
	_tire(root,at)
	_pipe(root,at+Vector3(side*.08,0,0),at+Vector3(side*.18,0,0),.345,"alloy")
	_pipe(root,at+Vector3(side*.18,0,0),at+Vector3(side*.19,0,0),.261,"recess")
	_pipe(root,at+Vector3(side*.19,0,0),at+Vector3(side*.225,0,0),.174,"alloy")
	_pipe(root,at+Vector3(side*.225,0,0),at+Vector3(side*.25,0,0),.09,"chassis")
	for i in 8:
		var a := float(i)*TAU/8
		var p := at+Vector3(side*.232,cos(a)*.137,sin(a)*.137)
		_pipe(root,p,p+Vector3(side*.015,0,0),.024,"alloy")
	for i in 24:
		var a := float(i)*TAU/24
		var p := at+Vector3(0,cos(a)*.567,sin(a)*.567)
		var block := _box(root,p,Vector3(.20,.014,.030),"tread")
		block.rotation.x=a

static func _solid(root: Node3D, id: String, at: Vector3, size: Vector3) -> void:
	var node := Node3D.new()
	node.name=id
	node.position=at
	root.add_child(node)
	G.collision(node,size)
