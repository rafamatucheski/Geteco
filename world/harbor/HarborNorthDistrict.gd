@tool
extends "res://world/harbor/HarborDistrict.gd"
## Northgate is an authored extension of Northbank, not another road renderer.
## Buildings and their ground-level approaches share the district audit contract.
## The firehouse is an accessible exterior only; no dispatch/mission is implied.

const NORTH_LAND := Rect2(4380, -2400, 2380, 2300)
const HIGHWAY_LAND := Rect2(5700, -4470, 600, 2120)
const FIRE_APRON := Rect2(5725, -1260, 310, 160)
const WATER_COLOR := Color("#204754")

func _build_animated_water() -> void:
	preload("res://geodata/nature/WaterPresentation.gd").rectangle(self, Rect2(4380, -10000, 2380, 9900), WATER_COLOR)

func get_street_lamp_points() -> Array[Dictionary]:
	return [{"pos":Vector2(5000,-1920),"south":true},{"pos":Vector2(6100,-1920),"south":true},{"pos":Vector2(5000,-1030),"south":true},{"pos":Vector2(6100,-1030),"south":true},{"pos":Vector2(5050,-285),"south":true},{"pos":Vector2(6050,-285),"south":true}]
const TREE_POINTS: Array[Vector2] = [
	Vector2(4835,-1518),Vector2(4900,-1522),Vector2(5360,-1520),
	Vector2(5750,-1530),Vector2(6310,-1530),
	Vector2(4830,-180),Vector2(4900,-174),Vector2(5340,-180),
	Vector2(5770,-178),Vector2(5840,-174),Vector2(6270,-178),
]
const TREE_STYLES := [1,3,2,3,1,3,1,2,1,3,3]
const TREE_SCALES := [0.8,0.7,0.85,0.8,0.85,0.8,0.75,0.8,0.85,0.7,0.9]
const ROCK_POINTS := [Vector2(4950,-185),Vector2(4970,-190),Vector2(5910,-189),Vector2(5933,-181),Vector2(6190,-1530)]
const BENCH_POINTS: Array[Vector2] = [
	Vector2(5080, -1535), Vector2(6090, -1540),
	Vector2(5030, -160), Vector2(6010, -160),
]


