class_name PortContainer20ft3D
extends Node3D

## Contêiner ISO padrão de 20 pés (6.06m x 2.44m x 2.59m).
## Origem no piso Y=0, centrado em X e Z.
## Detalhes: corrugações laterais, postes de canto, trancas verticais e dobradiças.

@export_enum("PacificBlue", "RustRed", "CargoTeal", "IndustrialAmber", "ReeferWhite") var color_theme: int = 0: set = set_color_theme

const LENGTH: float = 6.06
const WIDTH: float = 2.44
const HEIGHT: float = 2.59

var _obstacle_bounds: Array[AABB] = []
var _is_built: bool = false
var _main_material: StandardMaterial3D

func _ready() -> void:
	if not _is_built:
		_build_model()

func set_color_theme(theme_idx: int) -> void:
	color_theme = theme_idx
	if _is_built:
		_update_theme_material()

func get_dimensions() -> Vector3:
	return Vector3(WIDTH, HEIGHT, LENGTH)

func get_obstacle_bounds() -> Array[AABB]:
	if not _is_built:
		_build_model()
	return _obstacle_bounds.duplicate()

func _update_theme_material() -> void:
	var mat := _get_theme_material()
	_main_material.albedo_color = mat.albedo_color
	_main_material.roughness = mat.roughness
	_main_material.metallic = mat.metallic

func _get_theme_material() -> StandardMaterial3D:
	match color_theme:
		1: return PortArtMaterials.container_rust()
		2: return PortArtMaterials.container_teal()
		3: return PortArtMaterials.container_amber()
		4: return PortArtMaterials.container_white()
		_: return PortArtMaterials.container_blue()

func _build_model() -> void:
	_is_built = true
	_obstacle_bounds.clear()
	_obstacle_bounds.append(AABB(Vector3(-WIDTH * 0.5, 0.0, -LENGTH * 0.5), Vector3(WIDTH, HEIGHT, LENGTH)))

	var base_theme := _get_theme_material()
	_main_material = StandardMaterial3D.new()
	_main_material.albedo_color = base_theme.albedo_color
	_main_material.roughness = base_theme.roughness
	_main_material.metallic = base_theme.metallic

	var mat_frame := PortArtMaterials.get_mat("container_frame_dark", base_theme.albedo_color.darkened(0.25), 0.5, 0.55)
	var mat_hardware := PortArtMaterials.steel_galvanized()
	var mat_seal := PortArtMaterials.rubber_black()

	var half_w := WIDTH * 0.5
	var half_l := LENGTH * 0.5
	var half_h := HEIGHT * 0.5

	# 1. Corpo principal selado
	_box(Vector3(0.0, half_h, 0.0), Vector3(WIDTH - 0.08, HEIGHT - 0.08, LENGTH - 0.08), _main_material)

	# 2. Trilhos estruturais superior e inferior (Longarinas)
	for side_x in [-half_w, half_w]:
		# Longarina inferior
		_box(Vector3(side_x, 0.07, 0.0), Vector3(0.12, 0.14, LENGTH), mat_frame)
		# Longarina superior
		_box(Vector3(side_x, HEIGHT - 0.07, 0.0), Vector3(0.12, 0.14, LENGTH), mat_frame)

	# Travessas frontais e traseiras
	for side_z in [-half_l, half_l]:
		_box(Vector3(0.0, 0.07, side_z), Vector3(WIDTH, 0.14, 0.12), mat_frame)
		_box(Vector3(0.0, HEIGHT - 0.07, side_z), Vector3(WIDTH, 0.14, 0.12), mat_frame)

	# 3. Quatro Postes de Canto e Blocos ISO (Corner Castings)
	for cx in [-half_w, half_w]:
		for cz in [-half_l, half_l]:
			# Coluna vertical
			_box(Vector3(cx, half_h, cz), Vector3(0.14, HEIGHT, 0.14), mat_frame)
			# Bloco de canto inferior com furo
			_box(Vector3(cx, 0.08, cz), Vector3(0.16, 0.16, 0.16), mat_hardware)
			# Bloco de canto superior com furo
			_box(Vector3(cx, HEIGHT - 0.08, cz), Vector3(0.16, 0.16, 0.16), mat_hardware)

	# 4. Corrugações das Paredes Laterais (nervuras estampadas com relevo rítmico)
	var num_ribs := 18
	var rib_step := (LENGTH - 0.60) / float(num_ribs)
	for side_x in [-half_w - 0.015, half_w + 0.015]:
		for i in range(num_ribs + 1):
			var z_pos := -half_l + 0.30 + float(i) * rib_step
			_box(Vector3(side_x, half_h, z_pos), Vector3(0.04, HEIGHT - 0.32, rib_step * 0.45), _main_material)

	# 5. Portas Traseiras com Trancas Verticais Duplas (Face +Z)
	var door_z := half_l + 0.01
	_box(Vector3(0.0, half_h, door_z), Vector3(0.02, HEIGHT - 0.28, 0.04), mat_seal) # vedação central

	for rod_x in [-0.45, -0.15, 0.15, 0.45]:
		# Barra vertical de tranca (Locking rod)
		_cyl(Vector3(rod_x, half_h, door_z + 0.04), 0.02, HEIGHT - 0.35, mat_hardware)
		# Mancais superior e inferior
		_box(Vector3(rod_x, 0.25, door_z + 0.04), Vector3(0.08, 0.10, 0.06), mat_frame)
		_box(Vector3(rod_x, HEIGHT - 0.25, door_z + 0.04), Vector3(0.08, 0.10, 0.06), mat_frame)
		# Alavanca de fechamento (Handle)
		_box(Vector3(rod_x, 1.15, door_z + 0.07), Vector3(0.04, 0.32, 0.04), mat_hardware)

	# Dobradiças externas (3 por folha)
	for hinge_x in [-half_w + 0.05, half_w - 0.05]:
		for hy in [0.45, half_h, HEIGHT - 0.45]:
			_box(Vector3(hinge_x, hy, door_z), Vector3(0.10, 0.10, 0.06), mat_hardware)

	# 6. Nervuras estruturais do teto
	for ti in range(8):
		var tz := -half_l + 0.65 + float(ti) * (LENGTH - 1.30) / 7.0
		_box(Vector3(0.0, HEIGHT - 0.02, tz), Vector3(WIDTH - 0.30, 0.03, 0.35), _main_material)

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
	cm.radial_segments = 12
	mi.mesh = cm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi
