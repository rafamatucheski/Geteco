extends Node2D
## Aparelho visível: o som da rádio tem uma origem no cenário.
var powered := true
var _clock := 0.0

func _process(delta: float) -> void:
	_clock += delta
	if _clock > 0.15:
		_clock = 0.0
		queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(-14, -7, 28, 14), Color("302e2b"))
	draw_rect(Rect2(-12, -5, 11, 10), Color("171c20"))
	for x in [-10, -7, -4]:
		draw_line(Vector2(x, -4), Vector2(x, 4), Color("6f7776"), 1)
	draw_rect(Rect2(2, -4, 10, 4), Color("71c3a3") if powered else Color("384740"))
	draw_circle(Vector2(7, 3), 2, Color("c3ad7a"))
	draw_line(Vector2(10, -7), Vector2(17, -20), Color("b9bdb5"), 1)
