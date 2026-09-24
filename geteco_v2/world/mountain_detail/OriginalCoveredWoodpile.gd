extends Node3D

## Pilha de Lenha Coberta (Covered Firewood Stack 3D):
## Telheiro e depósito rústico de estocagem e secagem de lenha em escala métrica humana (1:1).
## Possui armação de vigas pesadas, cobertura inclinada com espessa camada de neve,
## dezenas de toras cilíndricas e rachadas empilhadas, feixe de gravetos com barbante,
## e toco com machado de rachar lenha e marreta de ferro.

# Contratos de Integração Exigidos:
@export var footprint_size: Vector2 = Vector2(2.4, 1.4)
@export var entrance_local_position: Vector3 = Vector3(0.0, 0.0, 0.7)
@export var entrance_clearance: float = 1.40

# Customização da cor principal antes ou depois de entrar na árvore:
@export var main_color: Color = Color("#4a3525"): set = set_main_color
@export var timber_color: Color = Color("#322217")
@export var snow_color: Color = Color("#f0f4f8")

var _materials: Dictionary = {}
var _is_built: bool = false

func _init(p_main_color: Color = Color("#4a3525")) -> void:
	main_color = p_main_color

func _ready() -> void:
	if not _is_built:
		_build_woodpile()

func set_main_color(new_color: Color) -> void:
	main_color = new_color
	if _materials.has("wood_frame"):
		_materials["wood_frame"].albedo_color = main_color

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

