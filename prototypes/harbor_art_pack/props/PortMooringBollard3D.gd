class_name PortMooringBollard3D
extends Node3D

## Cabeço de amarração portuário em ferro fundido (Mooring Bollard tipo Tee-head).
## Base de ancoragem aparafusada, pescoço cônico, chifres de retenção de cabos e amarra de corda naval enrolada.
## Dimensões: 0.70m largura x 0.65m altura x 0.60m profundidade.
## Origem no piso Y=0, centrado em X e Z.

const WIDTH: float = 0.70
const HEIGHT: float = 0.65
const DEPTH: float = 0.60

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

	var mat_iron := PortArtMaterials.cast_iron()
	var mat_hardware := PortArtMaterials.steel_galvanized()
	var mat_rope := PortArtMaterials.rope_hemp()

	# 1. Flange de base elíptica/arredondada
	_cyl(Vector3(0.0, 0.03, 0.0), 0.28, 0.06, mat_iron)

	# Quatro parafusos prisioneiros de ancoragem no concreto
	for a in [45.0, 135.0, 225.0, 315.0]:
		var rad := deg_to_rad(a)
		var bx := cos(rad) * 0.23
		var bz := sin(rad) * 0.23
		_cyl(Vector3(bx, 0.07, bz), 0.02, 0.03, mat_hardware)

	# 2. Pescoço central robusto de ferro fundido
	var neck := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.17
	cm.bottom_radius = 0.21
	cm.height = 0.44
	cm.radial_segments = 16
	neck.mesh = cm
	neck.position = Vector3(0.0, 0.26, 0.0)
	neck.material_override = mat_iron
	add_child(neck)

	# 3. Cabeça alargada e chifres laterais (Tee-head horns)
	_cyl(Vector3(0.0, 0.52, 0.0), 0.22, 0.14, mat_iron)

	# Chifres transversais projetados para os lados (+X e -X)
	for hx in [-0.22, 0.22]:
		var horn := _cyl(Vector3(hx, 0.54, 0.0), 0.07, 0.24, mat_iron, Vector3(0, 0, 90 if hx > 0 else -90))
		horn.rotation_degrees.z = 70.0 if hx > 0 else -70.0

	# 4. Cabo naval grosso enrolado na base (Mooring hawser rope)
	# Três voltas de corda sobrepostas ao redor do tronco inferior
	for r_i in range(3):
		var tm := TorusMesh.new()
		tm.inner_radius = 0.20 + float(r_i) * 0.02
		tm.outer_radius = 0.28 + float(r_i) * 0.02
		tm.rings = 20
		tm.ring_segments = 10

		var mi_rope := MeshInstance3D.new()
		mi_rope.mesh = tm
		mi_rope.position = Vector3(0.0, 0.08 + float(r_i) * 0.065, 0.0)
		mi_rope.material_override = mat_rope
		add_child(mi_rope)

	# Laço de corda passando pelo chifre direito
	var loop := _cyl(Vector3(0.18, 0.45, 0.05), 0.035, 0.28, mat_rope)
	loop.rotation_degrees.x = 25.0
	loop.rotation_degrees.z = -30.0

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
