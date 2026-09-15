class_name MountainSkiStartArch
extends "res://world/mountain_pass/MountainStaticModelView.gd"

var course_color := Color("78a95c")

func setup(col: Color) -> void:
	course_color = col
	if is_instance_valid(model):
		model.set_course_color(course_color)

func _ready() -> void:
	z_as_relative = false
	z_index = 5
	build_view(preload("res://world/mountain_pass/MountainSkiStartArch3D.gd"), 5.5, 18.0, Vector3(0, 1.7, 0), Vector3(0, 10, 8), Vector2i(256, 256))
	add_solid(Rect2(-1.9, -0.25, 0.4, 0.5), "LeftPost")
	add_solid(Rect2(1.5, -0.25, 0.4, 0.5), "RightPost")
	if is_instance_valid(model):
		model.set_course_color(course_color)
