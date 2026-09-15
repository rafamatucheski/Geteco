extends "res://world/mountain_pass/MountainStaticModelView.gd"

var accent := Color("65b9d1")
var ground_angle := 0.0

func _ready() -> void:
	z_as_relative = false
	z_index = 5
	build_view(preload("res://world/mountain_pass/MountainSkiGate3D.gd"), 3.7, 18.0, Vector3(0, 0.9, 0), Vector3(0, 5, 4), Vector2i(192, 192))
	# Turn the gate on the ground, keeping its posts vertical in the image.
	# Rotating the baked Sprite2D also tilted the upright posts sideways.
	var ground_scale := camera_3d.unproject_position(Vector3.BACK).distance_to(camera_3d.unproject_position(Vector3.ZERO)) / camera_3d.unproject_position(Vector3.RIGHT).distance_to(camera_3d.unproject_position(Vector3.ZERO))
	model.rotation.y = -atan2(sin(ground_angle) / ground_scale, cos(ground_angle))
	model.set_accent(accent)
	add_solid(Rect2(-1.28, -0.14, 0.24, 0.28), "LeftGatePost")
	add_solid(Rect2(1.04, -0.14, 0.24, 0.28), "RightGatePost")

func project_point(point: Vector3) -> Vector2:
	return super.project_point(model.transform * point)
