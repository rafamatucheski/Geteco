@tool
extends Node3D

## SummitSUVLoadoutTrunk3D
## Prévia 3D procedural do porta-malas traseiro do Summit SUV 4x4 (Lobos de Gelo).
## Reproduz em escala real (1:1 métrica) a traseira do veículo oficial com:
## - Compartimento horizontal acolchoado para arma longa (fuzil de caça / escopeta);
## - Estojo tático rígido (Pelican style) para arma curta (pistola / submetralhadora);
## - Suporte de saque rápido para arma de corpo a corpo (faca de caça / taco);
## - Detalhes de carpete automotivo, tapete de borracha estriada, guarnições de vedação e anéis D-ring;
## - Tampa traseira articulada com dobradiça superior no teto e pistões a gás telescópicos;
## - Métodos set_open(bool) e set_loadout(Dictionary) compatíveis com a prévia da Astra.

# Contratos de dimensão e engenharia
var footprint_size: Vector2 = Vector2(2.05, 2.20)
var load_floor_height: float = 0.68 # Altura do assoalho de carga a partir do solo (Y=0)

# Propriedades de cor e acabamento
@export var paint_color: Color = Color("#2980b9") # Azul glacial dos Lobos de Gelo
@export var trim_color: Color = Color("#1e272e") # Plástico preto fosco tático
@export var steel_color: Color = Color("#2c3e50") # Aço reforçado de para-choque

# Estado da tampa traseira
var is_open: bool = true
var open_ratio: float = 1.0 # 0.0 = totalmente fechada, 1.0 = totalmente aberta (82 graus)
var _target_open_ratio: float = 1.0
var _door_angle_max_deg: float = 82.0

# Dicionário de loadout atual (compatível com a prévia em prototypes/loadout/index.html)
var current_loadout: Dictionary = {
	"curta": "pistol",
	"longa": "rifle",
	"corpo": "knife"
}

# Referências para nós dinâmicos
var door_pivot: Node3D = null
var strut_left_cyl: Node3D = null
var strut_left_rod: Node3D = null
var strut_right_cyl: Node3D = null
var strut_right_rod: Node3D = null

# Nós de slots de armas
var slot_longa_root: Node3D = null
var slot_curta_root: Node3D = null
var slot_corpo_root: Node3D = null

var _is_built: bool = false

func _init(initial_open: bool = true, initial_loadout: Dictionary = {}) -> void:
	is_open = initial_open
	open_ratio = 1.0 if initial_open else 0.0
	_target_open_ratio = open_ratio
	if not initial_loadout.is_empty():
		current_loadout = initial_loadout.duplicate()

func _ready() -> void:
	if not _is_built:
		_build_all()
	_update_door_transforms(open_ratio)

func _process(delta: float) -> void:
	if absf(open_ratio - _target_open_ratio) > 0.001:
		# Animação suave com amortecimento exponencial
		var step: float = delta * 4.5
		open_ratio = lerpf(open_ratio, _target_open_ratio, clampf(step, 0.0, 1.0))
		if absf(open_ratio - _target_open_ratio) < 0.002:
			open_ratio = _target_open_ratio
		_update_door_transforms(open_ratio)

## Abre ou fecha o porta-malas suavemente (ou de forma imediata)
func set_open(open_state: bool, immediate: bool = false) -> void:
	is_open = open_state
	_target_open_ratio = 1.0 if open_state else 0.0
	if immediate:
		open_ratio = _target_open_ratio
		_update_door_transforms(open_ratio)

## Define o equipamento nos 3 slots (chaves: "curta", "longa", "corpo")
func set_loadout(loadout: Dictionary) -> void:
	for k in ["curta", "longa", "corpo"]:
		if loadout.has(k):
			current_loadout[k] = loadout[k]
	if _is_built:
		_refresh_weapons_visuals()

func get_loadout() -> Dictionary:
	return current_loadout.duplicate()

# ==============================================================================
# CONSTRUÇÃO PROCEDURAL COMPLETA
# ==============================================================================

