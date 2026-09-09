class_name PortHandTruck3D
extends Node3D

## Carrinho manual de duas rodas para armazém portuário (Hand Truck / Diabo de Carga).
## Estrutura tubular em aço de segurança, chapa de apoio frontal, eixo e rodas de borracha maciça.
## Dimensões: 0.55m x 1.30m x 0.50m.
## Origem no piso Y=0, centrado em X e Z.

const WIDTH: float = 0.55
const HEIGHT: float = 1.30
const DEPTH: float = 0.50

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

	var mat_frame := PortArtMaterials.safety_yellow()
	var mat_metal := PortArtMaterials.steel_dark()
	var mat_rubber := PortArtMaterials.rubber_black()
	var mat_hub := PortArtMaterials.steel_galvanized()

	var half_w := WIDTH * 0.5
	var wheel_r := 0.12
	var wheel_th := 0.06
	var axle_y := wheel_r

	# 1. Chapa de carga frontal chanfrada (Toe plate na base)
	_box(Vector3(0.0, 0.015, 0.15), Vector3(WIDTH - 0.10, 0.012, 0.30), mat_metal)
	# Batente traseiro da chapa
	_box(Vector3(0.0, 0.06, 0.01), Vector3(WIDTH - 0.08, 0.09, 0.02), mat_metal)

	# 2. Duas colunas tubulares verticais principais
	for cx in [-half_w + 0.10, half_w - 0.10]:
		_cyl(Vector3(cx, HEIGHT * 0.5, 0.0), 0.018, HEIGHT - 0.10, mat_frame)
		# Punho superior emborrachado curvado para trás
		_cyl(Vector3(cx, HEIGHT - 0.04, -0.07), 0.02, 0.14, mat_rubber, Vector3(45, 0, 0))

	# 3. Travessas horizontais curvas de reforço
	for ty in [0.35, 0.65, 0.95]:
		_box(Vector3(0.0, ty, 0.0), Vector3(WIDTH - 0.18, 0.03, 0.025), mat_frame)

	# 4. Eixo transversal traseiro e suportes de fixação
	_cyl(Vector3(0.0, axle_y, -0.10), 0.015, WIDTH - 0.04, mat_metal, Vector3(0, 0, 90))
	for sx in [-half_w + 0.10, half_w - 0.10]:
		_box(Vector3(sx, axle_y * 0.8, -0.05), Vector3(0.02, axle_y * 1.5, 0.10), mat_metal)

	# 5. Rodas de borracha com cubo de aço galvanizado
	for wx in [-half_w + 0.04, half_w - 0.04]:
		# Pneu de borracha
		_cyl(Vector3(wx, axle_y, -0.10), wheel_r, wheel_th, mat_rubber, Vector3(0, 0, 90))
		# Cubo da roda
		_cyl(Vector3(wx + (0.01 if wx > 0 else -0.01), axle_y, -0.10), wheel_r * 0.5, wheel_th + 0.01, mat_hub, Vector3(0, 0, 90))

func _box(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
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
