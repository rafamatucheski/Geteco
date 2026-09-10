class_name MountainSceneryBuilder
extends RefCounted

## Construtor de Cenografia e Detalhamento da Montanha (MountainPass):
## - Baia oceanica profunda com rebentacao e orla rochosa
## - Curvas de nivel topograficas e encostas de montanha naturais
## - Rede de estradinhas de terra da serra conectando os vales
## - Floresta densa de pinheiros alpinos (MountainPineTree)
## - Serraria autentica com galpao de cedro, toras, fogueira e serragem
## - Lago alpino turquesa cristalino com corredeiras e ponte suspensa
## - Chales Alpinos com chamine de pedra, varanda, lenha e interiores jogaveis
## - Loja Ammu-Nation de Montanha com estacionamento, estande de tiro e armeiro
## - Esconderijo dos contrabandistas em caverna com caixas de armas militares
## - Mirante da serra com balcao de pedra, binoculo panoramico e vista da cidade
## - Base militar no cume: rotatoria asfaltada, bunker, heliponto [H], torre e radar

const PINE_SCRIPT := preload("res://world/mountain_pass/MountainPine3D.gd")
const ROCK_SCRIPT := preload("res://world/shared/nature/ProceduralUrbanRock.gd")
const ENTRANCE_SCENE: PackedScene = preload("res://scripts/entrances/BuildingEntrance.tscn")
const PICKUP_SCRIPT := preload("res://world/mountain_pass/MountainPickup.gd")
const ARCTIC_JEEP_SCRIPT := preload("res://world/mountain_pass/ArcticJeep.gd")

# Curvas das 3 estradinhas de terra
static var dirt_road_curves: Array[Curve2D] = []

static func build_streamed_scenery(root_node: Node2D) -> void:
	var scenery := Node2D.new()
	scenery.name = "MountainSceneryDetailed"
	root_node.add_child(scenery)
	var road := root_node.get_node("MountainPassRoad")
	var pieces := root_node.get_node("Setpieces")
	var interiors := root_node.get_node("MountainInteriorManager")
	_init_dirt_roads()
	var jobs: Array[Callable] = [
		build_mountain_base_terrain.bind(scenery), build_backcountry_dirt_roads.bind(scenery),
		build_rocky_cliffs_and_ridges.bind(scenery, road), build_lake_and_rapids.bind(scenery),
		build_secret_mountain_lake.bind(scenery, pieces), build_mountain_chalets.bind(scenery, pieces, interiors),
		build_mountain_ammunation.bind(scenery, pieces, interiors), build_dense_pine_forest.bind(scenery, road, true),
		build_road_signage_and_chevrons.bind(scenery), build_detailed_sawmill.bind(pieces.get_node("LoggingCamp")),
		build_detailed_footbridge.bind(pieces.get_node("GorgeneckFootbridge")), build_detailed_cave_cache.bind(pieces.get_node("CaveCache")),
		build_detailed_overlook.bind(pieces.get_node("ScenicOverlookArea")), build_detailed_bunker.bind(pieces.get_node("AltitudeOutpostBunker"))]
	for job in jobs:
		if not is_instance_valid(root_node) or not root_node.is_inside_tree():
			return
		await job.call()
		if not is_instance_valid(root_node) or not root_node.is_inside_tree():
			return
		await root_node.get_tree().process_frame

static func build_full_scenery(root_node: Node2D) -> void:
	var scenery_root := Node2D.new()
	scenery_root.name = "MountainSceneryDetailed"
	root_node.add_child(scenery_root)

	var road: MountainPassRoad = root_node.get_node_or_null("MountainPassRoad") as MountainPassRoad
	var setpieces: Node2D = root_node.get_node_or_null("Setpieces")
	var interior_mgr = root_node.get_node_or_null("MountainInteriorManager")

	_init_dirt_roads()

	build_mountain_base_terrain(scenery_root)
	build_backcountry_dirt_roads(scenery_root)
	build_rocky_cliffs_and_ridges(scenery_root, road)
	build_lake_and_rapids(scenery_root)
	build_secret_mountain_lake(scenery_root, setpieces)
	build_mountain_chalets(scenery_root, setpieces, interior_mgr)
	build_mountain_ammunation(scenery_root, setpieces, interior_mgr)
	await build_dense_pine_forest(scenery_root, road)
	build_road_signage_and_chevrons(scenery_root)

	if setpieces:
		build_detailed_sawmill(setpieces.get_node_or_null("LoggingCamp"))
		build_detailed_footbridge(setpieces.get_node_or_null("GorgeneckFootbridge"))
		build_detailed_cave_cache(setpieces.get_node_or_null("CaveCache"))
		build_detailed_overlook(setpieces.get_node_or_null("ScenicOverlookArea"))
		build_detailed_bunker(setpieces.get_node_or_null("AltitudeOutpostBunker"))

static func _init_dirt_roads() -> void:
	dirt_road_curves.clear()

	# 1. Estrada dos Chales (East Vale Road)
	var c1 := Curve2D.new()
	c1.add_point(Vector2(6350, 560))
	c1.add_point(Vector2(6850, 690))
	c1.add_point(Vector2(7350, 620))
	c1.add_point(Vector2(7850, 580))
	c1.add_point(Vector2(8350, 480))
	c1.add_point(Vector2(8700, 460))
	dirt_road_curves.append(c1)

	# 2. Estrada da Ammu-Nation (Timber Ridge Cut)
	var c2 := Curve2D.new()
	c2.add_point(Vector2(6650, 120))
	c2.add_point(Vector2(7150, -60))
	c2.add_point(Vector2(7450, -160))
	c2.add_point(Vector2(7750, -220))
	dirt_road_curves.append(c2)

	# 3. Trilha da Caverna (Smuggler's Cut)
	var c3 := Curve2D.new()
	c3.add_point(Vector2(6120, 320))
	c3.add_point(Vector2(6040, 100))
	c3.add_point(Vector2(6060, -150))
	c3.add_point(Vector2(6200, -320))
	dirt_road_curves.append(c3)

	# 4. Trilha do Lago Secreto dos Contrabandistas (Secret Tarn Trail)
	var c4 := Curve2D.new()
	c4.add_point(Vector2(6200, -320))
	c4.add_point(Vector2(5960, -560))
	c4.add_point(Vector2(5780, -780))
	c4.add_point(Vector2(5640, -960))
	dirt_road_curves.append(c4)

