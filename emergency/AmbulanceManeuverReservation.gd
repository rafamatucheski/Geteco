extends Node
## Traffic priority for a hull-checked maneuver, through the existing vehicle
## clearance API. No invisible physical walls are added for walking actors.
var active := true
var ambulance: Node2D
var allow_hospital_return := false
var _shields: Array[Dictionary] = []

func configure(unit: Node2D) -> void:
	ambulance = unit
	add_to_group("medical_rescue_work_zone")
	var size: Vector2 = unit.get_node("CollisionShape2D").shape.get_rect().size
	for i in 12:
		var shape := RectangleShape2D.new()
		shape.size = size+Vector2(20,8)
		_shields.append({"shape":shape,"disabled":true,"global_transform":Transform2D.IDENTITY})

func follow(points: PackedVector2Array, angles: PackedFloat32Array, cursor: int) -> void:
	for shield in _shields: shield.disabled = true
	var used := 0
	var previous := Vector2.INF
	for i in range(maxi(0,cursor-1),points.size()):
		if points[i].distance_to(previous) < 16: continue
		_shields[used].global_transform = Transform2D(angles[i],points[i])
		_shields[used].disabled = false
		previous = points[i]
		used += 1
		if used == _shields.size(): break

func cancel() -> void:
	active = false
	queue_free()

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(ambulance) or not ambulance.visible or ambulance.get("is_broken") == true or ambulance.get("is_acting") == true or (ambulance.get("is_returning_to_base") == true and not allow_hospital_return) or bool(ambulance.get_meta("hospital_available",false)):
		cancel()
