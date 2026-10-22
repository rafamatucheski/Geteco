extends RefCounted
## Shared geometry for equipped weapons and the trunk arsenal.
const POSE = preload("res://gameplay/WeaponPoseData.gd")
const GEO := preload("res://gameplay/WeaponPresentation3D.gd")
const SURFACES := preload("res://assets/urban_detail/UrbanSurfaces.gd")

## Materiais de arma com textura (veio da madeira, metal escovado) em vez de cor chapada.
## O UV triplanar fica no espaço do OBJETO: o de mundo, usado na cidade, faria a textura
## "nadar" quando a arma se move na mão. `tile` em metros do modelo (armas têm ~0.1-0.8 m).
static var _textured_cache: Dictionary = {}

static func _textured(kind: String, color: Color, roughness: float, metallic: float, tile: float) -> StandardMaterial3D:
	var key := "arsenal_%s_%s_%.2f_%.2f" % [kind, color.to_html(false), roughness, metallic]
	if _textured_cache.has(key):
		return _textured_cache[key]
	var mat := SURFACES.material(key, kind, color, roughness, metallic, tile, 0.6).duplicate() as StandardMaterial3D
	mat.uv1_world_triplanar = false
	mat.uv1_scale = Vector3.ONE / tile
	_textured_cache[key] = mat
	return mat

