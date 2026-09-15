class_name MountainChairliftTower3D
extends Node3D

## Torre tubular de teleférico alpino em 3D.
## Inclui fundação de concreto, mastro de aço, escada de serviço,
## braço transversal com baterias de roldanas e sinalizador de topo.

var tower_number := 1
var is_lit := false
var beacon_light: OmniLight3D
var beacon_mesh: MeshInstance3D

func _ready() -> void:
	_build_tower()

func set_tower_number(num: int) -> void:
	tower_number = num

func set_lit(lit: bool) -> void:
	is_lit = lit
	if is_instance_valid(beacon_light):
		beacon_light.visible = lit
	if is_instance_valid(beacon_mesh) and beacon_mesh.material_override is StandardMaterial3D:
		var mat := beacon_mesh.material_override as StandardMaterial3D
		mat.emission_energy_multiplier = 2.5 if lit else 0.2

func _build_tower() -> void:
	var concrete := _mat(Color("585c60"), 0.95)
	var galvanized := _mat(Color("637078"), 0.45, 0.65)
	var dark_steel := _mat(Color("262f36"), 0.60, 0.50)
	var sheave_rubber := _mat(Color("181d22"), 0.85)
	var yellow := _mat(Color("d9a738"), 0.50)
	var beacon_mat := _mat(Color("ff4433"), 0.2, 0.0, 1.0)
	beacon_mat.emission_enabled = true
	beacon_mat.emission = Color("ff4433")

	# 1. Fundação de concreto
	_box("ConcreteBase", Vector3(0, 0.25, 0), Vector3(1.8, 0.5, 1.8), concrete)

	# 2. Mastro principal (coluna tubular cilíndrica)
	_cylinder("PylonBase", Vector3(0, 2.5, 0), 0.42, 4.0, galvanized)
	_cylinder("PylonTop", Vector3(0, 6.0, 0), 0.35, 3.5, galvanized)

	# 3. Escada de serviço vertical
	for h in range(1, 8):
		_box("LadderRung_%d" % h, Vector3(0.38, float(h), 0), Vector3(0.08, 0.04, 0.45), dark_steel)
	_box("LadderRailLeft", Vector3(0.38, 4.0, -0.22), Vector3(0.04, 7.5, 0.04), dark_steel)
	_box("LadderRailRight", Vector3(0.38, 4.0, 0.22), Vector3(0.04, 7.5, 0.04), dark_steel)

	# 4. Plataforma de serviço e guarda-corpo
	_box("PlatformFloor", Vector3(0, 7.4, 0), Vector3(1.4, 0.1, 1.4), dark_steel)
	for side in [-0.65, 0.65]:
		_box("RailZ_%s" % side, Vector3(0, 8.0, side), Vector3(1.4, 0.05, 0.05), yellow)
		_box("RailX_%s" % side, Vector3(side, 8.0, 0), Vector3(0.05, 0.05, 1.4), yellow)

	# 5. Braço transversal (Crossarm)
	_box("CrossarmMain", Vector3(0, 7.8, 0), Vector3(0.45, 0.45, 4.8), galvanized)
	for z in [-1.5, 1.5]:
		_box("CrossarmBrace_%s" % z, Vector3(0, 7.2, z * 0.5), Vector3(0.25, 0.8, 0.25), galvanized, Vector3(z * 18.0, 0, 0))

	# 6. Baterias de roldanas (sheaves / polias) de sustentação de cabo
	for side in [-2.1, 2.1]:
		# Suporte da bateria
		_box("SheaveMount_%s" % side, Vector3(0, 7.95, side), Vector3(0.9, 0.14, 0.22), dark_steel)
		# 4 roldanas alinhadas por lado
		for s in range(4):
			var offset_x := (float(s) - 1.5) * 0.24
			var sheave := MeshInstance3D.new()
			var c := CylinderMesh.new()
			c.top_radius = 0.14
			c.bottom_radius = 0.14
			c.height = 0.08
			c.radial_segments = 14
			sheave.mesh = c
			sheave.position = Vector3(offset_x, 7.95, side)
			sheave.rotation_degrees = Vector3(90, 0, 0)
			sheave.material_override = sheave_rubber
			add_child(sheave)

	# 7. Sinalizador luminoso de topo (aviso aeronáutico e iluminação noturna)
	beacon_mesh = _box("TopBeacon", Vector3(0, 8.4, 0), Vector3(0.2, 0.35, 0.2), beacon_mat)
	beacon_light = OmniLight3D.new()
	beacon_light.position = Vector3(0, 8.6, 0)
	beacon_light.light_color = Color("ff5533")
	beacon_light.light_energy = 1.8
	beacon_light.omni_range = 14.0
	beacon_light.visible = is_lit
	add_child(beacon_light)

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

func _box(name_str: String, point: Vector3, size: Vector3, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name_str
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = point
	node.rotation_degrees = rotation
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
	mesh.radial_segments = 14
	node.mesh = mesh
	node.position = point
	node.material_override = material
	add_child(node)
	return node
