@tool
class_name PortMarkedCarSet
extends Node2D

## PortMarkedCarSet.gd
## Módulo visual autoral e independente para o cenário da primeira missão no Porto.
## Layout 100% fixo e determinístico construído com geometria nativa do Godot 4.
## Totalmente desacoplado: pronto para o CODEX instanciar carros, polícia e lógica.

# Dimensões e Limites do Set
const PORT_BOUNDS := Rect2(0.0, 0.0, 1600.0, 1080.0)

# Coordenadas fixas dos 8 marcadores autorais
const TARGET_SPAWN_POS := Vector2(270.0, 540.0)
const DELIVERY_POS := Vector2(170.0, 710.0)
const ROADBLOCK_A_POS := Vector2(550.0, 250.0)
const ROADBLOCK_B_POS := Vector2(1200.0, 320.0)
const POLICE_SPAWN_A_POS := Vector2(300.0, 110.0)
const POLICE_SPAWN_B_POS := Vector2(1440.0, 380.0)
const ESCAPE_ROUTE_POS := Vector2(1520.0, 160.0)
const CAMERA_ANCHOR_POS := Vector2(800.0, 560.0)

# Paleta industrial cartunesca alinhada à malha viária oficial de Bairro 1
const COLOR_ASPHALT := Color("#202932")
const COLOR_CONCRETE_QUAY := Color("#7d8285")
const COLOR_CONCRETE_YARD := Color("#888d8e")
const COLOR_SIDEWALK := Color("#aaa9a1")
const COLOR_CURB := Color("#70767a")
const COLOR_LANE_YELLOW := Color("#dfc84d")
const COLOR_ZEBRA_WHITE := Color("#dadcd6")
const COLOR_HAZARD_YELLOW := Color("#d89e24")
const COLOR_HAZARD_BLACK := Color("#1a1c1e")
const COLOR_SEA_WATER := Color("#173147")
const COLOR_SEA_FOAM := Color("#7fb5d4")
const COLOR_FENCE_STEEL := Color("#4f5860")
const COLOR_DELIVERY_ZONE := Color("#2ecc71")

# Dicionário de marcadores instanciados
var _markers: Dictionary = {}
var _standalone_camera: Camera2D = null
var _wave_time: float = 0.0

func _ready() -> void:
	z_index = 0
	# Force-rebuild all visual children. Editor serialization corrupts inner
	# class scripts (saves them as empty GDScript sub-resources), so any
	# previously serialized nodes would have blank _draw() methods.
	for child_name in [
		"GroundVisuals", "PerimeterFences", "IndustrialBuildings",
		"ContainerStacks", "PierGantryCrane", "SecurityGatehouse",
		"IndustrialProps", "PortLighting", "MissionMarkers"
	]:
		var stale = get_node_or_null(child_name)
		if stale != null:
			remove_child(stale)
			stale.queue_free()
	_build_ground_and_water()
	_build_perimeter_and_fences()
	_build_warehouses()
	_build_container_stacks()
	_build_gantry_crane()
	_build_gatehouse()
	_build_industrial_props()
	_build_lighting()
	_build_mission_markers()
	if not Engine.is_editor_hint():
		_setup_camera_anchor_support()

func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		_wave_time += delta * 2.0
		# Redesenho leve da espuma da água a cada ~0.15s
		var water_node = get_node_or_null("GroundVisuals/WaterVisual")
		if water_node and water_node is CanvasItem:
			water_node.queue_redraw()

# ==============================================================================
# 1. PISO, RUAS, CALÇADAS E ÁGUA PORTUÁRIA
# ==============================================================================
func _build_ground_and_water() -> void:
	var ground_root := Node2D.new()
	ground_root.name = "GroundVisuals"
	ground_root.z_index = -10
	add_child(ground_root)
	
	# Sub-nó com o desenho vetorial completo do solo
	var ground_drawer := _PortGroundDrawer.new()
	ground_drawer.name = "PavementsAndRoads"
	ground_root.add_child(ground_drawer)
	
	# Água do Porto com ondulação vetorial
	var water_drawer := _PortWaterDrawer.new(self)
	water_drawer.name = "WaterVisual"
	ground_root.add_child(water_drawer)
	
	# Barreira de colisão na beira do cais para impedir carros de caírem na água
	var sea_barrier := StaticBody2D.new()
	sea_barrier.name = "QuaySeaBarrier"
	sea_barrier.collision_layer = 1
	sea_barrier.collision_mask = 0
	
	var sea_col := CollisionShape2D.new()
	var sea_shape := RectangleShape2D.new()
	sea_shape.size = Vector2(1600.0, 24.0)
	sea_col.shape = sea_shape
	sea_col.position = Vector2(800.0, 928.0)
	sea_barrier.add_child(sea_col)
	add_child(sea_barrier)

# ==============================================================================
# 2. CERCAS, PORTÕES E PERÍMETRO DE SEGURANÇA
# ==============================================================================
func _build_perimeter_and_fences() -> void:
	var fence_root := Node2D.new()
	fence_root.name = "PerimeterFences"
	fence_root.z_index = 2
	add_child(fence_root)
	
	# Seções de cerca com colisão estática
	# 1. Cerca Norte - Lado Oeste (X: 60 até 440, Y: 224) - Atrás da calçada de pedestres
	_add_fence_section(fence_root, Vector2(60, 224), Vector2(440, 224), "FenceNorth_West")
	# 2. Cerca Norte - Lado Leste (X: 660 até 1540, Y: 224) - Atrás da calçada de pedestres
	_add_fence_section(fence_root, Vector2(660, 224), Vector2(1540, 224), "FenceNorth_East")
	# 3. Cerca Oeste (X: 60, Y: 224 até 920)
	_add_fence_section(fence_root, Vector2(60, 224), Vector2(60, 920), "FenceWest")
	# 4. Cerca Leste - Trecho Superior (X: 1540, Y: 240 até 920) - Deixa saída de fuga aberta (Y: 120 a 240)
	_add_fence_section(fence_root, Vector2(1540, 240), Vector2(1540, 920), "FenceEast")
	
	# Mureta baixa de proteção ao redor do pátio traseiro (Warehouse Alpha)
	_add_wall_section(fence_root, Rect2(60, 760, 240, 12), "RetainingWall_SouthYard")

func _add_fence_section(parent: Node, start: Vector2, end_pt: Vector2, section_name: String) -> void:
	var body := StaticBody2D.new()
	body.name = section_name
	body.set_meta("_edit_group_", true)
	body.collision_layer = 1
	body.collision_mask = 0
	
	var col := CollisionShape2D.new()
	var seg := SegmentShape2D.new()
	seg.a = start
	seg.b = end_pt
	col.shape = seg
	body.add_child(col)
	
	var visual := _PortFenceDrawer.new(start, end_pt)
	body.add_child(visual)
	parent.add_child(body)

func _add_wall_section(parent: Node, rect: Rect2, wall_name: String) -> void:
	var body := StaticBody2D.new()
	body.name = wall_name
	body.set_meta("_edit_group_", true)
	body.collision_layer = 1
	body.collision_mask = 0
	
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	col.shape = shape
	col.position = rect.get_center()
	body.add_child(col)
	
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		rect.position,
		rect.position + Vector2(rect.size.x, 0),
		rect.end,
		rect.position + Vector2(0, rect.size.y)
	])
	poly.color = Color("#4b5358")
	body.add_child(poly)
	parent.add_child(body)

