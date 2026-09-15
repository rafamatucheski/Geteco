@tool
extends Node2D

## Ashbend Court: authored residential enclave. Roads belong exclusively to
## UnifiedRoadNetwork2D; this provider never paints a second asphalt surface.
const FINISH := preload("res://world/harbor/ExteriorFinish.gd")
const SURFACE := preload("res://world/harbor/UrbanGround.gd")
const HOUSE := preload("res://world/harbor/cobras/CobraResidence.gd")
const LAMP := preload("res://geodata/StreetLamp.gd")
const BARREL := preload("res://world/harbor/cobras/CobraBurningBarrel.gd")
const BARRICADE := preload("res://world/harbor/cobras/CobraBarricade.gd")
const CENTER := Vector2(7700, 1700)
const RADIUS := 300.0
const WIDTH := 84.0
const LAND := Rect2(6510, 960, 2010, 1450)
const VISUAL_LAND := Rect2(6760, 960, 1760, 1450)
const SITES := [
	{"id":"PorchHouse", "rect":Rect2(6980, 1260, 220, 160), "kind":0, "color":Color("72594b")},
	{"id":"Duplex", "rect":Rect2(7410, 1060, 250, 165), "kind":1, "color":Color("726d53")},
	{"id":"ShingleHouse", "rect":Rect2(7850, 1110, 225, 155), "kind":2, "color":Color("4e6260")},
	{"id":"CobraWorkshop", "rect":Rect2(8230, 1390, 220, 255), "kind":3, "color":Color("655343")},
	{"id":"CourtyardHouse", "rect":Rect2(8250, 1890, 205, 170), "kind":0, "color":Color("775e54")},
	{"id":"BrickDuplex", "rect":Rect2(7870, 2170, 260, 170), "kind":1, "color":Color("765043")},
	{"id":"TinRoofHouse", "rect":Rect2(7440, 2170, 220, 145), "kind":2, "color":Color("596454")},
	{"id":"CornerBungalow", "rect":Rect2(6930, 2010, 235, 155), "kind":0, "color":Color("6c6759")},
]
const ROUTES := [
	[Vector2(6730,1580), Vector2(7220,1580), Vector2(7250,1450), Vector2(7290,1290), Vector2(7730,1290), Vector2(8150,1290), Vector2(8150,1760)],
	[Vector2(6730,1820), Vector2(7200,1820), Vector2(7300,2080), Vector2(7750,2080), Vector2(8170,2080), Vector2(8170,1760)],
	[Vector2(7700,1290), Vector2(7740,1040)],
	[Vector2(7750,2080), Vector2(7750,2360)],
]
const LANDSCAPE := [
	["court_shade_west","shade",Vector2(7580,1610),40.0],
	["court_shade_south","shade",Vector2(7730,1820),36.0],
	["western_elm","shade",Vector2(6800,1100),43.0],
	["western_sapling","dry",Vector2(6910,1130),23.0],
	["dry_backyard","dry",Vector2(7240,1090),26.0],
	["southern_dry","dry",Vector2(7340,2350),24.0],
	["east_wind_tree","dry",Vector2(8370,2230),27.0],
	["north_coast_rock","coastal",Vector2(8410,1040),34.0],
	["north_coast_scrub","coastal",Vector2(8448,1190),24.0],
	["south_coast_rock","coastal",Vector2(8445,2340),31.0],
	["south_coast_scrub","coastal",Vector2(8380,2370),22.0],
]
var _landscape_cache: Array[Dictionary] = []
const PARKING := {"workshop":Vector2(8340,1750), "secret":Vector2(7050,2290)}
const ENTRANCE_PATHS := [
	[Vector2(7119,1420),Vector2(7119,1580)],
	[Vector2(7472,1225),Vector2(7472,1290)],
	[Vector2(7597,1225),Vector2(7597,1290)],
	[Vector2(7992,1265),Vector2(7992,1290)],
	[Vector2(8340,1645),Vector2(8340,1750),Vector2(8150,1750)],
	[Vector2(8379,2060),Vector2(8379,2110),Vector2(8170,2110),Vector2(8170,2080)],
	[Vector2(7935,2340),Vector2(7935,2360),Vector2(7750,2360)],
	[Vector2(8065,2340),Vector2(8065,2360),Vector2(7935,2360)],
	[Vector2(7579,2315),Vector2(7579,2360),Vector2(7750,2360)],
	[Vector2(7078,2165),Vector2(7078,2200),Vector2(7220,2200),Vector2(7220,1820)],
]
const SECRET_DRIVE := [Vector2(7050,2290),Vector2(7220,2290),Vector2(7220,1700)]
const FENCES := [
	[Vector2(6870,1230),Vector2(6870,1440)],
	[Vector2(7380,1005),Vector2(7650,1005)],
	[Vector2(7860,2385),Vector2(8150,2385)],
]

