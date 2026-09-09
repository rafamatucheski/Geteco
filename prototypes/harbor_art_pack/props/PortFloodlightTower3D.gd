class_name PortFloodlightTower3D
extends Node3D

## Torre de iluminação portuária de 4,50m (Port Floodlight Tower).
## Base de concreto com flange de aço, mastro tubular, escada de serviço com degraus e dois refletores industriais halógenos direcionados para a área de carga.
## Dimensões: 1.40m largura x 4.50m altura x 0.90m profundidade.
## Origem no piso Y=0, centrado em X e Z.

const WIDTH: float = 1.40
const HEIGHT: float = 4.50
const DEPTH: float = 0.90

var _obstacle_bounds: Array[AABB] = []
var _is_built: bool = false

func _ready() -> void:
	if not _is_built:
		_build_model()

func get_dimensions() -> Vector3:
	return Vector3(WIDTH, HEIGHT, DEPTH)

func get_obstacle_bounds() -> Array[AABB]:
	if not _is_built:
		_build_model()
	return _obstacle_bounds.duplicate()

func _build_model() -> void:
	_is_built = true
	_obstacle_bounds.clear()
	# Bound principal da base
	_obstacle_bounds.append(AABB(Vector3(-0.45, 0.0, -0.45), Vector3(0.90, HEIGHT, 0.90)))

	var mat_mast := PortArtMaterials.steel_dark()
	var mat_hardware := PortArtMaterials.steel_galvanized()
	var mat_housing := PortArtMaterials.floodlight_casing()
	var mat_emissive := PortArtMaterials.floodlight_emission()
	var mat_concrete := PortArtMaterials.get_mat("concrete_base", Color("#7f8c8d"), 0.05, 0.90)

	# 1. Base cúbica de concreto anti-impacto
	_box(Vector3(0.0, 0.20, 0.0), Vector3(0.70, 0.40, 0.70), mat_concrete)

	# Flange de aço e mão-francesa / aletas de reforço
	_box(Vector3(0.0, 0.41, 0.0), Vector3(0.55, 0.03, 0.55), mat_mast)
	for a in [0.0, 90.0, 180.0, 270.0]:
		var gusset := _box(Vector3(0.0, 0.55, 0.0), Vector3(0.03, 0.25, 0.20), mat_mast)
		gusset.rotation_degrees.y = a

	# 2. Mastro tubular vertical principal (Y=0.40m até Y=4.40m)
	_cyl(Vector3(0.0, 2.40, 0.0), 0.09, 4.00, mat_mast)

	# 3. Degraus da escada de serviço na face traseira (-Z)
	for li in range(14):
		var rung_y := 0.65 + float(li) * 0.26
		_cyl(Vector3(0.0, rung_y, -0.16), 0.012, 0.32, mat_hardware, Vector3(0, 0, 90))
		# Suportes laterais do degrau
		_box(Vector3(-0.16, rung_y, -0.10), Vector3(0.02, 0.02, 0.12), mat_hardware)
		_box(Vector3(0.16, rung_y, -0.10), Vector3(0.02, 0.02, 0.12), mat_hardware)

	# 4. Travessa / Cruzezeta superior de iluminação (Y=4.25m)
	_box(Vector3(0.0, 4.25, 0.0), Vector3(1.30, 0.08, 0.08), mat_mast)
	_cyl(Vector3(0.0, 4.45, 0.0), 0.02, 0.40, mat_hardware) # Para-raios no topo

	# 5. Dois refletores industriais duplos apontados para frente (+Z) e inclinados para o solo
	for lx in [-0.45, 0.45]:
		# Haste de articulação do refletor
		_box(Vector3(lx, 4.15, 0.08), Vector3(0.04, 0.14, 0.04), mat_mast)

		# Caixa do refletor inclinada em 35 graus
		var head_root := Node3D.new()
		head_root.position = Vector3(lx, 4.08, 0.12)
		head_root.rotation_degrees.x = 35.0
		add_child(head_root)

		# Carcaça traseira
		_box_child(head_root, Vector3(0.0, 0.0, 0.0), Vector3(0.36, 0.26, 0.18), mat_housing)
		# Viseira e lente emissiva brilhante
		_box_child(head_root, Vector3(0.0, 0.0, 0.09), Vector3(0.38, 0.28, 0.02), mat_housing)
		_box_child(head_root, Vector3(0.0, 0.0, 0.095), Vector3(0.32, 0.22, 0.01), mat_emissive)

func _box(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi

func _box_child(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi

func _cyl(pos: Vector3, radius: float, height: float, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 14
	mi.mesh = cm
	mi.position = pos
	if rot_deg != Vector3.ZERO:
		mi.rotation_degrees = rot_deg
	mi.material_override = mat
	add_child(mi)
	return mi
