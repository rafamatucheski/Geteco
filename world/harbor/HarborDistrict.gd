@tool
extends Node2D
const SURFACE := preload("res://world/harbor/UrbanGround.gd")

## A separate authored district, not a replacement for DistrictOneComplete.
## Ground, lots and accesses share the same world coordinates as RoadLayout.
const BUILDING := preload("res://world/harbor/HarborBuilding.gd")
const TREE := preload("res://geodata/nature/ProceduralStreetTree.gd")
const MEDICAL_PARKING := preload("res://world/harbor/HarborMedicalParking.gd")
const LOCAL_STREETS := preload("res://world/harbor/HarborLocalStreets.gd")
const LAND_BOUNDS := Rect2(-100, -100, 3300, 2580)
const SPAWN := Vector2(715, 1800)
const TERMINAL_LOT := Rect2(1500, 810, 600, 350)
const FOUNTAIN_POSITION := Vector2(1675, 1810)

var sites: Array[Dictionary] = []
var accesses: Array[Dictionary] = []

## Congelado pela ferramenta "Congelar Nós Procedurais" do city_layout_editor:
## prédios/árvores/postes já viraram nós salvos e arrastáveis na cena, então
## _ready() não os recria por cima (duplicaria tudo). _build_sites() continua
## rodando sempre -- sites/accesses são consultados por fora (HarborRoadNetwork
## corta a calçada nas aberturas de acesso; get_spatial_audit() os usa) --
## mas cada chamada de _building()/_access() só recria o NÓ quando ainda não
## está congelado; congelado, elas só preenchem os dois arrays e voltam.
@export var baked_from_editor := false

func _ready() -> void:
	_build_sites()
	if not baked_from_editor:
		_build_animated_water()
		_build_trees()
		_build_site_solids()
		_build_boundaries()
		_build_street_lamps()
	_build_memorial_trees()
	call_deferred("_bind_street_lamp_weather")
	queue_redraw()

func _build_animated_water() -> void:
	preload("res://geodata/nature/WaterPresentation.gd").rectangle(self, Rect2(-5000, 2480, 8200, 10000), Color("204754"))
	preload("res://geodata/nature/WaterPresentation.gd").fountain(self, FOUNTAIN_POSITION)

func _has_terminal() -> bool:
	return get_parent() != null and get_parent().has_node("ArrivalStop")

func _bench_points() -> Array[Vector2]:
	var points: Array[Vector2] = [Vector2(1650, 2070), Vector2(1920, 2070)]
	if not _has_terminal():
		points.append_array([Vector2(1575, 870), Vector2(1910, 870), Vector2(1575, 1060), Vector2(1910, 1060)])
	return points

func _build_street_lamps() -> void:
	const LAMP_SCRIPT := preload("res://geodata/StreetLamp.gd")
	for p in get_street_lamp_points():
		if name == "District" and LOCAL_STREETS.reserves(p.pos, 12.0): continue
		var blocked:=false
		for site in sites:
			if (site.bounds as Rect2).grow(12).has_point(p.pos): blocked=true
		if blocked: continue
		var lamp := LAMP_SCRIPT.new()
		lamp.position = p.pos
		lamp.is_facing_south = p.south
		add_child(lamp)

func _bind_street_lamp_weather() -> void:
	var weather := get_tree().get_first_node_in_group("day_night_manager")
	if weather == null:
		return
	for lamp in get_children():
		if lamp is StreetLamp:
			if not weather.time_changed.is_connected(lamp.set_lit):
				weather.time_changed.connect(lamp.set_lit)
			lamp.set_lit(weather.is_dark)