func _ready() -> void:
	z_index = 0
	add_to_group("cobra_neighborhood")
	if has_node("Buildings"):
		return
	var buildings := Node2D.new()
	buildings.name = "Buildings"
	add_child(buildings)
	for site in SITES:
		var house := HOUSE.new()
		house.name = site.id
		house.position = site.rect.position
		house.size = site.rect.size
		house.variant = site.kind
		house.wall_color = site.color
		buildings.add_child(house)
	for feature in get_landscape_definitions():
		if feature.kind == "coastal": continue
		var p: Vector2 = feature.center
		var trunk := StaticBody2D.new()
		trunk.name = "TreeTrunk"
		trunk.set_meta("impact_material", &"wood")
		trunk.position = p
		trunk.collision_layer = 1
		trunk.collision_mask = 0
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 8.0
		shape.shape = circle
		trunk.add_child(shape)
		add_child(trunk)
		# A copa é pintada no chão do bairro; repete-a sobre quem passa atrás do
		# tronco para o ator não parecer em pé sobre a árvore.
		var canopy := Node2D.new()
		canopy.name = "TreeCanopyOcclusion"
		add_child(canopy)
		preload("res://world/shared/interiors/ExteriorOcclusion.gd").attach_drawn(canopy, feature.bounds, p.y, func(canvas: CanvasItem): _draw_landscape(feature, canvas))
	for p in [Vector2(6890,1635),Vector2(7170,1765),Vector2(7450,1450),Vector2(7980,1450),Vector2(8010,1920),Vector2(7450,1960)]:
		var lamp := LAMP.new()
		lamp.position = p
		add_child(lamp)
	# Território hostil: barris de fogo nos três postos de guarda reais
	# (mesmos pontos consumidos por CobraTerritory.get_spawn_points()) e
	# barricada de pneu flanqueando a única via de acesso ao bairro.
	for p in [Vector2(7185, 1615), Vector2(7375, 1400), Vector2(8185, 1730)]:
		var barrel := BARREL.new()
		barrel.position = p
		add_child(barrel)
	for p in [Vector2(7300, 1625), Vector2(7300, 1775)]:
		var barricade := BARRICADE.new()
		barricade.position = p
		add_child(barricade)
	_solid_line("EasternCoast", Vector2(8520,960), Vector2(8520,2410), 24.0)
	for fence in FENCES:
		_solid_line("YardFence",fence[0],fence[1],5.0)
	# Reuse the neighborhood exclusion contract for every added trunk/canopy.
	var planted := 0
	for p in [Vector2(6830,1510),Vector2(6840,1910),Vector2(7110,1050),Vector2(7250,1190),Vector2(8110,1070),Vector2(8360,1280),Vector2(8400,2140),Vector2(8240,2310),Vector2(7330,2250),Vector2(7580,1515),Vector2(7860,1600),Vector2(7830,1840),Vector2(7720,1885)]:
		var clear := _clear_for_prop(p,65)
		for path in get_garden_paths():
			for i in range(path.size()-1):
				if Geometry2D.get_closest_point_to_segment(p,path[i],path[i+1]).distance_to(p)<65: clear=false
		for feature in get_landscape_definitions():
			if p.distance_to(feature.center)<feature.radius+55: clear=false
		for fence in FENCES:
			if Geometry2D.get_closest_point_to_segment(p,fence[0],fence[1]).distance_to(p)<70: clear=false
		for bench in [Vector2(7630,1570),Vector2(7820,1740),Vector2(7600,1840)]:
			if p.distance_to(bench+Vector2(18,4))<85: clear=false
		if clear:
			FINISH.tree(self,p,130+planted,1.15)
			planted+=1
	queue_redraw()

func _solid_line(id: String, a: Vector2, b: Vector2, thickness: float) -> void:
	var body := StaticBody2D.new()
	body.name = id
	if id == "YardFence": body.set_meta("impact_material", &"metal")
	body.position = (a+b)*0.5
	body.rotation = (b-a).angle()
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(a.distance_to(b),thickness)
	collider.shape = rect
	body.add_child(collider)
	add_child(body)