# ==============================================================================
# 3. GALPÕES INDUSTRIAIS 2.5D COM COLISÃO SÓLIDA
# ==============================================================================
func _build_warehouses() -> void:
	var buildings_root := Node2D.new()
	buildings_root.name = "IndustrialBuildings"
	buildings_root.z_index = 4
	add_child(buildings_root)
	
	# Galpão Alfa: "DOCA 01 - ALFÂNDEGA / LOGÍSTICA"
	# Onde o carro-alvo estará estacionado na rampa coberta
	var warehouse_alpha := _PortWarehouse.new(
		Rect2(80.0, 240.0, 360.0, 200.0),
		"DOCA 01 - ALFÂNDEGA",
		Color("#2b3e50"), # Teto azul ardósia industrial
		Color("#17242f"), # Borda
		Color("#5c6d7a"), # Fachada 2.5D
		Color("#d35400"), # Portões basculantes laranja
		true # Com rampa de carga ao sul
	)
	warehouse_alpha.name = "WarehouseAlpha_Doca01"
	warehouse_alpha.set_meta("_edit_group_", true)
	buildings_root.add_child(warehouse_alpha)
	
	# Galpão Beta: "DOCA 02 - ARMAZÉM FRIGORÍFICO"
	var warehouse_beta := _PortWarehouse.new(
		Rect2(1250.0, 420.0, 280.0, 180.0),
		"DOCA 02 - FRIGORÍFICO",
		Color("#6d4036"), # Teto terracota / ferrugem industrial
		Color("#351e18"), # Borda
		Color("#7d5b53"), # Fachada 2.5D
		Color("#27ae60"), # Portões verdes industriais
		false
	)
	warehouse_beta.name = "WarehouseBeta_Doca02"
	warehouse_beta.set_meta("_edit_group_", true)
	buildings_root.add_child(warehouse_beta)
	
	# Oficina Mecânica e Manutenção Naval (Canto Nordeste)
	var workshop := _PortWarehouse.new(
		Rect2(1280.0, 230.0, 180.0, 110.0),
		"OFICINA NAVAL",
		Color("#48535a"), # Zinco escuro
		Color("#22292e"),
		Color("#5e6970"),
		Color("#c0392b"),
		false
	)
	workshop.name = "NavalWorkshop"
	workshop.set_meta("_edit_group_", true)
	buildings_root.add_child(workshop)

# ==============================================================================
# 4. PÁTIO DE CONTÊINERES COM LABIRINTO DE FUGA
# ==============================================================================
func _build_container_stacks() -> void:
	var container_root := Node2D.new()
	container_root.name = "ContainerStacks"
	container_root.z_index = 5
	add_child(container_root)
	
	# Definição determinística de todos os contêineres do pátio
	# Cada contêiner possui tamanho padronizado 120 x 48 px com extrusão 2.5D
	var container_specs := [
		# Bloco Noroeste (Stack 1) - Companhias Navais Fictícias
		{"pos": Vector2(620, 250), "color": Color("#1f4788"), "label": "NSL-104", "roof_lines": 10}, # Nave Sul
		{"pos": Vector2(750, 250), "color": Color("#b03a2e"), "label": "BRC-772", "roof_lines": 10}, # Brasa Cargas
		{"pos": Vector2(620, 310), "color": Color("#196f3d"), "label": "ATL-490", "roof_lines": 10}, # Atlântico Log
		{"pos": Vector2(750, 310), "color": Color("#d4ac0d"), "label": "PLE-901", "roof_lines": 10}, # Porto Leste
		
		# Bloco Nordeste (Stack 2) - Estreitamento para o Roadblock B
		{"pos": Vector2(890, 250), "color": Color("#2874a6"), "label": "CTF-202", "roof_lines": 10}, # Costa Forte
		{"pos": Vector2(1020, 250), "color": Color("#ba4a00"), "label": "MRD-612", "roof_lines": 10}, # Meridiano Cargas
		{"pos": Vector2(890, 310), "color": Color("#7d3c98"), "label": "VMR-884", "roof_lines": 10}, # Via Marítima
		{"pos": Vector2(1020, 310), "color": Color("#117864"), "label": "SRA-505", "roof_lines": 10}, # Serra Shipping
		
		# Bloco Central / Sul (Stack 3) - Cria corredor em S e rotas alternativas
		{"pos": Vector2(640, 520), "color": Color("#922b21"), "label": "NSL-119", "roof_lines": 10}, # Nave Sul
		{"pos": Vector2(770, 520), "color": Color("#1f618d"), "label": "BRC-708", "roof_lines": 10}, # Brasa Cargas
		{"pos": Vector2(640, 580), "color": Color("#d68910"), "label": "ATL-221", "roof_lines": 10}, # Atlântico Log
		{"pos": Vector2(770, 580), "color": Color("#145a32"), "label": "PLE-990", "roof_lines": 10}, # Porto Leste
		
		# Bloco Sudeste (Stack 4) - Próximo ao Cais e ao Galpão Beta
		{"pos": Vector2(950, 580), "color": Color("#2e4053"), "label": "CTF-303", "roof_lines": 10}, # Costa Forte
		{"pos": Vector2(1080, 580), "color": Color("#a04000"), "label": "MRD-404", "roof_lines": 10}, # Meridiano Cargas
		{"pos": Vector2(950, 640), "color": Color("#1b4f72"), "label": "VMR-508", "roof_lines": 10}, # Via Marítima
		{"pos": Vector2(1080, 640), "color": Color("#78281f"), "label": "SRA-808", "roof_lines": 10}  # Serra Shipping
	]
	
	for i in range(container_specs.size()):
		var spec: Dictionary = container_specs[i]
		var c := _PortContainer.new(
			spec.pos,
			Vector2(120.0, 48.0),
			spec.color,
			spec.label,
			spec.roof_lines
		)
		c.name = "Container_%02d_%s" % [i + 1, spec.label]
		c.set_meta("_edit_group_", true)
		container_root.add_child(c)

# ==============================================================================
# 5. GUINDASTE PÓRTICO GIGANTE DO CAIS (GANTRY CRANE)
# ==============================================================================
func _build_gantry_crane() -> void:
	var crane := _PortGantryCrane.new(Vector2(850.0, 840.0))
	crane.name = "PierGantryCrane"
	crane.set_meta("_edit_group_", true)
	crane.z_index = 8
	add_child(crane)

# ==============================================================================
# 6. GUARITA DE SEGURANÇA E CANCELA (GATEHOUSE)
# ==============================================================================
func _build_gatehouse() -> void:
	var gatehouse := _PortGatehouse.new(Vector2(550.0, 320.0))
	gatehouse.name = "SecurityGatehouse"
	gatehouse.set_meta("_edit_group_", true)
	gatehouse.z_index = 6
	add_child(gatehouse)
	
	var manager = get_node_or_null("/root/TrafficLightManager")
	if manager != null and manager.has_method("register_intersection"):
		var gate_world_pos := global_position + Vector2(550.0, 320.0)
		manager.register_intersection(&"Bairro1_PortMainGate", gate_world_pos, 220.0, false)

# ==============================================================================
# 7. DETALHES INDUSTRIAIS: CABEÇOS, BOIAS, PALETES E MARCAS NO ASFALTO
# ==============================================================================
func _build_industrial_props() -> void:
	var props_root := Node2D.new()
	props_root.name = "IndustrialProps"
	props_root.z_index = 3
	add_child(props_root)
	
	# 1. Cabeços de Amarração de Navio (Bollards) ao longo da borda do cais
	for x in range(120, 1500, 110):
		var bollard := _PortBollard.new(Vector2(x, 912))
		bollard.name = "Bollard_%d" % x
		props_root.add_child(bollard)
		
	# 2. Estações de Boias de Salvamento
	for x in [220, 620, 1120, 1440]:
		var buoy := _PortLifebuoy.new(Vector2(x, 908))
		buoy.name = "Lifebuoy_%d" % x
		props_root.add_child(buoy)
		
	# 3. Pilhas de Paletes de Madeira e Caixas (Fora das ruas, encostadas em paredes)
	var pallet_positions := [
		Vector2(452, 280), Vector2(452, 330), Vector2(452, 380),
		Vector2(1188, 540), Vector2(1188, 590),
		Vector2(1248, 250), Vector2(1248, 290)
	]
	for idx in range(pallet_positions.size()):
		var pallet := _PortPalletStack.new(pallet_positions[idx])
		pallet.name = "PalletStack_%02d" % (idx + 1)
		props_root.add_child(pallet)

