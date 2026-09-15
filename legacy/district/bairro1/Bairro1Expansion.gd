@tool
class_name Bairro1Expansion
extends Node2D

## Fixed southern half of Bairro 1.  Nothing in this node is randomized: its
## four subareas, curved roads, lots, alleys and public routes are authored.
## Instantiate at Vector2.ZERO.  Coordinates intentionally start at y=1280,
## below CentralDistrict, and never touch the existing north-east coast.

const EXPANSION_BOUNDS := Rect2(0, 1280, 2400, 2200)
const ROAD_WIDTH := 164.0
const LOCAL_ROAD_WIDTH := 112.0
const SIDEWALK_MARGIN := 42.0
const BUILDING_SETBACK := 12.0

# The gateway is the district's four-lane trunk and the elevated highway is
# only its rendered/elevated representation. Keep lane centres and painted
# separators here so graph generation and viaduct drawing cannot drift apart.
const GATEWAY_MEDIAN_HALF_WIDTH := 7.0
const GATEWAY_LANE_OFFSETS := [-59.0, -20.0, 20.0, 59.0]
const GATEWAY_LANE_SEPARATOR_OFFSETS := [-41.0, 41.0]

const ROAD_COLOR := Color("#202932")
const ROAD_EDGE_COLOR := Color("#151c23")
const SIDEWALK_COLOR := Color("#aaa9a1")
const CURB_COLOR := Color("#70767a")
const LOT_GROUND_COLOR := Color("#555952")
const LANE_COLOR := Color("#dfc84d")
const ALLEY_COLOR := Color("#3d4345")

const PROCEDURAL_TREE := preload("res://geodata/nature/ProceduralStreetTree.gd")
const PROCEDURAL_ROCK := preload("res://geodata/nature/ProceduralUrbanRock.gd")
const LAMP_SCRIPT := preload("res://geodata/StreetLamp.gd")
const BUILDING_SCRIPT := preload("res://geodata/ProceduralBuilding.gd")
const INTERSECTION_SCRIPT := preload("res://geodata/roads/CityIntersection.gd")

# Main north/south connection from CentralDistrict to Bairro 2.  These are
# control points; Catmull-Rom sampling below turns them into real curves.
static var GATEWAY_SPINE := PackedVector2Array([
	Vector2(870, 1260), Vector2(870, 1500), Vector2(870, 1740),
	Vector2(1050, 1980), Vector2(1280, 2200), Vector2(1340, 2500),
	Vector2(1400, 2800), Vector2(1480, 3500),
])
static var MIDTOWN_CROSS := PackedVector2Array([
	Vector2(-30, 1740), Vector2(350, 1740), Vector2(700, 1800), Vector2(1050, 1950),
	Vector2(1400, 2100), Vector2(1800, 2140), Vector2(2100, 2140), Vector2(2450, 2140),
])
static var SOUTH_CROSS := PackedVector2Array([
	Vector2(-30, 2800), Vector2(350, 2750), Vector2(700, 2760),
	Vector2(1050, 2880), Vector2(1400, 3000), Vector2(1800, 3040),
	Vector2(2150, 3040), Vector2(2450, 3040),
])
static var EAST_ARC := PackedVector2Array([
	Vector2(2450, 2140), Vector2(2450, 2400), Vector2(2460, 2700), Vector2(2450, 3040),
])
static var WEST_LOCAL := PackedVector2Array([
	Vector2(-30, 2360), Vector2(250, 2360), Vector2(550, 2450),
	Vector2(800, 2620), Vector2(1050, 2880),
])

# These three links are part of the authored road graph, rather than cosmetic
# stubs at the map edge.  Together with the five main streets they form real
# circulation loops: traffic can take a turn at each junction and never needs
# to make a visible U-turn in the middle of a street.
static var NORTH_LINK := PackedVector2Array([
	Vector2(870, 1260), Vector2(980, 1260), Vector2(1160, 1215), Vector2(1460, 1210), Vector2(1780, 1260),
])
static var EAST_LINK := PackedVector2Array([
	Vector2(1750, 1260), Vector2(1950, 1450), Vector2(2020, 1700),
	Vector2(1980, 1950), Vector2(1900, 2140),
])
static var WEST_LINK := PackedVector2Array([
	Vector2(-30, 1740), Vector2(-30, 2000), Vector2(-30, 2180), Vector2(-30, 2360),
])

# As oito ruas que já formam o Bairro 1 atual. Os pontos abaixo são salvos na
# cena e aparecem como alças arrastáveis no editor, sem trocar o mapa por demo.
@export_group("Editar ruas atuais")
@export var render_legacy_roads: bool = true:
	set(value):
		render_legacy_roads = value
		queue_redraw()
@export var gateway_spine_points: PackedVector2Array = GATEWAY_SPINE
@export var midtown_cross_points: PackedVector2Array = MIDTOWN_CROSS
@export var south_cross_points: PackedVector2Array = SOUTH_CROSS
@export var east_arc_points: PackedVector2Array = EAST_ARC
@export var west_local_points: PackedVector2Array = WEST_LOCAL
@export var north_link_points: PackedVector2Array = NORTH_LINK
@export var east_link_points: PackedVector2Array = EAST_LINK
@export var west_link_points: PackedVector2Array = WEST_LINK
@export_range(48.0, 360.0, 2.0) var main_road_width: float = ROAD_WIDTH:
	set(value):
		main_road_width = value
		_build_route_cache(true)
		queue_redraw()
@export_range(32.0, 240.0, 2.0) var local_road_width: float = LOCAL_ROAD_WIDTH:
	set(value):
		local_road_width = value
		_build_route_cache(true)
		queue_redraw()

# DistrictRailLine owns the track geometry. Clearance checks below query its
# geodata API, so moving the track cannot leave a stale copied corridor here.
const RAIL_CLEARANCE := 70.0
const LAMP_ROAD_CLEARANCE := 18.0
const LAMP_INTERSECTION_CLEARANCE := 112.0
const INVALID_DECOR_POSITION := Vector2(1000000.0, 1000000.0)

var subareas: Array[Dictionary] = [
	{"id": "PORTA_CENTRAL", "bounds": Rect2(0, 1280, 1020, 940)},
	{"id": "MIRANTE_LESTE", "bounds": Rect2(1020, 1280, 1380, 940)},
	{"id": "BAIXADA_OESTE", "bounds": Rect2(0, 2220, 1250, 1260)},
	{"id": "PORTO_NOVO", "bounds": Rect2(1250, 2220, 1150, 1260)},
]