# 0. Base do Terreno: Oceano Amplo, Relevos de Floresta e Neve Alpina
static func build_mountain_base_terrain(parent: Node2D) -> void:
	var base := Node2D.new()
	base.name = "MountainBaseTerrain"
	base.z_index = -12
	parent.add_child(base)

	# A. Oceano Profundo
	var ocean := Polygon2D.new()
	ocean.color = Color("#10202a")
	ocean.polygon = PackedVector2Array([
		Vector2(-4000, 5000), Vector2(4650, 5000),
		Vector2(4650, -5000), Vector2(-4000, -5000)
	])
	base.add_child(ocean)

	for oy in range(-4000, 4500, 450):
		var wave := Line2D.new()
		wave.width = 3.0
		wave.default_color = Color(0.18, 0.32, 0.40, 0.45)
		wave.points = PackedVector2Array([
			Vector2(1200, oy), Vector2(2500, oy + 40), Vector2(4400, oy - 20)
		])
		base.add_child(wave)

	var beach := Polygon2D.new()
	beach.color = Color("#2c2720")
	beach.polygon = PackedVector2Array([
		Vector2(4600, 5000), Vector2(4700, 5000),
		Vector2(4720, -5000), Vector2(4620, -5000)
	])
	base.add_child(beach)

	var foam := Line2D.new()
	foam.width = 8.0
	foam.default_color = Color(0.65, 0.78, 0.85, 0.5)
	foam.points = PackedVector2Array([
		Vector2(4625, 5000), Vector2(4635, 2000),
		Vector2(4615, 0), Vector2(4640, -2000), Vector2(4630, -5000)
	])
	base.add_child(foam)

	# B. Chao da Floresta
	var forest_floor := Polygon2D.new()
	forest_floor.color = Color("#172315")
	forest_floor.polygon = PackedVector2Array([
		Vector2(4650, 5000), Vector2(12000, 5000),
		Vector2(12000, -5000), Vector2(4650, -5000)
	])
	base.add_child(forest_floor)

	# Curvas de nivel do relevo florestal
	var terrace1 := Polygon2D.new()
	terrace1.color = Color("#1c2b1a")
	terrace1.polygon = PackedVector2Array([
		Vector2(5500, 1800), Vector2(7200, 1600), Vector2(8800, 1100),
		Vector2(9500, -400), Vector2(8500, -1100), Vector2(7400, -900),
		Vector2(6200, -600), Vector2(5400, 600)
	])
	base.add_child(terrace1)

	var terrace2 := Polygon2D.new()
	terrace2.color = Color("#223320")
	terrace2.polygon = PackedVector2Array([
		Vector2(6000, 300), Vector2(7600, 100), Vector2(8200, -700),
		Vector2(7300, -1100), Vector2(5900, -750)
	])
	base.add_child(terrace2)

	# C. Chao Alpino de Neve e Gelo
	var snow_drifts := Node2D.new()
	snow_drifts.name = "AlpineSnowDrifts"
	base.add_child(snow_drifts)

	var permafrost := Polygon2D.new()
	permafrost.color = Color("#3a433e")
	permafrost.polygon = PackedVector2Array([
		Vector2(4650, -1350), Vector2(5400, -1290), Vector2(6200, -1430),
		Vector2(7000, -1340), Vector2(8000, -1460), Vector2(10000, -1380),
		Vector2(10000, -5000), Vector2(4650, -5000)
	])
	snow_drifts.add_child(permafrost)

	var snow_pack := Polygon2D.new()
	snow_pack.color = Color("#d7e1ea")
	snow_pack.polygon = PackedVector2Array([
		Vector2(4650, -1520), Vector2(5300, -1470), Vector2(6000, -1590),
		Vector2(6700, -1500), Vector2(7500, -1630), Vector2(8300, -1520),
		Vector2(10000, -1570), Vector2(10000, -5000), Vector2(4650, -5000)
	])
	snow_drifts.add_child(snow_pack)

	var high_snow := Polygon2D.new()
	high_snow.color = Color("#e7eff7")
	high_snow.polygon = PackedVector2Array([
		Vector2(4650, -2250), Vector2(5500, -2200), Vector2(6300, -2320),
		Vector2(7100, -2260), Vector2(10000, -2320), Vector2(10000, -5000), Vector2(4650, -5000)
	])
	snow_drifts.add_child(high_snow)

# 1. Rede de Estradas de Terra da Serra (Backcountry Roads)
static func build_backcountry_dirt_roads(parent: Node2D) -> void:
	var roads_root := Node2D.new()
	roads_root.name = "BackcountryDirtRoads"
	roads_root.z_index = 0
	parent.add_child(roads_root)

	for curve in dirt_road_curves:
		var pts := curve.tessellate(5, 8.0)
		if pts.size() < 2:
			continue

		# A. Base larga de leito de terra e cascalho batido
		var road_base := Line2D.new()
		road_base.width = 74.0
		road_base.default_color = Color("#34291e")
		road_base.points = pts
		roads_root.add_child(road_base)

		# B. Cascalho intermediario
		var gravel := Line2D.new()
		gravel.width = 64.0
		gravel.default_color = Color("#453728")
		gravel.points = pts
		roads_root.add_child(gravel)

		# C. Duas trilhas de pneus desgastadas onde as rodas passam
		var left_rut := PackedVector2Array()
		var right_rut := PackedVector2Array()
		for i in range(pts.size()):
			var p := pts[i]
			var tan := Vector2.RIGHT
			if i < pts.size() - 1: tan = (pts[i + 1] - p).normalized()
			elif i > 0: tan = (p - pts[i - 1]).normalized()
			var n := Vector2(-tan.y, tan.x)
			left_rut.append(p + n * 18.0)
			right_rut.append(p - n * 18.0)

		var r1 := Line2D.new()
		r1.width = 9.0
		r1.default_color = Color("#241c14", 0.75)
		r1.points = left_rut
		roads_root.add_child(r1)

		var r2 := Line2D.new()
		r2.width = 9.0
		r2.default_color = Color("#241c14", 0.75)
		r2.points = right_rut
		roads_root.add_child(r2)

# 2. Encostas Rochosas Naturais e Cristas
static func build_rocky_cliffs_and_ridges(parent: Node2D, road: MountainPassRoad) -> void:
	var cliffs := Node2D.new()
	cliffs.name = "CliffFacesAndRidges"
	cliffs.z_index = -4
	parent.add_child(cliffs)

	var rock_coords: Array[Vector2] = [
		Vector2(4850, 310), Vector2(5750, 320), Vector2(6080, 470),
		Vector2(6550, -320), Vector2(6850, -420), Vector2(6350, -680),
		Vector2(7050, -1250), Vector2(6450, -1550), Vector2(6050, -1950),
		Vector2(6750, -2300), Vector2(6320, -2680), Vector2(6680, -2700),
		Vector2(6200, -2820), Vector2(6800, -2840), Vector2(6500, -3050),
		Vector2(7650, 720), Vector2(8550, 560), Vector2(8050, -320)
	]
	for idx in range(rock_coords.size()):
		var rpos := rock_coords[idx]
		if road and road.is_point_on_road(rpos, 95.0):
			continue
		var rock = ROCK_SCRIPT.new()
		rock.position = rpos
		rock.variant_seed = idx * 23 + 7
		rock.rock_size = Vector2(randf_range(38, 70), randf_range(26, 48))
		rock.base_color = Color("#6c7b8c") if rpos.y < -1500.0 else Color("#483f36")
		cliffs.add_child(rock)

