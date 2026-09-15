@tool
extends "res://world/harbor/HarborDistrict.gd"

## Northbank: a second developed shore, joined to Breakwater by Foundry Bridge.
## Reuses the same physical building/access audit; no second road renderer.
const EAST_LAND := Rect2(4380, -100, 2380, 2700)
# A montanha contínua começa em (4300,-4960); sua costa fica em x=4650
# local. O antigo oceano de Northbank não pode continuar sólido sob essa terra.
const MOUNTAIN_LAND := Rect2(8950, -9960, 7350, 10000)
@export var cobra_connection_enabled := false
const NATURE := [
	[Vector2(4860,1123),1,0.95,"426451"],[Vector2(4925,1122),3,0.75,"65775a"],[Vector2(5340,1120),2,0.85,"354f49"],
	[Vector2(5730,970),3,0.9,"537366"],[Vector2(6290,970),3,1.05,"647c68"],
	[Vector2(4870,1685),1,0.8,"506d48"],[Vector2(4940,1685),3,0.7,"758060"],[Vector2(5320,1685),1,0.85,"3f624d"],
	[Vector2(5920,1845),1,1.15,"4c6955"],[Vector2(5985,1890),3,0.8,"6d7c60"],[Vector2(6260,1825),3,1.0,"527569"],
	[Vector2(5920,2040),2,0.85,"3f5c50"],[Vector2(6250,2040),1,0.85,"697c55"]]
const ROCKS := [Vector2(4990,1697),Vector2(5011,1694),Vector2(5880,1935),Vector2(5896,1943),Vector2(6325,1980)]
const PROMENADE_GARDENS := [Rect2(4525,2365,125,65),Rect2(5110,2360,155,62),Rect2(5940,2370,95,58),Rect2(6480,2355,130,72)]
const PROMENADE_BENCHES := [Vector2(4665,2400),Vector2(5290,2405),Vector2(6080,2400),Vector2(6380,2400)]

func _build_animated_water() -> void:
	# O mar desta margem pertence ao Waterfront; não duplicar a fonte da praça.
	pass

func get_street_lamp_points() -> Array[Dictionary]:
	return [{"pos":Vector2(5080,1060),"south":true},{"pos":Vector2(6100,1330),"south":true},{"pos":Vector2(5050,1330),"south":true},{"pos":Vector2(6100,2280),"south":false},{"pos":Vector2(5050,2280),"south":false},{"pos":Vector2(6020,480),"south":true}]

func _build_sites() -> void:
	_building("ExchangeTower", Vector2(5000, 720), Vector2(300, 320), "office", "NORTHBANK EXCHANGE", "#83c6cc")
	get_node("ExchangeTower").height_override = 128.0
	_building("CivicTower", Vector2(5305, 680), Vector2(170, 240), "office", "HORIZON", "#aacacd")
	get_node("CivicTower").height_override = 95.0
	_building("MaritimeMuseum", Vector2(6020, 700), Vector2(460, 250), "office", "MARITIME MUSEUM", "#e0c9a1")
	for i in 3:
		# The workshop's authored window reaches 176px; retain its original
		# 180px lot width rather than letting the facade overhang the footprint.
		_building("NorthbankHomes%d" % i, Vector2([4900, 5120, 5330][i], 1510), [Vector2(160,190),Vector2(180,210),Vector2(180,170)][i], ["rowhouse_terrace","brownstone","artisan_workshop"][i], "", ["#8b6254","#aaa08b","#657679"][i])
	_building("IslandGrocer", Vector2(4930, 1990), Vector2(240, 170), "corner_shop", "NORTHBANK GROCERY", "#e0b975")
	_building("IslandCinema", Vector2(5270, 1990), Vector2(240, 170), "shop", "THE ORION / CINEMA", "#ce877e")
	_building("Aquarium", Vector2(6100, 1550), Vector2(360, 270), "office", "BAY AQUARIUM", "#73bfc6")
	_building("PromenadeCafe", Vector2(5790, 1515), Vector2(170, 210), "corner_shop", "TIDELINE", "#deb976")
	for i in 4:
		var x: float = [4900, 5290, 5840, 6200][i]
		_building("NorthbankFront%d" % i, Vector2(x, 145), Vector2(260, 180), "office" if i > 1 else "brownstone", ["BRIDGE HOUSE", "FOUNDERS CLUB", "DESIGN WORKS", "EASTGATE HOTEL"][i], "#96b7b4")
		_access("NorthbankFrontEntry%d" % i, Rect2(x - 25, 235, 50, 165), Vector2(x, 270), false)
	_access("ExchangeEntry", Rect2(4970, 880, 60, 120), Vector2(5000, 925), false)
	_access("HorizonEntry", Rect2(5275, 800, 60, 200), Vector2(5305, 845), false)
	_access("MuseumEntry", Rect2(5820, 825, 70, 425), Vector2(5855, 880), false)
	_access("NorthbankCourtyard", Rect2(4765, 1250, 40, 420), Vector2(4785, 1660), false)
	_access("GroceryEntry", Rect2(4905, 2075, 50, 125), Vector2(4930, 2110), false)
	_access("CinemaEntry", Rect2(5245, 2075, 50, 125), Vector2(5270, 2110), false)
	_access("AquariumEntry", Rect2(6070, 1685, 60, 515), Vector2(6100, 1730), false)
	_access("CafeEntry", Rect2(5760, 1620, 60, 580), Vector2(5790, 1670), false)

