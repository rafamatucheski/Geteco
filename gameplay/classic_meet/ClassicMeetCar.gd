extends StaticBody3D
## Period silhouettes for parked exhibition cars; front is local -Z.
var model_id := "gol"
var paint := Color("c93c31")
var hood_open := false
var neon := Color.TRANSPARENT
var neon_light: OmniLight3D
var neon_visual: Node3D
static var materials: Dictionary = {}

func _ready() -> void:
	name = model_id.capitalize()
	collision_layer = 1
	collision_mask = 0
	set_meta("classic_meet_car",model_id)
	var length := 4.42 if model_id == "parati" else (4.48 if model_id == "passat" else 3.88)
	var half := length*.5
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.74,1.47,length)
	collision.shape = shape
	collision.position.y = .77
	add_child(collision)
	_box("Chassis",Vector3(0,.42,0),Vector3(1.58,.22,length-.2),Color("242b30"))
	_box("LowerBody",Vector3(0,.68,0),Vector3(1.68,.36,length-.08),paint)
	_box("Beltline",Vector3(0,.91,.4),Vector3(1.69,.14,length-1.08),paint)
	var cabin_back := half-.20 if model_id == "parati" else 1.35
	var roof_back := cabin_back-.12 if model_id == "parati" else cabin_back-.62
	_prism(1.53,1.29,.93,1.48,-.80,-.38,cabin_back,roof_back,Color("233942"))
	_box("Roof",Vector3(0,1.49,(roof_back-.38)*.5),Vector3(1.31,.075,roof_back+.43),paint)
	for side in [-1.0,1.0]:
		_beam("WindshieldPillar",Vector3(side*.77,.95,-.8),Vector3(side*.66,1.5,-.39),.065,paint)
		_beam("RearPillar",Vector3(side*.77,.95,cabin_back),Vector3(side*.66,1.49,roof_back),.09,paint)
		_box("CenterPillar",Vector3(side*.735,1.19,.36),Vector3(.065,.50,.07),paint)
		_box("SideMolding",Vector3(side*.852,.72,.02),Vector3(.027,.058,length-.42),Color("22262a"))
		_box("DoorHandle",Vector3(side*.865,.91,.38),Vector3(.025,.055,.16),Color("b2b4b1"))
		_box("MirrorStem",Vector3(side*.89,1.00,-.67),Vector3(.12,.035,.045),Color("20272d"))
		_box("Mirror",Vector3(side*.98,1.025,-.67),Vector3(.15,.095,.13),paint)
		if model_id == "parati":
			_box("WagonRearPillar",Vector3(side*.736,1.2,1.03),Vector3(.06,.49,.065),paint)
			_box("RoofRail",Vector3(side*.53,1.58,.67),Vector3(.045,.06,1.76),Color("464c51"))
		for z in [-half+.68,half-.65]: _wheel(Vector3(side*.85,.35,z),side)
	for z in [-half,half]:
		_box("Bumper",Vector3(0,.51,z),Vector3(1.77,.17,.15),Color("292d30"))
		_box("ChromeBumperStrip",Vector3(0,.56,z+signf(z)*.083),Vector3(1.58,.038,.025),Color("c2c1b5"))
		_box("LicensePlate",Vector3(0,.63,z+signf(z)*.09),Vector3(.40,.13,.024),Color("cccbb9"))
	_box("Grille",Vector3(0,.84,-half-.022),Vector3(.8,.19,.026),Color("182024"))
	for y in [.78,.83,.88]: _box("GrilleSlat",Vector3(0,y,-half-.04),Vector3(.78,.013,.018),Color("747c7d"))
	for side in [-1.0,1.0]:
		if model_id == "passat":
			for x in [.49,.69]: _round("RoundHeadlamp",Vector3(side*x,.83,-half-.044),.086,.045,Color("e2dbba"),Vector3(PI*.5,0,0))
		else: _box("Headlamp",Vector3(side*.60,.83,-half-.035),Vector3(.36,.19,.034),Color("e0dec2"))
		_box("FrontIndicator",Vector3(side*.78,.78,-half-.04),Vector3(.11,.12,.035),Color("cc8b34"))
		_box("TailLamp",Vector3(side*.60,.85,half+.018),Vector3(.39,.17,.03),Color("8c2924"))
	_box("RearDeck",Vector3(0,.965,(cabin_back+half)*.5),Vector3(1.6,.11,maxf(.08,half-cabin_back)),paint)
	_build_hood(half)
	if neon.a > 0: _build_neon(length)
	_batch_static_meshes()

func _batch_static_meshes() -> void:
	var surfaces: Dictionary = {}
	for node in find_children("*","MeshInstance3D",true,false):
		if is_instance_valid(neon_visual) and neon_visual.is_ancestor_of(node): continue
		var material: Material = node.material_override
		if not surfaces.has(material):
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			surfaces[material] = surface
		var local: Transform3D = global_transform.affine_inverse()*node.global_transform
		surfaces[material].append_from(node.mesh,0,local)
		node.get_parent().remove_child(node)
		node.free()
	for material in surfaces:
		var mesh := MeshInstance3D.new()
		mesh.name = "BodyDetails"
		mesh.mesh = surfaces[material].commit()
		mesh.material_override = material
		add_child(mesh)

