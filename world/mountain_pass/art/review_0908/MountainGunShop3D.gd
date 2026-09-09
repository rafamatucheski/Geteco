class_name MountainGunShop3D
extends Node3D

## Fachada da Loja de Armas de Montanha (Mountain Gun Shop 3D):
## Modelo arquitetural exterior de inverno em escala métrica humana (1:1).
## Apresenta fundação de pedra de cantaria, alpendre frontal com vigas maciças,
## letreiro proeminente com cruz de mira e brasão de armas, vitrines com grades de ferro forjado,
## caixas de munição militar, alvos de tiro na varanda e telhado alpino com espessa camada de neve.

# Contratos de Integração:
@export var footprint_size: Vector2 = Vector2(8.6, 6.4)
@export var entrance_local_position: Vector3 = Vector3(0.0, 0.0, 3.2)
@export var entrance_clearance: float = 1.30

# Customização da cor principal:
@export var main_color: Color = Color("#2d3b32"): set = set_main_color
@export var trim_color: Color = Color("#422b18")
@export var accent_color: Color = Color("#c0392b")
@export var snow_color: Color = Color("#f0f4f8")

var _materials: Dictionary = {}
var _is_built: bool = false

func _init(p_main_color: Color = Color("#2d3b32")) -> void:
	main_color = p_main_color

func _ready() -> void:
	if not _is_built:
		_build_model()

func set_main_color(new_color: Color) -> void:
	main_color = new_color
	if _materials.has("wall_wood"):
		_materials["wall_wood"].albedo_color = main_color

func _mat(id: String, color: Color, roughness: float = 0.8, metallic: float = 0.0, glow: float = 0.0) -> StandardMaterial3D:
	if _materials.has(id):
		return _materials[id]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	m.shading_mode = StandardMaterial3D.SHADING_MODE_PER_PIXEL
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
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

