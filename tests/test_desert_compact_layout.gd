extends SceneTree
## Contratos de conteúdo/espaço do deserto compacto. Física, viagem renderizada e FPS
## são checagens à parte; este inventário não certifica esse comportamento.
const L := preload("res://world/desert/DesertLayout.gd")
const VILLAGE := preload("res://world/desert/DesertMoonVillage.gd")
const HOMES := preload("res://world/desert/village/DesertVillageHomes.gd")
const UNDERGROUND := preload("res://world/desert/underground/DesertUnderground.gd")
const ROAD := preload("res://runtime/desert/roadside/RoadsideLayout.gd")
const WILDS := preload("res://runtime/desert/wilds/DesertWilds.gd")
const RELICS := preload("res://world/desert/expansion/DesertRelics.gd")
const LAND := preload("res://world/desert/expansion/DesertLandforms.gd")
const MINE := preload("res://world/mining/MiningLayout.gd")
const CANYON := preload("res://world/desert/canyon/DesertSmugglerLayout.gd")
const RUINS := preload("res://world/desert/DesertAbandonedSite.gd")
const NORTH := preload("res://world/desert/north_pass/DesertNorthPassLayout.gd")
const ROUTES := preload("res://gameplay/NativeTrafficRoutes.gd")
const MEET := preload("res://world/desert/drag_meet/DesertDragMeet.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const STRIP_SKY := preload("res://runtime/atmosphere/DragStripSky.gd")
const CANYON_STATE := preload("res://runtime/desert/canyon/CanyonState.gd")
const CANYON_TERRAIN := preload("res://world/desert/canyon/DesertSmugglerTerrain.gd")
const CANYON_REMAINS := preload("res://world/desert/canyon/ScavengerRemains.gd")
const ORIGINAL_AREA := 1940.0 * 1576.5
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func inside(point: Vector3, label: String) -> void:
	check(L.contains(point) or point.is_equal_approx(L.BRIDGE_END), "Playable bounds contain " + label + ": " + str(point))

func ids(rows: Array, expected: Array, label: String) -> void:
	var actual: Array = []
	for row in rows:
		check(not actual.has(str(row.id)), label + " has unique id " + str(row.id))
		actual.append(str(row.id))
	actual.sort()
	var wanted := expected.duplicate()
	wanted.sort()
	check(actual == wanted, label + " preserves every authored content id")

func run() -> void:
	var area := L.BOUNDS.size.x * L.BOUNDS.size.y
	var reduction := 1.0 - area / ORIGINAL_AREA
	check(reduction >= .50, "Playable area is reduced by at least 50 percent")
	check(L.BOUNDS.size.x < 1940.0 and L.BOUNDS.size.y < 1576.5, "Both physical map dimensions shrink")
	check(is_equal_approx(L.DRAG_LENGTH, 800.0), "Competition remains exactly 800 metres")
	var finish: Vector3 = L.drag_start_point() + L.drag_direction() * L.DRAG_LENGTH
	inside(L.drag_start_point(), "drag start")
	inside(finish, "drag finish")
	inside(L.drag_staging_point(), "drag staging")
	check(L.drag_start_point().distance_to(finish) == 800.0, "Start and finish stay 800 metres apart")
	var gateway := preload("res://world/north_gateway/NorthGatewayLayout.gd")
	check(L.BRIDGE_END.is_equal_approx(Vector3(gateway.TERMINAL.x, gateway.DECK_HEIGHT, gateway.END_Z)), "External bridge connection is preserved")
	var building_ids: Array = ["desert_bank", "desert_digo", "desert_fuel", "desert_motel", "desert_diner", "desert_market"]
	for i in 10: building_ids.append("desert_home_%02d" % i)
	ids(L.buildings(), building_ids, "Town buildings")
	for building in L.buildings():
		inside(building.position, str(building.id))
		check(building.size.x >= 14 and building.size.z >= 10, "Building retains human-scale dimensions: " + str(building.id))
		var footprint := Rect2(Vector2(building.position.x,building.position.z)-Vector2(building.size.x,building.size.z)*.5,Vector2(building.size.x,building.size.z))
		check(L.BOUNDS.encloses(footprint), "Complete building footprint fits map: " + str(building.id))
	ids(VILLAGE.definitions(), ["santa_lua_home_1", "santa_lua_home_2", "santa_lua_home_3", "santa_lua_home_4", "santa_lua_store", "santa_lua_water_tower", "santa_lua_courtyard"], "Santa Lua")
	ids(HOMES.definitions(), ["santa_lua_home_1", "santa_lua_home_2", "santa_lua_home_3", "santa_lua_home_4"], "Santa Lua interiors")
	ids(UNDERGROUND.definitions(), ["desert_under_culvert", "desert_under_well", "desert_under_cellar", "desert_under_mine"], "Underground interiors")
	ids(ROAD.SITES, ["sol_poente", "radio_tower", "scrapyard", "food_truck", "salt_works", "weigh_station", "motel", "chapel", "grandstand"], "Roadside sites")
	ids(WILDS.SITES, ["homestead_salt", "homestead_mesa", "homestead_dry", "homestead_well", "outlaws_ridge", "outlaws_wash", "outlaws_flats", "outlaws_dunes", "cave_coyote", "cave_vulture", "cave_whisper", "cave_sun", "cave_brother", "cave_crater"], "Wilds sites")
	ids(RELICS.sites(), ["station", "mine", "wagon", "wreck"], "Relic discoveries")
	ids(LAND.locations(), ["desert_wind_dunes", "desert_dry_wash", "desert_salt_pan", "desert_natural_arch", "desert_hoodoo", "desert_basalt_fan", "desert_balanced_rock"], "Natural landmarks")
	ids(RUINS.definitions(), ["desert_abandoned_house", "desert_abandoned_cabin"], "Open ruins")
	for collection in [L.place_definitions(), HOMES.definitions(), UNDERGROUND.definitions()]:
		for place in collection:
			inside(place.entry_position, str(place.id) + " entry")
			inside(place.return_position, str(place.id) + " return")
	for collection in [ROAD.SITES, WILDS.SITES]:
		for site in collection: inside(Vector3(site.center.x, 0, site.center.y), str(site.id))
	for site in WILDS.SITES:
		var radius: float = WILDS.site_radius(site)
		var center: Vector2 = site.center
		check(L.BOUNDS.encloses(Rect2(center-Vector2.ONE*radius,Vector2.ONE*radius*2)), "Entire wilds site fits compact boundary: " + str(site.id))
		check(L.road_clear(center,radius), "Wilds site clears actual driving lanes: " + str(site.id))
		check(MINE.reservation_clear(center,radius) and CANYON.reservation_clear(center,radius), "Wilds site stays outside quarry and smuggler gorge: " + str(site.id))
		check(NORTH.reservation_clear(center,radius), "Wilds site clears the north roadworks and rock cut: " + str(site.id))
		check(VILLAGE.reservation_clear(center,radius) and RUINS.reservation_clear(center,radius) and not ROAD.reserved(center,radius), "Wilds site clears inhabited/explorable locations: " + str(site.id))
		check(LAND.reservation_clear(center,radius) and RELICS.reservation_clear(center,radius), "Wilds site clears authored landforms and relics: " + str(site.id))
	for collection in [VILLAGE.definitions(), LAND.locations(), RUINS.definitions()]:
		for site in collection: inside(site.position, str(site.id))
	for site in RELICS.sites(): inside(Vector3(site.position.x, 0, site.position.y), str(site.id))
	inside(MINE.CENTER, "mining pit")
	inside(MINE.GATE, "mining gate")
	inside(CANYON.CENTER, "smuggler camp")
	inside(CANYON.ARMORY_POS, "smuggler armory")
	inside(NORTH.GATE, "north pass gate")
	inside(NORTH.END, "north pass end")
	for bounds: Rect2 in [MINE.BOUNDS,CANYON.BOUNDS,VILLAGE.BOUNDS]: check(L.BOUNDS.encloses(bounds), "Full authored landform footprint fits compact bounds: " + str(bounds))
	var roads := L.roads()
	shortcut_clearance(roads)
	sky_contract()
	canyon_contract()
	ids(roads, ["desert_route_66", "desert_main_street", "desert_west_highway", "desert_salt_highway", "desert_digo_street", "desert_bank_approach", "desert_truck_stop_entry", "desert_drag_access", "desert_drag_town_link", "desert_drag_strip", "desert_drag_return"], "Original roads plus the direct town/meet connection")
	for road in roads:
		for point: Vector3 in road.points: inside(point, str(road.id))
		if str(road.id).begins_with("desert_drag"): check(not bool(road.traffic), "Race road excludes ambient traffic: " + str(road.id))
	var graph := ROUTES.new()
	graph.configure(roads.filter(func(road: Dictionary): return road.get("traffic", true)))
	var private_graph := ROUTES.new()
	private_graph.configure(roads)
	for pair in [[Vector3(-590,0,-540),Vector3(-935,0,-760)],[Vector3(-935,0,-760),Vector3(-590,0,-540)]]:
		var shortcut: Curve3D = private_graph.route_between(pair[0],pair[1])
		var public_route: Curve3D = graph.route_between(pair[0],pair[1])
		check(shortcut!=null and shortcut.get_baked_length()<450, "Town/meet shortcut is connected and shorter than 450m in both directions")
		if shortcut!=null and public_route!=null: check(shortcut.get_baked_length()<public_route.get_baked_length()*.7, "Private shortcut removes at least 30 percent of the western detour")
	var destinations := [L.BRIDGE_END, L.BANK, L.WORKSHOP, L.TRUCK_STOP]
	for a: Vector3 in destinations:
		for b: Vector3 in destinations:
			if a == b: continue
			var route: Curve3D = graph.route_between(a, b)
			check(route != null and route.point_count > 1, "Directed ambient route connects " + str(a) + " to " + str(b))
	for failure in failures: push_error(failure)
	print("DESERT_COMPACT_LAYOUT ", JSON.stringify({"checks": checks, "failures": failures, "old_area_m2": ORIGINAL_AREA, "new_area_m2": area, "reduction_percent": reduction * 100.0, "drag_metres": L.DRAG_LENGTH}))
	quit(0 if failures.is_empty() else 1)

func polygon_area(polygon: PackedVector2Array) -> float:
	var twice := 0.0
	for i in polygon.size(): twice += polygon[i].cross(polygon[(i+1)%polygon.size()])
	return absf(twice)*.5

func overlaps(first: PackedVector2Array, second: PackedVector2Array) -> bool:
	for intersection: PackedVector2Array in Geometry2D.intersect_polygons(first,second):
		if polygon_area(intersection)>.001: return true
	return false

func shortcut_clearance(roads: Array[Dictionary]) -> void:
	var link: Dictionary = {}
	for road in roads:
		if road.id == "desert_drag_town_link": link=road
	check(not link.is_empty(), "Direct town/meet link exists for full-width clearance checks")
	if link.is_empty(): return
	var path := PackedVector2Array()
	for point: Vector3 in link.points: path.append(Vector2(point.x,point.z))
	var pavement := Geometry2D.offset_polyline(path,float(link.width)*.5,Geometry2D.JOIN_ROUND,Geometry2D.END_BUTT)
	var bounds: Rect2=L.DRAG_MEET_BOUNDS
	var paddock := PackedVector2Array([bounds.position,Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y)])
	var cuts_paddock := false
	for polygon: PackedVector2Array in pavement: cuts_paddock=cuts_paddock or overlaps(polygon,paddock)
	# Inspeciona só a ligação nova. A rota final dela pode entrar no paddock pelo
	# acesso original; essa conexão final autorizada não é colisão.
	check(not cuts_paddock, "Town shortcut's full paved width remains outside the reserved paddock")
	for car in MEET.car_spots():
		var dimensions: Array=FLEET.spec(str(car.model)).bounds_size
		var footprint := PackedVector2Array()
		var transform := Transform3D(Basis(Vector3.UP,float(car.yaw)),car.position)
		for corner: Vector2 in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
			var world: Vector3=transform*Vector3(corner.x*(float(dimensions[0])*.5+.25),0,corner.y*(float(dimensions[2])*.5+.25))
			footprint.append(Vector2(world.x,world.z))
		var intersects := false
		for polygon: PackedVector2Array in pavement: intersects=intersects or overlaps(polygon,footprint)
		check(not intersects, "Full-width shortcut clears parked car hull plus25cm: " + str(car.id))