func _build_trees() -> void:
	for item in NATURE:
		var tree := TREE.new()
		tree.position = item[0]
		tree.tree_style = [TREE.TreeStyle.STREET,TREE.TreeStyle.BROADLEAF,TREE.TreeStyle.PINE,TREE.TreeStyle.COASTAL][item[1]]
		tree.crown_scale = item[2]
		tree.leaf_color = Color(item[3])
		tree.variant_seed = int(tree.position.x + tree.position.y)
		add_child(tree)

func get_environment_detail_contract() -> Dictionary:
	var trees: Array[Dictionary] = []
	var rocks: Array[Dictionary] = []
	for item in NATURE:
		var opaque := Rect2(-22,-47,44,61) if item[1] == TREE.TreeStyle.PINE else (Rect2(-43,-47,89,65) if item[1] == TREE.TreeStyle.COASTAL else Rect2(-34,-46,70,70))
		trees.append({"position":item[0],"style":item[1],"scale":item[2],"bounds":Rect2(item[0]+Vector2(-48,-49)*item[2],Vector2(98,77)*item[2]),"opaque_bounds":Rect2(item[0]+opaque.position*item[2],opaque.size*item[2])})
	for point in ROCKS: rocks.append({"position":point,"bounds":Rect2(point-Vector2(10,7),Vector2(23,17))})
	for bounds in PROMENADE_GARDENS: rocks.append({"kind":"planter","position":bounds.get_center(),"bounds":bounds})
	for point in PROMENADE_BENCHES: rocks.append({"kind":"bench","position":point,"bounds":Rect2(point+Vector2(-2,-2),Vector2(70,25))})
	return {"coordinate_space":"local","trees":trees,"rocks":rocks,"paths":get_sidewalk_routes() + [PackedVector2Array([Vector2(4825,1727),Vector2(5390,1727)]),PackedVector2Array([Vector2(4460,2465),Vector2(6670,2465)])]}

func _build_site_solids() -> void:
	# Museum courtyard compass sculpture; its approach is deliberately off-axis.
	var base := StaticBody2D.new()
	base.name = "CompassSculpture"
	base.position = Vector2(6080, 1000)
	base.collision_layer = 1
	base.collision_mask = 0
	var shape := CircleShape2D.new()
	shape.radius = 40
	var collision := CollisionShape2D.new()
	collision.shape = shape
	base.add_child(collision)
	add_child(base)

