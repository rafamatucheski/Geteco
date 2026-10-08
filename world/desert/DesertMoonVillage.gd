extends RefCounted
## Santa Lua is a small inhabited roadside hamlet. Geometry and physics share
## authored parts, while collision is admitted before deferred visual dressing.
const G := preload("res://world/desert/DesertGeometry.gd")
const MATERIALS := preload("res://world/desert/DesertTownMaterials.gd")
const CENTER := Vector3(-528,0,-822)
const BOUNDS := Rect2(-565,-865,75,87)
const APPROACH := Rect2(-536,-879,16,63)
static var _parts_cache: Dictionary = {}
static var _meshes: Dictionary = {}

static func definitions() -> Array[Dictionary]:
	return [
		{"id":"santa_lua_home_1","position":Vector3(-550,0,-842),"size":Vector3(11,3.4,8),"yaw":PI*.5,"kind":"home","style":"adobe","finish":"adobe","lamp":true},
		{"id":"santa_lua_home_2","position":Vector3(-506,0,-842),"size":Vector3(10,3.1,8),"yaw":-PI*.5,"kind":"home","style":"ranch","finish":"wood","lamp":false},
		{"id":"santa_lua_home_3","position":Vector3(-550,0,-816),"size":Vector3(10,3.15,8),"yaw":PI*.5,"kind":"home","style":"stone","finish":"stone","lamp":false},
		{"id":"santa_lua_home_4","position":Vector3(-506,0,-816),"size":Vector3(11,3.5,8),"yaw":-PI*.5,"kind":"home","style":"shed","finish":"steel","lamp":true},
		{"id":"santa_lua_store","position":Vector3(-528,0,-793),"size":Vector3(13,3.9,8),"yaw":PI,"kind":"store","finish":"cream","lamp":true},
		{"id":"santa_lua_water_tower","position":Vector3(-550,0,-790),"size":Vector3(6,11,6),"yaw":0.0,"kind":"tower"},
		{"id":"santa_lua_courtyard","position":CENTER,"size":Vector3(64,2,73),"yaw":0.0,"kind":"courtyard"},
	]

static func reservation_clear(point: Vector2, radius := 0.0) -> bool:
	return not BOUNDS.grow(radius+2).has_point(point) and not APPROACH.grow(radius+2).has_point(point)

static func records() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for definition in definitions(): result.append({"kind":"moon_village","position":definition.position,"data":definition})
	return result

static func build_collision(parent: Node3D, rect: Rect2) -> void:
	for data in definitions():
		if not rect.has_point(Vector2(data.position.x,data.position.z)): continue
		var body := StaticBody3D.new()
		body.name=str(data.id)+"_solids"
		body.position=data.position
		body.rotation.y=data.yaw
		body.collision_layer=1
		body.collision_mask=0
		body.set_meta("desert_village_solid",true)
		parent.add_child(body)
		for part in _parts(data):
			if not part.solid: continue
			var shape: Shape3D
			if part.shape=="cylinder":
				var cylinder := CylinderShape3D.new()
				cylinder.radius=part.size.x
				cylinder.height=part.size.y
				shape=cylinder
			elif part.shape in ["gable","shed"]:
				var prism := ConvexPolygonShape3D.new()
				var points := PackedVector3Array()
				for point in _prism_vertices(part.shape): points.append(point*Vector3(part.size))
				prism.points=points
				shape=prism
			else:
				var box := BoxShape3D.new()
				box.size=part.size
				shape=box
			var collider := CollisionShape3D.new()
			collider.name=part.id
			collider.position=part.position
			collider.rotation=part.rotation
			collider.shape=shape
			collider.set_meta("village_solid_id",part.id)
			body.add_child(collider)

