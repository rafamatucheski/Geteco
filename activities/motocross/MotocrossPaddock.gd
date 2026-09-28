extends Node3D
## Exterior rental hut and rest area. The hut is solid and has no accessible
## interior; the counter, parked bikes and seated riders stay off the race path.
const BIKE := preload("res://activities/motocross/MotocrossBike.gd")
var player: Node3D
var parked_bikes: Array[CharacterBody3D] = []
var drinkers: Array[Node3D] = []
var _materials: Dictionary = {}
var _batches: Dictionary = {}

func configure(actor: Node3D = null) -> void:
	player = actor

func _ready() -> void:
	name = "MotocrossPaddock"
	add_to_group("motocross_paddock")
	_build_hut()
	_build_seating()
	_flush(self)
	_build_parked_bikes()

func _build_hut() -> void:
	var timber := _finish_material(Color("826044"))
	var pale := _finish_material(Color("c6b998"))
	var dark := _material(Color("3d3b33"))
	var roof := _material(Color("576064"), 0.15)
	var red := _material(Color("a65132"))
	var center := Vector3(-234, 0.13, -35)
	# Full closed shell is collision-solid; no decorative open doorway implies
	# an interior that the player can accidentally enter or spawn inside.
	_box(Vector3(6.0, 2.65, 5.0), center + Vector3(0, 1.325, 0), pale)
	_solid("ClosedRentalHut", center + Vector3(0, 1.325, 0), Vector3(6.0, 2.65, 5.0))
	_box(Vector3(9.1, 0.12, 6.0), center + Vector3(1.4, -0.06, 0), dark)
	_solid("RentalDeck", center + Vector3(1.4, -0.06, 0), Vector3(9.1, 0.12, 6.0))
	for index in 13:
		var z := center.z - 2.4 + float(index) * 0.4
		_box(Vector3(0.035, 2.52, 0.035), Vector3(-230.98, 1.43, z), timber)
	for x in [-236.9, -231.1]:
		for z in [-37.4, -32.6]: _box(Vector3(0.18, 2.8, 0.18), Vector3(x, 1.52, z), timber)
	for side in [-1.0, 1.0]:
		_box(Vector3(6.8, 0.16, 3.14), center + Vector3(0, 3.09, side * 1.37), roof, Vector3(side * 0.30, 0, 0))
		for rib in 15:
			_box(Vector3(0.045, 0.05, 3.10), center + Vector3(-3.25 + float(rib) * 0.46, 3.18, side * 1.37), dark, Vector3(side * 0.30, 0, 0))
	_box(Vector3(6.9, 0.12, 0.16), center + Vector3(0, 3.53, 0), dark)
	# Closed shutter and framed side window: the service is on the porch.
	_box(Vector3(0.05, 1.05, 1.35), center + Vector3(3.03, 1.78, -0.35), dark)
	_box(Vector3(0.07, 0.06, 1.47), center + Vector3(3.065, 2.34, -0.35), timber)
	_box(Vector3(0.07, 0.06, 1.47), center + Vector3(3.065, 1.22, -0.35), timber)
	for z in [-1.06, 0.36]: _box(Vector3(0.07, 1.14, 0.06), center + Vector3(3.065, 1.78, z), timber)
	# Porch faces east, with its front edge at x=-227.2. ENTRY and the owned
	# motorcycle slot (-220,-40) remain unobstructed.
	_box(Vector3(3.8, 0.12, 5.8), Vector3(-229.15, 2.80, -35), roof, Vector3(0, 0, -0.08))
	for z in [-37.6, -32.4]:
		_box(Vector3(0.14, 2.65, 0.14), Vector3(-227.35, 1.455, z), timber)
		_solid("PorchPost", Vector3(-227.35, 1.455, z), Vector3(0.14, 2.65, 0.14))
	_box(Vector3(0.64, 0.98, 2.65), Vector3(-228.35, 0.62, -35.05), timber)
	_box(Vector3(0.91, 0.09, 2.86), Vector3(-228.35, 1.155, -35.05), dark)
	_solid("RentalCounter", Vector3(-228.35, 0.67, -35.05), Vector3(0.91, 1.08, 2.86))
	# Helmets and a pair of gloves identify the rental counter visually.
	_helmet(self, Vector3(-228.30, 1.42, -34.18), red)
	_box(Vector3(0.14, 0.055, 0.21), Vector3(-228.40, 1.23, -35.70), dark)
	_box(Vector3(0.14, 0.055, 0.21), Vector3(-228.20, 1.23, -35.65), dark, Vector3(0, 0.3, 0))
	_flush(self)
	var vendor := _person(Vector3(-229.6, 0.13, -35.0), -PI / 2.0, Color("a94e2e"), false)
	vendor.name = "RentalKeeper"
	var sign := Label3D.new()
	sign.text = "VÉRTICE"
	sign.font_size = 54
	sign.pixel_size = 0.013
	sign.modulate = Color("f1e0b9")
	sign.outline_size = 5
	sign.position = Vector3(-227.17, 2.46, -35)
	sign.rotation.y = PI / 2.0
	add_child(sign)