func get_street_lamp_points() -> Array[Dictionary]:
	var points: Array[Dictionary] = [
		{"pos": Vector2(506, 508), "south": false},
		{"pos": Vector2(738, 508), "south": false},
		{"pos": Vector2(506, 1136), "south": true},
		{"pos": Vector2(743, 1136), "south": true},
		{"pos": Vector2(1174, 1136), "south": true},
	]
	# Replace the old painted round fixtures with working modern street lamps.
	for point in [Vector2(1465, 955), Vector2(2015, 955), Vector2(500, 550), Vector2(1195, 550), Vector2(2320, 1390), Vector2(2890, 1390)]:
		if _has_terminal() and TERMINAL_LOT.has_point(point):
			continue
		points.append({"pos": point, "south": true})
	for x in [650,1000,1550,1900,2450,2800]:
		for y in [315,515,1165,1335,2285]:
			# Keep the bank entrance axis clear; the lamp belongs beside the frontage.
			var lamp_point := Vector2(790,285) if x == 650 and y == 315 else Vector2(x,y)
			if x == 1550 and y == 315:
				lamp_point.x += 70.0 # Keep the Ammu-Nation street-to-door approach clear.
			# The route 510 convoy uses more curb length than a rigid vehicle while
			# its two joints straighten after these corners. Keep the physical lamp
			# bases on the same sidewalk, beyond that swept tail envelope.
			if x == 650 and y == 2285:
				lamp_point.x = 800.0
			elif x == 2800 and y == 315:
				lamp_point.x = 2650.0
			points.append({"pos":lamp_point,"south":y in [315,1165]})
	for x in [315,485,1215,1385,2115,2285]:
		for y in [850,1650,1950]:
			# Keep the medical yard's turning aisle clear; its lamp is on the footway.
			var lamp_point := Vector2(2136, y) if x == 2115 and y == 1650 else Vector2(x,y)
			# Keep the complete 28px east alley clear, including its outer edge.
			if x==1215 and y==850: lamp_point.x=1204
			points.append({"pos":lamp_point,"south":true})
	return points



func _building(id: String, center: Vector2, size: Vector2, kind: String, title: String, accent_color: String, entrance: Dictionary = {}) -> void:
	var bounds := Rect2(center - size * 0.5, size)
	sites.append({"id": id, "bounds": bounds, "kind": kind})
	if baked_from_editor:
		return
	var building := preload("res://world/harbor/hospital/HarborHospital.gd").new() if id == "Clinic" else BUILDING.new()
	building.name = id
	building.position = center
	building.footprint = size
	building.building_kind = kind
	building.business_name = title
	building.accent = Color(accent_color)
	building.variant_seed = sites.size() * 17
	building.entrance_offset = float(entrance.get("offset", 0.0))
	building.entrance_north = bool(entrance.get("north", false))
	add_child(building)

func _access(id: String, bounds: Rect2, destination: Vector2, vehicle: bool) -> void:
	accesses.append({"id": id, "bounds": bounds, "destination": destination, "vehicle": vehicle})
	if baked_from_editor:
		return
	var marker := Marker2D.new()
	marker.name = id
	marker.position = destination
	add_child(marker)