# 3. Lago Alpino, Riacho e Corredeiras de Espuma
static func build_lake_and_rapids(parent: Node2D) -> void:
	var water_system := Node2D.new()
	water_system.name = "WaterSystemDetailed"
	water_system.z_index = -3
	parent.add_child(water_system)

	var lake_shore := Polygon2D.new()
	lake_shore.color = Color("#342e26")
	lake_shore.polygon = PackedVector2Array([
		Vector2(6720, 350), Vector2(7200, 270), Vector2(7440, -140),
		Vector2(7220, -300), Vector2(6940, -110), Vector2(6740, 140)
	])
	water_system.add_child(lake_shore)

	var shallow_water := Polygon2D.new()
	shallow_water.color = Color("#226274")
	shallow_water.polygon = PackedVector2Array([
		Vector2(6750, 330), Vector2(7170, 250), Vector2(7400, -130),
		Vector2(7190, -270), Vector2(6960, -90), Vector2(6760, 130)
	])
	water_system.add_child(shallow_water)

	var deep_water := Polygon2D.new()
	deep_water.color = Color("#133c4a")
	deep_water.polygon = PackedVector2Array([
		Vector2(6830, 270), Vector2(7120, 200), Vector2(7320, -110),
		Vector2(7130, -210), Vector2(6980, -60), Vector2(6840, 110)
	])
	water_system.add_child(deep_water)

	var stream := Line2D.new()
	stream.width = 44.0
	stream.default_color = Color("#1e5668")
	stream.points = PackedVector2Array([
		Vector2(7380, -260), Vector2(7120, -40), Vector2(6890, 160), Vector2(6760, 270)
	])
	water_system.add_child(stream)

	var rapids := Line2D.new()
	rapids.width = 13.0
	rapids.default_color = Color(0.85, 0.94, 0.98, 0.7)
	rapids.points = PackedVector2Array([
		Vector2(7220, -130), Vector2(7050, 40), Vector2(6920, 150)
	])
	water_system.add_child(rapids)