static func build_record(parent: Node3D, data: Dictionary) -> Array[OmniLight3D]:
	var village := Node3D.new()
	village.name=data.id
	village.position=data.position
	village.rotation.y=data.yaw
	village.set_meta("desert_moon_village",true)
	parent.add_child(village)
	var groups: Dictionary={}
	for part in _parts(data):
		var key: String=part.shape+":"+part.finish
		if not groups.has(key): groups[key]={"shape":part.shape,"finish":part.finish,"transforms":[]}
		groups[key].transforms.append(Transform3D(Basis.from_euler(part.rotation)*Basis.from_scale(part.size),part.position))
	for group in groups.values():
		var mesh := MultiMesh.new()
		mesh.transform_format=MultiMesh.TRANSFORM_3D
		mesh.mesh=_mesh(group.shape)
		mesh.instance_count=group.transforms.size()
		for i in group.transforms.size(): mesh.set_instance_transform(i,group.transforms[i])
		var instance := MultiMeshInstance3D.new()
		instance.name="Village_"+str(group.finish)+"_"+str(group.shape)
		instance.multimesh=mesh
		if Engine.get_meta("geteco_live_preview_build",false): instance.set_meta("preview_instance_transforms",group.transforms)
		instance.material_override=MATERIALS.material(group.finish)
		village.add_child(instance)
	if data.kind=="store": G.sign_name(village,"Santa Lua",Vector3(0,3.57,4.27),44)
	var lights: Array[OmniLight3D]=[]
	if data.get("lamp",false):
		var lamp := OmniLight3D.new()
		lamp.name="PorchLanternLight"
		lamp.position=Vector3(1.45,2.65,5.1)
		lamp.light_color=Color("ffd29b")
		lamp.omni_range=11.0
		lamp.omni_attenuation=1.8
		lamp.light_energy=0
		lamp.shadow_enabled=false
		village.add_child(lamp)
		lights.append(lamp)
	return lights

static func build_ground(parent: Node3D, rect: Rect2) -> void:
	# Continuous regional terrain owns all support. These thin visual layers sit
	# above it and stop at the asphalt shoulder, with a broad vehicle turn-in.
	# Disjoint pieces form one courtyard footprint, without coplanar overlaps.
	for area in [Rect2(-536,-872,16,20),Rect2(-546,-852,36,49),Rect2(-558,-826,12,9),Rect2(-510,-826,12,9)]:
		var clipped: Rect2=area.intersection(rect)
		if not clipped.has_area(): continue
		var offset := .018
		G.quad(parent,"SantaLuaWornGround",PackedVector3Array([
			Vector3(clipped.position.x,offset,clipped.position.y),Vector3(clipped.end.x,offset,clipped.position.y),
			Vector3(clipped.end.x,offset,clipped.end.y),Vector3(clipped.position.x,offset,clipped.end.y)
		]),G.material(Color("ad9570"),true))

static func _parts(data: Dictionary) -> Array[Dictionary]:
	var key: String=data.id
	if _parts_cache.has(key): return _parts_cache[key]
	var parts: Array[Dictionary]=[]
	match data.kind:
		"home", "store": _house(parts,data)
		"tower": _tower(parts)
		"courtyard": _courtyard(parts)
	_parts_cache[key]=parts
	return parts

static func _box(parts: Array[Dictionary],id: String,at: Vector3,size: Vector3,finish: String,solid := false,rotation := Vector3.ZERO) -> void:
	parts.append({"id":id,"position":at,"size":size,"finish":finish,"shape":"box","solid":solid,"rotation":rotation})

static func _cylinder(parts: Array[Dictionary],id: String,at: Vector3,radius: float,height: float,finish: String,solid := false) -> void:
	parts.append({"id":id,"position":at,"size":Vector3(radius,height,radius),"finish":finish,"shape":"cylinder","solid":solid,"rotation":Vector3.ZERO})

static func _beam(parts: Array[Dictionary],id: String,start: Vector3,end: Vector3,width: float,finish: String,solid := false) -> void:
	var direction := end-start
	_box(parts,id,(start+end)*.5,Vector3(width,direction.length(),width),finish,solid,Basis(Quaternion(Vector3.UP,direction.normalized())).get_euler())

