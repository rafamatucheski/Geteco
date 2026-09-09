class_name PortPierFender3D
extends Node3D

## Defensa cilíndrica de borracha marinha vulcanizada para píer/cais (Pier Fender).
## Absorvedor de impacto para atracação de navios, com flanges de extremidade e correntes de ancoragem.
## Dimensões: 1.50m comprimento x 0.55m altura x 0.55m largura.
## Origem no piso Y=0, centrado em X e Z.

const LENGTH: float = 1.50
const RADIUS: float = 0.275
const HEIGHT: float = 0.55

var _obstacle_bounds: Array[AABB] = []
var _is_built: bool = false

func _ready() -> void:
	if not _is_built:
		_build_model()

func get_dimensions() -> Vector3:
	return Vector3(LENGTH, HEIGHT, RADIUS * 2.0)

func get_obstacle_bounds() -> Array[AABB]:
	if not _is_built:
		_build_model()
	return _obstacle_bounds.duplicate()

func _build_model() -> void:
	_is_built = true
	_obstacle_bounds.clear()
	_obstacle_bounds.append(AABB(Vector3(-LENGTH * 0.5, 0.0, -RADIUS), Vector3(LENGTH, HEIGHT, RADIUS * 2.0)))

	var mat_rubber := PortArtMaterials.marine_fender()
	var mat_iron := PortArtMaterials.cast_iron()
	var mat_hardware := PortArtMaterials.steel_galvanized()

	var half_l := LENGTH * 0.5
	var center_y := RADIUS

	# 1. Cilindro principal de borracha vulcanizada (horizontal no eixo X)
	_cyl(Vector3(0.0, center_y, 0.0), RADIUS, LENGTH - 0.20, mat_rubber, Vector3(0, 0, 90))

	# 2. Flanges e anéis reforçados de borracha nas duas extremidades
	for end_x in [-half_l + 0.12, half_l - 0.12]:
		_cyl(Vector3(end_x, center_y, 0.0), RADIUS + 0.015, 0.08, mat_rubber, Vector3(0, 0, 90))

	# 3. Tampas de terminação e furos de passagem de eixo
	for end_x in [-half_l + 0.02, half_l - 0.02]:
		_cyl(Vector3(end_x, center_y, 0.0), RADIUS * 0.65, 0.06, mat_iron, Vector3(0, 0, 90))
		_cyl(Vector3(end_x, center_y, 0.0), 0.06, 0.12, mat_hardware, Vector3(0, 0, 90))

	# 4. Manilhas e elos de corrente de fixação nas pontas
	for end_x in [-half_l - 0.06, half_l + 0.06]:
		# Manilha de aço
		_cyl(Vector3(end_x, center_y, 0.0), 0.05, 0.06, mat_iron)
		# Elos de corrente caídos em direção ao solo
		_box(Vector3(end_x, center_y * 0.5, 0.0), Vector3(0.03, center_y, 0.04), mat_iron)

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
	cm.radial_segments = 16
	mi.mesh = cm
	mi.position = pos
	if rot_deg != Vector3.ZERO:
		mi.rotation_degrees = rot_deg
	mi.material_override = mat
	add_child(mi)
	return mi
