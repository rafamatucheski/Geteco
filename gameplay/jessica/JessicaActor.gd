extends CharacterBody3D
## Non-combat mission contact; no damage/death routine.
var visual: Node3D

func _ready() -> void:
	name = "Jessica"
	set_meta("gameplay_role","jessica")
	set_meta("reaction_exempt",true)
	add_to_group("jessica_character")
	collision_layer = 2
	collision_mask = 7
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .28
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = .85
	add_child(shape)
	visual = preload("res://gameplay/jessica/JessicaModel.gd").new()
	add_child(visual)

func set_talking(value: bool) -> void:
	if is_instance_valid(visual): visual.set_talking(value)