static func _house(parts: Array[Dictionary],data: Dictionary) -> void:
	var size: Vector3=data.size
	var h := size.y
	var style: String=data.get("style","store")
	# Exterior shells remain solid; the authored porch access transfers to the
	# corresponding NativePlace, with no empty box trapping a restored actor.
	_box(parts,"HouseShell",Vector3(0,h*.5,0),size,data.finish,true)
	_box(parts,"StoneFooting",Vector3(0,.19,0),Vector3(size.x+.28,.38,size.z+.28),"stone",true)
	for side in [-1.0,1.0]:
		_box(parts,"CornerQuoin",Vector3(side*(size.x*.5-.17),h*.5,4.05),Vector3(.36,h,.2),"wood" if style in ["ranch","shed"] else "stone")
		var window_width: float=1.35 if style=="adobe" else (2.65 if style=="ranch" else 1.8)
		var window_height: float=1.8 if style=="stone" else (1.05 if style=="shed" else 1.35)
		_box(parts,"WindowReveal",Vector3(side*size.x*.29,1.72,4.09),Vector3(window_width+.28,window_height+.28,.22),"wood")
		_box(parts,"WindowGlass",Vector3(side*size.x*.29,1.74,4.22),Vector3(window_width,window_height,.025),"glass")
		_box(parts,"WindowMullion",Vector3(side*size.x*.29,1.74,4.25),Vector3(.085,window_height,.06),"wood")
		_box(parts,"WindowSill",Vector3(side*size.x*.29,1.66-window_height*.5,4.31),Vector3(window_width+.44,.13,.39),"stone")
		if style in ["adobe","stone","store"]:
			for shutter in [-1.0,1.0]:
				_box(parts,"Shutter",Vector3(side*size.x*.29+shutter*(window_width*.5+.32),1.74,4.16),Vector3(.38,window_height+.21,.12),"wood")
		_box(parts,"PorchPost",Vector3(side*(size.x*.5-.4),1.46,6.7),Vector3(.19,2.92,.19),"wood",true)
		_box(parts,"PorchSideRail",Vector3(side*(size.x*.5-.4),.77,5.56),Vector3(.12,.16,2.25),"wood",true)
		for rung in 5:
			_box(parts,"PorchBaluster",Vector3(side*(size.x*.5-.4),.48,4.67+float(rung)*.42),Vector3(.075,.78,.075),"wood",true)
	_box(parts,"DoorTrim",Vector3(0,1.24,4.11),Vector3(1.5,2.48,.19),"wood")
	_box(parts,"ClosedDoor",Vector3(0,1.19,4.24),Vector3(1.16,2.26,.08),"wood" if style in ["adobe","ranch"] else "rust")
	_box(parts,"DoorPanel",Vector3(0,.78,4.29),Vector3(.86,.78,.025),"wood")
	_box(parts,"DoorHandle",Vector3(.39,1.13,4.31),Vector3(.065,.16,.07),"steel")
	# The porch surface is flush with the regional floor; posts and furniture
	# remain physical, while the roof is well above pedestrian head clearance.
	_box(parts,"PorchPaving",Vector3(0,.024,5.38),Vector3(size.x+.5,.046,3.1),"wood" if style=="ranch" else "stone")
	_box(parts,"PorchBeam",Vector3(0,2.96,6.7),Vector3(size.x+.55,.24,.22),"wood",true)
	_roof_and_siding(parts,data,style)
	_bench(parts,Vector3(-size.x*.28,0,5.23),0)
	_cylinder(parts,"PorchPlanter",Vector3(size.x*.35,.3,5.42),.32,.6,"rust",true)
	for i in 5:
		_beam(parts,"DryAgave",Vector3(size.x*.35,.5,5.42),Vector3(size.x*.35+sin(float(i)*TAU/5)*.4,1.02,5.42+cos(float(i)*TAU/5)*.4),.055,"wood")
	if data.kind=="store":
		_box(parts,"Nameboard",Vector3(0,3.57,4.13),Vector3(6,.71,.18),"wood")
		for x in [-4.0,4.0]:
			_box(parts,"ProduceCrate",Vector3(x,.47,5.37),Vector3(1.15,.94,.84),"wood",true)
			for band in [-.35,.35]: _box(parts,"CrateBand",Vector3(x+band,.47,5.81),Vector3(.075,.96,.035),"steel")
	if data.get("lamp",false):
		_box(parts,"LanternBracket",Vector3(1.45,2.72,4.55),Vector3(.065,.065,.9),"steel")
		_box(parts,"LanternBody",Vector3(1.45,2.55,4.97),Vector3(.25,.36,.25),"cream")
		_box(parts,"LanternCap",Vector3(1.45,2.77,4.97),Vector3(.36,.075,.36),"steel")
		for side in [-1.0,1.0]: _box(parts,"LanternFrame",Vector3(1.45+side*.13,2.55,5.1),Vector3(.035,.4,.035),"steel")

