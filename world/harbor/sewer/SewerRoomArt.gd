extends Node2D

## Compact maintenance gallery: raised brick courses, wet stone, utility
## equipment and a hidden storage bay. Static architecture costs no idle loop.
const BOUNDS := Rect2(-130, -118, 460, 270)
const CHANNEL := Rect2(112, -100, 54, 234)

func _unhandled_input(event: InputEvent) -> void:
	var controller: Variant = get_meta("sewer_controller", null)
	if is_instance_valid(controller) and event.is_action_pressed("interact"):
		controller._unhandled_input(event)
		get_viewport().set_input_as_handled()

func _ready() -> void:
	add_child(preload("res://world/harbor/sewer/SewerRoomModel.gd").new())

func _draw() -> void:
	draw_rect(Rect2(-2200, -1500, 4400, 3000), Color("#090f12"))
