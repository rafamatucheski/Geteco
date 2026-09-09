class_name PortWeatheredPallet3D
extends Node3D

## Pallet de madeira envelhecido e desgastado pelo ambiente marinho.
## Madeira acinzentada, tábuas com quebras parciais e pregos aparentes.
## Origem no piso Y=0, centrado em X e Z.

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

	var mat_wood := PortArtMaterials.wood_pallet_weathered()
	var mat_nail := PortArtMaterials.rusty_iron()

	var half_l := LENGTH * 0.5
	var half_w := WIDTH * 0.5
	var board_th := 0.022
	var block_h := 0.078

	# 1. Três tábuas inferiores (base com ligeiro desgaste)
	for bz in [-half_w + 0.07, 0.0, half_w - 0.07]:
		_box(Vector3(0.0, board_th * 0.5, bz), Vector3(LENGTH - 0.02, board_th, 0.10), mat_wood)

	# 2. Nove blocos de apoio (3x3)
	for bx in [-half_l + 0.08, 0.0, half_l - 0.08]:
		for bz in [-half_w + 0.07, 0.0, half_w - 0.07]:
			_box(Vector3(bx, board_th + block_h * 0.5, bz), Vector3(0.12, block_h, 0.10), mat_wood)

	# 3. Três travessas intermediárias
	var cross_y := board_th + block_h + board_th * 0.5
	for bx in [-half_l + 0.08, 0.0, half_l - 0.08]:
		_box(Vector3(bx, cross_y, 0.0), Vector3(0.12, board_th, WIDTH), mat_wood)

	# 4. Cinco tábuas do deck superior com desgastes
	var top_y := board_th + block_h + board_th + board_th * 0.5
	# Tábua 1 (borda frontal - completa)
	_box(Vector3(0.0, top_y, -half_w + 0.07), Vector3(LENGTH, board_th, 0.13), mat_wood)
	# Tábua 2 (quebrada na ponta direita)
	_box(Vector3(-0.15, top_y, -0.20), Vector3(LENGTH - 0.30, board_th, 0.09), mat_wood)
	# Tábua 3 (centro - completa mas desgastada)
	_box(Vector3(0.0, top_y, 0.0), Vector3(LENGTH, board_th, 0.12), mat_wood)
	# Tábua 4 (lascada na ponta esquerda)
	_box(Vector3(0.12, top_y, 0.20), Vector3(LENGTH - 0.24, board_th, 0.09), mat_wood)
	# Tábua 5 (borda traseira - completa com ligeira inclinação)
	var t5 := _box(Vector3(0.0, top_y + 0.005, half_w - 0.07), Vector3(LENGTH, board_th, 0.13), mat_wood)
	t5.rotation_degrees.z = 0.8

	# Pontos de pregos oxidados
	for px in [-half_l + 0.08, half_l - 0.08]:
		_box(Vector3(px, top_y + 0.012, -half_w + 0.07), Vector3(0.01, 0.006, 0.01), mat_nail)
		_box(Vector3(px, top_y + 0.012, half_w - 0.07), Vector3(0.01, 0.006, 0.01), mat_nail)

func _box(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi
