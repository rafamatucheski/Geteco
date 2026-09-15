extends Node2D
## Flush grave cover: all geometry lies on the floor, with no raised obstacle.
## The ledger owns identity and occupancy; unloading this visual cannot erase it.
func _ready() -> void:
	z_index = 2
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(-14,-21,28,42),Color("554c3a"))
	draw_rect(Rect2(-12,-19,24,38),Color("807e6b"))
	draw_rect(Rect2(-10,-17,20,34),Color("6a6b5f"),false,1)
	draw_line(Vector2(0,-12),Vector2(0,0),Color("b4b09a"),2)
	draw_line(Vector2(-4,-8),Vector2(4,-8),Color("b4b09a"),2)
