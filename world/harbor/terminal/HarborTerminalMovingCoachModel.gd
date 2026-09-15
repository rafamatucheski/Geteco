extends "res://world/harbor/terminal/HarborCoachModel3D.gd"
## The circulating vehicle adds moving wheels and split boarding doors.
var door_leaves: Array[Node3D] = []
var rolling_wheels: Array[Node3D] = []

func _ready() -> void:
	super._ready()
	for child in get_children():
		if child is MeshInstance3D and child.mesh is CylinderMesh:
			rolling_wheels.append(child)
			child.set_meta("independent_motion",true)
	var glazing := _mat(Color("537482"), 0.22)
	for side in [-1.0, 1.0]:
		var leaf := _box(Vector3(-1.40, 1.52, DOOR_Z + side * 0.28), Vector3(0.045, 2.03, 0.53), glazing)
		door_leaves.append(leaf)
		leaf.set_meta("independent_motion",true)
	preload("res://VehicleMeshBatcher.gd").batch_model(self)

func update_motion(distance_m: float, doors: float) -> void:
	for wheel in rolling_wheels:
		wheel.rotate_object_local(Vector3.UP, distance_m / 0.58)
	for index in door_leaves.size():
		var side := -1.0 if index == 0 else 1.0
		door_leaves[index].position.z = DOOR_Z + side * (0.28 + doors * 0.48)