# 35 authored lots: 32 structures and three recognizable public plazas.
var lots: Array[Dictionary] = [
	# Porta Central -- older compact blocks around the northern gateway.
	{"zone": "PORTA_CENTRAL", "kind": "office", "rect": Rect2(54, 1334, 224, 224)},
	{"zone": "PORTA_CENTRAL", "kind": "corner_shop", "rect": Rect2(300, 1338, 212, 218)},
	{"zone": "PORTA_CENTRAL", "kind": "brownstone", "rect": Rect2(536, 1340, 182, 218)},
	{"zone": "PORTA_CENTRAL", "kind": "rowhouse", "rect": Rect2(58, 1940, 242, 202)},
	{"zone": "PORTA_CENTRAL", "kind": "shop", "rect": Rect2(326, 1980, 226, 178)},
	{"zone": "BAIXADA_OESTE", "kind": "office", "rect": Rect2(780, 3250, 220, 160)},
	{"zone": "BAIXADA_OESTE", "kind": "park", "rect": Rect2(1020, 3240, 210, 170)},

	# Mirante Leste -- taller civic/commercial silhouettes and lookout squares.
	# Civic buildings are deliberately unlike the commercial blocks: each has a
	# distinct roof silhouette and a real operational marker in CivicServices.
	{"zone": "MIRANTE_LESTE", "kind": "police_precinct", "rect": Rect2(1060, 1338, 226, 160)},
	{"zone": "MIRANTE_LESTE", "kind": "brownstone", "rect": Rect2(1310, 1340, 224, 160)},
	{"zone": "MIRANTE_LESTE", "kind": "clothing_shop", "rect": Rect2(1060, 1510, 214, 135)},
	{"zone": "MIRANTE_LESTE", "kind": "police_substation", "rect": Rect2(1300, 1510, 250, 135)},
	{"zone": "MIRANTE_LESTE", "kind": "rowhouse", "rect": Rect2(1990, 1310, 202, 190)},
	{"zone": "MIRANTE_LESTE", "kind": "corner_shop", "rect": Rect2(2210, 1350, 170, 210)},
	{"zone": "MIRANTE_LESTE", "kind": "office", "rect": Rect2(1280, 1840, 222, 210)},
	{"zone": "MIRANTE_LESTE", "kind": "hospital", "rect": Rect2(1530, 1900, 180, 210)},
	{"zone": "MIRANTE_LESTE", "kind": "park", "rect": Rect2(2040, 1780, 250, 170)},

	# Baixada Oeste -- workshops, warehouses and dense workers' housing.
	{"zone": "BAIXADA_OESTE", "kind": "warehouse", "rect": Rect2(52, 2460, 228, 224)},
	{"zone": "BAIXADA_OESTE", "kind": "garage", "rect": Rect2(305, 2470, 212, 214)},
	{"zone": "BAIXADA_OESTE", "kind": "warehouse", "rect": Rect2(545, 2160, 210, 150)},
	{"zone": "BAIXADA_OESTE", "kind": "office", "rect": Rect2(550, 3260, 200, 160)},
	{"zone": "BAIXADA_OESTE", "kind": "rowhouse", "rect": Rect2(50, 2980, 214, 250)},
	{"zone": "BAIXADA_OESTE", "kind": "brownstone", "rect": Rect2(290, 2970, 222, 258)},
	{"zone": "BAIXADA_OESTE", "kind": "shop", "rect": Rect2(538, 2990, 210, 232)},
	{"zone": "BAIXADA_OESTE", "kind": "rowhouse", "rect": Rect2(776, 2990, 230, 232)},
	{"zone": "BAIXADA_OESTE", "kind": "warehouse", "rect": Rect2(1020, 3010, 190, 208)},
	{"zone": "BAIXADA_OESTE", "kind": "park", "rect": Rect2(80, 3260, 420, 168)},

	# Porto Novo -- mixed renewal district, large roofs and service courts.
	{"zone": "PORTO_NOVO", "kind": "office", "rect": Rect2(1535, 2380, 216, 214)},
	{"zone": "PORTO_NOVO", "kind": "fire_station", "rect": Rect2(1775, 2340, 238, 236)},
	{"zone": "PORTO_NOVO", "kind": "warehouse", "rect": Rect2(2040, 2325, 290, 238)},
	{"zone": "PORTO_NOVO", "kind": "corner_shop", "rect": Rect2(1540, 2605, 204, 160)},
	{"zone": "PORTO_NOVO", "kind": "office", "rect": Rect2(1770, 2610, 226, 194)},
	{"zone": "PORTO_NOVO", "kind": "garage", "rect": Rect2(2020, 2600, 304, 198)},
	{"zone": "PORTO_NOVO", "kind": "brownstone", "rect": Rect2(1580, 3160, 226, 230)},
	{"zone": "PORTO_NOVO", "kind": "rowhouse", "rect": Rect2(1830, 3175, 224, 210)},
	{"zone": "PORTO_NOVO", "kind": "office", "rect": Rect2(2080, 3160, 252, 226)},
]

var alleys: Array[Rect2] = [
	Rect2(282, 1338, 14, 218), Rect2(516, 1340, 16, 216),
	Rect2(1050, 1570, 505, 24), Rect2(1510, 1830, 14, 220),
	Rect2(282, 2470, 18, 214), Rect2(520, 2520, 20, 190),
	Rect2(267, 2970, 18, 258), Rect2(516, 2990, 18, 232),
	Rect2(1754, 2340, 16, 236), Rect2(2018, 2330, 16, 230),
	Rect2(1750, 2610, 15, 200), Rect2(2000, 2600, 15, 204),
]

var tree_positions := PackedVector2Array([
	Vector2(28, 1325), Vector2(742, 1328), Vector2(24, 1582), Vector2(748, 1585),
	Vector2(586, 1630), Vector2(786, 1710), Vector2(28, 1880), Vector2(570, 1980),
	Vector2(1035, 1325), Vector2(1568, 1330), Vector2(1030, 1580), Vector2(1572, 1590),
	Vector2(1960, 1325), Vector2(2380, 1325), Vector2(1970, 1585), Vector2(2310, 1760),
	Vector2(2025, 1800), Vector2(2295, 1925), Vector2(30, 2440), Vector2(530, 2485),
	Vector2(770, 2515), Vector2(1000, 2580), Vector2(28, 2960), Vector2(525, 2965),
	Vector2(760, 2970), Vector2(1015, 2990), Vector2(55, 3280), Vector2(520, 3280),
	Vector2(80, 3400), Vector2(480, 3400), Vector2(1510, 2360), Vector2(2348, 2300),
	Vector2(1512, 2610), Vector2(2350, 2585), Vector2(1535, 3140), Vector2(2355, 3140),
	Vector2(1815, 3150), Vector2(2062, 3150), Vector2(2365, 3380), Vector2(1460, 3420),
])