func _build_sites() -> void:
	_building("BridgeCourtWest",Vector2(4925,-2240),Vector2(260,175),"brownstone","", "#ac9275")
	_building("BridgeCourtEast",Vector2(5290,-2240),Vector2(245,175),"office","", "#a5ad9b")
	_building("BridgeQuayHouse",Vector2(6485,-2195),Vector2(225,145),"brownstone","", "#b39c84")
	for x in [4925,5290,6485]:
		var front_y := -2122.0 if x==6485 else -2152.0
		_access("BridgeFrontage%d" % x,Rect2(x-24,front_y,48,-2082-front_y),Vector2(x,-2090),false)
	# Four coherent blocks: homes and practical businesses near the regional road.
	_building("GatewayFlats", Vector2(4915, -1730), Vector2(250, 220), "brownstone", "GATEWAY FLATS", "#b6ac93")
	_building("TransitHouse", Vector2(5260, -1730), Vector2(230, 220), "office", "TRANSIT HOUSE", "#8ab6b9")
	_building("MotorWorkshop", Vector2(4925, -1360), Vector2(270, 210), "garage", "", "#6bd2b2")
	_building("RoadsideSupplies", Vector2(5265, -1360), Vector2(230, 210), "shop", "HARDWARE / SUPPLY", "#bc9a74")
	_building("ServiceLodge", Vector2(5860, -1740), Vector2(300, 220), "office", "THE GATEWAY LODGE", "#9baaae")
	_building("ParcelOffice", Vector2(6200, -1740), Vector2(200, 220), "warehouse", "NORTH PARCEL", "#acaa84")
	_building("NorthFireStation", Vector2(5880, -1370), Vector2(310, 220), "fire_station", "NORTHGATE FIRE / 03", "#d97958")
	_building("ServiceCafe", Vector2(6200, -1370), Vector2(200, 220), "corner_shop", "EARLY SHIFT", "#d7b477")
	_building("CanalHomesWest", Vector2(4915, -860), Vector2(250, 180), "brownstone", "", "#b8a182")
	_building("CanalHomesEast", Vector2(5260, -860), Vector2(230, 180), "brownstone", "", "#a6b2a0")
	_building("NorthGrocer", Vector2(4915, -585), Vector2(250, 160), "corner_shop", "CANAL GROCERY", "#d8bc78")
	_building("CycleWorkshop", Vector2(5260, -585), Vector2(230, 160), "shop", "SPOKE / CYCLE CO.", "#82b8b4")
	_building("GardenFlats", Vector2(5875, -860), Vector2(310, 180), "brownstone", "", "#bd9e84")
	_building("UnionApartments", Vector2(6220, -860), Vector2(210, 180), "office", "NORTH UNION", "#9fbcc0")
	_building("CommunityHall", Vector2(5875, -585), Vector2(310, 160), "office", "NORTHGATE HALL", "#c9b597")
	_building("CornerPharmacy", Vector2(6220, -585), Vector2(210, 160), "shop", "CORNER PHARMACY", "#90bdb4")
	# Upper rows enter from the side streets; their approaches never cross a
	# second building to reach the next avenue. Lower rows face the avenue.
	_access("GatewayEntry", Rect2(4650, -1619, 265, 50), Vector2(4890, -1594), false)
	_access("TransitEntry", Rect2(5260, -1619, 290, 50), Vector2(5290, -1594), false)
	_access("MotorWorkshopApron", Rect2(4790, -1255, 270, 155), Vector2(4925, -1198), true)
	_access("RoadsideEntry", Rect2(5240, -1255, 50, 155), Vector2(5265, -1205), false)
	_access("LodgeEntry", Rect2(5550, -1629, 310, 50), Vector2(5830, -1604), false)
	_access("ParcelEntry", Rect2(6200, -1629, 250, 50), Vector2(6230, -1604), false)
	_access("FireStationApron", FIRE_APRON, Vector2(5880, -1198), true)
	_access("ServiceCafeEntry", Rect2(6175, -1260, 50, 160), Vector2(6200, -1205), false)
	_access("CanalWestEntry", Rect2(4650, -769, 265, 50), Vector2(4890, -744), false)
	_access("CanalEastEntry", Rect2(5260, -769, 290, 50), Vector2(5290, -744), false)
	_access("NorthGrocerEntry", Rect2(4890, -505, 50, 155), Vector2(4915, -470), false)
	_access("CycleWorkshopEntry", Rect2(5235, -505, 50, 155), Vector2(5260, -470), false)
	_access("GardenFlatsEntry", Rect2(5550, -769, 325, 50), Vector2(5850, -744), false)
	_access("UnionApartmentEntry", Rect2(6220, -769, 230, 50), Vector2(6250, -744), false)
	_access("CommunityHallEntry", Rect2(5845, -505, 60, 155), Vector2(5875, -470), false)
	_access("PharmacyEntry", Rect2(6195, -505, 50, 155), Vector2(6220, -470), false)


func _build_trees() -> void:
	_build_bridge_trees()
	for i in 8:
		preload("res://world/harbor/ExteriorFinish.gd").tree(self,[Vector2(4700,-2310),Vector2(5570,-2190),Vector2(5485,-2260),Vector2(6280,-2325),Vector2(6685,-2290),Vector2(4480,-1650),Vector2(4480,-700),Vector2(6620,-850)][i],330+i,1.25)
	for index in TREE_POINTS.size():
		var tree := TREE.new()
		tree.position = TREE_POINTS[index]
		tree.tree_style = [TREE.TreeStyle.STREET,TREE.TreeStyle.BROADLEAF,TREE.TreeStyle.PINE,TREE.TreeStyle.COASTAL][TREE_STYLES[index]]
		tree.crown_scale = TREE_SCALES[index]
		tree.leaf_color = Color(["476456","64775d","35564b"][index%3])
		tree.variant_seed = int(absf(tree.position.x + tree.position.y))
		add_child(tree)

