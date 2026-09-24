extends CharacterBody3D
## Maciota deliberately has no health, receive_damage or death entrypoint.
var visual: Node3D
var gait := 0.0
func _ready() -> void:
	collision_layer = 2
	collision_mask = 7
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .32
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = .85
	add_child(shape)
	visual = preload("res://assets/maciota/MaciotaModel.gd").new()
	add_child(visual)

func walk_step(destination: Vector3, delta: float) -> float:
	var offset := destination - global_position
	offset.y = 0
	velocity = offset.normalized() * minf(3.625, offset.length() / maxf(delta, .001))
	velocity.y = -1 if is_on_floor() else -8
	var before := global_position
	move_and_slide()
	var moved := before.distance_to(global_position)
	gait += moved * 6
	visual.rotation.y = atan2(-offset.x, -offset.z)
	visual.left_upper_leg.rotation.x = sin(gait) * .25
	visual.right_upper_leg.rotation.x = -sin(gait) * .25
	return moved