static func _make_mat(col: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = col
	material.roughness = roughness
	return material

## build() leva 16-22 ms por chamada (medido em tests/measure/probe_police_model_cost.gd)
## e é chamado por cada policial e por cada loot de arma. A arma é montada uma vez por
## id e copiada; duplicate() compartilha malhas e materiais entre as cópias.
static var _templates: Dictionary = {}

# Retencao global ate o root sair; worlds/transicoes conservam os templates.
static func _watch_template_shutdown() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and not tree.root.tree_exiting.is_connected(_release_templates):
		tree.root.tree_exiting.connect(_release_templates, CONNECT_ONE_SHOT)

static func _release_templates() -> void:
	for entry in _templates.values():
		var node: Node = entry.node
		if is_instance_valid(node) and node.get_parent() == null: node.free()
	_templates.clear()

## Modelos-padrão de todas as armas montados sob a cortina (21/10): com GETECO_WEAPON_TEMPLATE a mão
## usa build_cached, e a primeira vez que o jogador puxa cada arma deixava de montar no quadro só se o
## modelo já existisse. Um quadro entre armas para a tela de carregamento andar. Katana tem modelo próprio.
static func warm_templates(tree: SceneTree, ids: Array) -> void:
	for id in ids:
		var key := str(id)
		if key == "katana" or key == "fists" or _templates.has(key): continue
		var template := Node3D.new()
		_templates[key] = {"node": template, "tip": build(template, key)}
		_watch_template_shutdown()
		await tree.process_frame

static func build_cached(root: Node3D, id: String) -> Vector3:
	if not _templates.has(id):
		var template := Node3D.new()
		_templates[id] = {"node": template, "tip": build(template, id)}
		_watch_template_shutdown()
	var entry: Dictionary = _templates[id]
	for child in (entry.node as Node3D).get_children():
		root.add_child(child.duplicate())
	return entry.tip

static func build(root: Node3D, id: String) -> Vector3:
	if id == "katana": return preload("res://gameplay/KatanaModel.gd").build(root)
	var mat_chrome := _textured("metal", Color(0.56, 0.60, 0.65), 0.32, 0.72, 0.18)
	var mat_gunmetal := _textured("metal", Color(0.18, 0.20, 0.24), 0.40, 0.62, 0.18)

	var mat_polymer := GEO._mat(Color("25282c"), 0.0, 0.70)

	var mat_wood := _textured("wood", Color(0.36, 0.19, 0.10), 0.55, 0.0, 0.30)

	var mat_brass := GEO._mat(Color("b8a16a"), 0.72, 0.38)

	var flash_pos := Vector3(0.0, 0.0, -0.15)

	match id:
		"shotgun":
			# 1. Cano Principal Superior de AÃƒÂ§o
			var barrel = MeshInstance3D.new()
			var cyl_b = CylinderMesh.new()
			cyl_b.top_radius = 0.020
			cyl_b.bottom_radius = 0.020
			cyl_b.height = 0.44
			barrel.mesh = cyl_b
			barrel.material_override = mat_chrome
			barrel.rotation_degrees = Vector3(90, 0, 0)
			barrel.position = Vector3(0.0, 0.03, -0.18)
			root.add_child(barrel)

			# 2. Tubo do Carregador Inferior
			var mag_tube = MeshInstance3D.new()
			var cyl_mt = CylinderMesh.new()
			cyl_mt.top_radius = 0.016
			cyl_mt.bottom_radius = 0.016
			cyl_mt.height = 0.32
			mag_tube.mesh = cyl_mt
			mag_tube.material_override = mat_gunmetal
			mag_tube.rotation_degrees = Vector3(90, 0, 0)
			mag_tube.position = Vector3(0.0, -0.01, -0.12)
			root.add_child(mag_tube)

			# 3. AbraÃƒÂ§adeira do Cano / Mira de Esfera Dourada
			var band = MeshInstance3D.new()
			var box_bd = BoxMesh.new()
			box_bd.size = Vector3(0.045, 0.065, 0.02)
			band.mesh = box_bd
			band.material_override = mat_gunmetal
			band.position = Vector3(0.0, 0.01, -0.34)
			root.add_child(band)

			var front_bead = MeshInstance3D.new()
			var sph_bd = SphereMesh.new()
			sph_bd.radius = 0.012
			sph_bd.height = 0.024
			front_bead.mesh = sph_bd
			front_bead.material_override = mat_brass
			front_bead.position = Vector3(0.0, 0.055, -0.38)
			root.add_child(front_bead)

			# 4. Telha de Bombeamento Estriada de Madeira
			var pump = MeshInstance3D.new()
			pump.name = "Pump"
			var box_p := Vector3(0.052, 0.052, 0.14)
			pump.mesh = GEO.section_mesh(box_p, .009)
			pump.material_override = mat_wood
			pump.position = Vector3(0.0, -0.01, -0.16)
			root.add_child(pump)

			# 5. Caixa da Culatra (Receptor) com Janela de EjeÃƒÂ§ÃƒÂ£o
			var receiver = MeshInstance3D.new()
			var box_rc := Vector3(0.048, 0.075, 0.16)
			receiver.mesh = GEO.section_mesh(box_rc, .008)
			receiver.material_override = mat_gunmetal
			receiver.position = Vector3(0.0, 0.01, 0.0)
			root.add_child(receiver)

			# 6. Coronha ClÃƒÂ¡ssica de Madeira com Soleira
			GEO._stock_profile(root, "WalnutShoulderStock", PackedVector2Array([
				Vector2(.06,-.018),Vector2(.105,-.007),Vector2(.17,.0025),
				Vector2(.26,-.004),Vector2(.26,-.0825),Vector2(.19,-.078),
				Vector2(.12,-.050),Vector2(.06,-.054)]), .042, mat_wood)

			var pad = MeshInstance3D.new()
			var box_pd = BoxMesh.new()
			box_pd.size = Vector3(0.044, 0.090, 0.02)
			pad.mesh = box_pd
			pad.material_override = mat_polymer
			pad.position = Vector3(0.0, -0.04, 0.26)
			root.add_child(pad)

			flash_pos = Vector3(0.0, 0.03, -0.42)

		"sawed_off":
			flash_pos = preload("res://gameplay/SawedOffPresentation.gd").build(root)

		"magnum":
			# RevÃƒÂ³lver Magnum .44 com cano longo de 8", nervura superior e tambor
			# Cano de ~4" (13 cm no modelo, ~16 cm no Dante). O de 22 cm, somado à escala
			# V1->V2 do rig, deixava o revólver com comprimento de arma longa vista de cima.
			var geo := preload("res://gameplay/WeaponPresentation3D.gd")
			# Cano redondo com nervura, luva do extrator por baixo e armação atrás do tambor,
			# em vez do bloco único que lia como pistola de caixa.
			geo._cylinder(root, "Barrel", Vector3(0.0, 0.030, -0.105), 0.0145, 0.13, mat_chrome, Vector3(90, 0, 0))
			geo._box(root, "BarrelRib", Vector3(0.0, 0.0475, -0.105), Vector3(0.010, 0.006, 0.13), mat_chrome)
			geo._cylinder(root, "EjectorShroud", Vector3(0.0, 0.008, -0.095), 0.0105, 0.09, mat_gunmetal, Vector3(90, 0, 0))
			geo._box(root, "FrontSight", Vector3(0.0, 0.058, -0.162), Vector3(0.008, 0.016, 0.014), mat_brass)
			geo._box(root, "TopStrap", Vector3(0.0, 0.0445, 0.002), Vector3(0.026, 0.013, 0.100), mat_gunmetal)
			geo._box(root, "FrameFront", Vector3(0.0, 0.018, -0.056), Vector3(0.030, 0.050, 0.028), mat_gunmetal)
			geo._box(root, "FrameRear", Vector3(0.0, 0.014, 0.052), Vector3(0.032, 0.060, 0.044), mat_gunmetal)
			geo._box(root, "RearSight", Vector3(0.0, 0.054, 0.034), Vector3(0.014, 0.008, 0.012), mat_gunmetal)

			# Tambor Giratório (nó animado na recarga: mantém nome e eixo)
			var cylinder_mg = MeshInstance3D.new()
			cylinder_mg.name = "ReloadCylinder"
			cylinder_mg.mesh = _fluted_drum_mesh()
			# Aço claro e pouco metálico: com metal alto o tambor refletia o ambiente escuro e
			# sumia contra a armação de gunmetal na vista lateral.
			var mat_drum := StandardMaterial3D.new()
			mat_drum.albedo_color = Color(0.64, 0.67, 0.72)
			mat_drum.metallic = 0.55
			mat_drum.roughness = 0.38
			cylinder_mg.material_override = mat_drum
			cylinder_mg.rotation_degrees = Vector3(90, 0, 0)
			cylinder_mg.position = Vector3(0.0, 0.01, 0.0)
			root.add_child(cylinder_mg)

			# Cabo de madeira com perfil inclinado para trás (substitui a caixa inclinada)
			geo._profile(root, "Grip", PackedVector2Array([Vector2(0.050,0.022),Vector2(-0.023,0.0),Vector2(0.005,-0.115),Vector2(0.073,-0.108),Vector2(0.067,-0.045),Vector2(0.059,-0.010)]), 0.031, mat_wood)

			flash_pos = Vector3(0.0, 0.03, -0.165)

		"ak47":
			# Fuzil AK-47 com madeira clÃƒÂ¡ssica, quebra-chamas e carregador curvo
			var barrel_ak = MeshInstance3D.new()
			var cyl_ak = CylinderMesh.new()
			cyl_ak.top_radius = 0.015
			cyl_ak.bottom_radius = 0.015
			cyl_ak.height = 0.36
			barrel_ak.mesh = cyl_ak
			barrel_ak.material_override = mat_chrome
			barrel_ak.rotation_degrees = Vector3(90, 0, 0)
			barrel_ak.position = Vector3(0.0, 0.02, -0.22)
			root.add_child(barrel_ak)

			# Guarda-mÃƒÂ£o de Madeira
			var hguard_ak = MeshInstance3D.new()
			var box_hg := Vector3(0.048, 0.060, 0.16)
			hguard_ak.mesh = GEO.section_mesh(box_hg, .009)
			hguard_ak.material_override = mat_wood
			hguard_ak.position = Vector3(0.0, 0.01, -0.15)
			root.add_child(hguard_ak)

			# Receptor de AÃƒÂ§o Estampado
			var receiver_ak = MeshInstance3D.new()
			var box_rak := Vector3(0.046, 0.075, 0.20)
			receiver_ak.mesh = GEO.section_mesh(box_rak, .010)
			receiver_ak.material_override = mat_gunmetal
			receiver_ak.position = Vector3(0.0, 0.01, 0.0)
			root.add_child(receiver_ak)

			# Carregador Banana Curvo
			preload("res://gameplay/WeaponPresentation3D.gd")._profile(root,"CurvedMagazine",PackedVector2Array([Vector2(-0.083,-0.025),Vector2(-0.025,-0.025),Vector2(-0.022,-0.080),Vector2(-0.032,-0.13),Vector2(-0.065,-0.185),Vector2(-0.115,-0.165),Vector2(-0.084,-0.115),Vector2(-0.078,-0.070)]),0.028,mat_gunmetal)

			# Coronha de Madeira ClÃƒÂ¡ssica
			GEO._stock_profile(root,"ShapedStock",PackedVector2Array([Vector2(0.07,0.016),Vector2(0.15,0.015),Vector2(0.29,0.02),Vector2(0.29,-0.06),Vector2(0.23,-0.056),Vector2(0.14,-0.024),Vector2(0.07,-0.02)]),0.040,mat_wood)

			flash_pos = Vector3(0.0, 0.02, -0.42)

		"m4a1":
			# Fuzil M4A1 TÃƒÂ¡tico Militar com Mira HologrÃƒÂ¡fica
			var barrel_m4 = MeshInstance3D.new()
			var cyl_m4 = CylinderMesh.new()
			cyl_m4.top_radius = 0.015
			cyl_m4.bottom_radius = 0.015
			cyl_m4.height = 0.34
			barrel_m4.mesh = cyl_m4
			barrel_m4.material_override = mat_chrome
			barrel_m4.rotation_degrees = Vector3(90, 0, 0)
			barrel_m4.position = Vector3(0.0, 0.02, -0.22)
			root.add_child(barrel_m4)

			# Guarda-mÃƒÂ£o Quad-Rail Preto
			var rail_m4 = MeshInstance3D.new()
			var box_rm4 := Vector3(0.046, 0.055, 0.16)
			rail_m4.mesh = GEO.section_mesh(box_rm4, .010)
			rail_m4.material_override = mat_polymer
			rail_m4.position = Vector3(0.0, 0.015, -0.15)
			root.add_child(rail_m4)

			# Receptor Preto com Mira HologrÃƒÂ¡fica
			var receiver_m4 = MeshInstance3D.new()
			var box_rcm4 := Vector3(0.046, 0.075, 0.20)
			receiver_m4.mesh = GEO.section_mesh(box_rcm4, .010)
			receiver_m4.material_override = mat_gunmetal
			receiver_m4.position = Vector3(0.0, 0.01, 0.0)
			root.add_child(receiver_m4)

			var holo_sight = MeshInstance3D.new()
			var box_hs = BoxMesh.new()
			box_hs.size = Vector3(0.035, 0.035, 0.07)
			holo_sight.mesh = box_hs
			holo_sight.material_override = mat_polymer
			holo_sight.position = Vector3(0.0, 0.065, -0.02)
			root.add_child(holo_sight)

			# Carregador STANAG 30 Tiros
			GEO._profile(root, "STANAGMagazine", PackedVector2Array([
				Vector2(-.069,-.020),Vector2(-.014,-.020),Vector2(-.015,-.095),
				Vector2(-.029,-.176),Vector2(-.058,-.183),Vector2(-.083,-.164),
				Vector2(-.074,-.092)]), .026, mat_polymer)

			# Coronha TÃƒÂ¡tica RetrÃƒÂ¡til Crane
			GEO._profile(root, "RetractableStock", PackedVector2Array([
				Vector2(.07,.016),Vector2(.14,.016),Vector2(.17,.040),
				Vector2(.25,.040),Vector2(.25,-.040),Vector2(.205,-.040),
				Vector2(.16,-.018),Vector2(.07,-.016)]), .038, mat_polymer)

			flash_pos = Vector3(0.0, 0.02, -0.40)

		"hunting_rifle":
			preload("res://gameplay/WeaponPresentation3D.gd").build(root, "hunting_rifle")
			flash_pos = Vector3(0, 0.055, -0.59)

		"rpg":
			# LanÃƒÂ§a-Foguetes RPG-7 apoiado diretamente sobre o ombro direito
			var launcher_tube = MeshInstance3D.new()
			var cyl_tube = CylinderMesh.new()
			cyl_tube.top_radius = 0.034
			cyl_tube.bottom_radius = 0.034
			cyl_tube.height = 0.74
			launcher_tube.mesh = cyl_tube
			launcher_tube.material_override = _make_mat(Color(0.22, 0.28, 0.18), 0.4)
			launcher_tube.rotation_degrees = Vector3(90, 0, 0)
			launcher_tube.position = Vector3(0.0, 0.08, 0.05)
			root.add_child(launcher_tube)

			# Cone Exaustor Traseiro
			var exhaust = MeshInstance3D.new()
			var cyl_ex = CylinderMesh.new()
			cyl_ex.top_radius = 0.048
			cyl_ex.bottom_radius = 0.034
			cyl_ex.height = 0.12
			exhaust.mesh = cyl_ex
			exhaust.material_override = mat_gunmetal
			exhaust.rotation_degrees = Vector3(90, 0, 0)
			exhaust.position = Vector3(0.0, 0.08, 0.44)
			root.add_child(exhaust)

			# Ogiva CÃƒÂ´nica RPG Frontal
			var warhead = MeshInstance3D.new()
			warhead.name = "LoadedRocket"
			warhead.mesh = _rocket_mesh()
			warhead.material_override = _make_mat(Color(0.32, 0.42, 0.20), 0.3)
			warhead.rotation_degrees = Vector3(-90, 0, 0)
			warhead.position = Vector3(0.0, 0.08, -0.40)
			root.add_child(warhead)

			# Escudo TÃƒÂ©rmico de Madeira
			var shield_rpg = MeshInstance3D.new()
			var cyl_sh = CylinderMesh.new()
			cyl_sh.top_radius = 0.042
			cyl_sh.bottom_radius = 0.042
			cyl_sh.height = 0.24
			shield_rpg.mesh = cyl_sh
			shield_rpg.material_override = mat_wood
			shield_rpg.rotation_degrees = Vector3(90, 0, 0)
			shield_rpg.position = Vector3(0.0, 0.08, 0.0)
			root.add_child(shield_rpg)

			# Empunhadura e Gatilho do RPG
			var grip_rpg = MeshInstance3D.new()
			var box_grpg := Vector3(0.032, 0.09, 0.045)
			grip_rpg.mesh = GEO.section_mesh(box_grpg, .005)
			grip_rpg.material_override = mat_gunmetal
			grip_rpg.position = Vector3(0.0, 0.0, -0.10)
			root.add_child(grip_rpg)
			var support_handle := MeshInstance3D.new()
			support_handle.name = "SupportHandle"
			var support_box := Vector3(0.032, 0.09, 0.04)
			support_handle.mesh = GEO.section_mesh(support_box, .005)
			support_handle.position = Vector3(0, 0, -0.22)
			support_handle.material_override = mat_wood
			root.add_child(support_handle)

			flash_pos = Vector3(0.0, 0.08, -0.50)

		"flamethrower":
			# LanÃƒÂ§a-Chamas com Bico LanÃƒÂ§a-Jato e Garrafa de CombustÃƒÂ­vel
			var flame_tube = MeshInstance3D.new()
			var cyl_ft = CylinderMesh.new()
			cyl_ft.top_radius = 0.024
			cyl_ft.bottom_radius = 0.024
			cyl_ft.height = 0.42
			flame_tube.mesh = cyl_ft
			flame_tube.material_override = mat_gunmetal
			flame_tube.rotation_degrees = Vector3(90, 0, 0)
			flame_tube.position = Vector3(0.0, 0.02, -0.16)
			root.add_child(flame_tube)

			# BotijÃƒÂ£o de CombustÃƒÂ­vel Vermelho no Corpo da Arma
			var fuel_tank = MeshInstance3D.new()
			var cyl_tk = CylinderMesh.new()
			cyl_tk.top_radius = 0.045
			cyl_tk.bottom_radius = 0.045
			cyl_tk.height = 0.16
			fuel_tank.mesh = cyl_tk
			fuel_tank.material_override = GEO._mat(Color("993f32"), 0.28, 0.52)
			fuel_tank.rotation_degrees = Vector3(90, 0, 0)
			fuel_tank.position = Vector3(0.075, -0.045, -0.06)
			root.add_child(fuel_tank)
			var geometry := preload("res://gameplay/WeaponPresentation3D.gd")
			geometry._box(root, "TankBracket", Vector3(0.037, -0.03, -0.06), Vector3(0.08, 0.022, 0.06), mat_gunmetal)
			geometry._cylinder(root, "FuelValve", Vector3(0.075, -0.045, -0.155), 0.017, 0.035, mat_brass, Vector3(90,0,0))
			geometry._box(root, "SupportHandle", Vector3(0, -0.055, -0.14), Vector3(0.032, 0.105, 0.04), mat_polymer)
			geometry._cylinder(root, "NozzleShroud", Vector3(0, 0.02, -0.35), 0.034, 0.085, mat_gunmetal, Vector3(90,0,0))
			geometry._cylinder(root, "NozzleBore", Vector3(0, 0.02, -0.394), 0.020, 0.003, mat_polymer, Vector3(90,0,0))
			geometry._cylinder(root, "Igniter", Vector3(0, -0.018, -0.36), 0.008, 0.075, mat_brass, Vector3(90,0,0))
			geometry._trigger_guard(root, Vector3(0, -0.02, -0.015), mat_gunmetal)

			flash_pos = Vector3(0.0, 0.02, -0.40)

		"grenade":
			# Granada de MÃƒÂ£o de FragmentaÃƒÂ§ÃƒÂ£o Tipo Abacaxi
			preload("res://gameplay/WeaponPresentation3D.gd")._pineapple(root, "GrenadeBody", Vector3(0.0, 0.0, -0.10), 0.047, _make_mat(Color(0.25, 0.35, 0.18), 0.4))

			var pin = MeshInstance3D.new()
			var cyl_pn = CylinderMesh.new()
			cyl_pn.top_radius = 0.015
			cyl_pn.bottom_radius = 0.015
			cyl_pn.height = 0.03
			pin.mesh = cyl_pn
			pin.material_override = mat_brass
			pin.position = Vector3(0.0, 0.055, -0.10)
			root.add_child(pin)

			flash_pos = Vector3(0.0, 0.0, -0.12)

		"smg", "micro_smg":
			# 1. Receptor TÃƒÂ¡tico com Trilho Superior
			var receiver = MeshInstance3D.new()
			var box_r := Vector3(0.046, 0.072, 0.24)
			receiver.mesh = GEO.section_mesh(box_r, .011)
			receiver.material_override = mat_gunmetal
			receiver.position = Vector3(0.0, 0.01, -0.06)
			root.add_child(receiver)

			var rail = MeshInstance3D.new()
			var box_rl = BoxMesh.new()
			box_rl.size = Vector3(0.035, 0.015, 0.18)
			rail.mesh = box_rl
			rail.material_override = mat_polymer
			rail.position = Vector3(0.0, 0.052, -0.06)
			root.add_child(rail)

			# 2. Cano com Quebra-Chamas / Compensador TÃƒÂ¡tico
			var barrel = MeshInstance3D.new()
			var cyl_smg = CylinderMesh.new()
			cyl_smg.top_radius = 0.016
			cyl_smg.bottom_radius = 0.016
			cyl_smg.height = 0.16
			barrel.mesh = cyl_smg
			barrel.material_override = mat_chrome
			barrel.rotation_degrees = Vector3(90, 0, 0)
			barrel.position = Vector3(0.0, 0.01, -0.24)
			root.add_child(barrel)

			var comp = MeshInstance3D.new()
			var cyl_cp = CylinderMesh.new()
			cyl_cp.top_radius = 0.022
			cyl_cp.bottom_radius = 0.022
			cyl_cp.height = 0.05
			comp.mesh = cyl_cp
			comp.material_override = mat_gunmetal
			comp.rotation_degrees = Vector3(90, 0, 0)
			comp.position = Vector3(0.0, 0.01, -0.32)
			root.add_child(comp)

			GEO._profile(root, "ContouredForeEnd", PackedVector2Array([
				Vector2(-.230,.025),Vector2(-.128,.025),Vector2(-.120,-.025),
				Vector2(-.205,-.029),Vector2(-.231,-.010)]), .050, mat_polymer)

			# 3. Carregador Curvo Banana de 30 Tiros
			var geo_smg := preload("res://gameplay/WeaponPresentation3D.gd")
			geo_smg._profile(root, "Magazine", PackedVector2Array([Vector2(-0.045,-0.030),Vector2(-0.095,-0.030),Vector2(-0.108,-0.090),Vector2(-0.128,-0.190),Vector2(-0.075,-0.195),Vector2(-0.058,-0.100)]), 0.028, mat_polymer)

			# 4. Empunhadura e coronha de arame rebatível
			var grip = MeshInstance3D.new()
			var box_gp := Vector3(0.034, 0.09, 0.05)
			grip.mesh = GEO.section_mesh(box_gp, .005)
			grip.material_override = mat_polymer
			grip.position = Vector3(0.0, -0.05, 0.03)
			grip.rotation_degrees = Vector3(-12, 0, 0)
			root.add_child(grip)

			for side in [-1.0, 1.0]:
				geo_smg._cylinder(root, "WireStockRod", Vector3(side * 0.017, 0.03, 0.125), 0.0042, 0.13, mat_chrome, Vector3(90, 0, 0))
			geo_smg._box(root, "WireStockBrace", Vector3(0.0, 0.03, 0.188), Vector3(0.040, 0.012, 0.008), mat_chrome)
			geo_smg._box(root, "WireStockStrut", Vector3(0.0, 0.0, 0.189), Vector3(0.006, 0.060, 0.006), mat_chrome)

			flash_pos = Vector3(0.0, 0.01, -0.36)

		"fists":
			# Maos livres: nao adiciona nenhuma peca ao suporte da arma. root
			# ja e' um Node3D vazio criado acima, entao o jogador simplesmente nao
			# segura nada -- isso e' o que resolve "so tem arma equipada, sumiu o soco".
			pass

		"knife", "axe", "knuckles", "bat":
			preload("res://gameplay/WeaponPresentation3D.gd").build(root, id)
			flash_pos = Vector3(0, 0, -0.235)

		_: # pistol
			preload("res://gameplay/WeaponPresentation3D.gd").build(root, "pistol")
			flash_pos = Vector3(0, 0.055, -0.15)

	# These models had receivers but no firing-hand handle.
	if id in ["ak47", "m4a1", "flamethrower"]:
		var handle := MeshInstance3D.new()
		handle.name = "FiringGrip"
		var handle_mesh := BoxMesh.new()
		handle_mesh.size = Vector3(0.034, 0.09, 0.045)
		handle.mesh = handle_mesh
		handle.position = POSE.GRIPS[id]
		handle.material_override = mat_polymer
		root.add_child(handle)

	preload("res://gameplay/WeaponFinish3D.gd").apply(root, id, flash_pos)
	return flash_pos

## Ogive with shoulder and neck, preserving LoadedRocket's local Y extents.
## The reload rig rotates/translates that MeshInstance as one piece.
static var _rocket_body_mesh: ArrayMesh
static func _rocket_mesh() -> ArrayMesh:
	if _rocket_body_mesh != null: return _rocket_body_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var profile := PackedVector2Array([
		Vector2(-.09,.023),Vector2(-.075,.045),Vector2(-.052,.056),
		Vector2(-.025,.056),Vector2(.025,.036),Vector2(.070,.015),Vector2(.09,.008)])
	var segments := 16
	for ring in profile.size()-1:
		for side in segments:
			var a := TAU*side/segments
			var b := TAU*(side+1)/segments
			var first := profile[ring]
			var second := profile[ring+1]
			var points := [Vector3(cos(a)*first.y,first.x,sin(a)*first.y),Vector3(cos(b)*first.y,first.x,sin(b)*first.y),Vector3(cos(b)*second.y,second.x,sin(b)*second.y),Vector3(cos(a)*second.y,second.x,sin(a)*second.y)]
			for k in [0,1,2,0,2,3]: st.add_vertex(points[k])
	for end in [0,profile.size()-1]:
		var row := profile[end]
		for side in segments:
			var a := TAU*side/segments
			var b := TAU*(side+1)/segments
			var points := [Vector3(0,row.x,0),Vector3(cos(a)*row.y,row.x,sin(a)*row.y),Vector3(cos(b)*row.y,row.x,sin(b)*row.y)]
			for k in ([0,2,1] if end == 0 else [0,1,2]): st.add_vertex(points[k])
	st.generate_normals()
	_rocket_body_mesh = st.commit()
	return _rocket_body_mesh

## Six broad cylinder flutes are geometry, so they remain readable from either
## side and rotate with the real reload cylinder. Same .028 radius/.08 length.
static var _revolver_drum_mesh: ArrayMesh
static func _fluted_drum_mesh() -> ArrayMesh:
	if _revolver_drum_mesh != null: return _revolver_drum_mesh
	var ring := PackedVector2Array()
	for flute in 6:
		for step in 6:
			var angle := TAU * (float(flute) + float(step)/6.0) / 6.0
			var radius := .025 if step in [2,3] else .028
			ring.append(Vector2(cos(angle),sin(angle))*radius)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i+1)%ring.size()]
		st.set_normal(Vector3(b.y-a.y,0,a.x-b.x).normalized())
		var points := [Vector3(a.x,-.04,a.y),Vector3(b.x,-.04,b.y),Vector3(b.x,.04,b.y),Vector3(a.x,.04,a.y)]
		for k in [0,1,2,0,2,3]: st.add_vertex(points[k])
		for side in [-1.0,1.0]:
			st.set_normal(Vector3(0,side,0))
			var cap := [Vector3(0,side*.04,0),Vector3(a.x,side*.04,a.y),Vector3(b.x,side*.04,b.y)]
			for k in ([0,2,1] if side < 0.0 else [0,1,2]): st.add_vertex(cap[k])
	_revolver_drum_mesh = st.commit()
	return _revolver_drum_mesh