# ==============================================================================
# 8. ILUMINAÇÃO INDUSTRIAL (TORRES DE REFLETORES E POSTES)
# ==============================================================================
func _build_lighting() -> void:
	var light_root := Node2D.new()
	light_root.name = "PortLighting"
	light_root.z_index = 7
	add_child(light_root)
	
	# Torres de Refletores de Alta Potência (Quatro cantos estratégicos do pátio)
	var tower_positions := [
		Vector2(90, 200),   # Noroeste
		Vector2(1510, 200), # Nordeste
		Vector2(90, 740),   # Sudoeste (ilumina área de entrega)
		Vector2(1510, 740), # Sudeste (ilumina cais leste)
		Vector2(570, 740)   # Central Sul (ilumina cais e contêineres)
	]
	for i in range(tower_positions.size()):
		var tower := _PortFloodlightTower.new(tower_positions[i])
		tower.name = "FloodlightTower_%02d" % (i + 1)
		tower.set_meta("_edit_group_", true)
		light_root.add_child(tower)
		
	# Postes de Luz ao longo da calçada norte
	for x in [240, 420, 720, 980, 1220, 1400]:
		var lamp := _PortStreetLamp.new(Vector2(x, 32))
		lamp.name = "StreetLampNorth_%d" % x
		lamp.set_meta("_edit_group_", true)
		light_root.add_child(lamp)

# ==============================================================================
# 9. MARCADORES AUTORAIS DA MISSÃO (MARKER2D COM NOMES E GRUPOS EXATOS)
# ==============================================================================
func _build_mission_markers() -> void:
	var markers_root := Node2D.new()
	markers_root.name = "MissionMarkers"
	markers_root.z_index = 12
	add_child(markers_root)
	
	var marker_defs := [
		{
			"id": &"campaign_port_target_spawn",
			"node_name": "campaign_port_target_spawn",
			"pos": TARGET_SPAWN_POS,
			"rot": 0.0, # Apontado para o leste (saída da rampa)
			"color": Color("#f1c40f") # Amarelo Alvo
		},
		{
			"id": &"campaign_port_delivery",
			"node_name": "campaign_port_delivery",
			"pos": DELIVERY_POS,
			"rot": -PI * 0.5, # Apontado para o norte (estacionamento de ré/frente)
			"color": Color("#2ecc71") # Verde Entrega
		},
		{
			"id": &"campaign_trap_roadblock_a",
			"node_name": "campaign_trap_roadblock_a",
			"pos": ROADBLOCK_A_POS,
			"rot": PI * 0.5, # Bloqueio vertical fechando a garganta do portão
			"color": Color("#e74c3c") # Vermelho Armadilha A
		},
		{
			"id": &"campaign_trap_roadblock_b",
			"node_name": "campaign_trap_roadblock_b",
			"pos": ROADBLOCK_B_POS,
			"rot": 0.0, # Bloqueio horizontal fechando a passagem leste
			"color": Color("#e67e22") # Laranja Armadilha B
		},
		{
			"id": &"campaign_port_police_spawn_a",
			"node_name": "campaign_port_police_spawn_a",
			"pos": POLICE_SPAWN_A_POS,
			"rot": 0.0, # Polícia vindo pelo oeste da avenida norte
			"color": Color("#3498db") # Azul Polícia A
		},
		{
			"id": &"campaign_port_police_spawn_b",
			"node_name": "campaign_port_police_spawn_b",
			"pos": POLICE_SPAWN_B_POS,
			"rot": PI, # Polícia vindo pelo leste da avenida norte
			"color": Color("#2980b9") # Azul Polícia B
		},
		{
			"id": &"campaign_port_escape_route",
			"node_name": "campaign_port_escape_route",
			"pos": ESCAPE_ROUTE_POS,
			"rot": 0.0, # Rota de fuga saindo para o leste
			"color": Color("#9b59b6") # Roxo Fuga
		},
		{
			"id": &"campaign_port_camera_anchor",
			"node_name": "campaign_port_camera_anchor",
			"pos": CAMERA_ANCHOR_POS,
			"rot": 0.0,
			"color": Color("#ecf0f1") # Branco Câmera
		}
	]
	
	for def: Dictionary in marker_defs:
		var marker_id: StringName = def.id
		var marker := Marker2D.new()
		marker.name = String(def.node_name)
		marker.position = def.pos
		marker.rotation = def.rot
		marker.set_meta("marker_id", marker_id)
		marker.set_meta("visual_color", def.color)
		marker.add_to_group(String(marker_id), true)
		
		# Giz / Ícone visual discreto para inspeção no editor ou testes
		var gizmo := _PortMarkerGizmo.new(def.color, String(marker_id))
		gizmo.name = "GizmoVisual"
		marker.add_child(gizmo)
		
		markers_root.add_child(marker)
		_markers[marker_id] = marker

# ==============================================================================
# 10. SUPORTE A CÂMERA STANDALONE
# ==============================================================================
func _setup_camera_anchor_support() -> void:
	var anchor := get_marker(&"campaign_port_camera_anchor")
	if anchor == null: return
	
	# Se a cena for executada de forma independente (sem player ou câmera pré-existente)
	# adiciona uma Camera2D no anchor para permitir visualização imediata do set
	if not Engine.is_editor_hint():
		var existing_cam := get_viewport().get_camera_2d()
		if existing_cam == null:
			_standalone_camera = Camera2D.new()
			_standalone_camera.name = "StandalonePortCamera"
			_standalone_camera.position = Vector2.ZERO
			_standalone_camera.zoom = Vector2(0.85, 0.85)
			_standalone_camera.enabled = true
			anchor.add_child(_standalone_camera)

# ==============================================================================
# API PÚBLICA DE CONSULTA PARA O CODEX
# ==============================================================================

## Retorna o nó Marker2D pelo seu identificador StringName
func get_marker(marker_id: StringName) -> Marker2D:
	if _markers.has(marker_id):
		return _markers[marker_id] as Marker2D
	for node in get_tree().get_nodes_in_group(String(marker_id)):
		if node is Marker2D:
			return node as Marker2D
	return null

## Retorna a posição global de um marcador pelo ID
func get_marker_position(marker_id: StringName) -> Vector2:
	var m := get_marker(marker_id)
	return m.global_position if m != null else Vector2.INF

## Retorna a rotação em radianos de um marcador
func get_marker_rotation(marker_id: StringName) -> float:
	var m := get_marker(marker_id)
	return m.global_rotation if m != null else 0.0

## Propriedades diretas de conveniência para rápida integração
var target_spawn_position: Vector2:
	get: return get_marker_position(&"campaign_port_target_spawn")

var delivery_position: Vector2:
	get: return get_marker_position(&"campaign_port_delivery")

var roadblock_a_position: Vector2:
	get: return get_marker_position(&"campaign_trap_roadblock_a")

var roadblock_b_position: Vector2:
	get: return get_marker_position(&"campaign_trap_roadblock_b")

var police_spawn_a_position: Vector2:
	get: return get_marker_position(&"campaign_port_police_spawn_a")

var police_spawn_b_position: Vector2:
	get: return get_marker_position(&"campaign_port_police_spawn_b")

var escape_route_position: Vector2:
	get: return get_marker_position(&"campaign_port_escape_route")

var camera_anchor_position: Vector2:
	get: return get_marker_position(&"campaign_port_camera_anchor")

## Dicionário de validação estrutural do set para testes automatizados
func get_validation_report() -> Dictionary:
	var missing: Array[String] = []
	var required := [
		"campaign_port_target_spawn",
		"campaign_port_delivery",
		"campaign_trap_roadblock_a",
		"campaign_trap_roadblock_b",
		"campaign_port_police_spawn_a",
		"campaign_port_police_spawn_b",
		"campaign_port_escape_route",
		"campaign_port_camera_anchor"
	]
	for req in required:
		if get_marker(StringName(req)) == null:
			missing.append(req)
	
	return {
		"is_valid": missing.is_empty(),
		"bounds": PORT_BOUNDS,
		"missing_markers": missing,
		"markers_count": _markers.size(),
		"warehouses_count": get_node("IndustrialBuildings").get_child_count() if has_node("IndustrialBuildings") else 0,
		"containers_count": get_node("ContainerStacks").get_child_count() if has_node("ContainerStacks") else 0,
		"lighting_count": get_node("PortLighting").get_child_count() if has_node("PortLighting") else 0
	}


# ==============================================================================
# SUB-CLASSES AUXILIARES DE RENDERIZAÇÃO VETORIAL NATIVA
# ==============================================================================