func _build_all() -> void:
	_is_built = true

	# Materiais PBR padronizados
	var mat_paint := _mat("paint_body", paint_color, 0.35, 0.30)
	var mat_trim := _mat("black_trim", trim_color, 0.05, 0.80)
	var mat_steel := _mat("heavy_steel", steel_color, 0.75, 0.35)
	var mat_bumper_step := _mat("rubber_step", Color("#15191d"), 0.0, 0.95)
	var mat_carpet := _mat("carpet_fabric", Color("#22282d"), 0.0, 0.98)
	var mat_mat := _mat("rubber_mat", Color("#14171a"), 0.0, 0.92)
	var mat_foam := _mat("dense_foam", Color("#191d21"), 0.0, 0.90)
	var mat_seal := _mat("rubber_seal", Color("#0e1113"), 0.0, 0.95)
	var mat_glass := _mat("tinted_glass", Color("#1c2833"), 0.35, 0.15)
	mat_glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_glass.albedo_color = Color(0.11, 0.16, 0.20, 0.82)
	var mat_taillight := _mat("lens_tail", Color("#c0392b"), 0.10, 0.20, 0.7)
	var mat_reverse := _mat("lens_white", Color("#f5f6fa"), 0.10, 0.10, 0.8)
	var mat_turn := _mat("lens_amber", Color("#e67e22"), 0.10, 0.20, 0.7)
	var mat_chrome := _mat("chrome_steel", Color("#d5dbdb"), 0.90, 0.15)
	var mat_led_strip := _mat("led_courtesy", Color("#fff8e7"), 0.10, 0.10, 1.4)
	var mat_pelican := _mat("pelican_case", Color("#181b1e"), 0.15, 0.65)
	var mat_brass := _mat("brass_hardware", Color("#d4ac0d"), 0.80, 0.30)

	# --------------------------------------------------------------------------
	# 1. ESTRUTURA DO CHASSI TRASEIRO E PARA-CHOQUE COM DEGRAU
	# --------------------------------------------------------------------------
	# Chassi inferior e skidplate traseiro
	_add_box_to(self, Vector3(0.0, 0.38, 1.65), Vector3(1.95, 0.16, 1.50), mat_trim)

	# Rodas traseiras com banda de rodagem e calotas (para fidelidade de proporção)
	for s in [-1.0, 1.0]:
		var wheel := _add_cyl_to(self, Vector3(s * 0.98, 0.36, 1.45), 0.38, 0.27, mat_trim, Vector3(0, 0, 90))
		_add_cyl_to(self, Vector3(s * 1.10, 0.36, 1.45), 0.20, 0.05, mat_chrome, Vector3(0, 0, 90)) # Roda de liga
		# Alargadores de para-lama (Fender Flares)
		_add_box_to(self, Vector3(s * 1.04, 0.78, 1.45), Vector3(0.12, 0.42, 1.10), mat_trim)

	# Para-choque de aço pesado de expedição (Y = 0.52m, Z = 2.40m)
	_add_box_to(self, Vector3(0.0, 0.52, 2.40), Vector3(2.02, 0.28, 0.18), mat_steel)
	# Degrau central emborrachado com frisos anti-derrapantes
	_add_box_to(self, Vector3(0.0, 0.65, 2.42), Vector3(0.85, 0.03, 0.16), mat_bumper_step)
	for rz in [-0.04, 0.0, 0.04]:
		_add_box_to(self, Vector3(0.0, 0.67, 2.42 + rz), Vector3(0.81, 0.015, 0.018), mat_trim)

	# Engate de reboque reforçado (Tow Hitch Receiver)
	_add_box_to(self, Vector3(0.0, 0.40, 2.48), Vector3(0.12, 0.12, 0.14), mat_steel)
	_add_cyl_to(self, Vector3(0.0, 0.40, 2.54), 0.035, 0.04, mat_chrome, Vector3(90, 0, 0))

	# --------------------------------------------------------------------------
	# 2. CARROCERIA TRASEIRA E COLUNAS 'D'
	# --------------------------------------------------------------------------
	# Painéis laterais da carroceria azul glacial
	for s in [-1.0, 1.0]:
		# Lateral inferior (Y: 0.55 a 1.10m)
		_add_box_to(self, Vector3(s * 0.97, 0.82, 1.70), Vector3(0.16, 0.54, 1.40), mat_paint)
		# Coluna D angular (Y: 1.10 a 1.62m)
		_add_box_to(self, Vector3(s * 0.94, 1.36, 2.22), Vector3(0.18, 0.54, 0.28), mat_paint)
		# Janela vigia traseira fixa escurecida
		_add_box_to(self, Vector3(s * 0.86, 1.36, 1.55), Vector3(0.03, 0.52, 1.05), mat_glass)

		# Conjunto de Lanternas Traseiras Verticais (Taillights em Y: 0.88 a 1.34m)
		_add_box_to(self, Vector3(s * 0.96, 1.22, 2.38), Vector3(0.11, 0.22, 0.04), mat_taillight) # Freio/Posição
		_add_box_to(self, Vector3(s * 0.96, 1.04, 2.38), Vector3(0.11, 0.12, 0.04), mat_turn)      # Seta âmbar
		_add_box_to(self, Vector3(s * 0.96, 0.92, 2.38), Vector3(0.11, 0.10, 0.04), mat_reverse)   # Luz de ré

	# Extremidade do teto superior (Y = 1.62m, Z: 0.90 a 2.18m)
	_add_box_to(self, Vector3(0.0, 1.64, 1.60), Vector3(1.76, 0.08, 1.20), mat_paint)
	# Travessa final do bagageiro de teto tubular
	_add_cyl_to(self, Vector3(0.0, 1.73, 1.55), 0.025, 1.52, mat_steel, Vector3(0, 0, 90))
	# Estepe off-road amarrado no teto (visível parcialmente)
	var spare := _add_cyl_to(self, Vector3(0.0, 1.82, 1.15), 0.38, 0.22, mat_trim, Vector3(90, 0, 0))
	_add_box_to(self, Vector3(0.0, 1.86, 1.15), Vector3(0.40, 0.04, 0.40), mat_steel)

	# --------------------------------------------------------------------------
	# 3. MOLDURA DO VÃO DO PORTA-MALAS & GUARNIÇÃO DE BORRACHA (WEATHERSTRIP)
	# --------------------------------------------------------------------------
	# Soleira do porta-malas (Y = 0.68m, Z = 2.30m)
	_add_box_to(self, Vector3(0.0, 0.67, 2.28), Vector3(1.58, 0.04, 0.14), mat_trim)
	# Guarnição de borracha perimetral contínua que veda a porta fechada
	# Base inferior
	_add_box_to(self, Vector3(0.0, 0.69, 2.32), Vector3(1.48, 0.025, 0.025), mat_seal)
	# Laterais verticais
	for s in [-1.0, 1.0]:
		_add_box_to(self, Vector3(s * 0.74, 1.14, 2.32), Vector3(0.025, 0.92, 0.025), mat_seal)
	# Topo superior
	_add_box_to(self, Vector3(0.0, 1.60, 2.18), Vector3(1.48, 0.025, 0.025), mat_seal)

	# Trinco inferior central de engate da fechadura
	_add_box_to(self, Vector3(0.0, 0.69, 2.30), Vector3(0.08, 0.03, 0.04), mat_steel)
	_add_box_to(self, Vector3(0.0, 0.705, 2.30), Vector3(0.04, 0.015, 0.02), mat_chrome)

	# --------------------------------------------------------------------------
	# 4. INTERIOR DO PORTA-MALAS (CAÇAMBA DE CARGA)
	# --------------------------------------------------------------------------
	# Paredes internas laterais com revestimento termoformado escuro
	for s in [-1.0, 1.0]:
		_add_box_to(self, Vector3(s * 0.78, 1.10, 1.65), Vector3(0.06, 0.80, 1.20), mat_carpet)
		# Bolsão de rede elástica porta-objetos na lateral
		_add_box_to(self, Vector3(s * 0.75, 0.95, 1.80), Vector3(0.02, 0.22, 0.42), mat_trim)
		_add_box_to(self, Vector3(s * 0.74, 0.95, 1.80), Vector3(0.01, 0.18, 0.38), _mat("net_fabric", Color("#303a42"), 0.0, 0.95))

	# Forro do teto interno (Headliner) com luz de cortesia LED
	_add_box_to(self, Vector3(0.0, 1.58, 1.65), Vector3(1.50, 0.03, 1.18), mat_carpet)
	_add_box_to(self, Vector3(0.0, 1.56, 1.85), Vector3(0.24, 0.015, 0.08), mat_trim)
	_add_box_to(self, Vector3(0.0, 1.555, 1.85), Vector3(0.20, 0.01, 0.05), mat_led_strip) # Barra LED de teto

	# Luz pontual de cortesia automática (ilumina o interior da caçamba quando aberta)
	var cargo_light := OmniLight3D.new()
	cargo_light.name = "CargoCourtesyLight"
	cargo_light.position = Vector3(0.0, 1.50, 1.80)
	cargo_light.light_color = Color("#fff2df")
	cargo_light.light_energy = 1.8
	cargo_light.omni_range = 2.2
	cargo_light.shadow_enabled = false
	add_child(cargo_light)

	# Parede frontal da caçamba (atrás da 2ª fileira de assentos de passageiros)
	_add_box_to(self, Vector3(0.0, 1.08, 1.05), Vector3(1.52, 0.80, 0.08), mat_carpet)
	# Costas dos bancos com apoios de cabeça
	for sx in [-0.42, 0.42]:
		_add_box_to(self, Vector3(sx, 1.52, 1.08), Vector3(0.24, 0.16, 0.10), mat_carpet)
		_add_cyl_to(self, Vector3(sx - 0.06, 1.44, 1.08), 0.01, 0.08, mat_chrome)
		_add_cyl_to(self, Vector3(sx + 0.06, 1.44, 1.08), 0.01, 0.08, mat_chrome)

	# --------------------------------------------------------------------------
	# 5. ASSOALHO DE CARGA & ACABAMENTOS EM TECIDO / BORRACHA
	# --------------------------------------------------------------------------
	# Base de assoalho com forração completa em carpete automotivo
	_add_box_to(self, Vector3(0.0, 0.67, 1.66), Vector3(1.50, 0.03, 1.16), mat_carpet)

	# Tapete de borracha pesada vulcanizada sobreposto (Heavy-Duty Cargo Mat)
	_add_box_to(self, Vector3(0.0, 0.686, 1.68), Vector3(1.42, 0.012, 1.08), mat_mat)
	# Frisos em alto relevo na borracha para canaletas de água e neve derretida
	for fz in [1.25, 1.40, 1.55, 1.70, 1.85, 2.00, 2.15]:
		_add_box_to(self, Vector3(0.0, 0.694, fz), Vector3(1.36, 0.005, 0.025), mat_trim)

	# Anéis de amarração de carga em aço nos quatro cantos (D-Rings)
	for dx in [-0.64, 0.64]:
		for dz in [1.22, 2.14]:
			_add_box_to(self, Vector3(dx, 0.695, dz), Vector3(0.05, 0.006, 0.05), mat_steel)
			_add_cyl_to(self, Vector3(dx, 0.702, dz), 0.02, 0.006, mat_chrome, Vector3(90, 0, 0))

	# Estojo de primeiros socorros / triângulo de emergência preso na lateral direita
	_add_box_to(self, Vector3(0.68, 0.72, 1.30), Vector3(0.12, 0.06, 0.22), _mat("med_red", Color("#b03a2e"), 0.2, 0.8))
	_add_box_to(self, Vector3(0.68, 0.752, 1.30), Vector3(0.06, 0.002, 0.02), _mat("med_cross", Color("#ffffff"), 0.1, 0.6))
	_add_box_to(self, Vector3(0.68, 0.752, 1.30), Vector3(0.02, 0.002, 0.06), _mat("med_cross", Color("#ffffff"), 0.1, 0.6))
	# Cinta de fixação de borracha preta
	_add_box_to(self, Vector3(0.68, 0.73, 1.30), Vector3(0.13, 0.02, 0.03), mat_seal)

	# --------------------------------------------------------------------------
	# 6. BERÇO DE ARMAS: OS TRÊS SLOTS DA ASTRA (LONGA, CURTA, CORPO A CORPO)
	# --------------------------------------------------------------------------
	_build_weapon_slots(mat_foam, mat_pelican, mat_trim, mat_brass, mat_steel)

	# --------------------------------------------------------------------------
	# 7. TAMPA TRASEIRA ARTICULADA (TAILGATE DOOR) COM DOBRADIÇA SUPERIOR
	# --------------------------------------------------------------------------
	_build_tailgate_door(mat_paint, mat_trim, mat_glass, mat_steel, mat_taillight, mat_chrome)

	# --------------------------------------------------------------------------
	# 8. PISTÕES A GÁS TELESCÓPICOS (GAS STRUTS)
	# --------------------------------------------------------------------------
	_build_gas_struts(mat_trim, mat_chrome)

	# Popula os visuais iniciais das armas de acordo com o loadout
	_refresh_weapons_visuals()

