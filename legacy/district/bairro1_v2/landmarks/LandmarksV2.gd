@tool
class_name LandmarksV2
extends Node2D

## LandmarksV2.gd
## Gerenciador e compositor dos marcos unicos, identidade visual, variacao urbana,
## becos caracteristicos e iluminacao noturna do Bairro 1 V2.
## Respeita estritamente o contrato com LayoutV2:
## - z_index elevado para renderizar acima do piso/ruas.
## - Nenhum landmark invade faixas de rolamento ou calcadas de transito.
## - Letreiros compactos posicionados nos topos dos predios, sem cruzar vias.
## - Becos totalmente navegaveis e desobstruidos.
## - Nenhuma colisao solida fisica criada.

const MODULAR_KIT := preload("res://legacy/district/bairro1_v2/landmarks/ModularUrbanKit.gd")
const LANDMARK_BUILDING := preload("res://legacy/district/bairro1_v2/landmarks/LandmarkBuilding.gd")

var _landmarks: Dictionary = {}
var _alleys: Dictionary = {}
var _is_rebuilt: bool = false

# Coordenadas de fallback para execucao standalone (quando LayoutV2 ainda nao estiver no parent)
const FALLBACK_POSITIONS := {
	"MarketEntrance": Vector2(700.0, 600.0),
	"TerminalStop": Vector2(1250.0, 600.0),
	"ParkEntrance": Vector2(0.0, 1100.0),
	"GarageEntrance": Vector2(1400.0, 950.0),
	"WarehouseEntrance": Vector2(1420.0, 1360.0),
	"RailUnderpass": Vector2(900.0, 1500.0),
	"PortApproach": Vector2(1800.0, 90.0),
	"PlayerSpawn": Vector2(150.0, 1080.0),
	"ExitDistrict2": Vector2(2000.0, 700.0),
	"ExitDistrict3": Vector2(1900.0, 1520.0)
}

func _ready() -> void:
	name = "LandmarksV2"
	# z_index elevado garante que predios, telhados, toldos, arvores e props
	# renderizem consistentemente acima do asfalto das ruas (z_index 2 do RoadNetwork)
	z_index = 10
	add_to_group("bairro1_v2_landmarks_root")
	call_deferred("_build_all_landmarks")

func _build_all_landmarks() -> void:
	for child in get_children():
		child.queue_free()
	_landmarks.clear()
	_alleys.clear()

	# 1. Instanciar os 8 Marcos Unicos + Passagem Ferroviaria com offsets precisos de lote
	_spawn_market()
	_spawn_terminal()
	_spawn_park_and_courts()
	_spawn_auto_garage()
	_spawn_warehouse()
	_spawn_bar_boteco()
	_spawn_laundromat()
	_spawn_community_school()
	_spawn_rail_underpass()

	# 2. Preenchimento Cenografico dos 3 Becos (sem bloquear a passagem)
	_build_alley_mural_resistance()
	_build_alley_hidden_fire_escape()
	_build_alley_loading_and_observation()

	_is_rebuilt = true
	print("LANDMARKS_V2_READY: 8 marcos unicos, 3 becos cenograficos e rede de iluminacao construidos sem invadir ruas!")

# ==============================================================================
# RESOLUCAO DE MARCADORES (LayoutV2 com Fallback Standalone)
# ==============================================================================

func get_marker_position(marker_name: String) -> Vector2:
	var parent_node := get_parent()
	if parent_node != null:
		var marker := parent_node.find_child(marker_name, true, false) as Marker2D
		if marker != null:
			return marker.global_position - global_position
	if get_tree() != null and get_tree().root != null:
		var marker_root := get_tree().root.find_child(marker_name, true, false) as Marker2D
		if marker_root != null:
			return marker_root.global_position - global_position
	return FALLBACK_POSITIONS.get(marker_name, Vector2(1000, 1000))

