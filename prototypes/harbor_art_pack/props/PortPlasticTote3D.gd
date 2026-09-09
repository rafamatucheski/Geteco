class_name PortPlasticTote3D
extends Node3D

## Caixa plástica industrial empilhável (Eurobox 0.60m x 0.40m x 0.35m).
## Nervuras de reforço estrutural, alças ergonômicas embutidas e borda de empilhamento.
## Origem no piso Y=0, centrado em X e Z.

@export_enum("Blue", "Grey") var tote_color: int = 0: set = set_tote_color

const LENGTH: float = 0.60
const WIDTH: float = 0.40
const HEIGHT: float = 0.35

var _obstacle_bounds: Array[AABB] = []
var _is_built: bool = false
var _main_material: StandardMaterial3D

func _ready() -> void:
	if not _is_built:
		_build_model()

func set_tote_color(col_idx: int) -> void:
	tote_color = col_idx
	if _is_built:
		_update_color_material()

func get_dimensions() -> Vector3:
	return Vector3(LENGTH, HEIGHT, WIDTH)

func get_obstacle_bounds() -> Array[AABB]:
	if not _is_built:
		_build_model()
	return _obstacle_bounds.duplicate()

func _update_color_material() -> void:
	var mat := PortArtMaterials.plastic_grey() if (tote_color == 1) else PortArtMaterials.plastic_blue()
	_main_material.albedo_color = mat.albedo_color
	_main_material.roughness = mat.roughness

func _build_model() -> void:
	_is_built = true
	_obstacle_bounds.clear()
	_obstacle_bounds.append(AABB(Vector3(-LENGTH * 0.5, 0.0, -WIDTH * 0.5), Vector3(LENGTH, HEIGHT, WIDTH)))

	var base_mat := PortArtMaterials.plastic_grey() if (tote_color == 1) else PortArtMaterials.plastic_blue()
	_main_material = StandardMaterial3D.new()
	_main_material.albedo_color = base_mat.albedo_color
	_main_material.roughness = base_mat.roughness
	_main_material.metallic = 0.15

	var mat_recess := PortArtMaterials.steel_dark()
	var half_l := LENGTH * 0.5
	var half_w := WIDTH * 0.5
	var half_h := HEIGHT * 0.5

	# 1. Base inferior e corpo principal afunilado sutilmente
	_box(Vector3(0.0, 0.02, 0.0), Vector3(LENGTH - 0.04, 0.04, WIDTH - 0.04), _main_material)
	_box(Vector3(0.0, half_h, 0.0), Vector3(LENGTH - 0.03, HEIGHT - 0.04, WIDTH - 0.03), _main_material)

	# 2. Aba/Borda perimetral superior de encaixe (Rim)
	_box(Vector3(0.0, HEIGHT - 0.025, 0.0), Vector3(LENGTH, 0.05, WIDTH), _main_material)

	# 3. Nervuras verticais de reforço nas laterais
	for side_z in [-half_w - 0.005, half_w + 0.005]:
		for rx in [-0.20, -0.10, 0.0, 0.10, 0.20]:
			_box(Vector3(rx, half_h, side_z), Vector3(0.015, HEIGHT - 0.07, 0.015), _main_material)

	# 4. Alças embutidas vazadas nas cabeceiras (+X e -X)
	for side_x in [-half_l - 0.002, half_l + 0.002]:
		_box(Vector3(side_x, HEIGHT - 0.09, 0.0), Vector3(0.02, 0.04, 0.12), mat_recess)

func _box(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi
