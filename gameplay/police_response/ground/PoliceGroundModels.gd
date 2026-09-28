extends RefCounted
## Authored motorcycle chassis and a compact, fully physical tracked vehicle.
## Static geometry/materials are shared; no extra lights or autonomous loops.
static var _materials: Dictionary = {}
static var _boxes: Dictionary = {}
static var _geometry: Dictionary = {}
const KIT := preload("res://world/city_look/CityPropKit.gd")
const DETAIL := preload("res://runtime/HeavyVehicleDetail.gd")

static func motorcycle(model: Node3D) -> void:
	for side in [-1.0, 1.0]:
		_armor(model,"PolicePannier",Vector3(side*.43,.45,.63),Vector2(.30,.62),Vector2(.26,.54),.39,.065,Color("e4e7e4"))
		_box(model, "PannierStripe", Vector3(side * .577,.67,.63), Vector3(.012,.14,.5), Color("17283a"))
		_box(model,"PannierLid",Vector3(side*.43,.856,.63),Vector3(.26,.023,.49),Color("323b43"))
		_box(model,"PannierLatch",Vector3(side*.585,.75,.66),Vector3(.023,.065,.06),Color("b6bfc3"))
		_box(model, "PoliceBeacon", Vector3(side * .28,1.08,.79), Vector3(.16,.16,.16), Color("e83c42") if side < 0 else Color("3689ef"), "bar_left" if side < 0 else "bar_right")
	_armor(model,"PoliceFairing",Vector3(0,.76,-.65),Vector2(.48,.29),Vector2(.61,.16),.29,.08,Color("f0f1e9"))
	var screen := _armor(model,"PoliceWindshield",Vector3(0,1.05,-.67),Vector2(.55,.045),Vector2(.43,.038),.38,.04,Color("718b98"))
	screen.rotation.x = -.12
	_box(model,"ScreenMount",Vector3(0,1.09,-.637),Vector3(.41,.035,.018),Color("29343c"))
	# The rider is the authored articulated bike pilot. Child patches inherit its
	# visibility on mount/dismount and never leave a floating police badge behind.
	for part in model.get_children():
		if not part is MeshInstance3D or part.mesh == null: continue
		var material := part.get_active_material(0) as StandardMaterial3D
		if material == null or material.albedo_color.to_html(false) != "253043": continue
		var center: Vector3 = part.mesh.get_aabb().get_center()
		_box(part,"OfficerBadge",center+Vector3(-.10,.05,-.135),Vector3(.055,.077,.018),Color("c4b568"))
		break

static func tank() -> Node3D:
	var model := Node3D.new()
	model.name = "ArmyTank"
	_armor(model,"SlopedLowerHull",Vector3(0,.43,.03),Vector2(1.98,4.12),Vector2(2.56,4.65),.49,.23,Color("505c41"),"paint")
	_armor(model,"GlacisArmor",Vector3(0,.92,.03),Vector2(2.56,4.65),Vector2(2.17,3.86),.51,.26,Color("64704e"),"paint")
	_tracks(model)
	_details(model,"HullFittings",_hull_details())
	for side in [-1.0,1.0]:
		for section in 5:
			_armor(model,"SideSkirt",Vector3(side*1.36,1.02,-1.77+section*.89),Vector2(.37,.84),Vector2(.27,.80),.23,.07,Color("576448"),"paint")
		_box(model,"Headlight",Vector3(side*.89,1.17,-2.165),Vector3(.19,.15,.06),Color("f5f6fa"),"headlight")
	var turret := Node3D.new()
	turret.name = "TankTurret"
	turret.position = Vector3(0,1.48,-.28)
	model.add_child(turret)
	_armor(turret,"OctagonalTurret",Vector3(0,-.04,.10),Vector2(1.91,2.15),Vector2(1.43,1.56),.65,.37,Color("687653"),"paint")
	_armor(turret,"ArmoredMantlet",Vector3(0,.025,-.88),Vector2(.66,.47),Vector2(.54,.39),.48,.11,Color("505e43"),"paint")
	_details(turret,"TurretFittings",_turret_details())
	var barrel := Node3D.new()
	barrel.name = "TankBarrel"
	barrel.position = Vector3(0,.28,-1.02)
	turret.add_child(barrel)
	var recoil := Node3D.new()
	recoil.name = "BarrelRecoil"
	barrel.add_child(recoil)
	_details(recoil,"CannonTube",_barrel_details())
	var muzzle := Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0,0,-1.36)
	recoil.add_child(muzzle)
	return model

