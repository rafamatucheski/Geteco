extends StaticBody3D
## Instructor remains at the paddock and streams out with the course.
## Supplied Meshy appearance; gameplay identity and collision stay on this actor.
const HOME := Vector3(-226.7, .13, -39)
var model: Node3D

func _ready() -> void:
	name = "Digo"
	add_to_group("digo_instructor")
	add_to_group("digo_character")
	set_meta("gameplay_role", "digo_instructor")
	set_meta("reaction_exempt", true)
	collision_layer = 3
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .29
	capsule.height = 1.76
	shape.shape = capsule
	shape.position.y = .88
	add_child(shape)
	model = preload("res://gameplay/digo/DigoMeshyModel.gd").new()
	model.name = "DigoModel"
	add_child(model)