func _build_sites() -> void:
	# A built northern frontage frames Foundry Avenue as a city street rather
	# than the edge of a closed racing circuit. Its entries face the avenue.
	for i in 6:
		var x: float = [650, 990, 1550, 1890, 2460, 2780][i]
		var title: String = ["BANCO / NORTH PIER", "FOUNDRY FLATS", "ROAST / COFFEE", "ROUPAS / UNION", "POSTO / CONVENIÊNCIA", "CUSTOMS HOUSE"][i]
		_building("NorthFrontage%d" % i, Vector2(x, 140), Vector2(230, 180), "bank_branch" if i == 0 else ("brownstone" if i < 4 else "office"), title, "#a9b9a5")
		_access("NorthEntry%d" % i, Rect2(x - 25, 230, 50, 170), Vector2(x, 270), false)
	# Quadra 1 Pilot: Westgate Core
	# North frontage: authentic semi-detached rowhouse terraces (construções geminadas) facing Foundry Ave
	_building("FoundryTerraceWest", Vector2(621, 640), Vector2(210, 230), "rowhouse_terrace", "FOUNDRY TERRACES W", "#a87d60")
	_building("FoundryTerraceEast", Vector2(855, 640), Vector2(210, 230), "rowhouse_terrace", "FOUNDRY TERRACES E", "#94765a")

	# Northeast corner: L-shaped industrial loft complex with courtyard wing
	_building("FoundryLofts", Vector2(1077, 655), Vector2(186, 260), "l_shaped_block", "UNION LOFTS & WORKS", "#8b6e58")
	# Southwest corner: authentic Corner Building (Edifício de Esquina) facing Westgate Dr x Market St
	_building("CornerDiner", Vector2(621, 1040), Vector2(210, 160), "corner_shop", "ANCHOR DINER", "#e49d68")
	# Southeast frontage: Market St street-level retail and laundry (distinct facades, proportions, and uses)
	_building("Laundry", Vector2(845, 1045), Vector2(170, 150), "commercial_laundromat", "WASH / DRY", "#4a8084")
	_building("UnionWorkshop", Vector2(1065, 1038), Vector2(195, 164), "artisan_workshop", "HARBOR BINDERY", "#825a47")
	_building("MarketHall", Vector2(1750, 665), Vector2(480, 220), "warehouse_shop", "BREAKWATER MARKET", "#d1a866")
	_building("ColdStorage", Vector2(2600, 710), Vector2(420, 280), "warehouse", "COLD STORAGE  /  04", "#78afb6")
	_building("Garage", LOCAL_STREETS.GARAGE_POSITION, Vector2(390, 250), "garage", "WESTGATE MOTOR CO.", "#e8b44f", {"offset": -40.0})
	_building("Police", LOCAL_STREETS.POLICE_POSITION, Vector2(190, 250), "police_precinct", "HARBOR PATROL", "#68a8d3")
	_building("Clinic", MEDICAL_PARKING.CLINIC_POSITION, Vector2(260, 230), "hospital", "BAY MEDICAL", "#78c7bd")
	_building("Apartments", Vector2(1550, 1530), Vector2(185, 230), "office", "UNION LOFTS", "#c89f85")
	_building("FreightOffice", Vector2(2520, 1510), Vector2(285, 170), "office", "PORT AUTHORITY", "#c1b37c")
	_building("FreightDepot", Vector2(2570, 1930), Vector2(330, 260), "warehouse", "TRANSATLANTIC / 02", "#c97d57")
	# Access strips end at building fronts, never inside building solids.
	_access("GarageAccess", Rect2(620, 1620, 160, 98), Vector2(750, 1660), true)
	_access("GarageSouthAccess", Rect2(640, 1718, 140, 482), Vector2(710, 2100), true)
	_access("PatrolNorthAccess", Rect2(899, 1718, 80, 372), Vector2(939, 1718), true)
	_access("MedicalSouthAccess", Rect2(2041, 1690, 84, 270), Vector2(2083, 1960), true)
	_access("PatrolAccess", Rect2(904, 1990, 70, 100), Vector2(939, 2045), true)
	_access("PatrolWalk", Rect2(985, 2075, 190, 65), Vector2(1080, 2120), false)
	if _has_terminal():
		# The market is reached along its northern terminal-side promenade.
		_access("MarketAccess", Rect2(1820, 775, 50, 45), Vector2(1845, 800), false)
	else:
		_access("MarketAccess", Rect2(1820, 775, 50, 475), Vector2(1845, 820), false)
	_access("ColdStorageAccess", Rect2(2450, 850, 310, 400), Vector2(2600, 1040), true)
	_access("ClinicAccess", Rect2(1750, 1645, 100, 120), Vector2(1800, 1705), false)
	# Both medical services park fully inside the shared yard, behind its aisle.
	_access("ClinicVehicleAccess", Rect2(1930, 1533, 215, 74), MEDICAL_PARKING.AMBULANCE_STOP, true)
	_access("CoronerVehicleAccess", Rect2(1930, 1418, 215, 74), MEDICAL_PARKING.CORONER_STOP, true)
	_access("FreightAccess", Rect2(2375, 2060, 390, 140), Vector2(2550, 2115), true)
	_access("PortOfficeWalk", Rect2(2365, 1250, 100, 175), Vector2(2415, 1380), false)
	_access("DinerWalk", Rect2(590, 1120, 62, 28), Vector2(621, 1136), false)
	_access("LaundryWalk", Rect2(815, 1120, 60, 28), Vector2(845, 1136), false)
	_access("WorkshopWalk", Rect2(1035, 1120, 60, 28), Vector2(1065, 1136), false)
	_access("LoftsWalk", Rect2(1520, 1645, 60, 95), Vector2(1550, 1690), false)
	_access("HomesWalk", Rect2(730, 860, 26, 270), Vector2(743, 880), false)


## MountainPine3D compartilha um SubViewport 3D entre árvores do mesmo pai
## via get_parent().add_child() síncrono (diferente do StreetLamp, que já
## posterga pro root da árvore). Isso só funciona quando cada árvore entra na
## cena ao vivo, uma de cada vez -- dentro de uma subárvore congelada e
## pré-montada pelo bake, o pai ainda está "montando filhos" no momento em
## que MountainPine3D tenta anexar sua view, e o Godot recusa. Por isso as
## árvores de memorial ficam de fora do congelamento (_ready() sempre chama
## esta função, congelado ou não) até esse código de view compartilhada
## receber o mesmo conserto que o StreetLamp.gd já tem.
func _build_memorial_trees() -> void:
	# Memorial's east buffer used painted circles, including one row beneath
	# Memorial North. Plant only the free pockets between roads and footways.
	for x in [45, 205]:
		for y in [1100, 1640, 1820, 2000]:
			if has_node("MemorialTree_%d_%d" % [x, y]):
				continue
			var memorial_tree := preload("res://world/mountain_pass/MountainPine3D.gd").new()
			memorial_tree.name = "MemorialTree_%d_%d" % [x, y]
			memorial_tree.position = Vector2(x,y)
			memorial_tree.variant_seed = 3 if x == 45 else 4
			memorial_tree.tree_scale = .85
			memorial_tree.add_to_group("memorial_verge_tree")
			add_child(memorial_tree)

