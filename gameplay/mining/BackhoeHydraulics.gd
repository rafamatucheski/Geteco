extends Node
## Four hydraulic joints, finite angular sweeps and physical carrier colliders.
## No independent per-frame callback: MiningMachine owns input and lifecycle.
const MIN_POSE := Vector4(-1.15,-.65,-1.15,-1.0)
const MAX_POSE := Vector4(1.15,.65,.40,1.15)
const RATE := Vector4(.65,.48,.65,.85)
const SWEEP_ANGLE := .025
var vehicle: CharacterBody3D
var swing: Node3D
var boom: Node3D
var dipper: Node3D
var bucket: Node3D
var pose := Vector4.ZERO
var shapes: Array[CollisionShape3D] = []
var _links: Array[Node3D] = []
var _locals: Array[Transform3D] = []
var _accepted: Array[Transform3D] = []

func configure(car: CharacterBody3D) -> void:
	vehicle = car
	swing = car.visual.get_node("RearExcavator")
	boom = swing.get_node("Boom")
	dipper = boom.get_node("Dipper")
	bucket = dipper.get_node("DiggingBucket")
	_beam_shape(boom,Vector3.ZERO,Vector3(0,1.8,.8),.38)
	_beam_shape(dipper,Vector3.ZERO,Vector3(0,-1.8,.55),.32)
	_box_shape(bucket,Vector3(.85,.79,.81),Transform3D(Basis.IDENTITY,Vector3(0,-.275,-.155)))
	apply_pose()
	accept_motion()

func _beam_shape(link: Node3D, a: Vector3, b: Vector3, width: float) -> void:
	_box_shape(link,Vector3(width,a.distance_to(b),width),Transform3D(Basis(Quaternion(Vector3.UP,(b-a).normalized())),(a+b)*.5))

func _box_shape(link: Node3D, size: Vector3, local: Transform3D) -> void:
	var shape := CollisionShape3D.new()
	shape.name = "RearHydraulicCollider%d" % shapes.size()
	var box := BoxShape3D.new(); box.size = size
	shape.shape = box
	vehicle.add_child(shape)
	shapes.append(shape); _links.append(link); _locals.append(local)

func apply_pose() -> void:
	swing.rotation.y = pose.x
	boom.rotation.x = pose.y
	dipper.rotation.x = pose.z
	bucket.rotation.x = pose.w
	var inverse := vehicle.global_transform.affine_inverse()
	for index in shapes.size():
		shapes[index].transform = inverse*_links[index].global_transform*_locals[index]

func operate(direction: Vector4, delta: float, excluded: Array[RID]) -> bool:
	if not is_finite(delta) or delta <= 0 or not direction.is_finite(): return false
	var target := pose
	for index in 4: target[index] = clampf(pose[index]+clampf(direction[index],-1,1)*minf(delta,10.0)*RATE[index],MIN_POSE[index],MAX_POSE[index])
	var distance := 0.0
	for index in 4: distance = maxf(distance,absf(target[index]-pose[index]))
	if distance < .00001: return false
	var start := pose
	var steps := ceili(distance/SWEEP_ANGLE)
	for step in steps:
		var safe := pose
		var before := transforms()
		pose = start.lerp(target,float(step+1)/steps)
		apply_pose()
		if not _self_clear() or not motion_clear(before,excluded):
			pose = safe; apply_pose(); break
	accept_motion()
	return not pose.is_equal_approx(start)

func _self_clear() -> bool:
	# The carrier RID is excluded from world sweeps because the boom's mounting
	# pivot intentionally meets it. Protect the cab/chassis separately so the
	# digging end cannot fold through the operator or engine.
	var solids := [AABB(Vector3(-1.0,.95,-.82),Vector3(2.0,2.05,1.84)), AABB(Vector3(-1.25,.30,-2.15),Vector3(2.5,.65,4.05))]
	for index in [1,2]:
		var shape := shapes[index]
		var half: Vector3 = shape.shape.size*.5
		var bounds := AABB(shape.transform* -half,Vector3.ZERO)
		for corner in 8:
			var point := Vector3(half.x if corner&1 else -half.x,half.y if corner&2 else -half.y,half.z if corner&4 else -half.z)
			bounds = bounds.expand(shape.transform*point)
		for solid in solids:
			if bounds.intersects(solid): return false
	return true

func transforms() -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for shape in shapes: result.append(shape.global_transform)
	return result

func accept_motion() -> void:
	_accepted = transforms()

func carrier_motion_clear(excluded: Array[RID]) -> bool:
	return motion_clear(_accepted,excluded)

func motion_clear(before: Array[Transform3D], excluded: Array[RID]) -> bool:
	var space := vehicle.get_world_3d().direct_space_state
	for index in shapes.size():
		var shape := shapes[index]
		var after := shape.global_transform
		if before[index].is_equal_approx(after): continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape.shape
		query.collision_mask = 7
		query.exclude = excluded
		query.margin = .015
		# Translation is swept. Rotation is sampled in <=.025 rad increments;
		# an added margin covers the maximum corner arc between samples.
		var angle := before[index].basis.get_rotation_quaternion().angle_to(after.basis.get_rotation_quaternion())
		var steps := maxi(1,ceili(angle/SWEEP_ANGLE))
		for step in steps:
			var a := before[index].interpolate_with(after,float(step)/steps)
			var b := before[index].interpolate_with(after,float(step+1)/steps)
			query.transform = a
			query.motion = b.origin-a.origin
			var sweep := space.cast_motion(query)
			if not sweep.is_empty() and sweep[0] < .995: return false
			query.transform = b; query.motion = Vector3.ZERO
			if not space.intersect_shape(query,1).is_empty(): return false
	return true

func _exit_tree() -> void:
	for shape in shapes:
		if is_instance_valid(shape) and is_instance_valid(vehicle) and not vehicle.is_queued_for_deletion(): shape.queue_free()
