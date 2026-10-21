extends RefCounted
## Digo-only static furniture. Existing tagged proxy meshes remain the physics
## authority; these visible details never extend into the vehicle bay or routes.
const MATERIALS := ["steel","steel_dark","enamel_red","enamel_green","wood","rubber","plastic","screen"]
const LEGACY_PREFIXES := ["Workbench","ToolChest","Drawer","TuningDesk","Computer","DeskChair","LiftPost","LiftFoot","PartsShelf","PartsCrate","SocketTool","TuningKeyboard","PartsNotebook","SeatCushion","SeatBack","SeatLeg"]
static var _cached_mesh: ArrayMesh
var _surfaces: Dictionary = {}
var _box_mesh: BoxMesh
var _cylinder_mesh: CylinderMesh
var _tire_mesh: TorusMesh

static func install(room: Node3D) -> MeshInstance3D:
	# Hide the coarse visual only. NativePlace still reads its original AABB and
	# interior_solid_id, including the chair and lift's full reserved footprint.
	for child in room.get_children():
		if not child is MeshInstance3D: continue
		for prefix in LEGACY_PREFIXES:
			if str(child.name).begins_with(prefix):
				child.set_meta("digo_refined_proxy",true)
				child.hide()
				break
	if _cached_mesh == null:
		var builder := new()
		_cached_mesh = builder._build()
	var details := MeshInstance3D.new()
	details.name = "DigoFurnitureDetails"
	details.mesh = _cached_mesh
	details.set_meta("digo_static_furniture",true)
	room.add_child(details)
	return details

func _build() -> ArrayMesh:
	_box_mesh = BoxMesh.new()
	_box_mesh.size = Vector3.ONE
	_cylinder_mesh = CylinderMesh.new()
	_cylinder_mesh.top_radius = 1.0
	_cylinder_mesh.bottom_radius = 1.0
	_cylinder_mesh.height = 1.0
	_cylinder_mesh.radial_segments = 12
	_tire_mesh = TorusMesh.new()
	_tire_mesh.inner_radius = .17
	_tire_mesh.outer_radius = .33
	_tire_mesh.rings = 16
	_tire_mesh.ring_segments = 8
	for kind in MATERIALS:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		_surfaces[kind] = surface
	_workbench()
	_tool_chest()
	_desk()
	_lift()
	_shelves()
	var result := ArrayMesh.new()
	for kind in MATERIALS:
		var surface: SurfaceTool = _surfaces[kind]
		surface.set_material(_material(kind))
		surface.commit(result)
		result.surface_set_name(result.get_surface_count()-1,kind)
	return result

func _append(mesh: Mesh, at: Vector3, scale: Vector3, kind: String, rotation := Vector3.ZERO) -> void:
	var basis := Basis.from_euler(rotation).scaled(scale)
	_surfaces[kind].append_from(mesh,0,Transform3D(basis,at))

func _box(at: Vector3, size: Vector3, kind: String, rotation := Vector3.ZERO) -> void:
	_append(_box_mesh,at,size,kind,rotation)

func _cylinder(at: Vector3, radius: float, height: float, kind: String, rotation := Vector3.ZERO) -> void:
	_append(_cylinder_mesh,at,Vector3(radius,height,radius),kind,rotation)

