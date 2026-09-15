extends "res://ResponderNavigation.gd"
## Time-sliced full-team clearance used before choosing a parking pose.
## The probe never renders or collides; the future ambulance is an analytic
## solid in every swept edge, while all other solids come from live physics.
var probe: CharacterBody2D
var inverse := Transform2D.IDENTITY
var occupied := Rect2()
var key := ""

func configure(unit: CharacterBody2D, patient: Node2D, pose: Transform2D, start: Vector2, radius: float, half: Vector2) -> void:
	key = "%s:%s:%s"%[pose,patient.get_instance_id(),patient.global_position]
	inverse = pose.affine_inverse()
	occupied = Rect2(-half-Vector2.ONE*radius,(half+Vector2.ONE*radius)*2)
	probe = CharacterBody2D.new()
	probe.name = "MedicalRouteProbe"
	probe.top_level = true
	probe.collision_layer = 0
	probe.collision_mask = 3
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	shape.shape.radius = radius
	probe.add_child(shape)
	unit.add_child(probe)
	probe.global_position = start
	probe.add_collision_exception_with(unit)
	if patient is PhysicsBody2D: probe.add_collision_exception_with(patient)

func route(goal: Vector2) -> Array[Vector2]:
	return _plan(probe,goal)

func _clear_segment(body: CharacterBody2D, start: Vector2, end: Vector2, queries: Array[PhysicsShapeQueryParameters2D]) -> bool:
	var a := inverse*start
	var b := inverse*end
	var near := 0.0
	var far := 1.0
	var direction := b-a
	var crosses := true
	for axis in 2:
		if absf(direction[axis]) < .00001:
			if a[axis] < occupied.position[axis] or a[axis] > occupied.end[axis]: crosses = false
		else:
			var first := (occupied.position[axis]-a[axis])/direction[axis]
			var last := (occupied.end[axis]-a[axis])/direction[axis]
			near = maxf(near,minf(first,last))
			far = minf(far,maxf(first,last))
			if near > far: crosses = false
	if crosses: return false
	return super._clear_segment(body,start,end,queries)

func dispose() -> void:
	_search_pending = false
	if is_instance_valid(probe): probe.queue_free()
	probe = null
