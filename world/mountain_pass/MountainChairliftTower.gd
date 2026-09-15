class_name MountainChairliftTower
extends "res://world/mountain_pass/MountainStaticModelView.gd"

var tower_number := 1

func _ready() -> void:
	z_as_relative = false
	z_index = 5
	build_view(preload("res://world/mountain_pass/MountainChairliftTower3D.gd"), 9.5, 18.0, Vector3(0, 4.2, 0), Vector3(0, 16, 13), Vector2i(320, 480))
	add_solid(Rect2(-0.85, -0.85, 1.7, 1.7), "TowerBase")
	if is_instance_valid(model):
		model.set_tower_number(tower_number)
	_update_lighting()

func _process(_delta: float) -> void:
	_update_lighting()

func _update_lighting() -> void:
	if not is_instance_valid(model): return
	var schedule_script := preload("res://world/mountain_pass/MountainSkiSchedule.gd")
	var night := not schedule_script.is_open(self)
	if model.is_lit != night:
		model.set_lit(night)
		if viewport_3d:
			viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
