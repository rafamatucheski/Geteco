class_name PortPalletStack3D
extends Node3D

## Pilha organizada de 5 pallets industriais encaixados.
## Altura total: ~0.72m.
## Origem no piso Y=0, centrado em X e Z.

const LENGTH: float = 1.20
const WIDTH: float = 0.80
const HEIGHT: float = 0.72
const PALLET_COUNT: int = 5

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

	var y_offsets := [0.0, 0.144, 0.288, 0.432, 0.576]
	var yaws := [0.0, 1.2, -0.8, 0.5, -1.0]

	for i in range(PALLET_COUNT):
		var p_root := Node3D.new()
		p_root.position.y = y_offsets[i]
		p_root.rotation_degrees.y = yaws[i]
		add_child(p_root)

		var mat_wood: StandardMaterial3D = PortArtMaterials.wood_pallet_clean() if (i % 2 == 0) else PortArtMaterials.wood_pallet_weathered()
		_build_single_pallet(p_root, mat_wood)

func _build_single_pallet(parent: Node3D, mat_wood: Material) -> void:
	var half_l := LENGTH * 0.5
	var half_w := WIDTH * 0.5
	var board_th := 0.022
	var block_h := 0.078

	# Base
	for bz in [-half_w + 0.07, 0.0, half_w - 0.07]:
		_box_child(parent, Vector3(0.0, board_th * 0.5, bz), Vector3(LENGTH, board_th, 0.10), mat_wood)

	# Blocos 3x3
	for bx in [-half_l + 0.08, 0.0, half_l - 0.08]:
		for bz in [-half_w + 0.07, 0.0, half_w - 0.07]:
			_box_child(parent, Vector3(bx, board_th + block_h * 0.5, bz), Vector3(0.12, block_h, 0.10), mat_wood)

	# Travessas
	var cross_y := board_th + block_h + board_th * 0.5
	for bx in [-half_l + 0.08, 0.0, half_l - 0.08]:
		_box_child(parent, Vector3(bx, cross_y, 0.0), Vector3(0.12, board_th, WIDTH), mat_wood)

	# Topo
	var top_y := board_th + block_h + board_th + board_th * 0.5
	var z_offsets := [-half_w + 0.07, -0.20, 0.0, 0.20, half_w - 0.07]
	for bz in z_offsets:
		var board_w := 0.13 if (bz == z_offsets[0] or bz == z_offsets[4] or bz == 0.0) else 0.09
		_box_child(parent, Vector3(0.0, top_y, bz), Vector3(LENGTH, board_th, board_w), mat_wood)

func _box_child(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi
