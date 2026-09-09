class_name TrailSignAndBench3D
extends Node3D

## Placa de Trilha e Banco de Madeira (Trail Sign & Wooden Bench 3D):
## Conjunto de descanso e sinalização de trilha alpina em escala métrica humana (1:1).
## Possui banco rústico com assento ergonômico a 0,45 m do solo (proporcional à pessoa de 1,80 m),
## poste com setas de madeira esculpida apontando destinos, marcações de trilha alpina (blazes)
## e acúmulo volumétrico de neve.

# Contratos de Integração Exigidos:
@export var footprint_size: Vector2 = Vector2(2.2, 1.3)
@export var entrance_local_position: Vector3 = Vector3(0.0, 0.0, 0.65)
@export var entrance_clearance: float = 1.20

# Customização da cor principal antes ou depois de entrar na árvore:
@export var main_color: Color = Color("#6b4c35"): set = set_main_color
@export var timber_color: Color = Color("#4a3222")
@export var snow_color: Color = Color("#f0f4f8")

var _materials: Dictionary = {}
var _is_built: bool = false

func _init(p_main_color: Color = Color("#6b4c35")) -> void:
	main_color = p_main_color

func _ready() -> void:
	if not _is_built:
		_build_prop()

func set_main_color(new_color: Color) -> void:
	main_color = new_color
	if _materials.has("wood_bench"):
		_materials["wood_bench"].albedo_color = main_color

func _mat(id: String, color: Color, roughness: float = 0.8, metallic: float = 0.0) -> StandardMaterial3D:
	if _materials.has(id):
		return _materials[id]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	m.shading_mode = StandardMaterial3D.SHADING_MODE_PER_PIXEL
	_materials[id] = m
	return m

