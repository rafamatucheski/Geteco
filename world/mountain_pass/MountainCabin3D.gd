class_name MountainCabin3D
extends Node3D

## Cenário 3D Cinematográfico do Chalé Alpino de Montanha (Godot 4 PBR):
## Sala de estar em 3D real com iluminação dinâmica, sombras suaves, materiais nobres:
## - Lustre de ferro forjado vazado estilo roda de carroça (TorusMesh) com lâmpadas Edison
## - Lareira monumental de pedras com fogão a lenha 3D, chaleira de cobre e chamas vivas
## - Sofá Chesterfield 3D em couro conhaque capitonê, poltrona e manta xadrez
## - Mesa de centro de tronco maciço com mapa topográfico 3D, bússola e caneca esmaltada
## - Tapete de pele com cabeça esculpida de urso pardo 3D
## - Cama de toras roliças de 4 postes com colcha patchwork e criado-mudo com abajur
## - Bar dos caçadores em ardósia com banquetas de couro, garrafas de uísque e tábua de pão
## - Mesa de rádio com luminária verde, diário e caixas de munição
## - Suporte de rifles decorativos; as armas coletáveis ficam no piso livre

var materials: Dictionary = {}
# Set while building each physical object; collision is derived from its meshes.
var _solid_id: StringName = &""

func _ready() -> void:
	_setup_environment_and_lights()
	_build_room_shell()
	_build_monumental_fireplace()
	_build_living_lounge()
	_build_hunter_kitchenette()
	_build_rustic_bedroom()
	_build_armory_and_ranger_desk()
	_build_mudroom_and_entry()
	var fire := preload("res://world/mountain_pass/MountainHearthEffects3D.gd").new()
	fire.name = "LivingHearth"
	fire.position = Vector3(0.4, 0.47, -3.48)
	fire.smoke_height = 0.5
	add_child(fire)
	var steam := preload("res://world/mountain_pass/MountainHearthEffects3D.gd").new()
	steam.name = "KettleSteam"
	steam.position = Vector3(-0.3, 1.02, -3.7)
	steam.show_flames = false
	steam.warmth = 0.0
	steam.smoke_height = 0.45
	steam.scale = Vector3.ONE * 0.6
	add_child(steam)

# ==============================================================================
# 1. MATERIAIS PBR & ILUMINAÇÃO 3D
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