# ==============================================================================
# SEÇÃO 6: SLOTS DE ARMAS E ACESSÓRIOS
# ==============================================================================

func _build_weapon_slots(mat_foam: Material, mat_pelican: Material, mat_trim: Material, mat_brass: Material, mat_steel: Material) -> void:
	# --------------------------------------------------------------------------
	# A. SLOT LONGA (Fundo Central / Horizontal: X = -0.60 a +0.60, Z = 1.48)
	# --------------------------------------------------------------------------
	# Bandeja moldada em espuma de alta densidade usinada sob medida
	var tray_longa := _add_box_to(self, Vector3(0.05, 0.71, 1.50), Vector3(1.18, 0.045, 0.32), mat_foam)
	tray_longa.name = "LongGunFoamTray"

	# Frisos de acabamento da bandeja e reforço de borda
	_add_box_to(self, Vector3(0.05, 0.71, 1.34), Vector3(1.20, 0.05, 0.02), mat_trim)
	_add_box_to(self, Vector3(0.05, 0.71, 1.66), Vector3(1.20, 0.05, 0.02), mat_trim)
	_add_box_to(self, Vector3(-0.55, 0.71, 1.50), Vector3(0.02, 0.05, 0.34), mat_trim)
	_add_box_to(self, Vector3(0.65, 0.71, 1.50), Vector3(0.02, 0.05, 0.34), mat_trim)

	# Presilhas táticas com tiras de velcro/borracha e fivelas de liberação rápida
	for sx in [-0.28, 0.38]:
		_add_box_to(self, Vector3(sx, 0.74, 1.50), Vector3(0.04, 0.015, 0.32), mat_trim)
		_add_box_to(self, Vector3(sx, 0.75, 1.50), Vector3(0.045, 0.012, 0.06), mat_steel)

	# Nó pai para a arma longa (instanciada dinamicamente)
	slot_longa_root = Node3D.new()
	slot_longa_root.name = "SlotLongaRoot"
	slot_longa_root.position = Vector3(0.05, 0.74, 1.50)
	add_child(slot_longa_root)

	# --------------------------------------------------------------------------
	# B. SLOT CURTA (Lado Esquerdo: Estojo Pelican / Hard Case Tático)
	# --------------------------------------------------------------------------
	# Maleta rígida reforçada em X = -0.36, Z = 1.95 (Y = 0.70m)
	var case_root := Node3D.new()
	case_root.name = "PistolHardCase"
	case_root.position = Vector3(-0.32, 0.70, 1.95)
	case_root.rotation_degrees = Vector3(0, -6.0, 0)
	add_child(case_root)

	# Fundo da maleta aberta
	_add_box_to(case_root, Vector3(0.0, 0.035, 0.0), Vector3(0.52, 0.07, 0.38), mat_pelican)
	# Nervuras de reforço estrutural externo
	for nx in [-0.18, -0.06, 0.06, 0.18]:
		_add_box_to(case_root, Vector3(nx, 0.035, 0.0), Vector3(0.02, 0.075, 0.39), mat_trim)
	# Alça de transporte dobrável e fechos de pressão de latão
	_add_box_to(case_root, Vector3(0.0, 0.04, 0.20), Vector3(0.18, 0.03, 0.04), mat_trim)
	_add_box_to(case_root, Vector3(-0.16, 0.05, 0.195), Vector3(0.04, 0.04, 0.02), mat_brass)
	_add_box_to(case_root, Vector3(0.16, 0.05, 0.195), Vector3(0.04, 0.04, 0.02), mat_brass)

	# Berço interno de espuma alveolar com recorte de precisão
	_add_box_to(case_root, Vector3(0.0, 0.065, 0.0), Vector3(0.48, 0.025, 0.34), mat_foam)

	# Tampa da maleta semiaberta inclinada para trás (ângulo de 70 graus)
	var lid_pivot := Node3D.new()
	lid_pivot.name = "CaseLidPivot"
	lid_pivot.position = Vector3(0.0, 0.07, -0.19)
	lid_pivot.rotation_degrees = Vector3(72.0, 0.0, 0.0)
	case_root.add_child(lid_pivot)
	_add_box_to(lid_pivot, Vector3(0.0, 0.02, -0.18), Vector3(0.52, 0.04, 0.36), mat_pelican)
	_add_box_to(lid_pivot, Vector3(0.0, 0.03, -0.18), Vector3(0.48, 0.02, 0.32), mat_foam) # Espuma caixa de ovo

	# Carregadores sobressalentes na maleta (sempre presentes como detalhe de estojo)
	for mx in [-0.14, -0.08]:
		_add_box_to(case_root, Vector3(mx, 0.075, 0.09), Vector3(0.03, 0.025, 0.12), _mat("mag_steel", Color("#272a2e"), 0.7, 0.4))
		_add_cyl_to(case_root, Vector3(mx, 0.082, 0.04), 0.006, 0.02, mat_brass, Vector3(90, 0, 0)) # Ponta de projétil

	# Nó pai para a arma curta (pistola ou smg)
	slot_curta_root = Node3D.new()
	slot_curta_root.name = "SlotCurtaRoot"
	slot_curta_root.position = Vector3(0.08, 0.085, -0.02)
	case_root.add_child(slot_curta_root)

	# --------------------------------------------------------------------------
	# C. SLOT CORPO A CORPO (Lado Direito: Suporte Rígido de Saque Rápido)
	# --------------------------------------------------------------------------
	var melee_bracket := Node3D.new()
	melee_bracket.name = "MeleeMountBracket"
	melee_bracket.position = Vector3(0.42, 0.70, 1.92)
	melee_bracket.rotation_degrees = Vector3(0, 12.0, 0)
	add_child(melee_bracket)

	# Placa base de montagem tática aparafusada no assoalho
	_add_box_to(melee_bracket, Vector3(0.0, 0.015, 0.0), Vector3(0.24, 0.02, 0.44), mat_trim)
	for bz in [-0.18, 0.18]:
		_add_cyl_to(melee_bracket, Vector3(-0.09, 0.026, bz), 0.008, 0.006, mat_steel)
		_add_cyl_to(melee_bracket, Vector3(0.09, 0.026, bz), 0.008, 0.006, mat_steel)

	# Calha emborrachada de apoio com fita de retenção rápida
	_add_box_to(melee_bracket, Vector3(0.0, 0.035, 0.0), Vector3(0.16, 0.025, 0.38), mat_foam)
	_add_box_to(melee_bracket, Vector3(0.0, 0.055, 0.0), Vector3(0.18, 0.015, 0.04), mat_trim)
	_add_box_to(melee_bracket, Vector3(0.08, 0.06, 0.0), Vector3(0.03, 0.018, 0.03), mat_brass) # Botão de pressão

	# Nó pai para a arma corpo a corpo (faca ou taco)
	slot_corpo_root = Node3D.new()
	slot_corpo_root.name = "SlotCorpoRoot"
	slot_corpo_root.position = Vector3(0.0, 0.05, 0.0)
	melee_bracket.add_child(slot_corpo_root)