var additional_tree_positions := PackedVector2Array([
	Vector2(635, 1640), Vector2(718, 1690),
	Vector2(2070, 1810), Vector2(2160, 1840), Vector2(2250, 1890),
	Vector2(130, 3310), Vector2(245, 3340), Vector2(365, 3375), Vector2(455, 3305),
	Vector2(1180, 2340), Vector2(1215, 2450), Vector2(1160, 2900),
	Vector2(1220, 3180), Vector2(2345, 2780), Vector2(2355, 3250),
	Vector2(1040, 3400), Vector2(1180, 3430), Vector2(610, 2240),
])

var rock_positions := PackedVector2Array([
	Vector2(612, 1712), Vector2(748, 1635),
	Vector2(2075, 1908), Vector2(2180, 1788), Vector2(2270, 1930),
	Vector2(105, 3378), Vector2(205, 3288), Vector2(330, 3410), Vector2(468, 3370),
	Vector2(1170, 2390), Vector2(1220, 2550), Vector2(1160, 3210),
	Vector2(2370, 2660), Vector2(2360, 2860), Vector2(2325, 3440),
	Vector2(1080, 3450), Vector2(30, 2170), Vector2(620, 2185),
])

var lamp_positions := PackedVector2Array([
	Vector2(800, 1320), Vector2(950, 1420), Vector2(805, 1570), Vector2(995, 1710),
	Vector2(920, 1870), Vector2(1125, 2010), Vector2(1190, 2180), Vector2(1450, 2180),
	Vector2(1740, 1320), Vector2(1650, 1500), Vector2(1700, 1730), Vector2(1810, 1950),
	Vector2(2040, 2030), Vector2(2320, 2050), Vector2(40, 1665), Vector2(310, 1665),
	Vector2(600, 1760), Vector2(790, 1940), Vector2(40, 2275), Vector2(300, 2255),
	Vector2(560, 2300), Vector2(780, 2400), Vector2(970, 2530), Vector2(40, 2760),
	Vector2(330, 2720), Vector2(660, 2675), Vector2(980, 2665), Vector2(1270, 2700),
	Vector2(1580, 2820), Vector2(1910, 2940), Vector2(2280, 2950), Vector2(1300, 3000),
	Vector2(1400, 3250), Vector2(1515, 3440),
])

var parking_spots: Array[Dictionary] = [
	{"position": Vector2(260, 1910), "rotation": 0.0, "zone": "PORTA_CENTRAL"},
	{"position": Vector2(360, 1910), "rotation": 0.0, "zone": "PORTA_CENTRAL"},
	{"position": Vector2(1120, 1810), "rotation": 0.0, "zone": "MIRANTE_LESTE"},
	{"position": Vector2(1200, 1810), "rotation": 0.0, "zone": "MIRANTE_LESTE"},
	{"position": Vector2(1940, 1650), "rotation": PI * 0.5, "zone": "MIRANTE_LESTE"},
	{"position": Vector2(2290, 2010), "rotation": 0.0, "zone": "MIRANTE_LESTE"},
	{"position": Vector2(60, 2200), "rotation": 0.0, "zone": "BAIXADA_OESTE"},
	{"position": Vector2(150, 2200), "rotation": 0.0, "zone": "BAIXADA_OESTE"},
	{"position": Vector2(410, 2395), "rotation": 0.12, "zone": "BAIXADA_OESTE"},
	{"position": Vector2(900, 2470), "rotation": 0.45, "zone": "BAIXADA_OESTE"},
	{"position": Vector2(70, 2900), "rotation": -0.10, "zone": "BAIXADA_OESTE"},
	{"position": Vector2(650, 2870), "rotation": -0.08, "zone": "BAIXADA_OESTE"},
	{"position": Vector2(1560, 2300), "rotation": -0.08, "zone": "PORTO_NOVO"},
	{"position": Vector2(1900, 2260), "rotation": -0.15, "zone": "PORTO_NOVO"},
	{"position": Vector2(2200, 2230), "rotation": 0.0, "zone": "PORTO_NOVO"},
	{"position": Vector2(1580, 3070), "rotation": 0.27, "zone": "PORTO_NOVO"},
	{"position": Vector2(1880, 3120), "rotation": 0.02, "zone": "PORTO_NOVO"},
	{"position": Vector2(2200, 3120), "rotation": 0.02, "zone": "PORTO_NOVO"},
]

var _roads: Dictionary = {}
var _vehicle_routes: Dictionary = {}
var _pedestrian_routes: Array[PackedVector2Array] = []

func _ready() -> void:
	z_index = 0
	add_to_group("district_one_layout")
	# Persisted Marker2D handles are the authored source whenever this provider
	# is instanced in a composed district. Instance-level exported-array
	# overrides may be stale; resolving the handles here makes editor and runtime
	# consume exactly the same geometry.
	_sync_road_points_from_markers()
	_build_route_cache()
	if Engine.is_editor_hint():
		# Preview only: the real roads, lots and crossings are drawn below.  Do
		# not spawn runtime collisions, traffic, lamps or NPCs into the scene.
		_ensure_editor_road_points()
		queue_redraw()
		return
	if render_legacy_roads:
		validate_layout()
	_create_buildings_and_collisions()
	if render_legacy_roads:
		_create_authored_intersections()
	_create_decor()
	queue_redraw()
	add_to_group("bairro1_expansion")
	print("BAIRRO1_EXPANSION_READY: 4 subareas, 35 fixed lots, curved roads and Bairro 2 gateway")

func _build_route_cache(force: bool = false) -> void:
	if not _roads.is_empty() and not force:
		return
	_roads = {
		"gateway_spine": {"points": _catmull_rom(gateway_spine_points, 8), "width": main_road_width},
		"midtown_cross": {"points": _catmull_rom(midtown_cross_points, 8), "width": main_road_width},
		"south_cross": {"points": _catmull_rom(south_cross_points, 8), "width": main_road_width},
		"east_arc": {"points": _catmull_rom(east_arc_points, 8), "width": main_road_width},
		"west_local": {"points": _catmull_rom(west_local_points, 8), "width": local_road_width},
		"north_link": {"points": _catmull_rom(north_link_points, 8), "width": main_road_width},
		"east_link": {"points": _catmull_rom(east_link_points, 8), "width": main_road_width},
		"west_link": {"points": _catmull_rom(west_link_points, 8), "width": local_road_width},
	}
	_build_connected_vehicle_routes()
	_pedestrian_routes = [
		_build_two_way_loop(_roads.gateway_spine.points, main_road_width * 0.5 + 25.0),
		_build_two_way_loop(_roads.midtown_cross.points, main_road_width * 0.5 + 25.0),
		_build_two_way_loop(_roads.south_cross.points, main_road_width * 0.5 + 25.0),
		_build_two_way_loop(_roads.east_arc.points, main_road_width * 0.5 + 25.0),
	]

