extends Node2D
## Exterior motor pool. The centre aisle is the real depot spawn/return route.
## Confined strictly to the precinct lot (y <= 2140), preserving dock_street lanes and sidewalk continuity.

func _ready() -> void:
	z_index = 3
	queue_redraw()

func _draw() -> void:
	# 1. Precinct lot asphalt (between building wall at y=-50 and sidewalk at y=13)
	draw_rect(Rect2(-95, -50, 190, 63), Color("#3e4548"))

	# 2. Driveway apron crossing the sidewalk zone to meet dock_street curb (stops exactly at y=55)
	draw_rect(Rect2(-36, 13, 72, 42), Color("#353a3d"))
	draw_line(Vector2(-36, 13), Vector2(36, 13), Color("#2b3033"), 1.0)

	# 3. Sidewalk continuity & curb returns on left and right of driveway
	# Left sidewalk
	draw_rect(Rect2(-95, 13, 59, 42), Color("#c0b79e"))
	draw_line(Vector2(-95, 55), Vector2(-36, 55), Color("#8a8370"), 2.0)
	draw_line(Vector2(-36, 13), Vector2(-36, 55), Color("#8a8370"), 2.0)
	draw_line(Vector2(-66, 13), Vector2(-66, 55), Color("#a9a18d"), 1.0)

	# Right sidewalk
	draw_rect(Rect2(36, 13, 59, 42), Color("#c0b79e"))
	draw_line(Vector2(36, 55), Vector2(95, 55), Color("#8a8370"), 2.0)
	draw_line(Vector2(36, 13), Vector2(36, 55), Color("#8a8370"), 2.0)
	draw_line(Vector2(66, 13), Vector2(66, 55), Color("#a9a18d"), 1.0)

	# Dropped curb transition at street apron threshold (y=55)
	draw_line(Vector2(-36, 55), Vector2(36, 55), Color("#565e61"), 1.5)

	# 4. Parking Stalls (Vagas) - inside precinct yard (y from -44 to 10), before the sidewalk
	for side in [-1.0, 1.0]:
		var left: float = -89.0 if side < 0.0 else 38.0
		var right: float = left + 51.0
		var outline := PackedVector2Array([
			Vector2(left, -44), Vector2(left, 10), Vector2(right, 10), Vector2(right, -44)
		])
		draw_polyline(outline, Color("#d6dad2"), 2.0, true)

		# Concrete wheel stops near the building wall
		draw_rect(Rect2(left + 8, -40, 35, 5), Color("#cbd5e1"))
		draw_rect(Rect2(left + 8, -40, 35, 5), Color("#475569"), false, 1.0)

		# Subtle police precinct stall identification mark
		draw_rect(Rect2(left + 18, -16, 15, 4), Color("#4ba4d8", 0.6))

	# 5. Legible Entrance & Exit (Central Driveway Aisle)
	# Center dashed divider
	for cy in [-24, -8, 8, 24, 40]:
		draw_line(Vector2(0, cy), Vector2(0, cy + 9), Color("#d8cfab"), 1.5)

	# Entry Lane (Left, heading North into precinct)
	draw_line(Vector2(-18, 30), Vector2(-18, -4), Color("#9fa995"), 2.0)
	draw_polyline(PackedVector2Array([Vector2(-23, 6), Vector2(-18, -4), Vector2(-13, 6)]), Color("#9fa995"), 2.0)

	# Exit Lane (Right, heading South out to dock_street)
	draw_line(Vector2(18, -10), Vector2(18, 24), Color("#9fa995"), 2.0)
	draw_polyline(PackedVector2Array([Vector2(13, 14), Vector2(18, 24), Vector2(23, 14)]), Color("#9fa995"), 2.0)

	# Stop line on exit lane at the street threshold
	draw_line(Vector2(2, 53), Vector2(34, 53), Color("#e4e8dc"), 3.0)
