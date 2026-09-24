extends Node3D
## A full 3D terrace table: joinery, crockery, cutlery, food, articulated guests
## and a folding eight-panel parasol. All motion is advanced by the nearby view.
const PARTS := preload("res://characters/pedestrians/CitizenDetails.gd")
const GUEST := preload("res://world/harbor/restaurants/RestaurantGuest3D.gd")
var guests: Array[Node3D] = []
var place_settings: Array[Node3D] = []
var canopy: Node3D
var opening := 0.0
var guest_progress := [0.0, 0.0]
var target_guests := 0
var clock := 0.0
var variant := 0
var built := false

func build(index := 0, fabric := Color("b66342")) -> void:
	if built: return
	built = true
	variant = index
	var wood := Color("986c44")
	var metal := Color("344540")
	_cylinder(self,.52,.075,Vector3(0,.75,0),wood)
	_cylinder(self,.49,.025,Vector3(0,.79,0),Color("c79e70"))
	for seam in [-.3,-.15,0,.15,.3]:
		var length := sqrt(.48*.48-seam*seam)*2.0
		_piece(self,Vector3(length,.003,.012),Vector3(0,.804,seam),wood.darkened(.2))
	_cylinder(self,.075,.68,Vector3(0,.36,0),metal)
	for angle in 4:
		var foot := _piece(self,Vector3(.48,.05,.045),Vector3.ZERO,metal)
		foot.rotation.y = angle*PI*.5
		foot.position = Vector3(cos(foot.rotation.y)*.18,.055,-sin(foot.rotation.y)*.18)
	# Chairs face each other across the table, with knees beneath the tabletop.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var chair := Node3D.new()
		chair.name = "BistroChair%d" % i
		chair.position.x = side*.86
		chair.rotation.y = side*PI*.5
		add_child(chair)
		_piece(chair,Vector3(.46,.055,.44),Vector3(0,.45,0),wood)
		for x in [-.185,.185]:
			for z in [-.17,.17]:
				_piece(chair,Vector3(.035,.44,.035),Vector3(x,.22,z),metal)
			_piece(chair,Vector3(.035,.50,.035),Vector3(x,.67,.20),metal)
		for y in [.61,.72,.83]:
			_piece(chair,Vector3(.40,.075,.038),Vector3(0,y,.20),wood)
		var guest := GUEST.new()
		guest.name = "DiningGuest%d" % i
		add_child(guest)
		guest.build(index*2+i)
		guest.position = chair.position
		guest.rotation.y = chair.rotation.y
		guest.hide()
		guests.append(guest)
		var setting := Node3D.new()
		setting.position.x = side*.31
		add_child(setting)
		_cylinder(setting,.155,.017,Vector3(0,.824,0),Color("f0e9d8"))
		_cylinder(setting,.115,.006,Vector3(0,.837,0),Color("dfd1b1"))
		_piece(setting,Vector3(.12,.035,.09),Vector3(-.025,.859,.01),Color("a45d30"),true)
		for leaf in 3:
			_piece(setting,Vector3(.055,.022,.048),Vector3(.043+leaf*.016,.851,-.035+leaf*.029),Color("72914a"),true)
		_piece(setting,Vector3(.08,.008,.12),Vector3(0,.82,.23),Color("e4cda8"))
		_piece(setting,Vector3(.014,.012,.14),Vector3(.105,.83,.235),Color("b8c6c7"))
		_cylinder(setting,.045,.115,Vector3(0,.871,-.22),Color("e8e3d7"))
		_cylinder(setting,.034,.006,Vector3(0,.931,-.22),Color("513022"))
		place_settings.append(setting)
	# Small glass bud vase and salt shaker occupy the centre away from plates.
	_cylinder(self,.036,.12,Vector3(.025,.869,.115),Color("638b81"))
	_piece(self,Vector3(.012,.18,.013),Vector3(.025,1.01,.115),Color("5c7850"))
	_piece(self,Vector3(.09,.06,.075),Vector3(.025,1.10,.115),Color("dfb66e"),true)
	_cylinder(self,.027,.07,Vector3(-.035,.856,-.11),Color("e0d9c8"))
	# Rear mounted pole keeps the diners and table centre unobstructed.
	_cylinder(self,.16,.045,Vector3(0,.024,-.42),Color("4a4b44"))
	_cylinder(self,.023,2.42,Vector3(0,1.23,-.42),Color("ddd3b1"))
	_piece(self,Vector3(.046,.046,.35),Vector3(0,2.34,-.255),Color("ddd3b1"))
	canopy = Node3D.new()
	canopy.name = "FoldingParasol"
	canopy.position = Vector3(0,2.34,-.1)
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
		var mesh := MeshInstance3D.new()
		mesh.mesh = surface.commit()
		var material := StandardMaterial3D.new()
		material.albedo_color = fabric if panel%2==0 else Color("e7d5b1")
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.roughness = .95
		mesh.material_override = material
		canopy.add_child(mesh)
		var rib := _piece(canopy,Vector3(.015,edge_a.length(),.015),edge_a*.5,Color("6a6556"))
		rib.quaternion = Quaternion(Vector3.UP,edge_a.normalized())
	_cylinder(canopy,.055,.075,Vector3(0,.022,0),Color("ddd3b1"))
	_set_opening(0.0)