# ==============================================================================
# 1. MERCADO MUNICIPAL / FEIRA
# Lote ao norte do Eixo Comercial e a leste da Rua Local Norte 1.
# ==============================================================================
func _spawn_market() -> void:
	var anchor := get_marker_position("MarketEntrance")
	var market := LANDMARK_BUILDING.new()
	market.name = "Landmark_MercadoMunicipal"
	market.landmark_type = LandmarkBuilding.LandmarkType.MARKET
	market.landmark_title = "Mercado Municipal"
	market.footprint_size = Vector2(220.0, 150.0)
	# Recuo para o interior do lote (Nordeste do cruzamento), mantendo a rua e calcada 100% livres
	market.position = anchor + Vector2(0.0, -130.0)
	add_child(market)
	_landmarks["market"] = market

# ==============================================================================
# 2. TERMINAL RODOVIÁRIO DISTRITAL
# Lote ao norte do Eixo Comercial e a leste da Rua Local Norte 2.
# ==============================================================================
func _spawn_terminal() -> void:
	var anchor := get_marker_position("TerminalStop")
	var terminal := LANDMARK_BUILDING.new()
	terminal.name = "Landmark_TerminalRodoviario"
	terminal.landmark_type = LandmarkBuilding.LandmarkType.BUS_TERMINAL
	terminal.landmark_title = "Terminal Rodoviário Distrital"
	terminal.footprint_size = Vector2(240.0, 150.0)
	# Recuo para o lote de transporte a Nordeste da parada
	terminal.position = anchor + Vector2(0.0, -130.0)
	add_child(terminal)
	_landmarks["terminal"] = terminal

# ==============================================================================
# 3. PARQUE URBANO & QUADRAS
# Área verde externa a oeste do traçado viário da Avenida de Entrada.
# ==============================================================================
func _spawn_park_and_courts() -> void:
	var anchor := get_marker_position("ParkEntrance")
	var park := LANDMARK_BUILDING.new()
	park.name = "Landmark_ParqueCentral"
	park.landmark_type = LandmarkBuilding.LandmarkType.PARK_SPORTS
	park.landmark_title = "Parque Urbano & Quadras"
	park.footprint_size = Vector2(260.0, 200.0)
	# Posicionado na campina oeste, com entrada voltada para o portal
	park.position = anchor + Vector2(-150.0, -80.0)
	add_child(park)
	_landmarks["park"] = park

# ==============================================================================
# 4. OFICINA MECÂNICA / PREPARAÇÃO
# Lote industrial a leste da Rua Local Sul 2.
# ==============================================================================
func _spawn_auto_garage() -> void:
	var anchor := get_marker_position("GarageEntrance")
	var garage := LANDMARK_BUILDING.new()
	garage.name = "Landmark_OficinaVeloz"
	garage.landmark_type = LandmarkBuilding.LandmarkType.AUTO_GARAGE
	garage.landmark_title = "Oficina & Preparação Veloz"
	garage.footprint_size = Vector2(200.0, 140.0)
	# Recuo a leste da rua, com portão de rolo e rampa alinhados ao acesso
	garage.position = anchor
	add_child(garage)
	_landmarks["garage"] = garage

# ==============================================================================
# 5. GALPÃO INDUSTRIAL / LOGÍSTICA
# Lote de cargas a leste da curva sul da Rua Local Sul 2.
# ==============================================================================
func _spawn_warehouse() -> void:
	var anchor := get_marker_position("WarehouseEntrance")
	var wh := LANDMARK_BUILDING.new()
	wh.name = "Landmark_GalpaoLogistica"
	wh.landmark_type = LandmarkBuilding.LandmarkType.WAREHOUSE
	wh.landmark_title = "Galpão Logística & Cargas"
	wh.footprint_size = Vector2(220.0, 160.0)
	# Recuo a leste, deixando o leito carroçável totalmente desimpedido
	wh.position = anchor + Vector2(170.0, -10.0)
	add_child(wh)
	_landmarks["warehouse"] = wh