static func _roof_and_siding(parts: Array[Dictionary],data: Dictionary,style: String) -> void:
	var size: Vector3=data.size
	var h: float=size.y
	match style:
		"adobe":
			_box(parts,"FlatAdobeRoof",Vector3(0,h+.1,0),Vector3(size.x+.3,.2,8.3),"adobe",true)
			for side in [-1.0,1.0]:
				_box(parts,"AdobeParapet",Vector3(side*size.x*.5,h+.46,0),Vector3(.32,.75,8.3),"adobe",true)
				_box(parts,"AdobeParapet",Vector3(0,h+.46,side*4.02),Vector3(size.x,.75,.32),"adobe",true)
			_box(parts,"SteppedAdobeCrown",Vector3(0,h+.78,4.02),Vector3(3.8,.6,.36),"adobe",true)
			for i in 10:
				var x: float=-size.x*.44+float(i)*size.x*.88/9.0
				_cylinder(parts,"ExposedViga",Vector3(x,h-.18,4.24),.085,.72,"wood")
				parts[-1].rotation=Vector3(PI*.5,0,0)
			for i in 18:
				_box(parts,"PergolaSlat",Vector3(-size.x*.5+float(i)*size.x/17.0,3.13,5.34),Vector3(.2,.16,3.62),"wood",true)
		"ranch":
			# One broad roof shelters the house and veranda as a single ranch form.
			_prism(parts,"RanchLoft",Vector3(0,h,1.25),Vector3(11.5,1.3,size.x),"wood","gable",Vector3(0,PI*.5,0))
			for side in [-1.0,1.0]:
				var slope: float=float(side)*.222
				var z: float=1.25+float(side)*2.875
				_box(parts,"LongRanchRoof",Vector3(0,h+.71,z),Vector3(size.x+1.2,.14,6.02),"roof",true,Vector3(slope,0,0))
				for i in 14:
					_box(parts,"RanchRoofSeam",Vector3(-size.x*.5+float(i)*size.x/13.0,h+.81,z),Vector3(.04,.04,6.01),"steel",false,Vector3(slope,0,0))
			_box(parts,"RanchRidge",Vector3(0,h+1.39,1.25),Vector3(size.x+1.22,.15,.24),"steel")
			for row in 11:
				var y: float=.42+float(row)*.24
				for side in [-1.0,1.0]:
					_box(parts,"RanchClapboard",Vector3(side*(size.x*.5+.018),y,0),Vector3(.055,.055,8),"wood")
				_box(parts,"RanchRearClapboard",Vector3(0,y,-4.018),Vector3(size.x,.055,.055),"wood")
			for side in [-1.0,1.0]:
				_beam(parts,"RanchPorchBrace",Vector3(side*(size.x*.5-.4),2.3,6.7),Vector3(side*(size.x*.5-1.25),2.9,6.7),.13,"wood",true)
		"stone":
			# A steep front-facing gable and a heavy side chimney distinguish stone.
			_prism(parts,"StoneGable",Vector3(0,h,0),Vector3(size.x,2.3,8),"stone","gable")
			for side in [-1.0,1.0]:
				var roll: float=-float(side)*.431
				_box(parts,"HighStoneRoof",Vector3(side*size.x*.25,h+1.24,0),Vector3(5.86,.17,8.65),"rust",true,Vector3(0,0,roll))
				for i in 12:
					_box(parts,"StoneRoofSeam",Vector3(side*size.x*.25,h+1.34,-4.2+float(i)*8.4/11.0),Vector3(5.85,.04,.04),"wood",false,Vector3(0,0,roll))
			_box(parts,"StoneRoofRidge",Vector3(0,h+2.46,0),Vector3(.22,.15,8.8),"rust")
			_box(parts,"SideStoneChimney",Vector3(size.x*.5-.52,(h+2.65)*.5,-1.7),Vector3(1.02,h+2.65,1.3),"stone",true)
			_box(parts,"SideChimneyCap",Vector3(size.x*.5-.52,h+2.73,-1.7),Vector3(1.3,.17,1.56),"chalk")
			_box(parts,"StonePorchCanopy",Vector3(0,3.13,5.35),Vector3(size.x+.8,.16,3.58),"wood",true,Vector3(-.07,0,0))
			for side in [-1.0,1.0]:
				for row in 6:
					_box(parts,"CornerMasonry",Vector3(side*(size.x*.5-.2),.45+float(row)*.44,4.035),Vector3(.7,.22,.16),"chalk")
		"shed":
			# A single weathered sheet roof slopes across the facade; a smaller
			# offset porch canopy leaves its right-hand bay visibly open.
			_prism(parts,"ShedUpperWall",Vector3(0,h,0),Vector3(size.x,1.45,8),"steel","shed")
			_box(parts,"SingleSlopeRoof",Vector3(0,h+.83,0),Vector3(size.x+1.05,.16,8.7),"rust",true,Vector3(0,0,-.131))
			for i in 17:
				var x: float=-size.x*.5+float(i)*size.x/16.0
				_box(parts,"ShedRoofSeam",Vector3(x,h+.925-x*.13,0),Vector3(.046,.04,8.69),"steel",false,Vector3(0,0,-.131))
			_box(parts,"OffsetLeanToCanopy",Vector3(-1.9,3.14,5.35),Vector3(7.3,.14,3.57),"roof",true,Vector3(-.065,0,0))
			for side in [-1.0,1.0]:
				for i in 19:
					_box(parts,"CorrugatedSideRib",Vector3(side*(size.x*.5+.025),h*.5,-3.9+float(i)*.43),Vector3(.065,h-.12,.06),"roof")
			for i in 23:
				_box(parts,"CorrugatedRearRib",Vector3(-size.x*.5+.15+float(i)*.48,h*.5,-4.025),Vector3(.06,h-.12,.065),"roof")
		_:
			_box(parts,"StorePorchRoof",Vector3(0,3.11,5.35),Vector3(size.x+1.2,.13,3.6),"rust",true,Vector3(-.08,0,0))
			_prism(parts,"StoreLoft",Vector3(0,h,0),Vector3(8,1.0,size.x),"cream","gable",Vector3(0,PI*.5,0))
			for side in [-1.0,1.0]:
				var slope: float=float(side)*.22
				_box(parts,"StorePitchedRoof",Vector3(0,h+.55,side*2.05),Vector3(size.x+.95,.15,4.5),"roof",true,Vector3(slope,0,0))
				for i in 15:
					_box(parts,"StoreRoofSeam",Vector3(-size.x*.5+float(i)*size.x/14.0,h+.655,side*2.04),Vector3(.045,.045,4.5),"steel",false,Vector3(slope,0,0))
			_box(parts,"StoreRoofRidge",Vector3(0,h+1.06,0),Vector3(size.x+1.1,.15,.25),"steel")

