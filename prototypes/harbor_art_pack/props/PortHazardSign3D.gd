class_name PortHazardSign3D
extends Node3D

## Cavalete de sinalização de segurança e advertência portuária (Hazard Sign).
## Placa com faixas zebradas de perigo (preto e amarelo segurança) e armação tubular dobrável.
## Dimensões: 0.75m largura x 0.90m altura x 0.45m profundidade aberta.
## Origem no piso Y=0, centrado em X e Z.

const WIDTH: float = 0.75
const HEIGHT: float = 0.90
const DEPTH: float = 0.45

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
	_obstacle_bounds.append(AABB(Vector3(-WIDTH * 0.5, 0.0, -DEPTH * 0.5), Vector3(WIDTH, HEIGHT, DEPTH)))

	var mat_yellow := PortArtMaterials.safety_yellow()
	var mat_black := PortArtMaterials.hazard_black()
	var mat_frame := PortArtMaterials.steel_dark()
	var mat_hinge := PortArtMaterials.steel_galvanized()

	var half_w := WIDTH * 0.5

	# 1. Pés tubulares em 'A' (pernas dianteiras e traseiras)
	for side_x in [-half_w + 0.05, half_w - 0.05]:
		# Perna frontal inclinada para frente
		var leg_f := _cyl(Vector3(side_x, HEIGHT * 0.48, 0.09), 0.015, HEIGHT, mat_frame)
		leg_f.rotation_degrees.x = 12.0
		# Perna traseira inclinada para trás
		var leg_r := _cyl(Vector3(side_x, HEIGHT * 0.48, -0.09), 0.015, HEIGHT, mat_frame)
		leg_r.rotation_degrees.x = -12.0

	# Dobradiça superior e alça
	_cyl(Vector3(0.0, HEIGHT - 0.02, 0.0), 0.018, WIDTH, mat_frame, Vector3(90, 0, 0))
	_cyl(Vector3(0.0, HEIGHT + 0.04, 0.0), 0.012, 0.22, mat_hinge, Vector3(90, 0, 0)) # alça

	# 2. Painel frontal de sinalização inclinado
	var sign_node := Node3D.new()
	sign_node.position = Vector3(0.0, 0.52, 0.10)
	sign_node.rotation_degrees.x = 12.0
	add_child(sign_node)

	# Fundo da placa amarelo
	_box_child(sign_node, Vector3(0.0, 0.0, 0.0), Vector3(WIDTH - 0.10, 0.55, 0.02), mat_yellow)

	# Faixas zebradas diagonais pretas (Black & Yellow hazard stripes)
	for si in range(6):
		var stripe_x := -0.25 + float(si) * 0.10
		var stripe := _box_child(sign_node, Vector3(stripe_x, 0.0, 0.012), Vector3(0.045, 0.55, 0.005), mat_black)
		stripe.rotation_degrees.z = 40.0

	# Moldura de proteção da placa
	_box_child(sign_node, Vector3(0.0, 0.27, 0.0), Vector3(WIDTH - 0.08, 0.02, 0.03), mat_frame)
	_box_child(sign_node, Vector3(0.0, -0.27, 0.0), Vector3(WIDTH - 0.08, 0.02, 0.03), mat_frame)

	# 3. Corrente limitadora de abertura na base
	_box(Vector3(-half_w + 0.05, 0.15, 0.0), Vector3(0.01, 0.01, 0.22), mat_hinge)
	_box(Vector3(half_w - 0.05, 0.15, 0.0), Vector3(0.01, 0.01, 0.22), mat_hinge)

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
	cm.radial_segments = 12
	mi.mesh = cm
	mi.position = pos
	if rot_deg != Vector3.ZERO:
		mi.rotation_degrees = rot_deg
	mi.material_override = mat
	add_child(mi)
	return mi