# 3B. Lago Secreto dos Contrabandistas (Secret Glacial Tarn) com Segredo Submerso e Cofre
static func build_secret_mountain_lake(parent: Node2D, setpieces: Node2D) -> void:
	var secret_lake := Node2D.new()
	secret_lake.name = "SecretMountainLake"
	secret_lake.position = Vector2(5450, -1150)
	secret_lake.z_index = -3
	parent.add_child(secret_lake)

	# 1. ACAMPAMENTO DOS CONTRABANDISTAS (Clareira de Terra Batida fora da água)
	var camp := Node2D.new()
	camp.name = "SmugglerCampsite"
	camp.position = Vector2(180, 180) # Coordenada local: (5450 + 180, -1150 + 180) = (5630, -970)
	camp.z_index = 2
	secret_lake.add_child(camp)

	# Pátio orgânico de terra batida e cascalho onde a estrada termina
	var camp_ground := Polygon2D.new()
	camp_ground.color = Color("#382e22")
	camp_ground.polygon = PackedVector2Array([
		Vector2(-95, -70), Vector2(35, -80), Vector2(85, -30), Vector2(90, 50),
		Vector2(45, 90), Vector2(-40, 85), Vector2(-90, 30)
	])
	camp.add_child(camp_ground)

	var gravel_rim := Line2D.new()
	gravel_rim.width = 4.0
	gravel_rim.default_color = Color("#4a3e30")
	gravel_rim.points = camp_ground.polygon
	camp.add_child(gravel_rim)

	# Trilhas de pneu manobrando no pátio de terra
	for tx in [-15.0, 15.0]:
		var rut := Line2D.new()
		rut.width = 7.0
		rut.default_color = Color("#221b14", 0.7)
		rut.points = PackedVector2Array([Vector2(65, 30 + tx), Vector2(10, 15 + tx), Vector2(-45, -10 + tx)])
		camp.add_child(rut)

	# Fogueira de acampamento com círculo de pedras e calor (heat_source)
	var fire_pit := Node2D.new()
	fire_pit.position = Vector2(25, -20)
	camp.add_child(fire_pit)

	var stone_ring := Line2D.new()
	stone_ring.width = 4.5
	stone_ring.default_color = Color("#57606f")
	var s_ring_pts := PackedVector2Array()
	for i in 12:
		var a := TAU * float(i) / 12.0
		s_ring_pts.append(Vector2(cos(a) * 14.0, sin(a) * 14.0))
	s_ring_pts.append(s_ring_pts[0])
	stone_ring.points = s_ring_pts
	fire_pit.add_child(stone_ring)

	var fire_effect := preload("res://world/mountain_pass/MountainCampfire.gd").new()
	fire_effect.name = "AnimatedCampfire"
	fire_pit.add_child(fire_effect)

	var camp_heat := Area2D.new()
	camp_heat.name = "CampHeatSource"
	camp_heat.add_to_group("heat_source")
	var ch_col := CollisionShape2D.new()
	var ch_circ := CircleShape2D.new()
	ch_circ.radius = 180.0
	ch_col.shape = ch_circ
	camp_heat.add_child(ch_col)
	fire_pit.add_child(camp_heat)

	var fire_glow := PointLight2D.new()
	fire_glow.color = Color(1.0, 0.65, 0.3)
	fire_glow.energy = 1.6
	fire_glow.texture_scale = 2.4
	var f_img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for ly in 64:
		for lx in 64:
			var d: float = Vector2(lx - 31.5, ly - 31.5).length()
			var a: float = clampf(1.0 - d / 31.5, 0.0, 1.0)
			f_img.set_pixel(lx, ly, Color(1, 1, 1, a * a))
	fire_glow.texture = ImageTexture.create_from_image(f_img)
	fire_pit.add_child(fire_glow)

	# Caixas de suprimentos e galões no acampamento
	for cx in [Vector2(-60, 40), Vector2(-45, 55)]:
		var box := Polygon2D.new()
		box.color = Color("#59402b")
		box.polygon = PackedVector2Array([Vector2(-12, -10), Vector2(12, -10), Vector2(12, 10), Vector2(-12, 10)])
		box.position = cx
		camp.add_child(box)

	# JEEPZÃO 3D DE GELO PRONTO PARA ROUBAR
	var arctic_jeep = ARCTIC_JEEP_SCRIPT.new()
	arctic_jeep.name = "SmugglerArcticJeep3D"
	arctic_jeep.position = Vector2(-20, 15)
	arctic_jeep.rotation = deg_to_rad(-42.0) # Apontado para a estrada de fuga
	camp.add_child(arctic_jeep)

	# Trilha de pedestres a pé que desce da clareira até a praia do lago
	var footpath := Line2D.new()
	footpath.width = 16.0
	footpath.default_color = Color("#3f3325")
	footpath.points = PackedVector2Array([Vector2(-40, -10), Vector2(-80, -45), Vector2(-110, -70)])
	camp.add_child(footpath)

	# 2. MARGEM E ÁGUAS DO LAGO GLACIAL (Formato Orgânico e Natural)
	var shore := Polygon2D.new()
	shore.color = Color("#2a241e")
	shore.polygon = PackedVector2Array([
		Vector2(-240, -150), Vector2(-80, -185), Vector2(110, -170), Vector2(230, -110),
		Vector2(245, 20), Vector2(175, 120), Vector2(65, 135), Vector2(-60, 155),
		Vector2(-170, 140), Vector2(-255, 30)
	])
	shore.polygon = Transform2D(0,Vector2(1.35,1.65),0,Vector2.ZERO) * shore.polygon
	secret_lake.add_child(shore)

	var beach_sand := Line2D.new()
	beach_sand.width = 12.0
	beach_sand.default_color = Color("#3e352b")
	beach_sand.points = shore.polygon
	secret_lake.add_child(beach_sand)

	var shallow := Polygon2D.new()
	shallow.color = Color("#175b6a")
	shallow.polygon = PackedVector2Array([
		Vector2(-220, -135), Vector2(-75, -165), Vector2(95, -150), Vector2(210, -95),
		Vector2(220, 15), Vector2(155, 105), Vector2(50, 120), Vector2(-50, 135),
		Vector2(-150, 125), Vector2(-230, 20)
	])
	shallow.polygon = Transform2D(0,Vector2(1.35,1.65),0,Vector2.ZERO) * shallow.polygon
	secret_lake.add_child(shallow)

	var deep := Polygon2D.new()
	deep.color = Color("#0b2f3a")
	deep.polygon = PackedVector2Array([
		Vector2(-170, -105), Vector2(-55, -125), Vector2(75, -115), Vector2(160, -70),
		Vector2(165, 10), Vector2(115, 80), Vector2(20, 95), Vector2(-80, 85), Vector2(-170, 10)
	])
	deep.polygon = Transform2D(0,Vector2(1.35,1.65),0,Vector2.ZERO) * deep.polygon
	secret_lake.add_child(deep)

	# Fragmentos fraturados: bordas submersas, espessura e geada irregular.
	var ice_positions := [Vector2(-135, -75), Vector2(95, -60), Vector2(-95, 65), Vector2(45, 80), Vector2(-54, -177), Vector2(-31, -168), Vector2(-66, -158)]
	for i in range(ice_positions.size()):
		var ice := preload("res://world/mountain_pass/MountainLakeIce.gd").new()
		ice.name = "FracturedIce%d" % i
		ice.variant = i
		ice.position = ice_positions[i]
		ice.rotation = float(i) * 1.17
		ice.scale = Vector2.ONE * [0.85, 0.6, 1.0, 0.55, 0.8, 0.5, 0.4][i]
		secret_lake.add_child(ice)

	# Cascata presa à margem: silhueta estreita e quebrada, sem blocos retos.
	var frozen_fall := Polygon2D.new()
	frozen_fall.color = Color("#709ba6")
	frozen_fall.polygon = PackedVector2Array([
		Vector2(-63, -257), Vector2(-49, -260), Vector2(-44, -246),
		Vector2(-48, -232), Vector2(-39, -219), Vector2(-42, -205),
		Vector2(-34, -191), Vector2(-38, -177), Vector2(-44, -169),
		Vector2(-52, -180), Vector2(-50, -195), Vector2(-57, -211),
		Vector2(-55, -225), Vector2(-64, -240)
	])
	secret_lake.add_child(frozen_fall)
	for i in range(3):
		var vein := Line2D.new()
		vein.width = 1.4 + float(i) * 0.5
		vein.default_color = Color(0.77, 0.91, 0.94, 0.65)
		var offset := Vector2(float(i) * 4, 0)
		vein.points = PackedVector2Array([Vector2(-59, -253) + offset, Vector2(-54, -237) + offset, Vector2(-53, -220) + offset, Vector2(-47, -201) + offset, Vector2(-44, -181) + offset])
		secret_lake.add_child(vein)

	# Walk-in cargo wreck: the same actor explores its floor without teleport.
	var plane_wreck := preload("res://world/mountain_pass/MountainCargoPlane.gd").new()
	plane_wreck.name = "SmugglerCargoPlane"
	secret_lake.add_child(plane_wreck)
	var water_effects := preload("res://world/mountain_pass/MountainLakeWater.gd").new()
	water_effects.name = "InteractiveLakeWater"
	water_effects.polygon = shallow.polygon
	water_effects.plane = plane_wreck
	secret_lake.add_child(water_effects)
	water_effects.animate_surface(shallow)
	water_effects.animate_surface(deep)

	# 4. SEGREDO 2: ILHA SECRETA COM COFRE DE ARMAS E OURO (Secret Vault Islet)
	var island := Node2D.new()
	island.name = "SecretCacheIsland"
	island.position = Vector2(245, -65)
	secret_lake.add_child(island)

	# Ilhota de rochas de ardósia com musgo
	var is_rock := Polygon2D.new()
	water_effects.dry_islands.append(is_rock)
	is_rock.color = Color("#423a31")
	is_rock.polygon = PackedVector2Array([
		Vector2(-50, -45), Vector2(45, -40), Vector2(60, 25), Vector2(25, 55),
		Vector2(-35, 50), Vector2(-55, 10)
	])
	island.add_child(is_rock)

	var is_moss := Polygon2D.new()
	is_moss.color = Color("#22331f")
	is_moss.polygon = PackedVector2Array([
		Vector2(-40, -35), Vector2(35, -30), Vector2(45, 15), Vector2(15, 40), Vector2(-40, 25)
	])
	island.add_child(is_moss)

	# Pinheiro retorcido de montanha na ilha
	var lone_pine = PINE_SCRIPT.new()
	lone_pine.position = Vector2(20, -15)
	lone_pine.tree_scale = 1.15
	lone_pine.is_snowy = true
	island.add_child(lone_pine)

	# Píer de tábuas de cedro
	var pier := Line2D.new()
	pier.width = 14.0
	pier.default_color = Color("#4e3725")
	pier.points = PackedVector2Array([Vector2(-40, 20), Vector2(-75, 40)])
	island.add_child(pier)

	# Barco a remo de madeira amarrado ao píer
	var rowboat := Polygon2D.new()
	rowboat.color = Color("#6d4c35")
	rowboat.polygon = PackedVector2Array([
		Vector2(-95, 30), Vector2(-72, 22), Vector2(-68, 48), Vector2(-92, 54)
	])
	island.add_child(rowboat)

	# Remos de madeira cruzados no barco
	var oar := Line2D.new()
	oar.width = 2.0
	oar.default_color = Color("#b8860b")
	oar.points = PackedVector2Array([Vector2(-90, 24), Vector2(-70, 52)])
	island.add_child(oar)

	# Pedras de travessia (stepping stones) com anéis de ondulação na água
	for step_pos in [Vector2(45, 105), Vector2(58, 75), Vector2(65, 50)]:
		var ripple := Line2D.new()
		ripple.width = 1.8
		ripple.default_color = Color(0.6, 0.85, 0.95, 0.5)
		var r_pts := PackedVector2Array()
		for i in 10:
			var a := TAU * float(i) / 10.0
			r_pts.append(Vector2(cos(a) * 16.0, sin(a) * 12.0))
		r_pts.append(r_pts[0])
		ripple.points = r_pts
		ripple.position = step_pos
		secret_lake.add_child(ripple)

		var stone := Polygon2D.new()
		stone.color = Color("#574f44")
		stone.polygon = PackedVector2Array([Vector2(-12, -9), Vector2(11, -10), Vector2(13, 9), Vector2(-10, 10)])
		stone.position = step_pos
		secret_lake.add_child(stone)
		water_effects.dry_islands.append(stone)

	# O COFRE ABERTO / CAIXA MILITAR DE CONTRABANDO
	var cache_box := Polygon2D.new()
	cache_box.color = Color("#192a56") # Caixa Pelican militar azul-marinho reforçada
	cache_box.polygon = PackedVector2Array([
		Vector2(-20, -14), Vector2(20, -14), Vector2(20, 14), Vector2(-20, 14)
	])
	cache_box.position = Vector2(-8, 5)
	island.add_child(cache_box)

	var box_border := Line2D.new()
	box_border.width = 2.0
	box_border.default_color = Color("#273c75")
	box_border.points = cache_box.polygon
	box_border.position = cache_box.position
	island.add_child(box_border)

	# Lingotes de Ouro maciço reluzentes
	for gy in [-4.0, 4.0]:
		var gold := Polygon2D.new()
		gold.color = Color("#f1c40f")
		gold.polygon = PackedVector2Array([Vector2(-14, gy - 2), Vector2(-2, gy - 2), Vector2(-2, gy + 2), Vector2(-14, gy + 2)])
		gold.position = cache_box.position
		island.add_child(gold)

	# Fuzil de Sniper Especial com Cano Longo e Luneta
	var sniper_body := Line2D.new()
	sniper_body.width = 2.5
	sniper_body.default_color = Color("#2d3436")
	sniper_body.points = PackedVector2Array([Vector2(0, -10), Vector2(16, 10)])
	sniper_body.position = cache_box.position
	island.add_child(sniper_body)

	var sniper_scope := Line2D.new()
	sniper_scope.width = 3.5
	sniper_scope.default_color = Color("#00cec9") # Lente azulada
	sniper_scope.points = PackedVector2Array([Vector2(6, -3), Vector2(10, 2)])
	sniper_scope.position = cache_box.position
	island.add_child(sniper_scope)

	# Lampião misterioso aceso na ilhota
	var island_light := PointLight2D.new()
	island_light.position = Vector2(-10, -20)
	island_light.color = Color(1.0, 0.78, 0.38)
	island_light.energy = 2.0
	island_light.texture_scale = 2.6
	island_light.texture = ImageTexture.create_from_image(f_img)
	island.add_child(island_light)