func _workbench() -> void:
	# Authored envelope: x[-11.75,-7.65], y[0,1.3], z[-6,-4.8].
	_box(Vector3(-9.7,1.245,-5.4),Vector3(4.1,.11,1.2),"steel")
	_box(Vector3(-9.7,.67,-5.45),Vector3(4.0,1.04,1.04),"enamel_green")
	_box(Vector3(-9.7,.11,-5.44),Vector3(3.9,.15,1.02),"steel_dark")
	for column in 3:
		for row in 3:
			var at := Vector3(-11.05+float(column)*1.35,.36+float(row)*.30,-4.88)
			_box(at,Vector3(1.25,.25,.08),"enamel_green")
			_box(at+Vector3(0,.045,.055),Vector3(.34,.026,.025),"steel")
			_box(at+Vector3(.43,.035,.045),Vector3(.09,.045,.008),"plastic")
	# A vise anchored on the worktop, wholly above the existing footprint.
	_box(Vector3(-11.20,1.35,-5.56),Vector3(.31,.10,.25),"steel_dark")
	_box(Vector3(-11.20,1.435,-5.56),Vector3(.32,.10,.10),"steel")
	_cylinder(Vector3(-11.20,1.35,-5.39),.018,.25,"steel",Vector3(0,0,PI*.5))
	# Familiar hand tools, proportioned in metres rather than giant silhouettes.
	for index in 3:
		var x := -10.45+float(index)*.27
		_box(Vector3(x,1.322,-5.35),Vector3(.025,.018,.22),"steel",Vector3(0,.13*float(index),0))
		_cylinder(Vector3(x,1.326,-5.23),.035,.018,"steel")
		_cylinder(Vector3(x,1.337,-5.23),.018,.008,"steel_dark")
	_box(Vector3(-9.40,1.328,-5.35),Vector3(.04,.035,.16),"enamel_red")
	_box(Vector3(-9.40,1.325,-5.52),Vector3(.012,.012,.20),"steel")
	_box(Vector3(-8.85,1.33,-5.4),Vector3(.032,.034,.28),"wood",Vector3(0,-.35,0))
	_box(Vector3(-8.80,1.35,-5.54),Vector3(.18,.07,.065),"steel_dark",Vector3(0,-.35,0))
	for index in 5: _cylinder(Vector3(-8.25+float(index)*.085,1.325,-5.6),.026,.05,"steel")

func _tool_chest() -> void:
	# Original chest footprint 1.8 x 1m; castors and handles stay inside it.
	_box(Vector3(-10.4,.67,-2.12),Vector3(1.76,.92,.94),"enamel_red")
	_box(Vector3(-10.4,1.16,-2.1),Vector3(1.8,.08,1.0),"steel_dark")
	for row in 5:
		var y := .34+float(row)*.16
		_box(Vector3(-10.4,y,-1.63),Vector3(1.65,.13,.035),"enamel_red")
		_box(Vector3(-10.4,y+.022,-1.603),Vector3(1.2,.022,.018),"steel")
	for x in [-11.12,-9.68]:
		for z in [-2.45,-1.75]:
			_cylinder(Vector3(x,.105,z),.10,.055,"rubber",Vector3(0,0,PI*.5))
			_box(Vector3(x,.19,z),Vector3(.045,.10,.09),"steel")

func _desk() -> void:
	_box(Vector3(8.4,1.245,0),Vector3(3.2,.11,1.5),"wood")
	for x in [7.05,9.75]:
		_box(Vector3(x,.61,0),Vector3(.12,1.18,1.30),"steel_dark")
	_box(Vector3(9.2,.75,0),Vector3(1.22,.84,1.26),"wood")
	for row in 3:
		_box(Vector3(9.2,.46+float(row)*.25,.65),Vector3(1.1,.21,.035),"wood")
		_box(Vector3(9.2,.49+float(row)*.25,.685),Vector3(.25,.025,.025),"steel")
	# Computer remains inside its original tagged .75 x .64 x .25m bounds.
	_box(Vector3(8.4,1.72,-.195),Vector3(.75,.48,.22),"plastic")
	_box(Vector3(8.4,1.72,-.061),Vector3(.67,.39,.008),"screen")
	_box(Vector3(8.4,1.41,-.18),Vector3(.065,.18,.10),"steel_dark")
	_box(Vector3(8.4,1.335,-.18),Vector3(.38,.03,.23),"plastic")
	_box(Vector3(8.4,1.33,.38),Vector3(.65,.045,.20),"plastic")
	for row in 3: _box(Vector3(8.4,1.355,.325+float(row)*.05),Vector3(.55,.008,.024),"steel_dark")
	_box(Vector3(9.3,1.34,.05),Vector3(.36,.075,.48),"wood")
	# Chair envelope exactly matches the original reserved .75 x .9 x .75m.
	_box(Vector3(8.4,.45,-2),Vector3(.69,.11,.65),"rubber")
	_box(Vector3(8.4,.69,-2.32),Vector3(.69,.42,.10),"rubber")
	_cylinder(Vector3(8.4,.23,-2),.045,.40,"steel")
	for angle in [0.0,PI*.5]: _box(Vector3(8.4,.075,-2),Vector3(.69,.045,.06),"steel_dark",Vector3(0,angle,0))
	for side in [-1.0,1.0]:
		for end in [-1.0,1.0]: _cylinder(Vector3(8.4+side*.28,.055,-2+end*.28),.05,.04,"rubber",Vector3(PI*.5,0,0))