func get_entrance_paths() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for path in ENTRANCE_PATHS:
		result.append(PackedVector2Array(path))
	return result

func get_secret_drive() -> PackedVector2Array:
	return PackedVector2Array(SECRET_DRIVE)

func get_road_graph_definitions() -> Array[Dictionary]:
	var result: Array[Dictionary] = [_road("cobra_approach", PackedVector2Array([Vector2(6450,1700),Vector2(7400,1700)]))]
	var cardinal := PackedVector2Array([Vector2(7400,1700),Vector2(7700,1400),Vector2(8000,1700),Vector2(7700,2000),Vector2(7400,1700)])
	var ids := ["cobra_court_northwest", "cobra_court_northeast", "cobra_court_southeast", "cobra_court_southwest"]
	for quarter in 4:
		var points := PackedVector2Array()
		for step in 13:
			var angle := PI + float(quarter) * PI * 0.5 + float(step) / 12.0 * PI * 0.5
			points.append(CENTER + Vector2(cos(angle), sin(angle)) * RADIUS)
		# Shared exact endpoints avoid floating-point seams and false dangling ends.
		# Each quarter has a distinct endpoint pair, satisfying the graph's
		# duplicate-edge contract without exempting the authored circular road.
		points[0] = cardinal[quarter]
		points[12] = cardinal[quarter+1]
		result.append(_road(ids[quarter], points))
	return result

func _road(id: String, points: PackedVector2Array) -> Dictionary:
	return {"id":id,"points":points,"width":WIDTH,"open_start":false,"open_end":false}

func get_neighborhood_bounds() -> Rect2:
	return LAND

func get_building_footprints() -> Array[Rect2]:
	var result: Array[Rect2] = []
	for site in SITES:
		result.append(site.rect)
	return result

func get_pedestrian_routes() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for route in ROUTES:
		result.append(PackedVector2Array(route))
	return result

func get_spawn_points() -> PackedVector2Array:
	return PackedVector2Array([Vector2(7220,1580),Vector2(7330,1350),Vector2(8150,1760),Vector2(7750,2080),Vector2(7200,1850)])

func get_parking_positions() -> Dictionary:
	return PARKING.duplicate()

func get_spatial_audit() -> Array[String]:
	var errors: Array[String] = []
	var placed := {}
	for feature in get_landscape_definitions(): placed[feature.id] = true
	for candidate in LANDSCAPE:
		if not placed.has(candidate[0]): errors.append("Landscape placement rejected: " + str(candidate[0]))
	for site in SITES:
		for road in get_road_graph_definitions():
			var points: PackedVector2Array = road.points
			for i in range(points.size()-1):
				for step in 17:
					var sample := points[i].lerp(points[i+1],float(step)/16.0)
					if site.rect.grow(WIDTH*0.5+42.0+18.0).has_point(sample):
						errors.append("%s infringes road/sidewalk setback on %s" % [site.id,road.id])
	return errors