# ==============================================================================
# SEÇÃO 7: TAMPA TRASEIRA ARTICULADA (TAILGATE DOOR)
# ==============================================================================

func _build_tailgate_door(mat_paint: Material, mat_trim: Material, mat_glass: Material, mat_steel: Material, mat_taillight: Material, mat_chrome: Material) -> void:
	# Pivô superior da dobradiça no teto traseiro
	door_pivot = Node3D.new()
	door_pivot.name = "TailgateHingePivot"
	# Eixo de rotação localizado exatamente na junção traseira do teto
	door_pivot.position = Vector3(0.0, 1.62, 2.18)
	add_child(door_pivot)

	# Dobradiças duplas de aço no teto
	for s in [-0.55, 0.55]:
		_add_cyl_to(door_pivot, Vector3(s, 0.0, 0.0), 0.022, 0.09, mat_steel, Vector3(0, 0, 90))

	# Estrutura da porta em coordenadas locais do pivô:
	# Quando fechada (rotation.x = 0), a porta desce de Y=0 até Y = -0.95m em Z = 0.12m
	var door_body := Node3D.new()
	door_body.name = "TailgateBody"
	door_pivot.add_child(door_body)

	# 1. Painel Inferior da Porta (Lata externa pintada em azul glacial)
	_add_box_to(door_body, Vector3(0.0, -0.68, 0.12), Vector3(1.54, 0.54, 0.08), mat_paint)
	# Rebaixo de placa de licença e maçaneta externa
	_add_box_to(door_body, Vector3(0.0, -0.68, 0.165), Vector3(0.48, 0.22, 0.02), mat_trim)
	_add_box_to(door_body, Vector3(0.0, -0.54, 0.17), Vector3(0.18, 0.04, 0.03), mat_chrome) # Puxador de abertura

	# Letreiro metálico "SUMMIT 4x4" em relevo no canto inferior esquerdo
	_add_box_to(door_body, Vector3(-0.52, -0.82, 0.165), Vector3(0.24, 0.03, 0.01), mat_chrome)

	# 2. Moldura Superior e Vidro Vigia Traseiro Temperado
	# Colunas laterais da moldura da janela
	for s in [-1.0, 1.0]:
		_add_box_to(door_body, Vector3(s * 0.72, -0.22, 0.08), Vector3(0.10, 0.44, 0.06), mat_paint)
	# Moldura superior da janela com aerofólio
	_add_box_to(door_body, Vector3(0.0, -0.02, 0.05), Vector3(1.54, 0.06, 0.08), mat_paint)
	# Aerofólio de teto com brake light LED
	_add_box_to(door_body, Vector3(0.0, 0.02, 0.07), Vector3(1.56, 0.05, 0.12), mat_paint)
	_add_box_to(door_body, Vector3(0.0, 0.02, 0.132), Vector3(0.32, 0.025, 0.01), mat_taillight) # 3º Brake Light

	# Vidro fumê traseiro integrado
	_add_box_to(door_body, Vector3(0.0, -0.22, 0.08), Vector3(1.36, 0.42, 0.025), mat_glass)
	# Linhas do desembaçador térmico no vidro
	for ly in [-0.34, -0.28, -0.22, -0.16, -0.10]:
		_add_box_to(door_body, Vector3(0.0, ly, 0.093), Vector3(1.24, 0.003, 0.002), _mat("defrost", Color("#c0392b"), 0.3, 0.5))

	# Braço do limpador de para-brisa traseiro
	_add_box_to(door_body, Vector3(0.0, -0.42, 0.11), Vector3(0.04, 0.04, 0.04), mat_trim) # Motor
	_add_box_to(door_body, Vector3(0.14, -0.32, 0.10), Vector3(0.32, 0.018, 0.015), mat_trim, Vector3(0, 0, 32.0))
	_add_box_to(door_body, Vector3(0.26, -0.24, 0.095), Vector3(0.38, 0.012, 0.012), mat_trim, Vector3(0, 0, 32.0))

	# 3. Forração Interna da Tampa (Vista quando aberta!)
	# Painel de acabamento moldado em polímero com frisos de isolamento acústico
	_add_box_to(door_body, Vector3(0.0, -0.68, 0.07), Vector3(1.46, 0.50, 0.03), _mat("tailgate_liner", Color("#1f2429"), 0.0, 0.95))
	# Puxador embutido para fechar a tampa com a mão
	_add_box_to(door_body, Vector3(0.35, -0.75, 0.052), Vector3(0.14, 0.06, 0.02), mat_trim)
	# Luz vermelha de advertência de porta aberta na borda inferior
	_add_box_to(door_body, Vector3(0.65, -0.92, 0.07), Vector3(0.08, 0.03, 0.02), mat_taillight)
	_add_box_to(door_body, Vector3(-0.65, -0.92, 0.07), Vector3(0.08, 0.03, 0.02), mat_taillight)

	# Gancho de travamento inferior
	_add_box_to(door_body, Vector3(0.0, -0.94, 0.08), Vector3(0.05, 0.03, 0.04), mat_chrome)

