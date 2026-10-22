extends CharacterBody3D
## A real swept body: the resident never slides through furniture or Dante.
var model: Node3D
var place: Node3D
var phase := 0
var elapsed := 0.0
var working := false
var tool: Node3D
const POINTS := [Vector3(-2.65,0,-1.1),Vector3(-2.65,0,-2.65)]

func _ready() -> void:
	collision_layer = 2
	collision_mask = 3
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.7
	capsule.radius = .28
	collision.shape = capsule
	collision.position.y = .85
	add_child(collision)
	tool = Node3D.new()
	tool.name = "WorkingSpanner"
	model.add_child(tool)
	var details := preload("res://assets/maciota/WorkshopDetails.gd")
	var metal := details.material("a9b5b7",.3,.7)
	details.box(tool,"SpannerHandle",Vector3.ZERO,Vector3(.025,.025,.20),metal)
	for side in [-1,1]:
		details.box(tool,"SpannerJaw",Vector3(side*.028,0,.11),Vector3(.018,.025,.07),metal)
	model.body.hand_provider = _hands

func _hands() -> Array:
	if not working: return [null,null]
	var stroke := sin(elapsed*5.0)*.045
	return [model.to_global(Vector3(-.18,1.03,.32)),model.to_global(Vector3(.17,1.03+stroke,.40))]

func _physics_process(delta: float) -> void:
	if not is_instance_valid(place) or not place.interior_active: return
	elapsed += delta
	var target: Vector3 = POINTS[phase]
	var offset := target-position
	offset.y = 0
	working = offset.length() < .06
	velocity = Vector3.ZERO if working else offset.normalized()*.65
	velocity.y = -1
	move_and_slide()
	if not working:
		model.rotation.y = lerp_angle(model.rotation.y,atan2(offset.x,offset.z),minf(delta*6,1))
		elapsed = 0
	else:
		model.rotation.y = lerp_angle(model.rotation.y,PI,minf(delta*6,1))
		if elapsed > (7.0 if phase == 1 else 4.0):
			phase = 1-phase
			elapsed = 0
	tool.visible = working
	tool.position = Vector3(.17,1.03+sin(elapsed*5)*.045,.40)
	tool.rotation.x = sin(elapsed*5)*.2
	place.interaction_points["mechanic"] = global_position + Vector3(0,0,.8)