func _ensure_editor_road_points() -> void:
	if get_node_or_null("RoadControlPoints") != null:
		return
	var controls := Node2D.new()
	controls.name = "RoadControlPoints"
	add_child(controls)
	var edited_root := get_tree().edited_scene_root
	if edited_root != null:
		controls.owner = edited_root
	for road_id in _editor_road_sets():
		var points: PackedVector2Array = _editor_road_sets()[road_id]
		for index in points.size():
			var marker := Marker2D.new()
			marker.name = "%s_%02d" % [String(road_id).capitalize(), index + 1]
			marker.position = points[index]
			marker.set_meta("road_id", road_id)
			marker.set_meta("point_index", index)
			controls.add_child(marker)
			if edited_root != null:
				marker.owner = edited_root

func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	# Clear cached legacy intersection art. The unified renderer owns junction
	# geometry whenever this scene is composed inside DistrictOneComplete.
	var old_intersections := get_node_or_null("AuthoredRoadIntersections")
	if old_intersections != null:
		old_intersections.queue_free()
	queue_redraw()
	var changed := _sync_road_points_from_markers()
	if changed:
		_build_route_cache(true)
		queue_redraw()

func _sync_road_points_from_markers() -> bool:
	var controls := get_node_or_null("RoadControlPoints") as Node2D
	if controls == null:
		return false
	var current_sets := _editor_road_sets()
	var marker_sets := {}
	for road_id in current_sets:
		marker_sets[road_id] = {}
	for child in controls.get_children():
		if not child is Marker2D:
			continue
		var marker := child as Marker2D
		var road_id := String(marker.get_meta("road_id", ""))
		var point_index := int(marker.get_meta("point_index", -1))
		if not marker_sets.has(road_id) or point_index < 0:
			continue
		(marker_sets[road_id] as Dictionary)[point_index] = marker.position

	# Never mix half a handle set with half an exported array. A provider with
	# missing/non-contiguous handles falls back atomically to its exported data.
	for road_id in current_sets:
		var indexed_points := marker_sets[road_id] as Dictionary
		if indexed_points.is_empty():
			return false
		var highest_index := -1
		for point_index in indexed_points:
			highest_index = maxi(highest_index, int(point_index))
		if indexed_points.size() != highest_index + 1:
			return false

	var changed := false
	for road_id in current_sets:
		var indexed_points := marker_sets[road_id] as Dictionary
		var marker_points := PackedVector2Array()
		for point_index in range(indexed_points.size()):
			marker_points.append(indexed_points[point_index])
		var current_points := current_sets[road_id] as PackedVector2Array
		if not _road_point_arrays_equal(current_points, marker_points):
			_set_editor_road_points(String(road_id), marker_points)
			changed = true
	return changed

func _road_point_arrays_equal(first: PackedVector2Array, second: PackedVector2Array) -> bool:
	if first.size() != second.size():
		return false
	for index in range(first.size()):
		if not first[index].is_equal_approx(second[index]):
			return false
	return true

func _editor_road_sets() -> Dictionary:
	return {"gateway_spine": gateway_spine_points.duplicate(), "midtown_cross": midtown_cross_points.duplicate(), "south_cross": south_cross_points.duplicate(), "east_arc": east_arc_points.duplicate(), "west_local": west_local_points.duplicate(), "north_link": north_link_points.duplicate(), "east_link": east_link_points.duplicate(), "west_link": west_link_points.duplicate()}

func _set_editor_road_points(road_id: String, points: PackedVector2Array) -> void:
	match road_id:
		"gateway_spine": gateway_spine_points = points
		"midtown_cross": midtown_cross_points = points
		"south_cross": south_cross_points = points
		"east_arc": east_arc_points = points
		"west_local": west_local_points = points
		"north_link": north_link_points = points
		"east_link": east_link_points = points
		"west_link": west_link_points = points

func _two_way_lane_definitions(road_width: float) -> Array[Dictionary]:
	# Offsets are derived from the same editable width that draws the pavement;
	# moving or resizing a road therefore cannot detach its traffic paths.
	var lane_offset := road_width * 0.25
	return [
		{"lane_id": "forward_01", "offset": lane_offset, "direction": 1, "direction_name": "forward"},
		{"lane_id": "reverse_01", "offset": -lane_offset, "direction": -1, "direction_name": "reverse"},
	]

static func get_gateway_lane_definitions() -> Array[Dictionary]:
	# gateway_spine is authored north -> south. Positive offsets are its
	# right-hand/southbound carriageway and negative offsets return northbound,
	# matching every other two-way road provider in the district.
	return [
		{"lane_id": "reverse_02", "offset": GATEWAY_LANE_OFFSETS[0], "direction": -1, "direction_name": "reverse"},
		{"lane_id": "reverse_01", "offset": GATEWAY_LANE_OFFSETS[1], "direction": -1, "direction_name": "reverse"},
		{"lane_id": "forward_01", "offset": GATEWAY_LANE_OFFSETS[2], "direction": 1, "direction_name": "forward"},
		{"lane_id": "forward_02", "offset": GATEWAY_LANE_OFFSETS[3], "direction": 1, "direction_name": "forward"},
	]

func get_road_graph_definitions() -> Array[Dictionary]:
	_sync_road_points_from_markers()
	var main_lanes := _two_way_lane_definitions(main_road_width)
	var local_lanes := _two_way_lane_definitions(local_road_width)
	return [
		{"id": "gateway_spine", "points": gateway_spine_points, "width": main_road_width, "lanes": get_gateway_lane_definitions(), "render": false, "open_start": true, "open_end": true},
		{"id": "midtown_cross", "points": midtown_cross_points, "width": main_road_width, "lanes": main_lanes, "open_start": true, "snap_end": "Bairro1RoadNetwork/coastal_exit", "snap_end_t": 0.0, "snap_end_mode": "tangent"},
		{"id": "south_cross", "points": south_cross_points, "width": main_road_width, "lanes": main_lanes, "open_start": true, "snap_end": "Bairro1Expansion/east_link", "snap_end_t": 1.0, "snap_end_mode": "perpendicular", "guard_rail_openings": [{"position": Vector2(2130, 2940), "radius": 170.0}]},
		{"id": "east_arc", "points": east_arc_points, "width": main_road_width, "lanes": main_lanes, "snap_start": "Bairro1Expansion/north_link", "snap_start_t": 1.0, "snap_start_mode": "perpendicular", "snap_end": "Bairro1RoadNetwork/coastal_exit", "snap_end_t": 0.0, "snap_end_mode": "tangent"},
		{"id": "west_local", "points": west_local_points, "width": local_road_width, "lanes": local_lanes, "snap_start": "Bairro1Expansion/west_link", "snap_end": "Bairro1Expansion/south_cross"},
		{"id": "north_link", "points": north_link_points, "width": main_road_width, "lanes": main_lanes, "snap_start": "Bairro1Expansion/gateway_spine", "snap_start_t": 0.0, "snap_end": "Bairro1Expansion/east_arc", "snap_end_t": 0.0, "snap_end_mode": "perpendicular"},
		{"id": "east_link", "points": east_link_points, "width": main_road_width, "lanes": main_lanes, "snap_start": "Bairro1RoadNetwork/coastal_exit", "snap_start_t": 0.0, "snap_start_mode": "perpendicular", "snap_end": "Bairro1Expansion/south_cross", "snap_end_t": 1.0, "snap_end_mode": "perpendicular"},
		{"id": "west_link", "points": west_link_points, "width": local_road_width, "lanes": local_lanes, "snap_start": "Bairro1Expansion/midtown_cross", "snap_end": "Bairro1Expansion/west_local"},
	]