# 4. Casas de Montanha e Chales Alpinos
static func build_mountain_chalets(parent: Node2D, setpieces: Node2D, interior_mgr: Node2D) -> void:
	var chalets_root := Node2D.new()
	chalets_root.name = "MountainChalets"
	chalets_root.z_index = 2
	parent.add_child(chalets_root)

	# Chale 1: Pine Crest Cabin
	_build_single_chalet(
		chalets_root,
		# Recuado para dentro da mata, mantendo a estrada como acesso.
		Vector2(7480, 760),
		Vector2(150, 110),
		"PineCrestCabin",
		"CHALE DOS PINHAIS",
		interior_mgr,
		false
	)

	# Chale 2: Timberline Chalet
	_build_single_chalet(
		chalets_root,
		Vector2(8350, 730),
		Vector2(170, 120),
		"TimberlineChalet",
		"CHALE DA ENCOSTA",
		interior_mgr,
		true
	)

	# Chale 3: Ranger Lookout Station
	_build_single_chalet(
		chalets_root,
		Vector2(6050, 780),
		Vector2(130, 95),
		"RangerStation",
		"POSTO FLORESTAL",
		interior_mgr,
		false
	)

static func _build_single_chalet(parent: Node2D, pos: Vector2, _size: Vector2, id: String, title: String, interior_mgr: Node2D, has_vehicle: bool) -> void:
	var chalet := preload("res://world/mountain_pass/MountainProp.gd").new()
	chalet.name = id
	chalet.position = pos
	chalet.model_script = preload("res://world/mountain_pass/art/winter_props/LumberjackCabin3D.gd")
	chalet.paint = Color("68503c") if id != "RangerStation" else Color("45616a")
	parent.add_child(chalet)
	var yard := Polygon2D.new()
	yard.name = "ChaletYard"
	yard.z_index = -1
	yard.color = Color("3d382e")
	yard.polygon = PackedVector2Array([Vector2(-70,-40),Vector2(70,-40),Vector2(85,75),Vector2(-80,75)])
	chalet.add_child(yard)
	var door: BuildingEntrance = ENTRANCE_SCENE.instantiate()
	door.name = "Door"
	door.position = chalet.project(chalet.model.entrance_local_position)+Vector2(0,12)
	door.display_name = title
	door.destination_id = &"mountain_cabin"
	door.custom_prompt_text = "E"
	chalet.add_child(door)
	door.get_node("Facade").hide()
	interior_mgr.register_exterior_entrance(door,&"mountain_cabin",door.global_position+Vector2(0,26))
	if has_vehicle:
		var pickup = PICKUP_SCRIPT.new()
		pickup.name = "ChaletRanchPickup3D"
		pickup.position = Vector2(110,30)
		pickup.rotation = 0.08
		chalet.add_child(pickup)
	var access := Line2D.new()
	access.name = "CabinFootpath"
	access.z_index = -1
	access.width = 22
	access.default_color = Color("494333")
	# Acesso lateral: deixa a estrada de terra e a porta livres da construção.
	access.points = PackedVector2Array([Vector2(-95,-180),Vector2(-95,55),door.position+Vector2(0,25)])
	chalet.add_child(access)