# --- DESENHADOR DE PISO, RUAS E CALÇADAS ---
class _PortGroundDrawer extends Node2D:
	func _draw() -> void:
		# 1. Base Geral do Pátio Portuário (Asfalto Industrial Escuro)
		draw_rect(PortMarkedCarSet.PORT_BOUNDS, Color("#1f242b"))
		
		# 2. Concreto Reforçado do Cais Sul (Y: 760 até 920)
		draw_rect(Rect2(60, 760, 1480, 160), Color("#74797c"))
		for x in range(60, 1540, 60):
			draw_line(Vector2(x, 760), Vector2(x, 920), Color("#585d60"), 1.0)
		for y in range(760, 920, 40):
			draw_line(Vector2(60, y), Vector2(1540, y), Color("#585d60"), 1.0)
			
		# Faixa de Perigo Zebrada Amarela e Preta na beirada do Cais
		var hazard_rect := Rect2(60, 912, 1480, 10)
		draw_rect(hazard_rect, Color("#d49925"))
		for hx in range(60, 1540, 24):
			draw_line(Vector2(hx, 912), Vector2(hx + 12, 922), Color("#1a1c1e"), 5.0)
			
		# Trilhos de Aço do Guindaste Pórtico
		draw_line(Vector2(60, 780), Vector2(1540, 780), Color("#3e464c"), 4.0)
		draw_line(Vector2(60, 780), Vector2(1540, 780), Color("#8a959e"), 1.5)
		draw_line(Vector2(60, 902), Vector2(1540, 902), Color("#3e464c"), 4.0)
		draw_line(Vector2(60, 902), Vector2(1540, 902), Color("#8a959e"), 1.5)
		
		# 3. Avenida Norte (Acesso ao Porto) - 164px de largura (Y: 28 até 192), centro em Y = 110.0
		# Inicia em X = -30 para garantir fusão invisível e sem degraus com Bairro1RoadNetwork
		draw_rect(Rect2(-30, 28, 1630, 164), PortMarkedCarSet.COLOR_ASPHALT)
		
		# 4. Avenidas Internas e Pátios de Carga (Mesma cor uniforme de asfalto)
		# Avenida Oeste / Entrada Principal: X: 440 até 660, Y: 180 até 760
		draw_rect(Rect2(440, 180, 220, 580), PortMarkedCarSet.COLOR_ASPHALT)
		
		# Corredor Transversal Central (conecta Avenida Oeste à Avenida Leste)
		draw_rect(Rect2(580, 370, 640, 90), PortMarkedCarSet.COLOR_ASPHALT)
		
		# Avenida Leste (Ligação do Cais com Corredor Central): X: 1140 a 1260, Y: 370 a 760
		draw_rect(Rect2(1140, 370, 120, 390), PortMarkedCarSet.COLOR_ASPHALT)
		
		# Corredor de Serviço Central (X: 850 a 930): mesma cor uniforme de asfalto
		draw_rect(Rect2(850, 240, 80, 520), PortMarkedCarSet.COLOR_ASPHALT)
		
		# Pátio de Carga e Estacionamento da Oficina Naval (X: 1140 a 1460, Y: 180 a 370)
		var workshop_apron := Rect2(1140, 180, 320, 190)
		draw_rect(workshop_apron, Color("#2c343d"))
		draw_rect(workshop_apron, Color("#1c2228"), false, 2.0)
		
		# Vagas de carga/descarga demarcadas na oficina:
		for bay_x in range(1160, 1280, 55):
			var bay_rect := Rect2(bay_x, 195, 45, 55)
			draw_rect(bay_rect, Color(0.9, 0.9, 0.9, 0.10))
			draw_rect(bay_rect, PortMarkedCarSet.COLOR_ZEBRA_WHITE, false, 1.5)
			
		# Mureta / Guia de proteção amarela zebrada antes da cerca norte (wheel stop):
		draw_line(Vector2(1140, 186), Vector2(1460, 186), PortMarkedCarSet.COLOR_HAZARD_YELLOW, 3.5)
		for zx in range(1140, 1460, 16):
			draw_line(Vector2(zx, 186), Vector2(zx + 8, 186), PortMarkedCarSet.COLOR_HAZARD_BLACK, 3.5)
			
		# ======================================================================
		# CALÇADAS E MEIO-FIO (SEM VÁCUO, SEM SOBREPOSIÇÃO, FECHAMENTO PERFEITO)
		# ======================================================================
		# Calçada Norte da Avenida (Y: 0 até 28) - Alinhamento milimétrico com Bairro 1
		draw_rect(Rect2(-30, 0, 1630, 28), PortMarkedCarSet.COLOR_SIDEWALK)
		draw_line(Vector2(-30, 28), Vector2(1600, 28), PortMarkedCarSet.COLOR_CURB, 3.0)
		
		# Calçada Sul - Trecho Oeste (X: -30 até 440, Y: 192 até 224) - Largura 32px
		draw_rect(Rect2(-30, 192, 470, 32), PortMarkedCarSet.COLOR_SIDEWALK)
		draw_line(Vector2(-30, 192), Vector2(420, 192), PortMarkedCarSet.COLOR_CURB, 3.0)
		# Meio-fio curvo arredondado na esquina oeste da entrada
		draw_arc(Vector2(420, 212), 20.0, -PI * 0.5, 0.0, 10, PortMarkedCarSet.COLOR_CURB, 3.0)
		draw_line(Vector2(440, 212), Vector2(440, 380), PortMarkedCarSet.COLOR_CURB, 3.0)
		
		# Calçada Sul - Trecho Leste (X: 660 até 1600, Y: 192 até 224)
		draw_rect(Rect2(660, 192, 940, 32), PortMarkedCarSet.COLOR_SIDEWALK)
		draw_line(Vector2(680, 192), Vector2(1600, 192), PortMarkedCarSet.COLOR_CURB, 3.0)
		# Meio-fio curvo arredondado na esquina leste da entrada
		draw_arc(Vector2(680, 212), 20.0, -PI, -PI * 0.5, 10, PortMarkedCarSet.COLOR_CURB, 3.0)
		draw_line(Vector2(660, 212), Vector2(660, 380), PortMarkedCarSet.COLOR_CURB, 3.0)
		
		# Ilha Central de Concreto da Guarita (posicionada internamente no pátio em Y: 280 a 360)
		# Deixa a Avenida Norte (Y: 28 a 192) totalmente livre e desobstruída
		var island_rect := Rect2(530, 280, 40, 80)
		draw_rect(island_rect, PortMarkedCarSet.COLOR_SIDEWALK)
		draw_line(Vector2(530, 280), Vector2(530, 360), PortMarkedCarSet.COLOR_CURB, 2.5)
		draw_line(Vector2(570, 280), Vector2(570, 360), PortMarkedCarSet.COLOR_CURB, 2.5)
		# Pontas arredondadas (bullnose) da ilha da guarita
		draw_arc(Vector2(550, 280), 20.0, -PI, 0.0, 10, PortMarkedCarSet.COLOR_CURB, 2.5)
		draw_arc(Vector2(550, 360), 20.0, 0.0, PI, 10, PortMarkedCarSet.COLOR_CURB, 2.5)
		
		# Faixa de Pedestre transversal na calçada sul da avenida conectando os lados oeste e leste
		for cw_x in range(448, 652, 16):
			draw_rect(Rect2(cw_x, 198, 10, 20), PortMarkedCarSet.COLOR_ZEBRA_WHITE)
			
		# ======================================================================
		# FAIXAS DE TRÂNSITO CONTÍNUAS (SEM VÁCUO, COM ARCOS DE CURVA SUAVES)
		# ======================================================================
		# 1. Faixa Central da Avenida Norte (em Y = 110.0, contínua com Bairro 1)
		for ax in range(-20, 1580, 45):
			if ax >= 420 and ax <= 660:
				continue # Abertura do entroncamento
			draw_line(Vector2(ax, 110), Vector2(ax + 25, 110), PortMarkedCarSet.COLOR_LANE_YELLOW, 3.0)
			
		# 2. Faixa da Pista de Entrada (Oeste da Guarita): desce de (485, 230) até (485, 360)
		for ay in range(230, 360, 36):
			draw_line(Vector2(485, ay), Vector2(485, ay + 18), PortMarkedCarSet.COLOR_LANE_YELLOW, 2.5)
			
		# 3. Faixa da Pista de Saída (Leste da Guarita): sobe de (615, 360) até (615, 230)
		for ay in range(230, 360, 36):
			draw_line(Vector2(615, ay), Vector2(615, ay + 18), PortMarkedCarSet.COLOR_LANE_YELLOW, 2.5)
			
		# 4. Avenida Central (descendo em direção ao cais): X = 550, Y = 370 até 740
		for ay in range(370, 740, 38):
			draw_line(Vector2(550, ay), Vector2(550, ay + 20), PortMarkedCarSet.COLOR_LANE_YELLOW, 2.5)
			
		# 5. Curva Suave Oeste (conecta descida da entrada ao Corredor Transversal Central):
		var arc_w_center := Vector2(610, 355)
		for step in range(0, 3):
			var a1 := PI * 0.5 + float(step) * (PI * 0.5 / 3.0)
			var a2 := a1 + (PI * 0.5 / 5.0)
			draw_arc(arc_w_center, 60.0, a1, a2, 6, PortMarkedCarSet.COLOR_LANE_YELLOW, 2.5)
			
		# 6. Corredor Transversal Central (sem corte, contínuo até X = 1140):
		for cx in range(610, 1140, 38):
			draw_line(Vector2(cx, 415), Vector2(cx + 20, 415), PortMarkedCarSet.COLOR_LANE_YELLOW, 2.5)
			
		# 7. Curva Suave Leste (conecta Corredor Central à Avenida Leste SEM VÁCUO):
		var arc_e_center := Vector2(1140, 475)
		for step in range(0, 3):
			var a1 := -PI * 0.5 + float(step) * (PI * 0.5 / 3.0)
			var a2 := a1 + (PI * 0.5 / 5.0)
			draw_arc(arc_e_center, 60.0, a1, a2, 6, PortMarkedCarSet.COLOR_LANE_YELLOW, 2.5)
			
		# 8. Avenida Leste (descendo contínua até o Cais):
		for ey in range(475, 740, 38):
			draw_line(Vector2(1200, ey), Vector2(1200, ey + 20), PortMarkedCarSet.COLOR_LANE_YELLOW, 2.5)
			
		# 5. Pátio de Entrega do Carro Roubado (Delivery Zone)
		var deliv_box := Rect2(120, 660, 100, 100)
		draw_rect(deliv_box, Color(0.18, 0.80, 0.44, 0.20)) # Fundo verde translúcido
		draw_rect(deliv_box, Color("#2ecc71"), false, 3.5) # Borda verde viva
		
		# Cantoneiras em L nas quatro quinas da vaga de entrega
		var c_size := 16.0
		# Noroeste
		draw_line(deliv_box.position, deliv_box.position + Vector2(c_size, 0), Color("#f1c40f"), 4.0)
		draw_line(deliv_box.position, deliv_box.position + Vector2(0, c_size), Color("#f1c40f"), 4.0)
		# Nordeste
		var ne := deliv_box.position + Vector2(deliv_box.size.x, 0)
		draw_line(ne, ne + Vector2(-c_size, 0), Color("#f1c40f"), 4.0)
		draw_line(ne, ne + Vector2(0, c_size), Color("#f1c40f"), 4.0)
		# Sudoeste
		var sw := deliv_box.position + Vector2(0, deliv_box.size.y)
		draw_line(sw, sw + Vector2(c_size, 0), Color("#f1c40f"), 4.0)
		draw_line(sw, sw + Vector2(0, -c_size), Color("#f1c40f"), 4.0)
		# Sudeste
		draw_line(deliv_box.end, deliv_box.end + Vector2(-c_size, 0), Color("#f1c40f"), 4.0)
		draw_line(deliv_box.end, deliv_box.end + Vector2(0, -c_size), Color("#f1c40f"), 4.0)
		
		# Marcas de frenagem no asfalto (sem círculos pretos redondos de óleo)
		draw_line(Vector2(515, 360), Vector2(515, 410), Color(0.05, 0.05, 0.06, 0.35), 3.0)
		draw_line(Vector2(545, 360), Vector2(545, 410), Color(0.05, 0.05, 0.06, 0.35), 3.0)

# --- DESENHADOR DA ÁGUA DO MAR COM ESPUMA ---
class _PortWaterDrawer extends Node2D:
	var _parent_set: PortMarkedCarSet
	func _init(set_ref: PortMarkedCarSet = null) -> void:
		_parent_set = set_ref
		
	func _draw() -> void:
		var water_rect := Rect2(0, 924, 1600, 160)
		draw_rect(water_rect, Color("#14293a"))
		
		# Espuma e ondulações do mar encostando no cais
		var phase: float = _parent_set._wave_time if _parent_set else 0.0
		var points := PackedVector2Array()
		points.append(Vector2(0, 924))
		for x in range(0, 1620, 20):
			var wave_y = 925.0 + sin(x * 0.02 + phase) * 2.5
			points.append(Vector2(x, wave_y))
		points.append(Vector2(1600, 924))
		
		draw_polyline(points, Color(0.50, 0.72, 0.85, 0.65), 2.5)

# --- CERCA DE SEGURANÇA COMPOSTA ---
class _PortFenceDrawer extends Node2D:
	@export_storage var _a: Vector2
	@export_storage var _b: Vector2
	func _init(start: Vector2 = Vector2.ZERO, end_pt: Vector2 = Vector2.ZERO) -> void:
		_a = start
		_b = end_pt
		
	func _draw() -> void:
		# Linha principal de aço
		draw_line(_a, _b, Color("#4f5860"), 3.5)
		draw_line(_a, _b, Color("#8b969e"), 1.2)
		
		# Mourões de fixação de concreto a cada 35px
		var dist = _a.distance_to(_b)
		var dir = (_b - _a).normalized()
		var count = int(dist / 35.0)
		for i in range(count + 1):
			var pt = _a + dir * (i * 35.0)
			draw_circle(pt, 3.5, Color("#262e33"))
			draw_circle(pt, 2.0, Color("#a8b3bc"))