func _build_hood(half: float) -> void:
	var hood_length := half-.79
	if not hood_open:
		_box("ClosedHood",Vector3(0,.96,-.79-hood_length*.5),Vector3(1.59,.09,hood_length),paint)
		return
	_box("EngineBay",Vector3(0,.80,-.79-hood_length*.5),Vector3(1.40,.08,hood_length-.06),Color("161d22"))
	_box("EngineBlock",Vector3(-.12,.99,-1.33),Vector3(.58,.27,.49),Color("727a7e"))
	_box("ValveCover",Vector3(-.12,1.14,-1.33),Vector3(.42,.06,.45),Color("acb1b0"))
	for x in [-.28,-.17,-.06,.05]: _box("ValveRib",Vector3(x,1.176,-1.33),Vector3(.017,.012,.39),Color("616a70"))
	_round("AirFilter",Vector3(.32,1.02,-1.23),.20,.09,Color("343c42"),Vector3.ZERO)
	_box("Battery",Vector3(-.48,1.00,-1.70),Vector3(.24,.21,.23),Color("21262b"))
	_box("BatteryTerminal",Vector3(-.43,1.115,-1.71),Vector3(.05,.035,.035),Color("b8362e"))
	_box("Radiator",Vector3(0,.94,-half+.15),Vector3(1.03,.27,.10),Color("383e43"))
	var hood := Node3D.new()
	hood.name = "OpenHood"
	hood.position = Vector3(0,.99,-.79)
	hood.rotation.x = 1.08
	add_child(hood)
	_box("HoodPanel",Vector3(0,0,-hood_length*.5),Vector3(1.59,.07,hood_length),paint,hood)
	_box("HoodInsulation",Vector3(0,-.042,-hood_length*.5),Vector3(1.24,.024,hood_length*.77),Color("313a3d"),hood)
	_beam("HoodSupport",Vector3(.65,.88,-half+.22),Vector3(.65,1.69,-1.2),.018,Color("909a9c"))
	var hood_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.59,.09,hood_length)
	hood_shape.shape = box
	hood_shape.transform = hood.transform*Transform3D(Basis.IDENTITY,Vector3(0,0,-hood_length*.5))
	add_child(hood_shape)

func _build_neon(length: float) -> void:
	neon_visual = Node3D.new()
	neon_visual.name = "Underglow"
	add_child(neon_visual)
	for side in [-1.0,1.0]:
		var strip := _box("NeonTube",Vector3(side*.74,.24,0),Vector3(.045,.035,length-.85),neon,neon_visual)
		strip.material_override = _material(neon,true)
	neon_light = OmniLight3D.new()
	neon_light.name = "NeonGroundLight"
	neon_light.position.y = .22
	neon_light.light_color = neon
	neon_light.light_energy = 4.0
	neon_light.omni_range = 2.6
	neon_light.omni_attenuation = 1.45
	neon_light.shadow_enabled = false
	neon_light.light_specular = .35
	add_child(neon_light)

func set_neon_enabled(enabled: bool) -> void:
	if is_instance_valid(neon_visual): neon_visual.visible = enabled
	if is_instance_valid(neon_light): neon_light.visible = enabled

func _wheel(point: Vector3, side: float) -> void:
	_round("Tire",point,.325,.21,Color("191e22"),Vector3(0,0,PI*.5))
	_round("AlloyRim",point+Vector3(side*.112,0,0),.226,.026,Color("b2b9ba"),Vector3(0,0,PI*.5))
	_round("RimInset",point+Vector3(side*.13,0,0),.173,.03,Color("444d52"),Vector3(0,0,PI*.5))
	for spoke in 5:
		var spoke_mesh := _box("RimSpoke",point+Vector3(side*.15,0,0),Vector3(.025,.035,.38),Color("b8c0c1"))
		spoke_mesh.rotation.x = float(spoke)*PI/5.0
	_round("Hub",point+Vector3(side*.17,0,0),.058,.03,Color("c7cdca"),Vector3(0,0,PI*.5))

func _material(color: Color, glow := false) -> StandardMaterial3D:
	var key := str(color)+str(glow)
	if not materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = .40 if color == paint else .72
		mat.metallic = .24 if color == paint else .12
		if glow:
			mat.emission_enabled = true
			mat.emission = color
			mat.emission_energy_multiplier = 1.3
		materials[key] = mat
	return materials[key]

func _box(label: String, point: Vector3, size: Vector3, color: Color, parent: Node3D = self) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = label
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(color)
	mesh.position = point
	parent.add_child(mesh)
	return mesh

func _round(label: String, point: Vector3, radius: float, height: float, color: Color, angles: Vector3) -> void:
	var node := MeshInstance3D.new()
	node.name = label
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	node.mesh = mesh
	node.material_override = _material(color)
	node.position = point
	node.rotation = angles
	add_child(node)

func _beam(label: String, a: Vector3, b: Vector3, width: float, color: Color) -> void:
	var node := _box(label,(a+b)*.5,Vector3(width,a.distance_to(b),width),color)
	node.quaternion = Quaternion(Vector3.UP,(b-a).normalized())

func _prism(base_width: float, roof_width: float, low: float, high: float, front: float, roof_front: float, rear: float, roof_rear: float, color: Color) -> void:
	var points := PackedVector3Array([
		Vector3(-base_width*.5,low,front),Vector3(base_width*.5,low,front),Vector3(base_width*.5,low,rear),Vector3(-base_width*.5,low,rear),
		Vector3(-roof_width*.5,high,roof_front),Vector3(roof_width*.5,high,roof_front),Vector3(roof_width*.5,high,roof_rear),Vector3(-roof_width*.5,high,roof_rear)])
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in [0,1,5,0,5,4,1,2,6,1,6,5,2,3,7,2,7,6,3,0,4,3,4,7,4,5,6,4,6,7]: surface.add_vertex(points[index])
	surface.generate_normals()
	var node := MeshInstance3D.new()
	node.name = "GlazedCabin"
	node.mesh = surface.commit()
	node.material_override = _material(color)
	add_child(node)