func _build_boundaries() -> void:
	# The northern cap is now owned by NorthDistrict, beyond the new blocks.
	# Keeping the old wall at y=-130 would silently block the three extensions.
	var boundaries: Array[Rect2] = [Rect2(6760, -5000, 8000, 268), Rect2(6760, -4387, 8000, 14387), Rect2(4380, 2600, 2380, 7000)]
	if cobra_connection_enabled:
		# The peninsula is real land: remove only its part of the old ocean wall.
		# Its own perimeter is closed by CobraNeighborhood, not an invisible gate
		# across the new public street and pedestrian approaches.
		boundaries = [Rect2(6760, -5000, 8000, 268), Rect2(6760, -4387, 8000, 5347), Rect2(6760, 2410, 8000, 7590), Rect2(4380, 2600, 2380, 7000)]
	var water_only: Array[Rect2] = []
	for boundary in boundaries:
		water_only.append_array(_subtract_land(boundary, MOUNTAIN_LAND))
	for rect in water_only:
		var body := StaticBody2D.new()
		body.name = "EastWaterBoundary%d" % get_child_count()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = rect.get_center()
		var pieces := preload("res://world/harbor/HarborSouthPortLayout.gd").subtract_surfaces(preload("res://world/harbor/HarborSouthPortLayout.gd").rect_polygon(rect))
		for cutout in preload("res://world/harbor/HarborNorthAccess.gd").water_cutouts():
			var next: Array[PackedVector2Array] = []
			for piece in pieces: next.append_array(Geometry2D.clip_polygons(piece,cutout))
			pieces = next
		for piece in pieces:
			var collision := CollisionPolygon2D.new()
			var local_piece := PackedVector2Array()
			for point in piece: local_piece.append(point - body.position)
			collision.polygon = local_piece
			body.add_child(collision)
		add_child(body)

static func _subtract_land(water: Rect2, land: Rect2) -> Array[Rect2]:
	var overlap := water.intersection(land)
	if not overlap.has_area(): return [water]
	var result: Array[Rect2] = []
	for piece in [
		Rect2(water.position,Vector2(overlap.position.x-water.position.x,water.size.y)),
		Rect2(Vector2(overlap.end.x,water.position.y),Vector2(water.end.x-overlap.end.x,water.size.y)),
		Rect2(Vector2(overlap.position.x,water.position.y),Vector2(overlap.size.x,overlap.position.y-water.position.y)),
		Rect2(Vector2(overlap.position.x,overlap.end.y),Vector2(overlap.size.x,water.end.y-overlap.end.y)),
	]:
		if piece.has_area(): result.append(piece)
	return result

func get_sidewalk_routes() -> Array[PackedVector2Array]:
	return [
		PackedVector2Array([Vector2(4810, 1168), Vector2(5400, 1168)]),
		PackedVector2Array([Vector2(5710, 1168), Vector2(6310, 1168)]),
		PackedVector2Array([Vector2(4810, 1332), Vector2(5410, 1332)]),
		PackedVector2Array([Vector2(5710, 1332), Vector2(6310, 1332)]),
		PackedVector2Array([Vector2(4820, 2118), Vector2(5410, 2118)]),
		PackedVector2Array([Vector2(5710, 2118), Vector2(6310, 2118)]),
	]