# 5. Loja Ammu-Nation da Montanha (Timber Ridge Guns & Ammo)
static func build_mountain_ammunation(parent: Node2D, _setpieces: Node2D, interior_mgr: Node2D) -> void:
	var shop := preload("res://world/mountain_pass/MountainGunShopFacade.gd").new()
	shop.name = "MountainAmmuNation"
	shop.position = Vector2(7750, -220)
	parent.add_child(shop)
	shop.install_entrance(interior_mgr)

# 6. Floresta Densa de Pinheiros (MountainPineTree)
static func build_dense_pine_forest(parent: Node2D, road: MountainPassRoad, streamed := false) -> void:
	var chunk_started := Time.get_ticks_usec()
	var chunk_trees := 0
	var forest := Node2D.new()
	forest.name = "DensePineForest"
	forest.z_index = 6
	parent.add_child(forest)

	var lake_bounds := Rect2(6680, -320, 800, 700)
	var secret_lake_bounds := Rect2(5080, -1500, 740, 680)
	var bunker_bounds := Rect2(6340, -2920, 320, 260)
	var ammu_bounds := Rect2(7560, -320, 380, 260)

	var cluster_configs: Array[Dictionary] = [
		{"center": Vector2(4780, 180), "count": 25, "radius": 220.0, "snow": false},
		{"center": Vector2(4780, 640), "count": 25, "radius": 220.0, "snow": false},
		{"center": Vector2(5850, 680), "count": 28, "radius": 300.0, "snow": false},
		{"center": Vector2(6750, 560), "count": 32, "radius": 280.0, "snow": false},
		{"center": Vector2(7650, 750), "count": 30, "radius": 300.0, "snow": false},
		{"center": Vector2(8500, 650), "count": 32, "radius": 320.0, "snow": false},
		{"center": Vector2(8100, 100), "count": 30, "radius": 320.0, "snow": false},
		{"center": Vector2(8300, -300), "count": 30, "radius": 340.0, "snow": false},
		{"center": Vector2(7800, -800), "count": 28, "radius": 320.0, "snow": false},
		{"center": Vector2(6450, -420), "count": 26, "radius": 260.0, "snow": false},
		{"center": Vector2(5850, -820), "count": 24, "radius": 250.0, "snow": false},
		{"center": Vector2(5450, -1150), "count": 32, "radius": 360.0, "snow": true},
		{"center": Vector2(6750, -950), "count": 28, "radius": 280.0, "snow": false},
		{"center": Vector2(6100, -1450), "count": 26, "radius": 280.0, "snow": true},
		{"center": Vector2(7150, -1750), "count": 28, "radius": 300.0, "snow": true},
		{"center": Vector2(5900, -2150), "count": 24, "radius": 260.0, "snow": true},
		{"center": Vector2(6950, -2550), "count": 24, "radius": 240.0, "snow": true},
		{"center": Vector2(6200, -2700), "count": 18, "radius": 220.0, "snow": true},
		{"center": Vector2(6850, -2750), "count": 18, "radius": 220.0, "snow": true}
	]

	for cfg in cluster_configs:
		var center: Vector2 = cfg["center"]
		var count: int = cfg["count"]
		var radius: float = cfg["radius"]
		var is_snow: bool = cfg["snow"]

		var placed := 0
		var attempts := 0
		while placed < count and attempts < count * 6:
			if streamed and (chunk_trees >= 2 or Time.get_ticks_usec()-chunk_started > 4000):
				await parent.get_tree().process_frame
				if not is_instance_valid(parent) or not parent.is_inside_tree():
					return
				chunk_started = Time.get_ticks_usec()
				chunk_trees = 0
			attempts += 1
			var angle := randf() * TAU
			var dist := sqrt(randf()) * radius
			var pos := center + Vector2(cos(angle), sin(angle)) * dist

			var reserved := false
			if preload("res://world/mountain_pass/MountainVillageLayout.gd").is_reserved(pos): continue
			for site in [Vector2(7940,850),Vector2(8610,700),Vector2(7660,-730),Vector2(6610,-1250),Vector2(6710,-1280)]:
				if Rect2(site-Vector2(105,80),Vector2(230,160)).has_point(pos): reserved = true
			if reserved: continue
			if Rect2(5800, 440, 420, 460).has_point(pos) or Rect2(6750, -3170, 430, 380).has_point(pos):
				continue
			if road and road.is_point_on_road(pos, 95.0):
				continue
			if _is_point_on_dirt_road(pos, 42.0):
				continue
			if lake_bounds.has_point(pos) or secret_lake_bounds.has_point(pos) or bunker_bounds.has_point(pos) or ammu_bounds.has_point(pos) or pos.distance_to(Vector2(6500, -2660)) < 165.0:
				continue
			if pos.distance_to(Vector2(7480, 760)) < 125.0 or pos.distance_to(Vector2(8350, 730)) < 145.0 or pos.distance_to(Vector2(8460, 760)) < 95.0 or pos.distance_to(Vector2(6050, 780)) < 80.0:
				continue

			var pine = PINE_SCRIPT.new()
			pine.position = pos
			pine.is_snowy = is_snow
			pine.tree_scale = randf_range(0.85, 1.45)
			pine.variant_seed = int(pos.x * 43 + pos.y * 71)
			forest.add_child(pine)
			chunk_trees += 1
			placed += 1

static func _is_point_on_dirt_road(pos: Vector2, tolerance: float) -> bool:
	for curve in dirt_road_curves:
		var closest := curve.get_closest_point(pos)
		if pos.distance_to(closest) < tolerance:
			return true
	return false

