class_name PortOilDrum3D
extends Node3D

## Tambor metálico industrial de 200 litros (55 galões: diâmetro 0.58m, altura 0.88m).
## Anéis de rolagem estampados (rolling hoops), bordas crimpadas (chimes) e bujões rosqueados (bungs).
## Origem no piso Y=0, centrado em X e Z.

@export_enum("Blue", "Rust", "YellowSafety", "DarkGrey") var drum_color: int = 0: set = set_drum_color

const RADIUS: float = 0.29
const HEIGHT: float = 0.88

var _obstacle_bounds: Array[AABB] = []
var _is_built: bool = false
var _main_material: StandardMaterial3D

func _ready() -> void:
	if not _is_built:
		_build_model()

func set_drum_color(idx: int) -> void:
	drum_color = idx
	if _is_built:
		_update_material()

func get_dimensions() -> Vector3:
	return Vector3(RADIUS * 2.0, HEIGHT, RADIUS * 2.0)

func get_obstacle_bounds() -> Array[AABB]:
	if not _is_built:
		_build_model()
	return _obstacle_bounds.duplicate()

func _update_material() -> void:
	var mat := _get_color_mat()
	_main_material.albedo_color = mat.albedo_color
	_main_material.roughness = mat.roughness
	_main_material.metallic = mat.metallic

func _get_color_mat() -> StandardMaterial3D:
	match drum_color:
		1: return PortArtMaterials.container_rust()
		2: return PortArtMaterials.safety_yellow()
		3: return PortArtMaterials.steel_dark()
		_: return PortArtMaterials.container_blue()

func _build_model() -> void:
	_is_built = true
	_obstacle_bounds.clear()
	_obstacle_bounds.append(AABB(Vector3(-RADIUS, 0.0, -RADIUS), Vector3(RADIUS * 2.0, HEIGHT, RADIUS * 2.0)))

	var base_mat := _get_color_mat()
	_main_material = StandardMaterial3D.new()
	_main_material.albedo_color = base_mat.albedo_color
	_main_material.roughness = base_mat.roughness
	_main_material.metallic = base_mat.metallic

	var mat_hardware := PortArtMaterials.steel_galvanized()
	var mat_rim := PortArtMaterials.get_mat("drum_rim_dark", base_mat.albedo_color.darkened(0.2), 0.6, 0.45)

	var half_h := HEIGHT * 0.5

	# 1. Corpo principal cilíndrico
	_cyl(Vector3(0.0, half_h, 0.0), RADIUS - 0.01, HEIGHT, _main_material)

	# 2. Bordas crimpadas superior e inferior (Chimes)
	_cyl(Vector3(0.0, 0.02, 0.0), RADIUS + 0.006, 0.04, mat_rim)
	_cyl(Vector3(0.0, HEIGHT - 0.02, 0.0), RADIUS + 0.006, 0.04, mat_rim)

	# 3. Dois anéis de rolagem estampados (Rolling hoops a 1/3 e 2/3 da altura)
	_cyl(Vector3(0.0, HEIGHT * 0.35, 0.0), RADIUS + 0.008, 0.035, _main_material)
	_cyl(Vector3(0.0, HEIGHT * 0.65, 0.0), RADIUS + 0.008, 0.035, _main_material)

	# 4. Tampa superior rebaixada
	_cyl(Vector3(0.0, HEIGHT - 0.015, 0.0), RADIUS - 0.02, 0.01, mat_rim)

	# 5. Bujões rosqueados (Bung plugs: 2" flange e 3/4" respire)
	_cyl(Vector3(0.12, HEIGHT + 0.005, 0.0), 0.025, 0.02, mat_hardware)
	_cyl(Vector3(-0.12, HEIGHT + 0.004, 0.05), 0.016, 0.016, mat_hardware)

func _cyl(pos: Vector3, radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 16
	mi.mesh = cm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi
