extends Node3D

## Cenário 3D Autêntico da Delegacia de Polícia do Porto (Harbor Patrol)
## Renderiza em tempo real a delegacia volumétrica completa em padrão PBR:
## - Arquitetura institucional: piso em granilite polido no lobby, linóleo nos escritórios,
##   concreto nas celas, paredes bicolores com lambris e rodapés de madeira escura.
## - Balcão central de triagem em L com divisória de vidro blindado, interfone e carimbos.
## - Salão dos Detetives (Bullpen) com 4 mesas, computadores CRT, arquivos de metal
##   e Grande Mural de Investigação com fotos de suspeitos e linhas vermelhas.
## - Carceragem com 2 celas de grades cilíndricas de aço, beliche, banco e sanitário inox.
## - Sala de Interrogatório com vidro espelhado unilateral, mesa de aço e luminária pendente.
## - Armaria de alta segurança com divisória aramada, racks de escopetas e caixas de evidência.
## - Área de espera com longarina de cadeiras, bebedouro com galão azul e quadro de avisos.
## - Iluminação PBR com sombras suaves, tubos fluorescentes e rádio com alerta piscante.

var materials: Dictionary = {}
var radio_light: OmniLight3D
var radio_beacon: MeshInstance3D
var anim_clock: float = 0.0

func _ready() -> void:
	_setup_lighting_and_env()
	_build_architectural_shell()
	_build_reception_front_desk()
	_build_detective_bullpen()
	_build_holding_cells()
	_build_interrogation_room()
	_build_armory_and_evidence()
	_build_waiting_area()
	_build_ceiling_fixtures()

func _process(delta: float) -> void:
	anim_clock += delta
	if is_instance_valid(radio_light):
		var flash := sin(anim_clock * 8.0)
		radio_light.light_energy = 0.8 + flash * 0.6
		if is_instance_valid(radio_beacon):
			var mat: StandardMaterial3D = radio_beacon.material_override
			if mat:
				mat.emission_energy_multiplier = 1.0 + flash * 0.8

# ==============================================================================
# 1. MATERIAIS PBR & ILUMINAÇÃO
# ==============================================================================

func _mat(key: String, color: Color, metallic: float = 0.0, roughness: float = 0.6, glow: float = 0.0) -> StandardMaterial3D:
	if materials.has(key):
		return materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	m.shading_mode = StandardMaterial3D.SHADING_MODE_PER_PIXEL
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	materials[key] = m
	return m

