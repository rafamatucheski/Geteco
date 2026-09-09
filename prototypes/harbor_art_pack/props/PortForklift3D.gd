class_name PortForklift3D
extends Node3D

## Empilhadeira industrial portuária decorativa contrabalançada.
## Detalhes: chassi robusto, contrapeso traseiro, mastro duplo com cilindros hidráulicos,
## garfos de aço forjado, gaiola de segurança ROPS, assento, volante e pneus industriais maciços.
## Dimensões totais: 1.25m largura x 2.25m altura x 3.50m comprimento (incluindo garfos).
## Origem no piso Y=0, centrado em X, chassi de Z=-1.80m até Z=+0.60m, garfos até Z=+1.70m.

const WIDTH: float = 1.25
const HEIGHT: float = 2.25
const TOTAL_LENGTH: float = 3.50

var _obstacle_bounds: Array[AABB] = []
var _is_built: bool = false

func _ready() -> void:
	if not _is_built:
		_build_model()

func get_dimensions() -> Vector3:
	return Vector3(WIDTH, HEIGHT, TOTAL_LENGTH)

func get_obstacle_bounds() -> Array[AABB]:
	if not _is_built:
		_build_model()
	return _obstacle_bounds.duplicate()

func _build_model() -> void:
	_is_built = true
	_obstacle_bounds.clear()
	_obstacle_bounds.append(AABB(Vector3(-WIDTH * 0.5, 0.0, -1.80), Vector3(WIDTH, HEIGHT, TOTAL_LENGTH)))

	var mat_orange := PortArtMaterials.forklift_orange()
	var mat_dark := PortArtMaterials.steel_dark()
	var mat_hardware := PortArtMaterials.steel_galvanized()
	var mat_rubber := PortArtMaterials.rubber_black()
	var mat_strobe := PortArtMaterials.safety_yellow()
	var mat_light := PortArtMaterials.floodlight_emission()

	var half_w := WIDTH * 0.5

	# 1. Chassi principal inferior
	_box(Vector3(0.0, 0.42, -0.50), Vector3(1.10, 0.45, 1.90), mat_orange)
	# Capô do motor traseiro
	_box(Vector3(0.0, 0.72, -0.85), Vector3(1.00, 0.35, 1.10), mat_orange)

	# 2. Contrapeso maciço traseiro com engate
	_box(Vector3(0.0, 0.50, -1.55), Vector3(1.18, 0.60, 0.35), mat_dark)
	# Pino de reboque no contrapeso
	_cyl(Vector3(0.0, 0.45, -1.74), 0.03, 0.18, mat_hardware)

	# 3. Rodas e Eixos
	# Rodas dianteiras de tração maiores (Z = 0.35, raio 0.33, Y = 0.33)
	var front_r := 0.33
	var front_th := 0.16
	for wx in [-half_w + 0.08, half_w - 0.08]:
		_cyl(Vector3(wx, front_r, 0.35), front_r, front_th, mat_rubber, Vector3(0, 0, 90))
		_cyl(Vector3(wx + (0.01 if wx > 0 else -0.01), front_r, 0.35), front_r * 0.55, front_th + 0.01, mat_dark, Vector3(0, 0, 90))

	# Rodas traseiras direcionais menores (Z = -1.25, raio 0.25, Y = 0.25)
	var rear_r := 0.25
	var rear_th := 0.14
	for wx in [-half_w + 0.10, half_w - 0.10]:
		_cyl(Vector3(wx, rear_r, -1.25), rear_r, rear_th, mat_rubber, Vector3(0, 0, 90))
		_cyl(Vector3(wx + (0.01 if wx > 0 else -0.01), rear_r, -1.25), rear_r * 0.55, rear_th + 0.01, mat_dark, Vector3(0, 0, 90))

	# 4. Gaiola de Proteção do Operador (ROPS Overhead Guard)
	var cage_h := 2.10
	var cage_w := 0.96
	var cage_half_w := cage_w * 0.5

	# Quatro pilares da cabine
	for cx in [-cage_half_w, cage_half_w]:
		# Pilar dianteiro
		_cyl(Vector3(cx, 1.35, 0.10), 0.025, 1.45, mat_dark)
		# Pilar traseiro inclinado
		_cyl(Vector3(cx, 1.35, -1.15), 0.025, 1.45, mat_dark)

	# Teto com grelha de barras de proteção
	_box(Vector3(0.0, cage_h, -0.52), Vector3(cage_w, 0.04, 1.35), mat_dark)
	for gi in range(6):
		var gz := -1.10 + float(gi) * 0.20
		_box(Vector3(0.0, cage_h + 0.02, gz), Vector3(cage_w - 0.06, 0.03, 0.04), mat_dark)

	# Giroflex/Luz estroboscópica no teto
	_cyl(Vector3(0.0, cage_h + 0.10, -0.52), 0.07, 0.12, mat_strobe)

	# Faróis auxiliares de trabalho na frente do teto
	for fx in [-cage_half_w + 0.10, cage_half_w - 0.10]:
		_box(Vector3(fx, cage_h - 0.08, 0.12), Vector3(0.12, 0.08, 0.06), mat_dark)
		_box(Vector3(fx, cage_h - 0.08, 0.155), Vector3(0.10, 0.06, 0.01), mat_light)

	# 5. Cabine do Motorista (Assento, Volante, Painel)
	# Assento anatômico
	_box(Vector3(0.0, 0.75, -0.45), Vector3(0.48, 0.10, 0.44), mat_rubber) # assento
	_box(Vector3(0.0, 1.05, -0.65), Vector3(0.46, 0.50, 0.08), mat_rubber) # encosto
	# Painel de instrumentos e coluna de direção
	_box(Vector3(0.0, 0.85, -0.05), Vector3(0.60, 0.35, 0.25), mat_dark)
	# Coluna e volante inclinado
	_cyl(Vector3(-0.08, 1.12, -0.15), 0.02, 0.32, mat_dark, Vector3(-35, 0, 0))
	_cyl(Vector3(-0.08, 1.25, -0.25), 0.18, 0.03, mat_rubber, Vector3(-35, 0, 0))
	# Alavancas de comando hidráulico
	for li in range(3):
		_cyl(Vector3(0.16 + float(li) * 0.05, 1.15, -0.12), 0.008, 0.22, mat_hardware, Vector3(-20, 0, 0))

	# 6. Mastro de Elevação Frontal (Duas vigas I verticais em Z = 0.65m)
	var mast_z := 0.65
	var mast_h := 2.25
	for mx in [-0.40, 0.40]:
		_box(Vector3(mx, mast_h * 0.5, mast_z), Vector3(0.08, mast_h, 0.12), mat_dark)

	# Travessas horizontais do mastro
	_box(Vector3(0.0, 0.40, mast_z), Vector3(0.88, 0.08, 0.06), mat_dark)
	_box(Vector3(0.0, mast_h - 0.10, mast_z), Vector3(0.88, 0.08, 0.06), mat_dark)

	# Cilindro hidráulico central de elevação
	_cyl(Vector3(0.0, 1.05, mast_z - 0.04), 0.045, 1.60, mat_hardware)

	# 7. Carro de Carga e Garfos de Aço Forjado
	var carriage_z := mast_z + 0.08
	# Grade protetora do carro de carga (Load backrest)
	_box(Vector3(0.0, 0.60, carriage_z), Vector3(0.92, 0.80, 0.04), mat_dark)

	# Dois garfos de aço forjado em 'L'
	for fork_x in [-0.28, 0.28]:
		# Parte vertical do garfo (engatada no carro)
		_box(Vector3(fork_x, 0.45, carriage_z + 0.03), Vector3(0.10, 0.70, 0.04), mat_dark)
		# Lâmina horizontal do garfo (projetando-se para frente até Z=1.70m)
		var blade_l := 1.05
		_box(Vector3(fork_x, 0.04, carriage_z + 0.05 + blade_l * 0.5), Vector3(0.10, 0.04, blade_l), mat_dark)
		# Ponta chanfrada do garfo
		_box(Vector3(fork_x, 0.035, carriage_z + 0.05 + blade_l), Vector3(0.09, 0.02, 0.06), mat_dark)

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