# 7. Serraria Autentica (LoggingCamp)
static func build_detailed_sawmill(sawmill_node: Node2D) -> void:
	if sawmill_node == null:
		return
	
	sawmill_node.position = Vector2(6350, 560)
	sawmill_node.z_index = 1

	var yard := Polygon2D.new()
	yard.color = Color("#382e22")
	yard.polygon = PackedVector2Array([
		Vector2(-180, -110), Vector2(180, -110),
		Vector2(200, 130), Vector2(-170, 140)
	])
	sawmill_node.add_child(yard)

	var driveway := Polygon2D.new()
	driveway.color = Color("#382e22")
	driveway.polygon = PackedVector2Array([
		Vector2(-35, -165), Vector2(35, -165),
		Vector2(55, -100), Vector2(-55, -100)
	])
	sawmill_node.add_child(driveway)

	var shed := preload("res://world/mountain_pass/MountainProp.gd").new()
	shed.name = "SawmillShed3D"
	shed.model_script = preload("res://world/mountain_pass/art/winter_props/LumberjackCabin3D.gd")
	sawmill_node.add_child(shed)
	for point in [Vector2(-95,5),Vector2(-95,55)]:
		var stack := preload("res://world/mountain_pass/MountainProp.gd").new()
		stack.model_script = preload("res://world/mountain_pass/art/winter_props/CoveredWoodpile3D.gd")
		stack.position = point
		sawmill_node.add_child(stack)
	var lumber := Node2D.new()
	lumber.position = Vector2(40, 85)
	sawmill_node.add_child(lumber)
	for i in 4:
		var plank_stack := Polygon2D.new()
		plank_stack.color = Color("#9d7d4f").lightened(i * 0.05)
		var py: float = (i - 2) * 9.0
		plank_stack.polygon = PackedVector2Array([Vector2(-35, py - 3), Vector2(35, py - 3), Vector2(35, py + 3), Vector2(-35, py + 3)])
		lumber.add_child(plank_stack)

	var sawdust := Polygon2D.new()
	sawdust.color = Color("#b59357", 0.75)
	sawdust.polygon = PackedVector2Array([Vector2(-50, 70), Vector2(-15, 60), Vector2(-10, 100), Vector2(-45, 95)])
	sawmill_node.add_child(sawdust)

	var work_truck = PICKUP_SCRIPT.new()
	work_truck.name = "SawmillRanchPickup3D"
	work_truck.paint_color = Color("#576574")
	work_truck.position = Vector2(120, 50)
	work_truck.rotation = -0.25
	sawmill_node.add_child(work_truck)

# 8. Ponte Suspensa Pedestre de Madeira (GorgeneckFootbridge)
static func build_detailed_footbridge(bridge_node: Node2D) -> void:
	if bridge_node == null:
		return
	
	bridge_node.position = Vector2(7050, 40)
	bridge_node.z_index = 4

	for sy in [-20.0, 20.0]:
		var cable := Line2D.new()
		cable.width = 3.2
		cable.default_color = Color("#636e72")
		cable.points = PackedVector2Array([
			Vector2(-95, sy), Vector2(-30, sy - 9),
			Vector2(30, sy - 9), Vector2(95, sy)
		])
		bridge_node.add_child(cable)

	for i in 18:
		var t: float = float(i) / 17.0
		var px: float = lerpf(-90.0, 90.0, t)
		var plank := Line2D.new()
		plank.width = 8.5
		plank.default_color = Color(0.44, 0.32, 0.20).lightened((i % 2) * 0.08)
		plank.points = PackedVector2Array([Vector2(px, -20), Vector2(px, 20)])
		bridge_node.add_child(plank)

	for px in [-95.0, 95.0]:
		for py in [-24.0, 24.0]:
			var post := Polygon2D.new()
			post.color = Color("#2d2015")
			post.polygon = PackedVector2Array([
				Vector2(px - 5, py - 5), Vector2(px + 5, py - 5),
				Vector2(px + 5, py + 5), Vector2(px - 5, py + 5)
			])
			bridge_node.add_child(post)

# 9. Caverna Secreta dos Contrabandistas (CaveCache)
static func build_detailed_cave_cache(cave_node: Node2D) -> void:
	if cave_node == null:
		return
	
	cave_node.position = Vector2(6200, -320)
	cave_node.z_index = 3

	var mouth := Polygon2D.new()
	mouth.color = Color("#0c0b0a")
	mouth.polygon = PackedVector2Array([
		Vector2(-55, -40), Vector2(55, -40), Vector2(45, 35), Vector2(-45, 35)
	])
	cave_node.add_child(mouth)

	var arch := Polygon2D.new()
	arch.color = Color("#483f36")
	arch.polygon = PackedVector2Array([
		Vector2(-65, -50), Vector2(65, -50), Vector2(55, -30), Vector2(-55, -30)
	])
	cave_node.add_child(arch)

	var crate1 := Polygon2D.new()
	crate1.color = Color("#2d4a2d")
	crate1.polygon = PackedVector2Array([Vector2(-20, -12), Vector2(10, -12), Vector2(10, 8), Vector2(-20, 8)])
	cave_node.add_child(crate1)

	var c_line := Line2D.new()
	c_line.width = 1.5
	c_line.default_color = Color("#1e331e")
	c_line.points = PackedVector2Array([Vector2(-5, -12), Vector2(-5, 8)])
	cave_node.add_child(c_line)

	var crate2 := Polygon2D.new()
	crate2.color = Color("#6b573b")
	crate2.polygon = PackedVector2Array([Vector2(14, -6), Vector2(32, -6), Vector2(32, 10), Vector2(14, 10)])
	cave_node.add_child(crate2)

	var lantern := PointLight2D.new()
	lantern.position = Vector2(0, 5)
	lantern.color = Color(1.0, 0.7, 0.3)
	lantern.energy = 1.6
	lantern.texture_scale = 2.0
	var limg := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for ly in 64:
		for lx in 64:
			var d: float = Vector2(lx - 31.5, ly - 31.5).length()
			var a: float = clampf(1.0 - d / 31.5, 0.0, 1.0)
			limg.set_pixel(lx, ly, Color(1, 1, 1, a * a))
	lantern.texture = ImageTexture.create_from_image(limg)
	cave_node.add_child(lantern)

# 10. Mirante Panoramico com Vista para a Cidade (ScenicOverlookArea)
static func build_detailed_overlook(overlook_node: Node2D) -> void:
	if overlook_node == null:
		return
	
	overlook_node.position = Vector2(7050, -1350)
	overlook_node.z_index = 2

	var terrace := Polygon2D.new()
	terrace.color = Color("#22272d")
	var t_pts := PackedVector2Array([Vector2(-50, -60), Vector2(40, -60)])
	for i in 10:
		var a := -PI * 0.5 + float(i) * (PI / 9.0)
		t_pts.append(Vector2(40 + cos(a) * 65.0, sin(a) * 65.0))
	t_pts.append(Vector2(-50, 65))
	terrace.polygon = t_pts
	overlook_node.add_child(terrace)

	var wall := Line2D.new()
	wall.width = 6.0
	wall.default_color = Color("#8395a7")
	var w_pts := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + float(i) * (PI / 9.0)
		w_pts.append(Vector2(40 + cos(a) * 65.0, sin(a) * 65.0))
	wall.points = w_pts
	overlook_node.add_child(wall)

	var scope := Node2D.new()
	scope.position = Vector2(78, 0)
	overlook_node.add_child(scope)

	var base_s := Line2D.new()
	base_s.width = 4.0
	base_s.default_color = Color("#2c3e50")
	base_s.points = PackedVector2Array([Vector2(0, 7), Vector2(0, -7)])
	scope.add_child(base_s)

	var lenses := Line2D.new()
	lenses.width = 3.2
	lenses.default_color = Color("#3498db")
	lenses.points = PackedVector2Array([Vector2(4, 0), Vector2(14, 0)])
	scope.add_child(lenses)