## Public integration API.  Traffic/NPC populators should consume these exact
## authored polylines instead of inventing paths or spawning in a heap.
func get_vehicle_routes() -> Dictionary:
	_build_route_cache()
	return _vehicle_routes.duplicate(true)

func get_pedestrian_routes() -> Array:
	_build_route_cache()
	var result: Array = []
	for route in _pedestrian_routes:
		result.append(route.duplicate())
	return result

func get_parking_spots() -> Array:
	return _safe_parking_spots()


func _safe_parking_spots() -> Array[Dictionary]:
	# Parking remains authored (posicao e zona sao decisao de design), mas a
	# ROTACAO nao e mais confiavel vinda do array -- ela e recalculada aqui a
	# partir da tangente real da rua mais proxima, toda vez que essa funcao
	# roda. Antes, "rotation" era um numero digitado a mao por vaga; se a
	# curva da rua/calcada perto dela mudasse depois (autores editam a rua o
	# tempo todo), a vaga ficava travada num angulo antigo e o carro nascia
	# torto, atravessado na pista (bug real reportado: taxi diagonal preso
	# empurrando pedestre). Mesmo principio ja aplicado em _road_point_at()
	# para as faixas de pedestre e nas cancelas do cruzamento ferroviario:
	# fonte unica de verdade em vez de coordenada authored duplicada.
	#
	# A canonical railway continua com autoridade final sobre o corredor de
	# seguranca. Se qualquer um dos dois for editado depois, uma vaga que
	# chegar no lastro e removida automaticamente do desenho e do spawn, em
	# vez de deixar um carro estacionado sobre o trilho.
	_build_route_cache()
	var result: Array[Dictionary] = []
	var rail_corridor := _rail_corridor_points()
	for source in parking_spots:
		var spot := source as Dictionary
		var position_value: Vector2 = spot.get("position", Vector2.ZERO)
		if not rail_corridor.is_empty() and _point_hits_polyline(position_value, rail_corridor, RAIL_CLEARANCE):
			continue
		var fixed_spot := spot.duplicate(true)
		var tangent := _nearest_road_tangent_angle(position_value, main_road_width * 0.5 + 90.0)
		if tangent.found:
			fixed_spot["rotation"] = tangent.angle
		result.append(fixed_spot)
	return result

## Varre todas as ruas conhecidas (_roads, ja amostradas em curva real via
## _catmull_rom) e devolve o angulo tangente do ponto mais proximo de
## "position", desde que esteja a "max_distance" px ou menos. Isso garante
## que qualquer coisa authorada perto de uma rua (vaga de estacionamento,
## e no futuro outros props de calcada) sempre acompanha a curva de verdade,
## em vez de um angulo fixo que pode ficar desatualizado.
func _nearest_road_tangent_angle(position_value: Vector2, max_distance: float) -> Dictionary:
	var best_distance := max_distance
	var best_angle := 0.0
	var found := false
	for road_id in _roads:
		var road: Dictionary = _roads[road_id]
		var points: PackedVector2Array = road.get("points", PackedVector2Array())
		for index in range(points.size() - 1):
			var a := points[index]
			var b := points[index + 1]
			var closest := Geometry2D.get_closest_point_to_segment(position_value, a, b)
			var distance := position_value.distance_to(closest)
			if distance <= best_distance:
				best_distance = distance
				var tangent := a.direction_to(b)
				if not tangent.is_zero_approx():
					best_angle = tangent.angle()
					found = true
	return {"found": found, "angle": best_angle}

func get_next_district_connection() -> Dictionary:
	return {
		"position": Vector2(1480, EXPANSION_BOUNDS.end.y),
		"forward": Vector2(0.16, 0.99).normalized(),
		"road_width": ROAD_WIDTH,
		"label": "BAIRRO_2_SUL",
	}

func _build_connected_vehicle_routes() -> void:
	# A PathFollow vehicle must be given a closed, authored circuit.  The old
	# implementation closed each individual road by doubling back at its end,
	# which caused the conspicuous turns reported in the playtest.  These circuits
	# use actual junctions and the three new connecting streets instead.
	# A single closed boulevard loop keeps every moving vehicle on one of two
	# offset lanes.  There are no crossing routes or hidden U-turns, so cars do
	# not compete for the same centre point at a junction.
	var boulevard_loop := _catmull_rom(PackedVector2Array([
		Vector2(870, 1740), Vector2(1280, 1740), Vector2(1750, 1900), Vector2(2100, 2080), Vector2(2450, 2140),
		Vector2(2450, 2400), Vector2(2460, 2700), Vector2(2450, 3040), Vector2(2150, 3000), Vector2(1800, 2900),
		Vector2(1400, 2800), Vector2(1340, 2500), Vector2(1280, 2200), Vector2(1050, 1980), Vector2(870, 1740),
	]), 5)
	_vehicle_routes.clear()
	_add_circuit_pair("boulevard_loop", boulevard_loop)

func _add_circuit_pair(route_id: String, centerline: PackedVector2Array) -> void:
	# Opposite traffic is offset to the other side of its carriageway.  This is
	# not a turnaround: both directions keep circulating through the same real
	# junction graph.
	_vehicle_routes[route_id + "_cw"] = _offset_polyline(centerline, 28.0)
	var reverse := centerline.duplicate()
	reverse.reverse()
	_vehicle_routes[route_id + "_ccw"] = _offset_polyline(reverse, 28.0)