func _draw() -> void:
	# Dry coastal soil, no luminous green blanket. Static batched drawing only.
	FINISH.meadow(self,VISUAL_LAND,913,Color("64724f"))
	draw_rect(Rect2(6510,1580,940,240),Color("777361"))
	draw_polyline(PackedVector2Array(SECRET_DRIVE),Color("837d67"),64.0,true)
	draw_line(Vector2(8500,960),Vector2(8500,2410),Color("9b9580"),34.0,true)
	for route in ROUTES:
		draw_polyline(PackedVector2Array(route),Color("99917b"),36.0,true)
		draw_polyline(PackedVector2Array(route),Color("827e6c"),29.0,true)
	for site in SITES:
		SURFACE.paint(self,site.rect.grow(26),Color("8c866c"),"gravel")
		FINISH.aggregate(self,site.rect.grow(26),int(site.rect.position.x))
	for path in ENTRANCE_PATHS:
		draw_polyline(PackedVector2Array(path),Color("9e9580"),20,true)
	for fence in FENCES:
		draw_line(fence[0],fence[1],Color("aaa082"),4,true)
		var length: float = fence[0].distance_to(fence[1])
		for i in range(int(length/18)+1):
			var p: Vector2 = fence[0].lerp(fence[1],float(i)/maxf(1,int(length/18)))
			draw_circle(p,3,Color("4c4537"))
	# Back gardens are inhabited spaces, not identical decorative strips.
	for p in [Vector2(7080,1180),Vector2(7950,1040),Vector2(8310,2140)]:
		# Sombra e pontaletes verticais de suporte do varal
		draw_line(p+Vector2(2,16),p+Vector2(76,16),Color(0.04,0.05,0.06,0.20),2)
		draw_line(p+Vector2(0,-3),p+Vector2(0,18),Color("524330"),3)
		draw_line(p+Vector2(74,-3),p+Vector2(74,18),Color("524330"),3)
		draw_circle(p+Vector2(0,18),2.5,Color("382e22"))
		draw_circle(p+Vector2(74,18),2.5,Color("382e22"))
		draw_line(p,p+Vector2(74,0),Color("383a32"),2)
		for i in 4:
			draw_rect(Rect2(p+Vector2(8+i*16,1),Vector2(11,18+i%2*7)),[Color("9a927a"),Color("606b65"),Color("8d6d59"),Color("555753")][i])
	for p in [Vector2(6960,1470),Vector2(8180,1400),Vector2(8170,2320)]:
		draw_rect(Rect2(p+Vector2(2,2),Vector2(15,20)),Color(0.04,0.05,0.06,0.25))
		draw_rect(Rect2(p,Vector2(15,20)),Color("354337"))
		draw_rect(Rect2(p-Vector2(1,2),Vector2(17,5)),Color("58604c"))
	var table := Vector2(8280,2180)
	draw_circle(table+Vector2(2,3),18,Color(0.04,0.05,0.06,0.22))
	for i in 3:
		draw_circle(table+Vector2.RIGHT.rotated(float(i)*TAU/3)*29+Vector2(1,2),7,Color(0.04,0.05,0.06,0.22))
	draw_circle(table,18,Color("937857"))
	for i in 3:
		draw_circle(table+Vector2.RIGHT.rotated(float(i)*TAU/3)*29,7,Color("63573e"))
	# Central communal dry garden; no obstacle inside the turning road.
	var lawn := PackedVector2Array()
	for i in 64: lawn.append(CENTER+Vector2.from_angle(TAU*i/64.0)*200)
	FINISH.surface_polygon(self,lawn,Color("62774f"),"grass")
	for i in 220:
		var a := float(i)*2.39996
		var p := CENTER+Vector2(cos(a),sin(a))*sqrt(float(i)/220.0)*190
		draw_line(p,p+Vector2(1,-4),Color("819260"),1.3)
	_draw_cobra_emblem()
	# North opening matches the authored footpath; the rest of the rim stays closed.
	draw_arc(CENTER,198,-PI/2+.09,3*PI/2-.09,64,Color("938674"),5,true)
	for garden_path in get_garden_paths():
		draw_polyline(garden_path,Color("9b9077"),30,true)
	for p in [Vector2(7630,1570),Vector2(7820,1740),Vector2(7600,1840)]:
		draw_rect(Rect2(p+Vector2(1,2),Vector2(36,9)),Color(0.04,0.05,0.06,0.25))
		draw_rect(Rect2(p,Vector2(36,9)),Color("423b31"))
		for j in 3:
			draw_line(p+Vector2(0,j*3),p+Vector2(36,j*3),Color("a08560"),1)
	for feature in get_landscape_definitions():
		_draw_landscape(feature)
	# Workshop forecourt and concealed gravel parking, both physically accessible.
	SURFACE.paint(self,Rect2(8220,1670,270,150),Color("8c8977"),"gravel")
	SURFACE.yard(self,Rect2(8220,1670,270,150),83,true)
	draw_rect(Rect2(6930,2220,270,145),Color("7b735e"))
	for i in 5:
		draw_circle(Vector2(8430+i%2*14,1690+i*20),9,Color("292e2b"))

## Marca de gangue pintada no chão da praça central — herda a composição do
## brasão do território legado (IronCobraCulDeSac.gd), com a paleta terrosa
## que o resto do bairro já usa em vez do vermelho saturado do original.
func _draw_cobra_emblem() -> void:
	var origin := CENTER + Vector2(0, -30)
	var scale_factor := 1.6
	draw_circle(origin, 34.0 * scale_factor, Color(0.30, 0.05, 0.05, 0.55))
	draw_arc(origin, 34.0 * scale_factor, 0, TAU, 32, Color("6b1414"), 3.0)
	var snake_body := PackedVector2Array([
		Vector2(0, -22), Vector2(12, -14), Vector2(14, -2), Vector2(4, 8),
		Vector2(-12, 14), Vector2(-10, 22), Vector2(0, 24), Vector2(8, 20)
	])
	for i in snake_body.size():
		snake_body[i] = origin + snake_body[i] * scale_factor
	draw_polyline(snake_body, Color("8c3226"), 6.0 * scale_factor)
	var head := origin + Vector2(0, -22) * scale_factor
	draw_circle(head, 8.0 * scale_factor, Color("a83c2e"))
	draw_line(head + Vector2(-3, 2) * scale_factor, head + Vector2(-3, 9) * scale_factor, Color("d8cbb0"), 2.0)
	draw_line(head + Vector2(3, 2) * scale_factor, head + Vector2(3, 9) * scale_factor, Color("d8cbb0"), 2.0)
	draw_circle(head + Vector2(-3, -2) * scale_factor, 2.0, Color("c9a13a"))
	draw_circle(head + Vector2(3, -2) * scale_factor, 2.0, Color("c9a13a"))