func _box(pos: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	mi.set_meta("interior_solid_id", _solid_id)
	return mi

func _box_child(p: Node3D, pos: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	p.add_child(mi)
	mi.set_meta("interior_solid_id", _solid_id)
	return mi

func _cyl(pos: Vector3, radius: float, height: float, material: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 16
	mi.mesh = cm
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	mi.set_meta("interior_solid_id", _solid_id)
	return mi

func _torus(pos: Vector3, inner_rad: float, outer_rad: float, material: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = inner_rad
	tm.outer_radius = outer_rad
	tm.rings = 24
	tm.ring_segments = 12
	mi.mesh = tm
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	mi.set_meta("interior_solid_id", _solid_id)
	return mi

func _setup_environment_and_lights() -> void:
	# Luz solar fria de montanha entrando pelas janelas
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, 35.0, 0.0)
	sun.light_color = Color(0.85, 0.92, 1.0)
	sun.light_energy = 0.48
	sun.shadow_enabled = true
	add_child(sun)

	# Luz radiante dourada do lustre de roda de carroça central
	var chandelier_light := OmniLight3D.new()
	chandelier_light.position = Vector3(0.0, 3.1, 0.0)
	chandelier_light.light_color = Color(1.0, 0.82, 0.52)
	chandelier_light.light_energy = 2.4
	chandelier_light.omni_range = 14.0
	chandelier_light.shadow_enabled = true
	add_child(chandelier_light)

	# Fogo da lareira com brilho âmbar profundo e sombras dinâmicas
	var fire_omni := OmniLight3D.new()
	fire_omni.position = Vector3(0.0, 0.65, -3.6)
	fire_omni.light_color = Color(1.0, 0.58, 0.18)
	fire_omni.light_energy = 1.2
	fire_omni.omni_range = 9.0
	fire_omni.shadow_enabled = true
	add_child(fire_omni)

# ==============================================================================
# 2. ARQUITETURA EM TORAS, PISO NOBRE & LUSTRE VAZADO
# ==============================================================================

func _build_room_shell() -> void:
	var mat_floor := _mat("floor", Color("#3b2213"), 0.0, 0.45)
	var mat_log := _mat("log", Color("#331e11"), 0.0, 0.75)
	var mat_chink := _mat("chink", Color("#d5c8b2"), 0.0, 0.9)
	var mat_beam := _mat("beam", Color("#24140a"), 0.0, 0.6)
	var mat_iron := _mat("iron", Color("#151518"), 0.7, 0.3)
	var mat_glass := _mat("glass", Color(0.5, 0.75, 0.95, 0.6), 0.2, 0.1)

	# 1. Piso amplo de tábuas corridas (14m x 9.5m)
	_box(Vector3(0.0, -0.1, 0.0), Vector3(14.0, 0.2, 9.5), mat_floor)

	# Linhas simulando as réguas do piso
	for pz in range(-4, 5):
		_box(Vector3(0.0, 0.005, float(pz)), Vector3(14.0, 0.01, 0.03), _mat("floor_seam", Color("#1b0f07")))

	# 2. Paredes de Toras Horizontais Sobrepostas
	# Parede Norte (Fundos com Lareira)
	for i in 12:
		var ly: float = 0.15 + float(i) * 0.30
		_cyl(Vector3(0.0, ly, -4.6), 0.16, 14.0, mat_log, Vector3(0, 0, 90))
		if i < 11:
			_box(Vector3(0.0, ly + 0.15, -4.6), Vector3(14.0, 0.04, 0.1), mat_chink)

	# Parede Oeste (Lateral Esquerda)
	for i in 12:
		var ly: float = 0.15 + float(i) * 0.30
		_cyl(Vector3(-6.9, ly, 0.0), 0.16, 9.4, mat_log, Vector3(90, 0, 0))

	# Parede Leste (Lateral Direita)
	for i in 12:
		var ly: float = 0.15 + float(i) * 0.30
		_cyl(Vector3(6.9, ly, 0.0), 0.16, 9.4, mat_log, Vector3(90, 0, 0))

	# Parede Sul com corte baixo para a câmera ver o interior sem obstáculos
	for i in 3:
		var ly: float = 0.15 + float(i) * 0.30
		_cyl(Vector3(-4.5, ly, 4.6), 0.16, 5.0, mat_log, Vector3(0, 0, 90))
		_cyl(Vector3(4.5, ly, 4.6), 0.16, 5.0, mat_log, Vector3(0, 0, 90))

	# Vigas Mestras Elevadas junto ao topo das paredes (Y = 3.7m)
	for bx in [-3.8, 3.8]:
		_box(Vector3(bx, 3.7, 0.0), Vector3(0.28, 0.28, 9.4), mat_beam)
		_box(Vector3(bx, 3.7, -4.5), Vector3(0.34, 0.34, 0.15), mat_iron)

	# Janelas Panorâmicas no Norte
	for wx in [-3.8, 3.8]:
		_box(Vector3(wx, 2.0, -4.55), Vector3(1.8, 1.4, 0.15), mat_beam)
		_box(Vector3(wx, 2.0, -4.54), Vector3(1.6, 1.2, 0.04), mat_glass)
		_box(Vector3(wx, 2.0, -4.53), Vector3(0.06, 1.2, 0.06), mat_beam)
		_box(Vector3(wx, 2.0, -4.53), Vector3(1.6, 0.06, 0.06), mat_beam)

	# Lustre Roda de Carroça 3D em Ferro Forjado VAZADO (TorusMesh)
	var mat_brass := _mat("brass", Color("#d4af37"), 0.8, 0.3)
	var mat_edison := _mat("edison", Color(1.0, 0.95, 0.75), 0.0, 0.2, 3.0)

	_torus(Vector3(0.0, 3.2, 0.0), 0.95, 1.05, mat_iron) # Aro de ferro forjado vazado!
	_cyl(Vector3(0.0, 3.2, 0.0), 0.12, 0.1, mat_iron) # Cubo central

	# Raios do aro
	for i in 4:
		var a := TAU * float(i) / 4.0
		_cyl(Vector3(cos(a) * 0.5, 3.2, sin(a) * 0.5), 0.025, 1.0, mat_iron, Vector3(0, -rad_to_deg(a), 90))

	# 6 lâmpadas Edison no aro
	for i in 6:
		var a := TAU * float(i) / 6.0
		var pos_bulb := Vector3(cos(a) * 1.0, 3.25, sin(a) * 1.0)
		_cyl(pos_bulb, 0.04, 0.06, mat_brass)
		_cyl(pos_bulb + Vector3(0, 0.06, 0), 0.03, 0.06, mat_edison)

# ==============================================================================
# 3. LAREIRA MONUMENTAL, FOGÃO DE FERRO FUNDIDO, CHALEIRA & CHAMINÉ 3D
# ==============================================================================

func _build_monumental_fireplace() -> void:
	var mat_stone := _mat("stone", Color("#45423f"), 0.0, 0.85)
	var mat_stone_hi := _mat("stone_hi", Color("#585450"), 0.0, 0.8)
	var mat_cavity := _mat("cavity", Color("#0e0d0c"), 0.0, 0.95)
	var mat_mantel := _mat("mantel", Color("#331e10"), 0.0, 0.5)
	var mat_iron := _mat("iron", Color("#18181a"), 0.7, 0.35)
	var mat_copper := _mat("copper", Color("#b85e2b"), 0.85, 0.25)
	var mat_flame := _mat("flame", Color(1.0, 0.48, 0.10), 0.0, 0.5, 1.0)
	var mat_bone := _mat("bone", Color("#f0e8d5"), 0.0, 0.5)
	var mat_brass := _mat("brass", Color("#d4af37"), 0.8, 0.3)

	# Chaminé e parede de pedras de rio
	_solid_id = &"Fireplace"
	_box(Vector3(0.0, 1.8, -4.2), Vector3(3.2, 3.6, 1.0), mat_stone)
	_box(Vector3(0.0, 0.15, -3.9), Vector3(3.6, 0.3, 1.5), mat_stone_hi)

	# Cavidade interna da lareira
	_box(Vector3(0.0, 0.8, -3.95), Vector3(2.0, 1.2, 0.6), mat_cavity)

	# Viga maciça de carvalho (Mantelpiece)
	_box(Vector3(0.0, 1.55, -3.65), Vector3(3.4, 0.18, 0.4), mat_mantel)

	# Relógio e castiçais de latão com chamas
	_box(Vector3(0.0, 1.74, -3.65), Vector3(0.4, 0.22, 0.15), mat_mantel)
	_box(Vector3(0.0, 1.74, -3.55), Vector3(0.18, 0.18, 0.02), _mat("white", Color("#fafafa")))
	for cx in [-1.2, 1.2]:
		_cyl(Vector3(cx, 1.72, -3.65), 0.05, 0.18, mat_brass)
		_box(Vector3(cx, 1.85, -3.65), Vector3(0.03, 0.06, 0.03), mat_flame)

	# Fogão 3D de Ferro Fundido aberto com fogo visível
	_box(Vector3(-0.45, 0.55, -3.85), Vector3(0.65, 0.7, 0.6), mat_iron)
	_cyl(Vector3(-0.45, 1.15, -3.85), 0.08, 0.6, mat_iron)
	# Chaleira de cobre sobre o fogão
	_cyl(Vector3(-0.45, 0.95, -3.85), 0.14, 0.16, mat_copper)
	_box(Vector3(-0.3, 0.98, -3.85), Vector3(0.12, 0.04, 0.04), mat_copper)

	# Fogo vivo com toras de bétula ardendo no nicho da lareira
	_box(Vector3(0.4, 0.38, -3.8), Vector3(0.6, 0.18, 0.45), mat_flame)
	for lx in [-0.15, 0.0, 0.15]:
		_cyl(Vector3(0.4 + lx, 0.46, -3.8), 0.06, 0.45, _mat("birch", Color("#d5ccbb")), Vector3(0, 0, 90))

	# Cesto de lenha de bétula
	_solid_id = &"LogBasket"
	_box(Vector3(1.9, 0.3, -3.8), Vector3(0.7, 0.5, 0.6), mat_iron)
	for ly in [0.2, 0.35, 0.5]:
		_cyl(Vector3(1.9, ly, -3.8), 0.07, 0.6, _mat("birch", Color("#d5ccbb")), Vector3(90, 0, 0))

	# Galhadas de Cervo 3D na chaminé
	_solid_id = &""
	_box(Vector3(0.0, 2.5, -3.65), Vector3(0.35, 0.45, 0.08), mat_mantel)
	_cyl(Vector3(0.0, 2.5, -3.55), 0.1, 0.15, _mat("deer_fur", Color("#7f5233")), Vector3(90, 0, 0))
	_cyl(Vector3(-0.25, 2.8, -3.55), 0.03, 0.55, mat_bone, Vector3(0, 0, 30))
	_cyl(Vector3(0.25, 2.8, -3.55), 0.03, 0.55, mat_bone, Vector3(0, 0, -30))
	_cyl(Vector3(-0.42, 2.95, -3.55), 0.025, 0.35, mat_bone, Vector3(0, 0, 60))
	_cyl(Vector3(0.42, 2.95, -3.55), 0.025, 0.35, mat_bone, Vector3(0, 0, -60))

# ==============================================================================
# 4. SALA DE ESTAR: SOFÁ CHESTERFIELD 3D, MESA DE TRONCO & URSO
# ==============================================================================

func _build_living_lounge() -> void:
	var mat_leather := _mat("leather_cognac", Color("#502a14"), 0.0, 0.35)
	var mat_leather_dark := _mat("leather_dark", Color("#331a0b"), 0.0, 0.4)
	var mat_plaid := _mat("plaid_red", Color("#8e2820"), 0.0, 0.8)
	var mat_wood_table := _mat("wood_table", Color("#5c3c26"), 0.0, 0.5)
	var mat_bear_fur := _mat("bear_fur", Color("#2d180b"), 0.0, 0.9)
	var mat_bear_snout := _mat("bear_snout", Color("#5c381e"), 0.0, 0.7)
	var mat_paper := _mat("paper", Color("#eee5d3"), 0.0, 0.9)
	var mat_blue_mug := _mat("blue_mug", Color("#2471a3"), 0.0, 0.2)

	# 1. Tapete de Pele de Urso Pardo 3D
	_box(Vector3(0.0, 0.02, -1.2), Vector3(2.6, 0.04, 2.4), mat_bear_fur)
	for pz in [-2.0, -0.4]:
		_box(Vector3(-1.4, 0.02, pz), Vector3(0.6, 0.04, 0.5), mat_bear_fur)
		_box(Vector3(1.4, 0.02, pz), Vector3(0.6, 0.04, 0.5), mat_bear_fur)
	_box(Vector3(0.0, 0.16, -2.4), Vector3(0.4, 0.25, 0.5), mat_bear_fur)
	_box(Vector3(0.0, 0.12, -2.7), Vector3(0.24, 0.18, 0.3), mat_bear_snout)

	# 2. Sofá Chesterfield 3D em Couro Conhaque
	_solid_id = &"Sofa"
	var sofa_pos := Vector3(-2.2, 0.0, -1.2)
	_box(sofa_pos + Vector3(0.0, 0.45, 0.0), Vector3(1.1, 0.4, 2.2), mat_leather)
	_box(sofa_pos + Vector3(-0.45, 0.85, 0.0), Vector3(0.35, 0.8, 2.2), mat_leather_dark)
	_cyl(sofa_pos + Vector3(0.0, 0.75, -1.1), 0.22, 1.1, mat_leather_dark, Vector3(0, 0, 90))
	_cyl(sofa_pos + Vector3(0.0, 0.75, 1.1), 0.22, 1.1, mat_leather_dark, Vector3(0, 0, 90))
	_box(sofa_pos + Vector3(-0.42, 0.95, 0.0), Vector3(0.38, 0.45, 0.7), mat_plaid)

	# 3. Poltrona de Couro Aconchegante
	_solid_id = &"Armchair"
	var chair_pos := Vector3(2.2, 0.0, -1.2)
	_box(chair_pos + Vector3(0.0, 0.45, 0.0), Vector3(1.0, 0.4, 1.1), mat_leather)
	_box(chair_pos + Vector3(0.42, 0.85, 0.0), Vector3(0.3, 0.8, 1.1), mat_leather_dark)
	_cyl(chair_pos + Vector3(0.0, 0.75, -0.55), 0.2, 1.0, mat_leather_dark, Vector3(0, 0, 90))
	_cyl(chair_pos + Vector3(0.0, 0.75, 0.55), 0.2, 1.0, mat_leather_dark, Vector3(0, 0, 90))

	# 4. Mesa de Centro de Tronco Maciço com Pés
	_solid_id = &"CoffeeTable"
	var table_pos := Vector3(0.0, 0.0, -1.2)
	for tx in [-0.65, 0.65]:
		for tz in [-0.4, 0.4]:
			_cyl(table_pos + Vector3(tx, 0.2, tz), 0.06, 0.4, mat_wood_table)
	_box(table_pos + Vector3(0.0, 0.44, 0.0), Vector3(1.6, 0.1, 1.0), mat_wood_table)

	# Mapa, Bússola e Caneca Azul
	_box(table_pos + Vector3(-0.15, 0.50, 0.0), Vector3(0.8, 0.01, 0.55), mat_paper)
	_cyl(table_pos + Vector3(0.35, 0.51, -0.15), 0.08, 0.03, _mat("brass", Color("#d4af37"), 0.8, 0.3))
	_cyl(table_pos + Vector3(0.45, 0.56, 0.2), 0.07, 0.12, mat_blue_mug)

# ==============================================================================
# 5. COZINHA & BAR RÚSTICO DOS CAÇADORES (Noroeste)
# ==============================================================================

func _build_hunter_kitchenette() -> void:
	var mat_slate := _mat("slate", Color("#26292b"), 0.0, 0.3)
	var mat_wood := _mat("wood_counter", Color("#422818"), 0.0, 0.6)
	var mat_leather := _mat("leather_seat", Color("#843f1e"), 0.0, 0.4)
	var mat_bread := _mat("bread", Color("#cda26f"), 0.0, 0.8)
	var mat_amber_glass := _mat("amber_bottle", Color(0.9, 0.5, 0.1, 0.85), 0.1, 0.2)

	_solid_id = &"Counter"
	var bar_pos := Vector3(-4.8, 0.0, -2.8)
	_box(bar_pos + Vector3(0.0, 0.55, 0.0), Vector3(2.4, 1.1, 0.9), mat_wood)
	_box(bar_pos + Vector3(0.0, 1.12, 0.0), Vector3(2.5, 0.08, 1.0), mat_slate)

	_solid_id = &"CounterReturn"
	_box(bar_pos + Vector3(1.0, 0.55, 1.0), Vector3(0.9, 1.1, 1.1), mat_wood)
	_box(bar_pos + Vector3(1.0, 1.12, 1.0), Vector3(1.0, 0.08, 1.2), mat_slate)

	for bz in [-0.3, 0.7]:
		_solid_id = StringName("BarStool" + str(bz))
		var stool_pos := bar_pos + Vector3(1.8, 0.0, bz)
		_cyl(stool_pos + Vector3(0, 0.4, 0), 0.04, 0.8, mat_wood)
		_cyl(stool_pos + Vector3(0, 0.8, 0), 0.22, 0.1, mat_leather)

	_solid_id = &""
	_box(bar_pos + Vector3(-0.4, 1.18, 0.0), Vector3(0.5, 0.04, 0.35), mat_wood)
	_cyl(bar_pos + Vector3(-0.4, 1.25, -0.05), 0.12, 0.26, mat_bread, Vector3(0, 0, 90))

	# Faca de Caça Tática 3D cravada na tábua de corte


	for bx in [0.2, 0.5]:
		_cyl(bar_pos + Vector3(bx, 1.30, 0.1), 0.07, 0.28, mat_amber_glass)

	_box(Vector3(-5.2, 2.2, -4.5), Vector3(2.2, 0.06, 0.3), mat_wood)
	for px in [-5.8, -5.2, -4.6]:
		_cyl(Vector3(px, 2.35, -4.45), 0.06, 0.2, _mat("jar", Color(0.8, 0.2, 0.2, 0.8), 0.1, 0.2))

# ==============================================================================
# 6. QUARTO RÚSTICO & COLCHA PATCHWORK (Sudoeste)
# ==============================================================================

func _build_rustic_bedroom() -> void:
	var mat_pine_log := _mat("pine_log", Color("#382012"), 0.0, 0.7)
	var mat_quilt := _mat("quilt", Color("#842a27"), 0.0, 0.8)
	var mat_quilt_blue := _mat("quilt_blue", Color("#1b3b55"), 0.0, 0.8)
	var mat_quilt_green := _mat("quilt_green", Color("#1a4d2e"), 0.0, 0.8)
	var mat_pillow := _mat("pillow", Color("#f2eee6"), 0.0, 0.9)
	var mat_chest := _mat("chest", Color("#2c1a0e"), 0.0, 0.6)
	var mat_iron := _mat("iron", Color("#18181a"), 0.7, 0.35)

	_solid_id = &"Bed"
	var bed_pos := Vector3(-4.8, 0.0, 1.8)

	for px in [-1.1, 1.1]:
		for pz in [-1.4, 1.4]:
			_cyl(bed_pos + Vector3(px, 0.6, pz), 0.1, 1.2, mat_pine_log)

	_box(bed_pos + Vector3(0.0, 0.35, 0.0), Vector3(2.2, 0.4, 2.7), mat_pine_log)
	_box(bed_pos + Vector3(0.0, 0.65, 0.0), Vector3(2.0, 0.3, 2.5), mat_quilt)

	_box(bed_pos + Vector3(-0.45, 0.81, 0.2), Vector3(0.8, 0.04, 0.8), mat_quilt_blue)
	_box(bed_pos + Vector3(0.45, 0.81, 0.2), Vector3(0.8, 0.04, 0.8), mat_quilt_green)
	_box(bed_pos + Vector3(0.0, 0.81, 0.9), Vector3(1.8, 0.04, 0.5), _mat("throw_wool", Color("#263238")))

	for tx in [-0.5, 0.5]:
		_box(bed_pos + Vector3(tx, 0.88, -0.9), Vector3(0.65, 0.18, 0.45), mat_pillow)

	_solid_id = &"BedsideTable"
	var nightstand_pos := bed_pos + Vector3(1.6, 0.0, -1.0)
	_box(nightstand_pos + Vector3(0.0, 0.35, 0.0), Vector3(0.7, 0.7, 0.6), mat_pine_log)
	_cyl(nightstand_pos + Vector3(0.0, 0.85, 0.0), 0.15, 0.25, _mat("lamp_shade", Color(1.0, 0.9, 0.7), 0.0, 0.5, 1.5))

	var bed_light := OmniLight3D.new()
	bed_light.position = nightstand_pos + Vector3(0, 0.9, 0)
	bed_light.light_color = Color(1.0, 0.82, 0.52)
	bed_light.light_energy = 1.1
	bed_light.omni_range = 3.5
	add_child(bed_light)

	_solid_id = &"Chest"
	var chest_pos := bed_pos + Vector3(0.0, 0.0, 1.8)
	_box(chest_pos + Vector3(0.0, 0.3, 0.0), Vector3(1.4, 0.6, 0.6), mat_chest)
	_box(chest_pos + Vector3(-0.4, 0.3, 0.0), Vector3(0.06, 0.62, 0.62), mat_iron)
	_box(chest_pos + Vector3(0.4, 0.3, 0.0), Vector3(0.06, 0.62, 0.62), mat_iron)

# ==============================================================================
# 7. ESTAÇÃO TÁTICA DO SILAS VANCE & ARMARIA 3D (Leste)
# ==============================================================================

func _build_armory_and_ranger_desk() -> void:
	var mat_desk := _mat("desk", Color("#3d2516"), 0.0, 0.5)
	var mat_radio := _mat("radio", Color("#263238"), 0.5, 0.4)
	var mat_gun_wood := _mat("gun_wood", Color("#5d4037"), 0.0, 0.5)
	var mat_gun_steel := _mat("gun_steel", Color("#212121"), 0.8, 0.25)
	var mat_ammo_green := _mat("ammo_green", Color("#334d28"), 0.3, 0.6)
	var mat_banker_lamp := _mat("banker", Color("#196f3d"), 0.1, 0.3, 2.0)

	_solid_id = &"RangerDesk"
	var desk_pos := Vector3(4.8, 0.0, 0.2)
	_box(desk_pos + Vector3(0.0, 0.45, 0.0), Vector3(1.2, 0.9, 2.2), mat_desk)

	_box(desk_pos + Vector3(-0.2, 1.05, -0.4), Vector3(0.5, 0.35, 0.7), mat_radio)
	_cyl(desk_pos + Vector3(-0.35, 1.4, -0.65), 0.015, 0.8, _mat("antenna", Color("#b0bec5"), 0.9, 0.2))

	_cyl(desk_pos + Vector3(0.2, 0.98, 0.6), 0.09, 0.04, _mat("brass", Color("#d4af37"), 0.8, 0.3))
	_cyl(desk_pos + Vector3(0.2, 1.15, 0.6), 0.08, 0.22, mat_banker_lamp, Vector3(0, 0, 90))

	var desk_light := OmniLight3D.new()
	desk_light.position = desk_pos + Vector3(0.2, 1.15, 0.6)
	desk_light.light_color = Color(0.7, 1.0, 0.6)
	desk_light.light_energy = 1.0
	desk_light.omni_range = 3.0
	add_child(desk_light)

	_box(desk_pos + Vector3(0.1, 0.93, 0.0), Vector3(0.35, 0.04, 0.45), _mat("logbook", Color("#e5dfc7")))
	_box(desk_pos + Vector3(0.1, 0.98, -0.5), Vector3(0.25, 0.1, 0.18), mat_radio)

	# Suporte de Rifles de Caça 3D na Parede Leste (Armaria do Caçador)
	_solid_id = &""
	var gun_pos := Vector3(6.75, 2.0, -2.2)
	_box(gun_pos, Vector3(0.12, 1.25, 1.8), mat_desk)
	# Fundo em veludo nobre bordô
	_box(gun_pos + Vector3(-0.05, 0.0, 0.0), Vector3(0.04, 1.15, 1.68), _mat("rack_velvet", Color("#4a121a"), 0.0, 0.9))

	for gy in [-0.3, 0.0, 0.3]:
		_box(gun_pos + Vector3(-0.08, gy, -0.4), Vector3(0.06, 0.12, 0.5), mat_gun_wood)
		_cyl(gun_pos + Vector3(-0.08, gy + 0.02, 0.2), 0.025, 1.1, mat_gun_steel, Vector3(90, 0, 0))
		_cyl(gun_pos + Vector3(-0.08, gy + 0.08, -0.05), 0.035, 0.35, mat_gun_steel, Vector3(90, 0, 0))


	_solid_id = &"AmmoCrates"
	_box(Vector3(5.5, 0.25, -2.8), Vector3(0.8, 0.5, 0.6), mat_ammo_green)
	_box(Vector3(5.5, 0.6, -2.8), Vector3(0.6, 0.3, 0.5), mat_ammo_green)

# ==============================================================================
# 8. MUDROOM DE ENTRADA, ESQUIS & CABIDEIRO (Sul)
# ==============================================================================

func _build_mudroom_and_entry() -> void:
	var mat_wood := _mat("mud_wood", Color("#331e11"), 0.0, 0.7)
	var mat_ski := _mat("ski_wood", Color("#b9770e"), 0.0, 0.3)
	var mat_parka := _mat("parka_blue", Color("#1b4f72"), 0.0, 0.8)
	var mat_rubber := _mat("rubber", Color("#1b1b1e"), 0.0, 0.9)

	_solid_id = &""
	var mud_pos := Vector3(0.0, 0.0, 3.8)
	_box(mud_pos + Vector3(0, 0.01, 0), Vector3(2.2, 0.02, 1.2), mat_rubber)
	_solid_id = &"EntryDoor"
	_box(mud_pos + Vector3(0, 1.5, 0.7), Vector3(1.6, 2.8, 0.15), mat_wood)

	_solid_id = &"SkiStand"
	_cyl(Vector3(-2.4, 1.4, 4.2), 0.05, 2.6, mat_ski, Vector3(-12, 0, 8))
	_cyl(Vector3(-2.2, 1.4, 4.2), 0.05, 2.6, mat_ski, Vector3(-12, 0, -8))

	_solid_id = &"CoatStand"
	var coat_pos := Vector3(2.2, 0.0, 4.2)
	_cyl(coat_pos + Vector3(0, 1.1, 0), 0.05, 2.2, mat_wood)
	_box(coat_pos + Vector3(0, 1.4, 0), Vector3(0.6, 1.0, 0.35), mat_parka)

