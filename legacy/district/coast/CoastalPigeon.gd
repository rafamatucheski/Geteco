class_name CoastalPigeon
extends Node2D

## Small deterministic ambient bird. It has no collision layer and never joins
## pedestrian or traffic groups, so it cannot block or attract game agents.

@export var variant_seed: int = 0
@export var roam_radius := Vector2(34.0, 18.0)

var _origin := Vector2.ZERO
var _clock := 0.0
var _heading := 1.0


func _ready() -> void:
	_origin = position
	_clock = float(variant_seed) * 0.73
	_heading = -1.0 if variant_seed % 2 else 1.0
	z_index = 8
	queue_redraw()


func _process(delta: float) -> void:
	_clock += delta
	# Slow, looping peck-and-hop motion keeps the birds alive without AI or
	# navigation dependencies. The path is fixed for every seed.
	var travel := Vector2(
		sin(_clock * 0.42 + variant_seed) * roam_radius.x,
		cos(_clock * 0.31 + variant_seed * 0.4) * roam_radius.y
	)
	position = _origin + travel
	_heading = signf(cos(_clock * 0.42 + variant_seed))
	if is_zero_approx(_heading):
		_heading = 1.0
	queue_redraw()


func _draw() -> void:
	var peck := maxf(0.0, sin(_clock * 3.4 + variant_seed))
	var hop := maxf(0.0, sin(_clock * 2.1 + variant_seed * 0.7)) * 2.0
	var wing := sin(_clock * 8.0 + variant_seed) * 2.0
	var body_at := Vector2(0.0, -5.0 - hop)

	_draw_flat_ellipse(Vector2(0.0, 1.0), Vector2(7.0, 2.5), Color(0.03, 0.05, 0.06, 0.28))
	draw_circle(body_at, 4.4, Color("#68727c"))
	draw_circle(body_at + Vector2(_heading * 3.6, -3.0 + peck * 2.6), 2.7, Color("#89939b"))
	draw_circle(body_at + Vector2(_heading * 4.6, -3.6 + peck * 2.6), 0.65, Color("#1c2226"))
	var beak := PackedVector2Array([
		body_at + Vector2(_heading * 6.0, -2.7 + peck * 2.6),
		body_at + Vector2(_heading * 8.4, -1.9 + peck * 2.6),
		body_at + Vector2(_heading * 5.7, -1.3 + peck * 2.6)
	])
	draw_colored_polygon(beak, Color("#d6a640"))
	draw_line(body_at + Vector2(-2.5, 0.5), body_at + Vector2(-6.0 * _heading, -wing), Color("#4d5963"), 2.0)
	draw_line(body_at + Vector2(2.5, 0.5), body_at + Vector2(6.0 * _heading, wing), Color("#59656f"), 2.0)
	draw_line(Vector2(-1.5, -1.0), Vector2(-1.5, 1.0), Color("#c45d4d"), 1.0)
	draw_line(Vector2(1.5, -1.0), Vector2(1.5, 1.0), Color("#c45d4d"), 1.0)


func _draw_flat_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in 16:
		var angle := TAU * float(index) / 16.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, color)