static func _octagon(size: Vector2, bevel: float, height: float) -> PackedVector3Array:
	var x := size.x*.5
	var z := size.y*.5
	var b := minf(bevel,minf(x,z)*.7)
	return PackedVector3Array([Vector3(-x+b,height,-z),Vector3(x-b,height,-z),Vector3(x,height,-z+b),Vector3(x,height,z-b),Vector3(x-b,height,z),Vector3(-x+b,height,z),Vector3(-x,height,z-b),Vector3(-x,height,-z+b)])

static func _armor(root: Node3D, title: String, point: Vector3, base: Vector2, top: Vector2, height: float, bevel: float, color: Color, key := "") -> MeshInstance3D:
	var cache := str([base,top,height,bevel])
	if not _geometry.has(cache):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(-1)
		var bottom := _octagon(base,bevel,0)
		var roof := _octagon(top,bevel,height)
		for index in 8:
			var next := (index+1)%8
			# Winding follows the existing native vehicle mesh builders.
			_triangle(st,bottom[index],roof[index],roof[next])
			_triangle(st,bottom[index],roof[next],bottom[next])
			_triangle(st,Vector3(0,height,0),roof[next],roof[index])
			_triangle(st,Vector3.ZERO,bottom[index],bottom[next])
		st.generate_normals()
		_geometry[cache] = st.commit()
	var part := MeshInstance3D.new()
	part.name = title
	part.mesh = _geometry[cache]
	part.position = point
	part.material_override = _material(color)
	if not key.is_empty(): part.set_meta("vehicle_material_key",key)
	root.add_child(part)
	return part

static func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)

static func _details(root: Node3D, title: String, mesh: ArrayMesh) -> void:
	var part := MeshInstance3D.new()
	part.name = title
	part.mesh = mesh
	part.material_override = KIT.material()
	root.add_child(part)

static func _tracks(root: Node3D) -> void:
	var tracks := MultiMeshInstance3D.new()
	tracks.name = "IndividualTrackLinks"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(.50,.085,.20)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = 112
	var radius := .445
	var straight := 3.7
	var length := straight*2.0+TAU*radius
	for side_index in 2:
		for index in 56:
			var cursor := float(index)/56.0*length
			var point := Vector3(-1.30 if side_index == 0 else 1.30,.57,0)
			var angle := 0.0
			if cursor < straight:
				point.y -= radius
				point.z = -straight*.5+cursor
			elif cursor < straight+PI*radius:
				var theta := (cursor-straight)/radius-PI*.5
				point += Vector3(0,sin(theta)*radius,straight*.5+cos(theta)*radius)
				angle = atan2(-cos(theta),-sin(theta))
			elif cursor < straight*2.0+PI*radius:
				point.y += radius
				point.z = straight*.5-(cursor-straight-PI*radius)
				angle = PI
			else:
				var theta := (cursor-straight*2.0-PI*radius)/radius+PI*.5
				point += Vector3(0,sin(theta)*radius,-straight*.5+cos(theta)*radius)
				angle = atan2(-cos(theta),-sin(theta))
			mm.set_instance_transform(side_index*56+index,Transform3D(Basis(Vector3.RIGHT,angle),point))
	tracks.multimesh = mm
	tracks.material_override = _material(Color("282e2b"))
	root.add_child(tracks)

static func _hull_details() -> ArrayMesh:
	if _geometry.has("hull_details"): return _geometry.hull_details
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0,1.0]:
		for index in 7:
			var center := Vector3(side*1.3,.56,-1.83+index*.61)
			DETAIL._tube(st,center+Vector3(side*.17,0,0),center+Vector3(side*.245,0,0),.33,Color("151b18"),14)
			DETAIL._tube(st,center+Vector3(side*.248,0,0),center+Vector3(side*.255,0,0),.249,Color("657050"),12)
			DETAIL._tube(st,center+Vector3(side*.256,0,0),center+Vector3(side*.27,0,0),.093,Color("353e30"),10)
			for bolt in 5:
				var theta := float(bolt)*TAU/5.0
				var p := center+Vector3(side*.264,sin(theta)*.16,cos(theta)*.16)
				DETAIL._tube(st,p,p+Vector3(side*.016,0,0),.019,Color("b2b59a"),5)
		# Headlight cages, towing eyes and rear exhaust cover.
		DETAIL._box(st,Vector3(side*.89,1.13,-2.13),Vector3(.31,.035,.16),Color("303b2e"))
		DETAIL._tube(st,Vector3(side*.69,.76,-2.29),Vector3(side*.69,.80,-2.45),.063,Color("333c2d"),8)
		DETAIL._tube(st,Vector3(side*.82,1.10,1.99),Vector3(side*.82,1.10,2.2),.12,Color("252c27"),10)
		DETAIL._box(st,Vector3(side*1.1,1.26,.93),Vector3(.06,.055,1.06),Color("292f24"))
	# Rear engine grilles and louvers are one batched mesh, not individual nodes.
	DETAIL._box(st,Vector3(0,1.434,1.22),Vector3(1.56,.03,.70),Color("222c25"))
	for index in 13:
		DETAIL._box(st,Vector3(-.72+index*.12,1.46,1.22),Vector3(.065,.035,.69),Color("586444"))
	DETAIL._tube(st,Vector3(-.74,1.27,1.88),Vector3(.74,1.27,1.88),.03,Color("293428"),8)
	st.generate_normals()
	_geometry.hull_details = st.commit()
	return _geometry.hull_details