func _build_trees() -> void:
	var positions: Array[Vector2] = []
	for x in [1465, 2015]:
		for y in [865, 1025]:
			positions.append(Vector2(x, y))
	for x in [1460, 1750, 2040]:
		for y in [1840, 2040]:
			positions.append(Vector2(x, y))
	# Quadra 1 organic tree placement:
	positions.append(Vector2(650, 805))
	positions.append(Vector2(880, 805))
	for point in positions:
		if name == "District" and LOCAL_STREETS.reserves(point, 32.0): continue
		if _has_terminal() and TERMINAL_LOT.grow(22).has_point(point):
			continue
		var tree := TREE.new()
		tree.position = point
		tree.crown_scale = 1.25
		tree.variant_seed = int(point.x + point.y)
		add_child(tree)

func _build_boundaries() -> void:
	# Water owns the east boundary. Rail is fenced off south of the playable streets.
	# Each wall is also tagged "traffic_hard_boundary" with its local AABB so
	# ambient traffic lanes ending nearby -- westgate_drive/union_avenue/
	# warehouse_way/quay_boulevard all terminate at dock_street (y=2200), only
	# ~190px from the seawall curb below -- brake with a safety margin instead
	# of coming to rest right at the wall's doorstep. See TrafficVehicle.gd's
	# _lane_end_boundary_margin().
	for rect in [Rect2(-130, -130, 30, 1200), Rect2(-1450, 1070, 140, 25), Rect2(-1190, 1070, 1060, 25), Rect2(-1450, 1070, 25, 1338), Rect2(-1450, 2390, 1350, 18), Rect2(-130, -130, 3360, 30), Rect2(-100, 2390, 3165, 18), Rect2(3170, 2390, 30, 18), Rect2(-5000, 3500, 8200, 6500)]:
		var body := StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = rect.get_center()
		var collision := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		collision.shape = shape
		body.add_child(collision)
		body.add_to_group("traffic_hard_boundary")
		body.set_meta("boundary_aabb_local", Rect2(-rect.size * 0.5, rect.size))
		add_child(body)
	var southern_water := StaticBody2D.new()
	southern_water.name = "SouthernWaterBoundary"
	southern_water.collision_layer = 1
	southern_water.collision_mask = 0
	var coast := CollisionPolygon2D.new()
	coast.polygon = PackedVector2Array([Vector2(-5000, 2480), Vector2(2853, 2480), Vector2(2890, 3330), Vector2(3010, 3500), Vector2(-5000, 3500)])
	southern_water.add_child(coast)
	southern_water.add_to_group("traffic_hard_boundary")
	southern_water.set_meta("boundary_aabb_local", _polygon_aabb(coast.polygon))
	add_child(southern_water)

func _polygon_aabb(points: PackedVector2Array) -> Rect2:
	var aabb := Rect2(points[0], Vector2.ZERO)
	for p in points:
		aabb = aabb.expand(p)
	return aabb

func _build_site_solids() -> void:
	# Props that look solid are solid; footprints also feed the runtime audit.
	var obstacles: Array[Rect2] = []
	var storage := preload("res://world/harbor/HarborStorageArt.gd").new()
	storage.name = "HarborStorageArt"
	storage.position = Vector2(2600, 1700)
	add_child(storage)
	if name == "District":
		var supplies := preload("res://world/harbor/HarborGarageSupplies.gd").new()
		supplies.name = "GarageSupplies"
		supplies.position = Vector2(1090, 1495)
		add_child(supplies)
	for point in _bench_points():
		obstacles.append(Rect2(point, Vector2(65, 19)))
	for rect in obstacles:
		var body := StaticBody2D.new()
		body.position = rect.get_center()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		var collision := CollisionShape2D.new()
		collision.shape = shape
		body.add_child(collision)
		add_child(body)
	var fountain := StaticBody2D.new()
	fountain.name = "FountainSolid"
	fountain.position = FOUNTAIN_POSITION
	fountain.collision_layer = 1
	fountain.collision_mask = 0
	var circle := CircleShape2D.new()
	circle.radius = 60
	var collision := CollisionShape2D.new()
	collision.shape = circle
	fountain.add_child(collision)
	add_child(fountain)