func _build_bridge_trees() -> void:
	# Replace the flat verge dots along the complete causeway. The existing
	# projected broadleaf models share two static 3D renders for all 30 trees.
	# The old dots north of -3960 were covered by the interchange asphalt;
	# do not turn those hidden marks into solid trees in the curved lanes.
	const BRIDGE_TREE = preload("res://world/mountain_pass/MountainPine3D.gd")
	var index := 0
	for x in [5729.0, 6271.0]:
		for y in range(-3960, -2410, 105):
			var tree := BRIDGE_TREE.new()
			tree.name = "BridgeTree%02d" % index
			tree.position = Vector2(x,y)
			tree.variant_seed = 3 if index % 2 == 0 else 4
			tree.tree_scale = 0.85 + float(index % 3) * 0.05
			tree.is_snowy = false
			tree.add_to_group("bridge_verge_tree")
			add_child(tree)
			index += 1

func get_environment_detail_contract() -> Dictionary:
	var trees: Array[Dictionary] = []
	var rocks: Array[Dictionary] = []
	for index in TREE_POINTS.size():
		var s: float = TREE_SCALES[index]
		var style: int = TREE_STYLES[index]
		var opaque := Rect2(-22,-47,44,61) if style == TREE.TreeStyle.PINE else (Rect2(-43,-47,89,65) if style == TREE.TreeStyle.COASTAL else Rect2(-34,-46,70,70))
		trees.append({"position":TREE_POINTS[index],"style":style,"scale":s,"bounds":Rect2(TREE_POINTS[index]+Vector2(-48,-49)*s,Vector2(98,77)*s),"opaque_bounds":Rect2(TREE_POINTS[index]+opaque.position*s,opaque.size*s)})
	for point in ROCK_POINTS: rocks.append({"position":point,"bounds":Rect2(point-Vector2(10,7),Vector2(23,17))})
	return {"coordinate_space":"local","trees":trees,"rocks":rocks,"paths":get_sidewalk_routes()+[PackedVector2Array([Vector2(5990,-330),Vector2(5990,-130),Vector2(5790,-130)])],"fire_apron":FIRE_APRON}


func _build_site_solids() -> void:
	for i in range(BENCH_POINTS.size()):
		_add_obstacle(Rect2(BENCH_POINTS[i], Vector2(65, 19)), "Bench%d" % i)


func _build_boundaries() -> void:
	# Two northern water blocks leave the highway causeway uninterrupted at
	# y=-2400. The cap is beyond the authored turnaround, never across its lanes.
	var cutouts := preload("res://world/harbor/HarborNorthAccess.gd").water_cutouts()
	for rect in get_north_water_collision_rects():
		var pieces: Array[PackedVector2Array] = [PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])]
		for cutout in cutouts:
			var next: Array[PackedVector2Array] = []
			for piece in pieces: next.append_array(Geometry2D.clip_polygons(piece,cutout))
			pieces = next
		for piece in pieces:
			var body := StaticBody2D.new()
			body.name = "NorthWater"
			body.collision_layer = 1
			body.collision_mask = 0
			var collision := CollisionPolygon2D.new()
			collision.polygon = piece
			body.add_child(collision)
			add_child(body)


func _add_obstacle(bounds: Rect2, label: String) -> void:
	var body := StaticBody2D.new()
	body.name = label
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = bounds.get_center()
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = bounds.size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)


func get_north_water_collision_rects() -> Array[Rect2]:
	return [
		Rect2(4380, -10000, 1320, 7600),
		Rect2(6300, -10000, 460, 5268),
		Rect2(6300, -4387, 460, 1987),
		Rect2(5700, -10000, 600, 5240),
	]


func get_north_terrain_audit_data() -> Dictionary:
	return {
		"land_bounds": NORTH_LAND,
		"highway_land_bounds": HIGHWAY_LAND,
		"fire_apron": FIRE_APRON,
		"water_obstacles": get_north_water_collision_rects(),
		"tree_positions": TREE_POINTS.duplicate(),
		"fire_dispatch_integrated": is_inside_tree() and get_tree().get_first_node_in_group("emergency_depot_director") != null,
	}