static func _turret_details() -> ArrayMesh:
	if _geometry.has("turret_details"): return _geometry.turret_details
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	DETAIL._tube(st,Vector3(0,-.055,.1),Vector3(0,.015,.1),.76,Color("333c2d"),20)
	DETAIL._tube(st,Vector3(.29,.614,.23),Vector3(.29,.69,.23),.32,Color("3e4c35"),20)
	DETAIL._tube(st,Vector3(.29,.692,.23),Vector3(.29,.704,.23),.255,Color("657553"),20)
	for x in [.14,.44]:
		DETAIL._tube(st,Vector3(x,.71,.20),Vector3(x,.77,.20),.022,Color("222d23"),6)
	DETAIL._tube(st,Vector3(.14,.77,.20),Vector3(.44,.77,.20),.022,Color("222d23"),6)
	for index in 3:
		DETAIL._box(st,Vector3(-.14+index*.20,.65,-.39),Vector3(.135,.085,.105),Color("233d41"))
	for side in [-1.0,1.0]:
		for index in 3:
			var p := Vector3(side*.76,.28,.15+index*.17)
			DETAIL._tube(st,p,p+Vector3(side*.13,.14,-.08),.043,Color("323f2d"),8)
		DETAIL._box(st,Vector3(side*.73,.23,.77),Vector3(.10,.20,.43),Color("3c4c36"))
	DETAIL._tube(st,Vector3(-.56,.5,.57),Vector3(-.56,1.15,.57),.013,Color("202b23"),6)
	DETAIL._tube(st,Vector3(-.56,1.15,.57),Vector3(-.54,1.34,.54),.009,Color("202b23"),6)
	DETAIL._box(st,Vector3(-.26,.70,.30),Vector3(.1,.20,.12),Color("273326"))
	DETAIL._box(st,Vector3(-.26,.82,.16),Vector3(.11,.09,.40),Color("263329"))
	DETAIL._tube(st,Vector3(-.26,.83,.02),Vector3(-.26,.83,-.46),.021,Color("18231d"),8)
	st.generate_normals()
	_geometry.turret_details = st.commit()
	return _geometry.turret_details

static func _barrel_details() -> ArrayMesh:
	if _geometry.has("barrel_details"): return _geometry.barrel_details
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	DETAIL._tube(st,Vector3.ZERO,Vector3(0,0,-1.20),.098,Color("525e44"),18)
	DETAIL._tube(st,Vector3(0,0,-.18),Vector3(0,0,-.43),.135,Color("677353"),18)
	DETAIL._tube(st,Vector3(0,0,-1.16),Vector3(0,0,-1.35),.131,Color("37412f"),18)
	DETAIL._tube(st,Vector3(0,0,-1.351),Vector3(0,0,-1.36),.088,Color("111914"),18)
	st.generate_normals()
	_geometry.barrel_details = st.commit()
	return _geometry.barrel_details

static func _material(color: Color, emission := false) -> StandardMaterial3D:
	var key := str(color)+str(emission)
	if not _materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = .72
		mat.emission_enabled = emission
		mat.emission = color
		_materials[key] = mat
	return _materials[key]

static func _box(root: Node3D, title: String, point: Vector3, size: Vector3, color: Color, key := "") -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = title
	if not _boxes.has(size):
		var mesh := BoxMesh.new()
		mesh.size = size
		_boxes[size] = mesh
	part.mesh = _boxes[size]
	part.material_override = _material(color, key.begins_with("bar_") or key == "headlight")
	if not key.is_empty(): part.set_meta("vehicle_material_key",key)
	part.position = point
	root.add_child(part)
	return part