func _draw() -> void:
	SURFACE.paint(self,EAST_LAND, Color("#a19d8c"),"stone")
	# Low coastal planting breaks long paved margins without narrowing the footway.
	for patch in [Rect2(4430,530,85,500),Rect2(4430,1470,85,550),Rect2(6610,560,85,390),Rect2(6610,1870,85,220)]:
		preload("res://world/harbor/ExteriorFinish.gd").meadow(self,patch,int(patch.position.y)+51,Color("62765a"))
	# Reclaimed shore: stone sea wall with a public promenade, no empty green slab.
	for x in [4380, 6725]:
		draw_rect(Rect2(x, -100, 35, 2700), Color("#b9b6a4"))
		draw_line(Vector2(x + 12, -100), Vector2(x + 12, 2600), Color("#7b8f8d"), 3)
	draw_rect(Rect2(4380, 2565, 2380, 35), Color("#b9b6a4"))
	for x in [4780, 5680]:
		for row in [530, 1380]:
			SURFACE.paint(self,Rect2(x, row, 640, 710 if row > 1000 else 600), Color("#b5ac95"),"stone")
			draw_rect(Rect2(x + 8, row + 8, 624, 694 if row > 1000 else 584), Color("#9b9789"), false, 2)
	for x in [4900, 5290, 5840, 6200]:
		draw_rect(Rect2(x - 145, -35, 290, 60), Color("#5a7768"))
	# Exchange forecourt is open stone, the southern promenade an actual park.
	for x in range(4800, 5410, 45):
		draw_line(Vector2(x, 925), Vector2(x, 1125), Color("#a39e8c"), 1)
	SURFACE.paint(self,Rect2(4810, 1655, 600, 150), Color("#6c8067"),"grass")
	SURFACE.paint(self,Rect2(4810, 1711, 600, 32), Color("#c5bca3"),"stone")
	SURFACE.paint(self,Rect2(5695, 1740, 625, 340), Color("#819383"),"grass")
	for i in ROCKS.size():
		_draw_east_rock(ROCKS[i], i % 3)
	for access in accesses:
		SURFACE.paint(self,access.bounds, Color("#d0c4a7"),"stone")
	SURFACE.garden_edge(self,Rect2(4810,1655,600,150),81)
	SURFACE.garden_edge(self,Rect2(5695,1740,625,340),82)
	SURFACE.foundations(self,sites)
	# Broad waterfront promenade outside the perimeter road, with small gardens.
	SURFACE.paint(self,Rect2(4440, 2335, 2260, 170), Color("#d0c4a7"),"stone")
	for index in PROMENADE_GARDENS.size():
		_draw_promenade_planter(PROMENADE_GARDENS[index], index)
	for point in PROMENADE_BENCHES: _draw_bench(point)
	for x in [4830, 5760, 6270]:
		SURFACE.paint(self,Rect2(x, 2200, 60, 305), Color("#d0c4a7"),"stone")
	# Compass-shaped courtyard monument gives this shore a different landmark.
	var center := Vector2(6080, 1000)
	draw_circle(center, 46, Color("#8c9589"))
	draw_circle(center, 36, Color("#597984"))
	for i in 4:
		var direction := Vector2.RIGHT.rotated(i * PI * 0.5)
		var side := direction.orthogonal()
		draw_colored_polygon(PackedVector2Array([center + direction * 54, center + side * 10, center - side * 10]), Color("#e1c892") if i % 2 == 0 else Color("#b9c4be"))
	for point in [Vector2(5180, 900), Vector2(5125, 1120), Vector2(5980, 920), Vector2(6220, 1080), Vector2(5880, 1900), Vector2(6200, 1990)]:
		_draw_bench(point)

func _draw_east_rock(point: Vector2, variant: int) -> void:
	draw_colored_polygon(PackedVector2Array([point + Vector2(-9, 4), point + Vector2(0, 8), point + Vector2(11, 6), point + Vector2(12, 3), point + Vector2(2, 2)]), Color(0.04, 0.05, 0.06, 0.28))
	match variant:
		0:
			draw_colored_polygon(PackedVector2Array([point+Vector2(-10,1),point+Vector2(-6,-7),point+Vector2(6,-5),point+Vector2(11,3),point+Vector2(4,8)]), Color("#637270"))
			draw_colored_polygon(PackedVector2Array([point+Vector2(-6,-7),point+Vector2(6,-5),point+Vector2(3,1),point+Vector2(-8,2)]), Color("#9aa08e"))
			draw_line(point+Vector2(-2,-2), point+Vector2(5,4), Color("#4b5755"), 1.5)
		1:
			draw_colored_polygon(PackedVector2Array([point+Vector2(-8,3),point+Vector2(-7,-5),point+Vector2(2,-7),point+Vector2(10,-2),point+Vector2(7,7),point+Vector2(-2,8)]), Color("#5a6a67"))
			draw_colored_polygon(PackedVector2Array([point+Vector2(-7,-5),point+Vector2(2,-7),point+Vector2(1,-1),point+Vector2(-6,0)]), Color("#8c9482"))
			draw_line(point+Vector2(0,-3), point+Vector2(4,3), Color("#44504e"), 1.5)
		_:
			draw_colored_polygon(PackedVector2Array([point+Vector2(-9,-1),point+Vector2(-4,-7),point+Vector2(8,-4),point+Vector2(10,4),point+Vector2(2,7),point+Vector2(-7,5)]), Color("#687875"))
			draw_colored_polygon(PackedVector2Array([point+Vector2(-4,-7),point+Vector2(8,-4),point+Vector2(4,0),point+Vector2(-5,-2)]), Color("#9ea492"))
			draw_line(point+Vector2(-1,-3), point+Vector2(3,3), Color("#4c5855"), 1.5)