# ==============================================================================
# SEÇÃO 8: PISTÕES A GÁS TELESCÓPICOS (GAS STRUTS)
# ==============================================================================

func _build_gas_struts(mat_trim: Material, mat_chrome: Material) -> void:
	# Pistão Esquerdo
	strut_left_cyl = Node3D.new()
	strut_left_cyl.name = "GasStrutLeftCylinder"
	strut_left_cyl.position = Vector3(-0.73, 1.15, 2.22)
	add_child(strut_left_cyl)
	_add_cyl_to(strut_left_cyl, Vector3(0, 0.20, 0), 0.014, 0.40, mat_trim) # Corpo preto do amortecedor

	strut_left_rod = Node3D.new()
	strut_left_rod.name = "GasStrutLeftRod"
	strut_left_cyl.add_child(strut_left_rod)
	_add_cyl_to(strut_left_rod, Vector3(0, 0.38, 0), 0.007, 0.36, mat_chrome) # Haste de aço cromado deslizante

	# Pistão Direito
	strut_right_cyl = Node3D.new()
	strut_right_cyl.name = "GasStrutRightCylinder"
	strut_right_cyl.position = Vector3(0.73, 1.15, 2.22)
	add_child(strut_right_cyl)
	_add_cyl_to(strut_right_cyl, Vector3(0, 0.20, 0), 0.014, 0.40, mat_trim)

	strut_right_rod = Node3D.new()
	strut_right_rod.name = "GasStrutRightRod"
	strut_right_cyl.add_child(strut_right_rod)
	_add_cyl_to(strut_right_rod, Vector3(0, 0.38, 0), 0.007, 0.36, mat_chrome)