func _build_seating() -> void:
	var wood := _finish_material(Color("805434"))
	var frame := _material(Color("363c38"), 0.2)
	var center := Vector3(-233.5, 0.13, -28)
	_box(Vector3(3.1, 0.12, 1.25), center + Vector3(0, 0.78, 0), wood)
	_solid("PicnicTable", center + Vector3(0, 0.43, 0), Vector3(3.1, 0.86, 1.25))
	for x in [-1.12, 1.12]:
		for z in [-0.45, 0.45]: _box(Vector3(0.10, 0.74, 0.10), center + Vector3(x, 0.37, z), frame)
	for side in [-1.0, 1.0]:
		var bench := center + Vector3(0, 0.45, side * 1.10)
		_box(Vector3(3.15, 0.09, 0.46), bench, wood)
		_solid("RiderBench", bench - Vector3(0, 0.23, 0), Vector3(3.15, 0.55, 0.46))
		for x in [-1.14, 1.14]: _box(Vector3(0.11, 0.43, 0.36), bench + Vector3(x, -0.23, 0), frame)
	_flush(self)
	var seats := [Vector3(-234.28, 0.13, -26.90), Vector3(-232.75, 0.13, -26.90), Vector3(-233.52, 0.13, -29.10)]
	var colors := [Color("d57627"), Color("356f9e"), Color("a94338")]
	for index in seats.size():
		var actor := _person(seats[index], 0.0 if index < 2 else PI, colors[index], true)
		actor.name = "RestingMotocrossRider%d" % index
		drinkers.append(actor)
	_helmet(self, center + Vector3(-1.14, 1.04, 0), _material(colors[1]))
	_helmet(self, center + Vector3(1.05, 1.04, 0.05), _material(colors[0]))
	_helmet(self, center + Vector3(1.19, 0.69, -1.10), _material(colors[2]))
	_bottle(center + Vector3(-0.30, 0.85, 0.28))
	_bottle(center + Vector3(0.38, 0.85, -0.20))
	_box(Vector3(0.70, 0.46, 0.48), center + Vector3(2.2, 0.23, 0.05), _material(Color("597069")))
	_box(Vector3(0.74, 0.08, 0.51), center + Vector3(2.2, 0.49, 0.05), _material(Color("e4dfc6")))
	_solid("RiderCooler", center + Vector3(2.2, 0.26, 0.05), Vector3(0.74, 0.54, 0.51))

func _build_parked_bikes() -> void:
	for index in 3:
		var bike := BIKE.new()
		bike.name = "RentalMotocross%d" % index
		preload("res://activities/motocross/MotocrossModels.gd").apply(bike,index)
		bike.position = Vector3(-214, 0.13, -36.0 + float(index) * 4.0)
		bike.rotation.y = PI / 2.0
		bike.race_enabled = false
		add_child(bike)
		bike.set_physics_process(false)
		bike.rider.hide()
		bike.visual.rotation.z = -0.12
		parked_bikes.append(bike)
		_bar(bike.position + Vector3(0, 0.12, 0.22), bike.position + Vector3(0, 0.04, 0.45), 0.025, _material(Color("3a3d39")))
	_flush(self)

