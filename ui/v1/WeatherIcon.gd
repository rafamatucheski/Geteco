extends Control
## Exact V1 weather glyph, fed by the V2 weather authority.

var state := "sun"
const INK := Color("d9e3e5")

func _draw() -> void:
	var center := Vector2(15, 15)
	match state:
		"sun":
			draw_arc(center, 5, 0, TAU, 24, INK, 1.5, true)
			for index in 8:
				var direction := Vector2.from_angle(index * TAU / 8.0)
				draw_line(center + direction * 8, center + direction * 11, INK, 1.5, true)
		"moon":
			var crescent := PackedVector2Array()
			for index in 25:
				crescent.append(center + Vector2.from_angle(PI * 0.5 + index * PI / 24.0) * 9)
			for index in 25:
				crescent.append(center + Vector2(4, 0) + Vector2.from_angle(-PI * 0.5 - index * PI / 24.0) * Vector2(5, 9))
			draw_colored_polygon(crescent, INK)
		"cloud", "rain", "storm":
			draw_circle(Vector2(10, 12), 5, INK)
			draw_circle(Vector2(16, 9), 6, INK)
			draw_circle(Vector2(22, 12), 4, INK)
			draw_line(Vector2(8, 16), Vector2(23, 16), INK, 2, true)
			if state == "storm":
				draw_polyline(PackedVector2Array([Vector2(18,17), Vector2(14,22), Vector2(18,22), Vector2(14,28)]), Color("e5cf8e"), 2, true)
			elif state == "rain":
				for x in [10, 16, 22]:
					draw_line(Vector2(x, 20), Vector2(x - 2, 25), Color("9dc8da"), 1.5, true)
		"snow":
			for index in 6:
				var direction := Vector2.from_angle(index * TAU / 6.0)
				draw_line(center, center + direction * 10, INK, 1.5, true)
				draw_line(center + direction * 6, center + direction * 6 + direction.rotated(2.3) * 4, INK, 1.5, true)
		"wind":
			for index in 3:
				draw_line(Vector2(5 + index * 2, 9 + index * 6), Vector2(24 - index * 2, 9 + index * 6), INK, 1.5, true)
