class_name MountainHelipad
extends "res://world/mountain_pass/MountainProjectedExterior.gd"
var platform_body: StaticBody2D

func _ready() -> void:
	z_index = 3
	build_view(preload("res://world/mountain_pass/MountainHelipad3D.gd"),10.0,18.0,Vector3(.5,.8,0),Vector3(0,13,11),Vector2i(512,448))
	depth_bounds = Rect2(-4.2,-4.2,9.4,8.4)
	install_projected_solids()
	platform_body = solid_body