func get_garden_paths() -> Array[PackedVector2Array]:
	# Stop 2px beyond the south asphalt edge, accounting for its curved profile.
	# The existing crossing, owned by the network, supplies the road portion.
	return [PackedVector2Array([CENTER+Vector2(-175,-20),CENTER+Vector2(145,70)]),
		PackedVector2Array([Vector2(7695,1728),Vector2(7692,1635),Vector2(7700,1502),Vector2(7700,1444)])]

func get_visual_terrain_bounds() -> Rect2:
	return VISUAL_LAND

func get_landscape_definitions() -> Array[Dictionary]:
	if not _landscape_cache.is_empty(): return _landscape_cache.duplicate(true)
	for entry in LANDSCAPE:
		var p: Vector2 = entry[2]
		var radius: float = entry[3]
		if not _clear_for_prop(p,radius*sqrt(2.0)+1): continue
		var clear := true
		var bounds := Rect2(p-Vector2.ONE*radius,Vector2.ONE*radius*2)
		for bench in [Vector2(7630,1570),Vector2(7820,1740),Vector2(7600,1840)]:
			if bounds.intersects(Rect2(bench,Vector2(36,9)).grow(8)): clear = false
		for path in get_garden_paths():
			for i in range(path.size()-1):
				if Geometry2D.get_closest_point_to_segment(p,path[i],path[i+1]).distance_to(p) < radius*sqrt(2.0)+16: clear = false
		# Existing interaction/encounter pockets: no newly authored clutter.
		for pocket in [Vector2(7210,1850),Vector2(8150,2080),Vector2(8195,1760),Vector2(8115,1825),Vector2(8115,1695)]:
			if p.distance_to(pocket)<radius+65: clear = false
		if not clear: continue
		_landscape_cache.append({"id":entry[0],"kind":entry[1],"center":p,"radius":radius,
			"bounds":Rect2(p-Vector2.ONE*radius,Vector2.ONE*radius*2),"trunk_radius":0.0 if entry[1]=="coastal" else 8.0})
	return _landscape_cache.duplicate(true)

