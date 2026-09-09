class_name PatrolShelter3D
extends Node3D

## Abrigo de Patrulha e Posto de Vigia (Patrol Shelter 3D):
## Refúgio alpino de inverno em escala métrica humana (1:1).
## Possui pórtico frontal aberto com vão livre de 1,30 m, vigas mestras com contraventamento diagonal,
## banco de guarda florestal ergonômico a 0,45 m, bancada com rádio transmissor, prancheta de mapas,
## raquetes de neve na parede, cata-vento no cume e telhado espesso com neve acumulada.

# Contratos de Integração Exigidos:
@export var footprint_size: Vector2 = Vector2(3.0, 2.4)
@export var entrance_local_position: Vector3 = Vector3(0.0, 0.0, 1.2)
@export var entrance_clearance: float = 1.30

# Customização da cor principal antes ou depois de entrar na árvore:
@export var main_color: Color = Color("#3e4a3d"): set = set_main_color
@export var timber_color: Color = Color("#4a321f")
@export var snow_color: Color = Color("#f0f4f8")

var _materials: Dictionary = {}
var _is_built: bool = false

func _init(p_main_color: Color = Color("#3e4a3d")) -> void:
	main_color = p_main_color

func _ready() -> void:
	if not _is_built:
		_build_shelter()

func set_main_color(new_color: Color) -> void:
	main_color = new_color
	if _materials.has("wood_wall"):
		_materials["wood_wall"].albedo_color = main_color

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
	cm.radial_segments = 16
	mi.mesh = cm
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = mat
	add_child(mi)
	return mi

