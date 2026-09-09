@tool
extends Node2D
## Harbor crossing: structure only. Foundry's provider/UnifiedRoadNetwork draws
## its continuous asphalt, sidewalk and lanes across the navigable deck.

const WEST_SHORE_X := 3200.0
const EAST_SHORE_X := 4380.0
const DECK_BOUNDS := Rect2(3200.0, 298.0, 1180.0, 204.0)
const ROAD_BOUNDS := Rect2(3000.0, 340.0, 1650.0, 120.0)
const PYLON_X: Array[float] = [3500.0, 4060.0]
const RAIL_BOUNDS: Array[Rect2] = [
	Rect2(3200.0, 284.0, 1180.0, 8.0),
	Rect2(3200.0, 508.0, 1180.0, 8.0),
]

@export var is_in_mountain_pass: bool = false


func _ready() -> void:
	# Under the shared road renderer (z=2); no opaque structural shape covers asphalt.
	z_index = 1
	_build_rails()
	queue_redraw()


func _build_rails() -> void:
	if has_node("BridgeEdgeRails"):
		return
	var body := StaticBody2D.new()
	body.name = "BridgeEdgeRails"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for i in range(RAIL_BOUNDS.size()):
		var bounds := RAIL_BOUNDS[i]
		var shape := RectangleShape2D.new()
		shape.size = bounds.size
		var collision := CollisionShape2D.new()
		collision.name = "NorthRail" if i == 0 else "SouthRail"
		collision.shape = shape
		collision.position = bounds.get_center()
		body.add_child(collision)


func get_bridge_audit_data() -> Dictionary:
	var pylons: Array[Rect2] = []
	for x in PYLON_X:
		pylons.append(Rect2(x - 23.0, 220.0, 46.0, 61.0))
		pylons.append(Rect2(x - 23.0, 519.0, 46.0, 61.0))
	return {
		"deck_bounds": DECK_BOUNDS,
		"road_bounds": ROAD_BOUNDS,
		"rail_obstacles": RAIL_BOUNDS.duplicate(),
		"pylon_bounds": pylons,
		"west_approach": Vector2(3000.0, 400.0),
		"east_approach": Vector2(4650.0, 400.0),
		"water_crossing_start": Vector2(WEST_SHORE_X, 400.0),
		"water_crossing_end": Vector2(EAST_SHORE_X, 400.0),
		"collision_free_width": DECK_BOUNDS.size.y,
	}


func _draw() -> void:
	# Top-down superstructure: piers and cable fans sit outside both sidewalks.
	# The uninterrupted road remains the shared network's geometry, not a second road.
	draw_rect(Rect2(3207, 512, 1180, 28), Color(0.025, 0.10, 0.13, 0.29))
	draw_rect(Rect2(3200, 281, 1180, 238), Color("626e6e"))
	draw_rect(Rect2(3200, 290, 1180, 220), Color("a7aaa0"))
	for x in range(3220, 4380, 40):
		draw_line(Vector2(x, 283), Vector2(x, 297), Color("ced0bb"), 2.0)
		draw_line(Vector2(x, 503), Vector2(x, 517), Color("ced0bb"), 2.0)
	for rail in RAIL_BOUNDS:
		draw_rect(rail, Color("5e7479"))
		draw_line(rail.position + Vector2(0, 2), Vector2(rail.end.x, rail.position.y + 2), Color("c6d3cc"), 2.5)
	for x in PYLON_X:
		_draw_pylon_pair(x)
	# Expansion joints only in the concrete edge, not painted over road markings.
	for x in [3208.0, 3495.0, 4055.0, 4372.0]:
		for y in [292.0, 503.0]:
			draw_line(Vector2(x, y), Vector2(x, y + 5), Color("445459"), 3.0)
	# Small repeating luminaires give the span a recognizable nighttime silhouette.
	for x in range(3260, 4340, 150):
		for y in [279.0, 521.0]:
			draw_circle(Vector2(x, y), 4.0, Color("ead8a3"))
			draw_circle(Vector2(x, y), 9.0, Color(0.91, 0.78, 0.47, 0.1))


func _draw_pylon_pair(x: float) -> void:
	for north in [true, false]:
		var foot_y := 250.0 if north else 550.0
		var deck_y := 286.0 if north else 514.0
		var mast_y := 205.0 if north else 595.0
		var top := Vector2(x, mast_y)
		# Four fan stays each way; no stay spans across the traversable road.
		for offset in [-245.0, -185.0, -125.0, -65.0, 65.0, 125.0, 185.0, 245.0]:
			var anchorage := Vector2(clampf(x + offset, WEST_SHORE_X + 8.0, EAST_SHORE_X - 8.0), deck_y)
			draw_line(top + Vector2(5, 6), anchorage + Vector2(5, 6), Color(0.05, 0.14, 0.17, 0.20), 2.5, true)
			draw_line(top, anchorage, Color("b7c8c6"), 1.5, true)
		draw_rect(Rect2(x - 26, foot_y - 32, 52, 64), Color(0.035, 0.11, 0.14, 0.32))
		draw_rect(Rect2(x - 23, foot_y - 30, 46, 60), Color("d5ccb0"))
		draw_rect(Rect2(x - 15, foot_y - 25, 30, 50), Color("829391"))
		draw_line(Vector2(x, deck_y), top, Color("d7d8c1"), 11.0, true)
		draw_line(Vector2(x - 3, deck_y), top - Vector2(3, 0), Color("8da4a4"), 3.0, true)
		draw_circle(top, 5.0, Color("e7bd78"))