func _create_authored_intersections() -> void:
	var controls := Node2D.new()
	controls.name = "AuthoredRoadIntersections"
	controls.z_index = 12
	add_child(controls)
	# One CityIntersection means four visible signal posts plus zebra/stop-line
	# geometry.  They register with the shared TrafficLightManager automatically.
	var intersections := [
		{"id": "GatewayMidtown", "at": Vector2(870, 1740), "width": ROAD_WIDTH},
		{"id": "GatewaySouth", "at": Vector2(1400, 2800), "width": ROAD_WIDTH},
		{"id": "EastMidtown", "at": Vector2(2450, 2140), "width": ROAD_WIDTH},
		{"id": "EastSouth", "at": Vector2(2450, 3040), "width": ROAD_WIDTH},
		{"id": "WestMidtown", "at": Vector2(-30, 1740), "width": LOCAL_ROAD_WIDTH},
		{"id": "WestSouth", "at": Vector2(-30, 2360), "width": LOCAL_ROAD_WIDTH},
		{"id": "NorthGateway", "at": Vector2(870, 1260), "width": ROAD_WIDTH},
		{"id": "NorthEast", "at": Vector2(1780, 1260), "width": ROAD_WIDTH},
	]
	for data in intersections:
		var intersection := INTERSECTION_SCRIPT.new() as CityIntersection
		intersection.name = "Intersection_%s" % String(data.id)
		intersection.position = data.at
		intersection.road_width = float(data.width)
		intersection.sidewalk_width = SIDEWALK_MARGIN
		intersection.has_yellow_box = float(data.width) >= ROAD_WIDTH
		intersection.has_traffic_lights = true
		controls.add_child(intersection)

func validate_layout() -> void:
	assert(lots.size() == 35, "Bairro 1 expansion must keep its 35 authored lots")
	var rail_corridor := _rail_corridor_points()
	var railway_conflicts: Array[int] = []
	var road_conflicts: Array[String] = []
	var lot_conflicts: Array[String] = []
	for lot_index in lots.size():
		var lot: Dictionary = lots[lot_index]
		var rect: Rect2 = lot.rect
		assert(EXPANSION_BOUNDS.encloses(rect), "%s lot lies outside Bairro 1" % lot.zone)
		assert(rect.position.y >= 1280.0, "%s overlaps CentralDistrict" % lot.zone)
		for road_name in _roads:
			var road: Dictionary = _roads[road_name]
			if _rect_hits_road(rect, road.points, float(road.width) * 0.5 + 5.0):
				road_conflicts.append("%d:%s" % [lot_index, road_name])
		if _rect_hits_road(rect, rail_corridor, RAIL_CLEARANCE):
			railway_conflicts.append(lot_index)
	for i in lots.size():
		for j in range(i + 1, lots.size()):
			if (lots[i].rect as Rect2).intersects(lots[j].rect as Rect2):
				lot_conflicts.append("%d:%d" % [i, j])
	assert(
		road_conflicts.is_empty() and lot_conflicts.is_empty() and railway_conflicts.is_empty(),
		"Layout conflicts -- roads=%s lots=%s railway=%s" % [road_conflicts, lot_conflicts, railway_conflicts]
	)
	_validate_road_network()
	for lamp_index in lamp_positions.size():
		var safe_lamp := _resolve_lamp_position(lamp_positions[lamp_index], lamp_index)
		if safe_lamp != INVALID_DECOR_POSITION:
			assert(_lamp_position_is_clear(safe_lamp), "Lamp %d would obstruct a road or railway" % lamp_index)

func _create_buildings_and_collisions() -> void:
	var visual_root := Node2D.new()
	visual_root.name = "AuthoredBuildings"
	visual_root.y_sort_enabled = true
	visual_root.z_index = 20
	add_child(visual_root)
	for index in lots.size():
		var lot: Dictionary = lots[index]
		var rect: Rect2 = lot.rect
		var building_rect := rect.grow(-BUILDING_SETBACK)
		var building := BUILDING_SCRIPT.new() as ProceduralBuilding
		building.name = "%s_%02d" % [lot.zone, index + 1]
		building.position = building_rect.get_center()
		building.footprint = building_rect.size
		building.building_kind = String(lot.kind)
		building.variant_seed = 100 + index
		if lot.has("arcade_depth"):
			building.arcade_depth = float(lot.arcade_depth)
		visual_root.add_child(building)

func _create_decor() -> void:
	var rail_corridor := _rail_corridor_points()
	var decor := Node2D.new()
	decor.name = "FixedStreetDecor"
	decor.z_index = 7
	add_child(decor)
	for index in tree_positions.size():
		if not _point_hits_polyline(tree_positions[index], rail_corridor, RAIL_CLEARANCE) and not _point_inside_solid_lot(tree_positions[index], 8.0):
			_add_tree(decor, tree_positions[index], 0.88 + float(index % 4) * 0.05)
	for index in additional_tree_positions.size():
		var tree_position := additional_tree_positions[index]
		if _nature_position_is_clear(tree_position, 11.0):
			_add_tree(decor, tree_position, 0.82 + float(index % 5) * 0.055)
	for index in rock_positions.size():
		var rock_position := rock_positions[index]
		if _nature_position_is_clear(rock_position, 10.0):
			_add_rock(decor, rock_position, index)
	for index in lamp_positions.size():
		var safe_position := _resolve_lamp_position(lamp_positions[index], index)
		if safe_position == INVALID_DECOR_POSITION:
			continue
		var lamp := LAMP_SCRIPT.new() as StreetLamp
		lamp.name = "StreetLamp_%02d" % (index + 1)
		lamp.position = safe_position
		lamp.set_meta("roadside_clearance_checked", true)
		lamp.is_facing_south = index % 2 == 0
		decor.add_child(lamp)