# --- GALPÃO INDUSTRIAL 2.5D ---
class _PortWarehouse extends StaticBody2D:
	@export_storage var _rect: Rect2
	@export_storage var _label: String
	@export_storage var _roof_color: Color
	@export_storage var _edge_color: Color
	@export_storage var _front_color: Color
	@export_storage var _door_color: Color
	@export_storage var _has_ramp: bool
	
	func _init(rect: Rect2 = Rect2(), label: String = "", roof_col: Color = Color.WHITE, edge_col: Color = Color.BLACK, front_col: Color = Color.GRAY, door_col: Color = Color.DARK_GRAY, has_ramp: bool = false) -> void:
		_rect = rect
		_label = label
		_roof_color = roof_col
		_edge_color = edge_col
		_front_color = front_col
		_door_color = door_col
		_has_ramp = has_ramp
		collision_layer = 1
		collision_mask = 0
		
	func _ready() -> void:
		# Colisor Sólido cobrindo todo o footprint do galpão
		if not has_node("Collision"):
			var col := CollisionShape2D.new()
			col.name = "Collision"
			var shape := RectangleShape2D.new()
			shape.size = _rect.size
			col.shape = shape
			col.position = _rect.get_center()
			add_child(col)
		queue_redraw()
		
	func _draw() -> void:
		# Sombra projetada do galpão (Drop Shadow)
		draw_rect(Rect2(_rect.position + Vector2(10, 12), _rect.size), Color(0.04, 0.05, 0.06, 0.38))
		
		# Fachada Frontal 2.5D (Efeito de extrusão para baixo)
		var facade_h := 32.0
		var facade_rect := Rect2(_rect.position.x, _rect.end.y - facade_h, _rect.size.x, facade_h)
		draw_rect(facade_rect, _front_color)
		draw_rect(facade_rect, _edge_color, false, 2.0)
		
		# Portões Basculantes de Carga (Roll-up Cargo Doors)
		var num_doors := 3 if _rect.size.x > 250 else 2
		var door_w := _rect.size.x / (num_doors * 1.8)
		var spacing := _rect.size.x / num_doors
		for d in range(num_doors):
			var dx = _rect.position.x + 24.0 + d * spacing
			var door_rect := Rect2(dx, facade_rect.position.y + 4, door_w, facade_h - 4)
			draw_rect(door_rect, _door_color)
			draw_rect(door_rect, _edge_color, false, 1.5)
			# Frisos horizontais metálicos do portão
			for dy in range(int(door_rect.position.y + 4), int(door_rect.end.y), 4):
				draw_line(Vector2(door_rect.position.x, dy), Vector2(door_rect.end.x, dy), Color(0.1, 0.1, 0.1, 0.4), 1.0)
				
		# Telhado Principal Metálico
		var roof_rect := Rect2(_rect.position, Vector2(_rect.size.x, _rect.size.y - facade_h))
		draw_rect(roof_rect, _roof_color)
		draw_rect(roof_rect, _edge_color, false, 3.0)
		
		# Linhas de Ondulação Metálica do Telhado
		for rx in range(int(roof_rect.position.x + 15), int(roof_rect.end.x), 15):
			draw_line(Vector2(rx, roof_rect.position.y), Vector2(rx, roof_rect.end.y), _roof_color.darkened(0.20), 1.0)
			
		# Clarabóias de Vidro Industriais no Teto
		var num_skylights := 3
		for s in range(num_skylights):
			var sx = roof_rect.position.x + 45.0 + s * (roof_rect.size.x / 3.2)
			var sy = roof_rect.get_center().y - 18.0
			var s_rect := Rect2(sx, sy, 36.0, 26.0)
			draw_rect(s_rect, Color("#5dade2"))
			draw_rect(s_rect, _edge_color, false, 1.5)
			draw_line(Vector2(s_rect.position.x + 4, s_rect.end.y - 4), Vector2(s_rect.end.x - 4, s_rect.position.y + 4), Color(1, 1, 1, 0.5), 1.5)
			
		# Exaustores / Condensadores Industriais no Teto
		var vent_center := roof_rect.position + Vector2(roof_rect.size.x - 45, 35)
		draw_circle(vent_center, 16.0, Color("#2c3e50"))
		draw_circle(vent_center, 12.0, Color("#7f8c8d"))
		draw_circle(vent_center, 6.0, Color("#1a252f"))
		
		# Rampa de Carga Sul (se aplicável)
		if _has_ramp:
			var ramp_rect := Rect2(_rect.position.x + 20, _rect.end.y, _rect.size.x - 40, 24)
			draw_rect(ramp_rect, Color("#616a6b"))
			draw_rect(ramp_rect, Color("#343a40"), false, 1.5)
			# Faixa zebrada amarela de atenção
			for zx in range(int(ramp_rect.position.x), int(ramp_rect.end.x), 16):
				draw_line(Vector2(zx, ramp_rect.end.y - 4), Vector2(zx + 8, ramp_rect.end.y), Color("#f39c12"), 2.0)

# --- CONTÊINER INTERMODAL 2.5D COM COLISÃO ---
class _PortContainer extends StaticBody2D:
	@export_storage var _pos: Vector2
	@export_storage var _size: Vector2
	@export_storage var _color: Color
	@export_storage var _label: String
	@export_storage var _lines: int
	
	func _init(pos: Vector2 = Vector2.ZERO, size: Vector2 = Vector2(80, 32), color: Color = Color.GRAY, label: String = "", lines: int = 10) -> void:
		_pos = pos
		_size = size
		_color = color
		_label = label
		_lines = lines
		collision_layer = 1
		collision_mask = 0
		
	func _ready() -> void:
		if not has_node("Collision"):
			var col := CollisionShape2D.new()
			col.name = "Collision"
			var shape := RectangleShape2D.new()
			shape.size = _size
			col.shape = shape
			col.position = _pos + _size * 0.5
			add_child(col)
		queue_redraw()
		
	func _draw() -> void:
		# Sombra projetada
		draw_rect(Rect2(_pos + Vector2(6, 6), _size), Color(0.04, 0.05, 0.06, 0.35))
		
		# Extrusão 2.5D na borda inferior
		var ext_h := 10.0
		var ext_rect := Rect2(_pos.x, _pos.y + _size.y - ext_h, _size.x, ext_h)
		draw_rect(ext_rect, _color.darkened(0.40))
		draw_rect(ext_rect, Color("#111315"), false, 1.2)
		
		# Teto principal do contêiner
		var roof_rect := Rect2(_pos.x, _pos.y, _size.x, _size.y - ext_h)
		draw_rect(roof_rect, _color)
		draw_rect(roof_rect, Color("#111315"), false, 2.0)
		
		# Frisos de corrugação metálica do teto
		var step := roof_rect.size.x / (_lines + 1)
		for i in range(1, _lines + 1):
			var lx = roof_rect.position.x + i * step
			draw_line(Vector2(lx, roof_rect.position.y + 2), Vector2(lx, roof_rect.end.y - 2), _color.darkened(0.25), 2.0)
			
		# Castings de Canto (Corner Castings em ferro fundido preto)
		var cw := 7.0
		var ch := 6.0
		var corners := [
			roof_rect.position,
			Vector2(roof_rect.end.x - cw, roof_rect.position.y),
			Vector2(roof_rect.position.x, roof_rect.end.y - ch),
			Vector2(roof_rect.end.x - cw, roof_rect.end.y - ch)
		]
		for c in corners:
			draw_rect(Rect2(c, Vector2(cw, ch)), Color("#1b1e23"))
			draw_rect(Rect2(c + Vector2(1.5, 1.5), Vector2(cw - 3, ch - 3)), Color("#343a40"))