func get_spatial_audit() -> Array[String]:
	var errors: Array[String] = []
	var layout := get_node_or_null("../RoadLayout")
	if layout == null:
		errors.append("RoadLayout missing")
		return errors
	var definitions: Array = layout.get_road_graph_definitions()
	for i in sites.size():
		var site := sites[i]
		# Covers roof shadow as well as solid footprint, not just the center marker.
		var bounds: Rect2 = site.bounds.grow(18)
		for road in definitions:
			var points: PackedVector2Array = road.points
			for j in range(points.size() - 1):
				var reserved := Rect2(points[j], Vector2.ZERO).expand(points[j + 1]).grow(float(road.width) * 0.5 + 42.0)
				if reserved.intersects(bounds):
					errors.append("%s invades road/sidewalk %s" % [site.id, road.id])
		for j in range(i + 1, sites.size()):
			if bounds.intersects(sites[j].bounds):
				errors.append("Overlapping buildings: %s / %s" % [site.id, sites[j].id])
		for access in accesses:
			if site.bounds.grow(-1).intersects(access.bounds):
				errors.append("%s blocks access %s" % [site.id, access.id])
	return errors

func _draw() -> void:
	# The descent to the tunnel follows a narrow built embankment, not a larger
	# rectangular lawn. The return railway is underground beyond the portal.
	SURFACE.paint(self,LAND_BOUNDS, Color("#6b7067"),"concrete")
	SURFACE.paint(self,Rect2(-1450,1070,1850,1320), Color("#52674e"),"grass")
	draw_colored_polygon(PackedVector2Array([Vector2(2850, 2410), Vector2(3200, 2410), Vector2(3200, 3500), Vector2(3010, 3500), Vector2(2890, 3330)]), Color("#747a69"))
	draw_colored_polygon(PackedVector2Array([Vector2(3010, 3110), Vector2(3200, 3160), Vector2(3200, 3480), Vector2(3030, 3450), Vector2(2940, 3280)]), Color("#576255"))
	for point in [Vector2(2980, 3120), Vector2(2940, 3190), Vector2(2980, 3370), Vector2(3060, 3440), Vector2(3170, 3390)]:
		draw_colored_polygon(PackedVector2Array([point + Vector2(-28, 13), point + Vector2(-17, -24), point + Vector2(15, -30), point + Vector2(36, 5), point + Vector2(13, 21)]), Color("#919084"))
	# Compact rear gardens, fenced service pockets and a planted west buffer.
	SURFACE.paint(self,Rect2(515, -45, 2390, 310), Color("#9b9787"),"concrete")
	for x in [650, 990, 1550, 1890, 2460, 2780]:
		SURFACE.paint(self,Rect2(x - 135, -35, 270, 65), Color("#4f6658"),"grass")
		preload("res://geodata/nature/GrassDetail.gd").paint(self, Rect2(x - 130, -30, 260, 55), x)
		draw_line(Vector2(x - 135, -35), Vector2(x + 135, -35), Color("#b1ac97"), 3)
	SURFACE.paint(self,Rect2(10, 500, 225, 1670), Color("#536b5b"),"grass")
	preload("res://geodata/nature/GrassDetail.gd").paint(self, Rect2(10, 500, 225, 1670), 71)
	SURFACE.paint(self,Rect2(93, 500, 45, 1670), Color("#b4aa95"),"stone")
	for y in range(560, 2140, 180):
		if y >= 1070: continue # Memorial buffer now uses solid 3D trees.
		for x in [45, 205]:
			draw_circle(Vector2(x + 6, y + 8), 33, Color("#3d4f44"))
			draw_circle(Vector2(x, y), 30, Color("#446b53"))
			draw_circle(Vector2(x - 8, y - 7), 20, Color("#557d5e"))
	# Footways connect the planted buffer to the two neighborhood streets.
	for y in [620, 1435, 2100]:
		SURFACE.paint(self,Rect2(95, y, 305, 40), Color("#b4aa95"),"stone")
	# Flush planted strips occupy empty outer pavement, leaving the promenade open.
	for patch in [Rect2(265,-55,150,300),Rect2(2930,-40,190,240),Rect2(2940,560,100,420),Rect2(2940,1480,100,560)]:
		preload("res://world/harbor/ExteriorFinish.gd").meadow(self,patch,int(patch.position.y)+930)
	for x in [520,1440,2310]:
		SURFACE.paint(self,Rect2(x,2340,230,24),Color("707b58"),"grass")
		SURFACE.garden_edge(self,Rect2(x,2340,230,24),x)
	# Authored district blocks replace the old grass blanket.
	for block in [Rect2(510, 510, 680, 630), Rect2(1410, 510, 680, 630), Rect2(2310, 510, 580, 630), Rect2(510, 1360, 680, 730), Rect2(1410, 1360, 680, 730), Rect2(2310, 1360, 580, 730)]:
		SURFACE.paint(self,block, Color("#a69f8c"),"concrete")
		# Shallow curb attached to the paving, with a lit lip and dark riser.
		draw_line(Vector2(block.position.x, block.end.y - 3), Vector2(block.end.x, block.end.y - 3), Color("#c4bba7"), 2)
		draw_line(Vector2(block.position.x, block.end.y), block.end, Color("#6b665d"), 3)
		draw_line(Vector2(block.end.x - 1, block.position.y), block.end - Vector2(1, 0), Color("#777064"), 2)
		draw_rect(block.grow(-8), Color("#8e897b"), false, 2)
	# Quadra 1: residential courtyard, landscaped garden pocket, service yard, and diner café
	_draw_quadra1_urban_spaces()

	SURFACE.paint(self,Rect2(1440, 790, 620, 345), Color("#b7ad96"),"stone")
	for x in range(1440, 2060, 40):
		draw_line(Vector2(x, 795), Vector2(x, 1135), Color("#a49d8c"), 1)
	for y in range(795, 1135, 40):
		draw_line(Vector2(1440, y), Vector2(2060, y), Color("#a49d8c"), 1)
	# Union plaza shares the sidewalk concrete and world-aligned tile grid.
	SURFACE.paint(self,Rect2(1440, 1740, 620, 330), Color("#aaa9a1"),"concrete")
	SURFACE.paint(self,Rect2(1440, 1910, 620, 65), Color("#aaa9a1"),"concrete")
	SURFACE.paint(self,Rect2(1515, 1660, 70, 475), Color("#aaa9a1"),"concrete")
	_draw_court(Rect2(1785, 1745, 205, 120))
	for access in accesses:
		SURFACE.paint(self,access.bounds, Color("#676e70") if access.vehicle else Color("#aaa9a1"),"concrete")
		SURFACE.yard(self,access.bounds,int(access.bounds.position.x),access.vehicle)
	# Parking belongs beside the driveway, outside the door/turning corridor.
	SURFACE.foundations(self,sites)
	SURFACE.paint(self,Rect2(520, 1810, 100, 270), Color("#656b6b"),"concrete")
	SURFACE.yard(self,Rect2(520,1810,100,270),913,true)
	for y in [1810, 1945, 2080]:
		draw_line(Vector2(520, y), Vector2(610, y), Color("#d8cfab"), 2)
	draw_line(Vector2(520, 1810), Vector2(520, 2080), Color("#d8cfab"), 2)
	_draw_parking(Rect2(2480, 935, 280, 180), 3)
	# The plaza's water feature has an explicit solid, added by the preview audit.
	draw_circle(FOUNTAIN_POSITION, 60, Color("#7b8078"))
	draw_circle(FOUNTAIN_POSITION, 51, Color("#397d86"))
	draw_arc(FOUNTAIN_POSITION, 40, 0, TAU, 48, Color("#92c3be"), 2, true)
	draw_circle(FOUNTAIN_POSITION, 13, Color("#c4c4ad"))
	for point in _bench_points():
		_draw_bench(point)
	# Rail service strip, fenced from road users; no hidden road/train overlap.
	draw_rect(Rect2(-100, 2390, 3300, 80), Color("#7a786c"))
	SURFACE.paint(self,Rect2(300, 2330, 2700, 45), Color("#c0b79e"),"stone")
	draw_line(Vector2(-100, 2470), Vector2(2850, 2470), Color("#a5a899"), 8)
	for x in range(-100, 3065, 55):
		draw_line(Vector2(x, 2390), Vector2(x, 2405), Color("#333e43"), 3)
	draw_line(Vector2(-100, 2396), Vector2(3065, 2396), Color("#b2b3a6"), 2)
	draw_line(Vector2(3170, 2396), Vector2(3200, 2396), Color("#b2b3a6"), 2)