func _lift() -> void:
	for side in [-1.0,1.0]:
		var x: float = side*2.1
		_box(Vector3(x,1.8,-3.5),Vector3(.46,3.6,.60),"enamel_red")
		_box(Vector3(x,1.85,-3.22),Vector3(.24,3.25,.035),"steel_dark")
		_cylinder(Vector3(x,1.78,-3.23),.033,2.80,"steel")
		_box(Vector3(x,.44,-3.22),Vector3(.36,.35,.035),"steel")
		_box(Vector3(x,.08,-3.5),Vector3(.9,.16,1.1),"steel_dark")
		for edge in [-1.0,1.0]:
			for end in [-1.0,1.0]: _cylinder(Vector3(x+edge*.33,.145,-3.5+end*.40),.035,.025,"steel")
		_box(Vector3(x,1.30,-3.21),Vector3(.22,.32,.012),"plastic")
		for button in 2: _cylinder(Vector3(x-.045+float(button)*.09,1.30,-3.195),.025,.012,"enamel_green",Vector3(PI*.5,0,0))

func _shelves() -> void:
	for index in 3:
		var x := 5.0+float(index)*2.1
		for side in [-1.0,1.0]:
			for end in [-1.0,1.0]: _box(Vector3(x+side*.855,1.1,-7.9+end*.405),Vector3(.07,2.2,.07),"steel_dark")
		for y in [.12,.78,1.44,2.14]:
			_box(Vector3(x,y,-7.9),Vector3(1.8,.065,.9),"steel")
			_box(Vector3(x,y,-7.465),Vector3(1.8,.10,.03),"enamel_green")
		if index == 0:
			for tier in 3:
				for side in [-1.0,1.0]:
					for pile in 3: _append(_tire_mesh,Vector3(x+side*.42,.25+float(tier)*.66+float(pile)*.17,-7.9),Vector3.ONE,"rubber")
		else:
			for tier in 3:
				var at := Vector3(x,.44+float(tier)*.66,-7.9)
				_box(at,Vector3(1.5,.42,.70),"wood")
				for side in [-1.0,1.0]: _box(at+Vector3(side*.58,0,.359),Vector3(.045,.42,.014),"steel_dark")
				_box(at+Vector3(0,.05,.36),Vector3(.31,.035,.02),"steel_dark")

func _material(kind: String) -> StandardMaterial3D:
	# Local fallback palette, replaced by DigoWorkshopMaterials via surface names.
	var palette := {"steel":"a7aba4","steel_dark":"3c4545","enamel_red":"9c4f39","enamel_green":"58695d","wood":"99764d","rubber":"242928","plastic":"303b3b","screen":"3d5960"}
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(str(palette[kind]))
	material.roughness = .82 if kind in ["wood","rubber","plastic"] else .53
	material.metallic = .65 if kind in ["steel","steel_dark"] else .08
	return material