func _build_model() -> void:
	_is_built = true

	# Materiais PBR
	var wall_mat := _mat("wall_wood", main_color, 0.85)
	var trim_mat := _mat("trim_wood", trim_color, 0.90)
	var deck_mat := _mat("deck_wood", Color("#3d2716"), 0.80)
	var stone_mat := _mat("stone_base", Color("#3e3f42"), 0.95)
	var roof_mat := _mat("roof_slate", Color("#26292d"), 0.85)
	var snow_mat := _mat("snow", snow_color, 0.95)
	var iron_mat := _mat("iron", Color("#1c1c1e"), 0.35, 0.85)
	var gold_mat := _mat("gold_trim", Color("#f1c40f"), 0.35, 0.80)
	var red_mat := _mat("sign_red", accent_color, 0.70)
	var glass_mat := _mat("display_glass", Color(0.72, 0.84, 0.90, 0.85), 0.15)
	var ammo_green := _mat("ammo_crate", Color("#3d4a2f"), 0.75)
	var target_mat := _mat("paper_target", Color("#e8e0cc"), 0.9)
	var bullseye_mat := _mat("bullseye", Color("#c0392b"), 0.8)

	var b_w: float = 8.2  # Largura do corpo principal
	var b_d: float = 4.4  # Profundidade do corpo (Z de -2.2 a +2.2)
	var b_h: float = 3.2  # Altura das paredes

	# ==============================================================================
	# 1. FUNDAÇÃO DE PEDRA DE CANTARIA (Y = 0.0 a 0.28)
	# ==============================================================================
	_add_box(Vector3(0.0, 0.14, 0.0), Vector3(b_w + 0.3, 0.28, b_d + 0.3), stone_mat)

	# Deck da Varanda Frontal (Z = 2.2 a 3.2)
	_add_box(Vector3(0.0, 0.14, 2.70), Vector3(b_w + 0.4, 0.28, 1.20), deck_mat)
	# Degrau de entrada rústico no centro (+Z = 3.25, Y = 0.0 a 0.14)
	_add_box(Vector3(0.0, 0.07, 3.35), Vector3(1.60, 0.14, 0.40), deck_mat)

	# ==============================================================================
	# 2. PAREDES PRINCIPAIS (TÁBUAS DE PINHO DE MONTANHA)
	# ==============================================================================
	# Paredes laterais (X = ±4.1)
	for sx in [-4.1, 4.1]:
		_add_box(Vector3(sx, 0.28 + b_h * 0.5, 0.0), Vector3(0.20, b_h, b_d), wall_mat)
		# Frisos e tábuas horizontais
		for y_step in [1.0, 1.8, 2.6]:
			_add_box(Vector3(sx + (0.11 if sx > 0 else -0.11), y_step, 0.0), Vector3(0.04, 0.08, b_d + 0.05), trim_mat)

	# Parede traseira fechada (-Z = -2.2)
	_add_box(Vector3(0.0, 0.28 + b_h * 0.5, -2.2), Vector3(b_w, b_h, 0.20), wall_mat)

	# Pilares estruturais nos 4 cantos
	for cx in [-4.1, 4.1]:
		for cz in [-2.2, 2.2]:
			_add_box(Vector3(cx, 0.28 + b_h * 0.5, cz), Vector3(0.28, b_h, 0.28), trim_mat)

	# ==============================================================================
	# 3. FACHADA FRONTAL (+Z = 2.2): VITRINES COM GRADES E ENTRADA
	# ==============================================================================
	# Painel esquerdo (vitrine 1)
	_add_box(Vector3(-2.6, 0.28 + b_h * 0.5, 2.2), Vector3(3.0, b_h, 0.20), wall_mat)
	# Painel direito (vitrine 2)
	_add_box(Vector3(2.6, 0.28 + b_h * 0.5, 2.2), Vector3(3.0, b_h, 0.20), wall_mat)
	# Viga sobre a porta central (Y: 2.45 a 3.48)
	_add_box(Vector3(0.0, 2.96, 2.2), Vector3(2.20, 1.04, 0.20), wall_mat)

	# Aberturas das 2 Grandes Vitrines de Exposição
	for side in [-1.0, 1.0]:
		var vx: float = side * 2.5
		# Moldura da vitrine
		_add_box(Vector3(vx, 1.65, 2.22), Vector3(2.20, 1.50, 0.12), trim_mat)
		# Vidro temperado com reflexo
		_add_box(Vector3(vx, 1.65, 2.23), Vector3(1.96, 1.30, 0.02), glass_mat)
		# Peitoril de madeira da vitrine
		_add_box(Vector3(vx, 0.90, 2.28), Vector3(2.26, 0.08, 0.22), trim_mat)
		_add_box(Vector3(vx, 0.94, 2.28), Vector3(2.20, 0.03, 0.18), snow_mat)

		# Grades de Segurança de Ferro Forjado (Barras verticais e horizontais)
		for bar_i in range(5):
			var bx: float = vx - 0.75 + float(bar_i) * 0.375
			_add_cyl(Vector3(bx, 1.65, 2.30), 0.014, 1.35, iron_mat)
		_add_box(Vector3(vx, 1.30, 2.30), Vector3(2.00, 0.03, 0.03), iron_mat)
		_add_box(Vector3(vx, 2.00, 2.30), Vector3(2.00, 0.03, 0.03), iron_mat)

		# Silhueta de armas em exposição dentro da vitrine
		_add_box(Vector3(vx, 1.60, 2.15), Vector3(1.20, 0.14, 0.04), iron_mat) # Rifle
		_add_box(Vector3(vx, 1.80, 2.15), Vector3(0.85, 0.12, 0.04), iron_mat) # Carabina

	# ==============================================================================
	# 4. PORTA DE ENTRADA REFORÇADA (Largura 1.30 m, Altura 2.15 m)
	# ==============================================================================
	# Batentes maciços de madeira
	_add_box(Vector3(-0.70, 1.25, 2.24), Vector3(0.12, 2.20, 0.14), trim_mat)
	_add_box(Vector3(0.70, 1.25, 2.24), Vector3(0.12, 2.20, 0.14), trim_mat)
	_add_box(Vector3(0.0, 2.38, 2.24), Vector3(1.52, 0.14, 0.14), trim_mat)

	# Folha da porta com reforços de aço e tachas
	var door_mat := _mat("gun_door", Color("#332014"), 0.8)
	_add_box(Vector3(0.0, 1.22, 2.18), Vector3(1.28, 2.12, 0.08), door_mat)
	# Chapa de proteção de aço na base da porta (Kick plate)
	_add_box(Vector3(0.0, 0.45, 2.23), Vector3(1.20, 0.35, 0.02), iron_mat)
	# Janelinha com grade na porta
	_add_box(Vector3(0.0, 1.70, 2.23), Vector3(0.35, 0.35, 0.03), iron_mat)
	# Puxador industrial de ferro
	_add_box(Vector3(0.48, 1.15, 2.24), Vector3(0.04, 0.24, 0.05), iron_mat)

	# ==============================================================================
	# 5. ALPENDRE FRONTAL COM PILARES DE VIGAS MACIÇAS (Z = 3.20)
	# ==============================================================================
	for px in [-3.9, -1.3, 1.3, 3.9]:
		# Pilar de sustentação
		_add_box(Vector3(px, 1.45, 3.20), Vector3(0.18, 2.62, 0.18), trim_mat)
		# Mão-francesa diagonal no topo
		_add_box(Vector3(px, 2.55, 3.00), Vector3(0.10, 0.10, 0.42), trim_mat, Vector3(-35.0, 0, 0))

	# Viga mestre transversal do alpendre
	_add_box(Vector3(0.0, 2.76, 3.20), Vector3(b_w + 0.4, 0.16, 0.18), trim_mat)

	# Cobertura do alpendre inclinada (caimento para a frente)
	_add_box(Vector3(0.0, 2.92, 2.72), Vector3(b_w + 0.5, 0.08, 1.30), roof_mat, Vector3(15.0, 0, 0))
	_add_box(Vector3(0.0, 2.98, 2.72), Vector3(b_w + 0.46, 0.07, 1.26), snow_mat, Vector3(15.0, 0, 0))

	# Lanternas alpinas com luz âmbar nos pilares do alpendre
	for lx in [-1.3, 1.3]:
		_add_box(Vector3(lx, 2.0, 3.32), Vector3(0.04, 0.04, 0.14), iron_mat)
		_add_cyl(Vector3(lx, 1.88, 3.38), 0.06, 0.16, _mat("lantern_glow", Color("#f39c12"), 0.3, 0.0, 1.5))

	# ==============================================================================
	# 6. LETREIRO MONUMENTAL DA LOJA DE ARMAS (AMMU-NATION / TIMBER RIDGE GUNS)
	# ==============================================================================
	# Painel vermelho central sobre a porta (Y = 2.90, Z = 2.32)
	_add_box(Vector3(0.0, 2.95, 2.32), Vector3(4.20, 0.85, 0.06), red_mat)
	# Moldura dourada elegante
	_add_box(Vector3(0.0, 2.95, 2.34), Vector3(4.24, 0.05, 0.04), gold_mat)
	_add_box(Vector3(0.0, 2.55, 2.34), Vector3(4.24, 0.05, 0.04), gold_mat)
	_add_box(Vector3(0.0, 3.35, 2.34), Vector3(4.24, 0.05, 0.04), gold_mat)
	_add_box(Vector3(-2.10, 2.95, 2.34), Vector3(0.05, 0.85, 0.04), gold_mat)
	_add_box(Vector3(2.10, 2.95, 2.34), Vector3(0.05, 0.85, 0.04), gold_mat)

	# Emblema central de Cruz de Mira e Rifle Dourado
	_add_cyl(Vector3(0.0, 2.95, 2.36), 0.22, 0.02, gold_mat, Vector3(90, 0, 0))
	_add_cyl(Vector3(0.0, 2.95, 2.37), 0.16, 0.02, red_mat, Vector3(90, 0, 0))
	_add_box(Vector3(0.0, 2.95, 2.38), Vector3(0.38, 0.03, 0.02), gold_mat) # Retículo horizontal
	_add_box(Vector3(0.0, 2.95, 2.38), Vector3(0.03, 0.38, 0.02), gold_mat) # Retículo vertical
	# Faixas com texto entalhado simulado
	_add_box(Vector3(-1.10, 2.95, 2.36), Vector3(1.50, 0.24, 0.02), gold_mat)
	_add_box(Vector3(1.10, 2.95, 2.36), Vector3(1.50, 0.24, 0.02), gold_mat)

	# Galhada de Cervo (Antlers) entalhada acima do letreiro
	_add_box(Vector3(0.0, 3.52, 2.32), Vector3(0.20, 0.16, 0.06), trim_mat)
	_add_cyl(Vector3(-0.25, 3.68, 2.35), 0.02, 0.35, _mat("antler", Color("#d5cbb8"), 0.8), Vector3(0, 0, -35.0))
	_add_cyl(Vector3(0.25, 3.68, 2.35), 0.02, 0.35, _mat("antler", Color("#d5cbb8"), 0.8), Vector3(0, 0, 35.0))

	# ==============================================================================
	# 7. ADEREÇOS EXTERIORES NA VARANDA (CAIXAS DE MUNIÇÃO E ALVOS)
	# ==============================================================================
	# Pilha de caixas militares verdes de munição na lateral esquerda da varanda (X = -3.2, Z = 2.8)
	_add_box(Vector3(-3.2, 0.42, 2.70), Vector3(0.55, 0.28, 0.35), ammo_green)
	_add_box(Vector3(-3.2, 0.42, 2.70), Vector3(0.57, 0.04, 0.04), iron_mat) # Fechos
	_add_box(Vector3(-3.2, 0.68, 2.70), Vector3(0.52, 0.24, 0.32), ammo_green)
	_add_box(Vector3(-3.2, 0.88, 2.70), Vector3(0.48, 0.03, 0.28), snow_mat)

	# Alvo humanoide de silhueta de estande na lateral direita da varanda (X = 3.2, Z = 2.7)
	_add_box(Vector3(3.2, 0.35, 2.70), Vector3(0.08, 0.70, 0.08), trim_mat) # Tripé
	_add_box(Vector3(3.2, 1.15, 2.70), Vector3(0.45, 0.65, 0.03), target_mat) # Silhueta
	_add_cyl(Vector3(3.2, 1.20, 2.72), 0.12, 0.01, bullseye_mat, Vector3(90, 0, 0)) # Centro
	_add_cyl(Vector3(3.2, 1.20, 2.73), 0.04, 0.01, gold_mat, Vector3(90, 0, 0))     # Ponto 10

	# ==============================================================================
	# 8. OITÕES TRIANGULARES E TELHADO ALPINO COM ESPESSA CAMADA DE NEVE
	# ==============================================================================
	for sz in [-2.2, 2.2]:
		_add_box(Vector3(0.0, 3.75, sz), Vector3(5.8, 0.65, 0.18), wall_mat)
		_add_box(Vector3(0.0, 4.25, sz), Vector3(3.2, 0.55, 0.18), wall_mat)
		_add_box(Vector3(0.0, 4.65, sz), Vector3(1.2, 0.40, 0.18), wall_mat)

	# Telhado em Duas Águas (Caimento lateral a ~32 graus, Cume a Y = 4.85m)
	var r_len: float = b_d + 1.20 # 5.60m de comprimento Z com beirais
	var r_w: float = 5.20        # Largura da água

	_add_box(Vector3(-2.25, 4.10, 0.0), Vector3(r_w, 0.14, r_len), roof_mat, Vector3(0, 0, 32.0))
	_add_box(Vector3(2.25, 4.10, 0.0), Vector3(r_w, 0.14, r_len), roof_mat, Vector3(0, 0, -32.0))

	# Cumeeira central reforçada
	_add_box(Vector3(0.0, 4.90, 0.0), Vector3(0.24, 0.22, r_len + 0.10), trim_mat)

	# Caibros decorativos sob os beirais frontais e traseiros
	for fz in [-2.35, 2.35]:
		for rx in [-3.8, -2.4, -1.0, 0.0, 1.0, 2.4, 3.8]:
			var ry: float = 4.80 - absf(rx) * 0.62
			_add_box(Vector3(rx, ry - 0.10, fz), Vector3(0.10, 0.12, 0.32), trim_mat)

	# Camada volumétrica espessa de neve nas duas águas
	_add_box(Vector3(-2.25, 4.20, 0.0), Vector3(r_w * 0.98, 0.10, r_len * 0.98), snow_mat, Vector3(0, 0, 32.0))
	_add_box(Vector3(2.25, 4.20, 0.0), Vector3(r_w * 0.98, 0.10, r_len * 0.98), snow_mat, Vector3(0, 0, -32.0))
	_add_box(Vector3(0.0, 5.02, 0.0), Vector3(0.40, 0.12, r_len), snow_mat)

	# Beirais de neve pendentes (Snow Drifts) nas bordas laterais
	for sx in [-4.40, 4.40]:
		_add_box(Vector3(sx, 3.10, 0.0), Vector3(0.16, 0.10, r_len * 0.95), snow_mat)

	# Chaminé de Tijolo/Pedra nos Fundos (X = 2.8, Z = -1.4, Y = 5.2m)
	_add_box(Vector3(2.8, 4.40, -1.4), Vector3(0.55, 1.80, 0.55), stone_mat)
	_add_box(Vector3(2.8, 5.35, -1.4), Vector3(0.65, 0.12, 0.65), iron_mat) # Chapéu de chaminé
	_add_box(Vector3(2.8, 5.42, -1.4), Vector3(0.60, 0.06, 0.60), snow_mat)
