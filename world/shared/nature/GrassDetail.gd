extends Node2D
## Static ground detail: one cached CanvasItem, no blade nodes or frame updates.
var bounds := Rect2(-380, -340, 760, 680)
var dark := false
var grass_seed := 41

func _draw() -> void:
	paint(self, bounds, grass_seed, dark)

static func paint(canvas: CanvasItem, area: Rect2, seed_value: int, shaded := false) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var low := Color("263b30") if shaded else Color("425a43")
	var high := Color("526448") if shaded else Color("72845a")
	var count := int(area.get_area() / 230.0)

	var shadow_points := PackedVector2Array()
	var blade_points := PackedVector2Array()
	var blade_colors := PackedColorArray()
	var shadow_col := Color(0.04, 0.08, 0.05, 0.24)

	for i in range(count):
		var p := area.position + Vector2(rng.randf_range(9, area.size.x - 9), rng.randf_range(12, area.size.y - 5))
		var tint := low.lerp(high, rng.randf_range(0.15, 0.8))
		var height := rng.randf_range(3.0, 8.0)

		shadow_points.append(p + Vector2(-2, 1))
		shadow_points.append(p + Vector2(5, 2))

		for blade in range(3):
			var offset := float(blade - 1) * 2.2
			var tip := p + Vector2(offset * 1.7 + rng.randf_range(-1.0, 1.0), -height * rng.randf_range(0.6, 1.0))
			var b_tint := tint.lightened(float(blade) * 0.055)
			blade_points.append(p + Vector2(offset, 0))
			blade_points.append(tip)
			blade_colors.append(b_tint)

	if not shadow_points.is_empty():
		canvas.draw_multiline_colors(shadow_points, PackedColorArray([shadow_col]), 2.0)
	if not blade_points.is_empty():
		canvas.draw_multiline_colors(blade_points, blade_colors, 1.5)