func _resolve_lamp_position(candidate: Vector2, lamp_index: int) -> Vector2:
	# Authored markers are only hints.  Snap each fixture to the nearest outer
	# kerb so an old marker can never leave a pole in a live lane or junction.
	var nearest_point := Vector2.ZERO
	var nearest_normal := Vector2.UP
	var nearest_width := 0.0
	var nearest_distance := INF
	var road_hits := 0
	for road_name in _roads:
		var road: Dictionary = _roads[road_name]
		var points: PackedVector2Array = road.points
		var half_width := float(road.width) * 0.5
		var road_distance := INF
		for segment_index in range(points.size() - 1):
			var a := points[segment_index]
			var b := points[segment_index + 1]
			var closest := Geometry2D.get_closest_point_to_segment(candidate, a, b)
			var distance := candidate.distance_to(closest)
			if distance < road_distance:
				road_distance = distance
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_point = closest
				var tangent := a.direction_to(b)
				nearest_normal = tangent.orthogonal().normalized()
				nearest_width = half_width
		if road_distance <= half_width + LAMP_INTERSECTION_CLEARANCE:
			road_hits += 1
	# At junctions the corners and sight triangles stay completely empty.
	if road_hits > 1 and nearest_distance <= nearest_width + LAMP_INTERSECTION_CLEARANCE:
		return INVALID_DECOR_POSITION
	if nearest_distance > nearest_width + SIDEWALK_MARGIN + 28.0:
		return INVALID_DECOR_POSITION
	var side := signf((candidate - nearest_point).dot(nearest_normal))
	if is_zero_approx(side):
		side = -1.0 if lamp_index % 2 == 0 else 1.0
	var target_distance := nearest_width + LAMP_ROAD_CLEARANCE
	var primary := nearest_point + nearest_normal * side * target_distance
	if _lamp_position_is_clear(primary):
		return primary
	var opposite := nearest_point - nearest_normal * side * target_distance
	if _lamp_position_is_clear(opposite):
		return opposite
	return INVALID_DECOR_POSITION

func _lamp_position_is_clear(point: Vector2) -> bool:
	if not EXPANSION_BOUNDS.grow(-8.0).has_point(point):
		return false
	if _point_hits_polyline(point, _rail_corridor_points(), RAIL_CLEARANCE + 12.0):
		return false
	if _point_inside_solid_lot(point, 10.0):
		return false
	for road_name in _roads:
		var road: Dictionary = _roads[road_name]
		if _point_hits_polyline(point, road.points, float(road.width) * 0.5 + 10.0):
			return false
	return true

func _validate_road_network() -> void:
	# Every secondary route must touch the fixed connected component.  This is a
	# geometry assertion, not a visual guess, and prevents future isolated roads.
	assert(_road_ribbons_touch("gateway_spine", "midtown_cross"), "Midtown road disconnected from gateway spine")
	assert(_road_ribbons_touch("gateway_spine", "south_cross"), "South road disconnected from gateway spine")
	assert(_road_ribbons_touch("south_cross", "west_local"), "West local road disconnected from south road")
	assert(_road_ribbons_touch("midtown_cross", "east_arc"), "East arc disconnected from midtown road")
	assert((_roads.gateway_spine.points as PackedVector2Array)[0].distance_to(Vector2(870, 1260)) < 1.0, "Gateway no longer meets Central District")

func _road_ribbons_touch(first_name: String, second_name: String) -> bool:
	var first: Dictionary = _roads[first_name]
	var second: Dictionary = _roads[second_name]
	var maximum_gap := (float(first.width) + float(second.width)) * 0.5 - 4.0
	for first_point in first.points:
		if _point_hits_polyline(first_point, second.points, maximum_gap):
			return true
	return false

func _add_tree(parent: Node2D, at: Vector2, scale_factor: float) -> void:
	var tree := PROCEDURAL_TREE.new() as ProceduralStreetTree
	tree.name = "ProceduralTree"
	tree.position = at
	tree.variant_seed = int(at.x * 5.0 + at.y * 11.0)
	tree.crown_scale = scale_factor
	if tree.variant_seed % 7 == 0:
		tree.tree_style = ProceduralStreetTree.TreeStyle.PINE
	elif tree.variant_seed % 5 == 0:
		tree.tree_style = ProceduralStreetTree.TreeStyle.BROADLEAF
	else:
		tree.tree_style = ProceduralStreetTree.TreeStyle.STREET
	tree.leaf_color = Color("#315f43") if tree.variant_seed % 2 == 0 else Color("#47744d")
	parent.add_child(tree)


func _add_rock(parent: Node2D, at: Vector2, seed: int) -> void:
	var rock := PROCEDURAL_ROCK.new() as ProceduralUrbanRock
	rock.name = "ProceduralRock_%02d" % (seed + 1)
	rock.position = at
	rock.variant_seed = 200 + seed
	rock.rock_size = Vector2(22 + seed % 4 * 4, 16 + seed % 3 * 3)
	rock.base_color = [Color("#555d5a"), Color("#64645d"), Color("#4e5859")][seed % 3]
	parent.add_child(rock)

func _add_rect_collision(rect: Rect2, node_name: String) -> void:
	var body := StaticBody2D.new()
	body.name = node_name
	body.position = rect.get_center()
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("building_blocker")
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)

func _draw() -> void:
	draw_rect(EXPANSION_BOUNDS, Color("#4b5555"))
	for subarea in subareas:
		var bounds: Rect2 = subarea.bounds
		draw_rect(bounds.grow(-10), LOT_GROUND_COLOR)
		draw_rect(bounds.grow(-10), Color("#3e4746"), false, 3.0)
	for alley in alleys:
		draw_rect(alley, ALLEY_COLOR)
		draw_line(alley.position + Vector2(3, 4), alley.end - Vector2(3, 4), Color("#2c3235"), 2.0)
	if render_legacy_roads:
		# Standalone fallback. DistrictOneComplete disables this and lets the
		# unified graph render every street in shared material passes.
		for road_name in _roads:
			var road: Dictionary = _roads[road_name]
			var points: PackedVector2Array = road.points
			var width: float = road.width
			draw_polyline(points, SIDEWALK_COLOR, width + SIDEWALK_MARGIN * 2.0, true)
			draw_polyline(points, CURB_COLOR, width + 10.0, true)
			draw_polyline(points, ROAD_EDGE_COLOR, width + 4.0, true)
			draw_polyline(points, ROAD_COLOR, width, true)
			_draw_dashed_centerline(points)
	# Crossings are drawn regardless of render_legacy_roads: they are a real
	# gameplay/visual feature (pedestrian crossings), not a fallback pavement
	# renderer, and must survive even when UnifiedRoadNetwork2D owns the asphalt.
	_draw_authored_crossings()
	_draw_parking_marks()

func _draw_dashed_centerline(points: PackedVector2Array) -> void:
	var draw_dash := true
	var carry := 0.0
	const STEP := 22.0
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var length := a.distance_to(b)
		if length < 0.1:
			continue
		var direction := a.direction_to(b)
		var walked := carry
		while walked < length:
			var finish := minf(walked + STEP, length)
			if draw_dash:
				draw_line(a + direction * walked, a + direction * finish, LANE_COLOR, 3.0, true)
			draw_dash = not draw_dash
			walked = finish
		carry = maxf(0.0, walked - length)