func _draw_quadra1_urban_spaces() -> void:
	# 1. Residential Courtyard & Garden (North half: between rowhouses and rail line)
	# Stone paving for the pedestrian courtyard
	SURFACE.paint(self,Rect2(520, 755, 450, 100), Color("#b5ad9a"),"stone")
	for x in range(530, 970, 36):
		draw_line(Vector2(x, 755), Vector2(x, 855), Color("#a39a86"), 1.0)
	for y in range(755, 855, 25):
		draw_line(Vector2(520, y), Vector2(970, y), Color("#a39a86"), 1.0)
	
	# Lush garden pocket
	SURFACE.paint(self,Rect2(545, 770, 220, 70), Color("#4d6655"),"grass")
	SURFACE.paint(self,Rect2(545, 770, 220, 70).grow(-2), Color("#445d4b"),"grass")
	preload("res://geodata/nature/GrassDetail.gd").paint(self, Rect2(549, 774, 212, 62), 105)
	SURFACE.garden_edge(self,Rect2(549,774,212,62),105)
	draw_rect(Rect2(545, 770, 220, 70), Color("#8e8a7b"), false, 2.0)
	# Garden footpath
	draw_colored_polygon(PackedVector2Array([
		Vector2(650, 755), Vector2(665, 755), Vector2(665, 840), Vector2(650, 840)
	]), Color("#c5bcab"))
	# Park benches in courtyard garden
	_draw_bench(Vector2(565, 775))
	_draw_bench(Vector2(695, 775))
	# Garden birdbath / ornamental fountain
	draw_circle(Vector2(657, 800) + Vector2(1, 2), 7, Color(0.04, 0.05, 0.06, 0.35))
	draw_circle(Vector2(657, 800), 7, Color("#8c8577"))
	draw_circle(Vector2(657, 800), 5, Color("#48818a"))
	
	# Pedestrian passage alley from Foundry Ave (between West and East terraces)
	SURFACE.paint(self,Rect2(726, 520, 24, 235), Color("#a8a18e"),"concrete")
	for y in range(525, 755, 18):
		draw_line(Vector2(727, y), Vector2(749, y), Color("#968e7d"), 1.0)
	
	# 2. Rear Service Yard & Alley (South/East quadrant)
	# HarborAlleys owns the walkable service passages; do not redraw the old
	# 40px strip that overlapped the Laundry's west wall.
	# Rear industrial yard behind shops and beneath rail viaduct
	SURFACE.paint(self,Rect2(766, 855, 404, 105), Color("#5c605f"),"concrete")
	# Concrete slab expansion seams
	for x in range(780, 1170, 60):
		draw_line(Vector2(x, 855), Vector2(x, 960), Color("#484c4b"), 1.0)
	draw_line(Vector2(766, 910), Vector2(1170, 910), Color("#484c4b"), 1.0)
	
	# Service props in rear yard:
	# Commercial dumpsters
	_draw_service_dumpster(Rect2(915, 875, 44, 26), Color("#3d5e4a"))
	_draw_service_dumpster(Rect2(968, 875, 40, 26), Color("#385369"))
	# HVAC outdoor chiller units
	_draw_service_hvac(Rect2(1020, 876, 26, 22))
	_draw_service_hvac(Rect2(1052, 876, 26, 22))
	# Stacked wooden cargo pallets
	_draw_service_pallets(Rect2(870, 878, 28, 26))
	# Storm drain catch basin grate
	draw_rect(Rect2(780, 915, 20, 16), Color("#2b2e30"))
	draw_rect(Rect2(782, 917, 16, 12), Color("#181a1c"))
	for gx in range(784, 797, 3):
		draw_line(Vector2(gx, 918), Vector2(gx, 928), Color("#3e4345"), 1.5)
	
	# 3. Sidewalk Café Terrace for Anchor Diner (SW Corner)
	SURFACE.paint(self,Rect2(516, 1120, 210, 28), Color("#a97155"),"brick") # Terracotta paving
	for tx in range(516, 726, 15):
		draw_line(Vector2(tx, 1120), Vector2(tx, 1148), Color("#915f47"), 1.0)
	# Planter boxes along sidewalk boundary
	draw_rect(Rect2(522, 1142, 54, 6), Color("#543f32"))
	draw_rect(Rect2(523, 1141, 52, 4), Color("#497552"))
	draw_rect(Rect2(662, 1142, 54, 6), Color("#543f32"))
	draw_rect(Rect2(663, 1141, 52, 4), Color("#497552"))
	# Mesas, cadeiras e clientes 3D são criados por HarborRestaurantLife.

