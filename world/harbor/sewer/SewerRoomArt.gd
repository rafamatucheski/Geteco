extends Node2D

## Compact maintenance gallery: raised brick courses, wet stone, utility
## equipment and a hidden storage bay. Static architecture costs no idle loop.
const BOUNDS := Rect2(-130, -118, 460, 270)
const CHANNEL := Rect2(112, -100, 54, 234)
var spawn_point: Marker2D

func _ready() -> void:
	var model := preload("res://world/harbor/sewer/SewerRoomModel.gd").new()
	model.name = "RoomModel"
	add_child(model)
	spawn_point = Marker2D.new()
	spawn_point.name = "SpawnPoint"
	add_child(spawn_point)

func project_floor(point: Vector2) -> Vector2:
	return get_node("RoomModel").project_floor(point)

func _draw() -> void:
	draw_rect(Rect2(-2200, -1500, 4400, 3000), Color("#090f12"))
