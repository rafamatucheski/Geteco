extends RefCounted
## Shared geometry for equipped weapons and the trunk arsenal.
const POSE = preload("res://gameplay/WeaponPoseData.gd")

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
	var mat_chrome := StandardMaterial3D.new()
	mat_chrome.albedo_color = Color(0.56, 0.60, 0.65)
	mat_chrome.metallic = 0.92
	mat_chrome.roughness = 0.30

	var mat_gunmetal := StandardMaterial3D.new()
	mat_gunmetal.albedo_color = Color(0.18, 0.20, 0.24)
	mat_gunmetal.metallic = 0.85
	mat_gunmetal.roughness = 0.35

	var mat_polymer := StandardMaterial3D.new()
	mat_polymer.albedo_color = Color(0.08, 0.08, 0.10)
	mat_polymer.roughness = 0.70

	var mat_wood := StandardMaterial3D.new()
	mat_wood.albedo_color = Color(0.36, 0.19, 0.10)
	mat_wood.roughness = 0.55

	var mat_brass := StandardMaterial3D.new()
	mat_brass.albedo_color = Color(0.92, 0.78, 0.22)
	mat_brass.metallic = 0.88
	mat_brass.roughness = 0.25

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
			var box_p = BoxMesh.new()
			box_p.size = Vector3(0.052, 0.052, 0.14)
			pump.mesh = box_p
			pump.material_override = mat_wood
			pump.position = Vector3(0.0, -0.01, -0.16)
			root.add_child(pump)

			# 5. Caixa da Culatra (Receptor) com Janela de EjeÃƒÂ§ÃƒÂ£o
			var receiver = MeshInstance3D.new()
			var box_rc = BoxMesh.new()
			box_rc.size = Vector3(0.048, 0.075, 0.16)
			receiver.mesh = box_rc
			receiver.material_override = mat_gunmetal
			receiver.position = Vector3(0.0, 0.01, 0.0)
			root.add_child(receiver)

			# 6. Coronha ClÃƒÂ¡ssica de Madeira com Soleira
			var stock = MeshInstance3D.new()
			var box_s = BoxMesh.new()
			box_s.size = Vector3(0.042, 0.085, 0.20)
			stock.mesh = box_s
			stock.material_override = mat_wood
			stock.position = Vector3(0.0, -0.04, 0.16)
			root.add_child(stock)

			var pad = MeshInstance3D.new()
			var box_pd = BoxMesh.new()
			box_pd.size = Vector3(0.044, 0.090, 0.02)
			pad.mesh = box_pd
			pad.material_override = mat_polymer
			pad.position = Vector3(0.0, -0.04, 0.26)
			root.add_child(pad)

			flash_pos = Vector3(0.0, 0.03, -0.42)

		"sawed_off":
			# Cano Duplo Curto Serrado (Side-by-side)
			var barrel_l = MeshInstance3D.new()
			var cyl_bl = CylinderMesh.new()
			cyl_bl.top_radius = 0.018
			cyl_bl.bottom_radius = 0.018
			cyl_bl.height = 0.22
			barrel_l.mesh = cyl_bl
			barrel_l.material_override = mat_chrome
			barrel_l.rotation_degrees = Vector3(90, 0, 0)
			barrel_l.position = Vector3(-0.018, 0.02, -0.10)
			root.add_child(barrel_l)

			var barrel_r = MeshInstance3D.new()
			var cyl_br = CylinderMesh.new()
			cyl_br.top_radius = 0.018
			cyl_br.bottom_radius = 0.018
			cyl_br.height = 0.22
			barrel_r.mesh = cyl_br
			barrel_r.material_override = mat_chrome
			barrel_r.rotation_degrees = Vector3(90, 0, 0)
			barrel_r.position = Vector3(0.018, 0.02, -0.10)
			root.add_child(barrel_r)

			# Receptor Basculante
			var receiver_so = MeshInstance3D.new()
			var box_rso = BoxMesh.new()
			box_rso.size = Vector3(0.062, 0.065, 0.12)
			receiver_so.mesh = box_rso
			receiver_so.material_override = mat_gunmetal
			receiver_so.position = Vector3(0.0, 0.01, 0.01)
			root.add_child(receiver_so)

			# Cabo Pistola Serrado de Madeira
			var grip_so = MeshInstance3D.new()
			var box_gso = BoxMesh.new()
			box_gso.size = Vector3(0.038, 0.10, 0.06)
			grip_so.mesh = box_gso
			grip_so.material_override = mat_wood
			grip_so.position = Vector3(0.0, -0.05, 0.05)
			grip_so.rotation_degrees = Vector3(-20, 0, 0)
			root.add_child(grip_so)

			flash_pos = Vector3(0.0, 0.02, -0.23)

		"magnum":
			# RevÃƒÂ³lver Magnum .44 com cano longo de 8", nervura superior e tambor
			# Cano de ~4" (13 cm no modelo, ~16 cm no Dante). O de 22 cm, somado à escala
			# V1->V2 do rig, deixava o revólver com comprimento de arma longa vista de cima.
			var barrel_mg = MeshInstance3D.new()
			var box_bmg = BoxMesh.new()
			box_bmg.size = Vector3(0.032, 0.045, 0.13)
			barrel_mg.mesh = box_bmg
			barrel_mg.material_override = mat_chrome
			barrel_mg.position = Vector3(0.0, 0.03, -0.085)
			root.add_child(barrel_mg)

			var front_sight_mg = MeshInstance3D.new()
			var box_fsm = BoxMesh.new()
			box_fsm.size = Vector3(0.012, 0.018, 0.018)
			front_sight_mg.mesh = box_fsm
			front_sight_mg.material_override = mat_brass
			front_sight_mg.position = Vector3(0.0, 0.06, -0.14)
			root.add_child(front_sight_mg)

			# Tambor GiratÃƒÂ³rio
			var cylinder_mg = MeshInstance3D.new()
			cylinder_mg.name = "ReloadCylinder"
			var cyl_mg = CylinderMesh.new()
			cyl_mg.top_radius = 0.028
			cyl_mg.bottom_radius = 0.028
			cyl_mg.height = 0.08
			cylinder_mg.mesh = cyl_mg
			cylinder_mg.material_override = mat_gunmetal
			cylinder_mg.rotation_degrees = Vector3(90, 0, 0)
			cylinder_mg.position = Vector3(0.0, 0.01, 0.0)
			root.add_child(cylinder_mg)

			# Cabo de Madeira Nobre
			var grip_mg = MeshInstance3D.new()
			var box_gmg = BoxMesh.new()
			box_gmg.size = Vector3(0.034, 0.10, 0.055)
			grip_mg.mesh = box_gmg
			grip_mg.material_override = mat_wood
			grip_mg.position = Vector3(0.0, -0.05, 0.03)
			grip_mg.rotation_degrees = Vector3(-18, 0, 0)
			root.add_child(grip_mg)

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
			var box_hg = BoxMesh.new()
			box_hg.size = Vector3(0.048, 0.060, 0.16)
			hguard_ak.mesh = box_hg
			hguard_ak.material_override = mat_wood
			hguard_ak.position = Vector3(0.0, 0.01, -0.15)
			root.add_child(hguard_ak)

			# Receptor de AÃƒÂ§o Estampado
			var receiver_ak = MeshInstance3D.new()
			var box_rak = BoxMesh.new()
			box_rak.size = Vector3(0.046, 0.075, 0.20)
			receiver_ak.mesh = box_rak
			receiver_ak.material_override = mat_gunmetal
			receiver_ak.position = Vector3(0.0, 0.01, 0.0)
			root.add_child(receiver_ak)

			# Carregador Banana Curvo
			preload("res://gameplay/WeaponPresentation3D.gd")._profile(root,"CurvedMagazine",PackedVector2Array([Vector2(-0.083,-0.025),Vector2(-0.025,-0.025),Vector2(-0.022,-0.080),Vector2(-0.032,-0.13),Vector2(-0.065,-0.185),Vector2(-0.115,-0.165),Vector2(-0.084,-0.115),Vector2(-0.078,-0.070)]),0.028,mat_gunmetal)

			# Coronha de Madeira ClÃƒÂ¡ssica
			preload("res://gameplay/WeaponPresentation3D.gd")._profile(root,"ShapedStock",PackedVector2Array([Vector2(0.07,0.016),Vector2(0.15,0.015),Vector2(0.29,0.02),Vector2(0.29,-0.06),Vector2(0.23,-0.056),Vector2(0.14,-0.024),Vector2(0.07,-0.02)]),0.040,mat_wood)

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
			var box_rm4 = BoxMesh.new()
			box_rm4.size = Vector3(0.046, 0.055, 0.16)
			rail_m4.mesh = box_rm4
			rail_m4.material_override = mat_polymer
			rail_m4.position = Vector3(0.0, 0.015, -0.15)
			root.add_child(rail_m4)

			# Receptor Preto com Mira HologrÃƒÂ¡fica
			var receiver_m4 = MeshInstance3D.new()
			var box_rcm4 = BoxMesh.new()
			box_rcm4.size = Vector3(0.046, 0.075, 0.20)
			receiver_m4.mesh = box_rcm4
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
			var mag_m4 = MeshInstance3D.new()
			var box_mm4 = BoxMesh.new()
			box_mm4.size = Vector3(0.026, 0.16, 0.055)
			mag_m4.mesh = box_mm4
			mag_m4.material_override = mat_polymer
			mag_m4.position = Vector3(0.0, -0.10, -0.04)
			mag_m4.rotation_degrees = Vector3(10, 0, 0)
			root.add_child(mag_m4)

			# Coronha TÃƒÂ¡tica RetrÃƒÂ¡til Crane
			var stock_m4 = MeshInstance3D.new()
			var box_sm4 = BoxMesh.new()
			box_sm4.size = Vector3(0.038, 0.080, 0.18)
			stock_m4.mesh = box_sm4
			stock_m4.material_override = mat_polymer
			stock_m4.position = Vector3(0.0, 0.0, 0.16)
			root.add_child(stock_m4)

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
			var cyl_wh = CylinderMesh.new()
			cyl_wh.top_radius = 0.008
			cyl_wh.bottom_radius = 0.056
			cyl_wh.height = 0.18
			warhead.mesh = cyl_wh
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
			var box_grpg = BoxMesh.new()
			box_grpg.size = Vector3(0.032, 0.09, 0.045)
			grip_rpg.mesh = box_grpg
			grip_rpg.material_override = mat_gunmetal
			grip_rpg.position = Vector3(0.0, 0.0, -0.10)
			root.add_child(grip_rpg)
			var support_handle := MeshInstance3D.new()
			support_handle.name = "SupportHandle"
			var support_box := BoxMesh.new()
			support_box.size = Vector3(0.032, 0.09, 0.04)
			support_handle.mesh = support_box
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
			fuel_tank.material_override = _make_mat(Color(0.85, 0.15, 0.12), 0.3)
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
			var grenade_body = MeshInstance3D.new()
			var sph_gn = SphereMesh.new()
			sph_gn.radius = 0.045
			sph_gn.height = 0.09
			grenade_body.mesh = sph_gn
			grenade_body.material_override = _make_mat(Color(0.25, 0.35, 0.18), 0.4)
			grenade_body.position = Vector3(0.0, 0.0, -0.10)
			root.add_child(grenade_body)

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
			var box_r = BoxMesh.new()
			box_r.size = Vector3(0.046, 0.072, 0.24)
			receiver.mesh = box_r
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

			# 3. Carregador Curvo Banana de 30 Tiros
			var mag = MeshInstance3D.new()
			var box_m = BoxMesh.new()
			box_m.size = Vector3(0.028, 0.16, 0.05)
			mag.mesh = box_m
			mag.material_override = mat_polymer
			mag.position = Vector3(0.0, -0.10, -0.07)
			mag.rotation_degrees = Vector3(18, 0, 0)
			root.add_child(mag)

			# 4. Empunhadura e Coronha TÃƒÂ¡tica RebatÃƒÂ­vel Dobrada
			var grip = MeshInstance3D.new()
			var box_gp = BoxMesh.new()
			box_gp.size = Vector3(0.034, 0.09, 0.05)
			grip.mesh = box_gp
			grip.material_override = mat_polymer
			grip.position = Vector3(0.0, -0.05, 0.03)
			grip.rotation_degrees = Vector3(-12, 0, 0)
			root.add_child(grip)

			var wire_stock = MeshInstance3D.new()
			var box_ws = BoxMesh.new()
			box_ws.size = Vector3(0.038, 0.03, 0.14)
			wire_stock.mesh = box_ws
			wire_stock.material_override = mat_chrome
			wire_stock.position = Vector3(0.0, 0.03, 0.12)
			root.add_child(wire_stock)

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
