class_name MountainSkiStartArch3D
extends Node3D

## Pórtico 3D de largada de prova de ski alpino.
## Estrutura de madeira/aço com travessa superior, faixa de largada colorida
## da pista (Verde, Azul, Preta) e painel digital.

var course_color := Color("78a95c")

func _ready() -> void:
	_build_arch()

func set_course_color(col: Color) -> void:
	course_color = col
	for c in get_children():
		c.queue_free()
	_build_arch()

func _build_arch() -> void:
	var timber := _mat(Color("3b2b20"), 0.88)
	var banner_mat := _mat(course_color, 0.65)
	var white_mat := _mat(Color("e8edf0"), 0.55)
	var dark := _mat(Color("1b2024"), 0.70)
	var clock_display := _mat(Color("ff6622"), 0.20, 0.0, 1.4)
	clock_display.emission_enabled = true
	clock_display.emission = Color("ff6622")

	# 1. Pilares verticais de tora de madeira
	for side in [-1.8, 1.8]:
		_cylinder("Post_%s" % side, Vector3(side, 1.6, 0), 0.18, 3.2, timber)
		# Suporte de fixação na base de concreto/neve
		_box("Footing_%s" % side, Vector3(side, 0.1, 0), Vector3(0.5, 0.2, 0.5), dark)

	# 2. Travessa horizontal superior
	_box("HeaderBeam", Vector3(0, 3.1, 0), Vector3(4.0, 0.26, 0.26), timber)

	# 3. Painel / Faixa de largada com cor da pista
	_box("BannerBoard", Vector3(0, 2.7, 0), Vector3(3.4, 0.65, 0.08), banner_mat)
	# Listras brancas de competição
	for x in [-1.2, 1.2]:
		_box("Chevron_%s" % x, Vector3(x, 2.7, 0.045), Vector3(0.18, 0.55, 0.02), white_mat)

	# 4. Display de cronometragem
	_box("ClockHousing", Vector3(0, 3.45, 0), Vector3(1.2, 0.42, 0.22), dark)
	_box("ClockScreen", Vector3(0, 3.45, 0.115), Vector3(1.05, 0.32, 0.02), clock_display)

	# 5. Bandeirolas laterais
	for side in [-2.05, 2.05]:
		_cylinder("FlagPole_%s" % side, Vector3(side, 2.2, 0), 0.025, 2.8, dark)
		_box("FlagFabric_%s" % side, Vector3(side + (0.2 if side < 0 else -0.2), 2.9, 0), Vector3(0.42, 0.65, 0.02), banner_mat)

func _mat(color: Color, roughness: float, metallic := 0.0, emission := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m

func _box(name_str: String, point: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name_str
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = point
	node.material_override = material
	add_child(node)
	return node

func _cylinder(name_str: String, point: Vector3, radius: float, height: float, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name_str
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	node.mesh = mesh
	node.position = point
	node.material_override = material
	add_child(node)
	return node
