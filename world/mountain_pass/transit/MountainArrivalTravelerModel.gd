extends "res://world/mountain_pass/WinterResidentModel.gd"

var winter_outfit := true

func _ready() -> void:
	preload("res://characters/pedestrians/WinterWardrobe.gd").build(self, winter_outfit)
	prepare_seated_rig()

func put_on_winter_clothes() -> void:
	if winter_outfit: return
	winter_outfit = true
	limbs.clear()
	breath = null
	for child in get_children():
		remove_child(child)
		child.queue_free()
	preload("res://characters/pedestrians/WinterWardrobe.gd").build(self, true)
	prepare_seated_rig()
