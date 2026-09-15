extends Node3D
## Reusable intercity coach. Local +Z is the nose, floor at Y=0.
## Set livery / operator_name before adding it to the scene.
const DOOR_Z := 5.05 # Ahead of the front axle.
var livery := Color("197f88")
var operator_name := "COSTA SUL"
var fleet_number := "2407"

func _ready() -> void:
	var ivory := _mat(Color("bdbbb1"))
	var paint := _mat(livery)
	var dark := _mat(Color("172c37"), 0.28)
	var rubber := _mat(Color("172026"))
	var metal := _mat(Color("839196"), 0.35)
	var white := _mat(Color("ffeac1"), 0.25, true)
	var red := _mat(Color("ed503b"), 0.3, true)
	_box(Vector3(0, 1.54, 0), Vector3(2.55, 2.58, 11.50), ivory)
	_box(Vector3(0, 2.92, -0.1), Vector3(2.53, 0.66, 10.96), dark)
	_box(Vector3(0, 3.33, -0.1), Vector3(2.58, 0.19, 11.15), ivory)
	_box(Vector3(0, 0.67, 0), Vector3(2.59, 0.36, 11.60), paint)
	_box(Vector3(0, 2.20, 0), Vector3(2.60, 0.26, 11.56), paint)
	# Glazed coach front, low bumper, destination panel and paired lamps.
	_box(Vector3(0, 2.56, 5.77), Vector3(2.32, 1.15, 0.06), dark)
	_box(Vector3(0, 3.05, 5.82), Vector3(1.92, 0.26, 0.05), rubber)
	_box(Vector3(0, 1.49, 5.79), Vector3(2.51, 0.36, 0.06), paint)
	_box(Vector3(0, 0.35, 5.85), Vector3(2.60, 0.19, 0.15), metal)
	_box(Vector3(0, 0.76, 5.84), Vector3(0.95, 0.32, 0.07), dark)
	for side in [-1.0, 1.0]:
		_box(Vector3(side * 0.94, 1.12, 5.82), Vector3(0.45, 0.26, 0.08), white)
		_box(Vector3(side * 1.0, 1.70, -5.78), Vector3(0.23, 0.62, 0.07), red)
		_box(Vector3(side * 1.34, 2.66, 5.24), Vector3(0.13, 0.12, 0.62), metal)
		_box(Vector3(side * 1.49, 2.66, 5.45), Vector3(0.25, 0.44, 0.30), dark)
		# Pillars interrupt the long dark window ribbon.
		for i in 8:
			_box(Vector3(side * 1.286, 2.89, -4.72 + i * 1.32), Vector3(0.05, 0.77, 0.10), ivory)
		for z in [-3.60, -2.45, 3.82]:
			_wheel(Vector3(side * 1.27, 0.60, z), rubber, metal)
		for i in 4:
			_box(Vector3(side * 1.30, 1.45, -1.3 + i * 1.12), Vector3(0.02, 0.74, 0.025), metal)
		_box(Vector3(side * 1.31, 1.79, 0.45), Vector3(0.018, 0.035, 4.4), metal)
		for i in 5:
			_box(Vector3(side * 1.30, 1.11 + i * 0.12, -4.87), Vector3(0.025, 0.035, 1.04), dark)
		var brand := _text(operator_name, Vector3(side * 1.315, 1.64, -0.1), 58, Color("f8f1d9"))
		brand.rotation.y = side * PI / 2.0
	# Right-side boarding door has glazing, step and metal jambs.
	_box(Vector3(-1.32, 1.48, DOOR_Z), Vector3(0.07, 2.24, 1.15), dark)
	_box(Vector3(-1.37, 0.39, DOOR_Z), Vector3(0.19, 0.13, 1.19), metal)
	_box(Vector3(-1.36, 1.51, DOOR_Z), Vector3(0.035, 2.10, 0.055), metal)
	_box(Vector3(0, 3.56, -1.70), Vector3(1.83, 0.30, 2.72), ivory)
	for i in 6:
		_box(Vector3(0, 3.72, -2.68 + i * 0.37), Vector3(1.53, 0.025, 0.10), metal)
	_text("HARBOR", Vector3(0, 3.05, 5.86), 40, Color("ffdc84"))
	_text(fleet_number, Vector3(0.55, 1.73, 5.84), 33, Color("193d4b"))
	var rear := _text(operator_name, Vector3(0, 2.00, -5.82), 43, livery)
	rear.rotation.y = PI

func _mat(color: Color, roughness := 0.75, glow := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.emission_enabled = glow
	material.emission = color
	material.emission_energy_multiplier = 0.30
	return material

func _box(pos: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = pos
	add_child(mesh)
	return mesh

func _wheel(pos: Vector3, rubber: Material, metal: Material) -> void:
	for layer in 2:
		var wheel := MeshInstance3D.new()
		var shape := CylinderMesh.new()
		shape.top_radius = 0.58 if layer == 0 else 0.31
		shape.bottom_radius = shape.top_radius
		shape.height = 0.25 if layer == 0 else 0.27
		shape.radial_segments = 16
		wheel.mesh = shape
		wheel.material_override = rubber if layer == 0 else metal
		wheel.position = pos
		wheel.rotation.z = PI / 2.0
		add_child(wheel)

func _text(value: String, pos: Vector3, font_size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = value
	label.font_size = font_size
	label.pixel_size = 0.005
	label.modulate = color
	label.outline_size = 0
	label.position = pos
	add_child(label)
	return label
