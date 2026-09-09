class_name PortContainerOpen3D
extends Node3D

## Contêiner ISO de 20 pés aberto com interior acessível e visível.
## Portas traseiras abertas em ângulo simétrico de 115° para fora.
## Piso interno nivelado de madeira tratada com vão de entrada desimpedido.
## Colisores precisos por partes (paredes, teto, piso e folhas de porta),
## preservando o vão de entrada e o corredor interno para circulação a pé.
## Origem no piso Y=0, centrado em X e Z (corpo principal de Z=-3.03 a +3.03).

@export_enum("PacificBlue", "RustRed", "CargoTeal", "IndustrialAmber", "ReeferWhite") var color_theme: int = 1: set = set_color_theme

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
	# Largura total com portas abertas: ~3.32m (de X = -1.66 a +1.66m)
	# Altura total: 2.59m
	# Comprimento total: ~7.13m (de Z = -3.03 a +4.10m)
	return Vector3(3.32, HEIGHT, 7.13)

func get_obstacle_bounds() -> Array[AABB]:
	if not _is_built:
		_build_model()
	return _obstacle_bounds.duplicate()

## Retorna o volume livre interno para circulação de personagens e carga
func get_interior_bounds() -> AABB:
	var half_w := WIDTH * 0.5
	var half_l := LENGTH * 0.5
	return AABB(Vector3(-half_w + 0.16, 0.14, -half_l + 0.16), Vector3(WIDTH - 0.32, HEIGHT - 0.30, LENGTH - 0.20))

