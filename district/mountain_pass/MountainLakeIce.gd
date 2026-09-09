extends Node2D
## Fractured floes with submerged edges, exposed thickness and frost veins.
var variant: int = 0

func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7823 + variant * 193
	var rim := PackedVector2Array()
	for i in range(11):
		var angle := TAU * float(i) / 11.0
		var radius := rng.randf_range(0.76, 1.12)
		rim.append(Vector2(cos(angle) * 22.0, sin(angle) * 13.0) * radius)
	var underwater := PackedVector2Array()
	var bottom := PackedVector2Array()
	for point in rim:
		underwater.append(point * 1.14 + Vector2(0, 3))
		bottom.append(point + Vector2(0, 2.5))
	draw_colored_polygon(underwater, Color(0.23, 0.57, 0.62, 0.3))
	draw_colored_polygon(bottom, Color("#54828e"))
	draw_colored_polygon(rim, Color("#a2c7ce"))
	var frost := PackedVector2Array()
	for point in rim:
		frost.append(point * rng.randf_range(0.62, 0.87) + Vector2(-1, -1))
	draw_colored_polygon(frost, Color("#d5e7e8"))
	for i in range(rim.size()):
		if i % 3 != 0:
			draw_line(rim[i], rim[(i + 1) % rim.size()], Color(0.86, 0.97, 0.98, 0.72), 0.65, true)
	var joint := Vector2(rng.randf_range(-5, 5), rng.randf_range(-3, 3))
	for i in [1, 5, 8]:
		var tip := rim[i] * 0.94
		var bend := joint.lerp(tip, 0.58) + Vector2(2, -1.5)
		draw_polyline(PackedVector2Array([joint, bend, tip]), Color(0.3, 0.56, 0.62, 0.65), 0.6, true)
		draw_line(bend, bend + Vector2(-3, -3), Color(0.5, 0.7, 0.75, 0.6), 0.5, true)