func _build_shelter() -> void:
	_is_built = true
	var wood_wall := _mat("wood_wall", main_color, 0.85)
	var wood_beam := _mat("wood_beam", timber_color, 0.90)
	var wood_floor := _mat("wood_floor", Color("#332215"), 0.80)
	var stone_mat := _mat("stone", Color("#424245"), 0.95)
	var snow_mat := _mat("snow", snow_color, 0.95)
	var iron_mat := _mat("iron", Color("#222225"), 0.5, 0.7)
	var radio_mat := _mat("radio", Color("#273746"), 0.6, 0.4)
	var map_mat := _mat("map_paper", Color("#e5d3b3"), 0.8)

	# 1. Fundação e Piso Elevado (Y = 0.0 a 0.14)
	for cx in [-1.4, 1.4]:
		for cz in [-1.1, 1.1]:
			_add_box(Vector3(cx, 0.07, cz), Vector3(0.35, 0.14, 0.35), stone_mat)

	# Soalho de pranchas rústicas
	_add_box(Vector3(0.0, 0.10, 0.0), Vector3(2.85, 0.08, 2.25), wood_floor)

	# Degrau de entrada em +Z (frente desobstruída)
	_add_box(Vector3(0.0, 0.05, 1.20), Vector3(1.50, 0.10, 0.28), wood_beam)

	# 2. Quatro Pilares Mestres de Canto (X = ±1.35, Z = ±1.05, altura Y = 2.40m)
	var post_h: float = 2.40
	for px in [-1.35, 1.35]:
		for pz in [-1.05, 1.05]:
			_add_box(Vector3(px, 0.14 + post_h * 0.5, pz), Vector3(0.18, post_h, 0.18), wood_beam)

	# Vigas de coroamento superiores (amarração perimetral)
	_add_box(Vector3(0.0, 2.50, -1.05), Vector3(2.88, 0.16, 0.18), wood_beam)
	_add_box(Vector3(0.0, 2.50, 1.05), Vector3(2.88, 0.16, 0.18), wood_beam)
	_add_box(Vector3(-1.35, 2.50, 0.0), Vector3(0.18, 0.16, 2.28), wood_beam)
	_add_box(Vector3(1.35, 2.50, 0.0), Vector3(0.18, 0.16, 2.28), wood_beam)

	# 3. Paredes de Tábuas Verticais nos Fundos (-Z) e Laterais (±X)
	_add_box(Vector3(0.0, 1.30, -1.05), Vector3(2.52, 2.24, 0.10), wood_wall)
	_add_box(Vector3(0.0, 1.30, -1.12), Vector3(2.54, 0.08, 0.05), wood_beam)

	for sx in [-1.35, 1.35]:
		_add_box(Vector3(sx, 1.15, 0.0), Vector3(0.10, 1.95, 1.92), wood_wall)
		_add_box(Vector3(sx + (0.06 if sx > 0 else -0.06), 1.15, 0.0), Vector3(0.04, 0.10, 2.10), wood_beam, Vector3(32.0, 0, 0))

	# 4. Fachada Frontal Aberta (+Z = 1.05): Guarda-corpo lateral e vão central livre
	_add_box(Vector3(-1.02, 0.60, 1.05), Vector3(0.65, 0.85, 0.10), wood_wall)
	_add_box(Vector3(-1.02, 1.05, 1.05), Vector3(0.70, 0.08, 0.14), wood_beam)
	_add_box(Vector3(1.02, 0.60, 1.05), Vector3(0.65, 0.85, 0.10), wood_wall)
	_add_box(Vector3(1.02, 1.05, 1.05), Vector3(0.70, 0.08, 0.14), wood_beam)

	# Batentes do pórtico frontal delimitando a passagem livre (1.30 m de vão livre)
	_add_box(Vector3(-0.68, 1.30, 1.05), Vector3(0.12, 2.25, 0.14), wood_beam)
	_add_box(Vector3(0.68, 1.30, 1.05), Vector3(0.12, 2.25, 0.14), wood_beam)
	_add_box(Vector3(0.0, 2.25, 1.05), Vector3(1.48, 0.14, 0.14), wood_beam)

	# 5. Mobiliário e Detalhes Internos de Patrulha
	# Banco rústico na parede dos fundos (Y = 0.45m - escala ergonômica exata de 1,80m)
	var bench_mat := _mat("bench", Color("#422b18"), 0.75)
	_add_box(Vector3(0.0, 0.45, -0.80), Vector3(2.10, 0.06, 0.38), bench_mat)
	_add_box(Vector3(-0.80, 0.22, -0.80), Vector3(0.10, 0.40, 0.32), wood_beam)
	_add_box(Vector3(0.80, 0.22, -0.80), Vector3(0.10, 0.40, 0.32), wood_beam)
	_add_box(Vector3(0.0, 0.75, -0.96), Vector3(2.00, 0.18, 0.04), bench_mat)

	# Raquetes de Neve (Snowshoes) penduradas na parede dos fundos acima do banco
	for r_x in [-0.45, -0.15]:
		_add_box(Vector3(r_x, 1.45, -0.98), Vector3(0.18, 0.55, 0.02), wood_beam, Vector3(0, 0, 15.0))
		_add_box(Vector3(r_x, 1.45, -0.96), Vector3(0.12, 0.45, 0.01), iron_mat, Vector3(0, 0, 15.0)) # Amarração de tiras

	# Prateleira / Bancada de vigia na parede direita (+X)
	_add_box(Vector3(1.15, 1.05, 0.20), Vector3(0.32, 0.05, 0.90), bench_mat)
	_add_box(Vector3(1.15, 0.88, 0.20), Vector3(0.06, 0.28, 0.06), wood_beam, Vector3(0, 0, -45.0))

	# Rádio militar/florestal com antena telescópica na bancada
	_add_box(Vector3(1.15, 1.18, 0.40), Vector3(0.20, 0.16, 0.24), radio_mat)
	_add_cyl(Vector3(1.15, 1.42, 0.48), 0.008, 0.42, iron_mat) # Antena
	_add_box(Vector3(1.04, 1.18, 0.40), Vector3(0.02, 0.08, 0.16), iron_mat) # Painel frontal com dials

	# Prancheta com mapa topográfico de montanha na bancada
	_add_box(Vector3(1.15, 1.09, -0.05), Vector3(0.22, 0.015, 0.30), wood_beam)
	_add_box(Vector3(1.15, 1.105, -0.05), Vector3(0.18, 0.005, 0.26), map_mat)

	# Gancho de lanterna de ferro forjado no pilar frontal esquerdo
	_add_box(Vector3(-0.62, 1.85, 1.10), Vector3(0.04, 0.04, 0.16), iron_mat)
	_add_cyl(Vector3(-0.62, 1.72, 1.16), 0.055, 0.14, iron_mat)

	# 6. TELHADO INCLINADO COM CAIBROS E BEIRAIS
	var roof_mat := _mat("shelter_roof", Color("#2a1d13"), 0.85)
	var r_len: float = 2.65
	var r_w: float = 3.30

	_add_box(Vector3(0.0, 2.70, 0.35), Vector3(r_w, 0.10, 1.45), roof_mat, Vector3(18.0, 0, 0))
	_add_box(Vector3(0.0, 2.70, -0.45), Vector3(r_w, 0.10, 1.55), roof_mat, Vector3(-24.0, 0, 0))
	_add_box(Vector3(0.0, 2.92, -0.05), Vector3(r_w + 0.08, 0.14, 0.16), wood_beam)

	# 7. CAMADA VOLUMÉTRICA DE NEVE NO TELHADO
	_add_box(Vector3(0.0, 2.78, 0.35), Vector3(r_w * 0.98, 0.08, 1.42), snow_mat, Vector3(18.0, 0, 0))
	_add_box(Vector3(0.0, 2.78, -0.45), Vector3(r_w * 0.98, 0.09, 1.52), snow_mat, Vector3(-24.0, 0, 0))
	_add_box(Vector3(0.0, 3.01, -0.05), Vector3(r_w, 0.10, 0.28), snow_mat)

	_add_box(Vector3(0.0, 2.45, -1.22), Vector3(r_w * 0.96, 0.06, 0.10), snow_mat)
	_add_box(Vector3(0.0, 2.46, 1.15), Vector3(r_w * 0.96, 0.06, 0.10), snow_mat)

	# 8. CATA-VENTO / ANEMÔMETRO METEOROLÓGICO NO CUME DO TELHADO (X = 0, Z = -0.05, Y = 3.1 a 3.65)
	_add_cyl(Vector3(0.0, 3.25, -0.05), 0.015, 0.45, iron_mat) # Haste vertical
	_add_box(Vector3(0.0, 3.48, -0.05), Vector3(0.38, 0.02, 0.02), iron_mat) # Braço horizontal N-S
	_add_box(Vector3(0.0, 3.48, -0.05), Vector3(0.02, 0.02, 0.38), iron_mat) # Braço horizontal E-W
	_add_box(Vector3(0.08, 3.56, -0.05), Vector3(0.28, 0.06, 0.01), iron_mat, Vector3(0, 25.0, 0)) # Seta do cata-vento
