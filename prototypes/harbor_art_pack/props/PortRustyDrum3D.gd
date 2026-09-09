class_name PortRustyDrum3D
extends Node3D

## Tambor industrial de 200L oxidado, amassado e com vazamento de óleo.
## Metal com pátina de ferrugem marinha, deformação e mancha de graxa.
## Origem no piso Y=0, centrado em X e Z.

const RADIUS: float = 0.29
const HEIGHT: float = 0.88

var _obstacle_bounds: Array[AABB] = []
var _is_built: bool = false

func _ready() -> void:
	if not _is_built:
		_build_model()

func get_dimensions() -> Vector3:
	return Vector3(RADIUS * 2.0, HEIGHT, RADIUS * 2.0)

func get_obstacle_bounds() -> Array[AABB]:
	if not _is_built:
		_build_model()
	return _obstacle_bounds.duplicate()

func _build_model() -> void:
	_is_built = true
	_obstacle_bounds.clear()
	_obstacle_bounds.append(AABB(Vector3(-RADIUS, 0.0, -RADIUS), Vector3(RADIUS * 2.0, HEIGHT, RADIUS * 2.0)))

	var mat_rust := PortArtMaterials.rusty_iron()
	var mat_dark := PortArtMaterials.steel_dark()
	var mat_oil := PortArtMaterials.oil_stain()

	var half_h := HEIGHT * 0.5

	# 1. Corpo cilíndrico oxidado
	_cyl(Vector3(0.0, half_h, 0.0), RADIUS - 0.01, HEIGHT, mat_rust)

	# 2. Bordas amassadas
	_cyl(Vector3(0.0, 0.02, 0.0), RADIUS + 0.005, 0.04, mat_dark)
	var top_rim := _cyl(Vector3(0.01, HEIGHT - 0.02, 0.0), RADIUS + 0.005, 0.04, mat_dark)
	top_rim.rotation_degrees.z = 2.0

	# 3. Anéis de rolagem desgastados
	_cyl(Vector3(0.0, HEIGHT * 0.35, 0.0), RADIUS + 0.006, 0.035, mat_rust)
	_cyl(Vector3(0.0, HEIGHT * 0.65, 0.0), RADIUS + 0.006, 0.035, mat_rust)

	# 4. Amassado acentuado na lateral frontal (+Z)
	var dent := _box(Vector3(0.0, half_h + 0.05, RADIUS - 0.04), Vector3(0.20, 0.22, 0.05), mat_dark)
	dent.rotation_degrees.y = 15.0

	# 5. Escorrimento de óleo na lateral e no topo
	_box(Vector3(0.08, half_h - 0.10, RADIUS - 0.005), Vector3(0.12, 0.40, 0.01), mat_oil)
	_cyl(Vector3(0.06, HEIGHT - 0.01, 0.04), 0.08, 0.005, mat_oil)

	# 6. Bujão oxidado
	_cyl(Vector3(0.12, HEIGHT + 0.005, 0.0), 0.025, 0.02, mat_dark)

func _box(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi

func _cyl(pos: Vector3, radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 14
	mi.mesh = cm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi
