class_name PortLongCrate3D
extends Node3D

## Caixa longa para maquinário naval e eixos sobressalentes (2.20m x 0.70m x 0.60m).
## Madeira ripada, cantoneiras de aço, cintas de arqueação metálicas e sapatas inferiores.
## Origem no piso Y=0, centrado em X e Z.

const LENGTH: float = 2.20
const WIDTH: float = 0.70
const HEIGHT: float = 0.60

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

	var mat_wood := PortArtMaterials.wood_crate()
	var mat_frame := PortArtMaterials.wood_pallet_clean()
	var mat_band := PortArtMaterials.steel_dark()
	var mat_hardware := PortArtMaterials.steel_galvanized()

	var half_l := LENGTH * 0.5
	var half_w := WIDTH * 0.5

	# 1. Quatro sapatas inferiores transversais para empilhadeira
	for sx in [-0.80, -0.27, 0.27, 0.80]:
		_box(Vector3(sx, 0.035, 0.0), Vector3(0.10, 0.07, WIDTH - 0.04), mat_frame)

	# 2. Caixa principal fechada
	var body_h := HEIGHT - 0.07
	_box(Vector3(0.0, 0.07 + body_h * 0.5, 0.0), Vector3(LENGTH - 0.04, body_h, WIDTH - 0.04), mat_wood)

	# 3. Moldura perimetral externa
	var batt_th := 0.02
	var batt_w := 0.07

	# Cantos longitudinais superiores e inferiores
	for side_z in [-half_w, half_w]:
		_box(Vector3(0.0, 0.07 + batt_w * 0.5, side_z), Vector3(LENGTH, batt_w, batt_th), mat_frame)
		_box(Vector3(0.0, HEIGHT - batt_w * 0.5, side_z), Vector3(LENGTH, batt_w, batt_th), mat_frame)

	for side_x in [-half_l, half_l]:
		_box(Vector3(side_x, 0.07 + body_h * 0.5, 0.0), Vector3(batt_th, body_h, WIDTH), mat_frame)

	# 4. Cintas de arqueação em aço escuro (Metal strapping bands)
	for bx in [-0.70, -0.20, 0.20, 0.70]:
		# Cinta no topo
		_box(Vector3(bx, HEIGHT + 0.005, 0.0), Vector3(0.03, 0.008, WIDTH + 0.02), mat_band)
		# Cintas laterais
		_box(Vector3(bx, 0.07 + body_h * 0.5, -half_w - 0.005), Vector3(0.03, body_h, 0.008), mat_band)
		_box(Vector3(bx, 0.07 + body_h * 0.5, half_w + 0.005), Vector3(0.03, body_h, 0.008), mat_band)
		# Fivela / Selo da cinta
		_box(Vector3(bx, HEIGHT * 0.6, half_w + 0.012), Vector3(0.05, 0.04, 0.015), mat_hardware)

func _box(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi
