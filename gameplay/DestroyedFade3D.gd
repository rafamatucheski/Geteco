extends RefCounted
## One-shot cleanup, owned by the destroyed node and paused with gameplay.
const DELAY := 10.0
const DURATION := 2.0

static func schedule(body: Node3D, delay := DELAY) -> void:
	if not is_instance_valid(body) or body.has_meta("destroyed_cleanup"): return
	body.set_meta("destroyed_cleanup", true)
	var timer := body.create_tween()
	timer.tween_interval(delay)
	timer.tween_callback(func(): fade(body))

static func fade(body: Node3D) -> void:
	if not is_instance_valid(body) or body.has_meta("destroyed_fading"): return
	body.set_meta("destroyed_fading", true)
	var meshes: Array[GeometryInstance3D] = []
	var initial: Array[float] = []
	var pending: Array[Node] = [body]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is GeometryInstance3D:
			meshes.append(node)
			initial.append(node.transparency)
		if node is CollisionObject3D:
			node.collision_layer = 0
			node.collision_mask = 0
		if node is RigidBody3D: node.freeze = true
		for child in node.get_children(): pending.append(child)
	var tween := body.create_tween()
	tween.tween_method(func(amount: float):
		for i in meshes.size():
			if is_instance_valid(meshes[i]): meshes[i].transparency = lerpf(initial[i], 1.0, amount)
	, 0.0, 1.0, DURATION)
	tween.tween_callback(body.queue_free)
