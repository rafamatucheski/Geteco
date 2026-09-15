extends Node3D
## A freestanding job board in Maciota's office, built in workshop metres.
func _ready() -> void:
	var steel := _material(Color("384247"), .65)
	var wood := _material(Color("805b39"), .92)
	var slate := _material(Color("253b35"), .97)
	var paper := _material(Color("e7dfc3"), 1.0)
	var ink := _material(Color("526b70"), 1.0)
	var brass := _material(Color("cea453"), .65)
	for x in [-.95, .95]:
		_box(self, Vector3(x, .06, 0), Vector3(.16, .12, .62), steel)
		_box(self, Vector3(x, .65, 0), Vector3(.07, 1.25, .07), steel)
	_box(self, Vector3(0, .38, 0), Vector3(1.95, .065, .065), steel)
	var face := Node3D.new()
	face.name = "PinnedJobs"
	face.position.y = 1.38
	face.rotation.x = -.16
	add_child(face)
	_box(face, Vector3.ZERO, Vector3(2.18, 1.35, .10), wood)
	_box(face, Vector3(0, 0, .061), Vector3(2.02, 1.19, .024), slate)
	for x in [-1.05, 1.05]:
		_box(face, Vector3(x, 0, .075), Vector3(.055, 1.31, .03), brass)
	for y in [-.64, .64]:
		_box(face, Vector3(0, y, .075), Vector3(2.12, .055, .03), brass)
	# Pinned route sketches and car photographs communicate contracts without
	# extra decorative labels. The existing localized interaction opens the UI.
	for index in 3:
		var page := Node3D.new()
		page.position = Vector3(-.65 + index * .65, .14, .092)
		page.rotation.z = [-.06, .035, -.025][index]
		face.add_child(page)
		_box(page, Vector3.ZERO, Vector3(.52, .69, .012), paper)
		_box(page, Vector3(0, .06, .012), Vector3(.41, .27, .008), ink)
		var car_color := _material([Color("c58f47"), Color("b7c4bd"), Color("ad5750")][index], .8)
		_box(page, Vector3(0, .035, .021), Vector3(.31, .075, .008), car_color)
		_box(page, Vector3(-.02, .09, .021), Vector3(.16, .07, .008), car_color)
		for x in [-.105, .105]: _box(page, Vector3(x, -.008, .027), Vector3(.055, .04, .008), steel)
		for row in 3:
			_box(page, Vector3(-.025, -.16 - row * .055, .012), Vector3(.30 - row * .05, .013, .006), ink)
		_pin(page, Vector3(0, .285, .021), Color("cf5946") if index != 1 else Color("d5b65b"))
	for index in 3:
		_box(face, Vector3(-.72 + index * .66, -.40, .10), Vector3(.35, .11, .014), _material(Color("d1b85d"), 1.0))
		_box(face, Vector3(-.72 + index * .66, -.40, .112), Vector3(.22, .012, .006), ink)
	_box(face, Vector3(0, -.69, .15), Vector3(2.12, .055, .26), steel)
	_box(face, Vector3(.62, -.65, .19), Vector3(.22, .06, .10), wood)
	_box(face, Vector3(.18, -.65, .18), Vector3(.18, .025, .025), paper)

func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material

func _box(parent: Node3D, point: Vector3, size: Vector3, material: Material) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = BoxMesh.new()
	instance.mesh.size = size
	instance.material_override = material
	instance.position = point
	parent.add_child(instance)

func _pin(parent: Node3D, point: Vector3, color: Color) -> void:
	var pin := MeshInstance3D.new()
	pin.mesh = SphereMesh.new()
	pin.mesh.radius = .025
	pin.mesh.height = .05
	pin.mesh.radial_segments = 8
	pin.mesh.rings = 4
	pin.position = point
	pin.material_override = _material(color, .6)
	parent.add_child(pin)
