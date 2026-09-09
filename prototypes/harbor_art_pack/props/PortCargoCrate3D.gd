class_name PortCargoCrate3D
extends Node3D

## Caixa de carga pesada reforçada para estiva marítima (1.10m x 0.90m x 0.95m).
## Painéis de madeira, travamento em 'X', cantoneiras de aço e sapatas para empilhadeira.
## Origem no piso Y=0, centrado em X e Z.

const LENGTH: float = 1.10
const WIDTH: float = 0.90
const HEIGHT: float = 0.95

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
	var mat_metal := PortArtMaterials.steel_dark()
	var mat_stencil := PortArtMaterials.hazard_black()

	var half_l := LENGTH * 0.5
	var half_w := WIDTH * 0.5
	var half_h := HEIGHT * 0.5

	# 1. Sapatas de apoio inferiores (Forklift skids)
	for bz in [-half_w + 0.12, 0.0, half_w - 0.12]:
		_box(Vector3(0.0, 0.04, bz), Vector3(LENGTH - 0.04, 0.08, 0.09), mat_wood)

	# 2. Corpo principal (painéis internos de compensado)
	var body_h := HEIGHT - 0.08
	_box(Vector3(0.0, 0.08 + body_h * 0.5, 0.0), Vector3(LENGTH - 0.06, body_h, WIDTH - 0.06), mat_wood)

	# 3. Moldura estrutural externa de tábuas
	var batt_th := 0.025
	var batt_w := 0.08

	# Pilares verticais nos 4 cantos
	for cx in [-half_l + batt_th * 0.5, half_l - batt_th * 0.5]:
		for cz in [-half_w + batt_th * 0.5, half_w - batt_th * 0.5]:
			_box(Vector3(cx, 0.08 + body_h * 0.5, cz), Vector3(batt_w, body_h, batt_w), mat_frame)

	# Molduras horizontais superiores e inferiores
	for side_z in [-half_w, half_w]:
		_box(Vector3(0.0, 0.08 + batt_w * 0.5, side_z), Vector3(LENGTH, batt_w, batt_th), mat_frame)
		_box(Vector3(0.0, HEIGHT - batt_w * 0.5, side_z), Vector3(LENGTH, batt_w, batt_th), mat_frame)

	for side_x in [-half_l, half_l]:
		_box(Vector3(side_x, 0.08 + batt_w * 0.5, 0.0), Vector3(batt_th, batt_w, WIDTH), mat_frame)
		_box(Vector3(side_x, HEIGHT - batt_w * 0.5, 0.0), Vector3(batt_th, batt_w, WIDTH), mat_frame)

	# 4. Travessas diagonais de reforço (Frontal e Traseira)
	for side_z in [-half_w - 0.005, half_w + 0.005]:
		var diag := _box(Vector3(0.0, 0.08 + body_h * 0.5, side_z), Vector3(1.15, batt_w, batt_th), mat_frame)
		diag.rotation_degrees.z = 38.0

	# 5. Cantoneiras de ferro reforçado nos 8 cantos
	for cx in [-half_l, half_l]:
		for cz in [-half_w, half_w]:
			# Cantoneira inferior
			_box(Vector3(cx, 0.08 + 0.06, cz), Vector3(0.10, 0.12, 0.10), mat_metal)
			# Cantoneira superior
			_box(Vector3(cx, HEIGHT - 0.06, cz), Vector3(0.10, 0.12, 0.10), mat_metal)

	# 6. Carimbo/Etiqueta estêncil de carga frágil na face frontal
	_box(Vector3(0.0, 0.65, half_w + 0.015), Vector3(0.24, 0.14, 0.005), mat_stencil)

func _box(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi
