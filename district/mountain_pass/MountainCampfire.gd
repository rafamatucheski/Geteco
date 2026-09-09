extends Node2D
## Small procedural fire, drawn over logs inside the existing stone ring.
var elapsed := 0.0
var redraw_elapsed := 0.0

func _process(delta: float) -> void:
	elapsed += delta
	redraw_elapsed += delta
	if redraw_elapsed >= 0.05:
		redraw_elapsed = 0.0
		queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, 10.5, Color("#292624"))
	for i in range(3):
		var angle := float(i) * 1.05 + 0.2
		var end := Vector2(cos(angle), sin(angle)) * 10.0
		draw_line(-end, end, Color("#493126"), 4.0, true)
		draw_line(-end + Vector2(0, -1), end + Vector2(0, -1), Color("#805039"), 1.0, true)
	for i in range(9):
		var angle := float(i) * 2.4
		var ember := Vector2(cos(angle), sin(angle)) * (3.0 + float(i % 3) * 2.0)
		draw_circle(ember, 1.0 + 0.35 * sin(elapsed * 6.0 + i), Color("#ec6020"))
	# Smoke drifts upward and fades, separate from the bright flame tips.
	for i in range(5):
		var age := fposmod(elapsed * 0.3 + float(i) / 5.0, 1.0)
		var center := Vector2(sin(age * 5.0 + i) * 4.0 + age * 8.0, -13.0 - age * 29.0)
		draw_circle(center, 2.0 + age * 5.0, Color(0.43, 0.46, 0.47, sin(age * PI) * 0.17))
	for i in range(5):
		var x := float(i - 2) * 2.8
		var height: float = 11.0 + (2.0 - absf(float(i - 2))) * 3.0 + sin(elapsed * 8.0 + i * 2.1) * 3.0
		var sway := sin(elapsed * 5.0 + i) * 2.1
		var base := Vector2(x, 2.0)
		var flame := PackedVector2Array([
			base + Vector2(-3.8, 0), base + Vector2(-4, -height * 0.35),
			base + Vector2(-1.8 + sway, -height * 0.65),
			base + Vector2(sway, -height), base + Vector2(2.8 + sway, -height * 0.5),
			base + Vector2(3.5, -height * 0.2), base + Vector2(2.5, 1)
		])
		draw_colored_polygon(flame, Color("#ef6b16"))
		var core := PackedVector2Array([
			base + Vector2(-2, 0), base + Vector2(-1.5, -height * 0.3),
			base + Vector2(sway * 0.5, -height * 0.68),
			base + Vector2(2, -height * 0.22), base + Vector2(1.5, 0.5)
		])
		draw_colored_polygon(core, Color("#ffd267"))
	for i in range(6):
		var age := fposmod(elapsed * (0.45 + float(i % 3) * 0.1) + float(i) / 6.0, 1.0)
		var spark := Vector2(sin(age * 7.0 + i * 2.0) * (2.0 + age * 6.0), -6.0 - age * 29.0)
		draw_line(spark, spark + Vector2(0.3, 1.6), Color(1.0, 0.64, 0.18, 1.0 - age), 0.8, true)