func get_pedestrian_crossing_definitions() -> Array[Dictionary]:
	# Stable road-relative references are the sole source for both drawing and
	# gameplay Area2D generation. No crossing owns a copied world coordinate.
	return [
		{"id": "gateway_north", "road_id": "gateway_spine", "t": 0.0},
		{"id": "gateway_midtown", "road_id": "gateway_spine", "t": 0.52},
		{"id": "gateway_south", "road_id": "gateway_spine", "t": 0.65},
		{"id": "south_cross_central", "road_id": "south_cross", "t": 0.50},
		{"id": "east_link_upper", "road_id": "east_link", "t": 0.85},
		{"id": "midtown_cross_west", "road_id": "midtown_cross", "t": 0.22},
	]

func _draw_authored_crossings() -> void:
	if _has_composed_safety_renderer():
		return
	# Crossings are anchored to a point along the REAL baked curve (road id +
	# fraction of its length), never a hardcoded world Vector2. A fixed
	# coordinate drifts off the pavement the instant that road's control
	# points are edited -- that drift is exactly what produced crosswalks
	# floating beside the road instead of on it. Sampling the live polyline
	# means a crossing is always on its road, no matter how the road moves.
	for crossing in get_pedestrian_crossing_definitions():
		var placement := _road_point_at(String(crossing.road_id), float(crossing.t))
		_draw_crosswalk(placement.position, placement.angle)

func _has_composed_safety_renderer() -> bool:
	var composition_root := get_parent()
	if composition_root == null:
		return false
	for sibling in composition_root.get_children():
		if sibling != self and (sibling.is_in_group("district_road_safety_system") or String(sibling.name).begins_with("DistrictRoadSafety")):
			return true
	return false

func _road_point_at(road_id: String, t: float) -> Dictionary:
	var road: Dictionary = _roads.get(road_id, {})
	var points: PackedVector2Array = road.get("points", PackedVector2Array())
	if points.size() < 2:
		return {"position": Vector2.ZERO, "angle": 0.0}
	var index := clampi(roundi(clampf(t, 0.0, 1.0) * float(points.size() - 1)), 0, points.size() - 1)
	var prev_index := maxi(0, index - 1)
	var next_index := mini(points.size() - 1, index + 1)
	var tangent := points[prev_index].direction_to(points[next_index])
	if tangent.is_zero_approx():
		tangent = Vector2.RIGHT
	return {"position": points[index], "angle": tangent.angle()}

func _draw_crosswalk(center: Vector2, angle: float) -> void:
	var along := Vector2.RIGHT.rotated(angle)
	var across := Vector2.DOWN.rotated(angle)
	for stripe in range(-4, 5):
		var stripe_center := center + along * float(stripe * 15)
		draw_line(stripe_center - across * 13.0, stripe_center + across * 13.0, Color("#e9e7de"), 8.0, true)

func _draw_parking_marks() -> void:
	for spot in _safe_parking_spots():
		var center: Vector2 = spot.position
		var angle: float = spot.rotation
		var forward := Vector2.RIGHT.rotated(angle)
		var side := Vector2.DOWN.rotated(angle)
		draw_line(center - forward * 25.0 - side * 13.0, center - forward * 25.0 + side * 13.0, Color("#b8b195"), 2.0)
		draw_line(center + forward * 25.0 - side * 13.0, center + forward * 25.0 + side * 13.0, Color("#b8b195"), 2.0)

func _catmull_rom(control: PackedVector2Array, subdivisions: int) -> PackedVector2Array:
	var sampled := PackedVector2Array()
	if control.size() < 2:
		return control.duplicate()
	for index in range(control.size() - 1):
		var p0 := control[maxi(0, index - 1)]
		var p1 := control[index]
		var p2 := control[index + 1]
		var p3 := control[mini(control.size() - 1, index + 2)]
		for step in subdivisions:
			var t := float(step) / float(subdivisions)
			var t2 := t * t
			var t3 := t2 * t
			var point := 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
			sampled.append(point)
	sampled.append(control[control.size() - 1])
	return sampled

func _offset_polyline(points: PackedVector2Array, amount: float) -> PackedVector2Array:
	var shifted := PackedVector2Array()
	for index in points.size():
		var before := points[maxi(0, index - 1)]
		var after := points[mini(points.size() - 1, index + 1)]
		var tangent := before.direction_to(after)
		var normal := Vector2(-tangent.y, tangent.x)
		shifted.append(points[index] + normal * amount)
	return shifted

func _build_two_way_loop(centerline: PackedVector2Array, offset: float) -> PackedVector2Array:
	var forward := _offset_polyline(centerline, offset)
	var backward := _offset_polyline(centerline, -offset)
	var loop := PackedVector2Array()
	loop.append_array(forward)
	for index in range(backward.size() - 1, -1, -1):
		loop.append(backward[index])
	if not loop.is_empty():
		loop.append(loop[0])
	return loop

func _rect_hits_road(rect: Rect2, points: PackedVector2Array, radius: float) -> bool:
	var probes := PackedVector2Array([
		rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y),
		rect.get_center(), Vector2(rect.get_center().x, rect.position.y), Vector2(rect.get_center().x, rect.end.y),
		Vector2(rect.position.x, rect.get_center().y), Vector2(rect.end.x, rect.get_center().y),
	])
	for index in range(points.size() - 1):
		var a := points[index]
		var b := points[index + 1]
		for probe in probes:
			if probe.distance_to(Geometry2D.get_closest_point_to_segment(probe, a, b)) <= radius:
				return true
	return false

func _point_hits_polyline(point: Vector2, points: PackedVector2Array, radius: float) -> bool:
	for index in range(points.size() - 1):
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point, points[index], points[index + 1])) <= radius:
			return true
	return false


func _rail_corridor_points() -> PackedVector2Array:
	var rail_line := get_node_or_null("../DistrictRailLine") as Node2D
	if rail_line == null or not rail_line.has_method("get_rail_graph_data"):
		return PackedVector2Array()
	var rail_data: Dictionary = rail_line.call("get_rail_graph_data")
	var global_points: PackedVector2Array = rail_data.get("global_points", PackedVector2Array())
	var local_points := PackedVector2Array()
	for world_point in global_points:
		local_points.append(to_local(world_point))
	return local_points

func _point_inside_solid_lot(point: Vector2, margin: float) -> bool:
	for lot in lots:
		if String(lot.kind) != "park" and (lot.rect as Rect2).grow(margin).has_point(point):
			return true
	return false


func _nature_position_is_clear(point: Vector2, radius: float) -> bool:
	if not EXPANSION_BOUNDS.grow(-8.0).has_point(point):
		return false
	if _point_hits_polyline(point, _rail_corridor_points(), RAIL_CLEARANCE + radius):
		return false
	if _point_inside_solid_lot(point, radius):
		return false
	for road_name in _roads:
		var road: Dictionary = _roads[road_name]
		if _point_hits_polyline(point, road.points, float(road.width) * 0.5 + radius + 12.0):
			return false
	return true