# ==============================================================================
# 6. BAR DO BAIRRO (Boteco / Sinuca)
# Localizado na testada norte da quadra inicial de entrada.
# ==============================================================================
func _spawn_bar_boteco() -> void:
	var anchor := get_marker_position("PlayerSpawn")
	var bar := LANDMARK_BUILDING.new()
	bar.name = "Landmark_BarBoteco"
	bar.landmark_type = LandmarkBuilding.LandmarkType.BAR_BOTECO
	bar.landmark_title = "Boteco do Esquina"
	bar.footprint_size = Vector2(160.0, 120.0)
	# Recuado com segurança ao norte da Avenida de Entrada
	bar.position = anchor + Vector2(140.0, -170.0)
	add_child(bar)
	_landmarks["bar"] = bar

# ==============================================================================
# 7. LAVANDERIA 24H
# Vizinha ao Bar no quarteirão residencial/comercial.
# ==============================================================================
func _spawn_laundromat() -> void:
	var anchor := get_marker_position("PlayerSpawn")
	var wash := LANDMARK_BUILDING.new()
	wash.name = "Landmark_Lavanderia24h"
	wash.landmark_type = LandmarkBuilding.LandmarkType.LAUNDROMAT
	wash.landmark_title = "Lavanderia Express 24h"
	wash.footprint_size = Vector2(140.0, 110.0)
	# Ao lado do bar, na mesma fachada comercial ao norte da avenida
	wash.position = anchor + Vector2(290.0, -180.0)
	add_child(wash)
	_landmarks["laundromat"] = wash

# ==============================================================================
# 8. ESCOLA / CENTRO COMUNITÁRIO
# No centro da grande quadra cívica entre as Ruas Locais Sul 1 e Sul 2.
# ==============================================================================
func _spawn_community_school() -> void:
	var anchor := get_marker_position("PlayerSpawn")
	var school := LANDMARK_BUILDING.new()
	school.name = "Landmark_CentroComunitarioEscola"
	school.landmark_type = LandmarkBuilding.LandmarkType.COMMUNITY_SCHOOL
	school.landmark_title = "Centro Comunitário & Escola Municipal"
	school.footprint_size = Vector2(220.0, 150.0)
	# Centro do quarteirão cívico (X ~ 1130, Y ~ 950)
	school.position = anchor + Vector2(980.0, -130.0)
	add_child(school)
	_landmarks["school"] = school

# ==============================================================================
# 9. PASSAGEM FERROVIÁRIA / TÚNEL
# Enquadra a Rua Local Sul 1 no cruzamento com a ferrovia ao sul.
# ==============================================================================
func _spawn_rail_underpass() -> void:
	var anchor := get_marker_position("RailUnderpass")
	var underpass := LANDMARK_BUILDING.new()
	underpass.name = "Landmark_PassagemFerroviaria"
	underpass.landmark_type = LandmarkBuilding.LandmarkType.RAIL_UNDERPASS
	underpass.landmark_title = "Passagem Ferroviária Inferior"
	underpass.footprint_size = Vector2(190.0, 90.0)
	# Pilares laterais ficam nas margens da rua, vão central fica 100% transitável
	underpass.position = anchor
	add_child(underpass)
	_landmarks["underpass"] = underpass