func _add_box(pos: Vector3, size: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = mat
	add_child(mi)
	return mi

func _add_cyl(pos: Vector3, radius: float, height: float, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 14
	mi.mesh = cm
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = mat
	add_child(mi)
	return mi

func _build_prop() -> void:
	_is_built = true
	var wood_bench := _mat("wood_bench", main_color, 0.75)
	var wood_post := _mat("wood_post", timber_color, 0.85)
	var wood_sign := _mat("wood_sign", Color("#9c7047"), 0.70)
	var snow_mat := _mat("snow", snow_color, 0.95)
	var iron_mat := _mat("iron", Color("#262629"), 0.4, 0.8)
	var text_mat := _mat("text_cut", Color("#22150b"), 0.9)
	var blaze_red := _mat("blaze_red", Color("#c0392b"), 0.7)
	var blaze_white := _mat("blaze_white", Color("#ecf0f1"), 0.7)

	# 1. BANCO RÚSTICO DE MADEIRA (Assento a exatamente 0,45 m do chão)
	var bx: float = -0.35

	for side in [-1.0, 1.0]:
		var leg_x: float = bx + side * 0.55
		_add_cyl(Vector3(leg_x, 0.22, -0.08), 0.065, 0.44, wood_post, Vector3(-12.0, 0, 0))
		_add_cyl(Vector3(leg_x, 0.22, 0.08), 0.065, 0.44, wood_post, Vector3(12.0, 0, 0))
		_add_box(Vector3(leg_x, 0.16, 0.0), Vector3(0.08, 0.06, 0.32), wood_post)
		_add_box(Vector3(leg_x, 0.55, -0.16), Vector3(0.06, 0.45, 0.06), wood_post, Vector3(-14.0, 0, 0))

	# Assento de prancha maciça lavrada a machado (Y = 0.45 m)
	_add_box(Vector3(bx, 0.45, 0.0), Vector3(1.48, 0.06, 0.38), wood_bench)
	_add_box(Vector3(bx, 0.43, 0.18), Vector3(1.46, 0.03, 0.03), wood_post)

	# Encosto de prancha inclinada (Y = 0.78 m)
	_add_box(Vector3(bx, 0.76, -0.21), Vector3(1.44, 0.18, 0.04), wood_bench, Vector3(-14.0, 0, 0))

	# Neve assentada nos cantos externos
	_add_box(Vector3(bx - 0.62, 0.49, 0.0), Vector3(0.18, 0.03, 0.34), snow_mat)
	_add_box(Vector3(bx + 0.62, 0.49, 0.0), Vector3(0.18, 0.03, 0.34), snow_mat)
	_add_box(Vector3(bx - 0.58, 0.86, -0.23), Vector3(0.24, 0.04, 0.06), snow_mat, Vector3(-14.0, 0, 0))

	# 2. POSTE DE SINALIZAÇÃO DE TRILHA (X = 0.75, Z = -0.10, Altura = 2.15 m)
	var px: float = 0.75
	var pz: float = -0.10

	# Base de pedras de calçamento
	_add_cyl(Vector3(px, 0.06, pz), 0.28, 0.12, _mat("stone_base", Color("#48484a"), 0.95))
	_add_cyl(Vector3(px, 0.12, pz), 0.24, 0.03, snow_mat)

	# Poste de madeira quadrado
	_add_box(Vector3(px, 1.08, pz), Vector3(0.14, 2.14, 0.14), wood_post)

	# Marcação de Trilha Alpina Pintada no Poste (Vermelho-Branco-Vermelho a Y = 1.15m)
	_add_box(Vector3(px, 1.22, pz + 0.071), Vector3(0.09, 0.04, 0.005), blaze_red)
	_add_box(Vector3(px, 1.17, pz + 0.071), Vector3(0.09, 0.04, 0.005), blaze_white)
	_add_box(Vector3(px, 1.12, pz + 0.071), Vector3(0.09, 0.04, 0.005), blaze_red)

	# Tampa chanfrada do poste no topo (Y = 2.16m)
	_add_box(Vector3(px, 2.16, pz), Vector3(0.17, 0.04, 0.17), wood_post)
	_add_box(Vector3(px, 2.20, pz), Vector3(0.15, 0.05, 0.15), snow_mat)

	# 3. TRÊS SETAS DIRECIONAIS DE MADEIRA ENTALHADA
	# Seta 1: Superior (Y = 1.95 m) - "◄ CUME 2.8 KM"
	_add_box(Vector3(px - 0.28, 1.95, pz + 0.08), Vector3(0.68, 0.14, 0.03), wood_sign)
	_add_box(Vector3(px - 0.64, 1.95, pz + 0.08), Vector3(0.10, 0.10, 0.03), wood_sign, Vector3(0, 0, 45.0))
	_add_box(Vector3(px - 0.28, 1.95, pz + 0.096), Vector3(0.50, 0.04, 0.005), text_mat)
	_add_cyl(Vector3(px, 1.95, pz + 0.10), 0.015, 0.02, iron_mat, Vector3(90, 0, 0))
	_add_box(Vector3(px - 0.28, 2.03, pz + 0.08), Vector3(0.66, 0.03, 0.05), snow_mat)

	# Seta 2: Meio (Y = 1.72 m) - "VALE DO CEDRO ►"
	_add_box(Vector3(px + 0.26, 1.72, pz - 0.08), Vector3(0.65, 0.14, 0.03), wood_sign)
	_add_box(Vector3(px + 0.60, 1.72, pz - 0.08), Vector3(0.10, 0.10, 0.03), wood_sign, Vector3(0, 0, 45.0))
	_add_box(Vector3(px + 0.26, 1.72, pz - 0.096), Vector3(0.48, 0.04, 0.005), text_mat)
	_add_cyl(Vector3(px, 1.72, pz - 0.10), 0.015, 0.02, iron_mat, Vector3(90, 0, 0))
	_add_box(Vector3(px + 0.26, 1.80, pz - 0.08), Vector3(0.63, 0.03, 0.05), snow_mat)

	# Seta 3: Inferior (Y = 1.48 m) - "◄ ABRIGO 0.6 KM"
	_add_box(Vector3(px - 0.24, 1.48, pz + 0.08), Vector3(0.58, 0.13, 0.03), wood_sign)
	_add_box(Vector3(px - 0.55, 1.48, pz + 0.08), Vector3(0.09, 0.09, 0.03), wood_sign, Vector3(0, 0, 45.0))
	_add_box(Vector3(px - 0.24, 1.48, pz + 0.096), Vector3(0.42, 0.035, 0.005), text_mat)
	_add_cyl(Vector3(px, 1.48, pz + 0.10), 0.015, 0.02, iron_mat, Vector3(90, 0, 0))
	_add_box(Vector3(px - 0.24, 1.56, pz + 0.08), Vector3(0.56, 0.03, 0.05), snow_mat)