func get_sidewalk_routes() -> Array[PackedVector2Array]:
	return [
		PackedVector2Array([Vector2(4810, -1182), Vector2(5400, -1182)]),
		PackedVector2Array([Vector2(5710, -1018), Vector2(6310, -1018)]),
		PackedVector2Array([Vector2(4810, -415), Vector2(5400, -415)]),
		PackedVector2Array([Vector2(5710, -415), Vector2(6310, -415)]),
	]


func _draw() -> void:
	# Water surrounds the narrow engineered causeway; no oversized green slab.
	SURFACE.paint(self,NORTH_LAND, Color("#999789"),"concrete")
	SURFACE.paint(self,HIGHWAY_LAND, Color("#82887d"),"gravel")
	_draw_northern_shore()
	for patch in [Rect2(4430,-1850,120,520),Rect2(4430,-960,120,460),Rect2(6540,-1770,155,450),Rect2(6535,-950,160,510),Rect2(4750,-2380,750,40),Rect2(6320,-2380,350,40)]:
		preload("res://world/harbor/ExteriorFinish.gd").meadow(self,patch,int(patch.position.x),Color("667858"))
	# Gravel verges stay beyond both carriageway+sidewalk envelopes. The main
	# provider renders the carriageways and central separation above this terrain.
	for x in [5708.0, 6250.0]:
		SURFACE.paint(self,Rect2(x, -4430, 42, 2030), Color("#b0ac96"),"gravel")
	SURFACE.paint(self,Rect2(5980, -4050, 40, 1650), Color("#7d8b74"),"grass")
	for y in range(-3990, -2410, 100):
		draw_line(Vector2(5990, y), Vector2(6010, y), Color("#a9ad8e"), 2)
	# Plazas north of the first urban avenue announce the neighborhood entrance.
	SURFACE.paint(self,Rect2(4785, -2320, 620, 160), Color("#b4ac96"),"stone")
	for stripe in range(0, 600, 40):
		draw_line(Vector2(4785 + stripe, -2320), Vector2(4785 + stripe, -2160), Color("#a39f8d"), 1)
	SURFACE.paint(self,Rect2(6335, -2320, 240, 160), Color("#b4ac96"),"stone")
	# Northwest/northeast and southwest/southeast blocks have clearly different
	# residential courts and working aprons rather than random isolated props.
	for x in [4775.0, 5675.0]:
		SURFACE.paint(self,Rect2(x, -1875, 650, 650), Color("#ada38e"),"concrete")
		draw_rect(Rect2(x + 8, -1867, 634, 634), Color("#969183"), false, 2)
		SURFACE.paint(self,Rect2(x, -975, 650, 510), Color("#b2a68f"),"concrete")
		draw_rect(Rect2(x + 8, -967, 634, 494), Color("#989080"), false, 2)
	for x in [4800.0, 5720.0]:
		SURFACE.paint(self,Rect2(x, -1550, 590, 65), Color("#c3b69e"),"stone")
		SURFACE.paint(self,Rect2(x, -707, 590, 30), Color("#c3b69e"),"stone")
	for access in accesses:
		SURFACE.paint(self,access.bounds, Color("#737a77") if access.vehicle else Color("#c8bca3"),"concrete")
		if access.vehicle: SURFACE.yard(self,access.bounds,int(access.bounds.position.x),true)
	_draw_fire_apron()
	SURFACE.foundations(self,sites)
	# Small public gardens form the seam to the existing Northbank frontage.
	for x in [4780.0, 5690.0]:
		SURFACE.paint(self,Rect2(x, -235, 650, 120), Color("#75836b"),"grass")
		SURFACE.paint(self,Rect2(x, -155, 650, 35), Color("#c6bba2"),"stone")
		SURFACE.paint(self,Rect2(x + 290, -350, 45, 235), Color("#c6bba2"),"stone")
		SURFACE.garden_edge(self,Rect2(x+8,-230,270,60),int(x))
		SURFACE.garden_edge(self,Rect2(x+345,-230,295,60),int(x)+1)
	for point in BENCH_POINTS:
		_draw_bench(point)
	for i in ROCK_POINTS.size():
		_draw_north_rock(ROCK_POINTS[i], i)