func _draw_promenade_planter(garden: Rect2, index: int) -> void:
	# Borda arquitetônica de pedra esculpida (curbing)
	draw_rect(garden, Color("#9d9685"))
	draw_rect(garden.grow(-2), Color("#6d695b"), false, 1.0)
	var bed := garden.grow(-3)
	draw_rect(bed, Color(["3d463a", "464b38", "3b4740", "444a37"][index]))
	# Composições botânicas equilibradas para cada canteiro
	var shrub_data: Array = []
	match index:
		0: # 125x65
			shrub_data = [
				[Vector2(24, 22), 13.0, Color("#3f614b"), Color("#5f8569")],
				[Vector2(58, 38), 15.0, Color("#486b53"), Color("#6d9478")],
				[Vector2(95, 26), 14.0, Color("#385945"), Color("#587d63")],
				[Vector2(38, 44), 9.0, Color("#506e50"), Color("#7a9973")],
				[Vector2(78, 18), 8.0, Color("#557252"), Color("#7d9c75")]
			]
		1: # 155x62 - preenchimento estendido cobrindo os 155px
			shrub_data = [
				[Vector2(25, 32), 14.0, Color("#42634e"), Color("#658a71")],
				[Vector2(58, 22), 12.0, Color("#4d6f58"), Color("#72967d")],
				[Vector2(92, 38), 15.0, Color("#395b46"), Color("#5b8066")],
				[Vector2(126, 24), 13.0, Color("#4a6d55"), Color("#6e9379")],
				[Vector2(75, 42), 8.0, Color("#5c7553"), Color("#829c75")],
				[Vector2(110, 44), 8.0, Color("#5c7553"), Color("#829c75")]
			]
		2: # 95x58
			shrub_data = [
				[Vector2(24, 28), 13.0, Color("#3d5e48"), Color("#5e8167")],
				[Vector2(52, 34), 14.0, Color("#456851"), Color("#698e74")],
				[Vector2(74, 22), 11.0, Color("#375641"), Color("#55775f")],
				[Vector2(38, 18), 8.0, Color("#547053"), Color("#7b9776")]
			]
		_: # 130x72
			shrub_data = [
				[Vector2(26, 36), 14.0, Color("#41624c"), Color("#63876e")],
				[Vector2(64, 24), 13.0, Color("#496d55"), Color("#6f947b")],
				[Vector2(98, 40), 15.0, Color("#375843"), Color("#587c63")],
				[Vector2(50, 48), 10.0, Color("#516e50"), Color("#799872")],
				[Vector2(85, 20), 9.0, Color("#577456"), Color("#7f9e78")]
			]
	for s in shrub_data:
		var pos: Vector2 = garden.position + s[0]
		var rad: float = s[1]
		# Sombra de solo
		draw_circle(pos + Vector2(2, 3), rad * 0.85, Color(0.04, 0.05, 0.06, 0.24))
		# Base escura da folhagem
		draw_circle(pos, rad, s[2])
		# Copa e destaques
		draw_circle(pos + Vector2(-1, -2), rad * 0.75, s[3])
		draw_circle(pos + Vector2(1, -rad * 0.4), rad * 0.35, Color(s[3]).lightened(0.18))
	# Pontos de flores/detalhes costeiros discretos
	for flower_offset in [Vector2(garden.size.x * 0.32, 14), Vector2(garden.size.x * 0.68, garden.size.y - 14)]:
		draw_circle(garden.position + flower_offset, 2.0, Color("#e8c878"))

func _draw_bench(point: Vector2) -> void:
	draw_rect(Rect2(point + Vector2(2, 3), Vector2(65, 19)), Color(0.04, 0.05, 0.06, 0.28))
	draw_rect(Rect2(point, Vector2(65, 19)), Color("#463b30"))
	draw_rect(Rect2(point + Vector2(2, 1), Vector2(4, 17)), Color("#26221d"))
	draw_rect(Rect2(point + Vector2(59, 1), Vector2(4, 17)), Color("#26221d"))
	draw_rect(Rect2(point + Vector2(30, 1), Vector2(4, 17)), Color("#26221d"))
	for y in [3, 8, 13]:
		draw_line(point + Vector2(6, y), point + Vector2(59, y), Color("#bd9b69"), 3.0)
		draw_line(point + Vector2(6, y - 1), point + Vector2(59, y - 1), Color("#d4b584"), 1.0)
		draw_line(point + Vector2(6, y + 1), point + Vector2(59, y + 1), Color("#8a6f47"), 1.0)