# 11. Base Militar e Bunker de Radar no Cume (AltitudeOutpostBunker)
static func build_detailed_bunker(bunker_node: Node2D) -> void:
	if bunker_node == null:
		return
	
	bunker_node.position = Vector2(6500, -2800)
	bunker_node.z_index = 3

	var loop := Polygon2D.new()
	loop.color = Color("#22272e")
	loop.polygon = PackedVector2Array([
		Vector2(-130, -30), Vector2(130, -30),
		Vector2(145, 150), Vector2(-145, 150)
	])
	bunker_node.add_child(loop)

	var helipad := Node2D.new()
	helipad.position = Vector2(-70, 60)
	bunker_node.add_child(helipad)

	var h_circle := Line2D.new()
	h_circle.width = 3.5
	h_circle.default_color = Color("#f1c40f", 0.9)
	var c_pts := PackedVector2Array()
	for i in 24:
		var a := TAU * float(i) / 24.0
		c_pts.append(Vector2(cos(a) * 38.0, sin(a) * 38.0))
	c_pts.append(c_pts[0])
	h_circle.points = c_pts
	helipad.add_child(h_circle)

	for hx in [-13.0, 13.0]:
		var h_leg := Line2D.new()
		h_leg.width = 3.5
		h_leg.default_color = Color("#f1c40f", 0.9)
		h_leg.points = PackedVector2Array([Vector2(hx, -18), Vector2(hx, 18)])
		helipad.add_child(h_leg)

	var h_mid := Line2D.new()
	h_mid.width = 3.5
	h_mid.default_color = Color("#f1c40f", 0.9)
	h_mid.points = PackedVector2Array([Vector2(-13, 0), Vector2(13, 0)])
	helipad.add_child(h_mid)

	var bunker := Node2D.new()
	bunker.position = Vector2(0, -90)
	bunker_node.add_child(bunker)

	var b_shadow := Polygon2D.new()
	b_shadow.color = Color(0.02, 0.03, 0.05, 0.35)
	b_shadow.polygon = PackedVector2Array([
		Vector2(-125, -65), Vector2(125, -65),
		Vector2(135, 55), Vector2(-115, 55)
	])
	bunker.add_child(b_shadow)

	var b_body := Polygon2D.new()
	b_body.color = Color("#3d444d")
	b_body.polygon = PackedVector2Array([
		Vector2(-120, -70), Vector2(120, -70),
		Vector2(125, 45), Vector2(-125, 45)
	])
	bunker.add_child(b_body)

	for sx in [-70.0, 0.0, 70.0]:
		var slit := Polygon2D.new()
		slit.color = Color("#0f172a")
		slit.polygon = PackedVector2Array([
			Vector2(sx - 16, -42), Vector2(sx + 16, -42),
			Vector2(sx + 16, -32), Vector2(sx - 16, -32)
		])
		bunker.add_child(slit)

		var slit_light := PointLight2D.new()
		slit_light.position = Vector2(sx, -37)
		slit_light.color = Color(1.0, 0.75, 0.35)
		slit_light.energy = 0.9
		slit_light.texture_scale = 0.8
		var simg := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		for ly in 32:
			for lx in 32:
				var d: float = Vector2(lx - 15.5, ly - 15.5).length()
				var a: float = clampf(1.0 - d / 15.5, 0.0, 1.0)
				simg.set_pixel(lx, ly, Color(1, 1, 1, a * a))
		slit_light.texture = ImageTexture.create_from_image(simg)
		bunker.add_child(slit_light)

	var tower := Node2D.new()
	tower.position = Vector2(85, -60)
	bunker.add_child(tower)

	var t_legs := Line2D.new()
	t_legs.width = 3.5
	t_legs.default_color = Color("#e74c3c")
	t_legs.points = PackedVector2Array([Vector2(-14, 14), Vector2(0, -65), Vector2(14, 14)])
	tower.add_child(t_legs)

	var beacon := PointLight2D.new()
	beacon.name = "TowerBeacon"
	beacon.position = Vector2(0, -68)
	beacon.color = Color(1.0, 0.15, 0.15)
	beacon.energy = 2.2
	beacon.texture_scale = 2.0
	var bimg := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for fy in 32:
		for fx in 32:
			var d: float = Vector2(fx - 15.5, fy - 15.5).length()
			var a: float = clampf(1.0 - d / 15.5, 0.0, 1.0)
			bimg.set_pixel(fx, fy, Color(1, 1, 1, a * a))
	beacon.texture = ImageTexture.create_from_image(bimg)
	tower.add_child(beacon)

	var radar := Node2D.new()
	radar.position = Vector2(-75, -20)
	bunker.add_child(radar)

	var dish := Line2D.new()
	dish.width = 5.0
	dish.default_color = Color("#ecf0f1")
	dish.points = PackedVector2Array([Vector2(-24, -28), Vector2(0, -12), Vector2(24, -28)])
	radar.add_child(dish)

	var gen := Polygon2D.new()
	gen.color = Color("#2c3e50")
	gen.polygon = PackedVector2Array([Vector2(85, 20), Vector2(125, 20), Vector2(125, 60), Vector2(85, 60)])
	bunker_node.add_child(gen)

# 12. Placas Viarias de Curva Perigosa (Chevrons >>>)
static func build_road_signage_and_chevrons(parent: Node2D) -> void:
	var signs := Node2D.new()
	signs.name = "RoadSignage"
	signs.z_index = 4
	parent.add_child(signs)

	var chevron_locations: Array[Dictionary] = [
		{"pos": Vector2(7060, -220), "rot": -0.3},
		{"pos": Vector2(7080, -260), "rot": 0.0},
		{"pos": Vector2(7060, -300), "rot": 0.3},
		{"pos": Vector2(6060, -750), "rot": -0.3},
		{"pos": Vector2(6040, -790), "rot": 0.0},
		{"pos": Vector2(6060, -830), "rot": 0.3},
		{"pos": Vector2(7110, -1320), "rot": -0.3},
		{"pos": Vector2(7130, -1360), "rot": 0.0},
		{"pos": Vector2(7110, -1400), "rot": 0.3}
	]

	for cdata in chevron_locations:
		var sign_node := Node2D.new()
		sign_node.position = cdata["pos"]
		sign_node.rotation = cdata["rot"]
		signs.add_child(sign_node)

		var board := Polygon2D.new()
		board.color = Color("#f39c12")
		board.polygon = PackedVector2Array([Vector2(-8, -14), Vector2(8, -14), Vector2(8, 14), Vector2(-8, 14)])
		sign_node.add_child(board)

		var arrow := Line2D.new()
		arrow.width = 2.8
		arrow.default_color = Color("#1e272e")
		arrow.points = PackedVector2Array([Vector2(-5, -7), Vector2(3, 0), Vector2(-5, 7)])
		sign_node.add_child(arrow)