func _draw_service_dumpster(rect: Rect2, color: Color) -> void:
	# Drop shadow
	draw_rect(Rect2(rect.position + Vector2(3, 4), rect.size), Color(0.04, 0.05, 0.06, 0.35))
	# Dumpster steel body
	draw_rect(rect, color)
	draw_rect(rect.grow(-2), color.lightened(0.15))
	# Hinged split lids
	var half_w := rect.size.x * 0.5
	draw_rect(Rect2(rect.position, Vector2(half_w - 1, rect.size.y * 0.45)), Color("#26292b"))
	draw_rect(Rect2(rect.position + Vector2(half_w + 1, 0), Vector2(half_w - 1, rect.size.y * 0.45)), Color("#26292b"))
	# Plastic lid handles
	draw_line(rect.position + Vector2(6, 4), rect.position + Vector2(half_w - 6, 4), Color("#51575b"), 2.0)
	draw_line(rect.position + Vector2(half_w + 6, 4), rect.position + Vector2(rect.size.x - 6, 4), Color("#51575b"), 2.0)

func _draw_service_hvac(rect: Rect2) -> void:
	draw_rect(Rect2(rect.position + Vector2(3, 4), rect.size), Color(0.04, 0.05, 0.06, 0.35))
	draw_rect(rect, Color("#363a3d"))
	draw_rect(rect.grow(-2), Color("#60676b"))
	for y in range(4, int(rect.size.y - 4), 4):
		draw_line(rect.position + Vector2(4, y), rect.position + Vector2(rect.size.x - 4, y), Color("#26292b"), 1.5)
	# Fan circle
	draw_circle(rect.get_center(), 5, Color("#26292b"))
	draw_circle(rect.get_center(), 2, Color("#959da3"))