static func _prism(parts: Array[Dictionary],id: String,at: Vector3,size: Vector3,finish: String,shape: String,rotation := Vector3.ZERO) -> void:
	parts.append({"id":id,"position":at,"size":size,"finish":finish,"shape":shape,"solid":true,"rotation":rotation})

static func _prism_vertices(kind: String) -> PackedVector3Array:
	var ridge_x: float=-.5 if kind=="shed" else 0.0
	return PackedVector3Array([Vector3(-.5,0,.5),Vector3(.5,0,.5),Vector3(ridge_x,1,.5),Vector3(-.5,0,-.5),Vector3(.5,0,-.5),Vector3(ridge_x,1,-.5)])

static func _bench(parts: Array[Dictionary],at: Vector3,yaw: float) -> void:
	var frame := Basis(Vector3.UP,yaw)
	_box(parts,"BenchSeat",at+Vector3(0,.48,0),Vector3(1.8,.15,.66),"wood",true,Vector3(0,yaw,0))
	_box(parts,"BenchBack",at+frame*Vector3(0,.94,-.3),Vector3(1.8,.7,.12),"wood",true,Vector3(0,yaw,0))
	for side in [-1.0,1.0]: _box(parts,"BenchLeg",at+frame*Vector3(side*.67,.21,0),Vector3(.15,.42,.55),"steel",true,Vector3(0,yaw,0))

