extends CharacterBody3D
## Um corpo varrido de verdade: o morador nunca desliza através dos móveis nem do Dante.
var model: Node3D
var place: Node3D
var phase := 0
var elapsed := 0.0
var working := false
var tool: Node3D
var workpiece: MeshInstance3D
var work_contact: Node3D
var blocked_time := 0.0
const POINTS := [Vector3(-2.65,0,-1.1),Vector3(-1.5,0,-1.45),Vector3(-1.5,0,-2.94),Vector3(-1.5,0,-1.45)]

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
	details.box(tool,"SpannerHandle",Vector3(0,0,-.14),Vector3(.035,.035,.23),metal)
	for side in [-1,1]:
		details.box(tool,"SpannerJaw",Vector3(side*.028,0,0),Vector3(.018,.025,.07),metal)
	model.body.hand_provider = _hands

func _hands() -> Array:
	if not working or not is_instance_valid(workpiece): return [null,null]
	# Uma palma firma a peça real; a outra segura o cabo da chave.
	return [workpiece.to_global(Vector3(.12,.16,.15)),tool.to_global(Vector3(0,0,-.17))]

func _at_station(target: Vector3) -> bool:
	return Vector2(position.x-target.x,position.z-target.z).length() < .06

func _sync_tool() -> void:
	tool.visible = working
	if not working: return
	# Pivô na porca: a rotação nunca afasta a boca da chave do contato físico.
	tool.global_transform = Transform3D(Basis(Vector3.UP,PI*.5+sin(elapsed*4.5)*.32),work_contact.global_position)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(place) or not place.interior_active: return
	var target: Vector3 = POINTS[phase]
	var offset := target-position
	offset.y = 0
	var arrived := _at_station(target)
	velocity = Vector3.ZERO if arrived else offset.normalized()*.65
	velocity.y = -1
	var before := position
	move_and_slide()
	if not arrived and before.distance_to(position) < delta*.08:
		blocked_time += delta
		if blocked_time > 2.0:
			phase = (phase+1)%POINTS.size()
			blocked_time = 0.0
			elapsed = 0.0
	else: blocked_time = 0.0
	working = phase == 2 and arrived and _at_station(POINTS[2]) and is_instance_valid(workpiece) and workpiece.is_visible_in_tree() and is_instance_valid(work_contact) and global_position.distance_to(work_contact.global_position) < 1.6
	if arrived:
		elapsed += delta
		if working:
			var toward := workpiece.global_position-global_position
			model.rotation.y = lerp_angle(model.rotation.y,atan2(toward.x,toward.z),minf(delta*8,1))
		if elapsed > (7.0 if phase == 2 else .25 if phase in [1,3] else 4.0):
			phase = (phase+1)%POINTS.size()
			elapsed = 0.0
			working = false
	else:
		model.rotation.y = lerp_angle(model.rotation.y,atan2(offset.x,offset.z),minf(delta*6,1))
		elapsed = 0.0
	_sync_tool()
	place.interaction_points["mechanic"] = global_position + Vector3(0,0,.8)