# --- GUINDASTE PÓRTICO GIGANTE DO CAIS ---
class _PortGantryCrane extends Node2D:
	@export_storage var _base_pos: Vector2
	
	func _init(base_pos: Vector2 = Vector2.ZERO) -> void:
		_base_pos = base_pos
		
	func _ready() -> void:
		# Estrutura sólida completa, sem túnel no miolo do guindaste.
		if has_node("CraneStructure"):
			queue_redraw()
			return
		var structure := Node2D.new()
		structure.name = "CraneStructure"
		add_child(structure)
		# Pernas: colisão mais larga para fechar o envelope do chassi.
		_add_leg_collider(structure, Vector2(-100, -60), "Leg_NW")
		_add_leg_collider(structure, Vector2(100, -60), "Leg_NE")
		_add_leg_collider(structure, Vector2(-100, 60), "Leg_SW")
		_add_leg_collider(structure, Vector2(100, 60), "Leg_SE")
		# Estruturas intermediárias: impedem atravessar por baixo do tablado e da torre.
		_add_rect_collider(structure, Rect2(-36, -32, 72, 204), "CraneCentralRiser")
		_add_rect_collider(structure, Rect2(-98, -52, 24, 172), "CraneLeftBay")
		_add_rect_collider(structure, Rect2(74, -52, 24, 172), "CraneRightBay")
		_add_rect_collider(structure, Rect2(-20, 172, 40, 42), "CraneDeckBase")
		queue_redraw()
		
	func _add_leg_collider(parent: Node, offset: Vector2, leg_name: String) -> void:
		var leg_body := StaticBody2D.new()
		leg_body.name = leg_name
		leg_body.collision_layer = 1
		leg_body.collision_mask = 0
		leg_body.position = _base_pos + offset
		
		var col := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(34.0, 42.0)
		col.shape = shape
		leg_body.add_child(col)
		parent.add_child(leg_body)
		
	func _add_rect_collider(parent: Node, bounds: Rect2, name: String) -> void:
		var body := StaticBody2D.new()
		body.name = name
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = _base_pos + bounds.position
		
		var col := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = bounds.size
		col.shape = shape
		col.position = bounds.size * 0.5
		body.add_child(col)
		parent.add_child(body)
		
	func _draw() -> void:
		var bp := _base_pos
		# Sombra diagonal do guindaste no cais e na água
		draw_line(bp + Vector2(-90, 60), bp + Vector2(110, 160), Color(0.04, 0.05, 0.06, 0.30), 18.0)
		draw_line(bp + Vector2(0, 0), bp + Vector2(0, 220), Color(0.04, 0.05, 0.06, 0.25), 14.0)
		
		# 1. Vigas Principais do Pórtico (Trecho Leste-Oeste em Amarelo Segurança)
		var frame_col := Color("#e5a01d")
		var shadow_frame := Color("#b57c12")
		
		# Travesseiros transversais
		draw_rect(Rect2(bp + Vector2(-115, -68), Vector2(30, 28)), Color("#2c3e50")) # Rodeiros
		draw_rect(Rect2(bp + Vector2(85, -68), Vector2(30, 28)), Color("#2c3e50"))
		draw_rect(Rect2(bp + Vector2(-115, 52), Vector2(30, 28)), Color("#2c3e50"))
		draw_rect(Rect2(bp + Vector2(85, 52), Vector2(30, 28)), Color("#2c3e50"))
		
		# Pernas em Treliça (A-Frames)
		draw_line(bp + Vector2(-100, -50), bp + Vector2(-40, 0), frame_col, 10.0)
		draw_line(bp + Vector2(100, -50), bp + Vector2(40, 0), frame_col, 10.0)
		draw_line(bp + Vector2(-100, 50), bp + Vector2(-40, 0), frame_col, 10.0)
		draw_line(bp + Vector2(100, 50), bp + Vector2(40, 0), frame_col, 10.0)
		
		# Travessas de reforço em X
		draw_line(bp + Vector2(-80, -40), bp + Vector2(-80, 40), shadow_frame, 4.0)
		draw_line(bp + Vector2(80, -40), bp + Vector2(80, 40), shadow_frame, 4.0)
		draw_line(bp + Vector2(-90, -40), bp + Vector2(90, 40), shadow_frame, 3.0)
		draw_line(bp + Vector2(-90, 40), bp + Vector2(90, -40), shadow_frame, 3.0)
		
		# 2. Ponte Superior e Sala de Máquinas do Guindaste
		var bridge_rect := Rect2(bp + Vector2(-60, -25), Vector2(120, 50))
		draw_rect(bridge_rect, frame_col)
		draw_rect(bridge_rect, Color("#8c5e0d"), false, 3.0)
		
		# Cabine do Operador envidraçada
		var cab_rect := Rect2(bp + Vector2(-20, 10), Vector2(40, 30))
		draw_rect(cab_rect, Color("#34495e"))
		draw_rect(cab_rect.grow(-3), Color("#5dade2")) # Vidros azuis
		
		# 3. Lança Metálica (Boom) avançando sobre a água do mar (ao Sul)
		var boom_start := bp + Vector2(0, 25)
		var boom_end := bp + Vector2(0, 190)
		draw_line(boom_start + Vector2(-8, 0), boom_end + Vector2(-8, 0), frame_col, 5.0)
		draw_line(boom_start + Vector2(8, 0), boom_end + Vector2(8, 0), frame_col, 5.0)
		for by in range(int(boom_start.y + 15), int(boom_end.y), 20):
			draw_line(Vector2(boom_start.x - 8, by), Vector2(boom_start.x + 8, by + 10), shadow_frame, 2.5)
			
		# Carro de Carga (Trolley) e Spreader de Contêiner suspenso
		var trolley_pos := bp + Vector2(0, 130)
		draw_rect(Rect2(trolley_pos - Vector2(16, 12), Vector2(32, 24)), Color("#c0392b"))
		# Cabos de aço
		draw_line(trolley_pos, trolley_pos + Vector2(0, 20), Color("#7f8c8d"), 1.5)
		# Spreader amarelo
		draw_rect(Rect2(trolley_pos + Vector2(-22, 20), Vector2(44, 12)), Color("#f1c40f"))

# --- GUARITA DE SEGURANÇA E CANCELA ---
class _PortGatehouse extends StaticBody2D:
	func _init(pos: Vector2 = Vector2.ZERO) -> void:
		position = pos
		collision_layer = 1
		collision_mask = 0
		
	func _ready() -> void:
		if not has_node("Collision"):
			var col := CollisionShape2D.new()
			col.name = "Collision"
			var shape := RectangleShape2D.new()
			shape.size = Vector2(44.0, 36.0)
			col.shape = shape
			col.position = Vector2.ZERO
			add_child(col)
		queue_redraw()
		
		var manager = get_node_or_null("/root/TrafficLightManager")
		if manager != null and manager.has_signal("phase_changed"):
			manager.phase_changed.connect(_on_traffic_phase_changed)

	func _on_traffic_phase_changed(_ew: int, _ns: int) -> void:
		queue_redraw()
		
	func _draw() -> void:
		# Sincronização com TrafficLightManager para Bairro1_PortMainGate (eixo NS)
		var is_gate_green := false
		var manager = get_node_or_null("/root/TrafficLightManager")
		if manager != null and manager.has_method("is_green_for"):
			is_gate_green = manager.is_green_for("NS")

		var red_active := Color("#ff3b30")
		var red_dim := Color("#ff3b30").darkened(0.72)
		var green_active := Color("#34d058")
		var green_dim := Color("#34d058").darkened(0.72)

		var cur_red := red_dim if is_gate_green else red_active
		var cur_green := green_active if is_gate_green else green_dim

		# Ilha de concreto de segurança (Curb Island interna)
		var island := Rect2(Vector2(-28, -36), Vector2(56, 72))
		draw_rect(island, Color("#7f8c8d"))
		draw_rect(island, Color("#566573"), false, 2.0)
		
		# Cabine da Guarita (Branca/Azul corporativo portuário)
		var booth := Rect2(Vector2(-20, -16), Vector2(40, 32))
		draw_rect(booth, Color("#ecf0f1"))
		draw_rect(booth, Color("#2c3e50"), false, 2.5)
		
		# Janelas de Vidro Fumê nos 4 lados
		draw_rect(Rect2(booth.position + Vector2(4, 4), Vector2(booth.size.x - 8, 8)), Color("#1f618d"))
		draw_rect(Rect2(booth.position + Vector2(4, booth.size.y - 12), Vector2(booth.size.x - 8, 8)), Color("#1f618d"))
		
		# Antena de Rádio e Giroflex no teto
		draw_circle(Vector2.ZERO, 4.0, Color("#e67e22"))
		draw_line(Vector2.ZERO, Vector2(0, -14), Color("#95a5a6"), 2.0)
		
		# Haste da Cancela (Boom Barrier zebra vermelha e branca)
		# Posicionada no lado oeste da cabine: ergue-se no verde e fecha no vermelho
		var barrier_pivot := Vector2(-26, 0)
		draw_circle(barrier_pivot, 5.0, Color("#e74c3c"))
		var barrier_vec := Vector2(-15, -58) if is_gate_green else Vector2(-60, 0)
		draw_line(barrier_pivot, barrier_pivot + barrier_vec, Color("#e74c3c"), 4.0)
		for zx in range(10, 60, 14):
			var p1 := barrier_pivot + barrier_vec * (float(zx) / 60.0)
			var p2 := barrier_pivot + barrier_vec * (float(zx + 6) / 60.0)
			draw_line(p1, p2, Color("#ecf0f1"), 4.0)
			
		# Sinaleira / Semáforo de Cancela da Portaria (Instalado na própria ilha de concreto)
		# Entrada (Oeste)
		var sig_in := Vector2(-24, -26)
		draw_line(Vector2(-24, -4), sig_in, Color("#2c3e50"), 2.5)
		draw_rect(Rect2(sig_in - Vector2(4, 12), Vector2(8, 14)), Color("#1b2631"))
		draw_rect(Rect2(sig_in - Vector2(4, 12), Vector2(8, 14)), Color("#566573"), false, 1.0)
		draw_circle(sig_in - Vector2(0, 8), 2.5, cur_red) # Luz Vermelha (Pare)
		draw_circle(sig_in - Vector2(0, 2), 2.5, cur_green) # Luz Verde (Siga)
		
		# Saída (Leste)
		var sig_out := Vector2(24, 26)
		draw_line(Vector2(24, 4), sig_out, Color("#2c3e50"), 2.5)
		draw_rect(Rect2(sig_out - Vector2(4, 2), Vector2(8, 14)), Color("#1b2631"))
		draw_rect(Rect2(sig_out - Vector2(4, 2), Vector2(8, 14)), Color("#566573"), false, 1.0)
		draw_circle(sig_out + Vector2(0, 2), 2.5, cur_red) # Luz Vermelha
		draw_circle(sig_out + Vector2(0, 8), 2.5, cur_green) # Luz Verde
		
		# Linha de Retenção (Faixa de Parada / Stop Line) horizontal única no asfalto da entrada
		draw_line(Vector2(-85, -28), Vector2(-26, -28), Color("#dadcd6"), 4.0)

