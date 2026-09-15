class_name MountainSkiFinishArch3D
extends Node3D

## Pórtico 3D de chegada de prova de ski alpino.
## Estrutura robusta com banner quadriculado de chegada, sensores de tempo
## e almofadas de proteção de impacto nas laterais.

func _ready() -> void:
	_build_arch()

func _build_arch() -> void:
	var dark := _mat(Color("1e262c"), 0.65)
	var red := _mat(Color("c4382a"), 0.70)
	var white := _mat(Color("edf2f4"), 0.55)
	var padding_mat := _mat(Color("3b749e"), 0.85)
	var display_mat := _mat(Color("3cd070"), 0.20, 0.0, 1.4)
	display_mat.emission_enabled = true
	display_mat.emission = Color("3cd070")

	# 1. Pilares verticais com almofadas de proteção
	for side in [-2.2, 2.2]:
		_box("Pylon_%s" % side, Vector3(side, 1.8, 0), Vector3(0.3, 3.6, 0.3), dark)
		# Almofada protetora de impacto
		_box("Pad_%s" % side, Vector3(side, 0.8, 0), Vector3(0.55, 1.5, 0.55), padding_mat)

	# 2. Travessa principal superior
	_box("FinishTruss", Vector3(0, 3.5, 0), Vector3(4.8, 0.35, 0.35), dark)

	# 3. Painel quadriculado de CHEGADA
	_box("BannerBase", Vector3(0, 3.0, 0), Vector3(4.2, 0.65, 0.08), dark)
	for i in range(8):
		var x := -1.75 + float(i) * 0.5
		var mat := red if i % 2 == 0 else white
		_box("Check_%d" % i, Vector3(x, 3.0, 0.045), Vector3(0.48, 0.6, 0.02), mat)

	# 4. Painel de cronometragem oficial
	_box("TimingHousing", Vector3(0, 3.85, 0), Vector3(1.6, 0.45, 0.25), dark)
	_box("TimingScreen", Vector3(0, 3.85, 0.13), Vector3(1.4, 0.32, 0.02), display_mat)

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