## Retorna o vão livre de entrada na porta traseira (+Z)
func get_entrance_bounds() -> AABB:
	var half_l := LENGTH * 0.5
	return AABB(Vector3(-1.06, 0.14, half_l - 0.10), Vector3(2.12, HEIGHT - 0.30, 0.40))

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

	var half_w := WIDTH * 0.5
	var half_l := LENGTH * 0.5
	var half_h := HEIGHT * 0.5

	# =========================================================================
	# COLISORES SUGERIDOS REALISTAS (PRESERVANDO CORREDOR E ENTRADA LIVRES)
	# =========================================================================
	# 1. Piso estrutural da base (espessura 0.14m no solo)
	_obstacle_bounds.append(AABB(Vector3(-half_w, 0.0, -half_l), Vector3(WIDTH, 0.14, LENGTH)))

	# 2. Teto estrutural
	_obstacle_bounds.append(AABB(Vector3(-half_w, HEIGHT - 0.14, -half_l), Vector3(WIDTH, 0.14, LENGTH)))

	# 3. Parede traseira de fundo (-Z)
	_obstacle_bounds.append(AABB(Vector3(-half_w, 0.14, -half_l), Vector3(WIDTH, HEIGHT - 0.28, 0.16)))

	# 4. Parede lateral esquerda (-X)
	_obstacle_bounds.append(AABB(Vector3(-half_w, 0.14, -half_l), Vector3(0.16, HEIGHT - 0.28, LENGTH)))

	# 5. Parede lateral direita (+X)
	_obstacle_bounds.append(AABB(Vector3(half_w - 0.16, 0.14, -half_l), Vector3(0.16, HEIGHT - 0.28, LENGTH)))

	# 6. Folha da porta esquerda aberta (-115° para fora e frente)
	_obstacle_bounds.append(AABB(Vector3(-1.66, 0.14, half_l), Vector3(0.56, HEIGHT - 0.28, 1.08)))

	# 7. Folha da porta direita aberta (+115° para fora e frente)
	_obstacle_bounds.append(AABB(Vector3(1.10, 0.14, half_l), Vector3(0.56, HEIGHT - 0.28, 1.08)))

	# =========================================================================
	# GEOMETRIA PROCEDURAL DETALHADA
	# =========================================================================
	var base_theme := _get_theme_material()
	_main_material = StandardMaterial3D.new()
	_main_material.albedo_color = base_theme.albedo_color
	_main_material.roughness = base_theme.roughness
	_main_material.metallic = base_theme.metallic

	var mat_frame := PortArtMaterials.get_mat("container_frame_dark_open", base_theme.albedo_color.darkened(0.25), 0.5, 0.55)
	var mat_hardware := PortArtMaterials.steel_galvanized()
	var mat_floor := PortArtMaterials.wood_crate()
	var mat_interior := PortArtMaterials.container_interior()

	# 1. Piso interno e base
	_box(Vector3(0.0, 0.08, 0.0), Vector3(WIDTH - 0.2, 0.12, LENGTH - 0.2), mat_floor)

	# 2. Teto
	_box(Vector3(0.0, HEIGHT - 0.06, 0.0), Vector3(WIDTH - 0.1, 0.10, LENGTH - 0.1), _main_material)

	# 3. Parede de fundo (-Z)
	_box(Vector3(0.0, half_h, -half_l + 0.05), Vector3(WIDTH - 0.1, HEIGHT - 0.2, 0.10), _main_material)

	# 4. Paredes laterais (+X e -X)
	for side_x in [-half_w + 0.05, half_w - 0.05]:
		_box(Vector3(side_x, half_h, 0.0), Vector3(0.10, HEIGHT - 0.2, LENGTH - 0.2), _main_material)
		var interior_x: float = side_x + (0.04 if side_x < 0.0 else -0.04)
		_box(Vector3(interior_x, half_h, 0.0), Vector3(0.02, HEIGHT - 0.3, LENGTH - 0.4), mat_interior)

	# 5. Longarinas e colunas perimetrais
	for side_x in [-half_w, half_w]:
		_box(Vector3(side_x, 0.07, 0.0), Vector3(0.12, 0.14, LENGTH), mat_frame)
		_box(Vector3(side_x, HEIGHT - 0.07, 0.0), Vector3(0.12, 0.14, LENGTH), mat_frame)

	for side_z in [-half_l, half_l]:
		_box(Vector3(0.0, 0.07, side_z), Vector3(WIDTH, 0.14, 0.12), mat_frame)
		_box(Vector3(0.0, HEIGHT - 0.07, side_z), Vector3(WIDTH, 0.14, 0.12), mat_frame)

	for cx in [-half_w, half_w]:
		for cz in [-half_l, half_l]:
			_box(Vector3(cx, half_h, cz), Vector3(0.14, HEIGHT, 0.14), mat_frame)
			_box(Vector3(cx, 0.08, cz), Vector3(0.16, 0.16, 0.16), mat_hardware)
			_box(Vector3(cx, HEIGHT - 0.08, cz), Vector3(0.16, 0.16, 0.16), mat_hardware)

	# 6. Corrugações externas
	var num_ribs := 16
	var rib_step := (LENGTH - 0.80) / float(num_ribs)
	for side_x in [-half_w - 0.015, half_w + 0.015]:
		for i in range(num_ribs + 1):
			var z_pos := -half_l + 0.40 + float(i) * rib_step
			_box(Vector3(side_x, half_h, z_pos), Vector3(0.04, HEIGHT - 0.32, rib_step * 0.45), _main_material)

	# 7. Portas Traseiras Abertas Simetricamente (+Z)
	var leaf_w: float = 1.15
	var leaf_h: float = HEIGHT - 0.28

	# Folha Esquerda (dobradiça em -half_w + 0.08, abrindo a -115° para fora/frente)
	var door_left := Node3D.new()
	door_left.position = Vector3(-half_w + 0.08, 0.0, half_l)
	door_left.rotation_degrees.y = -115.0
	add_child(door_left)
	_build_door_leaf(door_left, leaf_w, leaf_h, 1.0, _main_material, mat_frame, mat_hardware)

	# Folha Direita (dobradiça em +half_w - 0.08, abrindo a +115° para fora/frente)
	var door_right := Node3D.new()
	door_right.position = Vector3(half_w - 0.08, 0.0, half_l)
	door_right.rotation_degrees.y = 115.0
	add_child(door_right)
	_build_door_leaf(door_right, leaf_w, leaf_h, -1.0, _main_material, mat_frame, mat_hardware)

func _build_door_leaf(parent: Node3D, leaf_w: float, leaf_h: float, sign_dir: float, mat_body: Material, mat_frame: Material, mat_hardware: Material) -> void:
	var offset_x := leaf_w * 0.5 * sign_dir

	var p := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(leaf_w, leaf_h, 0.06)
	p.mesh = bm
	p.position = Vector3(offset_x, leaf_h * 0.5 + 0.14, 0.0)
	p.material_override = mat_body
	parent.add_child(p)

	var frame := MeshInstance3D.new()
	var fbm := BoxMesh.new()
	fbm.size = Vector3(leaf_w + 0.04, leaf_h + 0.04, 0.04)
	frame.mesh = fbm
	frame.position = Vector3(offset_x, leaf_h * 0.5 + 0.14, -0.02)
	frame.material_override = mat_frame
	parent.add_child(frame)

	var rod := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.02
	cm.bottom_radius = 0.02
	cm.height = leaf_h * 0.95
	rod.mesh = cm
	rod.position = Vector3(offset_x + 0.25 * sign_dir, leaf_h * 0.5 + 0.14, 0.05)
	rod.material_override = mat_hardware
	parent.add_child(rod)

func _box(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi
