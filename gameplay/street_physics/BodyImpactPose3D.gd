extends RefCounted
## Articulated presentation on one swept body, with no per-limb physics solver.
var joints: Array[Dictionary] = []
var models: Array[Dictionary] = []

func capture(visual: Node3D) -> void:
	_gather(visual)

func _gather(node: Node) -> void:
	# CivilianModel also drives police/responder/worker appearances.
	if node is Node3D and "thighs" in node and "forearms" in node:
		models.append({"node":node,"processing":node.is_processing()})
		node.set_process(false)
		for side in 2:
			var sign_side := -1.0 if side == 0 else 1.0
			_add(node.thighs[side], Vector3(-.28 if side == 0 else -.12, 0, sign_side*.14))
			_add(node.shins[side], Vector3(.42 if side == 0 else .22, 0, 0))
			_add(node.feet[side], Vector3.ZERO)
			_add(node.upper_arms[side], Vector3(.12, 0, sign_side*(.52 if side == 0 else .35)))
			_add(node.forearms[side], Vector3(-.38 if side == 0 else -.62, 0, 0))
		_add(node.spine, Vector3(-.08, .05, .04))
		_add(node.head_node, Vector3(.12, -.1, 0))
		return
	for child in node.get_children(): _gather(child)

func _add(node: Node3D, rest: Vector3) -> void:
	if not is_instance_valid(node): return
	joints.append({"node":node,"initial":node.transform,"rest":rest})

func apply(age: float, grounded: bool, recovery := 0.0) -> void:
	var weight := smoothstep(0.0, .3, age) * (1.0-recovery)
	# One bounded, damped follow-through; limbs stop moving after landing.
	var lag := sin(age*10.0)*exp(-age*4.0)*.18 if not grounded else 0.0
	for i in joints.size():
		var pose: Dictionary = joints[i]
		var node: Node3D = pose.node
		if not is_instance_valid(node): continue
		var initial: Transform3D = pose.initial
		var rotation: Vector3 = pose.rest + Vector3(lag*(1.0 if i%2 == 0 else -.5),0,0)
		node.basis = initial.basis.slerp(Basis.from_euler(rotation).scaled(initial.basis.get_scale()),weight)

func restore() -> void:
	for pose in joints:
		if is_instance_valid(pose.node): pose.node.transform = pose.initial
	for saved in models:
		if not is_instance_valid(saved.node): continue
		if saved.node.has_method("teleported"): saved.node.teleported()
		saved.node.set_process(saved.processing)
