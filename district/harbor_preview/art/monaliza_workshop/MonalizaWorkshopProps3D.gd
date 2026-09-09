@tool
extends Node3D

## MonalizaWorkshopProps3D
## Cenário 3D procedural isolado da oficina do Jäger "Maciota" onde fica a baía
## de preparação do primeiro carro pessoal do Dante: o cupê Monaliza.
##
## Zonas funcionais integradas:
## 1. Área de Serviço / Baía do Elevador:
##    - Vaga livre central desobstruída de 3.50 m x 6.00 m (solo Y=0)
##    - Elevador automotivo hidráulico de 2 colunas com braços articulados e botoeira
##    - Bancada de motores com turbo desmontado, intercooler, morsa e ferramentas
##    - Armário de ferramentas sobre rodízios, mangueira de ar, tambor de óleo e pneus
##    - Iluminação industrial suspensa discreta
## 2. Sala Própria do Maciota (Lounge Executivo Privado VIP):
##    - Acesso a pé fluido através de vão de porta amplo (1.40 m livre, Z entre +0.80m e +2.20m)
##    - Divisória envidraçada estilo loft industrial voltada para a baía do carro
##    - Mesa executiva nobre de mogno com acabamentos em latão polido
##    - Poltrona presidencial de couro capitonê do Maciota e poltrona de visitante
##    - Decanter de uísque de cristal, copos tumbler e bandeja dourada
##    - Luminária clássica de banqueiro com cúpula verde esmeralda e luz suave
##    - Tapete persa ornamental sob a mesa executiva
##    - Cofre pesado de aço e disco de vinil dourado "King of the Night" na parede
##
## Contratos fundamentais de integração com Astra:
## - Origem no centro da vaga do carro: Vector3(0, 0, 0)
## - Piso do nível de solo: Y = 0.0
## - Vaga livre central de 3.5 x 6.0 m desobstruída para o cupê (1.86 x 4.46 x 1.25 m)
## - Saída frontal (+Z) e corredores de circulação a pé 100% livres
## - Sem corpos físicos nativos pesados (expondo get_obstacle_bounds() em AABB)
## - Sem luzes dinâmicas de sombra por objeto para máxima fluidez
## - Pontos de interesse expostos via get_interaction_points()

# Dimensões de referência
var stall_size: Vector2 = Vector2(3.50, 6.00)
var car_reference_size: Vector3 = Vector3(1.86, 1.25, 4.46)
var room_bounds: AABB = AABB(Vector3(-4.40, 0.0, -4.30), Vector3(11.20, 3.80, 9.20))

# Lista interna de obstáculos rígidos (caixas AABB em coordenadas locais em metros)
var _obstacle_bounds: Array[AABB] = []
var _layout_offset := Vector3.ZERO
var _is_built: bool = false

func _ready() -> void:
	if not _is_built:
		_build_workshop()

## Retorna os volumes de colisão AABB (em metros) para a Astra gerar colisões consistentes
func get_obstacle_bounds() -> Array[AABB]:
	if not _is_built:
		_build_workshop()
	return _obstacle_bounds.duplicate()

## Retorna os pontos de interesse locais (em metros) para navegação, interação e diálogos
func get_interaction_points() -> Dictionary:
	return {
		"shop_entrance": Vector3(0.0, 0.0, 4.40),
		"car_driver_door": Vector3(-1.25, 0.0, 0.0),
		"car_passenger_door": Vector3(1.25, 0.0, 0.0),
		"car_hood": Vector3(0.0, 0.0, 2.40),
		"car_trunk": Vector3(0.0, 0.0, -2.40),
		"workbench": Vector3(-0.95, 0.0, -3.20),
		"lift_controls": Vector3(2.05, 0.0, 0.45),
		"office_doorway": Vector3(2.40, 0.0, 1.50),
		"maciota_desk": Vector3(4.50, 0.0, -0.20), # Ponto onde Dante fica em frente à mesa
		"maciota_seat": Vector3(3.40, 0.0, -1.80), # Ponto de interação ao lado da mesa do Maciota
	}

## Retorna as dimensões da vaga livre demarcada no piso
func get_stall_size() -> Vector2:
	return stall_size

## Retorna o transform local da vaga
func get_stall_transform() -> Transform3D:
	return Transform3D.IDENTITY

## Retorna as dimensões de referência do cupê Monaliza
func get_car_reference_size() -> Vector3:
	return car_reference_size

## Retorna a caixa envolvente total da oficina
func get_room_bounds() -> AABB:
	return room_bounds

# ==============================================================================
# CONSTRUÇÃO PROCEDURAL DA OFICINA COMPLETA
# ==============================================================================