func _person(at: Vector3, yaw: float, color: Color, seated: bool) -> Node3D:
	var actor := preload("res://activities/motocross/MotocrossSpectator.gd").new()
	actor.configure({"identity":drinkers.size()+int(not seated)*5,"jersey":color,"seated":seated,"seat_height":.495,"drinking":seated,"deck":self,"bounds":Rect2(-238,-32,10,9) if seated else Rect2(-230.9,-37.6,3.7,5.2)})
	actor.position = at
	actor.rotation.y = yaw
	add_child(actor)
	return actor

func _helmet(parent: Node3D, at: Vector3, material: Material) -> void:
	# Caller batches all non-animated props into the paddock mesh.
	_ellipsoid(at, Vector3(0.23, 0.22, 0.25), material)
	_box(Vector3(0.33, 0.12, 0.065), at + Vector3(0, 0.02, -0.23), _material(Color("202a29")))
	_box(Vector3(0.36, 0.035, 0.23), at + Vector3(0, 0.15, -0.22), material)
	_box(Vector3(0.22, 0.08, 0.13), at + Vector3(0, -0.12, -0.25), material)

func _bottle(base: Vector3) -> void:
	var glass := _material(Color("5d3c1b"), 0.15)
	_bar(base + Vector3(0, 0.02, 0), base + Vector3(0, 0.21, 0), 0.043, glass)
	_bar(base + Vector3(0, 0.20, 0), base + Vector3(0, 0.32, 0), 0.024, glass)
	_bar(base + Vector3(0, 0.085, 0), base + Vector3(0, 0.16, 0), 0.044, _material(Color("d6bb76")))

func _material(color: Color, metallic: float = 0.0) -> StandardMaterial3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.85
		material.metallic = metallic
		_materials[color] = material
	return _materials[color]

func _finish_material(color: Color) -> ShaderMaterial:
	var key := color.to_html()+"wood"
	if not _materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = preload("res://activities/motocross/MotocrossFinish.gdshader")
		material.set_shader_parameter("base_color",color)
		_materials[key] = material
	return _materials[key]

func _solid(title: String, at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = title
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)

func _box(size: Vector3, at: Vector3, material: Material, angles := Vector3.ZERO) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_batch(mesh, Transform3D(Basis.from_euler(angles), at), material)

func _ellipsoid(at: Vector3, radii: Vector3, material: Material) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 10
	mesh.rings = 6
	_batch(mesh, Transform3D(Basis.from_scale(radii), at), material)

func _bar(a: Vector3, b: Vector3, radius: float, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 8
	var direction := (b - a).normalized()
	var rotation_axis := Vector3.UP.cross(direction)
	var basis := Basis.IDENTITY
	if rotation_axis.length_squared() > 0.0001:
		basis = Basis(rotation_axis.normalized(), acos(clampf(Vector3.UP.dot(direction), -1.0, 1.0)))
	_batch(mesh, Transform3D(basis, (a + b) * 0.5), material)

func _batch(mesh: PrimitiveMesh, where: Transform3D, material: Material) -> void:
	if not _batches.has(material):
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		builder.set_material(material)
		_batches[material] = builder
	var source := ArrayMesh.new()
	source.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.get_mesh_arrays())
	var surface: SurfaceTool = _batches[material]
	surface.append_from(source, 0, where)

func _flush(parent: Node3D) -> void:
	for material in _batches:
		var mesh := MeshInstance3D.new()
		var builder: SurfaceTool = _batches[material]
		mesh.mesh = builder.commit()
		mesh.material_override = material
		parent.add_child(mesh)
	_batches.clear()