# Atualiza dinamicamente as transformações e rotações da tampa e dos pistões a gás
func _update_door_transforms(ratio: float) -> void:
	if door_pivot == null:
		return

	# Rotação da porta: de 0.0 graus (fechada) a +82 graus (totalmente aberta)
	var current_angle_deg: float = ratio * _door_angle_max_deg
	door_pivot.rotation_degrees.x = current_angle_deg

	# Controla a luz de cortesia do teto da caçamba
	var light = get_node_or_null("CargoCourtesyLight")
	if light is Light3D:
		light.visible = (ratio > 0.15)

	# Animação dos pistões a gás
	# Ponto de ancoragem na porta em coordenadas locais da porta
	var local_on_door := Vector3(0.0, -0.45, 0.05)
	var door_rot_rad: float = deg_to_rad(current_angle_deg)
	var rot_y: float = local_on_door.y * cos(door_rot_rad) - local_on_door.z * sin(door_rot_rad)
	var rot_z: float = local_on_door.y * sin(door_rot_rad) + local_on_door.z * cos(door_rot_rad)
	var door_anchor_global := door_pivot.position + Vector3(0.0, rot_y, rot_z)

	for side in [-1.0, 1.0]:
		var cyl: Node3D = strut_left_cyl if side < 0 else strut_right_cyl
		var rod: Node3D = strut_left_rod if side < 0 else strut_right_rod
		if cyl == null or rod == null:
			continue

		var base_pos := cyl.position
		var target_pos := Vector3(side * 0.71, door_anchor_global.y, door_anchor_global.z)
		var delta_v := target_pos - base_pos
		var dist := delta_v.length()

		# Alinha o cilindro na direção do alvo
		var pitch_deg: float = rad_to_deg(atan2(-delta_v.z, delta_v.y))
		cyl.rotation_degrees = Vector3(pitch_deg - 90.0, 0.0, 0.0)

		# Haste telescópica estica ou recolhe
		var ext_ratio: float = clampf((dist - 0.38) / 0.32, 0.0, 1.0)
		rod.position.y = ext_ratio * 0.22

# ==============================================================================
# SEÇÃO 9: RENDERIZAÇÃO DAS ARMAS NOS SLOTS (REATIVO AO LOADOUT)
# ==============================================================================

func _refresh_weapons_visuals() -> void:
	if slot_longa_root:
		for c in slot_longa_root.get_children():
			c.queue_free()
		_spawn_long_gun(current_loadout.get("longa", "rifle"))

	if slot_curta_root:
		for c in slot_curta_root.get_children():
			c.queue_free()
		_spawn_sidearm(current_loadout.get("curta", "pistol"))

	if slot_corpo_root:
		for c in slot_corpo_root.get_children():
			c.queue_free()
		_spawn_melee(current_loadout.get("corpo", "knife"))

