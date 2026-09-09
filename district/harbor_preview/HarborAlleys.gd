@tool
extends Node2D
## Walk-through residential passages, not streets or vehicle lane providers.
## Endpoints overlap the existing sidewalks; the elevated railway passes above.

const ALLEY_WIDTH := 28.0
# Re-routed for the Quadra 1 Westgate layout (FoundryTerraceWest/East,
# FoundryLofts, CornerDiner, Laundry, UnionWorkshop): the internal gaps
# between those buildings' street frontage are only 24px, narrower than this
# alley's own required 28px width, so a corridor threaded straight between
# them cannot avoid clipping one side or the other. Both alleys instead enter
# from an outer margin that IS wide enough — the strip beside westgate_drive
# for the west alley, the open block-corner east of FoundryLofts for the
# east alley — then jog through the clear band between the two building
# rows to descend through the one gap on the Market St side that is wide
# enough (34px between CornerDiner/Laundry, 37.5px between Laundry/
# UnionWorkshop), each centered with equal clearance on both sides.
const ALLEYS := [
	{
		# The CornerDiner/Laundry gap (726-760) would otherwise be this alley's
		# natural south descent, but a StreetLamp sits at its exact center
		# (743, 1136) — HarborDistrict._build_street_lamps() is inherited
		# unchanged by HarborEastDistrict/HarborNorthDistrict, so the same
		# hardcoded lamp_points end up planted at these small local
		# coordinates in all three district roots. Routing entirely within
		# the wide, empty margin beside westgate_drive (west of every
		# Quadra 1 building) sidesteps both the lamp and every building gap.
		"id": "foundry_court_west",
		"points": [Vector2(478, 482), Vector2(478, 700), Vector2(458, 700), Vector2(458, 1168)],
	},
	{
		"id": "foundry_court_east",
		"points": [Vector2(1230, 482), Vector2(1230, 930), Vector2(948.75, 930), Vector2(948.75, 1168)],
	},
]


func _ready() -> void:
	z_index = 1
	queue_redraw()


func get_alley_definitions() -> Array[Dictionary]:
	var definitions: Array[Dictionary] = []
	for alley in ALLEYS:
		definitions.append({
			"id": String(alley.id),
			"points": PackedVector2Array(alley.points),
			"width": ALLEY_WIDTH,
			"pedestrian_only": true,
		})
	return definitions


func _draw() -> void:
	for alley in ALLEYS:
		var points := PackedVector2Array(alley.points)
		# Flush low stone edging is decorative, never an invisible collision wall.
		draw_polyline(points, Color("#85887f"), ALLEY_WIDTH + 4.0, true)
		draw_polyline(points, Color("#b7b09d"), ALLEY_WIDTH, true)
		for index in range(1, points.size() - 1):
			draw_rect(Rect2(points[index] - Vector2.ONE * 16.0, Vector2.ONE * 32.0), Color("#85887f"))
			draw_rect(Rect2(points[index] - Vector2.ONE * 14.0, Vector2.ONE * 28.0), Color("#b7b09d"))
		for index in range(points.size() - 1):
			_draw_paving(points[index], points[index + 1])
		for index in range(1, points.size() - 1):
			_draw_drain(points[index])


func _draw_paving(start: Vector2, finish: Vector2) -> void:
	var direction := (finish - start).normalized()
	var side := direction.orthogonal()
	var length := start.distance_to(finish)
	# A slightly worn central band and stone joints stay within the reserved path.
	draw_line(start, finish, Color(0.81, 0.79, 0.70, 0.23), 9.0, true)
	for step in range(12, int(length) - 10, 21):
		var center := start + direction * step
		draw_line(center - side * 12, center + side * 12, Color("#969a8e"), 1.0, true)
		var joint_side := 5.0 if step % 2 == 0 else -5.0
		draw_line(center + side * joint_side, center + direction * 12 + side * joint_side, Color("#a0a292"), 1.0, true)
	# Thin open drainage seam; no transverse curb or bollard at either entrance.
	draw_line(start + side * 11.0, finish + side * 11.0, Color("#7c857c"), 1.0, true)


func _draw_drain(center: Vector2) -> void:
	var bounds := Rect2(center - Vector2(5, 5), Vector2(10, 10))
	draw_rect(bounds, Color("#626e6c"))
	for offset in [-3.0, 0.0, 3.0]:
		draw_line(center + Vector2(offset, -4), center + Vector2(offset, 4), Color("#a7ab99"), 1.0)