func _box(pos: Vector3, size: Vector3, material: Material, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi

func _cyl(pos: Vector3, radius: float, height: float, material: Material, parent: Node3D = self, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 12
	mi.mesh = cm
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi

func _setup_lighting_and_env() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62, -28, 0)
	sun.light_energy = 1.25
	sun.light_color = Color("#eef4f8")
	sun.shadow_enabled = true
	sun.shadow_bias = 0.03
	add_child(sun)

	# Luz de preenchimento suave interna
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(45, 140, 0)
	fill.light_energy = 0.35
	fill.light_color = Color("#9ab2c9")
	fill.shadow_enabled = false
	add_child(fill)

# ==============================================================================
# 2. ESTRUTURA ARQUITETÔNICA (Paredes, Pisos, Divisórias)
# ==============================================================================

func _build_architectural_shell() -> void:
	var floor_lobby_mat := _mat("floor_lobby", Color("#2b3542"), 0.1, 0.4) # Granilite / Terrazzo
	var floor_office_mat := _mat("floor_office", Color("#1f2732"), 0.05, 0.6) # Linóleo
	var floor_cell_mat := _mat("floor_cell", Color("#181d24"), 0.0, 0.85) # Concreto rústico
	var border_tile_mat := _mat("floor_border", Color("#11161d"), 0.1, 0.5)

	# Piso base geral (22m x 15m, centro em (0, -0.5))
	_box(Vector3(0, -0.05, -0.5), Vector3(22.4, 0.1, 15.4), floor_lobby_mat)
	# Setor de celas (piso de concreto cinza escuro)
	_box(Vector3(6.5, -0.04, -4.0), Vector3(8.0, 0.1, 6.2), floor_cell_mat)
	# Setor dos detetives (piso de linóleo)
	_box(Vector3(-5.5, -0.04, -4.2), Vector3(10.0, 0.1, 6.4), floor_office_mat)

	# Frisos decorativos no piso do lobby
	_box(Vector3(0, 0.005, 1.8), Vector3(10.0, 0.01, 0.08), border_tile_mat)
	_box(Vector3(-0.8, 0.005, 3.8), Vector3(0.08, 0.01, 4.0), border_tile_mat)
	_box(Vector3(0.8, 0.005, 3.8), Vector3(0.08, 0.01, 4.0), border_tile_mat)

	# Paredes externas (altura 3.2m)
	var wall_ext_mat := _mat("wall_ext", Color("#334155"), 0.0, 0.8)
	var wall_base_mat := _mat("wall_base", Color("#1e293b"), 0.05, 0.7) # Lambril inferior escuro
	var trim_mat := _mat("wall_trim", Color("#64748b"), 0.2, 0.4)

	var h := 3.2
	# Parede Norte (fundo, Z = -8.0)
	_solid(_box(Vector3(0, h * 0.5, -8.1), Vector3(22.4, h, 0.25), wall_ext_mat))
	_solid(_box(Vector3(0, 0.5, -7.96), Vector3(22.4, 1.0, 0.05), wall_base_mat))
	_box(Vector3(0, 1.02, -7.94), Vector3(22.4, 0.05, 0.03), trim_mat)

	# Parede Sul (frente com vão da porta central, Z = 7.0)
	# Vão da porta entre X = -1.2 e 1.2
	_solid(_box(Vector3(-6.2, h * 0.5, 7.1), Vector3(10.0, h, 0.25), wall_ext_mat))
	_solid(_box(Vector3(-6.2, 0.5, 6.96), Vector3(10.0, 1.0, 0.05), wall_base_mat))
	_box(Vector3(-6.2, 1.02, 6.94), Vector3(10.0, 0.05, 0.03), trim_mat)

	_solid(_box(Vector3(6.2, h * 0.5, 7.1), Vector3(10.0, h, 0.25), wall_ext_mat))
	_solid(_box(Vector3(6.2, 0.5, 6.96), Vector3(10.0, 1.0, 0.05), wall_base_mat))
	_box(Vector3(6.2, 1.02, 6.94), Vector3(10.0, 0.05, 0.03), trim_mat)

	# Viga sobre a porta de entrada
	_box(Vector3(0, 2.7, 7.1), Vector3(2.4, 1.0, 0.25), wall_ext_mat)

	# Parede Oeste (esquerda, X = -11.1)
	_solid(_box(Vector3(-11.1, h * 0.5, -0.5), Vector3(0.25, h, 15.4), wall_ext_mat))
	_solid(_box(Vector3(-10.96, 0.5, -0.5), Vector3(0.05, 1.0, 15.4), wall_base_mat))

	# Parede Leste (direita, X = 11.1)
	_solid(_box(Vector3(11.1, h * 0.5, -0.5), Vector3(0.25, h, 15.4), wall_ext_mat))
	_solid(_box(Vector3(10.96, 0.5, -0.5), Vector3(0.05, 1.0, 15.4), wall_base_mat))

	# Divisórias Internas:
	var partition_mat := _mat("partition", Color("#283548"), 0.0, 0.75)

	# Parede divisória entre Sala de Interrogatório e Bullpen (X de -11 a -6, Z = -1.0)
	_solid(_box(Vector3(-8.5, h * 0.5, -1.0), Vector3(5.0, h, 0.18), partition_mat))
	# Parede Leste da Sala de Interrogatório (X = -6.0, Z de -1.0 a 2.5)
	_solid(_box(Vector3(-6.0, h * 0.5, 0.75), Vector3(0.18, h, 3.5), partition_mat))

	# Parede divisória Norte dos Escritórios / Bullpen com o corredor central (Z = -1.0, X de -4.5 a -1.2)
	_solid(_box(Vector3(-2.8, h * 0.5, -1.0), Vector3(3.2, h, 0.18), partition_mat))

	# Parede divisória da Armaria (X de 4.0 a 11.0, Z = 0.5)
	_solid(_box(Vector3(7.5, h * 0.5, 0.5), Vector3(7.0, h, 0.18), partition_mat))
	# Parede Oeste da Armaria (X = 4.0, Z de 0.5 a 4.5)
	_solid(_box(Vector3(4.0, h * 0.5, 2.5), Vector3(0.18, h, 4.0), partition_mat))

	# Pilares estruturais robustos
	var pillar_mat := _mat("pillar", Color("#1c2430"), 0.1, 0.6)
	for px in [-6.0, -1.2, 3.8]:
		_solid(_box(Vector3(px, h * 0.5, -1.0), Vector3(0.45, h, 0.45), pillar_mat))
	for px in [-6.0, 4.0]:
		_solid(_box(Vector3(px, h * 0.5, 3.5), Vector3(0.45, h, 0.45), pillar_mat))

# ==============================================================================
# 3. RECEPÇÃO CENTRAL & BALCÃO BLINDADO (Onde fica o Sargento Morales)
# ==============================================================================

func _build_reception_front_desk() -> void:
	var desk_parent := Node3D.new()
	desk_parent.name = "FrontDeskRig"
	add_child(desk_parent)

	var wood_desk_mat := _mat("front_desk_wood", Color("#1a2634"), 0.05, 0.5)
	var counter_top_mat := _mat("front_counter_top", Color("#384959"), 0.15, 0.3)
	var glass_mat := _mat("security_glass", Color(0.45, 0.7, 0.85, 0.4), 0.3, 0.1)
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var steel_frame_mat := _mat("steel_frame", Color("#475569"), 0.6, 0.3)
	var brass_mat := _mat("brass_accent", Color("#c59b27"), 0.7, 0.3)

	# Balcão frontal principal (comprimento 3.6m, largura 0.7m, altura 1.15m em Z = 0.8)
	_solid(_box(Vector3(0.0, 0.55, 0.8), Vector3(3.6, 1.1, 0.65), wood_desk_mat, desk_parent))
	# Tampo saliente em pedra polida
	_solid(_box(Vector3(0.0, 1.12, 0.8), Vector3(3.7, 0.06, 0.75), counter_top_mat, desk_parent))

	# Asa lateral em L do balcão (voltada para o interior, X = 1.7, Z de 0.8 a -0.5)
	_solid(_box(Vector3(1.65, 0.55, 0.15), Vector3(0.65, 1.1, 1.3), wood_desk_mat, desk_parent))
	_solid(_box(Vector3(1.65, 1.12, 0.15), Vector3(0.75, 0.06, 1.4), counter_top_mat, desk_parent))

	# Divisória de Vidro Blindado sobre o balcão
	_box(Vector3(0.0, 1.68, 0.8), Vector3(3.5, 1.06, 0.04), glass_mat, desk_parent)
	# Moldura de aço do vidro
	_solid(_box(Vector3(0.0, 2.22, 0.8), Vector3(3.6, 0.05, 0.06), steel_frame_mat, desk_parent))
	for vx in [-1.75, -0.6, 0.6, 1.75]:
		_solid(_box(Vector3(vx, 1.68, 0.8), Vector3(0.05, 1.08, 0.06), steel_frame_mat, desk_parent))

	# Grade de comunicação / orifícios de fala (Speech Grille) no vidro em frente ao sargento
	for gy in range(3):
		_solid(_box(Vector3(0.0, 1.45 + gy * 0.06, 0.8), Vector3(0.24, 0.02, 0.06), steel_frame_mat, desk_parent))
	# Microfone pescoço de ganso
	_solid(_cyl(Vector3(0.3, 1.16, 0.65), 0.04, 0.03, steel_frame_mat, desk_parent))
	_solid(_cyl(Vector3(0.3, 1.25, 0.68), 0.008, 0.18, steel_frame_mat, desk_parent, Vector3(20, 0, 0)))

	# Computador do balcão de triagem (Monitor CRT + Gabinete)
	var monitor_case_mat := _mat("crt_case", Color("#c2b8a3"), 0.0, 0.7)
	var screen_mat := _mat("police_screen", Color("#0e3a2f"), 0.1, 0.2, 0.8) # Fósforo verde
	var keyboard_mat := _mat("keyboard", Color("#8a8375"), 0.1, 0.6)

	_box(Vector3(-0.7, 1.35, 0.65), Vector3(0.42, 0.36, 0.35), monitor_case_mat, desk_parent)
	_box(Vector3(-0.7, 1.35, 0.83), Vector3(0.34, 0.28, 0.01), screen_mat, desk_parent)
	_box(Vector3(-0.7, 1.16, 0.62), Vector3(0.38, 0.03, 0.16), keyboard_mat, desk_parent)

	# Rádio de Despacho Policial com Giroflex / Luz Intermitente
	var radio_box_mat := _mat("radio_box", Color("#1b2028"), 0.2, 0.5)
	_box(Vector3(0.85, 1.20, 0.65), Vector3(0.32, 0.12, 0.22), radio_box_mat, desk_parent)
	# Antena metálica
	_solid(_cyl(Vector3(0.96, 1.45, 0.60), 0.006, 0.45, steel_frame_mat, desk_parent))
	# Luz do rádio (Giroflex miniatura)
	var beacon_mat := _mat("radio_beacon_mat", Color("#38bdf8"), 0.0, 0.1, 2.0)
	radio_beacon = _cyl(Vector3(0.75, 1.28, 0.65), 0.035, 0.06, beacon_mat, desk_parent)

	radio_light = OmniLight3D.new()
	radio_light.position = Vector3(0.75, 1.35, 0.65)
	radio_light.light_color = Color("#38bdf8")
	radio_light.light_energy = 1.2
	radio_light.omni_range = 3.5
	desk_parent.add_child(radio_light)

	# Bandejas de documentos, pastas de queixas e carimbos
	var paper_mat := _mat("paper_cream", Color("#ede8d5"), 0.0, 0.9)
	var folder_mat := _mat("folder_manila", Color("#c89f65"), 0.0, 0.8)
	_solid(_box(Vector3(-1.3, 1.17, 0.65), Vector3(0.26, 0.05, 0.34), steel_frame_mat, desk_parent))
	_box(Vector3(-1.3, 1.20, 0.65), Vector3(0.24, 0.03, 0.32), paper_mat, desk_parent)
	_box(Vector3(1.3, 1.16, 0.65), Vector3(0.28, 0.02, 0.38), folder_mat, desk_parent)
	_cyl(Vector3(-0.25, 1.17, 0.60), 0.025, 0.04, brass_mat, desk_parent) # Sineta de balcão

	# Cadeira giratória do sargento
	var chair_mat := _mat("office_chair", Color("#17202a"), 0.1, 0.7)
	_solid(_cyl(Vector3(0.0, 0.25, -0.1), 0.25, 0.5, steel_frame_mat, desk_parent))
	_solid(_box(Vector3(0.0, 0.52, -0.1), Vector3(0.48, 0.08, 0.45), chair_mat, desk_parent))
	_solid(_box(Vector3(0.0, 0.82, -0.3), Vector3(0.46, 0.52, 0.08), chair_mat, desk_parent))

# ==============================================================================
# 4. SALÃO DOS DETETIVES (BULLPEN)
# ==============================================================================

func _build_detective_bullpen() -> void:
	var bullpen := Node3D.new()
	bullpen.name = "DetectiveBullpen"
	add_child(bullpen)

	var desk_mat := _mat("detective_desk", Color("#2c3b4d"), 0.1, 0.5)
	var top_mat := _mat("detective_top", Color("#403328"), 0.0, 0.6) # Madeira média
	var file_mat := _mat("file_cabinet", Color("#3e4c59"), 0.3, 0.4)
	var lamp_mat := _mat("desk_lamp_green", Color("#196f3d"), 0.2, 0.3, 0.5)

	# 4 Mesas em duplas no centro do salão
	var desk_positions := [
		Vector3(-8.0, 0.0, -5.5),
		Vector3(-4.5, 0.0, -5.5),
		Vector3(-8.0, 0.0, -3.0),
		Vector3(-4.5, 0.0, -3.0)
	]

	for i in range(desk_positions.size()):
		var dp: Vector3 = desk_positions[i]
		var d := Node3D.new()
		d.position = dp
		bullpen.add_child(d)

		# Estrutura da mesa
		_solid(_box(Vector3(0, 0.38, 0), Vector3(1.6, 0.74, 0.85), desk_mat, d))
		_solid(_box(Vector3(0, 0.76, 0), Vector3(1.7, 0.04, 0.95), top_mat, d))

		# Monitor CRT com tela âmbar
		var screen_amber := _mat("amber_screen_%d" % i, Color("#4a2800"), 0.1, 0.2, 0.7)
		_box(Vector3(-0.35, 1.0, -0.1), Vector3(0.38, 0.32, 0.32), _mat("crt_case", Color("#c2b8a3")), d)
		_box(Vector3(-0.35, 1.0, 0.07), Vector3(0.30, 0.24, 0.01), screen_amber, d)
		_box(Vector3(-0.35, 0.80, 0.22), Vector3(0.35, 0.02, 0.14), _mat("keyboard", Color("#8a8375")), d)

		# Luminária de mesa clássica verde
		_cyl(Vector3(0.45, 0.81, -0.2), 0.06, 0.02, _mat("brass_accent", Color("#c59b27")), d)
		_box(Vector3(0.45, 0.98, -0.2), Vector3(0.22, 0.08, 0.12), lamp_mat, d)

		# Luz da luminária
		var lamp_light := OmniLight3D.new()
		lamp_light.position = Vector3(0.45, 0.92, -0.2)
		lamp_light.light_color = Color("#ffeaad")
		lamp_light.light_energy = 0.6
		lamp_light.omni_range = 2.0
		d.add_child(lamp_light)

		# Pilhas de processos e xícara de café
		_box(Vector3(0.4, 0.81, 0.15), Vector3(0.24, 0.06, 0.32), _mat("folder_manila", Color("#c89f65")), d)
		_cyl(Vector3(0.15, 0.83, 0.25), 0.04, 0.08, _mat("coffee_mug", Color("#f0f3f4")), d)

		# Cadeira de escritório
		_solid(_box(Vector3(0, 0.48, 0.75), Vector3(0.45, 0.06, 0.42), _mat("office_chair", Color("#17202a")), d))
		_solid(_box(Vector3(0, 0.76, 0.94), Vector3(0.42, 0.48, 0.06), _mat("office_chair", Color("#17202a")), d))

	# Ficheiros / Arquivos de Metal de 4 gavetas contra a parede Oeste
	for fz in [-6.8, -5.8, -4.8, -3.8]:
		var f := _box(Vector3(-10.6, 0.7, fz), Vector3(0.65, 1.35, 0.55), file_mat, bullpen)
		# Puxadores de metal das gavetas
		for gy in range(4):
			_box(Vector3(0.33, -0.45 + gy * 0.3, 0), Vector3(0.02, 0.03, 0.12), _mat("steel_frame", Color("#475569")), f)

	# GRANDE MURAL DE INVESTIGAÇÃO (Evidence Corkboard) na parede Norte
	var corkboard_parent := Node3D.new()
	corkboard_parent.name = "EvidenceCorkboard"
	corkboard_parent.position = Vector3(-6.2, 1.85, -7.92)
	bullpen.add_child(corkboard_parent)

	var cork_mat := _mat("corkboard", Color("#936848"), 0.0, 0.9)
	var wood_frame_mat := _mat("cork_frame", Color("#382315"), 0.1, 0.7)
	var red_string_mat := _mat("red_string", Color("#b03a2e"), 0.0, 0.5, 0.4)

	# Painel de cortiça (3.8m x 1.6m)
	_box(Vector3(0, 0, 0), Vector3(3.8, 1.6, 0.04), cork_mat, corkboard_parent)
	_solid(_box(Vector3(0, 0.82, 0), Vector3(3.9, 0.06, 0.06), wood_frame_mat, corkboard_parent))
	_solid(_box(Vector3(0, -0.82, 0), Vector3(3.9, 0.06, 0.06), wood_frame_mat, corkboard_parent))
	_solid(_box(Vector3(1.92, 0, 0), Vector3(0.06, 1.7, 0.06), wood_frame_mat, corkboard_parent))
	_solid(_box(Vector3(-1.92, 0, 0), Vector3(0.06, 1.7, 0.06), wood_frame_mat, corkboard_parent))

	# Fotos de suspeitos, recortes de jornais e mapa no mural
	var photo_mat := _mat("mugshot", Color("#d5dbdb"), 0.0, 0.7)
	var map_mat := _mat("harbor_map", Color("#d4cbb3"), 0.0, 0.8)

	_box(Vector3(0, 0.1, 0.03), Vector3(1.1, 0.75, 0.01), map_mat, corkboard_parent) # Mapa central
	# Fotos de suspeitos dispostas no quadro
	for p_pos in [Vector3(-1.2, 0.4, 0.03), Vector3(-1.3, -0.3, 0.03), Vector3(1.2, 0.45, 0.03), Vector3(1.3, -0.3, 0.03), Vector3(-0.5, 0.55, 0.03), Vector3(0.6, 0.55, 0.03)]:
		_box(p_pos, Vector3(0.24, 0.28, 0.01), photo_mat, corkboard_parent)
		_cyl(p_pos + Vector3(0, 0.13, 0.01), 0.012, 0.02, _mat("pin_red", Color("#e74c3c")), corkboard_parent, Vector3(90, 0, 0))

	# Linhas vermelhas de ligação (linhas de barbante ligando os crimes)
	_box(Vector3(-0.6, 0.25, 0.035), Vector3(1.1, 0.012, 0.005), red_string_mat, corkboard_parent)
	_box(Vector3(0.6, 0.28, 0.035), Vector3(1.1, 0.012, 0.005), red_string_mat, corkboard_parent)

# ==============================================================================
# 5. CARCERAGEM & CELAS DE CUSTÓDIA TEMPORÁRIA
# ==============================================================================

func _build_holding_cells() -> void:
	var holding := Node3D.new()
	holding.name = "HoldingCells"
	add_child(holding)

	var cell_steel_mat := _mat("cell_steel", Color("#21262d"), 0.7, 0.35)
	var lock_mat := _mat("cell_lock", Color("#d4ac0d"), 0.8, 0.2)
	var bench_mat := _mat("cell_bench", Color("#34495e"), 0.0, 0.8)
	var inox_mat := _mat("stainless_steel", Color("#7f8c8d"), 0.85, 0.2)

	# Corredor das celas: Z de -7.5 a -1.5, X de 4.0 a 10.8
	# Cela 1 (Esquerda): X de 4.2 a 7.2, Z de -7.8 a -2.0
	# Cela 2 (Direita):  X de 7.5 a 10.5, Z de -7.8 a -2.0

	var cell_front_z := -2.0
	var h := 3.2

	# Viga horizontal superior das grades
	_box(Vector3(7.4, 2.8, cell_front_z), Vector3(6.6, 0.12, 0.12), cell_steel_mat, holding)
	_solid(_box(Vector3(7.4, 0.06, cell_front_z), Vector3(6.6, 0.12, 0.12), cell_steel_mat, holding))
	_solid(_box(Vector3(7.4, 1.4, cell_front_z), Vector3(6.6, 0.08, 0.08), cell_steel_mat, holding))

	# Parede de separação entre Cela 1 e Cela 2 (X = 7.35, Z de -7.8 a -2.0)
	_solid(_box(Vector3(7.35, h * 0.5, -4.9), Vector3(0.2, h, 5.8), _mat("wall_ext", Color("#334155")), holding))

	# Pilares das portas das celas
	for px in [4.2, 5.7, 7.2, 7.5, 9.0, 10.5]:
		_solid(_box(Vector3(px, h * 0.5, cell_front_z), Vector3(0.12, h, 0.12), cell_steel_mat, holding))

	# Grades verticais de aço (cilindros de 3D real)
	for cx in [Vector2(4.2, 7.2), Vector2(7.5, 10.5)]:
		var start_x: float = cx.x
		var end_x: float = cx.y
		var bars_count := int((end_x - start_x) / 0.18)
		for b in range(bars_count):
			var bx: float = start_x + b * 0.18 + 0.09
			# Deixa o vão da fechadura livre
			if absf(bx - 5.7) > 0.06 and absf(bx - 9.0) > 0.06:
				_solid(_cyl(Vector3(bx, 1.4, cell_front_z), 0.022, 2.7, cell_steel_mat, holding))

	# Caixas das fechaduras eletrônicas / trincos pesados de prisão
	_box(Vector3(5.72, 1.35, cell_front_z), Vector3(0.18, 0.28, 0.14), lock_mat, holding)
	_box(Vector3(9.02, 1.35, cell_front_z), Vector3(0.18, 0.28, 0.14), lock_mat, holding)

	# Interior da Cela 1 (Onde fica o detento):
	# Banco de concreto na parede esquerda
	_solid(_box(Vector3(4.6, 0.25, -5.0), Vector3(0.65, 0.48, 3.2), bench_mat, holding))
	# Beliche metálico no fundo
	_solid(_box(Vector3(5.7, 0.45, -7.2), Vector3(2.2, 0.1, 0.9), cell_steel_mat, holding))
	_solid(_box(Vector3(5.7, 1.55, -7.2), Vector3(2.2, 0.1, 0.9), cell_steel_mat, holding))
	for lx in [4.65, 6.75]:
		_solid(_cyl(Vector3(lx, 1.1, -7.6), 0.025, 2.2, cell_steel_mat, holding))
		_solid(_cyl(Vector3(lx, 1.1, -6.8), 0.025, 2.2, cell_steel_mat, holding))

	# Vaso sanitário + pia integrados de aço inox de prisão
	_solid(_box(Vector3(7.0, 0.35, -7.2), Vector3(0.42, 0.65, 0.55), inox_mat, holding))
	_solid(_cyl(Vector3(7.0, 0.72, -7.2), 0.16, 0.12, inox_mat, holding))

	# Interior da Cela 2:
	_solid(_box(Vector3(10.1, 0.25, -5.0), Vector3(0.65, 0.48, 3.2), bench_mat, holding))
	_solid(_box(Vector3(8.9, 0.45, -7.2), Vector3(2.2, 0.1, 0.9), cell_steel_mat, holding))
	_solid(_box(Vector3(8.9, 1.55, -7.2), Vector3(2.2, 0.1, 0.9), cell_steel_mat, holding))
	_solid(_box(Vector3(7.7, 0.35, -7.2), Vector3(0.42, 0.65, 0.55), inox_mat, holding))

# ==============================================================================
# 6. SALA DE INTERROGATÓRIO
# ==============================================================================

func _build_interrogation_room() -> void:
	var inter := Node3D.new()
	inter.name = "InterrogationRoom"
	add_child(inter)

	var mirror_mat := _mat("two_way_mirror", Color(0.2, 0.35, 0.45, 0.85), 0.8, 0.1)
	var steel_mat := _mat("interrogation_steel", Color("#2c3e50"), 0.6, 0.4)

	# Janela de Vidro Espelhado voltada para o salão dos detetives (Z = -1.0, X de -9.5 a -7.5)
	_box(Vector3(-8.5, 1.6, -1.0), Vector3(2.2, 1.1, 0.08), mirror_mat, inter)
	_solid(_box(Vector3(-8.5, 2.18, -1.0), Vector3(2.3, 0.06, 0.12), steel_mat, inter))
	_solid(_box(Vector3(-8.5, 1.02, -1.0), Vector3(2.3, 0.06, 0.12), steel_mat, inter))

	# Mesa pesada de metal no centro da sala de interrogatório (X = -8.5, Z = 0.8)
	_solid(_box(Vector3(-8.5, 0.72, 0.8), Vector3(1.5, 0.06, 0.9), steel_mat, inter))
	_solid(_box(Vector3(-8.5, 0.35, 0.8), Vector3(1.3, 0.68, 0.1), steel_mat, inter))
	for leg_x in [-9.1, -7.9]:
		_solid(_cyl(Vector3(leg_x, 0.35, 0.4), 0.03, 0.7, steel_mat, inter))
		_solid(_cyl(Vector3(leg_x, 0.35, 1.2), 0.03, 0.7, steel_mat, inter))

	# Duas cadeiras de aço (uma de cada lado)
	_solid(_box(Vector3(-8.5, 0.45, 0.15), Vector3(0.42, 0.05, 0.4), steel_mat, inter))
	_solid(_box(Vector3(-8.5, 0.75, -0.02), Vector3(0.4, 0.55, 0.05), steel_mat, inter))
	_solid(_box(Vector3(-8.5, 0.45, 1.45), Vector3(0.42, 0.05, 0.4), steel_mat, inter))
	_solid(_box(Vector3(-8.5, 0.75, 1.62), Vector3(0.4, 0.55, 0.05), steel_mat, inter))

	# Gravador de rolo / fita cassete sobre a mesa
	_box(Vector3(-8.1, 0.78, 0.8), Vector3(0.22, 0.06, 0.16), _mat("recorder", Color("#1b2631")), inter)

	# Luminária cônica rebaixada lançando foco de luz direto na mesa
	var cone_mat := _mat("lamp_cone", Color("#17202a"), 0.3, 0.5)
	_cyl(Vector3(-8.5, 2.6, 0.8), 0.005, 1.2, steel_mat, inter)
	_cyl(Vector3(-8.5, 2.0, 0.8), 0.22, 0.18, cone_mat, inter)

	var spot := SpotLight3D.new()
	spot.position = Vector3(-8.5, 1.9, 0.8)
	spot.rotation_degrees = Vector3(-90, 0, 0)
	spot.light_color = Color("#fff4d6")
	spot.light_energy = 2.2
	spot.spot_range = 3.5
	spot.spot_angle = 42.0
	spot.shadow_enabled = true
	inter.add_child(spot)

# ==============================================================================
# 7. ARMARIA & DEPÓSITO DE EVIDÊNCIAS
# ==============================================================================

func _build_armory_and_evidence() -> void:
	var armory := Node3D.new()
	armory.name = "ArmoryRoom"
	add_child(armory)

	var mesh_mat := _mat("armory_mesh", Color(0.3, 0.35, 0.4, 0.7), 0.6, 0.4)
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var steel_mat := _mat("steel_frame", Color("#475569"))
	var wood_gun_mat := _mat("gun_wood", Color("#4a2311"), 0.0, 0.6)
	var gun_metal_mat := _mat("gun_metal", Color("#17202a"), 0.9, 0.25)
	var box_cardboard_mat := _mat("evidence_box", Color("#a07855"), 0.0, 0.8)

	# Divisória de tela aramada com o corredor (X de 4.0 a 10.8, Z = 0.5)
	_box(Vector3(7.4, 1.6, 0.5), Vector3(6.6, 3.0, 0.04), mesh_mat, armory)
	_box(Vector3(7.4, 3.1, 0.5), Vector3(6.6, 0.08, 0.08), steel_mat, armory)
	for x in range(4, 11, 2):
		_solid(_box(Vector3(float(x), 1.6, 0.5), Vector3(0.08, 3.1, 0.08), steel_mat, armory))

	# Rack de armas na parede Leste (X = 10.8, Z de 1.2 a 3.8)
	_solid(_box(Vector3(10.8, 1.4, 2.5), Vector3(0.12, 1.8, 2.8), steel_mat, armory))
	_solid(_box(Vector3(10.7, 0.55, 2.5), Vector3(0.25, 0.08, 2.7), steel_mat, armory))
	_solid(_box(Vector3(10.7, 1.85, 2.5), Vector3(0.25, 0.08, 2.7), steel_mat, armory))

	# Espingardas / Fuzis no suporte
	for gz in [1.5, 1.9, 2.3, 2.7, 3.1, 3.5]:
		# Coronha de madeira
		_box(Vector3(10.7, 0.85, gz), Vector3(0.06, 0.42, 0.08), wood_gun_mat, armory)
		# Cano de aço
		_cyl(Vector3(10.7, 1.5, gz), 0.015, 0.95, gun_metal_mat, armory)

	# Estantes de evidências na parede Sul da armaria (Z = 6.8, X de 5.0 a 10.0)
	for sz in [1.0, 1.8, 2.6]:
		_solid(_box(Vector3(7.5, sz, 6.8), Vector3(5.0, 0.05, 0.6), steel_mat, armory))
	for sx in [5.1, 7.5, 9.9]:
		_solid(_box(Vector3(sx, 1.6, 6.8), Vector3(0.06, 3.0, 0.58), steel_mat, armory))

	# Caixas de evidências seladas com etiquetas
	for bx in [5.6, 6.3, 7.0, 8.2, 9.0]:
		_box(Vector3(bx, 1.2, 6.8), Vector3(0.48, 0.35, 0.42), box_cardboard_mat, armory)
		_box(Vector3(bx, 1.2, 6.58), Vector3(0.2, 0.12, 0.01), _mat("paper_cream", Color("#ede8d5")), armory) # Etiqueta

# ==============================================================================
# 8. ÁREA DE ESPERA & TERMINAL INTERATIVO
# ==============================================================================

func _build_waiting_area() -> void:
	var wait_zone := Node3D.new()
	wait_zone.name = "WaitingArea"
	add_child(wait_zone)

	var seat_mat := _mat("seat_blue", Color("#1f4068"), 0.1, 0.5)
	var frame_mat := _mat("steel_frame", Color("#475569"))
	var water_base_mat := _mat("water_cooler_base", Color("#d5dbdb"), 0.1, 0.4)
	var water_bottle_mat := _mat("water_bottle", Color(0.2, 0.6, 0.9, 0.55), 0.2, 0.1)
	water_bottle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# Fileira de longarinas / cadeiras de espera (Z de 3.2 a 5.0, X = -3.2)
	_solid(_box(Vector3(-3.2, 0.22, 4.1), Vector3(0.4, 0.04, 2.2), frame_mat, wait_zone))
	for sz in [3.3, 3.8, 4.3, 4.8]:
		_solid(_box(Vector3(-3.2, 0.45, sz), Vector3(0.45, 0.05, 0.38), seat_mat, wait_zone))
		_solid(_box(Vector3(-3.4, 0.72, sz), Vector3(0.05, 0.48, 0.38), seat_mat, wait_zone))

	# Bebedouro de água com galão azul
	var cooler_pos := Vector3(-4.8, 0.0, 5.5)
	_solid(_box(cooler_pos + Vector3(0, 0.5, 0), Vector3(0.4, 1.0, 0.38), water_base_mat, wait_zone))
	# Torneiras azul e vermelha
	_cyl(cooler_pos + Vector3(0.08, 0.85, 0.2), 0.015, 0.04, _mat("tap_blue", Color("#2980b9")), wait_zone, Vector3(90, 0, 0))
	_cyl(cooler_pos + Vector3(-0.08, 0.85, 0.2), 0.015, 0.04, _mat("tap_red", Color("#c0392b")), wait_zone, Vector3(90, 0, 0))
	# Galão azul invertido de 20 litros
	_cyl(cooler_pos + Vector3(0, 1.25, 0), 0.16, 0.45, water_bottle_mat, wait_zone)
	_cyl(cooler_pos + Vector3(0, 1.5, 0), 0.06, 0.08, water_bottle_mat, wait_zone)

	# Lixeira de pedal inox ao lado do bebedouro
	_solid(_cyl(cooler_pos + Vector3(0.45, 0.22, 0), 0.12, 0.44, _mat("stainless_steel", Color("#7f8c8d")), wait_zone))

	# MESA DO TERMINAL DE OCORRÊNCIAS & MANDADOS (X = -4.2, Z = 1.5)
	var term_table_pos := Vector3(-4.2, 0.0, 1.5)
	_solid(_box(term_table_pos + Vector3(0, 0.38, 0), Vector3(1.2, 0.74, 0.7), _mat("detective_desk", Color("#2c3b4d")), wait_zone))
	_solid(_box(term_table_pos + Vector3(0, 0.76, 0), Vector3(1.26, 0.04, 0.76), _mat("detective_top", Color("#403328")), wait_zone))

	# Monitor do Terminal de Ocorrências com tela azul vibrante
	var term_screen_mat := _mat("terminal_police_blue", Color("#0a3d62"), 0.1, 0.2, 1.2)
	_box(term_table_pos + Vector3(0, 1.05, 0), Vector3(0.44, 0.35, 0.28), _mat("crt_case", Color("#c2b8a3")), wait_zone)
	_box(term_table_pos + Vector3(0, 1.05, 0.15), Vector3(0.36, 0.27, 0.01), term_screen_mat, wait_zone)
	_box(term_table_pos + Vector3(0, 0.80, 0.22), Vector3(0.38, 0.02, 0.15), _mat("keyboard", Color("#8a8375")), wait_zone)

	var term_light := OmniLight3D.new()
	term_light.position = term_table_pos + Vector3(0, 1.1, 0.25)
	term_light.light_color = Color("#38bdf8")
	term_light.light_energy = 0.8
	term_light.omni_range = 2.2
	wait_zone.add_child(term_light)

# ==============================================================================
# 9. LUMINÁRIAS DE TETO & DETALHES INSTITUCIONAIS
# ==============================================================================

func _build_ceiling_fixtures() -> void:
	var ceiling := Node3D.new()
	ceiling.name = "CeilingFixtures"
	add_child(ceiling)

	var fix_metal := _mat("fixture_metal", Color("#334155"), 0.3, 0.5)
	var tube_glow := _mat("tube_glow", Color("#f8fafc"), 0.0, 0.1, 1.8)

	var light_positions := [
		Vector3(0.0, 3.1, 3.5),
		Vector3(0.0, 3.1, -0.5),
		Vector3(-6.0, 3.1, -4.5),
		Vector3(-6.0, 3.1, 1.0),
		Vector3(7.5, 3.1, -4.5),
		Vector3(7.5, 3.1, 3.0)
	]

	for lp in light_positions:
		# Calha metálica da lâmpada fluorescente
		_box(lp, Vector3(1.6, 0.08, 0.32), fix_metal, ceiling)
		# Dois tubos fluorescentes brilhantes
		_cyl(lp + Vector3(0, -0.04, -0.08), 0.022, 1.45, tube_glow, ceiling, Vector3(0, 0, 90))
		_cyl(lp + Vector3(0, -0.04, 0.08), 0.022, 1.45, tube_glow, ceiling, Vector3(0, 0, 90))

		var omni := OmniLight3D.new()
		omni.position = lp + Vector3(0, -0.15, 0)
		omni.light_color = Color("#f1f5f9")
		omni.light_energy = 0.95
		omni.omni_range = 6.0
		ceiling.add_child(omni)

	# Câmeras de segurança CFTV (Dome) nos cantos do teto
	var cctv_mat := _mat("cctv_case", Color("#1e293b"), 0.2, 0.4)
	for cp in [Vector3(-10.5, 3.0, 6.5), Vector3(10.5, 3.0, 6.5), Vector3(3.5, 3.0, -1.2)]:
		_cyl(cp, 0.09, 0.06, cctv_mat, ceiling)
		_cyl(cp + Vector3(0, -0.04, 0), 0.06, 0.04, _mat("lens_glass", Color("#0f172a")), ceiling)


func _solid(mesh: MeshInstance3D) -> MeshInstance3D:
	mesh.set_meta("interior_solid_id", StringName("Solid%d" % mesh.get_instance_id()))
	return mesh