# --- CABEÇO DE AMARRAÇÃO (BOLLARD) ---
class _PortBollard extends Node2D:
	func _init(pos: Vector2 = Vector2.ZERO) -> void:
		position = pos
	func _draw() -> void:
		draw_circle(Vector2(2, 2), 6.0, Color(0.05, 0.05, 0.05, 0.35)) # Sombra
		draw_circle(Vector2.ZERO, 5.5, Color("#1c2833")) # Base de ferro
		draw_circle(Vector2.ZERO, 3.5, Color("#566573"))
		draw_circle(Vector2(0, -1), 2.0, Color("#85929e"))

# --- BOIA DE RESGATE ---
class _PortLifebuoy extends Node2D:
	func _init(pos: Vector2 = Vector2.ZERO) -> void:
		position = pos
	func _draw() -> void:
		# Poste de suporte
		draw_line(Vector2.ZERO, Vector2(0, -10), Color("#7f8c8d"), 2.5)
		# Boia circular vermelha e branca
		var center := Vector2(0, -12)
		draw_circle(center, 7.0, Color("#e74c3c"))
		draw_circle(center, 4.0, Color("#1f242b"))
		# Faixas brancas
		draw_line(center + Vector2(-7, 0), center + Vector2(-4, 0), Color.WHITE, 2.0)
		draw_line(center + Vector2(4, 0), center + Vector2(7, 0), Color.WHITE, 2.0)

# --- PILHA DE PALETES E CAIXAS ---
class _PortPalletStack extends Node2D:
	func _init(pos: Vector2 = Vector2.ZERO) -> void:
		position = pos
	func _draw() -> void:
		draw_rect(Rect2(Vector2(-14, -10), Vector2(28, 20)), Color("#b9770e"))
		draw_rect(Rect2(Vector2(-14, -10), Vector2(28, 20)), Color("#7e5109"), false, 1.5)
		draw_line(Vector2(-14, 0), Vector2(14, 0), Color("#7e5109"), 1.0)
		draw_line(Vector2(0, -10), Vector2(0, 10), Color("#7e5109"), 1.0)

# --- TORRE DE REFLETORES DE ALTA POTÊNCIA COM POINTLIGHT2D ---
class _PortFloodlightTower extends StaticBody2D:
	@export_storage var _pos: Vector2
	var _light: PointLight2D
	
	func _init(pos: Vector2 = Vector2.ZERO) -> void:
		_pos = pos
		collision_layer = 1
		collision_mask = 0
		
	func _ready() -> void:
		# Colisor da base da torre
		if not has_node("Collision"):
			var col := CollisionShape2D.new()
			col.name = "Collision"
			var shape := CircleShape2D.new()
			shape.radius = 7.0
			col.shape = shape
			col.position = _pos
			add_child(col)
		if has_node("FloodLight"):
			_light = get_node("FloodLight") as PointLight2D
			_bind_day_night()
			queue_redraw()
			return
		
		# Iluminação PointLight2D Halógena Industrial
		_light = PointLight2D.new()
		_light.name = "FloodLight"
		_light.color = Color(1.0, 0.92, 0.75, 1.0) # Luz quente âmbar/halógena
		_light.energy = 1.25
		_light.position = _pos
		
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.40, 1.0])
		grad.colors = PackedColorArray([
			Color(1.0, 0.95, 0.80, 1.0),
			Color(1.0, 0.88, 0.65, 0.60),
			Color(1.0, 0.85, 0.50, 0.0)
		])
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.width = 380
		tex.height = 380
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		_light.texture = tex
		_light.visible = true
		add_child(_light)
		
		# Conecta com day_night_manager caso presente na árvore
		_bind_day_night()
		
		queue_redraw()

	func _bind_day_night() -> void:
		if Engine.is_editor_hint():
			return
		var dnm = get_tree().get_first_node_in_group("day_night_manager")
		if dnm and dnm.has_signal("time_changed") and not dnm.time_changed.is_connected(_on_time_changed):
			dnm.time_changed.connect(_on_time_changed)

	func _on_time_changed(is_night: bool) -> void:
		if _light:
			_light.visible = is_night
		
	func _draw() -> void:
		# Sombra da torre
		draw_circle(_pos + Vector2(3, 3), 9.0, Color(0.05, 0.05, 0.05, 0.35))
		
		# Base de concreto de fixação
		draw_rect(Rect2(_pos - Vector2(8, 8), Vector2(16, 16)), Color("#566573"))
		draw_rect(Rect2(_pos - Vector2(8, 8), Vector2(16, 16)), Color("#2c3e50"), false, 1.5)
		
		# Poste treliçado central
		draw_circle(_pos, 5.5, Color("#1b2631"))
		
		# Cruzeta de refletores com 4 focos
		draw_line(_pos - Vector2(14, 0), _pos + Vector2(14, 0), Color("#7f8c8d"), 3.0)
		for lx in [-12, -4, 4, 12]:
			draw_circle(_pos + Vector2(lx, 0), 2.5, Color("#f9e79f"))

# --- POSTE DE LUZ DA CALÇADA COM POINTLIGHT2D ---
class _PortStreetLamp extends StaticBody2D:
	@export_storage var _pos: Vector2
	var _light: PointLight2D
	
	func _init(pos: Vector2 = Vector2.ZERO) -> void:
		_pos = pos
		collision_layer = 1
		collision_mask = 0
		
	func _ready() -> void:
		if not has_node("Collision"):
			var col := CollisionShape2D.new()
			col.name = "Collision"
			var shape := CircleShape2D.new()
			shape.radius = 5.0
			col.shape = shape
			col.position = _pos
			add_child(col)
		if has_node("LampLight"):
			_light = get_node("LampLight") as PointLight2D
			queue_redraw()
			return
		
		_light = PointLight2D.new()
		_light.name = "LampLight"
		_light.color = Color(1.0, 0.90, 0.70, 1.0)
		_light.energy = 0.95
		_light.position = _pos + Vector2(0, 16)
		
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		grad.colors = PackedColorArray([
			Color(1.0, 0.92, 0.75, 1.0),
			Color(1.0, 0.85, 0.60, 0.50),
			Color(1.0, 0.80, 0.40, 0.0)
		])
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.width = 220
		tex.height = 220
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		_light.texture = tex
		_light.visible = true
		add_child(_light)
		
		queue_redraw()
		
	func _draw() -> void:
		draw_circle(_pos + Vector2(2, 2), 6.0, Color(0.05, 0.05, 0.05, 0.35))
		draw_circle(_pos, 4.5, Color("#2c3e50"))
		draw_line(_pos, _pos + Vector2(0, 16), Color("#7f8c8d"), 3.0)
		draw_circle(_pos + Vector2(0, 16), 3.5, Color("#f9e79f"))

# --- GIZMO VISUAL DE MARCADOR PARA O EDITOR E DEPURAÇÃO ---
class _PortMarkerGizmo extends Node2D:
	@export_storage var _col: Color
	@export_storage var _name: String
	func _init(col: Color = Color.WHITE, marker_name: String = "") -> void:
		_col = col
		_name = marker_name
		z_index = 20
		
	func _draw() -> void:
		# Desenha apenas no editor ou quando em modo depuração
		if Engine.is_editor_hint():
			draw_circle(Vector2.ZERO, 10.0, _col)
			draw_circle(Vector2.ZERO, 14.0, _col, false, 2.0)
			# Seta de orientação
			draw_line(Vector2.ZERO, Vector2(24, 0), _col, 3.0)
			draw_line(Vector2(24, 0), Vector2(18, -5), _col, 3.0)
			draw_line(Vector2(24, 0), Vector2(18, 5), _col, 3.0)
