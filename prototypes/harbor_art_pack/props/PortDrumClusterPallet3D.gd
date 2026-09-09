class_name PortDrumClusterPallet3D
extends Node3D

## Conjunto de 4 tambores industriais agrupados e cintados sobre pallet de madeira.
## Padrão clássico de logística portuária com cinta de amarração de carga.
## Origem no piso Y=0, centrado em X e Z.

const LENGTH: float = 1.20
const WIDTH: float = 0.80
const HEIGHT: float = 1.03

var _obstacle_bounds: Array[AABB] = []
var _is_built: bool = false

func _ready() -> void:
	if not _is_built:
		_build_model()

func get_dimensions() -> Vector3:
	return Vector3(LENGTH, HEIGHT, WIDTH)

func get_obstacle_bounds() -> Array[AABB]:
	if not _is_built:
		_build_model()
	return _obstacle_bounds.duplicate()

func _build_model() -> void:
	_is_built = true
	_obstacle_bounds.clear()
	_obstacle_bounds.append(AABB(Vector3(-LENGTH * 0.5, 0.0, -WIDTH * 0.5), Vector3(LENGTH, HEIGHT, WIDTH)))

	# 1. Base do pallet
	var pallet := PortWoodenPallet3D.new()
	add_child(pallet)

	var pallet_top_y := 0.144
	var drum_r := 0.27
	var drum_h := 0.88

	var mat_blue := PortArtMaterials.container_blue()
	var mat_teal := PortArtMaterials.container_teal()
	var mat_amber := PortArtMaterials.container_amber()
	var mat_strap := PortArtMaterials.safety_orange()
	var mat_ratchet := PortArtMaterials.steel_galvanized()
	var mat_hardware := PortArtMaterials.steel_dark()

	# 2. Quatro tambores em posições quadrantes
	var drum_positions := [
		Vector3(-0.29, pallet_top_y, -0.25),
		Vector3(0.29, pallet_top_y, -0.25),
		Vector3(-0.29, pallet_top_y, 0.25),
		Vector3(0.29, pallet_top_y, 0.25)
	]
	var drum_mats := [mat_blue, mat_teal, mat_blue, mat_amber]

	for i in range(4):
		var d_pos: Vector3 = drum_positions[i]
		var d_mat: StandardMaterial3D = drum_mats[i]

		# Cilindro do tambor
		_cyl(Vector3(d_pos.x, d_pos.y + drum_h * 0.5, d_pos.z), drum_r, drum_h, d_mat)
		# Borda superior e anéis
		_cyl(Vector3(d_pos.x, d_pos.y + drum_h - 0.02, d_pos.z), drum_r + 0.005, 0.03, mat_hardware)
		_cyl(Vector3(d_pos.x, d_pos.y + drum_h * 0.5, d_pos.z), drum_r + 0.005, 0.03, d_mat)
		# Bujão
		_cyl(Vector3(d_pos.x + 0.12, d_pos.y + drum_h + 0.004, d_pos.z), 0.022, 0.015, mat_ratchet)

	# 3. Cinta de amarração / Catraca perimetral (Ratchet cargo strap)
	var strap_y := pallet_top_y + drum_h * 0.55
	# Cintas horizontais contornando o cluster
	_box(Vector3(0.0, strap_y, -0.53), Vector3(0.60, 0.05, 0.02), mat_strap)
	_box(Vector3(0.0, strap_y, 0.53), Vector3(0.60, 0.05, 0.02), mat_strap)
	_box(Vector3(-0.57, strap_y, 0.0), Vector3(0.02, 0.05, 0.52), mat_strap)
	_box(Vector3(0.57, strap_y, 0.0), Vector3(0.02, 0.05, 0.52), mat_strap)

	# Fivela da catraca na lateral frontal
	_box(Vector3(0.10, strap_y, 0.545), Vector3(0.08, 0.09, 0.035), mat_ratchet)

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
