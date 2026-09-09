class_name PortReeferContainer3D
extends Node3D

## Contêiner Frigorífico ISO de 20 pés (Reefer Container).
## Caracterizado por acabamento isotérmico branco e unidade condensadora/compressor na extremidade frontal.
## Origem no piso Y=0, centrado em X e Z.

const LENGTH: float = 6.06
const WIDTH: float = 2.44
const HEIGHT: float = 2.59

var _obstacle_bounds: Array[AABB] = []
var _is_built: bool = false

func _ready() -> void:
	if not _is_built:
		_build_model()

func get_dimensions() -> Vector3:
	return Vector3(WIDTH, HEIGHT, LENGTH)

func get_obstacle_bounds() -> Array[AABB]:
	if not _is_built:
		_build_model()
	return _obstacle_bounds.duplicate()

func _build_model() -> void:
	_is_built = true
	_obstacle_bounds.clear()
	_obstacle_bounds.append(AABB(Vector3(-WIDTH * 0.5, 0.0, -LENGTH * 0.5), Vector3(WIDTH, HEIGHT, LENGTH)))

	var mat_body := PortArtMaterials.container_white()
	var mat_frame := PortArtMaterials.get_mat("reefer_frame", Color("#95a5a6"), 0.5, 0.45)
	var mat_machinery := PortArtMaterials.steel_dark()
	var mat_grille := PortArtMaterials.steel_galvanized()
	var mat_indicator := PortArtMaterials.get_mat("reefer_led", Color("#2ecc71"), 0.1, 0.2, 2.0, Color("#2ecc71"))
	var mat_seal := PortArtMaterials.rubber_black()

	var half_w := WIDTH * 0.5
	var half_l := LENGTH * 0.5
	var half_h := HEIGHT * 0.5

	# 1. Corpo principal isotérmico (painéis lisos brancos com perfil sutil)
	_box(Vector3(0.0, half_h, 0.25), Vector3(WIDTH - 0.08, HEIGHT - 0.08, LENGTH - 0.58), mat_body)

	# 2. Longarinas e colunas perimetrais
	for side_x in [-half_w, half_w]:
		_box(Vector3(side_x, 0.07, 0.0), Vector3(0.12, 0.14, LENGTH), mat_frame)
		_box(Vector3(side_x, HEIGHT - 0.07, 0.0), Vector3(0.12, 0.14, LENGTH), mat_frame)

	for side_z in [-half_l, half_l]:
		_box(Vector3(0.0, 0.07, side_z), Vector3(WIDTH, 0.14, 0.12), mat_frame)
		_box(Vector3(0.0, HEIGHT - 0.07, side_z), Vector3(WIDTH, 0.14, 0.12), mat_frame)

	for cx in [-half_w, half_w]:
		for cz in [-half_l, half_l]:
			_box(Vector3(cx, half_h, cz), Vector3(0.14, HEIGHT, 0.14), mat_frame)
			_box(Vector3(cx, 0.08, cz), Vector3(0.16, 0.16, 0.16), mat_grille)
			_box(Vector3(cx, HEIGHT - 0.08, cz), Vector3(0.16, 0.16, 0.16), mat_grille)

	# 3. Painéis laterais horizontais estruturais (Reefer panels)
	for side_x in [-half_w - 0.01, half_w + 0.01]:
		for yi in range(5):
			var y_pos := 0.45 + float(yi) * 0.42
			_box(Vector3(side_x, y_pos, 0.25), Vector3(0.03, 0.06, LENGTH - 0.70), mat_frame)

	# 4. Unidade condensadora / Refrigeração embutida na frente (-Z)
	var mach_z := -half_l + 0.28
	# Nicho de refrigeração recuado
	_box(Vector3(0.0, half_h, mach_z), Vector3(WIDTH - 0.35, HEIGHT - 0.35, 0.45), mat_machinery)

	# Grelhas do condensador (ventiladores duplos)
	_cyl(Vector3(-0.50, half_h + 0.35, mach_z - 0.23), 0.38, 0.04, mat_grille, Vector3(90, 0, 0))
	_cyl(Vector3(0.50, half_h + 0.35, mach_z - 0.23), 0.38, 0.04, mat_grille, Vector3(90, 0, 0))

	# Aletas horizontais de ventilação
	for gi in range(7):
		var gy := 0.45 + float(gi) * 0.14
		_box(Vector3(0.0, gy, mach_z - 0.22), Vector3(WIDTH - 0.60, 0.03, 0.03), mat_grille)

	# Caixa de controle de temperatura digital e display
	_box(Vector3(0.65, 1.20, mach_z - 0.24), Vector3(0.32, 0.42, 0.08), mat_frame)
	_box(Vector3(0.65, 1.25, mach_z - 0.285), Vector3(0.14, 0.08, 0.02), mat_indicator)

	# 5. Portas traseiras isotérmicas (+Z)
	var door_z := half_l + 0.01
	_box(Vector3(0.0, half_h, door_z), Vector3(0.02, HEIGHT - 0.28, 0.04), mat_seal)
	for rod_x in [-0.45, -0.15, 0.15, 0.45]:
		_cyl(Vector3(rod_x, half_h, door_z + 0.04), 0.02, HEIGHT - 0.35, mat_grille)
		_box(Vector3(rod_x, 1.15, door_z + 0.07), Vector3(0.04, 0.32, 0.04), mat_grille)

func _box(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi

func _cyl(pos: Vector3, radius: float, height: float, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 14
	mi.mesh = cm
	mi.position = pos
	if rot_deg != Vector3.ZERO:
		mi.rotation_degrees = rot_deg
	mi.material_override = mat
	add_child(mi)
	return mi
