@tool
extends Node2D
## Harbor crossing: structure only. Foundry's provider/UnifiedRoadNetwork draws
## its continuous asphalt, sidewalk and lanes across the navigable deck.

const WEST_SHORE_X := 3200.0
const EAST_SHORE_X := 4380.0
const MOUNTAIN_EAST_SHORE_X := 4650.0
const DECK_BOUNDS := Rect2(3200.0, 298.0, 1180.0, 204.0)
const ROAD_BOUNDS := Rect2(3000.0, 340.0, 1650.0, 120.0)
const PYLON_X: Array[float] = [3500.0, 4060.0]
const RAIL_BOUNDS: Array[Rect2] = [
	Rect2(3200.0, 284.0, 1180.0, 8.0),
	Rect2(3200.0, 508.0, 1180.0, 8.0),
]

@export var is_in_mountain_pass: bool = false


func get_east_shore_x() -> float:
	return MOUNTAIN_EAST_SHORE_X if is_in_mountain_pass else EAST_SHORE_X


func get_rail_bounds() -> Array[Rect2]:
	var east := get_east_shore_x()
	var length := east - WEST_SHORE_X
	return [
		Rect2(WEST_SHORE_X, 284.0, length, 8.0),
		Rect2(WEST_SHORE_X, 508.0, length, 8.0),
	]


func _ready() -> void:
	# Under the shared road renderer (z=2); no opaque structural shape covers asphalt.
	z_index = 1
	_build_rails()
	_build_lighting()
	queue_redraw()

func _build_lighting() -> void:
	if Engine.is_editor_hint() or has_node("BridgeLighting"): return
	var lighting := Node2D.new()
	lighting.name = "BridgeLighting"
	add_child(lighting)
	const FIXTURE = preload("res://geodata/roads/RoadLuminaire3D.gd")
	var east := int(get_east_shore_x())
	var rails := get_rail_bounds()
	for x in range(3280, east, 210):
		for north in [true, false]:
			var strip := FIXTURE.new()
			strip.fixture_kind = "strip"
			strip.position = Vector2(x, rails[0 if north else 1].get_center().y)
			strip.target_offset = Vector2(x, 400) - strip.position
			strip.emits_ground_light = north
			lighting.add_child(strip)
			# Paired rail housings share a broad wash, keeping each road sector
			# below the engine's per-CanvasItem light limit.
			strip.pool.scale = Vector2(2.1, 1.5)
	for x in range(3320, east, 340):
		# South rail flood poles projected upward into the driving lane. The
		# north fixtures provide the wash; low strips remain on both rails.
		var flood := FIXTURE.new()
		flood.position = Vector2(x, rails[0].get_center().y)
		flood.target_offset = Vector2(x, 400) - flood.position
		lighting.add_child(flood)


func _build_rails() -> void:
	if has_node("BridgeEdgeRails"):
		return
	var body := StaticBody2D.new()
	body.name = "BridgeEdgeRails"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var rails := get_rail_bounds()
	for i in range(rails.size()):
		var bounds := rails[i]
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
	var east := get_east_shore_x()
	var deck := Rect2(WEST_SHORE_X, 298.0, east - WEST_SHORE_X, 204.0)
	return {
		"deck_bounds": deck,
		"road_bounds": ROAD_BOUNDS,
		"rail_obstacles": get_rail_bounds(),
		"pylon_bounds": pylons,
		"west_approach": Vector2(3000.0, 400.0),
		"east_approach": Vector2(4650.0, 400.0),
		"water_crossing_start": Vector2(WEST_SHORE_X, 400.0),
		"water_crossing_end": Vector2(east, 400.0),
		"collision_free_width": deck.size.y,
	}


