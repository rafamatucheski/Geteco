extends Node3D
## Static native counterpart of the productive V1 restaurant terrace.
## Scheduling/guests remain an external routine contract; this model keeps the
## six authored anchors visually and physically complete without callbacks.

var venue_id := ""
var table_index := 0
var fabric := Color("b96a46")

static var _materials: Dictionary = {}
static var _boxes: Dictionary = {}
static var _cylinders: Dictionary = {}

func configure(id: String, index: int, color: Color) -> void:
	venue_id = id
	table_index = index
	fabric = color

func _ready() -> void:
	name = "%sTable%d" % [venue_id.to_pascal_case(),table_index+1]
	set_meta("source_id","world/harbor/restaurants/HarborRestaurantLife.gd")
	set_meta("venue_id",venue_id)
	_build()

func _build() -> void:
	var wood := Color("986c44")
	var metal := Color("344540")
	_cylinder("TableTop",.52,.075,Vector3(0,.75,0),wood)
	_cylinder("TableInset",.49,.025,Vector3(0,.80,0),Color("c79e70"))
	_cylinder("TablePedestal",.075,.68,Vector3(0,.36,0),metal)
	for angle in 4:
		var yaw := float(angle)*PI*.5
		var foot := _box("TableFoot",Vector3(.48,.05,.045),Vector3(cos(yaw)*.18,.055,-sin(yaw)*.18),metal)
		foot.rotation.y = yaw
	for chair_index in 2:
		var side := -1.0 if chair_index==0 else 1.0
		var chair := Node3D.new()
		chair.name = "BistroChair%d"%chair_index
		chair.position.x = side*.86
		chair.rotation.y = side*PI*.5
		add_child(chair)
		_box_at(chair,"ChairSeat",Vector3(.46,.055,.44),Vector3(0,.45,0),wood)
		for x in [-.185,.185]:
			for z in [-.17,.17]: _box_at(chair,"ChairLeg",Vector3(.035,.44,.035),Vector3(x,.22,z),metal)
			_box_at(chair,"ChairBackPost",Vector3(.035,.50,.035),Vector3(x,.67,.20),metal)
		for y in [.61,.72,.83]: _box_at(chair,"ChairBackSlat",Vector3(.40,.075,.038),Vector3(0,y,.20),wood)
		var setting_x := side*.31
		_cylinder("Plate",.155,.017,Vector3(setting_x,.824,0),Color("f0e9d8"))
		_cylinder("FoodPlate",.115,.006,Vector3(setting_x,.837,0),Color("dfd1b1"))
		_box("Meal",Vector3(.12,.035,.09),Vector3(setting_x-.025,.859,.01),Color("a45d30"))
		_box("Napkin",Vector3(.08,.008,.12),Vector3(setting_x,.82,.23),Color("e4cda8"))
		_box("Cutlery",Vector3(.014,.012,.14),Vector3(setting_x+.105,.83,.235),Color("b8c6c7"))
		_cylinder("Glass",.045,.115,Vector3(setting_x,.871,-.22),Color("e8e3d7"))
	_cylinder("BudVase",.036,.12,Vector3(.025,.869,.115),Color("638b81"))
	_box("FlowerStem",Vector3(.012,.18,.013),Vector3(.025,1.01,.115),Color("5c7850"))
	_box("Flower",Vector3(.09,.06,.075),Vector3(.025,1.10,.115),Color("dfb66e"))
	_cylinder("ParasolBase",.16,.045,Vector3(0,.024,-.42),Color("4a4b44"))
	_cylinder("ParasolPole",.023,2.42,Vector3(0,1.23,-.42),Color("ddd3b1"))
	_build_parasol(Vector3(0,2.34,-.10))
	_build_collision()

func _build_parasol(origin: Vector3) -> void:
	var canopy := Node3D.new()
	canopy.name = "Parasol"
	canopy.position = origin
	add_child(canopy)
	for panel in 8:
		var a := float(panel)*TAU/8.0
		var b := float(panel+1)*TAU/8.0
		var edge_a := Vector3(cos(a)*1.30,-.34,sin(a)*1.30)
		var edge_b := Vector3(cos(b)*1.30,-.34,sin(b)*1.30)
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for vertex in [Vector3.ZERO,edge_b,edge_a,edge_a,edge_b,edge_b-Vector3(0,.11,0),edge_a,edge_b-Vector3(0,.11,0),edge_a-Vector3(0,.11,0)]:
			surface.add_vertex(vertex)
		surface.generate_normals()
		var part := MeshInstance3D.new()
		part.name = "CanopyPanel"
		part.mesh = surface.commit()
		part.material_override = _material(fabric if panel%2==0 else Color("e7d5b1"))
		canopy.add_child(part)

func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "TerraceFurnitureSolid"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	_add_shape(body,Vector3(0,.48,0),Vector3(1.05,.96,1.05))
	_add_shape(body,Vector3(-.86,.48,0),Vector3(.48,.96,.52))
	_add_shape(body,Vector3(.86,.48,0),Vector3(.48,.96,.52))

func _add_shape(body: StaticBody3D, point: Vector3, size: Vector3) -> void:
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.position = point
	collider.shape = shape
	body.add_child(collider)

func _box(label: String, size: Vector3, point: Vector3, color: Color) -> MeshInstance3D:
	return _box_at(self,label,size,point,color)

func _box_at(parent: Node3D, label: String, size: Vector3, point: Vector3, color: Color) -> MeshInstance3D:
	var key := str(size)
	if not _boxes.has(key):
		var resource := BoxMesh.new()
		resource.size = size
		_boxes[key] = resource
	var result := MeshInstance3D.new()
	result.name = label
	result.mesh = _boxes[key]
	result.position = point
	result.material_override = _material(color)
	parent.add_child(result)
	return result

func _cylinder(label: String, radius: float, height: float, point: Vector3, color: Color) -> MeshInstance3D:
	var key := "%s:%s"%[radius,height]
	if not _cylinders.has(key):
		var resource := CylinderMesh.new()
		resource.top_radius = radius
		resource.bottom_radius = radius
		resource.height = height
		resource.radial_segments = 12
		_cylinders[key] = resource
	var result := MeshInstance3D.new()
	result.name = label
	result.mesh = _cylinders[key]
	result.position = point
	result.material_override = _material(color)
	add_child(result)
	return result

static func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html(true)
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = .84
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[key] = material
	return _materials[key]