func sky_contract() -> void:
	var sky := STRIP_SKY.new()
	var environment := Environment.new()
	var original_sky := Sky.new()
	environment.sky=original_sky
	environment.background_mode=Environment.BG_COLOR
	for point: Vector3 in [L.drag_start_point(),L.drag_start_point()+L.drag_direction()*800,L.drag_meet_center()]:
		sky.apply(environment,point,.9,.3,.5,false)
		check(sky.installed and environment.sky==sky.sky and is_equal_approx(float(sky.material.get_shader_parameter("region_weight")),1.0), "Local race sky fully applies at relocated course/meet point: " + str(point))
	sky.apply(environment,L.drag_start_point(),.9,.3,.5,true)
	check(not sky.installed and environment.sky==original_sky and environment.background_mode==Environment.BG_COLOR, "Entering an interior restores the previous sky")
	sky.apply(environment,L.drag_start_point(),.9,.3,.5,false)
	sky.apply(environment,L.BRIDGE_END,.9,.3,.5,false)
	check(not sky.installed and environment.sky==original_sky, "Leaving the compact race area releases local sky ownership")

func canyon_contract() -> void:
	check(is_equal_approx(CANYON.BOUNDS.get_area(),270.0*360.0*.3), "Canyon playable footprint is70percent smaller than its original97200m2")
	check(is_equal_approx(CANYON.BRIDGE_START.distance_to(CANYON.BRIDGE_END),245.0*.3), "Canyon bridge is70percent shorter:73.5m remain")
	check(is_equal_approx(CANYON.DEPTH,72.0*.3), "Canyon depth is reduced70percent to21.6m")
	check(is_equal_approx(CANYON.BRIDGE_WIDTH,3.8), "Bridge keeps its original3.8m walking width")
	check(CANYON.CENTER==Vector3(-1204,0,-492) and CANYON.CAMP_BOUNDS==Rect2(-1240,-524,72,64), "Smuggler camp keeps its full-size footprint and position")
	check(CANYON.ARMORY_POS==Vector3(-1220,0,-481) and CANYON.BOUNDS.encloses(CANYON.CAMP_BOUNDS), "Both armory rewards remain in the preserved camp")
	check(CANYON.GATE_Z>CANYON.BRIDGE_START.z and CANYON.GATE_Z<CANYON.BRIDGE_END.z, "Vehicle gate stays between the shorter bridge and camp")
	var expected_posts := [Vector3(-8,0,-20),Vector3(8,0,-20),Vector3(-20,0,-9),Vector3(20,0,-9),Vector3(-24,0,5),Vector3(22,0,5),Vector3(-6,0,14),Vector3(10,0,17)]
	check(CANYON.POSTS==expected_posts and CANYON_STATE.GUARD_COUNT==8, "All eight authored defender stations retain their camp-local positions")
	check(CANYON_STATE.RECEIPTS==["desert_canyon_ak47","desert_canyon_grenades"] and CANYON_STATE.WEAPONS==["ak47","grenade"] and CANYON_STATE.AMMO==[90,3], "The canyon preserves both armory rewards and ammunition")
	for point: Vector3 in CANYON.combat_spawn_points():
		check(CANYON.CAMP_BOUNDS.has_point(Vector2(point.x,point.z)) and absf(CANYON_TERRAIN.surface_height(Vector2(point.x,point.z)))<.05, "Full-size defender station keeps a level camp floor: " + str(point))
	check(CANYON_REMAINS.BODY_POINTS.size()==4 and CANYON_REMAINS.BIRD_OFFSETS.size()==6, "All four remains groups and six feeding birds are preserved")
	for point: Vector2 in CANYON_REMAINS.BODY_POINTS:
		check(CANYON.BOUNDS.has_point(point) and CANYON_TERRAIN.surface_height(point)<-1.0, "Relocated remains stay on the canyon floor: " + str(point))
