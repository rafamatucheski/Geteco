extends Node3D
var variant := 0
var roof_access_point: Vector3:
	get: return Vector3(5.85,0,-2.0) if variant == 0 else Vector3.INF
var roof_access_yaw := PI*.5
var roof_access_route: Array[Vector3]:
	get: return [Vector3(3.5,0,-.1),Vector3(3.5,0,-2),Vector3(5.85,0,-2)] if variant == 0 else []
func _ready() -> void:
	if variant == 0:
		preload("res://world/places/AmmunationInteriorCraft.gd").build(self)
	else:
		preload("res://assets/regions/source/guns/ammunation/AmmunationArt.gd").room(self,true)
