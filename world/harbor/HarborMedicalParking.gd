extends Node2D
## Side bays face Warehouse Way; pedestrian entry stays south of the clinic.
func _ready() -> void:
	z_index = 3

func _draw() -> void:
	for y in [1455.0, 1570.0]:
		draw_rect(Rect2(2040, y - 55, 105, 110), Color("454d51"))
		# Full ambulance envelope, with an open end toward the street.
		draw_polyline(PackedVector2Array([
			Vector2(2140, y - 27), Vector2(2043, y - 27),
			Vector2(2043, y + 27), Vector2(2140, y + 27)
		]), Color("e3e5d8"), 2.0)
		draw_line(Vector2(2070, y), Vector2(2130, y), Color("dfcc79"), 2.0)
		draw_polyline(PackedVector2Array([Vector2(2120, y - 7), Vector2(2130, y), Vector2(2120, y + 7)]), Color("dfcc79"), 2.0)
		draw_line(Vector2(2142, y - 27), Vector2(2142, y + 27), Color("eeeeee"), 3.0)
		draw_string(ThemeDB.fallback_font, Vector2(2045, y - 35), "EMERGENCIA" if y > 1500 else "IML", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