func _draw() -> void:
	var east := get_east_shore_x()
	var length := east - WEST_SHORE_X
	var rails := get_rail_bounds()

	# Top-down superstructure: piers and cable fans sit outside both sidewalks.
	# The uninterrupted road remains the shared network's geometry, not a second road.
	draw_rect(Rect2(3207, 512, length, 28), Color(0.025, 0.10, 0.13, 0.29))
	draw_rect(Rect2(3200, 281, length, 238), Color("626e6e"))
	draw_rect(Rect2(3200, 290, length, 220), Color("858e89"))
	for x in range(3220, int(east), 40):
		draw_line(Vector2(x, 283), Vector2(x, 297), Color("ced0bb"), 2.0)
		draw_line(Vector2(x, 503), Vector2(x, 517), Color("ced0bb"), 2.0)
	for rail in rails:
		draw_rect(rail, Color("5e7479"))
		draw_line(rail.position + Vector2(0, 2), Vector2(rail.end.x, rail.position.y + 2), Color("c6d3cc"), 2.5)
		# Postes verticais da mureta metalica
		for px in range(int(rail.position.x), int(rail.end.x) + 1, 40):
			draw_line(Vector2(px, rail.position.y), Vector2(px, rail.position.y + rail.size.y), Color("3d4b4f"), 2.0)
	for x in PYLON_X:
		_draw_pylon_pair(x, east)
	# Expansion joints only in the concrete edge, not painted over road markings.
	var joints: Array[float] = [3208.0, 3495.0, 4055.0, east - 8.0]
	for x in joints:
		for y in [292.0, 503.0]:
			draw_line(Vector2(x, y), Vector2(x, y + 5), Color("445459"), 3.0)

	# Cabeceira / Encontro da ponte no término da travessia aquática
	_draw_abutment(east)


func _draw_abutment(x: float) -> void:
	# Cabeceira de concreto armado ancorando a ponte na margem:
	# Sombra de profundidade na agua/costa
	draw_rect(Rect2(x - 6, 274, 48, 254), Color(0.03, 0.08, 0.10, 0.38))
	# Bloco estrutural de concreto da cabeceira (abutment cap)
	draw_rect(Rect2(x - 4, 276, 42, 250), Color("4d5a5e"))
	draw_rect(Rect2(x - 2, 278, 36, 246), Color("879496"))
	draw_rect(Rect2(x, 280, 30, 242), Color("929e99"))

	# Muros de ala / guarda-rodas (parapets) onde a mureta metalica engasta:
	# Parapet Norte
	draw_rect(Rect2(x - 6, 276, 46, 20), Color("3a4548"))
	draw_rect(Rect2(x - 4, 278, 42, 16), Color("939e9e"))
	draw_rect(Rect2(x - 2, 280, 38, 12), Color("c5cdbe"))
	draw_line(Vector2(x - 6, 288), Vector2(x + 38, 288), Color("e0e6db"), 2.0)

	# Parapet Sul
	draw_rect(Rect2(x - 6, 506, 46, 20), Color("3a4548"))
	draw_rect(Rect2(x - 4, 508, 42, 16), Color("939e9e"))
	draw_rect(Rect2(x - 2, 510, 38, 12), Color("c5cdbe"))
	draw_line(Vector2(x - 6, 516), Vector2(x + 38, 516), Color("e0e6db"), 2.0)

	# Junta de dilatacao da transicao tabuleiro -> cabeceira
	draw_line(Vector2(x, 280), Vector2(x, 522), Color("242d30"), 3.0)
	draw_line(Vector2(x + 2, 280), Vector2(x + 2, 522), Color("3d4b4e"), 1.5)


func _draw_pylon_pair(x: float, max_east: float = EAST_SHORE_X) -> void:
	for north in [true, false]:
		var foot_y := 250.0 if north else 550.0
		var deck_y := 286.0 if north else 514.0
		var mast_y := 205.0 if north else 595.0
		var top := Vector2(x, mast_y)
		# Four fan stays each way; no stay spans across the traversable road.
		for offset in [-245.0, -185.0, -125.0, -65.0, 65.0, 125.0, 185.0, 245.0]:
			var anchorage := Vector2(clampf(x + offset, WEST_SHORE_X + 8.0, max_east - 8.0), deck_y)
			draw_line(top + Vector2(5, 6), anchorage + Vector2(5, 6), Color(0.05, 0.14, 0.17, 0.20), 2.5, true)
			draw_line(top, anchorage, Color("b7c8c6"), 1.5, true)
		draw_rect(Rect2(x - 26, foot_y - 32, 52, 64), Color(0.035, 0.11, 0.14, 0.32))
		draw_rect(Rect2(x - 23, foot_y - 30, 46, 60), Color("d5ccb0"))
		draw_rect(Rect2(x - 15, foot_y - 25, 30, 50), Color("829391"))
		draw_line(Vector2(x, deck_y), top, Color("d7d8c1"), 11.0, true)
		draw_line(Vector2(x - 3, deck_y), top - Vector2(3, 0), Color("8da4a4"), 3.0, true)
		draw_circle(top, 5.0, Color("e7bd78"))