# 1. Renderiza Arma Longa no Berço Acolchoado
func _spawn_long_gun(weapon_id: String) -> void:
	var id := weapon_id.to_lower()
	var wood := _mat("gun_wood", Color("#5c341f"), 0.1, 0.65)
	var steel := _mat("gun_steel", Color("#272a2e"), 0.85, 0.30)
	var dark := _mat("gun_dark", Color("#1b1e21"), 0.50, 0.50)
	var brass := _mat("gun_brass", Color("#d4ac0d"), 0.75, 0.30)
	var lens := _mat("scope_lens", Color("#2980b9"), 0.60, 0.10)

	var w_node := Node3D.new()
	w_node.name = "LongGunModel"
	slot_longa_root.add_child(w_node)

	if id in ["rifle", "hunting_rifle", "sniper"]:
		# Rifle de precisão / caça com coronha de nogueira e luneta telescópica
		# Orientado horizontalmente ao longo de X (Cano apontando para a esquerda / -X)
		# Coronha de nogueira
		_add_box_to(w_node, Vector3(0.24, 0.02, 0.0), Vector3(0.42, 0.08, 0.045), wood)
		_add_box_to(w_node, Vector3(0.44, 0.02, 0.0), Vector3(0.025, 0.085, 0.048), dark) # Buttpad de borracha
		# Caixa de culatra e ferrolho
		_add_box_to(w_node, Vector3(-0.04, 0.025, 0.0), Vector3(0.22, 0.05, 0.04), dark)
		_add_cyl_to(w_node, Vector3(-0.02, 0.05, 0.025), 0.01, 0.035, steel, Vector3(0, 0, 90)) # Alavanca do ferrolho
		_add_cyl_to(w_node, Vector3(-0.02, 0.065, 0.038), 0.012, 0.015, dark)                   # Manopla
		# Cano estriado de aço longo
		_add_cyl_to(w_node, Vector3(-0.35, 0.025, 0.0), 0.014, 0.48, steel, Vector3(0, 0, 90))
		_add_cyl_to(w_node, Vector3(-0.58, 0.025, 0.0), 0.011, 0.03, dark, Vector3(0, 0, 90))  # Boca / muzzle brake
		# Luneta óptica montada sobre anéis
		_add_box_to(w_node, Vector3(-0.02, 0.06, 0.0), Vector3(0.04, 0.025, 0.03), dark) # Anel dianteiro
		_add_box_to(w_node, Vector3(0.08, 0.06, 0.0), Vector3(0.04, 0.025, 0.03), dark)  # Anel traseiro
		_add_cyl_to(w_node, Vector3(0.03, 0.08, 0.0), 0.018, 0.26, dark, Vector3(0, 0, 90)) # Corpo da luneta
		_add_cyl_to(w_node, Vector3(-0.10, 0.08, 0.0), 0.025, 0.05, dark, Vector3(0, 0, 90)) # Objetiva
		_add_cyl_to(w_node, Vector3(-0.126, 0.08, 0.0), 0.022, 0.005, lens, Vector3(0, 0, 90)) # Lente frontal
		_add_cyl_to(w_node, Vector3(0.16, 0.08, 0.0), 0.022, 0.04, dark, Vector3(0, 0, 90))  # Ocular
		# Guarda-mato e gatilho
		_add_box_to(w_node, Vector3(0.05, -0.025, 0.0), Vector3(0.08, 0.025, 0.02), dark)

	elif id in ["shotgun", "escopeta", "pump"]:
		# Escopeta tática de calibre 12 com telha corrediça e cano duplo
		# Coronha e empunhadura sintética preta
		_add_box_to(w_node, Vector3(0.24, 0.02, 0.0), Vector3(0.36, 0.07, 0.042), dark)
		_add_box_to(w_node, Vector3(0.41, 0.02, 0.0), Vector3(0.03, 0.075, 0.045), _mat("pad", Color("#111315"), 0.0, 0.95))
		# Culatra de aço fosco
		_add_box_to(w_node, Vector3(-0.02, 0.022, 0.0), Vector3(0.24, 0.06, 0.045), steel)
		# Cano principal (calibre 12) e tubo carregador inferior
		_add_cyl_to(w_node, Vector3(-0.32, 0.035, 0.0), 0.016, 0.46, steel, Vector3(0, 0, 90))
		_add_cyl_to(w_node, Vector3(-0.28, 0.008, 0.0), 0.014, 0.38, dark, Vector3(0, 0, 90))
		# Telha de engatilhamento em polímero estriado (Pump fore-end)
		_add_cyl_to(w_node, Vector3(-0.22, 0.008, 0.0), 0.022, 0.16, dark, Vector3(0, 0, 90))
		# Massa de mira dourada na ponta
		_add_box_to(w_node, Vector3(-0.54, 0.052, 0.0), Vector3(0.015, 0.015, 0.008), brass)
	else:
		# Espaço vazio: mostra o berço de espuma com recorte negativo da arma
		_add_box_to(w_node, Vector3(0.05, 0.005, 0.0), Vector3(0.95, 0.015, 0.12), _mat("foam_void", Color("#0e1012"), 0.0, 0.98))

