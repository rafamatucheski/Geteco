class_name ProceduralUrbanRock
extends StaticBody2D

## Faceted code-native rock for plazas, railway embankments and coastline.

@export var rock_size := Vector2(30, 22)
@export var base_color := Color("#59615f")
@export var variant_seed := 0
@export var collision_enabled := true

var _points := PackedVector2Array()


func _init() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _ready() -> void:
	collision_layer = 1 if collision_enabled else 0
	collision_mask = 0
	z_index = 4
	add_to_group("procedural_rock")
	add_to_group("nature_obstacle")
	_points = _build_outline()
	if collision_enabled:
		var collision := CollisionShape2D.new()
		collision.name = "RockCollision"
		var shape := ConvexPolygonShape2D.new()
		shape.points = _points
		collision.shape = shape
		add_child(collision)
	queue_redraw()


func _draw() -> void:
	if _points.is_empty():
		_points = _build_outline()
	var shadow := PackedVector2Array()
	for point in _points:
		shadow.append(point + Vector2(7, 7))
	draw_colored_polygon(shadow, Color(0.03, 0.04, 0.05, 0.38))
	draw_colored_polygon(_points, base_color)
	var outline := _points.duplicate()
	outline.append(_points[0])
	draw_polyline(outline, base_color.darkened(0.38), 2.2, true)
	# Three asymmetric facets create volume without a raster texture.
	var top := Vector2(-rock_size.x * 0.10, -rock_size.y * 0.26)
	draw_colored_polygon(PackedVector2Array([_points[0], _points[1], _points[2], top]), base_color.lightened(0.20))
	draw_colored_polygon(PackedVector2Array([top, _points[2], _points[3], _points[4]]), base_color.darkened(0.11))
	draw_colored_polygon(PackedVector2Array([_points[5], _points[6], _points[7], top]), base_color.lightened(0.07))
	# Short cracks and a small lichen patch add readable material detail.
	draw_line(top + Vector2(-2, 1), top + Vector2(4, 5), base_color.darkened(0.45), 1.4, true)
	draw_line(top + Vector2(4, 5), top + Vector2(1, 9), base_color.darkened(0.45), 1.2, true)
	draw_circle(Vector2(rock_size.x * 0.18, -rock_size.y * 0.16), maxf(2.0, rock_size.x * 0.08), Color("#77836c"))


func _build_outline() -> PackedVector2Array:
	var result := PackedVector2Array()
	for index in 8:
		var angle := TAU * float(index) / 8.0
		var variation := 0.82 + _seed_value(index + 3) * 0.18
		result.append(Vector2(
			cos(angle) * rock_size.x * 0.5 * variation,
			sin(angle) * rock_size.y * 0.5 * variation
		))
	return result


func _seed_value(index: int) -> float:
	return fposmod(sin(float(variant_seed * 71 + index * 43)) * 24634.6345, 1.0)
