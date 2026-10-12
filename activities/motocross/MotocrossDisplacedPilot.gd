extends CharacterBody3D
## The same helmet, jersey and articulated body removed from the stolen bike.
var visual: Node3D
var direction := Vector3.ZERO
var age := 0.0
var stride := 0.0
var bike: WeakRef

func _ready() -> void:
	collision_layer = 2
	collision_mask = 7
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .3
	capsule.height = 1.72
	shape.shape = capsule
	shape.position.y = .86
	add_child(shape)

func _physics_process(delta: float) -> void:
	age += delta
	if age > 25.0: queue_free(); return
	velocity.x = direction.x * 2.8
	velocity.z = direction.z * 2.8
	velocity.y = -1.0 if is_on_floor() else velocity.y - 20.0 * delta
	move_and_slide()
	stride += Vector2(velocity.x, velocity.z).length() * delta * 3
	visual.position.y = .77
	visual.rotation = Vector3(0, atan2(-direction.x, -direction.z) - rotation.y, 0)
	var source: Node3D = bike.get_ref() if bike != null else null
	if is_instance_valid(source): visual.pose(source, 0.0, sin(stride))
