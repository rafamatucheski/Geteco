class_name MountainGunShopInterior3D
extends Node3D

## Interior da Loja de Armas de Montanha (Mountain Gun Shop Interior 3D):
## Cenário volumétrico de interior em escala métrica humana (1:1).
## Apresenta balcão de atendimento com vitrines de vidro para pistolas e munições,
## estantes de parede repletas de fuzis e espingardas, bancada de armeiro com morsa e peças desmontadas,
## estande de tiro indoor com alvos de silhueta e sandbags, fogão a lenha de ferro fundido e cofre militar.

@export var room_size: Vector3 = Vector3(9.6, 3.4, 7.6)
@export var main_color: Color = Color("#4a321f"): set = set_main_color
@export var trim_color: Color = Color("#2a1b12")
@export var counter_color: Color = Color("#5a3d28")

var _materials: Dictionary = {}
var _is_built: bool = false

func _init(p_main_color: Color = Color("#4a321f")) -> void:
	main_color = p_main_color

func _ready() -> void:
	if not _is_built:
		_build_interior()

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

func _build_interior() -> void:
	_is_built = true

	# Paleta de materiais do interior
	var wall_mat := _mat("wall_wood", main_color, 0.85)
	var trim_mat := _mat("trim_wood", trim_color, 0.90)
	var floor_mat := _mat("floor_wood", Color("#3b2617"), 0.75)
	var counter_mat := _mat("counter_wood", counter_color, 0.70)
	var slate_top := _mat("counter_slate", Color("#272b30"), 0.50)
	var glass_mat := _mat("showcase_glass", Color(0.75, 0.88, 0.95, 0.75), 0.15)
	var iron_mat := _mat("gun_steel", Color("#212124"), 0.35, 0.85)
	var steel_mat := iron_mat
	var stone_mat := _mat("stove_stone", Color("#555653"), 0.95)
	var stock_wood := _mat("rifle_stock", Color("#824921"), 0.65)
	var brass_mat := _mat("ammo_brass", Color("#d4ac0d"), 0.30, 0.90)
	var ammo_green := _mat("ammo_tin", Color("#3d4a2f"), 0.75)
	var target_paper := _mat("target_paper", Color("#f4ede2"), 0.90)
	var target_red := _mat("target_red", Color("#c0392b"), 0.80)
	var sandbag_mat := _mat("sandbag", Color("#c4a47c"), 0.95)
	var foam_acoustic := _mat("acoustic_foam", Color("#1f2421"), 0.95)
	var lamp_glow := _mat("banker_glow", Color("#0a5c36"), 0.4, 0.0, 1.2)

	var rw: float = room_size.x
	var rh: float = room_size.y
	var rd: float = room_size.z

	# ==============================================================================
	# 1. ENVOLTÓRIA: PISO, PAREDES E ESTRUTURA CUTAWAY
	# ==============================================================================
	# Piso de tábuas de cedro enceradas
	_add_box(Vector3(0.0, 0.05, 0.0), Vector3(rw, 0.10, rd), floor_mat)

	# Parede Traseira (-Z = -rd/2 = -3.8m)
	_add_box(Vector3(0.0, rh * 0.5, -rd * 0.5), Vector3(rw, rh, 0.18), wall_mat)
	# Vigas e rodapés da parede traseira
	_add_box(Vector3(0.0, 0.20, -rd * 0.5 + 0.10), Vector3(rw, 0.20, 0.08), trim_mat)
	_add_box(Vector3(0.0, rh - 0.15, -rd * 0.5 + 0.10), Vector3(rw, 0.20, 0.08), trim_mat)

	# Parede Esquerda (-X = -rw/2 = -4.8m)
	_add_box(Vector3(-rw * 0.5, rh * 0.5, 0.0), Vector3(0.18, rh, rd), wall_mat)

	# Parede Direita (+X = +rw/2 = +4.8m) — Área do Estande de Tiro
	_add_box(Vector3(rw * 0.5, rh * 0.5, 0.0), Vector3(0.18, rh, rd), wall_mat)

	# Parede Frontal Cutaway (+Z = +rd/2 = +3.8m):
	# Parede rebaixada a 0.85m nas laterais para permitir visualização isométrica desobstruída
	_add_box(Vector3(-2.8, 0.45, rd * 0.5), Vector3(3.6, 0.90, 0.18), wall_mat)
	_add_box(Vector3(2.8, 0.45, rd * 0.5), Vector3(3.6, 0.90, 0.18), wall_mat)
	# Batentes da porta frontal de entrada no chão (vão livre de 1.8m entre X = -0.9 e +0.9)
	_add_box(Vector3(-0.95, 1.20, rd * 0.5), Vector3(0.14, 2.40, 0.22), trim_mat)
	_add_box(Vector3(0.95, 1.20, rd * 0.5), Vector3(0.14, 2.40, 0.22), trim_mat)
	# Tapete de entrada emborrachado na porta
	_add_box(Vector3(0.0, 0.11, rd * 0.5 - 0.60), Vector3(1.60, 0.02, 0.90), _mat("mat_rubber", Color("#151515"), 0.95))

	# ==============================================================================
	# 2. BALCÃO DE ATENDIMENTO COM VITRINES DE VIDRO (L-SHAPE)
	# ==============================================================================
	# Balcão Frontal: de X = -3.2 a 0.8, em Z = 0.60, altura ergonômica Y = 0.95m
	var c_len: float = 3.8
	_add_box(Vector3(-1.2, 0.45, 0.60), Vector3(c_len, 0.90, 0.70), counter_mat)
	_add_box(Vector3(-1.2, 0.92, 0.60), Vector3(c_len + 0.10, 0.06, 0.80), slate_top)

	# Vitrine de Vidro embutida no balcão frontal (X: -2.8 a -0.2)
	_add_box(Vector3(-1.5, 0.65, 0.60), Vector3(2.40, 0.35, 0.55), glass_mat)
	# Pistolas e revólveres em exibição sobre feltro bordô dentro da vitrine
	var felt_mat := _mat("felt_red", Color("#6e1e1e"), 0.85)
	_add_box(Vector3(-1.5, 0.50, 0.60), Vector3(2.30, 0.02, 0.50), felt_mat)
	for pi in range(4):
		var px: float = -2.3 + float(pi) * 0.55
		# Revólver/Pistola de cano preto e cabo de madeira
		_add_box(Vector3(px, 0.53, 0.60), Vector3(0.20, 0.04, 0.03), iron_mat)
		_add_box(Vector3(px - 0.06, 0.52, 0.60), Vector3(0.04, 0.08, 0.03), stock_wood, Vector3(0, 0, -25.0))
		# Caixinha de munição ao lado
		_add_box(Vector3(px + 0.08, 0.53, 0.72), Vector3(0.08, 0.04, 0.06), brass_mat)

	# Balcão Lateral (L-Return): de Z = 0.6 a -1.8 em X = 0.70
	_add_box(Vector3(0.70, 0.45, -0.60), Vector3(0.70, 0.90, 2.40), counter_mat)
	_add_box(Vector3(0.70, 0.92, -0.60), Vector3(0.80, 0.06, 2.50), slate_top)

	# Caixa registradora vintage de latão sobre o balcão (X = 0.70, Z = 0.0, Y = 0.95m)
	_add_box(Vector3(0.70, 1.12, 0.0), Vector3(0.42, 0.34, 0.38), brass_mat)
	_add_box(Vector3(0.70, 1.32, -0.05), Vector3(0.30, 0.12, 0.08), iron_mat) # Mostrador de valores
	_add_cyl(Vector3(0.70, 0.98, 0.40), 0.05, 0.04, brass_mat)                # Sino de atendimento

	# ==============================================================================
	# 3. ESTANTES DE PAREDE COM FUZIS E MUNIÇÃO (ATRÁS DO BALCÃO: -Z = -3.7m)
	# ==============================================================================
	# Grande Armário / Painel Expositor de Armas Longas (X: -4.2 a 0.2, Y: 0.2 a 3.0m)
	_add_box(Vector3(-2.0, 1.60, -3.65), Vector3(4.20, 2.80, 0.20), trim_mat)
	_add_box(Vector3(-2.0, 1.60, -3.60), Vector3(4.00, 2.60, 0.08), _mat("pegboard", Color("#2d2016"), 0.85))

	# Fuzis e Espingardas enfileirados nos suportes de parede
	for ri in range(7):
		var rx: float = -3.7 + float(ri) * 0.55
		# Fuzil de caça vertical (Y: 0.8 a 2.1m)
		_add_box(Vector3(rx, 1.10, -3.52), Vector3(0.08, 0.45, 0.04), stock_wood)  # Coronha
		_add_cyl(Vector3(rx, 1.65, -3.52), 0.015, 0.85, iron_mat)                   # Cano de aço
		_add_box(Vector3(rx, 1.35, -3.50), Vector3(0.04, 0.16, 0.05), iron_mat)    # Caixa da culatra
		_add_cyl(Vector3(rx, 1.45, -3.48), 0.02, 0.25, iron_mat, Vector3(0, 0, 90)) # Luneta de precisão
		# Travas de segurança de ferro segurando cada arma
		_add_box(Vector3(rx, 1.70, -3.50), Vector3(0.12, 0.03, 0.06), iron_mat)

	# Prateleira superior de caixas de munição militar (Y = 2.40m)
	_add_box(Vector3(-2.0, 2.45, -3.50), Vector3(4.10, 0.06, 0.35), trim_mat)
	for ai in range(8):
		var ax: float = -3.7 + float(ai) * 0.50
		_add_box(Vector3(ax, 2.60, -3.50), Vector3(0.32, 0.22, 0.20), ammo_green)
		_add_box(Vector3(ax, 2.72, -3.50), Vector3(0.08, 0.03, 0.04), iron_mat) # Alça de transporte

	# Troféu de Galhadas de Alce esculpido acima do painel de armas (X = -2.0, Y = 3.1m)
	_add_box(Vector3(-2.0, 3.05, -3.62), Vector3(0.25, 0.20, 0.06), trim_mat)
	_add_cyl(Vector3(-2.35, 3.20, -3.58), 0.025, 0.55, _mat("antler_i", Color("#d5cbba"), 0.8), Vector3(0, 0, -42.0))
	_add_cyl(Vector3(-1.65, 3.20, -3.58), 0.025, 0.55, _mat("antler_i", Color("#d5cbba"), 0.8), Vector3(0, 0, 42.0))

	# Cofre Forte de Armas de Aço Pesado no canto traseiro esquerdo (X = -4.2, Z = -3.2)
	_add_box(Vector3(-4.2, 1.15, -3.2), Vector3(0.85, 2.10, 0.85), iron_mat)
	_add_cyl(Vector3(-3.75, 1.15, -3.2), 0.12, 0.04, brass_mat, Vector3(0, 0, 90)) # Roda giratória do cofre

	# ==============================================================================
	# 4. BANCADA DO ARMEIRO (GUNSMITH WORKBENCH) — CANTO DIREITO/CENTRO (Z = -2.8m)
	# ==============================================================================
	# Mesa de trabalho de carvalho maciço (X = 1.6, Z = -2.8, Y = 0.90m)
	_add_box(Vector3(1.6, 0.44, -2.8), Vector3(1.60, 0.84, 0.80), trim_mat)
	_add_box(Vector3(1.6, 0.88, -2.8), Vector3(1.70, 0.06, 0.90), _mat("bench_top", Color("#422d1b"), 0.70))

	# Morsa de ferro forjado na ponta da bancada (X = 0.90, Z = -2.5)
	_add_box(Vector3(0.90, 0.98, -2.5), Vector3(0.16, 0.14, 0.22), iron_mat)
	_add_cyl(Vector3(0.85, 0.98, -2.5), 0.015, 0.18, iron_mat, Vector3(90, 0, 0)) # Fuso da morsa

	# Luminária Banker's Lamp clássica com cúpula verde na bancada
	_add_cyl(Vector3(2.10, 0.93, -3.0), 0.07, 0.02, brass_mat)
	_add_cyl(Vector3(2.10, 1.08, -3.0), 0.015, 0.30, brass_mat)
	_add_box(Vector3(2.10, 1.22, -2.95), Vector3(0.20, 0.08, 0.10), lamp_glow)

	# Fuzil desmontado sobre o tapete de limpeza de armeiro
	var clean_mat := _mat("cleaning_mat", Color("#1a3c5a"), 0.85)
	_add_box(Vector3(1.6, 0.92, -2.8), Vector3(0.90, 0.01, 0.45), clean_mat)
	_add_box(Vector3(1.4, 0.94, -2.8), Vector3(0.40, 0.03, 0.04), stock_wood) # Coronha separada
	_add_cyl(Vector3(1.8, 0.94, -2.8), 0.012, 0.55, iron_mat, Vector3(0, 0, 90)) # Cano separado
	_add_box(Vector3(1.6, 0.94, -2.68), Vector3(0.12, 0.02, 0.04), iron_mat)    # Ferrolho / mola

	# Painel de ferramentas do armeiro na parede atrás da bancada (X: 0.9 a 2.4, Y: 1.2 a 2.2)
	_add_box(Vector3(1.65, 1.70, -3.68), Vector3(1.50, 0.95, 0.04), _mat("tool_board", Color("#222224"), 0.8))
	# Ferramentas suspensas (chaves, alicates, martelo de latão)
	_add_box(Vector3(1.20, 1.70, -3.64), Vector3(0.04, 0.28, 0.02), iron_mat) # Chave
	_add_box(Vector3(1.40, 1.70, -3.64), Vector3(0.04, 0.25, 0.02), iron_mat) # Alicate
	_add_box(Vector3(1.65, 1.70, -3.64), Vector3(0.03, 0.22, 0.02), brass_mat) # Martelo de armeiro
	_add_box(Vector3(1.90, 1.70, -3.64), Vector3(0.03, 0.32, 0.02), steel_mat) # Vareta de limpeza

	# ==============================================================================
	# 5. ESTANDE DE TIRO INDOOR (INDOOR SHOOTING LANE) — LADO DIREITO (X = 3.2 a 4.6)
	# ==============================================================================
	# Parete divisória acústica separando a loja do estande (X = 3.0, Z de -3.8 a 1.2)
	_add_box(Vector3(3.0, rh * 0.5, -1.3), Vector3(0.14, rh, 5.0), trim_mat)
	# Janela de inspeção com vidro blindado na divisória (X = 3.0, Y = 1.6, Z = 0.0)
	_add_box(Vector3(3.0, 1.60, 0.0), Vector3(0.16, 1.10, 1.40), glass_mat)

	# Espumas acústicas piramidais escuras nas paredes do estande
	for fz in [-3.2, -2.0, -0.8, 0.4]:
		_add_box(Vector3(4.68, 1.70, fz), Vector3(0.06, 1.80, 0.90), foam_acoustic)

	# Cabine de disparo (Firing Stall Counter) em X = 3.8, Z = 1.2, Y = 1.0m
	_add_box(Vector3(3.8, 0.50, 1.2), Vector3(1.40, 1.00, 0.40), trim_mat)
	_add_box(Vector3(3.8, 1.02, 1.2), Vector3(1.46, 0.04, 0.46), slate_top)
	# Linha vermelha de segurança no chão (Firing Line)
	_add_box(Vector3(3.8, 0.06, 1.5), Vector3(1.50, 0.01, 0.10), _mat("red_line", Color("#c0392b"), 0.7))

	# Trilho aéreo de alvo móvel (Overhead Target Pulley Rail)
	_add_box(Vector3(3.8, 2.90, -1.3), Vector3(0.06, 0.06, 4.80), steel_mat)

	# Alvo de papel de silhueta no final da raia (X = 3.8, Z = -3.2, Y = 1.65m)
	_add_box(Vector3(3.8, 1.65, -3.2), Vector3(0.55, 0.85, 0.02), target_paper)
	_add_cyl(Vector3(3.8, 1.75, -3.18), 0.14, 0.01, target_red, Vector3(90, 0, 0)) # Anéis de pontuação
	_add_cyl(Vector3(3.8, 1.75, -3.17), 0.05, 0.01, _mat("target_10", Color("#f1c40f"), 0.8), Vector3(90, 0, 0)) # Centro 10
	# Fios de sustentação do alvo presos ao trilho superior
	_add_cyl(Vector3(3.6, 2.30, -3.2), 0.004, 1.20, steel_mat)
	_add_cyl(Vector3(4.0, 2.30, -3.2), 0.004, 1.20, steel_mat)

	# Barreira de contenção de areia nos fundos da raia (Bullet Trap Sandbags)
	for sy in [0.20, 0.50, 0.80]:
		for sx in [3.3, 3.8, 4.3]:
			_add_box(Vector3(sx, sy, -3.6), Vector3(0.48, 0.28, 0.32), sandbag_mat)

	# ==============================================================================
	# 6. FOGÃO A LENHA / ESTUFA DE FERRO FUNDIDO (CANTO FRONTAL ESQUERDO)
	# ==============================================================================
	# Mantém a loja aquecida na nevasca da serra (X = -3.8, Z = 2.4)
	_add_box(Vector3(-3.8, 0.07, 2.4), Vector3(1.10, 0.04, 1.10), stone_mat) # Placa refratária no chão
	_add_box(Vector3(-3.8, 0.45, 2.4), Vector3(0.60, 0.70, 0.60), iron_mat)  # Corpo da estufa
	_add_cyl(Vector3(-3.8, 1.85, 2.4), 0.08, 2.20, iron_mat)                 # Tubo de exaustão subindo
	_add_cyl(Vector3(-3.8, 0.85, 2.4), 0.12, 0.12, brass_mat)                # Chaleira de cobre em cima
