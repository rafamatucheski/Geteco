class_name ProceduralStreetTree
extends StaticBody2D

## Code-native GTA-like tree.  The silhouette, facets and shadow are generated
## by Godot drawing primitives, so it stays crisp and consistent with the
## procedural buildings instead of looking like a pasted photograph.

enum TreeStyle { STREET, BROADLEAF, PINE, COASTAL }

@export var tree_style: TreeStyle = TreeStyle.STREET
@export_range(0.65, 1.45, 0.01) var crown_scale := 1.0
@export var variant_seed := 0
@export var leaf_color := Color("#38684a")
@export var trunk_color := Color("#594334")


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	z_index = 8
	add_to_group("procedural_tree")
	add_to_group("nature_obstacle")
	if not has_node("TrunkCollision"):
		var collision := CollisionShape2D.new()
		collision.name = "TrunkCollision"
		collision.position = Vector2(0, 5) * crown_scale
		var shape := CircleShape2D.new()
		shape.radius = 12.0 * crown_scale
		collision.shape = shape
		add_child(collision)
	queue_redraw()


func _draw() -> void:
	var s := crown_scale
	_draw_ellipse(Vector2(7, 10) * s, Vector2(27, 16) * s, Color(0.03, 0.05, 0.05, 0.34))
	# Stone/soil tree pit grounds the trunk on the pavement.
	draw_circle(Vector2(0, 7) * s, 10.0 * s, Color("#4b4034"))
	draw_circle(Vector2(0, 7) * s, 11.5 * s, Color("#8b8574"), false, 2.0 * s)
	match tree_style:
		TreeStyle.PINE:
			_draw_pine(s)
		TreeStyle.COASTAL:
			_draw_coastal(s)
		_:
			_draw_round_crown(s)


func _draw_round_crown(s: float) -> void:
	var crown_center := Vector2(0, -13) * s
	# Trunk and two visible branches provide depth beneath the crown.
	draw_colored_polygon(_scaled_points(PackedVector2Array([
		Vector2(-5, 9), Vector2(5, 9), Vector2(4, -15), Vector2(-3, -15)
	]), s), trunk_color)
	draw_line(Vector2(0, -6) * s, Vector2(-13, -18) * s, trunk_color.darkened(0.12), 4.0 * s, true)
	draw_line(Vector2(1, -8) * s, Vector2(14, -19) * s, trunk_color.lightened(0.08), 3.0 * s, true)
	var dark := leaf_color.darkened(0.28)
	var mid := leaf_color
	var light := leaf_color.lightened(0.18)
	for index in 9:
		var angle := TAU * float(index) / 9.0 + _seed_value(1) * 0.35
		var distance := (9.0 + _seed_value(index + 4) * 8.0) * s
		var radius := (10.0 + _seed_value(index + 13) * 5.0) * s
		var center := crown_center + Vector2(cos(angle), sin(angle)) * distance
		draw_circle(center + Vector2(2, 3) * s, radius + 1.5 * s, dark)
		draw_circle(center, radius, mid.lightened((_seed_value(index + 30) - 0.5) * 0.12))
	# Dense centre and offset highlights keep the canopy from reading as circles.
	draw_circle(crown_center, 18.0 * s, mid)
	for highlight in [Vector2(-10, -23), Vector2(4, -29), Vector2(13, -17)]:
		draw_circle(highlight * s, 5.0 * s, light)
	draw_arc(crown_center, 19.5 * s, 0.15, 2.4, 18, dark, 2.0 * s, true)


func _draw_pine(s: float) -> void:
	draw_rect(Rect2(Vector2(-4, -2) * s, Vector2(8, 16) * s), trunk_color)
	var dark := leaf_color.darkened(0.34)
	var mid := leaf_color.darkened(0.04)
	var light := leaf_color.lightened(0.17)
	for tier in 4:
		var y := float(7 - tier * 11) * s
		var half_width := float(22 - tier * 3) * s
		var height := float(27 - tier * 2) * s
		var triangle := PackedVector2Array([
			Vector2(-half_width, y), Vector2(half_width, y), Vector2(0, y - height)
		])
		draw_colored_polygon(triangle, dark if tier == 0 else mid)
		draw_line(Vector2(-half_width * 0.62, y - 4 * s), Vector2(0, y - height + 5 * s), light, 2.0 * s, true)
	draw_circle(Vector2(0, -39) * s, 3.0 * s, light)


func _draw_coastal(s: float) -> void:
	# Wind-bent trunk/crown gives the promenade a distinct silhouette.
	var bend := -1.0 if variant_seed % 2 == 0 else 1.0
	draw_line(Vector2(0, 10) * s, Vector2(7 * bend, -15) * s, trunk_color.darkened(0.16), 9.0 * s, true)
	draw_line(Vector2(-1, 8) * s, Vector2(5 * bend, -15) * s, trunk_color.lightened(0.10), 3.0 * s, true)
	var base := Vector2(12 * bend, -20) * s
	var dark := leaf_color.darkened(0.30)
	for index in 7:
		var angle := -1.6 + float(index) * 0.48
		var center := base + Vector2(cos(angle) * 17.0 * bend, sin(angle) * 13.0) * s
		var radius := (9.0 + _seed_value(index + 40) * 4.0) * s
		draw_circle(center + Vector2(3, 4) * s, radius + 1.0 * s, dark)
		draw_circle(center, radius, leaf_color.lightened(float(index % 3) * 0.05))
	draw_line(base, base + Vector2(19 * bend, -8) * s, leaf_color.lightened(0.22), 2.0 * s, true)


func _draw_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for step in 20:
		var angle := TAU * float(step) / 20.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, color)


func _seed_value(index: int) -> float:
	return fposmod(sin(float(variant_seed * 97 + index * 53)) * 43758.5453, 1.0)


func _scaled_points(points: PackedVector2Array, factor: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		result.append(point * factor)
	return result