# 2. Renderiza Arma Curta na Maleta Pelican
func _spawn_sidearm(weapon_id: String) -> void:
	var id := weapon_id.to_lower()
	var steel := _mat("gun_steel", Color("#2d3136"), 0.85, 0.30)
	var dark := _mat("gun_poly", Color("#1c1f22"), 0.20, 0.70)
	var grip_rubber := _mat("grip_rub", Color("#15181a"), 0.0, 0.95)

	var w_node := Node3D.new()
	w_node.name = "SidearmModel"
	slot_curta_root.add_child(w_node)

	if id in ["pistol", "pistola", "revolver"]:
		# Pistola semiautomática tática 9mm deitada no berço de espuma
		# Ferrolho de aço superior
		_add_box_to(w_node, Vector3(-0.02, 0.025, -0.04), Vector3(0.038, 0.034, 0.18), steel)
		# Ranhuras de ciclagem no ferrolho
		for rz in [0.01, 0.025, 0.04]:
			_add_box_to(w_node, Vector3(-0.02, 0.027, rz), Vector3(0.039, 0.028, 0.004), dark)
		# Armação de polímero e empunhadura
		_add_box_to(w_node, Vector3(-0.02, 0.01, -0.02), Vector3(0.034, 0.025, 0.14), dark)
		_add_box_to(w_node, Vector3(-0.02, 0.015, 0.06), Vector3(0.034, 0.035, 0.09), grip_rubber, Vector3(25.0, 0, 0))
		# Guarda-mato e gatilho
		_add_box_to(w_node, Vector3(-0.02, 0.01, 0.02), Vector3(0.018, 0.028, 0.05), dark)

	elif id in ["smg", "submetralhadora", "sub"]:
		# Submetralhadora compacta com coronha rebatida e carregador curvo
		_add_box_to(w_node, Vector3(-0.02, 0.025, -0.02), Vector3(0.045, 0.05, 0.26), steel)
		_add_cyl_to(w_node, Vector3(-0.02, 0.03, -0.17), 0.012, 0.07, steel, Vector3(90, 0, 0)) # Cano
		_add_box_to(w_node, Vector3(-0.02, 0.015, 0.05), Vector3(0.034, 0.038, 0.07), dark, Vector3(22.0, 0, 0))
		# Carregador alongado
		_add_box_to(w_node, Vector3(-0.02, 0.01, -0.01), Vector3(0.028, 0.035, 0.06), steel)
		# Coronha metálica rebatida na lateral
		_add_box_to(w_node, Vector3(0.012, 0.04, -0.02), Vector3(0.008, 0.03, 0.22), steel)
	else:
		# Recorte vazio de pistola na espuma
		_add_box_to(w_node, Vector3(-0.02, 0.005, 0.0), Vector3(0.08, 0.015, 0.22), _mat("foam_void", Color("#0e1012"), 0.0, 0.98))

# 3. Renderiza Arma Corpo a Corpo no Suporte Rápido
func _spawn_melee(weapon_id: String) -> void:
	var id := weapon_id.to_lower()
	var steel := _mat("knife_steel", Color("#85929e"), 0.90, 0.20)
	var brass := _mat("knife_brass", Color("#d4ac0d"), 0.80, 0.25)
	var rubber := _mat("knife_rubber", Color("#1b2024"), 0.0, 0.90)
	var wood := _mat("bat_wood", Color("#c49a6c"), 0.1, 0.60)

	var w_node := Node3D.new()
	w_node.name = "MeleeModel"
	slot_corpo_root.add_child(w_node)

	if id in ["knife", "faca", "combat_knife", "hunting_knife"]:
		# Faca de caça tática com lâmina drop-point serrilhada e guarda de latão
		# Lâmina de aço fosco (apontando para frente / -Z)
		_add_box_to(w_node, Vector3(0.0, 0.022, -0.08), Vector3(0.008, 0.038, 0.19), steel)
		# Fio de corte chanfrado e dorso serrilhado
		for sz in [-0.14, -0.11, -0.08, -0.05]:
			_add_box_to(w_node, Vector3(0.0, 0.042, sz), Vector3(0.009, 0.006, 0.012), steel)
		# Guarda-mão oval de latão maciço
		_add_box_to(w_node, Vector3(0.0, 0.022, 0.02), Vector3(0.022, 0.065, 0.014), brass)
		# Cabo emborrachado com sulcos ergonômicos para os dedos
		_add_box_to(w_node, Vector3(0.0, 0.022, 0.09), Vector3(0.025, 0.038, 0.13), rubber)
		for gz in [0.05, 0.08, 0.11]:
			_add_box_to(w_node, Vector3(0.0, 0.022, gz), Vector3(0.028, 0.041, 0.012), _mat("k_dark", Color("#111315"), 0.0, 0.95))
		# Pomo de aço no final do cabo com orifício para fiel
		_add_box_to(w_node, Vector3(0.0, 0.022, 0.16), Vector3(0.026, 0.042, 0.016), steel)

	elif id in ["bat", "taco", "baseball"]:
		# Taco esportivo de madeira nobre de freixo torneada
		# Corpo cônico do taco
		_add_cyl_to(w_node, Vector3(0.0, 0.025, -0.07), 0.032, 0.26, wood, Vector3(90, 0, 0))
		# Transição e empunhadura mais fina
		_add_cyl_to(w_node, Vector3(0.0, 0.025, 0.10), 0.018, 0.18, wood, Vector3(90, 0, 0))
		# Grip tape escuro na empunhadura
		_add_cyl_to(w_node, Vector3(0.0, 0.025, 0.10), 0.0195, 0.14, rubber, Vector3(90, 0, 0))
		# Pomo final de retenção
		_add_cyl_to(w_node, Vector3(0.0, 0.025, 0.18), 0.026, 0.02, wood, Vector3(90, 0, 0))
	else:
		# Suporte vazio com borracha de assento
		_add_box_to(w_node, Vector3(0.0, 0.005, 0.0), Vector3(0.06, 0.01, 0.32), _mat("foam_void", Color("#0e1012"), 0.0, 0.98))

# ==============================================================================
# MÉTODOS UTILITÁRIOS DE CRIAÇÃO PROCEDURAL
# ==============================================================================

func _mat(id_name: String, color: Color, metallic: float, roughness: float, emission_energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = id_name
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission_energy
	return m

func _add_box_to(parent: Node, pos: Vector3, size: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = mat
	parent.add_child(mi)
	return mi

func _add_cyl_to(parent: Node, pos: Vector3, radius: float, height: float, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
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
	parent.add_child(mi)
	return mi