static func _tower(parts: Array[Dictionary]) -> void:
	for x in [-1.8,1.8]:
		for z in [-1.8,1.8]:
			_box(parts,"TowerFoot",Vector3(x,.19,z),Vector3(.74,.38,.74),"stone",true)
			_box(parts,"TowerLeg",Vector3(x,3.7,z),Vector3(.24,7.4,.24),"wood",true)
	for side in [-1.0,1.0]:
		for y in [1.1,3.8]:
			_beam(parts,"TowerDiagonal",Vector3(-1.8,y,side*1.8),Vector3(1.8,y+2.7,side*1.8),.12,"steel",true)
			_beam(parts,"TowerDiagonal",Vector3(side*1.8,y,-1.8),Vector3(side*1.8,y+2.7,1.8),.12,"steel",true)
	_cylinder(parts,"WaterTank",Vector3(0,8.55,0),2.6,3.25,"wood",true)
	for y in [7.05,7.6,9.2,10.08]: _cylinder(parts,"TankRing",Vector3(0,y,0),2.64,.12,"steel")
	_cylinder(parts,"TankLid",Vector3(0,10.23,0),2.8,.18,"rust",true)
	for side in [-1.0,1.0]: _box(parts,"TowerLadderRail",Vector3(side*.3,4.45,2.76),Vector3(.08,8.9,.08),"steel",true)
	for step in 26: _box(parts,"TowerLadderRung",Vector3(0,.33+float(step)*.34,2.76),Vector3(.65,.07,.07),"steel")
	_box(parts,"WaterPipe",Vector3(2.7,3.5,0),Vector3(.16,7,.16),"steel",true)

static func _courtyard(parts: Array[Dictionary]) -> void:
	_bench(parts,Vector3(-10,0,-6),PI*.5)
	_bench(parts,Vector3(10,0,8),-PI*.5)
	# The central 14 m corridor stays open to pedestrians and turning cars.
	for at in [Vector3(-12,0,12),Vector3(12,0,-14)]:
		_cylinder(parts,"WaterBarrel",at+Vector3.UP*.52,.4,1.04,"wood",true)
		for y in [.12,.87]: _cylinder(parts,"BarrelHoop",at+Vector3.UP*y,.41,.055,"steel")
	for x in [-33.0,33.0]:
		for z in [-35.0,-27.0,-19.0,-11.0,-3.0,5.0,13.0,21.0,29.0]:
			_box(parts,"BoundaryFencePost",Vector3(x,.66,z),Vector3(.17,1.32,.17),"wood",true)
			if z<29.0:
				for y in [.49,1.01]: _box(parts,"BoundaryFenceRail",Vector3(x,y,z+4),Vector3(.11,.13,8),"wood",true)
	# Laundry, rain barrels and stored firewood make the place read as occupied
	# without extra NPC loops or explanatory labels.
	for x in [-25.0,-17.0]: _box(parts,"ClothesPost",Vector3(x,2,-33),Vector3(.12,4,.12),"wood",true)
	_beam(parts,"ClothesLine",Vector3(-25,3.22,-33),Vector3(-17,3.22,-33),.022,"steel")
	for i in 5:
		_box(parts,"HangingLaundry",Vector3(-23.8+float(i)*1.35,2.7,-33),Vector3(.72,.92,.028),"chalk" if i%2==0 else "cream")
	for i in 5:
		_box(parts,"StackedFirewood",Vector3(27.5,.17+float(floori(float(i)/3.0))*.25,22+float(i%3)*.35),Vector3(1.8,.25,.27),"wood",true)
	_box(parts,"StoneTrough",Vector3(22,.4,28),Vector3(3.8,.8,1.2),"stone",true)
	_box(parts,"TroughDarkBasin",Vector3(22,.808,28),Vector3(3.36,.03,.84),"glass")

static func _mesh(kind: String) -> Mesh:
	if _meshes.has(kind): return _meshes[kind]
	var mesh: Mesh
	if kind in ["gable","shed"]:
		var vertices := _prism_vertices(kind)
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		# Godot front faces use clockwise winding, including the triangular ends.
		for index in [0,2,1,3,4,5,0,5,2,0,3,5,2,4,1,2,5,4,3,1,4,3,0,1]:
			surface.add_vertex(vertices[index])
		surface.generate_normals()
		mesh=surface.commit()
	elif kind=="cylinder":
		var cylinder := CylinderMesh.new()
		cylinder.top_radius=1.0
		cylinder.bottom_radius=1.0
		cylinder.height=1.0
		cylinder.radial_segments=16
		cylinder.rings=1
		mesh=cylinder
	else:
		var box := BoxMesh.new()
		box.size=Vector3.ONE
		mesh=box
	_meshes[kind]=mesh
	return mesh