func _build_woodpile() -> void:
	_is_built = true
	var wood_frame := _mat("wood_frame", main_color, 0.85)
	var wood_beam := _mat("wood_beam", timber_color, 0.90)
	var bark_mat := _mat("bark", Color("#2a1b12"), 0.95)
	var cut_end_mat := _mat("cut_end", Color("#dcb274"), 0.65)
	var snow_mat := _mat("snow", snow_color, 0.95)
	var iron_mat := _mat("iron", Color("#202024"), 0.35, 0.85)
	var rope_mat := _mat("rope", Color("#a67c52"), 0.9)

	# 1. Fundação e Longarinas de Base (Elevam a lenha do chão: Y = 0.0 a 0.12)
	_add_box(Vector3(-0.95, 0.06, 0.0), Vector3(0.14, 0.12, 1.10), wood_beam)
	_add_box(Vector3(0.0, 0.06, 0.0), Vector3(0.14, 0.12, 1.10), wood_beam)
	_add_box(Vector3(0.95, 0.06, 0.0), Vector3(0.14, 0.12, 1.10), wood_beam)
	_add_box(Vector3(0.0, 0.14, -0.30), Vector3(2.05, 0.04, 0.16), wood_frame)
	_add_box(Vector3(0.0, 0.14, 0.30), Vector3(2.05, 0.04, 0.16), wood_frame)

	# 2. Quatro Pilares da Estrutura
	_add_box(Vector3(-1.00, 0.98, 0.50), Vector3(0.12, 1.76, 0.12), wood_beam)
	_add_box(Vector3(1.00, 0.98, 0.50), Vector3(0.12, 1.76, 0.12), wood_beam)
	_add_box(Vector3(-1.00, 0.83, -0.50), Vector3(0.12, 1.46, 0.12), wood_beam)
	_add_box(Vector3(1.00, 0.83, -0.50), Vector3(0.12, 1.46, 0.12), wood_beam)

	# Travessas Laterais de Retenção da Lenha (±X)
	for sx in [-1.00, 1.00]:
		_add_box(Vector3(sx, 0.55, 0.0), Vector3(0.08, 0.10, 0.96), wood_frame)
		_add_box(Vector3(sx, 1.05, 0.0), Vector3(0.08, 0.10, 0.96), wood_frame)
		_add_box(Vector3(sx, 1.40, 0.0), Vector3(0.08, 0.10, 0.96), wood_frame)

	# Travessa Traseira de Encosto (-Z = -0.50)
	_add_box(Vector3(0.0, 0.70, -0.50), Vector3(1.95, 0.10, 0.06), wood_frame)
	_add_box(Vector3(0.0, 1.20, -0.50), Vector3(1.95, 0.10, 0.06), wood_frame)

	# 3. Pilha Esculpida de Toras de Lenha (Mix de toras redondas e rachadas)
	var row_configs = [
		{"y": 0.24, "count": 10, "x_start": -0.82, "dx": 0.18, "r": 0.082},
		{"y": 0.40, "count": 9,  "x_start": -0.73, "dx": 0.18, "r": 0.080},
		{"y": 0.56, "count": 10, "x_start": -0.82, "dx": 0.18, "r": 0.078},
		{"y": 0.72, "count": 9,  "x_start": -0.73, "dx": 0.18, "r": 0.076},
		{"y": 0.88, "count": 8,  "x_start": -0.64, "dx": 0.18, "r": 0.075},
		{"y": 1.04, "count": 7,  "x_start": -0.55, "dx": 0.18, "r": 0.072},
		{"y": 1.20, "count": 6,  "x_start": -0.46, "dx": 0.18, "r": 0.070},
		{"y": 1.34, "count": 4,  "x_start": -0.28, "dx": 0.18, "r": 0.068}
	]

	for row in row_configs:
		var ry: float = row["y"]
		var rc: int = row["count"]
		var rx0: float = row["x_start"]
		var rdx: float = row["dx"]
		var rad: float = row["r"]
		for i in range(rc):
			var lx: float = rx0 + float(i) * rdx
			_add_cyl(Vector3(lx, ry, 0.0), rad, 0.80, bark_mat, Vector3(90, 0, 0))
			_add_cyl(Vector3(lx, ry, 0.405), rad * 0.96, 0.015, cut_end_mat, Vector3(90, 0, 0))
			_add_cyl(Vector3(lx, ry, -0.405), rad * 0.96, 0.015, cut_end_mat, Vector3(90, 0, 0))

	# 4. Feixe de Gravetos e Cavacos de Acendimento amarrados na base (+X = 0.85, Z = 0.58)
	var kindling_mat := _mat("kindling", Color("#b88a53"), 0.75)
	_add_box(Vector3(0.85, 0.15, 0.58), Vector3(0.22, 0.22, 0.45), kindling_mat)
	_add_box(Vector3(0.85, 0.15, 0.58), Vector3(0.24, 0.24, 0.03), rope_mat) # Barbante de amarração

	# 5. Vigas de Suporte Superior do Telhado
	_add_box(Vector3(0.0, 1.84, 0.50), Vector3(2.20, 0.12, 0.12), wood_beam)
	_add_box(Vector3(0.0, 1.54, -0.50), Vector3(2.20, 0.12, 0.12), wood_beam)
	_add_box(Vector3(-1.00, 1.69, 0.0), Vector3(0.12, 0.10, 1.15), wood_beam, Vector3(-16.0, 0, 0))
	_add_box(Vector3(1.00, 1.69, 0.0), Vector3(0.12, 0.10, 1.15), wood_beam, Vector3(-16.0, 0, 0))

	# 6. Telhado Inclinado de Tábuas com Beirais Volumétricos
	var roof_thick := _mat("roof_wood", Color("#2c1c12"), 0.85)
	_add_box(Vector3(0.0, 1.76, 0.0), Vector3(2.36, 0.08, 1.34), roof_thick, Vector3(-16.0, 0, 0))

	# 7. Camada Volumétrica de Neve Acumulada no Telhado
	_add_box(Vector3(0.0, 1.83, 0.0), Vector3(2.32, 0.07, 1.30), snow_mat, Vector3(-16.0, 0, 0))
	_add_box(Vector3(0.0, 1.95, 0.64), Vector3(2.32, 0.05, 0.08), snow_mat)
	_add_box(Vector3(0.0, 1.57, -0.64), Vector3(2.32, 0.05, 0.08), snow_mat)

	# 8. Toco de Rachar Lenha com Machado e Cunha de Ferro (Lateral X = -1.45, Z = 0.20)
	var stump_mat := _mat("stump", Color("#3b2618"), 0.9)
	var stump_top := _mat("stump_top", Color("#cfa365"), 0.7)
	_add_cyl(Vector3(-1.45, 0.32, 0.20), 0.24, 0.64, stump_mat)
	_add_cyl(Vector3(-1.45, 0.645, 0.20), 0.23, 0.015, stump_top)
	_add_box(Vector3(-1.45, 0.655, 0.34), Vector3(0.20, 0.02, 0.08), snow_mat)

	# Machado cravado
	var handle_mat := _mat("handle", Color("#bc8a4d"), 0.6)
	_add_box(Vector3(-1.45, 0.92, 0.16), Vector3(0.04, 0.62, 0.05), handle_mat, Vector3(18.0, 0, 0))
	_add_box(Vector3(-1.45, 0.70, 0.23), Vector3(0.05, 0.14, 0.16), iron_mat)
	_add_box(Vector3(-1.45, 0.66, 0.28), Vector3(0.02, 0.10, 0.06), iron_mat)

	# Marreta pesada de forja (Sledgehammer) encostada na lateral do toco
	_add_box(Vector3(-1.45, 0.45, 0.48), Vector3(0.04, 0.85, 0.04), handle_mat, Vector3(22.0, 0, 0))
	_add_box(Vector3(-1.45, 0.10, 0.62), Vector3(0.12, 0.12, 0.20), iron_mat)