## `canvas` nulo desenha no próprio bairro, com a sombra. A oclusão passa o
## overlay e recebe só a árvore em pé: sombra de chão sobre o ator ficaria errada.
func _draw_landscape(feature: Dictionary, canvas: CanvasItem = null) -> void:
	var grounded := canvas == null
	if grounded: canvas = self
	var p: Vector2 = feature.center
	var r: float = feature.radius
	var fid: String = String(feature.get("id", ""))
	if feature.kind == "shade":
		if grounded: canvas.draw_circle(p+Vector2(r*.12,r*.18),r*.75,Color(0.08,.10,.07,.32))
		# An irregular crown outline and small facets replace identical circles.
		# All offsets stay inside the published bounds, including branch strokes.
		var crown := PackedVector2Array()
		for i in 19:
			var angle := float(i)*TAU/19.0
			var reach := r*(.70+float((i*7)%5)*.037)
			crown.append(p+Vector2(cos(angle),sin(angle))*reach)
		canvas.draw_colored_polygon(crown,Color("394e37"))
		for i in 11:
			var angle := float(i)*2.39996
			var center := p+Vector2(cos(angle),sin(angle))*r*(.23+float(i%3)*.16)
			var size := r*(.17+float(i%2)*.07)
			var facet := PackedVector2Array([center+Vector2(-size,-size*.2),center+Vector2(-size*.3,-size*.8),center+Vector2(size*.8,-size*.5),center+Vector2(size*.6,size*.6),center+Vector2(-size*.5,size*.8)])
			canvas.draw_colored_polygon(facet,[Color("506443"),Color("61764d"),Color("435c3c"),Color("718154")][i%4])
		canvas.draw_line(p+Vector2(0,r*.83),p+Vector2(-r*.04,r*.25),Color("594832"),6)
		canvas.draw_line(p+Vector2(-r*.04,r*.35),p+Vector2(-r*.33,r*.12),Color("594832"),3)
		canvas.draw_line(p+Vector2(-r*.04,r*.38),p+Vector2(r*.28,r*.22),Color("776044"),3)
	elif feature.kind == "dry":
		# Sombra suave de solo sob arvore seca
		if grounded: canvas.draw_circle(p+Vector2(r*.12,r*.18),r*.6,Color(0.06,.08,.06,.22))
		canvas.draw_line(p+Vector2(0,r*.8),p-Vector2(0,r*.65),Color("776247"),5)
		canvas.draw_line(p,p+Vector2(-r*.7,-r*.35),Color("776247"),3)
		canvas.draw_line(p-Vector2(0,r*.3),p+Vector2(r*.65,-r*.7),Color("776247"),3)
		canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(-r*.85,-r*.3),p+Vector2(-r*.4,-r*.78),p+Vector2(r*.12,-r*.62),p+Vector2(r*.3,-r*.1),p+Vector2(-r*.25,r*.25)]),Color("747647"))
		canvas.draw_circle(p+Vector2(r*.48,-r*.6),r*.25,Color("8a8856"))
	else:
		# Elementos costeiros: diferenciacao entre rochas e arbustos litoraneos
		if fid.ends_with("_scrub"):
			# Vegetacao arbustiva costeira de dunas/litoral
			draw_circle(p+Vector2(r*.14,r*.18),r*.62,Color(0.05,.07,.05,.24))
			draw_circle(p,r*.55,Color("3f5235"))
			draw_circle(p+Vector2(-r*.1,-r*.12),r*.45,Color("576e48"))
			draw_circle(p+Vector2(r*.15,-r*.08),r*.38,Color("6c855a"))
			draw_circle(p+Vector2(0,r*.12),r*.32,Color("4e633f"))
			# Pontos de grama/detalhes secos de restinga
			for angle_i in [0.8, 2.2, 4.0]:
				draw_line(p+Vector2(cos(angle_i),sin(angle_i))*r*.3, p+Vector2(cos(angle_i),sin(angle_i))*r*.65, Color("8b9968"), 2)
		else:
			# Rocha costeira com sombra e vegetacao na base (desenhada antes da rocha)
			draw_colored_polygon(PackedVector2Array([p+Vector2(-r*.7,r*.3),p+Vector2(-r*.2,r*.72),p+Vector2(r*.65,r*.58),p+Vector2(r*.75,r*.15),p+Vector2(0,r*.2)]),Color(0.04,0.05,0.06,0.28))
			draw_circle(p+Vector2(r*.58,r*.48),r*.24,Color("555f3e"))
			draw_circle(p+Vector2(-r*.62,r*.35),r*.18,Color("485437"))
			var stone := PackedVector2Array([p+Vector2(-r*.8,r*.1),p+Vector2(-r*.5,-r*.55),p+Vector2(r*.13,-r*.68),p+Vector2(r*.65,-r*.2),p+Vector2(r*.55,r*.5),p+Vector2(-r*.3,r*.65)])
			draw_colored_polygon(stone,Color("726f63"))
			draw_colored_polygon(PackedVector2Array([stone[0],stone[1],stone[2],p]),Color("a39a82"))
			draw_line(p,stone[4],Color("514f47"),2)

func _clear_for_prop(p: Vector2, margin: float) -> bool:
	for footprint in get_building_footprints():
		if footprint.grow(margin).has_point(p):
			return false
	for road in get_road_graph_definitions():
		var pts: PackedVector2Array = road.points
		for i in range(pts.size()-1):
			if Geometry2D.get_closest_point_to_segment(p,pts[i],pts[i+1]).distance_to(p)<WIDTH*0.5+42+margin:
				return false
	for route in get_pedestrian_routes():
		for i in range(route.size()-1):
			if Geometry2D.get_closest_point_to_segment(p,route[i],route[i+1]).distance_to(p)<margin:
				return false
	for route in get_entrance_paths()+[get_secret_drive()]:
		for i in range(route.size()-1):
			if Geometry2D.get_closest_point_to_segment(p,route[i],route[i+1]).distance_to(p)<margin:
				return false
	return true
