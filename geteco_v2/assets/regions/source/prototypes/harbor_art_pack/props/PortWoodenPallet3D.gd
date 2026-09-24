extends Node3D
const PortArtMaterials := preload("res://assets/regions/source/prototypes/harbor_art_pack/PortArtMaterials.gd")

## Pallet de madeira padrão industrial/Euro (1.20m x 0.80m x 0.144m).
## Origem no piso Y=0, centrado em X e Z.
## Projetado com entradas reais de garfos para empilhadeira.

const LENGTH: float = 1.20
const WIDTH: float = 0.80
const HEIGHT: float = 0.144

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

	var mat_wood := PortArtMaterials.wood_pallet_clean()

	var half_l := LENGTH * 0.5
	var half_w := WIDTH * 0.5
	var board_th := 0.022
	var block_h := 0.078

	# 1. Três tábuas inferiores (base)
	for bz in [-half_w + 0.07, 0.0, half_w - 0.07]:
		_box(Vector3(0.0, board_th * 0.5, bz), Vector3(LENGTH, board_th, 0.10), mat_wood)

	# 2. Nove blocos de apoio (3x3)
	for bx in [-half_l + 0.08, 0.0, half_l - 0.08]:
		for bz in [-half_w + 0.07, 0.0, half_w - 0.07]:
			_box(Vector3(bx, board_th + block_h * 0.5, bz), Vector3(0.12, block_h, 0.10), mat_wood)

	# 3. Três travessas intermediárias perpendiculares
	var cross_y := board_th + block_h + board_th * 0.5
	for bx in [-half_l + 0.08, 0.0, half_l - 0.08]:
		_box(Vector3(bx, cross_y, 0.0), Vector3(0.12, board_th, WIDTH), mat_wood)

	# 4. Cinco tábuas do deck superior
	var top_y := board_th + block_h + board_th + board_th * 0.5
	var z_offsets := [-half_w + 0.07, -0.20, 0.0, 0.20, half_w - 0.07]
	for bz in z_offsets:
		var board_w := 0.13 if (bz == z_offsets[0] or bz == z_offsets[4] or bz == 0.0) else 0.09
		_box(Vector3(0.0, top_y, bz), Vector3(LENGTH, board_th, board_w), mat_wood)

func _box(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi
