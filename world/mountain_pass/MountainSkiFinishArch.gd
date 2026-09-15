class_name MountainSkiFinishArch
extends "res://world/mountain_pass/MountainStaticModelView.gd"

func _ready() -> void:
	z_as_relative = false
	z_index = 5
	build_view(preload("res://world/mountain_pass/MountainSkiFinishArch3D.gd"), 6.2, 18.0, Vector3(0, 1.8, 0), Vector3(0, 11, 9), Vector2i(288, 256))
	add_solid(Rect2(-2.4, -0.3, 0.5, 0.6), "LeftFinishPylon")
	add_solid(Rect2(1.9, -0.3, 0.5, 0.6), "RightFinishPylon")
