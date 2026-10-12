extends Node2D
## Retained as a position-update hook for the HUD's directional objective arrow.
## Doorways no longer draw a ground rectangle.
var update_position: Callable
func _ready() -> void:
	process_priority = 1100 # After the camera and the rest of the HUD.
func _process(_delta: float) -> void:
	if update_position.is_valid(): update_position.call()