static var _box_meshes: Dictionary = {}
static var _sphere_meshes: Dictionary = {}
static var _cylinder_meshes: Dictionary = {}
static var _materials: Dictionary = {}

static func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html(true)
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .8
	_materials[key] = material
	return material

static func _piece(parent: Node3D, size: Vector3, point: Vector3, color: Color, round_shape := false) -> MeshInstance3D:
	var key := "%s:%s" % [str(size), str(round_shape)]
	var mesh: Mesh
	if round_shape:
		if not _sphere_meshes.has(key):
			var sphere := SphereMesh.new()
			sphere.radius = .5
			sphere.height = 1.0
			sphere.radial_segments = 8
			sphere.rings = 4
			_sphere_meshes[key] = sphere
		mesh = _sphere_meshes[key]
	else:
		if not _box_meshes.has(key):
			var box := BoxMesh.new()
			box.size = size
			_box_meshes[key] = box
		mesh = _box_meshes[key]
	var part := MeshInstance3D.new()
	part.mesh = mesh
	if round_shape: part.scale = size
	part.position = point
	part.material_override = _material(color)
	parent.add_child(part)
	return part

func _cylinder(parent: Node3D, radius: float, height: float, point: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var key := "%s:%s" % [radius, height]
	if not _cylinder_meshes.has(key):
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = radius
		cylinder.bottom_radius = radius
		cylinder.height = height
		cylinder.radial_segments = 16
		_cylinder_meshes[key] = cylinder
	mesh.mesh = _cylinder_meshes[key]
	mesh.position = point
	mesh.material_override = _material(color)
	parent.add_child(mesh)
	return mesh

func set_conditions(count: int, rain: float, delta: float, snap := false) -> void:
	target_guests = clampi(count,0,2)
	clock += delta
	var umbrella_target := 1.0 if rain > .05 else 0.0
	_set_opening(umbrella_target if snap else move_toward(opening,umbrella_target,delta*.40))
	for i in 2:
		var wanted := 1.0 if i < target_guests else 0.0
		guest_progress[i] = wanted if snap else move_toward(guest_progress[i],wanted,delta/(3.1+i*.45))
		var progress := float(guest_progress[i])
		var guest: Node3D = guests[i]
		guest.visible = progress > .001
		# Approach from the façade, sit gradually; reverse on closing time.
		var sit := smoothstep(.68,1.0,progress)
		guest.position.z = lerpf(-1.15,0.0,minf(progress/.68,1.0))
		var seat_yaw := (-1.0 if i == 0 else 1.0)*PI*.5
		var walk_yaw := PI if wanted>progress else 0.0
		guest.rotation.y = lerp_angle(walk_yaw,seat_yaw,smoothstep(.48,.76,progress))
		guest.pose(clock,sit,progress > .01 and progress < .68)
		place_settings[i].visible = progress > .68

func _set_opening(value: float) -> void:
	opening = value
	canopy.scale = Vector3(lerpf(.065,1.0,value),lerpf(1.8,1.0,value),lerpf(.065,1.0,value))

func get_status() -> Dictionary:
	return {"guests":target_guests,"umbrella_open":opening>.95,"opening":opening,"activities":[guests[0].activity,guests[1].activity]}