# ==============================================================================
# BECO 1: VIELA DA RESISTÊNCIA (Mural de arte urbana e caçamba em reentrância)
# Alinhado ao Beco Oeste (X=400), montado rente à parede lateral oeste.
# ==============================================================================
func _build_alley_mural_resistance() -> void:
	var alley_root := Node2D.new()
	alley_root.name = "Alley_VielaDaResistencia"
	# Posicionado na margem oeste do beco (X ~ 356), deixando os 72px centrais livres
	var player_pos := get_marker_position("PlayerSpawn")
	alley_root.position = Vector2(player_pos.x + 210.0, 1050.0)
	add_child(alley_root)
	
	var mural := MODULAR_KIT.create_graffiti_mural(Vector2.ZERO, Vector2(80.0, 28.0), "RESISTÊNCIA")
	alley_root.add_child(mural)
	
	var dumpster := MODULAR_KIT.create_dumpster(Vector2(-15.0, 32.0), Color("#27ae60"), 0.0)
	alley_root.add_child(dumpster)
	
	var lamp := MODULAR_KIT.create_street_lamp(Vector2(40.0, -15.0), "city", Color("#ff9f43"))
	alley_root.add_child(lamp)
	_alleys["mural"] = alley_root

# ==============================================================================
# BECO 2: BECO DA ESCADA OCULTA (Escada de incêndio metálica na parede norte)
# Alinhado ao Beco Norte (Y=300..320), montado rente à fachada superior.
# ==============================================================================
func _build_alley_hidden_fire_escape() -> void:
	var alley_root := Node2D.new()
	alley_root.name = "Alley_EscadaOculta"
	# Posicionado na fachada norte do beco (Y ~ 265), deixando o piso do beco livre
	var market_pos := get_marker_position("MarketEntrance")
	alley_root.position = Vector2(market_pos.x + 220.0, 265.0)
	add_child(alley_root)
	
	var ladder := MODULAR_KIT.create_fire_escape_ladder(Vector2.ZERO, 65.0)
	alley_root.add_child(ladder)
	
	var pallets := MODULAR_KIT.create_pallet_stack(Vector2(-18.0, -10.0), 3)
	alley_root.add_child(pallets)
	
	var lamp := MODULAR_KIT.create_street_lamp(Vector2(20.0, -12.0), "city", Color("#ffdd59"))
	alley_root.add_child(lamp)
	_alleys["fire_escape"] = alley_root

# ==============================================================================
# BECO 3: ÁREA DE CARGA & PONTO DE OBSERVAÇÃO (Mirante elevado e doca de fundo)
# Alinhado ao Beco Sul (Y=1200..1220), recuado ao norte da via de serviço.
# ==============================================================================
func _build_alley_loading_and_observation() -> void:
	var alley_root := Node2D.new()
	alley_root.name = "Alley_CargaEObservacao"
	# Recuado ao norte do Beco Sul (Y ~ 1160)
	var garage_pos := get_marker_position("GarageEntrance")
	alley_root.position = Vector2(garage_pos.x - 220.0, 1160.0)
	add_child(alley_root)
	
	var dock := MODULAR_KIT.create_loading_dock(Vector2.ZERO, Vector2(85.0, 26.0))
	alley_root.add_child(dock)
	
	var mirante := MODULAR_KIT.create_rooftop_observation_point(Vector2(45.0, -35.0), Vector2(45.0, 28.0))
	alley_root.add_child(mirante)
	
	var floodlight := MODULAR_KIT.create_industrial_floodlight(Vector2(15.0, -10.0), PI * 0.5, Color("#ffd32a"))
	alley_root.add_child(floodlight)
	_alleys["observation"] = alley_root

# ==============================================================================
# API PÚBLICA PARA CODEX E TESTES
# ==============================================================================

func get_landmark(id: String) -> Node2D:
	return _landmarks.get(id, null)

func get_all_landmarks() -> Dictionary:
	return _landmarks

func get_all_alleys() -> Dictionary:
	return _alleys

func get_landmark_summary() -> Array[Dictionary]:
	var summary: Array[Dictionary] = []
	for id in _landmarks:
		var node = _landmarks[id] as LandmarkBuilding
		if node != null:
			summary.append({
				"id": id,
				"name": node.name,
				"title": node.landmark_title,
				"type": node.landmark_type,
				"position": node.position,
				"footprint": node.footprint_size
			})
	return summary

func realign_to_markers() -> void:
	_build_all_landmarks()
