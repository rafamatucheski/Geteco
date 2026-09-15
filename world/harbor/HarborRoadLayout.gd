@tool
extends Node2D

## The preview's single source of road geometry. Every end joins another road;
## Foundry Avenue crosses the water as a bridge and joins the eastern island;
## every other street terminates at another street, never a dangling gateway.
## The elevated railway has no at-grade lane connection to this road graph.
const STREET_DEFINITIONS := [
	{"id": "memorial_north", "start": Vector2(-1250, 1250), "end": Vector2(400, 1250), "width": 100.0},
	{"id": "memorial_west", "start": Vector2(-1250, 2200), "end": Vector2(-1250, 1250), "width": 100.0},
	{"id": "memorial_south", "start": Vector2(400, 2200), "end": Vector2(-1250, 2200), "width": 100.0},
	{"id": "foundry_avenue", "start": Vector2(400, 400), "end": Vector2(6450, 400), "width": 120.0},
	{"id": "market_street", "start": Vector2(400, 1250), "end": Vector2(3000, 1250), "width": 120.0},
	{"id": "dock_street", "start": Vector2(400, 2200), "end": Vector2(3000, 2200), "width": 120.0},
	{"id": "westgate_drive", "start": Vector2(400, 400), "end": Vector2(400, 2200), "width": 110.0},
	{"id": "union_avenue", "start": Vector2(1300, 400), "end": Vector2(1300, 2200), "width": 130.0},
	{"id": "warehouse_way", "start": Vector2(2200, 400), "end": Vector2(2200, 2200), "width": 110.0},
	{"id": "quay_boulevard", "start": Vector2(3000, 400), "end": Vector2(3000, 2200), "width": 120.0},
	{"id": "island_esplanade", "start": Vector2(4650, -2000), "end": Vector2(4650, 2200), "width": 120.0},
	{"id": "east_union_avenue", "start": Vector2(5550, -2000), "end": Vector2(5550, 2200), "width": 120.0},
	{"id": "eastgate_drive", "start": Vector2(6450, -2000), "end": Vector2(6450, 2200), "width": 120.0},
	{"id": "island_market_street", "start": Vector2(4650, 1250), "end": Vector2(6450, 1250), "width": 120.0},
	{"id": "island_dock_street", "start": Vector2(4650, 2200), "end": Vector2(6450, 2200), "width": 120.0},
	# Local streets divide the large Northbank blocks; both ends are real T
	# junctions, not decorative driveways or excused open ends.
	{"id": "exchange_lane", "start": Vector2(4650, 1000), "end": Vector2(5550, 1000), "width": 72.0},
	{"id": "courtyard_lane", "start": Vector2(4650, 1790), "end": Vector2(5550, 1790), "width": 72.0},
	{"id": "northbank_neighborhood_street", "start": Vector2(4650, -350), "end": Vector2(6450, -350), "width": 90.0},
	{"id": "northbank_civic_avenue", "start": Vector2(4650, -1100), "end": Vector2(6450, -1100), "width": 120.0},
	{"id": "northbank_gateway_avenue", "start": Vector2(4650, -2000), "end": Vector2(6450, -2000), "width": 120.0},
	{"id": "map2_highway_inbound", "start": Vector2(5880, -4200), "end": Vector2(5880, -2000), "width": 96.0, "one_way": true},
	{"id": "map2_highway_outbound", "start": Vector2(6120, -2000), "end": Vector2(6120, -4200), "width": 96.0, "one_way": true},
	{"id": "map2_temporary_return", "start": Vector2(6120, -4200), "end": Vector2(5880, -4200), "width": 96.0, "one_way": true},
]


func get_road_graph_definitions() -> Array[Dictionary]:
	var definitions: Array[Dictionary] = []
	for street in STREET_DEFINITIONS + preload("res://world/harbor/HarborLocalStreets.gd").ROADS:
		var definition := {
			"id": String(street.id),
			"points": PackedVector2Array([street.start, street.end]),
			"width": float(street.width),
			"open_start": false,
			"open_end": false,
		}
		if bool(street.get("one_way", false)):
			definition["lanes"] = [
				{"lane_id": "forward_01", "offset": 22.0, "direction": 1, "direction_name": "forward"},
				{"lane_id": "forward_02", "offset": -22.0, "direction": 1, "direction_name": "forward"},
			]
		if String(street.id) in ["map2_highway_inbound","map2_highway_outbound"]:
			definition["guard_rail_openings"] = [preload("res://world/harbor/HarborNorthAccess.gd").avenue_opening(String(street.id) == "map2_highway_inbound")]
		definitions.append(definition)
	# UnifiedRoadNetwork2D generates its normal forward/reverse pair of lanes.
	definitions.append_array(preload("res://world/harbor/HarborMountainConnector.gd").road_definitions())
	definitions.append_array(preload("res://world/harbor/HarborSouthPortLayout.gd").roads())
	return definitions


func get_reserved_road_rects() -> Array[Rect2]:
	# Includes the shared 42px sidewalk and an additional 24px facade/shadow
	# setback. Building footprints must not intersect any of these rectangles.
	var reserved: Array[Rect2] = []
	for street in STREET_DEFINITIONS + preload("res://world/harbor/HarborLocalStreets.gd").ROADS:
		var first: Vector2 = street.start
		var last: Vector2 = street.end
		reserved.append(Rect2(first, Vector2.ZERO).expand(last).grow(float(street.width) * 0.5 + 42.0 + 24.0))
	for definition in preload("res://world/harbor/HarborMountainConnector.gd").road_definitions():
		var points: PackedVector2Array = definition.points
		for i in range(points.size()-1):
			reserved.append(Rect2(points[i], Vector2.ZERO).expand(points[i+1]).grow(114))
	for definition in preload("res://world/harbor/HarborSouthPortLayout.gd").roads():
		var points: PackedVector2Array = definition.points
		for i in range(points.size()-1):
			reserved.append(Rect2(points[i],Vector2.ZERO).expand(points[i+1]).grow(float(definition.width)*.5+66))
	return reserved