func _build_workshop() -> void:
	_is_built = true
	_obstacle_bounds.clear()

	# Materiais PBR padronizados e otimizados
	var mat_concrete := _mat("shop_concrete", Color("#272c30"), 0.10, 0.65)
	var mat_office_floor := _mat("office_wood_floor", Color("#382215"), 0.05, 0.50)
	var mat_carpet := _mat("persian_carpet", Color("#581845"), 0.0, 0.90)
	var mat_carpet_gold := _mat("carpet_gold_fringe", Color("#d4ac0d"), 0.70, 0.35)
	var mat_yellow_line := _mat("safety_yellow", Color("#f39c12"), 0.15, 0.40)
	var mat_black_stripe := _mat("hazard_black", Color("#191d20"), 0.05, 0.85)
	var mat_steel_dark := _mat("industrial_steel", Color("#212529"), 0.80, 0.35)
	var mat_lift_blue := _mat("lift_paint_blue", Color("#1b3b6f"), 0.45, 0.35)
	var mat_hydraulic_chrome := _mat("hydraulic_chrome", Color("#e0e0e0"), 0.95, 0.10)
	var mat_wood_mahogany := _mat("executive_mahogany", Color("#33180c"), 0.05, 0.40)
	var mat_wood_bench := _mat("bench_wood", Color("#4a3222"), 0.05, 0.70)
	var mat_leather_black := _mat("boss_leather", Color("#18181b"), 0.15, 0.45)
	var mat_leather_visitor := _mat("visitor_leather", Color("#3b271d"), 0.10, 0.55)
	var mat_aluminum := _mat("polished_alu", Color("#bdc3c7"), 0.90, 0.20)
	var mat_cast_iron := _mat("cast_iron", Color("#2b3035"), 0.65, 0.55)
	var mat_tool_red := _mat("tool_red", Color("#962d24"), 0.30, 0.40)
	var mat_racing_blue := _mat("monaliza_blue", Color("#1e3799"), 0.40, 0.30)
	var mat_racing_orange := _mat("monaliza_orange", Color("#e67e22"), 0.30, 0.40)
	var mat_rubber := _mat("rubber_black", Color("#14171a"), 0.0, 0.92)
	var mat_brass := _mat("brass_fitting", Color("#d4ac0d"), 0.85, 0.25)
	var mat_banker_green := _mat("banker_glass", Color("#1e5631"), 0.20, 0.15, 0.60)
	var mat_whiskey := _mat("whiskey_amber", Color("#c67d1a"), 0.10, 0.10)
	var mat_glass := _mat("industrial_glass", Color(0.2, 0.3, 0.35, 0.45), 0.20, 0.10)
	mat_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mat_banner_bg := _mat("banner_canvas", Color("#0f172a"), 0.05, 0.80)
	var mat_banner_text := _mat("banner_white", Color("#f8fafc"), 0.10, 0.30)
	var mat_light_glow := _mat("fluorescent_glow", Color("#ffffff"), 0.10, 0.10, 1.8)
	var mat_warm_light_glow := _mat("lamp_warm_glow", Color("#ffddaa"), 0.10, 0.10, 2.2)

	# --------------------------------------------------------------------------
	# 1. PISOS (ÁREA DE SERVIÇO EM CONCRETO + ESCRITÓRIO EM MADEIRA NOBRE)
	# --------------------------------------------------------------------------
	# Piso de concreto da oficina mecânica (X: -4.30 a +2.40, Z: -4.20 a +4.70)
	_add_box(Vector3(-0.95, -0.05, 0.25), Vector3(6.70, 0.10, 8.90), mat_concrete)
	# Piso de madeira nobre encerada do escritório do Maciota (X: +2.40 a +6.60, Z: -4.20 a +4.70)
	_add_box(Vector3(4.50, -0.05, 0.25), Vector3(4.20, 0.10, 8.90), mat_office_floor)
	# Soleira de latão polido no vão da porta (Z: 0.80 a 2.20)
	_add_box(Vector3(2.40, 0.002, 1.50), Vector3(0.08, 0.004, 1.40), mat_brass)

	# Linhas pintadas em amarelo de segurança delimitando a vaga livre (3.5 x 6.0 m)
	# Limite Traseiro (Z = -3.00 m, X: -1.75 a +1.75)
	_add_box(Vector3(0.0, 0.002, -3.00), Vector3(3.50, 0.004, 0.10), mat_yellow_line)
	# Limite Esquerdo (X = -1.75 m, Z: -3.00 a +3.00)
	_add_box(Vector3(-1.75, 0.002, 0.0), Vector3(0.10, 0.004, 6.00), mat_yellow_line)
	# Limite Direito (X = +1.75 m, Z: -3.00 a +3.00)
	_add_box(Vector3(1.75, 0.002, 0.0), Vector3(0.10, 0.004, 6.00), mat_yellow_line)

	# Cantoneiras zebradas nos 2 cantos traseiros da vaga
	for s in [-1.0, 1.0]:
		_add_box(Vector3(s * 1.55, 0.003, -2.85), Vector3(0.35, 0.003, 0.06), mat_black_stripe, Vector3(0, 45.0 * s, 0))
		_add_box(Vector3(s * 1.55, 0.003, -2.75), Vector3(0.35, 0.003, 0.06), mat_black_stripe, Vector3(0, 45.0 * s, 0))

	# Linha frontal de parada indicativa no chão (Z = +2.20 m)
	_add_box(Vector3(0.0, 0.002, 2.20), Vector3(1.20, 0.004, 0.06), mat_yellow_line)

	# --------------------------------------------------------------------------
	# 2. ENVELOPE ARQUITETÔNICO: PAREDES EXTERNAS E PORTAL INDUSTRIAL
	# --------------------------------------------------------------------------
	var mat_wall_dark := _mat("outer_wall", Color("#20252b"), 0.10, 0.85)

	# Parede traseira completa (Z = -4.20 m, de X = -4.30 a +6.60, altura 3.80 m)
	_add_box(Vector3(1.15, 1.90, -4.20), Vector3(10.90, 3.80, 0.20), mat_wall_dark)
	_register_obstacle(Vector3(1.15, 1.90, -4.20), Vector3(10.90, 3.80, 0.20))

	# Parede lateral esquerda da oficina (X = -4.30 m, Z: -4.20 a +4.70)
	_add_box(Vector3(-4.30, 1.90, 0.25), Vector3(0.20, 3.80, 8.90), mat_wall_dark)
	_register_obstacle(Vector3(-4.30, 1.90, 0.25), Vector3(0.20, 3.80, 8.90))

	# Parede lateral direita do escritório (X = +6.60 m, Z: -4.20 a +4.70)
	_add_box(Vector3(6.60, 1.90, 0.25), Vector3(0.20, 3.80, 8.90), mat_wall_dark)
	_register_obstacle(Vector3(6.60, 1.90, 0.25), Vector3(0.20, 3.80, 8.90))

	# Parede frontal (+Z = +4.70 m) com portal industrial aberto de 4.20 m para o carro
	# Painel frontal esquerdo
	_add_box(Vector3(-3.20, 1.90, 4.70), Vector3(2.00, 3.80, 0.20), mat_wall_dark)
	_register_obstacle(Vector3(-3.20, 1.90, 4.70), Vector3(2.00, 3.80, 0.20))
	# Painel frontal direito (frente do escritório)
	_add_box(Vector3(4.50, 1.90, 4.70), Vector3(4.20, 3.80, 0.20), mat_wall_dark)
	_register_obstacle(Vector3(4.50, 1.90, 4.70), Vector3(4.20, 3.80, 0.20))
	# Viga superior do portal frontal (vão livre inferior de 3.20 m de altura)
	_add_box(Vector3(0.0, 3.50, 4.70), Vector3(4.40, 0.60, 0.24), mat_steel_dark)
	_add_cyl(Vector3(0.0, 3.45, 4.60), 0.18, 4.20, mat_cast_iron, Vector3(0, 0, 90))

	# --------------------------------------------------------------------------
	# 3. DIVISÓRIA DA SALA DO MACIOTA E VÃO DE ACESSO A PÉ (X = +2.40 m)
	# --------------------------------------------------------------------------
	# Divisória entre a oficina e o escritório:
	# - Segmento Traseiro com janela loft (Z: -4.20 m a +0.80 m, comp. 5.00 m)
	# - Vão de porta aberto (Z: +0.80 m a +2.20 m, larg. 1.40 m)
	# - Segmento Frontal fechado (Z: +2.20 m a +4.70 m, comp. 2.50 m)

	# Segmento Traseiro da divisória (Z: -4.20 m até +0.80 m, centro Z = -1.70 m)
	_add_box(Vector3(2.40, 0.50, -1.70), Vector3(0.14, 1.00, 5.00), mat_wall_dark)
	_register_obstacle(Vector3(2.40, 0.50, -1.70), Vector3(0.16, 1.00, 5.00))
	# Vidro translúcido com caixilho de aço (Y: 1.00 a 2.60 m)
	_add_box(Vector3(2.40, 1.80, -1.70), Vector3(0.04, 1.60, 4.90), mat_glass)
	# Esquadrias horizontais e verticais do vidro
	for gy in [1.00, 1.80, 2.60]:
		_add_box(Vector3(2.40, gy, -1.70), Vector3(0.08, 0.04, 5.00), mat_steel_dark)
	for gz in [-3.60, -2.70, -1.80, -0.90, 0.0]:
		_add_box(Vector3(2.40, 1.80, gz), Vector3(0.08, 1.60, 0.04), mat_steel_dark)
	# Viga superior da divisória (Y: 2.60 a 3.80 m)
	_add_box(Vector3(2.40, 3.20, -1.70), Vector3(0.14, 1.20, 5.00), mat_wall_dark)

	# Segmento Frontal da divisória (Z: +2.20 m até +4.70 m, centro Z = 3.45 m)
	_add_box(Vector3(2.40, 1.90, 3.45), Vector3(0.14, 3.80, 2.50), mat_wall_dark)
	_register_obstacle(Vector3(2.40, 1.90, 3.45), Vector3(0.16, 3.80, 2.50))

	# Batente da porta de acesso à sala (Z entre +0.80 e +2.20, vão 100% livre no chão)
	_add_box(Vector3(2.40, 1.10, 0.80), Vector3(0.16, 2.20, 0.08), mat_steel_dark)
	_add_box(Vector3(2.40, 1.10, 2.20), Vector3(0.16, 2.20, 0.08), mat_steel_dark)
	_add_box(Vector3(2.40, 2.25, 1.50), Vector3(0.16, 0.10, 1.48), mat_steel_dark)
	_add_box(Vector3(2.40, 3.05, 1.50), Vector3(0.14, 1.50, 1.40), mat_wall_dark)

	# Placa metálica discreta em latão ao lado do batente: "JÄGER"
	_add_box(Vector3(2.32, 1.65, 2.35), Vector3(0.02, 0.12, 0.28), mat_brass)

	# --------------------------------------------------------------------------
	# 4. ELEVADOR AUTOMOTIVO HIDRÁULICO DE 2 COLUNAS (TWO-POST CAR LIFT)
	# --------------------------------------------------------------------------
	# Duas colunas em X = -2.05 m e X = +2.05 m (totalmente fora da vaga de 3.5m: |X| >= 1.90)
	# Alinhadas no eixo central do carro (Z = 0.0 m)

	for col_x in [-2.05, 2.05]:
		var col_dir: float = -1.0 if col_x < 0.0 else 1.0
		var col_pos := Vector3(col_x, 1.60, 0.0)

		# Sapata de ancoragem no piso com parafusos de fixação
		_add_box(Vector3(col_x, 0.02, 0.0), Vector3(0.40, 0.04, 0.40), mat_steel_dark)
		for bx in [-0.15, 0.15]:
			for bz in [-0.15, 0.15]:
				_add_cyl(Vector3(col_x + bx, 0.05, bz), 0.02, 0.03, mat_brass)

		# Coluna principal de aço perfil C estrutural (altura 3.20 m, largura X 0.26 m)
		_add_box(col_pos, Vector3(0.26, 3.20, 0.30), mat_lift_blue)
		# Canaleta interna da guia do carrinho
		_add_box(Vector3(col_x - col_dir * 0.09, 1.60, 0.0), Vector3(0.06, 3.10, 0.18), mat_steel_dark)

		# Obstáculo de colisão das colunas (centrado em col_x, tamanho X: 0.30m -> limites |X|: 1.90 a 2.20)
		_register_obstacle(Vector3(col_x, 1.60, 0.0), Vector3(0.30, 3.20, 0.35))

		# Carrinho de elevação (Carriage) repousando em altura baixa de trabalho (Y = 0.35 m)
		var carr_pos := Vector3(col_x - col_dir * 0.07, 0.35, 0.0)
		_add_box(carr_pos, Vector3(0.18, 0.45, 0.32), mat_steel_dark)
		# Cilindro hidráulico interno visível
		_add_cyl(Vector3(col_x - col_dir * 0.07, 1.20, 0.0), 0.04, 1.50, mat_hydraulic_chrome)

		# Braços articulados telescópicos apontando para os pontos de apoio do chassi
		# Braço dianteiro (aponta para Z = +1.15 m, X aproximando do chassi a 0.90 m)
		var arm_front_mid := Vector3(col_x - col_dir * 0.50, 0.22, 0.55)
		_add_box(arm_front_mid, Vector3(0.12, 0.10, 0.95), mat_lift_blue, Vector3(0, -col_dir * 28.0, 0))
		var pad_front := Vector3(col_x - col_dir * 1.05, 0.24, 1.15)
		_add_cyl(pad_front, 0.07, 0.05, mat_steel_dark)
		_add_cyl(pad_front + Vector3(0, 0.03, 0), 0.075, 0.02, mat_rubber)

		# Braço traseiro (aponta para Z = -1.15 m, X aproximando do chassi a 0.90 m)
		var arm_rear_mid := Vector3(col_x - col_dir * 0.50, 0.22, -0.55)
		_add_box(arm_rear_mid, Vector3(0.12, 0.10, 0.95), mat_lift_blue, Vector3(0, col_dir * 28.0, 0))
		var pad_rear := Vector3(col_x - col_dir * 1.05, 0.24, -1.15)
		_add_cyl(pad_rear, 0.07, 0.05, mat_steel_dark)
		_add_cyl(pad_rear + Vector3(0, 0.03, 0), 0.075, 0.02, mat_rubber)

	# Travessa superior de sincronismo de cabos (Overhead Crossbeam) em Y = 3.25 m
	_add_box(Vector3(0.0, 3.25, 0.0), Vector3(4.10, 0.12, 0.16), mat_lift_blue)

	# Unidade Motora Eletro-Hidráulica & Botoeira (montada na face externa da coluna direita)
	var pump_pos := Vector3(2.23, 1.45, 0.0)
	_add_box(pump_pos, Vector3(0.14, 0.70, 0.20), mat_steel_dark)
	_add_cyl(Vector3(2.23, 1.75, 0.0), 0.055, 0.25, mat_cast_iron)
	# Botoeira industrial com botões
	_add_box(Vector3(2.18, 1.40, 0.13), Vector3(0.06, 0.20, 0.08), _mat("ctrl_yellow", Color("#f39c12"), 0.2, 0.5))
	_add_cyl(Vector3(2.18, 1.45, 0.18), 0.015, 0.02, _mat("btn_green", Color("#2ecc71"), 0.1, 0.3), Vector3(90, 0, 0))
	_add_cyl(Vector3(2.18, 1.38, 0.18), 0.015, 0.02, _mat("btn_black", Color("#2c3e50"), 0.1, 0.3), Vector3(90, 0, 0))
	_add_cyl(Vector3(2.18, 1.30, 0.18), 0.022, 0.025, mat_tool_red, Vector3(90, 0, 0))

	# --------------------------------------------------------------------------
	# 5. BANCADA DE MOTORES (WORKBENCH) — FUNDOS DA BAÍA (X = -0.60 m, Z = -3.65 m)
	# --------------------------------------------------------------------------
	_layout_offset = Vector3(-0.35, 0, 0)
	var bench_center := Vector3(-0.60, 0.45, -3.65)
	var bench_size := Vector3(2.10, 0.90, 0.70)
	_register_obstacle(bench_center, bench_size + Vector3(0.1, 0.0, 0.1))

	# Pernas de aço e travessas da bancada
	for bx in [-1.55, 0.35]:
		for bz in [-3.92, -3.38]:
			_add_box(Vector3(bx, 0.43, bz), Vector3(0.06, 0.86, 0.06), mat_steel_dark)
	# Prateleira inferior
	_add_box(Vector3(-0.60, 0.18, -3.65), Vector3(1.96, 0.03, 0.58), mat_steel_dark)
	# Tampo espesso de madeira tratada
	_add_box(Vector3(-0.60, 0.88, -3.65), Vector3(2.10, 0.06, 0.70), mat_wood_bench)
	# Aba de proteção metálica posterior
	_add_box(Vector3(-0.60, 0.94, -3.98), Vector3(2.10, 0.08, 0.03), mat_steel_dark)

	# Morsa de bancada em ferro fundido azul Monaliza
	_add_box(Vector3(0.25, 0.94, -3.42), Vector3(0.18, 0.06, 0.18), mat_racing_blue)
	_add_box(Vector3(0.25, 1.02, -3.42), Vector3(0.14, 0.12, 0.22), mat_racing_blue)
	_add_box(Vector3(0.25, 1.06, -3.32), Vector3(0.16, 0.05, 0.04), mat_steel_dark)
	_add_cyl(Vector3(0.25, 1.02, -3.28), 0.012, 0.22, mat_aluminum, Vector3(0, 0, 90))

	# Turboalimentador desmontado:
	_add_cyl(Vector3(-0.40, 0.98, -3.55), 0.11, 0.09, mat_cast_iron, Vector3(90, 0, 0))
	_add_box(Vector3(-0.40, 0.98, -3.48), Vector3(0.14, 0.12, 0.06), mat_cast_iron)
	_add_cyl(Vector3(-0.16, 0.97, -3.55), 0.12, 0.08, mat_aluminum, Vector3(90, 0, 0))
	_add_cyl(Vector3(-0.16, 0.97, -3.49), 0.065, 0.06, mat_aluminum, Vector3(90, 0, 0))
	_add_box(Vector3(-0.02, 0.915, -3.68), Vector3(0.24, 0.01, 0.18), _mat("shop_rag", Color("#2980b9"), 0.0, 0.95))
	_add_cyl(Vector3(-0.02, 0.94, -3.68), 0.012, 0.16, mat_steel_dark, Vector3(0, 0, 90))
	_add_cyl(Vector3(-0.08, 0.94, -3.68), 0.042, 0.03, mat_aluminum, Vector3(0, 0, 90))

	# Intercooler frontal apoiado verticalmente
	_add_box(Vector3(-1.15, 1.10, -3.90), Vector3(0.72, 0.32, 0.07), mat_aluminum)
	_add_box(Vector3(-1.15, 1.10, -3.86), Vector3(0.68, 0.28, 0.01), _mat("fins", Color("#7f8c8d"), 0.6, 0.5))
	_add_box(Vector3(-1.54, 1.10, -3.90), Vector3(0.08, 0.30, 0.08), mat_aluminum)
	_add_box(Vector3(-0.76, 1.10, -3.90), Vector3(0.08, 0.30, 0.08), mat_aluminum)
	_add_cyl(Vector3(-1.54, 1.20, -3.82), 0.038, 0.10, mat_racing_orange, Vector3(90, 0, 0))
	_add_cyl(Vector3(-0.76, 1.20, -3.82), 0.038, 0.10, mat_racing_blue, Vector3(90, 0, 0))

	_layout_offset = Vector3.ZERO
	# Banner decorativo na parede dos fundos da oficina (cenográfico)
	_add_box(Vector3(-0.80, 2.65, -4.08), Vector3(3.20, 1.10, 0.02), mat_banner_bg)
	_add_box(Vector3(-0.80, 2.80, -4.07), Vector3(3.00, 0.05, 0.01), mat_racing_blue)
	_add_box(Vector3(-0.80, 2.73, -4.07), Vector3(3.00, 0.03, 0.01), mat_racing_orange)
	_add_box(Vector3(-0.80, 2.40, -4.07), Vector3(2.60, 0.26, 0.01), mat_banner_text)

	# --------------------------------------------------------------------------
	# 6. EQUIPAMENTOS DE APOIO DA OFICINA (LATERAL ESQUERDA)
	# --------------------------------------------------------------------------
	# Armário / Carrinho de ferramentas vermelho (X = -2.85 m, Z = -2.10 m)
	_layout_offset = Vector3(-0.60, 0, 0)
	var chest_center := Vector3(-2.85, 0.58, -2.10)
	var chest_size := Vector3(0.85, 1.16, 0.55)
	_register_obstacle(chest_center, chest_size + Vector3(0.1, 0.0, 0.1))
	_add_box(chest_center, Vector3(0.82, 0.98, 0.52), mat_tool_red)
	for i in range(5):
		var gy: float = 0.28 + float(i) * 0.15
		_add_box(Vector3(-2.85, gy, -1.83), Vector3(0.74, 0.11, 0.02), mat_black_stripe)
		_add_box(Vector3(-2.85, gy + 0.03, -1.815), Vector3(0.68, 0.018, 0.015), mat_aluminum)
	_add_box(Vector3(-2.85, 1.08, -2.10), Vector3(0.84, 0.02, 0.54), mat_rubber)

	_layout_offset = Vector3.ZERO
	# Carretel de mangueira de ar na parede esquerda (X = -4.18 m, Y = 1.70 m, Z = -1.20 m)
	_add_box(Vector3(-4.22, 1.70, -1.20), Vector3(0.08, 0.24, 0.18), mat_steel_dark)
	_add_cyl(Vector3(-4.08, 1.70, -1.20), 0.19, 0.18, mat_tool_red, Vector3(0, 0, 90))
	_add_cyl(Vector3(-3.95, 1.35, -1.15), 0.014, 0.50, mat_rubber, Vector3(15.0, 0, 0))
	_add_cyl(Vector3(-3.95, 1.10, -1.08), 0.018, 0.06, mat_brass, Vector3(15.0, 0, 0))

	# Tambor de óleo industrial 200L azul Monaliza (X = -3.50 m, Z = -3.50 m)
	var drum_pos := Vector3(-3.50, 0.45, -3.50)
	_add_cyl(drum_pos, 0.29, 0.90, mat_racing_blue)
	_add_cyl(Vector3(-3.50, 0.25, -3.50), 0.305, 0.03, mat_steel_dark)
	_add_cyl(Vector3(-3.50, 0.65, -3.50), 0.305, 0.03, mat_steel_dark)
	_register_obstacle(drum_pos, Vector3(0.65, 0.92, 0.65))

	# Roda com pneu slick de corrida encostada na parede esquerda (X = -3.85 m, Z = 0.80 m)
	var tire_pos := Vector3(-3.85, 0.33, 0.80)
	_add_cyl(tire_pos, 0.33, 0.24, mat_rubber, Vector3(0, 0, 80.0))
	_add_cyl(tire_pos + Vector3(0.02, 0, 0), 0.21, 0.06, mat_aluminum, Vector3(0, 0, 80.0))
	_register_obstacle(tire_pos, Vector3(0.40, 0.66, 0.50))

	# Dois cavaletes de sustentação (Jack Stands) recolhidos (X = -2.30 m, Z = -3.65 m)
	for jx in [-2.30, -2.62]:
		var j_pos := Vector3(jx, 0.20, -3.65)
		_add_box(j_pos, Vector3(0.18, 0.28, 0.18), mat_tool_red)
		_add_cyl(Vector3(jx, 0.38, -3.65), 0.016, 0.14, mat_steel_dark)
		_add_box(Vector3(jx, 0.44, -3.65), Vector3(0.08, 0.03, 0.06), mat_cast_iron)
		_register_obstacle(Vector3(jx, 0.22, -3.65), Vector3(0.24, 0.45, 0.24))

	# --------------------------------------------------------------------------
	# 7. SALA PRÓPRIA DO MACIOTA: MOBILIÁRIO VIP E DETALHES DE PERSONALIDADE
	# --------------------------------------------------------------------------
	# A sala fica à direita (X: +2.40 m a +6.60 m, Z: -4.20 m a +4.70 m)

	# A. Tapete Persa Ornamental sob a mesa executiva
	# Dimensões: 2.60 m x 1.80 m, centrado em X = 4.50 m, Z = -1.80 m
	_add_box(Vector3(4.50, 0.003, -1.80), Vector3(2.60, 0.003, 1.80), mat_carpet)
	_add_box(Vector3(4.50, 0.004, -0.90), Vector3(2.64, 0.004, 0.05), mat_carpet_gold)
	_add_box(Vector3(4.50, 0.004, -2.70), Vector3(2.64, 0.004, 0.05), mat_carpet_gold)
	_add_box(Vector3(3.20, 0.004, -1.80), Vector3(0.05, 0.004, 1.80), mat_carpet_gold)
	_add_box(Vector3(5.80, 0.004, -1.80), Vector3(0.05, 0.004, 1.80), mat_carpet_gold)

	# B. Mesa Executiva Nobre de Mogno do Maciota (X = 4.50 m, Z = -1.80 m)
	# Dimensões: 1.70 m x 0.80 m, altura 0.76 m (Z de -2.20 a -1.40)
	var desk_center := Vector3(4.50, 0.38, -1.80)
	var desk_size := Vector3(1.70, 0.76, 0.80)
	_register_obstacle(desk_center, desk_size + Vector3(0.06, 0.0, 0.06))

	_add_box(Vector3(4.50, 0.73, -1.80), Vector3(1.70, 0.06, 0.80), mat_wood_mahogany)
	_add_box(Vector3(4.50, 0.73, -1.40), Vector3(1.72, 0.02, 0.02), mat_brass)
	_add_box(Vector3(4.50, 0.73, -2.20), Vector3(1.72, 0.02, 0.02), mat_brass)
	for gx in [3.90, 5.10]:
		_add_box(Vector3(gx, 0.35, -1.80), Vector3(0.48, 0.68, 0.74), mat_wood_mahogany)
		for gy in [0.20, 0.40, 0.60]:
			_add_box(Vector3(gx, gy, -1.42), Vector3(0.12, 0.02, 0.02), mat_brass)
	_add_box(Vector3(4.50, 0.42, -1.46), Vector3(0.72, 0.56, 0.03), mat_wood_mahogany)
	_add_box(Vector3(4.50, 0.765, -1.75), Vector3(0.65, 0.005, 0.45), _mat("desk_pad", Color("#112918"), 0.0, 0.8))

	# C. Poltrona Presidencial do Maciota (Atrás da mesa: X = 4.50 m, Z = -2.75 m)
	var chair_center := Vector3(4.50, 0.55, -2.75)
	_register_obstacle(chair_center, Vector3(0.65, 1.10, 0.65))
	_add_cyl(Vector3(4.50, 0.08, -2.75), 0.32, 0.04, mat_steel_dark)
	_add_cyl(Vector3(4.50, 0.22, -2.75), 0.035, 0.26, mat_hydraulic_chrome)
	_add_box(Vector3(4.50, 0.45, -2.70), Vector3(0.62, 0.14, 0.58), mat_leather_black)
	_add_box(Vector3(4.50, 0.85, -2.95), Vector3(0.58, 0.72, 0.12), mat_leather_black, Vector3(-5.0, 0, 0))
	for ax in [4.16, 4.84]:
		_add_box(Vector3(ax, 0.62, -2.73), Vector3(0.06, 0.22, 0.38), mat_steel_dark)
		_add_box(Vector3(ax, 0.73, -2.73), Vector3(0.08, 0.04, 0.38), mat_leather_black)

	# D. Poltrona de Visitante do Dante (Frente da mesa: X = 4.50 m, Z = -0.85 m)
	_layout_offset = Vector3(0.55, 0, -0.20)
	var vchair_center := Vector3(4.50, 0.45, -0.85)
	_register_obstacle(vchair_center, Vector3(0.60, 0.90, 0.60))
	for px in [4.24, 4.76]:
		for pz in [-1.08, -0.62]:
			_add_cyl(Vector3(px, 0.22, pz), 0.025, 0.44, mat_wood_mahogany)
	_add_box(Vector3(4.50, 0.44, -0.85), Vector3(0.56, 0.10, 0.52), mat_leather_visitor)
	_add_box(Vector3(4.50, 0.72, -0.61), Vector3(0.52, 0.50, 0.08), mat_leather_visitor, Vector3(6.0, 0, 0))

	_layout_offset = Vector3.ZERO
	# E. Objetos de Personalidade do Maciota sobre a Mesa:
	# 1. Luminária clássica de banqueiro (Banker's Lamp) com cúpula verde esmeralda
	var lamp_pos := Vector3(5.05, 0.76, -1.95)
	_add_cyl(lamp_pos + Vector3(0, 0.02, 0), 0.07, 0.03, mat_brass)
	_add_cyl(lamp_pos + Vector3(0, 0.18, 0), 0.012, 0.30, mat_brass)
	_add_cyl(lamp_pos + Vector3(0, 0.30, 0), 0.06, 0.20, mat_banker_green, Vector3(0, 0, 90))
	_add_box(lamp_pos + Vector3(0, 0.27, 0), 0.04 * Vector3.ONE, mat_warm_light_glow)

	# 2. Bandeja de latão com garrafa decanter de uísque e copos de cristal
	var tray_pos := Vector3(3.95, 0.76, -1.85)
	_add_box(tray_pos + Vector3(0, 0.01, 0), Vector3(0.32, 0.02, 0.24), mat_brass)
	_add_box(tray_pos + Vector3(-0.06, 0.10, 0.0), Vector3(0.10, 0.16, 0.10), mat_whiskey)
	_add_cyl(tray_pos + Vector3(-0.06, 0.20, 0.0), 0.025, 0.04, mat_brass)
	_add_box(tray_pos + Vector3(-0.06, 0.23, 0.0), Vector3(0.04, 0.03, 0.04), mat_aluminum)
	_add_cyl(tray_pos + Vector3(0.07, 0.05, -0.04), 0.032, 0.07, mat_whiskey)
	_add_cyl(tray_pos + Vector3(0.07, 0.05, 0.05), 0.032, 0.07, mat_aluminum)

	# 3. Cinzeiro de cristal com charuto cubano repousado
	var ash_pos := Vector3(4.45, 0.77, -1.52)
	_add_cyl(ash_pos, 0.05, 0.02, mat_cast_iron)
	_add_cyl(ash_pos + Vector3(0.02, 0.015, 0.0), 0.008, 0.08, _mat("cigar", Color("#422c1d"), 0.0, 0.9), Vector3(0, 0, 75))

	# F. Cofre Pesado de Aço do Maciota (Canto dos Fundos: X = 6.00 m, Z = -3.70 m)
	var safe_pos := Vector3(6.00, 0.65, -3.70)
	var safe_size := Vector3(0.80, 1.30, 0.70)
	_register_obstacle(safe_pos, safe_size)
	_add_box(safe_pos, safe_size, mat_steel_dark)
	_add_box(safe_pos + Vector3(-0.02, 0.0, 0.35), Vector3(0.70, 1.20, 0.04), _mat("safe_door", Color("#15181b"), 0.7, 0.4))
	for hy in [-0.40, 0.40]:
		_add_cyl(safe_pos + Vector3(-0.35, hy, 0.38), 0.03, 0.12, mat_brass)
	_add_cyl(safe_pos + Vector3(0.12, 0.05, 0.39), 0.09, 0.03, mat_aluminum, Vector3(90, 0, 0))
	_add_cyl(safe_pos + Vector3(0.12, 0.22, 0.38), 0.04, 0.02, mat_brass, Vector3(90, 0, 0))

	# G. Decoração de Parede: Disco de Vinil Dourado "King of the Night" (Parede de trás)
	var record_pos := Vector3(4.50, 2.20, -4.08)
	_add_box(record_pos, Vector3(0.85, 0.85, 0.03), mat_steel_dark)
	_add_box(record_pos + Vector3(0, 0, 0.015), Vector3(0.75, 0.75, 0.01), mat_carpet)
	_add_cyl(record_pos + Vector3(0, 0, 0.025), 0.30, 0.01, mat_brass, Vector3(90, 0, 0))
	_add_cyl(record_pos + Vector3(0, 0, 0.032), 0.10, 0.01, mat_tool_red, Vector3(90, 0, 0))
	_add_box(record_pos + Vector3(0, -0.28, 0.025), Vector3(0.35, 0.07, 0.01), mat_brass)

	# H. Cabideiro de Pé (Mancebo) com Chapéu Fedora no escritório
	var coat_pos := Vector3(6.00, 0.90, 1.50)
	_register_obstacle(coat_pos, Vector3(0.40, 1.80, 0.40))
	_add_cyl(coat_pos + Vector3(0, -0.85, 0), 0.22, 0.05, mat_brass)
	_add_cyl(coat_pos, 0.025, 1.80, mat_brass)
	for gi in range(4):
		var gang := float(gi) * PI * 0.5
		var gx := cos(gang) * 0.14
		var gz := sin(gang) * 0.14
		_add_cyl(coat_pos + Vector3(gx, 0.75, gz), 0.01, 0.16, mat_brass, Vector3(cos(gang) * 35, 0, sin(gang) * 35))
	_add_cyl(coat_pos + Vector3(0.12, 0.78, 0.0), 0.14, 0.02, mat_leather_black)
	_add_cyl(coat_pos + Vector3(0.12, 0.83, 0.0), 0.08, 0.08, mat_leather_black)
	_add_cyl(coat_pos + Vector3(0.12, 0.80, 0.0), 0.085, 0.015, mat_carpet_gold)

	# I. Arquivo / Aparador Lateral de Escritório (Parede Leste: X = 6.25 m, Z = -1.20 m)
	var credenza_pos := Vector3(6.25, 0.45, -1.20)
	var credenza_size := Vector3(0.50, 0.90, 1.20)
	_register_obstacle(credenza_pos, credenza_size)
	_add_box(credenza_pos, credenza_size, mat_wood_mahogany)
	for d in [-0.30, 0.30]:
		_add_box(Vector3(5.98, 0.45, -1.20 + d), Vector3(0.03, 0.80, 0.50), mat_wood_bench)
		_add_box(Vector3(5.95, 0.45, -1.20 + d), Vector3(0.02, 0.12, 0.02), mat_brass)

	# --------------------------------------------------------------------------
	# 8. LUMINÁRIAS SUSPENSAS INDUSTRIAIS (ÁREA DE SERVIÇO & SALA)
	# --------------------------------------------------------------------------
	for lx in [-1.20, 0.80]:
		_add_box(Vector3(lx, 3.40, -0.40), Vector3(0.24, 0.08, 3.60), mat_steel_dark)
		_add_box(Vector3(lx - 0.06, 3.35, -0.40), Vector3(0.06, 0.02, 3.50), mat_light_glow)
		_add_box(Vector3(lx + 0.06, 3.35, -0.40), Vector3(0.06, 0.02, 3.50), mat_light_glow)
		for lz in [-1.90, 1.10]:
			_add_cyl(Vector3(lx, 3.65, lz), 0.005, 0.50, mat_aluminum)

	_add_box(Vector3(4.50, 3.40, -1.80), Vector3(1.20, 0.06, 1.20), mat_steel_dark)
	_add_box(Vector3(4.50, 3.36, -1.80), Vector3(1.00, 0.02, 1.00), mat_warm_light_glow)

# ==============================================================================
# MÉTODOS UTILITÁRIOS
# ==============================================================================

func _register_obstacle(center: Vector3, size: Vector3) -> void:
	var aabb := AABB(center + _layout_offset - size * 0.5, size)
	_obstacle_bounds.append(aabb)

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

func _add_box(pos: Vector3, size: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos + _layout_offset
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
	mi.position = pos + _layout_offset
	mi.rotation_degrees = rot_deg
	mi.material_override = mat
	add_child(mi)
	return mi
