extends Node3D
var variant := 0
func _ready() -> void:
	preload("res://assets/regions/source/guns/ammunation/AmmunationArt.gd").room(self,variant == 1)