func _draw_service_pallets(rect: Rect2) -> void:
	draw_rect(Rect2(rect.position + Vector2(3, 3), rect.size), Color(0.04, 0.05, 0.06, 0.35))
	draw_rect(rect, Color("#8c6e49"))
	# Wooden slats
	for y in range(3, int(rect.size.y), 6):
		draw_line(rect.position + Vector2(2, y), rect.position + Vector2(rect.size.x - 2, y), Color("#aa8b62"), 3.0)
		draw_line(rect.position + Vector2(2, y + 2), rect.position + Vector2(rect.size.x - 2, y + 2), Color("#574229"), 1.0)

func _draw_cafe_table(pos: Vector2, umbrella_color: Color) -> void:
	# Chairs
	draw_circle(pos + Vector2(-9, 0), 3, Color("#5e4a3d"))
	draw_circle(pos + Vector2(9, 0), 3, Color("#5e4a3d"))
	# Umbrella shadow
	draw_circle(pos + Vector2(3, 4), 8, Color(0.04, 0.05, 0.06, 0.30))
	# Tabletop umbrella
	draw_circle(pos, 8, umbrella_color)
	draw_circle(pos, 8, umbrella_color.darkened(0.2), false, 1.5)
	draw_circle(pos, 2, Color("#f5ebd8"))


func _draw_parking(rect: Rect2, spaces: int) -> void:
	SURFACE.paint(self,rect, Color("#656b6b"),"concrete")
	SURFACE.yard(self,rect,spaces*931,true)
	var step := rect.size.x / spaces
	for i in range(spaces + 1):
		var start := rect.position + Vector2(i * step, 0)
		draw_line(start, start + Vector2(0, minf(85, rect.size.y)), Color("#d8cfab"), 2)

func _draw_container(rect: Rect2, color: Color) -> void:
	draw_rect(Rect2(rect.position + Vector2(4, 5), rect.size), Color("#424b49"))
	draw_rect(rect, color)
	draw_rect(rect.grow(-3), color.lightened(0.25), false, 2)
	for x in range(int(rect.position.x + 8), int(rect.end.x - 4), 9):
		draw_line(Vector2(x, rect.position.y + 4), Vector2(x, rect.end.y - 4), color.darkened(0.2), 2)

func _draw_bench(point: Vector2) -> void:
	draw_texture_rect(preload("res://systems/ContactShadow.gd").texture(), Rect2(point + Vector2(-4, -1), Vector2(77, 27)), false, Color(0.025,0.03,0.045,0.40))
	draw_rect(Rect2(point, Vector2(65, 19)), Color("#594e42"))
	for y in [3, 8, 13]:
		draw_line(point + Vector2(3, y), point + Vector2(62, y), Color("#bd9b69"), 3)

func _draw_court(rect: Rect2) -> void:
	draw_rect(rect.grow(9), Color("#344d4b"))
	draw_rect(rect, Color("#537b73"))
	draw_rect(rect.grow(-6), Color("#d2ceac"), false, 2)
	draw_line(rect.position + Vector2(rect.size.x * 0.5, 6), Vector2(rect.get_center().x, rect.end.y - 6), Color("#d2ceac"), 2)
	draw_circle(rect.get_center(), 23, Color("#d2ceac"), false, 2)

func _draw_label(point: Vector2, text: String, size: int, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, point, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