func _draw_north_rock(point: Vector2, index: int) -> void:
	# Sombra suave de contato no solo
	draw_colored_polygon(PackedVector2Array([point + Vector2(-9, 4), point + Vector2(0, 8), point + Vector2(11, 6), point + Vector2(12, 3), point + Vector2(2, 2)]), Color(0.04, 0.05, 0.06, 0.28))
	if index == 4:
		# Pedra ornamental do pátio norte: base de brita e pequeno detalhe botânico rasteiro
		draw_circle(point + Vector2(1, 2), 11.0, Color("#7a7566"))
		draw_circle(point + Vector2(1, 2), 9.0, Color("#5a5649"))
		draw_circle(point + Vector2(-6, 3), 4.0, Color("#4d6648"))
		draw_circle(point + Vector2(7, 4), 3.0, Color("#587352"))
		draw_colored_polygon(PackedVector2Array([point+Vector2(-8,2),point+Vector2(-5,-6),point+Vector2(6,-5),point+Vector2(10,2),point+Vector2(4,7),point+Vector2(-3,7)]), Color("#65726a"))
		draw_colored_polygon(PackedVector2Array([point+Vector2(-5,-6),point+Vector2(6,-5),point+Vector2(3,0),point+Vector2(-6,1)]), Color("#9aa08d"))
		draw_line(point+Vector2(-1,-2), point+Vector2(4,3), Color("#47524b"), 1.5)
		return

	match index % 2:
		0:
			draw_colored_polygon(PackedVector2Array([point+Vector2(-10,1),point+Vector2(-6,-7),point+Vector2(6,-5),point+Vector2(11,3),point+Vector2(4,8)]), Color("#63726a"))
			draw_colored_polygon(PackedVector2Array([point+Vector2(-6,-7),point+Vector2(6,-5),point+Vector2(3,1),point+Vector2(-8,2)]), Color("#9ba08d"))
			draw_line(point+Vector2(-2,-2), point+Vector2(5,4), Color("#46524b"), 1.5)
		1:
			draw_colored_polygon(PackedVector2Array([point+Vector2(-8,3),point+Vector2(-7,-5),point+Vector2(3,-7),point+Vector2(10,-2),point+Vector2(7,7),point+Vector2(-2,8)]), Color("#5a6861"))
			draw_colored_polygon(PackedVector2Array([point+Vector2(-7,-5),point+Vector2(3,-7),point+Vector2(2,-1),point+Vector2(-5,0)]), Color("#8c9482"))
			draw_line(point+Vector2(0,-3), point+Vector2(4,3), Color("#414e47"), 1.5)

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


func _draw_northern_shore() -> void:
	for rect in [Rect2(4380, -2400, 1320, 18), Rect2(6300, -2400, 460, 18), Rect2(5700, -4470, 600, 18), Rect2(4380, -2400, 18, 2300), Rect2(6742, -2400, 18, 2300), Rect2(5700, -4470, 12, 2070), Rect2(6288, -4470, 12, 2070)]:
		draw_rect(rect, Color("#b1b3a0"))
	for y in range(-4380, -2400, 130):
		for x in [5700.0, 6300.0]:
			draw_line(Vector2(x, y), Vector2(x, y + 65), Color("#42666b"), 4)


func _draw_fire_apron() -> void:
	# Keep the entire departure area empty. Bay guide lines are paint, not gates.
	SURFACE.paint(self,FIRE_APRON, Color("#737975"),"concrete")
	for x in [5762.0, 5880.0, 5998.0]:
		draw_line(Vector2(x - 35, -1250), Vector2(x - 35, -1175), Color("#d9c795"), 2)
		draw_line(Vector2(x + 35, -1250), Vector2(x + 35, -1175), Color("#d9c795"), 2)
